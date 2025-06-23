#!/bin/bash

# VPN Service Access Manager - Environment-Aware
# Discovers and manages VPN access to AWS services dynamically
# Integrated with toolkit's environment management system
#
# Usage: ./manage_vpn_service_access.sh <action> [vpn-sg-id] [options]

set -e

# 獲取腳本目錄
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 載入環境管理器 (必須第一個載入)
source "$SCRIPT_DIR/../lib/env_manager.sh"

# 初始化環境
if ! env_init_for_script "manage_vpn_service_access.sh"; then
    echo -e "${RED}錯誤: 環境初始化失敗${NC}" >&2
    exit 1
fi

# Configuration
AWS_REGION="${AWS_REGION:-us-east-1}"
ACTION=""
VPN_SG=""
DRY_RUN=false

# Service definitions
SERVICES="MySQL_RDS:3306 Redis:6379 HBase_Master:16010 HBase_RegionServer:16020 HBase_Custom:8765 Phoenix_Query:8000 Phoenix_Web:8080 EKS_API:443"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# Enhanced logging functions with core integration
log_info() { 
    echo -e "${GREEN}[INFO]${NC} $*"
    log_message_core "INFO: $*"
}
log_warning() { 
    echo -e "${YELLOW}[WARNING]${NC} $*"
    log_message_core "WARNING: $*"
}
log_error() { 
    echo -e "${RED}[ERROR]${NC} $*"
    log_message_core "ERROR: $*"
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        discover|create|remove)
            ACTION="$1"
            shift
            ;;
        --region)
            AWS_REGION="$2"
            shift 2
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        -h|--help)
            echo "Usage: $0 <action> [vpn-sg-id] [options]"
            echo ""
            echo "Environment-aware VPN Service Access Manager"
            echo "Integrated with toolkit's AWS profile and environment management"
            echo ""
            echo "Actions:"
            echo "  discover              - Find security groups for services"
            echo "  create <vpn-sg-id>    - Create VPN access rules"
            echo "  remove <vpn-sg-id>    - Remove VPN access rules"
            echo ""
            echo "Options:"
            echo "  --region REGION       - AWS region (default: us-east-1)"
            echo "  --dry-run            - Preview changes only"
            echo ""
            echo "Environment Features:"
            echo "  • Automatically uses correct AWS profile for current environment"
            echo "  • Cross-account validation to prevent wrong environment operations"
            echo "  • Integrated logging with core toolkit logging system"
            echo "  • Environment-specific operation tracking"
            exit 0
            ;;
        sg-*)
            VPN_SG="$1"
            shift
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Validate
if [[ -z "$ACTION" ]]; then
    log_error "Action required: discover, create, or remove"
    exit 1
fi

if [[ "$ACTION" != "discover" && -z "$VPN_SG" ]]; then
    log_error "VPN Security Group ID required for $ACTION"
    exit 1
fi

# Check AWS CLI and environment
log_info "驗證 AWS 環境和權限..."
log_message_core "開始 AWS 環境驗證: region=$AWS_REGION, environment=$CURRENT_ENVIRONMENT"

# 驗證 AWS CLI 配置和環境
if ! aws_with_profile sts get-caller-identity --region "$AWS_REGION" &> /dev/null; then
    log_error "AWS CLI 未配置或無法訪問 AWS 服務"
    log_error "請檢查 AWS 憑證和網絡連接"
    exit 1
fi

# 顯示當前環境信息
caller_identity=$(aws_with_profile sts get-caller-identity --region "$AWS_REGION" 2>/dev/null)
if [ $? -eq 0 ]; then
    account_id=$(echo "$caller_identity" | jq -r '.Account' 2>/dev/null)
    user_arn=$(echo "$caller_identity" | jq -r '.Arn' 2>/dev/null)
    log_info "當前 AWS 環境: $CURRENT_ENVIRONMENT"
    log_info "AWS 帳戶: $account_id"
    log_info "AWS 區域: $AWS_REGION"
    log_info "使用者身份: $user_arn"
    log_message_core "AWS 環境驗證成功: account=$account_id, user=$user_arn"
else
    log_warning "無法獲取 AWS 身份信息，但基本連接正常"
fi

# Discover security groups for services
discover_services() {
    log_info "Discovering security groups for services in $AWS_REGION..."
    echo
    
    > /tmp/discovered_services.txt
    
    for service_def in $SERVICES; do
        IFS=':' read -r service_name port <<< "$service_def"
        
        echo "🔍 $service_name (port $port):"
        
        # Find security groups with this port
        aws_with_profile ec2 describe-security-groups \
            --region "$AWS_REGION" \
            --query "SecurityGroups[?IpPermissions[?FromPort<=\`$port\` && ToPort>=\`$port\`]].{GroupId:GroupId,GroupName:GroupName,VpcId:VpcId}" \
            --output json | \
        jq -r '.[] | "  • \(.GroupId) (\(.GroupName // "No Name")) in VPC \(.VpcId)"'
        
        # Save first match for each service
        first_sg=$(aws_with_profile ec2 describe-security-groups \
            --region "$AWS_REGION" \
            --query "SecurityGroups[?IpPermissions[?FromPort<=\`$port\` && ToPort>=\`$port\`]].GroupId" \
            --output text | awk '{print $1}')
        
        if [[ -n "$first_sg" && "$first_sg" != "None" ]]; then
            echo "$service_name:$port:$first_sg" >> /tmp/discovered_services.txt
        fi
        
        echo
    done
    
    if [[ -s /tmp/discovered_services.txt ]]; then
        echo "📋 Summary - Primary Security Groups:"
        echo "===================================="
        while IFS=':' read -r service port sg_id; do
            echo "export ${service}_SG=\"$sg_id\"  # Port $port"
        done < /tmp/discovered_services.txt
    fi
}

# Create VPN access rules
create_rules() {
    local vpn_sg="$1"
    
    if [[ ! -s /tmp/discovered_services.txt ]]; then
        log_error "No services discovered. Run 'discover' first."
        exit 1
    fi
    
    log_info "Creating VPN access rules for $vpn_sg..."
    echo
    
    local success=0
    local total=0
    
    while IFS=':' read -r service port target_sg; do
        ((total++))
        
        if [[ "$DRY_RUN" == "true" ]]; then
            log_info "[DRY-RUN] Would create: $service (port $port) in $target_sg"
            continue
        fi
        
        log_info "Creating: $service (port $port) in $target_sg"
        
        if aws_with_profile ec2 authorize-security-group-ingress \
            --group-id "$target_sg" \
            --protocol tcp \
            --port "$port" \
            --source-group "$vpn_sg" \
            --region "$AWS_REGION" 2>/dev/null; then
            echo "  ✅ Success"
            ((success++))
        else
            echo "  ⚠️  May already exist or failed"
        fi
    done < /tmp/discovered_services.txt
    
    echo
    log_info "Created $success/$total rules"
}

# Remove VPN access rules
remove_rules() {
    local vpn_sg="$1"
    
    if [[ ! -s /tmp/discovered_services.txt ]]; then
        log_error "No services discovered. Run 'discover' first."
        exit 1
    fi
    
    log_info "Removing VPN access rules for $vpn_sg..."
    echo
    
    local success=0
    local total=0
    
    while IFS=':' read -r service port target_sg; do
        # Find existing rules
        local rule_ids
        rule_ids=$(aws_with_profile ec2 describe-security-group-rules \
            --region "$AWS_REGION" \
            --filters "Name=group-id,Values=$target_sg" \
            --query "SecurityGroupRules[?ReferencedGroupInfo.GroupId=='$vpn_sg' && !IsEgress && FromPort<=\`$port\` && ToPort>=\`$port\`].SecurityGroupRuleId" \
            --output text 2>/dev/null || echo "")
        
        for rule_id in $rule_ids; do
            if [[ -n "$rule_id" && "$rule_id" != "None" ]]; then
                ((total++))
                
                if [[ "$DRY_RUN" == "true" ]]; then
                    log_info "[DRY-RUN] Would remove: $service (port $port) rule $rule_id"
                    continue
                fi
                
                log_info "Removing: $service (port $port) rule $rule_id"
                
                if aws_with_profile ec2 revoke-security-group-ingress \
                    --group-id "$target_sg" \
                    --security-group-rule-ids "$rule_id" \
                    --region "$AWS_REGION" 2>/dev/null; then
                    echo "  ✅ Success"
                    ((success++))
                else
                    echo "  ❌ Failed"
                fi
            fi
        done
    done < /tmp/discovered_services.txt
    
    echo
    log_info "Removed $success/$total rules"
}

# Main execution
main() {
    log_info "🔧 VPN Service Access Manager - Environment-Aware"
    log_info "Action: $ACTION | Region: $AWS_REGION | Environment: $CURRENT_ENVIRONMENT"
    if [[ -n "$VPN_SG" ]]; then
        log_info "VPN Security Group: $VPN_SG"
    fi
    log_message_core "VPN Service Access Manager 執行開始: action=$ACTION, region=$AWS_REGION, environment=$CURRENT_ENVIRONMENT, vpn_sg=$VPN_SG"
    echo "================================"
    
    case "$ACTION" in
        "discover")
            discover_services
            ;;
        "create")
            discover_services
            echo
            create_rules "$VPN_SG"
            ;;
        "remove")
            discover_services
            echo
            remove_rules "$VPN_SG"
            ;;
    esac
    
    # Cleanup
    rm -f /tmp/discovered_services.txt
    
    echo
    log_info "✅ Operation completed!"
    log_message_core "VPN Service Access Manager 執行完成: action=$ACTION, environment=$CURRENT_ENVIRONMENT"
}

main "$@"
