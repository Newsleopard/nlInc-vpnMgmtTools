#!/usr/bin/env bash
# ====================================================================
# VPN Certificate Expiry Monitor（server + client）
# --------------------------------------------------------------------
# 檢查 staging / production Client VPN 的憑證到期日，接近到期時透過既有的
# Slack webhook（存在 SSM /vpn/{env}/slack/webhook）發提醒。監控兩類憑證：
#   - server 憑證：ACM，ARN 取自 configs/{env}/vpn_endpoint.conf
#   - client 憑證：本機 certs/{env}/users/*.crt（排除 ca.crt）
#
# 為什麼 client 憑證也要監控：它過期時 AWS VPN Client 只顯示「TLS handshake
# error」，跟 server 憑證過期的畫面一模一樣，從 GUI 分不出根因。2026-06-27
# 就是這樣無預警斷線的 —— 當時本監控只看 ACM，完全沒有告警。
#
# 設計為由 launchd 每天執行；平常靜默，只在下列情況發訊息：
#   - 所有 server 查詢都失敗        → 每天提醒（FAILURE，監控自身失明也要叫）
#   - 任一憑證 <= CRIT_DAYS         → 每天提醒（CRITICAL）
#   - 任一憑證 <= WARN_DAYS         → 每週一提醒（WARNING）
#   - 有部分查詢失敗                → 每週一提醒（WARNING）
#   - 每月 1 號                     → 心跳訊息（證明監控仍運作）
#
# 已過期的 client 憑證會持續觸發 CRITICAL，直到它被續期或（人員已離職時）
# 從 certs/{env}/users/ 移除 —— 這是刻意的，過期憑證留在那裡本身就是問題。
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
# SKIP_CLIENT_CERTS=1 可關閉 client 憑證檢查（例如手上沒有 certs/ 的機器）
SKIP_CLIENT_CERTS="${SKIP_CLIENT_CERTS:-0}"

# 要監控的環境： "環境名:AWS profile"（假設本機 AWS profile 名與環境名相同）
# 可用環境變數 VPN_CERT_ENVS 覆寫（空白分隔），例：VPN_CERT_ENVS="staging:staging"
# 只裝單一 profile 的機器可藉此避免每週一收到另一環境的「查詢失敗」噪音。
if [ -n "${VPN_CERT_ENVS:-}" ]; then
    # shellcheck disable=SC2206
    ENVIRONMENTS=($VPN_CERT_ENVS)
else
    ENVIRONMENTS=("staging:staging" "production:production")
fi

# --- 路徑 ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
LOG_DIR="$PROJECT_ROOT/logs"
# 建不出 log 目錄就必須大聲死掉：沒有 set -e，log() 會安靜地什麼都不寫，
# 腳本照樣 exit 0 —— 那正是這支監控壞掉一個多月沒人發現的形狀。
# 78 = EX_CONFIG，是 launchd 唯一會記下來的訊號。
mkdir -p "$LOG_DIR" || { echo "無法建立 log 目錄：$LOG_DIR" >&2; exit 78; }
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
    # ${} 必須加大括號：後面緊接全形「）」時，UTF-8 locale 下 bash 會把它的第一個
    # byte 併進變數名，set -u 直接讓整個 subshell 爆掉，診斷訊息就永遠印不出來。
    [ -n "$notafter" ] && [ "$notafter" != "None" ] || { log "[$env] 無法取得 ACM NotAfter（profile=${profile}）"; return 1; }

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

# --- 讀取單一 client 憑證檔的剩餘天數，回傳 "days|enddate"，失敗回傳非 0 ---
client_cert_days_left() {
    local crt="$1"
    local enddate norm exp_epoch now_epoch days
    # openssl 輸出形如 "notAfter=Nov 19 02:21:12 2028 GMT"
    enddate=$(openssl x509 -in "$crt" -noout -enddate 2>>"$LOG_FILE" | cut -d= -f2-)
    [ -n "$enddate" ] || { log "[client] 讀不到 notAfter：$crt"; return 1; }

    # 個位數日期會補成兩個空白（"Jun  5"），先壓成單一空白才餵得進 BSD date
    norm=$(printf '%s' "$enddate" | tr -s ' ')
    exp_epoch=$(date -j -f "%b %d %H:%M:%S %Y %Z" "$norm" +%s 2>/dev/null)
    [ -n "$exp_epoch" ] || { log "[client] 日期解析失敗：${crt}（${enddate}）"; return 1; }

    now_epoch=$(date +%s)
    # 向負無窮取整：未過期天數正確，已過期顯示負數（與 get_days_left 一致）
    days=$(( (exp_epoch - now_epoch) / 86400 ))
    [ $(( (exp_epoch - now_epoch) % 86400 )) -lt 0 ] && days=$(( days - 1 ))
    echo "${days}|${norm}"
}

