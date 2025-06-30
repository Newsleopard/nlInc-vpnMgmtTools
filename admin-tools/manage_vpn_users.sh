#!/bin/bash

# VPN 用戶管理工具 - 管理員專用
# 用途：統一管理 VPN 用戶權限和證書
# 版本：1.0

# 全域變數
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARENT_DIR="$(dirname "$SCRIPT_DIR")"

# Check for help first before environment initialization
for arg in "$@"; do
    if [[ "$arg" == "-h" || "$arg" == "--help" ]]; then
        cat << 'EOF'
用法: $0 [選項] [動作]

動作:
  add USERNAME              添加新用戶並分配 VPN 權限
  remove USERNAME           移除用戶的 VPN 權限
  list                      列出所有有 VPN 權限的用戶
  status USERNAME           查看用戶權限狀態
  batch-add FILE            從文件批量添加用戶
  check-permissions USER    檢查用戶的 S3 權限

選項:
  -e, --environment ENV     目標環境 (staging/production)
  -p, --profile PROFILE     AWS CLI profile
  -b, --bucket-name NAME    S3 存儲桶名稱 (預設: vpn-csr-exchange)
  --create-user             如果用戶不存在則自動創建
  --dry-run                 顯示將要執行的操作但不實際執行
  -v, --verbose             顯示詳細輸出
  -h, --help               顯示此幫助訊息

範例:
  $0 add john                     # 添加用戶 john
  $0 add jane --create-user       # 添加用戶 jane，如不存在則創建
  $0 remove old-employee          # 移除用戶權限
  $0 list                         # 列出所有用戶
  $0 status john                  # 查看用戶狀態
  $0 check-permissions john       # 檢查用戶權限

注意: 執行前請確保已正確設定環境和 AWS 憑證
EOF
        exit 0
    fi
done

# 載入新的 Profile Selector (替代 env_manager.sh)
source "$PARENT_DIR/lib/profile_selector.sh"

# 載入環境核心函式 (用於顯示功能)
source "$PARENT_DIR/lib/env_core.sh"

# 參數初始化
AWS_PROFILE=""
TARGET_ENVIRONMENT=""
BUCKET_NAME=""
ACTION=""
USERNAME=""
CREATE_USER=false
DRY_RUN=false

# Parse command line arguments for profile selection only, preserve others
REMAINING_ARGS=()
while [[ $# -gt 0 ]]; do
    case $1 in
        -e|--environment)
            TARGET_ENVIRONMENT="$2"
            shift 2
            ;;
        -p|--profile)
            AWS_PROFILE="$2"
            shift 2
            ;;
        *)
            # Preserve all other arguments for original script logic
            REMAINING_ARGS+=("$1")
            shift
            ;;
    esac
done

# Restore remaining arguments for original script parsing
set -- "${REMAINING_ARGS[@]}"

# Select and validate profile
if ! select_and_validate_profile --profile "$AWS_PROFILE" --environment "$TARGET_ENVIRONMENT"; then
    log_error "Profile 選擇失敗"
    exit 1
fi

# 設定預設值
BUCKET_NAME="${BUCKET_NAME:-vpn-csr-exchange}"

# 載入核心函式庫
source "$PARENT_DIR/lib/core_functions.sh"

# 執行兼容性檢查
check_macos_compatibility

# 顏色定義
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# 預設配置
DEFAULT_BUCKET_NAME="vpn-csr-exchange"
POLICY_NAME="VPN-CSR-TeamMember-Policy"

# 使用說明
show_usage() {
    echo "用法: $0 [選項] [動作]"
    echo ""
    echo "動作:"
    echo "  add USERNAME              添加新用戶並分配 VPN 權限"
    echo "  remove USERNAME           移除用戶的 VPN 權限"
    echo "  list                      列出所有有 VPN 權限的用戶"
    echo "  status USERNAME           查看用戶權限狀態"
    echo "  batch-add FILE            從文件批量添加用戶"
    echo "  check-permissions USER    檢查用戶的 S3 權限"
    echo ""
    echo "選項:"
    echo "  -e, --environment ENV     目標環境 (staging/production)"
    echo "  -p, --profile PROFILE     AWS CLI profile"
    echo "  -b, --bucket-name NAME    S3 存儲桶名稱 (預設: $DEFAULT_BUCKET_NAME)"
    echo "  --create-user             如果用戶不存在則自動創建"
    echo "  --dry-run                 顯示將要執行的操作但不實際執行"
    echo "  -v, --verbose             顯示詳細輸出"
    echo "  -h, --help               顯示此幫助訊息"
    echo ""
    echo "範例:"
    echo "  $0 add john                     # 添加用戶 john"
    echo "  $0 add jane --create-user       # 添加用戶 jane，如不存在則創建"
    echo "  $0 remove old-employee          # 移除用戶權限"
    echo "  $0 list                         # 列出所有用戶"
    echo "  $0 status john                  # 查看用戶狀態"
    echo "  $0 check-permissions john       # 檢查用戶權限"
    echo "  $0 batch-add users.txt          # 批量添加用戶"
    echo ""
    echo "注意："
    echo "  此工具專注於用戶管理。如需設置 S3 bucket 和基礎設施，請使用："
    echo "  ./admin-tools/setup_csr_s3_bucket.sh"
}

