#!/bin/bash

# VPN Cost Automation Deployment Script
# Supports production, staging, and both environment deployment modes

set -e

# Configuration constants
readonly MIN_NODE_VERSION=20
readonly STACK_NAME_PREFIX="VpnAutomation"
readonly SECURE_STACK_PREFIX="VpnSecureParameters"
readonly DEFAULT_REGION="us-east-1"
readonly TIMEOUT_SECONDS=300

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
CDK_DIR="$PROJECT_ROOT/cdklib"

# Global variables initialization
PRODUCTION_URL=""
API_KEY_VALUE=""
DRY_RUN=${DRY_RUN:-false}

# Create logs directory if it doesn't exist
mkdir -p "$PROJECT_ROOT/logs"

# Load profile selector for AWS profile awareness
source "$PROJECT_ROOT/lib/profile_selector.sh" 2>/dev/null || {
    print_error "Failed to load profile selector library"
    exit 1
}

# Configuration management functions
load_deploy_config() {
    if [[ -f "$DEPLOY_CONFIG_FILE" ]]; then
        source "$DEPLOY_CONFIG_FILE"
        log_operation "INFO" "Loaded deployment configuration from $DEPLOY_CONFIG_FILE"
    fi
}

save_deploy_config() {
    local staging_profile="$1"
    local production_profile="$2"
    
    cat > "$DEPLOY_CONFIG_FILE" << EOF
# Deployment configuration - automatically generated on $(date)
# Override these values by setting environment variables

STAGING_PROFILE="${staging_profile}"
PRODUCTION_PROFILE="${production_profile}"
USE_SECURE_PARAMETERS="${USE_SECURE_PARAMETERS:-false}"

# Last deployment information
LAST_DEPLOYMENT_TIME="$(date '+%Y-%m-%d %H:%M:%S')"
LAST_DEPLOYMENT_USER="$(whoami)"
EOF
    chmod 600 "$DEPLOY_CONFIG_FILE"
    log_operation "INFO" "Saved deployment configuration to $DEPLOY_CONFIG_FILE"
}

# Load deployment configuration at startup
load_deploy_config

# Utility functions for reusable operations
get_stack_name() {
    local environment="$1"
    echo "${STACK_NAME_PREFIX}-${environment}"
}

get_secure_stack_name() {
    local environment="$1"
    echo "${SECURE_STACK_PREFIX}-${environment}"
}

# Get stack output value
get_stack_output() {
    local stack_name="$1"
    local output_key="$2"
    local profile="$3"
    
    aws cloudformation describe-stacks \
        --stack-name "$stack_name" \
        --query "Stacks[0].Outputs[?OutputKey==\`$output_key\`].OutputValue" \
        --output text \
        --profile "$profile" 2>/dev/null || echo ""
}

# Validate input function
validate_yes_no_input() {
    local prompt="$1"
    local response
    while true; do
        read -p "$prompt (y/N): " -n 1 -r response
        echo
        case "$response" in
            [Yy]) return 0 ;;
            [Nn]|"") return 1 ;;
            *) print_warning "Please enter 'y' or 'n'" ;;
        esac
    done
}

# Enhanced profile detection using new profile selector
get_env_profile() {
    local environment="$1"
    local interactive="${2:-false}"
    
    log_operation "INFO" "Getting profile for environment: $environment"
    
    # Try to get profile for specific environment
    local profile=$(get_profile_for_environment "$environment" 2>/dev/null)
    
    if [[ -n "$profile" ]]; then
        echo "$profile"
        return 0
    fi
    
    # If interactive mode and no profile found, prompt user
    if [[ "$interactive" == "true" ]]; then
        print_warning "No suitable profile found for $environment environment"
        profile=$(select_profile_interactive "$environment")
        if [[ -n "$profile" ]]; then
            echo "$profile"
            return 0
        fi
    fi
    
    # Fallback defaults
    case "$environment" in
        "prod"|"production") echo "prod" ;;
        "staging"|"dev") echo "default" ;;
        *) echo "default" ;;
    esac
}

# Enhanced error handling
handle_aws_error() {
    local exit_code=$1
    local operation="$2"
    if [ $exit_code -ne 0 ]; then
        print_error "AWS operation failed: $operation"
        return 1
    fi
}

# Safe AWS call wrapper
safe_aws_call() {
    local operation="$1"
    shift
    
    if ! "$@" 2>/dev/null; then
        print_error "AWS operation failed: $operation"
        return 1
    fi
}

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

# Logging function
log_operation() {
    local level="$1"
    local message="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [$level] $message" >> "$PROJECT_ROOT/logs/deploy.log"
}

# Function to store Slack URL history with secure permissions
store_slack_url() {
    local environment=$1
    local slack_url=$2
    local history_file="$PROJECT_ROOT/.slack-urls-history"
    
    # Create history file if it doesn't exist with secure permissions
    if [ ! -f "$history_file" ]; then
        umask 077
        touch "$history_file"
        chmod 600 "$history_file"
    fi
    
    # Store the URL with timestamp
    echo "${environment}|${slack_url}|$(date +%Y%m%d_%H%M%S)" >> "$history_file"
    log_operation "INFO" "Stored Slack URL for $environment"
}

# Function to get previous Slack URL
get_previous_slack_url() {
    local environment=$1
    local history_file="$PROJECT_ROOT/.slack-urls-history"
    
    if [ -f "$history_file" ]; then
        # Get the most recent URL for this environment
        grep "^${environment}|" "$history_file" | tail -2 | head -1 | cut -d'|' -f2
    else
        echo ""
    fi
}

# Function to notify about Slack URL changes
notify_slack_url_change() {
    local environment=$1
    local new_url=$2
    local previous_url=$(get_previous_slack_url "$environment")
    
    # Store the new URL
    store_slack_url "$environment" "$new_url"
    
    # Check if URL has changed
    if [ -n "$previous_url" ] && [ "$previous_url" != "$new_url" ]; then
        echo ""
        echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo -e "${RED}⚠️  IMPORTANT: Slack Webhook URL has changed! ⚠️${NC}"
        echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo ""
        echo -e "${YELLOW}Environment:${NC} $environment"
        echo -e "${RED}Previous URL:${NC} $previous_url"
        echo -e "${GREEN}New URL:${NC}      $new_url"
        echo ""
        echo -e "${YELLOW}ACTION REQUIRED:${NC}"
        echo "1. Go to your Slack App configuration: https://api.slack.com/apps"
        echo "2. Navigate to 'Slash Commands'"
        echo "3. Find the /vpn command"
        echo "4. Update the Request URL to:"
        echo -e "   ${BLUE}$new_url${NC}"
        echo "5. Save the changes"
        echo ""
        echo -e "${YELLOW}Without this update, your /vpn commands will fail with 'dispatch_unknown_error'${NC}"
        echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo ""
    elif [ -z "$previous_url" ]; then
        # First deployment
        echo ""
        echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo -e "${GREEN}🎉 First deployment completed! Configure your Slack App${NC}"
        echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo ""
        echo -e "${YELLOW}Environment:${NC} $environment"
        echo -e "${GREEN}Slack URL:${NC} $new_url"
        echo ""
        echo -e "${YELLOW}To enable /vpn commands:${NC}"
        echo "1. Go to your Slack App configuration: https://api.slack.com/apps"
        echo "2. Navigate to 'Slash Commands'"
        echo "3. Create or update the /vpn command"
        echo "4. Set the Request URL to:"
        echo -e "   ${BLUE}$new_url${NC}"
        echo "5. Save the changes"
        echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo ""
    else
        # URL unchanged
        echo ""
        echo -e "${GREEN}✅ Slack URL unchanged:${NC} $new_url"
    fi
}

