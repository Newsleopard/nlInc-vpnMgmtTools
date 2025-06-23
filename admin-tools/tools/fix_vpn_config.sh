#!/bin/bash

# VPN Configuration Fix Script
# This script helps fix common VPN endpoint configuration issues

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
CONFIG_DIR="configs/staging"
CONFIG_FILE="$CONFIG_DIR/vpn_endpoint.conf"
BACKUP_FILE="${CONFIG_FILE}.backup.$(date +%Y%m%d_%H%M%S)"

echo -e "${GREEN}🔧 VPN Configuration Fix Tool${NC}"
echo "======================================"

# Check if config file exists
if [ ! -f "$CONFIG_FILE" ]; then
    echo -e "${RED}❌ Configuration file not found: $CONFIG_FILE${NC}"
    exit 1
fi

# Create backup
cp "$CONFIG_FILE" "$BACKUP_FILE"
echo -e "${GREEN}✅ Backup created: $BACKUP_FILE${NC}"

# Source the configuration
source "$CONFIG_FILE"

# Function to update config file
update_config() {
    local key="$1"
    local new_value="$2"
    local file="$3"
    
    if grep -q "^$key=" "$file"; then
        sed -i.tmp "s|^$key=.*|$key=\"$new_value\"|" "$file" && rm "${file}.tmp"
        echo -e "${GREEN}✅ Updated $key to: $new_value${NC}"
    else
        echo "$key=\"$new_value\"" >> "$file"
        echo -e "${GREEN}✅ Added $key: $new_value${NC}"
    fi
}

# 1. Fix Subnet Issues
echo -e "\n${YELLOW}1. Checking and fixing subnet configuration...${NC}"

# Check if current subnet is available
if ! aws ec2 describe-subnets --subnet-ids "$SUBNET_ID" > /dev/null 2>&1; then
    echo -e "${RED}❌ Current subnet $SUBNET_ID is not accessible${NC}"
    
    # Find available subnets in the same VPC
    available_subnets=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=$VPC_ID" "Name=state,Values=available" --query 'Subnets[*].[SubnetId,AvailabilityZone,CidrBlock]' --output text)
    
    if [ -n "$available_subnets" ]; then
        echo -e "${YELLOW}Available subnets in VPC $VPC_ID:${NC}"
        echo "$available_subnets" | nl
        
        # Use the first available subnet
        new_subnet=$(echo "$available_subnets" | head -1 | awk '{print $1}')
        echo -e "${BLUE}Selecting subnet: $new_subnet${NC}"
        
        update_config "SUBNET_ID" "$new_subnet" "$CONFIG_FILE"
        SUBNET_ID="$new_subnet"
    else
        echo -e "${RED}❌ No available subnets found in VPC $VPC_ID${NC}"
        exit 1
    fi
else
    echo -e "${GREEN}✅ Current subnet $SUBNET_ID is accessible${NC}"
fi

# 2. Fix Certificate Issues
echo -e "\n${YELLOW}2. Checking and fixing certificate configuration...${NC}"

# Check if current certificate is valid
if ! aws acm describe-certificate --certificate-arn "$SERVER_CERT_ARN" > /dev/null 2>&1; then
    echo -e "${RED}❌ Current certificate $SERVER_CERT_ARN is not accessible${NC}"
    
    # List available certificates
    available_certs=$(aws acm list-certificates --query 'CertificateSummaryList[?Status==`ISSUED`].[CertificateArn,DomainName]' --output text)
    
    if [ -n "$available_certs" ]; then
        echo -e "${YELLOW}Available certificates:${NC}"
        echo "$available_certs" | nl
        
        # Use the first available certificate
        new_cert=$(echo "$available_certs" | head -1 | awk '{print $1}')
        echo -e "${BLUE}Selecting certificate: $new_cert${NC}"
        
        update_config "SERVER_CERT_ARN" "$new_cert" "$CONFIG_FILE"
        SERVER_CERT_ARN="$new_cert"
    else
        echo -e "${RED}❌ No valid certificates found${NC}"
        echo -e "${YELLOW}You may need to import or create a new certificate${NC}"
        exit 1
    fi
else
    # Check certificate status
    cert_status=$(aws acm describe-certificate --certificate-arn "$SERVER_CERT_ARN" --query 'Certificate.Status' --output text)
    if [ "$cert_status" != "ISSUED" ]; then
        echo -e "${RED}❌ Certificate status: $cert_status (should be ISSUED)${NC}"
        exit 1
    fi
    echo -e "${GREEN}✅ Current certificate $SERVER_CERT_ARN is valid${NC}"
fi

# 3. Clean up conflicting resources
echo -e "\n${YELLOW}3. Cleaning up conflicting resources...${NC}"

# Check for existing endpoints with the same name
existing_endpoints=$(aws ec2 describe-client-vpn-endpoints --query 'ClientVpnEndpoints[?Tags[?Key==`Name` && Value==`'"$VPN_NAME"'`]].[ClientVpnEndpointId,State.Code]' --output text)

if [ -n "$existing_endpoints" ]; then
    echo -e "${YELLOW}⚠️ Found existing endpoints with name '$VPN_NAME':${NC}"
    echo "$existing_endpoints"
    
    echo -e "${BLUE}Do you want to delete these endpoints? (y/N)${NC}"
    read -r response
    if [[ "$response" =~ ^[Yy]$ ]]; then
        while IFS=$'\t' read -r endpoint_id state; do
            if [ -n "$endpoint_id" ]; then
                echo -e "${YELLOW}Deleting endpoint: $endpoint_id${NC}"
                aws ec2 delete-client-vpn-endpoint --client-vpn-endpoint-id "$endpoint_id" || true
                echo -e "${GREEN}✅ Deleted endpoint: $endpoint_id${NC}"
            fi
        done <<< "$existing_endpoints"
    fi
else
    echo -e "${GREEN}✅ No conflicting endpoints found${NC}"
fi

# 4. Check and fix CloudWatch log group conflicts
echo -e "\n${YELLOW}4. Checking CloudWatch log group...${NC}"

log_group_name="/aws/clientvpn/$VPN_NAME"
clean_log_name=$(echo "$log_group_name" | sed 's/[^a-zA-Z0-9-]/-/g')

# Check if log group exists
if aws logs describe-log-groups --log-group-name-prefix "$log_group_name" --query 'logGroups[0].logGroupName' --output text 2>/dev/null | grep -q "$log_group_name"; then
    echo -e "${YELLOW}⚠️ Log group '$log_group_name' already exists${NC}"
    echo -e "${BLUE}Do you want to delete the existing log group? (y/N)${NC}"
    read -r response
    if [[ "$response" =~ ^[Yy]$ ]]; then
        aws logs delete-log-group --log-group-name "$log_group_name"
        echo -e "${GREEN}✅ Deleted log group: $log_group_name${NC}"
    fi
else
    echo -e "${GREEN}✅ No conflicting log group found${NC}"
fi

# 5. Validate final configuration
echo -e "\n${YELLOW}5. Validating final configuration...${NC}"

# Re-source the updated configuration
source "$CONFIG_FILE"

# Validate all parameters
errors=0

if [ -z "$VPC_ID" ]; then
    echo -e "${RED}❌ VPC_ID is not set${NC}"
    ((errors++))
fi

if [ -z "$SUBNET_ID" ]; then
    echo -e "${RED}❌ SUBNET_ID is not set${NC}"
    ((errors++))
fi

if [ -z "$VPN_CIDR" ]; then
    echo -e "${RED}❌ VPN_CIDR is not set${NC}"
    ((errors++))
fi

if [ -z "$SERVER_CERT_ARN" ]; then
    echo -e "${RED}❌ SERVER_CERT_ARN is not set${NC}"
    ((errors++))
fi

if [ -z "$VPN_NAME" ]; then
    echo -e "${RED}❌ VPN_NAME is not set${NC}"
    ((errors++))
fi

if [ $errors -eq 0 ]; then
    echo -e "\n${GREEN}🎉 Configuration fix completed successfully!${NC}"
    echo -e "${GREEN}✅ All parameters are properly configured${NC}"
    echo -e "${YELLOW}You can now run the VPN endpoint creation script${NC}"
    
    # Show updated configuration
    echo -e "\n${BLUE}Updated configuration:${NC}"
    echo "VPC_ID=$VPC_ID"
    echo "SUBNET_ID=$SUBNET_ID"
    echo "VPN_CIDR=$VPN_CIDR"
    echo "SERVER_CERT_ARN=$SERVER_CERT_ARN"
    echo "VPN_NAME=$VPN_NAME"
else
    echo -e "\n${RED}❌ Configuration fix failed. $errors error(s) found.${NC}"
    echo -e "${YELLOW}Please check the configuration file manually: $CONFIG_FILE${NC}"
    echo -e "${YELLOW}Backup is available at: $BACKUP_FILE${NC}"
    exit 1
fi
