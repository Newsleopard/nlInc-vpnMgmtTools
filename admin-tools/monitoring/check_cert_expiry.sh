#!/usr/bin/env bash
# ====================================================================
# VPN Server Certificate Expiry Monitor
# --------------------------------------------------------------------
# 檢查 staging / production Client VPN 的 server 憑證到期日，接近到期時
# 透過既有的 Slack webhook（存在 SSM /vpn/{env}/slack/webhook）發提醒。
#
# 設計為由 launchd 每天執行；平常靜默，只在下列情況發訊息：
#   - 任一環境查詢失敗（全部失敗）→ 每天提醒（FAILURE，監控自身失明也要叫）
#   - 任一環境 <= CRIT_DAYS         → 每天提醒（CRITICAL）
#   - 任一環境 <= WARN_DAYS         → 每週一提醒（WARNING）
#   - 有部分環境查詢失敗            → 每週一提醒（WARNING）
#   - 每月 1 號                     → 心跳訊息（證明監控仍運作）
#
# Webhook 在執行時才從 SSM 解密讀取，不寫死於檔案。
# 無任何密鑰或硬編碼基礎設施 ID，可安全進版控。
# ====================================================================

set -uo pipefail

# --- launchd 環境 PATH 很精簡，明確補上常見工具路徑 ---
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"

# --- 可調參數（可用環境變數覆寫）---
WARN_DAYS="${WARN_DAYS:-60}"
CRIT_DAYS="${CRIT_DAYS:-14}"
REGION="${AWS_REGION:-us-east-1}"
# 用哪個環境的 webhook 當通知管道（預設 staging，集中到同一個 channel）
WEBHOOK_ENV="${WEBHOOK_ENV:-staging}"
WEBHOOK_PROFILE="${WEBHOOK_PROFILE:-$WEBHOOK_ENV}"

# 要監控的環境： "環境名:AWS profile"
ENVIRONMENTS=("staging:staging" "production:production")

# --- 路徑 ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
LOG_DIR="$PROJECT_ROOT/logs"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/cert_monitor.log"

log() { echo "$(date '+%Y-%m-%d %H:%M:%S') $*" >>"$LOG_FILE"; }

# --- 純 bash JSON 字串跳脫（不依賴 python3 / jq）---
json_escape() {
    local s="$1"
    s="${s//\\/\\\\}"      # \  -> \\
    s="${s//\"/\\\"}"      # "  -> \"
    s="${s//$'\r'/}"        # 去除 CR
    s="${s//$'\n'/\\n}"     # 真正換行 -> \n
    s="${s//$'\t'/\\t}"     # tab -> \t
    printf '%s' "$s"
}

# --- 讀取某環境 server 憑證的剩餘天數，回傳 "days|enddate"，失敗回傳非 0 ---
get_days_left() {
    local env="$1" profile="$2"
    local conf="$PROJECT_ROOT/configs/$env/vpn_endpoint.conf"
    [ -f "$conf" ] || { log "[$env] 找不到 $conf"; return 1; }

    # 取 SERVER_CERT_ARN：去除行內 # 註解、引號、所有空白
    local arn
    arn=$(grep -E '^SERVER_CERT_ARN=' "$conf" | head -1 | cut -d'=' -f2- \
        | sed 's/#.*//' | tr -d '"' | tr -d "'" | tr -d '[:space:]')
    [ -n "$arn" ] || { log "[$env] vpn_endpoint.conf 無 SERVER_CERT_ARN"; return 1; }

    local notafter
    notafter=$(aws acm describe-certificate --profile "$profile" --region "$REGION" \
        --certificate-arn "$arn" --query 'Certificate.NotAfter' --output text 2>>"$LOG_FILE")
    [ -n "$notafter" ] && [ "$notafter" != "None" ] || { log "[$env] 無法取得 ACM NotAfter（profile=$profile）"; return 1; }

    # ACM CLI 回傳如 2028-09-24T18:52:45+08:00 或 ...Z；保留時區 offset 再解析
    local norm clean exp_epoch now_epoch days
    norm="${notafter/%Z/+0000}"
    # 把 offset 的冒號去掉（BSD date %z 要 +0800 而非 +08:00）
    clean=$(printf '%s' "$norm" | sed -E 's/([+-][0-9]{2}):([0-9]{2})$/\1\2/')
    exp_epoch=$(date -j -f "%Y-%m-%dT%H:%M:%S%z" "$clean" +%s 2>/dev/null)
    # fallback：若無 offset 可解析，退回前 19 字以本地時區解析
    [ -n "$exp_epoch" ] || exp_epoch=$(date -j -f "%Y-%m-%dT%H:%M:%S" "${notafter:0:19}" +%s 2>/dev/null)
    [ -n "$exp_epoch" ] || { log "[$env] 日期解析失敗: $notafter"; return 1; }

    now_epoch=$(date +%s)
    # 向負無窮取整：未過期天數正確，已過期顯示負數
    days=$(( (exp_epoch - now_epoch) / 86400 ))
    [ $(( (exp_epoch - now_epoch) % 86400 )) -lt 0 ] && days=$(( days - 1 ))
    echo "${days}|${notafter:0:19}"
}

