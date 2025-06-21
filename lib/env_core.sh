#!/bin/bash

# Environment Core Library for Team Member Operations
# 輕量級環境管理，專為團隊成員設計，避免暴露敏感配置資訊

# 顏色定義
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# 環境映射函數（相容舊版 bash）
get_env_display_name() {
    local environment="$1"
    local config_file="$PROJECT_ROOT/configs/$environment/$environment.env"
    
    # Try to read from config file first
    if [ -f "$config_file" ]; then
        local display_name
        display_name=$(grep "^ENV_DISPLAY_NAME=" "$config_file" 2>/dev/null | cut -d'=' -f2 | tr -d '"' | tr -d "'")
        if [ -n "$display_name" ]; then
            echo "$display_name"
            return 0
        fi
    fi
    
    # Fallback to generic name if config not found
    echo "Environment: $environment"
}

get_env_aws_profile() {
    local environment="$1"
    local config_file="$PROJECT_ROOT/configs/$environment/$environment.env"
    
    # Try to read from config file first
    if [ -f "$config_file" ]; then
        local aws_profile
        # Check ENV_AWS_PROFILE first (preferred)
        aws_profile=$(grep "^ENV_AWS_PROFILE=" "$config_file" 2>/dev/null | cut -d'=' -f2 | tr -d '"' | tr -d "'")
        if [ -n "$aws_profile" ]; then
            echo "$aws_profile"
            return 0
        fi
        
        # Fallback to AWS_PROFILE
        aws_profile=$(grep "^AWS_PROFILE=" "$config_file" 2>/dev/null | cut -d'=' -f2 | tr -d '"' | tr -d "'")
        if [ -n "$aws_profile" ]; then
            echo "$aws_profile"
            return 0
        fi
    fi
    
    # Fallback to 'default' if nothing found
    echo "default"
}

# AWS Profile 檢測功能
detect_available_aws_profiles() {
    echo -e "${BLUE}檢測可用的 AWS profiles...${NC}"
    
    # 檢查 AWS CLI 是否已安裝
    if ! command -v aws &> /dev/null; then
        echo -e "${RED}AWS CLI 未安裝${NC}"
        return 1
    fi
    
    # 列出所有 profiles
    local profiles
    profiles=$(aws configure list-profiles 2>/dev/null)
    
    if [ -z "$profiles" ]; then
        echo -e "${YELLOW}未找到任何 AWS profiles${NC}"
        return 1
    fi
    
    printf "${GREEN}找到以下 AWS profiles:${NC}\n"
    while IFS= read -r profile; do
        # 檢查每個 profile 是否有效
        if aws sts get-caller-identity --profile "$profile" &>/dev/null; then
            printf "  ${GREEN}✓${NC} %s (有效)\n" "$profile"
        else
            printf "  ${YELLOW}⚠${NC} %s (無效或需要重新配置)\n" "$profile"
        fi
    done <<< "$profiles"
    
    return 0
}

# 根據 AWS profile 推測環境
detect_environment_from_profile() {
    local selected_profile="$1"
    
    # 根據 profile 名稱推測環境
    case "$selected_profile" in
        *prod*|*production*)
            echo "production"
            ;;
        *stg*|*staging*|default)
            echo "staging"
            ;;
        *)
            echo "unknown"
            ;;
    esac
}

# 從 CA 證書路徑或內容判斷環境
detect_environment_from_ca_cert() {
    local ca_cert_path="$1"
    
    if [ ! -f "$ca_cert_path" ]; then
        echo "unknown"
        return 1
    fi
    
    # 從檔案路徑判斷
    if [[ "$ca_cert_path" == *"staging"* ]] || [[ "$ca_cert_path" == *"stg"* ]]; then
        echo "staging"
        return 0
    elif [[ "$ca_cert_path" == *"production"* ]] || [[ "$ca_cert_path" == *"prod"* ]]; then
        echo "production"
        return 0
    fi
    
    # 從證書內容判斷（檢查 CN 或 O 欄位）
    local cert_subject
    cert_subject=$(openssl x509 -in "$ca_cert_path" -noout -subject 2>/dev/null)
    
    if [[ "$cert_subject" == *"staging"* ]] || [[ "$cert_subject" == *"Staging"* ]]; then
        echo "staging"
        return 0
    elif [[ "$cert_subject" == *"production"* ]] || [[ "$cert_subject" == *"Production"* ]]; then
        echo "production"
        return 0
    fi
    
    # 無法判斷
    echo "unknown"
    return 1
}

