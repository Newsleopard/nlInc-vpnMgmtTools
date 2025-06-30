#!/bin/bash

# S3 CSR 交換桶設置工具 - 管理員專用
# 用途：創建和配置用於安全 CSR 交換的 S3 存儲桶
# 版本：1.0

# 全域變數
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARENT_DIR="$(dirname "$SCRIPT_DIR")"

# 載入新的 Profile Selector (替代 env_manager.sh)
source "$PARENT_DIR/lib/profile_selector.sh"

# 載入環境核心函式 (用於顯示功能)
source "$PARENT_DIR/lib/env_core.sh"

# 參數初始化
AWS_PROFILE=""
TARGET_ENVIRONMENT=""
BUCKET_NAME=""
AWS_REGION=""
CREATE_POLICIES=false
LIST_POLICIES=false
PUBLISH_ASSETS=false
CLEANUP_MODE=false
VERBOSE=false
SHOW_HELP=false

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -b|--bucket-name)
            BUCKET_NAME="$2"
            shift 2
            ;;
        -r|--region)
            AWS_REGION="$2"
            shift 2
            ;;
        -p|--profile)
            AWS_PROFILE="$2"
            shift 2
            ;;
        -e|--environment)
            TARGET_ENVIRONMENT="$2"
            shift 2
            ;;
        --create-policies)
            CREATE_POLICIES=true
            shift
            ;;
        --list-policies)
            LIST_POLICIES=true
            shift
            ;;
        --publish-assets)
            PUBLISH_ASSETS=true
            shift
            ;;
        --cleanup)
            CLEANUP_MODE=true
            shift
            ;;
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        -h|--help)
            SHOW_HELP=true
            shift
            ;;
        *)
            echo "未知參數: $1"
            echo "使用 --help 查看可用選項"
            exit 1
            ;;
    esac
done

# Show help if requested
if [[ "$SHOW_HELP" == true ]]; then
    cat << 'EOF'
S3 CSR 交換桶設置工具 - 管理員專用

用法: $0 [選項]

選項:
  -b, --bucket-name NAME     S3 存儲桶名稱 (預設: vpn-csr-exchange)
  -r, --region REGION        AWS 區域 (預設: us-east-1)
  -p, --profile PROFILE      AWS CLI profile
  -e, --environment ENV      目標環境 (staging|prod)
  --create-policies         創建 IAM 政策（不包含用戶管理）
  --list-policies           列出創建的 IAM 政策狀態
  --publish-assets          自動發布初始公用資產 (CA 證書和端點配置)
  --cleanup                 清理存儲桶和相關資源
  -v, --verbose             顯示詳細輸出
  -h, --help               顯示此幫助訊息

功能說明:
  此工具將創建一個 S3 存儲桶用於安全的 CSR 交換，包括：
  • 設置適當的存儲桶政策和權限
  • 創建用於 CSR 上傳和證書下載的前綴結構
  • 配置生命週期政策自動清理舊文件
  • 創建必要的 IAM 政策（用戶分配請使用 manage_vpn_users.sh）

範例:
  $0                                     # 互動式選擇 profile 和環境
  $0 -b my-vpn-csr-bucket               # 使用自定義存儲桶名稱
  $0 -e prod -p prod                     # 為 production 環境設置
  $0 --profile staging --create-policies # 只創建 staging 環境 IAM 政策
  $0 --environment prod --publish-assets  # 發布 production 資產

注意: 執行前請確保已正確設定環境和 AWS 憑證
EOF
    exit 0
fi

# Select and validate profile
if ! select_and_validate_profile --profile "$AWS_PROFILE" --environment "$TARGET_ENVIRONMENT"; then
    log_error "Profile 選擇失敗"
    exit 1
fi

# 設定預設值
BUCKET_NAME="${BUCKET_NAME:-vpn-csr-exchange}"
AWS_REGION="${AWS_REGION:-us-east-1}"

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

# 預設配置 (環境感知)
get_default_bucket_name() {
    # 使用環境和帳戶ID來確保存儲桶名稱唯一性
    local env_suffix=""
    if [[ -n "$SELECTED_ENVIRONMENT" ]]; then
        env_suffix="-${SELECTED_ENVIRONMENT}"
    fi
    
    # 如果有帳戶ID，使用它來確保唯一性
    if [[ -n "$ACCOUNT_ID" ]]; then
        echo "vpn-csr-exchange${env_suffix}-${ACCOUNT_ID}"
    else
        # 備用方案：使用隨機數
        local random_suffix=$(date +%s | tail -c 6)
        echo "vpn-csr-exchange${env_suffix}-${random_suffix}"
    fi
}

