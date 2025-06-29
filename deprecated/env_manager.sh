#!/bin/bash

# Environment Manager for nlInc-vpnMgmtTools
# 環境管理器 - 提供雙環境支援的核心功能
# Version: 1.0
# Date: 2025-05-24

# 設定腳本路徑
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
CURRENT_ENV_FILE="$PROJECT_ROOT/.current_env"

# 載入增強確認模組
if [[ -f "$SCRIPT_DIR/enhanced_confirmation.sh" ]]; then
    source "$SCRIPT_DIR/enhanced_confirmation.sh"
else
    echo "警告: 找不到增強確認模組 $SCRIPT_DIR/enhanced_confirmation.sh" >&2
fi

# 顏色定義
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 載入當前環境設定
load_current_env() {
    if [[ -f "$CURRENT_ENV_FILE" ]]; then
        source "$CURRENT_ENV_FILE"
    else
        CURRENT_ENVIRONMENT="staging"
        echo "CURRENT_ENVIRONMENT=staging" > "$CURRENT_ENV_FILE"
        echo "LAST_SWITCHED_TIME=$(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "$CURRENT_ENV_FILE"
        echo "SWITCHED_BY=system" >> "$CURRENT_ENV_FILE"
    fi
}

# 顯示當前環境狀態
env_current() {
    load_current_env
    
    # 載入環境配置以獲取顯示資訊
    local env_file="$PROJECT_ROOT/configs/${CURRENT_ENVIRONMENT}/${CURRENT_ENVIRONMENT}.env"
    if [[ -f "$env_file" ]]; then
        source "$env_file"
        local icon="${ENV_ICON:-⚪}"
        local display_name="${ENV_DISPLAY_NAME:-$CURRENT_ENVIRONMENT}"
        
        echo -e "\n=== 當前 VPN 環境狀態 ==="
        echo -e "環境: ${icon} ${display_name}"
        echo -e "名稱: ${CURRENT_ENVIRONMENT}"
        echo -e "最後切換: ${LAST_SWITCHED_TIME:-未知}"
        echo -e "切換者: ${SWITCHED_BY:-未知}"
        
        # 顯示 AWS Profile 資訊
        local current_profile
        current_profile=$(get_env_profile "$CURRENT_ENVIRONMENT" 2>/dev/null)
        if [[ -n "$current_profile" ]]; then
            echo -e "AWS Profile: ${GREEN}$current_profile${NC}"
            
            # 顯示 AWS 帳戶資訊
            if command -v aws &> /dev/null && aws configure list-profiles | grep -q "^$current_profile$"; then
                local account_id region
                account_id=$(aws sts get-caller-identity --profile "$current_profile" --query Account --output text 2>/dev/null)
                region=$(aws configure get region --profile "$current_profile" 2>/dev/null)
                
                if [[ -n "$account_id" ]]; then
                    echo -e "AWS 帳戶: ${account_id}"
                fi
                if [[ -n "$region" ]]; then
                    echo -e "AWS 區域: ${region}"
                fi
            fi
        else
            echo -e "AWS Profile: ${YELLOW}未設定${NC}"
        fi
        
        # 檢查環境健康狀態
        if env_health_check "${CURRENT_ENVIRONMENT}"; then
            echo -e "狀態: ${GREEN}🟢 健康${NC}"
        else
            echo -e "狀態: ${YELLOW}🟡 警告${NC}"
        fi
        echo "========================"
    else
        echo -e "${RED}錯誤: 找不到環境配置檔案 $env_file${NC}"
        return 1
    fi
}

# 切換環境
env_switch() {
    local target_env="$1"
    
    if [[ -z "$target_env" ]]; then
        echo -e "${RED}錯誤: 請指定目標環境 (staging 或 production)${NC}"
        return 1
    fi
    
    # 驗證目標環境是否存在
    local target_env_file="$PROJECT_ROOT/configs/${target_env}/${target_env}.env"
    if [[ ! -f "$target_env_file" ]]; then
        echo -e "${RED}錯誤: 環境 '$target_env' 不存在${NC}"
        echo "可用環境: staging, production"
        return 1
    fi
    
    load_current_env
    
    # 如果已經是目標環境，直接返回
    if [[ "$CURRENT_ENVIRONMENT" == "$target_env" ]]; then
        echo -e "${YELLOW}已經在 $target_env 環境中${NC}"
        env_current
        return 0
    fi
    
    # 載入目標環境資訊以顯示切換確認
    source "$target_env_file"
    local target_icon="${ENV_ICON:-⚪}"
    local target_display_name="${ENV_DISPLAY_NAME:-$target_env}"
    
    # 顯示切換確認
    echo -e "\n🔄 ${BLUE}環境切換確認${NC}"
    echo -e "從: $(get_env_display_info "$CURRENT_ENVIRONMENT")"
    echo -e "到: ${target_icon} ${target_display_name}"
    echo ""
    echo "此操作將："
    echo "• 切換所有後續操作到 $target_env 環境"
    echo "• 載入 $target_env 環境配置"
    echo "• 記錄環境切換歷史"
    echo ""
    
    # 使用增強確認系統進行環境切換確認
    if ! smart_operation_confirmation "SWITCH_ENVIRONMENT" "$target_env" 1 "切換到 $target_env 環境"; then
        echo -e "${YELLOW}環境切換已取消${NC}"
        return 1
    fi
    
    # 執行環境切換
    if perform_env_switch "$target_env"; then
        echo -e "${GREEN}✅ 環境切換成功${NC}"
        env_current
    else
        echo -e "${RED}❌ 環境切換失敗${NC}"
        return 1
    fi
}

# 載入環境配置
env_load_config() {
    local env_name="${1:-$CURRENT_ENVIRONMENT}"
    
    if [[ -z "$env_name" ]]; then
        load_current_env
        env_name="$CURRENT_ENVIRONMENT"
    fi
    
    local env_file="$PROJECT_ROOT/configs/${env_name}/${env_name}.env"
    local vpn_endpoint_file="$PROJECT_ROOT/configs/${env_name}/vpn_endpoint.conf"
    
    # 載入環境基本配置
    if [[ -f "$env_file" ]]; then
        source "$env_file"
        
        # 確保 AWS_PROFILE 環境變數被正確設定和匯出
        if [[ -n "$ENV_AWS_PROFILE" ]]; then
            export AWS_PROFILE="$ENV_AWS_PROFILE"
        elif [[ -n "$AWS_PROFILE" ]]; then
            export AWS_PROFILE="$AWS_PROFILE"
        else
            # 回退到環境預設 profile
            if [[ -f "$PROJECT_ROOT/lib/env_core.sh" ]]; then
                source "$PROJECT_ROOT/lib/env_core.sh"
                local default_profile
                default_profile=$(get_env_profile "$env_name" 2>/dev/null)
                if [[ -n "$default_profile" ]]; then
                    export AWS_PROFILE="$default_profile"
                fi
            fi
        fi
        
        # 設定環境特定的目錄路徑 - 跨平台兼容
        export VPN_CERT_DIR="$PROJECT_ROOT/${CERT_DIR#./}"
        export VPN_CONFIG_DIR="$PROJECT_ROOT/${CONFIG_DIR#./}"
        export VPN_LOG_DIR="$PROJECT_ROOT/${LOG_DIR#./}"
        
        # 建立必要的目錄
        mkdir -p "$VPN_CERT_DIR" "$VPN_CONFIG_DIR" "$VPN_LOG_DIR"
        
        # 載入 VPN 端點配置（如果存在）
        if [[ -f "$vpn_endpoint_file" ]]; then
            source "$vpn_endpoint_file"
        fi
        
        echo -e "${GREEN}✅ 已載入 $env_name 環境配置${NC}"
        return 0
    else
        echo -e "${RED}錯誤: 找不到環境配置檔案 $env_file${NC}"
        return 1
    fi
}

# 執行環境切換的內部函式
perform_env_switch() {
    local target_env="$1"
    local current_time=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    local current_user="${USER:-unknown}"
    
    # 更新當前環境檔案
    cat > "$CURRENT_ENV_FILE" << EOF
CURRENT_ENVIRONMENT=$target_env
LAST_SWITCHED_TIME=$current_time
SWITCHED_BY=$current_user
EOF
    
    # 驗證切換是否成功
    if [[ -f "$CURRENT_ENV_FILE" ]]; then
        # 載入新環境配置
        env_load_config "$target_env"
        return 0
    else
        return 1
    fi
}

# 獲取環境顯示資訊
get_env_display_info() {
    local env_name="$1"
    local env_file="$PROJECT_ROOT/configs/${env_name}/${env_name}.env"
    
    if [[ -f "$env_file" ]]; then
        local ENV_ICON ENV_DISPLAY_NAME
        source "$env_file"
        echo "${ENV_ICON:-⚪} ${ENV_DISPLAY_NAME:-$env_name}"
    else
        echo "⚪ $env_name"
    fi
}

# 環境健康檢查
env_health_check() {
    local env_name="$1"
    local verbose="${2:-false}"
    local env_file="$PROJECT_ROOT/configs/${env_name}/${env_name}.env"
    
    local health_status=0
    
    if [[ "$verbose" == "true" ]]; then
        echo -e "${BLUE}檢查 $env_name 環境健康狀態...${NC}"
    fi
    
    # 基本檢查：配置檔案存在
    if [[ ! -f "$env_file" ]]; then
        if [[ "$verbose" == "true" ]]; then
            echo -e "${RED}✗ 環境配置檔案不存在: $env_file${NC}"
        fi
        return 1
    fi
    
    # 載入配置並檢查必要目錄
    source "$env_file"
    local cert_dir="$PROJECT_ROOT/$CERT_DIR"
    local config_dir="$PROJECT_ROOT/$CONFIG_DIR"
    local log_dir="$PROJECT_ROOT/$LOG_DIR"
    
    # 檢查目錄是否存在且可寫入
    if [[ ! -d "$cert_dir" ]] || [[ ! -w "$cert_dir" ]]; then
        if [[ "$verbose" == "true" ]]; then
            echo -e "${RED}✗ 證書目錄問題: $cert_dir${NC}"
        fi
        health_status=1
    elif [[ "$verbose" == "true" ]]; then
        echo -e "${GREEN}✓ 證書目錄正常${NC}"
    fi
    
    if [[ ! -d "$config_dir" ]] || [[ ! -w "$config_dir" ]]; then
        if [[ "$verbose" == "true" ]]; then
            echo -e "${RED}✗ 配置目錄問題: $config_dir${NC}"
        fi
        health_status=1
    elif [[ "$verbose" == "true" ]]; then
        echo -e "${GREEN}✓ 配置目錄正常${NC}"
    fi
    
    if [[ ! -d "$log_dir" ]] || [[ ! -w "$log_dir" ]]; then
        if [[ "$verbose" == "true" ]]; then
            echo -e "${YELLOW}⚠ 日誌目錄問題: $log_dir${NC}"
        fi
        # Log directory issue is not critical
    elif [[ "$verbose" == "true" ]]; then
        echo -e "${GREEN}✓ 日誌目錄正常${NC}"
    fi
    
    # 檢查 AWS Profile 配置
    local profile
    profile=$(get_env_profile "$env_name" 2>/dev/null)
    
    if [[ -n "$profile" ]]; then
        if command -v aws &> /dev/null; then
            # 檢查 profile 是否存在
            if ! aws configure list-profiles | grep -q "^$profile$"; then
                if [[ "$verbose" == "true" ]]; then
                    echo -e "${RED}✗ AWS profile '$profile' 不存在${NC}"
                fi
                health_status=1
            else
                # 檢查 profile 是否可以通過身份驗證
                if aws sts get-caller-identity --profile "$profile" &>/dev/null; then
                    if [[ "$verbose" == "true" ]]; then
                        echo -e "${GREEN}✓ AWS profile '$profile' 有效${NC}"
                        
                        # 檢查跨帳戶驗證
                        if validate_profile_matches_environment "$profile" "$env_name" 2>/dev/null; then
                            echo -e "${GREEN}✓ Profile 帳戶匹配環境${NC}"
                        else
                            echo -e "${YELLOW}⚠ Profile 可能不匹配環境帳戶${NC}"
                        fi
                    fi
                else
                    if [[ "$verbose" == "true" ]]; then
                        echo -e "${RED}✗ AWS profile '$profile' 無法通過身份驗證${NC}"
                    fi
                    health_status=1
                fi
            fi
        else
            if [[ "$verbose" == "true" ]]; then
                echo -e "${YELLOW}⚠ AWS CLI 未安裝，無法驗證 profile${NC}"
            fi
        fi
    else
        if [[ "$verbose" == "true" ]]; then
            echo -e "${YELLOW}⚠ 未設定 AWS profile${NC}"
        fi
        # Missing profile is not critical for basic health check
    fi
    
    return $health_status
}

# 列出所有可用環境
env_list() {
    echo -e "\n=== 可用的 VPN 環境 ==="
    
    local current_env
    load_current_env
    current_env="$CURRENT_ENVIRONMENT"
    
    for env_dir in "$PROJECT_ROOT/configs"/*; do
        if [[ -d "$env_dir" ]]; then
            local env_name=$(basename "$env_dir")
            local env_file="$env_dir/${env_name}.env"
            if [[ -f "$env_file" ]]; then
                source "$env_file"
                
                local icon="${ENV_ICON:-⚪}"
                local display_name="${ENV_DISPLAY_NAME:-$env_name}"
                local status=""
                
                if [[ "$env_name" == "$current_env" ]]; then
                    status="${GREEN}(當前)${NC}"
                fi
                
                echo -e "  ${icon} ${display_name} ${status}"
            fi
        fi
    done
    echo "========================"
}

# 環境選擇器介面
env_selector() {
    while true; do
        clear
        echo -e "=== ${BLUE}AWS Client VPN 多環境管理控制台${NC} ==="
        echo ""
        
        # 顯示當前環境
        load_current_env
        local current_display=$(get_env_display_info "$CURRENT_ENVIRONMENT")
        echo -e "當前環境: ${current_display} ${GREEN}(活躍)${NC}"
        echo ""
        
        # 顯示可用環境
        echo "可用環境:"
        local counter=1
        for env_dir in "$PROJECT_ROOT/configs"/*; do
            if [[ -d "$env_dir" ]]; then
                local env_name=$(basename "$env_dir")
                local env_file="$env_dir/${env_name}.env"
                if [[ -f "$env_file" ]]; then
                    source "$env_file"
                    
                    local icon="${ENV_ICON:-⚪}"
                    local display_name="${ENV_DISPLAY_NAME:-$env_name}"
                    local description=""
                    
                    case "$env_name" in
                        staging)
                            description="開發測試環境"
                            ;;
                        production)
                            description="生產營運環境"
                            ;;
                    esac
                    
                    echo "  ${counter}. ${icon} ${env_name} - ${description}"
                    counter=$((counter + 1))
                fi
            fi
        done
        
        echo ""
        echo "快速操作:"
        echo "  [S] 環境狀態    [H] 健康檢查    [Q] 退出"
        echo ""
        
        read -p "請選擇環境或操作 [1-2/S/H/Q]: " choice
        
        case "$choice" in
            1)
                env_switch "staging"
                read -p "按 Enter 繼續..."
                ;;
            2)
                env_switch "production"
                read -p "按 Enter 繼續..."
                ;;
            [Ss])
                env_current
                read -p "按 Enter 繼續..."
                ;;
            [Hh])
        echo "檢查環境健康狀態..."
        for env_dir in "$PROJECT_ROOT/configs"/*; do
            if [[ -d "$env_dir" ]]; then
                local env_name=$(basename "$env_dir")
                local env_file="$env_dir/${env_name}.env"
                if [[ -f "$env_file" ]]; then
                    if env_health_check "$env_name"; then
                        echo -e "${env_name}: ${GREEN}🟢 健康${NC}"
                    else
                        echo -e "${env_name}: ${YELLOW}🟡 警告${NC}"
                    fi
                fi
            fi
        done
                read -p "按 Enter 繼續..."
                ;;
            [Qq])
                echo -e "${BLUE}感謝使用 AWS Client VPN 管理工具${NC}"
                break
                ;;
            *)
                echo -e "${RED}無效的選擇，請重新輸入${NC}"
                sleep 1
                ;;
        esac
    done
}

# 初始化環境管理器
env_init() {
    # 建立必要的目錄結構
    mkdir -p "$PROJECT_ROOT/certs/staging" \
             "$PROJECT_ROOT/certs/production" \
             "$PROJECT_ROOT/configs/staging" \
             "$PROJECT_ROOT/configs/production" \
             "$PROJECT_ROOT/logs/staging" \
             "$PROJECT_ROOT/logs/production"
    
    # 初始化當前環境檔案
    if [[ ! -f "$CURRENT_ENV_FILE" ]]; then
        echo "CURRENT_ENVIRONMENT=staging" > "$CURRENT_ENV_FILE"
        echo "LAST_SWITCHED_TIME=$(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "$CURRENT_ENV_FILE"
        echo "SWITCHED_BY=system" >> "$CURRENT_ENV_FILE"
    fi
    
    echo -e "${GREEN}✅ 環境管理器初始化完成${NC}"
}

# 腳本整合相關函數
# ===================

# 為其他腳本提供環境初始化
env_init_for_script() {
    local script_name="$1"
    
    # 載入當前環境
    load_current_env
    
    # 載入環境配置
    if ! env_load_config "$CURRENT_ENVIRONMENT"; then
        echo -e "${RED}錯誤: 無法載入環境配置${NC}" >&2
        return 1
    fi
    
    # 設定環境變數供其他腳本使用
    export CURRENT_VPN_ENV="$CURRENT_ENVIRONMENT"
    export VPN_ENV_DISPLAY_NAME="$ENV_DISPLAY_NAME"
    export VPN_ENV_ICON="$ENV_ICON"
    export VPN_ENV_COLOR="$ENV_COLOR"
    
    # 記錄腳本啟動
    if [[ -n "$script_name" ]]; then
        log_env_action "SCRIPT_START" "$script_name started in $CURRENT_ENVIRONMENT environment"
    fi
    
    return 0
}

# 驗證環境是否適合執行特定操作
env_validate_operation() {
    local operation="$1"
    local env_name="${2:-$CURRENT_ENVIRONMENT}"
    
    # 載入環境配置
    local env_file="$PROJECT_ROOT/configs/${env_name}/${env_name}.env"
    if [[ ! -f "$env_file" ]]; then
        echo -e "${RED}錯誤: 環境 $env_name 不存在${NC}" >&2
        return 1
    fi
    
    source "$env_file"
    
    # 使用增強確認系統進行操作驗證
    if [[ "$REQUIRE_OPERATION_CONFIRMATION" == "true" ]]; then
        if ! smart_operation_confirmation "$operation" "$env_name" 1 "在 $env_name 環境執行 $operation"; then
            echo -e "${YELLOW}操作已取消${NC}"
            return 1
        fi
    fi
    
    return 0
}

# 環境操作日誌記錄
log_env_action() {
    local action="$1"
    local message="$2"
    local timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    local user="${USER:-unknown}"
    
    # 確保日誌目錄存在
    load_current_env
    env_load_config "$CURRENT_ENVIRONMENT"
    mkdir -p "$VPN_LOG_DIR"
    
    # 寫入環境操作日誌
    local log_file="$VPN_LOG_DIR/env_operations.log"
    echo "[$timestamp] [$user] [$action] $message" >> "$log_file"
}

# 獲取環境特定配置值
env_get_config() {
    local config_key="$1"
    local env_name="${2:-$CURRENT_ENVIRONMENT}"
    
    # 載入環境配置
    local env_file="$PROJECT_ROOT/configs/${env_name}/${env_name}.env"
    if [[ -f "$env_file" ]]; then
        source "$env_file"
        # 使用間接變數引用獲取配置值
        echo "${!config_key}"
    else
        return 1
    fi
}

# 設定環境特定的檔案路徑
env_setup_paths() {
    local env_name="${1:-$CURRENT_ENVIRONMENT}"
    
    env_load_config "$env_name"
    
    # 設定路徑環境變數
    export VPN_ENDPOINT_CONFIG_FILE="$VPN_CONFIG_DIR/vpn_endpoint.conf"
    export VPN_USER_CONFIG_FILE="$VPN_CONFIG_DIR/user_vpn.conf"
    export VPN_CA_CERT_FILE="$VPN_CERT_DIR/ca.crt"
    export VPN_SERVER_CERT_FILE="$VPN_CERT_DIR/server.crt"
    export VPN_SERVER_KEY_FILE="$VPN_CERT_DIR/server.key"
    export VPN_ADMIN_LOG_FILE="$VPN_LOG_DIR/vpn_admin.log"
    export VPN_USER_LOG_FILE="$VPN_LOG_DIR/user_vpn_setup.log"
    
    # 團隊成員設定專用路徑
    export USER_VPN_CONFIG_FILE="$VPN_CONFIG_DIR/user_vpn.conf"
    export TEAM_SETUP_LOG_FILE="$VPN_LOG_DIR/team_member_setup.log"
    export USER_CERT_DIR="$VPN_CERT_DIR/user-certificates"
    export USER_VPN_CONFIG_DIR="$VPN_CONFIG_DIR/user-configs"
    
    # 確保目錄存在
    mkdir -p "$VPN_CERT_DIR" "$VPN_CONFIG_DIR" "$VPN_LOG_DIR" "$USER_CERT_DIR" "$USER_VPN_CONFIG_DIR"
}

# 顯示環境感知的標題
show_env_aware_header() {
    local script_title="$1"
    local env_name="${2:-$CURRENT_ENVIRONMENT}"
    
    # 載入環境配置
    env_load_config "$env_name"
    
    echo -e "${BLUE}========================================================${NC}"
    echo -e "${BLUE}           $script_title${NC}"
    echo -e "${BLUE}========================================================${NC}"
    echo -e ""
    echo -e "當前環境: ${ENV_ICON} ${ENV_DISPLAY_NAME}"
    if [[ "$env_name" == "production" ]]; then
        echo -e "${RED}⚠️  您正在 Production 環境中操作${NC}"
    fi
    echo -e "${BLUE}========================================================${NC}"
    echo -e ""
}

# 增強版環境操作確認
env_enhanced_operation_confirm() {
    local operation="$1"
    local env_name="$2"
    local description="$3"
    local batch_mode="${4:-false}"
    
    # 使用增強確認模組
    if [[ "$batch_mode" == "true" ]]; then
        # batch_operation_confirmation 需要: operation, target_count, env_name
        local target_count="1"  # 預設為 1，可從 description 中解析更多資訊
        batch_operation_confirmation "$operation" "$target_count" "$env_name"
    else
        smart_operation_confirmation "$operation" "$env_name" 1 "$description"
    fi
}

# 環境感知的操作執行
env_aware_operation() {
    local operation="$1"
    local description="$2"
    shift 2
    local args=("$@")
    
    load_current_env
    
    # 記錄操作開始
    log_env_action "OPERATION_START" "$operation: $description"
    
    # 環境驗證和確認
    if ! env_validate_operation "$operation" "$CURRENT_ENVIRONMENT"; then
        log_env_action "OPERATION_CANCELLED" "$operation: User cancelled"
        return 1
    fi
    
    # 執行操作（這裡可以調用實際的操作函數）
    echo -e "${BLUE}正在執行操作: $description${NC}"
    echo -e "環境: $(get_env_display_info "$CURRENT_ENVIRONMENT")"
    
    # 記錄操作完成
    log_env_action "OPERATION_COMPLETE" "$operation: $description completed successfully"
    
    return 0
}

# =======================================
# Profile Management Integration (Phase 2)
# =======================================

# Load core functions for profile management
if [[ -f "$SCRIPT_DIR/core_functions.sh" ]]; then
    source "$SCRIPT_DIR/core_functions.sh"
fi

if [[ -f "$SCRIPT_DIR/env_core.sh" ]]; then
    source "$SCRIPT_DIR/env_core.sh"
fi

# Set AWS profile for specific environment
env_set_profile() {
    local environment="$1"
    local profile="$2"
    local force="${3:-false}"
    
    if [[ -z "$environment" ]] || [[ -z "$profile" ]]; then
        echo -e "${RED}錯誤: 請指定環境和 AWS profile${NC}" >&2
        echo "使用方式: env_set_profile <environment> <profile> [force]"
        return 1
    fi
    
    # Validate environment exists
    local env_file="$PROJECT_ROOT/configs/${environment}/${environment}.env"
    if [[ ! -f "$env_file" ]]; then
        echo -e "${RED}錯誤: 環境 '$environment' 不存在${NC}" >&2
        return 1
    fi
    
    # Validate AWS profile exists and is valid
    if ! validate_aws_profile_config "$profile" "$environment"; then
        if [[ "$force" != "true" ]]; then
            echo -e "${RED}錯誤: AWS profile '$profile' 無效或無法通過驗證${NC}" >&2
            return 1
        else
            echo -e "${YELLOW}警告: 強制設定 profile '$profile'，即使驗證失敗${NC}" >&2
        fi
    fi
    
    # Save profile to environment configuration
    if save_profile_to_config "$environment" "$profile"; then
        echo -e "${GREEN}✅ 已設定 $environment 環境的 AWS profile 為 '$profile'${NC}"
        
        # If this is the current environment, update active profile
        load_current_env
        if [[ "$CURRENT_ENVIRONMENT" == "$environment" ]]; then
            export AWS_PROFILE="$profile"
            export ENV_AWS_PROFILE="$profile"
            echo -e "${GREEN}✅ 已更新當前環境的活躍 profile${NC}"
        fi
        
        # Log the profile change
        log_env_action "PROFILE_SET" "Set AWS profile '$profile' for $environment environment"
        return 0
    else
        echo -e "${RED}錯誤: 無法保存 profile 配置${NC}" >&2
        return 1
    fi
}

# Get current AWS profile for environment
env_get_profile() {
    local environment="${1:-$CURRENT_ENVIRONMENT}"
    local show_details="${2:-false}"
    
    if [[ -z "$environment" ]]; then
        load_current_env
        environment="$CURRENT_ENVIRONMENT"
    fi
    
    # Get profile from environment configuration
    local profile
    profile=$(get_env_profile "$environment")
    
    if [[ -z "$profile" ]]; then
        echo -e "${YELLOW}警告: $environment 環境未設定 AWS profile${NC}" >&2
        return 1
    fi
    
    if [[ "$show_details" == "true" ]]; then
        echo -e "${BLUE}$environment 環境的 AWS profile:${NC}"
        echo -e "  Profile: ${GREEN}$profile${NC}"
        
        # Show profile details if valid
        if aws configure list-profiles | grep -q "^$profile$"; then
            local account_id region
            account_id=$(aws sts get-caller-identity --profile "$profile" --query Account --output text 2>/dev/null)
            region=$(aws configure get region --profile "$profile" 2>/dev/null)
            
            echo -e "  帳戶 ID: ${account_id:-未知}"
            echo -e "  區域: ${region:-預設}"
            
            # Validate profile matches environment
            if validate_profile_matches_environment "$profile" "$environment" 2>/dev/null; then
                echo -e "  狀態: ${GREEN}✓ 有效且匹配環境${NC}"
            else
                echo -e "  狀態: ${YELLOW}⚠ 有效但可能不匹配環境${NC}"
            fi
        else
            echo -e "  狀態: ${RED}✗ Profile 不存在${NC}"
        fi
    else
        echo "$profile"
    fi
    
    return 0
}

# Validate profile integration for environment
env_validate_profile_integration() {
    local environment="${1:-$CURRENT_ENVIRONMENT}"
    local fix_issues="${2:-false}"
    
    if [[ -z "$environment" ]]; then
        load_current_env
        environment="$CURRENT_ENVIRONMENT"
    fi
    
    echo -e "${BLUE}驗證 $environment 環境的 AWS profile 整合...${NC}"
    
    local profile
    profile=$(get_env_profile "$environment")
    
    if [[ -z "$profile" ]]; then
        echo -e "${RED}✗ 環境 $environment 未設定 AWS profile${NC}"
        if [[ "$fix_issues" == "true" ]]; then
            echo -e "${BLUE}嘗試自動修復...${NC}"
            if profile=$(select_aws_profile_for_environment "$environment"); then
                env_set_profile "$environment" "$profile"
                echo -e "${GREEN}✅ 已自動設定 profile: $profile${NC}"
            else
                echo -e "${RED}無法自動修復 profile 設定${NC}"
                return 1
            fi
        else
            return 1
        fi
    fi
    
    # Validate profile exists
    if ! aws configure list-profiles | grep -q "^$profile$"; then
        echo -e "${RED}✗ AWS profile '$profile' 不存在${NC}"
        return 1
    fi
    
    # Validate profile authentication
    if ! aws sts get-caller-identity --profile "$profile" &>/dev/null; then
        echo -e "${RED}✗ AWS profile '$profile' 無法通過身份驗證${NC}"
        return 1
    fi
    
    # Cross-account validation
    if ! validate_profile_matches_environment "$profile" "$environment"; then
        echo -e "${YELLOW}⚠ Profile 可能不匹配環境 (帳戶 ID 驗證失敗)${NC}"
        if [[ "$fix_issues" == "true" ]]; then
            echo -e "${BLUE}建議重新選擇 profile...${NC}"
            if new_profile=$(select_aws_profile_for_environment "$environment" true); then
                env_set_profile "$environment" "$new_profile"
                echo -e "${GREEN}✅ 已更新 profile: $new_profile${NC}"
            fi
        fi
    else
        echo -e "${GREEN}✅ Profile 驗證通過${NC}"
    fi
    
    # Validate environment configuration consistency
    local env_file="$PROJECT_ROOT/configs/${environment}/${environment}.env"
    if [[ -f "$env_file" ]]; then
        source "$env_file"
        if [[ "$AWS_PROFILE" != "$profile" ]] || [[ "$ENV_AWS_PROFILE" != "$profile" ]]; then
            echo -e "${YELLOW}⚠ 環境配置文件中的 profile 設定不一致${NC}"
            if [[ "$fix_issues" == "true" ]]; then
                save_profile_to_config "$environment" "$profile"
                echo -e "${GREEN}✅ 已修復配置文件中的 profile 設定${NC}"
            fi
        fi
    fi
    
    echo -e "${GREEN}✅ $environment 環境的 profile 整合驗證完成${NC}"
    log_env_action "PROFILE_VALIDATED" "Profile integration validated for $environment environment"
    return 0
}

# Load environment with automatic profile setup
env_load_with_profile() {
    local env_name="${1:-$CURRENT_ENVIRONMENT}"
    local auto_fix="${2:-false}"
    
    if [[ -z "$env_name" ]]; then
        load_current_env
        env_name="$CURRENT_ENVIRONMENT"
    fi
    
    echo -e "${BLUE}載入 $env_name 環境並設定 AWS profile...${NC}"
    
    # First load the environment configuration normally
    if ! env_load_config "$env_name"; then
        echo -e "${RED}錯誤: 無法載入環境配置${NC}" >&2
        return 1
    fi
    
    # Validate and setup profile integration
    if ! env_validate_profile_integration "$env_name" "$auto_fix"; then
        if [[ "$auto_fix" != "true" ]]; then
            echo -e "${YELLOW}警告: Profile 整合驗證失敗，建議使用 --auto-fix 選項${NC}" >&2
        else
            echo -e "${RED}錯誤: 無法修復 profile 整合問題${NC}" >&2
            return 1
        fi
    fi
    
    # Load profile from configuration
    if load_profile_from_config "$env_name"; then
        echo -e "${GREEN}✅ 已載入 $env_name 環境並設定 AWS profile${NC}"
        echo -e "  環境: $(get_env_display_info "$env_name")"
        echo -e "  AWS Profile: ${AWS_PROFILE:-未設定}"
        
        # Log the environment load with profile
        log_env_action "ENV_LOADED_WITH_PROFILE" "Environment $env_name loaded with AWS profile: ${AWS_PROFILE:-none}"
        return 0
    else
        echo -e "${YELLOW}警告: 環境已載入但未能設定 AWS profile${NC}" >&2
        return 1
    fi
}

# Switch environments with profile validation
env_switch_with_profile() {
    local target_env="$1"
    local validate_profile="${2:-true}"
    
    if [[ -z "$target_env" ]]; then
        echo -e "${RED}錯誤: 請指定目標環境 (staging 或 production)${NC}" >&2
        return 1
    fi
    
    # First validate the target environment exists
    local target_env_file="$PROJECT_ROOT/configs/${target_env}/${target_env}.env"
    if [[ ! -f "$target_env_file" ]]; then
        echo -e "${RED}錯誤: 環境 '$target_env' 不存在${NC}" >&2
        return 1
    fi
    
    load_current_env
    
    # Check if already in target environment
    if [[ "$CURRENT_ENVIRONMENT" == "$target_env" ]]; then
        echo -e "${YELLOW}已經在 $target_env 環境中${NC}"
        # Still validate profile integration
        if [[ "$validate_profile" == "true" ]]; then
            env_validate_profile_integration "$target_env"
        fi
        env_current
        return 0
    fi
    
    # Validate profile integration for target environment
    if [[ "$validate_profile" == "true" ]]; then
        echo -e "${BLUE}驗證目標環境的 AWS profile 設定...${NC}"
        if ! env_validate_profile_integration "$target_env" "true"; then
            echo -e "${RED}錯誤: 目標環境的 profile 設定有問題${NC}" >&2
            echo -e "${YELLOW}建議先使用 env_set_profile 設定正確的 AWS profile${NC}" >&2
            return 1
        fi
    fi
    
    # Show enhanced switch confirmation with profile information
    source "$target_env_file"
    local target_icon="${ENV_ICON:-⚪}"
    local target_display_name="${ENV_DISPLAY_NAME:-$target_env}"
    local target_profile=$(get_env_profile "$target_env")
    
    echo -e "\n🔄 ${BLUE}環境切換確認 (含 AWS Profile)${NC}"
    echo -e "從: $(get_env_display_info "$CURRENT_ENVIRONMENT")"
    echo -e "到: ${target_icon} ${target_display_name}"
    echo -e "AWS Profile: ${target_profile:-未設定}"
    echo ""
    echo "此操作將："
    echo "• 切換所有後續操作到 $target_env 環境"
    echo "• 載入 $target_env 環境配置"
    echo "• 設定 AWS profile 為 '${target_profile:-未設定}'"
    echo "• 記錄環境切換歷史"
    echo ""
    
    # Use enhanced confirmation system
    if ! smart_operation_confirmation "SWITCH_ENVIRONMENT_WITH_PROFILE" "$target_env" 1 "切換到 $target_env 環境並設定 AWS profile"; then
        echo -e "${YELLOW}環境切換已取消${NC}"
        return 1
    fi
    
    # Perform the environment switch
    if perform_env_switch "$target_env"; then
        # Load with profile integration
        if env_load_with_profile "$target_env" "true"; then
            echo -e "${GREEN}✅ 環境切換成功 (含 AWS profile 設定)${NC}"
            env_current
            log_env_action "ENV_SWITCHED_WITH_PROFILE" "Switched to $target_env environment with AWS profile: ${AWS_PROFILE:-none}"
        else
            echo -e "${YELLOW}⚠ 環境切換成功但 profile 設定有問題${NC}"
            env_current
        fi
    else
        echo -e "${RED}❌ 環境切換失敗${NC}"
        return 1
    fi
}

# 主程式入口點
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    case "${1:-}" in
        current)
            env_current
            ;;
        switch)
            env_switch "$2"
            ;;
        switch-with-profile)
            env_switch_with_profile "$2" "${3:-true}"
            ;;
        load)
            env_load_config "$2"
            ;;
        load-with-profile)
            env_load_with_profile "$2" "${3:-false}"
            ;;
        list)
            env_list
            ;;
        selector)
            env_selector
            ;;
        init)
            env_init
            ;;
        health)
            env_health_check "$2" "${3:-false}"
            ;;
        set-profile)
            env_set_profile "$2" "$3" "${4:-false}"
            ;;
        get-profile)
            env_get_profile "$2" "${3:-false}"
            ;;
        validate-profile)
            env_validate_profile_integration "$2" "${3:-false}"
            ;;
        *)
            echo "使用方式: $0 {current|switch <env>|load <env>|list|selector|init|health <env>|profile commands}"
            echo ""
            echo "基本命令:"
            echo "  current                          顯示當前環境狀態"
            echo "  switch <env>                     切換到指定環境"
            echo "  switch-with-profile <env>        切換環境並驗證 AWS profile"
            echo "  load <env>                       載入環境配置"
            echo "  load-with-profile <env> [fix]    載入環境並設定 AWS profile"
            echo "  list                             列出所有可用環境"
            echo "  selector                         啟動互動式環境選擇器"
            echo "  init                             初始化環境管理器"
            echo "  health <env> [verbose]           檢查環境健康狀態"
            echo ""
            echo "Profile 管理命令:"
            echo "  set-profile <env> <profile> [force]     設定環境的 AWS profile"
            echo "  get-profile [env] [details]             取得環境的 AWS profile"
            echo "  validate-profile [env] [fix]            驗證環境的 profile 整合"
            echo ""
            echo "範例:"
            echo "  $0 set-profile staging default          設定 staging 環境使用 default profile"
            echo "  $0 get-profile production true          顯示 production 環境的詳細 profile 資訊"
            echo "  $0 validate-profile staging true        驗證並自動修復 staging 環境的 profile"
            echo "  $0 health staging true                   詳細檢查 staging 環境健康狀態"
            exit 1
            ;;
    esac
fi
