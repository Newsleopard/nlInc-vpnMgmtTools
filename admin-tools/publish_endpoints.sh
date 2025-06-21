#!/bin/bash

# VPN 端點和公用資產發布工具 - 管理員專用
# 用途：將 CA 證書和 VPN 端點資訊發布到 S3 供團隊成員自動獲取
# 版本：1.0

# 全域變數
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARENT_DIR="$(dirname "$SCRIPT_DIR")"

# 載入環境管理器 (必須第一個載入)
source "$PARENT_DIR/lib/env_manager.sh"

# 初始化環境
if ! env_init_for_script "publish_endpoints.sh"; then
    echo -e "${RED}錯誤: 無法初始化環境管理器${NC}"
    exit 1
fi

# 驗證 AWS Profile 整合
echo -e "${BLUE}正在驗證 AWS Profile 設定...${NC}"
if ! env_validate_profile_integration "$CURRENT_ENVIRONMENT" "true"; then
    echo -e "${YELLOW}警告: AWS Profile 設定可能有問題，但繼續執行發布工具${NC}"
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

# 預設配置 (固定桶名稱)
get_default_bucket_name() {
    echo "vpn-csr-exchange"
}

DEFAULT_BUCKET_NAME="$(get_default_bucket_name)"

# 使用說明
show_usage() {
    echo "用法: $0 [選項]"
    echo ""
    echo "選項:"
    echo "  -b, --bucket-name NAME     S3 存儲桶名稱 (預設: $DEFAULT_BUCKET_NAME)"
    echo "  -e, --environment ENV      特定環境 (staging/production) 或 'all' 發布所有"
    echo "  -p, --profile PROFILE      AWS CLI profile"
    echo "  --ca-only                  只發布 CA 證書"
    echo "  --endpoints-only           只發布端點資訊"
    echo "  --force                    強制覆蓋現有文件"
    echo "  -v, --verbose              顯示詳細輸出"
    echo "  -h, --help                顯示此幫助訊息"
    echo ""
    echo "功能說明:"
    echo "  此工具將 CA 證書和 VPN 端點資訊發布到 S3 存儲桶的 public/ 前綴"
    echo "  供團隊成員自動下載使用，實現零接觸 VPN 設置流程"
    echo ""
    echo "範例:"
    echo "  $0                                     # 發布所有環境的資產"
    echo "  $0 -e production                      # 只發布 production 環境"
    echo "  $0 --ca-only                          # 只發布 CA 證書"
    echo "  $0 --endpoints-only -e staging        # 只發布 staging 端點資訊"
    echo "  $0 -b my-vpn-bucket --force           # 使用自定義存儲桶並強制覆蓋"
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
    
    if ! command -v aws &> /dev/null; then
        echo -e "${RED}AWS CLI 未安裝${NC}"
        return 1
    fi
    
    if ! aws_with_profile sts get-caller-identity --profile "$AWS_PROFILE" &>/dev/null; then
        echo -e "${RED}AWS 憑證無效或未設置 (profile: $AWS_PROFILE)${NC}"
        return 1
    fi
    
    echo -e "${GREEN}✓ AWS 配置有效${NC}"
    return 0
}

# 檢查 S3 存儲桶
check_s3_bucket() {
    echo -e "${BLUE}檢查 S3 存儲桶...${NC}"
    
    if ! aws_with_profile s3 ls "s3://$BUCKET_NAME" --profile "$AWS_PROFILE" &>/dev/null; then
        echo -e "${RED}無法訪問 S3 存儲桶: $BUCKET_NAME${NC}"
        echo -e "${YELLOW}請先運行 setup_csr_s3_bucket.sh 創建存儲桶${NC}"
        return 1
    fi
    
    echo -e "${GREEN}✓ S3 存儲桶可訪問${NC}"
    return 0
}

