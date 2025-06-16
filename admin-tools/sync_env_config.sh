#!/bin/bash

# sync_env_config.sh
# 同步環境配置文件腳本 - 從 template.env.example 同步變量並從AWS獲取值
# Sync environment configuration script - sync variables from template.env.example and fetch values from AWS

set -euo pipefail

# 獲取腳本目錄
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# 載入核心函數
source "$PROJECT_ROOT/lib/core_functions.sh"
source "$PROJECT_ROOT/lib/env_manager.sh"

# 配置文件路径
TEMPLATE_FILE="$PROJECT_ROOT/configs/template.env.example"
CONFIGS_DIR="$PROJECT_ROOT/configs"

# 顏色定義
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 日志函數
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 顯示幫助信息
show_help() {
    cat << EOF
使用方法: $0 [選項] [環境名稱]

同步環境配置文件 - 從 template.env.example 同步變量並從AWS獲取值

選項:
  -h, --help              顯示此幫助信息
  -d, --dry-run          試跑模式，只顯示將要進行的更改
  -f, --force            強制覆蓋現有值
  --fetch-aws            從AWS獲取動態值（VPC、子網、端點ID等）
  --backup               在修改前創建備份
  --all                  同步所有環境

參數:
  環境名稱               要同步的環境名稱（staging, production等）

示例:
  $0 staging                    # 同步staging環境
  $0 --fetch-aws production     # 同步production環境並從AWS獲取值
  $0 --all --backup             # 同步所有環境並創建備份
  $0 --dry-run staging          # 預覽staging環境的更改

EOF
}

# 從 template.env.example 提取所有必需的變量
extract_template_variables() {
    local template_file="$1"
    
    if [[ ! -f "$template_file" ]]; then
        log_error "模板文件不存在: $template_file"
        return 1
    fi
    
    # 提取所有變量定義，包括注釋和實際值
    local in_critical_section=false
    local in_optional_section=false
    local in_autogen_section=false
    
    while IFS= read -r line; do
        # 檢查段落標記
        if [[ "$line" =~ "CRITICAL CONFIGURATION - REQUIRED FOR ALL ENVIRONMENTS" ]]; then
            in_critical_section=true
            continue
        elif [[ "$line" =~ "OPTIONAL CONFIGURATION" ]]; then
            in_critical_section=false
            in_optional_section=true
            continue
        elif [[ "$line" =~ "AUTO-GENERATED CONFIGURATION" ]]; then
            in_optional_section=false
            in_autogen_section=true
            continue
        fi
        
        # 處理變量行
        if [[ "$line" =~ ^[[:space:]]*([A-Z_][A-Z0-9_]*)=(.*)$ ]]; then
            local var_name="${BASH_REMATCH[1]}"
            local var_value="${BASH_REMATCH[2]}"
            local priority="optional"
            
            if [[ "$in_critical_section" == true ]]; then
                priority="critical"
            elif [[ "$in_autogen_section" == true ]]; then
                priority="autogen"
            fi
            
            echo "$var_name|$var_value|$priority"
        fi
        
        # 處理註釋掉的變量
        if [[ "$line" =~ ^[[:space:]]*#[[:space:]]*([A-Z_][A-Z0-9_]*)=(.*)$ ]]; then
            local var_name="${BASH_REMATCH[1]}"
            local var_value="${BASH_REMATCH[2]}"
            local priority="optional"
            
            if [[ "$in_critical_section" == true ]]; then
                priority="critical"
            elif [[ "$in_autogen_section" == true ]]; then
                priority="autogen"
            fi
            
            echo "$var_name|$var_value|$priority|commented"
        fi
        
    done < "$template_file"
}

# 獲取環境配置文件路徑
get_env_config_path() {
    local env_name="$1"
    
    # 檢查多個可能的路徑
    local possible_paths=(
        "$CONFIGS_DIR/$env_name/$env_name.env"
        "$CONFIGS_DIR/$env_name.env"
        "$CONFIGS_DIR/$env_name/config.env"
    )
    
    for path in "${possible_paths[@]}"; do
        if [[ -f "$path" ]]; then
            echo "$path"
            return 0
        fi
    done
    
    # 如果都不存在，返回默認路徑
    echo "$CONFIGS_DIR/$env_name/$env_name.env"
}

# 智能檢測環境對應的AWS Profile
detect_aws_profile_for_environment() {
    local env_name="$1"
    
    # 檢查是否有AWS CLI
    if ! command -v aws &> /dev/null; then
        echo "default"
        return
    fi
    
    # 獲取所有可用的AWS profiles
    local available_profiles
    available_profiles=$(aws configure list-profiles 2>/dev/null || echo "")
    
    if [[ -z "$available_profiles" ]]; then
        log_warning "未找到任何AWS Profile，使用默認profile"
        echo "default"
        return
    fi
    
    # 不要在這裡輸出log，因為會被捕獲到變數中
    
    # 環境特定的profile匹配邏輯
    local suggested_profiles=()
    case "$env_name" in
        staging|stage|stg|dev)
            suggested_profiles=("staging" "stage" "stg" "dev" "development" "staging-vpn" "dev-vpn")
            ;;
        production|prod|prd)
            suggested_profiles=("production" "prod" "prd" "prod-vpn" "production-vpn")
            ;;
        *)
            suggested_profiles=("$env_name" "${env_name}-vpn" "$env_name-admin")
            ;;
    esac
    
    # 嘗試找到匹配的profile
    for suggested in "${suggested_profiles[@]}"; do
        if echo "$available_profiles" | grep -q "^$suggested$"; then
            echo "$suggested"
            return
        fi
    done
    
    # 如果只有一個profile，直接使用
    local profile_count
    profile_count=$(echo "$available_profiles" | wc -l)
    if [[ "$profile_count" -eq 1 ]]; then
        local single_profile
        single_profile=$(echo "$available_profiles" | head -1)
        echo "$single_profile"
        return
    fi
    
    # 使用default作為最後的備用
    if echo "$available_profiles" | grep -q "^default$"; then
        echo "default"
    else
        # 使用第一個可用的profile
        local first_profile
        first_profile=$(echo "$available_profiles" | head -1)
        echo "$first_profile"
    fi
}

# 智能檢測環境對應的AWS Region
detect_aws_region_for_environment() {
    local env_name="$1"
    local aws_profile="${2:-}"
    
    # 從環境變數檢查
    if [[ -n "${AWS_DEFAULT_REGION:-}" ]]; then
        echo "$AWS_DEFAULT_REGION"
        return
    fi
    
    # 嘗試從AWS CLI配置檢查 (先檢查profile特定的region)
    local profile_region=""
    if [[ -n "${aws_profile:-}" ]]; then
        profile_region=$(aws configure get region --profile "$aws_profile" 2>/dev/null || echo "")
    fi
    
    if [[ -n "$profile_region" ]]; then
        echo "$profile_region"
        return
    fi
    
    # 再檢查默認region
    local default_region
    default_region=$(aws configure get region 2>/dev/null || echo "")
    
    if [[ -n "$default_region" ]]; then
        echo "$default_region"
        return
    fi
    
    # 環境特定的region建議
    case "$env_name" in
        production|prod)
            echo "us-east-1"
            ;;
        staging|stage|dev)
            echo "us-east-1"
            ;;
        *)
            echo "us-east-1"
            ;;
    esac
}

# 從AWS獲取動態值
fetch_aws_values() {
    local env_name="$1"
    local aws_profile="$2"
    local aws_region="$3"
    
    echo "[INFO] 從AWS獲取 $env_name 環境的動態值..." >&2
    
    # 驗證AWS CLI配置
    if ! command -v aws &> /dev/null; then
        echo "[ERROR] AWS CLI 未安裝" >&2
        return 1
    fi
    
    # 使用環境感知的AWS CLI包裝器
    local aws_cmd="aws"
    export AWS_PROFILE="$aws_profile"
    export AWS_DEFAULT_REGION="$aws_region"
    echo "[INFO] 設定AWS環境變數: AWS_PROFILE=$AWS_PROFILE, AWS_DEFAULT_REGION=$AWS_DEFAULT_REGION" >&2
    
    # 測試AWS連接 (簡化測試避免subshell問題)
    echo "[INFO] 測試AWS連接 (Profile: $aws_profile, Region: $aws_region)..." >&2
    
    # 直接測試而不依賴複雜的subshell
    if AWS_PROFILE="$aws_profile" AWS_DEFAULT_REGION="$aws_region" aws sts get-caller-identity --output text --query 'Account' >/dev/null 2>&1; then
        local account_id
        account_id=$(AWS_PROFILE="$aws_profile" AWS_DEFAULT_REGION="$aws_region" aws sts get-caller-identity --output text --query 'Account' 2>/dev/null)
        echo "[SUCCESS] AWS連接成功 - 賬戶: $account_id" >&2
    else
        echo "[ERROR] 無法連接到AWS。請檢查以下項目：" >&2
        echo "[ERROR] 1. AWS Profile '$aws_profile' 是否存在" >&2
        echo "[ERROR] 2. AWS憑證是否有效" >&2
        echo "[ERROR] 3. 網路連接是否正常" >&2
        return 1
    fi
    
    # 獲取VPC信息
    echo "[INFO] 掃描VPC資源..." >&2
    local vpcs
    vpcs=$($aws_cmd ec2 describe-vpcs --query 'Vpcs[?!IsDefault].[VpcId,CidrBlock,Tags[?Key==`Name`].Value|[0]]' --output text 2>/dev/null || echo "")
    
    local vpc_found=false
    if [[ -n "$vpcs" ]]; then
        while IFS=$'\t' read -r vpc_id cidr_block vpc_name; do
            # 尋找包含EKS或primary關鍵字的VPC
            if [[ "$vpc_name" =~ [Ee][Kk][Ss] ]] || [[ "$vpc_name" =~ [Pp]rimary ]] || [[ "$vpc_name" =~ $env_name ]]; then
                echo "PRIMARY_VPC_ID=$vpc_id"
                echo "PRIMARY_VPC_CIDR=$cidr_block"
                echo "PRIMARY_VPC_NAME=$vpc_name"
                echo "[SUCCESS] 發現主要VPC: $vpc_id ($vpc_name)" >&2
                vpc_found=true
                
                # 獲取該VPC的子網
                local subnets
                subnets=$($aws_cmd ec2 describe-subnets --filters "Name=vpc-id,Values=$vpc_id" --query 'Subnets[0].SubnetId' --output text 2>/dev/null || echo "")
                if [[ -n "$subnets" && "$subnets" != "None" ]]; then
                    echo "PRIMARY_SUBNET_ID=$subnets"
                    echo "[SUCCESS] 發現主要子網: $subnets" >&2
                fi
                break
            fi
        done <<< "$vpcs"
    fi
    
    if [[ "$vpc_found" == "false" ]]; then
        echo "[WARNING] 未找到匹配的VPC (搜索關鍵字: EKS, Primary, $env_name)" >&2
        echo "[INFO] 可用的VPC列表:" >&2
        while IFS=$'\t' read -r vpc_id cidr_block vpc_name; do
            echo "[INFO]   - $vpc_id ($vpc_name) $cidr_block" >&2
        done <<< "$vpcs"
    fi
    
    # 獲取Client VPN端點
    echo "[INFO] 掃描Client VPN端點..." >&2
    local endpoints
    endpoints=$($aws_cmd ec2 describe-client-vpn-endpoints --query 'ClientVpnEndpoints[?Status.Code==`available`].[ClientVpnEndpointId,Tags[?Key==`Name`].Value|[0]]' --output text 2>/dev/null || echo "")
    
    local endpoint_found=false
    if [[ -n "$endpoints" ]]; then
        while IFS=$'\t' read -r endpoint_id endpoint_name; do
            if [[ "$endpoint_name" =~ $env_name ]] || [[ "$endpoint_name" =~ [Vv][Pp][Nn] ]]; then
                echo "ENDPOINT_ID=$endpoint_id"
                echo "[SUCCESS] 發現VPN端點: $endpoint_id ($endpoint_name)" >&2
                endpoint_found=true
                break
            fi
        done <<< "$endpoints"
    fi
    
    if [[ "$endpoint_found" == "false" ]]; then
        echo "[WARNING] 未找到匹配的Client VPN端點 (搜索關鍵字: $env_name, VPN)" >&2
        if [[ -n "$endpoints" ]]; then
            echo "[INFO] 可用的VPN端點列表:" >&2
            while IFS=$'\t' read -r endpoint_id endpoint_name; do
                echo "[INFO]   - $endpoint_id ($endpoint_name)" >&2
            done <<< "$endpoints"
        else
            echo "[INFO] AWS賬戶中沒有任何可用的Client VPN端點" >&2
        fi
    fi
    
    # 獲取S3 bucket
    echo "[INFO] 掃描S3 buckets..." >&2
    local buckets
    buckets=$($aws_cmd s3api list-buckets --query 'Buckets[].Name' --output text 2>/dev/null || echo "")
    
    local bucket_found=false
    if [[ -n "$buckets" ]]; then
        for bucket in $buckets; do
            if [[ "$bucket" =~ $env_name.*vpn ]] || [[ "$bucket" =~ vpn.*$env_name ]]; then
                local env_upper
                env_upper=$(echo "$env_name" | tr '[:lower:]' '[:upper:]')
                echo "${env_upper}_S3_BUCKET=$bucket"
                echo "[SUCCESS] 發現S3 bucket: $bucket" >&2
                bucket_found=true
                break
            fi
        done
    fi
    
    if [[ "$bucket_found" == "false" ]]; then
        echo "[WARNING] 未找到匹配的S3 bucket (搜索關鍵字: $env_name + vpn)" >&2
    fi
    
    # 獲取賬戶ID
    if [[ -n "$account_id" ]]; then
        local env_upper
        env_upper=$(echo "$env_name" | tr '[:lower:]' '[:upper:]')
        echo "${env_upper}_ACCOUNT_ID=$account_id"
        echo "[SUCCESS] 獲取賬戶ID: $account_id" >&2
    fi
    
    # 總結AWS掃描結果
    echo "[INFO] AWS資源掃描完成:" >&2
    echo "[INFO]   ✓ VPC: $([ "$vpc_found" == "true" ] && echo "找到" || echo "未找到")" >&2
    echo "[INFO]   ✓ VPN端點: $([ "$endpoint_found" == "true" ] && echo "找到" || echo "未找到")" >&2
    echo "[INFO]   ✓ S3 bucket: $([ "$bucket_found" == "true" ] && echo "找到" || echo "未找到")" >&2
    echo "[INFO]   ✓ 賬戶ID: $([ -n "$account_id" ] && echo "獲取成功" || echo "獲取失敗")" >&2
}

# 備份配置文件
backup_config() {
    local config_file="$1"
    
    if [[ ! -f "$config_file" ]]; then
        return 0
    fi
    
    local backup_file="${config_file}.backup.$(date +%Y%m%d_%H%M%S)"
    cp "$config_file" "$backup_file"
    log_success "已備份配置文件: $backup_file"
}

# 同步單個環境配置
sync_environment() {
    local env_name="$1"
    local dry_run="$2"
    local force="$3"
    local fetch_aws="$4"
    local backup="$5"
    
    log_info "開始同步環境: $env_name"
    
    local config_file
    config_file=$(get_env_config_path "$env_name")
    
    # 檢查配置文件狀態
    if [[ -f "$config_file" ]]; then
        log_info "發現現有配置文件: $config_file"
    else
        log_warning "配置文件不存在，將從模板創建: $config_file"
    fi
    
    # 確保配置文件目錄存在
    local config_dir
    config_dir=$(dirname "$config_file")
    if [[ ! -d "$config_dir" ]]; then
        if [[ "$dry_run" == "true" ]]; then
            log_info "[DRY-RUN] 將創建目錄: $config_dir"
        else
            mkdir -p "$config_dir"
            log_success "創建目錄: $config_dir"
        fi
    fi
    
    # 備份現有配置
    if [[ "$backup" == "true" && -f "$config_file" ]]; then
        if [[ "$dry_run" == "false" ]]; then
            backup_config "$config_file"
        else
            log_info "[DRY-RUN] 將備份配置文件"
        fi
    fi
    
    # 讀取現有配置
    local existing_vars_list=""
    if [[ -f "$config_file" ]]; then
        existing_vars_list=$(grep -E '^[A-Z_][A-Z0-9_]*=' "$config_file" || true)
    fi
    
    # 提取模板變量
    local template_vars
    template_vars=$(extract_template_variables "$TEMPLATE_FILE")
    
    # 從AWS獲取動態值
    local aws_values_list=""
    if [[ "$fetch_aws" == "true" ]]; then
        local aws_profile="default"
        local aws_region="us-east-1"
        
        # 從現有配置中獲取AWS設定
        if [[ -n "$existing_vars_list" ]]; then
            local profile_line=$(echo "$existing_vars_list" | grep "^AWS_PROFILE=" || echo "")
            if [[ -n "$profile_line" ]]; then
                aws_profile=$(echo "$profile_line" | cut -d'=' -f2- | sed 's/^"\(.*\)"$/\1/')
            fi
            
            local region_line=$(echo "$existing_vars_list" | grep "^AWS_REGION=" || echo "")
            if [[ -n "$region_line" ]]; then
                aws_region=$(echo "$region_line" | cut -d'=' -f2- | sed 's/^"\(.*\)"$/\1/')
            fi
        else
            # 配置文件不存在，智能檢測AWS Profile
            log_info "配置文件不存在，正在智能檢測AWS Profile..."
            
            # 先獲取可用profiles用於顯示
            local available_profiles
            available_profiles=$(aws configure list-profiles 2>/dev/null || echo "")
            if [[ -n "$available_profiles" ]]; then
                log_info "可用的AWS Profiles: $(echo "$available_profiles" | tr '\n' ' ')"
            fi
            
            aws_profile=$(detect_aws_profile_for_environment "$env_name")
            aws_region=$(detect_aws_region_for_environment "$env_name" "$aws_profile")
            
            # 檢查是否成功檢測到特定profile
            if [[ "$aws_profile" != "default" ]] && echo "$available_profiles" | grep -q "^$aws_profile$"; then
                log_success "自動檢測到AWS Profile: $aws_profile"
            else
                log_warning "未找到與環境 '$env_name' 匹配的AWS Profile，使用: $aws_profile"
            fi
        fi
        
        log_info "最終使用AWS配置: Profile=$aws_profile, Region=$aws_region"
        
        if [[ "$dry_run" == "false" ]]; then
            log_info "開始執行AWS資源掃描..."
            aws_values_list=$(fetch_aws_values "$env_name" "$aws_profile" "$aws_region" || true)
            if [[ -n "$aws_values_list" ]]; then
                log_success "AWS掃描完成，獲取到 $(echo "$aws_values_list" | wc -l) 個值"
                log_info "AWS獲取的值："
                while IFS= read -r line; do
                    if [[ -n "$line" ]]; then
                        log_info "  - $line"
                    fi
                done <<< "$aws_values_list"
            else
                log_warning "AWS掃描完成，但未獲取到任何值"
            fi
        else
            log_info "[DRY-RUN] 將從AWS獲取動態值 (Profile: $aws_profile, Region: $aws_region)"
        fi
    fi
    
    # 準備新配置內容
    local new_config=""
    local changes_made=0
    
    # 添加頭部注釋
    local env_display_name="$(echo ${env_name:0:1} | tr '[:lower:]' '[:upper:]')${env_name:1}"
    new_config+="# $env_display_name Environment Configuration\n"
    new_config+="# Synced from template.env.example on $(date)\n\n"
    
    # 處理關鍵配置變量
    new_config+="# ====================================================================\n"
    new_config+="# CRITICAL CONFIGURATION - REQUIRED FOR ALL ENVIRONMENTS\n"
    new_config+="# ====================================================================\n\n"
    
    # 分組處理變量
    local current_section=""
    while IFS='|' read -r var_name var_value priority commented; do
        if [[ "$priority" != "$current_section" ]]; then
            current_section="$priority"
            case "$priority" in
                "critical")
                    # 已經添加了標題
                    ;;
                "optional")
                    new_config+="\n# ====================================================================\n"
                    new_config+="# OPTIONAL CONFIGURATION - ADVANCED/FUTURE FEATURES\n"
                    new_config+="# ====================================================================\n\n"
                    ;;
                "autogen")
                    new_config+="\n# ====================================================================\n"
                    new_config+="# AUTO-GENERATED CONFIGURATION - DO NOT MODIFY\n"
                    new_config+="# ====================================================================\n\n"
                    ;;
            esac
        fi
        
        local current_value=""
        
        # 從現有配置列表中查找對應的值
        if [[ -n "$existing_vars_list" ]]; then
            current_value=$(echo "$existing_vars_list" | grep "^$var_name=" | cut -d'=' -f2- | sed 's/^"\(.*\)"$/\1/' || echo "")
        fi
        local aws_value=""
        
        # 從AWS值列表中查找對應的值
        if [[ -n "$aws_values_list" ]]; then
            aws_value=$(echo "$aws_values_list" | grep "^$var_name=" | cut -d'=' -f2- || echo "")
        fi
        
        local final_value=""
        
        # 決定最終值的優先級：AWS值 > 現有值 > 模板值（調整為環境）
        if [[ -n "$aws_value" ]]; then
            final_value="$aws_value"
        elif [[ -n "$current_value" && "$force" == "false" ]]; then
            final_value="$current_value"
        else
            # 替換模板中的佔位符
            final_value=$(echo "$var_value" | sed "s/template/$env_name/g" | sed "s/Template/$env_display_name/g")
            # 移除可能的引號和注釋
            final_value=$(echo "$final_value" | sed 's/^"\(.*\)"$/\1/' | sed 's/[[:space:]]*#.*$//')
            # 確保路徑值不包含多餘引號
            if [[ "$var_name" =~ (CERT_DIR|CONFIG_DIR|LOG_DIR|ENV_DISPLAY_NAME) ]]; then
                final_value=$(echo "$final_value" | sed 's/^"\(.*\)"$/\1/')
            fi
            
            # 特殊處理：使用檢測到的AWS配置而不是模板值
            if [[ "$var_name" == "AWS_PROFILE" && "$fetch_aws" == "true" ]]; then
                final_value="$aws_profile"
            elif [[ "$var_name" == "AWS_REGION" && "$fetch_aws" == "true" ]]; then
                final_value="$aws_region"
            fi
        fi
        
        # 檢查是否需要註釋掉
        local var_line=""
        if [[ "$commented" == "commented" && -z "$current_value" && -z "$aws_value" ]]; then
            var_line="# $var_name=\"$final_value\""
        else
            var_line="$var_name=\"$final_value\""
        fi
        
        new_config+="$var_line\n"
        
        # 檢查是否有變更
        if [[ "$current_value" != "$final_value" ]]; then
            changes_made=$((changes_made + 1))
            if [[ "$dry_run" == "true" ]]; then
                log_info "[DRY-RUN] $var_name: '$current_value' -> '$final_value'"
            else
                log_info "更新 $var_name: '$current_value' -> '$final_value'"
            fi
        fi
        
    done <<< "$template_vars"
    
    # 保留現有但不在模板中的變量
    new_config+="\n# ====================================================================\n"
    new_config+="# EXISTING VARIABLES NOT IN TEMPLATE\n"
    new_config+="# ====================================================================\n\n"
    
    local found_extra=false
    if [[ -n "$existing_vars_list" ]]; then
        while IFS='=' read -r key value; do
            if [[ "$key" =~ ^[A-Z_][A-Z0-9_]*$ ]] && ! echo "$template_vars" | grep -q "^$key|"; then
                new_config+="$key=$value\n"
                log_warning "保留現有變量: $key"
                found_extra=true
            fi
        done <<< "$existing_vars_list"
    fi
    
    if [[ "$found_extra" == "false" ]]; then
        new_config+="# No additional variables found\n"
    fi
    
    # 寫入配置文件
    if [[ "$dry_run" == "false" ]]; then
        echo -e "$new_config" > "$config_file"
        if [[ ! -f "$config_file.backup."* ]]; then
            log_success "已創建新環境配置: $config_file ($changes_made 個變數)"
        else
            log_success "已同步環境配置: $config_file ($changes_made 個變更)"
        fi
    else
        if [[ -f "$config_file" ]]; then
            log_info "[DRY-RUN] 將更新現有配置文件，寫入 $changes_made 個變更到: $config_file"
        else
            log_info "[DRY-RUN] 將創建新配置文件，寫入 $changes_made 個變數到: $config_file"
        fi
    fi
    
    return 0
}

# 主函數
main() {
    local dry_run="false"
    local force="false"
    local fetch_aws="false"
    local backup="false"
    local sync_all="false"
    local env_names=()
    
    # 解析命令行參數
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_help
                exit 0
                ;;
            -d|--dry-run)
                dry_run="true"
                shift
                ;;
            -f|--force)
                force="true"
                shift
                ;;
            --fetch-aws)
                fetch_aws="true"
                shift
                ;;
            --backup)
                backup="true"
                shift
                ;;
            --all)
                sync_all="true"
                shift
                ;;
            -*)
                log_error "未知選項: $1"
                show_help
                exit 1
                ;;
            *)
                env_names+=("$1")
                shift
                ;;
        esac
    done
    
    # 檢查模板文件
    if [[ ! -f "$TEMPLATE_FILE" ]]; then
        log_error "模板文件不存在: $TEMPLATE_FILE"
        exit 1
    fi
    
    # 確定要同步的環境
    if [[ "$sync_all" == "true" ]]; then
        # 自動發現所有環境
        env_names=()
        for dir in "$CONFIGS_DIR"/*; do
            if [[ -d "$dir" ]]; then
                local env_name
                env_name=$(basename "$dir")
                if [[ "$env_name" != "template" ]]; then
                    env_names+=("$env_name")
                fi
            fi
        done
        
        # 也檢查根目錄下的配置文件
        for file in "$CONFIGS_DIR"/*.env; do
            if [[ -f "$file" ]]; then
                local env_name
                env_name=$(basename "$file" .env)
                if [[ "$env_name" != "template" ]]; then
                    env_names+=("$env_name")
                fi
            fi
        done
    fi
    
    # 如果沒有指定環境，顯示幫助
    if [[ ${#env_names[@]} -eq 0 ]]; then
        log_error "請指定要同步的環境名稱或使用 --all"
        show_help
        exit 1
    fi
    
    # 顯示操作摘要
    log_info "同步配置摘要:"
    log_info "  模板文件: $TEMPLATE_FILE"
    log_info "  試跑: $dry_run"
    log_info "  強制覆蓋: $force"
    log_info "  獲取AWS值: $fetch_aws"
    log_info "  創建備份: $backup"
    log_info "  環境列表: ${env_names[*]}"
    echo
    
    # 確認操作
    if [[ "$dry_run" == "false" ]]; then
        read -p "是否繼續？(Y/n): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]] && [[ -n $REPLY ]]; then
            log_info "操作已取消"
            exit 0
        fi
    fi
    
    # 同步每個環境
    local success_count=0
    local total_count=${#env_names[@]}
    
    for env_name in "${env_names[@]}"; do
        if sync_environment "$env_name" "$dry_run" "$force" "$fetch_aws" "$backup"; then
            success_count=$((success_count + 1))
        else
            log_error "同步環境失敗: $env_name"
        fi
        echo
    done
    
    # 顯示最終結果
    log_success "同步完成: $success_count/$total_count 個環境"
    
    if [[ "$dry_run" == "true" ]]; then
        log_info "這是試跑模式，沒有實際修改文件"
        log_info "要應用更改，請移除 --dry-run 參數"
    fi
}

# 執行主函數
main "$@"