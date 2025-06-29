#!/bin/bash

# CSR 簽署工具 - 管理員專用
# 用途：安全地簽署團隊成員的 CSR，保持 CA 私鑰隔離
# 版本：1.0

# 全域變數
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARENT_DIR="$(dirname "$SCRIPT_DIR")"

# Check for help first before environment initialization
for arg in "$@"; do
    if [[ "$arg" == "-h" || "$arg" == "--help" ]]; then
        cat << 'EOF'
用法: $0 [選項] <csr-file> [days-valid] [output-dir]

參數:
  csr-file      要簽署的 CSR 文件路徑或檔名
                (使用 --upload-s3 時，可自動從 S3 下載 CSR)
  days-valid    證書有效天數 (預設: 365)
  output-dir    輸出目錄 (預設: CSR 文件所在目錄)

選項:
  -e, --environment ENV  指定環境 (staging/production)
  -b, --bucket NAME      S3 存儲桶名稱 (預設: vpn-csr-exchange)
  -p, --profile PROFILE  AWS CLI profile
  --upload-s3           簽署後自動上傳證書到 S3
  --no-s3               停用 S3 功能
  -v, --verbose         顯示詳細輸出
  -h, --help           顯示此幫助訊息

範例:
  $0 user.csr                           # 簽署 CSR，預設 365 天
  $0 user.csr 180                      # 簽署 CSR，180 天有效期
  $0 user.csr 365 /output/path         # 指定輸出目錄

注意: 執行前請確保已正確設定環境和 AWS 憑證
EOF
        exit 0
    fi
done

# 載入環境管理器 (必須第一個載入)
source "$PARENT_DIR/lib/env_manager.sh"

# 初始化環境
if ! env_init_for_script "sign_csr.sh"; then
    echo -e "${RED}錯誤: 無法初始化環境管理器${NC}"
    exit 1
fi

# 驗證 AWS Profile 整合
echo -e "${BLUE}正在驗證 AWS Profile 設定...${NC}"
if ! env_validate_profile_integration "$CURRENT_ENVIRONMENT" "true"; then
    echo -e "${YELLOW}警告: AWS Profile 設定可能有問題，但繼續執行 CSR 簽署工具${NC}"
fi

# 設定環境特定路徑
env_setup_paths

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

# 使用說明
show_usage() {
    echo "用法: $0 [選項] <csr-file> [days-valid] [output-dir]"
    echo ""
    echo "參數:"
    echo "  csr-file      要簽署的 CSR 文件路徑或檔名"
    echo "                (使用 --upload-s3 時，可自動從 S3 下載 CSR)"
    echo "  days-valid    證書有效天數 (預設: 365)"
    echo "  output-dir    輸出目錄 (預設: CSR 文件所在目錄)"
    echo ""
    echo "選項:"
    echo "  -e, --environment ENV  指定環境 (staging/production)"
    echo "  -b, --bucket NAME      S3 存儲桶名稱 (預設: vpn-csr-exchange)"
    echo "  -p, --profile PROFILE  AWS CLI profile"
    echo "  --upload-s3           簽署後自動上傳證書到 S3"
    echo "  --no-s3               停用 S3 功能"
    echo "  -v, --verbose         顯示詳細輸出"
    echo "  -h, --help           顯示此幫助訊息"
    echo ""
    echo "範例:"
    echo "  $0 user.csr                           # 簽署 CSR，預設 365 天"
    echo "  $0 user.csr 180                      # 簽署 CSR，180 天有效期"
    echo "  $0 user.csr 365 /output/path         # 指定輸出目錄"
    echo "  $0 -e production user.csr            # 指定 production 環境"
    echo "  $0 --upload-s3 user.csr              # 簽署並上傳到 S3"
    echo "  $0 -b my-bucket --upload-s3 user.csr # 使用自定義 S3 存儲桶"
    echo ""
    echo "零接觸工作流程:"
    echo "  $0 --upload-s3 -e production user.csr  # 簽署並自動上傳供用戶下載"
    echo ""
    echo "注意:"
    echo "• 此工具需要 CA 私鑰存在於環境配置目錄中"
    echo "• 簽署的證書將放置在指定的輸出目錄"
    echo "• 使用 --upload-s3 可實現零接觸證書交付"
    echo "• 使用 --upload-s3 時，如本地無 CSR 文件會自動從 S3 下載"
    echo "• 所有操作都會記錄到日誌文件中"
}

# S3 零接觸功能
# =====================================

# 生成環境特定的存儲桶名稱
get_default_bucket_name() {
    # 使用環境和帳戶ID來確保存儲桶名稱唯一性，與 setup_csr_s3_bucket.sh 保持一致
    local env_suffix=""
    if [[ -n "$CURRENT_ENVIRONMENT" ]]; then
        env_suffix="-${CURRENT_ENVIRONMENT}"
    fi
    
    # 如果有帳戶ID，使用它來確保唯一性
    if [[ -n "$ACCOUNT_ID" ]]; then
        echo "vpn-csr-exchange${env_suffix}-${ACCOUNT_ID}"
    else
        # 備用方案：嘗試從 AWS 獲取帳戶ID
        local account_id
        if [[ -n "$AWS_PROFILE" ]]; then
            account_id=$(aws sts get-caller-identity --query 'Account' --output text --profile "$AWS_PROFILE" 2>/dev/null)
            if [[ -n "$account_id" ]]; then
                echo "vpn-csr-exchange${env_suffix}-${account_id}"
                return 0
            fi
        fi
        # 最後備用方案：使用基本名稱
        echo "vpn-csr-exchange${env_suffix}"
    fi
}

# 更新 S3 存儲桶名稱
update_s3_bucket_name() {
    # 獲取帳戶ID
    if [[ -z "$ACCOUNT_ID" ]] && [[ -n "$AWS_PROFILE" ]]; then
        ACCOUNT_ID=$(aws sts get-caller-identity --query 'Account' --output text --profile "$AWS_PROFILE" 2>/dev/null)
    fi
    
    # 如果 S3_BUCKET 是預設值，重新生成
    if [[ "$S3_BUCKET" == "vpn-csr-exchange" ]]; then
        S3_BUCKET=$(get_default_bucket_name)
        echo -e "${BLUE}使用環境特定的存儲桶名稱: $S3_BUCKET${NC}"
    fi
}

# 檢查 S3 存儲桶訪問權限
check_s3_access() {
    if [ "$DISABLE_S3" = true ]; then
        return 0
    fi
    
    echo -e "${BLUE}檢查 S3 存儲桶訪問權限...${NC}"
    
    # 更新存儲桶名稱
    update_s3_bucket_name
    
    if ! aws s3 ls "s3://$S3_BUCKET/" --profile "$AWS_PROFILE" &>/dev/null; then
        echo -e "${RED}無法訪問 S3 存儲桶: $S3_BUCKET${NC}"
        echo -e "${YELLOW}請檢查：${NC}"
        echo -e "  • 存儲桶是否存在"
        echo -e "  • IAM 權限是否正確設置"
        echo -e "  • AWS profile 是否有效"
        return 1
    fi
    
    echo -e "${GREEN}✓ S3 存儲桶訪問正常${NC}"
    return 0
}

# 上傳證書到 S3
upload_certificate_to_s3() {
    local cert_file="$1"
    local username="$2"
    
    if [ "$DISABLE_S3" = true ]; then
        return 0
    fi
    
    echo -e "${BLUE}上傳證書到 S3...${NC}"
    
    # 確保存儲桶名稱是最新的
    update_s3_bucket_name
    
    local s3_cert_path="s3://$S3_BUCKET/cert/${username}.crt"
    
    if aws s3 cp "$cert_file" "$s3_cert_path" \
        --sse AES256 \
        --acl bucket-owner-full-control \
        --profile "$AWS_PROFILE"; then
        echo -e "${GREEN}✓ 證書已上傳到 S3${NC}"
        echo -e "${GREEN}✓ S3 位置: $s3_cert_path${NC}"
        log_message "證書已上傳到 S3: $s3_cert_path"
        return 0
    else
        echo -e "${RED}證書上傳失敗${NC}"
        return 1
    fi
}

# 可選：從 S3 下載 CSR（用於批次處理工作流程）
download_csr_from_s3() {
    local username="$1"
    local output_file="$2"
    
    if [ "$DISABLE_S3" = true ]; then
        return 1
    fi
    
    echo -e "${BLUE}從 S3 下載 CSR...${NC}"
    
    # 確保存儲桶名稱是最新的
    update_s3_bucket_name
    
    local s3_csr_path="s3://$S3_BUCKET/csr/${username}.csr"
    
    if aws s3 cp "$s3_csr_path" "$output_file" --profile "$AWS_PROFILE"; then
        echo -e "${GREEN}✓ CSR 已從 S3 下載${NC}"
        return 0
    else
        echo -e "${RED}CSR 下載失敗${NC}"
        return 1
    fi
}

# 記錄函數
log_message() {
    local message="$1"
    echo "$(date '+%Y-%m-%d %H:%M:%S'): $message" >> "$LOG_FILE"
    if [ "$VERBOSE" = true ]; then
        echo -e "${BLUE}[LOG]${NC} $message"
    fi
}

# 驗證 CSR 文件
validate_csr() {
    local csr_file="$1"
    
    echo -e "${BLUE}驗證 CSR 文件...${NC}"
    
    # 檢查文件存在
    if [ ! -f "$csr_file" ]; then
        echo -e "${RED}CSR 文件不存在: $csr_file${NC}"
        return 1
    fi
    
    # 檢查 CSR 格式
    if ! openssl req -in "$csr_file" -text -noout >/dev/null 2>&1; then
        echo -e "${RED}無效的 CSR 格式${NC}"
        return 1
    fi
    
    # 顯示 CSR 詳細資訊
    echo -e "${GREEN}✓ CSR 文件有效${NC}"
    
    if [ "$VERBOSE" = true ]; then
        echo -e "${CYAN}CSR 詳細資訊：${NC}"
        openssl req -in "$csr_file" -text -noout | grep -E "(Subject:|Public Key Algorithm:|Public-Key:)"
    fi
    
    # 提取用戶名
    local subject
    subject=$(openssl req -in "$csr_file" -noout -subject 2>/dev/null)
    local username
    username=$(echo "$subject" | sed -n 's/.*CN=\([^,]*\).*/\1/p')
    
    if [ -z "$username" ]; then
        echo -e "${RED}無法從 CSR 中提取用戶名${NC}"
        return 1
    fi
    
    echo -e "${GREEN}✓ 用戶名: $username${NC}"
    CSR_USERNAME="$username"
    
    return 0
}

# 查找並驗證 CA 文件
find_ca_files() {
    local environment="$1"
    
    echo -e "${BLUE}查找 CA 證書和私鑰...${NC}"
    
    # 映射環境名稱到實際文件夾名稱
    local env_folder
    case "$environment" in
        "production")
            env_folder="prod"
            ;;
        "staging")
            env_folder="staging"
            ;;
        *)
            env_folder="$environment"
            ;;
    esac
    
    # 查找 CA 證書
    local ca_cert_paths=(
        "$PARENT_DIR/certs/$env_folder/pki/ca.crt"
        "$PARENT_DIR/certs/$env_folder/ca.crt"
        "$PARENT_DIR/certs/ca.crt"
    )
    
    CA_CERT=""
    for cert_path in "${ca_cert_paths[@]}"; do
        if [ -f "$cert_path" ]; then
            CA_CERT="$cert_path"
            break
        fi
    done
    
    if [ -z "$CA_CERT" ]; then
        echo -e "${RED}找不到 CA 證書文件${NC}"
        echo -e "${YELLOW}查找路徑：${NC}"
        for path in "${ca_cert_paths[@]}"; do
            echo -e "  $path"
        done
        return 1
    fi
    
    # 查找 CA 私鑰
    local ca_key_paths=(
        "$PARENT_DIR/certs/$env_folder/pki/private/ca.key"
        "$PARENT_DIR/certs/$env_folder/ca.key"
        "$PARENT_DIR/certs/ca.key"
    )
    
    CA_KEY=""
    for key_path in "${ca_key_paths[@]}"; do
        if [ -f "$key_path" ]; then
            CA_KEY="$key_path"
            break
        fi
    done
    
    if [ -z "$CA_KEY" ]; then
        echo -e "${RED}找不到 CA 私鑰文件${NC}"
        echo -e "${YELLOW}查找路徑：${NC}"
        for path in "${ca_key_paths[@]}"; do
            echo -e "  $path"
        done
        return 1
    fi
    
    # 驗證 CA 證書
    if ! openssl x509 -in "$CA_CERT" -text -noout >/dev/null 2>&1; then
        echo -e "${RED}CA 證書格式無效: $CA_CERT${NC}"
        return 1
    fi
    
    # 驗證 CA 私鑰
    if ! openssl rsa -in "$CA_KEY" -check -noout >/dev/null 2>&1; then
        echo -e "${RED}CA 私鑰格式無效: $CA_KEY${NC}"
        return 1
    fi
    
    # 驗證證書和私鑰匹配
    local cert_modulus key_modulus
    cert_modulus=$(openssl x509 -in "$CA_CERT" -modulus -noout 2>/dev/null)
    key_modulus=$(openssl rsa -in "$CA_KEY" -modulus -noout 2>/dev/null)
    
    if [ "$cert_modulus" != "$key_modulus" ]; then
        echo -e "${RED}CA 證書與私鑰不匹配${NC}"
        return 1
    fi
    
    echo -e "${GREEN}✓ CA 證書: $CA_CERT${NC}"
    echo -e "${GREEN}✓ CA 私鑰: $CA_KEY${NC}"
    echo -e "${GREEN}✓ CA 證書與私鑰匹配${NC}"
    
    return 0
}

# 簽署 CSR
sign_csr() {
    local csr_file="$1"
    local days_valid="$2"
    local output_dir="$3"
    local output_cert="$output_dir/${CSR_USERNAME}.crt"
    
    echo -e "${BLUE}簽署 CSR...${NC}"
    
    # 確保輸出目錄存在
    if ! mkdir -p "$output_dir"; then
        echo -e "${RED}無法創建輸出目錄: $output_dir${NC}"
        return 1
    fi
    
    # 檢查輸出文件是否已存在
    if [ -f "$output_cert" ]; then
        local overwrite
        read -p "證書文件已存在: $output_cert。是否覆蓋? (y/n): " overwrite
        if [[ ! "$overwrite" =~ ^[Yy]$ ]]; then
            echo -e "${YELLOW}取消簽署操作${NC}"
            return 1
        fi
    fi
    
    # 簽署證書
    if ! openssl x509 -req -in "$csr_file" \
        -CA "$CA_CERT" \
        -CAkey "$CA_KEY" \
        -CAcreateserial \
        -out "$output_cert" \
        -days "$days_valid" \
        -extensions v3_req \
        -extfile <(cat <<EOF
[v3_req]
basicConstraints = CA:FALSE
keyUsage = nonRepudiation, digitalSignature, keyEncipherment
subjectAltName = @alt_names

[alt_names]
DNS.1 = ${CSR_USERNAME}
DNS.2 = ${CSR_USERNAME}.vpn-client
EOF
); then
        echo -e "${RED}證書簽署失敗${NC}"
        return 1
    fi
    
    # 設置正確權限
    chmod 644 "$output_cert"
    
    # 驗證生成的證書
    if ! openssl x509 -in "$output_cert" -text -noout >/dev/null 2>&1; then
        echo -e "${RED}生成的證書格式無效${NC}"
        return 1
    fi
    
    echo -e "${GREEN}✓ 證書簽署成功${NC}"
    echo -e "${GREEN}✓ 輸出證書: $output_cert${NC}"
    
    # 顯示證書資訊
    if [ "$VERBOSE" = true ]; then
        echo -e "${CYAN}證書詳細資訊：${NC}"
        openssl x509 -in "$output_cert" -text -noout | grep -E "(Subject:|Issuer:|Not Before:|Not After :|Public Key Algorithm:)"
    fi
    
    # 記錄簽署操作
    log_message "為用戶 $CSR_USERNAME 簽署證書: $output_cert (有效期: $days_valid 天)"
    
    return 0
}

# 顯示簽署完成指示
show_completion_instructions() {
    local output_cert="$1"
    local environment="$2"
    local uploaded_s3="$3"
    
    echo -e "\n${GREEN}=============================================${NC}"
    echo -e "${GREEN}       證書簽署完成！       ${NC}"
    echo -e "${GREEN}=============================================${NC}"
    echo -e ""
    echo -e "${CYAN}📋 證書資訊：${NC}"
    echo -e "  👤 用戶名: ${CYAN}$CSR_USERNAME${NC}"
    echo -e "  🌍 環境: ${CYAN}$environment${NC}"
    echo -e "  📄 本地證書: ${YELLOW}$output_cert${NC}"
    
    if [ "$uploaded_s3" = true ]; then
        echo -e "  ☁️  S3 位置: ${YELLOW}s3://$S3_BUCKET/cert/${CSR_USERNAME}.crt${NC}"
    fi
    echo -e ""
    
    echo -e "${CYAN}📋 後續操作：${NC}"
    echo -e ""
    
    if [ "$uploaded_s3" = true ]; then
        echo -e "${BLUE}🎯 零接觸模式 - 已完成${NC}"
        echo -e "   ✅ 證書已自動上傳到 S3"
        echo -e "   ✅ 用戶可以直接執行恢復命令"
        echo -e ""
        echo -e "${BLUE}📢 通知用戶：${NC}"
        echo -e "   告知用戶 ${CYAN}$CSR_USERNAME${NC} 證書已準備完成"
        echo -e "   指示用戶執行: ${CYAN}./team_member_setup.sh --resume${NC}"
        echo -e ""
        echo -e "${BLUE}💡 零接觸優勢：${NC}"
        echo -e "   • 無需手動傳輸證書文件"
        echo -e "   • 自動加密存儲在 S3"
        echo -e "   • 用戶可立即完成 VPN 設置"
    else
        echo -e "${BLUE}📁 手動模式 - 需要額外步驟${NC}"
        echo -e ""
        echo -e "${BLUE}1. 將簽署的證書提供給用戶：${NC}"
        echo -e "   ${YELLOW}$output_cert${NC}"
        echo -e ""
        echo -e "${BLUE}2. 指示用戶將證書放置到正確位置：${NC}"
        echo -e "   ${CYAN}certs/$environment/users/${CSR_USERNAME}.crt${NC}"
        echo -e ""
        echo -e "${BLUE}3. 或者手動上傳到 S3：${NC}"
        echo -e "   ${CYAN}aws_with_profile s3 cp $output_cert s3://$S3_BUCKET/cert/${CSR_USERNAME}.crt --sse aws:kms${NC}"
        echo -e ""
        echo -e "${BLUE}4. 通知用戶執行恢復命令：${NC}"
        echo -e "   傳統模式: ${CYAN}./team_member_setup.sh --resume-cert${NC}"
        echo -e "   零接觸模式: ${CYAN}./team_member_setup.sh --resume${NC}"
    fi
    
    echo -e ""
    echo -e "${YELLOW}💡 安全提醒：${NC}"
    echo -e "• 請確認證書已安全傳遞給正確的用戶"
    echo -e "• 所有 S3 傳輸都使用 KMS 加密"
    echo -e "• 記錄證書頒發信息以便審計"
    echo -e "• 建議設置證書過期提醒"
}

# 主函數
main() {
    # 預設值
    local environment=""
    local days_valid=365
    local output_dir=""
    local csr_file=""
    VERBOSE=false
    CSR_USERNAME=""
    CA_CERT=""
    CA_KEY=""
    S3_BUCKET="vpn-csr-exchange"  # 將在運行時更新為環境特定名稱
    # Get AWS profile from environment manager
    AWS_PROFILE="$(env_get_profile "$CURRENT_ENVIRONMENT" 2>/dev/null || echo default)"
    UPLOAD_S3=false
    DISABLE_S3=false
    ACCOUNT_ID=""  # 將在運行時設置
    
    # 解析命令行參數
    while [[ $# -gt 0 ]]; do
        case $1 in
            -e|--environment)
                environment="$2"
                shift 2
                ;;
            -b|--bucket)
                S3_BUCKET="$2"
                shift 2
                ;;
            -p|--profile)
                AWS_PROFILE="$2"
                shift 2
                ;;
            --upload-s3)
                UPLOAD_S3=true
                shift
                ;;
            --no-s3)
                DISABLE_S3=true
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
            -*)
                echo -e "${RED}未知選項: $1${NC}"
                show_usage
                exit 1
                ;;
            *)
                if [ -z "$csr_file" ]; then
                    csr_file="$1"
                elif [[ "$1" =~ ^[0-9]+$ ]]; then
                    days_valid="$1"
                elif [ -z "$output_dir" ]; then
                    output_dir="$1"
                fi
                shift
                ;;
        esac
    done
    
    # 檢查必需參數
    if [ -z "$csr_file" ]; then
        echo -e "${RED}錯誤: 必須指定 CSR 文件${NC}"
        show_usage
        exit 1
    fi
    
    # 設置預設輸出目錄
    if [ -z "$output_dir" ]; then
        output_dir="$(dirname "$csr_file")"
    fi
    
    # 使用當前環境或指定的環境
    if [ -z "$environment" ]; then
        environment="$CURRENT_ENVIRONMENT"
        echo -e "${BLUE}使用當前環境: $environment${NC}"
    fi
    
    # 驗證環境有效性
    if [[ ! "$environment" =~ ^(staging|production)$ ]]; then
        echo -e "${RED}無效的環境: $environment${NC}"
        echo -e "${YELLOW}有效環境: staging, production${NC}"
        exit 1
    fi
    
    # 設置日誌文件
    LOG_FILE="$PARENT_DIR/logs/$environment/csr_signing.log"
    mkdir -p "$(dirname "$LOG_FILE")"
    
    show_env_aware_header "CSR 簽署工具 - 管理員專用"
    
    # 顯示 AWS Profile 資訊
    local current_profile
    current_profile=$(env_get_profile "$CURRENT_ENVIRONMENT" 2>/dev/null)
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
        if validate_profile_matches_environment "$current_profile" "$CURRENT_ENVIRONMENT" 2>/dev/null; then
            echo -e "  狀態: ${GREEN}✓ 有效且匹配環境${NC}"
        else
            echo -e "  狀態: ${YELLOW}⚠ 有效但可能不匹配環境${NC}"
        fi
    else
        echo -e "${CYAN}AWS 配置狀態:${NC}"
        echo -e "  Profile: ${YELLOW}未設定${NC}"
    fi
    echo -e ""
    
    echo -e "${BLUE}簽署配置:${NC}"
    echo -e "  環境: $environment"
    echo -e "  CSR 文件: $csr_file"
    echo -e "  有效天數: $days_valid"
    echo -e "  輸出目錄: $output_dir"
    echo -e "  S3 存儲桶: $S3_BUCKET"
    echo -e "  AWS Profile: $AWS_PROFILE"
    echo -e ""
    
    # 檢查 S3 訪問（如果需要）- 這裡會更新存儲桶名稱
    if [ "$UPLOAD_S3" = true ]; then
        if ! check_s3_access; then
            echo -e "${YELLOW}S3 訪問失敗，將跳過 S3 上傳${NC}"
            UPLOAD_S3=false
        else
            # 更新顯示的存儲桶名稱
            echo -e "${BLUE}更新後的簽署配置:${NC}"
            echo -e "  S3 存儲桶: $S3_BUCKET"
            echo -e ""
        fi
    fi
    
    # 檢查 CSR 文件是否存在，如需要則從 S3 下載
    if [ ! -f "$csr_file" ] && [ "$UPLOAD_S3" = true ]; then
        echo -e "${BLUE}本地 CSR 文件不存在，嘗試從 S3 下載...${NC}"
        
        # 提取用戶名（假設 CSR 文件名格式為 username.csr）
        local temp_username
        temp_username=$(basename "$csr_file" .csr)
        
        # 創建臨時目錄下載 CSR
        local temp_csr_dir="/tmp/vpn_csr_download"
        mkdir -p "$temp_csr_dir"
        local temp_csr_file="$temp_csr_dir/${temp_username}.csr"
        
        if download_csr_from_s3 "$temp_username" "$temp_csr_file"; then
            echo -e "${GREEN}✓ CSR 已從 S3 下載到臨時位置${NC}"
            csr_file="$temp_csr_file"
            # 同時更新輸出目錄到原始位置（而非臨時目錄）
            if [ "$output_dir" = "$(dirname "$1")" ]; then
                output_dir="$(dirname "$1")"  # 保持原始輸output_dir
            fi
        else
            echo -e "${RED}無法從 S3 下載 CSR: ${temp_username}.csr${NC}"
            echo -e "${YELLOW}請檢查：${NC}"
            echo -e "  • CSR 是否已上傳到 S3: s3://$S3_BUCKET/csr/${temp_username}.csr"
            echo -e "  • S3 存取權限是否正確"
            echo -e "  • AWS profile 設定是否有效"
            exit 1
        fi
    fi
    
    # 執行簽署流程
    if ! validate_csr "$csr_file"; then
        exit 1
    fi
    
    if ! find_ca_files "$environment"; then
        exit 1
    fi
    
    if ! sign_csr "$csr_file" "$days_valid" "$output_dir"; then
        exit 1
    fi
    
    # S3 上傳（如果啟用）
    if [ "$UPLOAD_S3" = true ]; then
        local cert_file="$output_dir/${CSR_USERNAME}.crt"
        if upload_certificate_to_s3 "$cert_file" "$CSR_USERNAME"; then
            echo -e "${GREEN}✓ 零接觸證書交付完成${NC}"
        else
            echo -e "${YELLOW}⚠ S3 上傳失敗，但證書簽署成功${NC}"
        fi
    fi
    
    show_completion_instructions "$output_dir/${CSR_USERNAME}.crt" "$environment" "$UPLOAD_S3"
    
    # 清理臨時 CSR 文件 (如果從 S3 下載)
    if [[ "$csr_file" == "/tmp/vpn_csr_download/"* ]]; then
        rm -f "$csr_file"
        echo -e "${BLUE}✓ 臨時 CSR 文件已清理${NC}"
    fi
    
    echo -e "${GREEN}CSR 簽署完成！${NC}"
}

# 只有在腳本直接執行時才執行主程序
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi