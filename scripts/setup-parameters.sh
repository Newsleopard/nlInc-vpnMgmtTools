#!/bin/bash

# VPN Cost Automation Parameter Setup Script
# Sets up required Parameter Store values for the automation
# Environment-aware version that reads configuration files

# 全域變數
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Color codes for output (basic colors for help function)
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 不使用 set -e，改用手動錯誤處理以避免程式意外退出

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to show usage
show_usage() {
    echo -e "${BLUE}========================================================${NC}"
    echo -e "${BLUE}           VPN Cost Automation Parameter Setup Script${NC}"
    echo -e "${BLUE}========================================================${NC}"
    echo ""
    echo "此腳本會自動使用當前環境設定進行參數配置"
    echo ""
    echo "使用方式: $0 [options]"
    echo ""
    echo "選項:"
    echo "  --endpoint-id ID     VPN endpoint ID (如果未提供，將從配置檔案讀取)"
    echo "  --subnet-id ID       Subnet ID (如果未提供，將從配置檔案讀取)"
    echo "  --slack-webhook URL  Slack webhook URL (必須提供)"
    echo "  --slack-secret SEC   Slack signing secret (必須提供)"
    echo "  --slack-bot-token TK Slack bot OAuth token (必須提供)"
    echo "  --secure             使用加密參數 (encrypted)"
    echo "  --auto-read          自動從配置檔案讀取所有可用參數"
    echo ""
    echo "範例:"
    echo "  # 使用配置檔案中的 endpoint-id 和 subnet-id"
    echo "  $0 --auto-read \\"
    echo "    --slack-webhook https://hooks.slack.com/services/... \\"
    echo "    --slack-secret your-slack-signing-secret \\"
    echo "    --slack-bot-token xoxb-your-bot-token"
    echo ""
    echo "  # 手動指定參數"
    echo "  $0 --endpoint-id cvpn-endpoint-0123456789abcdef \\"
    echo "    --subnet-id subnet-0123456789abcdef \\"
    echo "    --slack-webhook https://hooks.slack.com/services/... \\"
    echo "    --slack-secret your-slack-signing-secret \\"
    echo "    --slack-bot-token xoxb-your-bot-token"
    echo ""
    echo "注意："
    echo "  - 此腳本會自動使用當前環境的 AWS profile"
    echo "  - 可使用 './vpn_env.sh switch <env>' 切換環境"
    echo "  - 執行前請確保已正確設定環境"
}

# Parse command line arguments
ENDPOINT_ID=""
SUBNET_ID=""
SLACK_WEBHOOK=""
SLACK_SECRET=""
SLACK_BOT_TOKEN=""
USE_SECURE_PARAMETERS=false
AUTO_READ_CONFIG=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --endpoint-id)
            ENDPOINT_ID="$2"
            shift 2
            ;;
        --subnet-id)
            SUBNET_ID="$2"
            shift 2
            ;;
        --slack-webhook)
            SLACK_WEBHOOK="$2"
            shift 2
            ;;
        --slack-secret)
            SLACK_SECRET="$2"
            shift 2
            ;;
        --slack-bot-token)
            SLACK_BOT_TOKEN="$2"
            shift 2
            ;;
        --secure)
            USE_SECURE_PARAMETERS=true
            shift
            ;;
        --auto-read)
            AUTO_READ_CONFIG=true
            shift
            ;;
        -h|--help)
            show_usage
            exit 0
            ;;
        *)
            print_error "Unknown option: $1"
            show_usage
            exit 1
            ;;
    esac
done

# Now that we've handled help, initialize the environment
print_status "正在初始化環境管理器..."

# 載入環境管理器
source "$SCRIPT_DIR/../lib/env_manager.sh"

# 初始化環境
if ! env_init_for_script "setup-parameters.sh"; then
    print_error "無法初始化環境管理器"
    exit 1
fi

# 驗證 AWS Profile 整合
print_status "正在驗證 AWS Profile 設定..."
if ! env_validate_profile_integration "$CURRENT_ENVIRONMENT" "true"; then
    print_warning "AWS Profile 設定可能有問題，但繼續執行設定工具"