# --- 發送 Slack（從 SSM 讀 webhook）---
# NO_SLACK=1：算出等級、照常寫 log，但不真的送出。安裝後的自我驗證用這個模式，
# 因為它要驗的是「job 起不起得來」，不是「該不該叫人」——2026-08-17 就是少了它，
# 從 worktree（沒有 configs/）跑驗證，誤發了一則 FAILURE 到團隊 channel。
send_slack() {
    local text="$1" webhook
    if [ "${NO_SLACK:-0}" = "1" ]; then
        log "NO_SLACK=1，略過送出（訊息內容見上）"
        return 0
    fi
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

# --- client 憑證：本機 certs/{env}/users/*.crt（排除 CA）---
# 刻意獨立成第二個迴圈：上面的迴圈在 server 查詢失敗時會 continue，
# 混在一起會讓「ACM 查不到」連帶把 client 憑證檢查也一起跳過。
client_fail=0
client_checked=0
if [ "$SKIP_CLIENT_CERTS" = "1" ]; then
    log "已略過 client 憑證檢查（SKIP_CLIENT_CERTS=1）"
else
    for entry in "${ENVIRONMENTS[@]}"; do
        env="${entry%%:*}"
        users_dir="$PROJECT_ROOT/certs/$env/users"
        [ -d "$users_dir" ] || { log "[$env] 無 client 憑證目錄：${users_dir}"; continue; }
        # nullglob：目錄裡沒有 .crt 時直接不進迴圈，不必用 [ -e ] 去猜 glob 有沒有展開。
        # ⛔ 這裡以前是 `[ -e "$crt" ] || break` —— 一個斷掉的 symlink 會讓整個目錄
        # 剩下的憑證全部不被檢查，而且沒有任何 log。過期憑證就是這樣被漏掉的形狀。
        shopt -s nullglob
        for crt in "$users_dir"/*.crt; do
            if [ ! -e "$crt" ]; then                                 # 斷掉的 symlink / 剛被刪除
                log "[$env] 憑證檔讀不到（斷掉的 symlink？）：${crt}"
                client_fail=$(( client_fail + 1 ))
                continue
            fi
            [ "$(basename "$crt")" = "ca.crt" ] && continue          # CA 不是 client 憑證
            user="$(basename "$crt" .crt)"
            if ! cresult=$(client_cert_days_left "$crt"); then
                client_fail=$(( client_fail + 1 ))
                status_lines+="• ${env}/${user} (client)：⚠️ 讀取失敗（見 log）"$'\n'
                continue
            fi
            client_checked=$(( client_checked + 1 ))
            cdays="${cresult%%|*}"; cend="${cresult##*|}"
            log "[$env] client 憑證 ${user}：剩餘 ${cdays} 天（到期 ${cend}）"
            cicon="✅"
            [ "$cdays" -le "$WARN_DAYS" ] && cicon="🟠"
            [ "$cdays" -le "$CRIT_DAYS" ] && cicon="🔴"
            if [ "$cdays" -le 0 ]; then
                status_lines+="• ${env}/${user} (client)：🔴 已過期 $(( -cdays )) 天（到期 ${cend}）"$'\n'
            else
                status_lines+="• ${env}/${user} (client)：${cicon} 剩 ${cdays} 天（到期 ${cend}）"$'\n'
            fi
            [ "$cdays" -lt "$min_days" ] && min_days="$cdays"
        done
        shopt -u nullglob
    done
    log "client 憑證檢查完成：${client_checked} 張，讀取失敗 ${client_fail} 張"
fi

# 覆蓋數一定要進訊息本體：否則「檢查了 4 張都健康」與「一張都沒看到」
# 送出的內容一模一樣，心跳訊息就證明不了任何事。
if [ "$SKIP_CLIENT_CERTS" = "1" ]; then
    status_lines+="• client 憑證：已略過（SKIP_CLIENT_CERTS=1）"$'\n'
else
    status_lines+="• client 憑證：已檢查 ${client_checked} 張（讀取失敗 ${client_fail} 張）"$'\n'
fi

# client 軸完全看不到東西 ＝ 失明，與「ACM 全部查不到」同級，每天叫。
# 沒有這一條的話，certs/ 不存在只會留一行 log，而對外表現得跟健康完全一樣。
client_blind=0
if [ "$SKIP_CLIENT_CERTS" != "1" ] && [ "$client_checked" -eq 0 ]; then
    client_blind=1
fi

weekday=$(date +%u)   # 1=Mon .. 7=Sun
dom=$(date +%d)       # 01..31

# --- 決定提醒等級（fail-loud：全失敗最高優先，永不靜默吞掉失敗）---
level=""
if [ "$fail_count" -ge "$total" ]; then
    level="FAILURE"                                              # server 全部查詢失敗 → 每天叫
elif [ "$client_blind" = "1" ]; then
    level="FAILURE"                                              # client 軸一張都沒看到 → 每天叫
elif [ "$min_days" -le "$CRIT_DAYS" ]; then
    level="CRITICAL"                                            # 緊急 → 每天
elif [ "$min_days" -le "$WARN_DAYS" ] && [ "$weekday" = "1" ]; then
    level="WARNING"                                             # 接近到期 → 每週一
elif [ "$weekday" = "1" ] && { [ "$fail_count" -gt 0 ] || [ "$client_fail" -gt 0 ]; }; then
    level="WARNING"                                             # 部分查詢失敗（server 或 client）→ 每週一
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
    CRITICAL)  header="🔴 *VPN 憑證即將到期（緊急）*" ;;
    WARNING)   header="🟠 *VPN 憑證到期提醒*" ;;
    HEARTBEAT) header="✅ *VPN 憑證監控月報*" ;;
esac

msg="${header}"$'\n'"${status_lines}"
if [ "$level" = "CRITICAL" ] || [ "$level" = "WARNING" ]; then
    msg+=$'\n'"server 憑證續期：用現有 CA 重簽 → 匯入*新* ACM ARN → modify-client-vpn-endpoint（同 ARN reimport 無效）。詳見 memory: vpn-server-cert-renewal。"
    msg+=$'\n'"client 憑證續期：重新產 CSR → admin-tools/sign_csr.sh 簽 → 換掉 .ovpn 的 <cert>/<key>，server 端不用動。詳見 memory: vpn-client-cert-renewal。"
fi

log "等級=${level}，發送 Slack"
if send_slack "$msg"; then
    log "===== 結束 ====="
else
    log "===== 結束（Slack 發送失敗，alert 未送達）====="
    exit 1
fi