# 記錄函數
log_message() {
    local message="$1"
    echo "$(date '+%Y-%m-%d %H:%M:%S'): $message" >> "$LOG_FILE"
    if [ "$VERBOSE" = true ]; then
        echo -e "${BLUE}[LOG]${NC} $message"
    fi
}

# 檢查 AWS 配置
check_aws_config() {
    echo -e "${BLUE}檢查 AWS CLI 配置...${NC}"
    
    if ! command -v aws &> /dev/null; then
        echo -e "${RED}AWS CLI 未安裝${NC}"
        return 1
    fi
    
    if ! aws_with_profile sts get-caller-identity --profile "$AWS_PROFILE" &>/dev/null; then
        echo -e "${RED}AWS 憑證無效或未設置 (profile: $AWS_PROFILE)${NC}"
        return 1
    fi
    
    ACCOUNT_ID=$(aws_with_profile sts get-caller-identity --profile "$AWS_PROFILE" --query 'Account' --output text)
    USER_ARN=$(aws_with_profile sts get-caller-identity --profile "$AWS_PROFILE" --query 'Arn' --output text)
    
    echo -e "${GREEN}✓ AWS 配置有效${NC}"
    echo -e "${GREEN}✓ 帳戶 ID: $ACCOUNT_ID${NC}"
    echo -e "${GREEN}✓ 用戶: $USER_ARN${NC}"
    
    return 0
}

# 檢查用戶是否存在
check_user_exists() {
    local username="$1"
    
    if aws_with_profile iam get-user --user-name "$username" --profile "$AWS_PROFILE" &>/dev/null; then
        return 0
    else
        return 1
    fi
}

# 檢查政策是否存在
check_policy_exists() {
    local policy_arn="arn:aws:iam::$ACCOUNT_ID:policy/$POLICY_NAME"
    
    if aws_with_profile iam get-policy --policy-arn "$policy_arn" --profile "$AWS_PROFILE" &>/dev/null; then
        return 0
    else
        return 1
    fi
}

# 確保 IAM 政策存在
ensure_policies_exist() {
    if ! check_policy_exists; then
        echo -e "${YELLOW}VPN 政策不存在，正在創建基礎設施...${NC}"
        echo -e "${BLUE}執行: ./admin-tools/setup_csr_s3_bucket.sh --create-policies${NC}"
        
        if "$SCRIPT_DIR/setup_csr_s3_bucket.sh" --create-policies; then
            echo -e "${GREEN}✓ IAM 政策創建完成${NC}"
        else
            echo -e "${RED}創建 IAM 政策失敗${NC}"
            echo -e "${YELLOW}請先執行基礎設施設置：${NC}"
            echo -e "${CYAN}./admin-tools/setup_csr_s3_bucket.sh${NC}"
            return 1
        fi
    fi
    return 0
}

# 檢查用戶是否擁有 VPN 政策
check_user_has_policy() {
    local username="$1"
    
    if aws_with_profile iam list-attached-user-policies --user-name "$username" --profile "$AWS_PROFILE" --query "AttachedPolicies[?PolicyName=='$POLICY_NAME']" --output text | grep -q "$POLICY_NAME"; then
        return 0
    else
        return 1
    fi
}