# 查找 CA 證書
find_ca_certificate() {
    echo -e "${BLUE}查找 CA 證書...${NC}"
    
    # 查找各環境的 CA 證書
    local ca_cert_paths=()
    
    if [ "$ENVIRONMENT" = "all" ] || [ "$ENVIRONMENT" = "staging" ]; then
        ca_cert_paths+=(
            "$PARENT_DIR/certs/staging/pki/ca.crt"
            "$PARENT_DIR/certs/staging/ca.crt"
        )
    fi
    
    if [ "$ENVIRONMENT" = "all" ] || [ "$ENVIRONMENT" = "production" ]; then
        ca_cert_paths+=(
            "$PARENT_DIR/certs/production/pki/ca.crt"
            "$PARENT_DIR/certs/production/ca.crt"
        )
    fi
    
    # 通用路徑
    ca_cert_paths+=(
        "$PARENT_DIR/certs/ca.crt"
    )
    
    CA_CERT=""
    for cert_path in "${ca_cert_paths[@]}"; do
        if [ -f "$cert_path" ]; then
            CA_CERT="$cert_path"
            echo -e "${GREEN}✓ 找到 CA 證書: $cert_path${NC}"
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
    
    # 驗證 CA 證書
    if ! openssl x509 -in "$CA_CERT" -text -noout >/dev/null 2>&1; then
        echo -e "${RED}CA 證書格式無效: $CA_CERT${NC}"
        return 1
    fi
    
    echo -e "${GREEN}✓ CA 證書驗證成功${NC}"
    return 0
}

# 生成端點資訊 JSON
generate_endpoints_json() {
    echo -e "${BLUE}生成端點資訊 JSON...${NC}"
    
    local work_dir="$PARENT_DIR/work"
    mkdir -p "$work_dir"
    
    local endpoints_file="$work_dir/vpn_endpoints.json"
    
    # 開始 JSON 文件
    echo "{" > "$endpoints_file"
    
    local first_env=true
    
    # 處理指定環境
    for env in staging production; do
        if [ "$ENVIRONMENT" != "all" ] && [ "$ENVIRONMENT" != "$env" ]; then
            continue
        fi
        
        local config_file="$PARENT_DIR/configs/$env/${env}.env"
        
        if [ ! -f "$config_file" ]; then
            echo -e "${YELLOW}⚠ 配置文件不存在: $config_file${NC}"
            continue
        fi
        
        # 載入環境配置
        local endpoint_id region
        if source "$config_file" 2>/dev/null; then
            endpoint_id="$ENDPOINT_ID"
            region="$AWS_REGION"
        else
            echo -e "${YELLOW}⚠ 無法載入配置: $config_file${NC}"
            continue
        fi
        
        if [ -z "$endpoint_id" ] || [ -z "$region" ]; then
            echo -e "${YELLOW}⚠ $env 環境配置不完整 (endpoint_id: $endpoint_id, region: $region)${NC}"
            continue
        fi
        
        # 添加逗號分隔符
        if [ "$first_env" = false ]; then
            echo "," >> "$endpoints_file"
        fi
        first_env=false
        
        # 添加環境配置
        echo "  \"$env\": {" >> "$endpoints_file"
        echo "    \"endpoint_id\": \"$endpoint_id\"," >> "$endpoints_file"
        echo "    \"region\": \"$region\"" >> "$endpoints_file"
        echo -n "  }" >> "$endpoints_file"
        
        echo -e "${GREEN}✓ 添加 $env 環境: $endpoint_id ($region)${NC}"
    done
    
    # 結束 JSON 文件
    echo "" >> "$endpoints_file"
    echo "}" >> "$endpoints_file"
    
    # 驗證 JSON 格式
    if command -v jq >/dev/null 2>&1; then
        if ! jq . "$endpoints_file" >/dev/null 2>&1; then
            echo -e "${RED}生成的 JSON 格式無效${NC}"
            return 1
        fi
    fi
    
    echo -e "${GREEN}✓ 端點資訊 JSON 生成完成: $endpoints_file${NC}"
    ENDPOINTS_JSON="$endpoints_file"
    return 0
}

# 發布 CA 證書到 S3
publish_ca_certificate() {
    echo -e "${BLUE}發布 CA 證書到 S3...${NC}"
    
    local s3_path="s3://$BUCKET_NAME/public/ca.crt"
    
    # 檢查是否需要覆蓋
    if [ "$FORCE" = false ]; then
        if aws_with_profile s3 ls "$s3_path" --profile "$AWS_PROFILE" &>/dev/null; then
            local overwrite
            read -p "CA 證書已存在於 S3。是否覆蓋? (y/n): " overwrite
            if [[ ! "$overwrite" =~ ^[Yy]$ ]]; then
                echo -e "${YELLOW}跳過 CA 證書發布${NC}"
                return 0
            fi
        fi
    fi
    
    # 上傳 CA 證書
    if aws_with_profile s3 cp "$CA_CERT" "$s3_path" \
        --sse aws:kms \
        --acl bucket-owner-full-control \
        --profile "$AWS_PROFILE"; then
        echo -e "${GREEN}✓ CA 證書已發布到 S3${NC}"
        log_message "CA 證書已發布: $s3_path"
    else
        echo -e "${RED}CA 證書發布失敗${NC}"
        return 1
    fi
    
    # 可選：生成並上傳 SHA-256 哈希
    local ca_hash
    ca_hash=$(openssl dgst -sha256 "$CA_CERT" | awk '{print $2}')
    if [ -n "$ca_hash" ]; then
        echo "$ca_hash" > "/tmp/ca.crt.sha256"
        if aws_with_profile s3 cp "/tmp/ca.crt.sha256" "s3://$BUCKET_NAME/public/ca.crt.sha256" \
            --sse aws:kms \
            --acl bucket-owner-full-control \
            --profile "$AWS_PROFILE"; then
            echo -e "${GREEN}✓ CA 證書哈希已發布${NC}"
            rm -f "/tmp/ca.crt.sha256"
        fi
    fi
    
    return 0
}

# 發布端點資訊到 S3
publish_endpoints() {
    echo -e "${BLUE}發布端點資訊到 S3...${NC}"
    
    local s3_path="s3://$BUCKET_NAME/public/vpn_endpoints.json"
    
    # 檢查是否需要覆蓋
    if [ "$FORCE" = false ]; then
        if aws_with_profile s3 ls "$s3_path" --profile "$AWS_PROFILE" &>/dev/null; then
            local overwrite
            read -p "端點資訊已存在於 S3。是否覆蓋? (y/n): " overwrite
            if [[ ! "$overwrite" =~ ^[Yy]$ ]]; then
                echo -e "${YELLOW}跳過端點資訊發布${NC}"
                return 0
            fi
        fi
    fi
    
    # 上傳端點資訊
    if aws_with_profile s3 cp "$ENDPOINTS_JSON" "$s3_path" \
        --sse aws:kms \
        --acl bucket-owner-full-control \
        --profile "$AWS_PROFILE"; then
        echo -e "${GREEN}✓ 端點資訊已發布到 S3${NC}"
        log_message "端點資訊已發布: $s3_path"
    else
        echo -e "${RED}端點資訊發布失敗${NC}"
        return 1
    fi
    
    return 0
}

# 顯示發布結果
show_publication_summary() {
    echo -e "\n${GREEN}=============================================${NC}"
    echo -e "${GREEN}       公用資產發布完成！       ${NC}"
    echo -e "${GREEN}=============================================${NC}"
    echo -e ""
    echo -e "${CYAN}📋 發布摘要：${NC}"
    echo -e "  🪣 存儲桶: ${YELLOW}$BUCKET_NAME${NC}"
    echo -e "  👤 AWS Profile: ${YELLOW}$AWS_PROFILE${NC}"
    echo -e "  🌍 環境: ${YELLOW}$ENVIRONMENT${NC}"
    echo -e ""
    
    if [ "$CA_ONLY" = false ]; then
        echo -e "${BLUE}📁 發布的資產：${NC}"
        if [ "$ENDPOINTS_ONLY" = false ]; then
            echo -e "  📜 CA 證書: ${CYAN}s3://$BUCKET_NAME/public/ca.crt${NC}"
        fi
        if [ "$CA_ONLY" = false ]; then
            echo -e "  📄 端點資訊: ${CYAN}s3://$BUCKET_NAME/public/vpn_endpoints.json${NC}"
        fi
    fi
    
    echo -e ""
    echo -e "${CYAN}📋 團隊成員使用方法：${NC}"
    echo -e "  ${BLUE}1.${NC} 初始化設置："
    echo -e "     ${CYAN}./team_member_setup.sh --init${NC}"
    echo -e ""
    echo -e "  ${BLUE}2.${NC} 等待管理員簽署證書"
    echo -e ""
    echo -e "  ${BLUE}3.${NC} 完成設置："
    echo -e "     ${CYAN}./team_member_setup.sh --resume${NC}"
    echo -e ""
    echo -e "${YELLOW}💡 提示：${NC}"
    echo -e "• 團隊成員現在可以自動獲取所需的配置文件"
    echo -e "• 無需手動傳遞 CA 證書或端點 ID"
    echo -e "• 所有文件都使用 KMS 加密保護"
}