# Function to check prerequisites
check_prerequisites() {
    print_status "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        print_error "AWS CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check if CDK is installed
    if ! command -v cdk &> /dev/null; then
        print_error "AWS CDK CLI is not installed. Please install it with: npm install -g aws-cdk"
        exit 1
    fi
    
    # Check if Node.js is installed
    if ! command -v node &> /dev/null; then
        print_error "Node.js is not installed. Please install Node.js 20+ first."
        exit 1
    fi
    
    # Check Node.js version
    NODE_VERSION=$(node --version | cut -d'v' -f2 | cut -d'.' -f1)
    if [ "$NODE_VERSION" -lt 20 ]; then
        print_error "Node.js version 20+ is required. Current version: $(node --version)"
        exit 1
    fi
    
    # Check if npx is available
    if ! command -v npx &> /dev/null; then
        print_error "npx is not available. Please install Node.js properly."
        exit 1
    fi
    
    # Check if TypeScript compilation tools are available
    cd "$CDK_DIR"
    if ! npx ts-node --version &> /dev/null; then
        print_error "TypeScript compilation tools not available. Run 'npm install' in cdklib directory."
        exit 1
    fi
    
    print_success "Prerequisites check passed"
}

# Function to setup Lambda dependencies
setup_lambda_dependencies() {
    print_status "Setting up Lambda dependencies..."
    
    cd "$PROJECT_ROOT/lambda"
    
    if [ ! -f "package-lock.json" ]; then
        print_status "Installing Lambda dependencies..."
        npm install
    else
        print_status "Lambda dependencies already installed"
    fi
    
    print_status "Building Lambda functions..."
    
    # Build slack-handler function
    if [ -f "$PROJECT_ROOT/lambda/slack-handler/build.sh" ]; then
        print_status "Building slack-handler Lambda function..."
        cd "$PROJECT_ROOT/lambda/slack-handler"
        ./build.sh
    else
        print_status "No build script found for slack-handler, skipping..."
    fi
    
    # Build vpn-control function
    if [ -f "$PROJECT_ROOT/lambda/vpn-control/build.sh" ]; then
        print_status "Building vpn-control Lambda function..."
        cd "$PROJECT_ROOT/lambda/vpn-control"
        ./build.sh
    else
        print_status "No build script found for vpn-control, skipping..."
    fi
    
    # Build vpn-monitor function
    if [ -f "$PROJECT_ROOT/lambda/vpn-monitor/build.sh" ]; then
        print_status "Building vpn-monitor Lambda function..."
        cd "$PROJECT_ROOT/lambda/vpn-monitor"
        ./build.sh
    else
        print_status "No build script found for vpn-monitor, skipping..."
    fi
    
    # Build shared layer
    print_status "Building shared Lambda layer..."
    cd "$PROJECT_ROOT/lambda/shared"
    if [ -f "build-layer.sh" ]; then
        ./build-layer.sh
        print_status "Shared layer built successfully"
    elif [ -f "tsconfig.json" ]; then
        npx tsc
        print_status "Shared layer compiled successfully"
    else
        print_status "No build script found for shared layer, skipping..."
    fi
    
    # Return to lambda directory
    cd "$PROJECT_ROOT/lambda"
    
    print_success "Lambda setup completed"
    print_status "Lambda functions configured with 256MB memory for optimal performance"
    print_status "Slack handler timeout set to 15s to meet Slack's 3-second response requirement"
}

# Function to setup CDK dependencies
setup_cdk_dependencies() {
    print_status "Setting up CDK dependencies..."
    
    cd "$CDK_DIR"
    
    if [ ! -f "package-lock.json" ]; then
        print_status "Installing CDK dependencies..."
        npm install
    else
        print_status "CDK dependencies already installed"
    fi
    
    print_status "Building CDK project..."
    npm run build
    
    print_success "CDK setup completed"
}

# Function to validate AWS credentials and profile
validate_aws_profile() {
    local profile=$1
    local environment=$2
    
    print_status "Validating AWS profile: $profile for $environment environment"
    log_operation "INFO" "Validating AWS profile: $profile for $environment"
    
    # Test AWS credentials
    if ! safe_aws_call "test credentials" aws sts get-caller-identity --profile "$profile"; then
        print_error "AWS profile '$profile' is not configured or credentials are invalid"
        print_error "Please configure your AWS profile with: aws configure --profile $profile"
        log_operation "ERROR" "Invalid AWS profile: $profile"
        exit 1
    fi
    
    # Get account ID safely
    local account_id
    account_id=$(aws sts get-caller-identity --profile "$profile" --query Account --output text 2>/dev/null)
    if [[ -z "$account_id" ]]; then
        print_error "Failed to get account ID for profile: $profile"
        return 1
    fi
    
    ACCOUNT_ID="$account_id"
    print_status "Account ID: $ACCOUNT_ID"
    log_operation "INFO" "Validated profile $profile, Account ID: $ACCOUNT_ID"
    
    # Check if CDK is bootstrapped for this account/region
    REGION=$(aws configure get region --profile "$profile" || echo "us-east-1")
    export CDK_DEFAULT_REGION="$REGION"
    export CDK_DEFAULT_ACCOUNT="$ACCOUNT_ID"
    
    print_status "Using region: $REGION"
    
    # Bootstrap CDK if needed
    print_status "Checking CDK bootstrap status..."
    if ! aws cloudformation describe-stacks --stack-name CDKToolkit --profile "$profile" --region "$REGION" &> /dev/null; then
        print_warning "CDK is not bootstrapped for this account/region. Bootstrapping now..."
        cd "$CDK_DIR"
        AWS_PROFILE="$profile" cdk bootstrap
        print_success "CDK bootstrap completed"
    else
        print_status "CDK is already bootstrapped"
    fi
}

# Map environment names between config directories and CDK stack names
map_env_to_config_dir() {
    local env="$1"
    case "$env" in
        "production") echo "prod" ;;
        "staging") echo "staging" ;;
        "prod") echo "prod" ;;
        *) echo "$env" ;;
    esac
}

# Map config directory names to CDK environment names
map_config_dir_to_cdk_env() {
    local config_dir="$1"
    case "$config_dir" in
        "prod") echo "production" ;;
        "staging") echo "staging" ;;
        *) echo "$config_dir" ;;
    esac
}

# Auto-detect and set CDK environment variables from AWS profile
auto_set_cdk_environment() {
    local profile="$1"
    
    if [ -z "$CDK_DEFAULT_ACCOUNT" ] || [ -z "$CDK_DEFAULT_REGION" ]; then
        print_status "Auto-detecting CDK environment from AWS profile: $profile"
        
        local account_id=$(aws sts get-caller-identity --profile "$profile" --query Account --output text 2>/dev/null)
        local region=$(aws configure get region --profile "$profile" 2>/dev/null || echo "us-east-1")
        
        if [ -n "$account_id" ] && [ "$account_id" != "None" ]; then
            export CDK_DEFAULT_ACCOUNT="$account_id"
            export CDK_DEFAULT_REGION="$region"
            print_status "CDK Account: $account_id"
            print_status "CDK Region: $region"
        else
            print_error "Failed to detect AWS account ID for profile: $profile"
            return 1
        fi
    fi
}

