#!/bin/bash

# VPN Cost Automation Deployment Script
# Supports production, staging, and both environment deployment modes

set -e

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

# Load environment manager for AWS profile awareness
source "$PROJECT_ROOT/lib/env_core.sh" 2>/dev/null || true

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
        print_error "Node.js is not installed. Please install Node.js 18+ first."
        exit 1
    fi
    
    # Check Node.js version
    NODE_VERSION=$(node --version | cut -d'v' -f2 | cut -d'.' -f1)
    if [ "$NODE_VERSION" -lt 18 ]; then
        print_error "Node.js version 18+ is required. Current version: $(node --version)"
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
    
    # Test AWS credentials
    if ! aws sts get-caller-identity --profile "$profile" &> /dev/null; then
        print_error "AWS profile '$profile' is not configured or credentials are invalid"
        print_error "Please configure your AWS profile with: aws configure --profile $profile"
        exit 1
    fi
    
    # Get account ID
    ACCOUNT_ID=$(aws sts get-caller-identity --profile "$profile" --query Account --output text)
    print_status "Account ID: $ACCOUNT_ID"
    
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
    
    print_status "驗證部署環境: $environment"
    
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
        print_success "AWS profile 驗證成功: $profile"
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
            
            # Apply the updated environment variables
            aws lambda update-function-configuration \
                --function-name "$slack_function_name" \
                --environment "Variables=$updated_env" \
                --profile "$staging_profile" \
                --output table \
                --query 'Environment.Variables.{ProductionEndpoint:PRODUCTION_API_ENDPOINT,ProductionKey:PRODUCTION_API_KEY}' \
                > /dev/null 2>&1
            
            if [ $? -eq 0 ]; then
                print_success "✅ Lambda environment variables updated successfully"
            else
                print_warning "⚠️  Failed to update Lambda environment variables"
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
    print_status "🚀 部署到生產環境"
    
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
        ENVIRONMENT=production AWS_PROFILE="$profile" cdk deploy --app "npx ts-node bin/vpn-automation.ts" --require-approval never --context environment="production"
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
    
    print_status "💡 To deploy staging, run: $0 staging"
}

# Function to deploy staging environment
deploy_staging() {
    print_status "🚀 部署到測試環境"
    
    # Add environment validation
    if ! validate_deployment_environment "staging" "$STAGING_PROFILE"; then
        print_error "測試環境驗證失敗"
        return 1
    fi
    
    local profile=${STAGING_PROFILE:-$(get_env_profile "staging" 2>/dev/null || echo "default")}
    local use_secure_params=${USE_SECURE_PARAMETERS:-false}
    
    validate_aws_profile "$profile" "staging"
    
    print_status "📡 Getting production API Gateway URL..."
    
    # Try to get production URL from CloudFormation
    local production_profile=${PRODUCTION_PROFILE:-$(get_env_profile "prod" 2>/dev/null || echo "prod")}
    PRODUCTION_URL=$(aws cloudformation describe-stacks \
        --stack-name VpnAutomation-production \
        --query 'Stacks[0].Outputs[?OutputKey==`ApiGatewayUrl`].OutputValue' \
        --output text \
        --profile "$production_profile" 2>/dev/null || echo "")
    
    # Try to get API key from production stack
    API_KEY_ID=""
    API_KEY_VALUE=""
    if [ -n "$PRODUCTION_URL" ] && [ "$PRODUCTION_URL" != "None" ]; then
        API_KEY_ID=$(aws cloudformation describe-stacks \
            --stack-name VpnAutomation-production \
            --query 'Stacks[0].Outputs[?OutputKey==`ApiKeyId`].OutputValue' \
            --output text \
            --profile "$production_profile" 2>/dev/null || echo "")
        
        if [ -n "$API_KEY_ID" ] && [ "$API_KEY_ID" != "None" ]; then
            API_KEY_VALUE=$(aws apigateway get-api-key \
                --api-key "$API_KEY_ID" \
                --include-value \
                --query 'value' \
                --output text \
                --profile "$production_profile" 2>/dev/null || echo "")
            
            if [ -n "$API_KEY_VALUE" ]; then
                export PRODUCTION_API_KEY="$API_KEY_VALUE"
                print_status "✅ Retrieved production API key for cross-account authentication"
            fi
        fi
    fi
    
    # Try to load from saved file if CloudFormation query failed
    if [ -z "$PRODUCTION_URL" ] && [ -f "$PROJECT_ROOT/.production-url" ]; then
        source "$PROJECT_ROOT/.production-url"
        PRODUCTION_URL=$(echo "$PRODUCTION_API_ENDPOINT" | sed 's/vpn$//')
        
        if [ -n "$PRODUCTION_API_KEY" ]; then
            print_status "✅ Found saved production API configuration with authentication"
        fi
    fi
    
    if [ -z "$PRODUCTION_URL" ] || [ "$PRODUCTION_URL" = "None" ]; then
        print_error "❌ Cannot get production API Gateway URL."
        print_error "Please ensure production is deployed first: $0 production"
        exit 1
    fi
    
    print_success "✅ Found production URL: $PRODUCTION_URL"
    
    cd "$CDK_DIR"
    
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
        if [ -n "$PRODUCTION_API_KEY" ]; then
            export PRODUCTION_API_KEY="$PRODUCTION_API_KEY"
            print_status "🔐 Deploying with production API authentication"
        else
            print_status "ℹ️  Deploying without production API key - cross-account calls will use existing configuration"
        fi
        
        cdk deploy --app "npx ts-node bin/vpn-automation.ts" --require-approval never --context environment="staging"
    fi
    
    print_success "✅ Staging deployment completed!"
    print_success "🔗 Staging will route production commands to: $PRODUCTION_URL"
    
    # Automatically update staging parameter store with production API information
    print_status "🔧 Automatically configuring cross-account routing parameters..."
    update_staging_cross_account_config "$profile" "$PRODUCTION_URL" "$production_profile"
    
    # Also update the Lambda environment variables for immediate effect
    if [ -n "$PRODUCTION_URL" ] && [ -n "$PRODUCTION_API_KEY" ]; then
        update_staging_lambda_config "$profile" "$PRODUCTION_URL" "$PRODUCTION_API_KEY"
    fi
    
    if [ -n "$PRODUCTION_API_KEY" ]; then
        print_success "🔐 Cross-account authentication configured successfully"
    else
        print_status "ℹ️  Cross-account authentication will be configured via parameter store during runtime"
    fi
}

# Function to deploy both environments
deploy_both() {
    print_status "🚀 Deploying both environments..."
    
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
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            --secure-parameters)
                USE_SECURE_PARAMETERS=true
                export USE_SECURE_PARAMETERS=true
                shift
                ;;
            *)
                # Store non-option arguments
                ARGS+=("$1")
                shift
                ;;
        esac
    done
}

# Main script logic
main() {
    # Parse all arguments first
    ARGS=()
    parse_arguments "$@"
    
    # Use the parsed command
    case "${ARGS[0]:-}" in
        "production")
            check_prerequisites
            setup_lambda_dependencies
            setup_cdk_dependencies
            deploy_production
            ;;
        "staging")
            check_prerequisites
            setup_lambda_dependencies
            setup_cdk_dependencies
            deploy_staging
            ;;
        "both")
            check_prerequisites
            setup_lambda_dependencies
            setup_cdk_dependencies
            deploy_both
            ;;
        "destroy-staging")
            destroy_environment "staging"
            ;;
        "destroy-production")
            destroy_environment "production"
            ;;
        "diff-staging")
            check_prerequisites
            setup_lambda_dependencies
            setup_cdk_dependencies
            show_diff "staging"
            ;;
        "diff-production")
            check_prerequisites
            setup_lambda_dependencies
            setup_cdk_dependencies
            show_diff "production"
            ;;
        "status")
            show_deployment_status
            ;;
        "validate-routing")
            validate_cross_account_routing
            ;;
        *)
            show_usage
            exit 1
            ;;
    esac
}

# Update usage message - around line 620
usage() {
    echo "使用方式: $0 {production|staging|both} [--secure-parameters]"
    echo ""
    echo "選項:"
    echo "  production        僅部署到生產環境"
    echo "  staging           僅部署到測試環境"
    echo "  both              部署到兩個環境"
    echo "  --secure-parameters 部署安全參數堆疊"
    echo ""
    echo "部署前準備步驟:"
    echo "  1. 安裝依賴: npm install"
    echo "  2. 設置 AWS profiles: 'production' 和 'staging'"
    echo "  3. 設置環境變數:"
    echo "     export CDK_DEFAULT_ACCOUNT=your-account-id"
    echo "     export CDK_DEFAULT_REGION=your-region"
    echo "  4. 配置參數 (部署後): scripts/setup-parameters.sh --all --auto-read --secure \\"
    echo "       --slack-webhook 'https://hooks.slack.com/services/...' \\"
    echo "       --slack-secret 'your-signing-secret' \\"
    echo "       --slack-bot-token 'xoxb-your-bot-token'"
    echo ""
    echo "範例:"
    echo "  $0 both --secure-parameters"
}

# Run main function with all arguments
main "$@"