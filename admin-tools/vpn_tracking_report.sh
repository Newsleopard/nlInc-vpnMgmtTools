#!/bin/bash

# VPN Security Group Tracking Report Generator
# Generates a human-readable report from vpn_security_groups_tracking.conf
# 版本：1.1 (直接 Profile 選擇版本)

# 全域變數
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARENT_DIR="$(dirname "$SCRIPT_DIR")"

# Parse command line arguments
AWS_PROFILE=""
TARGET_ENVIRONMENT=""

# Parse command line arguments for help first
for arg in "$@"; do
    if [[ "$arg" == "-h" || "$arg" == "--help" ]]; then
        cat << 'EOF'
VPN Security Group Tracking Report Generator

用法: $0 [選項]

選項:
  -p, --profile PROFILE     AWS CLI profile
  -e, --environment ENV     目標環境 (staging/production)
  --summary, -s             只顯示摘要資訊
  --commands, -c            包含移除指令
  -h, --help               顯示此幫助訊息

範例:
  $0                        # 完整報告
  $0 --summary              # 摘要報告
  $0 --commands             # 包含移除指令
EOF
        exit 0
    fi
done

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --profile|-p)
            AWS_PROFILE="$2"
            shift 2
            ;;
        --environment|-e)
            TARGET_ENVIRONMENT="$2"
            shift 2
            ;;
        --summary|-s|--commands|-c)
            # These will be handled later in main()
            break
            ;;
        --help|-h)
            # Already handled above
            shift
            ;;
        -*) 
            # Unknown options will be handled later
            break
            ;;
        *)
            shift
            ;;
    esac
done

# 載入新的 Profile Selector (替代 env_manager.sh)
source "$PARENT_DIR/lib/profile_selector.sh"

# 載入環境核心函式 (用於顯示功能)
source "$PARENT_DIR/lib/env_core.sh"

# Select and validate profile
if ! select_and_validate_profile --profile "$AWS_PROFILE" --environment "$TARGET_ENVIRONMENT"; then
    echo -e "${RED}錯誤: Profile 選擇失敗${NC}"
    exit 1
fi

# 載入核心函式庫
source "$PARENT_DIR/lib/core_functions.sh"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

# Get tracking file path
TRACKING_FILE="$PARENT_DIR/configs/${SELECTED_ENVIRONMENT}/vpn_security_groups_tracking.conf"

# Check if tracking file exists
if [[ ! -f "$TRACKING_FILE" ]]; then
    echo -e "${RED}❌ No VPN tracking file found: $TRACKING_FILE${NC}"
    echo -e "${YELLOW}💡 This means no VPN access rules have been configured yet.${NC}"
    exit 1
fi

# Parse tracking file
parse_tracking_file() {
    # Extract values from tracking file
    VPN_SG_ID=$(grep "^VPN_SECURITY_GROUP_ID=" "$TRACKING_FILE" | cut -d'=' -f2 | tr -d '"')
    LAST_CONFIG_TIME=$(grep "^VPN_LAST_CONFIGURATION_TIME=" "$TRACKING_FILE" | cut -d'=' -f2 | tr -d '"')
    CONFIG_METHOD=$(grep "^VPN_CONFIGURATION_METHOD=" "$TRACKING_FILE" | cut -d'=' -f2 | tr -d '"')
    TOTAL_COUNT=$(grep "^VPN_MODIFIED_SECURITY_GROUPS_COUNT=" "$TRACKING_FILE" | cut -d'=' -f2 | tr -d '"')
    MODIFIED_GROUPS=$(grep "^VPN_MODIFIED_SECURITY_GROUPS=" "$TRACKING_FILE" | cut -d'=' -f2 | tr -d '"')
    CONFIG_LOG=$(grep "^VPN_CONFIGURATION_LOG=" "$TRACKING_FILE" | cut -d'=' -f2 | tr -d '"')
}

# Generate service summary
generate_service_summary() {
    echo -e "${CYAN}=== 📊 VPN Access Rules Summary ===${NC}"
    echo
    
    if [[ -n "$MODIFIED_GROUPS" ]]; then
        # Create temporary files for counting
        local temp_services="/tmp/vpn_services_$$"
        local temp_summary="/tmp/vpn_summary_$$"
        
        # Extract and count services
        echo "$MODIFIED_GROUPS" | tr ';' '\n' | while IFS=':' read -r sg_id service_name port; do
            if [[ -n "$service_name" ]]; then
                echo "$service_name:$port:$sg_id"
            fi
        done > "$temp_services"
        
        # Generate summary by service type
        for service_type in "MySQL_RDS" "Redis" "EKS_API" "HBase_Master" "HBase_RegionServer" "HBase_Custom" "Phoenix_Query" "Phoenix_Web"; do
            local count=$(grep "^$service_type:" "$temp_services" | wc -l | xargs)
            if [[ $count -gt 0 ]]; then
                local port=$(grep "^$service_type:" "$temp_services" | head -1 | cut -d':' -f2)
                local first_sgs=$(grep "^$service_type:" "$temp_services" | head -3 | cut -d':' -f3 | tr '\n' ',' | sed 's/,$//')
                echo "$service_type:$port:$count:$first_sgs" >> "$temp_summary"
            fi
        done
        
        # Display service summary
        printf "${BOLD}%-20s %-8s %-12s %s${NC}\n" "Service" "Port" "Count" "Security Groups (sample)"
        echo "────────────────────────────────────────────────────────────────────────────────"
        
        while IFS=':' read -r service port count sgs; do
            local color="${GREEN}"
            
            # Determine color based on service
            case "$service" in
                "MySQL_RDS") color="${GREEN}" ;;
                "Redis") color="${YELLOW}" ;;
                "EKS_API") color="${BLUE}" ;;
                "HBase_Master"|"HBase_RegionServer"|"HBase_Custom") color="${CYAN}" ;;
                "Phoenix_Query"|"Phoenix_Web") color="${YELLOW}" ;;
                *) color="${NC}" ;;
            esac
            
            printf "${color}%-20s %-8s %-12s${NC} %s\n" \
                   "$service" "$port" "$count" \
                   "$(echo "$sgs" | cut -c1-50)..."
        done < "$temp_summary"
        
        # Clean up
        rm -f "$temp_services" "$temp_summary"
        echo
    else
        echo -e "${YELLOW}No VPN access rules configured.${NC}"
        echo
    fi
}

# Generate detailed security group list
generate_detailed_list() {
    echo -e "${CYAN}=== 🔧 Detailed Security Group Modifications ===${NC}"
    echo
    
    if [[ -n "$MODIFIED_GROUPS" ]]; then
        # Create temporary file to group by service
        local temp_grouped="/tmp/vpn_grouped_$$"
        
        # Parse and group security groups by service
        echo "$MODIFIED_GROUPS" | tr ';' '\n' | while IFS=':' read -r sg_id service_name port; do
            if [[ -n "$sg_id" && -n "$service_name" && -n "$port" ]]; then
                echo "$service_name:$port:$sg_id"
            fi
        done | sort > "$temp_grouped"
        
        if [[ -f "$temp_grouped" && -s "$temp_grouped" ]]; then
            local current_service=""
            local current_port=""
            
            while IFS=':' read -r service_name port sg_id; do
                # Group by service and port
                if [[ "$service_name:$port" != "$current_service:$current_port" ]]; then
                    if [[ -n "$current_service" ]]; then
                        echo
                    fi
                    echo -e "${BOLD}${YELLOW}📦 $service_name (Port $port):${NC}"
                    current_service="$service_name"
                    current_port="$port"
                fi
                
                # Get security group name if possible
                local sg_name=""
                if command -v aws >/dev/null 2>&1; then
                    sg_name=$(aws ec2 describe-security-groups \
                        --profile "$SELECTED_AWS_PROFILE" \
                        --group-ids "$sg_id" --region "${AWS_REGION:-us-east-1}" \
                        --query 'SecurityGroups[0].GroupName' --output text 2>/dev/null || echo "")
                fi
                
                if [[ -n "$sg_name" && "$sg_name" != "None" ]]; then
                    echo -e "  ${GREEN}•${NC} $sg_id (${DIM}$sg_name${NC})"
                else
                    echo -e "  ${GREEN}•${NC} $sg_id"
                fi
            done < "$temp_grouped"
            echo
        else
            echo -e "${YELLOW}No detailed information available${NC}"
            echo
        fi
        
        # Clean up
        rm -f "$temp_grouped"
    else
        echo -e "${YELLOW}No VPN access rules configured.${NC}"
        echo
    fi
}

# Generate AWS CLI commands for removal
generate_removal_commands() {
    echo -e "${CYAN}=== 🗑️ VPN Access Removal Commands ===${NC}"
    echo
    echo -e "${YELLOW}To remove all VPN access rules, use:${NC}"
    echo -e "${DIM}./admin-tools/manage_vpn_service_access.sh remove $VPN_SG_ID --region \${AWS_REGION:-us-east-1}${NC}"
    echo
    echo -e "${YELLOW}To preview what will be removed (dry-run):${NC}"
    echo -e "${DIM}./admin-tools/manage_vpn_service_access.sh remove $VPN_SG_ID --dry-run --region \${AWS_REGION:-us-east-1}${NC}"
    echo
}

# Generate audit information
generate_audit_info() {
    echo -e "${CYAN}=== 📋 Configuration Audit Information ===${NC}"
    echo
    echo -e "${BOLD}VPN Security Group ID:${NC} $VPN_SG_ID"
    echo -e "${BOLD}Environment:${NC} $SELECTED_ENVIRONMENT"
    echo -e "${BOLD}Last Configuration:${NC} $LAST_CONFIG_TIME"
    echo -e "${BOLD}Configuration Method:${NC} $CONFIG_METHOD"
    echo -e "${BOLD}Total Modifications:${NC} $TOTAL_COUNT security group rules"
    echo -e "${BOLD}Tracking File:${NC} $TRACKING_FILE"
    echo
}

# Generate configuration timeline
generate_timeline() {
    echo -e "${CYAN}=== ⏰ Configuration Timeline ===${NC}"
    echo
    
    if [[ -n "$CONFIG_LOG" ]]; then
        echo -e "${DIM}Showing recent configuration changes:${NC}"
        echo
        
        # Parse configuration log and show recent entries
        IFS=';' read -ra LOG_ENTRIES <<< "$CONFIG_LOG"
        local count=0
        local max_entries=10
        
        for entry in "${LOG_ENTRIES[@]}"; do
            if [[ -n "$entry" && $count -lt $max_entries ]]; then
                IFS='|' read -r timestamp vpn_sg target_sg service port action rule_id <<< "$entry"
                
                local action_color=""
                case "$action" in
                    "ADD") action_color="${GREEN}➕" ;;
                    "REMOVE") action_color="${RED}➖" ;;
                    *) action_color="${YELLOW}•" ;;
                esac
                
                echo -e "${DIM}$timestamp${NC} ${action_color} $service:$port ${NC}→ $target_sg"
                ((count++))
            fi
        done
        
        if [[ ${#LOG_ENTRIES[@]} -gt $max_entries ]]; then
            echo -e "${DIM}... and $((${#LOG_ENTRIES[@]} - max_entries)) more entries${NC}"
        fi
        echo
    fi
}

# Main report generation
main() {
    local format="full"
    local show_commands=false
    
    # Parse remaining command line arguments (profile args already handled)
    while [[ $# -gt 0 ]]; do
        case $1 in
            --profile|-p)
                # Skip profile arguments (already handled)
                shift 2
                ;;
            --environment|-e)
                # Skip environment arguments (already handled)
                shift 2
                ;;
            --summary|-s)
                format="summary"
                shift
                ;;
            --commands|-c)
                show_commands=true
                shift
                ;;
            --help|-h)
                # Help already handled earlier
                exit 0
                ;;
            *)
                echo "Unknown option: $1"
                exit 1
                ;;
        esac
    done
    
    # Parse tracking file
    parse_tracking_file
    
    # Generate report header
    echo
    echo -e "${BOLD}${BLUE}🔒 VPN Security Group Tracking Report${NC}"
    echo -e "${DIM}Generated: $(date)${NC}"
    echo -e "${DIM}Environment: ${BOLD}$SELECTED_ENVIRONMENT${NC}"
    echo "═══════════════════════════════════════════════════════════════════════"
    echo
    
    # Check if there are any modifications
    if [[ -z "$VPN_SG_ID" || "$TOTAL_COUNT" == "0" ]]; then
        echo -e "${YELLOW}ℹ️  No VPN access rules are currently configured.${NC}"
        echo -e "${DIM}Run VPN endpoint creation to configure access rules.${NC}"
        echo
        return 0
    fi
    
    # Generate audit info
    generate_audit_info
    
    # Generate reports based on format
    if [[ "$format" == "summary" ]]; then
        generate_service_summary
    else
        generate_service_summary
        generate_detailed_list
        generate_timeline
    fi
    
    # Generate removal commands if requested
    if [[ "$show_commands" == "true" ]]; then
        generate_removal_commands
    fi
    
    echo -e "${GREEN}✅ Report generation completed${NC}"
    echo
}

main "$@"