#!/bin/bash

# AWS Client VPN 團隊成員設定腳本 for macOS
# 用途：允許團隊成員連接到已存在的 AWS Client VPN 端點
# 版本：1.2 (環境感知版本)

# 全域變數
TEAM_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 載入環境管理器 (必須第一個載入)
source "$TEAM_SCRIPT_DIR/lib/env_manager.sh"

# 初始化環境
if ! env_init_for_script "team_member_setup.sh"; then
    echo -e "${RED}錯誤: 無法初始化環境管理器${NC}"
    exit 1
fi

# 設定環境特定路徑
env_setup_paths

# 環境感知的配置檔案
USER_CONFIG_FILE="$USER_VPN_CONFIG_FILE"
LOG_FILE="$TEAM_SETUP_LOG_FILE"

# 載入核心函式庫
source "$TEAM_SCRIPT_DIR/lib/core_functions.sh"

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
    show_env_aware_header "AWS Client VPN 團隊成員設定工具"
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

# 設定 AWS 配置
setup_aws_config() {
    echo -e "\\n${YELLOW}[2/6] 設定 AWS 配置...${NC}"
    
    # 檢查現有配置
    local existing_config=false
    local use_existing_config=false
    local aws_region=""
    
    if [ -f ~/.aws/credentials ] && [ -f ~/.aws/config ]; then
        existing_config=true
        echo -e "${BLUE}📋 檢測到現有的 AWS 配置檔案${NC}"
        echo -e "${BLUE}═══════════════════════════════════════${NC}"
        
        # 顯示配置檔案位置
        echo -e "配置檔案位置:"
        echo -e "  • ~/.aws/credentials"
        echo -e "  • ~/.aws/config"
        
        # 檢查是否可以使用現有配置
        echo -e "\n${BLUE}正在驗證現有配置...${NC}"
        if aws sts get-caller-identity > /dev/null 2>&1; then
            echo -e "${GREEN}✅ 現有 AWS 配置可正常使用${NC}"
            
            # 顯示當前配置詳細資訊
            local current_region current_output current_identity
            current_region=$(aws configure get region 2>/dev/null || echo "")
            current_output=$(aws configure get output 2>/dev/null || echo "")
            current_identity=$(aws sts get-caller-identity 2>/dev/null || echo "")
            
            echo -e "\n${BLUE}📊 當前 AWS 配置詳細資訊:${NC}"
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
                echo -e "  ${GREEN}Y${NC} - 使用現有配置 (推薦，如果這是您要使用的 AWS 帳號)"
                echo -e "      → 將使用上述顯示的 AWS 配置進行 VPN 設定"
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
                        echo -e "${GREEN}✅ 將使用現有的 AWS 配置${NC}"
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
    
    local endpoint_id
    if ! read_secure_input "請輸入 Client VPN 端點 ID: " endpoint_id "validate_endpoint_id"; then
        echo -e "${RED}VPN 端點 ID 驗證失敗${NC}"
        log_team_setup_message "VPN 端點 ID 驗證失敗"
        return 1
    fi
    
    # 驗證端點 ID
    echo -e "${BLUE}驗證 VPN 端點...${NC}"
    local endpoint_check
    endpoint_check=$(aws ec2 describe-client-vpn-endpoints --client-vpn-endpoint-ids "$endpoint_id" --region "$aws_region" 2>/dev/null || echo "not_found")
    
    if [[ "$endpoint_check" == "not_found" ]]; then
        echo -e "${RED}無法找到指定的 VPN 端點。請確認 ID 是否正確，以及您是否有權限訪問。${NC}"
        log_team_setup_message "VPN 端點驗證失敗: $endpoint_id"
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
    local original_dir="$PWD"  # 記錄原始目錄
    echo -e "\\n${YELLOW}[4/6] 生成個人 VPN 客戶端證書...${NC}"
    
    # 載入配置
    if ! source "$USER_CONFIG_FILE"; then
        echo -e "${RED}載入配置文件失敗${NC}"
        log_team_setup_message "載入配置文件失敗"
        cd "$original_dir" || {
            echo -e "${RED}警告: 無法恢復到原始目錄${NC}"
        }
        return 1
    fi
    
    # 檢查 USERNAME 是否已設定
    if [ -z "$USERNAME" ]; then
        echo -e "${RED}用戶名未設定，請先完成用戶資訊設定${NC}"
        cd "$original_dir" || {
            echo -e "${RED}警告: 無法恢復到原始目錄${NC}"
        }
        return 1
    fi
    
    # 檢查 CA 證書
    echo -e "${YELLOW}檢查 CA 證書文件...${NC}"
    
    local ca_cert_path=""
    
    # 優先檢查環境特定的 CA 證書路徑
    if [ -f "$VPN_CA_CERT_FILE" ]; then
        ca_cert_path="$VPN_CA_CERT_FILE"
    elif [ -f "$VPN_CERT_DIR/ca.crt" ]; then
        ca_cert_path="$VPN_CERT_DIR/ca.crt"
    else
        echo -e "${YELLOW}未找到 CA 證書文件。${NC}"
        if read_secure_input "請輸入 CA 證書文件的完整路徑: " ca_cert_path "validate_file_path"; then
            if [ ! -f "$ca_cert_path" ]; then
                echo -e "${RED}指定的 CA 證書文件不存在${NC}"
                cd "$original_dir" || {
                    echo -e "${RED}警告: 無法恢復到原始目錄${NC}"
                }
                return 1
            fi
        else
            echo -e "${RED}必須提供有效的 CA 證書文件路徑${NC}"
            cd "$original_dir" || {
                echo -e "${RED}警告: 無法恢復到原始目錄${NC}"
            }
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
        if read_secure_input "請輸入 CA 私鑰文件的完整路徑 (或按 Enter 跳過自動生成): " ca_key_path "validate_file_path_allow_empty"; then
            if [ -n "$ca_key_path" ] && [ ! -f "$ca_key_path" ]; then
                echo -e "${RED}指定的 CA 私鑰文件不存在${NC}"
                cd "$original_dir" || {
                    echo -e "${RED}警告: 無法恢復到原始目錄${NC}"
                }
                return 1
            fi
        fi
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
    
    # 複製 CA 證書
    if ! cp "$ca_cert_path" ./ca.crt; then
        echo -e "${RED}複製 CA 證書失敗${NC}"
        cd "$original_dir" || {
            echo -e "${RED}警告: 無法恢復到原始目錄${NC}"
        }
        return 1
    fi
    
    if [ -n "$ca_key_path" ]; then
        # 有 CA 私鑰，可以自動生成證書
        echo -e "${BLUE}自動生成客戶端證書...${NC}"
        
        # 檢查是否存在現有證書文件
        if [ -f "${USERNAME}.key" ] || [ -f "${USERNAME}.csr" ]; then
            local overwrite_key
            if read_secure_input "金鑰檔案 ${USERNAME}.key 或 ${USERNAME}.csr 已存在。是否覆蓋? (y/n): " overwrite_key "validate_yes_no"; then
                if [[ "$overwrite_key" =~ ^[Yy]$ ]]; then
                    rm -f "${USERNAME}.key" "${USERNAME}.csr" "${USERNAME}.crt"
                else
                    echo -e "${YELLOW}保留現有金鑰檔案。${NC}"
                    # 確保現有檔案權限正確
                    if [ -f "${USERNAME}.key" ]; then
                        chmod 600 "${USERNAME}.key"
                    fi
                    if [ -f "${USERNAME}.crt" ]; then
                        chmod 600 "${USERNAME}.crt"
                    fi
                    return 0
                fi
            else
                echo -e "${YELLOW}保留現有金鑰檔案。${NC}"
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
        
        # 生成 CSR
        if ! openssl req -new -key "${USERNAME}.key" -out "${USERNAME}.csr" \
          -subj "/CN=${USERNAME}/O=Client/C=TW"; then
            echo -e "${RED}生成 CSR 失敗${NC}"
            cd "$original_dir" || {
                echo -e "${RED}警告: 無法恢復到原始目錄${NC}"
            }
            return 1
        fi
        
        # 簽署證書
        if ! openssl x509 -req -in "${USERNAME}.csr" -CA ./ca.crt -CAkey "$ca_key_path" \
          -CAcreateserial -out "${USERNAME}.crt" -days 365; then
            echo -e "${RED}簽署證書失敗${NC}"
            cd "$original_dir" || {
                echo -e "${RED}警告: 無法恢復到原始目錄${NC}"
            }
            return 1
        fi
        
        # 設置證書文件權限
        chmod 600 "${USERNAME}.crt"
        
        # 清理 CSR 文件
        rm -f "${USERNAME}.csr"
        
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
        if read_secure_input "證書文件已準備好？(y/n): " cert_ready "validate_yes_no"; then
            if [[ ! "$cert_ready" =~ ^[Yy]$ ]]; then
                echo -e "${YELLOW}請準備好證書文件後重新執行腳本${NC}"
                return 1
            fi
        else
            echo -e "${YELLOW}請準備好證書文件後重新執行腳本${NC}"
            exit 0
        fi
        
        # 檢查證書文件是否存在
        if [ ! -f "$cert_dir/${USERNAME}.crt" ] || [ ! -f "$cert_dir/${USERNAME}.key" ]; then
            echo -e "${RED}找不到證書文件。請確認文件位置正確。${NC}"
            cd "$original_dir" || {
                echo -e "${RED}警告: 無法恢復到原始目錄${NC}"
            }
            return 1
        fi
        
        # 設置文件權限
        chmod 600 "$cert_dir/${USERNAME}.crt"
        chmod 600 "$cert_dir/${USERNAME}.key"
    fi
    
    log_team_setup_message "客戶端證書已準備完成"
    
    # 在函數結束前恢復目錄
    cd "$original_dir" || {
        echo -e "${RED}警告: 無法恢復到原始目錄${NC}"
    }
}

# 導入證書到 ACM
import_certificate() {
    echo -e "\\n${YELLOW}[5/6] 導入證書到 AWS Certificate Manager...${NC}"
    
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
    echo -e "\\n${YELLOW}[6/6] 設置 VPN 客戶端...${NC}"
    
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
    
    # 添加 AWS 域名分割 DNS 配置
    echo -e "${BLUE}配置 AWS 域名分割 DNS...${NC}"
    {
        echo ""
        echo "# AWS 域名分割 DNS 配置"
        echo "# 確保 AWS 內部服務域名通過 VPC DNS 解析"
        echo "dhcp-option DNS-priority 1"
        echo "dhcp-option DOMAIN internal"
        echo "dhcp-option DOMAIN $AWS_REGION.compute.internal"
        echo "dhcp-option DOMAIN ec2.internal"
        echo "dhcp-option DOMAIN $AWS_REGION.elb.amazonaws.com"
        echo "dhcp-option DOMAIN $AWS_REGION.rds.amazonaws.com"
        echo "dhcp-option DOMAIN $AWS_REGION.s3.amazonaws.com"
        echo "dhcp-option DOMAIN *.amazonaws.com"
        echo ""
        echo "# 路由配置：將 AWS 服務流量導向 VPN"
        echo "# EC2 metadata service"
        echo "route 169.254.169.254 255.255.255.255"
        echo "# VPC DNS resolver"
        echo "route 169.254.169.253 255.255.255.255"
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
    
    echo -e "${GREEN}VPN 客戶端設置完成！${NC}"
    echo -e "您的配置文件: ${BLUE}$config_dir/${USERNAME}-config.ovpn${NC}"
    
    log_team_setup_message "VPN 客戶端設置完成"
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
    
    # 載入環境配置以獲取環境資訊
    env_load_config "$CURRENT_ENVIRONMENT"
    
    echo -e "\\n${GREEN}=============================================${NC}"
    echo -e "${GREEN}       AWS Client VPN 設置完成！      ${NC}"
    echo -e "${GREEN}=============================================${NC}"
    echo -e ""
    echo -e "${CYAN}環境資訊：${NC}"
    echo -e "  目標環境: ${ENV_ICON} ${ENV_DISPLAY_NAME}"
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
    echo -e "連接成功後，嘗試 ping ${ENV_DISPLAY_NAME}環境中的某個私有 IP："
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
    echo -e "${BLUE}5.${NC} 輸入設定檔名稱：${YELLOW}${ENV_DISPLAY_NAME:-$CURRENT_ENVIRONMENT} VPN - ${USERNAME}${NC}"
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
    echo -e "${YELLOW}nmcli connection up '${ENV_DISPLAY_NAME:-$CURRENT_ENVIRONMENT} VPN - ${USERNAME}'${NC}"
}

# 通用連接指示
show_generic_instructions() {
    echo -e "${CYAN}通用連接說明：${NC}"
    echo -e "${BLUE}1.${NC} 安裝相容的 OpenVPN 客戶端"
    echo -e "${BLUE}2.${NC} 導入配置文件：${YELLOW}$USER_VPN_CONFIG_DIR/${USERNAME}-config.ovpn${NC}"
    echo -e "${BLUE}3.${NC} 使用設定檔名稱：${YELLOW}${ENV_DISPLAY_NAME:-$CURRENT_ENVIRONMENT} VPN - ${USERNAME}${NC}"
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
    # 環境操作驗證
    if ! env_validate_operation "TEAM_MEMBER_SETUP"; then
        return 1
    fi
    
    # 記錄操作開始
    log_env_action "TEAM_MEMBER_SETUP_START" "開始團隊成員 VPN 設定"
    
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
    
    log_env_action "TEAM_MEMBER_SETUP_COMPLETE" "團隊成員 VPN 設定完成"
}

# 記錄腳本啟動
log_team_setup_message "團隊成員 VPN 設置腳本已啟動"

# 只有在腳本直接執行時才執行主程序（不是被 source 時）
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main
fi