#!/bin/bash

# Test Cross-Account Routing Functionality
# This script validates the Epic 2.2 Multi-Environment Command Routing implementation

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

print_test_header() {
    echo ""
    echo "=================================================="
    echo -e "${BLUE}$1${NC}"
    echo "=================================================="
}

# Function to test API Gateway endpoint
test_api_endpoint() {
    local endpoint="$1"
    local api_key="$2"
    local test_payload="$3"
    local description="$4"
    
    print_status "Testing: $description"
    print_status "Endpoint: $endpoint"
    
    if [ -z "$api_key" ]; then
        print_warning "No API key provided - testing without authentication"
        HTTP_CODE=$(curl -s -o /tmp/api_response.json -w "%{http_code}" \
            -X POST \
            -H "Content-Type: application/json" \
            -d "$test_payload" \
            "$endpoint" 2>/dev/null || echo "000")
    else
        HTTP_CODE=$(curl -s -o /tmp/api_response.json -w "%{http_code}" \
            -X POST \
            -H "Content-Type: application/json" \
            -H "X-API-Key: $api_key" \
            -d "$test_payload" \
            "$endpoint" 2>/dev/null || echo "000")
    fi
    
    case "$HTTP_CODE" in
        "200")
            print_success "✅ API endpoint responded successfully (HTTP 200)"
            if [ -f /tmp/api_response.json ]; then
                RESPONSE_SUCCESS=$(cat /tmp/api_response.json | jq -r '.success // false' 2>/dev/null || echo "false")
                if [ "$RESPONSE_SUCCESS" = "true" ]; then
                    print_success "✅ VPN operation completed successfully"
                else
                    ERROR_MSG=$(cat /tmp/api_response.json | jq -r '.error // "Unknown error"' 2>/dev/null || echo "Unknown error")
                    print_warning "⚠️ VPN operation failed: $ERROR_MSG"
                fi
            fi
            ;;
        "400")
            print_warning "⚠️ Bad request (HTTP 400) - check payload format"
            if [ -f /tmp/api_response.json ]; then
                ERROR_MSG=$(cat /tmp/api_response.json | jq -r '.error // "Bad request"' 2>/dev/null || echo "Bad request")
                print_warning "Error details: $ERROR_MSG"
            fi
            ;;
        "401")
            print_error "❌ Unauthorized (HTTP 401) - API key authentication failed"
            ;;
        "403")
            print_error "❌ Forbidden (HTTP 403) - insufficient permissions"
            ;;
        "500")
            print_error "❌ Internal server error (HTTP 500)"
            if [ -f /tmp/api_response.json ]; then
                ERROR_MSG=$(cat /tmp/api_response.json | jq -r '.error // "Internal error"' 2>/dev/null || echo "Internal error")
                print_error "Error details: $ERROR_MSG"
            fi
            ;;
        "000")
            print_error "❌ Network error - could not connect to endpoint"
            ;;
        *)
            print_warning "⚠️ Unexpected HTTP status: $HTTP_CODE"
            ;;
    esac
    
    # Clean up
    rm -f /tmp/api_response.json
    
    return $([ "$HTTP_CODE" = "200" ] && echo 0 || echo 1)
}

# Function to get deployment information
get_deployment_info() {
    local environment="$1"
    local profile="$2"
    
    print_status "Getting deployment information for $environment..."
    
    # Check if stack exists
    if ! aws cloudformation describe-stacks --stack-name "VpnAutomationStack-$environment" --profile "$profile" &> /dev/null; then
        print_error "$environment environment is not deployed"
        return 1
    fi
    
    # Get API Gateway URL
    API_URL=$(aws cloudformation describe-stacks \
        --stack-name "VpnAutomationStack-$environment" \
        --query 'Stacks[0].Outputs[?OutputKey==`ApiGatewayUrl`].OutputValue' \
        --output text \
        --profile "$profile" 2>/dev/null || echo "")
    
    if [ -z "$API_URL" ] || [ "$API_URL" = "None" ]; then
        print_error "Could not retrieve API Gateway URL for $environment"
        return 1
    fi
    
    print_success "API Gateway URL: $API_URL"
    
    # Get API key if it exists (for production)
    API_KEY_ID=$(aws cloudformation describe-stacks \
        --stack-name "VpnAutomationStack-$environment" \
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
            print_success "API Key retrieved successfully"
        else
            print_warning "Could not retrieve API key value"
        fi
    else
        print_status "No API key configured for $environment"
    fi
    
    return 0
}

# Function to test local Lambda invocation
test_local_lambda() {
    local environment="$1"
    local profile="$2"
    
    print_status "Testing local Lambda function for $environment..."
    
    local test_payload='{
        "httpMethod": "POST",
        "body": "{\"action\":\"check\",\"environment\":\"'$environment'\",\"user\":\"test-user\",\"requestId\":\"test-local-'$(date +%s)'\"}"
    }'
    
    LAMBDA_RESULT=$(aws lambda invoke \
        --function-name "VpnAutomationStack-$environment-VpnControl" \
        --payload "$test_payload" \
        --cli-binary-format raw-in-base64-out \
        --profile "$profile" \
        /tmp/lambda_response.json 2>/dev/null || echo "failed")
    
    if [ "$LAMBDA_RESULT" = "failed" ]; then
        print_error "❌ Failed to invoke Lambda function"
        return 1
    fi
    
    if [ -f /tmp/lambda_response.json ]; then
        STATUS_CODE=$(cat /tmp/lambda_response.json | jq -r '.statusCode // 500' 2>/dev/null || echo "500")
        
        if [ "$STATUS_CODE" = "200" ]; then
            print_success "✅ Lambda function executed successfully"
            
            BODY=$(cat /tmp/lambda_response.json | jq -r '.body' 2>/dev/null || echo "{}")
            VPN_SUCCESS=$(echo "$BODY" | jq -r '.success // false' 2>/dev/null || echo "false")
            
            if [ "$VPN_SUCCESS" = "true" ]; then
                print_success "✅ VPN operation completed successfully"
            else
                ERROR_MSG=$(echo "$BODY" | jq -r '.error // "Unknown error"' 2>/dev/null || echo "Unknown error")
                print_warning "⚠️ VPN operation failed: $ERROR_MSG"
            fi
        else
            print_error "❌ Lambda function returned status code: $STATUS_CODE"
        fi
        
        rm -f /tmp/lambda_response.json
    fi
    
    return 0
}