# 添加用戶 VPN 權限
add_user_vpn_access() {
    local username="$1"
    local policy_arn="arn:aws:iam::$ACCOUNT_ID:policy/$POLICY_NAME"
    
    echo -e "${BLUE}為用戶 '$username' 添加 VPN 權限...${NC}"
    
    # 確保政策存在
    if ! ensure_policies_exist; then
        return 1
    fi
    
    # 檢查用戶是否存在
    if ! check_user_exists "$username"; then
        if [ "$CREATE_USER" = true ]; then
            echo -e "${BLUE}創建用戶 '$username'...${NC}"
            if [ "$DRY_RUN" = true ]; then
                echo -e "${YELLOW}[DRY RUN] 將執行: aws iam create-user --user-name $username${NC}"
            else
                if aws_with_profile iam create-user --user-name "$username" --profile "$AWS_PROFILE"; then
                    echo -e "${GREEN}✓ 用戶 '$username' 創建成功${NC}"
                    log_message "創建用戶: $username"
                else
                    echo -e "${RED}創建用戶失敗${NC}"
                    return 1
                fi
            fi
        else
            echo -e "${RED}錯誤: 用戶 '$username' 不存在，使用 --create-user 選項自動創建${NC}"
            return 1
        fi
    fi
    
    # 檢查用戶是否已擁有政策
    if check_user_has_policy "$username"; then
        echo -e "${YELLOW}用戶 '$username' 已擁有 VPN 權限${NC}"
        return 0
    fi
    
    # 附加政策
    echo -e "${BLUE}附加 VPN 政策到用戶 '$username'...${NC}"
    if [ "$DRY_RUN" = true ]; then
        echo -e "${YELLOW}[DRY RUN] 將執行: aws iam attach-user-policy --user-name $username --policy-arn $policy_arn${NC}"
    else
        if aws_with_profile iam attach-user-policy \
            --user-name "$username" \
            --policy-arn "$policy_arn" \
            --profile "$AWS_PROFILE"; then
            echo -e "${GREEN}✓ 成功為用戶 '$username' 添加 VPN 權限${NC}"
            log_message "為用戶添加 VPN 權限: $username"
            return 0
        else
            echo -e "${RED}附加政策失敗${NC}"
            return 1
        fi
    fi
}

# 移除用戶 VPN 權限
remove_user_vpn_access() {
    local username="$1"
    local policy_arn="arn:aws:iam::$ACCOUNT_ID:policy/$POLICY_NAME"
    
    echo -e "${BLUE}從用戶 '$username' 移除 VPN 權限...${NC}"
    
    # 檢查用戶是否存在
    if ! check_user_exists "$username"; then
        echo -e "${RED}錯誤: 用戶 '$username' 不存在${NC}"
        return 1
    fi
    
    # 檢查用戶是否擁有政策
    if ! check_user_has_policy "$username"; then
        echo -e "${YELLOW}用戶 '$username' 未擁有 VPN 權限${NC}"
        return 0
    fi
    
    # 移除政策
    if [ "$DRY_RUN" = true ]; then
        echo -e "${YELLOW}[DRY RUN] 將執行: aws iam detach-user-policy --user-name $username --policy-arn $policy_arn${NC}"
    else
        if aws_with_profile iam detach-user-policy \
            --user-name "$username" \
            --policy-arn "$policy_arn" \
            --profile "$AWS_PROFILE"; then
            echo -e "${GREEN}✓ 成功從用戶 '$username' 移除 VPN 權限${NC}"
            log_message "從用戶移除 VPN 權限: $username"
            return 0
        else
            echo -e "${RED}移除政策失敗${NC}"
            return 1
        fi
    fi
}

# 列出所有有 VPN 權限的用戶
list_vpn_users() {
    echo -e "${BLUE}列出所有擁有 VPN 權限的用戶...${NC}"
    
    local policy_arn="arn:aws:iam::$ACCOUNT_ID:policy/$POLICY_NAME"
    
    if ! check_policy_exists; then
        echo -e "${YELLOW}VPN 政策不存在${NC}"
        return 0
    fi
    
    echo -e "${CYAN}擁有 VPN 權限的用戶：${NC}"
    local users
    users=$(aws_with_profile iam list-entities-for-policy \
        --policy-arn "$policy_arn" \
        --query 'PolicyUsers[].UserName' \
        --output text \
        --profile "$AWS_PROFILE" 2>/dev/null)
    
    if [ -n "$users" ] && [ "$users" != "None" ]; then
        echo -e "${GREEN}找到以下用戶：${NC}"
        echo -e "${CYAN}用戶名${NC}            ${CYAN}創建時間${NC}                ${CYAN}最後活動${NC}"
        echo "----------------------------------------"
        
        for user in $users; do
            # 獲取用戶詳細信息
            local user_info
            user_info=$(aws_with_profile iam get-user --user-name "$user" --profile "$AWS_PROFILE" --output json 2>/dev/null)
            if [ $? -eq 0 ]; then
                local create_date
                create_date=$(echo "$user_info" | jq -r '.User.CreateDate' | cut -d'T' -f1)
                
                # 獲取最後使用時間
                local last_used
                last_used=$(aws_with_profile iam get-user --user-name "$user" --profile "$AWS_PROFILE" --query 'User.PasswordLastUsed' --output text 2>/dev/null || echo "N/A")
                if [ "$last_used" = "None" ] || [ "$last_used" = "null" ]; then
                    last_used="從未使用"
                else
                    last_used=$(echo "$last_used" | cut -d'T' -f1)
                fi
                
                printf "  ✓ %-15s %-20s %s\n" "$user" "$create_date" "$last_used"
            else
                echo -e "  ✓ $user (無法獲取詳細信息)"
            fi
        done
    else
        echo -e "${YELLOW}沒有用戶擁有 VPN 權限${NC}"
    fi
    
    return 0
}

# 查看用戶狀態
show_user_status() {
    local username="$1"
    
    echo -e "${BLUE}查看用戶 '$username' 狀態...${NC}"
    
    # 檢查用戶是否存在
    if ! check_user_exists "$username"; then
        echo -e "${RED}✗ 用戶 '$username' 不存在${NC}"
        return 1
    fi
    
    echo -e "${GREEN}✓ 用戶存在${NC}"
    
    # 獲取用戶基本信息
    local user_info
    user_info=$(aws_with_profile iam get-user --user-name "$username" --profile "$AWS_PROFILE" --output json 2>/dev/null)
    if [ $? -eq 0 ]; then
        local create_date arn user_id
        create_date=$(echo "$user_info" | jq -r '.User.CreateDate')
        arn=$(echo "$user_info" | jq -r '.User.Arn')
        user_id=$(echo "$user_info" | jq -r '.User.UserId')
        
        echo -e "${CYAN}用戶詳細信息：${NC}"
        echo -e "  ARN: $arn"
        echo -e "  用戶 ID: $user_id"
        echo -e "  創建時間: $create_date"
    fi
    
    # 檢查 VPN 權限
    if check_user_has_policy "$username"; then
        echo -e "${GREEN}✓ 擁有 VPN 權限${NC}"
    else
        echo -e "${YELLOW}✗ 未擁有 VPN 權限${NC}"
    fi
    
    # 列出所有附加的政策
    echo -e "${CYAN}附加的政策：${NC}"
    aws_with_profile iam list-attached-user-policies --user-name "$username" --profile "$AWS_PROFILE" --query 'AttachedPolicies[].PolicyName' --output table 2>/dev/null || echo "  無附加政策"
    
    return 0
}

# 檢查用戶 S3 權限
check_user_s3_permissions() {
    local username="$1"
    
    echo -e "${BLUE}檢查用戶 '$username' 的 S3 權限...${NC}"
    
    if ! check_user_exists "$username"; then
        echo -e "${RED}✗ 用戶 '$username' 不存在${NC}"
        return 1
    fi
    
    echo -e "${CYAN}測試 S3 權限：${NC}"
    
    # 測試 CSR 上傳權限
    echo -e "  測試 CSR 上傳權限..."
    local test_result
    test_result=$(aws_with_profile s3api put-object-acl --bucket "$BUCKET_NAME" --key "csr/test-${username}.csr" --profile "$username" 2>&1 || echo "FAILED")
    if [[ "$test_result" != *"FAILED"* ]]; then
        echo -e "${GREEN}  ✓ CSR 上傳權限正常${NC}"
    else
        echo -e "${RED}  ✗ CSR 上傳權限失敗${NC}"
        echo -e "    錯誤: $test_result"
    fi
    
    # 測試證書下載權限
    echo -e "  測試證書下載權限..."
    test_result=$(aws_with_profile s3api head-object --bucket "$BUCKET_NAME" --key "cert/test-${username}.crt" --profile "$username" 2>&1 || echo "FAILED")
    if [[ "$test_result" != *"FAILED"* ]]; then
        echo -e "${GREEN}  ✓ 證書下載權限正常${NC}"
    else
        echo -e "${YELLOW}  ? 證書下載權限測試 (文件可能不存在)${NC}"
    fi
    
    return 0
}

# 批量添加用戶
batch_add_users() {
    local file="$1"
    
    if [ ! -f "$file" ]; then
        echo -e "${RED}錯誤: 文件 '$file' 不存在${NC}"
        return 1
    fi
    
    echo -e "${BLUE}從文件 '$file' 批量添加用戶...${NC}"
    
    local success_count=0
    local fail_count=0
    local line_number=0
    
    while IFS= read -r line || [ -n "$line" ]; do
        line_number=$((line_number + 1))
        
        # 跳過空行和註釋行
        if [[ -z "$line" ]] || [[ "$line" =~ ^[[:space:]]*# ]]; then
            continue
        fi
        
        # 提取用戶名 (第一個字段)
        local username
        username=$(echo "$line" | awk '{print $1}')
        
        if [ -n "$username" ]; then
            echo -e "\n${CYAN}處理用戶: $username (行 $line_number)${NC}"
            if add_user_vpn_access "$username"; then
                success_count=$((success_count + 1))
            else
                fail_count=$((fail_count + 1))
            fi
        else
            echo -e "${YELLOW}跳過無效行 $line_number: $line${NC}"
        fi
    done < "$file"
    
    echo -e "\n${CYAN}批量處理完成：${NC}"
    echo -e "${GREEN}  成功: $success_count 個用戶${NC}"
    echo -e "${RED}  失敗: $fail_count 個用戶${NC}"
    
    return 0
}

# 主函數
main() {
    # 預設值
    BUCKET_NAME="$DEFAULT_BUCKET_NAME"
    # Get AWS profile from environment manager
    # AWS_PROFILE is already set from profile selection
    ENVIRONMENT=""
    CREATE_USER=false
    DRY_RUN=false
    VERBOSE=false
    ACTION=""
    TARGET_USER=""
    
    # 解析命令行參數
    while [[ $# -gt 0 ]]; do
        case $1 in
            add|remove|list|status|batch-add|check-permissions)
                ACTION="$1"
                if [[ "$1" != "list" ]]; then
                    TARGET_USER="$2"
                    shift
                fi
                shift
                ;;
            -e|--environment)
                ENVIRONMENT="$2"
                shift 2
                ;;
            -p|--profile)
                AWS_PROFILE="$2"
                shift 2
                ;;
            -b|--bucket-name)
                BUCKET_NAME="$2"
                shift 2
                ;;
            --create-user)
                CREATE_USER=true
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
    
    # 檢查必要參數
    if [ -z "$ACTION" ]; then
        echo -e "${RED}錯誤: 必須指定動作${NC}"
        show_usage
        exit 1
    fi
    
    if [[ "$ACTION" != "list" ]] && [ -z "$TARGET_USER" ]; then
        echo -e "${RED}錯誤: 動作 '$ACTION' 需要指定用戶名${NC}"
        show_usage
        exit 1
    fi
    
    # 設置日誌文件
    LOG_FILE="$PARENT_DIR/logs/user_management.log"
    mkdir -p "$(dirname "$LOG_FILE")"
    
    echo -e "${CYAN}========================================${NC}"
    show_team_env_header "VPN 用戶管理工具"
    
    # 顯示 AWS Profile 資訊
    local current_profile
    current_profile="$SELECTED_AWS_PROFILE"
    if [[ -n "$current_profile" ]]; then
        local account_id region
        account_id=$(aws_with_profile sts get-caller-identity --query Account --output text 2>/dev/null)
        region=$(aws_with_profile configure get region 2>/dev/null)
        
        echo -e "${CYAN}AWS 配置狀態:${NC}"
        echo -e "  Profile: ${GREEN}$current_profile${NC}"
        if [[ -n "$account_id" ]]; then
            echo -e "  帳戶 ID: ${account_id}"
        fi
        if [[ -n "$region" ]]; then
            echo -e "  區域: ${region}"
        fi
    fi
    echo -e "${CYAN}========================================${NC}"
    echo -e ""
    
    # 檢查 AWS 配置
    if ! check_aws_config; then
        exit 1
    fi
    
    # 執行指定動作
    case "$ACTION" in
        add)
            add_user_vpn_access "$TARGET_USER"
            ;;
        remove)
            remove_user_vpn_access "$TARGET_USER"
            ;;
        list)
            list_vpn_users
            ;;
        status)
            show_user_status "$TARGET_USER"
            ;;
        batch-add)
            batch_add_users "$TARGET_USER"
            ;;
        check-permissions)
            check_user_s3_permissions "$TARGET_USER"
            ;;
        *)
            echo -e "${RED}未知動作: $ACTION${NC}"
            show_usage
            exit 1
            ;;
    esac
    
    log_message "用戶管理操作完成: $ACTION $TARGET_USER"
}

# 只有在腳本直接執行時才執行主程序
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi