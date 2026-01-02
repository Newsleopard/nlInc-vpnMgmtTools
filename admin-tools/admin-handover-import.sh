#!/bin/bash
# =============================================================================
# VPN 管理員交接匯入腳本
# 用途：新任管理員使用此腳本匯入和恢復 VPN 系統檔案和設定
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
echo -e "${BLUE}VPN 管理員交接匯入工具${NC}"
echo -e "${BLUE}================================${NC}"
echo ""

# 檢查參數
if [ $# -ne 1 ]; then
    echo -e "${RED}使用方式：$0 <交接包檔案>${NC}"
    echo ""
    echo "範例："
    echo "  $0 vpn-handover-20240101-123456.tar.gz.enc"
    echo ""
    exit 1
fi

HANDOVER_FILE="$1"

# 檢查交接包檔案
if [ ! -f "$HANDOVER_FILE" ]; then
    echo -e "${RED}❌ 找不到交接包檔案：$HANDOVER_FILE${NC}"
    exit 1
fi

# 檢查必要工具
check_dependencies() {
    echo -e "${YELLOW}🔧 檢查必要工具...${NC}"

    local missing_tools=()

    for tool in openssl tar sha256sum aws jq; do
        if ! command -v $tool &> /dev/null; then
            missing_tools+=("$tool")
        fi
    done

    if [ ${#missing_tools[@]} -ne 0 ]; then
        echo -e "${RED}❌ 缺少必要工具：${missing_tools[*]}${NC}"
        echo ""
        echo "請先安裝缺少的工具："
        for tool in "${missing_tools[@]}"; do
            case $tool in
                aws)
                    echo "  brew install awscli"
                    ;;
                jq)
                    echo "  brew install jq"
                    ;;
                *)
                    echo "  brew install $tool"
                    ;;
            esac
        done
        echo ""
        exit 1
    fi

    echo -e "${GREEN}✅ 所有必要工具已就緒${NC}"
    echo ""
}

# 驗證 AWS 設定
check_aws_configuration() {
    echo -e "${YELLOW}☁️  檢查 AWS 設定...${NC}"

    # 檢查 AWS profiles
    local required_profiles=("staging" "production" "prod")
    local available_profiles
    available_profiles=$(aws configure list-profiles 2>/dev/null || echo "")

    echo "可用的 AWS profiles："
    if [ -n "$available_profiles" ]; then
        echo "$available_profiles" | sed 's/^/  - /'
        echo ""
    else
        echo -e "${YELLOW}⚠️  未找到任何 AWS profile${NC}"
        echo ""
    fi

    # 檢查基本連線
    for profile in "staging" "prod" "production"; do
        if echo "$available_profiles" | grep -q "^$profile$"; then
            echo -n "測試 $profile profile 連線... "
            if aws sts get-caller-identity --profile "$profile" &>/dev/null; then
                echo -e "${GREEN}✅ 成功${NC}"
            else
                echo -e "${YELLOW}⚠️  連線失敗${NC}"
            fi
        fi
    done
    echo ""
}

# 解密交接包
decrypt_handover_package() {
    echo -e "${YELLOW}🔓 解密交接包...${NC}"

    # 生成檢查碼並驗證
    ACTUAL_CHECKSUM=$(sha256sum "$HANDOVER_FILE" | cut -d' ' -f1)
    echo -e "${BLUE}檔案檢查碼：$ACTUAL_CHECKSUM${NC}"

    # 要求輸入解密密碼
    echo ""
    echo -e "${YELLOW}請輸入既有管理員提供的解密密碼：${NC}"
    read -s -p "解密密碼: " PASSWORD
    echo ""

    # 建立暫存目錄
    HANDOVER_ID=$(basename "$HANDOVER_FILE" .tar.gz.enc)
    TEMP_DIR="/tmp/$HANDOVER_ID-import"
    mkdir -p "$TEMP_DIR"

    # 解密檔案
    echo -e "${YELLOW}正在解密檔案...${NC}"
    if ! openssl enc -aes-256-cbc -d -salt -k "$PASSWORD" -in "$HANDOVER_FILE" | tar -xzf - -C "$TEMP_DIR" 2>/dev/null; then
        echo -e "${RED}❌ 解密失敗！密碼可能不正確。${NC}"
        rm -rf "$TEMP_DIR"
        exit 1
    fi

    echo -e "${GREEN}✅ 交接包解密成功${NC}"

    # 顯示交接資訊
    if [ -f "$TEMP_DIR/handover-info.txt" ]; then
        echo ""
        echo -e "${BLUE}📋 交接資訊：${NC}"
        cat "$TEMP_DIR/handover-info.txt" | sed 's/^/  /'
        echo ""
    fi
}

