#!/bin/bash

# VPN Setup Continuation Script
# This script continues the VPN setup from the current "pending-associate" state

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Load core functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$SCRIPT_DIR/lib/core_functions.sh" ]; then
    source "$SCRIPT_DIR/lib/core_functions.sh"
fi
if [ -f "$SCRIPT_DIR/lib/endpoint_creation.sh" ]; then
    source "$SCRIPT_DIR/lib/endpoint_creation.sh"
fi

# Configuration
CONFIG_DIR="configs/staging"
CONFIG_FILE="$CONFIG_DIR/vpn_endpoint.conf"
LOG_FILE="vpn_admin.log"

echo -e "${GREEN}🔧 VPN Setup Continuation Tool${NC}"
echo "=================================================="
echo -e "${YELLOW}此工具將完成現有 VPN 端點的設置流程${NC}"
echo ""

# Check if config file exists
if [ ! -f "$CONFIG_FILE" ]; then
    echo -e "${RED}❌ Configuration file not found: $CONFIG_FILE${NC}"
    exit 1
fi

# Source the configuration
source "$CONFIG_FILE"
echo -e "${GREEN}✅ Configuration loaded from $CONFIG_FILE${NC}"

# Verify required variables
if [ -z "$VPN_ENDPOINT_ID" ] || [ -z "$PRIMARY_VPC_ID" ] || [ -z "$PRIMARY_SUBNET_ID" ] || [ -z "$VPN_CIDR" ] || [ -z "$AWS_REGION" ]; then
    echo -e "${RED}❌ Missing required configuration variables${NC}"
    echo "Required: VPN_ENDPOINT_ID, PRIMARY_VPC_ID, PRIMARY_SUBNET_ID, VPN_CIDR, AWS_REGION"
    exit 1
fi

echo -e "${BLUE}檢查 VPN 端點狀態...${NC}"
endpoint_status=$(aws ec2 describe-client-vpn-endpoints \
    --client-vpn-endpoint-ids "$VPN_ENDPOINT_ID" \
    --region "$AWS_REGION" \
    --query 'ClientVpnEndpoints[0].Status.Code' \
    --output text 2>/dev/null || echo "not_found")

if [ "$endpoint_status" = "not_found" ]; then
    echo -e "${RED}❌ VPN 端點 $VPN_ENDPOINT_ID 不存在或無法訪問${NC}"
    exit 1
fi

echo -e "${GREEN}✅ VPN 端點狀態: $endpoint_status${NC}"

# Check current associations
echo -e "${BLUE}檢查現有子網關聯...${NC}"
associations=$(aws ec2 describe-client-vpn-target-networks \
    --client-vpn-endpoint-id "$VPN_ENDPOINT_ID" \
    --region "$AWS_REGION" \
    --query 'ClientVpnTargetNetworks[].{ID:AssociationId,Subnet:TargetNetworkId,VPC:VpcId,Status:Status.Code}' \
    --output table 2>/dev/null || echo "")

if [ -n "$associations" ]; then
    echo -e "${YELLOW}現有子網關聯:${NC}"
    echo "$associations"
    
    # Check if our target subnet is already associated
    target_associated=$(aws ec2 describe-client-vpn-target-networks \
        --client-vpn-endpoint-id "$VPN_ENDPOINT_ID" \
        --region "$AWS_REGION" \
        --query "ClientVpnTargetNetworks[?TargetNetworkId=='$PRIMARY_SUBNET_ID'].AssociationId" \
        --output text 2>/dev/null || echo "")
    
    if [ -n "$target_associated" ] && [ "$target_associated" != "None" ]; then
        echo -e "${GREEN}✅ 目標子網 $PRIMARY_SUBNET_ID 已經關聯${NC}"
        SUBNET_ALREADY_ASSOCIATED=true
    else
        echo -e "${YELLOW}⚠️ 目標子網 $PRIMARY_SUBNET_ID 尚未關聯${NC}"
        SUBNET_ALREADY_ASSOCIATED=false
    fi
else
    echo -e "${YELLOW}⚠️ 尚未關聯任何子網${NC}"
    SUBNET_ALREADY_ASSOCIATED=false
fi

# Step 1: Associate subnet if not already done
if [ "$SUBNET_ALREADY_ASSOCIATED" = "false" ]; then
    echo -e "\n${CYAN}=== 步驟 1: 關聯子網到 VPN 端點 ===${NC}"
    echo -e "${BLUE}關聯子網 $PRIMARY_SUBNET_ID 到端點 $VPN_ENDPOINT_ID...${NC}"
    
    association_result=$(aws ec2 associate-client-vpn-target-network \
        --client-vpn-endpoint-id "$VPN_ENDPOINT_ID" \
        --subnet-id "$PRIMARY_SUBNET_ID" \
        --region "$AWS_REGION" 2>&1)
    
    if [ $? -eq 0 ]; then
        association_id=$(echo "$association_result" | jq -r '.AssociationId' 2>/dev/null || echo "")
        echo -e "${GREEN}✅ 子網關聯成功${NC}"
        if [ -n "$association_id" ] && [ "$association_id" != "null" ]; then
            echo -e "${GREEN}關聯 ID: $association_id${NC}"
        fi
        
        # Wait for association to be active
        echo -e "${BLUE}等待子網關聯完成...${NC}"
        sleep 30
    else
        echo -e "${RED}❌ 子網關聯失敗:${NC}"
        echo "$association_result"
        exit 1
    fi
else
    echo -e "\n${CYAN}=== 步驟 1: 子網關聯檢查 ===${NC}"
    echo -e "${GREEN}✅ 子網已關聯，跳過此步驟${NC}"
fi

# Step 2: Add authorization rules
echo -e "\n${CYAN}=== 步驟 2: 添加授權規則 ===${NC}"

# Get VPC CIDR
vpc_cidr=$(aws ec2 describe-vpcs \
    --vpc-ids "$PRIMARY_VPC_ID" \
    --region "$AWS_REGION" \
    --query 'Vpcs[0].CidrBlock' \
    --output text 2>/dev/null)

if [ -z "$vpc_cidr" ] || [ "$vpc_cidr" = "None" ]; then
    echo -e "${RED}❌ 無法獲取 VPC CIDR${NC}"
    exit 1
fi

echo -e "${BLUE}VPC CIDR: $vpc_cidr${NC}"

# Check existing authorization rules
echo -e "${BLUE}檢查現有授權規則...${NC}"
existing_rules=$(aws ec2 describe-client-vpn-authorization-rules \
    --client-vpn-endpoint-id "$VPN_ENDPOINT_ID" \
    --region "$AWS_REGION" \
    --query "AuthorizationRules[?DestinationCidr=='$vpc_cidr'].DestinationCidr" \
    --output text 2>/dev/null || echo "")

if [ -n "$existing_rules" ] && [ "$existing_rules" != "None" ]; then
    echo -e "${GREEN}✅ 授權規則 ($vpc_cidr) 已存在${NC}"
else
    echo -e "${BLUE}添加授權規則 for $vpc_cidr...${NC}"
    auth_result=$(aws ec2 authorize-client-vpn-ingress \
        --client-vpn-endpoint-id "$VPN_ENDPOINT_ID" \
        --target-network-cidr "$vpc_cidr" \
        --authorize-all-groups \
        --region "$AWS_REGION" 2>&1)
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✅ 授權規則添加成功${NC}"
    else
        echo -e "${RED}❌ 授權規則添加失敗:${NC}"
        echo "$auth_result"
        # Continue anyway as this might be a duplicate rule error
    fi
fi

# Step 3: Create routes
echo -e "\n${CYAN}=== 步驟 3: 創建路由 ===${NC}"

# Check existing routes
echo -e "${BLUE}檢查現有路由...${NC}"
existing_routes=$(aws ec2 describe-client-vpn-routes \
    --client-vpn-endpoint-id "$VPN_ENDPOINT_ID" \
    --region "$AWS_REGION" \
    --query "Routes[?DestinationCidr=='$vpc_cidr'].DestinationCidr" \
    --output text 2>/dev/null || echo "")

if [ -n "$existing_routes" ] && [ "$existing_routes" != "None" ]; then
    echo -e "${GREEN}✅ 路由 ($vpc_cidr) 已存在${NC}"
else
    echo -e "${BLUE}創建路由 for $vpc_cidr...${NC}"
    route_result=$(aws ec2 create-client-vpn-route \
        --client-vpn-endpoint-id "$VPN_ENDPOINT_ID" \
        --destination-cidr-block "$vpc_cidr" \
        --target-vpc-subnet-id "$PRIMARY_SUBNET_ID" \
        --region "$AWS_REGION" 2>&1)
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✅ 路由創建成功${NC}"
    else
        echo -e "${RED}❌ 路由創建失敗:${NC}"
        echo "$route_result"
        # Continue anyway as this might be a duplicate route error
    fi
fi

# Step 4: Create default route for internet access (optional)
echo -e "\n${CYAN}=== 步驟 4: 創建預設路由 (可選) ===${NC}"
read -p "是否要添加預設路由 (0.0.0.0/0) 以提供完整的網際網路存取? (y/N): " add_default_route

if [[ "$add_default_route" =~ ^[Yy]$ ]]; then
    # Check existing default route
    existing_default=$(aws ec2 describe-client-vpn-routes \
        --client-vpn-endpoint-id "$VPN_ENDPOINT_ID" \
        --region "$AWS_REGION" \
        --query "Routes[?DestinationCidr=='0.0.0.0/0'].DestinationCidr" \
        --output text 2>/dev/null || echo "")
    
    if [ -n "$existing_default" ] && [ "$existing_default" != "None" ]; then
        echo -e "${GREEN}✅ 預設路由已存在${NC}"
    else
        echo -e "${BLUE}創建預設路由...${NC}"
        default_route_result=$(aws ec2 create-client-vpn-route \
            --client-vpn-endpoint-id "$VPN_ENDPOINT_ID" \
            --destination-cidr-block "0.0.0.0/0" \
            --target-vpc-subnet-id "$PRIMARY_SUBNET_ID" \
            --region "$AWS_REGION" 2>&1)
        
        if [ $? -eq 0 ]; then
            echo -e "${GREEN}✅ 預設路由創建成功${NC}"
        else
            echo -e "${RED}❌ 預設路由創建失敗:${NC}"
            echo "$default_route_result"
        fi
    fi
    
    # Add authorization rule for internet access
    echo -e "${BLUE}添加網際網路存取授權規則...${NC}"
    internet_auth_result=$(aws ec2 authorize-client-vpn-ingress \
        --client-vpn-endpoint-id "$VPN_ENDPOINT_ID" \
        --target-network-cidr "0.0.0.0/0" \
        --authorize-all-groups \
        --region "$AWS_REGION" 2>&1)
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✅ 網際網路存取授權規則添加成功${NC}"
    else
        echo -e "${YELLOW}⚠️ 網際網路存取授權規則可能已存在或添加失敗${NC}"
    fi
else
    echo -e "${YELLOW}跳過預設路由創建${NC}"
fi

# Final status check
echo -e "\n${CYAN}=== 最終狀態檢查 ===${NC}"
final_status=$(aws ec2 describe-client-vpn-endpoints \
    --client-vpn-endpoint-ids "$VPN_ENDPOINT_ID" \
    --region "$AWS_REGION" \
    --query 'ClientVpnEndpoints[0].Status.Code' \
    --output text 2>/dev/null)

echo -e "${BLUE}VPN 端點最終狀態: ${GREEN}$final_status${NC}"

# Show current configuration
echo -e "\n${CYAN}=== 當前配置摘要 ===${NC}"
echo -e "${GREEN}VPN 端點 ID: $VPN_ENDPOINT_ID${NC}"
echo -e "${GREEN}狀態: $final_status${NC}"
echo -e "${GREEN}VPC ID: $PRIMARY_VPC_ID${NC}"
echo -e "${GREEN}子網 ID: $PRIMARY_SUBNET_ID${NC}"
echo -e "${GREEN}VPN CIDR: $VPN_CIDR${NC}"
echo -e "${GREEN}VPC CIDR: $vpc_cidr${NC}"

# Update configuration file with endpoint ID if not set
if ! grep -q "^VPN_ENDPOINT_ID=" "$CONFIG_FILE" 2>/dev/null; then
    echo "VPN_ENDPOINT_ID=\"$VPN_ENDPOINT_ID\"" >> "$CONFIG_FILE"
    echo -e "${GREEN}✅ VPN_ENDPOINT_ID 已添加到配置文件${NC}"
fi

echo -e "\n${GREEN}🎉 VPN 設置完成！${NC}"
echo -e "${YELLOW}您現在可以使用管理工具生成客戶端配置文件，並開始使用 VPN。${NC}"
echo ""
echo -e "${BLUE}下一步：${NC}"
echo -e "1. 執行 ${CYAN}./admin/aws_vpn_admin.sh${NC} 來管理 VPN"
echo -e "2. 使用 'AWS VPN 客戶端管理' 功能生成用戶配置"
echo -e "3. 分發配置文件給需要 VPN 存取的團隊成員"
