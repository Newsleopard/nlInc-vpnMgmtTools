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
source "$PROJECT_ROOT/lib/enhanced_confirmation.sh"

# 配置文件路径
TEMPLATE_FILE="$PROJECT_ROOT/configs/template.env.example"
CONFIGS_DIR="$PROJECT_ROOT/configs"

# 顏色定義
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m' # No Color

# 全局變數
sync_mode="basic"

# 狀態圖示定義
STATUS_SYNCING="🔄"
STATUS_SUCCESS="✅"
STATUS_WARNING="⚠️"
STATUS_ERROR="❌"
STATUS_INFO="ℹ️"

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

# 顯示增強版標題
show_enhanced_header() {
    clear
    echo -e "${CYAN}${BOLD}╔═══════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}${BOLD}║                    環境配置同步工具 v2.0                          ║${NC}"
    echo -e "${CYAN}${BOLD}║                Environment Configuration Sync Tool                ║${NC}"
    echo -e "${CYAN}${BOLD}╚═══════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    # 顯示模板狀態
    if [[ -f "$TEMPLATE_FILE" ]]; then
        echo -e "${GREEN}${STATUS_SUCCESS} 模板文件: ${NC}$TEMPLATE_FILE"
    else
        echo -e "${RED}${STATUS_ERROR} 模板文件不存在: ${NC}$TEMPLATE_FILE"
    fi
    
    # 顯示可用環境
    local env_count=0
    echo -e "${BLUE}${STATUS_INFO} 可用環境:${NC}"
    
    # 檢查目錄式環境
    for dir in "$CONFIGS_DIR"/*; do
        if [[ -d "$dir" ]]; then
            local env_name=$(basename "$dir")
            if [[ "$env_name" != "template" ]]; then
                echo -e "  ${GREEN}•${NC} $env_name"
                env_count=$((env_count + 1))
            fi
        fi
    done
    
    # 檢查文件式環境
    for file in "$CONFIGS_DIR"/*.env; do
        if [[ -f "$file" ]]; then
            local env_name=$(basename "$file" .env)
            if [[ "$env_name" != "template" ]]; then
                echo -e "  ${GREEN}•${NC} $env_name (單檔)"
                env_count=$((env_count + 1))
            fi
        fi
    done
    
    if [[ $env_count -eq 0 ]]; then
        echo -e "  ${YELLOW}${STATUS_WARNING} 未發現任何環境${NC}"
    fi
    
    echo ""
}

# 互動式環境選擇
interactive_environment_selection() {
    local available_envs=()
    
    # 收集可用環境
    for dir in "$CONFIGS_DIR"/*; do
        if [[ -d "$dir" ]]; then
            local env_name=$(basename "$dir")
            if [[ "$env_name" != "template" ]]; then
                available_envs+=("$env_name")
            fi
        fi
    done
    
    for file in "$CONFIGS_DIR"/*.env; do
        if [[ -f "$file" ]]; then
            local env_name=$(basename "$file" .env)
            if [[ "$env_name" != "template" ]]; then
                # 避免重複
                if [[ ! " ${available_envs[@]} " =~ " ${env_name} " ]]; then
                    available_envs+=("$env_name")
                fi
            fi
        fi
    done
    
    if [[ ${#available_envs[@]} -eq 0 ]]; then
        echo -e "${RED}${STATUS_ERROR} 未發現任何可用環境${NC}" >&2
        return 1
    fi
    
    echo -e "${PURPLE}${BOLD}選擇要同步的環境:${NC}" >&2
    echo -e "  ${BOLD}[A]${NC} 全部環境 (${#available_envs[@]} 個)" >&2
    echo "" >&2
    
    local i=1
    for env in "${available_envs[@]}"; do
        # 檢查環境狀態
        local config_file=$(get_env_config_path "$env")
        local status_icon="${STATUS_INFO}"
        local status_text=""
        
        if [[ -f "$config_file" ]]; then
            status_icon="${STATUS_SUCCESS}"
            status_text=" (已配置)"
        else
            status_icon="${STATUS_WARNING}"
            status_text=" (未配置)"
        fi
        
        echo -e "  ${BOLD}[$i]${NC} $env${status_icon}${status_text}" >&2
        i=$((i + 1))
    done
    
    echo -e "  ${BOLD}[Q]${NC} 退出" >&2
    echo "" >&2
    
    while true; do
        read -p "請選擇 [1-${#available_envs[@]}/A/Q]: " choice >&2
        
        case "$choice" in
            [Aa])
                echo "all"
                return 0
                ;;
            [Qq])
                echo "quit"
                return 0
                ;;
            [1-9]*)
                if [[ "$choice" -ge 1 && "$choice" -le ${#available_envs[@]} ]]; then
                    local selected_env="${available_envs[$((choice - 1))]}"
                    echo "$selected_env"
                    return 0
                else
                    echo -e "${YELLOW}${STATUS_WARNING} 請輸入有效的選項 (1-${#available_envs[@]}/A/Q)${NC}" >&2
                fi
                ;;
            *)
                echo -e "${YELLOW}${STATUS_WARNING} 請輸入有效的選項 (1-${#available_envs[@]}/A/Q)${NC}" >&2
                ;;
        esac
    done
}

# 互動式操作模式選擇
interactive_operation_mode_selection() {
    echo -e "${PURPLE}${BOLD}選擇同步模式:${NC}" >&2
    echo -e "  ${BOLD}[1]${NC} 基本同步 - 僅更新缺失的變數" >&2
    echo -e "  ${BOLD}[2]${NC} 完整同步 - 同步所有變數 + 創建備份" >&2
    echo -e "  ${BOLD}[3]${NC} AWS同步 - 從AWS獲取動態值 + 完整同步" >&2
    echo -e "  ${BOLD}[4]${NC} 預覽模式 - 顯示變更但不實際修改" >&2
    echo -e "  ${BOLD}[5]${NC} 強制同步 - 覆蓋所有現有值" >&2
    echo -e "  ${BOLD}[Q]${NC} 返回" >&2
    echo "" >&2
    
    while true; do
        read -p "請選擇模式 [1-5/Q]: " mode >&2
        
        case "$mode" in
            1)
                echo "basic"
                return 0
                ;;
            2)
                echo "full"
                return 0
                ;;
            3)
                echo "aws"
                return 0
                ;;
            4)
                echo "preview"
                return 0
                ;;
            5)
                echo "force"
                return 0
                ;;
            [Qq])
                echo "quit"
                return 0
                ;;
            *)
                echo -e "${YELLOW}${STATUS_WARNING} 請輸入有效的選項 (1-5/Q)${NC}" >&2
                ;;
        esac
    done
}

# 顯示操作摘要並確認
show_operation_summary() {
    local env_names=("$@")
    local env_list=""
    
    # 創建環境列表字串
    for env in "${env_names[@]}"; do
        if [[ -n "$env_list" ]]; then
            env_list="$env_list, $env"
        else
            env_list="$env"
        fi
    done
    
    echo -e "${CYAN}${BOLD}╔═══════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}${BOLD}║                           操作摘要                                ║${NC}"
    echo -e "${CYAN}${BOLD}╚═══════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    echo -e "${BOLD}將執行以下操作:${NC}"
    echo -e "  模板文件: ${BLUE}$(basename "$TEMPLATE_FILE")${NC}"
    echo -e "  目標環境: ${GREEN}$env_list${NC}"
    echo -e "  同步模式: ${YELLOW}$(get_mode_description)${NC}"
    echo -e "  總環境數: ${PURPLE}${#env_names[@]}${NC} 個"
    echo ""
    
    # 顯示每個環境的狀態
    echo -e "${BOLD}環境詳情:${NC}"
    for env_name in "${env_names[@]}"; do
        local config_file=$(get_env_config_path "$env_name")
        local status=""
        local action=""
        
        if [[ -f "$config_file" ]]; then
            status="${GREEN}已存在${NC}"
            action="更新配置"
        else
            status="${YELLOW}新建${NC}"
            action="創建配置"
        fi
        
        echo -e "  ${BOLD}•${NC} $env_name: $status → $action"
    done
    echo ""
}

# 獲取模式描述
get_mode_description() {
    case "${sync_mode:-basic}" in
        "basic") echo "基本同步" ;;
        "full") echo "完整同步 + 備份" ;;
        "aws") echo "AWS同步 + 完整同步" ;;
        "preview") echo "預覽模式 (僅顯示)" ;;
        "force") echo "強制覆蓋模式" ;;
        *) echo "未知模式" ;;
    esac
}

# 互動式主介面
interactive_main() {
    show_enhanced_header
    
    # 環境選擇
    echo -e "${PURPLE}${BOLD}步驟 1/3: 選擇環境${NC}"
    local selected_env
    selected_env=$(interactive_environment_selection)
    
    if [[ "$selected_env" == "quit" ]]; then
        echo -e "${BLUE}${STATUS_INFO} 操作已取消${NC}"
        exit 0
    fi
    
    # 操作模式選擇
    echo ""
    echo -e "${PURPLE}${BOLD}步驟 2/3: 選擇同步模式${NC}"
    local selected_mode
    selected_mode=$(interactive_operation_mode_selection)
    
    if [[ "$selected_mode" == "quit" ]]; then
        echo -e "${BLUE}${STATUS_INFO} 操作已取消${NC}"
        exit 0
    fi
    
    # 設定全域變數
    sync_mode="$selected_mode"
    
    # 根據選擇設定參數
    local dry_run="false"
    local force="false"
    local fetch_aws="false"
    local backup="false"
    local sync_all="false"
    local env_names=()
    
    case "$selected_mode" in
        "basic")
            # 基本同步，無特殊參數
            ;;
        "full")
            backup="true"
            ;;
        "aws")
            backup="true"
            fetch_aws="true"
            ;;
        "preview")
            dry_run="true"
            ;;
        "force")
            force="true"
            backup="true"
            ;;
    esac
    
    # 設定環境列表
    if [[ "$selected_env" == "all" ]]; then
        sync_all="true"
        # 自動發現所有環境
        for dir in "$CONFIGS_DIR"/*; do
            if [[ -d "$dir" ]]; then
                local env_name=$(basename "$dir")
                if [[ "$env_name" != "template" ]]; then
                    env_names+=("$env_name")
                fi
            fi
        done
        
        for file in "$CONFIGS_DIR"/*.env; do
            if [[ -f "$file" ]]; then
                local env_name=$(basename "$file" .env)
                if [[ "$env_name" != "template" ]]; then
                    # 避免重複
                    if [[ ! " ${env_names[@]} " =~ " ${env_name} " ]]; then
                        env_names+=("$env_name")
                    fi
                fi
            fi
        done
    else
        env_names=("$selected_env")
    fi
    
    # 顯示操作摘要
    echo ""
    echo -e "${PURPLE}${BOLD}步驟 3/3: 確認操作${NC}"
    show_operation_summary "${env_names[@]}"
    
    # 簡單確認
    echo -e "${BOLD}確認執行同步操作？${NC}"
    read -p "請輸入 [Y/n]: " confirm
    
    if [[ ! "$confirm" =~ ^[Yy]?$ ]]; then
        echo -e "${BLUE}${STATUS_INFO} 操作已取消${NC}"
        exit 0
    fi
    
    # 執行同步
    execute_sync_operation "$dry_run" "$force" "$fetch_aws" "$backup" "${env_names[@]}"
}

# 執行同步操作
execute_sync_operation() {
    local dry_run="$1"
    local force="$2"
    local fetch_aws="$3"
    local backup="$4"
    shift 4
    local env_names=("$@")
    
    echo -e "${CYAN}${BOLD}╔═══════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}${BOLD}║                        開始執行同步                               ║${NC}"
    echo -e "${CYAN}${BOLD}╚═══════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    local success_count=0
    local total_count=${#env_names[@]}
    local current_count=0
    
    for env_name in "${env_names[@]}"; do
        current_count=$((current_count + 1))
        
        echo -e "${PURPLE}${BOLD}┌─ 處理環境 $current_count/$total_count: $env_name ─┐${NC}"
        echo -e "${STATUS_SYNCING} ${BLUE}正在同步環境: $env_name${NC}"
        
        if sync_environment "$env_name" "$dry_run" "$force" "$fetch_aws" "$backup"; then
            success_count=$((success_count + 1))
            echo -e "${STATUS_SUCCESS} ${GREEN}環境 $env_name 同步完成${NC}"
        else
            echo -e "${STATUS_ERROR} ${RED}環境 $env_name 同步失敗${NC}"
        fi
        
        echo -e "${PURPLE}${BOLD}└─────────────────────────────────────┘${NC}"
        echo ""
    done
    
    # 顯示最終結果
    echo -e "${CYAN}${BOLD}╔═══════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}${BOLD}║                         同步結果                                  ║${NC}"
    echo -e "${CYAN}${BOLD}╚═══════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    if [[ $success_count -eq $total_count ]]; then
        echo -e "${STATUS_SUCCESS} ${GREEN}${BOLD}所有環境同步成功！${NC}"
        echo -e "  成功: ${GREEN}$success_count${NC}/$total_count 個環境"
    else
        echo -e "${STATUS_WARNING} ${YELLOW}${BOLD}部分環境同步失敗${NC}"
        echo -e "  成功: ${GREEN}$success_count${NC}/$total_count 個環境"
        echo -e "  失敗: ${RED}$((total_count - success_count))${NC}/$total_count 個環境"
    fi
    
    if [[ "$dry_run" == "true" ]]; then
        echo ""
        echo -e "${STATUS_INFO} ${BLUE}這是預覽模式，沒有實際修改文件${NC}"
        echo -e "要應用更改，請選擇其他同步模式"
    fi
    
    echo ""
}

# 顯示幫助信息
show_help() {
    cat << EOF
使用方法: $0 [選項] [環境名稱]

同步環境配置文件 - 從 template.env.example 同步變量並從AWS獲取值

選項:
  -h, --help              顯示此幫助信息
  -i, --interactive       啟動互動式界面 (推薦)
  -d, --dry-run          試跑模式，只顯示將要進行的更改
  -f, --force            強制覆蓋現有值
  --fetch-aws            從AWS獲取動態值（VPC、子網、端點ID等）
  --backup               在修改前創建備份
  --all                  同步所有環境

參數:
  環境名稱               要同步的環境名稱（staging, production等）

互動模式:
  如果不提供任何參數，會自動進入互動式界面，提供：
  • 環境選擇菜單
  • 同步模式選擇
  • 操作預覽和確認
  • 可視化進度顯示

示例:
  $0                                  # 啟動互動式界面 (推薦)
  $0 --interactive                    # 啟動互動式界面
  $0 staging                          # 同步staging環境
  $0 --fetch-aws production           # 同步production環境並從AWS獲取值
  $0 --all --backup                   # 同步所有環境並創建備份
  $0 --dry-run staging                # 預覽staging環境的更改

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
                echo "VPC_ID=$vpc_id"
                echo "VPC_CIDR=$cidr_block"
                echo "VPC_NAME=$vpc_name"
                echo "[SUCCESS] 發現主要VPC: $vpc_id ($vpc_name)" >&2
                vpc_found=true
                
                # 獲取該VPC的子網
                local subnets
                subnets=$($aws_cmd ec2 describe-subnets --filters "Name=vpc-id,Values=$vpc_id" --query 'Subnets[0].SubnetId' --output text 2>/dev/null || echo "")
                if [[ -n "$subnets" && "$subnets" != "None" ]]; then
                    echo "SUBNET_ID=$subnets"
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
        # First check for unified bucket name
        for bucket in $buckets; do
            if [[ "$bucket" == "vpn-csr-exchange" ]]; then
                echo "# S3_BUCKET=$bucket  # Unified bucket for all environments"
                echo "[SUCCESS] 發現統一 S3 bucket: $bucket" >&2
                bucket_found=true
                break
            fi
        done
        
        # If unified bucket not found, check for legacy environment-specific buckets
        if [[ "$bucket_found" == "false" ]]; then
            for bucket in $buckets; do
                if [[ "$bucket" =~ $env_name.*vpn ]] || [[ "$bucket" =~ vpn.*$env_name ]]; then
                    echo "# S3_BUCKET=$bucket  # Legacy environment-specific bucket (consider migrating to vpn-csr-exchange)"
                    echo "[WARNING] 發現舊式 S3 bucket: $bucket (建議遷移至統一 bucket: vpn-csr-exchange)" >&2
                    bucket_found=true
                    break
                fi
            done
        fi
    fi
    
    if [[ "$bucket_found" == "false" ]]; then
        echo "[WARNING] 未找到 S3 bucket (請使用 setup_csr_s3_bucket.sh 創建統一 bucket: vpn-csr-exchange)" >&2
    fi
    
    # 獲取賬戶ID
    if [[ -n "$account_id" ]]; then
        echo "AWS_ACCOUNT_ID=$account_id"
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
    
    echo -e "  ${STATUS_SYNCING} 分析環境配置..."
    
    local config_file
    config_file=$(get_env_config_path "$env_name")
    
    # 檢查配置文件狀態
    if [[ -f "$config_file" ]]; then
        echo -e "  ${STATUS_INFO} 發現現有配置: $(basename "$config_file")"
    else
        echo -e "  ${STATUS_WARNING} 配置文件不存在，將新建: $(basename "$config_file")"
    fi
    
    # 確保配置文件目錄存在
    local config_dir
    config_dir=$(dirname "$config_file")
    if [[ ! -d "$config_dir" ]]; then
        if [[ "$dry_run" == "true" ]]; then
            echo -e "  ${STATUS_INFO} [預覽] 將創建目錄: $(basename "$config_dir")"
        else
            mkdir -p "$config_dir"
            echo -e "  ${STATUS_SUCCESS} 創建目錄: $(basename "$config_dir")"
        fi
    fi
    
    # 備份現有配置
    if [[ "$backup" == "true" && -f "$config_file" ]]; then
        if [[ "$dry_run" == "false" ]]; then
            backup_config "$config_file"
        else
            echo -e "  ${STATUS_INFO} [預覽] 將備份現有配置"
        fi
    fi
    
    echo -e "  ${STATUS_SYNCING} 讀取模板和現有配置..."
    
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
        echo -e "  ${STATUS_SYNCING} 檢測AWS配置..."
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
            echo -e "  ${STATUS_SYNCING} 智能檢測AWS Profile..."
            
            # 先獲取可用profiles用於顯示
            local available_profiles
            available_profiles=$(aws configure list-profiles 2>/dev/null || echo "")
            if [[ -n "$available_profiles" ]]; then
                echo -e "  ${STATUS_INFO} 可用AWS Profiles: $(echo "$available_profiles" | tr '\n' ' ')"
            fi
            
            aws_profile=$(detect_aws_profile_for_environment "$env_name")
            aws_region=$(detect_aws_region_for_environment "$env_name" "$aws_profile")
            
            # 檢查是否成功檢測到特定profile
            if [[ "$aws_profile" != "default" ]] && echo "$available_profiles" | grep -q "^$aws_profile$"; then
                echo -e "  ${STATUS_SUCCESS} 自動檢測到AWS Profile: $aws_profile"
            else
                echo -e "  ${STATUS_WARNING} 使用默認AWS Profile: $aws_profile"
            fi
        fi
        
        echo -e "  ${STATUS_INFO} 使用AWS配置: Profile=$aws_profile, Region=$aws_region"
        
        if [[ "$dry_run" == "false" ]]; then
            echo -e "  ${STATUS_SYNCING} 正在掃描AWS資源..."
            aws_values_list=$(fetch_aws_values "$env_name" "$aws_profile" "$aws_region" || true)
            if [[ -n "$aws_values_list" ]]; then
                local aws_count=$(echo "$aws_values_list" | wc -l)
                echo -e "  ${STATUS_SUCCESS} AWS掃描完成，獲取到 $aws_count 個值"
                echo -e "  ${STATUS_INFO} AWS獲取的值："
                while IFS= read -r line; do
                    if [[ -n "$line" ]]; then
                        echo -e "    ${GREEN}•${NC} $line"
                    fi
                done <<< "$aws_values_list"
            else
                echo -e "  ${STATUS_WARNING} AWS掃描完成，但未獲取到任何值"
            fi
        else
            echo -e "  ${STATUS_INFO} [預覽] 將從AWS獲取動態值 (Profile: $aws_profile, Region: $aws_region)"
        fi
    fi
    
    echo -e "  ${STATUS_SYNCING} 生成新配置..."
    
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
                echo -e "    ${STATUS_INFO} [預覽] $var_name: '$current_value' → '$final_value'"
            else
                echo -e "    ${STATUS_SUCCESS} 更新 $var_name: '$current_value' → '$final_value'"
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
                echo -e "    ${STATUS_WARNING} 保留現有變量: $key"
                found_extra=true
            fi
        done <<< "$existing_vars_list"
    fi
    
    if [[ "$found_extra" == "false" ]]; then
        new_config+="# No additional variables found\n"
    fi
    
    # 寫入配置文件
    if [[ "$dry_run" == "false" ]]; then
        echo -e "  ${STATUS_SYNCING} 寫入配置文件..."
        echo -e "$new_config" > "$config_file"
        if [[ ! -f "$config_file.backup."* ]]; then
            echo -e "  ${STATUS_SUCCESS} 新環境配置已創建: $(basename "$config_file") ($changes_made 個變數)"
        else
            echo -e "  ${STATUS_SUCCESS} 環境配置已同步: $(basename "$config_file") ($changes_made 個變更)"
        fi
    else
        if [[ -f "$config_file" ]]; then
            echo -e "  ${STATUS_INFO} [預覽] 將更新配置文件，$changes_made 個變更"
        else
            echo -e "  ${STATUS_INFO} [預覽] 將創建新配置文件，$changes_made 個變數"
        fi
    fi
    
    return 0
}

# 主函數
main() {
    # 如果沒有提供任何參數，進入互動模式
    if [[ $# -eq 0 ]]; then
        interactive_main
        return $?
    fi
    
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
            -i|--interactive)
                interactive_main
                return $?
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
    
    # 設定CLI模式的sync_mode
    if [[ "$dry_run" == "true" ]]; then
        sync_mode="preview"
    elif [[ "$force" == "true" ]]; then
        sync_mode="force"
    elif [[ "$fetch_aws" == "true" ]]; then
        sync_mode="aws"
    elif [[ "$backup" == "true" ]]; then
        sync_mode="full"
    else
        sync_mode="basic"
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
    execute_sync_operation "$dry_run" "$force" "$fetch_aws" "$backup" "${env_names[@]}"
}

# 執行主函數
main "$@"