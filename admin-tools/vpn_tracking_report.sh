#!/bin/bash

# VPN Security Group Tracking Report Generator
# Generates a human-readable report from vpn_security_groups_tracking.conf

set -e

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load environment management
source "$SCRIPT_DIR/../lib/env_manager.sh"

# Initialize environment
if ! env_init_for_script "vpn_tracking_report.sh"; then
    echo -e "${RED}错误: 环境初始化失败${NC}" >&2
    exit 1
fi

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
TRACKING_FILE="$SCRIPT_DIR/../configs/${CURRENT_ENVIRONMENT}/vpn_security_groups_tracking.conf"

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
        IFS=';' read -ra GROUPS <<< "$MODIFIED_GROUPS"
        
        local current_service=""
        for group in "${GROUPS[@]}"; do
            if [[ -n "$group" ]]; then
                IFS=':' read -r sg_id service_name port <<< "$group"
                
                # Group by service
                if [[ "$service_name" != "$current_service" ]]; then
                    if [[ -n "$current_service" ]]; then
                        echo
                    fi
                    echo -e "${BOLD}${YELLOW}📦 $service_name (Port $port):${NC}"
                    current_service="$service_name"
                fi
                
                # Get security group name if possible
                local sg_name=""
                if command -v aws >/dev/null 2>&1; then
                    sg_name=$(aws_with_profile ec2 describe-security-groups \
                        --group-ids "$sg_id" --region "${AWS_REGION:-us-east-1}" \
                        --query 'SecurityGroups[0].GroupName' --output text 2>/dev/null || echo "")
                fi
                
                if [[ -n "$sg_name" && "$sg_name" != "None" ]]; then
                    echo -e "  ${GREEN}•${NC} $sg_id (${DIM}$sg_name${NC})"
                else
                    echo -e "  ${GREEN}•${NC} $sg_id"
                fi
            fi
        done
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
    echo -e "${BOLD}Environment:${NC} $CURRENT_ENVIRONMENT"
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
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --summary|-s)
                format="summary"
                shift
                ;;
            --commands|-c)
                show_commands=true
                shift
                ;;
            --help|-h)
                cat << EOF
VPN Security Group Tracking Report Generator

Usage: $0 [options]

Options:
  --summary, -s     Show only summary information
  --commands, -c    Include removal commands
  --help, -h        Show this help message

Examples:
  $0                # Full report
  $0 --summary      # Summary only
  $0 --commands     # Include removal commands
EOF
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
    echo -e "${DIM}Environment: ${BOLD}$CURRENT_ENVIRONMENT${NC}"
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