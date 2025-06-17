#!/bin/bash

# VPN Cost Automation Parameter Setup Script
# Sets up required Parameter Store values for the automation

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

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
    echo "VPN Cost Automation Parameter Setup Script"
    echo ""
    echo "Usage: $0 <environment> [options]"
    echo ""
    echo "Environment:"
    echo "  staging      Set up parameters for staging environment"
    echo "  production   Set up parameters for production environment"
    echo ""
    echo "Options:"
    echo "  --profile PROFILE    AWS profile to use (default: environment name)"
    echo "  --region REGION      AWS region (default: from profile config)"
    echo "  --endpoint-id ID     VPN endpoint ID (required)"
    echo "  --subnet-id ID       Subnet ID (required)"
    echo "  --slack-webhook URL  Slack webhook URL (required)" 
    echo "  --slack-secret SEC   Slack signing secret (required)"
    echo ""
    echo "Example:"
    echo "  $0 staging \\"
    echo "    --endpoint-id cvpn-endpoint-0123456789abcdef \\"
    echo "    --subnet-id subnet-0123456789abcdef \\"
    echo "    --slack-webhook https://hooks.slack.com/services/... \\"
    echo "    --slack-secret your-slack-signing-secret"
}

# Parse command line arguments
ENVIRONMENT=""
AWS_PROFILE=""
AWS_REGION=""
ENDPOINT_ID=""
SUBNET_ID=""
SLACK_WEBHOOK=""
SLACK_SECRET=""

while [[ $# -gt 0 ]]; do
    case $1 in
        staging|production)
            ENVIRONMENT="$1"
            shift
            ;;
        --profile)
            AWS_PROFILE="$2"
            shift 2
            ;;
        --region)
            AWS_REGION="$2"
            shift 2
            ;;
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

# Validate required arguments
if [ -z "$ENVIRONMENT" ]; then
    print_error "Environment is required"
    show_usage
    exit 1
fi

if [ -z "$ENDPOINT_ID" ] || [ -z "$SUBNET_ID" ] || [ -z "$SLACK_WEBHOOK" ] || [ -z "$SLACK_SECRET" ]; then
    print_error "All parameters are required: --endpoint-id, --subnet-id, --slack-webhook, --slack-secret"
    show_usage
    exit 1
fi

# Set default profile if not specified
if [ -z "$AWS_PROFILE" ]; then
    AWS_PROFILE="$ENVIRONMENT"
fi

# Validate AWS profile
print_status "Validating AWS profile: $AWS_PROFILE"
if ! aws sts get-caller-identity --profile "$AWS_PROFILE" &> /dev/null; then
    print_error "AWS profile '$AWS_PROFILE' is not configured or credentials are invalid"
    exit 1
fi

# Get region if not specified
if [ -z "$AWS_REGION" ]; then
    AWS_REGION=$(aws configure get region --profile "$AWS_PROFILE" || echo "us-east-1")
fi

print_status "Using region: $AWS_REGION"

# Function to create or update parameter
create_parameter() {
    local param_name="$1"
    local param_value="$2"
    local param_type="$3"
    local description="$4"
    
    print_status "Setting parameter: $param_name"
    
    aws ssm put-parameter \
        --name "$param_name" \
        --value "$param_value" \
        --type "$param_type" \
        --description "$description" \
        --overwrite \
        --profile "$AWS_PROFILE" \
        --region "$AWS_REGION" > /dev/null
    
    if [ $? -eq 0 ]; then
        print_success "✅ Parameter $param_name set successfully"
    else
        print_error "❌ Failed to set parameter $param_name"
        exit 1
    fi
}

# Validate VPN endpoint exists
print_status "Validating VPN endpoint: $ENDPOINT_ID"
if ! aws ec2 describe-client-vpn-endpoints \
    --client-vpn-endpoint-ids "$ENDPOINT_ID" \
    --profile "$AWS_PROFILE" \
    --region "$AWS_REGION" \
    --query 'ClientVpnEndpoints[0].State' \
    --output text &> /dev/null; then
    print_error "VPN endpoint $ENDPOINT_ID not found or not accessible"
    exit 1
fi

ENDPOINT_STATE=$(aws ec2 describe-client-vpn-endpoints \
    --client-vpn-endpoint-ids "$ENDPOINT_ID" \
    --profile "$AWS_PROFILE" \
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
print_status "Validating subnet: $SUBNET_ID"
if ! aws ec2 describe-subnets \
    --subnet-ids "$SUBNET_ID" \
    --profile "$AWS_PROFILE" \
    --region "$AWS_REGION" \
    --query 'Subnets[0].SubnetId' \
    --output text &> /dev/null; then
    print_error "Subnet $SUBNET_ID not found or not accessible"
    exit 1
fi

print_success "✅ VPN endpoint and subnet validation passed"

# Create parameters
print_status "Creating Parameter Store parameters for $ENVIRONMENT environment..."

# VPN endpoint configuration
VPN_CONFIG=$(cat <<EOF
{
  "ENDPOINT_ID": "$ENDPOINT_ID",
  "SUBNET_ID": "$SUBNET_ID"
}
EOF
)

create_parameter \
    "/vpn/endpoint/conf" \
    "$VPN_CONFIG" \
    "String" \
    "VPN endpoint configuration (endpoint ID and subnet ID)"

# VPN state (initial state)
VPN_STATE=$(cat <<EOF
{
  "associated": false,
  "lastActivity": "$(date -u +"%Y-%m-%dT%H:%M:%S.000Z")"
}
EOF
)

create_parameter \
    "/vpn/endpoint/state" \
    "$VPN_STATE" \
    "String" \
    "VPN endpoint state (associated status and last activity)"

# Slack webhook (encrypted)
create_parameter \
    "/vpn/slack/webhook" \
    "$SLACK_WEBHOOK" \
    "SecureString" \
    "Slack webhook URL for VPN automation notifications"

# Slack signing secret (encrypted)
create_parameter \
    "/vpn/slack/signing_secret" \
    "$SLACK_SECRET" \
    "SecureString" \
    "Slack signing secret for request verification"

print_success "🎉 All parameters set successfully for $ENVIRONMENT environment!"

# Display summary
echo ""
print_status "📋 Parameter Summary:"
echo "   Environment: $ENVIRONMENT"
echo "   AWS Profile: $AWS_PROFILE"
echo "   AWS Region: $AWS_REGION"
echo "   VPN Endpoint: $ENDPOINT_ID"
echo "   Subnet: $SUBNET_ID"
echo "   Slack webhook: ***configured***"
echo "   Slack secret: ***configured***"
echo ""

print_status "🚀 Next steps:"
echo "   1. Deploy the CDK stack: ./scripts/deploy.sh $ENVIRONMENT"
echo "   2. Configure your Slack app to use the API Gateway endpoint"
echo "   3. Test the integration with: /vpn check $ENVIRONMENT"