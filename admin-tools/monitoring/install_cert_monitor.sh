#!/usr/bin/env bash
# ====================================================================
# 安裝 VPN 憑證到期監控的 launchd 排程（每天 10:00 執行）
# 用法：
#   ./admin-tools/monitoring/install_cert_monitor.sh           # 安裝 / 重新安裝
#   ./admin-tools/monitoring/install_cert_monitor.sh --test    # 安裝後立即強制發一則 Slack 測試
#   ./admin-tools/monitoring/install_cert_monitor.sh --uninstall
# ====================================================================
set -euo pipefail

# 可用 VPN_CERT_MONITOR_LABEL 覆寫，讓安裝流程本身能在不動到正式 job 的前提下被測試
LABEL="${VPN_CERT_MONITOR_LABEL:-com.newsleopard.vpn-cert-monitor}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHECK_SCRIPT="$SCRIPT_DIR/check_cert_expiry.sh"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
LOG_DIR="$PROJECT_ROOT/logs"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
GUI="gui/$(id -u)"

# launchd 自己開的 stdout/stderr 一定要放在 ~/Documents 之外。
# 原因（2026-08-17 實測）：~/Documents 底下的檔案會被系統蓋上 com.apple.macl
# 這個檔案級 TCC ACL，只授權特定 app 存取。macOS 26.5.2 更新（2026-07-11）之後
# launchd 不在授權名單內，開不了那兩個檔 → 每次啟動都以 EX_CONFIG(78) 失敗，
# 腳本一行都沒跑，而且 stderr 也寫不出來 → 監控靜默死亡一個多月沒人發現。
# ~/Library/Logs 不受 TCC 保護，不會有這個問題。
LAUNCHD_LOG_DIR="$HOME/Library/Logs/newsleopard-vpn"

uninstall() {
    launchctl bootout "$GUI/$LABEL" 2>/dev/null || launchctl unload "$PLIST" 2>/dev/null || true
    rm -f "$PLIST"
    echo "✅ 已移除排程與 plist：$PLIST"
}

if [ "${1:-}" = "--uninstall" ]; then
    uninstall
    exit 0
fi

[ -f "$CHECK_SCRIPT" ] || { echo "❌ 找不到檢查腳本：$CHECK_SCRIPT"; exit 1; }
chmod +x "$CHECK_SCRIPT"

# 從 git worktree 安裝會裝出一個沒有 configs/ 也沒有 certs/ 的監控（兩者都被
# gitignore），每天都判成「查詢失敗」而狂發假警報，而且 worktree 一刪就整個斷掉。
# 檢查的環境要跟 check_cert_expiry.sh 一致：VPN_CERT_ENVS 有設就以它為準，
# 否則才用預設的兩個。寫死 staging+production 會讓單一 profile 的機器裝不起來，
# 而 VPN_CERT_ENVS 這個覆寫正是為那種機器存在的。
if [ -n "${VPN_CERT_ENVS:-}" ]; then
    # shellcheck disable=SC2206
    _install_envs=($VPN_CERT_ENVS)
else
    _install_envs=("staging:staging" "production:production")
fi

missing_conf=""
missing_certs=""
for _entry in "${_install_envs[@]}"; do
    _e="${_entry%%:*}"
    [ -f "$PROJECT_ROOT/configs/$_e/vpn_endpoint.conf" ] || missing_conf="$missing_conf $_e"
    [ -d "$PROJECT_ROOT/certs/$_e/users" ] || missing_certs="$missing_certs $_e"
done

if [ -n "$missing_conf" ]; then
    echo "❌ 這個 checkout 缺少 configs/{$(echo "$missing_conf" | tr ' ' ',' | sed 's/^,//')}/vpn_endpoint.conf"
    echo "   —— 看起來是從 git worktree 或全新 clone 安裝的（configs/ 與 certs/ 都被 gitignore）。"
    echo "   從這裡安裝會每天發假警報，而且 worktree 一刪監控就整個斷掉。"
    echo "   請改在正式的工作目錄執行： $PROJECT_ROOT"
    exit 1
fi

# certs/ 缺少只擋不住，但一定要講出來 —— 它的失效方向是「安靜地什麼都不檢查」。
if [ -n "$missing_certs" ] && [ "${SKIP_CLIENT_CERTS:-0}" != "1" ]; then
    echo "⚠️ 找不到 client 憑證目錄：${missing_certs}（certs/<env>/users）"
    echo "   監控會照常安裝，但 client 憑證那一軸在這台機器上不會檢查到任何東西。"
    echo "   若這台機器本來就不該有 certs/，請改用 SKIP_CLIENT_CERTS=1 安裝，讓意圖留下紀錄。"
fi
mkdir -p "$HOME/Library/LaunchAgents" "$LOG_DIR" "$LAUNCHD_LOG_DIR"

# 舊版把 launchd 的 stdout/stderr 放在 $LOG_DIR，那兩個檔帶著 com.apple.macl
# 會讓 job 起不來。改路徑後它們已無作用，順手清掉避免下次誤判。
rm -f "$LOG_DIR/cert_monitor.launchd.out" "$LOG_DIR/cert_monitor.launchd.err"

# --- plist 產生器 -----------------------------------------------------
# 🔴 正式 plist 永遠不帶 NO_SLACK。驗證要用的「不發訊息」設定一律走下面的
# 影子 job（獨立 label、獨立檔案、trap 保證移除），這樣任何失敗路徑
# ——exit 1、逾時、Ctrl-C、set -e—— 都不可能留下一個註冊著、天天 exit 0、
# 卻永遠不發告警的正式 job。那種狀態比沒有監控更糟：它會讓人以為有監控。
# $1=plist 路徑 $2=label $3=no_slack(0|1) $4=stdout/stderr 檔名前綴
write_plist() {
    local plist_path="$1" label="$2" no_slack="$3" out_prefix="$4"
    local extra_env=""
    [ "$no_slack" = "1" ] && extra_env+=$'        <key>NO_SLACK</key>\n        <string>1</string>\n'
    # 這兩個是 check_cert_expiry.sh 的設定開關；只在本機有設時才寫進 plist，
    # 否則排程跑起來會忽略操作者在 shell 裡驗證過的設定（launchd 不繼承 shell 環境）。
    [ -n "${SKIP_CLIENT_CERTS:-}" ] && extra_env+=$'        <key>SKIP_CLIENT_CERTS</key>\n        <string>'"${SKIP_CLIENT_CERTS}"$'</string>\n'
    [ -n "${VPN_CERT_ENVS:-}" ] && extra_env+=$'        <key>VPN_CERT_ENVS</key>\n        <string>'"${VPN_CERT_ENVS}"$'</string>\n'
    cat > "$plist_path" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$label</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>$CHECK_SCRIPT</string>
    </array>
    <key>EnvironmentVariables</key>
    <dict>
        <key>PATH</key>
        <string>/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin</string>
${extra_env}    </dict>
    <key>StartCalendarInterval</key>
    <dict>
        <key>Hour</key><integer>10</integer>
        <key>Minute</key><integer>0</integer>
    </dict>
    <key>RunAtLoad</key>
    <false/>
    <key>StandardOutPath</key>
    <string>${out_prefix}.out</string>
    <key>StandardErrorPath</key>
    <string>${out_prefix}.err</string>
</dict>
</plist>
EOF
}

# 只印安全欄位 —— launchctl print 會把整個 login session 的 inherited environment
# 原樣吐出來（本機實際含有一個 ASANA PAT），不能叫人直接貼那份輸出去回報問題。
SAFE_PRINT="launchctl print $GUI/$LABEL | grep -E 'state|last exit code|std(out|err) path'"

# --- 第一段驗證：launchd 起得來嗎（用影子 job，絕不碰正式 plist）---------
VERIFY_LABEL="${LABEL}.verify"
VERIFY_PLIST="$LAUNCHD_LOG_DIR/${VERIFY_LABEL}.plist"
cleanup_verify() {
    launchctl bootout "$GUI/$VERIFY_LABEL" 2>/dev/null || true
    rm -f "$VERIFY_PLIST"
}
trap cleanup_verify EXIT

echo "🔎 安裝前驗證：用一次性影子 job 實際跑一次（NO_SLACK=1，不會發出任何訊息）..."
write_plist "$VERIFY_PLIST" "$VERIFY_LABEL" 1 "$LAUNCHD_LOG_DIR/verify"
launchctl bootout "$GUI/$VERIFY_LABEL" 2>/dev/null || true
if ! launchctl bootstrap "$GUI" "$VERIFY_PLIST" 2>&1; then
    echo "❌ 影子 job 載入失敗 —— launchd 連這份設定都收不下，正式 plist 不會被安裝。"
    exit 1
fi
launchctl kickstart -p "$GUI/$VERIFY_LABEL" >/dev/null 2>&1 || true

# 等到 launchd 記下 last exit code 才算跑完。
# ⛔ 不可改成「等 state 離開 running」：kickstart 是非同步的，job 還沒起來時
# state 就已經不是 running，會在它開始之前就判定失敗（實測踩過）。
exit_code=""
deadline=$(( $(date +%s) + 120 ))
while [ "$(date +%s)" -lt "$deadline" ]; do
    exit_code=$(launchctl print "$GUI/$VERIFY_LABEL" 2>/dev/null | sed -n 's/.*last exit code = \([0-9][0-9]*\).*/\1/p' | head -1) || true
    [ -n "$exit_code" ] && break
    sleep 2
done

if [ "${exit_code:-}" != "0" ]; then
    echo "❌ 驗證失敗：last exit code = ${exit_code:-未知（逾時，120 秒內沒跑完）}"
    echo "   ⛔ 正式排程未安裝 —— 寧可沒有監控，也不要裝一個看起來活著卻不會叫的。"
    echo "   78 = EX_CONFIG，通常是 launchd 開不了 plist 指定的檔案路徑；"
    echo "   先確認 stdout/stderr 路徑不在 ~/Documents 等 TCC 保護目錄下。"
    if [ -s "$LAUNCHD_LOG_DIR/verify.err" ]; then
        echo "   影子 job 的 stderr（保留在 $LAUNCHD_LOG_DIR/verify.err）："
        sed 's/^/     | /' "$LAUNCHD_LOG_DIR/verify.err"
    fi
    echo "   診斷： ls -la@ ${LAUNCHD_LOG_DIR}"
    exit 1
fi

# 第二段驗證：exit 0 只證明「行程跑完了」，不證明它看得見任何東西。
# NO_SLACK 之下即使全部查詢失敗也是 exit 0，所以再看它這一輪的實際產出。
covered=$(grep -c '剩餘' "$LOG_DIR/cert_monitor.log" 2>/dev/null || echo 0)
if [ "${covered:-0}" -eq 0 ]; then
    echo "⚠️ 注意：這一輪沒有任何憑證被實際讀到（log 沒有『剩餘 N 天』）。"
    echo "   job 起得來，但它可能什麼都看不到 —— 請檢查 $LOG_DIR/cert_monitor.log"
fi

cleanup_verify
# 驗證成功才清掉影子 job 的 stdout/stderr；失敗時刻意留著當診斷線索。
rm -f "$LAUNCHD_LOG_DIR/verify.out" "$LAUNCHD_LOG_DIR/verify.err"
trap - EXIT

# --- 驗證過了才安裝正式排程（永遠不帶 NO_SLACK）------------------------
write_plist "$PLIST" "$LABEL" 0 "$LAUNCHD_LOG_DIR/cert_monitor.launchd"
launchctl bootout "$GUI/$LABEL" 2>/dev/null || launchctl unload "$PLIST" 2>/dev/null || true
launchctl bootstrap "$GUI" "$PLIST" 2>/dev/null || launchctl load -w "$PLIST" 2>/dev/null || {
    echo "⚠️ launchctl 載入失敗（plist 已寫入 ${PLIST}），請手動檢查：launchctl bootstrap $GUI $PLIST"
    exit 1
}
grep -q 'NO_SLACK' "$PLIST" && { echo "❌ 內部錯誤：正式 plist 竟然含 NO_SLACK，已中止"; exit 1; }

echo "📝 已產生 plist：$PLIST"
echo "✅ 已驗證 launchd 可以啟動此設定並執行完成（exit 0），排程已安裝（每天 10:00）"
echo "   查看狀態： $SAFE_PRINT"
echo "   查看 log： tail -f $LOG_DIR/cert_monitor.log"

if [ "${1:-}" = "--test" ]; then
    echo ""
    echo "🧪 立即強制執行一次（FORCE_SEND=1，會發一則 Slack 心跳）..."
    FORCE_SEND=1 /bin/bash "$CHECK_SCRIPT"
    echo "   完成，請檢查 Slack 與 $LOG_DIR/cert_monitor.log"
fi