# 恢復檔案
restore_files() {
    echo -e "${YELLOW}📁 恢復檔案到專案目錄...${NC}"

    cd "$PROJECT_ROOT"

    # 計算恢復的檔案數量
    local restored_count=0

    # 恢復所有檔案，保持目錄結構
    find "$TEMP_DIR" -type f ! -name "handover-info.txt" | while read -r file; do
        # 計算相對路徑
        relative_path=$(realpath --relative-to="$TEMP_DIR" "$file")
        target_path="$PROJECT_ROOT/$relative_path"

        # 建立目標目錄
        mkdir -p "$(dirname "$target_path")"

        # 備份現有檔案（如果存在）
        if [ -f "$target_path" ]; then
            backup_path="${target_path}.backup.$(date +%Y%m%d-%H%M%S)"
            cp "$target_path" "$backup_path"
            echo -e "${YELLOW}⚠️  已備份現有檔案：$(basename "$target_path") -> $(basename "$backup_path")${NC}"
        fi

        # 複製檔案
        cp "$file" "$target_path"

        # 設定適當的檔案權限
        if [[ "$relative_path" == *".key" ]] || [[ "$relative_path" == *"/private/"* ]]; then
            chmod 600 "$target_path"
            echo -e "${GREEN}✓ 已恢復（私鑰）：$relative_path${NC}"
        elif [[ "$relative_path" == *".env" ]]; then
            chmod 600 "$target_path"
            echo -e "${GREEN}✓ 已恢復（設定檔）：$relative_path${NC}"
        else
            echo -e "${GREEN}✓ 已恢復：$relative_path${NC}"
        fi

        ((restored_count++))
    done

    echo ""
    echo -e "${GREEN}📦 共恢復 $restored_count 個檔案${NC}"
}

# 驗證憑證
verify_certificates() {
    echo -e "${YELLOW}🔒 驗證憑證完整性...${NC}"

    local cert_errors=0

    # 檢查 Staging 環境憑證
    if [ -f "$PROJECT_ROOT/certs/staging/pki/private/ca.key" ] && [ -f "$PROJECT_ROOT/certs/staging/pki/ca.crt" ]; then
        echo -n "驗證 Staging CA 憑證... "
        if openssl x509 -in "$PROJECT_ROOT/certs/staging/pki/ca.crt" -noout -text &>/dev/null; then
            # 檢查憑證和私鑰是否匹配
            cert_modulus=$(openssl x509 -in "$PROJECT_ROOT/certs/staging/pki/ca.crt" -noout -modulus 2>/dev/null)
            key_modulus=$(openssl rsa -in "$PROJECT_ROOT/certs/staging/pki/private/ca.key" -noout -modulus 2>/dev/null)

            if [ "$cert_modulus" = "$key_modulus" ]; then
                echo -e "${GREEN}✅ 有效${NC}"
            else
                echo -e "${RED}❌ 憑證與私鑰不匹配${NC}"
                ((cert_errors++))
            fi
        else
            echo -e "${RED}❌ 憑證格式錯誤${NC}"
            ((cert_errors++))
        fi
    else
        echo -e "${YELLOW}⚠️  Staging CA 憑證文件不完整${NC}"
    fi

    # 檢查 Production 環境憑證
    if [ -f "$PROJECT_ROOT/certs/production/pki/private/ca.key" ] && [ -f "$PROJECT_ROOT/certs/production/pki/ca.crt" ]; then
        echo -n "驗證 Production CA 憑證... "
        if openssl x509 -in "$PROJECT_ROOT/certs/production/pki/ca.crt" -noout -text &>/dev/null; then
            # 檢查憑證和私鑰是否匹配
            cert_modulus=$(openssl x509 -in "$PROJECT_ROOT/certs/production/pki/ca.crt" -noout -modulus 2>/dev/null)
            key_modulus=$(openssl rsa -in "$PROJECT_ROOT/certs/production/pki/private/ca.key" -noout -modulus 2>/dev/null)

            if [ "$cert_modulus" = "$key_modulus" ]; then
                echo -e "${GREEN}✅ 有效${NC}"
            else
                echo -e "${RED}❌ 憑證與私鑰不匹配${NC}"
                ((cert_errors++))
            fi
        else
            echo -e "${RED}❌ 憑證格式錯誤${NC}"
            ((cert_errors++))
        fi
    else
        echo -e "${YELLOW}⚠️  Production CA 憑證文件不完整${NC}"
    fi

    if [ $cert_errors -eq 0 ]; then
        echo -e "${GREEN}✅ 所有憑證驗證通過${NC}"
    else
        echo -e "${YELLOW}⚠️  發現 $cert_errors 個憑證問題，請聯繫既有管理員確認${NC}"
    fi

    echo ""
}

# 測試系統連線
test_system_connectivity() {
    echo -e "${YELLOW}🌐 測試系統連線...${NC}"

    # 測試 AWS VPN 端點
    for env in "staging" "production"; do
        config_file="$PROJECT_ROOT/configs/$env"
        if [ "$env" = "staging" ]; then
            config_file="$config_file/staging.env"
            profile="default"
        else
            config_file="$config_file/production.env"
            profile="prod"
        fi

        if [ -f "$config_file" ]; then
            echo -n "測試 $env 環境 VPN 端點存取... "

            # 從設定檔讀取端點 ID
            endpoint_id=""
            if [ -f "$PROJECT_ROOT/configs/$env/vpn_endpoint.conf" ]; then
                endpoint_id=$(grep "^ENDPOINT_ID=" "$PROJECT_ROOT/configs/$env/vpn_endpoint.conf" 2>/dev/null | cut -d'=' -f2 | tr -d '"')
            fi

            if [ -n "$endpoint_id" ] && aws ec2 describe-client-vpn-endpoints --client-vpn-endpoint-ids "$endpoint_id" --profile "$profile" &>/dev/null; then
                echo -e "${GREEN}✅ 可存取${NC}"
            elif aws configure list-profiles | grep -q "^$profile$"; then
                echo -e "${YELLOW}⚠️  端點 ID 可能需要更新${NC}"
            else
                echo -e "${YELLOW}⚠️  AWS profile 未設定${NC}"
            fi
        fi
    done

    # 測試 S3 存取
    echo -n "測試 S3 憑證交換存取... "
    if aws s3 ls s3://vpn-csr-exchange/ --profile staging &>/dev/null || aws s3 ls s3://vpn-csr-exchange/ --profile prod &>/dev/null; then
        echo -e "${GREEN}✅ 可存取${NC}"
    else
        echo -e "${YELLOW}⚠️  S3 存取可能需要設定${NC}"
    fi

    echo ""
}

# 顯示環境狀態摘要
show_system_summary() {
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}🎉 交接匯入完成！環境狀態摘要：${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo ""

    # 環境設定狀態
    echo -e "${BLUE}📋 環境設定狀態：${NC}"
    for env in "staging" "production"; do
        config_file="$PROJECT_ROOT/configs/$env"
        if [ "$env" = "staging" ]; then
            config_file="$config_file/staging.env"
        else
            config_file="$config_file/production.env"
        fi

        if [ -f "$config_file" ]; then
            echo -e "  ${GREEN}✅ $env 環境設定檔${NC}"
        else
            echo -e "  ${RED}❌ $env 環境設定檔${NC}"
        fi
    done
    echo ""

    # 憑證狀態
    echo -e "${BLUE}🔒 憑證狀態：${NC}"
    for env in "staging" "production"; do
        ca_key="$PROJECT_ROOT/certs/$env/pki/private/ca.key"
        ca_cert="$PROJECT_ROOT/certs/$env/pki/ca.crt"

        if [ -f "$ca_key" ] && [ -f "$ca_cert" ]; then
            # 顯示憑證到期時間
            expiry=$(openssl x509 -in "$ca_cert" -noout -enddate 2>/dev/null | cut -d= -f2)
            echo -e "  ${GREEN}✅ $env CA 憑證（到期：$expiry）${NC}"
        else
            echo -e "  ${RED}❌ $env CA 憑證${NC}"
        fi
    done
    echo ""

    # 下一步操作
    echo -e "${YELLOW}📋 接下來請執行：${NC}"
    echo ""
    echo -e "1. ${BLUE}驗證 AWS 設定${NC}"
    echo "   ✓ 確認 AWS profiles 設定正確"
    echo "   ✓ 測試對各環境的存取權限"
    echo ""

    echo -e "2. ${BLUE}測試管理工具${NC}"
    echo -e "   ✓ 執行：${GREEN}./admin-tools/aws_vpn_admin.sh${NC}"
    echo "   ✓ 確認可以檢視 VPN 端點狀態"
    echo ""

    echo -e "3. ${BLUE}測試憑證簽署功能${NC}"
    echo "   ✓ 可以嘗試簽署測試憑證"
    echo "   ✓ 確認 S3 上傳下載功能正常"
    echo ""

    echo -e "4. ${BLUE}更新系統存取認證（建議）${NC}"
    echo "   ✓ 考慮更換 Slack App 簽署密鑰"
    echo "   ✓ 考慮輪換敏感的系統密碼"
    echo ""

    echo -e "${RED}🔒 安全提醒：${NC}"
    echo "• 請立即刪除交接包檔案及其備份"
    echo "• 確認既有管理員已失去系統存取權"
    echo "• 建議在適當時機重新產生 CA 憑證"
    echo ""

    echo -e "${BLUE}📞 支援聯絡：${NC}"
    echo "• 技術支援：ct@newsleopard.tw"
    echo "• 文件位置：docs/admin-handover-guide.md"
    echo "• Slack 頻道：#vpn-support"
    echo ""
}

# 清理暫存檔案
cleanup() {
    if [ -d "$TEMP_DIR" ]; then
        rm -rf "$TEMP_DIR"
        echo -e "${GREEN}✅ 已清理暫存檔案${NC}"
    fi
}

# 主要執行流程
main() {
    cd "$PROJECT_ROOT"

    check_dependencies
    check_aws_configuration
    decrypt_handover_package
    restore_files
    verify_certificates
    test_system_connectivity
    show_system_summary

    # 清理
    cleanup

    echo -e "${GREEN}✨ 管理員交接匯入完成！${NC}"
}

# 設定陷阱來清理暫存檔案
trap cleanup EXIT

# 執行主程式
main "$@"