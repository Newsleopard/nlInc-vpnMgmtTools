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
    case "$1" in
        "staging") echo "Staging Environment 🟡" ;;
        "production") echo "Production Environment 🔴" ;;
        *) echo "Unknown Environment" ;;
    esac
}

get_env_aws_profile() {
    case "$1" in
        "staging") echo "default" ;;
        "production") echo "prod" ;;
        *) echo "" ;;
    esac
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

# 驗證 AWS 配置
validate_aws_profile_config() {
    local profile="$1"
    
    echo -e "${BLUE}驗證 AWS profile '$profile' 配置...${NC}"
    
    # 檢查 profile 是否存在
    if ! aws configure list-profiles | grep -q "^$profile$"; then
        echo -e "${RED}AWS profile '$profile' 不存在${NC}"
        return 1
    fi
    
    # 檢查是否可以獲取身份資訊
    if ! aws sts get-caller-identity --profile "$profile" &>/dev/null; then
        echo -e "${RED}AWS profile '$profile' 無法通過身份驗證${NC}"
        echo -e "${YELLOW}請檢查 Access Key 和 Secret Key 是否正確${NC}"
        return 1
    fi
    
    # 獲取配置資訊
    local region output
    region=$(aws configure get region --profile "$profile" 2>/dev/null)
    output=$(aws configure get output --profile "$profile" 2>/dev/null)
    
    echo -e "${GREEN}✓ AWS profile '$profile' 配置有效${NC}"
    echo -e "  區域: ${region:-預設}"
    echo -e "  輸出格式: ${output:-預設}"
    
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