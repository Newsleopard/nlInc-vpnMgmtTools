#!/bin/bash

# AWS Client VPN 團隊成員設定腳本 for macOS
# 用途：允許團隊成員連接到已存在的 AWS Client VPN 端點
# 版本：1.0

# 顏色設定
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# 全域變數
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
USER_CONFIG_FILE="$SCRIPT_DIR/.user_vpn_config"
LOG_FILE="$SCRIPT_DIR/user_vpn_setup.log"

# 載入核心函式庫
source "$SCRIPT_DIR/lib/core_functions.sh"

# 執行兼容性檢查
check_macos_compatibility

# 阻止腳本在出錯時繼續執行
set -e

# 記錄函數 (團隊設置專用)
log_team_setup_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S'): $1" >> "$LOG_FILE"
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

# 檢查必要工具（重新命名避免衝突）
check_team_prerequisites() {
    echo -e "\\n${YELLOW}[1/6] 檢查必要工具...${NC}"
    
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
    log_team_setup_message "必要工具檢查完成"
}

# 設定 AWS 配置
setup_aws_config() {
    echo -e "\\n${YELLOW}[2/6] 設定 AWS 配置...${NC}"
    
    # 檢查現有配置
    local existing_config=false
    local use_existing_config=false
    local aws_region=""
    
    if [ -f ~/.aws/credentials ] && [ -f ~/.aws/config ]; then
        existing_config=true
        echo -e "${BLUE}檢測到現有的 AWS 配置檔案${NC}"
        
        # 檢查是否可以使用現有配置
        if aws sts get-caller-identity > /dev/null 2>&1; then
            echo -e "${GREEN}✓ 現有 AWS 配置可正常使用${NC}"
            local current_region
            current_region=$(aws configure get region 2>/dev/null)
            if [ -n "$current_region" ]; then
                echo -e "${BLUE}當前 AWS 區域: $current_region${NC}"
                local use_existing
                if ! read_secure_input "是否使用現有的 AWS 配置？(y/n): " use_existing "validate_yes_no"; then
                    handle_error "確認輸入驗證失敗"
                    return 1
                fi
                
                if [[ "$use_existing" == "y" || "$use_existing" == "Y" ]]; then
                    use_existing_config=true
                    aws_region="$current_region"
                fi
            fi
        else
            echo -e "${YELLOW}⚠ 現有 AWS 配置無法正常使用，需要重新設定${NC}"
        fi
    fi
    
    if [ "$use_existing_config" = false ]; then
        echo -e "${YELLOW}請提供您的 AWS 帳戶資訊：${NC}"
        
        local aws_access_key
        local aws_secret_key
        
        if ! read_secure_input "請輸入 AWS Access Key ID: " aws_access_key "validate_aws_access_key_id"; then
            handle_error "AWS Access Key ID 驗證失敗"
            return 1
        fi
        
        if ! read_secure_hidden_input "請輸入 AWS Secret Access Key: " aws_secret_key "validate_aws_secret_access_key"; then
            handle_error "AWS Secret Access Key 驗證失敗"
            return 1
        fi
        
        if ! read_secure_input "請輸入 AWS 區域 (與 VPN 端點相同的區域): " aws_region "validate_aws_region"; then
            handle_error "AWS 區域驗證失敗"
            return 1
        fi
        
        # 備份現有配置檔案
        if [ "$existing_config" = true ]; then
            local backup_timestamp
            backup_timestamp=$(date +%Y%m%d_%H%M%S)
            echo -e "${BLUE}備份現有 AWS 配置檔案...${NC}"
            
            if [ -f ~/.aws/credentials ]; then
                cp ~/.aws/credentials ~/.aws/credentials.backup_$backup_timestamp
                echo -e "${GREEN}✓ 已備份 ~/.aws/credentials 到 ~/.aws/credentials.backup_$backup_timestamp${NC}"
            fi
            
            if [ -f ~/.aws/config ]; then
                cp ~/.aws/config ~/.aws/config.backup_$backup_timestamp
                echo -e "${GREEN}✓ 已備份 ~/.aws/config 到 ~/.aws/config.backup_$backup_timestamp${NC}"
            fi
        fi
        
        # 創建配置目錄
        mkdir -p ~/.aws
        
        # 使用 AWS CLI 命令安全地設定配置，這會保留其他設定檔
        echo -e "${BLUE}設定 AWS CLI 配置...${NC}"
        aws configure set aws_access_key_id "$aws_access_key"
        aws configure set aws_secret_access_key "$aws_secret_key"
        aws configure set default.region "$aws_region"
        aws configure set default.output json
        
        echo -e "${GREEN}AWS 配置已完成！${NC}"
    else
        echo -e "${GREEN}✓ 使用現有 AWS 配置${NC}"
    fi
    
    # 測試 AWS 連接
    echo -e "${BLUE}測試 AWS 連接...${NC}"
    if ! aws sts get-caller-identity > /dev/null; then
        handle_error "AWS 連接測試失敗"
        return 1
    fi
    echo -e "${GREEN}✓ AWS 連接測試成功${NC}"
    
    # 獲取 VPN 端點資訊
    echo -e "\\n${YELLOW}請向管理員獲取以下資訊：${NC}"
    local endpoint_id
    if ! read_secure_input "請輸入 Client VPN 端點 ID: " endpoint_id "validate_endpoint_id"; then
        handle_error "VPN 端點 ID 驗證失敗"
        return 1
    fi
    
    # 驗證端點 ID
    echo -e "${BLUE}驗證 VPN 端點...${NC}"
    local endpoint_check
    endpoint_check=$(aws ec2 describe-client-vpn-endpoints --client-vpn-endpoint-ids "$endpoint_id" --region "$aws_region" 2>/dev/null || echo "not_found")
    
    if [[ "$endpoint_check" == "not_found" ]]; then
        echo -e "${RED}無法找到指定的 VPN 端點。請確認 ID 是否正確，以及您是否有權限訪問。${NC}"
        return 1
    fi
    
    echo -e "${GREEN}✓ VPN 端點驗證成功${NC}"
    
    # 保存配置
    cat > "$USER_CONFIG_FILE" << EOF
AWS_REGION=$aws_region
ENDPOINT_ID=$endpoint_id
USERNAME=""
CLIENT_CERT_ARN=""
EOF
    
    # 設置配置文件權限
    chmod 600 "$USER_CONFIG_FILE"
    
    log_team_setup_message "AWS 配置已完成，端點 ID: $endpoint_id"
}