# --- 發送 Slack（從 SSM 讀 webhook）---
send_slack() {
    local text="$1" webhook
    webhook=$(aws ssm get-parameter --profile "$WEBHOOK_PROFILE" --region "$REGION" \
        --name "/vpn/$WEBHOOK_ENV/slack/webhook" --with-decryption \
        --query 'Parameter.Value' --output text 2>>"$LOG_FILE")
    if [ -z "$webhook" ] || [ "$webhook" = "None" ]; then
        log "錯誤：無法從 SSM 讀取 webhook，訊息未送出"
        return 1
    fi
    local payload code
    payload=$(printf '{"text":"%s"}' "$(json_escape "$text")")
    code=$(curl -s -o /dev/null -w '%{http_code}' -X POST \
        -H 'Content-type: application/json' --data "$payload" "$webhook" 2>>"$LOG_FILE")
    if [ "$code" = "200" ]; then
        log "Slack 已送出 (HTTP 200)"
    else
        log "Slack 送出失敗 (HTTP $code)"
        return 1
    fi
}

# ==================== 主流程 ====================
log "===== 開始檢查 ====="

min_days=99999
total=0
fail_count=0
status_lines=""
for entry in "${ENVIRONMENTS[@]}"; do
    env="${entry%%:*}"; profile="${entry##*:}"
    total=$(( total + 1 ))
    result=$(get_days_left "$env" "$profile")
    if [ -z "$result" ]; then
        fail_count=$(( fail_count + 1 ))
        status_lines+="• ${env}: ⚠️ 查詢失敗（見 log）"$'\n'
        continue
    fi
    days="${result%%|*}"; enddate="${result##*|}"
    log "[$env] 剩餘 ${days} 天（到期 ${enddate}）"
    icon="✅"
    [ "$days" -le "$WARN_DAYS" ] && icon="🟠"
    [ "$days" -le "$CRIT_DAYS" ] && icon="🔴"
    if [ "$days" -le 0 ]; then
        status_lines+="• ${env}: 🔴 已過期 $(( -days )) 天（到期 ${enddate}）"$'\n'
    else
        status_lines+="• ${env}: ${icon} 剩 ${days} 天（到期 ${enddate}）"$'\n'
    fi
    [ "$days" -lt "$min_days" ] && min_days="$days"
done

weekday=$(date +%u)   # 1=Mon .. 7=Sun
dom=$(date +%d)       # 01..31

# --- 決定提醒等級（fail-loud：全失敗最高優先，永不靜默吞掉失敗）---
level=""
if [ "$fail_count" -ge "$total" ]; then
    level="FAILURE"                                              # 全部查詢失敗 → 每天叫
elif [ "$min_days" -le "$CRIT_DAYS" ]; then
    level="CRITICAL"                                            # 緊急 → 每天
elif [ "$min_days" -le "$WARN_DAYS" ] && [ "$weekday" = "1" ]; then
    level="WARNING"                                             # 接近到期 → 每週一
elif [ "$fail_count" -gt 0 ] && [ "$weekday" = "1" ]; then
    level="WARNING"                                             # 部分環境查詢失敗 → 每週一
elif [ "$dom" = "01" ]; then
    level="HEARTBEAT"                                           # 月初心跳
fi

# FORCE_SEND=1：測試用，無論條件是否成立都送一則心跳
if [ -z "$level" ] && [ "${FORCE_SEND:-0}" = "1" ]; then
    level="HEARTBEAT"
fi

if [ -z "$level" ]; then
    log "靜默（min_days=${min_days}，fail=${fail_count}/${total}，未達提醒條件）"
    log "===== 結束 ====="
    exit 0
fi

case "$level" in
    FAILURE)   header="🔴 *VPN 憑證監控查詢失敗*（無法確認到期狀態，請檢查 AWS 憑證/網路）" ;;
    CRITICAL)  header="🔴 *VPN Server 憑證即將到期（緊急）*" ;;
    WARNING)   header="🟠 *VPN Server 憑證到期提醒*" ;;
    HEARTBEAT) header="✅ *VPN 憑證監控月報*" ;;
esac

msg="${header}"$'\n'"${status_lines}"
if [ "$level" = "CRITICAL" ] || [ "$level" = "WARNING" ]; then
    msg+=$'\n'"續期方式：用現有 CA 重簽 → 匯入*新* ACM ARN → modify-client-vpn-endpoint（同 ARN reimport 無效）。詳見 memory: vpn-server-cert-renewal。"
fi

log "等級=${level}，發送 Slack"
send_slack "$msg"
log "===== 結束 ====="