# VPN 管理員用戶列表 (環境感知)
if [[ "$SELECTED_ENVIRONMENT" == "staging" ]]; then
    VPN_ADMIN_USERS=(
        "ct"  # staging 環境使用小寫用戶名
        # 添加新管理員時，請在此處添加用戶名
    )
else
    VPN_ADMIN_USERS=(
        "CT"  # production 環境使用大寫用戶名
        # 添加新管理員時，請在此處添加用戶名
    )
fi

DEFAULT_BUCKET_NAME="$(get_default_bucket_name)"
DEFAULT_REGION="$AWS_REGION"

# 使用說明
show_usage() {
    echo "用法: $0 [選項]"
    echo ""
    echo "選項:"
    echo "  -b, --bucket-name NAME     S3 存儲桶名稱 (預設: $DEFAULT_BUCKET_NAME)"
    echo "  -r, --region REGION        AWS 區域 (預設: $DEFAULT_REGION)"
    echo "  -p, --profile PROFILE      AWS CLI profile (預設: 目前活躍的 profile)"
    echo "  -e, --environment ENV      目標環境 (staging/production)"
    echo "  --create-policies         創建 IAM 政策（不包含用戶管理）"
    echo "  --list-policies           列出創建的 IAM 政策狀態"
    echo "  --publish-assets          自動發布初始公用資產 (CA 證書和端點配置)"
    echo "  --cleanup                 清理存儲桶和相關資源"
    echo "  -v, --verbose             顯示詳細輸出"
    echo "  -h, --help               顯示此幫助訊息"
    echo ""
    echo "功能說明:"
    echo "  此工具將創建一個 S3 存儲桶用於安全的 CSR 交換，包括："
    echo "  • 設置適當的存儲桶政策和權限"
    echo "  • 創建用於 CSR 上傳和證書下載的前綴結構"
    echo "  • 配置生命週期政策自動清理舊文件"
    echo "  • 創建必要的 IAM 政策（用戶分配請使用 manage_vpn_users.sh）"
    echo ""
    echo "範例:"
    echo "  $0                                     # 使用預設設置創建存儲桶和政策"
    echo "  $0 -b my-vpn-csr-bucket               # 使用自定義存儲桶名稱"
    echo "  $0 -e production -p prod               # 為 production 環境設置"
    echo "  $0 --create-policies                  # 只創建 IAM 政策"
    echo "  $0 --publish-assets                   # 發布 CA 證書和端點配置"
    echo "  $0 --list-policies                    # 檢查政策狀態"
    echo "  $0 --cleanup                          # 清理資源"
    echo ""
    echo "用戶管理請使用:"
    echo "  ./admin-tools/manage_vpn_users.sh     # 專用的用戶管理工具"
}

# 記錄函數
log_message() {
    local message="$1"
    echo "$(date '+%Y-%m-%d %H:%M:%S'): $message" >> "$LOG_FILE"
    if [ "$VERBOSE" = true ]; then
        echo -e "${BLUE}[LOG]${NC} $message"
    fi
}

# 檢查 AWS CLI 配置
check_aws_config() {
    echo -e "${BLUE}檢查 AWS CLI 配置...${NC}"
    
    # 檢查 AWS CLI 是否安裝
    if ! command -v aws &> /dev/null; then
        echo -e "${RED}AWS CLI 未安裝${NC}"
        return 1
    fi
    
    # 檢查 AWS 憑證
    if ! aws sts get-caller-identity --profile "$AWS_PROFILE" &>/dev/null; then
        echo -e "${RED}AWS 憑證無效或未設置 (profile: $AWS_PROFILE)${NC}"
        return 1
    fi
    
    # 獲取帳戶資訊
    ACCOUNT_ID=$(aws sts get-caller-identity --profile "$AWS_PROFILE" --query 'Account' --output text)
    USER_ARN=$(aws sts get-caller-identity --profile "$AWS_PROFILE" --query 'Arn' --output text)
    
    # 如果存儲桶名稱是預設值，重新生成以包含帳戶ID
    if [[ "$BUCKET_NAME" == "vpn-csr-exchange" ]]; then
        BUCKET_NAME=$(get_default_bucket_name)
        echo -e "${BLUE}使用環境特定的存儲桶名稱: $BUCKET_NAME${NC}"
    fi
    
    echo -e "${GREEN}✓ AWS 配置有效${NC}"
    echo -e "${GREEN}✓ 帳戶 ID: $ACCOUNT_ID${NC}"
    echo -e "${GREEN}✓ 用戶: $USER_ARN${NC}"
    echo -e "${GREEN}✓ 存儲桶名稱: $BUCKET_NAME${NC}"
    
    return 0
}