# Main test function
main() {
    print_test_header "Epic 2.2: Multi-Environment Command Routing Tests"
    
    # Check prerequisites
    if ! command -v curl &> /dev/null; then
        print_error "curl is required for API testing"
        exit 1
    fi
    
    if ! command -v jq &> /dev/null; then
        print_error "jq is required for JSON parsing"
        exit 1
    fi
    
    if ! command -v aws &> /dev/null; then
        print_error "AWS CLI is required"
        exit 1
    fi
    
    # Environment setup
    local staging_profile=${STAGING_PROFILE:-"staging"}
    local production_profile=${PRODUCTION_PROFILE:-"production"}
    
    print_status "Using profiles: staging=$staging_profile, production=$production_profile"
    
    # Test 1: Get deployment information
    print_test_header "Test 1: Deployment Information"
    
    print_status "Checking production environment..."
    if get_deployment_info "production" "$production_profile"; then
        PRODUCTION_API_URL="$API_URL"
        PRODUCTION_API_KEY="$API_KEY_VALUE"
        print_success "Production environment is accessible"
    else
        print_error "Production environment check failed"
        exit 1
    fi
    
    print_status "Checking staging environment..."
    if get_deployment_info "staging" "$staging_profile"; then
        STAGING_API_URL="$API_URL"
        STAGING_API_KEY="$API_KEY_VALUE"
        print_success "Staging environment is accessible"
    else
        print_error "Staging environment check failed"
        exit 1
    fi
    
    # Test 2: Local Lambda function tests
    print_test_header "Test 2: Local Lambda Function Tests"
    
    test_local_lambda "staging" "$staging_profile"
    test_local_lambda "production" "$production_profile"
    
    # Test 3: API Gateway endpoint tests
    print_test_header "Test 3: API Gateway Endpoint Tests"
    
    # Test production VPN control endpoint (direct access)
    local prod_test_payload='{
        "command": {
            "action": "check",
            "environment": "production",
            "user": "test-user",
            "requestId": "api-test-prod-'$(date +%s)'"
        },
        "sourceAccount": "test",
        "crossAccountMetadata": {
            "requestTimestamp": "'$(date -u +%Y-%m-%dT%H:%M:%SZ)'",
            "sourceEnvironment": "test",
            "routingAttempt": 1,
            "userAgent": "CrossAccountRoutingTest/1.0"
        }
    }'
    
    test_api_endpoint "${PRODUCTION_API_URL}vpn" "$PRODUCTION_API_KEY" "$prod_test_payload" "Production VPN Control (Direct)"
    
    # Test staging VPN control endpoint (local)
    local staging_test_payload='{
        "action": "check",
        "environment": "staging",
        "user": "test-user",
        "requestId": "api-test-staging-'$(date +%s)'"
    }'
    
    test_api_endpoint "${STAGING_API_URL}vpn" "$STAGING_API_KEY" "$staging_test_payload" "Staging VPN Control (Local)"
    
    # Test 4: Cross-account routing simulation
    print_test_header "Test 4: Cross-Account Routing Simulation"
    
    if [ -n "$PRODUCTION_API_KEY" ]; then
        print_status "Simulating cross-account routing from staging to production..."
        
        # This simulates what the staging slack-handler would send to production
        local cross_account_payload='{
            "command": {
                "action": "check",
                "environment": "production",
                "user": "test-user",
                "requestId": "cross-account-test-'$(date +%s)'"
            },
            "sourceAccount": "staging",
            "crossAccountMetadata": {
                "requestTimestamp": "'$(date -u +%Y-%m-%dT%H:%M:%SZ)'",
                "sourceEnvironment": "staging",
                "routingAttempt": 1,
                "userAgent": "VPN-Automation-Slack-Handler/1.0"
            }
        }'
        
        if test_api_endpoint "${PRODUCTION_API_URL}vpn" "$PRODUCTION_API_KEY" "$cross_account_payload" "Cross-Account Routing (Staging → Production)"; then
            print_success "🎉 Cross-account routing is working correctly!"
        else
            print_error "❌ Cross-account routing failed"
        fi
    else
        print_warning "⚠️ No production API key available - skipping cross-account routing test"
    fi
    
    # Test 5: Authentication and error handling
    print_test_header "Test 5: Authentication and Error Handling"
    
    # Test without API key (should fail for production)
    print_status "Testing production endpoint without API key (should fail)..."
    test_api_endpoint "${PRODUCTION_API_URL}vpn" "" "$prod_test_payload" "Production VPN Control (No Auth)"
    
    # Test with invalid API key
    print_status "Testing production endpoint with invalid API key (should fail)..."
    test_api_endpoint "${PRODUCTION_API_URL}vpn" "invalid-api-key-12345" "$prod_test_payload" "Production VPN Control (Invalid Auth)"
    
    # Test with malformed payload
    print_status "Testing with malformed payload (should fail)..."
    test_api_endpoint "${PRODUCTION_API_URL}vpn" "$PRODUCTION_API_KEY" '{"invalid": "payload"}' "Production VPN Control (Malformed Payload)"
    
    # Final summary
    print_test_header "Test Summary"
    print_success "✅ Epic 2.2 Multi-Environment Command Routing tests completed!"
    print_status "Key capabilities tested:"
    print_status "  • Local Lambda function invocation"
    print_status "  • API Gateway endpoint accessibility"
    print_status "  • Cross-account routing metadata"
    print_status "  • API key authentication"
    print_status "  • Error handling and validation"
    
    echo ""
    print_status "📋 Next steps for complete Epic 2.2 validation:"
    print_status "  1. Test via actual Slack commands: /vpn check staging"
    print_status "  2. Test via actual Slack commands: /vpn check production"
    print_status "  3. Monitor CloudWatch metrics for cross-account operations"
    print_status "  4. Verify Slack notifications and alerts"
    echo ""
}

# Run main function
main "$@"