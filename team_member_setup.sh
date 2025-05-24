#!/bin/bash

# AWS Client VPN 團隊成員設定腳本 for macOS
# 用途：允許團隊成員連接到已存在的 AWS Client VPN 端點
# 版本：1.0

# 顏色設定
GREEN=\'\\\\033[0;32m\'
BLUE=\'\\\\033[0;34m\'
RED=\'\\\\033[0;31m\'
YELLOW=\'\\\\033[1;33m\'
CYAN=\'\\\\033[0;36m\'
NC=\'\\\\033[0m\' # No Color

# 全域變數
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
USER_CONFIG_FILE="$SCRIPT_DIR/.user_vpn_config"
LOG_FILE="$SCRIPT_DIR/user_vpn_setup.log"

# 載入核心函式庫
source "$SCRIPT_DIR/lib/core_functions.sh"

# 阻止腳本在出錯時繼續執行
set -e

# 記錄函數
log_message() {
    echo "$(date \'+%Y-%m-%d %H:%M:%S\'): $1" >> "$LOG_FILE"
}

# 顯示歡迎訊息
show_welcome() {
    clear
    echo -e "${CYAN}========================================================${NC}"
    echo -e "${CYAN}          AWS Client VPN 團隊成員設定工具             ${NC}"
    echo -e "${CYAN}========================================================${NC}"
    echo -e ""
    echo -e "${BLUE}此工具將幫助您設定 AWS Client VPN 連接${NC}"
    echo -e "${BLUE}以便安全連接到生產環境進行除錯${NC}"
    echo -e ""
    echo -e "${YELLOW}請確保您已從管理員那裡獲得：${NC}"
    echo -e "  - VPN 端點 ID"
    echo -e "  - CA 證書文件 (ca.crt)"
    echo -e "  - AWS 帳戶訪問權限"
    echo -e ""
    echo -e "${CYAN}========================================================${NC}"
    echo -e ""
    read -p "按任意鍵開始設定... " -n 1
}

# 檢查必要工具
check_prerequisites() {
    echo -e "\\\\n${YELLOW}[1/6] 檢查必要工具...${NC}"
    
    local tools=("brew" "aws" "jq" "openssl")
    local missing_tools=()
    
    for tool in "${tools[@]}"; do
        if ! command -v "$tool" &> /dev/null; then
            missing_tools+=("$tool")
        else
            echo -e "${GREEN}✓ $tool 已安裝${NC}"
        fi
    done
    
    if [ ${#missing_tools[@]} -gt 0 ]; then
        echo -e "${RED}缺少必要工具: ${missing_tools[*]}${NC}"
        echo -e "${YELLOW}正在安裝缺少的工具...${NC}"
        
        # 安裝 Homebrew
        if [[ " ${missing_tools[*]} " =~ " brew " ]]; then
            echo -e "${BLUE}安裝 Homebrew...${NC}"
            /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install.sh)"
        fi
        
        # 安裝其他工具
        for tool in "${missing_tools[@]}"; do
            if [[ "$tool" != "brew" ]]; then
                echo -e "${BLUE}安裝 $tool...${NC}"
                case "$tool" in
                    "aws")
                        brew install awscli
                        ;;
                    "jq")
                        brew install jq
                        ;;
                    "openssl")
                        echo -e "${GREEN}OpenSSL 通常已預安裝在 macOS${NC}"
                        ;;
                esac
            fi
        done
    fi
    
    echo -e "${GREEN}所有必要工具已準備就緒！${NC}"
    log_message "必要工具檢查完成"
}