# 創建 S3 存儲桶
create_s3_bucket() {
    echo -e "${BLUE}創建 S3 存儲桶...${NC}"
    
    # 檢查存儲桶是否已存在
    if aws_with_profile s3 ls "s3://$BUCKET_NAME" --profile "$AWS_PROFILE" &>/dev/null; then
        echo -e "${YELLOW}存儲桶已存在: $BUCKET_NAME${NC}"
        return 0
    fi
    
    # 創建存儲桶
    if [ "$REGION" = "us-east-1" ]; then
        # us-east-1 不需要 location constraint
        aws_with_profile s3 mb "s3://$BUCKET_NAME" --profile "$AWS_PROFILE"
    else
        aws_with_profile s3 mb "s3://$BUCKET_NAME" --region "$REGION" --profile "$AWS_PROFILE"
    fi
    
    if [ $? -ne 0 ]; then
        echo -e "${RED}創建存儲桶失敗${NC}"
        return 1
    fi
    
    echo -e "${GREEN}✓ 存儲桶已創建: $BUCKET_NAME${NC}"
    
    # 啟用版本控制
    aws_with_profile s3api put-bucket-versioning \
        --bucket "$BUCKET_NAME" \
        --versioning-configuration Status=Enabled \
        --profile "$AWS_PROFILE"
    
    echo -e "${GREEN}✓ 版本控制已啟用${NC}"
    
    # 設置預設加密
    aws_with_profile s3api put-bucket-encryption \
        --bucket "$BUCKET_NAME" \
        --server-side-encryption-configuration '{
            "Rules": [
                {
                    "ApplyServerSideEncryptionByDefault": {
                        "SSEAlgorithm": "AES256"
                    },
                    "BucketKeyEnabled": true
                }
            ]
        }' \
        --profile "$AWS_PROFILE"
    
    echo -e "${GREEN}✓ 預設加密已設置${NC}"
    
    return 0
}

# 設置存儲桶政策
setup_bucket_policy() {
    echo -e "${BLUE}設置存儲桶政策...${NC}"
    
    local policy_file="/tmp/bucket-policy-$$.json"
    
    # 構建管理員用戶 ARN 列表
    local admin_arns=""
    local first_admin=true
    
    # 構建管理員 ARN 陣列
    local admin_arns_array=()
    
    # 添加當前用戶 ARN
    admin_arns_array+=("\"$USER_ARN\"")
    
    # 添加配置的管理員用戶（避免重複，並驗證用戶存在）
    local current_user=$(echo "$USER_ARN" | sed 's/.*user\///')
    for admin in "${VPN_ADMIN_USERS[@]}"; do
        # 跳過當前用戶（避免重複）
        if [[ "$admin" != "$current_user" ]]; then
            # 檢查用戶是否存在（可選，為安全起見）
            if aws iam get-user --user-name "$admin" --profile "$AWS_PROFILE" &>/dev/null; then
                admin_arns_array+=("\"arn:aws:iam::$ACCOUNT_ID:user/$admin\"")
            else
                echo -e "${YELLOW}警告: 用戶 $admin 不存在，跳過${NC}"
            fi
        fi
    done
    
    # 使用 printf 正確格式化 JSON 陣列
    local admin_arns=""
    for i in "${!admin_arns_array[@]}"; do
        if [[ $i -eq 0 ]]; then
            admin_arns="${admin_arns_array[$i]}"
        else
            admin_arns="$admin_arns,
                    ${admin_arns_array[$i]}"
        fi
    done
    
    cat > "$policy_file" << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "AllowCSRUpload",
            "Effect": "Allow",
            "Principal": {
                "AWS": "arn:aws:iam::$ACCOUNT_ID:root"
            },
            "Action": "s3:PutObject",
            "Resource": "arn:aws:s3:::$BUCKET_NAME/csr/*",
            "Condition": {
                "StringEquals": {
                    "s3:x-amz-server-side-encryption": "AES256"
                }
            }
        },
        {
            "Sid": "AllowCertDownload",
            "Effect": "Allow",
            "Principal": {
                "AWS": "arn:aws:iam::$ACCOUNT_ID:root"
            },
            "Action": "s3:GetObject",
            "Resource": "arn:aws:s3:::$BUCKET_NAME/cert/*"
        },
        {
            "Sid": "AllowPublicAssetDownload",
            "Effect": "Allow",
            "Principal": {
                "AWS": "arn:aws:iam::$ACCOUNT_ID:root"
            },
            "Action": "s3:GetObject",
            "Resource": "arn:aws:s3:::$BUCKET_NAME/public/*"
        },
        {
            "Sid": "AllowAdminFullAccess",
            "Effect": "Allow",
            "Principal": {
                "AWS": [
                    $admin_arns
                ]
            },
            "Action": "s3:*",
            "Resource": [
                "arn:aws:s3:::$BUCKET_NAME",
                "arn:aws:s3:::$BUCKET_NAME/*"
            ]
        },
        {
            "Sid": "DenyUnencryptedUploads",
            "Effect": "Deny",
            "Principal": "*",
            "Action": "s3:PutObject",
            "Resource": "arn:aws:s3:::$BUCKET_NAME/*",
            "Condition": {
                "StringNotEquals": {
                    "s3:x-amz-server-side-encryption": "AES256"
                }
            }
        }
    ]
}
EOF
    
    # 驗證政策格式
    if [ "$VERBOSE" = true ]; then
        echo -e "${BLUE}生成的存儲桶政策：${NC}"
        cat "$policy_file"
        echo -e ""
    fi
    
    if aws s3api put-bucket-policy \
        --bucket "$BUCKET_NAME" \
        --policy "file://$policy_file" \
        --profile "$AWS_PROFILE"; then
        echo -e "${GREEN}✓ 存儲桶政策已設置${NC}"
    else
        echo -e "${RED}設置存儲桶政策失敗${NC}"
        echo -e "${YELLOW}政策內容：${NC}"
        cat "$policy_file"
        rm -f "$policy_file"
        return 1
    fi
    
    rm -f "$policy_file"
    return 0
}

# 創建文件夾結構
create_folder_structure() {
    echo -e "${BLUE}創建文件夾結構...${NC}"
    
    # 創建 csr/, cert/, 和 public/ 前綴
    # 使用臨時文件方式創建空對象
    local temp_file=$(mktemp)
    
    aws_with_profile s3 cp "$temp_file" "s3://$BUCKET_NAME/csr/.keep" --sse AES256 --profile "$AWS_PROFILE" 2>/dev/null || true
    aws_with_profile s3 cp "$temp_file" "s3://$BUCKET_NAME/cert/.keep" --sse AES256 --profile "$AWS_PROFILE" 2>/dev/null || true
    aws_with_profile s3 cp "$temp_file" "s3://$BUCKET_NAME/public/.keep" --sse AES256 --profile "$AWS_PROFILE" 2>/dev/null || true
    aws_with_profile s3 cp "$temp_file" "s3://$BUCKET_NAME/log/.keep" --sse AES256 --profile "$AWS_PROFILE" 2>/dev/null || true
    
    # 清理臨時文件
    rm -f "$temp_file"
    
    echo -e "${GREEN}✓ 文件夾結構已創建${NC}"
    echo -e "  📁 s3://$BUCKET_NAME/csr/    (CSR 上傳)"
    echo -e "  📁 s3://$BUCKET_NAME/cert/   (證書下載)"
    echo -e "  📁 s3://$BUCKET_NAME/public/ (公用資產)"
    echo -e "  📁 s3://$BUCKET_NAME/log/    (審計日誌)"
    
    return 0
}

# 設置生命週期政策
setup_lifecycle_policy() {
    echo -e "${BLUE}設置生命週期政策...${NC}"
    
    local lifecycle_file="/tmp/lifecycle-$$.json"
    
    cat > "$lifecycle_file" << EOF
{
    "Rules": [
        {
            "ID": "CleanupCSRFiles",
            "Status": "Enabled",
            "Filter": {
                "Prefix": "csr/"
            },
            "Expiration": {
                "Days": 30
            },
            "NoncurrentVersionExpiration": {
                "NoncurrentDays": 7
            }
        },
        {
            "ID": "CleanupCertFiles",
            "Status": "Enabled",
            "Filter": {
                "Prefix": "cert/"
            },
            "Expiration": {
                "Days": 7
            },
            "NoncurrentVersionExpiration": {
                "NoncurrentDays": 1
            }
        }
    ]
}
EOF
    
    if aws_with_profile s3api put-bucket-lifecycle-configuration \
        --bucket "$BUCKET_NAME" \
        --lifecycle-configuration "file://$lifecycle_file" \
        --profile "$AWS_PROFILE"; then
        echo -e "${GREEN}✓ 生命週期政策已設置${NC}"
        echo -e "  • CSR 文件 30 天後自動刪除"
        echo -e "  • 證書文件 7 天後自動刪除"
    else
        echo -e "${RED}設置生命週期政策失敗${NC}"
        rm -f "$lifecycle_file"
        return 1
    fi
    
    rm -f "$lifecycle_file"
    return 0
}

# 生成 IAM 政策範例
generate_iam_policies() {
    echo -e "${BLUE}生成 IAM 政策範例...${NC}"
    
    local policy_dir="$PARENT_DIR/iam-policies"
    mkdir -p "$policy_dir"
    
    # 團隊成員政策
    cat > "$policy_dir/team-member-csr-policy.json" << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "AllowCSRUpload",
            "Effect": "Allow",
            "Action": [
                "s3:PutObject",
                "s3:PutObjectAcl"
            ],
            "Resource": "arn:aws:s3:::$BUCKET_NAME/csr/\${aws:username}.csr",
            "Condition": {
                "StringEquals": {
                    "s3:x-amz-server-side-encryption": "AES256"
                }
            }
        },
        {
            "Sid": "AllowCertDownload",
            "Effect": "Allow",
            "Action": [
                "s3:GetObject"
            ],
            "Resource": "arn:aws:s3:::$BUCKET_NAME/cert/\${aws:username}.crt"
        }
    ]
}
EOF
    
    # 管理員政策
    cat > "$policy_dir/admin-csr-policy.json" << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "AllowFullCSRBucketAccess",
            "Effect": "Allow",
            "Action": [
                "s3:*"
            ],
            "Resource": [
                "arn:aws:s3:::$BUCKET_NAME",
                "arn:aws:s3:::$BUCKET_NAME/*"
            ]
        }
    ]
}
EOF
    
    echo -e "${GREEN}✓ IAM 政策範例已生成${NC}"
    echo -e "  📄 $policy_dir/team-member-csr-policy.json"
    echo -e "  📄 $policy_dir/admin-csr-policy.json"
    
    return 0
}

# 創建 IAM 用戶和政策
create_iam_resources() {
    echo -e "${BLUE}創建 IAM 資源...${NC}"
    
    # 創建團隊成員政策
    local policy_name="VPN-CSR-TeamMember-Policy"
    local admin_policy_name="VPN-CSR-Admin-Policy"
    
    # 檢查政策是否已存在
    if aws_with_profile iam get-policy --policy-arn "arn:aws:iam::$ACCOUNT_ID:policy/$policy_name" --profile "$AWS_PROFILE" &>/dev/null; then
        echo -e "${YELLOW}團隊成員政策已存在: $policy_name${NC}"
    else
        # 創建團隊成員政策
        aws_with_profile iam create-policy \
            --policy-name "$policy_name" \
            --policy-document "file://$PARENT_DIR/iam-policies/team-member-csr-policy.json" \
            --description "Allow team members to upload CSR and download certificates" \
            --profile "$AWS_PROFILE"
        
        if [ $? -eq 0 ]; then
            echo -e "${GREEN}✓ 團隊成員政策已創建: $policy_name${NC}"
        else
            echo -e "${RED}創建團隊成員政策失敗${NC}"
        fi
    fi
    
    # 檢查管理員政策是否已存在
    if aws_with_profile iam get-policy --policy-arn "arn:aws:iam::$ACCOUNT_ID:policy/$admin_policy_name" --profile "$AWS_PROFILE" &>/dev/null; then
        echo -e "${YELLOW}管理員政策已存在: $admin_policy_name${NC}"
    else
        # 創建管理員政策
        aws_with_profile iam create-policy \
            --policy-name "$admin_policy_name" \
            --policy-document "file://$PARENT_DIR/iam-policies/admin-csr-policy.json" \
            --description "Allow admin full access to CSR exchange bucket" \
            --profile "$AWS_PROFILE"
        
        if [ $? -eq 0 ]; then
            echo -e "${GREEN}✓ 管理員政策已創建: $admin_policy_name${NC}"
        else
            echo -e "${RED}創建管理員政策失敗${NC}"
        fi
    fi
    
    return 0
}

