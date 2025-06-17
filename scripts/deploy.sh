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
    
    print_success "Prerequisites check passed"
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

# Function to deploy production environment
deploy_production() {
    print_status "🚀 Deploying production environment..."
    
    local profile=${PRODUCTION_PROFILE:-"production"}
    validate_aws_profile "$profile" "production"
    
    cd "$CDK_DIR"
    
    print_status "Deploying production stack..."
    ENVIRONMENT=production AWS_PROFILE="$profile" cdk deploy --require-approval never
    
    print_success "✅ Production deployment completed!"
    
    # Get production API Gateway URL
    PRODUCTION_URL=$(aws cloudformation describe-stacks \
        --stack-name VpnAutomationStack-production \
        --query 'Stacks[0].Outputs[?OutputKey==`ApiGatewayUrl`].OutputValue' \
        --output text \
        --profile "$profile" 2>/dev/null || echo "")
    
    if [ -n "$PRODUCTION_URL" ]; then
        echo "export PRODUCTION_API_ENDPOINT=\"${PRODUCTION_URL}vpn\"" > "$PROJECT_ROOT/.production-url"
        print_success "Production API URL saved: $PRODUCTION_URL"
    fi
    
    print_warning "💡 To deploy staging, run: $0 staging"
}

# Function to deploy staging environment
deploy_staging() {
    print_status "🚀 Deploying staging environment..."
    
    local profile=${STAGING_PROFILE:-"staging"}
    validate_aws_profile "$profile" "staging"
    
    print_status "📡 Getting production API Gateway URL..."
    
    # Try to get production URL from CloudFormation
    local production_profile=${PRODUCTION_PROFILE:-"production"}
    PRODUCTION_URL=$(aws cloudformation describe-stacks \
        --stack-name VpnAutomationStack-production \
        --query 'Stacks[0].Outputs[?OutputKey==`ApiGatewayUrl`].OutputValue' \
        --output text \
        --profile "$production_profile" 2>/dev/null || echo "")
    
    # Try to load from saved file if CloudFormation query failed
    if [ -z "$PRODUCTION_URL" ] && [ -f "$PROJECT_ROOT/.production-url" ]; then
        source "$PROJECT_ROOT/.production-url"
        PRODUCTION_URL=$(echo "$PRODUCTION_API_ENDPOINT" | sed 's/vpn$//')
    fi
    
    if [ -z "$PRODUCTION_URL" ] || [ "$PRODUCTION_URL" = "None" ]; then
        print_error "❌ Cannot get production API Gateway URL."
        print_error "Please ensure production is deployed first: $0 production"
        exit 1
    fi
    
    print_success "✅ Found production URL: $PRODUCTION_URL"
    
    cd "$CDK_DIR"
    
    print_status "🚀 Deploying staging environment..."
    
    PRODUCTION_API_ENDPOINT="${PRODUCTION_URL}vpn" \
    ENVIRONMENT=staging \
    AWS_PROFILE="$profile" \
    cdk deploy --require-approval never
    
    print_success "✅ Staging deployment completed!"
    print_success "🔗 Staging will route production commands to: $PRODUCTION_URL"
}

# Function to deploy both environments
deploy_both() {
    print_status "🚀 Deploying both environments..."
    deploy_production
    echo ""
    deploy_staging
    print_success "🎉 Both environments deployed successfully!"
}

# Function to destroy environment
destroy_environment() {
    local environment=$1
    local profile
    
    if [ "$environment" = "production" ]; then
        profile=${PRODUCTION_PROFILE:-"production"}
    else
        profile=${STAGING_PROFILE:-"staging"}
    fi
    
    print_warning "⚠️  Destroying $environment environment..."
    print_warning "This will delete all resources in the VpnAutomationStack-$environment stack"
    
    read -p "Are you sure you want to continue? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_status "Destruction cancelled"
        exit 0
    fi
    
    validate_aws_profile "$profile" "$environment"
    
    cd "$CDK_DIR"
    
    print_status "Destroying $environment stack..."
    ENVIRONMENT="$environment" AWS_PROFILE="$profile" cdk destroy --force
    
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
    echo ""
    echo "Environment Variables:"
    echo "  STAGING_PROFILE      AWS profile for staging (default: staging)"
    echo "  PRODUCTION_PROFILE   AWS profile for production (default: production)"
    echo ""
    echo "Examples:"
    echo "  $0 production                    # Deploy production environment"
    echo "  $0 staging                       # Deploy staging environment"
    echo "  $0 both                          # Deploy both environments"
    echo "  STAGING_PROFILE=dev $0 staging   # Use custom profile"
    echo ""
    echo "First-time setup:"
    echo "  1. Configure AWS profiles: aws configure --profile production"
    echo "  2. Deploy production: $0 production"
    echo "  3. Deploy staging: $0 staging"
}

# Function to show diff
show_diff() {
    local environment=$1
    local profile
    
    if [ "$environment" = "production" ]; then
        profile=${PRODUCTION_PROFILE:-"production"}
    else
        profile=${STAGING_PROFILE:-"staging"}
    fi
    
    validate_aws_profile "$profile" "$environment"
    
    cd "$CDK_DIR"
    
    print_status "Showing differences for $environment environment..."
    
    if [ "$environment" = "staging" ]; then
        # For staging, we need production URL
        local production_profile=${PRODUCTION_PROFILE:-"production"}
        PRODUCTION_URL=$(aws cloudformation describe-stacks \
            --stack-name VpnAutomationStack-production \
            --query 'Stacks[0].Outputs[?OutputKey==`ApiGatewayUrl`].OutputValue' \
            --output text \
            --profile "$production_profile" 2>/dev/null || echo "")
        
        if [ -n "$PRODUCTION_URL" ]; then
            PRODUCTION_API_ENDPOINT="${PRODUCTION_URL}vpn" \
            ENVIRONMENT="$environment" \
            AWS_PROFILE="$profile" \
            cdk diff
        else
            print_warning "Production environment not found, showing diff without production URL"
            ENVIRONMENT="$environment" AWS_PROFILE="$profile" cdk diff
        fi
    else
        ENVIRONMENT="$environment" AWS_PROFILE="$profile" cdk diff
    fi
}

# Function to show deployment status
show_status() {
    print_status "Checking deployment status..."
    
    local staging_profile=${STAGING_PROFILE:-"staging"}
    local production_profile=${PRODUCTION_PROFILE:-"production"}
    
    # Check production
    if aws cloudformation describe-stacks --stack-name VpnAutomationStack-production --profile "$production_profile" &> /dev/null; then
        print_success "✅ Production environment is deployed"
        PRODUCTION_URL=$(aws cloudformation describe-stacks \
            --stack-name VpnAutomationStack-production \
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
    if aws cloudformation describe-stacks --stack-name VpnAutomationStack-staging --profile "$staging_profile" &> /dev/null; then
        print_success "✅ Staging environment is deployed"
        STAGING_URL=$(aws cloudformation describe-stacks \
            --stack-name VpnAutomationStack-staging \
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

# Main script logic
main() {
    case "${1:-}" in
        "production")
            check_prerequisites
            setup_cdk_dependencies
            deploy_production
            ;;
        "staging")
            check_prerequisites
            setup_cdk_dependencies
            deploy_staging
            ;;
        "both")
            check_prerequisites
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
            setup_cdk_dependencies
            show_diff "staging"
            ;;
        "diff-production")
            check_prerequisites
            setup_cdk_dependencies
            show_diff "production"
            ;;
        "status")
            show_status
            ;;
        *)
            show_usage
            exit 1
            ;;
    esac
}

main "$@"