# 主函數
main() {
    # 預設值
    BUCKET_NAME="$DEFAULT_BUCKET_NAME"
    ENVIRONMENT="all"
    # Get AWS profile from environment manager
    AWS_PROFILE="$(env_get_profile "$CURRENT_ENVIRONMENT" 2>/dev/null || echo default)"
    CA_ONLY=false
    ENDPOINTS_ONLY=false
    FORCE=false
    VERBOSE=false
    CA_CERT=""
    ENDPOINTS_JSON=""
    
    # 解析命令行參數
    while [[ $# -gt 0 ]]; do
        case $1 in
            -b|--bucket-name)
                BUCKET_NAME="$2"
                shift 2
                ;;
            -e|--environment)
                ENVIRONMENT="$2"
                shift 2
                ;;
            -p|--profile)
                AWS_PROFILE="$2"
                shift 2
                ;;
            --ca-only)
                CA_ONLY=true
                shift
                ;;
            --endpoints-only)
                ENDPOINTS_ONLY=true
                shift
                ;;
            --force)
                FORCE=true
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
    
    # 驗證環境參數
    if [[ ! "$ENVIRONMENT" =~ ^(all|staging|production)$ ]]; then
        echo -e "${RED}無效的環境: $ENVIRONMENT${NC}"
        echo -e "${YELLOW}有效選項: all, staging, production${NC}"
        exit 1
    fi
    
    # 檢查互斥選項
    if [ "$CA_ONLY" = true ] && [ "$ENDPOINTS_ONLY" = true ]; then
        echo -e "${RED}錯誤: --ca-only 和 --endpoints-only 不能同時使用${NC}"
        exit 1
    fi
    
    # 設置日誌文件
    LOG_FILE="$PARENT_DIR/logs/publish_endpoints.log"
    mkdir -p "$(dirname "$LOG_FILE")"
    
    show_env_aware_header "VPN 公用資產發布工具"
    
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
    
    echo -e "${BLUE}發布配置:${NC}"
    echo -e "  存儲桶: $BUCKET_NAME"
    echo -e "  環境: $ENVIRONMENT"
    echo -e "  AWS Profile: $AWS_PROFILE"
    echo -e ""
    
    # 檢查前置條件
    if ! check_aws_config; then
        exit 1
    fi
    
    if ! check_s3_bucket; then
        exit 1
    fi
    
    # 執行發布操作
    if [ "$ENDPOINTS_ONLY" = false ]; then
        if ! find_ca_certificate; then
            exit 1
        fi
        
        if ! publish_ca_certificate; then
            exit 1
        fi
    fi
    
    if [ "$CA_ONLY" = false ]; then
        if ! generate_endpoints_json; then
            exit 1
        fi
        
        if ! publish_endpoints; then
            exit 1
        fi
    fi
    
    show_publication_summary
    
    log_message "公用資產發布完成: bucket=$BUCKET_NAME, environment=$ENVIRONMENT"
    echo -e "${GREEN}發布完成！${NC}"
}

# 只有在腳本直接執行時才執行主程序
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi