#!/usr/bin/env bash
# ====================================================================
# 安裝 VPN 憑證到期監控的 launchd 排程（每天 10:00 執行）
# 用法：
#   ./admin-tools/monitoring/install_cert_monitor.sh           # 安裝 / 重新安裝
#   ./admin-tools/monitoring/install_cert_monitor.sh --test    # 安裝後立即強制發一則 Slack 測試
#   ./admin-tools/monitoring/install_cert_monitor.sh --uninstall
# ====================================================================
set -euo pipefail

LABEL="com.newsleopard.vpn-cert-monitor"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHECK_SCRIPT="$SCRIPT_DIR/check_cert_expiry.sh"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
LOG_DIR="$PROJECT_ROOT/logs"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
GUI="gui/$(id -u)"

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
mkdir -p "$HOME/Library/LaunchAgents" "$LOG_DIR"

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
    </dict>
    <key>StartCalendarInterval</key>
    <dict>
        <key>Hour</key><integer>10</integer>
        <key>Minute</key><integer>0</integer>
    </dict>
    <key>RunAtLoad</key>
    <false/>
    <key>StandardOutPath</key>
    <string>$LOG_DIR/cert_monitor.launchd.out</string>
    <key>StandardErrorPath</key>
    <string>$LOG_DIR/cert_monitor.launchd.err</string>
</dict>
</plist>
EOF

echo "📝 已產生 plist：$PLIST"

# 重新載入
launchctl bootout "$GUI/$LABEL" 2>/dev/null || launchctl unload "$PLIST" 2>/dev/null || true
launchctl bootstrap "$GUI" "$PLIST" 2>/dev/null || launchctl load -w "$PLIST" 2>/dev/null || {
    echo "⚠️ launchctl 載入失敗（plist 已寫入 $PLIST），請手動檢查：launchctl bootstrap $GUI $PLIST"
    exit 1
}

echo "✅ 排程已安裝（每天 10:00 執行）"
echo "   查看狀態： launchctl list | grep $LABEL"
echo "   查看 log： tail -f $LOG_DIR/cert_monitor.log"

if [ "${1:-}" = "--test" ]; then
    echo ""
    echo "🧪 立即強制執行一次（FORCE_SEND=1，會發一則 Slack 心跳）..."
    FORCE_SEND=1 /bin/bash "$CHECK_SCRIPT"
    echo "   完成，請檢查 Slack 與 $LOG_DIR/cert_monitor.log"
fi