# 設定用戶資訊
setup_user_info() {
    echo -e "\\n${YELLOW}[3/6] 設定用戶資訊...${NC}"
    
    # 使用安全輸入驗證獲取用戶名
    local username
    if ! read_secure_input "請輸入您的用戶名或姓名: " username "validate_username"; then
        handle_error "用戶名驗證失敗"
        return 1
    fi
    
    # 確認用戶名
    echo -e "${BLUE}您的用戶名: $username${NC}"
    local confirm
    if ! read_secure_input "確認使用此用戶名？(y/n): " confirm "validate_yes_no"; then
        handle_error "確認輸入驗證失敗"
        return 1
    fi
    
    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        echo -e "${YELLOW}請重新執行腳本並設定正確的用戶名${NC}"
        exit 0
    fi
    
    # 更新配置文件
    update_config "$USER_CONFIG_FILE" "USERNAME" "$username"
    
    echo -e "${GREEN}用戶資訊設定完成！${NC}"
    log_team_setup_message "用戶資訊已設定: $username"
}

# 生成個人客戶端證書
generate_client_certificate() {
    echo -e "\\n${YELLOW}[4/6] 生成個人 VPN 客戶端證書...${NC}"
    
    # 載入配置
    source "$USER_CONFIG_FILE"
    
    # 檢查 CA 證書
    echo -e "${YELLOW}檢查 CA 證書文件...${NC}"
    
    local ca_cert_path=""
    
    # 檢查當前目錄
    if [ -f "$SCRIPT_DIR/ca.crt" ]; then
        ca_cert_path="$SCRIPT_DIR/ca.crt"
    elif [ -f "$SCRIPT_DIR/certificates/ca.crt" ]; then
        ca_cert_path="$SCRIPT_DIR/certificates/ca.crt"
    else
        echo -e "${YELLOW}未找到 CA 證書文件。${NC}"
        if ! read_secure_input "請輸入 CA 證書文件的完整路徑: " ca_cert_path "validate_file_path"; then
            handle_error "CA 證書文件路徑驗證失敗"
            return 1
        fi
    fi
    
    echo -e "${GREEN}✓ 找到 CA 證書文件: $ca_cert_path${NC}"
    
    # 檢查 CA 私鑰
    local ca_key_path=""
    local ca_dir
    ca_dir=$(dirname "$ca_cert_path")
    
    if [ -f "$ca_dir/ca.key" ]; then
        ca_key_path="$ca_dir/ca.key"
    else
        echo -e "${YELLOW}未找到 CA 私鑰文件。${NC}"
        echo -e "${YELLOW}如果您沒有 CA 私鑰，請聯繫管理員生成您的證書。${NC}"
        if ! read_secure_input "請輸入 CA 私鑰文件的完整路徑 (或按 Enter 跳過自動生成): " ca_key_path "validate_file_path_allow_empty"; then
            handle_error "CA 私鑰文件路徑驗證失敗"
            return 1
        fi
    fi
    
    # 創建證書目錄
    local cert_dir="$SCRIPT_DIR/user-certificates"
    mkdir -p "$cert_dir"
    chmod 700 "$cert_dir"
    cd "$cert_dir"
    
    # 複製 CA 證書
    cp "$ca_cert_path" ./ca.crt
    
    if [ ! -z "$ca_key_path" ]; then
        # 有 CA 私鑰，可以自動生成證書
        echo -e "${BLUE}自動生成客戶端證書...${NC}"
        
        # 產生使用者私鑰和 CSR
        if [ -f "${USERNAME}.key" ] || [ -f "${USERNAME}.csr" ]; then
            local overwrite_key
            if ! read_secure_input "金鑰檔案 ${USERNAME}.key 或 ${USERNAME}.csr 已存在。是否覆蓋? (y/n): " overwrite_key "validate_yes_no"; then
                handle_error "覆蓋確認驗證失敗"
                return 1
            fi
            if [[ "$overwrite_key" == "y" || "$overwrite_key" == "Y" ]]; then
                rm -f "${USERNAME}.key" "${USERNAME}.csr"
            else
                echo -e "${YELLOW}保留現有金鑰檔案。如果您想重新產生，請先刪除它們。${NC}"
                # 確保現有的 .key 檔案權限正確
                if [ -f "${USERNAME}.key" ]; then
                    chmod 600 "${USERNAME}.key"
                    chown "$(whoami)" "${USERNAME}.key"
                fi
                return 0
            fi
        fi
        
        echo -e "${BLUE}正在為使用者 $USERNAME 產生私鑰和證書簽署請求 (CSR)...${NC}"
        openssl genrsa -out "${USERNAME}.key" 2048
        chmod 600 "${USERNAME}.key"
        chown "$(whoami)" "${USERNAME}.key"
        
        # 生成 CSR
        openssl req -new -key "${USERNAME}.key" -out "${USERNAME}.csr" \
          -subj "/CN=${USERNAME}/O=Client/C=TW"
        
        # 簽署證書
        openssl x509 -req -in "${USERNAME}.csr" -CA ./ca.crt -CAkey "$ca_key_path" \
          -CAcreateserial -out "${USERNAME}.crt" -days 365
        
        # 設置證書文件權限
        chmod 600 "${USERNAME}.crt"
        
        # 清理
        rm "${USERNAME}.csr"
        
        echo -e "${GREEN}✓ 客戶端證書生成完成${NC}"
    else
        # 沒有 CA 私鑰，需要手動處理
        echo -e "${YELLOW}無法自動生成證書。${NC}"
        echo -e "${YELLOW}請聯繫管理員為您生成客戶端證書，或提供以下資訊：${NC}"
        echo -e "  用戶名: $USERNAME"
        echo -e "  證書請求: 需要為此用戶生成客戶端證書"
        
        echo -e "\\n${BLUE}如果您已有客戶端證書，請將其放在以下位置：${NC}"
        echo -e "  證書文件: $cert_dir/${USERNAME}.crt"
        echo -e "  私鑰文件: $cert_dir/${USERNAME}.key"
        
        local cert_ready
        if ! read_secure_input "證書文件已準備好？(y/n): " cert_ready "validate_yes_no"; then
            handle_error "證書準備確認驗證失敗"
            return 1
        fi
        
        if [[ "$cert_ready" != "y" && "$cert_ready" != "Y" ]]; then
            echo -e "${YELLOW}請準備好證書文件後重新執行腳本${NC}"
            exit 0
        fi
        
        # 檢查證書文件是否存在
        if [ ! -f "$cert_dir/${USERNAME}.crt" ] || [ ! -f "$cert_dir/${USERNAME}.key" ]; then
            echo -e "${RED}找不到證書文件。請確認文件位置正確。${NC}"
            return 1
        fi
        
        # 設置文件權限
        chmod 600 "$cert_dir/${USERNAME}.crt"
        chmod 600 "$cert_dir/${USERNAME}.key"
    fi
    
    log_team_setup_message "客戶端證書已準備完成"
}

# 導入證書到 ACM
import_certificate() {
    echo -e "\\n${YELLOW}[5/6] 導入證書到 AWS Certificate Manager...${NC}"
    
    # 載入配置
    source "$USER_CONFIG_FILE"
    local cert_dir="$SCRIPT_DIR/user-certificates"
    
    # 檢查證書文件
    if [ ! -f "$cert_dir/${USERNAME}.crt" ] || [ ! -f "$cert_dir/${USERNAME}.key" ] || [ ! -f "$cert_dir/ca.crt" ]; then
        echo -e "${RED}證書文件不完整。請確認以下文件存在：${NC}"
        echo -e "  - $cert_dir/${USERNAME}.crt"
        echo -e "  - $cert_dir/${USERNAME}.key"
        echo -e "  - $cert_dir/ca.crt"
        return 1
    fi
    
    # 導入客戶端證書
    echo -e "${BLUE}導入客戶端證書到 ACM...${NC}"
    local client_cert
    client_cert=$(aws acm import-certificate \
      --certificate "fileb://$cert_dir/${USERNAME}.crt" \
      --private-key "fileb://$cert_dir/${USERNAME}.key" \
      --certificate-chain "fileb://$cert_dir/ca.crt" \
      --region "$AWS_REGION" \
      --tags Key=Name,Value="VPN-Client-${USERNAME}" Key=Purpose,Value="ClientVPN" Key=User,Value="$USERNAME")
    
    local client_cert_arn
    if ! client_cert_arn=$(echo "$client_cert" | jq -r '.CertificateArn' 2>/dev/null); then
        # 備用解析方法：使用 grep 和 sed 提取證書 ARN
        client_cert_arn=$(echo "$client_cert" | grep -o '"CertificateArn":"arn:aws:acm:[^"]*"' | sed 's/"CertificateArn":"//g' | sed 's/"//g' | head -1)
    fi
    
    # 驗證解析結果
    if ! validate_json_parse_result "$client_cert_arn" "客戶端證書ARN" "validate_certificate_arn"; then
        handle_error "無法獲取客戶端證書 ARN"
        return 1
    fi
    
    echo -e "${GREEN}✓ 證書導入完成${NC}"
    echo -e "證書 ARN: ${BLUE}$client_cert_arn${NC}"
    
    # 更新配置文件
    update_config "$USER_CONFIG_FILE" "CLIENT_CERT_ARN" "$client_cert_arn"
    
    log_team_setup_message "證書已導入到 ACM: $client_cert_arn"
}

# 設置 VPN 客戶端
setup_vpn_client() {
    echo -e "\\n${YELLOW}[6/6] 設置 VPN 客戶端...${NC}"
    
    # 載入配置
    source "$USER_CONFIG_FILE"
    local cert_dir="$SCRIPT_DIR/user-certificates"
    
    # 下載 VPN 配置
    echo -e "${BLUE}下載 VPN 配置文件...${NC}"
    local config_dir="$SCRIPT_DIR/vpn-config"
    mkdir -p "$config_dir"
    chmod 700 "$config_dir"
    
    if ! aws ec2 export-client-vpn-client-configuration \
      --client-vpn-endpoint-id "$ENDPOINT_ID" \
      --region "$AWS_REGION" \
      --output text > "$config_dir/client-config-base.ovpn"; then
        handle_error "下載 VPN 配置失敗"
        return 1
    fi
    
    # 創建個人配置文件
    echo -e "${BLUE}建立個人配置文件...${NC}"
    cp "$config_dir/client-config-base.ovpn" "$config_dir/${USERNAME}-config.ovpn"
    
    # 添加配置選項
    echo "reneg-sec 0" >> "$config_dir/${USERNAME}-config.ovpn"
    
    # 添加客戶端證書和密鑰
    echo "<cert>" >> "$config_dir/${USERNAME}-config.ovpn"
    cat "$cert_dir/${USERNAME}.crt" >> "$config_dir/${USERNAME}-config.ovpn"
    echo "</cert>" >> "$config_dir/${USERNAME}-config.ovpn"
    
    echo "<key>" >> "$config_dir/${USERNAME}-config.ovpn"
    cat "$cert_dir/${USERNAME}.key" >> "$config_dir/${USERNAME}-config.ovpn"
    echo "</key>" >> "$config_dir/${USERNAME}-config.ovpn"
    
    # 設置配置文件權限
    chmod 600 "$config_dir/${USERNAME}-config.ovpn"
    
    echo -e "${GREEN}✓ 個人配置文件已建立${NC}"
    
    # 下載並安裝 AWS VPN 客戶端
    echo -e "${BLUE}設置 AWS VPN 客戶端...${NC}"
    
    # 檢查是否已安裝
    if [ ! -d "/Applications/AWS VPN Client.app" ]; then
        echo -e "${BLUE}下載 AWS VPN 客戶端...${NC}"
        local vpn_client_url="https://d20adtppz83p9s.cloudfront.net/OSX/latest/AWS_VPN_Client.pkg"
        if ! curl -L -o ~/Downloads/AWS_VPN_Client.pkg "$vpn_client_url"; then
            handle_error "下載 AWS VPN 客戶端失敗"
            return 1
        fi
        
        echo -e "${BLUE}安裝 AWS VPN 客戶端...${NC}"
        if ! sudo installer -pkg ~/Downloads/AWS_VPN_Client.pkg -target /; then
            handle_error "安裝 AWS VPN 客戶端失敗"
            return 1
        fi
        
        echo -e "${GREEN}✓ AWS VPN 客戶端已安裝${NC}"
    else
        echo -e "${GREEN}✓ AWS VPN 客戶端已存在${NC}"
    fi
    
    echo -e "${GREEN}VPN 客戶端設置完成！${NC}"
    echo -e "您的配置文件: ${BLUE}$config_dir/${USERNAME}-config.ovpn${NC}"
    
    log_team_setup_message "VPN 客戶端設置完成"
}

# 顯示連接指示
show_connection_instructions() {
    # 載入配置
    source "$USER_CONFIG_FILE"
    
    echo -e "\\n${GREEN}=============================================${NC}"
    echo -e "${GREEN}       AWS Client VPN 設置完成！      ${NC}"
    echo -e "${GREEN}=============================================${NC}"
    echo -e ""
    echo -e "${CYAN}連接說明：${NC}"
    echo -e "${BLUE}1.${NC} 開啟 AWS VPN 客戶端 (在應用程式文件夾中)"
    echo -e "${BLUE}2.${NC} 點擊「檔案」>「管理設定檔」"
    echo -e "${BLUE}3.${NC} 點擊「添加設定檔」"
    echo -e "${BLUE}4.${NC} 選擇您的配置文件：${YELLOW}$SCRIPT_DIR/vpn-config/${USERNAME}-config.ovpn${NC}"
    echo -e "${BLUE}5.${NC} 輸入設定檔名稱：${YELLOW}Production Debug - ${USERNAME}${NC}"
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
    echo -e "\\n${BLUE}是否要進行連接測試？(需要先手動連接 VPN) (y/n): ${NC}"
    local test_choice
    read test_choice
    
    if [[ "$test_choice" == "y" ]]; then
        echo -e "${BLUE}請先使用 AWS VPN 客戶端連接，然後按任意鍵繼續測試...${NC}"
        read -n 1
        
        echo -e "${BLUE}測試 VPN 連接...${NC}"
        
        # 檢查 VPN 介面
        local vpn_interface
        vpn_interface=$(ifconfig | grep -E "utun|tun" | head -1 | cut -d: -f1)
        
        if [ ! -z "$vpn_interface" ]; then
            echo -e "${GREEN}✓ 檢測到 VPN 介面: $vpn_interface${NC}"
            
            # 嘗試 ping VPN 閘道
            local vpn_gateway
            vpn_gateway=$(route -n get default | grep "gateway" | awk '{print $2}')
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
    check_team_prerequisites
    setup_aws_config
    setup_user_info
    generate_client_certificate
    import_certificate
    setup_vpn_client
    
    # 顯示連接指示
    show_connection_instructions
    
    # 可選的連接測試
    test_connection
    
    log_team_setup_message "團隊成員 VPN 設置完成"
}

# 記錄腳本啟動
log_team_setup_message "團隊成員 VPN 設置腳本已啟動"

# 執行主程序
main