fi

# 設定環境特定路徑
env_setup_paths

# 環境感知的配置檔案
ENV_CONFIG_FILE="$VPN_CONFIG_DIR/${CURRENT_ENVIRONMENT}.env"
ENDPOINT_CONFIG_FILE="$VPN_ENDPOINT_CONFIG_FILE"
CONFIG_FILE="$ENV_CONFIG_FILE"  # Primary config for setup operations
LOG_FILE="$VPN_ADMIN_LOG_FILE"

# 載入核心函式庫
source "$SCRIPT_DIR/../lib/core_functions.sh"
source "$SCRIPT_DIR/../lib/aws_setup.sh"

# Function to read configuration from files
read_config_values() {
    print_status "讀取環境配置檔案..."
    
    # Validate and load main configuration
    if ! validate_main_config "$CONFIG_FILE"; then
        print_error "配置檔案驗證失敗: $CONFIG_FILE"
        print_status "請確保配置檔案存在且包含必要變數"
        return 1
    fi
    
    # Load environment configuration
    if ! load_config_core "$CONFIG_FILE"; then
        print_error "無法載入配置檔案: $CONFIG_FILE"
        return 1
    fi
    
    # Try to load endpoint configuration for auto-generated values
    if [ -f "$ENDPOINT_CONFIG_FILE" ]; then
        print_status "載入端點配置檔案: $ENDPOINT_CONFIG_FILE"
        if ! load_config_core "$ENDPOINT_CONFIG_FILE"; then
            print_warning "無法載入端點配置檔案，使用預設值"
        fi
    fi
    
    # Auto-read values from configuration if not provided via command line
    if [ "$AUTO_READ_CONFIG" = "true" ] || [ -z "$ENDPOINT_ID" ]; then
        if [ -n "$ENDPOINT_ID_FROM_CONFIG" ]; then
            ENDPOINT_ID="$ENDPOINT_ID_FROM_CONFIG"
            print_status "從配置檔案讀取 ENDPOINT_ID: $ENDPOINT_ID"
        fi
    fi
    
    if [ "$AUTO_READ_CONFIG" = "true" ] || [ -z "$SUBNET_ID" ]; then
        if [ -n "$SUBNET_ID" ]; then
            print_status "從配置檔案讀取 SUBNET_ID: $SUBNET_ID"
        fi
    fi
    
    return 0
}

# Read configuration values from files
if ! read_config_values; then
    print_error "無法讀取配置檔案"
    exit 1
fi

# Validate required arguments
if [ -z "$SLACK_WEBHOOK" ] || [ -z "$SLACK_SECRET" ] || [ -z "$SLACK_BOT_TOKEN" ]; then
    print_error "必須提供 Slack 參數: --slack-webhook, --slack-secret, --slack-bot-token"
    show_usage
    exit 1
fi

if [ -z "$ENDPOINT_ID" ] || [ -z "$SUBNET_ID" ]; then
    print_error "必須提供或從配置檔案讀取: --endpoint-id, --subnet-id"
    print_status "請檢查配置檔案 $CONFIG_FILE 或使用 --auto-read 選項"
    show_usage
    exit 1
fi

# Get current AWS profile from environment manager
CURRENT_AWS_PROFILE=$(env_get_profile "$CURRENT_ENVIRONMENT" 2>/dev/null)
if [ -z "$CURRENT_AWS_PROFILE" ]; then
    print_error "無法取得當前環境的 AWS profile"
    print_status "請使用 './vpn_env.sh status' 檢查環境狀態"
    exit 1
fi

print_status "使用 AWS Profile: $CURRENT_AWS_PROFILE"

# Validate AWS profile
print_status "驗證 AWS profile: $CURRENT_AWS_PROFILE"
if ! aws_with_profile sts get-caller-identity &> /dev/null; then
    print_error "AWS profile '$CURRENT_AWS_PROFILE' 未配置或憑證無效"
    exit 1
fi

# Get region from configuration or profile
if [ -n "$AWS_REGION" ]; then
    print_status "使用配置檔案中的區域: $AWS_REGION"
else
    AWS_REGION=$(aws configure get region --profile "$CURRENT_AWS_PROFILE" 2>/dev/null || echo "us-east-1")
    print_status "使用 profile 預設區域: $AWS_REGION"
fi

# Function to create or update parameter
create_parameter() {
    local param_name="$1"
    local param_value="$2"
    local param_type="$3"
    local description="$4"
    
    print_status "Setting parameter: $param_name"
    
    aws_with_profile ssm put-parameter \
        --name "$param_name" \
        --value "$param_value" \
        --type "$param_type" \
        --description "$description" \
        --overwrite \
        --region "$AWS_REGION" > /dev/null
    
    if [ $? -eq 0 ]; then
        print_success "✅ Parameter $param_name set successfully"
    else
        print_error "❌ Failed to set parameter $param_name"
        exit 1
    fi
}

# Function to set secure parameter (Epic 5.1)
set_secure_parameter() {
    local param_name="$1"
    local param_value="$2"
    local description="$3"
    local kms_key_alias="vpn-parameter-store-$CURRENT_ENVIRONMENT"
    
    print_status "Setting secure parameter: $param_name"
    
    # Check if KMS key exists
    if ! aws_with_profile kms describe-key --key-id "alias/$kms_key_alias" --region "$AWS_REGION" &> /dev/null; then
        print_error "❌ KMS key alias/$kms_key_alias not found. Please deploy with --secure-parameters first."
        exit 1
    fi
    
    aws_with_profile ssm put-parameter \
        --name "$param_name" \
        --value "$param_value" \
        --type "SecureString" \
        --key-id "alias/$kms_key_alias" \
        --description "$description" \
        --overwrite \
        --region "$AWS_REGION" > /dev/null
    
    if [ $? -eq 0 ]; then
        print_success "✅ Secure parameter $param_name set successfully (encrypted with KMS)"
    else
        print_error "❌ Failed to set secure parameter $param_name"
        exit 1
    fi
}

# Function to set parameter
set_parameter() {
    local param_name="$1"
    local param_value="$2"
    local param_type="$3"
    local description="$4"
    
    if [ "$USE_SECURE_PARAMETERS" = "true" ] && [[ "$param_name" == *"slack"* ]]; then
        # Use secure parameters for sensitive data
        set_secure_parameter "$param_name" "$param_value" "$description"
    else
        print_status "Setting parameter: $param_name"
        
        aws_with_profile ssm put-parameter \
            --name "$param_name" \
            --value "$param_value" \
            --type "$param_type" \
            --description "$description" \
            --overwrite \
            --region "$AWS_REGION" > /dev/null
        
        if [ $? -eq 0 ]; then
            print_success "✅ Parameter $param_name set successfully"
        else
            print_error "❌ Failed to set parameter $param_name"
            exit 1
        fi
    fi
}

# Validate VPN endpoint exists
print_status "驗證 VPN 端點: $ENDPOINT_ID"
if ! aws_with_profile ec2 describe-client-vpn-endpoints \
    --client-vpn-endpoint-ids "$ENDPOINT_ID" \
    --region "$AWS_REGION" \
    --query 'ClientVpnEndpoints[0].State' \
    --output text &> /dev/null; then
    print_error "VPN endpoint $ENDPOINT_ID 未找到或無法存取"
    exit 1
fi

ENDPOINT_STATE=$(aws_with_profile ec2 describe-client-vpn-endpoints \
    --client-vpn-endpoint-ids "$ENDPOINT_ID" \
    --region "$AWS_REGION" \
    --query 'ClientVpnEndpoints[0].Status.Code' \
    --output text)

print_status "VPN endpoint state: $ENDPOINT_STATE"

if [ "$ENDPOINT_STATE" != "available" ]; then
    print_warning "⚠️  VPN endpoint is not in 'available' state. Current state: $ENDPOINT_STATE"
    read -p "Continue anyway? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_status "Setup cancelled"
        exit 0
    fi
fi

# Validate subnet exists
print_status "驗證子網路: $SUBNET_ID"
if ! aws_with_profile ec2 describe-subnets \
    --subnet-ids "$SUBNET_ID" \
    --region "$AWS_REGION" \
    --query 'Subnets[0].SubnetId' \
    --output text &> /dev/null; then
    print_error "Subnet $SUBNET_ID 未找到或無法存取"
    exit 1
fi

print_success "✅ VPN endpoint and subnet validation passed"

# Create parameters
print_status "正在為 ${ENV_ICON} $ENV_DISPLAY_NAME 環境建立 Parameter Store 參數..."

# Log the operation
log_env_action "PARAM_SETUP_START" "開始設定 Parameter Store 參數"

# VPN endpoint configuration
VPN_CONFIG=$(cat <<EOF
{
  "ENDPOINT_ID": "$ENDPOINT_ID",
  "SUBNET_ID": "$SUBNET_ID",
  "ENVIRONMENT": "$CURRENT_ENVIRONMENT",
  "REGION": "$AWS_REGION"
}
EOF
)

set_parameter \
    "/vpn/endpoint/conf" \
    "$VPN_CONFIG" \
    "String" \
    "VPN endpoint configuration for $CURRENT_ENVIRONMENT environment (endpoint ID, subnet ID, region)"

# VPN state (initial state)
VPN_STATE=$(cat <<EOF
{
  "associated": false,
  "lastActivity": "$(date -u +"%Y-%m-%dT%H:%M:%S.000Z")",
  "environment": "$CURRENT_ENVIRONMENT"
}
EOF
)

set_parameter \
    "/vpn/endpoint/state" \
    "$VPN_STATE" \
    "String" \
    "VPN endpoint state for $CURRENT_ENVIRONMENT environment (associated status and last activity)"

# Slack webhook (encrypted)
set_parameter \
    "/vpn/slack/webhook" \
    "$SLACK_WEBHOOK" \
    "SecureString" \
    "Slack webhook URL for VPN automation notifications ($CURRENT_ENVIRONMENT environment)"

# Slack signing secret (encrypted)
set_parameter \
    "/vpn/slack/signing_secret" \
    "$SLACK_SECRET" \
    "SecureString" \
    "Slack signing secret for request verification ($CURRENT_ENVIRONMENT environment)"

# Slack bot token (encrypted)
set_parameter \
    "/vpn/slack/bot_token" \
    "$SLACK_BOT_TOKEN" \
    "SecureString" \
    "Slack bot OAuth token for posting messages ($CURRENT_ENVIRONMENT environment)"

log_env_action "PARAM_SETUP_COMPLETE" "Parameter Store 參數設定完成"
print_success "🎉 所有參數已成功設定於 ${ENV_ICON} $ENV_DISPLAY_NAME 環境！"

# Display summary
echo ""
print_status "📋 參數摘要:"
echo "   環境: ${ENV_ICON} $ENV_DISPLAY_NAME ($CURRENT_ENVIRONMENT)"
echo "   AWS Profile: $CURRENT_AWS_PROFILE"
echo "   AWS 區域: $AWS_REGION"
echo "   VPN 端點: $ENDPOINT_ID"
echo "   子網路: $SUBNET_ID"
echo "   Slack webhook: ***已配置***"
echo "   Slack secret: ***已配置***"
echo "   Slack bot token: ***已配置***"
echo "   配置檔案: $CONFIG_FILE"
echo ""

print_status "🚀 後續步驟:"
echo "   1. 部署 CDK stack: ./scripts/deploy.sh $CURRENT_ENVIRONMENT"
echo "   2. 設定您的 Slack app 使用 API Gateway endpoint"
echo "   3. 測試整合: /vpn check $CURRENT_ENVIRONMENT"
echo "   4. 使用 './vpn_env.sh status' 檢查環境狀態"