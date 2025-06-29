#!/bin/bash
#
# Script to verify and display Slack configuration for VPN management
# This helps diagnose "dispatch_unknown_error" issues

set -euo pipefail

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}=== VPN Slack Configuration Verification ===${NC}"
echo

# Function to check environment
check_environment() {
    local env=$1
    local profile=${2:-default}
    
    echo -e "${YELLOW}Checking $env environment...${NC}"
    
    # Get stack outputs
    local stack_name="VpnAutomation-$env"
    local slack_endpoint=""
    local api_url=""
    
    if aws cloudformation describe-stacks --stack-name "$stack_name" --profile "$profile" &>/dev/null; then
        slack_endpoint=$(aws cloudformation describe-stacks \
            --stack-name "$stack_name" \
            --query 'Stacks[0].Outputs[?OutputKey==`SlackEndpoint`].OutputValue' \
            --output text \
            --profile "$profile" 2>/dev/null || echo "Not found")
        
        api_url=$(aws cloudformation describe-stacks \
            --stack-name "$stack_name" \
            --query 'Stacks[0].Outputs[?OutputKey==`ApiGatewayUrl`].OutputValue' \
            --output text \
            --profile "$profile" 2>/dev/null || echo "Not found")
        
        echo -e "${GREEN}✓ Stack deployed${NC}"
        echo -e "  Slack Endpoint: ${BLUE}$slack_endpoint${NC}"
        echo -e "  API Gateway URL: ${BLUE}$api_url${NC}"
        
        # Check if Lambda was recently invoked
        local lambda_name=$(aws cloudformation describe-stack-resources \
            --stack-name "$stack_name" \
            --query 'StackResources[?LogicalResourceId==`SlackHandler`].PhysicalResourceId' \
            --output text \
            --profile "$profile" 2>/dev/null || echo "")
        
        if [ -n "$lambda_name" ]; then
            echo -e "  Lambda Function: ${BLUE}$lambda_name${NC}"
            
            # Check for recent invocations
            local invocation_count=$(aws cloudwatch get-metric-statistics \
                --namespace "AWS/Lambda" \
                --metric-name "Invocations" \
                --dimensions Name=FunctionName,Value="$lambda_name" \
                --start-time "$(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S)" \
                --end-time "$(date -u +%Y-%m-%dT%H:%M:%S)" \
                --period 3600 \
                --statistics Sum \
                --query 'Datapoints[0].Sum' \
                --output text \
                --profile "$profile" 2>/dev/null || echo "0")
            
            if [ "$invocation_count" != "null" ] && [ "$invocation_count" != "0" ]; then
                echo -e "  Recent invocations (last hour): ${GREEN}$invocation_count${NC}"
            else
                echo -e "  Recent invocations (last hour): ${RED}0${NC}"
            fi
        fi
        
        # Test endpoint connectivity
        echo -e "\n  Testing endpoint connectivity..."
        local http_code=$(curl -s -o /dev/null -w "%{http_code}" -X POST "$slack_endpoint" 2>/dev/null || echo "000")
        
        if [ "$http_code" = "200" ] || [ "$http_code" = "405" ] || [ "$http_code" = "400" ]; then
            echo -e "  ${GREEN}✓ Endpoint is reachable (HTTP $http_code)${NC}"
        else
            echo -e "  ${RED}✗ Endpoint unreachable (HTTP $http_code)${NC}"
        fi
        
    else
        echo -e "${RED}✗ Stack not deployed${NC}"
    fi
    
    echo
}

# Check both environments
check_environment "staging" "default"
check_environment "production" "prod"

# Display Slack app configuration instructions
echo -e "${YELLOW}=== Slack App Configuration Instructions ===${NC}"
echo
echo "To fix 'dispatch_unknown_error', update your Slack app configuration:"
echo
echo "1. Go to https://api.slack.com/apps/[YOUR_APP_ID]/slash-commands"
echo "2. Find the /vpn command"
echo "3. Update the Request URL to one of these endpoints:"
echo
echo -e "   ${BLUE}Staging:${NC}  https://ouyi2hof24.execute-api.us-east-1.amazonaws.com/prod/slack"
echo -e "   ${BLUE}Production:${NC} https://fuycmaqdc1.execute-api.us-east-1.amazonaws.com/prod/slack"
echo
echo "4. Save changes and wait 1-2 minutes"
echo "5. Test with: /vpn check stage"
echo
echo -e "${YELLOW}Common Issues:${NC}"
echo "- Wrong URL in Slack app (missing /prod/slack path)"
echo "- Using HTTP instead of HTTPS"
echo "- Incorrect API Gateway stage (should be 'prod')"
echo "- Old webhook URL from previous deployment"
echo

# Check if we can read Slack parameters
echo -e "${YELLOW}=== Checking Slack Parameters ===${NC}"
for env in staging production; do
    echo -e "\n${BLUE}$env environment:${NC}"
    
    profile="default"
    [ "$env" = "production" ] && profile="prod"
    
    # Check signing secret
    if aws ssm get-parameter --name "/vpn/$env/slack/signing_secret" --profile "$profile" &>/dev/null; then
        echo -e "  ${GREEN}✓ Signing secret configured${NC}"
    else
        echo -e "  ${RED}✗ Signing secret missing${NC}"
    fi
    
    # Check webhook
    if aws ssm get-parameter --name "/vpn/$env/slack/webhook" --profile "$profile" &>/dev/null; then
        echo -e "  ${GREEN}✓ Webhook URL configured${NC}"
    else
        echo -e "  ${RED}✗ Webhook URL missing${NC}"
    fi
    
    # Check bot token
    if aws ssm get-parameter --name "/vpn/$env/slack/bot_token" --profile "$profile" &>/dev/null; then
        echo -e "  ${GREEN}✓ Bot token configured${NC}"
    else
        echo -e "  ${RED}✗ Bot token missing${NC}"
    fi
done

echo
echo -e "${GREEN}=== Verification Complete ===${NC}"