# 列出 IAM 政策狀態
list_iam_policies() {
    echo -e "${BLUE}檢查 IAM 政策狀態...${NC}"
    
    local team_policy_name="VPN-CSR-TeamMember-Policy"
    local admin_policy_name="VPN-CSR-Admin-Policy"
    local team_policy_arn="arn:aws:iam::$ACCOUNT_ID:policy/$team_policy_name"
    local admin_policy_arn="arn:aws:iam::$ACCOUNT_ID:policy/$admin_policy_name"
    
    echo -e "${CYAN}政策狀態檢查：${NC}"
    
    # 檢查團隊成員政策
    if check_policy_exists "$team_policy_name"; then
        echo -e "${GREEN}✓ $team_policy_name 已存在${NC}"
        local attachment_count
        attachment_count=$(aws_with_profile iam get-policy --policy-arn "$team_policy_arn" --profile "$AWS_PROFILE" --query 'Policy.AttachmentCount' --output text 2>/dev/null)
        echo -e "  附加到 $attachment_count 個實體"
    else
        echo -e "${RED}✗ $team_policy_name 不存在${NC}"
    fi
    
    # 檢查管理員政策
    if check_policy_exists "$admin_policy_name"; then
        echo -e "${GREEN}✓ $admin_policy_name 已存在${NC}"
        local attachment_count
        attachment_count=$(aws_with_profile iam get-policy --policy-arn "$admin_policy_arn" --profile "$AWS_PROFILE" --query 'Policy.AttachmentCount' --output text 2>/dev/null)
        echo -e "  附加到 $attachment_count 個實體"
    else
        echo -e "${RED}✗ $admin_policy_name 不存在${NC}"
    fi
    
    echo -e ""
    echo -e "${CYAN}政策文件位置：${NC}"
    echo -e "  📄 $PARENT_DIR/iam-policies/team-member-csr-policy.json"
    echo -e "  📄 $PARENT_DIR/iam-policies/admin-csr-policy.json"
    
    echo -e ""
    echo -e "${YELLOW}💡 用戶管理操作請使用：${NC}"
    echo -e "  ${CYAN}./admin-tools/manage_vpn_users.sh list${NC}      # 列出有權限的用戶"
    echo -e "  ${CYAN}./admin-tools/manage_vpn_users.sh add USER${NC}  # 為用戶分配權限"
    
    return 0
}

# 檢查政策是否存在
check_policy_exists() {
    local policy_name="$1"
    local policy_arn="arn:aws:iam::$ACCOUNT_ID:policy/$policy_name"
    
    if aws_with_profile iam get-policy --policy-arn "$policy_arn" --profile "$AWS_PROFILE" &>/dev/null; then
        return 0
    else
        return 1
    fi
}

# 清理資源
cleanup_resources() {
    echo -e "${YELLOW}警告: 這將刪除 S3 存儲桶和相關資源${NC}"
    read -p "確定要繼續嗎? (輸入 'DELETE' 確認): " confirmation
    
    if [ "$confirmation" != "DELETE" ]; then
        echo -e "${BLUE}取消清理操作${NC}"
        return 0
    fi
    
    echo -e "${BLUE}清理資源...${NC}"
    
    # 刪除存儲桶內容
    aws_with_profile s3 rm "s3://$BUCKET_NAME" --recursive --profile "$AWS_PROFILE"
    
    # 刪除存儲桶
    aws_with_profile s3 rb "s3://$BUCKET_NAME" --profile "$AWS_PROFILE"
    
    echo -e "${GREEN}✓ S3 存儲桶已刪除${NC}"
    
    # 可選：刪除 IAM 政策（謹慎操作）
    read -p "是否也要刪除 IAM 政策? (y/n): " delete_policies
    if [[ "$delete_policies" =~ ^[Yy]$ ]]; then
        aws_with_profile iam delete-policy --policy-arn "arn:aws:iam::$ACCOUNT_ID:policy/VPN-CSR-TeamMember-Policy" --profile "$AWS_PROFILE" 2>/dev/null
        aws_with_profile iam delete-policy --policy-arn "arn:aws:iam::$ACCOUNT_ID:policy/VPN-CSR-Admin-Policy" --profile "$AWS_PROFILE" 2>/dev/null
        echo -e "${GREEN}✓ IAM 政策已刪除${NC}"
    fi
    
    return 0
}

