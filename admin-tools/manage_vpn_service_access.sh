#!/bin/bash

# VPN Service Access Manager - Environment-Aware
# Discovers and manages VPN access to AWS services dynamically
# Integrated with toolkit's environment management system
#
# Usage: ./manage_vpn_service_access.sh <action> [vpn-sg-id] [options]

set -e

# 獲取腳本目錄
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Check for help first before environment initialization
for arg in "$@"; do
    if [[ "$arg" == "-h" || "$arg" == "--help" ]]; then
        # Show basic help without environment initialization
        cat << EOF
VPN Service Access Manager - Environment-Aware

Usage: $0 <action> [vpn-sg-id] [options]

Actions:
  discover              - Discover available AWS services in the VPC
  display-services      - Display previously discovered services  
  create                - Create VPN access rules to discovered services
  remove                - Remove VPN access rules from services
  clean                 - Clean up tracking files and discovery cache
  report                - Generate human-readable VPN tracking report

Arguments:
  vpn-sg-id            - Security Group ID of the VPN client (required for create/remove)

Options:
  --region <region>    - AWS region (default: us-east-1)
  --dry-run           - Show what would be done without making changes
  -h, --help          - Show this help message

Examples:
  $0 discover --region us-east-1
  $0 create sg-1234567890abcdef0 --region us-east-1
  $0 remove sg-1234567890abcdef0 --region us-east-1

Environment Variables:
  VPN_USE_CACHED_DISCOVERY  - Use cached discovery data (default: false)
  VPN_DISCOVERY_CACHE_TTL   - Cache TTL in seconds (default: 3600)
  VPN_DISCOVERY_FAST_MODE   - Use fast discovery mode (default: true)

Note: Run without --help to see current environment details.
EOF
        exit 0
    fi
done

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
VPN_DISCOVERY_MIN_CONFIDENCE="${VPN_DISCOVERY_MIN_CONFIDENCE:-MEDIUM}"

# Performance optimization: Fast mode uses only actual-rules + resource-verified (proven most effective)
# Set to "false" for comprehensive discovery (all 5 methods) if you need maximum coverage
VPN_DISCOVERY_FAST_MODE="${VPN_DISCOVERY_FAST_MODE:-true}"

# Discovery caching configuration
VPN_USE_CACHED_DISCOVERY="${VPN_USE_CACHED_DISCOVERY:-false}"
VPN_DISCOVERY_CACHE_TTL="${VPN_DISCOVERY_CACHE_TTL:-3600}"  # 1 hour default cache

# Persistent discovery data storage
DISCOVERY_DATA_DIR="/tmp/vpn-discovery-cache"
DISCOVERY_PERSISTENT_FILE="$DISCOVERY_DATA_DIR/last_discovery_results.txt"
DISCOVERY_METADATA_FILE="$DISCOVERY_DATA_DIR/discovery_metadata.conf"

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

# Persistent discovery data management functions

# Check if cached discovery data is valid and recent
is_cached_discovery_valid() {
    local vpc_id="$1"
    local current_time=$(date +%s)
    
    # Create cache directory if it doesn't exist
    mkdir -p "$DISCOVERY_DATA_DIR"
    
    # Check if files exist
    if [[ ! -f "$DISCOVERY_PERSISTENT_FILE" ]] || [[ ! -f "$DISCOVERY_METADATA_FILE" ]]; then
        log_info "No cached discovery data found"
        return 1
    fi
    
    # Check if metadata file has required information
    local cached_vpc_id cached_timestamp cached_environment
    cached_vpc_id=$(grep "^VPC_ID=" "$DISCOVERY_METADATA_FILE" 2>/dev/null | cut -d'=' -f2 | tr -d '"')
    cached_timestamp=$(grep "^DISCOVERY_TIMESTAMP=" "$DISCOVERY_METADATA_FILE" 2>/dev/null | cut -d'=' -f2 | tr -d '"')
    cached_environment=$(grep "^ENVIRONMENT=" "$DISCOVERY_METADATA_FILE" 2>/dev/null | cut -d'=' -f2 | tr -d '"')
    
    # Validate VPC ID matches
    if [[ "$cached_vpc_id" != "$vpc_id" ]]; then
        log_info "Cached discovery is for different VPC ($cached_vpc_id vs $vpc_id)"
        return 1
    fi
    
    # Validate environment matches
    if [[ "$cached_environment" != "$CURRENT_ENVIRONMENT" ]]; then
        log_info "Cached discovery is for different environment ($cached_environment vs $CURRENT_ENVIRONMENT)"
        return 1
    fi
    
    # Check if cache is still valid (within TTL)
    if [[ -n "$cached_timestamp" ]]; then
        local cache_age=$((current_time - cached_timestamp))
        if [[ $cache_age -le $VPN_DISCOVERY_CACHE_TTL ]]; then
            local cache_age_minutes=$((cache_age / 60))
            log_info "Found valid cached discovery data (${cache_age_minutes} minutes old)"
            return 0
        else
            local cache_age_hours=$((cache_age / 3600))
            log_info "Cached discovery data is too old (${cache_age_hours} hours old, TTL: $((VPN_DISCOVERY_CACHE_TTL / 3600)) hours)"
            return 1
        fi
    else
        log_info "Cached discovery data has no timestamp"
        return 1
    fi
}

# Load cached discovery data
load_cached_discovery() {
    local vpc_id="$1"
    
    if ! is_cached_discovery_valid "$vpc_id"; then
        return 1
    fi
    
    log_info "📦 Loading cached discovery data..."
    
    # Copy cached data to working files
    cp "$DISCOVERY_PERSISTENT_FILE" /tmp/final_discoveries.txt
    
    # Verify the cached data is not empty
    if [[ ! -s /tmp/final_discoveries.txt ]]; then
        log_warning "Cached discovery data is empty"
        return 1
    fi
    
    local cached_count
    cached_count=$(wc -l < /tmp/final_discoveries.txt)
    log_info "✅ Loaded $cached_count cached services"
    
    return 0
}

# Save discovery data to persistent cache
save_discovery_cache() {
    local vpc_id="$1"
    local current_time=$(date +%s)
    
    # Create cache directory if it doesn't exist
    mkdir -p "$DISCOVERY_DATA_DIR"
    
    # Save discovery results
    if [[ -f /tmp/final_discoveries.txt ]] && [[ -s /tmp/final_discoveries.txt ]]; then
        cp /tmp/final_discoveries.txt "$DISCOVERY_PERSISTENT_FILE"
        
        # Create metadata file
        cat > "$DISCOVERY_METADATA_FILE" << EOF
# VPN Discovery Cache Metadata
# Created: $(date)

VPC_ID="$vpc_id"
ENVIRONMENT="$CURRENT_ENVIRONMENT"
AWS_REGION="$AWS_REGION"
DISCOVERY_TIMESTAMP="$current_time"
DISCOVERY_TTL="$VPN_DISCOVERY_CACHE_TTL"
DISCOVERY_METHODS="$VPN_DISCOVERY_METHOD"
DISCOVERY_MIN_CONFIDENCE="$VPN_DISCOVERY_MIN_CONFIDENCE"
DISCOVERY_FAST_MODE="$VPN_DISCOVERY_FAST_MODE"

# Statistics
TOTAL_SERVICES="$(wc -l < /tmp/final_discoveries.txt)"
HIGH_CONFIDENCE_SERVICES="$(grep -c ":HIGH$" /tmp/final_discoveries.txt 2>/dev/null || echo "0")"
MEDIUM_CONFIDENCE_SERVICES="$(grep -c ":MEDIUM$" /tmp/final_discoveries.txt 2>/dev/null || echo "0")"
EOF
        
        local cached_count
        cached_count=$(wc -l < "$DISCOVERY_PERSISTENT_FILE")
        log_info "💾 Saved $cached_count services to persistent cache"
        
        return 0
    else
        log_warning "No discovery data to cache"
        return 1
    fi
}

# Clear expired cache data
cleanup_discovery_cache() {
    if [[ -d "$DISCOVERY_DATA_DIR" ]]; then
        log_info "🧹 Cleaning up discovery cache..."
        rm -f "$DISCOVERY_PERSISTENT_FILE" "$DISCOVERY_METADATA_FILE"
        # Try to remove directory if empty
        rmdir "$DISCOVERY_DATA_DIR" 2>/dev/null || true
        log_info "✅ Discovery cache cleaned up"
    fi
}

# Usage information
show_usage() {
    cat << EOF
VPN Service Access Manager - Environment-Aware

Usage: $0 <action> [vpn-sg-id] [options]

Actions:
  discover              - Discover available AWS services in the VPC
  display-services      - Display previously discovered services  
  create                - Create VPN access rules to discovered services
  remove                - Remove VPN access rules from services
  clean                 - Clean up tracking files and discovery cache
  report                - Generate human-readable VPN tracking report

Arguments:
  vpn-sg-id            - Security Group ID of the VPN client (required for create/remove)

Options:
  --region <region>    - AWS region (default: $AWS_REGION)
  --dry-run           - Show what would be done without making changes
  -h, --help          - Show this help message

Examples:
  $0 discover --region us-east-1
  $0 create sg-1234567890abcdef0 --region us-east-1
  $0 remove sg-1234567890abcdef0 --region us-east-1

Environment Variables:
  VPN_USE_CACHED_DISCOVERY  - Use cached discovery data (default: false)
  VPN_DISCOVERY_CACHE_TTL   - Cache TTL in seconds (default: 3600)
  VPN_DISCOVERY_FAST_MODE   - Use fast discovery mode (default: true)

Environment:
  Current environment: $CURRENT_ENVIRONMENT
  AWS Region: $AWS_REGION
  Cache enabled: $VPN_USE_CACHED_DISCOVERY
EOF
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
    log_info "🔍 Enhanced Resource-to-SecurityGroup Mapping for VPC: $vpc_id"
    
    > /tmp/resource_verified_discoveries.txt
    > /tmp/resource_sg_mapping.json
    
    # RDS Instance Security Groups (Enhanced with detailed analysis)
    log_info "  Analyzing RDS instances and their actual security groups..."
    local rds_instances
    rds_instances=$(aws_with_profile rds describe-db-instances \
        --region "$AWS_REGION" \
        --query "DBInstances[?DBSubnetGroup.VpcId=='$vpc_id'].[DBInstanceIdentifier,Endpoint.Address,Endpoint.Port,VpcSecurityGroups[0].VpcSecurityGroupId,Engine]" \
        --output json 2>/dev/null || echo "[]")
    
    if [[ $(echo "$rds_instances" | jq '. | length') -gt 0 ]]; then
        echo "$rds_instances" | jq -c '.[] | {
            service: "RDS",
            resource_id: .[0],
            endpoint: .[1],
            port: .[2],
            security_group: .[3],
            engine: .[4]
        }' >> /tmp/resource_sg_mapping.json
        
        # Extract unique security groups used by RDS
        local rds_sgs
        rds_sgs=$(echo "$rds_instances" | jq -r '.[].VpcSecurityGroups[].VpcSecurityGroupId' 2>/dev/null | sort -u)
        
        for sg_id in $rds_sgs; do
            if [[ -n "$sg_id" && "$sg_id" != "None" && "$sg_id" != "null" ]]; then
                echo "MySQL_RDS:3306:$sg_id:resource-verified" >> /tmp/resource_verified_discoveries.txt
                log_info "  ✓ Found RDS security group: $sg_id"
            fi
        done
    fi
    
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
    
    
    # ElastiCache Security Groups (Enhanced analysis)
    log_info "  Analyzing ElastiCache clusters and their actual security groups..."
    local cache_clusters
    cache_clusters=$(aws_with_profile elasticache describe-cache-clusters \
        --region "$AWS_REGION" --show-cache-node-info \
        --query 'CacheClusters[?CacheSubnetGroupName!=null].[CacheClusterId,RedisConfiguration.PrimaryEndpoint.Address // CacheNodes[0].Endpoint.Address,RedisConfiguration.PrimaryEndpoint.Port // CacheNodes[0].Endpoint.Port,SecurityGroups[0].SecurityGroupId,Engine]' \
        --output json 2>/dev/null || echo "[]")
    
    if [[ $(echo "$cache_clusters" | jq '. | length') -gt 0 ]]; then
        echo "$cache_clusters" | jq -c '.[] | {
            service: "ElastiCache",
            resource_id: .[0],
            endpoint: .[1],
            port: .[2],
            security_group: .[3],
            engine: .[4]
        }' >> /tmp/resource_sg_mapping.json
        
        # Extract unique security groups and verify VPC
        local cache_sgs
        cache_sgs=$(echo "$cache_clusters" | jq -r '.[3]' | sort -u)
        
        for sg_id in $cache_sgs; do
            if [[ -n "$sg_id" && "$sg_id" != "None" && "$sg_id" != "null" ]]; then
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
    fi
    
    # EMR (HBase) Security Groups (Enhanced with detailed mapping)
    log_info "  Analyzing EMR clusters and their actual security groups..."
    local emr_clusters
    emr_clusters=$(aws_with_profile emr list-clusters --active \
        --region "$AWS_REGION" \
        --query 'Clusters[].[Id,Name]' --output json 2>/dev/null || echo "[]")
    
    if [[ $(echo "$emr_clusters" | jq '. | length') -gt 0 ]]; then
        echo "$emr_clusters" | jq -c '.[] | {service: "EMR", cluster_id: .[0], cluster_name: .[1]}' >> /tmp/resource_sg_mapping.json
        
        while IFS=$'\t' read -r cluster_id cluster_name; do
            if [[ -n "$cluster_id" && "$cluster_id" != "None" && "$cluster_id" != "null" ]]; then
                log_info "    Analyzing cluster: $cluster_id ($cluster_name)"
                
                local cluster_detail
                cluster_detail=$(aws_with_profile emr describe-cluster --cluster-id "$cluster_id" \
                    --region "$AWS_REGION" \
                    --query 'Cluster.[Id,Name,MasterPublicDnsName,Ec2InstanceAttributes.EmrManagedMasterSecurityGroup,Ec2InstanceAttributes.EmrManagedSlaveSecurityGroup]' \
                    --output json 2>/dev/null || echo "[]")
                
                if [[ $(echo "$cluster_detail" | jq '. | length') -gt 0 ]]; then
                    # Check VPC context by examining subnets
                    local subnet_ids
                    subnet_ids=$(aws_with_profile emr describe-cluster --cluster-id "$cluster_id" \
                        --region "$AWS_REGION" \
                        --query 'Cluster.Ec2InstanceAttributes.Ec2SubnetIds[0]' \
                        --output text 2>/dev/null)
                    
                    if [[ -n "$subnet_ids" && "$subnet_ids" != "None" ]]; then
                        local cluster_vpc
                        cluster_vpc=$(aws_with_profile ec2 describe-subnets \
                            --subnet-ids "$subnet_ids" --region "$AWS_REGION" \
                            --query 'Subnets[0].VpcId' --output text 2>/dev/null)
                        
                        if [[ "$cluster_vpc" == "$vpc_id" ]]; then
                            local master_sg slave_sg
                            master_sg=$(echo "$cluster_detail" | jq -r '.[3]')
                            slave_sg=$(echo "$cluster_detail" | jq -r '.[4]')
                            
                            # Add both master and slave security groups
                            if [[ -n "$master_sg" && "$master_sg" != "null" ]]; then
                                echo "HBase_Master:16010:$master_sg:resource-verified" >> /tmp/resource_verified_discoveries.txt
                                echo "HBase_Custom:8765:$master_sg:resource-verified" >> /tmp/resource_verified_discoveries.txt
                                log_info "  ✓ Found EMR Master security group: $master_sg (cluster: $cluster_id)"
                            fi
                            
                            if [[ -n "$slave_sg" && "$slave_sg" != "null" ]]; then
                                echo "HBase_RegionServer:16020:$slave_sg:resource-verified" >> /tmp/resource_verified_discoveries.txt
                                log_info "  ✓ Found EMR Slave security group: $slave_sg (cluster: $cluster_id)"
                            fi
                        fi
                    fi
                fi
            fi
        done < <(echo "$emr_clusters" | jq -r '.[] | "\(.[0])\t\(.[1])"')
    fi
    
    log_info "  ✅ Enhanced resource analysis completed"
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
        
        # Enhanced scoring by method (including new methods)
        case "$method" in
            "tag-based")
                score=100
                confidence="HIGH"
                ;;
            "resource-verified"|"resource-verified-resource-validated")
                score=95
                confidence="HIGH"
                ;;
            "actual-rules"|"actual-rules-resource-validated")
                score=90
                confidence="HIGH"
                ;;
            "pattern-based"|"pattern-based-resource-validated")
                score=75
                confidence="MEDIUM"
                ;;
            "port-only"|"port-only-resource-validated")
                score=40
                confidence="LOW"
                ;;
            *"resource-validated"*)
                # Boost score for resource-validated methods
                score=85
                confidence="HIGH"
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

# New: Real Rule Validation Method (Inspired by discover-sg-references.sh)
discover_services_by_actual_rules() {
    local vpc_id="$1"
    log_info "🔍 Actual Security Group Rules Analysis for VPC: $vpc_id"
    
    > /tmp/actual_rules_discoveries.txt
    > /tmp/port_rule_analysis.json
    
    # Get all security groups in the VPC
    local all_sgs
    all_sgs=$(aws_with_profile ec2 describe-security-groups \
        --filters "Name=vpc-id,Values=$vpc_id" \
        --query 'SecurityGroups[].GroupId' \
        --region "$AWS_REGION" --output text)
    
    log_info "  Analyzing actual security group rules for service ports..."
    
    # Define service ports we're interested in
    local service_port_mapping=(
        "3306:MySQL_RDS"
        "6379:Redis"
        "8765:HBase_Custom"
        "16010:HBase_Master"
        "16020:HBase_RegionServer"
        "443:EKS_API"
        "8000:Phoenix_Query"
        "8080:Phoenix_Web"
    )
    
    # For each service port, find security groups that actually have rules for it
    for port_service in "${service_port_mapping[@]}"; do
        IFS=':' read -r port service_name <<< "$port_service"
        
        log_info "    Analyzing rules for port $port ($service_name)..."
        
        # Find all security groups that have inbound rules for this port
        for sg_id in $all_sgs; do
            local port_rules
            port_rules=$(aws_with_profile ec2 describe-security-groups \
                --group-ids "$sg_id" --region "$AWS_REGION" \
                --query "SecurityGroups[0].IpPermissions[?FromPort<=\`$port\` && ToPort>=\`$port\`]" \
                --output json 2>/dev/null || echo "[]")
            
            if [[ $(echo "$port_rules" | jq '. | length') -gt 0 ]]; then
                # This SG has rules for this port - analyze the rules
                local rule_analysis
                rule_analysis=$(echo "$port_rules" | jq -c --arg sg_id "$sg_id" --arg port "$port" --arg service "$service_name" '
                    map({
                        sg_id: $sg_id,
                        service: $service,
                        port: ($port | tonumber),
                        protocol: .IpProtocol,
                        cidr_blocks: [.IpRanges[]?.CidrIp // empty],
                        referenced_sgs: [.UserIdGroupPairs[]?.GroupId // empty],
                        descriptions: [.IpRanges[]?.Description // empty, .UserIdGroupPairs[]?.Description // empty],
                        has_any_access: ((.IpRanges | length > 0) or (.UserIdGroupPairs | length > 0))
                    })')
                
                echo "$rule_analysis" | jq -c '.[]' >> /tmp/port_rule_analysis.json
                
                # If this SG has actual access rules (not just placeholder), consider it a candidate
                local has_access_rules
                has_access_rules=$(echo "$rule_analysis" | jq -r '.[0].has_any_access')
                
                if [[ "$has_access_rules" == "true" ]]; then
                    echo "$service_name:$port:$sg_id:actual-rules" >> /tmp/actual_rules_discoveries.txt
                    log_info "      ✓ Found $sg_id with actual rules for port $port"
                fi
            fi
        done
    done
    
    log_info "  ✅ Actual rules analysis completed"
}

# Enhanced: Cross-validation with resource mapping
cross_validate_discoveries_with_resources() {
    log_info "🔄 Cross-validating discoveries with actual resource usage..."
    
    > /tmp/validated_discoveries.txt
    
    # If we have resource mapping, use it to validate discoveries
    if [[ -f /tmp/resource_sg_mapping.json ]]; then
        log_info "  Using resource mapping for validation..."
        
        # For each discovered service, check if it matches actual resource usage
        while IFS=':' read -r service port sg_id method; do
            # Check if this SG is actually used by resources for this service type
            local resource_match=false
            
            case "$service" in
                "MySQL_RDS")
                    resource_match=$(jq -r --arg sg "$sg_id" '
                        select(.service == "RDS" and (.security_group == $sg or (.security_groups[]? == $sg))) | "true"
                    ' /tmp/resource_sg_mapping.json | head -1)
                    ;;
                "Redis")
                    resource_match=$(jq -r --arg sg "$sg_id" '
                        select(.service == "ElastiCache" and (.security_group == $sg or (.security_groups[]? == $sg))) | "true"
                    ' /tmp/resource_sg_mapping.json | head -1)
                    ;;
                "HBase_Master"|"HBase_RegionServer"|"HBase_Custom")
                    resource_match=$(jq -r --arg sg "$sg_id" '
                        select(.service == "EMR") | "true"
                    ' /tmp/resource_sg_mapping.json | head -1)
                    ;;
                "EKS_API")
                    resource_match=$(jq -r --arg sg "$sg_id" '
                        select(.service == "EKS" and (.security_groups[]? == $sg)) | "true"
                    ' /tmp/resource_sg_mapping.json | head -1)
                    ;;
            esac
            
            # Enhanced scoring based on resource validation
            local validation_method="$method"
            if [[ "$resource_match" == "true" ]]; then
                validation_method="${method}-resource-validated"
                log_info "    ✅ $service:$port:$sg_id validated by actual resource usage"
            else
                log_warning "    ⚠️  $service:$port:$sg_id not confirmed by resource usage"
            fi
            
            echo "$service:$port:$sg_id:$validation_method" >> /tmp/validated_discoveries.txt
            
        done < /tmp/combined_discoveries.txt
    else
        # Fallback to original discoveries if no resource mapping
        cp /tmp/combined_discoveries.txt /tmp/validated_discoveries.txt
    fi
    
    log_info "  ✅ Cross-validation completed"
}

# Multi-tier discovery orchestrator
perform_multi_tier_discovery() {
    local vpc_id="$1"
    
    # Check for fast mode environment variable (default: true for performance)
    local fast_mode="${VPN_DISCOVERY_FAST_MODE:-true}"
    
    if [[ "$fast_mode" == "true" ]]; then
        log_info "🚀 Fast Discovery Mode for VPC: $vpc_id (actual-rules + resource-verified)"
        perform_fast_discovery "$vpc_id"
    else
        log_info "🔍 Comprehensive Discovery Mode for VPC: $vpc_id (all 5 methods)"
        perform_comprehensive_discovery "$vpc_id"
    fi
}

# Fast discovery mode - proven effective with actual-rules + resource verification
perform_fast_discovery() {
    local vpc_id="$1"
    
    # Clear any existing discovery files
    rm -f /tmp/*_discoveries.txt /tmp/scored_discoveries.txt /tmp/final_discoveries.txt /tmp/resource_sg_mapping.json /tmp/port_rule_analysis.json
    
    # Fast discovery methods (proven most effective)
    local fast_methods=("actual-rules" "resource-verified")
    local total_methods=${#fast_methods[@]}
    local current_method=0
    
    log_info "📈 Using fast discovery (2 methods) - typically 3-5x faster"
    
    # Execute core discovery methods
    for method in "${fast_methods[@]}"; do
        ((current_method++))
        
        case "$method" in
            "actual-rules")
                discover_services_by_actual_rules "$vpc_id"
                ;;
            "resource-verified")
                discover_services_by_resource_verification "$vpc_id"
                ;;
        esac
        
    done
    
    # Process discoveries
    process_discovery_results "actual-rules,resource-verified"
}

# Comprehensive discovery mode - all 5 methods for maximum coverage
perform_comprehensive_discovery() {
    local vpc_id="$1"
    
    # Clear any existing discovery files
    rm -f /tmp/*_discoveries.txt /tmp/scored_discoveries.txt /tmp/final_discoveries.txt /tmp/resource_sg_mapping.json /tmp/port_rule_analysis.json
    
    # All discovery methods
    local comprehensive_methods=("tag-based" "resource-verified" "actual-rules" "pattern-based" "port-based")
    local total_methods=${#comprehensive_methods[@]}
    local current_method=0
    
    log_info "🔍 Using comprehensive discovery (5 methods) - maximum coverage"
    
    # Execute all discovery methods in priority order
    for method in "${comprehensive_methods[@]}"; do
        ((current_method++))
        
        case "$method" in
            "tag-based")
                discover_services_by_tags "$vpc_id"
                ;;
            "resource-verified")
                discover_services_by_resource_verification "$vpc_id"
                ;;
            "actual-rules")
                discover_services_by_actual_rules "$vpc_id"
                ;;
            "pattern-based")
                discover_services_by_enhanced_patterns "$vpc_id"
                ;;
            "port-based")
                log_info "⚠️ Port-based discovery used as fallback"
                ;;
        esac
        
    done
    
    # Process discoveries
    process_discovery_results "tag-based,resource-verified,actual-rules,pattern-based,port-based"
}

# Common discovery result processing
process_discovery_results() {
    local methods_used="$1"
    
    # Combine all discoveries and remove duplicates (keeping highest priority)
    > /tmp/combined_discoveries.txt
    
    # Process in priority order (higher priority methods override lower ones)
    for method in "port-based" "pattern-based" "actual-rules" "resource-verified" "tag-based"; do
        local method_file="/tmp/${method//-/_}_discoveries.txt"
        if [[ -f "$method_file" ]]; then
            cat "$method_file" >> /tmp/combined_discoveries.txt
        fi
    done
    
    # Remove duplicates (keep last occurrence which has highest priority)
    awk -F: '!seen[$1]++' /tmp/combined_discoveries.txt > /tmp/unique_discoveries.txt
    
    # Cross-validate with actual resource usage
    cross_validate_discoveries_with_resources
    
    # Validate and score all discoveries (use validated discoveries if available)
    local discovery_input="/tmp/validated_discoveries.txt"
    if [[ ! -f "$discovery_input" ]]; then
        discovery_input="/tmp/unique_discoveries.txt"
    fi
    validate_and_score_discoveries "$discovery_input" /tmp/scored_discoveries.txt
    
    # Filter by minimum confidence level
    echo -e "📊 Filtering by confidence level: $VPN_DISCOVERY_MIN_CONFIDENCE..." > /dev/tty 2>/dev/null || true
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
    
    log_info "✅ Discovery completed using methods: $methods_used"
    
    # Display summary
    local total_discoveries
    total_discoveries=$(wc -l < /tmp/final_discoveries.txt 2>/dev/null | xargs || echo "0")
    log_info "✅ Discovery completed: $total_discoveries services found"
    
    return 0
}

# Interactive confirmation and manual override system
auto_confirm_discovered_services() {
    local discoveries_file="$1"
    local confirmed_services=()
    
    log_info "Auto-confirming all discovered services"
    
    # Copy all discoveries to confirmed services
    if [[ -f "$discoveries_file" && -s "$discoveries_file" ]]; then
        while IFS=':' read -r service port sg_id method score confidence; do
            confirmed_services+=("$service:$port:$sg_id")
            log_info "Auto-confirmed: $service -> $sg_id (port $port, $confidence confidence)"
        done < "$discoveries_file"
    else
        log_warning "No discoveries found in file: $discoveries_file"
    fi
    
    # Save confirmed services for processing
    if [[ ${#confirmed_services[@]} -gt 0 ]]; then
        printf '%s\n' "${confirmed_services[@]}" > /tmp/confirmed_services.txt
        log_info "Auto-confirmed services: ${#confirmed_services[@]}"
    else
        log_warning "No services to auto-confirm"
        echo "" > /tmp/confirmed_services.txt
    fi
    return 0
}

# Display discovered services and ask user for confirmation
display_services_and_ask_confirmation() {
    local services_file="$1"
    
    if [[ ! -f "$services_file" || ! -s "$services_file" ]]; then
        echo -e "${YELLOW}⚠️ No services were discovered.${NC}"
        return 1
    fi
    
    local service_count=$(wc -l < "$services_file" | xargs)
    echo
    echo -e "${CYAN}=== 🔍 Discovered VPN Services ===${NC}"
    echo -e "${GREEN}Found $service_count services that can be configured for VPN access:${NC}"
    echo
    
    printf "%-20s %-8s %-20s %-12s\n" "Service" "Port" "Security Group" "Confidence"
    echo "────────────────────────────────────────────────────────────"
    
    while IFS=':' read -r service port sg_id rest; do
        # Extract confidence from rest if it's in the 6-field format
        local confidence=""
        if [[ "$rest" =~ :.*:.*:(.*) ]]; then
            confidence=$(echo "$rest" | cut -d':' -f3)
        else
            confidence="AUTO"
        fi
        
        # Color code by confidence level
        local color="${YELLOW}"
        case "$confidence" in
            "HIGH") color="${GREEN}" ;;
            "MEDIUM") color="${YELLOW}" ;;
            "LOW") color="${BLUE}" ;;
            *) color="${NC}" ;;
        esac
        
        printf "${color}%-20s %-8s %-20s %-12s${NC}\n" "$service" "$port" "${sg_id:0:18}..." "$confidence"
    done < "$services_file"
    
    echo
    echo -e "${BLUE}These services will be configured to allow VPN access through security group rules.${NC}"
    echo
    
    return 0
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
    local total_discovered=$(wc -l < "$discovery_file" 2>/dev/null | xargs || echo "0")
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

# Track security group modifications for cleanup purposes
track_security_group_modification() {
    local vpn_sg="$1"
    local target_sg="$2"
    local service="$3"
    local port="$4"
    local action="$5"  # "ADD" or "REMOVE"
    local rule_id="$6"  # Optional: security group rule ID
    
    local tracking_file="$SCRIPT_DIR/../configs/${CURRENT_ENVIRONMENT}/vpn_security_groups_tracking.conf"
    
    # Ensure directory exists
    local tracking_dir=$(dirname "$tracking_file")
    if [[ ! -d "$tracking_dir" ]]; then
        log_info "Creating tracking directory: $tracking_dir"
        echo -e "Creating tracking directory: $tracking_dir" > /dev/tty 2>/dev/null || true
        mkdir -p "$tracking_dir"
    fi
    
    # Create tracking file if it doesn't exist
    if [[ ! -f "$tracking_file" ]]; then
        log_info "Creating tracking file: $tracking_file"
        echo -e "Creating tracking file: $tracking_file" > /dev/tty 2>/dev/null || true
        create_tracking_file "$tracking_file" "$vpn_sg"
    fi
    
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local log_entry="${timestamp}|${vpn_sg}|${target_sg}|${service}|${port}|${action}|${rule_id:-}"
    
    # Update configuration log
    local current_log
    current_log=$(grep "^VPN_CONFIGURATION_LOG=" "$tracking_file" | cut -d'=' -f2- | tr -d '"' || echo "")
    
    local new_log
    if [[ -n "$current_log" ]]; then
        new_log="${current_log};${log_entry}"
    else
        new_log="$log_entry"
    fi
    
    # Update tracking file - use printf to avoid sed escaping issues
    grep -v "^VPN_CONFIGURATION_LOG=" "$tracking_file" > "${tracking_file}.tmp"
    echo "VPN_CONFIGURATION_LOG=\"$new_log\"" >> "${tracking_file}.tmp"
    mv "${tracking_file}.tmp" "$tracking_file"
    
    # If adding, update the modified security groups list
    if [[ "$action" == "ADD" ]]; then
        local current_groups
        current_groups=$(grep "^VPN_MODIFIED_SECURITY_GROUPS=" "$tracking_file" | cut -d'=' -f2- | tr -d '"' || echo "")
        
        local group_entry="${target_sg}:${service}:${port}"
        
        # Check if already exists
        if [[ ! "$current_groups" =~ $target_sg ]]; then
            local new_groups
            if [[ -n "$current_groups" ]]; then
                new_groups="${current_groups};${group_entry}"
            else
                new_groups="$group_entry"
            fi
            
            # Update security groups list
            grep -v "^VPN_MODIFIED_SECURITY_GROUPS=" "$tracking_file" > "${tracking_file}.tmp2"
            echo "VPN_MODIFIED_SECURITY_GROUPS=\"$new_groups\"" >> "${tracking_file}.tmp2"
            mv "${tracking_file}.tmp2" "$tracking_file"
            
            # Update count
            local count=$(echo "$new_groups" | tr ';' '\n' | wc -l | xargs)
            grep -v "^VPN_MODIFIED_SECURITY_GROUPS_COUNT=" "$tracking_file" > "${tracking_file}.tmp3"
            echo "VPN_MODIFIED_SECURITY_GROUPS_COUNT=\"$count\"" >> "${tracking_file}.tmp3"
            mv "${tracking_file}.tmp3" "$tracking_file"
        fi
    fi
    
    # Update last configuration time
    grep -v "^VPN_LAST_CONFIGURATION_TIME=" "$tracking_file" > "${tracking_file}.tmp4"
    echo "VPN_LAST_CONFIGURATION_TIME=\"$timestamp\"" >> "${tracking_file}.tmp4"
    mv "${tracking_file}.tmp4" "$tracking_file"
    
    log_info "📝 Tracked modification: $action $target_sg:$port for $service"
    echo -e "📝 Tracked modification: $action $target_sg:$port for $service" > /dev/tty 2>/dev/null || true
}

# Create tracking file with initial structure
create_tracking_file() {
    local tracking_file="$1"
    local vpn_sg="$2"
    
    cat > "$tracking_file" << EOF
# VPN Security Group Configuration Tracking
# This file tracks which security groups have been modified for VPN access
# Used for cleanup when removing VPN endpoint
# Updated: $(date '+%Y-%m-%d %H:%M:%S')

# VPN Security Group ID that was used for configuration
VPN_SECURITY_GROUP_ID="$vpn_sg"

# Last configuration timestamp
VPN_LAST_CONFIGURATION_TIME="$(date '+%Y-%m-%d %H:%M:%S %Z')"

# Configuration method used
VPN_CONFIGURATION_METHOD="actual-rules,resource-verified"

# Total number of security groups modified
VPN_MODIFIED_SECURITY_GROUPS_COUNT="0"

# List of modified security groups (TARGET_SG_ID:SERVICE_NAME:PORT format)
VPN_MODIFIED_SECURITY_GROUPS=""

# Detailed configuration log (for audit and cleanup)
# Format: timestamp|vpn_sg|target_sg|service|port|action|rule_id
VPN_CONFIGURATION_LOG=""
EOF
    
    log_info "📁 Created tracking file: $tracking_file"
}

# Get list of security groups modified for VPN access
get_modified_security_groups() {
    local tracking_file="$SCRIPT_DIR/../configs/${CURRENT_ENVIRONMENT}/vpn_security_groups_tracking.conf"
    
    if [[ ! -f "$tracking_file" ]]; then
        log_warning "No tracking file found: $tracking_file"
        return 1
    fi
    
    local modified_groups
    modified_groups=$(grep "^VPN_MODIFIED_SECURITY_GROUPS=" "$tracking_file" | cut -d'=' -f2- | tr -d '"')
    
    if [[ -n "$modified_groups" ]]; then
        echo "$modified_groups" | tr ';' '\n'
    fi
}

# Get VPN security group ID from tracking file
get_vpn_security_group_from_tracking() {
    local tracking_file="$SCRIPT_DIR/../configs/${CURRENT_ENVIRONMENT}/vpn_security_groups_tracking.conf"
    
    if [[ ! -f "$tracking_file" ]]; then
        log_warning "No tracking file found: $tracking_file"
        return 1
    fi
    
    grep "^VPN_SECURITY_GROUP_ID=" "$tracking_file" | cut -d'=' -f2- | tr -d '"'
}

# Create VPN access rules
create_rules() {
    local vpn_sg="$1"
    
    # Check multiple possible service files for backward compatibility
    local services_file="/tmp/discovered_services.txt"
    
    if [[ ! -s "$services_file" ]]; then
        # Try confirmed services first
        if [[ -s /tmp/confirmed_services.txt ]]; then
            services_file="/tmp/confirmed_services.txt"
            log_info "Using confirmed services file: $services_file"
        # Fallback to final discoveries
        elif [[ -s /tmp/final_discoveries.txt ]]; then
            # Convert final discoveries to expected format
            > /tmp/discovered_services.txt
            while IFS=':' read -r service port sg_id method score confidence; do
                echo "$service:$port:$sg_id" >> /tmp/discovered_services.txt
            done < /tmp/final_discoveries.txt
            services_file="/tmp/discovered_services.txt"
            log_info "Converted final discoveries to services file: $services_file"
        else
            log_error "No services discovered. Available files:"
            ls -la /tmp/*services* /tmp/*discoveries* 2>/dev/null || echo "  No discovery files found"
            exit 1
        fi
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
            echo -e "[DRY-RUN] Would create: $service (port $port) in $target_sg" > /dev/tty 2>/dev/null || true
            continue
        fi
        
        log_info "Creating: $service (port $port) in $target_sg"
        echo -e "Creating: $service (port $port) in $target_sg" > /dev/tty 2>/dev/null || true
        
        if aws_with_profile ec2 authorize-security-group-ingress \
            --group-id "$target_sg" \
            --protocol tcp \
            --port "$port" \
            --source-group "$vpn_sg" \
            --region "$AWS_REGION" 2>/dev/null; then
            echo "  ✅ Success"
            echo -e "  ✅ Success" > /dev/tty 2>/dev/null || true
            ((success++))
            # Track successfully configured rules with detailed information
            configured_rules+=("$service:$target_sg:$port")
            track_security_group_modification "$vpn_sg" "$target_sg" "$service" "$port" "ADD"
        else
            echo "  ⚠️  May already exist or failed"
            echo -e "  ⚠️  May already exist or failed" > /dev/tty 2>/dev/null || true
            # Still track for cleanup (might have been created before)
            configured_rules+=("$service:$target_sg:$port")
            track_security_group_modification "$vpn_sg" "$target_sg" "$service" "$port" "ADD" "existing_or_failed"
        fi
    done < "$services_file"
    
    echo
    log_info "Created $success/$total rules"
    echo -e "✅ Created $success/$total rules" > /dev/tty 2>/dev/null || true
    
    # Record configured security groups in .conf file if not dry run
    if [[ "$DRY_RUN" != "true" && ${#configured_rules[@]} -gt 0 ]]; then
        log_info "Recording configured security groups for cleanup tracking..."
        for rule in "${configured_rules[@]}"; do
            IFS=':' read -r service target_sg port <<< "$rule"
            if [[ -n "$service" && -n "$target_sg" && -n "$port" ]]; then
                # Load security group operations if available
                if [ -f "$SCRIPT_DIR/../lib/security_group_operations.sh" ]; then
                    source "$SCRIPT_DIR/../lib/security_group_operations.sh"
                    local config_file
                    config_file="$SCRIPT_DIR/../configs/${CURRENT_ENV}/vpn_endpoint.conf"
                    if [ -f "$config_file" ]; then
                        record_vpn_security_group_access "$config_file" "$service" "$target_sg" "$port" || \
                        log_warning "  ⚠️ Failed to record: $service -> $target_sg:$port"
                    fi
                fi
            else
                log_warning "  ⚠️ Failed to record: $rule -> invalid format"
            fi
        done
        log_info "✅ Security group tracking recorded for cleanup"
    fi
    
    # Track security group modifications
    for rule in "${configured_rules[@]}"; do
        IFS=':' read -r service target_sg port <<< "$rule"
        track_security_group_modification "$vpn_sg" "$target_sg" "$service" "$port" "ADD"
    done
}

# Enhanced VPN access rules removal using tracking file
remove_rules() {
    local vpn_sg="$1"
    
    # First try to get VPN SG from tracking file if not provided
    if [[ -z "$vpn_sg" ]]; then
        vpn_sg=$(get_vpn_security_group_from_tracking)
        if [[ -z "$vpn_sg" ]]; then
            log_error "No VPN security group provided and none found in tracking file"
            return 1
        fi
        log_info "Using VPN security group from tracking: $vpn_sg"
    fi
    
    log_info "🔍 ENHANCED SEARCH: Using tracking file + AWS discovery for VPN security group $vpn_sg..."
    echo
    
    # Method 1: Use tracking file for precise cleanup
    local tracking_file="$SCRIPT_DIR/../configs/${CURRENT_ENVIRONMENT}/vpn_security_groups_tracking.conf"
    local tracked_groups=()
    
    if [[ -f "$tracking_file" ]]; then
        log_info "📋 Found tracking file, reading configured security groups..."
        while IFS= read -r group_entry; do
            if [[ -n "$group_entry" ]]; then
                tracked_groups+=("$group_entry")
                local sg_id=$(echo "$group_entry" | cut -d':' -f1)
                local service=$(echo "$group_entry" | cut -d':' -f2)
                local port=$(echo "$group_entry" | cut -d':' -f3)
                echo "  📝 Tracked: $service on $sg_id:$port"
            fi
        done < <(get_modified_security_groups)
        
        if [[ ${#tracked_groups[@]} -gt 0 ]]; then
            log_info "Found ${#tracked_groups[@]} tracked security group modifications"
        else
            log_warning "No tracked modifications found in tracking file"
        fi
    else
        log_warning "No tracking file found: $tracking_file"
    fi
    
    # Method 2: AWS comprehensive search (fallback + verification)
    log_info "🔍 AWS comprehensive search for verification..."
    local all_vpn_rules
    all_vpn_rules=$(aws_with_profile ec2 describe-security-group-rules \
        --region "$AWS_REGION" \
        --query "SecurityGroupRules[?ReferencedGroupInfo.GroupId=='$vpn_sg' && !IsEgress].[GroupId,SecurityGroupRuleId,IpProtocol,FromPort,ToPort,ReferencedGroupInfo.GroupId]" \
        --output json 2>/dev/null || echo "[]")
    
    local aws_rule_count
    aws_rule_count=$(echo "$all_vpn_rules" | jq '. | length')
    
    log_info "AWS found $aws_rule_count total VPN access rules"
    
    # Display what will be removed
    if [[ $aws_rule_count -gt 0 ]]; then
        echo
        log_info "Rules to be removed:"
        echo "$all_vpn_rules" | jq -r '.[] | "  • Rule \(.[1]) in SG \(.[0]) - \(.[2]):\(.[3]) (references \(.[5]))"'
        echo
    elif [[ ${#tracked_groups[@]} -eq 0 ]]; then
        log_info "No VPN access rules found to remove"
        return 0
    fi
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would remove all $aws_rule_count AWS-discovered rules"
        if [[ ${#tracked_groups[@]} -gt 0 ]]; then
            log_info "[DRY-RUN] Would also clean up ${#tracked_groups[@]} tracked modifications"
        fi
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
            # Track removal in tracking file
            track_security_group_modification "$vpn_sg" "$target_sg" "unknown" "$port" "REMOVE" "$rule_id"
        else
            echo "  ❌ Failed"
        fi
    done < <(echo "$all_vpn_rules" | jq -c '.[]')
    
    echo
    log_info "Removed $success/$total AWS-discovered rules"
    
    # Clean up tracking file after successful removal
    if [[ $success -eq $total && $total -gt 0 ]]; then
        log_info "🧹 Cleaning up tracking file..."
        cleanup_tracking_file
        log_info "🎉 All VPN access rules successfully removed and tracking cleaned up!"
    elif [[ $total -eq 0 && -f "$tracking_file" ]]; then
        # No AWS rules found, but we have tracking file - clean it up anyway
        log_info "🧹 No AWS rules found, cleaning up tracking file..."
        cleanup_tracking_file
        log_info "✅ Tracking file cleaned up"
    else
        log_warning "⚠️  Some rules could not be removed. Tracking file preserved for manual cleanup."
    fi
}

# Clean up tracking file after successful VPN endpoint removal
cleanup_tracking_file() {
    local tracking_file="$SCRIPT_DIR/../configs/${CURRENT_ENVIRONMENT}/vpn_security_groups_tracking.conf"
    
    if [[ -f "$tracking_file" ]]; then
        # Reset tracking file to clean state
        local temp_file="${tracking_file}.cleanup_tmp"
        
        # Keep header and essential fields, reset the tracking data
        grep -E "^#|^VPN_SECURITY_GROUP_ID=|^VPN_CONFIGURATION_METHOD=" "$tracking_file" > "$temp_file"
        echo "VPN_MODIFIED_SECURITY_GROUPS_COUNT=\"0\"" >> "$temp_file"
        echo "VPN_MODIFIED_SECURITY_GROUPS=\"\"" >> "$temp_file"
        echo "VPN_CONFIGURATION_LOG=\"\"" >> "$temp_file"
        echo "VPN_LAST_CONFIGURATION_TIME=\"$(date '+%Y-%m-%d %H:%M:%S %Z') - CLEANED\"" >> "$temp_file"
        
        mv "$temp_file" "$tracking_file"
        log_info "📝 Tracking file reset to clean state"
    else
        log_info "No tracking file found to clean up"
    fi
}

# Main execution
main() {
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                show_usage
                exit 0
                ;;
            --region)
                if [[ -n "$2" ]]; then
                    AWS_REGION="$2"
                    shift 2
                else
                    log_error "Error: --region requires a value"
                    exit 1
                fi
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            discover|display-services|create|remove|clean|report)
                if [[ -z "$ACTION" ]]; then
                    ACTION="$1"
                    shift
                else
                    log_error "Multiple actions specified. Only one action is allowed."
                    exit 1
                fi
                ;;
            sg-*)
                if [[ -z "$VPN_SG" ]]; then
                    VPN_SG="$1"
                    shift
                else
                    log_error "Multiple security group IDs specified. Only one is allowed."
                    exit 1
                fi
                ;;
            *)
                # If it's not a known option, it might be the VPN_SG or an unknown option
                if [[ -z "$VPN_SG" && "$1" =~ ^[a-zA-Z0-9-]+$ ]]; then
                    VPN_SG="$1"
                    shift
                else
                    log_error "Unknown option or invalid security group ID: $1"
                    show_usage
                    exit 1
                fi
                ;;
        esac
    done
    
    log_info "🔧 VPN Service Access Manager - Environment-Aware"
    
    # Validate required parameters
    if [[ -z "$ACTION" ]]; then
        log_error "Error: Action is required"
        show_usage
        exit 1
    fi
    
    # Validate VPN_SG for actions that require it
    case "$ACTION" in
        "create"|"remove")
            if [[ -z "$VPN_SG" ]]; then
                log_error "Error: VPN Security Group ID is required for action '$ACTION'"
                show_usage
                exit 1
            fi
            ;;
        "report")
            # For report action, VPN_SG might contain report arguments, clear it
            VPN_SG=""
            ;;
    esac
    
    log_info "Action: $ACTION | Region: $AWS_REGION | Environment: $CURRENT_ENVIRONMENT"
    if [[ -n "$VPN_SG" ]]; then
        log_info "VPN Security Group: $VPN_SG"
        log_message_core "VPN Service Access Manager 執行開始: action=$ACTION, region=$AWS_REGION, environment=$CURRENT_ENVIRONMENT, vpn_sg=$VPN_SG"
    else
        log_message_core "VPN Service Access Manager 執行開始: action=$ACTION, region=$AWS_REGION, environment=$CURRENT_ENVIRONMENT"
    fi
    echo "================================"
    
    case "$ACTION" in
        "discover")
            discover_services
            ;;
        "display-services")
            # Display discovered services - run discovery if no data exists
            if [[ -f /tmp/final_discoveries.txt && -s /tmp/final_discoveries.txt ]]; then
                log_info "Using existing discovery data for display"
                display_services_and_ask_confirmation /tmp/final_discoveries.txt
            elif [[ -f /tmp/confirmed_services.txt && -s /tmp/confirmed_services.txt ]]; then
                log_info "Using existing confirmed services for display"
                display_services_and_ask_confirmation /tmp/confirmed_services.txt
            else
                log_info "No discovery data found, running discovery first..."
                echo -e "🔍 Running discovery to find services..." > /dev/tty 2>/dev/null || true
                if discover_services; then
                    if [[ -f /tmp/final_discoveries.txt && -s /tmp/final_discoveries.txt ]]; then
                        display_services_and_ask_confirmation /tmp/final_discoveries.txt
                    else
                        echo -e "${YELLOW}⚠️ No services were discovered.${NC}"
                        exit 1
                    fi
                else
                    echo -e "${RED}❌ Discovery failed.${NC}"
                    exit 1
                fi
            fi
            ;;
        "create")
            # Only run discovery if we don't have recent cached data
            if [[ "$VPN_USE_CACHED_DISCOVERY" == "true" ]] && [[ -f /tmp/final_discoveries.txt ]] && [[ -s /tmp/final_discoveries.txt ]]; then
                log_info "Using existing discovery data from this session"
            else
                discover_services
            fi
            echo
            create_rules "$VPN_SG"
            ;;
        "remove")
            # Only run discovery if we don't have recent cached data
            if [[ "$VPN_USE_CACHED_DISCOVERY" == "true" ]] && [[ -f /tmp/final_discoveries.txt ]] && [[ -s /tmp/final_discoveries.txt ]]; then
                log_info "Using existing discovery data from this session"
            else
                discover_services
            fi
            echo
            remove_rules "$VPN_SG"
            ;;
        "clean")
            cleanup_tracking_file
            cleanup_discovery_cache
            ;;
        "report")
            # Generate human-readable tracking report
            local report_script_path="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/vpn_tracking_report.sh"
            if [[ -f "$report_script_path" ]]; then
                # Extract report-specific arguments
                local report_args=()
                for arg in "$@"; do
                    case "$arg" in
                        --summary|-s|--commands|-c|--help|-h)
                            report_args+=("$arg")
                            ;;
                    esac
                done
                exec "$report_script_path" "${report_args[@]}"
            else
                echo -e "${RED}❌ VPN tracking report script not found${NC}"
                echo -e "${YELLOW}Expected location: $report_script_path${NC}"
                exit 1
            fi
            ;;
        *)
            log_error "Unknown action: $ACTION"
            show_usage
            exit 1
            ;;
    esac
    
    # Cleanup
    rm -f /tmp/discovered_services.txt
    
    echo
    log_info "✅ Operation completed!"
    log_message_core "VPN Service Access Manager 執行完成: action=$ACTION, environment=$CURRENT_ENVIRONMENT"
}

# Main service discovery function - orchestrates the entire discovery process
discover_services() {
    log_info "🔍 Starting VPN service discovery process..."
    
    # Get VPC ID from environment configuration
    local vpc_id
    if [[ -n "$VPC_ID" ]]; then
        vpc_id="$VPC_ID"
    else
        # Try to get VPC ID from VPN security group if provided
        if [[ -n "$VPN_SG" ]]; then
            vpc_id=$(aws_with_profile ec2 describe-security-groups \
                --group-ids "$VPN_SG" \
                --region "$AWS_REGION" \
                --query 'SecurityGroups[0].VpcId' \
                --output text 2>/dev/null)
        fi
        
        if [[ -z "$vpc_id" || "$vpc_id" == "None" ]]; then
            log_error "Unable to determine VPC ID. Please ensure VPC_ID is set in environment or provide a valid VPN security group."
            return 1
        fi
    fi
    
    log_info "Target VPC: $vpc_id"
    
    # Check if we should use cached discovery data
    if [[ "$VPN_USE_CACHED_DISCOVERY" == "true" ]]; then
        log_info "🔄 Checking for cached discovery data..."
        if load_cached_discovery "$vpc_id"; then
            log_info "✅ Using cached discovery data (skipping redundant discovery)"
            
            # Display summary from cache
            local discovery_count
            discovery_count=$(wc -l < /tmp/final_discoveries.txt)
            log_info "📦 Loaded $discovery_count cached services"
            
            if [[ "$discovery_count" -gt 0 ]]; then
                log_info "Cached services:"
                while IFS=':' read -r service port sg_id method score confidence; do
                    log_info "  📦 $service (port $port) - Security Group: $sg_id [$confidence confidence]"
                done < /tmp/final_discoveries.txt
            fi
            
            return 0
        else
            log_info "⚠️ No valid cached data found, performing fresh discovery..."
        fi
    fi
    
    # Perform multi-tier discovery
    if ! perform_multi_tier_discovery "$vpc_id"; then
        log_error "Service discovery failed"
        return 1
    fi
    
    # Check if any services were discovered
    if [[ ! -f /tmp/final_discoveries.txt ]] || [[ ! -s /tmp/final_discoveries.txt ]]; then
        log_warning "No services discovered in VPC $vpc_id"
        log_info "This could mean:"
        log_info "  - No AWS services are running in this VPC"
        log_info "  - Services are using non-standard configurations"
        log_info "  - Discovery methods need adjustment"
        return 0
    fi
    
    local discovery_count
    discovery_count=$(wc -l < /tmp/final_discoveries.txt)
    log_info "✅ Discovery completed: $discovery_count services found"
    
    # Save discovery data to cache for future use
    if [[ "$discovery_count" -gt 0 ]]; then
        save_discovery_cache "$vpc_id"
    fi
    
    # Display summary of discoveries
    if [[ "$discovery_count" -gt 0 ]]; then
        log_info "Discovered services:"
        while IFS=':' read -r service port sg_id method score confidence; do
            log_info "  📦 $service (port $port) - Security Group: $sg_id [$confidence confidence]"
        done < /tmp/final_discoveries.txt
    fi
    
    return 0
}

main "$@"
