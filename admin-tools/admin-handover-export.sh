#!/bin/bash
# =============================================================================
# VPN 管理員交接匯出腳本
# 用途：既有管理員使用此腳本匯出所有必要的 VPN 系統檔案和設定
# 作者：NewsLeopard VPN Toolkit
# =============================================================================

set -e

# 設定顏色輸出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 獲取腳本目錄
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

echo -e "${BLUE}================================${NC}"
echo -e "${BLUE}VPN 管理員交接匯出工具${NC}"
echo -e "${BLUE}================================${NC}"
echo ""

# 檢查必要工具
check_dependencies() {
    echo -e "${YELLOW}🔧 檢查必要工具...${NC}"

    for tool in openssl tar sha256sum; do
        if ! command -v $tool &> /dev/null; then
            echo -e "${RED}❌ 缺少必要工具：$tool${NC}"
            echo "請先安裝：brew install $tool"
            exit 1
        fi
    done

    echo -e "${GREEN}✅ 所有必要工具已就緒${NC}"
    echo ""
}

# 收集檔案清單
collect_files() {
    echo -e "${YELLOW}📦 收集交接檔案...${NC}"

    HANDOVER_FILES=()

    # 檢查並收集憑證檔案
    if [ -f "$PROJECT_ROOT/certs/staging/pki/private/ca.key" ]; then
        HANDOVER_FILES+=("certs/staging/pki/private/ca.key")
        HANDOVER_FILES+=("certs/staging/pki/ca.crt")
        HANDOVER_FILES+=("certs/staging/pki/private/server.key")
        HANDOVER_FILES+=("certs/staging/pki/issued/server.crt")
        echo -e "${GREEN}✅ 找到 Staging 環境 CA 憑證${NC}"
    else
        echo -e "${YELLOW}⚠️  未找到 Staging 環境 CA 憑證${NC}"
    fi

    if [ -f "$PROJECT_ROOT/certs/prod/pki/private/ca.key" ]; then
        HANDOVER_FILES+=("certs/prod/pki/private/ca.key")
        HANDOVER_FILES+=("certs/prod/pki/ca.crt")
        HANDOVER_FILES+=("certs/prod/pki/private/server.key")
        HANDOVER_FILES+=("certs/prod/pki/issued/server.crt")
        echo -e "${GREEN}✅ 找到 Production 環境 CA 憑證${NC}"
    else
        echo -e "${YELLOW}⚠️  未找到 Production 環境 CA 憑證${NC}"
    fi

    # 檢查並收集設定檔案
    if [ -f "$PROJECT_ROOT/configs/staging/staging.env" ]; then
        HANDOVER_FILES+=("configs/staging/staging.env")
        HANDOVER_FILES+=("configs/staging/vpn_endpoint.conf")
        echo -e "${GREEN}✅ 找到 Staging 環境設定檔${NC}"
    else
        echo -e "${YELLOW}⚠️  未找到 Staging 環境設定檔${NC}"
    fi

    if [ -f "$PROJECT_ROOT/configs/prod/prod.env" ]; then
        HANDOVER_FILES+=("configs/prod/prod.env")
        HANDOVER_FILES+=("configs/prod/vpn_endpoint.conf")
        echo -e "${GREEN}✅ 找到 Production 環境設定檔${NC}"
    else
        echo -e "${YELLOW}⚠️  未找到 Production 環境設定檔${NC}"
    fi

    # 收集其他重要檔案
    if [ -f "$PROJECT_ROOT/.gitignore" ]; then
        HANDOVER_FILES+=(".gitignore")
    fi

    if [ -d "$PROJECT_ROOT/iam-policies" ]; then
        for policy_file in "$PROJECT_ROOT/iam-policies"/*.json; do
            if [ -f "$policy_file" ]; then
                # Use basename to get relative path (macOS compatible)
                relative_path="iam-policies/$(basename "$policy_file")"
                HANDOVER_FILES+=("$relative_path")
            fi
        done
        echo -e "${GREEN}✅ 找到 IAM 政策檔案${NC}"
    fi

    echo -e "${GREEN}📋 共收集 ${#HANDOVER_FILES[@]} 個檔案${NC}"
    echo ""
}

# 建立交接包
create_handover_package() {
    echo -e "${YELLOW}🔐 建立交接包...${NC}"

    # 生成交接 ID
    HANDOVER_ID="vpn-handover-$(date +%Y%m%d-%H%M%S)"
    TEMP_DIR="/tmp/$HANDOVER_ID"
    PACKAGE_FILE="$PROJECT_ROOT/$HANDOVER_ID.tar.gz.enc"

    # 建立暫存目錄
    mkdir -p "$TEMP_DIR"

    # 複製檔案到暫存目錄
    cd "$PROJECT_ROOT"
    for file in "${HANDOVER_FILES[@]}"; do
        if [ -f "$file" ]; then
            # 保持目錄結構
            mkdir -p "$TEMP_DIR/$(dirname "$file")"
            cp "$file" "$TEMP_DIR/$file"
            echo "✓ 已複製：$file"
        fi
    done

    # 建立交接資訊檔案
    cat > "$TEMP_DIR/handover-info.txt" << EOF
VPN 系統交接資訊
================

交接 ID：$HANDOVER_ID
建立時間：$(date '+%Y-%m-%d %H:%M:%S %Z')
建立者：$(whoami)@$(hostname)
Git 版本：$(git rev-parse --short HEAD 2>/dev/null || echo "N/A")

檔案清單：
EOF

    # 添加檔案清單到資訊檔案
    for file in "${HANDOVER_FILES[@]}"; do
        if [ -f "$PROJECT_ROOT/$file" ]; then
            echo "- $file" >> "$TEMP_DIR/handover-info.txt"
        fi
    done

    echo ""
    echo -e "${YELLOW}🔑 請設定加密密碼${NC}"
    echo -e "${YELLOW}重要：密碼必須透過安全管道（電話或面對面）傳遞給新任管理員${NC}"
    echo ""

    # 要求輸入加密密碼
    read -s -p "請輸入加密密碼（至少 8 位元）: " PASSWORD
    echo ""
    read -s -p "請再次確認密碼: " PASSWORD_CONFIRM
    echo ""

    if [ "$PASSWORD" != "$PASSWORD_CONFIRM" ]; then
        echo -e "${RED}❌ 密碼不匹配！${NC}"
        rm -rf "$TEMP_DIR"
        exit 1
    fi

    if [ ${#PASSWORD} -lt 8 ]; then
        echo -e "${RED}❌ 密碼長度至少需要 8 位元！${NC}"
        rm -rf "$TEMP_DIR"
        exit 1
    fi

    # 建立加密的 tar 檔案
    cd "$TEMP_DIR"
    tar -czf - * | openssl enc -aes-256-cbc -salt -k "$PASSWORD" -out "$PACKAGE_FILE"

    # 生成檢查碼
    CHECKSUM=$(sha256sum "$PACKAGE_FILE" | cut -d' ' -f1)

    # 清理暫存檔案
    cd "$PROJECT_ROOT"
    rm -rf "$TEMP_DIR"

    echo -e "${GREEN}✅ 交接包建立完成！${NC}"
    echo ""
    echo -e "${BLUE}檔案位置：$PACKAGE_FILE${NC}"
    echo -e "${BLUE}檢查碼：$CHECKSUM${NC}"
    echo -e "${BLUE}檔案大小：$(du -h "$PACKAGE_FILE" | cut -f1)${NC}"
    echo ""
}

# 顯示交接說明（繁體中文）
show_handover_instructions() {
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}🎯 交接完成！請按照以下步驟進行：${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo ""

    echo -e "${YELLOW}📋 既有管理員（您）需要執行：${NC}"
    echo ""
    echo -e "1. ${BLUE}密碼傳遞（重要）${NC}"
    echo "   ✓ 透過電話或面對面方式告知新任管理員加密密碼"
    echo "   ✓ 絕不可透過 Email、Slack 或其他線上方式傳送密碼"
    echo "   ✓ 確認新任管理員正確記錄密碼"
    echo ""

    echo -e "2. ${BLUE}檔案傳遞${NC}"
    echo "   選項 A - 實體傳遞（最安全）："
    echo "   ✓ 將檔案複製到 USB 隨身碟"
    echo "   ✓ 親自交給新任管理員"
    echo ""
    echo "   選項 B - S3 臨時上傳："
    echo "   ✓ 執行以下指令上傳到臨時位置："
    echo -e "     ${GREEN}aws s3 cp $PACKAGE_FILE s3://your-temp-bucket/handover/ --expires \"\$(date -d '+7 days' -Iseconds)\"${NC}"
    echo "   ✓ 將 S3 URL 提供給新任管理員"
    echo "   ✓ 7 天後檔案將自動過期"
    echo ""

    echo -e "3. ${BLUE}交接驗證${NC}"
    echo "   ✓ 確認新任管理員成功執行 admin-handover-import.sh"
    echo "   ✓ 協助新任管理員測試基本 VPN 功能"
    echo "   ✓ 確認新任管理員能夠存取 AWS 控制台"
    echo ""

    echo -e "${YELLOW}📋 新任管理員需要執行：${NC}"
    echo ""
    echo -e "1. ${BLUE}環境準備${NC}"
    echo "   ✓ 確保已安裝 AWS CLI、openssl、jq 等工具"
    echo "   ✓ 設定基本的 AWS profiles（staging、production）"
    echo ""

    echo -e "2. ${BLUE}執行匯入腳本${NC}"
    echo "   ✓ 將交接包下載到專案根目錄"
    echo -e "   ✓ 執行：${GREEN}./admin-tools/admin-handover-import.sh $(basename "$PACKAGE_FILE")${NC}"
    echo ""

    echo -e "${RED}🔒 安全注意事項：${NC}"
    echo "• 交接完成後，請立即刪除交接包檔案"
    echo "• 建議新任管理員在確認無誤後更換所有密碼和金鑰"
    echo "• 如有任何問題，請聯繫技術支援團隊"
    echo ""

    echo -e "${BLUE}📞 緊急聯絡資訊：${NC}"
    echo "• 技術支援：ct@newsleopard.tw"
    echo "• Slack 頻道：#vpn-support"
    echo "• 文件位置：docs/admin-handover-guide.md"
    echo ""
}

# 主要執行流程
main() {
    cd "$PROJECT_ROOT"

    check_dependencies
    collect_files

    # 檢查是否有檔案可以交接
    if [ ${#HANDOVER_FILES[@]} -eq 0 ]; then
        echo -e "${RED}❌ 未找到任何可交接的檔案！${NC}"
        echo "請確認專案結構完整且憑證檔案存在。"
        exit 1
    fi

    create_handover_package
    show_handover_instructions

    echo -e "${GREEN}✨ 交接匯出完成！${NC}"
}

# 執行主程式
main "$@"