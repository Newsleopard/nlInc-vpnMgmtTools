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

# Service definitions with enhanced discovery configuration
SERVICES="MySQL_RDS:3306 Redis:6379 HBase_Master:16010 HBase_RegionServer:16020 HBase_Custom:8765 Phoenix_Query:8000 Phoenix_Web:8080 EKS_API:443"

# Discovery method configuration (priority order)
VPN_DISCOVERY_METHOD="${VPN_DISCOVERY_METHOD:-tag-based,resource-verified,pattern-based,port-based}"
VPN_DISCOVERY_INTERACTIVE="${VPN_DISCOVERY_INTERACTIVE:-true}"
VPN_DISCOVERY_MIN_CONFIDENCE="${VPN_DISCOVERY_MIN_CONFIDENCE:-MEDIUM}"

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

# Enhanced Service Discovery Functions

# Tag-based service discovery (Primary method)
discover_services_by_tags() {
    local vpc_id="$1"
    log_info "🏷️ Tag-based discovery for VPC: $vpc_id"
    
    local service_mappings=(
        "RDS:MySQL_RDS:3306"
        "Redis:Redis:6379"
        "HBase:HBase_Master:16010"
        "HBase:HBase_RegionServer:16020"
        "Phoenix:Phoenix_Query:8000"
        "EKS:EKS_API:443"
    )
    
    > /tmp/tag_based_discoveries.txt
    
    for mapping in "${service_mappings[@]}"; do
        IFS=':' read -r tag_value service_name port <<< "$mapping"
        
        log_info "  Searching for service: $service_name (tag: $tag_value)"
        
        # Search by primary service tag
        local tagged_sgs
        tagged_sgs=$(aws_with_profile ec2 describe-security-groups \
            --filters "Name=tag:Service,Values=$tag_value" \
                      "Name=vpc-id,Values=$vpc_id" \
            --query 'SecurityGroups[].{GroupId:GroupId,GroupName:GroupName,Tags:Tags}' \
            --region "$AWS_REGION" --output json 2>/dev/null || echo "[]")
        
        # Search by alternative tag variations if no results
        if [[ $(echo "$tagged_sgs" | jq '. | length') -eq 0 ]]; then
            tagged_sgs=$(aws_with_profile ec2 describe-security-groups \
                --filters "Name=tag:ServiceType,Values=$tag_value" \
                          "Name=vpc-id,Values=$vpc_id" \
                --query 'SecurityGroups[].{GroupId:GroupId,GroupName:GroupName,Tags:Tags}' \
                --region "$AWS_REGION" --output json 2>/dev/null || echo "[]")
        fi
        
        # Search by Application tag if still no results
        if [[ $(echo "$tagged_sgs" | jq '. | length') -eq 0 ]]; then
            tagged_sgs=$(aws_with_profile ec2 describe-security-groups \
                --filters "Name=tag:Application,Values=$tag_value" \
                          "Name=vpc-id,Values=$vpc_id" \
                --query 'SecurityGroups[].{GroupId:GroupId,GroupName:GroupName,Tags:Tags}' \
                --region "$AWS_REGION" --output json 2>/dev/null || echo "[]")
        fi
        
        if [[ $(echo "$tagged_sgs" | jq '. | length') -gt 0 ]]; then
            local best_sg_id
            best_sg_id=$(echo "$tagged_sgs" | jq -r '.[0].GroupId')
            echo "$service_name:$port:$best_sg_id:tag-based" >> /tmp/tag_based_discoveries.txt
            log_info "  ✓ Found tagged security group: $best_sg_id"
        else
            log_info "  ⚠️ No tagged security groups found for $service_name"
        fi
    done
}

