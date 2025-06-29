#!/bin/bash

# VPN Environment Manager Script
# 用途：切換和管理不同的 VPN 環境 (staging, production)

# 獲取腳本目錄
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARENT_DIR="$(dirname "$SCRIPT_DIR")"

# 載入環境管理器 (正確的路徑)
if [[ -f "$PARENT_DIR/lib/env_manager.sh" ]]; then
    source "$PARENT_DIR/lib/env_manager.sh"
else
    echo "Error: Environment manager not found at $PARENT_DIR/lib/env_manager.sh"
    exit 1
fi

# 初始化環境管理器
if ! env_init_for_script "vpn_env.sh"; then
    echo "Error: Failed to initialize environment manager"
    exit 1
fi

# 顯示使用說明
show_usage() {
    cat << EOF
VPN Environment Manager

Usage: $0 <command> [arguments]

Commands:
  switch <env>     - Switch to specified environment (staging/production)
  status           - Show current environment status
  list             - List all available environments
  validate         - Validate current environment configuration
  help             - Show this help message

Examples:
  $0 switch staging      # Switch to staging environment
  $0 switch production   # Switch to production environment
  $0 status              # Show current environment
  $0 list                # List available environments
EOF
}

# 切換環境
switch_environment() {
    local target_env="$1"
    
    if [[ -z "$target_env" ]]; then
        echo "Error: Environment name required"
        show_usage
        return 1
    fi
    
    # 直接使用 AWS profile 名稱作為環境名稱，不進行轉換
    case "$target_env" in
        staging|prod|production)
            # 保持原始名稱，不進行標準化轉換
            ;;
        *)
            echo "Error: Invalid environment '$target_env'"
            echo "Valid environments: staging, prod"
            return 1
            ;;
    esac
    
    echo "Switching to $target_env environment..."
    
    if env_switch "$target_env"; then
        echo "Successfully switched to $target_env environment"
        
        # 顯示新環境狀態
        show_environment_status
        
        return 0
    else
        echo "Error: Failed to switch to $target_env environment"
        return 1
    fi
}

# 顯示環境狀態
show_environment_status() {
    echo ""
    echo "=== Current Environment Status ==="
    echo "Environment: $CURRENT_ENVIRONMENT"
    
    # 顯示環境配置路徑
    local env_config="$PARENT_DIR/configs/$CURRENT_ENVIRONMENT/${CURRENT_ENVIRONMENT}.env"
    if [[ -f "$env_config" ]]; then
        echo "Config file: $env_config"
        echo "Status: ✓ Valid"
    else
        echo "Config file: $env_config"
        echo "Status: ✗ Missing"
    fi
    
    # 顯示 AWS Profile 狀態
    local current_profile
    current_profile=$(env_get_profile "$CURRENT_ENVIRONMENT" 2>/dev/null)
    if [[ -n "$current_profile" ]]; then
        echo "AWS Profile: $current_profile"
        
        # 驗證 profile 是否有效
        if aws configure list-profiles | grep -q "^$current_profile$" 2>/dev/null; then
            if aws sts get-caller-identity --profile "$current_profile" &>/dev/null; then
                local account_id region
                account_id=$(aws sts get-caller-identity --profile "$current_profile" --query Account --output text 2>/dev/null)
                region=$(aws configure get region --profile "$current_profile" 2>/dev/null)
                
                echo "AWS Account: ${account_id:-Unknown}"
                echo "AWS Region: ${region:-Unknown}"
                echo "Profile Status: ✓ Valid"
            else
                echo "Profile Status: ✗ Invalid or no access"
            fi
        else
            echo "Profile Status: ✗ Profile not found"
        fi
    else
        echo "AWS Profile: Not configured"
        echo "Profile Status: ✗ Missing"
    fi
    
    echo "=================================="
}

# 列出可用環境
list_environments() {
    echo ""
    echo "=== Available Environments ==="
    
    local configs_dir="$PARENT_DIR/configs"
    if [[ -d "$configs_dir" ]]; then
        for env_dir in "$configs_dir"/*; do
            if [[ -d "$env_dir" ]]; then
                local env_name=$(basename "$env_dir")
                local env_config="$env_dir/${env_name}.env"
                
                if [[ -f "$env_config" ]]; then
                    # 載入環境配置以獲取顯示名稱
                    local display_name icon
                    source "$env_config"
                    display_name="${ENV_DISPLAY_NAME:-$env_name}"
                    icon="${ENV_ICON:-⚪}"
                    
                    if [[ "$env_name" == "$CURRENT_ENVIRONMENT" ]]; then
                        echo "  $icon $display_name (current)"
                    else
                        echo "  $icon $display_name"
                    fi
                else
                    echo "  ⚠️  $env_name (missing config)"
                fi
            fi
        done
    else
        echo "No environments found in $configs_dir"
    fi
    
    echo "==============================="
}

# 驗證環境配置
validate_environment() {
    echo ""
    echo "=== Environment Validation ==="
    echo "Current environment: $CURRENT_ENVIRONMENT"
    
    # 驗證環境配置文件
    local env_config="$PARENT_DIR/configs/$CURRENT_ENVIRONMENT/${CURRENT_ENVIRONMENT}.env"
    if [[ -f "$env_config" ]]; then
        echo "✓ Environment config exists"
        
        # 檢查必要的配置變數
        source "$env_config"
        local required_vars=("AWS_REGION" "VPC_ID" "SUBNET_ID" "VPN_CIDR")
        local missing_vars=()
        
        for var in "${required_vars[@]}"; do
            if [[ -z "${!var}" ]]; then
                missing_vars+=("$var")
            fi
        done
        
        if [[ ${#missing_vars[@]} -eq 0 ]]; then
            echo "✓ All required configuration variables present"
        else
            echo "✗ Missing configuration variables: ${missing_vars[*]}"
        fi
    else
        echo "✗ Environment config missing: $env_config"
    fi
    
    # 驗證 AWS Profile
    local profile_valid=false
    if env_validate_profile_integration "$CURRENT_ENVIRONMENT" false; then
        echo "✓ AWS Profile configuration valid"
        profile_valid=true
    else
        echo "✗ AWS Profile configuration invalid or missing"
    fi
    
    # 驗證 VPN 端點配置 (如果存在)
    local endpoint_config="$PARENT_DIR/configs/$CURRENT_ENVIRONMENT/vpn_endpoint.conf"
    if [[ -f "$endpoint_config" ]]; then
        echo "✓ VPN endpoint configuration exists"
        
        source "$endpoint_config"
        if [[ -n "$ENDPOINT_ID" ]]; then
            echo "✓ Endpoint ID configured: $ENDPOINT_ID"
            
            # 如果 profile 有效，嘗試驗證端點是否存在
            if [[ "$profile_valid" == "true" ]] && [[ -n "$AWS_REGION" ]]; then
                if aws ec2 describe-client-vpn-endpoints \
                    --client-vpn-endpoint-ids "$ENDPOINT_ID" \
                    --region "$AWS_REGION" &>/dev/null; then
                    echo "✓ VPN endpoint exists and accessible"
                else
                    echo "✗ VPN endpoint not found or not accessible"
                fi
            fi
        else
            echo "✗ Endpoint ID not configured"
        fi
    else
        echo "ℹ️  VPN endpoint not configured (use aws_vpn_admin.sh to create)"
    fi
    
    echo "=============================="
}

# 主函數
main() {
    local command="$1"
    shift
    
    case "$command" in
        switch)
            switch_environment "$@"
            ;;
        status)
            show_environment_status
            ;;
        list)
            list_environments
            ;;
        validate)
            validate_environment
            ;;
        help|--help|-h)
            show_usage
            ;;
        "")
            echo "Error: Command required"
            show_usage
            exit 1
            ;;
        *)
            echo "Error: Unknown command '$command'"
            show_usage
            exit 1
            ;;
    esac
}

# 執行主函數
main "$@"