# 設定 AWS 配置
setup_aws_config() {
    echo -e "\\\\n${YELLOW}[2/6] 設定 AWS 配置...${NC}"
    
    if [ ! -f ~/.aws/credentials ] || [ ! -f ~/.aws/config ]; then
        echo -e "${YELLOW}請提供您的 AWS 帳戶資訊：${NC}"
        
        read -p "請輸入 AWS Access Key ID: " aws_access_key
        read -s -p "請輸入 AWS Secret Access Key: " aws_secret_key
        echo
        read -p "請輸入 AWS 區域 (與 VPN 端點相同的區域): " aws_region
        
        # 創建配置目錄和文件
        mkdir -p ~/.aws
        
        # 寫入認證
        cat > ~/.aws/credentials << EOF
[default]
aws_access_key_id = $aws_access_key
aws_secret_access_key = $aws_secret_key
EOF
        
        # 寫入配置
        cat > ~/.aws/config << EOF
[default]
region = $aws_region
output = json
EOF
        
        echo -e "${GREEN}AWS 配置已完成！${NC}"
    else
        echo -e "${GREEN}✓ AWS 已配置${NC}"
        aws_region=$(aws configure get region)
    fi
    
    # 測試 AWS 連接
    echo -e "${BLUE}測試 AWS 連接...${NC}"
    aws sts get-caller-identity > /dev/null
    echo -e "${GREEN}✓ AWS 連接測試成功${NC}"
    
    # 獲取 VPN 端點資訊
    echo -e "\\\\n${YELLOW}請向管理員獲取以下資訊：${NC}"
    read -p "請輸入 Client VPN 端點 ID: " endpoint_id
    
    # 驗證端點 ID
    echo -e "${BLUE}驗證 VPN 端點...${NC}"
    endpoint_check=$(aws ec2 describe-client-vpn-endpoints --client-vpn-endpoint-ids "$endpoint_id" --region "$aws_region" 2>/dev/null || echo "not_found")
    
    if [[ "$endpoint_check" == "not_found" ]]; then
        echo -e "${RED}無法找到指定的 VPN 端點。請確認 ID 是否正確，以及您是否有權限訪問。${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}✓ VPN 端點驗證成功${NC}"
    
    # 保存配置
    cat > "$USER_CONFIG_FILE" << EOF
AWS_REGION=$aws_region
ENDPOINT_ID=$endpoint_id
USER_NAME=""
CLIENT_CERT_ARN=""
EOF
    
    log_message "AWS 配置已完成，端點 ID: $endpoint_id"
}

# 設定用戶資訊
setup_user_info() {
    echo -e "\\\\n${YELLOW}[3/6] 設定用戶資訊...${NC}"
    
    # 獲取用戶名
    read -p "請輸入您的用戶名或姓名 (僅使用英文字母和數字，不含空格): " username
    username=$(echo "$username" | tr -cd \'[:alnum:]\')
    
    if [ -z "$username" ]; then
        echo -e "${RED}用戶名不能為空${NC}"
        exit 1
    fi
    
    # 確認用戶名
    echo -e "${BLUE}您的用戶名: $username${NC}"
    read -p "確認使用此用戶名？(y/n): " confirm
    
    if [[ "$confirm" != "y" ]]; then
        echo -e "${YELLOW}請重新執行腳本並設定正確的用戶名${NC}"
        exit 0
    fi
    
    # 更新配置文件
    sed -i \'\' "s/USER_NAME=\\\"\\\"/USER_NAME=\\\"$username\\\"/" "$USER_CONFIG_FILE"
    
    echo -e "${GREEN}用戶資訊設定完成！${NC}"
    log_message "用戶資訊已設定: $username"
}

# 生成個人客戶端證書
generate_client_certificate() {
    echo -e "\\\\n${YELLOW}[4/6] 生成個人 VPN 客戶端證書...${NC}"
    
    source "$USER_CONFIG_FILE"
    
    # 檢查 CA 證書
    echo -e "${YELLOW}檢查 CA 證書文件...${NC}"
    
    ca_cert_path=""
    
    # 檢查當前目錄
    if [ -f "$SCRIPT_DIR/ca.crt" ]; then
        ca_cert_path="$SCRIPT_DIR/ca.crt"
    elif [ -f "$SCRIPT_DIR/certificates/ca.crt" ]; then
        ca_cert_path="$SCRIPT_DIR/certificates/ca.crt"
    else
        echo -e "${YELLOW}未找到 CA 證書文件。${NC}"
        read -p "請輸入 CA 證書文件的完整路徑: " ca_cert_path
        
        if [ ! -f "$ca_cert_path" ]; then
            echo -e "${RED}無法找到 CA 證書文件: $ca_cert_path${NC}"
            exit 1
        fi
    fi
    
    echo -e "${GREEN}✓ 找到 CA 證書文件: $ca_cert_path${NC}"
    
    # 檢查 CA 私鑰
    ca_key_path=""
    ca_dir=$(dirname "$ca_cert_path")
    
    if [ -f "$ca_dir/ca.key" ]; then
        ca_key_path="$ca_dir/ca.key"
    else
        echo -e "${YELLOW}未找到 CA 私鑰文件。${NC}"
        echo -e "${YELLOW}如果您沒有 CA 私鑰，請聯繫管理員生成您的證書。${NC}"
        read -p "請輸入 CA 私鑰文件的完整路徑 (或按 Enter 跳過自動生成): " ca_key_path
        
        if [ ! -z "$ca_key_path" ] && [ ! -f "$ca_key_path" ]; then
            echo -e "${RED}無法找到 CA 私鑰文件: $ca_key_path${NC}"
            exit 1
        fi
    fi
    
    # 創建證書目錄
    cert_dir="$SCRIPT_DIR/user-certificates"
    mkdir -p "$cert_dir"
    cd "$cert_dir"
    
    # 複製 CA 證書
    cp "$ca_cert_path" ./ca.crt
    
    if [ ! -z "$ca_key_path" ]; then
        # 有 CA 私鑰，可以自動生成證書
        echo -e "${BLUE}自動生成客戶端證書...${NC}"
        
        # 產生使用者私鑰和 CSR
        if [ -f "${USER_NAME}.key" ] || [ -f "${USER_NAME}.csr" ]; then
            read -p "金鑰檔案 ${USER_NAME}.key 或 ${USER_NAME}.csr 已存在。是否覆蓋? (y/n): " overwrite_key
            if [[ "$overwrite_key" == "y" ]]; then
                rm -f "${USER_NAME}.key" "${USER_NAME}.csr"
            else
                echo -e "${YELLOW}保留現有金鑰檔案。如果您想重新產生，請先刪除它們。${NC}"
                # 如果使用者選擇不覆蓋，我們需要確保現有的 .key 檔案權限正確
                if [ -f "${USER_NAME}.key" ]; then
                    chmod 600 "${USER_NAME}.key"
                    chown "$(whoami)" "${USER_NAME}.key"
                fi
                return 0 # 假設如果保留，則不需要後續簽署等步驟，或者調用者會處理
            fi
        fi
        
        echo -e "${BLUE}正在為使用者 $USER_NAME 產生私鑰和證書簽署請求 (CSR)...${NC}"
        openssl genrsa -out "${USER_NAME}.key" 2048
        chmod 600 "${USER_NAME}.key"
        chown "$(whoami)" "${USER_NAME}.key"
        
        # 提示使用者輸入 CSR 的詳細資訊
        openssl req -new -key "${USER_NAME}.key" -out "${USER_NAME}.csr" \\
          -subj "/CN=${USER_NAME}/O=Client/C=TW"
        
        # 簽署證書
        openssl x509 -req -in "${USER_NAME}.csr" -CA ./ca.crt -CAkey "$ca_key_path" \\
          -CAcreateserial -out "${USER_NAME}.crt" -days 365
        
        # 清理
        rm "${USER_NAME}.csr"
        
        echo -e "${GREEN}✓ 客戶端證書生成完成${NC}"
    else
        # 沒有 CA 私鑰，需要手動處理
        echo -e "${YELLOW}無法自動生成證書。${NC}"
        echo -e "${YELLOW}請聯繫管理員為您生成客戶端證書，或提供以下資訊：${NC}"
        echo -e "  用戶名: $USER_NAME"
        echo -e "  證書請求: 需要為此用戶生成客戶端證書"
        
        echo -e "\\\\n${BLUE}如果您已有客戶端證書，請將其放在以下位置：${NC}"
        echo -e "  證書文件: $cert_dir/${USER_NAME}.crt"
        echo -e "  私鑰文件: $cert_dir/${USER_NAME}.key"
        
        read -p "證書文件已準備好？(y/n): " cert_ready
        
        if [[ "$cert_ready" != "y" ]]; then
            echo -e "${YELLOW}請準備好證書文件後重新執行腳本${NC}"
            exit 0
        fi
        
        # 檢查證書文件是否存在
        if [ ! -f "$cert_dir/${USER_NAME}.crt" ] || [ ! -f "$cert_dir/${USER_NAME}.key" ]; then
            echo -e "${RED}找不到證書文件。請確認文件位置正確。${NC}"
            exit 1
        fi
    fi
    
    log_message "客戶端證書已準備完成"
}

# 導入證書到 ACM
import_certificate() {
    echo -e "\\\\n${YELLOW}[5/6] 導入證書到 AWS Certificate Manager...${NC}"
    
    source "$USER_CONFIG_FILE"
    cert_dir="$SCRIPT_DIR/user-certificates"
    
    # 檢查證書文件
    if [ ! -f "$cert_dir/${USER_NAME}.crt" ] || [ ! -f "$cert_dir/${USER_NAME}.key" ] || [ ! -f "$cert_dir/ca.crt" ]; then
        echo -e "${RED}證書文件不完整。請確認以下文件存在：${NC}"
        echo -e "  - $cert_dir/${USER_NAME}.crt"
        echo -e "  - $cert_dir/${USER_NAME}.key"
        echo -e "  - $cert_dir/ca.crt"
        exit 1
    fi
    
    # 導入客戶端證書
    echo -e "${BLUE}導入客戶端證書到 ACM...${NC}"
    client_cert=$(aws acm import-certificate \\
      --certificate "fileb://$cert_dir/${USER_NAME}.crt" \\
      --private-key "fileb://$cert_dir/${USER_NAME}.key" \\
      --certificate-chain "fileb://$cert_dir/ca.crt" \\
      --region "$AWS_REGION" \\
      --tags Key=Name,Value="VPN-Client-${USER_NAME}" Key=Purpose,Value="ClientVPN" Key=User,Value="$USER_NAME")
    
    client_cert_arn=$(echo "$client_cert" | jq -r \'.CertificateArn\')
    
    echo -e "${GREEN}✓ 證書導入完成${NC}"
    echo -e "證書 ARN: ${BLUE}$client_cert_arn${NC}"
    
    # 更新配置文件
    sed -i \'\' "s/CLIENT_CERT_ARN=\\\"\\\"/CLIENT_CERT_ARN=\\\"$client_cert_arn\\\"/" "$USER_CONFIG_FILE"
    
    log_message "證書已導入到 ACM: $client_cert_arn"
}

# 設置 VPN 客戶端
setup_vpn_client() {
    echo -e "\\\\n${YELLOW}[6/6] 設置 VPN 客戶端...${NC}"
    
    source "$USER_CONFIG_FILE"
    cert_dir="$SCRIPT_DIR/user-certificates"
    
    # 下載 VPN 配置
    echo -e "${BLUE}下載 VPN 配置文件...${NC}"
    config_dir="$SCRIPT_DIR/vpn-config"
    mkdir -p "$config_dir"
    
    aws ec2 export-client-vpn-client-configuration \\
      --client-vpn-endpoint-id "$ENDPOINT_ID" \\
      --region "$AWS_REGION" \\
      --output text > "$config_dir/client-config-base.ovpn"
    
    # 創建個人配置文件
    echo -e "${BLUE}建立個人配置文件...${NC}"
    cp "$config_dir/client-config-base.ovpn" "$config_dir/${USER_NAME}-config.ovpn"
    
    # 添加配置選項
    echo "reneg-sec 0" >> "$config_dir/${USER_NAME}-config.ovpn"
    
    # 添加客戶端證書和密鑰
    echo "<cert>" >> "$config_dir/${USER_NAME}-config.ovpn"
    cat "$cert_dir/${USER_NAME}.crt" >> "$config_dir/${USER_NAME}-config.ovpn"
    echo "</cert>" >> "$config_dir/${USER_NAME}-config.ovpn"
    
    echo "<key>" >> "$config_dir/${USER_NAME}-config.ovpn"
    cat "$cert_dir/${USER_NAME}.key" >> "$config_dir/${USER_NAME}-config.ovpn"
    echo "</key>" >> "$config_dir/${USER_NAME}-config.ovpn"
    
    echo -e "${GREEN}✓ 個人配置文件已建立${NC}"
    
    # 下載並安裝 AWS VPN 客戶端
    echo -e "${BLUE}設置 AWS VPN 客戶端...${NC}"
    
    # 檢查是否已安裝
    if [ ! -d "/Applications/AWS VPN Client.app" ]; then
        echo -e "${BLUE}下載 AWS VPN 客戶端...${NC}"
        vpn_client_url="https://d20adtppz83p9s.cloudfront.net/OSX/latest/AWS_VPN_Client.pkg"
        curl -L -o ~/Downloads/AWS_VPN_Client.pkg "$vpn_client_url"
        
        echo -e "${BLUE}安裝 AWS VPN 客戶端...${NC}"
        sudo installer -pkg ~/Downloads/AWS_VPN_Client.pkg -target /
        
        echo -e "${GREEN}✓ AWS VPN 客戶端已安裝${NC}"
    else
        echo -e "${GREEN}✓ AWS VPN 客戶端已存在${NC}"
    fi
    
    echo -e "${GREEN}VPN 客戶端設置完成！${NC}"
    echo -e "您的配置文件: ${BLUE}$config_dir/${USER_NAME}-config.ovpn${NC}"
    
    log_message "VPN 客戶端設置完成"
}

# 顯示連接指示
show_connection_instructions() {
    source "$USER_CONFIG_FILE"
    
    echo -e "\\\\n${GREEN}=============================================${NC}"
    echo -e "${GREEN}       AWS Client VPN 設置完成！      ${NC}"
    echo -e "${GREEN}=============================================${NC}"
    echo -e ""
    echo -e "${CYAN}連接說明：${NC}"
    echo -e "${BLUE}1.${NC} 開啟 AWS VPN 客戶端 (在應用程式文件夾中)"
    echo -e "${BLUE}2.${NC} 點擊「檔案」>「管理設定檔」"
    echo -e "${BLUE}3.${NC} 點擊「添加設定檔」"
    echo -e "${BLUE}4.${NC} 選擇您的配置文件：${YELLOW}$SCRIPT_DIR/vpn-config/${USER_NAME}-config.ovpn${NC}"
    echo -e "${BLUE}5.${NC} 輸入設定檔名稱：${YELLOW}Production Debug - ${USER_NAME}${NC}"
    echo -e "${BLUE}6.${NC} 點擊「添加設定檔」完成添加"
    echo -e "${BLUE}7.${NC} 選擇剛添加的設定檔並點擊「連接」"
    echo -e ""
    echo -e "${CYAN}測試連接：${NC}"
    echo -e "連接成功後，嘗試 ping 生產環境中的某個私有 IP："
    echo -e "  ${YELLOW}ping 10.0.x.x${NC}  # 請向管理員詢問測試 IP"
    echo -e ""
    echo -e "${CYAN}故障排除：${NC}"
    echo -e "如果連接失敗，請："
    echo -e "${BLUE}1.${NC} 檢查您的網路連接"
    echo -e "${BLUE}2.${NC} 確認配置文件路徑正確"
    echo -e "${BLUE}3.${NC} 聯繫管理員檢查授權設置"
    echo -e "${BLUE}4.${NC} 查看 AWS VPN 客戶端的連接日誌"
    echo -e ""
    echo -e "${CYAN}重要提醒：${NC}"
    echo -e "${RED}•${NC} 僅在需要時連接 VPN"
    echo -e "${RED}•${NC} 使用完畢後請立即斷開連接"
    echo -e "${RED}•${NC} 請勿分享您的配置文件或證書"
    echo -e "${RED}•${NC} 如有問題請聯繫 IT 管理員"
    echo -e ""
    echo -e "${GREEN}設置完成！祝您除錯順利！${NC}"
}

# 清理和測試函數
test_connection() {
    echo -e "\\\\n${BLUE}是否要進行連接測試？(需要先手動連接 VPN) (y/n): ${NC}"
    read test_choice
    
    if [[ "$test_choice" == "y" ]]; then
        echo -e "${BLUE}請先使用 AWS VPN 客戶端連接，然後按任意鍵繼續測試...${NC}"
        read -n 1
        
        echo -e "${BLUE}測試 VPN 連接...${NC}"
        
        # 檢查 VPN 介面
        vpn_interface=$(ifconfig | grep -E "utun|tun" | head -1 | cut -d: -f1)
        
        if [ ! -z "$vpn_interface" ]; then
            echo -e "${GREEN}✓ 檢測到 VPN 介面: $vpn_interface${NC}"
            
            # 嘗試 ping VPN 閘道
            vpn_gateway=$(route -n get default | grep "gateway" | awk \'{print $2}\')
            if [ ! -z "$vpn_gateway" ]; then
                echo -e "${BLUE}測試連接到閘道 $vpn_gateway...${NC}"
                if ping -c 3 "$vpn_gateway" > /dev/null 2>&1; then
                    echo -e "${GREEN}✓ VPN 連接測試成功${NC}"
                else
                    echo -e "${YELLOW}⚠ 無法 ping 閘道，但這可能是正常的${NC}"
                fi
            fi
        else
            echo -e "${YELLOW}⚠ 未檢測到 VPN 介面，請確認已連接${NC}"
        fi
    fi
}

# 主函數
main() {
    # 顯示歡迎訊息
    show_welcome
    
    # 執行設置步驟
    check_prerequisites
    setup_aws_config
    setup_user_info
    generate_client_certificate
    import_certificate
    setup_vpn_client
    
    # 顯示連接指示
    show_connection_instructions
    
    # 可選的連接測試
    test_connection
    
    log_message "團隊成員 VPN 設置完成"
}

# 記錄腳本啟動
log_message "團隊成員 VPN 設置腳本已啟動"

# 執行主程序
main