# 發布初始公用資產
publish_initial_assets() {
    echo -e "${BLUE}發布初始公用資產...${NC}"
    
    # 檢查是否有 publish_endpoints.sh 工具
    local publish_script="$SCRIPT_DIR/publish_endpoints.sh"
    if [ -x "$publish_script" ]; then
        echo -e "${BLUE}使用 publish_endpoints.sh 自動發布資產...${NC}"
        if "$publish_script" -b "$BUCKET_NAME" -p "$AWS_PROFILE" -e "$ENVIRONMENT" --force; then
            echo -e "${GREEN}✓ 初始資產發布完成${NC}"
            return 0
        else
            echo -e "${YELLOW}⚠ 自動發布失敗，需要手動發布${NC}"
        fi
    fi
    
    echo -e "${YELLOW}手動發布資產指示：${NC}"
    echo -e ""
    echo -e "${BLUE}1. 發布 CA 證書和端點配置：${NC}"
    echo -e "   ${CYAN}./admin-tools/publish_endpoints.sh -b $BUCKET_NAME${NC}"
    echo -e ""
    echo -e "${BLUE}2. 或使用以下命令手動上傳：${NC}"
    echo -e "   ${CYAN}# 上傳 CA 證書${NC}"
    echo -e "   ${CYAN}aws_with_profile s3 cp certs/ca.crt s3://$BUCKET_NAME/public/ca.crt --sse aws:kms${NC}"
    echo -e ""
    echo -e "   ${CYAN}# 創建並上傳端點配置 JSON${NC}"
    echo -e "   ${CYAN}# (參考 publish_endpoints.sh 中的格式)${NC}"
    echo -e ""
    
    return 0
}

# 顯示設置完成資訊
show_completion_info() {
    echo -e "\n${GREEN}=============================================${NC}"
    echo -e "${GREEN}    S3 CSR 交換桶設置完成！    ${NC}"
    echo -e "${GREEN}=============================================${NC}"
    echo -e ""
    echo -e "${CYAN}📋 設置摘要：${NC}"
    echo -e "  🪣 存儲桶名稱: ${YELLOW}$BUCKET_NAME${NC}"
    echo -e "  🌍 區域: ${YELLOW}$REGION${NC}"
    echo -e "  👤 AWS Profile: ${YELLOW}$AWS_PROFILE${NC}"
    echo -e "  📁 CSR 上傳路徑: ${CYAN}s3://$BUCKET_NAME/csr/${NC}"
    echo -e "  📁 證書下載路徑: ${CYAN}s3://$BUCKET_NAME/cert/${NC}"
    echo -e ""
    echo -e "${CYAN}📋 後續操作：${NC}"
    echo -e ""
    echo -e "${BLUE}1. 用戶管理（使用專用工具）：${NC}"
    echo -e "   ${CYAN}./admin-tools/manage_vpn_users.sh list${NC}        # 列出有 VPN 權限的用戶"
    echo -e "   ${CYAN}./admin-tools/manage_vpn_users.sh add USERNAME${NC}  # 為用戶分配 VPN 權限"
    echo -e ""
    
    if [ "$PUBLISH_ASSETS" = true ]; then
        echo -e "${BLUE}2. 零接觸工作流程已就緒：${NC}"
        echo -e "   ✅ 存儲桶已配置完成"
        echo -e "   ✅ 公用資產已發布 (或提供發布指示)"
        echo -e "   ✅ 團隊成員可直接使用零接觸模式"
        echo -e ""
        echo -e "${BLUE}3. 團隊成員使用方法：${NC}"
        echo -e "   ${CYAN}./team_member_setup.sh --init${NC}    # 初始化並生成 CSR"
        echo -e "   ${CYAN}# 等待管理員簽署證書${NC}"
        echo -e "   ${CYAN}./team_member_setup.sh --resume${NC}  # 下載證書並完成設置"
        echo -e ""
        echo -e "${BLUE}4. 管理員簽署流程：${NC}"
        echo -e "   ${CYAN}./admin-tools/sign_csr.sh --upload-s3 -e production user.csr${NC}"
        echo -e "   ${CYAN}# 或使用批次處理工具${NC}"
    else
        echo -e "${BLUE}2. 發布公用資產 (零接觸工作流程)：${NC}"
        echo -e "   ${CYAN}./admin-tools/setup_csr_s3_bucket.sh --publish-assets${NC}"
        echo -e "   ${CYAN}# 或者${NC}"
        echo -e "   ${CYAN}./admin-tools/publish_endpoints.sh -b $BUCKET_NAME${NC}"
        echo -e ""
        echo -e "${BLUE}3. 傳統 CSR 命令：${NC}"
        echo -e "   ${CYAN}aws_with_profile s3 cp user.csr s3://$BUCKET_NAME/csr/user.csr${NC}"
        echo -e "   ${CYAN}aws_with_profile s3 cp s3://$BUCKET_NAME/cert/user.crt user.crt${NC}"
    fi
    echo -e ""
    echo -e "${YELLOW}💡 安全提醒：${NC}"
    echo -e "• 定期檢查存儲桶內容和訪問日誌"
    echo -e "• 確保只有授權用戶擁有相關 IAM 政策"
    echo -e "• 生命週期政策會自動清理舊文件"
}

# 主函數
main() {
    # 預設值
    BUCKET_NAME="vpn-csr-exchange"  # 將在 check_aws_config 中重新生成
    REGION="$DEFAULT_REGION"
    # Get AWS profile from environment manager
    # AWS_PROFILE is already set from profile selection
    ENVIRONMENT=""
    CREATE_POLICIES=false
    LIST_POLICIES=false
    CLEANUP=false
    PUBLISH_ASSETS=false
    VERBOSE=false
    
    # 解析命令行參數
    while [[ $# -gt 0 ]]; do
        case $1 in
            -b|--bucket-name)
                BUCKET_NAME="$2"
                shift 2
                ;;
            -r|--region)
                REGION="$2"
                shift 2
                ;;
            -p|--profile)
                AWS_PROFILE="$2"
                shift 2
                ;;
            -e|--environment)
                ENVIRONMENT="$2"
                shift 2
                ;;
            --create-policies)
                CREATE_POLICIES=true
                shift
                ;;
            --list-policies)
                LIST_POLICIES=true
                shift
                ;;
            --publish-assets)
                PUBLISH_ASSETS=true
                shift
                ;;
            --cleanup)
                CLEANUP=true
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
    
    # 設置日誌文件
    LOG_FILE="$PARENT_DIR/logs/s3_setup.log"
    mkdir -p "$(dirname "$LOG_FILE")"
    
    echo -e "${CYAN}========================================${NC}"
    show_team_env_header "S3 CSR 交換桶設置工具"
    
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
        
        # 驗證 profile 匹配環境
        if validate_profile_account "$current_profile" "$SELECTED_ENVIRONMENT" 2>/dev/null; then
            echo -e "  狀態: ${GREEN}✓ 有效且匹配環境${NC}"
        else
            echo -e "  狀態: ${YELLOW}⚠ 有效但可能不匹配環境${NC}"
        fi
    else
        echo -e "${CYAN}AWS 配置狀態:${NC}"
        echo -e "  Profile: ${YELLOW}未設定${NC}"
    fi
    echo -e ""
    echo -e "${CYAN}========================================${NC}"
    echo -e ""
    
    # 檢查 AWS 配置
    if ! check_aws_config; then
        exit 1
    fi
    
    # 處理特殊操作
    if [ "$LIST_POLICIES" = true ]; then
        list_iam_policies
        exit 0
    fi
    
    if [ "$CLEANUP" = true ]; then
        cleanup_resources
        exit 0
    fi
    
    # 執行主要設置流程
    if ! create_s3_bucket; then
        exit 1
    fi
    
    if ! setup_bucket_policy; then
        exit 1
    fi
    
    if ! create_folder_structure; then
        exit 1
    fi
    
    if ! setup_lifecycle_policy; then
        exit 1
    fi
    
    if ! generate_iam_policies; then
        exit 1
    fi
    
    # 總是創建 IAM 政策（基礎設施的一部分）
    if ! create_iam_resources; then
        exit 1
    fi
    
    if [ "$PUBLISH_ASSETS" = true ]; then
        if ! publish_initial_assets; then
            echo -e "${YELLOW}⚠ 資產發布失敗，但存儲桶設置完成${NC}"
        fi
    fi
    
    show_completion_info
    
    log_message "S3 CSR 交換桶設置完成: $BUCKET_NAME"
    echo -e "${GREEN}設置完成！${NC}"
}

# 只有在腳本直接執行時才執行主程序
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi