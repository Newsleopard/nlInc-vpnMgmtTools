#!/bin/bash

# AWS Client VPN 團隊成員設定腳本 for macOS
# 用途：允許團隊成員連接到已存在的 AWS Client VPN 端點
# 版本：1.2 (環境感知版本)

# 全域變數
TEAM_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 載入輕量級環境核心庫 (團隊成員專用)
source "$TEAM_SCRIPT_DIR/lib/env_core.sh"

# 全域變數
SELECTED_AWS_PROFILE=""
TARGET_ENVIRONMENT=""
USER_CONFIG_FILE=""
LOG_FILE=""

# 載入核心函式庫
source "$TEAM_SCRIPT_DIR/lib/core_functions.sh"

# 執行兼容性檢查
check_macos_compatibility

# 阻止腳本在出錯時繼續執行
set -e

# 記錄函數 (團隊設置專用)
log_team_setup_message() {
    # 只有在 LOG_FILE 已設定且目錄存在時才記錄
    if [ -n "$LOG_FILE" ] && [ -n "$(dirname "$LOG_FILE")" ]; then
        # 確保日誌目錄存在
        mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null
        echo "$(date '+%Y-%m-%d %H:%M:%S'): $1" >> "$LOG_FILE" 2>/dev/null || true
    fi
}

# 顯示歡迎訊息
show_welcome() {
    clear
    show_team_env_header "AWS Client VPN 團隊成員設定工具"
    echo -e ""
    echo -e "${BLUE}此工具將幫助您設定 AWS Client VPN 連接${NC}"
    echo -e "${BLUE}以便安全連接到目標環境進行除錯${NC}"
    echo -e ""
    echo -e "${YELLOW}請確保您已從管理員那裡獲得：${NC}"
    echo -e "  - VPN 端點 ID 和 AWS 區域"
    echo -e "  - CA 證書文件 (ca.crt)"
    echo -e "  - 適當的 AWS 帳戶訪問權限"
    echo -e ""
    echo -e "${CYAN}========================================================${NC}"
    echo -e ""
    press_any_key_to_continue
}

# 檢查必要工具（跨平台版本）
check_team_prerequisites() {
    echo -e "\\n${YELLOW}[1/6] 檢查必要工具...${NC}"
    
    local tools=("aws" "jq" "openssl")
    local missing_tools=()
    local os_type=$(uname -s)
    
    # 根據作業系統添加包管理器
    case "$os_type" in
        "Darwin")
            tools+=("brew")
            ;;
        "Linux")
            # Linux 系統通常使用系統包管理器，不需要額外檢查
            ;;
        *)
            echo -e "${YELLOW}⚠ 檢測到非常見作業系統: $os_type${NC}"
            ;;
    esac
    
    for tool in "${tools[@]}"; do
        if ! command -v "$tool" &> /dev/null; then
            missing_tools+=("$tool")
        else
            echo -e "${GREEN}✓ $tool 已安裝${NC}"
        fi
    done
    
    if [ ${#missing_tools[@]} -gt 0 ]; then
        echo -e "${RED}缺少必要工具: ${missing_tools[*]}${NC}"
        echo -e "${YELLOW}正在嘗試安裝缺少的工具...${NC}"
        
        case "$os_type" in
            "Darwin")
                install_tools_macos "${missing_tools[@]}"
                ;;
            "Linux")
                install_tools_linux "${missing_tools[@]}"
                ;;
            *)
                echo -e "${RED}不支援的作業系統自動安裝。請手動安裝以下工具: ${missing_tools[*]}${NC}"
                return 1
                ;;
        esac
    fi
    
    echo -e "${GREEN}所有必要工具已準備就緒！${NC}"
    log_team_setup_message "必要工具檢查完成"
}

# macOS 工具安裝
install_tools_macos() {
    local tools=("$@")
    
    # 安裝 Homebrew
    if [[ " ${tools[*]} " =~ " brew " ]]; then
        echo -e "${BLUE}安裝 Homebrew...${NC}"
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install.sh)"
    fi
    
    # 安裝其他工具
    for tool in "${tools[@]}"; do
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
}

# Linux 工具安裝
install_tools_linux() {
    local tools=("$@")
    
    # 檢測 Linux 發行版
    if command -v apt-get &> /dev/null; then
        # Debian/Ubuntu
        sudo apt-get update
        for tool in "${tools[@]}"; do
            case "$tool" in
                "aws")
                    echo -e "${BLUE}安裝 AWS CLI...${NC}"
                    curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
                    unzip awscliv2.zip
                    sudo ./aws/install
                    rm -rf awscliv2.zip aws/
                    ;;
                "jq")
                    sudo apt-get install -y jq
                    ;;
                "openssl")
                    sudo apt-get install -y openssl
                    ;;
            esac
        done
    elif command -v yum &> /dev/null; then
        # RHEL/CentOS
        for tool in "${tools[@]}"; do
            case "$tool" in
                "aws")
                    echo -e "${BLUE}安裝 AWS CLI...${NC}"
                    curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
                    unzip awscliv2.zip
                    sudo ./aws/install
                    rm -rf awscliv2.zip aws/
                    ;;
                "jq")
                    sudo yum install -y jq
                    ;;
                "openssl")
                    sudo yum install -y openssl
                    ;;
            esac
        done
    else
        echo -e "${RED}無法檢測 Linux 包管理器。請手動安裝: ${tools[*]}${NC}"
        return 1
    fi
}

# 初始化環境和 AWS 配置
init_environment_and_aws() {
    echo -e "\\n${YELLOW}[1/6] 初始化環境和 AWS 配置...${NC}"
    
    # 使用新的環境初始化
    if ! init_team_member_environment "team_member_setup.sh" "$TEAM_SCRIPT_DIR"; then
        echo -e "${RED}環境初始化失敗${NC}"
        return 1
    fi
    
    # 驗證選中的 AWS profile
    if ! validate_aws_profile_config "$SELECTED_AWS_PROFILE"; then
        echo -e "${RED}AWS profile 驗證失敗${NC}"
        return 1
    fi
    
    # 獲取 AWS 區域 (如果未設定則要求輸入)
    local aws_region
    aws_region=$(aws configure get region --profile "$SELECTED_AWS_PROFILE" 2>/dev/null)
    
    if [ -f ~/.aws/credentials ] && [ -f ~/.aws/config ]; then
        existing_config=true
        echo -e "${BLUE}📋 檢測到現有的 AWS 配置檔案${NC}"
        echo -e "${BLUE}═══════════════════════════════════════${NC}"
        
        # 顯示配置檔案位置
        echo -e "配置檔案位置:"
        echo -e "  • ~/.aws/credentials"
        echo -e "  • ~/.aws/config"
        
        # 檢查是否可以使用選中的 profile 配置
        echo -e "\n${BLUE}正在驗證選中的 profile '$SELECTED_AWS_PROFILE' 配置...${NC}"
        if aws sts get-caller-identity --profile "$SELECTED_AWS_PROFILE" > /dev/null 2>&1; then
            echo -e "${GREEN}✅ 選中的 AWS profile '$SELECTED_AWS_PROFILE' 配置可正常使用${NC}"
            
            # 顯示當前配置詳細資訊
            local current_region current_output current_identity
            current_region=$(aws configure get region --profile "$SELECTED_AWS_PROFILE" 2>/dev/null || echo "")
            current_output=$(aws configure get output --profile "$SELECTED_AWS_PROFILE" 2>/dev/null || echo "")
            current_identity=$(aws sts get-caller-identity --profile "$SELECTED_AWS_PROFILE" 2>/dev/null || echo "")
            
            echo -e "\n${BLUE}📊 選中的 AWS profile '$SELECTED_AWS_PROFILE' 詳細資訊:${NC}"
            echo -e "═══════════════════════════════════════"
            
            if [ -n "$current_region" ]; then
                echo -e "AWS 區域: ${GREEN}$current_region${NC}"
            else
                echo -e "AWS 區域: ${YELLOW}未設定${NC}"
            fi
            
            if [ -n "$current_output" ]; then
                echo -e "輸出格式: $current_output"
            else
                echo -e "輸出格式: 預設"
            fi
            
            # 顯示當前身份資訊（如果可獲取）
            if [ -n "$current_identity" ]; then
                local account_id user_arn
                if command -v jq >/dev/null 2>&1; then
                    account_id=$(echo "$current_identity" | jq -r '.Account' 2>/dev/null || echo "無法解析")
                    user_arn=$(echo "$current_identity" | jq -r '.Arn' 2>/dev/null || echo "無法解析")
                else
                    account_id=$(echo "$current_identity" | grep -o '"Account":"[^"]*"' | cut -d'"' -f4 || echo "無法解析")
                    user_arn=$(echo "$current_identity" | grep -o '"Arn":"[^"]*"' | cut -d'"' -f4 || echo "無法解析")
                fi
                echo -e "AWS 帳號: $account_id"
                echo -e "使用者身份: $user_arn"
            fi
            
            echo -e "═══════════════════════════════════════"
            
            if [ -n "$current_region" ]; then
                echo -e "\n${YELLOW}💡 您有以下選擇:${NC}"
                echo -e "  ${GREEN}Y${NC} - 使用選中的 profile '$SELECTED_AWS_PROFILE' (推薦)"
                echo -e "      → 將使用上述顯示的 AWS profile 配置進行 VPN 設定"
                echo -e "      → 不會修改您現有的 AWS 配置檔案"
                echo -e ""
                echo -e "  ${YELLOW}N${NC} - 重新配置 AWS 帳號"
                echo -e "      → 將要求您輸入新的 AWS Access Key 和 Secret Key"
                echo -e "      → 會備份現有配置檔案後覆寫設定"
                echo -e "      → 適用於需要使用不同 AWS 帳號的情況"
                echo -e ""
                
                local use_existing
                if read_secure_input "請選擇 (y/n): " use_existing "validate_yes_no"; then
                    if [[ "$use_existing" =~ ^[Yy]$ ]]; then
                        use_existing_config=true
                        aws_region="$current_region"
                        echo -e "${GREEN}✅ 將使用選中的 AWS profile '$SELECTED_AWS_PROFILE'${NC}"
                        echo -e "${BLUE}📋 已確認使用區域: $aws_region${NC}"
                    else
                        echo -e "${YELLOW}📝 將進行 AWS 帳號重新配置${NC}"
                    fi
                else
                    echo -e "${YELLOW}⚠️ 輸入無效，使用預設選項：重新配置${NC}"
                fi
            else
                echo -e "${YELLOW}⚠️ 現有配置中缺少 AWS 區域設定${NC}"
                echo -e "${BLUE}將自動進行重新配置以確保設定完整...${NC}"
            fi
        else
            echo -e "${RED}❌ 現有 AWS 配置無法正常使用${NC}"
            echo -e "${YELLOW}⚠️ 可能的原因:${NC}"
            echo -e "  • AWS Access Key 或 Secret Key 無效"
            echo -e "  • 網路連線問題"
            echo -e "  • AWS 帳號權限不足"
            echo -e ""
            echo -e "${BLUE}將自動進行重新配置...${NC}"
        fi
    else
        echo -e "${BLUE}📋 未檢測到 AWS 配置檔案${NC}"
        echo -e "${YELLOW}需要設定 AWS 憑證以繼續 VPN 配置${NC}"
    fi
    
    if [ "$use_existing_config" = false ]; then
        echo -e "\n${YELLOW}🔧 AWS 帳號配置設定${NC}"
        echo -e "═══════════════════════════════════════"
        echo -e "請提供您的 AWS 帳戶資訊用於 VPN 設定："
        echo -e ""
        echo -e "${BLUE}💡 您需要提供:${NC}"
        echo -e "  • AWS Access Key ID (通常以 AKIA 開頭)"
        echo -e "  • AWS Secret Access Key (較長的字母數字組合)"
        echo -e "  • AWS 區域 (需與 VPN 端點在同一區域)"
        echo -e ""
        echo -e "${YELLOW}⚠️ 重要提醒:${NC}"
        echo -e "  • 請確保您的 AWS 帳號有足夠權限進行 VPN 操作"
        echo -e "  • 輸入的憑證將用於上傳證書到 AWS Certificate Manager"
        echo -e "═══════════════════════════════════════"
        echo -e ""
        
        local aws_access_key
        local aws_secret_key
        
        if ! read_secure_input "請輸入 AWS Access Key ID: " aws_access_key "validate_aws_access_key_id"; then
            echo -e "${RED}AWS Access Key ID 驗證失敗${NC}"
            log_team_setup_message "AWS Access Key ID 驗證失敗"
            return 1
        fi
        
        if ! read_secure_hidden_input "請輸入 AWS Secret Access Key: " aws_secret_key "validate_aws_secret_access_key"; then
            echo -e "${RED}AWS Secret Access Key 驗證失敗${NC}"
            log_team_setup_message "AWS Secret Access Key 驗證失敗"
            return 1
        fi
        
        if ! read_secure_input "請輸入 AWS 區域 (與 VPN 端點相同的區域): " aws_region "validate_aws_region"; then
            echo -e "${RED}AWS 區域驗證失敗${NC}"
            log_team_setup_message "AWS 區域驗證失敗"
            return 1
        fi
        
        # 備份現有配置檔案
        if [ "$existing_config" = true ]; then
            local backup_timestamp
            backup_timestamp=$(date +%Y%m%d_%H%M%S)
            echo -e "${BLUE}💾 備份現有 AWS 配置檔案...${NC}"
            echo -e "備份時間戳記: $backup_timestamp"
            
            if [ -f ~/.aws/credentials ]; then
                if cp ~/.aws/credentials ~/.aws/credentials.backup_$backup_timestamp; then
                    echo -e "${GREEN}✅ 已備份 ~/.aws/credentials → ~/.aws/credentials.backup_$backup_timestamp${NC}"
                else
                    echo -e "${YELLOW}⚠️ 備份 credentials 失敗，繼續設定${NC}"
                fi
            fi
            
            if [ -f ~/.aws/config ]; then
                if cp ~/.aws/config ~/.aws/config.backup_$backup_timestamp; then
                    echo -e "${GREEN}✅ 已備份 ~/.aws/config → ~/.aws/config.backup_$backup_timestamp${NC}"
                else
                    echo -e "${YELLOW}⚠️ 備份 config 失敗，繼續設定${NC}"
                fi
            fi
            
            echo -e "${BLUE}📝 如需恢復原始配置，請執行:${NC}"
            echo -e "  cp ~/.aws/credentials.backup_$backup_timestamp ~/.aws/credentials"
            echo -e "  cp ~/.aws/config.backup_$backup_timestamp ~/.aws/config"
            echo -e ""
        fi
        
        # 創建配置目錄
        mkdir -p ~/.aws
        
        # 使用 AWS CLI 命令安全地設定配置
        echo -e "${BLUE}🔧 設定 AWS CLI 配置...${NC}"
        aws configure set aws_access_key_id "$aws_access_key"
        aws configure set aws_secret_access_key "$aws_secret_key"
        aws configure set default.region "$aws_region"
        aws configure set default.output json
        
        echo -e "${GREEN}✅ AWS 配置設定完成！${NC}"
        echo -e "${BLUE}新配置詳細資訊:${NC}"
        echo -e "  • 區域: $aws_region"
        echo -e "  • 輸出格式: json"
    else
        echo -e "${GREEN}✅ 使用現有 AWS 配置${NC}"
    fi
    
    # 測試 AWS 連接
    echo -e "${BLUE}測試 AWS 連接...${NC}"
    if ! aws sts get-caller-identity > /dev/null; then
        echo -e "${RED}AWS 連接測試失敗${NC}"
        log_team_setup_message "AWS 連接測試失敗"
        return 1
    fi
    echo -e "${GREEN}✓ AWS 連接測試成功${NC}"
    
    # 獲取 VPN 端點資訊
    echo -e "\\n${YELLOW}請向管理員獲取以下資訊：${NC}"
    
    # 確保 AWS 區域已設置
    if [ -z "$aws_region" ]; then
        echo -e "${YELLOW}⚠️ AWS 區域未設置，正在從當前配置獲取...${NC}"
        aws_region=$(aws configure get region 2>/dev/null)
        if [ -z "$aws_region" ]; then
            echo -e "${RED}❌ 無法獲取 AWS 區域設定${NC}"
            if ! read_secure_input "請輸入 AWS 區域 (與 VPN 端點相同的區域): " aws_region "validate_aws_region"; then
                echo -e "${RED}AWS 區域驗證失敗${NC}"
                log_team_setup_message "AWS 區域驗證失敗"
                return 1
            fi
        else
            echo -e "${GREEN}✓ 已從配置獲取 AWS 區域: $aws_region${NC}"
        fi
    fi
    
    # 設定環境變數供後續函數使用
    export AWS_PROFILE="$SELECTED_AWS_PROFILE"
    export AWS_REGION="$aws_region"
    
    echo -e "${GREEN}✓ 已設定環境變數:${NC}"
    echo -e "  AWS_PROFILE=$AWS_PROFILE"
    echo -e "  AWS_REGION=$AWS_REGION"
    
    log_team_setup_message "使用 AWS profile: $SELECTED_AWS_PROFILE, region: $aws_region"
}

# 設定 CA 證書和環境確認
setup_ca_cert_and_environment() {
    echo -e "\\n${YELLOW}[2/6] 設定 CA 證書和環境確認...${NC}"
    
    # 要求用戶提供 CA 證書
    local ca_cert_path
    if ! read_secure_input "請輸入 CA 證書檔案的完整路徑: " ca_cert_path "validate_file_path"; then
        echo -e "${RED}必須提供有效的 CA 證書檔案路徑${NC}"
        return 1
    fi
    
    if [ ! -f "$ca_cert_path" ]; then
        echo -e "${RED}CA 證書檔案不存在: $ca_cert_path${NC}"
        return 1
    fi
    
    echo -e "${GREEN}✓ 找到 CA 證書檔案: $ca_cert_path${NC}"
    
    # 從 CA 證書偵測環境
    local detected_env
    detected_env=$(detect_environment_from_ca_cert "$ca_cert_path")
    
    # 從 AWS profile 偵測環境
    local profile_env
    profile_env=$(detect_environment_from_profile "$SELECTED_AWS_PROFILE")
    
    echo -e "\\n${BLUE}環境偵測結果:${NC}"
    echo -e "  從 CA 證書偵測: ${detected_env:-無法判斷}"
    echo -e "  從 AWS profile 偵測: ${profile_env:-無法判斷}"
    
    # 環境確認
    TARGET_ENVIRONMENT=$(confirm_environment_selection "$detected_env" "$ca_cert_path" "$SELECTED_AWS_PROFILE")
    
    if [ -z "$TARGET_ENVIRONMENT" ]; then
        echo -e "${RED}環境選擇失敗${NC}"
        return 1
    fi
    
    echo -e "${GREEN}✓ 確認目標環境: $(get_env_display_name "$TARGET_ENVIRONMENT")${NC}"
    
    # 設定環境特定路徑
    setup_team_member_paths "$TARGET_ENVIRONMENT" "$TEAM_SCRIPT_DIR"
    
    # 設定配置檔案路徑
    USER_CONFIG_FILE="$USER_VPN_CONFIG_FILE"
    LOG_FILE="$TEAM_SETUP_LOG_FILE"
    
    # 複製 CA 證書到環境特定目錄
    local env_ca_cert="$USER_CERT_DIR/ca.crt"
    if ! cp "$ca_cert_path" "$env_ca_cert"; then
        echo -e "${RED}複製 CA 證書失敗${NC}"
        return 1
    fi
    
    chmod 600 "$env_ca_cert"
    echo -e "${GREEN}✓ CA 證書已複製到: $env_ca_cert${NC}"
    
    log_team_setup_message "環境設定完成: $TARGET_ENVIRONMENT, CA證書: $ca_cert_path"
}

# 獲取 VPN 端點資訊
setup_vpn_endpoint_info() {
    echo -e "\\n${YELLOW}[3/6] 設定 VPN 端點資訊...${NC}"
    
    echo -e "${BLUE}請向管理員獲取以下資訊：${NC}"
    
    local endpoint_id
    if ! read_secure_input "請輸入 Client VPN 端點 ID: " endpoint_id "validate_endpoint_id"; then
        echo -e "${RED}VPN 端點 ID 驗證失敗${NC}"
        return 1
    fi
    
    # 驗證端點 ID
    echo -e "${BLUE}驗證 VPN 端點...${NC}"
    echo -e "${BLUE}使用參數: --client-vpn-endpoint-ids $endpoint_id --region $AWS_REGION --profile $AWS_PROFILE${NC}"
    local endpoint_check
    endpoint_check=$(aws ec2 describe-client-vpn-endpoints --client-vpn-endpoint-ids "$endpoint_id" --region "$AWS_REGION" --profile "$AWS_PROFILE" 2>/dev/null || echo "not_found")
    
    if [[ "$endpoint_check" == "not_found" ]]; then
        echo -e "${RED}無法找到指定的 VPN 端點。請確認 ID 是否正確，以及您是否有權限訪問。${NC}"
        log_team_setup_message "VPN 端點驗證失敗: $endpoint_id"
        return 1
    fi
    
    echo -e "${GREEN}✓ VPN 端點驗證成功${NC}"
    
    # 保存配置
    cat > "$USER_CONFIG_FILE" << EOF
AWS_REGION=$AWS_REGION
AWS_PROFILE=$SELECTED_AWS_PROFILE
ENDPOINT_ID=$endpoint_id
TARGET_ENVIRONMENT=$TARGET_ENVIRONMENT
USERNAME=""
CLIENT_CERT_ARN=""
EOF
    
    # 設置配置文件權限
    chmod 600 "$USER_CONFIG_FILE"
    
    log_team_setup_message "VPN 端點配置完成: $endpoint_id"
}

# 設定用戶資訊
setup_user_info() {
    echo -e "\\n${YELLOW}[4/6] 設定用戶資訊...${NC}"
    
    # 使用安全輸入驗證獲取用戶名
    local username
    if ! read_secure_input "請輸入您的用戶名或姓名: " username "validate_username"; then
        echo -e "${RED}用戶名驗證失敗${NC}"
        log_team_setup_message "用戶名驗證失敗"
        return 1
    fi
    
    # 確認用戶名
    echo -e "${BLUE}您的用戶名: $username${NC}"
    local confirm
    if read_secure_input "確認使用此用戶名？(y/n): " confirm "validate_yes_no"; then
        if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
            echo -e "${YELLOW}請重新執行腳本並設定正確的用戶名${NC}"
            exit 0
        fi
    else
        echo -e "${YELLOW}使用預設選項：確認使用此用戶名${NC}"
    fi
    
    # 更新配置文件
    if ! update_config "$USER_CONFIG_FILE" "USERNAME" "$username"; then
        echo -e "${RED}更新配置文件失敗${NC}"
        log_team_setup_message "更新用戶名到配置文件失敗"
        return 1
    fi
    
    echo -e "${GREEN}用戶資訊設定完成！${NC}"
    log_team_setup_message "用戶資訊已設定: $username"
}

# 生成個人客戶端證書
generate_client_certificate() {
    if [ "$RESUME_CERT_MODE" = true ]; then
        echo -e "\\n${YELLOW}[5/6] 恢復模式：查找已簽署的證書...${NC}"
        resume_with_signed_certificate
    else
        echo -e "\\n${YELLOW}[5/6] 生成 CSR 並等待管理員簽署...${NC}"
        generate_csr_for_admin_signing
    fi
}

# 新的安全 CSR 生成流程（不需要 CA 私鑰）
generate_csr_for_admin_signing() {
    local original_dir="$PWD"
    
    # 載入配置
    if ! source "$USER_CONFIG_FILE"; then
        echo -e "${RED}載入配置文件失敗${NC}"
        log_team_setup_message "載入配置文件失敗"
        return 1
    fi
    
    # 創建環境特定的用戶證書目錄
    local cert_dir="$USER_CERT_DIR"
    mkdir -p "$cert_dir"
    chmod 700 "$cert_dir"
    
    # 安全地切換到證書目錄
    if ! cd "$cert_dir"; then
        echo -e "${RED}無法切換到證書目錄: $cert_dir${NC}"
        cd "$original_dir" || {
            echo -e "${RED}警告: 無法恢復到原始目錄${NC}"
        }
        return 1
    fi
    
    # 檢查是否存在現有證書文件
    if [ -f "${USERNAME}.key" ] || [ -f "${USERNAME}.csr" ]; then
        local overwrite_key
        if read_secure_input "金鑰檔案 ${USERNAME}.key 或 ${USERNAME}.csr 已存在。是否覆蓋? (y/n): " overwrite_key "validate_yes_no"; then
            if [[ "$overwrite_key" =~ ^[Yy]$ ]]; then
                rm -f "${USERNAME}.key" "${USERNAME}.csr" "${USERNAME}.crt"
            else
                echo -e "${YELLOW}保留現有金鑰檔案。${NC}"
                # 檢查是否已有簽署證書
                if [ -f "${USERNAME}.crt" ]; then
                    echo -e "${GREEN}✓ 發現已存在的簽署證書，將自動繼續${NC}"
                    cd "$original_dir" || true
                    return 0
                fi
                # 檢查是否需要等待簽署
                if [ -f "${USERNAME}.csr" ]; then
                    echo -e "${BLUE}發現現有 CSR，等待管理員簽署...${NC}"
                    show_csr_instructions "$cert_dir/${USERNAME}.csr"
                    cd "$original_dir" || true
                    exit 0
                fi
                cd "$original_dir" || true
                return 0
            fi
        else
            echo -e "${YELLOW}保留現有金鑰檔案。${NC}"
            cd "$original_dir" || true
            return 0
        fi
    fi
    
    echo -e "${BLUE}正在為使用者 $USERNAME 產生私鑰和證書簽署請求 (CSR)...${NC}"
    
    # 生成私鑰
    if ! openssl genrsa -out "${USERNAME}.key" 2048; then
        echo -e "${RED}生成私鑰失敗${NC}"
        cd "$original_dir" || {
            echo -e "${RED}警告: 無法恢復到原始目錄${NC}"
        }
        return 1
    fi
    chmod 600 "${USERNAME}.key"
    echo -e "${GREEN}✓ 私鑰已生成: ${USERNAME}.key${NC}"
    
    # 生成 CSR
    if ! openssl req -new -key "${USERNAME}.key" -out "${USERNAME}.csr" \
      -subj "/CN=${USERNAME}/O=VPN-Client/C=TW/L=Taipei/ST=Taiwan/OU=${TARGET_ENVIRONMENT}"; then
        echo -e "${RED}生成 CSR 失敗${NC}"
        cd "$original_dir" || {
            echo -e "${RED}警告: 無法恢復到原始目錄${NC}"
        }
        return 1
    fi
    chmod 644 "${USERNAME}.csr"
    echo -e "${GREEN}✓ CSR 已生成: ${USERNAME}.csr${NC}"
    
    # 顯示 CSR 上傳指示並退出
    show_csr_instructions "$cert_dir/${USERNAME}.csr"
    
    log_team_setup_message "CSR 已生成，等待管理員簽署"
    
    # 在函數結束前恢復目錄
    cd "$original_dir" || {
        echo -e "${RED}警告: 無法恢復到原始目錄${NC}"
    }
    
    # CSR 生成階段完成，退出腳本等待管理員簽署
    exit 0
}

# 恢復模式：使用已簽署的證書繼續設定
resume_with_signed_certificate() {
    local original_dir="$PWD"
    
    # 載入配置
    if ! source "$USER_CONFIG_FILE"; then
        echo -e "${RED}載入配置文件失敗${NC}"
        log_team_setup_message "載入配置文件失敗"
        return 1
    fi
    
    local cert_dir="$USER_CERT_DIR"
    
    # 檢查證書目錄
    if [ ! -d "$cert_dir" ]; then
        echo -e "${RED}證書目錄不存在: $cert_dir${NC}"
        echo -e "${YELLOW}請先執行腳本生成 CSR${NC}"
        return 1
    fi
    
    # 安全地切換到證書目錄
    if ! cd "$cert_dir"; then
        echo -e "${RED}無法切換到證書目錄: $cert_dir${NC}"
        return 1
    fi
    
    # 檢查必要文件
    if [ ! -f "${USERNAME}.key" ]; then
        echo -e "${RED}找不到私鑰文件: ${USERNAME}.key${NC}"
        echo -e "${YELLOW}請先執行腳本生成 CSR${NC}"
        cd "$original_dir" || true
        return 1
    fi
    
    if [ ! -f "${USERNAME}.crt" ]; then
        echo -e "${RED}找不到簽署證書: ${USERNAME}.crt${NC}"
        echo -e "${YELLOW}請等待管理員簽署您的 CSR，或檢查證書是否已下載到正確位置${NC}"
        echo -e "${BLUE}證書應放置在: $cert_dir/${USERNAME}.crt${NC}"
        cd "$original_dir" || true
        return 1
    fi
    
    # 驗證證書
    echo -e "${BLUE}驗證簽署證書...${NC}"
    if ! openssl x509 -in "${USERNAME}.crt" -text -noout >/dev/null 2>&1; then
        echo -e "${RED}證書格式無效${NC}"
        cd "$original_dir" || true
        return 1
    fi
    
    # 驗證私鑰與證書匹配
    local key_modulus cert_modulus
    key_modulus=$(openssl rsa -in "${USERNAME}.key" -modulus -noout 2>/dev/null)
    cert_modulus=$(openssl x509 -in "${USERNAME}.crt" -modulus -noout 2>/dev/null)
    
    if [ "$key_modulus" != "$cert_modulus" ]; then
        echo -e "${RED}私鑰與證書不匹配${NC}"
        cd "$original_dir" || true
        return 1
    fi
    
    # 設置正確權限
    chmod 600 "${USERNAME}.key"
    chmod 600 "${USERNAME}.crt"
    
    echo -e "${GREEN}✓ 證書驗證成功${NC}"
    echo -e "${GREEN}✓ 私鑰與證書匹配${NC}"
    
    # 清理 CSR 文件
    rm -f "${USERNAME}.csr"
    
    log_team_setup_message "使用已簽署證書繼續設定"
    
    # 在函數結束前恢復目錄
    cd "$original_dir" || {
        echo -e "${RED}警告: 無法恢復到原始目錄${NC}"
    }
}

# S3 零接觸功能
# =====================================

# 檢查 S3 存儲桶訪問權限
check_s3_access() {
    echo -e "${BLUE}檢查 S3 存儲桶訪問權限...${NC}"
    
    if ! aws s3 ls "s3://$S3_BUCKET/public/" --profile "$SELECTED_AWS_PROFILE" &>/dev/null; then
        echo -e "${RED}無法訪問 S3 存儲桶: $S3_BUCKET${NC}"
        echo -e "${YELLOW}請檢查：${NC}"
        echo -e "  • 存儲桶是否存在"
        echo -e "  • IAM 權限是否正確設置"
        echo -e "  • AWS profile 是否有效"
        return 1
    fi
    
    echo -e "${GREEN}✓ S3 存儲桶訪問正常${NC}"
    return 0
}

# 從 S3 下載 CA 證書
download_ca_from_s3() {
    echo -e "${BLUE}從 S3 下載 CA 證書...${NC}"
    
    local ca_cert_path="$USER_CERT_DIR/ca.crt"
    local s3_ca_path="s3://$S3_BUCKET/public/ca.crt"
    
    if ! aws s3 cp "$s3_ca_path" "$ca_cert_path" --profile "$SELECTED_AWS_PROFILE"; then
        echo -e "${RED}下載 CA 證書失敗${NC}"
        return 1
    fi
    
    # 驗證 CA 證書
    if ! openssl x509 -in "$ca_cert_path" -text -noout >/dev/null 2>&1; then
        echo -e "${RED}下載的 CA 證書格式無效${NC}"
        rm -f "$ca_cert_path"
        return 1
    fi
    
    # 可選：驗證 SHA-256 哈希
    if aws s3 cp "s3://$S3_BUCKET/public/ca.crt.sha256" "/tmp/ca.crt.sha256" --profile "$SELECTED_AWS_PROFILE" &>/dev/null; then
        local expected_hash actual_hash
        expected_hash=$(cat "/tmp/ca.crt.sha256" 2>/dev/null | tr -d '\n\r ')
        actual_hash=$(openssl dgst -sha256 "$ca_cert_path" | awk '{print $2}')
        
        if [ -n "$expected_hash" ] && [ "$expected_hash" = "$actual_hash" ]; then
            echo -e "${GREEN}✓ CA 證書哈希驗證成功${NC}"
        elif [ -n "$expected_hash" ]; then
            echo -e "${YELLOW}⚠ CA 證書哈希不匹配，但繼續執行${NC}"
        fi
        rm -f "/tmp/ca.crt.sha256"
    fi
    
    chmod 600 "$ca_cert_path"
    echo -e "${GREEN}✓ CA 證書下載完成: $ca_cert_path${NC}"
    return 0
}

# 從 S3 下載 VPN 端點配置
download_endpoints_from_s3() {
    echo -e "${BLUE}從 S3 下載 VPN 端點配置...${NC}"
    
    local endpoints_path="/tmp/vpn_endpoints.json"
    local s3_endpoints_path="s3://$S3_BUCKET/public/vpn_endpoints.json"
    
    if ! aws s3 cp "$s3_endpoints_path" "$endpoints_path" --profile "$SELECTED_AWS_PROFILE"; then
        echo -e "${RED}下載端點配置失敗${NC}"
        return 1
    fi
    
    # 驗證 JSON 格式
    if command -v jq >/dev/null 2>&1; then
        if ! jq . "$endpoints_path" >/dev/null 2>&1; then
            echo -e "${RED}下載的端點配置 JSON 格式無效${NC}"
            rm -f "$endpoints_path"
            return 1
        fi
    fi
    
    echo -e "${GREEN}✓ 端點配置下載完成${NC}"
    ENDPOINTS_CONFIG_FILE="$endpoints_path"
    return 0
}

# 從端點配置中選擇環境
select_environment_from_config() {
    echo -e "${BLUE}選擇 VPN 環境...${NC}"
    
    if [ ! -f "$ENDPOINTS_CONFIG_FILE" ]; then
        echo -e "${RED}端點配置文件不存在${NC}"
        return 1
    fi
    
    # 列出可用環境
    echo -e "${CYAN}可用的 VPN 環境：${NC}"
    local environments
    if command -v jq >/dev/null 2>&1; then
        environments=$(jq -r 'keys[]' "$ENDPOINTS_CONFIG_FILE" 2>/dev/null)
    else
        # 備用解析方法
        environments=$(grep -o '"[^"]*"[[:space:]]*:' "$ENDPOINTS_CONFIG_FILE" | sed 's/[":]//g' | tr -d ' ')
    fi
    
    if [ -z "$environments" ]; then
        echo -e "${RED}無法解析環境配置${NC}"
        return 1
    fi
    
    local env_array=()
    while IFS= read -r env; do
        env_array+=("$env")
        echo -e "  ${YELLOW}$((${#env_array[@]}))${NC}. $env"
    done <<< "$environments"
    
    if [ ${#env_array[@]} -eq 0 ]; then
        echo -e "${RED}沒有可用的環境${NC}"
        return 1
    fi
    
    # 如果只有一個環境，自動選擇
    if [ ${#env_array[@]} -eq 1 ]; then
        TARGET_ENVIRONMENT="${env_array[0]}"
        echo -e "${GREEN}✓ 自動選擇環境: $TARGET_ENVIRONMENT${NC}"
    else
        # 用戶選擇環境
        local choice
        while true; do
            read -p "請選擇環境 (1-${#env_array[@]}): " choice
            if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le ${#env_array[@]} ]; then
                TARGET_ENVIRONMENT="${env_array[$((choice-1))]}"
                echo -e "${GREEN}✓ 選擇環境: $TARGET_ENVIRONMENT${NC}"
                break
            else
                echo -e "${RED}無效選擇，請輸入 1-${#env_array[@]}${NC}"
            fi
        done
    fi
    
    # 提取環境配置
    if command -v jq >/dev/null 2>&1; then
        ENDPOINT_ID=$(jq -r ".[\"$TARGET_ENVIRONMENT\"].endpoint_id" "$ENDPOINTS_CONFIG_FILE" 2>/dev/null)
        AWS_REGION=$(jq -r ".[\"$TARGET_ENVIRONMENT\"].region" "$ENDPOINTS_CONFIG_FILE" 2>/dev/null)
    else
        # 備用解析方法
        local env_section
        env_section=$(sed -n "/\"$TARGET_ENVIRONMENT\"[[:space:]]*:/,/}/p" "$ENDPOINTS_CONFIG_FILE")
        ENDPOINT_ID=$(echo "$env_section" | grep -o '"endpoint_id"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*"endpoint_id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')
        AWS_REGION=$(echo "$env_section" | grep -o '"region"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*"region"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')
    fi
    
    if [ -z "$ENDPOINT_ID" ] || [ -z "$AWS_REGION" ]; then
        echo -e "${RED}無法解析環境配置 (endpoint_id: $ENDPOINT_ID, region: $AWS_REGION)${NC}"
        return 1
    fi
    
    echo -e "${GREEN}✓ 環境配置: 端點 $ENDPOINT_ID, 區域 $AWS_REGION${NC}"
    return 0
}

# 上傳 CSR 到 S3
upload_csr_to_s3() {
    local csr_file="$1"
    local username="$2"
    
    echo -e "${BLUE}上傳 CSR 到 S3...${NC}"
    
    local s3_csr_path="s3://$S3_BUCKET/csr/${username}.csr"
    
    if aws s3 cp "$csr_file" "$s3_csr_path" \
        --sse aws:kms \
        --profile "$SELECTED_AWS_PROFILE"; then
        echo -e "${GREEN}✓ CSR 已上傳到 S3${NC}"
        log_team_setup_message "CSR 已上傳到 S3: $s3_csr_path"
        return 0
    else
        echo -e "${RED}CSR 上傳失敗${NC}"
        return 1
    fi
}

# 從 S3 下載簽署證書
download_certificate_from_s3() {
    local username="$1"
    local cert_file="$2"
    
    echo -e "${BLUE}從 S3 下載簽署證書...${NC}"
    
    local s3_cert_path="s3://$S3_BUCKET/cert/${username}.crt"
    
    # 檢查證書是否存在
    if ! aws s3 ls "$s3_cert_path" --profile "$SELECTED_AWS_PROFILE" &>/dev/null; then
        echo -e "${YELLOW}證書尚未準備好，請等待管理員簽署${NC}"
        echo -e "${BLUE}證書位置: $s3_cert_path${NC}"
        return 1
    fi
    
    if aws s3 cp "$s3_cert_path" "$cert_file" --profile "$SELECTED_AWS_PROFILE"; then
        echo -e "${GREEN}✓ 證書已從 S3 下載${NC}"
        log_team_setup_message "證書已從 S3 下載: $s3_cert_path"
        return 0
    else
        echo -e "${RED}證書下載失敗${NC}"
        return 1
    fi
}

# 零接觸初始化模式
zero_touch_init_mode() {
    echo -e "\n${YELLOW}[零接觸模式] 初始化 VPN 設定...${NC}"
    
    # 檢查 S3 訪問
    if [ "$DISABLE_S3" = false ]; then
        if ! check_s3_access; then
            echo -e "${YELLOW}S3 訪問失敗，切換到本地模式${NC}"
            DISABLE_S3=true
        fi
    fi
    
    # 初始化環境和 AWS 配置
    if ! init_environment_and_aws; then
        return 1
    fi
    
    # 下載或使用本地 CA 證書
    if [ "$DISABLE_S3" = false ] && [ -z "$CA_PATH" ]; then
        if ! download_ca_from_s3; then
            echo -e "${YELLOW}CA 證書下載失敗，請手動提供${NC}"
            setup_ca_cert_and_environment
        fi
    else
        setup_ca_cert_and_environment
    fi
    
    # 下載或手動設置端點配置
    if [ "$DISABLE_S3" = false ] && [ -z "$ENDPOINT_ID" ]; then
        if download_endpoints_from_s3; then
            if select_environment_from_config; then
                echo -e "${GREEN}✓ 使用 S3 端點配置${NC}"
            else
                echo -e "${YELLOW}端點配置解析失敗，手動設置${NC}"
                setup_vpn_endpoint_info
            fi
        else
            echo -e "${YELLOW}端點配置下載失敗，手動設置${NC}"
            setup_vpn_endpoint_info
        fi
    else
        setup_vpn_endpoint_info
    fi
    
    # 設定用戶資訊
    setup_user_info
    
    # 載入配置以獲取用戶名
    if ! source "$USER_CONFIG_FILE"; then
        echo -e "${RED}載入配置文件失敗${NC}"
        return 1
    fi
    
    # 生成 CSR 並上傳
    generate_csr_for_zero_touch
    
    return 0
}

# 零接觸恢復模式
zero_touch_resume_mode() {
    echo -e "\n${YELLOW}[零接觸模式] 恢復 VPN 設定...${NC}"
    
    # 檢查是否有現有配置
    if [ ! -f "$USER_CONFIG_FILE" ]; then
        echo -e "${RED}找不到配置文件，請先執行初始化模式${NC}"
        echo -e "${YELLOW}執行: $0 --init${NC}"
        return 1
    fi
    
    # 載入配置
    if ! source "$USER_CONFIG_FILE"; then
        echo -e "${RED}載入配置文件失敗${NC}"
        return 1
    fi
    
    # 檢查 S3 訪問（如果啟用）
    if [ "$DISABLE_S3" = false ]; then
        if ! check_s3_access; then
            echo -e "${YELLOW}S3 訪問失敗，切換到本地模式${NC}"
            DISABLE_S3=true
        fi
    fi
    
    # 下載簽署證書
    local cert_file="$USER_CERT_DIR/${USERNAME}.crt"
    if [ "$DISABLE_S3" = false ]; then
        if download_certificate_from_s3 "$USERNAME" "$cert_file"; then
            echo -e "${GREEN}✓ 使用 S3 下載的證書${NC}"
        else
            echo -e "${YELLOW}證書下載失敗，檢查本地文件${NC}"
            if [ ! -f "$cert_file" ]; then
                echo -e "${RED}找不到簽署證書，請等待管理員簽署或檢查文件位置${NC}"
                return 1
            fi
        fi
    else
        if [ ! -f "$cert_file" ]; then
            echo -e "${RED}找不到簽署證書: $cert_file${NC}"
            return 1
        fi
    fi
    
    # 驗證證書
    if ! resume_with_signed_certificate; then
        return 1
    fi
    
    # 導入證書到 ACM
    import_certificate
    
    # 設置 VPN 客戶端
    setup_vpn_client
    
    # 顯示連接指示
    show_connection_instructions
    
    return 0
}

# 為零接觸模式生成 CSR
generate_csr_for_zero_touch() {
    local original_dir="$PWD"
    
    # 載入配置
    if ! source "$USER_CONFIG_FILE"; then
        echo -e "${RED}載入配置文件失敗${NC}"
        log_team_setup_message "載入配置文件失敗"
        return 1
    fi
    
    # 創建環境特定的用戶證書目錄
    local cert_dir="$USER_CERT_DIR"
    mkdir -p "$cert_dir"
    chmod 700 "$cert_dir"
    
    # 安全地切換到證書目錄
    if ! cd "$cert_dir"; then
        echo -e "${RED}無法切換到證書目錄: $cert_dir${NC}"
        cd "$original_dir" || true
        return 1
    fi
    
    # 檢查是否存在現有證書文件
    if [ -f "${USERNAME}.key" ] || [ -f "${USERNAME}.csr" ]; then
        local overwrite_key
        if read_secure_input "金鑰檔案 ${USERNAME}.key 或 ${USERNAME}.csr 已存在。是否覆蓋? (y/n): " overwrite_key "validate_yes_no"; then
            if [[ "$overwrite_key" =~ ^[Yy]$ ]]; then
                rm -f "${USERNAME}.key" "${USERNAME}.csr" "${USERNAME}.crt"
            else
                echo -e "${YELLOW}保留現有金鑰檔案。${NC}"
                cd "$original_dir" || true
                return 0
            fi
        else
            echo -e "${YELLOW}保留現有金鑰檔案。${NC}"
            cd "$original_dir" || true
            return 0
        fi
    fi
    
    echo -e "${BLUE}正在為使用者 $USERNAME 產生私鑰和證書簽署請求 (CSR)...${NC}"
    
    # 生成私鑰
    if ! openssl genrsa -out "${USERNAME}.key" 2048; then
        echo -e "${RED}生成私鑰失敗${NC}"
        cd "$original_dir" || true
        return 1
    fi
    chmod 600 "${USERNAME}.key"
    echo -e "${GREEN}✓ 私鑰已生成: ${USERNAME}.key${NC}"
    
    # 生成 CSR
    if ! openssl req -new -key "${USERNAME}.key" -out "${USERNAME}.csr" \
      -subj "/CN=${USERNAME}/O=VPN-Client/C=TW/L=Taipei/ST=Taiwan/OU=${TARGET_ENVIRONMENT}"; then
        echo -e "${RED}生成 CSR 失敗${NC}"
        cd "$original_dir" || true
        return 1
    fi
    chmod 644 "${USERNAME}.csr"
    echo -e "${GREEN}✓ CSR 已生成: ${USERNAME}.csr${NC}"
    
    # 上傳 CSR 到 S3（如果啟用）
    if [ "$DISABLE_S3" = false ]; then
        if upload_csr_to_s3 "$cert_dir/${USERNAME}.csr" "$USERNAME"; then
            echo -e "${GREEN}✓ CSR 已上傳到 S3，等待管理員簽署${NC}"
        else
            echo -e "${YELLOW}CSR 上傳失敗，請手動提供給管理員${NC}"
        fi
    fi
    
    # 顯示零接觸等待指示
    show_zero_touch_instructions "$cert_dir/${USERNAME}.csr"
    
    log_team_setup_message "CSR 已生成，等待管理員簽署"
    
    cd "$original_dir" || true
    
    # 零接觸模式：CSR 生成階段完成，退出腳本等待管理員簽署
    exit 0
}

# 顯示零接觸等待指示
show_zero_touch_instructions() {
    local csr_path="$1"
    
    echo -e "\n${GREEN}=============================================${NC}"
    echo -e "${GREEN}       零接觸 CSR 生成完成！       ${NC}"
    echo -e "${GREEN}=============================================${NC}"
    echo -e ""
    echo -e "${CYAN}📋 下一步操作：${NC}"
    echo -e ""
    
    if [ "$DISABLE_S3" = false ]; then
        echo -e "${BLUE}✅ CSR 已自動上傳到 S3 存儲桶${NC}"
        echo -e "   位置: ${YELLOW}s3://$S3_BUCKET/csr/${USERNAME}.csr${NC}"
        echo -e ""
        echo -e "${BLUE}🔔 通知管理員${NC}"
        echo -e "   告知管理員您的 CSR 已準備好簽署"
        echo -e "   用戶名: ${CYAN}$USERNAME${NC}"
        echo -e "   環境: ${CYAN}$TARGET_ENVIRONMENT${NC}"
        echo -e ""
        echo -e "${BLUE}⏳ 等待簽署完成${NC}"
        echo -e "   管理員簽署後，證書將自動上傳到:"
        echo -e "   ${YELLOW}s3://$S3_BUCKET/cert/${USERNAME}.crt${NC}"
        echo -e ""
        echo -e "${BLUE}🎯 完成設定${NC}"
        echo -e "   當管理員告知證書已簽署後，執行:"
        echo -e "   ${CYAN}$0 --resume${NC}"
    else
        echo -e "${BLUE}📁 本地 CSR 文件位置：${NC}"
        echo -e "   ${YELLOW}$csr_path${NC}"
        echo -e ""
        echo -e "${BLUE}📧 手動提供給管理員${NC}"
        echo -e "   將上述 CSR 文件提供給管理員進行簽署"
        echo -e ""
        echo -e "${BLUE}📥 等待簽署證書${NC}"
        echo -e "   簽署後的證書應放置在:"
        echo -e "   ${YELLOW}$USER_CERT_DIR/${USERNAME}.crt${NC}"
        echo -e ""
        echo -e "${BLUE}🎯 完成設定${NC}"
        echo -e "   當收到簽署證書後，執行:"
        echo -e "   ${CYAN}$0 --resume${NC}"
    fi
    
    echo -e ""
    echo -e "${YELLOW}💡 提示：${NC}"
    echo -e "• 請保留此 CSR 文件直到設定完成"
    echo -e "• 零接觸模式可自動處理大部分配置"
    echo -e "• 如有問題，請聯繫系統管理員"
    echo -e ""
    echo -e "${GREEN}設定暫停，等待證書簽署...${NC}"
}

# 顯示 CSR 上傳和等待指示
show_csr_instructions() {
    local csr_path="$1"
    
    echo -e "\n${GREEN}=============================================${NC}"
    echo -e "${GREEN}       CSR 生成完成！       ${NC}"
    echo -e "${GREEN}=============================================${NC}"
    echo -e ""
    echo -e "${CYAN}📋 下一步操作：${NC}"
    echo -e ""
    echo -e "${BLUE}1. 將以下 CSR 文件提供給管理員：${NC}"
    echo -e "   ${YELLOW}$csr_path${NC}"
    echo -e ""
    echo -e "${BLUE}2. 將 CSR 上傳到指定位置（根據管理員指示）：${NC}"
    echo -e "   • 上傳到 S3: ${CYAN}s3://vpn-csr-exchange/csr/${USERNAME}.csr${NC}"
    echo -e "   • 或者發送電子郵件給管理員"
    echo -e ""
    echo -e "${BLUE}3. 等待管理員簽署您的證書${NC}"
    echo -e ""
    echo -e "${BLUE}4. 當管理員告知證書已簽署後，執行以下命令繼續設定：${NC}"
    echo -e "   ${CYAN}$0 --resume-cert${NC}"
    echo -e ""
    echo -e "${YELLOW}💡 提示：${NC}"
    echo -e "• 請保留此 CSR 文件直到設定完成"
    echo -e "• 簽署後的證書文件將命名為: ${USERNAME}.crt"
    echo -e "• 管理員將提供具體的上傳和下載指示"
    echo -e ""
    echo -e "${GREEN}設定暫停，等待證書簽署...${NC}"
}
# 導入證書到 ACM
import_certificate() {
    echo -e "\\n${YELLOW}[6/6] 導入證書到 AWS Certificate Manager...${NC}"
    
    # 載入配置
    if ! source "$USER_CONFIG_FILE"; then
        echo -e "${RED}載入配置文件失敗${NC}"
        return 1
    fi
    
    local cert_dir="$USER_CERT_DIR"
    
    # 檢查證書文件
    local required_files=(
        "$cert_dir/${USERNAME}.crt"
        "$cert_dir/${USERNAME}.key"
        "$cert_dir/ca.crt"
    )
    
    for file in "${required_files[@]}"; do
        if [ ! -f "$file" ]; then
            echo -e "${RED}找不到必要的證書文件: $file${NC}"
            return 1
        fi
    done
    
    # 導入客戶端證書
    echo -e "${BLUE}導入客戶端證書到 ACM...${NC}"
    local client_cert
    if ! client_cert=$(aws acm import-certificate \
    --certificate "fileb://$cert_dir/${USERNAME}.crt" \
    --private-key "fileb://$cert_dir/${USERNAME}.key" \
    --certificate-chain "fileb://$cert_dir/ca.crt" \
    --region "$AWS_REGION" \
    --profile "$AWS_PROFILE" \
    --tags Key=Name,Value="VPN-Client-${USERNAME}" Key=Purpose,Value="ClientVPN" Key=User,Value="$USERNAME"); then
        echo -e "${RED}導入證書失敗${NC}"
        return 1
    fi
    
    local client_cert_arn
    if ! client_cert_arn=$(echo "$client_cert" | jq -r '.CertificateArn' 2>/dev/null); then
        # 備用解析方法
        client_cert_arn=$(echo "$client_cert" | grep -o '"CertificateArn":"arn:aws:acm:[^"]*"' | sed 's/"CertificateArn":"//g' | sed 's/"//g' | head -1)
    fi
    
    # 驗證解析結果
    if ! validate_json_parse_result "$client_cert_arn" "客戶端證書ARN" "validate_certificate_arn"; then
        echo -e "${RED}無法獲取客戶端證書 ARN${NC}"
        log_team_setup_message "無法獲取客戶端證書 ARN"
        return 1
    fi
    
    echo -e "${GREEN}✓ 證書導入完成${NC}"
    echo -e "證書 ARN: ${BLUE}$client_cert_arn${NC}"
    
    # 更新配置文件
    if ! update_config "$USER_CONFIG_FILE" "CLIENT_CERT_ARN" "$client_cert_arn"; then
        echo -e "${YELLOW}⚠ 更新配置文件失敗，但證書已成功導入${NC}"
    fi
    
    log_team_setup_message "證書已導入到 ACM: $client_cert_arn"
}

# 設置 VPN 客戶端
setup_vpn_client() {
    echo -e "\\n${YELLOW}[7/7] 設置 VPN 客戶端...${NC}"
    
    # 載入配置
    if ! source "$USER_CONFIG_FILE"; then
        echo -e "${RED}載入配置文件失敗${NC}"
        return 1
    fi
    
    local cert_dir="$USER_CERT_DIR"
    
    # 下載 VPN 配置
    echo -e "${BLUE}下載 VPN 配置文件...${NC}"
    local config_dir="$USER_VPN_CONFIG_DIR"
    mkdir -p "$config_dir"
    chmod 700 "$config_dir"
    
    if ! aws ec2 export-client-vpn-client-configuration \
      --client-vpn-endpoint-id "$ENDPOINT_ID" \
      --region "$AWS_REGION" \
      --profile "$AWS_PROFILE" \
      --output text > "$config_dir/client-config-base.ovpn"; then
        echo -e "${RED}下載 VPN 配置失敗${NC}"
        log_team_setup_message "下載 VPN 配置失敗"
        return 1
    fi
    
    # 創建個人配置文件
    echo -e "${BLUE}建立個人配置文件...${NC}"
    if ! cp "$config_dir/client-config-base.ovpn" "$config_dir/${USERNAME}-config.ovpn"; then
        echo -e "${RED}建立個人配置文件失敗${NC}"
        return 1
    fi
    
    # 添加配置選項
    echo "reneg-sec 0" >> "$config_dir/${USERNAME}-config.ovpn"
    
    # 添加進階 AWS 域名分割 DNS 和路由配置
    # 這個配置確保 AWS 服務能夠正確通過 VPN 連接存取，同時保持本地網路流量的正常路由
    echo -e "${BLUE}配置 AWS 域名分割 DNS 和進階路由...${NC}"
    {
        echo ""
        echo "# ========================================"
        echo "# AWS 進階 DNS 分流與路由配置"
        echo "# 由 team_member_setup.sh 自動生成"
        echo "# ========================================"
        echo ""
        echo "# DNS 優先級設定：確保 AWS 域名查詢優先使用 VPN DNS"
        echo "dhcp-option DNS-priority 1"
        echo ""
        echo "# AWS 內部域名配置：以下域名將通過 VPC DNS 解析"
        echo "dhcp-option DOMAIN internal                      # 一般內部域名"
        echo "dhcp-option DOMAIN $AWS_REGION.compute.internal  # EC2 私有 DNS 名稱 (區域特定)"
        echo "dhcp-option DOMAIN ec2.internal                  # EC2 一般內部域名"
        echo "dhcp-option DOMAIN $AWS_REGION.elb.amazonaws.com # Elastic Load Balancer 服務"
        echo "dhcp-option DOMAIN $AWS_REGION.rds.amazonaws.com # RDS 資料庫服務"
        echo "dhcp-option DOMAIN $AWS_REGION.s3.amazonaws.com  # S3 儲存服務"
        echo "dhcp-option DOMAIN *.amazonaws.com               # 所有 AWS 服務域名"
        echo ""
        echo "# ========================================"
        echo "# AWS 核心服務路由配置"
        echo "# 確保關鍵 AWS 服務能夠正確存取"
        echo "# ========================================"
        echo ""
        echo "# EC2 Instance Metadata Service (IMDS) - 應用程式取得實例資訊和 IAM 角色憑證"
        echo "route 169.254.169.254 255.255.255.255"
        echo ""
        echo "# VPC DNS Resolver - 確保所有 AWS 內部 DNS 查詢正確路由"
        echo "route 169.254.169.253 255.255.255.255"
        echo ""
        echo "# 注意：這些設定啟用以下功能："
        echo "# - EC2 私有 DNS 名稱解析"
        echo "# - AWS 服務內部端點存取"
        echo "# - 應用程式 IAM 角色整合"
        echo "# - VPC 內部服務發現"
        echo "# - 最佳化的 AWS 服務連接路徑"
        echo ""
    } >> "$config_dir/${USERNAME}-config.ovpn"
    
    # 添加客戶端證書和密鑰
    {
        echo "<cert>"
        cat "$cert_dir/${USERNAME}.crt"
        echo "</cert>"
        echo "<key>"
        cat "$cert_dir/${USERNAME}.key"
        echo "</key>"
    } >> "$config_dir/${USERNAME}-config.ovpn"
    
    # 設置配置文件權限
    chmod 600 "$config_dir/${USERNAME}-config.ovpn"
    
    echo -e "${GREEN}✓ 個人配置文件已建立${NC}"
    
    # 詢問用戶是否要安裝 AWS VPN 客戶端
    echo -e "\n${CYAN}========================================${NC}"
    echo -e "${CYAN}AWS VPN 客戶端安裝${NC}"
    echo -e "${CYAN}========================================${NC}"
    echo -e "您需要安裝 AWS VPN 客戶端來連接到 VPN。"
    echo -e "您可以選擇現在自動安裝，或稍後手動安裝。"
    echo
    
    local install_client
    if read_secure_input "是否要現在安裝 AWS VPN 客戶端？(y/n): " install_client "validate_yes_no"; then
        if [[ "$install_client" =~ ^[Yy]$ ]]; then
            # 下載並安裝 AWS VPN 客戶端（跨平台）
            echo -e "${BLUE}設置 AWS VPN 客戶端...${NC}"
            
            local os_type=$(uname -s)
            case "$os_type" in
                "Darwin")
                    setup_vpn_client_macos
                    ;;
                "Linux")
                    setup_vpn_client_linux
                    ;;
                *)
                    echo -e "${YELLOW}⚠ 未支援的作業系統自動安裝 VPN 客戶端${NC}"
                    echo -e "${BLUE}請手動下載並安裝 AWS VPN 客戶端：${NC}"
                    echo -e "  macOS: https://d20adtppz83p9s.cloudfront.net/OSX/latest/AWS_VPN_Client.pkg"
                    echo -e "  Windows: https://d20adtppz83p9s.cloudfront.net/WIN/latest/AWS_VPN_Client.msi"
                    echo -e "  Linux: 請使用 OpenVPN 客戶端"
                    ;;
            esac
            
            # 顯示如何啟動客戶端的說明
            show_vpn_client_launch_instructions
        else
            echo -e "${YELLOW}跳過 AWS VPN 客戶端安裝${NC}"
            echo -e "${BLUE}您可以稍後從以下連結手動下載安裝：${NC}"
            echo -e "  • macOS: https://d20adtppz83p9s.cloudfront.net/OSX/latest/AWS_VPN_Client.pkg"
            echo -e "  • Windows: https://d20adtppz83p9s.cloudfront.net/WIN/latest/AWS_VPN_Client.msi"
            echo -e "  • Linux: 請使用 OpenVPN 客戶端"
            echo
            echo -e "${BLUE}安裝完成後，請使用以下配置文件：${NC}"
            echo -e "  ${CYAN}$config_dir/${USERNAME}-config.ovpn${NC}"
        fi
    else
        echo -e "${YELLOW}跳過 AWS VPN 客戶端安裝${NC}"
    fi
    
    echo -e "${GREEN}VPN 客戶端設置完成！${NC}"
    echo -e "您的配置文件: ${BLUE}$config_dir/${USERNAME}-config.ovpn${NC}"
    
    log_team_setup_message "VPN 客戶端設置完成"
}

# 顯示 VPN 客戶端啟動說明
show_vpn_client_launch_instructions() {
    echo -e "\n${CYAN}========================================${NC}"
    echo -e "${CYAN}如何啟動 AWS VPN 客戶端${NC}"
    echo -e "${CYAN}========================================${NC}"
    
    local os_type=$(uname -s)
    case "$os_type" in
        "Darwin")
            echo -e "${BLUE}macOS 用戶：${NC}"
            echo -e "1. 開啟 Finder"
            echo -e "2. 前往「應用程式」資料夾"
            echo -e "3. 找到並雙擊「AWS VPN Client」"
            echo -e "4. 或者在 Spotlight 搜尋中輸入「AWS VPN Client」"
            echo
            echo -e "${BLUE}使用 Launchpad：${NC}"
            echo -e "• 按 F4 或點擊 Dock 中的 Launchpad 圖示"
            echo -e "• 搜尋「AWS VPN Client」並點擊"
            ;;
        "Linux")
            echo -e "${BLUE}Linux 用戶：${NC}"
            echo -e "請使用 OpenVPN 客戶端："
            echo -e "sudo openvpn --config $USER_VPN_CONFIG_DIR/${USERNAME}-config.ovpn"
            echo
            echo -e "${BLUE}或使用 Network Manager (GUI)：${NC}"
            echo -e "1. 打開網路設定"
            echo -e "2. 點擊「+」新增連接"
            echo -e "3. 選擇「匯入 VPN 連接」"
            echo -e "4. 選擇您的 .ovpn 文件"
            ;;
        *)
            echo -e "${BLUE}其他作業系統：${NC}"
            echo -e "請下載並安裝適合您作業系統的 VPN 客戶端"
            echo -e "• Windows: 下載並安裝 .msi 文件後，在開始選單中搜尋「AWS VPN Client」"
            echo -e "• 其他系統: 使用支援 OpenVPN 的客戶端"
            ;;
    esac
    
    echo
    echo -e "${GREEN}配置文件位置：${NC}"
    echo -e "  ${CYAN}$USER_VPN_CONFIG_DIR/${USERNAME}-config.ovpn${NC}"
    echo
    echo -e "${YELLOW}提示：${NC}"
    echo -e "• 首次連接時，VPN 客戶端會要求您匯入配置文件"
    echo -e "• 選擇上述路徑中的 .ovpn 文件"
    echo -e "• 連接後，您就可以安全地訪問內部資源"
    echo
}

# macOS VPN 客戶端安裝
setup_vpn_client_macos() {
    # 檢查是否已安裝
    if [ ! -d "/Applications/AWS VPN Client.app" ]; then
        echo -e "${BLUE}下載 AWS VPN 客戶端...${NC}"
        local vpn_client_url="https://d20adtppz83p9s.cloudfront.net/OSX/latest/AWS_VPN_Client.pkg"
        
        # 確保 Downloads 目錄存在
        mkdir -p ~/Downloads

        if ! curl -L -o ~/Downloads/AWS_VPN_Client.pkg "$vpn_client_url"; then
            echo -e "${RED}下載 AWS VPN 客戶端失敗${NC}"
            log_team_setup_message "下載 AWS VPN 客戶端失敗"
            return 1
        fi
        
        echo -e "${YELLOW}安裝 AWS VPN 客戶端需要管理員權限，請輸入密碼...${NC}"
        if ! sudo installer -pkg ~/Downloads/AWS_VPN_Client.pkg -target /; then
            echo -e "${RED}安裝失敗。請檢查權限或手動安裝。${NC}"
            echo -e "${BLUE}您也可以從以下位置手動安裝：~/Downloads/AWS_VPN_Client.pkg${NC}"
            return 1
        fi
        
        echo -e "${GREEN}✓ AWS VPN 客戶端已安裝${NC}"
    else
        echo -e "${GREEN}✓ AWS VPN 客戶端已存在${NC}"
    fi
}

# Linux VPN 客戶端設置
setup_vpn_client_linux() {
    echo -e "${BLUE}設置 OpenVPN 客戶端...${NC}"
    
    # 檢查 OpenVPN 是否已安裝
    if ! command -v openvpn &> /dev/null; then
        echo -e "${YELLOW}正在安裝 OpenVPN...${NC}"
        
        if command -v apt-get &> /dev/null; then
            sudo apt-get update
            sudo apt-get install -y openvpn
        elif command -v yum &> /dev/null; then
            sudo yum install -y openvpn
        else
            echo -e "${RED}無法自動安裝 OpenVPN。請手動安裝後重新執行腳本。${NC}"
            return 1
        fi
    fi
    
    echo -e "${GREEN}✓ OpenVPN 客戶端已準備就緒${NC}"
    echo -e "${BLUE}Linux 用戶可以使用以下命令連接 VPN：${NC}"
    echo -e "${YELLOW}sudo openvpn --config $config_dir/${USERNAME}-config.ovpn${NC}"
}

# 顯示連接指示
show_connection_instructions() {
    # 載入配置
    source "$USER_CONFIG_FILE"
    
    echo -e "\\n${GREEN}=============================================${NC}"
    echo -e "${GREEN}       AWS Client VPN 設置完成！      ${NC}"
    echo -e "${GREEN}=============================================${NC}"
    echo -e ""
    echo -e "${CYAN}環境資訊：${NC}"
    echo -e "  目標環境: $(get_env_display_name "$TARGET_ENVIRONMENT")"
    echo -e "  AWS Profile: ${AWS_PROFILE}"
    echo -e "  AWS Region: ${AWS_REGION}"
    echo -e "  用戶名稱: ${USERNAME}"
    echo -e "  配置文件: ${USER_VPN_CONFIG_DIR}/${USERNAME}-config.ovpn"
    echo -e ""
    
    local os_type=$(uname -s)
    case "$os_type" in
        "Darwin")
            show_macos_instructions
            ;;
        "Linux")
            show_linux_instructions
            ;;
        *)
            show_generic_instructions
            ;;
    esac
    
    echo -e ""
    echo -e "${CYAN}測試連接：${NC}"
    echo -e "連接成功後，嘗試 ping $(get_env_display_name "$TARGET_ENVIRONMENT")中的某個私有 IP："
    echo -e "  ${YELLOW}ping 10.0.x.x${NC}  # 請向管理員詢問測試 IP"
    echo -e ""
    echo -e "${CYAN}故障排除：${NC}"
    echo -e "如果連接失敗，請："
    echo -e "${BLUE}1.${NC} 檢查您的網路連接"
    echo -e "${BLUE}2.${NC} 確認配置文件路徑正確"
    echo -e "${BLUE}3.${NC} 聯繫管理員檢查授權設置"
    echo -e "${BLUE}4.${NC} 查看 VPN 客戶端的連接日誌"
    echo -e ""
    echo -e "${CYAN}重要提醒：${NC}"
    echo -e "${RED}•${NC} 僅在需要時連接 VPN"
    echo -e "${RED}•${NC} 使用完畢後請立即斷開連接"
    echo -e "${RED}•${NC} 請勿分享您的配置文件或證書"
    echo -e "${RED}•${NC} 如有問題請聯繫 IT 管理員"
    echo -e ""
    echo -e "${GREEN}設置完成！祝您除錯順利！${NC}"
}

# macOS 連接指示
show_macos_instructions() {
    echo -e "${CYAN}macOS 連接說明：${NC}"
    echo -e "${BLUE}1.${NC} 開啟 AWS VPN 客戶端 (在應用程式文件夾中)"
    echo -e "${BLUE}2.${NC} 點擊「檔案」>「管理設定檔」"
    echo -e "${BLUE}3.${NC} 點擊「添加設定檔」"
    echo -e "${BLUE}4.${NC} 選擇您的配置文件：${YELLOW}$USER_VPN_CONFIG_DIR/${USERNAME}-config.ovpn${NC}"
    echo -e "${BLUE}5.${NC} 輸入設定檔名稱：${YELLOW}$(get_env_display_name "$TARGET_ENVIRONMENT") VPN - ${USERNAME}${NC}"
    echo -e "${BLUE}6.${NC} 點擊「添加設定檔」完成添加"
    echo -e "${BLUE}7.${NC} 選擇剛添加的設定檔並點擊「連接」"
}

# Linux 連接指示
show_linux_instructions() {
    echo -e "${CYAN}Linux 連接說明：${NC}"
    echo -e "${BLUE}使用 OpenVPN 命令連接：${NC}"
    echo -e "${YELLOW}sudo openvpn --config $USER_VPN_CONFIG_DIR/${USERNAME}-config.ovpn${NC}"
    echo -e ""
    echo -e "${BLUE}或使用 NetworkManager (如果可用)：${NC}"
    echo -e "${YELLOW}sudo nmcli connection import type openvpn file $USER_VPN_CONFIG_DIR/${USERNAME}-config.ovpn${NC}"
    echo -e "${YELLOW}nmcli connection up '$(get_env_display_name "$TARGET_ENVIRONMENT") VPN - ${USERNAME}'${NC}"
}

# 通用連接指示
show_generic_instructions() {
    echo -e "${CYAN}通用連接說明：${NC}"
    echo -e "${BLUE}1.${NC} 安裝相容的 OpenVPN 客戶端"
    echo -e "${BLUE}2.${NC} 導入配置文件：${YELLOW}$USER_VPN_CONFIG_DIR/${USERNAME}-config.ovpn${NC}"
    echo -e "${BLUE}3.${NC} 使用設定檔名稱：${YELLOW}$(get_env_display_name "$TARGET_ENVIRONMENT") VPN - ${USERNAME}${NC}"
    echo -e "${BLUE}4.${NC} 連接到 VPN"
}

# 清理和測試函數
test_connection() {
    local test_choice
    if read_secure_input "是否要進行連接測試？(需要先手動連接 VPN) (y/n): " test_choice "validate_yes_no"; then
        if [[ "$test_choice" =~ ^[Yy]$ ]]; then
            echo -e "${BLUE}請先使用 AWS VPN 客戶端連接，然後按任意鍵繼續測試...${NC}"
            press_any_key_to_continue
            
            echo -e "${BLUE}測試 VPN 連接...${NC}"
            
            # 檢查 VPN 介面
            local vpn_interface
            vpn_interface=$(ifconfig | grep -E "utun|tun" | head -1 | cut -d: -f1)
            
            if [ -n "$vpn_interface" ]; then
                echo -e "${GREEN}✓ 檢測到 VPN 介面: $vpn_interface${NC}"
                
                # 嘗試 ping VPN 閘道
                local vpn_gateway
                vpn_gateway=$(route -n get default | grep "gateway" | awk '{print $2}' 2>/dev/null)
                if [ -n "$vpn_gateway" ]; then
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
    else
        echo -e "${BLUE}跳過連接測試${NC}"
    fi
}

# 主函數
main() {
    # 記錄操作開始
    if [ -n "$LOG_FILE" ]; then
        log_team_setup_message "開始團隊成員 VPN 設定"
    fi
    
    # 根據模式執行不同的工作流程
    if [ "$INIT_MODE" = true ]; then
        # 零接觸初始化模式
        show_welcome
        check_team_prerequisites
        zero_touch_init_mode
    elif [ "$RESUME_MODE" = true ]; then
        # 零接觸恢復模式
        show_welcome
        check_team_prerequisites
        zero_touch_resume_mode
    elif [ "$RESUME_CERT_MODE" = true ]; then
        # 傳統恢復模式（向後相容）
        show_welcome
        check_team_prerequisites
        init_environment_and_aws
        setup_ca_cert_and_environment
        setup_vpn_endpoint_info
        setup_user_info
        generate_client_certificate
        import_certificate
        setup_vpn_client
        show_connection_instructions
        test_connection
    else
        # 傳統完整模式（向後相容）
        show_welcome
        check_team_prerequisites
        init_environment_and_aws
        setup_ca_cert_and_environment
        setup_vpn_endpoint_info
        setup_user_info
        generate_client_certificate
        import_certificate
        setup_vpn_client
        show_connection_instructions
        test_connection
    fi
    
    if [ -n "$LOG_FILE" ]; then
        log_team_setup_message "團隊成員 VPN 設定完成"
    fi
}

# 解析命令行參數
parse_arguments() {
    RESUME_CERT_MODE=false
    INIT_MODE=false
    RESUME_MODE=false
    S3_BUCKET="vpn-csr-exchange"
    DISABLE_S3=false
    CA_PATH=""
    ENDPOINT_ID=""
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            --init)
                INIT_MODE=true
                shift
                ;;
            --resume)
                RESUME_MODE=true
                shift
                ;;
            --resume-cert)
                RESUME_CERT_MODE=true
                shift
                ;;
            --bucket)
                S3_BUCKET="$2"
                shift 2
                ;;
            --no-s3)
                DISABLE_S3=true
                shift
                ;;
            --ca-path)
                CA_PATH="$2"
                shift 2
                ;;
            --endpoint-id)
                ENDPOINT_ID="$2"
                shift 2
                ;;
            -h|--help)
                show_usage
                exit 0
                ;;
            *)
                echo -e "${RED}未知參數: $1${NC}"
                show_usage
                exit 1
                ;;
        esac
    done
    
    # 檢查互斥模式
    local mode_count=0
    [ "$INIT_MODE" = true ] && ((mode_count++))
    [ "$RESUME_MODE" = true ] && ((mode_count++))
    [ "$RESUME_CERT_MODE" = true ] && ((mode_count++))
    
    if [ $mode_count -gt 1 ]; then
        echo -e "${RED}錯誤: 不能同時使用多個模式${NC}"
        show_usage
        exit 1
    fi
    
    # 如果沒有指定模式，預設為 init 模式（零接觸工作流程）
    if [ $mode_count -eq 0 ]; then
        INIT_MODE=true
    fi
}

# 顯示使用說明
show_usage() {
    echo "用法: $0 [選項]"
    echo ""
    echo "工作模式:"
    echo "  --init           初始化模式：從 S3 下載配置，生成 CSR 並上傳 (預設)"
    echo "  --resume         恢復模式：從 S3 下載簽署證書並完成 VPN 設定"
    echo "  --resume-cert    舊版恢復模式：使用本地證書繼續設定 (向後相容)"
    echo ""
    echo "S3 配置選項:"
    echo "  --bucket NAME    使用指定的 S3 存儲桶 (預設: vpn-csr-exchange)"
    echo "  --no-s3          停用 S3 整合，使用本地檔案"
    echo ""
    echo "覆蓋選項 (用於測試和特殊情況):"
    echo "  --ca-path PATH   使用指定的 CA 證書文件，而非從 S3 下載"
    echo "  --endpoint-id ID 使用指定的端點 ID，而非從 S3 下載的配置"
    echo ""
    echo "其他選項:"
    echo "  -h, --help       顯示此幫助訊息"
    echo ""
    echo "使用範例:"
    echo "  $0               # 零接觸初始化 (從 S3 獲取配置)"
    echo "  $0 --init        # 明確指定初始化模式"
    echo "  $0 --resume      # 恢復模式 (管理員簽署證書後)"
    echo "  $0 --no-s3       # 停用 S3，使用傳統本地檔案模式"
    echo "  $0 --bucket my-bucket --init  # 使用自定義 S3 存儲桶"
    echo ""
    echo "工作流程:"
    echo "  1. 執行 '$0 --init' 生成 CSR 並上傳到 S3"
    echo "  2. 等待管理員簽署證書"
    echo "  3. 執行 '$0 --resume' 下載證書並完成設定"
}

# 只有在腳本直接執行時才執行主程序（不是被 source 時）
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    parse_arguments "$@"
    main
fi