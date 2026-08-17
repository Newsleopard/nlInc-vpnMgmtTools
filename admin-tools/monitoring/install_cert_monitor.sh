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
missing_conf=0
for _e in staging production; do
    [ -f "$PROJECT_ROOT/configs/$_e/vpn_endpoint.conf" ] || missing_conf=1
done
if [ "$missing_conf" = "1" ]; then
    echo "❌ 這個 checkout 缺少 configs/{staging,production}/vpn_endpoint.conf"
    echo "   —— 看起來是從 git worktree 或全新 clone 安裝的。請改在正式的工作目錄執行："
    echo "   $PROJECT_ROOT"
    exit 1
fi
mkdir -p "$HOME/Library/LaunchAgents" "$LOG_DIR" "$LAUNCHD_LOG_DIR"

# 舊版把 launchd 的 stdout/stderr 放在 $LOG_DIR，那兩個檔帶著 com.apple.macl
# 會讓 job 起不來。改路徑後它們已無作用，順手清掉避免下次誤判。
rm -f "$LOG_DIR/cert_monitor.launchd.out" "$LOG_DIR/cert_monitor.launchd.err"

# $1=1 時額外塞 NO_SLACK=1（只給安裝後驗證那一次用，正式排程不帶）
write_plist() {
    local no_slack_entry=""
    if [ "${1:-0}" = "1" ]; then
        no_slack_entry=$'        <key>NO_SLACK</key>\n        <string>1</string>\n'
    fi
    cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$LABEL</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>$CHECK_SCRIPT</string>
    </array>
    <key>EnvironmentVariables</key>
    <dict>
        <key>PATH</key>
        <string>/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin</string>
${no_slack_entry}    </dict>
    <key>StartCalendarInterval</key>
    <dict>
        <key>Hour</key><integer>10</integer>
        <key>Minute</key><integer>0</integer>
    </dict>
    <key>RunAtLoad</key>
    <false/>
    <key>StandardOutPath</key>
    <string>$LAUNCHD_LOG_DIR/cert_monitor.launchd.out</string>
    <key>StandardErrorPath</key>
    <string>$LAUNCHD_LOG_DIR/cert_monitor.launchd.err</string>
</dict>
</plist>
EOF
}

reload_job() {
    launchctl bootout "$GUI/$LABEL" 2>/dev/null || launchctl unload "$PLIST" 2>/dev/null || true
    launchctl bootstrap "$GUI" "$PLIST" 2>/dev/null || launchctl load -w "$PLIST" 2>/dev/null || {
        echo "⚠️ launchctl 載入失敗（plist 已寫入 $PLIST），請手動檢查：launchctl bootstrap $GUI $PLIST"
        exit 1
    }
}

# 先用「不送 Slack」的版本註冊，跑一次驗證
write_plist 1
reload_job
echo "📝 已產生 plist：$PLIST"

echo "📅 排程已註冊（每天 10:00 執行）"

# --- 安裝後自我驗證：真的跑一次，確認 job 起得來 -----------------------
# 這一步存在的理由：上一版安裝「成功」了，但 job 從 2026-07-12 起每天都以
# EX_CONFIG(78) 失敗、一個多月沒人發現。一個印 ✅ 卻沒驗證過的安裝腳本，
# 本身就是無聲失效點 —— 監控壞掉的樣子跟「一切正常」長得一模一樣。
echo "🔎 安裝後驗證：實際執行一次（NO_SLACK=1，不會發出任何訊息）..."
launchctl kickstart -p "$GUI/$LABEL" >/dev/null 2>&1 || true

# 等到 launchd 記下 last exit code 才算跑完。
# ⛔ 不可改成「等 state 離開 running」：kickstart 是非同步的，job 還沒起來時
# state 就已經不是 running，會在它開始之前就判定失敗（實測踩過）。
exit_code=""
deadline=$(( $(date +%s) + 120 ))
while [ "$(date +%s)" -lt "$deadline" ]; do
    exit_code=$(launchctl print "$GUI/$LABEL" 2>/dev/null | sed -n 's/.*last exit code = \([0-9][0-9]*\).*/\1/p' | head -1) || true
    [ -n "$exit_code" ] && break
    sleep 2
done

if [ "${exit_code:-}" = "0" ]; then
    write_plist 0          # 驗證過了，換成正式設定（不帶 NO_SLACK）
    reload_job
    echo "✅ 驗證通過：job 實際執行完成且 exit 0；已切回正式設定"
    echo "   查看狀態： launchctl print $GUI/$LABEL"
    echo "   查看 log： tail -f $LOG_DIR/cert_monitor.log"
else
    echo "❌ 驗證失敗：last exit code = ${exit_code:-未知}（排程已註冊但跑不起來）"
    echo "   78 = EX_CONFIG，通常是 launchd 開不了 plist 指定的檔案路徑；"
    echo "   先確認 stdout/stderr 路徑不在 ~/Documents 等 TCC 保護目錄下。"
    echo "   診斷： launchctl print $GUI/$LABEL"
    echo "          ls -la@ $LAUNCHD_LOG_DIR"
    exit 1
fi

if [ "${1:-}" = "--test" ]; then
    echo ""
    echo "🧪 立即強制執行一次（FORCE_SEND=1，會發一則 Slack 心跳）..."
    FORCE_SEND=1 /bin/bash "$CHECK_SCRIPT"
    echo "   完成，請檢查 Slack 與 $LOG_DIR/cert_monitor.log"
fi