# Resource association verification (Secondary method)
discover_services_by_resource_verification() {
    local vpc_id="$1"
    log_info "🔍 Resource association verification for VPC: $vpc_id"
    
    > /tmp/resource_verified_discoveries.txt
    
    # RDS Instance Security Groups
    log_info "  Checking RDS instances..."
    local rds_sgs
    rds_sgs=$(aws_with_profile rds describe-db-instances \
        --region "$AWS_REGION" \
        --query "DBInstances[?DBSubnetGroup.VpcId=='$vpc_id'].VpcSecurityGroups[].VpcSecurityGroupId" \
        --output text 2>/dev/null | tr '\t' '\n' | sort -u)
    
    for sg_id in $rds_sgs; do
        if [[ -n "$sg_id" && "$sg_id" != "None" ]]; then
            echo "MySQL_RDS:3306:$sg_id:resource-verified" >> /tmp/resource_verified_discoveries.txt
            log_info "  ✓ Found RDS security group: $sg_id"
        fi
    done
    
    # EKS Cluster Security Groups
    log_info "  Checking EKS clusters..."
    local clusters
    clusters=$(aws_with_profile eks list-clusters --region "$AWS_REGION" --query 'clusters[]' --output text 2>/dev/null)
    
    for cluster in $clusters; do
        local eks_sgs
        eks_sgs=$(aws_with_profile eks describe-cluster --name "$cluster" --region "$AWS_REGION" \
            --query 'cluster.resourcesVpcConfig.securityGroupIds[]' --output text 2>/dev/null)
        
        for sg_id in $eks_sgs; do
            if [[ -n "$sg_id" && "$sg_id" != "None" ]]; then
                # Verify this security group is in the target VPC
                local sg_vpc
                sg_vpc=$(aws_with_profile ec2 describe-security-groups \
                    --group-ids "$sg_id" --region "$AWS_REGION" \
                    --query 'SecurityGroups[0].VpcId' --output text 2>/dev/null)
                
                if [[ "$sg_vpc" == "$vpc_id" ]]; then
                    echo "EKS_API:443:$sg_id:resource-verified" >> /tmp/resource_verified_discoveries.txt
                    log_info "  ✓ Found EKS security group: $sg_id (cluster: $cluster)"
                fi
            fi
        done
    done
    
    # ElastiCache Security Groups (Redis)
    log_info "  Checking ElastiCache clusters..."
    local cache_sgs
    cache_sgs=$(aws_with_profile elasticache describe-cache-clusters \
        --region "$AWS_REGION" \
        --query "CacheClusters[?CacheSubnetGroupName!=null].SecurityGroups[].SecurityGroupId" \
        --output text 2>/dev/null | tr '\t' '\n' | sort -u)
    
    for sg_id in $cache_sgs; do
        if [[ -n "$sg_id" && "$sg_id" != "None" ]]; then
            # Verify this security group is in the target VPC
            local sg_vpc
            sg_vpc=$(aws_with_profile ec2 describe-security-groups \
                --group-ids "$sg_id" --region "$AWS_REGION" \
                --query 'SecurityGroups[0].VpcId' --output text 2>/dev/null)
            
            if [[ "$sg_vpc" == "$vpc_id" ]]; then
                echo "Redis:6379:$sg_id:resource-verified" >> /tmp/resource_verified_discoveries.txt
                log_info "  ✓ Found ElastiCache security group: $sg_id"
            fi
        fi
    done
    
    # EMR (HBase) Security Groups
    log_info "  Checking EMR clusters..."
    local emr_clusters
    emr_clusters=$(aws_with_profile emr list-clusters --active \
        --region "$AWS_REGION" \
        --query 'Clusters[].Id' --output text 2>/dev/null)
    
    for cluster_id in $emr_clusters; do
        if [[ -n "$cluster_id" && "$cluster_id" != "None" ]]; then
            local emr_sgs
            emr_sgs=$(aws_with_profile emr describe-cluster --cluster-id "$cluster_id" \
                --region "$AWS_REGION" \
                --query 'Cluster.Ec2InstanceAttributes.{Master:EmrManagedMasterSecurityGroup,Slave:EmrManagedSlaveSecurityGroup}' \
                --output text 2>/dev/null)
            
            echo "$emr_sgs" | tr '\t' '\n' | while read sg_id; do
                if [[ -n "$sg_id" && "$sg_id" != "None" ]]; then
                    # Verify this security group is in the target VPC
                    local sg_vpc
                    sg_vpc=$(aws_with_profile ec2 describe-security-groups \
                        --group-ids "$sg_id" --region "$AWS_REGION" \
                        --query 'SecurityGroups[0].VpcId' --output text 2>/dev/null)
                    
                    if [[ "$sg_vpc" == "$vpc_id" ]]; then
                        echo "HBase_Master:16010:$sg_id:resource-verified" >> /tmp/resource_verified_discoveries.txt
                        log_info "  ✓ Found EMR security group: $sg_id (cluster: $cluster_id)"
                    fi
                fi
            done
        fi
    done
}

# Enhanced pattern matching (Tertiary method)
discover_services_by_enhanced_patterns() {
    local vpc_id="$1"
    log_info "🔤 Enhanced pattern matching for VPC: $vpc_id"
    
    > /tmp/pattern_based_discoveries.txt
    
    for service_def in $SERVICES; do
        IFS=':' read -r service_name port <<< "$service_def"
        
        log_info "  Pattern matching for: $service_name (port $port)"
        
        # Define comprehensive pattern sets
        local patterns=()
        case "$service_name" in
            "MySQL_RDS")
                patterns=("*rds*" "*RDS*" "*mysql*" "*MySQL*" "*database*" "*db*" "*Database*")
                ;;
            "Redis")
                patterns=("*redis*" "*Redis*" "*cache*" "*Cache*" "*elasticache*" "*ElastiCache*")
                ;;
            "HBase_Master"|"HBase_RegionServer"|"HBase_Custom")
                patterns=("*hbase*" "*HBase*" "*emr*" "*EMR*" "*hadoop*" "*Hadoop*" "*ElasticMapReduce*")
                ;;
            "EKS_API")
                patterns=("*ControlPlane*" "*control-plane*" "*eks*" "*EKS*" "*kubernetes*" "*Kubernetes*" "*k8s*")
                ;;
            "Phoenix_Query"|"Phoenix_Web")
                patterns=("*phoenix*" "*Phoenix*" "*query*" "*Query*" "*web*" "*Web*")
                ;;
        esac
        
        # Search with multiple patterns
        local found=false
        for pattern in "${patterns[@]}"; do
            local matches
            matches=$(aws_with_profile ec2 describe-security-groups \
                --filters "Name=group-name,Values=$pattern" \
                          "Name=vpc-id,Values=$vpc_id" \
                --query "SecurityGroups[?IpPermissions[?FromPort<=\`$port\` && ToPort>=\`$port\`]].{GroupId:GroupId,GroupName:GroupName}" \
                --region "$AWS_REGION" --output json 2>/dev/null || echo "[]")
            
            if [[ $(echo "$matches" | jq '. | length') -gt 0 ]]; then
                local best_sg_id
                best_sg_id=$(echo "$matches" | jq -r '.[0].GroupId')
                echo "$service_name:$port:$best_sg_id:pattern-based" >> /tmp/pattern_based_discoveries.txt
                log_info "  ✓ Found by pattern '$pattern': $best_sg_id"
                found=true
                break
            fi
        done
        
        if [[ "$found" == "false" ]]; then
            log_info "  ⚠️ No pattern matches found for $service_name"
        fi
    done
}

