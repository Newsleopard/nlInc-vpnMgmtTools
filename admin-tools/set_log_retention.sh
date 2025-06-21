#!/bin/bash
#
# 設定 CloudWatch Log Groups 保留期間腳本
# 用於為現有的 VPN Client 和其他相關 Log Groups 設定 30 天保留期間
#

# 載入核心函式庫
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARENT_DIR="$(dirname "$SCRIPT_DIR")"

# 載入環境和工具函式
source "$PARENT_DIR/lib/core_functions.sh"
source "$PARENT_DIR/lib/aws_setup.sh"

# 顏色定義
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# 預設值
DEFAULT_RETENTION_DAYS=30
DEFAULT_REGION="us-east-1"

# 顯示使用說明
show_usage() {
    echo "用法: $0 [選項]"
    echo ""
    echo "選項:"
    echo "  -r, --region REGION        AWS 區域 (預設: $DEFAULT_REGION)"
    echo "  -d, --days DAYS           保留天數 (預設: $DEFAULT_RETENTION_DAYS)"
    echo "  -p, --profile PROFILE     AWS CLI profile"
    echo "  --vpn-only               只處理 VPN 相關的 log groups"
    echo "  --lambda-only            只處理 Lambda 相關的 log groups"
    echo "  --dry-run                只顯示將要執行的操作，不實際執行"
    echo "  -v, --verbose            顯示詳細輸出"
    echo "  -h, --help              顯示此幫助訊息"
    echo ""
    echo "功能說明:"
    echo "  此工具會掃描並設定 CloudWatch Log Groups 的保留期間"
    echo "  主要針對 VPN Client 和 Lambda 相關的 log groups"
    echo ""
    echo "範例:"
    echo "  $0                                     # 設定所有相關 log groups 為 30 天保留"
    echo "  $0 --vpn-only                         # 只設定 VPN log groups"
    echo "  $0 -d 7 --lambda-only                # 設定 Lambda log groups 為 7 天保留"
    echo "  $0 --dry-run                          # 預覽模式，不實際執行"
}

# 記錄函數
log_message() {
    local message="$1"
    echo "$(date '+%Y-%m-%d %H:%M:%S'): $message" >> "$PARENT_DIR/logs/log_retention_$(date +%Y%m%d).log"
    if [ "$VERBOSE" = true ]; then
        echo -e "${BLUE}[LOG]${NC} $message"
    fi
}

# 檢查 AWS CLI 配置
check_aws_config() {
    echo -e "${BLUE}檢查 AWS CLI 配置...${NC}"
    
    if ! command -v aws &> /dev/null; then
        echo -e "${RED}AWS CLI 未安裝${NC}"
        return 1
    fi
    
    if ! aws_with_profile sts get-caller-identity --profile "$AWS_PROFILE" &>/dev/null; then
        echo -e "${RED}AWS 認證失敗或 profile '$AWS_PROFILE' 無效${NC}"
        return 1
    fi
    
    echo -e "${GREEN}✓ AWS 配置有效${NC}"
    return 0
}

# 獲取指定類型的 log groups
get_log_groups() {
    local filter_type="$1"
    local log_groups=""
    
    case "$filter_type" in
        "vpn")
            log_groups=$(aws_with_profile logs describe-log-groups \
                --region "$REGION" \
                --log-group-name-prefix "/aws/clientvpn/" \
                --query 'logGroups[].{LogGroupName:logGroupName,RetentionInDays:retentionInDays}' \
                --output json 2>/dev/null)
            ;;
        "lambda")
            log_groups=$(aws_with_profile logs describe-log-groups \
                --region "$REGION" \
                --log-group-name-prefix "/aws/lambda/" \
                --query 'logGroups[].{LogGroupName:logGroupName,RetentionInDays:retentionInDays}' \
                --output json 2>/dev/null)
            ;;
        "all")
            # 獲取所有相關的 log groups
            local vpn_groups lambda_groups
            vpn_groups=$(aws_with_profile logs describe-log-groups \
                --region "$REGION" \
                --log-group-name-prefix "/aws/clientvpn/" \
                --query 'logGroups[].{LogGroupName:logGroupName,RetentionInDays:retentionInDays}' \
                --output json 2>/dev/null)
            lambda_groups=$(aws_with_profile logs describe-log-groups \
                --region "$REGION" \
                --log-group-name-prefix "/aws/lambda/" \
                --query 'logGroups[].{LogGroupName:logGroupName,RetentionInDays:retentionInDays}' \
                --output json 2>/dev/null)
            
            # 合併結果
            if [ "$vpn_groups" != "[]" ] && [ "$lambda_groups" != "[]" ]; then
                log_groups=$(echo "$vpn_groups $lambda_groups" | jq -s 'add')
            elif [ "$vpn_groups" != "[]" ]; then
                log_groups="$vpn_groups"
            elif [ "$lambda_groups" != "[]" ]; then
                log_groups="$lambda_groups"
            else
                log_groups="[]"
            fi
            ;;
    esac
    
    echo "$log_groups"
}

# 設定單個 log group 的保留期間
set_retention_for_log_group() {
    local log_group_name="$1"
    local current_retention="$2"
    local target_retention="$3"
    local dry_run="$4"
    
    # 檢查是否需要更新
    if [ "$current_retention" = "null" ] || [ -z "$current_retention" ]; then
        current_retention="永久"
        needs_update=true
    elif [ "$current_retention" != "$target_retention" ]; then
        needs_update=true
    else
        needs_update=false
    fi
    
    if [ "$needs_update" = true ]; then
        echo -e "${YELLOW}Log Group: $log_group_name${NC}"
        echo -e "  當前保留期間: $current_retention"
        echo -e "  目標保留期間: $target_retention 天"
        
        if [ "$dry_run" = true ]; then
            echo -e "  ${CYAN}[DRY RUN] 將會執行: aws logs put-retention-policy --log-group-name '$log_group_name' --retention-in-days $target_retention${NC}"
            return 0
        fi
        
        # 實際執行設定
        if aws_with_profile logs put-retention-policy \
            --log-group-name "$log_group_name" \
            --retention-in-days "$target_retention" \
            --region "$REGION" \
            --profile "$AWS_PROFILE" 2>/dev/null; then
            echo -e "  ${GREEN}✓ 保留期間設定成功${NC}"
            log_message "保留期間設定成功: $log_group_name -> $target_retention 天"
            return 0
        else
            echo -e "  ${RED}✗ 保留期間設定失敗${NC}"
            log_message "保留期間設定失敗: $log_group_name"
            return 1
        fi
    else
        if [ "$VERBOSE" = true ]; then
            echo -e "${GREEN}✓ $log_group_name (已設定為 $current_retention 天)${NC}"
        fi
        return 0
    fi
}

# 主要處理函數
process_log_groups() {
    local filter_type="$1"
    local retention_days="$2"
    local dry_run="$3"
    
    echo -e "${BLUE}獲取 Log Groups 清單...${NC}"
    local log_groups_json
    log_groups_json=$(get_log_groups "$filter_type")
    
    if [ "$log_groups_json" = "[]" ] || [ -z "$log_groups_json" ]; then
        echo -e "${YELLOW}未找到符合條件的 Log Groups${NC}"
        return 0
    fi
    
    local total_count success_count=0 failed_count=0
    total_count=$(echo "$log_groups_json" | jq length)
    
    echo -e "${CYAN}找到 $total_count 個 Log Groups${NC}"
    echo ""
    
    if [ "$dry_run" = true ]; then
        echo -e "${CYAN}=== DRY RUN 模式 - 預覽將要執行的操作 ===${NC}"
    fi
    
    # 處理每個 log group
    echo "$log_groups_json" | jq -c '.[]' | while read -r log_group; do
        local log_group_name current_retention
        log_group_name=$(echo "$log_group" | jq -r '.LogGroupName')
        current_retention=$(echo "$log_group" | jq -r '.RetentionInDays')
        
        if set_retention_for_log_group "$log_group_name" "$current_retention" "$retention_days" "$dry_run"; then
            ((success_count++))
        else
            ((failed_count++))
        fi
        echo ""
    done
    
    # 顯示摘要
    echo -e "${CYAN}=== 操作摘要 ===${NC}"
    echo -e "總計 Log Groups: $total_count"
    if [ "$dry_run" != true ]; then
        echo -e "成功設定: $success_count"
        echo -e "設定失敗: $failed_count"
    else
        echo -e "${CYAN}預覽模式完成，未實際執行任何變更${NC}"
    fi
}

# 主函數
main() {
    # 預設值
    REGION="$DEFAULT_REGION"
    RETENTION_DAYS="$DEFAULT_RETENTION_DAYS"
    AWS_PROFILE="default"
    FILTER_TYPE="all"
    DRY_RUN=false
    VERBOSE=false
    
    # 解析命令列參數
    while [[ $# -gt 0 ]]; do
        case $1 in
            -r|--region)
                REGION="$2"
                shift 2
                ;;
            -d|--days)
                RETENTION_DAYS="$2"
                shift 2
                ;;
            -p|--profile)
                AWS_PROFILE="$2"
                shift 2
                ;;
            --vpn-only)
                FILTER_TYPE="vpn"
                shift
                ;;
            --lambda-only)
                FILTER_TYPE="lambda"
                shift
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            -h|--help)
                show_usage
                exit 0
                ;;
            *)
                echo -e "${RED}未知參數: $1${NC}"
                show_usage
                exit 1
                ;;
        esac
    done
    
    # 驗證參數
    if ! [[ "$RETENTION_DAYS" =~ ^[0-9]+$ ]] || [ "$RETENTION_DAYS" -lt 1 ]; then
        echo -e "${RED}無效的保留天數: $RETENTION_DAYS${NC}"
        exit 1
    fi
    
    # 顯示配置資訊
    echo -e "${CYAN}=== CloudWatch Log Groups 保留期間設定工具 ===${NC}"
    echo ""
    echo -e "${BLUE}配置資訊:${NC}"
    echo -e "  AWS Profile: $AWS_PROFILE"
    echo -e "  區域: $REGION"
    echo -e "  保留天數: $RETENTION_DAYS"
    echo -e "  處理類型: $FILTER_TYPE"
    if [ "$DRY_RUN" = true ]; then
        echo -e "  ${CYAN}模式: 預覽模式 (不實際執行)${NC}"
    fi
    echo ""
    
    # 檢查前置條件
    if ! check_aws_config; then
        exit 1
    fi
    
    echo ""
    
    # 執行主要處理
    process_log_groups "$FILTER_TYPE" "$RETENTION_DAYS" "$DRY_RUN"
    
    log_message "Log Groups 保留期間設定完成"
}

# 只有在腳本直接執行時才執行主程序
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