# 環境確認對話
confirm_environment_selection() {
    local detected_env="$1"
    local ca_cert_path="$2"
    local selected_profile="$3"
    
    echo -e "\n${CYAN}========== 環境確認 ==========${NC}" >&2
    echo -e "基於以下資訊：" >&2
    echo -e "  AWS Profile: ${BLUE}$selected_profile${NC}" >&2
    echo -e "  CA 證書路徑: ${BLUE}$ca_cert_path${NC}" >&2
    
    if [ "$detected_env" != "unknown" ]; then
        echo -e "  偵測到環境: $(get_env_display_name "$detected_env")" >&2
        echo -e "" >&2
        
        local confirm
        read -p "確認使用此環境？(y/n): " confirm
        if [[ "$confirm" =~ ^[Yy]$ ]]; then
            echo "$detected_env"
            return 0
        fi
    fi
    
    # 手動選擇環境
    echo -e "\n${YELLOW}請手動選擇目標環境：${NC}" >&2
    echo "1) staging - $(get_env_display_name "staging")" >&2
    echo "2) production - $(get_env_display_name "production")" >&2
    
    local choice
    while true; do
        read -p "請選擇 (1/2): " choice
        case $choice in
            1)
                echo "staging"
                return 0
                ;;
            2)
                echo "production"
                return 0
                ;;
            *)
                echo -e "${RED}請選擇 1 或 2${NC}" >&2
                ;;
        esac
    done
}

# 設定環境特定路徑（簡化版）
setup_team_member_paths() {
    local environment="$1"
    local script_dir="$2"
    
    # 設定基本路徑
    export CURRENT_ENVIRONMENT="$environment"
    export ENV_DISPLAY_NAME="$(get_env_display_name "$environment")"
    
    # 設定團隊成員專用路徑
    export USER_CERT_DIR="$script_dir/certs/$environment/users"
    export USER_VPN_CONFIG_DIR="$script_dir/configs/$environment/users"
    export USER_VPN_CONFIG_FILE="$script_dir/configs/$environment/user_vpn_config.env"
    export TEAM_SETUP_LOG_FILE="$script_dir/logs/$environment/team_setup.log"
    
    # 創建必要目錄
    mkdir -p "$USER_CERT_DIR" "$USER_VPN_CONFIG_DIR" "$(dirname "$USER_VPN_CONFIG_FILE")" "$(dirname "$TEAM_SETUP_LOG_FILE")"
    
    # 設定權限
    chmod 700 "$USER_CERT_DIR" "$USER_VPN_CONFIG_DIR"
}

# 顯示環境感知標頭
show_team_env_header() {
    local title="$1"
    
    echo -e "${CYAN}================================================${NC}"
    echo -e "${CYAN}${title}${NC}"
    if [ -n "$ENV_DISPLAY_NAME" ]; then
        echo -e "${CYAN}目標環境: $ENV_DISPLAY_NAME${NC}"
    fi
    echo -e "${CYAN}================================================${NC}"
}

# =======================================
# Enhanced Profile Management Functions
# =======================================

# Map environment to suggested profile names
map_environment_to_profiles() {
    local environment="$1"
    local config_file="$PROJECT_ROOT/configs/$environment/$environment.env"
    
    # Try to read from config file first
    if [ -f "$config_file" ]; then
        local suggested_profiles
        suggested_profiles=$(grep "^SUGGESTED_AWS_PROFILES=" "$config_file" 2>/dev/null | cut -d'=' -f2 | tr -d '"' | tr -d "'")
        if [ -n "$suggested_profiles" ]; then
            echo "$suggested_profiles"
            return 0
        fi
    fi
    
    # Fallback to intelligent defaults based on environment name
    case "$environment" in
        staging|stg)
            echo "default staging stage"
            ;;
        production|prod|prd)
            echo "production prod prd"
            ;;
        dev|development)
            echo "dev development default"
            ;;
        test|testing)
            echo "test testing default"
            ;;
        *)
            # Generic fallback - suggest environment name and common variants
            echo "$environment default"
            ;;
    esac
}

# Get environment-specific profile preference
get_env_profile() {
    local environment="$1"
    local config_file="$PROJECT_ROOT/configs/$environment/$environment.env"
    
    # Try to load from config file first
    if [ -f "$config_file" ]; then
        local env_profile
        env_profile=$(grep "^ENV_AWS_PROFILE=" "$config_file" 2>/dev/null | cut -d'=' -f2 | tr -d '"' | tr -d "'")
        if [ -n "$env_profile" ]; then
            echo "$env_profile"
            return 0
        fi
        
        env_profile=$(grep "^AWS_PROFILE=" "$config_file" 2>/dev/null | cut -d'=' -f2 | tr -d '"' | tr -d "'")
        if [ -n "$env_profile" ]; then
            echo "$env_profile"
            return 0
        fi
    fi
    
    # Fallback to default mapping
    case "$environment" in
        staging)
            echo "default"
            ;;
        production)
            echo "production"
            ;;
        prod)
            echo "prod"
            ;;
        *)
            echo "default"
            ;;
    esac
}

# Get default profile for environment
get_env_default_profile() {
    local environment="$1"
    
    # Use the same logic as get_env_aws_profile since they serve the same purpose
    get_env_aws_profile "$environment"
}

# Validate profile matches environment account
validate_profile_matches_environment() {
    local profile="$1"
    local environment="$2"
    
    # Get account ID from profile
    local account_id
    account_id=$(aws sts get-caller-identity --profile "$profile" --query Account --output text 2>/dev/null)
    
    if [ -z "$account_id" ] || [ "$account_id" = "None" ]; then
        echo -e "${RED}無法取得 AWS 帳戶 ID，profile: $profile${NC}" >&2
        return 1
    fi
    
    # Load expected account ID from config if available
    local config_file="$PROJECT_ROOT/configs/$environment/$environment.env"
    local expected_account_var=""
    case "$environment" in
        staging) expected_account_var="STAGING_ACCOUNT_ID" ;;
        production) expected_account_var="PRODUCTION_ACCOUNT_ID" ;;
        prod) expected_account_var="PROD_ACCOUNT_ID" ;;
        *) expected_account_var="" ;;
    esac
    local expected_account=""
    
    if [ -f "$config_file" ]; then
        expected_account=$(grep "^${expected_account_var}=" "$config_file" 2>/dev/null | cut -d'=' -f2 | tr -d '"' | tr -d "'")
    fi
    
    # If we have expected account ID, validate it
    if [ -n "$expected_account" ]; then
        if [ "$account_id" != "$expected_account" ]; then
            echo -e "${RED}帳戶 ID 不匹配 - Profile '$profile' 屬於帳戶 $account_id，但 $environment 環境期望帳戶 $expected_account${NC}" >&2
            return 1
        fi
        echo -e "${GREEN}✓ Profile '$profile' 帳戶驗證通過 ($environment 環境)${NC}"
    else
        echo -e "${YELLOW}⚠ 無法驗證帳戶 ID - 環境配置中未設定 ${expected_account_var}${NC}" >&2
    fi
    
    return 0
}

# Select AWS profile for environment with smart detection
select_aws_profile_for_environment() {
    local environment="$1"
    local force_selection="${2:-false}"
    
    echo -e "${BLUE}為 $environment 環境選擇 AWS Profile...${NC}"
    
    # Check if already configured and not forcing selection
    if [ "$force_selection" != "true" ]; then
        local existing_profile
        existing_profile=$(get_env_profile "$environment")
        if [ -n "$existing_profile" ] && aws configure list-profiles | grep -q "^$existing_profile$"; then
            if validate_aws_profile_config "$existing_profile"; then
                echo -e "${GREEN}使用已配置的 profile: $existing_profile${NC}"
                echo "$existing_profile"
                return 0
            fi
        fi
    fi
    
    # Get available profiles
    local available_profiles
    available_profiles=$(aws configure list-profiles 2>/dev/null)
    
    if [ -z "$available_profiles" ]; then
        echo -e "${RED}未找到任何 AWS profiles${NC}"
        return 1
    fi
    
    # Get suggested profiles for environment
    local suggested_profiles
    suggested_profiles=$(map_environment_to_profiles "$environment")
    
    # Find matching profiles
    local matching_profiles=()
    local other_profiles=()
    
    while IFS= read -r profile; do
        if echo "$suggested_profiles" | grep -q "$profile"; then
            matching_profiles+=("$profile")
        else
            other_profiles+=("$profile")
        fi
    done <<< "$available_profiles"
    
    # Display options
    echo -e "\n${CYAN}可用的 AWS Profiles:${NC}"
    local i=1
    local profile_array=()
    
    # Show matching profiles first
    if [ ${#matching_profiles[@]} -gt 0 ]; then
        echo -e "${GREEN}推薦用於 $environment 環境:${NC}"
        for profile in "${matching_profiles[@]}"; do
            if aws sts get-caller-identity --profile "$profile" &>/dev/null; then
                echo -e "  $i) $profile ${GREEN}(有效, 推薦)${NC}"
                profile_array+=("$profile")
                ((i++))
            fi
        done
    fi
    
    # Show other profiles
    if [ ${#other_profiles[@]} -gt 0 ]; then
        echo -e "${YELLOW}其他可用 profiles:${NC}"
        for profile in "${other_profiles[@]}"; do
            if aws sts get-caller-identity --profile "$profile" &>/dev/null; then
                echo -e "  $i) $profile ${BLUE}(有效)${NC}"
                profile_array+=("$profile")
                ((i++))
            else
                echo -e "  $i) $profile ${RED}(需要重新配置)${NC}"
                profile_array+=("$profile")
                ((i++))
            fi
        done
    fi
    
    # User selection
    local choice
    local max_choice=${#profile_array[@]}
    
    if [ $max_choice -eq 0 ]; then
        echo -e "${RED}沒有可用的 AWS profiles${NC}"
        return 1
    fi
    
    while true; do
        read -p "請選擇 AWS profile (1-$max_choice): " choice
        if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "$max_choice" ]; then
            local selected_profile="${profile_array[$((choice-1))]}"
            
            # Validate selected profile
            if validate_aws_profile_config "$selected_profile"; then
                # Cross-account validation if possible
                validate_profile_matches_environment "$selected_profile" "$environment" || true
                echo "$selected_profile"
                return 0
            else
                echo -e "${RED}選擇的 profile 無效，請重新選擇${NC}"
            fi
        else
            echo -e "${RED}請輸入有效的數字 (1-$max_choice)${NC}"
        fi
    done
}

# Load profile from config file
load_profile_from_config() {
    local environment="$1"
    local config_file="$PROJECT_ROOT/configs/$environment/$environment.env"
    
    if [ ! -f "$config_file" ]; then
        return 1
    fi
    
    # Load environment-specific profile first
    local env_profile
    env_profile=$(grep "^ENV_AWS_PROFILE=" "$config_file" 2>/dev/null | cut -d'=' -f2 | tr -d '"' | tr -d "'")
    
    if [ -n "$env_profile" ]; then
        export AWS_PROFILE="$env_profile"
        export ENV_AWS_PROFILE="$env_profile"
        return 0
    fi
    
    # Fallback to AWS_PROFILE
    local aws_profile
    aws_profile=$(grep "^AWS_PROFILE=" "$config_file" 2>/dev/null | cut -d'=' -f2 | tr -d '"' | tr -d "'")
    
    if [ -n "$aws_profile" ]; then
        export AWS_PROFILE="$aws_profile"
        return 0
    fi
    
    return 1
}

# Save profile to config file
save_profile_to_config() {
    local environment="$1"
    local profile="$2"
    local config_file="$PROJECT_ROOT/configs/$environment/$environment.env"
    
    # Ensure config directory exists
    mkdir -p "$PROJECT_ROOT/configs/$environment"
    
    # Update or add AWS_PROFILE
    if [ -f "$config_file" ]; then
        # Use sed to update existing entry or add new one
        if grep -q "^AWS_PROFILE=" "$config_file"; then
            sed -i.bak "s/^AWS_PROFILE=.*/AWS_PROFILE=\"$profile\"/" "$config_file"
        else
            echo "AWS_PROFILE=\"$profile\"" >> "$config_file"
        fi
        
        if grep -q "^ENV_AWS_PROFILE=" "$config_file"; then
            sed -i.bak "s/^ENV_AWS_PROFILE=.*/ENV_AWS_PROFILE=\"$profile\"/" "$config_file"
        else
            echo "ENV_AWS_PROFILE=\"$profile\"" >> "$config_file"
        fi
        
        # Remove backup file
        rm -f "$config_file.bak"
    else
        # Create new config file
        cat > "$config_file" << EOF
# AWS Profile Configuration for $environment environment
AWS_PROFILE="$profile"
ENV_AWS_PROFILE="$profile"
EOF
    fi
    
    chmod 600 "$config_file"
    echo -e "${GREEN}已保存 AWS Profile '$profile' 到 $environment 環境配置${NC}"
    return 0
}

# Enhanced AWS profile validation
validate_aws_profile_config() {
    local profile="$1"
    local environment="${2:-}"
    
    echo -e "${BLUE}驗證 AWS profile '$profile' 配置...${NC}"
    
    # Check if profile exists
    if ! aws configure list-profiles | grep -q "^$profile$"; then
        echo -e "${RED}AWS profile '$profile' 不存在${NC}"
        return 1
    fi
    
    # Check authentication
    if ! aws sts get-caller-identity --profile "$profile" &>/dev/null; then
        echo -e "${RED}AWS profile '$profile' 無法通過身份驗證${NC}"
        echo -e "${YELLOW}請檢查 Access Key 和 Secret Key 是否正確${NC}"
        return 1
    fi
    
    # Get configuration information
    local region output account_id
    region=$(aws configure get region --profile "$profile" 2>/dev/null)
    output=$(aws configure get output --profile "$profile" 2>/dev/null)
    account_id=$(aws sts get-caller-identity --profile "$profile" --query Account --output text 2>/dev/null)
    
    echo -e "${GREEN}✓ AWS profile '$profile' 配置有效${NC}"
    echo -e "  帳戶 ID: ${account_id:-未知}"
    echo -e "  區域: ${region:-預設}"
    echo -e "  輸出格式: ${output:-預設}"
    
    # Environment-specific validation if provided
    if [ -n "$environment" ]; then
        validate_profile_matches_environment "$profile" "$environment"
    fi
    
    return 0
}

# 初始化團隊成員環境（簡化版）
init_team_member_environment() {
    local script_name="$1"
    local script_dir="$2"
    
    echo -e "${BLUE}初始化團隊成員環境設定...${NC}"
    
    # 檢測可用 AWS profiles
    if ! detect_available_aws_profiles; then
        echo -e "${RED}無法檢測 AWS profiles，請先配置 AWS CLI${NC}"
        return 1
    fi
    
    echo -e "\n${YELLOW}請選擇要使用的 AWS profile：${NC}"
    
    # 列出 profiles 供選擇
    local profiles
    profiles=$(aws configure list-profiles 2>/dev/null)
    
    if [ -z "$profiles" ]; then
        echo -e "${RED}未找到任何 AWS profiles${NC}"
        return 1
    fi
    
    # 將 profiles 轉換為帶編號的列表
    local i=1
    local profile_list=""
    while IFS= read -r profile; do
        # 檢查 profile 狀態
        if aws sts get-caller-identity --profile "$profile" &>/dev/null; then
            printf "%d) %s ${GREEN}(有效)${NC}\n" "$i" "$profile"
        else
            printf "%d) %s ${YELLOW}(需要重新配置)${NC}\n" "$i" "$profile"
        fi
        
        # 將 profile 加入列表
        if [ "$i" -eq 1 ]; then
            profile_list="$profile"
        else
            profile_list="$profile_list|$profile"
        fi
        ((i++))
    done <<< "$profiles"
    
    # 用戶選擇 profile
    local choice
    local max_choice=$((i-1))
    while true; do
        read -p "請選擇 AWS profile (1-$max_choice): " choice
        if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "$max_choice" ]; then
            # 從列表中取得選中的 profile
            export SELECTED_AWS_PROFILE=$(echo "$profile_list" | cut -d'|' -f"$choice")
            break
        else
            printf "${RED}請輸入有效的數字 (1-%d)${NC}\n" "$max_choice"
        fi
    done
    
    # 驗證選中的 profile
    if ! validate_aws_profile_config "$SELECTED_AWS_PROFILE"; then
        return 1
    fi
    
    # 偵測環境
    local detected_env
    detected_env=$(detect_environment_from_profile "$SELECTED_AWS_PROFILE")
    
    local env_name="未知"
    if [ "$detected_env" != "unknown" ]; then
        env_name="$(get_env_display_name "$detected_env")"
    fi
    echo -e "\n${BLUE}根據 AWS profile '$SELECTED_AWS_PROFILE' 推測環境: $env_name${NC}"
    
    return 0
}