# Discovery result validation and scoring
validate_and_score_discoveries() {
    local discoveries_file="$1"
    local output_file="${2:-/tmp/scored_discoveries.txt}"
    
    log_info "📊 Validating and scoring discovery results..."
    
    > "$output_file"
    
    while IFS=':' read -r service port sg_id method; do
        local score=0
        local confidence="LOW"
        
        # Base scoring by method
        case "$method" in
            "tag-based")
                score=100
                confidence="HIGH"
                ;;
            "resource-verified")
                score=90
                confidence="HIGH"
                ;;
            "pattern-based")
                score=70
                confidence="MEDIUM"
                ;;
            "port-only")
                score=40
                confidence="LOW"
                ;;
        esac
        
        # Additional validation checks
        if aws_with_profile ec2 describe-security-groups --group-ids "$sg_id" --region "$AWS_REGION" >/dev/null 2>&1; then
            score=$((score + 5))
        else
            score=$((score - 20))
            confidence="INVALID"
        fi
        
        # Check if security group has the expected port open
        local has_port
        has_port=$(aws_with_profile ec2 describe-security-groups \
            --group-ids "$sg_id" --region "$AWS_REGION" \
            --query "SecurityGroups[0].IpPermissions[?FromPort<=\`$port\` && ToPort>=\`$port\`]" \
            --output text 2>/dev/null)
        
        if [[ -n "$has_port" && "$has_port" != "None" ]]; then
            score=$((score + 5))
        fi
        
        # Adjust confidence based on final score
        if [[ $score -ge 90 ]]; then
            confidence="HIGH"
        elif [[ $score -ge 70 ]]; then
            confidence="MEDIUM"
        elif [[ $score -ge 50 ]]; then
            confidence="LOW"
        else
            confidence="VERY_LOW"
        fi
        
        echo "$service:$port:$sg_id:$method:$score:$confidence" >> "$output_file"
    done < "$discoveries_file"
    
    # Sort by score descending
    sort -t':' -k5 -nr "$output_file" -o "$output_file"
    
    log_info "✓ Discovery validation and scoring completed"
}

# Multi-tier discovery orchestrator
perform_multi_tier_discovery() {
    local vpc_id="$1"
    
    log_info "🚀 Starting multi-tier service discovery for VPC: $vpc_id"
    
    # Clear any existing discovery files
    rm -f /tmp/*_discoveries.txt /tmp/scored_discoveries.txt /tmp/final_discoveries.txt
    
    # Get discovery methods from configuration
    IFS=',' read -ra DISCOVERY_METHODS <<< "$VPN_DISCOVERY_METHOD"
    
    # Execute discovery methods in priority order
    for method in "${DISCOVERY_METHODS[@]}"; do
        case "$method" in
            "tag-based")
                discover_services_by_tags "$vpc_id"
                ;;
            "resource-verified")
                discover_services_by_resource_verification "$vpc_id"
                ;;
            "pattern-based")
                discover_services_by_enhanced_patterns "$vpc_id"
                ;;
            "port-based")
                # This is the original discovery method - will be implemented as fallback
                log_info "⚠️ Port-based discovery used as fallback"
                ;;
        esac
    done
    
    # Combine all discoveries and remove duplicates (keeping highest priority)
    > /tmp/combined_discoveries.txt
    
    # Process in reverse priority order so higher priority methods override
    for method in "port-based" "pattern-based" "resource-verified" "tag-based"; do
        local method_file="/tmp/${method//-/_}_discoveries.txt"
        if [[ -f "$method_file" ]]; then
            cat "$method_file" >> /tmp/combined_discoveries.txt
        fi
    done
    
    # Remove duplicates (keep last occurrence which has highest priority)
    awk -F: '!seen[$1]++' /tmp/combined_discoveries.txt > /tmp/unique_discoveries.txt
    
    # Validate and score all discoveries
    validate_and_score_discoveries /tmp/unique_discoveries.txt /tmp/scored_discoveries.txt
    
    # Filter by minimum confidence level
    > /tmp/final_discoveries.txt
    while IFS=':' read -r service port sg_id method score confidence; do
        case "$VPN_DISCOVERY_MIN_CONFIDENCE" in
            "HIGH")
                [[ "$confidence" == "HIGH" ]] && echo "$service:$port:$sg_id:$method:$score:$confidence" >> /tmp/final_discoveries.txt
                ;;
            "MEDIUM")
                [[ "$confidence" =~ ^(HIGH|MEDIUM)$ ]] && echo "$service:$port:$sg_id:$method:$score:$confidence" >> /tmp/final_discoveries.txt
                ;;
            "LOW")
                [[ "$confidence" =~ ^(HIGH|MEDIUM|LOW)$ ]] && echo "$service:$port:$sg_id:$method:$score:$confidence" >> /tmp/final_discoveries.txt
                ;;
            *)
                echo "$service:$port:$sg_id:$method:$score:$confidence" >> /tmp/final_discoveries.txt
                ;;
        esac
    done < /tmp/scored_discoveries.txt
    
    log_info "✅ Multi-tier discovery completed"
    
    # Display summary
    local total_discoveries
    total_discoveries=$(wc -l < /tmp/final_discoveries.txt 2>/dev/null || echo "0")
    log_info "📈 Discovery Summary: $total_discoveries services found meeting minimum confidence: $VPN_DISCOVERY_MIN_CONFIDENCE"
    
    return 0
}

# Interactive confirmation and manual override system
interactive_service_confirmation() {
    local discoveries_file="$1"
    local confirmed_services=()
    
    echo
    echo -e "${CYAN}=== 🔍 Interactive Service Discovery Confirmation ===${NC}"
    echo -e "${BLUE}Please review and confirm the discovered services:${NC}"
    echo
    
    local counter=1
    while IFS=':' read -r service port sg_id method score confidence; do
        local sg_name
        sg_name=$(aws_with_profile ec2 describe-security-groups \
            --group-ids "$sg_id" --region "$AWS_REGION" \
            --query 'SecurityGroups[0].GroupName' --output text 2>/dev/null || echo "Unknown")
        
        # Color code by confidence level
        local confidence_color=""
        case "$confidence" in
            "HIGH") confidence_color="${GREEN}" ;;
            "MEDIUM") confidence_color="${YELLOW}" ;;
            "LOW") confidence_color="${YELLOW}" ;;
            *) confidence_color="${RED}" ;;
        esac
        
        echo -e "${YELLOW}[$counter] $service (Port $port)${NC}"
        echo -e "    Security Group: $sg_id ($sg_name)"
        echo -e "    Discovery Method: $method"
        echo -e "    Confidence: ${confidence_color}$confidence${NC} (Score: $score)"
        echo
        
        local choice
        local attempts=0
        local max_attempts=5
        
        while [ $attempts -lt $max_attempts ]; do
            echo -n "Confirm this service? [y/n/s(kip)/m(anual override)]: "
            read -r choice
            
            # Clean input - remove any extra whitespace and take only first character for simple choices
            choice=$(echo "$choice" | xargs | tr '[:upper:]' '[:lower:]')
            
            case "$choice" in
                y|yes)
                    confirmed_services+=("$service:$port:$sg_id")
                    echo -e "${GREEN}✓ Confirmed${NC}"
                    echo
                    break
                    ;;
                n|no)
                    echo -e "${RED}✗ Rejected${NC}"
                    echo
                    break
                    ;;
                s|skip)
                    echo -e "${YELLOW}⏭ Skipped${NC}"
                    echo
                    break
                    ;;
                m|manual)
                    echo -e "${CYAN}Manual override for $service:${NC}"
                    local manual_sg_id
                    while true; do
                        echo -n "Enter security group ID (or 'cancel' to skip): "
                        read -r manual_sg_id
                        manual_sg_id=$(echo "$manual_sg_id" | xargs)
                        
                        if [[ "$manual_sg_id" == "cancel" ]]; then
                            echo -e "${YELLOW}⏭ Manual override cancelled${NC}"
                            break
                        elif [[ -n "$manual_sg_id" && "$manual_sg_id" =~ ^sg-[0-9a-f]{8,17}$ ]]; then
                            # Validate security group exists
                            if aws_with_profile ec2 describe-security-groups --group-ids "$manual_sg_id" --region "$AWS_REGION" >/dev/null 2>&1; then
                                confirmed_services+=("$service:$port:$manual_sg_id")
                                echo -e "${GREEN}✓ Manual override accepted: $manual_sg_id${NC}"
                                break
                            else
                                echo -e "${RED}✗ Invalid or non-existent security group ID: $manual_sg_id${NC}"
                                echo -e "${YELLOW}Please enter a valid security group ID (format: sg-xxxxxxxxx)${NC}"
                            fi
                        else
                            echo -e "${RED}✗ Invalid format. Security group ID should start with 'sg-'${NC}"
                            echo -e "${YELLOW}Example: sg-1234567890abcdef0${NC}"
                        fi
                    done
                    echo
                    break
                    ;;
                "")
                    echo -e "${YELLOW}Please enter a choice (y/n/s/m)${NC}"
                    attempts=$((attempts + 1))
                    ;;
                *)
                    if [[ ${#choice} -gt 20 ]]; then
                        echo -e "${RED}Invalid input detected. Please enter only: y, n, s, or m${NC}"
                        echo -e "${YELLOW}Hint: Don't paste discovery results here, just choose y/n/s/m${NC}"
                    else
                        echo -e "${RED}Invalid choice: '$choice'. Please enter y, n, s, or m${NC}"
                    fi
                    attempts=$((attempts + 1))
                    ;;
            esac
            
            if [ $attempts -eq $max_attempts ]; then
                echo -e "${YELLOW}Too many invalid attempts. Skipping this service.${NC}"
                echo
                break
            fi
        done
        
        ((counter++))
    done < "$discoveries_file"
    
    # Option to manually add completely new services
    echo -e "${CYAN}🔧 Add Additional Services?${NC}"
    echo -n "Would you like to manually add any services not discovered? [y/n]: "
    read choice
    if [[ "$choice" =~ ^[Yy] ]]; then
        manual_service_addition confirmed_services
    fi
    
    # Save confirmed services
    printf '%s\n' "${confirmed_services[@]}" > /tmp/confirmed_services.txt
    
    echo
    log_info "✅ Interactive confirmation completed"
    log_info "Confirmed services: ${#confirmed_services[@]}"
}

# Manual service addition capability
manual_service_addition() {
    local -n services_array=$1
    
    echo
    echo -e "${CYAN}=== 🛠️ Manual Service Addition ===${NC}"
    echo -e "${BLUE}Add services that were not automatically discovered:${NC}"
    echo
    
    while true; do
        echo -n "Service name (or 'done' to finish): "
        read service_name
        
        [[ "$service_name" == "done" ]] && break
        [[ -z "$service_name" ]] && continue
        
        echo -n "Port number: "
        read port
        [[ -z "$port" ]] && continue
        
        echo -n "Security Group ID: "
        read sg_id
        [[ -z "$sg_id" ]] && continue
        
        # Validate security group exists
        if aws_with_profile ec2 describe-security-groups --group-ids "$sg_id" --region "$AWS_REGION" >/dev/null 2>&1; then
            local sg_name
            sg_name=$(aws_with_profile ec2 describe-security-groups \
                --group-ids "$sg_id" --region "$AWS_REGION" \
                --query 'SecurityGroups[0].GroupName' --output text 2>/dev/null || echo "Unknown")
            
            echo -e "${GREEN}✓ Valid security group: $sg_id ($sg_name)${NC}"
            services_array+=("$service_name:$port:$sg_id")
            log_info "Manual service added: $service_name:$port:$sg_id"
        else
            echo -e "${RED}✗ Invalid security group ID: $sg_id${NC}"
            continue
        fi
        
        echo -n "Add another service? [y/n]: "
        read choice
        [[ ! "$choice" =~ ^[Yy] ]] && break
    done
    
    echo -e "${GREEN}✅ Manual service addition completed${NC}"
}

# Save discovery results to .conf file for tracking and audit purposes
# Parameters: discovery_file (e.g., /tmp/final_discoveries.txt)
save_discovery_results_to_conf() {
    local discovery_file="$1"
    
    # Get current environment configuration file
    local env_name
    env_name=$(get_current_environment_name 2>/dev/null || echo "staging")
    local config_file="$SCRIPT_DIR/../configs/${env_name}/vpn_endpoint.conf"
    
    if [ ! -f "$config_file" ]; then
        log_warning "VPN endpoint config file not found: $config_file"
        return 1
    fi
    
    if [ ! -f "$discovery_file" ] || [ ! -s "$discovery_file" ]; then
        log_warning "Discovery file not found or empty: $discovery_file"
        return 1
    fi
    
    log_info "💾 Saving discovery results to configuration file..."
    
    # Load required libraries for config updates
    if [ -f "$SCRIPT_DIR/../lib/endpoint_config.sh" ]; then
        source "$SCRIPT_DIR/../lib/endpoint_config.sh"
        log_info "  ✓ Loaded endpoint_config.sh library"
    else
        log_warning "Endpoint config library not found: $SCRIPT_DIR/../lib/endpoint_config.sh"
        log_info "  Will use manual configuration update fallback"
        # Continue with manual fallback instead of failing
    fi
    
    if [ -f "$SCRIPT_DIR/../lib/security_group_operations.sh" ]; then
        source "$SCRIPT_DIR/../lib/security_group_operations.sh"
    else
        log_warning "Security group operations library not found"
    fi
    
    # Update discovery metadata
    local current_time=$(date)
    local total_discovered=$(wc -l < "$discovery_file" 2>/dev/null || echo "0")
    local high_confidence=$(grep -c ":HIGH$" "$discovery_file" 2>/dev/null || echo "0")
    local medium_confidence=$(grep -c ":MEDIUM$" "$discovery_file" 2>/dev/null || echo "0")
    
    if command -v update_config_value >/dev/null 2>&1; then
        # Use the advanced config update function
        update_config_value "$config_file" "VPN_SERVICE_ACCESS_LAST_DISCOVERED" "$current_time"
        update_config_value "$config_file" "VPN_DISCOVERY_TOTAL_SERVICES" "$total_discovered"
        update_config_value "$config_file" "VPN_DISCOVERY_HIGH_CONFIDENCE" "$high_confidence"
        update_config_value "$config_file" "VPN_DISCOVERY_MEDIUM_CONFIDENCE" "$medium_confidence"
        update_config_value "$config_file" "VPN_DISCOVERY_METHODS_USED" "$VPN_DISCOVERY_METHOD"
        update_config_value "$config_file" "VPN_DISCOVERY_MIN_CONFIDENCE_USED" "$VPN_DISCOVERY_MIN_CONFIDENCE"
        
        log_info "  ✓ Updated discovery metadata using advanced config functions: $total_discovered services ($high_confidence HIGH, $medium_confidence MEDIUM confidence)"
    else
        # Fallback: Manual config file update
        log_info "  Using manual config file update fallback"
        
        # Create backup
        cp "$config_file" "$config_file.backup.$(date +%s)" 2>/dev/null || true
        
        # Manual update using echo and grep
        {
            echo ""
            echo "# VPN Service Discovery Results (Updated: $current_time)"
            echo "VPN_SERVICE_ACCESS_LAST_DISCOVERED=\"$current_time\""
            echo "VPN_DISCOVERY_TOTAL_SERVICES=\"$total_discovered\""
            echo "VPN_DISCOVERY_HIGH_CONFIDENCE=\"$high_confidence\""
            echo "VPN_DISCOVERY_MEDIUM_CONFIDENCE=\"$medium_confidence\""
            echo "VPN_DISCOVERY_METHODS_USED=\"$VPN_DISCOVERY_METHOD\""
            echo "VPN_DISCOVERY_MIN_CONFIDENCE_USED=\"$VPN_DISCOVERY_MIN_CONFIDENCE\""
        } >> "$config_file"
        
        log_info "  ✓ Manually appended discovery metadata: $total_discovered services ($high_confidence HIGH, $medium_confidence MEDIUM confidence)"
    fi
    
    # Store discovered services summary in readable format
    local discovered_services_summary=""
    while IFS=':' read -r service port sg_id method score confidence; do
        if [ -n "$service" ]; then
            if [ -z "$discovered_services_summary" ]; then
                discovered_services_summary="$service:$sg_id:$port($confidence)"
            else
                discovered_services_summary="$discovered_services_summary,$service:$sg_id:$port($confidence)"
            fi
        fi
    done < "$discovery_file"
    
    if [ -n "$discovered_services_summary" ]; then
        if command -v update_config_value >/dev/null 2>&1; then
            # Use advanced config function
            update_config_value "$config_file" "VPN_DISCOVERED_SERVICES_SUMMARY" "$discovered_services_summary"
            log_info "  ✓ Saved discovered services summary using advanced config functions"
        else
            # Manual fallback
            echo "VPN_DISCOVERED_SERVICES_SUMMARY=\"$discovered_services_summary\"" >> "$config_file"
            log_info "  ✓ Manually appended discovered services summary to configuration"
        fi
    else
        log_warning "  No discovered services summary to save"
    fi
    
    log_info "✅ Discovery results saved to $config_file"
    return 0
}

# Record configured VPN security groups to .conf file for cleanup tracking
# Parameters: array of "service:security_group_id:port" entries
record_vpn_configured_security_groups() {
    local configured_rules=("$@")
    
    # Get current environment configuration file
    local env_name
    env_name=$(get_current_environment_name 2>/dev/null || echo "staging")
    local config_file="$SCRIPT_DIR/../configs/${env_name}/vpn_endpoint.conf"
    
    if [ ! -f "$config_file" ]; then
        log_warning "VPN endpoint config file not found: $config_file"
        log_warning "Cannot record security group tracking for cleanup"
        return 1
    fi
    
    # Load security group tracking functions
    if [ -f "$SCRIPT_DIR/../lib/security_group_operations.sh" ]; then
        source "$SCRIPT_DIR/../lib/security_group_operations.sh"
    else
        log_warning "Security group operations library not found"
        return 1
    fi
    
    log_info "Recording configured security groups for cleanup tracking..."
    
    # Record each configured rule
    for rule in "${configured_rules[@]}"; do
        if [ -n "$rule" ]; then
            # Parse: service:security_group_id:port
            local service_name=$(echo "$rule" | cut -d':' -f1)
            local security_group_id=$(echo "$rule" | cut -d':' -f2)
            local port=$(echo "$rule" | cut -d':' -f3)
            
            if command -v record_vpn_security_group_access >/dev/null 2>&1; then
                if record_vpn_security_group_access "$config_file" "$service_name" "$security_group_id" "$port"; then
                    log_info "  ✓ Recorded: $service_name -> $security_group_id:$port"
                else
                    log_warning "  ⚠️ Failed to record: $service_name -> $security_group_id:$port"
                fi
            else
                log_warning "record_vpn_security_group_access function not available"
                break
            fi
        fi
    done
    
    log_info "✅ Security group tracking recorded for cleanup"
    return 0
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
            echo "  discover [vpn-sg-id]  - Find security groups for services (VPN SG ID optional for scoping)"
            echo "  create <vpn-sg-id>    - Create VPN access rules (VPN SG ID required)"
            echo "  remove <vpn-sg-id>    - Remove VPN access rules (VPN SG ID required)"
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

# Enhanced discover services function with multi-tier discovery
discover_services() {
    log_info "🔍 Enhanced Service Discovery - Multi-Tier Approach"
    log_info "Discovery methods: $VPN_DISCOVERY_METHOD"
    log_info "Minimum confidence: $VPN_DISCOVERY_MIN_CONFIDENCE"
    if [[ -n "$VPN_SG" ]]; then
        log_info "VPN Security Group (for scoping): $VPN_SG"
    else
        log_info "VPN Security Group: Not specified (global discovery)"
    fi
    echo
    
    # Get VPN security group VPC if VPN_SG is provided
    local target_vpc=""
    if [[ -n "$VPN_SG" ]]; then
        target_vpc=$(aws_with_profile ec2 describe-security-groups \
            --group-ids "$VPN_SG" \
            --region "$AWS_REGION" \
            --query 'SecurityGroups[0].VpcId' \
            --output text 2>/dev/null)
        if [[ -n "$target_vpc" && "$target_vpc" != "None" ]]; then
            log_info "🎯 Discovery scope: VPC $target_vpc (same as VPN security group)"
            echo
        fi
    else
        log_warning "No VPN security group provided - discovery will check all VPCs"
        echo
    fi
    
    # Perform multi-tier discovery
    if [[ -n "$target_vpc" ]]; then
        perform_multi_tier_discovery "$target_vpc"
    else
        log_warning "⚠️ Falling back to original discovery method (no VPC context)"
        discover_services_fallback
        return $?
    fi
    
    # Copy final discoveries to the expected format for backward compatibility
    > /tmp/discovered_services.txt
    if [[ -f /tmp/final_discoveries.txt && -s /tmp/final_discoveries.txt ]]; then
        while IFS=':' read -r service port sg_id method score confidence; do
            echo "$service:$port:$sg_id" >> /tmp/discovered_services.txt
        done < /tmp/final_discoveries.txt
    fi
    
    # Apply interactive confirmation if enabled
    if [[ "$VPN_DISCOVERY_INTERACTIVE" == "true" && -s /tmp/final_discoveries.txt ]]; then
        log_info "🔄 Starting interactive service confirmation..."
        
        # Check if we're in a non-interactive environment (CI/automation)
        if [[ ! -t 0 ]]; then
            log_warning "⚠️ Non-interactive environment detected, auto-confirming HIGH confidence services"
            > /tmp/confirmed_services.txt
            while IFS=':' read -r service port sg_id method score confidence; do
                if [[ "$confidence" == "HIGH" ]]; then
                    echo "$service:$port:$sg_id" >> /tmp/confirmed_services.txt
                    log_info "Auto-confirmed: $service -> $sg_id ($confidence confidence)"
                fi
            done < /tmp/final_discoveries.txt
        else
            # Interactive mode
            if interactive_service_confirmation /tmp/final_discoveries.txt 2>/dev/null; then
                log_info "✅ Interactive confirmation completed successfully"
            else
                log_warning "⚠️ Interactive confirmation failed, using auto-confirmation for HIGH confidence services"
                > /tmp/confirmed_services.txt
                while IFS=':' read -r service port sg_id method score confidence; do
                    if [[ "$confidence" == "HIGH" ]]; then
                        echo "$service:$port:$sg_id" >> /tmp/confirmed_services.txt
                        log_info "Auto-confirmed after failure: $service -> $sg_id ($confidence confidence)"
                    fi
                done < /tmp/final_discoveries.txt
            fi
        fi
        
        # Update discovered_services.txt with confirmed results
        if [[ -f /tmp/confirmed_services.txt && -s /tmp/confirmed_services.txt ]]; then
            cp /tmp/confirmed_services.txt /tmp/discovered_services.txt
            log_info "✅ Using confirmed services for VPN access rule creation"
        else
            log_warning "⚠️ No services confirmed, keeping all discovered services"
        fi
    else
        log_info "📋 Interactive confirmation disabled, using all discovered services"
    fi
    
    # Save discovery results to .conf file for tracking and audit
    if [[ -s /tmp/final_discoveries.txt ]]; then
        log_info "💾 Saving discovery results to configuration file..."
        if save_discovery_results_to_conf /tmp/final_discoveries.txt; then
            log_info "✅ Discovery results successfully saved to .conf file"
        else
            log_warning "⚠️ Failed to save discovery results to .conf file"
        fi
    else
        log_warning "⚠️ No final discoveries to save to .conf file"
    fi
    
    # Display enhanced discovery results
    if [[ -s /tmp/final_discoveries.txt ]]; then
        echo
        echo "📋 Enhanced Discovery Results:"
        echo "============================================="
        printf "%-15s %-6s %-20s %-15s %-6s %-10s\n" "Service" "Port" "Security Group" "Method" "Score" "Confidence"
        echo "---------------------------------------------"
        
        while IFS=':' read -r service port sg_id method score confidence; do
            # Get security group name for display
            local sg_name
            sg_name=$(aws_with_profile ec2 describe-security-groups \
                --group-ids "$sg_id" --region "$AWS_REGION" \
                --query 'SecurityGroups[0].GroupName' --output text 2>/dev/null || echo "Unknown")
            
            printf "%-15s %-6s %-20s %-15s %-6s %-10s\n" "$service" "$port" "${sg_id:0:18}..." "$method" "$score" "$confidence"
            echo "  └─ Name: $sg_name"
        done < /tmp/final_discoveries.txt
        
        echo
        echo "📊 Export Commands:"
        echo "==================="
        while IFS=':' read -r service port sg_id method score confidence; do
            echo "export ${service}_SG=\"$sg_id\"  # $method ($confidence confidence)"
        done < /tmp/final_discoveries.txt
    else
        log_warning "⚠️ No services discovered meeting minimum confidence level: $VPN_DISCOVERY_MIN_CONFIDENCE"
        log_info "Consider lowering VPN_DISCOVERY_MIN_CONFIDENCE or using manual configuration"
    fi
}

# Fallback discovery method (original implementation)
discover_services_fallback() {
    log_info "🔄 Using fallback discovery method..."
    
    > /tmp/discovered_services.txt
    
    for service_def in $SERVICES; do
        IFS=':' read -r service_name port <<< "$service_def"
        
        echo "🔍 $service_name (port $port):"
        
        # Find security groups with this port (global search)
        local query="SecurityGroups[?IpPermissions[?FromPort<=\`$port\` && ToPort>=\`$port\`]]"
        
        aws_with_profile ec2 describe-security-groups \
            --region "$AWS_REGION" \
            --query "$query.{GroupId:GroupId,GroupName:GroupName,VpcId:VpcId}" \
            --output json | \
        jq -r '.[] | "  • \(.GroupId) (\(.GroupName // "No Name")) in VPC \(.VpcId)"'
        
        # Save first match for each service
        local first_sg
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
        echo "📋 Fallback Discovery Results:"
        echo "=============================="
        while IFS=':' read -r service port sg_id; do
            echo "export ${service}_SG=\"$sg_id\"  # Port $port (fallback method)"
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
    local configured_rules=()
    
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
            # Track successfully configured rules
            configured_rules+=("$service:$target_sg:$port")
        else
            echo "  ⚠️  May already exist or failed"
            # Still track for cleanup (might have been created before)
            configured_rules+=("$service:$target_sg:$port")
        fi
    done < /tmp/discovered_services.txt
    
    echo
    log_info "Created $success/$total rules"
    
    # Record configured security groups in .conf file if not dry run
    if [[ "$DRY_RUN" != "true" && ${#configured_rules[@]} -gt 0 ]]; then
        record_vpn_configured_security_groups "${configured_rules[@]}"
    fi
}

# FIXED: Comprehensive VPN access rules removal
remove_rules() {
    local vpn_sg="$1"
    
    log_info "🔍 COMPREHENSIVE SEARCH: Finding ALL rules that reference VPN security group $vpn_sg..."
    echo
    
    # Find ALL security group rules that reference our VPN security group
    local all_vpn_rules
    all_vpn_rules=$(aws_with_profile ec2 describe-security-group-rules \
        --region "$AWS_REGION" \
        --query "SecurityGroupRules[?ReferencedGroupInfo.GroupId=='$vpn_sg' && !IsEgress].[GroupId,SecurityGroupRuleId,IpProtocol,FromPort,ToPort,ReferencedGroupInfo.GroupId]" \
        --output json 2>/dev/null || echo "[]")
    
    local rule_count
    rule_count=$(echo "$all_vpn_rules" | jq '. | length')
    
    if [[ $rule_count -eq 0 ]]; then
        log_info "No VPN access rules found that reference security group $vpn_sg"
        return 0
    fi
    
    log_info "Found $rule_count VPN access rules to remove:"
    echo
    
    # Display all rules that will be removed
    echo "$all_vpn_rules" | jq -r '.[] | "  • Rule \(.[1]) in SG \(.[0]) - \(.[2]):\(.[3]) (references \(.[5]))"'
    echo
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would remove all $rule_count rules above"
        return 0
    fi
    
    log_info "Removing VPN access rules..."
    echo
    
    local success=0
    local total=0
    
    # Process each rule
    while IFS= read -r rule; do
        local target_sg rule_id protocol port
        target_sg=$(echo "$rule" | jq -r '.[0]')
        rule_id=$(echo "$rule" | jq -r '.[1]')
        protocol=$(echo "$rule" | jq -r '.[2]')
        port=$(echo "$rule" | jq -r '.[3]')
        
        ((total++))
        
        # Get security group name for better logging
        local sg_name
        sg_name=$(aws_with_profile ec2 describe-security-groups \
            --group-ids "$target_sg" \
            --region "$AWS_REGION" \
            --query 'SecurityGroups[0].GroupName' \
            --output text 2>/dev/null || echo "Unknown")
        
        log_info "Removing: Rule $rule_id from $sg_name ($target_sg) - $protocol:$port"
        
        if aws_with_profile ec2 revoke-security-group-ingress \
            --group-id "$target_sg" \
            --security-group-rule-ids "$rule_id" \
            --region "$AWS_REGION" 2>/dev/null; then
            echo "  ✅ Success"
            ((success++))
        else
            echo "  ❌ Failed"
        fi
    done < <(echo "$all_vpn_rules" | jq -c '.[]')
    
    echo
    log_info "Removed $success/$total rules"
    
    if [[ $success -eq $total ]]; then
        log_info "🎉 All VPN access rules successfully removed!"
    else
        log_warning "⚠️  Some rules could not be removed. Check the errors above."
    fi
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
