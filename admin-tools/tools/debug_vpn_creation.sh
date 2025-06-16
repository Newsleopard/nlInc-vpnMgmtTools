#!/bin/bash

# VPN Creation Debug Script
# This script helps diagnose VPN endpoint creation issues

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
CONFIG_DIR="configs/staging"
CONFIG_FILE="$CONFIG_DIR/vpn_endpoint.conf"
LOG_FILE="vpn_admin.log"

echo -e "${GREEN}🔍 VPN Endpoint Creation Diagnostic Tool${NC}"
echo "=================================================="

# Check if config file exists
if [ ! -f "$CONFIG_FILE" ]; then
    echo -e "${RED}❌ Configuration file not found: $CONFIG_FILE${NC}"
    exit 1
fi

# Source the configuration
source "$CONFIG_FILE"
echo -e "${GREEN}✅ Configuration loaded from $CONFIG_FILE${NC}"

# 1. Check AWS CLI configuration
echo -e "\n${YELLOW}1. Checking AWS CLI Configuration...${NC}"
if ! aws sts get-caller-identity > /dev/null 2>&1; then
    echo -e "${RED}❌ AWS CLI not configured properly${NC}"
    exit 1
fi

aws_identity=$(aws sts get-caller-identity --output text)
echo -e "${GREEN}✅ AWS CLI configured: $aws_identity${NC}"

# 2. Check VPC and Subnet availability
echo -e "\n${YELLOW}2. Checking VPC and Subnet...${NC}"
if ! aws ec2 describe-vpcs --vpc-ids "$PRIMARY_VPC_ID" > /dev/null 2>&1; then
    echo -e "${RED}❌ VPC $PRIMARY_VPC_ID not found or accessible${NC}"
    exit 1
fi
echo -e "${GREEN}✅ VPC $PRIMARY_VPC_ID is accessible${NC}"

# Check subnet
if ! aws ec2 describe-subnets --subnet-ids "$PRIMARY_SUBNET_ID" > /dev/null 2>&1; then
    echo -e "${RED}❌ Subnet $PRIMARY_SUBNET_ID not found or accessible${NC}"
    
    # List available subnets in the VPC
    echo -e "${YELLOW}Available subnets in VPC $PRIMARY_VPC_ID:${NC}"
    aws ec2 describe-subnets --filters "Name=vpc-id,Values=$PRIMARY_VPC_ID" --query 'Subnets[*].[SubnetId,AvailabilityZone,CidrBlock,State]' --output table
    exit 1
fi
echo -e "${GREEN}✅ Subnet $PRIMARY_SUBNET_ID is accessible${NC}"

# 3. Check Certificate in ACM
echo -e "\n${YELLOW}3. Checking Server Certificate...${NC}"
if ! aws acm describe-certificate --certificate-arn "$SERVER_CERT_ARN" > /dev/null 2>&1; then
    echo -e "${RED}❌ Server certificate $SERVER_CERT_ARN not found${NC}"
    
    # List available certificates
    echo -e "${YELLOW}Available certificates in ACM:${NC}"
    aws acm list-certificates --query 'CertificateSummaryList[*].[CertificateArn,DomainName]' --output table
    exit 1
fi
echo -e "${GREEN}✅ Server certificate is accessible${NC}"

# Check certificate status
cert_status=$(aws acm describe-certificate --certificate-arn "$SERVER_CERT_ARN" --query 'Certificate.Status' --output text)
if [ "$cert_status" != "ISSUED" ]; then
    echo -e "${RED}❌ Certificate status: $cert_status (should be ISSUED)${NC}"
    exit 1
fi
echo -e "${GREEN}✅ Certificate status: $cert_status${NC}"

# 4. Check for existing VPN endpoints
echo -e "\n${YELLOW}4. Checking for existing VPN endpoints...${NC}"
existing_endpoints=$(aws ec2 describe-client-vpn-endpoints --query 'ClientVpnEndpoints[?Tags[?Key==`Name` && Value==`'"$VPN_NAME"'`]].[ClientVpnEndpointId,State.Code]' --output text)

if [ -n "$existing_endpoints" ]; then
    echo -e "${YELLOW}⚠️ Found existing endpoints with name '$VPN_NAME':${NC}"
    echo "$existing_endpoints"
    echo -e "${YELLOW}You may need to delete these before creating a new one.${NC}"
else
    echo -e "${GREEN}✅ No conflicting endpoints found${NC}"
fi

# 5. Check CloudWatch log group
echo -e "\n${YELLOW}5. Checking CloudWatch log group...${NC}"
log_group_name="/aws/clientvpn/$VPN_NAME"
clean_log_name=$(echo "$log_group_name" | sed 's/[^a-zA-Z0-9/_-]/-/g')

if aws logs describe-log-groups --log-group-name-prefix "$log_group_name" --query 'logGroups[0].logGroupName' --output text 2>/dev/null | grep -q "$log_group_name"; then
    echo -e "${YELLOW}⚠️ Log group '$log_group_name' already exists${NC}"
else
    echo -e "${GREEN}✅ Log group '$log_group_name' does not exist (good for new creation)${NC}"
fi

# 6. Test parameter formatting
echo -e "\n${YELLOW}6. Testing parameter formatting...${NC}"

# Test authentication options JSON
auth_options='[{
    "Type": "certificate-authentication",
    "MutualAuthentication": {
        "ClientRootCertificateChainArn": "'"$CLIENT_CERT_ARN"'"
    }
}]'

if echo "$auth_options" | jq . > /dev/null 2>&1; then
    echo -e "${GREEN}✅ Authentication options JSON is valid${NC}"
else
    echo -e "${RED}❌ Authentication options JSON is invalid${NC}"
    echo "$auth_options"
    exit 1
fi

# Test connection log options JSON
log_options='{
    "Enabled": true,
    "CloudwatchLogGroup": "'"$clean_log_name"'"
}'

if echo "$log_options" | jq . > /dev/null 2>&1; then
    echo -e "${GREEN}✅ Connection log options JSON is valid${NC}"
else
    echo -e "${RED}❌ Connection log options JSON is invalid${NC}"
    echo "$log_options"
    exit 1
fi

# Test tag specifications JSON
tag_specs='[{
    "ResourceType": "client-vpn-endpoint",
    "Tags": [
        {
            "Key": "Name",
            "Value": "'"$VPN_NAME"'"
        },
        {
            "Key": "Environment", 
            "Value": "staging"
        }
    ]
}]'

if echo "$tag_specs" | jq . > /dev/null 2>&1; then
    echo -e "${GREEN}✅ Tag specifications JSON is valid${NC}"
else
    echo -e "${RED}❌ Tag specifications JSON is invalid${NC}"
    echo "$tag_specs"
    exit 1
fi

echo -e "\n${GREEN}🎉 All diagnostic checks passed!${NC}"
echo -e "${YELLOW}You can now proceed with VPN endpoint creation.${NC}"

# 7. Preview the AWS CLI command that will be executed
echo -e "\n${YELLOW}7. AWS CLI Command Preview:${NC}"
echo "aws ec2 create-client-vpn-endpoint \\"
echo "    --client-cidr-block '$VPN_CIDR' \\"
echo "    --server-certificate-arn '$SERVER_CERT_ARN' \\"
echo "    --authentication-options '$auth_options' \\"
echo "    --connection-log-options '$log_options' \\"
echo "    --tag-specifications '$tag_specs' \\"
echo "    --description 'VPN endpoint for $VPN_NAME'"

echo -e "\n${GREEN}Diagnostic complete!${NC}"