# Add validation function after print functions
validate_deployment_environment() {
    local environment=$1
    local profile=$2
    
    print_status "Validating deployment environment: $environment"
    
    # Auto-set CDK environment variables if not already set
    if ! auto_set_cdk_environment "$profile"; then
        return 1
    fi
    
    # Validate AWS environment variables
    if [ -z "$CDK_DEFAULT_ACCOUNT" ] || [ -z "$CDK_DEFAULT_REGION" ]; then
        print_error "CDK 環境變數未設置"
        print_error "請設置 CDK_DEFAULT_ACCOUNT 和 CDK_DEFAULT_REGION"
        return 1
    fi
    
    print_status "CDK Account: $CDK_DEFAULT_ACCOUNT"
    print_status "CDK Region: $CDK_DEFAULT_REGION"
    
    # Validate AWS profile has necessary permissions
    if ! aws iam get-user --profile "$profile" &> /dev/null; then
        print_warning "無法驗證 profile 的 IAM 權限: $profile"
        print_warning "請確保 AWS profile 已正確配置"
    else
        print_success "AWS profile validation successful: $profile"
    fi
    
    # Validate CDK is properly installed
    if ! command -v cdk &> /dev/null; then
        print_error "CDK 未安裝或不在 PATH 中"
        return 1
    fi
    
    return 0
}

# Function to update staging Lambda environment variables with production API details
update_staging_lambda_config() {
    local staging_profile=$1
    local production_api_endpoint=$2
    local production_api_key=$3
    
    print_status "🔧 Updating staging Lambda environment variables..."
    
    # Get the staging Slack handler function name
    local slack_function_name=$(aws lambda list-functions \
        --profile "$staging_profile" \
        --query 'Functions[?contains(FunctionName, `SlackHandler`) && contains(FunctionName, `staging`)].FunctionName' \
        --output text 2>/dev/null | head -1)
    
    if [ -n "$slack_function_name" ]; then
        print_status "Updating Lambda function: $slack_function_name"
        
        # Get current environment variables
        local current_env=$(aws lambda get-function-configuration \
            --function-name "$slack_function_name" \
            --profile "$staging_profile" \
            --query 'Environment.Variables' \
            --output json 2>/dev/null)
        
        if [ -n "$current_env" ] && [ "$current_env" != "null" ]; then
            # Update the production API configuration
            local updated_env=$(echo "$current_env" | jq \
                --arg endpoint "$production_api_endpoint" \
                --arg key "$production_api_key" \
                '.PRODUCTION_API_ENDPOINT = $endpoint | .PRODUCTION_API_KEY = $key')
            
            # Apply the updated environment variables with better error handling
            if aws lambda update-function-configuration \
                --function-name "$slack_function_name" \
                --environment "Variables=$updated_env" \
                --profile "$staging_profile" \
                --output json > /dev/null 2>&1; then
                print_success "✅ Lambda environment variables updated successfully"
                log_operation "INFO" "Updated Lambda environment variables for $slack_function_name"
            else
                local error_msg=$(aws lambda update-function-configuration \
                    --function-name "$slack_function_name" \
                    --environment "Variables=$updated_env" \
                    --profile "$staging_profile" 2>&1 || echo "Unknown error")
                print_warning "⚠️  Failed to update Lambda environment variables: ${error_msg:0:100}"
                log_operation "ERROR" "Failed to update Lambda environment variables: $error_msg"
                # Continue anyway as this is not critical for deployment
            fi
        else
            print_warning "⚠️  Could not retrieve current Lambda environment variables"
        fi
    else
        print_warning "⚠️  Could not find staging Slack handler function"
    fi
}

# Function to automatically update staging cross-account configuration
update_staging_cross_account_config() {
    local staging_profile=$1
    local production_url=$2
    local production_profile=$3
    
    print_status "Updating staging cross-account configuration..."
    
    # Get production API key value
    local api_key_id=$(aws cloudformation describe-stacks \
        --stack-name VpnAutomation-production \
        --query 'Stacks[0].Outputs[?OutputKey==`ApiKeyId`].OutputValue' \
        --output text \
        --profile "$production_profile" 2>/dev/null || echo "")
    
    local api_key_value=""
    if [ -n "$api_key_id" ] && [ "$api_key_id" != "None" ]; then
        api_key_value=$(aws apigateway get-api-key \
            --api-key "$api_key_id" \
            --include-value \
            --query 'value' \
            --output text \
            --profile "$production_profile" 2>/dev/null || echo "")
    fi
    
    # Create the cross-account configuration JSON
    local cross_account_config=$(cat <<EOF
{
  "productionApiEndpoint": "${production_url}vpn",
  "productionApiKey": "${api_key_value:-PLACEHOLDER_PRODUCTION_API_KEY}",
  "retryConfig": {
    "maxRetries": 3,
    "backoffMultiplier": 2,
    "baseDelayMs": 1000
  }
}
EOF
)
    
    # Update the staging parameter store
    if aws ssm put-parameter \
        --name "/vpn/staging/cross_account/config" \
        --value "$cross_account_config" \
        --type "String" \
        --overwrite \
        --profile "$staging_profile" &> /dev/null; then
        
        if [ -n "$api_key_value" ]; then
            print_success "✅ Cross-account routing configured with production API key"
        else
            print_status "ℹ️  Cross-account routing configured - API key will be retrieved during runtime"
        fi
    else
        print_error "❌ Failed to update staging cross-account configuration"
    fi
}

# Function to deploy production environment
deploy_production() {
    print_status "🚀 Deploying to production environment"
    
    local profile=${PRODUCTION_PROFILE:-$(get_env_profile "prod" 2>/dev/null || echo "prod")}
    local use_secure_params=${USE_SECURE_PARAMETERS:-false}
    
    # Validate environment before deployment
    if ! validate_deployment_environment "production" "$profile"; then
        print_error "生產環境驗證失敗"
        return 1
    fi
    
    validate_aws_profile "$profile" "production"
    
    cd "$CDK_DIR"
    
    if [ "$use_secure_params" = "true" ]; then
        deploy_with_secure_parameters "production" "$profile"
    else
        print_status "Deploying production stack..."
        ENVIRONMENT=production AWS_PROFILE="$profile" cdk deploy --all --app "npx ts-node bin/vpn-automation.ts" --require-approval never --context environment="production"
    fi
    
    print_success "✅ Production deployment completed!"
    
    # Get production API Gateway URL
    PRODUCTION_URL=$(aws cloudformation describe-stacks \
        --stack-name VpnAutomation-production \
        --query 'Stacks[0].Outputs[?OutputKey==`ApiGatewayUrl`].OutputValue' \
        --output text \
        --profile "$profile" 2>/dev/null || echo "")
    
    if [ -n "$PRODUCTION_URL" ]; then
        # Save production URL for staging deployment
        echo "export PRODUCTION_API_ENDPOINT=\"${PRODUCTION_URL}vpn\"" > "$PROJECT_ROOT/.production-url"
        
        # Get API key if it exists
        API_KEY_ID=$(aws cloudformation describe-stacks \
            --stack-name VpnAutomation-production \
            --query 'Stacks[0].Outputs[?OutputKey==`ApiKeyId`].OutputValue' \
            --output text \
            --profile "$profile" 2>/dev/null || echo "")
        
        if [ -n "$API_KEY_ID" ] && [ "$API_KEY_ID" != "None" ]; then
            API_KEY_VALUE=$(aws apigateway get-api-key \
                --api-key "$API_KEY_ID" \
                --include-value \
                --query 'value' \
                --output text \
                --profile "$profile" 2>/dev/null || echo "")
            
            if [ -n "$API_KEY_VALUE" ]; then
                echo "export PRODUCTION_API_KEY=\"$API_KEY_VALUE\"" >> "$PROJECT_ROOT/.production-url"
                print_success "Production API configuration saved with authentication"
            else
                print_status "API key value not retrieved - will be configured during runtime"
            fi
        else
            print_status "Production API key will be managed via parameter store"
        fi
        
        print_success "Production API URL saved: $PRODUCTION_URL"
    fi
    
    # Get and check Slack endpoint URL
    SLACK_ENDPOINT=$(aws cloudformation describe-stacks \
        --stack-name VpnAutomation-production \
        --query 'Stacks[0].Outputs[?OutputKey==`SlackEndpoint`].OutputValue' \
        --output text \
        --profile "$profile" 2>/dev/null || echo "")
    
    if [ -n "$SLACK_ENDPOINT" ]; then
        notify_slack_url_change "production" "$SLACK_ENDPOINT"
    fi
    
    print_status "💡 To deploy staging, run: $0 staging"
}

# Get production API details for staging deployment
get_production_api_details() {
    local production_profile="$1"
    local production_url=""
    local api_key_value=""
    
    print_status "📡 Getting production API Gateway URL..."
    
    # Try to get production URL from CloudFormation
    production_url=$(safe_aws_call "get production URL" aws cloudformation describe-stacks \
        --stack-name VpnAutomation-production \
        --query 'Stacks[0].Outputs[?OutputKey==`ApiGatewayUrl`].OutputValue' \
        --output text \
        --profile "$production_profile" 2>/dev/null || echo "")
    
    # Try to get API key from production stack
    if [ -n "$production_url" ] && [ "$production_url" != "None" ]; then
        local api_key_id
        api_key_id=$(safe_aws_call "get API key ID" aws cloudformation describe-stacks \
            --stack-name VpnAutomation-production \
            --query 'Stacks[0].Outputs[?OutputKey==`ApiKeyId`].OutputValue' \
            --output text \
            --profile "$production_profile" 2>/dev/null || echo "")
        
        if [ -n "$api_key_id" ] && [ "$api_key_id" != "None" ]; then
            api_key_value=$(safe_aws_call "get API key value" aws apigateway get-api-key \
                --api-key "$api_key_id" \
                --include-value \
                --query 'value' \
                --output text \
                --profile "$production_profile" 2>/dev/null || echo "")
            
            if [ -n "$api_key_value" ]; then
                print_status "✅ Retrieved production API key for cross-account authentication"
            fi
        fi
    fi
    
    # Try to load from saved file if CloudFormation query failed
    if [ -z "$production_url" ] && [ -f "$PROJECT_ROOT/.production-url" ]; then
        source "$PROJECT_ROOT/.production-url"
        production_url=$(echo "$PRODUCTION_API_ENDPOINT" | sed 's/vpn$//')
        
        if [ -n "$PRODUCTION_API_KEY" ]; then
            api_key_value="$PRODUCTION_API_KEY"
            print_status "✅ Found saved production API configuration with authentication"
        fi
    fi
    
    # Return values via global variables
    PRODUCTION_URL="$production_url"
    API_KEY_VALUE="$api_key_value"
}

# Deploy staging environment with CDK
deploy_staging_cdk() {
    local profile="$1"
    local use_secure_params="$2"
    
    cd "$CDK_DIR" || {
        print_error "Failed to change to CDK directory: $CDK_DIR"
        return 1
    }
    
    if [ "$use_secure_params" = "true" ]; then
        print_status "🔒 Deploying staging with secure parameter management..."
        deploy_with_secure_parameters "staging" "$profile"
    else
        print_status "🚀 Deploying staging environment..."
        
        # Set up environment variables for staging deployment
        export PRODUCTION_API_ENDPOINT="${PRODUCTION_URL}vpn"
        export ENVIRONMENT=staging
        export AWS_PROFILE="$profile"
        
        # Include API key if available
        if [ -n "$API_KEY_VALUE" ]; then
            export PRODUCTION_API_KEY="$API_KEY_VALUE"
            print_status "🔐 Deploying with production API authentication"
        else
            print_status "ℹ️  Deploying without production API key - cross-account calls will use existing configuration"
        fi
        
        if ! safe_aws_call "CDK deploy staging" cdk deploy --all --app "npx ts-node bin/vpn-automation.ts" --require-approval never --context environment="staging"; then
            print_error "Failed to deploy staging environment"
            return 1
        fi
    fi
}

# Configure staging cross-account routing
configure_staging_cross_account() {
    local profile="$1"
    local production_profile="$2"
    
    print_status "🔧 Automatically configuring cross-account routing parameters..."
    update_staging_cross_account_config "$profile" "$PRODUCTION_URL" "$production_profile"
    
    # Always update the Lambda environment variables for immediate effect
    print_status "🔄 Re-fetching production API details for Lambda configuration..."
    
    local final_production_url=""
    local final_production_api_key=""
    
    # Try to get fresh production API details
    if [ -n "$production_profile" ]; then
        final_production_url=$(safe_aws_call "get final production URL" aws cloudformation describe-stacks \
            --stack-name VpnAutomation-production \
            --query 'Stacks[0].Outputs[?OutputKey==`ApiGatewayUrl`].OutputValue' \
            --output text \
            --profile "$production_profile" 2>/dev/null || echo "")
        
        if [ -n "$final_production_url" ] && [ "$final_production_url" != "None" ]; then
            final_production_url="${final_production_url}vpn"
            
            # Get API key
            local api_key_id
            api_key_id=$(safe_aws_call "get final API key ID" aws cloudformation describe-stacks \
                --stack-name VpnAutomation-production \
                --query 'Stacks[0].Outputs[?OutputKey==`ApiKeyId`].OutputValue' \
                --output text \
                --profile "$production_profile" 2>/dev/null || echo "")
            
            if [ -n "$api_key_id" ] && [ "$api_key_id" != "None" ]; then
                final_production_api_key=$(safe_aws_call "get final API key value" aws apigateway get-api-key \
                    --api-key "$api_key_id" \
                    --include-value \
                    --query 'value' \
                    --output text \
                    --profile "$production_profile" 2>/dev/null || echo "")
            fi
        fi
    fi
    
    # Update Lambda environment variables if we have production details
    if [ -n "$final_production_url" ] && [ -n "$final_production_api_key" ]; then
        update_staging_lambda_config "$profile" "$final_production_url" "$final_production_api_key"
        print_success "✅ Lambda environment variables updated with production API details"
        export PRODUCTION_API_KEY="$final_production_api_key"  # Update for the status message below
    else
        print_status "ℹ️  Lambda will use parameter store for cross-account routing (production API not available)"
    fi
    
    if [ -n "$PRODUCTION_API_KEY" ]; then
        print_success "🔐 Cross-account authentication configured successfully"
    else
        print_status "ℹ️  Cross-account authentication will be configured via parameter store during runtime"
    fi
}

# Function to deploy staging environment
deploy_staging() {
    print_status "🚀 Deploying to staging environment"
    
    local profile=${STAGING_PROFILE:-$(get_env_profile "staging" 2>/dev/null || echo "default")}
    local use_secure_params=${USE_SECURE_PARAMETERS:-false}
    
    # Validate environment
    if ! validate_deployment_environment "staging" "$profile"; then
        print_error "Staging environment validation failed"
        return 1
    fi
    
    validate_aws_profile "$profile" "staging"
    
    # Get production profile and API details
    local production_profile=${PRODUCTION_PROFILE:-$(get_env_profile "prod" 2>/dev/null || echo "prod")}
    get_production_api_details "$production_profile"
    
    if [ -z "$PRODUCTION_URL" ] || [ "$PRODUCTION_URL" = "None" ]; then
        print_error "❌ Cannot get production API Gateway URL."
        print_error "Please ensure production is deployed first: $0 production"
        return 1
    fi
    
    print_success "✅ Found production URL: $PRODUCTION_URL"
    
    # Deploy staging environment
    if ! deploy_staging_cdk "$profile" "$use_secure_params"; then
        return 1
    fi
    
    print_success "✅ Staging deployment completed!"
    print_success "🔗 Staging will route production commands to: $PRODUCTION_URL"
    
    # Get and check Slack endpoint URL for staging
    local slack_endpoint
    slack_endpoint=$(safe_aws_call "get Slack endpoint" aws cloudformation describe-stacks \
        --stack-name VpnAutomation-staging \
        --query 'Stacks[0].Outputs[?OutputKey==`SlackEndpoint`].OutputValue' \
        --output text \
        --profile "$profile" 2>/dev/null || echo "")
    
    if [ -n "$slack_endpoint" ]; then
        notify_slack_url_change "staging" "$slack_endpoint"
    fi
    
    # Configure cross-account routing
    configure_staging_cross_account "$profile" "$production_profile"
}

# Function to deploy both environments
deploy_both() {
    print_status "🚀 Deploying both environments..."
    
    local staging_profile=${STAGING_PROFILE:-$(get_env_profile "staging" 2>/dev/null || echo "default")}
    local production_profile=${PRODUCTION_PROFILE:-$(get_env_profile "prod" 2>/dev/null || echo "prod")}
    
    # Save configuration for future deployments
    save_deploy_config "$staging_profile" "$production_profile"
    
    # Deploy production first to get API details
    deploy_production
    echo ""
    
    # Deploy staging with production API configuration
    deploy_staging
    
    # Ensure cross-account configuration is properly set up
    print_status "🔧 Finalizing cross-account configuration..."
    local production_profile=${PRODUCTION_PROFILE:-$(get_env_profile "prod" 2>/dev/null || echo "prod")}
    local staging_profile=${STAGING_PROFILE:-$(get_env_profile "staging" 2>/dev/null || echo "default")}
    
    # Get production API details
    local production_url=$(aws cloudformation describe-stacks \
        --stack-name VpnAutomation-production \
        --query 'Stacks[0].Outputs[?OutputKey==`VpnControlEndpoint`].OutputValue' \
        --output text \
        --profile "$production_profile" 2>/dev/null || echo "")
    
    local api_key_id=$(aws cloudformation describe-stacks \
        --stack-name VpnAutomation-production \
        --query 'Stacks[0].Outputs[?OutputKey==`ApiKeyId`].OutputValue' \
        --output text \
        --profile "$production_profile" 2>/dev/null || echo "")
    
    local production_api_key=""
    if [ -n "$api_key_id" ] && [ "$api_key_id" != "None" ]; then
        production_api_key=$(aws apigateway get-api-key \
            --api-key "$api_key_id" \
            --include-value \
            --query 'value' \
            --output text \
            --profile "$production_profile" 2>/dev/null || echo "")
    fi
    
    # Update staging Lambda environment variables if we have the production details
    if [ -n "$production_url" ] && [ -n "$production_api_key" ]; then
        update_staging_lambda_config "$staging_profile" "$production_url" "$production_api_key"
        print_success "✅ Cross-account routing configured successfully"
    else
        print_warning "⚠️  Could not configure cross-account routing - missing production API details"
    fi
    
    print_success "🎉 Both environments deployed successfully!"
    
    # Final configuration summary
    echo ""
    print_status "=== Deployment Summary ==="
    print_success "Production environment: Deployed with profile $production_profile"
    print_success "Staging environment: Deployed with profile $staging_profile"
    print_status "Configuration saved to: $DEPLOY_CONFIG_FILE"
    
    if [ "$USE_SECURE_PARAMETERS" = "true" ]; then
        print_status "Next steps: Configure parameters with scripts/setup-parameters.sh --all --secure"
    fi
    
    echo ""
    print_status "📈 Deployment completed successfully! Check CloudWatch dashboards for monitoring."
}

# Function to destroy environment
destroy_environment() {
    local environment=$1
    local profile
    
    if [ "$environment" = "production" ]; then
        profile=${PRODUCTION_PROFILE:-$(get_env_profile "prod" 2>/dev/null || echo "prod")}
    else
        profile=${STAGING_PROFILE:-$(get_env_profile "staging" 2>/dev/null || echo "default")}
    fi
    
    print_warning "⚠️  Destroying $environment environment..."
    print_warning "This will delete all resources in the VpnAutomation-$environment stack"
    
    read -p "Are you sure you want to continue? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_status "Destruction cancelled"
        exit 0
    fi
    
    validate_aws_profile "$profile" "$environment"
    
    cd "$CDK_DIR"
    
    print_status "Destroying $environment stack..."
    ENVIRONMENT="$environment" AWS_PROFILE="$profile" cdk destroy --app "npx ts-node bin/vpn-automation.ts" --context environment="$environment" --force
    
    print_success "✅ $environment environment destroyed"
}

# Function to show usage
show_usage() {
    echo "VPN Cost Automation Deployment Script"
    echo ""
    echo "Usage: $0 [command] [options]"
    echo ""
    echo "Commands:"
    echo "  production       Deploy production environment only"
    echo "  staging          Deploy staging environment (requires production to exist)"
    echo "  both             Deploy production first, then staging"
    echo "  destroy-staging  Destroy staging environment"
    echo "  destroy-production  Destroy production environment"
    echo "  diff-staging     Show differences for staging deployment"
    echo "  diff-production  Show differences for production deployment"
    echo "  status           Show deployment status"
    echo "  validate-routing Validate cross-account routing configuration"
    echo ""
    echo "Options:"
    echo "  --secure-parameters  Enable Epic 5.1 secure parameter management with KMS encryption"
    echo ""
    echo "Environment Variables:"
    echo "  STAGING_PROFILE         AWS profile for staging (default: auto-detected from config)"
    echo "  PRODUCTION_PROFILE      AWS profile for production (default: auto-detected from config)"
    echo "  USE_SECURE_PARAMETERS   Enable secure parameter management (default: false)"
    echo ""
    echo "Examples:"
    echo "  $0 production                           # Deploy production environment"
    echo "  $0 staging                              # Deploy staging environment"
    echo "  $0 both                                 # Deploy both environments"
    echo "  $0 production --secure-parameters       # Deploy with Epic 5.1 secure parameters"
    echo "  USE_SECURE_PARAMETERS=true $0 both      # Deploy both with secure parameters"
    echo "  STAGING_PROFILE=dev $0 staging          # Use custom profile"
    echo ""
    echo "Epic 5.1 - Secure Parameter Management:"
    echo "  Use --secure-parameters flag to enable:"
    echo "  • KMS encryption for sensitive parameters"
    echo "  • SecureString parameter types for secrets"
    echo "  • Least-privilege IAM policies"
    echo "  • Parameter validation and configuration management"
    echo ""
    echo "First-time setup:"
    echo "  1. Configure AWS profiles: aws configure --profile production && aws configure --profile staging"
    echo "  2. Deploy both environments: $0 both --secure-parameters"
    echo "  3. Configure all parameters: scripts/setup-parameters.sh --all --auto-read --secure \\"
    echo "       --slack-webhook URL --slack-secret SECRET --slack-bot-token TOKEN"
    echo ""
    echo "⚠️  Important: After deployment, parameters contain placeholder values."
    echo "    You MUST run setup-parameters.sh with --all to configure real values."
    echo ""
    echo "💡 Tip: Slack parameters are shared across environments - configure once for both!"
}

# Function to show diff
show_diff() {
    local environment=$1
    local profile
    
    if [ "$environment" = "production" ]; then
        profile=${PRODUCTION_PROFILE:-$(get_env_profile "prod" 2>/dev/null || echo "prod")}
    else
        profile=${STAGING_PROFILE:-$(get_env_profile "staging" 2>/dev/null || echo "default")}
    fi
    
    validate_aws_profile "$profile" "$environment"
    
    cd "$CDK_DIR"
    
    print_status "Showing differences for $environment environment..."
    
    if [ "$environment" = "staging" ]; then
        # For staging, we need production URL
        local production_profile=${PRODUCTION_PROFILE:-$(get_env_profile "prod" 2>/dev/null || echo "prod")}
        PRODUCTION_URL=$(aws cloudformation describe-stacks \
            --stack-name VpnAutomation-production \
            --query 'Stacks[0].Outputs[?OutputKey==`ApiGatewayUrl`].OutputValue' \
            --output text \
            --profile "$production_profile" 2>/dev/null || echo "")
        
        if [ -n "$PRODUCTION_URL" ]; then
            PRODUCTION_API_ENDPOINT="${PRODUCTION_URL}vpn" \
            ENVIRONMENT="$environment" \
            AWS_PROFILE="$profile" \
            cdk diff --app "npx ts-node bin/vpn-automation.ts" --context environment="$environment"
        else
            print_warning "Production environment not found, showing diff without production URL"
            ENVIRONMENT="$environment" AWS_PROFILE="$profile" cdk diff --app "npx ts-node bin/vpn-automation.ts" --context environment="$environment"
        fi
    else
        ENVIRONMENT="$environment" AWS_PROFILE="$profile" cdk diff --app "npx ts-node bin/vpn-automation.ts" --context environment="$environment"
    fi
}

# Function to validate cross-account routing configuration
validate_cross_account_routing() {
    print_status "Validating cross-account routing configuration..."
    
    local staging_profile=${STAGING_PROFILE:-$(get_env_profile "staging" 2>/dev/null || echo "staging")}
    local production_profile=${PRODUCTION_PROFILE:-$(get_env_profile "prod" 2>/dev/null || echo "prod")}
    
    # Check if both environments are deployed
    if ! aws cloudformation describe-stacks --stack-name VpnAutomation-production --profile "$production_profile" &> /dev/null; then
        print_error "Production environment not deployed - cross-account routing will fail"
        return 1
    fi
    
    if ! aws cloudformation describe-stacks --stack-name VpnAutomation-staging --profile "$staging_profile" &> /dev/null; then
        print_error "Staging environment not deployed - cross-account routing not applicable"
        return 1
    fi
    
    # Get production API URL
    PRODUCTION_URL=$(aws cloudformation describe-stacks \
        --stack-name VpnAutomation-production \
        --query 'Stacks[0].Outputs[?OutputKey==`ApiGatewayUrl`].OutputValue' \
        --output text \
        --profile "$production_profile" 2>/dev/null)
    
    if [ -z "$PRODUCTION_URL" ] || [ "$PRODUCTION_URL" = "None" ]; then
        print_error "Could not retrieve production API URL"
        return 1
    fi
    
    # Check if API key exists
    API_KEY_ID=$(aws cloudformation describe-stacks \
        --stack-name VpnAutomation-production \
        --query 'Stacks[0].Outputs[?OutputKey==`ApiKeyId`].OutputValue' \
        --output text \
        --profile "$production_profile" 2>/dev/null || echo "")
    
    if [ -z "$API_KEY_ID" ] || [ "$API_KEY_ID" = "None" ]; then
        print_warning "No API key found in production - authentication will fail"
    else
        print_success "API key found: $API_KEY_ID"
    fi
    
    # Test API connectivity (if curl is available)
    if command -v curl &> /dev/null && [ -n "$API_KEY_ID" ]; then
        API_KEY_VALUE=$(aws apigateway get-api-key \
            --api-key "$API_KEY_ID" \
            --include-value \
            --query 'value' \
            --output text \
            --profile "$production_profile" 2>/dev/null || echo "")
        
        if [ -n "$API_KEY_VALUE" ]; then
            print_status "Testing production API connectivity..."
            HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
                -X POST \
                -H "Content-Type: application/json" \
                -H "X-API-Key: $API_KEY_VALUE" \
                -d '{"command":{"action":"check","environment":"production","user":"test","requestId":"health-check"},"sourceAccount":"staging"}' \
                "${PRODUCTION_URL}vpn" 2>/dev/null || echo "000")
            
            if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "400" ]; then
                print_success "Production API is reachable (HTTP $HTTP_CODE)"
            else
                print_warning "Production API returned HTTP $HTTP_CODE - check network/permissions"
            fi
        fi
    fi
    
    print_success "Cross-account routing validation completed"
}

# Function to validate secure parameters deployment
validate_secure_parameters() {
    local environment="$1"
    local profile="$2"
    
    print_status "Validating secure parameters for $environment..."
    
    # Check if the secure parameter stack exists
    local secure_stack_name="VpnSecureParameters-$environment"
    if ! aws cloudformation describe-stacks --stack-name "$secure_stack_name" --profile "$profile" &> /dev/null; then
        print_warning "Secure parameter stack not found: $secure_stack_name"
        return 1
    fi
    
    # Check if basic parameters exist
    local required_params=(
        "/vpn/$environment/endpoint/id"
        "/vpn/$environment/cost/optimization_config"
        "/vpn/slack/webhook"
    )
    
    local missing_params=0
    for param in "${required_params[@]}"; do
        if ! aws ssm get-parameter --name "$param" --profile "$profile" &> /dev/null; then
            print_warning "Missing parameter: $param"
            ((missing_params++))
        fi
    done
    
    if [ $missing_params -eq 0 ]; then
        print_success "All required parameters are present"
        return 0
    else
        print_warning "$missing_params parameters are missing"
        return 1
    fi
}

# Function to show deployment status
show_status() {
    print_status "Checking deployment status..."
    
    local staging_profile=${STAGING_PROFILE:-$(get_env_profile "staging" 2>/dev/null || echo "staging")}
    local production_profile=${PRODUCTION_PROFILE:-$(get_env_profile "prod" 2>/dev/null || echo "prod")}
    
    # Check production
    if aws cloudformation describe-stacks --stack-name VpnAutomation-production --profile "$production_profile" &> /dev/null; then
        print_success "✅ Production environment is deployed"
        PRODUCTION_URL=$(aws cloudformation describe-stacks \
            --stack-name VpnAutomation-production \
            --query 'Stacks[0].Outputs[?OutputKey==`ApiGatewayUrl`].OutputValue' \
            --output text \
            --profile "$production_profile" 2>/dev/null)
        if [ -n "$PRODUCTION_URL" ]; then
            echo "   Production API: $PRODUCTION_URL"
        fi
    else
        print_warning "⚠️  Production environment is not deployed"
    fi
    
    # Check staging
    if aws cloudformation describe-stacks --stack-name VpnAutomation-staging --profile "$staging_profile" &> /dev/null; then
        print_success "✅ Staging environment is deployed"
        STAGING_URL=$(aws cloudformation describe-stacks \
            --stack-name VpnAutomation-staging \
            --query 'Stacks[0].Outputs[?OutputKey==`ApiGatewayUrl`].OutputValue' \
            --output text \
            --profile "$staging_profile" 2>/dev/null)
        if [ -n "$STAGING_URL" ]; then
            echo "   Staging API: $STAGING_URL"
        fi
    else
        print_warning "⚠️  Staging environment is not deployed"
    fi
}

# Function to deploy with secure parameter management (Epic 5.1)
deploy_with_secure_parameters() {
    local environment=$1
    local profile=$2
    
    print_status "🔒 Epic 5.1: Deploying with secure parameter management..."
    
    cd "$CDK_DIR"
    
    # Deploy both stacks with correct app entry point and context
    print_status "Deploying secure VPN automation with parameter management..."
    
    # Set CDK context for environment
    export CDK_CONTEXT_ENVIRONMENT="$environment"
    
    if [ "$environment" = "staging" ]; then
        # For staging, include production URL if available
        if [ -n "$PRODUCTION_API_ENDPOINT" ]; then
            PRODUCTION_API_ENDPOINT="$PRODUCTION_API_ENDPOINT" \
            PRODUCTION_API_KEY="$PRODUCTION_API_KEY" \
            ENVIRONMENT="$environment" \
            AWS_PROFILE="$profile" \
            cdk deploy --all --app "npx ts-node bin/vpn-secure-automation.ts" \
            --require-approval never \
            --context environment="$environment"
        else
            ENVIRONMENT="$environment" AWS_PROFILE="$profile" \
            cdk deploy --all --app "npx ts-node bin/vpn-secure-automation.ts" \
            --require-approval never \
            --context environment="$environment"
        fi
    else
        ENVIRONMENT="$environment" AWS_PROFILE="$profile" \
        cdk deploy --all --app "npx ts-node bin/vpn-secure-automation.ts" \
        --require-approval never \
        --context environment="$environment"
    fi
    
    print_success "✅ Secure parameter management deployment completed!"
    
    # Automatically update staging cross-account configuration if this is staging deployment
    if [ "$environment" = "staging" ]; then
        print_status "🔧 Automatically configuring cross-account routing parameters..."
        
        # Get production profile and URL for staging configuration
        local production_profile=${PRODUCTION_PROFILE:-"prod"}
        local production_url=$(aws cloudformation describe-stacks \
            --stack-name VpnAutomation-production \
            --query 'Stacks[0].Outputs[?OutputKey==`ApiGatewayUrl`].OutputValue' \
            --output text \
            --profile "$production_profile" 2>/dev/null || echo "")
        
        if [ -n "$production_url" ] && [ "$production_url" != "None" ]; then
            update_staging_cross_account_config "$profile" "$production_url" "$production_profile"
        else
            print_warning "⚠️  Could not retrieve production URL for cross-account configuration"
        fi
    fi
    
    # Validate configuration
    print_status "🔍 Running post-deployment validation..."
    if validate_secure_parameters "$environment" "$profile"; then
        # Check if this was a first-time deployment with placeholder values
        local has_placeholders=false
        local test_param_value
        test_param_value=$(aws ssm get-parameter --name "/vpn/slack/webhook" --profile "$profile" --query 'Parameter.Value' --output text 2>/dev/null || echo "")
        
        if [[ "$test_param_value" == PLACEHOLDER_* ]]; then
            has_placeholders=true
        fi
        
        if [ "$has_placeholders" = "true" ]; then
            echo ""
            print_warning "🔧 First-time deployment detected!"
            print_status "Infrastructure is deployed, but parameters need configuration."
            print_status "Run: scripts/setup-parameters.sh $environment --secure"
        else
            print_success "✅ System is fully configured and ready to use!"
        fi
    else
        print_error "❌ Post-deployment validation failed. Check the errors above."
    fi
}

# Function to validate secure parameters (Epic 5.1)
validate_secure_parameters() {
    local environment=$1
    local profile=$2
    
    print_status "Validating secure parameter configuration..."
    
    # Check if KMS key exists
    KMS_KEY_ALIAS="vpn-parameter-store-$environment"
    if aws kms describe-key --key-id "alias/$KMS_KEY_ALIAS" --profile "$profile" &> /dev/null; then
        print_success "✅ KMS key found: $KMS_KEY_ALIAS"
    else
        print_error "❌ KMS key not found: $KMS_KEY_ALIAS"
        return 1
    fi
    
    # Phase 1: Check parameter structure exists (corrected paths)
    local required_params=(
        "/vpn/slack/webhook"
        "/vpn/slack/signing_secret"
        "/vpn/slack/bot_token"
        "/vpn/endpoint/conf"
        "/vpn/endpoint/state"
        "/vpn/cost/optimization_config"
        "/vpn/admin/overrides"
        "/vpn/cost/metrics"
        "/vpn/logging/config"
    )
    
    # Add environment-specific parameters
    if [ "$environment" = "staging" ]; then
        required_params+=(
            "/vpn/cross_account/config"
        )
    fi
    
    local missing_params=()
    local placeholder_params=()
    
    for param in "${required_params[@]}"; do
        if ! aws ssm get-parameter --name "$param" --profile "$profile" &> /dev/null; then
            missing_params+=("$param")
        else
            # Check for placeholder values
            local param_value
            param_value=$(aws ssm get-parameter --name "$param" --profile "$profile" --query 'Parameter.Value' --output text 2>/dev/null || echo "")
            
            if [[ "$param_value" == PLACEHOLDER_* ]]; then
                placeholder_params+=("$param")
            fi
        fi
    done
    
    # Report missing parameters (structure not created)
    if [ ${#missing_params[@]} -gt 0 ]; then
        print_error "❌ Missing parameters (infrastructure issue):"
        for param in "${missing_params[@]}"; do
            echo "   - $param"
        done
        print_error "This indicates a deployment problem. Parameters should be created by CDK."
        return 1
    fi
    
    # Report placeholder values (need configuration)
    if [ ${#placeholder_params[@]} -gt 0 ]; then
        print_warning "⚠️  Parameters exist but contain placeholder values:"
        for param in "${placeholder_params[@]}"; do
            echo "   - $param"
        done
        echo ""
        print_status "📋 Next steps for first-time setup:"
        print_status "1. Configure parameters: scripts/setup-parameters.sh $environment --secure"
        print_status "2. Update Slack app configuration with API Gateway URL"
        print_status "3. Test integration: Use /vpn check $environment in Slack"
        echo ""
        print_warning "💡 System is deployed but not yet functional until parameters are configured."
        return 0  # This is expected for first-time deployment
    fi
    
    print_success "✅ All required parameters exist and are configured"
    return 0
}

# Function to show deployment status with secure parameters
show_deployment_status() {
    print_status "📊 VPN Cost Automation Deployment Status"
    echo ""
    
    local staging_profile=${STAGING_PROFILE:-$(get_env_profile "staging" 2>/dev/null || echo "staging")}
    local production_profile=${PRODUCTION_PROFILE:-$(get_env_profile "prod" 2>/dev/null || echo "prod")}
    
    # Check production environment
    print_status "Production Environment:"
    if aws cloudformation describe-stacks --stack-name VpnAutomation-production --profile "$production_profile" &> /dev/null; then
        print_success "  ✅ VPN Automation Stack: Deployed"
        
        # Check secure parameter stack
        if aws cloudformation describe-stacks --stack-name VpnSecureParameters-production --profile "$production_profile" &> /dev/null; then
            print_success "  ✅ Secure Parameter Stack: Deployed (Epic 5.1)"
        else
            print_warning "  ⚠️  Secure Parameter Stack: Not deployed (can be added with --secure-parameters)"
        fi
    else
        print_warning "  ❌ Production not deployed"
    fi
    
    echo ""
    
    # Check staging environment
    print_status "Staging Environment:"
    if aws cloudformation describe-stacks --stack-name VpnAutomation-staging --profile "$staging_profile" &> /dev/null; then
        print_success "  ✅ VPN Automation Stack: Deployed"
        
        # Check secure parameter stack
        if aws cloudformation describe-stacks --stack-name VpnSecureParameters-staging --profile "$staging_profile" &> /dev/null; then
            print_success "  ✅ Secure Parameter Stack: Deployed (Epic 5.1)"
        else
            print_warning "  ⚠️  Secure Parameter Stack: Not deployed (can be added with --secure-parameters)"
        fi
    else
        print_warning "  ❌ Staging not deployed"
    fi
}

# Parse command line arguments
parse_arguments() {
    USE_SECURE_PARAMETERS=false
    STAGING_PROFILE=""
    PRODUCTION_PROFILE=""
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            --secure-parameters)
                USE_SECURE_PARAMETERS=true
                export USE_SECURE_PARAMETERS=true
                shift
                ;;
            --staging-profile)
                STAGING_PROFILE="$2"
                shift 2
                ;;
            --production-profile)
                PRODUCTION_PROFILE="$2"
                shift 2
                ;;
            --profile)
                # Use same profile for both environments if specific env profiles not set
                if [[ -z "$STAGING_PROFILE" ]]; then
                    STAGING_PROFILE="$2"
                fi
                if [[ -z "$PRODUCTION_PROFILE" ]]; then
                    PRODUCTION_PROFILE="$2"
                fi
                shift 2
                ;;
            -h|--help)
                show_deploy_help
                exit 0
                ;;
            *)
                # Store non-option arguments
                ARGS+=("$1")
                shift
                ;;
        esac
    done
}

# Show deployment help
show_deploy_help() {
    cat << 'EOF'
VPN Cost Automation Deployment Script

用法: ./scripts/deploy.sh [OPTIONS] [COMMAND]

Commands:
  staging                   Deploy to staging environment
  production               Deploy to production environment  
  both                     Deploy to both environments

Options:
  --secure-parameters      Use secure parameter management stack
  --staging-profile PROF   AWS profile for staging environment
  --production-profile PROF AWS profile for production environment
  --profile PROF           AWS profile for both environments
  -h, --help              Show this help message

Examples:
  ./scripts/deploy.sh staging                                    # Deploy staging with auto-detected profile
  ./scripts/deploy.sh --profile prod production                  # Deploy production with specific profile
  ./scripts/deploy.sh --staging-profile default --production-profile prod both  # Deploy both with specific profiles
  ./scripts/deploy.sh both --secure-parameters                   # Deploy both with secure parameters

EOF
}

# Cleanup function
cleanup() {
    local exit_code=$?
    # Only report error if it's an actual error (not usage display)
    if [ $exit_code -ne 0 ] && [ $exit_code -ne 130 ]; then  # 130 is Ctrl+C
        print_error "Deployment failed with exit code $exit_code"
        log_operation "ERROR" "Deployment failed with exit code $exit_code"
    fi
    # Cleanup temporary files if any
    if [[ -f "$PROJECT_ROOT/.production-url" ]] && [[ ! -s "$PROJECT_ROOT/.production-url" ]]; then
        rm -f "$PROJECT_ROOT/.production-url"
    fi
    exit $exit_code
}

# Set up error handling
trap cleanup EXIT

# Main script logic with enhanced error handling
main() {
    # Parse all arguments first
    ARGS=()
    parse_arguments "$@"
    
    local command="${ARGS[0]:-}"
    if [[ -z "$command" ]]; then
        show_usage
        exit 0  # Show usage is not an error condition
    fi
    
    log_operation "INFO" "Starting deployment command: $command"
    
    # Use the parsed command
    case "$command" in
        "production")
            if ! check_prerequisites; then
                print_error "Prerequisites check failed"
                exit 1
            fi
            setup_lambda_dependencies || exit 1
            setup_cdk_dependencies || exit 1
            deploy_production || exit 1
            ;;
        "staging")
            if ! check_prerequisites; then
                print_error "Prerequisites check failed"
                exit 1
            fi
            setup_lambda_dependencies || exit 1
            setup_cdk_dependencies || exit 1
            deploy_staging || exit 1
            ;;
        "both")
            if ! check_prerequisites; then
                print_error "Prerequisites check failed"
                exit 1
            fi
            setup_lambda_dependencies || exit 1
            setup_cdk_dependencies || exit 1
            deploy_both || exit 1
            ;;
        "destroy-staging")
            destroy_environment "staging" || exit 1
            ;;
        "destroy-production")
            destroy_environment "production" || exit 1
            ;;
        "diff-staging")
            if ! check_prerequisites; then
                print_error "Prerequisites check failed"
                exit 1
            fi
            setup_lambda_dependencies || exit 1
            setup_cdk_dependencies || exit 1
            show_diff "staging" || exit 1
            ;;
        "diff-production")
            if ! check_prerequisites; then
                print_error "Prerequisites check failed"
                exit 1
            fi
            setup_lambda_dependencies || exit 1
            setup_cdk_dependencies || exit 1
            show_diff "production" || exit 1
            ;;
        "status")
            show_deployment_status || exit 1
            ;;
        "validate-routing")
            validate_cross_account_routing || exit 1
            ;;
        *)
            print_error "Unknown command: $command"
            echo ""
            show_usage
            exit 1
            ;;
    esac
    
    log_operation "INFO" "Successfully completed deployment command: $command"
}

# Enhanced usage message with standardized English
usage() {
    echo "Usage: $0 {production|staging|both} [--secure-parameters]"
    echo ""
    echo "Options:"
    echo "  production        Deploy to production environment only"
    echo "  staging           Deploy to staging environment only"
    echo "  both              Deploy to both environments"
    echo "  --secure-parameters Deploy with secure parameter stack"
    echo ""
    echo "Pre-deployment steps:"
    echo "  1. Install dependencies: npm install"
    echo "  2. Configure AWS profiles: 'production' and 'staging'"
    echo "  3. Set environment variables:"
    echo "     export CDK_DEFAULT_ACCOUNT=your-account-id"
    echo "     export CDK_DEFAULT_REGION=your-region"
    echo "  4. Configure parameters (after deployment): scripts/setup-parameters.sh --all --auto-read --secure \\"
    echo "       --slack-webhook 'https://hooks.slack.com/services/...' \\"
    echo "       --slack-secret 'your-signing-secret' \\"
    echo "       --slack-bot-token 'xoxb-your-bot-token'"
    echo ""
    echo "Examples:"
    echo "  $0 both --secure-parameters"
    echo "  $0 production --production-profile prod"
    echo "  $0 staging --staging-profile dev"
}

# Run main function with all arguments
main "$@"