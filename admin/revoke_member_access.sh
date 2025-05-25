#!/bin/bash

# AWS Client VPN 撤銷團隊成員訪問權限腳本
# 用途：安全撤銷特定團隊成員的 VPN 訪問權限
# 版本：1.1 (環境感知版本)

# 全域變數
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 載入環境管理器 (必須第一個載入)
source "$SCRIPT_DIR/../lib/env_manager.sh"

# 初始化環境
if ! env_init_for_script "revoke_member_access.sh"; then
    echo -e "${RED}錯誤: 無法初始化環境管理器${NC}"
    exit 1
fi

# 設定環境特定路徑
env_setup_paths

# 環境感知的配置檔案
REVOCATION_LOG_DIR="$ENV_LOG_DIR/revocation"
LOG_FILE="$REVOCATION_LOG_DIR/revocation.log"
CONFIG_FILE="$VPN_ENDPOINT_CONFIG_FILE"
EASYRSA_DIR_REVOKE="$ENV_CERT_DIR/easy-rsa-env"

# 載入核心函式庫
source "$SCRIPT_DIR/../lib/core_functions.sh"
source "$SCRIPT_DIR/../lib/cert_management.sh"

# 阻止腳本在出錯時繼續執行
set -e

# 此腳本專用日誌函式 (撤銷操作專用，與 core_functions.sh 中的日誌分開)
log_revocation_message() {
    mkdir -p "$REVOCATION_LOG_DIR"
    echo "$(date '+%Y-%m-%d %H:%M:%S'): $1" >> "$LOG_FILE"
}

# 顯示歡迎訊息
show_welcome() {
    clear
    show_env_aware_header "AWS Client VPN 訪問權限撤銷工具"
    echo -e ""
    echo -e "${YELLOW}此工具用於撤銷團隊成員的 VPN 訪問權限${NC}"
    echo -e "${YELLOW}適用於以下情況：${NC}"
    echo -e "  ${BLUE}•${NC} 團隊成員角色變更"
    echo -e "  ${BLUE}•${NC} 暫時停用訪問權限"
    echo -e "  ${BLUE}•${NC} 安全事件響應"
    echo -e "  ${BLUE}•${NC} 定期權限審計"
    echo -e ""
    echo -e "${RED}警告：此操作會立即生效，請謹慎操作${NC}"
    echo -e ""
    echo -e "${CYAN}========================================================${NC}"
    echo -e ""
    press_any_key_to_continue
}

# 檢查必要工具和權限
check_revocation_prerequisites() {
    echo -e "\\n${YELLOW}[1/7] 檢查必要工具和權限...${NC}"
    
    # macOS 特定檢查
    if [ "$(uname)" = "Darwin" ]; then
        echo -e "${BLUE}檢測到 macOS 系統，執行 macOS 特定檢查...${NC}"
        
        # 檢查 macOS 版本
        local macos_version
        macos_version=$(sw_vers -productVersion)
        echo -e "${BLUE}macOS 版本: $macos_version${NC}"
        
        # 檢查 Homebrew
        if ! command -v brew >/dev/null 2>&1; then
            echo -e "${RED}錯誤: 需要 Homebrew 來管理相關工具${NC}"
            echo -e "${YELLOW}請先安裝 Homebrew: /bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\"${NC}"
            log_revocation_message "macOS: Homebrew 未安裝"
            exit 1
        fi
        
        # 檢查關鍵的 macOS 工具
        local macos_tools=("jq" "aws")
        local missing_macos_tools=()
        
        for tool in "${macos_tools[@]}"; do
            if ! command -v "$tool" >/dev/null 2>&1; then
                missing_macos_tools+=("$tool")
            fi
        done
        
        if [ ${#missing_macos_tools[@]} -gt 0 ]; then
            echo -e "${RED}缺少必要工具: ${missing_macos_tools[*]}${NC}"
            echo -e "${YELLOW}請使用 Homebrew 安裝: brew install ${missing_macos_tools[*]}${NC}"
            log_revocation_message "macOS: 缺少必要工具: ${missing_macos_tools[*]}"
            exit 1
        fi
        
        # 檢查 macOS 權限
        echo -e "${BLUE}檢查 macOS 權限設置...${NC}"
        
        # 檢查 EasyRSA 目錄權限
        if [ -d "$EASYRSA_DIR_REVOKE" ]; then
            local easyrsa_perms
            easyrsa_perms=$(stat -f "%OLp" "$EASYRSA_DIR_REVOKE" 2>/dev/null || echo "000")
            if [ "$easyrsa_perms" -lt 755 ]; then
                echo -e "${YELLOW}調整 EasyRSA 目錄權限...${NC}"
                chmod 755 "$EASYRSA_DIR_REVOKE" || {
                    echo -e "${RED}無法設置 EasyRSA 目錄權限${NC}"
                    log_revocation_message "macOS: 無法設置 EasyRSA 目錄權限"
                    exit 1
                }
            fi
        fi
        
        echo -e "${GREEN}✓ macOS 特定檢查完成${NC}"
        log_revocation_message "macOS 特定檢查完成"
    fi
    
    # 使用 core_functions.sh 中的 check_prerequisites
    if ! check_prerequisites; then
        log_revocation_message "先決條件檢查失敗，腳本終止。"
        exit 1
    fi
    
    # 額外檢查 AWS 配置
    if [ ! -f ~/.aws/credentials ] || [ ! -f ~/.aws/config ]; then
        echo -e "${RED}未找到 AWS 配置${NC}"
        echo -e "${YELLOW}請先配置 AWS CLI${NC}"
        log_revocation_message "AWS 配置未找到"
        exit 1
    fi
    
    # 測試 AWS 連接和權限
    echo -e "${BLUE}測試 AWS 連接和權限...${NC}"
    local aws_user
    aws_user=$(aws sts get-caller-identity --query 'Arn' --output text 2>/dev/null || echo "failed")
    
    if [[ "$aws_user" == "failed" ]]; then
        echo -e "${RED}AWS 連接失敗${NC}"
        log_revocation_message "AWS 連接失敗"
        exit 1
    fi
    
    echo -e "${GREEN}✓ AWS 連接成功${NC}"
    echo -e "${BLUE}當前 AWS 身份: $aws_user${NC}"
    log_revocation_message "AWS 連接成功，身份: $aws_user"
    
    # 檢查管理員權限
    local admin_check
    admin_check=$(aws ec2 describe-client-vpn-endpoints --max-items 1 2>/dev/null || echo "failed")
    
    if [[ "$admin_check" == "failed" ]]; then
        echo -e "${RED}權限不足：無法訪問 Client VPN 端點${NC}"
        echo -e "${YELLOW}請確認您有足夠的權限執行此操作${NC}"
        log_revocation_message "權限檢查失敗：無法訪問 Client VPN 端點"
        exit 1
    fi
    
    echo -e "${GREEN}✓ 權限檢查通過${NC}"
    log_revocation_message "權限檢查完成，操作者: $aws_user"
}

# 獲取撤銷資訊
get_revocation_info() {
    echo -e "\\n${YELLOW}[2/7] 獲取撤銷資訊...${NC}"
    
    # 使用 read_secure_input 和 validate_username 獲取用戶名
    echo -e "${BLUE}請輸入要撤銷訪問權限的用戶資訊：${NC}"
    read_secure_input "用戶名: " username "validate_username" || exit 1
    
    # 使用 validate_aws_region 獲取 AWS 區域
    aws_region=$(aws configure get region)
    if [ -z "$aws_region" ] || ! validate_aws_region "$aws_region"; then
        read_secure_input "請輸入 AWS 區域: " aws_region "validate_aws_region" || exit 1
    fi
    
    # 獲取 VPN 端點 ID
    echo -e "\\n${BLUE}可用的 Client VPN 端點：${NC}"
    local endpoints
    endpoints=$(aws ec2 describe-client-vpn-endpoints --region "$aws_region")
    echo "$endpoints" | jq -r '.ClientVpnEndpoints[] | "端點 ID: \\(.ClientVpnEndpointId), 狀態: \\(.Status.Code), 名稱: \\(.Tags[]? | select(.Key=="Name") | .Value // "無名稱")"'
    
    read_secure_input "請輸入 Client VPN 端點 ID: " endpoint_id "validate_endpoint_id" || exit 1
    
    # 驗證端點 ID
    local endpoint_check
    endpoint_check=$(aws ec2 describe-client-vpn-endpoints --client-vpn-endpoint-ids "$endpoint_id" --region "$aws_region" 2>/dev/null || echo "not_found")
    
    if [[ "$endpoint_check" == "not_found" ]]; then
        echo -e "${RED}無法找到指定的 VPN 端點${NC}"
        log_revocation_message "無法找到指定的 VPN 端點: $endpoint_id"
        exit 1
    fi
    
    echo -e "${GREEN}✓ VPN 端點驗證成功${NC}"
    
    # 撤銷原因
    echo -e "\\n${BLUE}請選擇撤銷原因：${NC}"
    echo -e "  ${GREEN}1.${NC} 人員離職"
    echo -e "  ${GREEN}2.${NC} 角色變更"
    echo -e "  ${GREEN}3.${NC} 安全事件"
    echo -e "  ${GREEN}4.${NC} 暫時停用"
    echo -e "  ${GREEN}5.${NC} 其他"
    
    local reason_choice
    read_secure_input "請選擇 (1-5): " reason_choice "validate_menu_choice" "1" "5" || exit 1
    
    case "$reason_choice" in
        1) revocation_reason="人員離職" ;;
        2) revocation_reason="角色變更" ;;
        3) revocation_reason="安全事件" ;;
        4) revocation_reason="暫時停用" ;;
        5) 
            local custom_reason
            read_secure_input "請輸入撤銷原因: " custom_reason "validate_username_allow_empty" # 允許空值，將使用預設
            revocation_reason="${custom_reason:-"其他"}"
            ;;
        *) revocation_reason="未指定" ;;
    esac
    
    # 確認資訊
    echo -e "\\n${CYAN}撤銷資訊確認：${NC}"
    echo -e "  用戶名: ${YELLOW}$username${NC}"
    echo -e "  VPN 端點 ID: ${YELLOW}$endpoint_id${NC}"
    echo -e "  AWS 區域: ${YELLOW}$aws_region${NC}"
    echo -e "  撤銷原因: ${YELLOW}$revocation_reason${NC}"
    
    log_revocation_message "準備撤銷用戶 $username 的訪問權限，原因: $revocation_reason"
}

# 搜尋用戶證書
find_user_certificates() {
    echo -e "\\n${YELLOW}[3/7] 搜尋用戶證書...${NC}"
    
    echo -e "${BLUE}正在 AWS Certificate Manager 中搜尋 ${username} 的證書...${NC}"
    
    # 列出所有證書
    local certificates
    certificates=$(aws acm list-certificates --region "$aws_region")
    
    # 搜索包含用戶名的證書
    user_cert_arns=()
    
    # 方法1: 通過域名搜索
    while IFS= read -r cert_arn; do
        if [ ! -z "$cert_arn" ]; then
            local cert_details domain_name
            cert_details=$(aws acm describe-certificate --certificate-arn "$cert_arn" --region "$aws_region")
            if ! domain_name=$(echo "$cert_details" | jq -r '.Certificate.DomainName // ""' 2>/dev/null); then
                # 備用解析方法：使用 grep 和 sed 提取域名
                domain_name=$(echo "$cert_details" | grep -o '"DomainName":"[^"]*"' | sed 's/"DomainName":"//g' | sed 's/"//g' | head -1)
            fi
            
            # 驗證解析結果
            if ! validate_json_parse_result "$domain_name" "證書域名" ""; then
                log_revocation_message "警告: 無法解析證書域名，跳過證書 $cert_arn"
                continue
            fi
            
            if [[ "$domain_name" == *"$username"* ]]; then
                user_cert_arns+=("$cert_arn")
                echo -e "${GREEN}✓ 找到證書 (域名匹配): $cert_arn${NC}"
            fi
        fi
    done <<< "$(echo "$certificates" | jq -r '.CertificateSummaryList[].CertificateArn' 2>/dev/null || echo "$certificates" | grep -o '"CertificateArn":"arn:aws:acm:[^"]*"' | sed 's/"CertificateArn":"//g' | sed 's/"//g')"
    
    # 方法2: 通過標籤搜索
    while IFS= read -r cert_arn; do
        if [ ! -z "$cert_arn" ]; then
            local tags contains_username
            tags=$(aws acm list-tags-for-certificate --certificate-arn "$cert_arn" --region "$aws_region" 2>/dev/null || echo '{"Tags":[]}')
            if ! contains_username=$(echo "$tags" | jq -r --arg username "$username" 'select(.Tags[] | select(.Key=="Name" or .Key=="User") | .Value | contains($username)) | true' 2>/dev/null); then
                # 備用解析方法：使用 grep 檢查標籤
                if echo "$tags" | grep -q "\"$username\""; then
                    contains_username="true"
                else
                    contains_username=""
                fi
            fi
            
            if [[ "$contains_username" == "true" ]] && [[ ! " ${user_cert_arns[@]} " =~ " ${cert_arn} " ]]; then
                user_cert_arns+=("$cert_arn")
                echo -e "${GREEN}✓ 找到證書 (標籤匹配): $cert_arn${NC}"
            fi
        fi
    done <<< "$(echo "$certificates" | jq -r '.CertificateSummaryList[].CertificateArn' 2>/dev/null || echo "$certificates" | grep -o '"CertificateArn":"arn:aws:acm:[^"]*"' | sed 's/"CertificateArn":"//g' | sed 's/"//g')"
    
    if [ ${#user_cert_arns[@]} -eq 0 ]; then
        echo -e "${YELLOW}未找到 ${username} 的證書${NC}"
        echo -e "${BLUE}請手動提供證書 ARN (如果知道的話):${NC}"
        local manual_cert_arn
        read_secure_input "證書 ARN (或按 Enter 跳過): " manual_cert_arn "validate_certificate_arn_allow_empty" # 允許空值
        
        if [ ! -z "$manual_cert_arn" ]; then
            user_cert_arns+=("$manual_cert_arn")
        fi
    else
        echo -e "${GREEN}找到 ${#user_cert_arns[@]} 個用戶證書${NC}"
    fi
    
    log_revocation_message "找到 ${#user_cert_arns[@]} 個 $username 的證書"
}

# 檢查當前連接
check_current_connections() {
    echo -e "\\n${YELLOW}[4/7] 檢查當前連接...${NC}"
    
    echo -e "${BLUE}檢查 ${username} 的活躍連接...${NC}"
    
    # 獲取當前連接
    local connections user_connections
    connections=$(aws ec2 describe-client-vpn-connections \\
      --client-vpn-endpoint-id "$endpoint_id" \\
      --region "$aws_region")
    
    # 搜索用戶的連接
    if ! user_connections=$(echo "$connections" | jq -r --arg username "$username" '.Connections[] | select(.CommonName | contains($username)) | .ConnectionId' 2>/dev/null); then
        # 備用解析方法：使用 grep 和 sed
        user_connections=$(echo "$connections" | grep -o '"ConnectionId":"[^"]*"' | sed 's/"ConnectionId":"//g' | sed 's/"//g' | while read conn_id; do
            if echo "$connections" | grep -A 5 -B 5 "$conn_id" | grep -q "\"$username\""; then
                echo "$conn_id"
            fi
        done)
    fi
    
    # 驗證解析結果
    if ! validate_json_parse_result "$user_connections" "用戶連接ID" ""; then
        log_revocation_message "警告: 無法解析用戶連接信息"
        user_connections=""
    fi
    
    if [ ! -z "$user_connections" ]; then
        echo -e "${RED}⚠ 發現用戶的活躍連接:${NC}"
        echo "$user_connections" | while read connection_id; do
            echo -e "  連接 ID: ${YELLOW}$connection_id${NC}"
        done
        
        local disconnect_choice
        read_secure_input "是否要斷開這些連接? (y/n): " disconnect_choice "validate_yes_no" || return 1
        
        if [[ "$disconnect_choice" =~ ^[Yy]$ ]]; then
            echo "$user_connections" | while read connection_id; do
                echo -e "${BLUE}斷開連接 $connection_id...${NC}"
                aws ec2 terminate-client-vpn-connections \\
                  --client-vpn-endpoint-id "$endpoint_id" \\
                  --connection-id "$connection_id" \\
                  --region "$aws_region"
            done
            echo -e "${GREEN}✓ 已斷開用戶的所有連接${NC}"
        fi
    else
        echo -e "${GREEN}✓ 未發現用戶的活躍連接${NC}"
    fi
    
    log_revocation_message "檢查並處理了 $username 的活躍連接"
}

# 撤銷證書和權限
revoke_certificates() {
    echo -e "\\n${YELLOW}[5/7] 撤銷證書和權限...${NC}"
    
    if [ ${#user_cert_arns[@]} -eq 0 ]; then
        echo -e "${YELLOW}沒有找到要撤銷的證書${NC}"
        return
    fi
    
    echo -e "${BLUE}開始撤銷證書...${NC}"
    
    revoked_certs=()
    failed_certs=()
    easyrsa_revoked=()
    easyrsa_failed=()
    
    # 第一步：執行本地 easyrsa 撤銷操作
    echo -e "\\n${CYAN}步驟 1: 執行本地 PKI 證書撤銷...${NC}"
    
    # 檢查 EasyRSA 目錄是否存在
    if [ ! -d "$EASYRSA_DIR_REVOKE" ]; then
        echo -e "${RED}錯誤: EasyRSA 目錄不存在: $EASYRSA_DIR_REVOKE${NC}"
        echo -e "${YELLOW}跳過本地證書撤銷操作${NC}"
    else
        echo -e "${BLUE}使用 EasyRSA 目錄: $EASYRSA_DIR_REVOKE${NC}"
        
        # 對於每個證書，嘗試從 ACM 標籤中獲取證書名稱並執行撤銷
        for cert_arn in "${user_cert_arns[@]}"; do
            echo -e "${BLUE}檢查證書: $cert_arn${NC}"
            
            # 從 ACM 獲取證書詳情和標籤
            local cert_tags
            cert_tags=$(aws acm list-tags-for-certificate --certificate-arn "$cert_arn" --region "$aws_region" 2>/dev/null)
            
            if [ $? -eq 0 ]; then
                # 嘗試從標籤中提取用戶名作為證書名稱
                local cert_name
                if command -v jq >/dev/null 2>&1; then
                    cert_name=$(echo "$cert_tags" | jq -r '.Tags[] | select(.Key=="User") | .Value' 2>/dev/null)
                else
                    # 備用方法：使用 grep 和 sed
                    cert_name=$(echo "$cert_tags" | grep -A1 '"Key": "User"' | grep '"Value"' | sed 's/.*"Value": "\([^"]*\)".*/\1/')
                fi
                
                if [ -n "$cert_name" ] && [ "$cert_name" != "null" ]; then
                    echo -e "${BLUE}找到證書名稱: $cert_name${NC}"
                    
                    # 執行本地 easyrsa 撤銷
                    if revoke_client_certificate_lib "$EASYRSA_DIR_REVOKE" "$cert_name" "$CONFIG_FILE"; then
                        echo -e "${GREEN}✓ 本地撤銷成功: $cert_name${NC}"
                        easyrsa_revoked+=("$cert_name")
                    else
                        echo -e "${RED}✗ 本地撤銷失敗: $cert_name${NC}"
                        easyrsa_failed+=("$cert_name")
                    fi
                else
                    echo -e "${YELLOW}無法從證書標籤中獲取用戶名，嘗試使用參數用戶名: $username${NC}"
                    
                    # 使用腳本參數中的用戶名嘗試撤銷
                    if revoke_client_certificate_lib "$EASYRSA_DIR_REVOKE" "$username" "$CONFIG_FILE"; then
                        echo -e "${GREEN}✓ 本地撤銷成功 (使用用戶名): $username${NC}"
                        easyrsa_revoked+=("$username")
                    else
                        echo -e "${RED}✗ 本地撤銷失敗 (使用用戶名): $username${NC}"
                        easyrsa_failed+=("$username")
                    fi
                fi
            else
                echo -e "${YELLOW}無法獲取證書標籤，跳過本地撤銷${NC}"
            fi
        done
        
        # 第二步：生成和更新 CRL
        if [ ${#easyrsa_revoked[@]} -gt 0 ]; then
            echo -e "\\n${CYAN}步驟 2: 生成和更新證書撤銷列表 (CRL)...${NC}"
            
            if generate_crl_lib "$EASYRSA_DIR_REVOKE"; then
                echo -e "${GREEN}✓ CRL 生成成功${NC}"
                
                # 第三步：將 CRL 導入到 VPN 端點
                echo -e "\\n${CYAN}步驟 3: 將 CRL 導入到 VPN 端點...${NC}"
                if import_crl_to_vpn_endpoint_lib "$EASYRSA_DIR_REVOKE" "$endpoint_id" "$aws_region"; then
                    echo -e "${GREEN}✓ CRL 已成功導入到 VPN 端點${NC}"
                else
                    echo -e "${RED}✗ CRL 導入到 VPN 端點失敗${NC}"
                    echo -e "${YELLOW}證書已在本地撤銷，但 VPN 端點可能需要手動更新 CRL${NC}"
                fi
            else
                echo -e "${RED}✗ CRL 生成失敗${NC}"
                echo -e "${YELLOW}證書已在本地撤銷，但 CRL 未更新${NC}"
            fi
        else
            echo -e "${YELLOW}沒有成功的本地撤銷操作，跳過 CRL 更新${NC}"
        fi
    fi
    
    # 第四步：處理 ACM 證書刪除/標記
    echo -e "\\n${CYAN}步驟 4: 處理 ACM 證書清理...${NC}"
    
    for cert_arn in "${user_cert_arns[@]}"; do
        echo -e "${BLUE}處理 ACM 證書: $cert_arn${NC}"
        
        # 嘗試刪除證書
        local delete_result
        delete_result=$(aws acm delete-certificate --certificate-arn "$cert_arn" --region "$aws_region" 2>&1 || echo "failed")
        
        if [[ "$delete_result" == "failed" ]] || [[ "$delete_result" == *"error"* ]]; then
            echo -e "${RED}✗ 無法刪除 ACM 證書 $cert_arn${NC}"
            echo -e "${YELLOW}錯誤詳情: $delete_result${NC}"
            failed_certs+=("$cert_arn")
            
            # 嘗試標記證書為已撤銷
            local tag_result
            tag_result=$(aws acm add-tags-to-certificate \\
              --certificate-arn "$cert_arn" \\
              --tags Key=Status,Value=Revoked Key=RevokedBy,Value="$(whoami)" Key=RevokedDate,Value="$(date -u +%Y-%m-%dT%H:%M:%SZ)" \\
              --region "$aws_region" 2>&1 || echo "tag_failed")
            
            if [[ "$tag_result" != "tag_failed" ]]; then
                echo -e "${YELLOW}已標記 ACM 證書為已撤銷${NC}"
            fi
        else
            echo -e "${GREEN}✓ 成功刪除 ACM 證書 $cert_arn${NC}"
            revoked_certs+=("$cert_arn")
        fi
    done
    
    # 顯示完整的撤銷結果
    echo -e "\\n${CYAN}完整證書撤銷結果:${NC}"
    echo -e "  ${GREEN}本地 PKI 撤銷成功:${NC} ${#easyrsa_revoked[@]} 個證書"
    echo -e "  ${RED}本地 PKI 撤銷失敗:${NC} ${#easyrsa_failed[@]} 個證書"
    echo -e "  ${GREEN}ACM 證書刪除成功:${NC} ${#revoked_certs[@]} 個證書"
    echo -e "  ${RED}ACM 證書刪除失敗:${NC} ${#failed_certs[@]} 個證書"
    
    if [ ${#easyrsa_revoked[@]} -gt 0 ]; then
        echo -e "\\n${GREEN}本地撤銷成功的證書:${NC}"
        for cert in "${easyrsa_revoked[@]}"; do
            echo -e "  ${GREEN}✓ $cert${NC}"
        done
    fi
    
    if [ ${#easyrsa_failed[@]} -gt 0 ]; then
        echo -e "\\n${YELLOW}本地撤銷失敗的證書:${NC}"
        for cert in "${easyrsa_failed[@]}"; do
            echo -e "  ${RED}✗ $cert${NC}"
        done
    fi
    
    if [ ${#failed_certs[@]} -gt 0 ]; then
        echo -e "\\n${YELLOW}ACM 刪除失敗的證書需要手動處理:${NC}"
        for cert in "${failed_certs[@]}"; do
            echo -e "  ${RED}\"$cert\"${NC}"
        done
    fi
    
    # 重要安全提醒
    if [ ${#easyrsa_revoked[@]} -gt 0 ]; then
        echo -e "\\n${GREEN}✓ 重要: 證書已在本地 PKI 系統中撤銷，VPN 端點的 CRL 已更新${NC}"
        echo -e "${GREEN}  用戶將無法再使用這些證書連接 VPN${NC}"
    else
        echo -e "\\n${RED}⚠ 警告: 沒有執行本地 PKI 撤銷操作${NC}"
        echo -e "${RED}  用戶可能仍然可以使用現有證書連接 VPN${NC}"
        echo -e "${YELLOW}  建議手動執行以下步驟:${NC}"
        echo -e "${YELLOW}  1. 進入 $EASYRSA_DIR_REVOKE${NC}"
        echo -e "${YELLOW}  2. 執行: ./easyrsa revoke $username${NC}"
        echo -e "${YELLOW}  3. 執行: ./easyrsa gen-crl${NC}"
        echo -e "${YELLOW}  4. 將 CRL 導入到 VPN 端點${NC}"
    fi
    
    log_revocation_message "證書撤銷完成 - 本地PKI成功: ${#easyrsa_revoked[@]}, 本地PKI失敗: ${#easyrsa_failed[@]}, ACM成功: ${#revoked_certs[@]}, ACM失敗: ${#failed_certs[@]}"
}

# 檢查和移除 IAM 權限
check_iam_permissions() {
    echo -e "\\n${YELLOW}[6/7] 檢查和處理 IAM 權限...${NC}"
    
    # 檢查是否有同名的 IAM 用戶
    local iam_user_exists
    iam_user_exists=$(aws iam get-user --user-name "$username" 2>/dev/null || echo "not_found")
    
    if [[ "$iam_user_exists" != "not_found" ]]; then
        echo -e "${BLUE}找到 IAM 用戶: $username${NC}"
        
        local handle_iam
        read_secure_input "是否要處理此 IAM 用戶的權限? (y/n): " handle_iam "validate_yes_no" || return 1
        
        if [[ "$handle_iam" =~ ^[Yy]$ ]]; then
            echo -e "${BLUE}處理 IAM 用戶權限...${NC}"
            
            # 列出並停用訪問密鑰
            echo -e "${BLUE}處理訪問密鑰...${NC}"
            local access_keys
            access_keys=$(aws iam list-access-keys --user-name "$username" --query 'AccessKeyMetadata[*].AccessKeyId' --output text)
            
            for key_id in $access_keys; do
                echo -e "${BLUE}停用訪問密鑰: $key_id${NC}"
                aws iam update-access-key --access-key-id "$key_id" --status Inactive --user-name "$username"
            done
            
            # 分離政策
            echo -e "${BLUE}分離用戶政策...${NC}"
            local attached_policies
            attached_policies=$(aws iam list-attached-user-policies --user-name "$username" --query 'AttachedPolicies[*].PolicyArn' --output text)
            for policy in $attached_policies; do
                echo -e "${BLUE}分離政策: $policy${NC}"
                aws iam detach-user-policy --user-name "$username" --policy-arn "$policy"
            done
            
            # 移除內嵌政策
            local inline_policies
            inline_policies=$(aws iam list-user-policies --user-name "$username" --query 'PolicyNames' --output text)
            for policy in $inline_policies; do
                echo -e "${BLUE}刪除內嵌政策: $policy${NC}"
                aws iam delete-user-policy --user-name "$username" --policy-name "$policy"
            done
            
            # 從群組中移除
            local user_groups
            user_groups=$(aws iam list-groups-for-user --user-name "$username" --query 'Groups[*].GroupName' --output text)
            for group in $user_groups; do
                echo -e "${BLUE}從群組移除: $group${NC}"
                aws iam remove-user-from-group --user-name "$username" --group-name "$group"
            done
            
            echo -e "${GREEN}✓ IAM 用戶權限已撤銷${NC}"
            
            # 詢問是否刪除用戶
            local delete_user
            read_secure_input "是否要刪除 IAM 用戶? (y/n): " delete_user "validate_yes_no" || return 1
            
            if [[ "$delete_user" =~ ^[Yy]$ ]]; then
                # 刪除訪問密鑰
                for key_id in $access_keys; do
                    echo -e "${BLUE}刪除訪問密鑰: $key_id${NC}"
                    aws iam delete-access-key --access-key-id "$key_id" --user-name "$username"
                done
                
                # 刪除用戶
                aws iam delete-user --user-name "$username"
                echo -e "${GREEN}✓ IAM 用戶已刪除${NC}"
            fi
        fi
    else
        echo -e "${GREEN}✓ 未找到同名的 IAM 用戶${NC}"
    fi
    
    log_revocation_message "IAM 權限檢查和處理完成"
}

# 生成撤銷報告
generate_revocation_report() {
    echo -e "\\n${YELLOW}[7/7] 生成撤銷報告...${NC}"
    
    # 創建報告文件
    local report_file="$REVOCATION_LOG_DIR/${username}_revocation_$(date +%Y%m%d_%H%M%S).log"
    
    cat > "$report_file" << EOF
=== AWS Client VPN 訪問權限撤銷報告 ===

撤銷時間: $(date)
操作者: $(whoami)
AWS 身份: $(aws sts get-caller-identity --query 'Arn' --output text)

被撤銷用戶資訊:
  用戶名: $username
  撤銷原因: $revocation_reason

VPN 端點資訊:
  端點 ID: $endpoint_id
  AWS 區域: $aws_region
  EasyRSA 目錄: $EASYRSA_DIR_REVOKE

本地 PKI 撤銷結果:
EOF
    
    if [ ${#easyrsa_revoked[@]} -gt 0 ]; then
        echo "  成功撤銷的本地證書:" >> "$report_file"
        for cert in "${easyrsa_revoked[@]}"; do
            echo "    ✓ $cert" >> "$report_file"
        done
    else
        echo "  無本地證書被成功撤銷" >> "$report_file"
    fi
    
    if [ ${#easyrsa_failed[@]} -gt 0 ]; then
        echo "" >> "$report_file"
        echo "  本地撤銷失敗的證書:" >> "$report_file"
        for cert in "${easyrsa_failed[@]}"; do
            echo "    ✗ $cert" >> "$report_file"
        done
    fi
    
    cat >> "$report_file" << EOF

ACM 證書處理結果:
EOF
    
    if [ ${#revoked_certs[@]} -gt 0 ]; then
        echo "  成功刪除的 ACM 證書:" >> "$report_file"
        for cert in "${revoked_certs[@]}"; do
            echo "    ✓ $cert" >> "$report_file"
        done
    else
        echo "  無 ACM 證書被刪除" >> "$report_file"
    fi
    
    if [ ${#failed_certs[@]} -gt 0 ]; then
        echo "" >> "$report_file"
        echo "  ACM 刪除失敗的證書:" >> "$report_file"
        for cert in "${failed_certs[@]}"; do
            echo "    ✗ $cert" >> "$report_file"
        done
    fi
    
    cat >> "$report_file" << EOF

IAM 用戶處理:
  $([ "$iam_user_exists" != "not_found" ] && echo "已處理同名 IAM 用戶" || echo "未發現同名 IAM 用戶")

安全狀態評估:
EOF
    
    if [ ${#easyrsa_revoked[@]} -gt 0 ]; then
        echo "  ✓ 證書已在本地 PKI 系統中正確撤銷" >> "$report_file"
        echo "  ✓ 證書撤銷列表 (CRL) 已更新並導入 VPN 端點" >> "$report_file"
        echo "  ✓ 用戶無法再使用被撤銷的證書連接 VPN" >> "$report_file"
    else
        echo "  ⚠ 警告: 證書未在本地 PKI 系統中撤銷" >> "$report_file"
        echo "  ⚠ 用戶可能仍然可以使用現有證書連接 VPN" >> "$report_file"
        echo "  ⚠ 需要手動執行本地證書撤銷操作" >> "$report_file"
    fi
    
    cat >> "$report_file" << EOF

後續建議:
  1. 監控日誌，確認沒有來自此用戶的連接嘗試
  2. 檢查生產環境訪問日誌
  3. 如需重新授權，需要重新生成證書
  4. 更新團隊的用戶清單文檔
EOF
    
    if [ ${#easyrsa_failed[@]} -gt 0 ] || [ ${#easyrsa_revoked[@]} -eq 0 ]; then
        cat >> "$report_file" << EOF
  5. ⚠ 手動完成證書撤銷步驟:
     a. 進入目錄: $EASYRSA_DIR_REVOKE
     b. 執行撤銷: ./easyrsa revoke $username
     c. 生成 CRL: ./easyrsa gen-crl
     d. 導入 CRL 到 VPN 端點: $endpoint_id
EOF
    fi
    
    cat >> "$report_file" << EOF

操作完成時間: $(date)
EOF
    
    echo -e "${GREEN}✓ 撤銷報告已生成: ${BLUE}$report_file${NC}"
    
    # 顯示摘要
    echo -e "\\n${CYAN}撤銷操作摘要:${NC}"
    echo -e "  被撤銷用戶: ${YELLOW}$username${NC}"
    echo -e "  撤銷原因: ${YELLOW}$revocation_reason${NC}"
    echo -e "  本地 PKI 撤銷: ${GREEN}${#easyrsa_revoked[@]} 成功${NC}, ${RED}${#easyrsa_failed[@]} 失敗${NC}"
    echo -e "  ACM 證書處理: ${GREEN}${#revoked_certs[@]} 成功${NC}, ${RED}${#failed_certs[@]} 失敗${NC}"
    echo -e "  IAM 用戶: $([ "$iam_user_exists" != "not_found" ] && echo "${YELLOW}已處理${NC}" || echo "${GREEN}未涉及${NC}")"
    echo -e "  報告文件: ${BLUE}$report_file${NC}"
    
    # 安全狀態指示
    if [ ${#easyrsa_revoked[@]} -gt 0 ]; then
        echo -e "  安全狀態: ${GREEN}✓ 撤銷完整，用戶無法連接 VPN${NC}"
    else
        echo -e "  安全狀態: ${RED}⚠ 不完整，需要手動完成撤銷${NC}"
    fi
    
    log_revocation_message "撤銷報告已生成: $report_file"
}

# 顯示最終指示
show_final_instructions() {
    echo -e "\\n${GREEN}=============================================${NC}"
    echo -e "${GREEN}     訪問權限撤銷操作完成！          ${NC}"
    echo -e "${GREEN}=============================================${NC}"
    echo -e ""
    
    # 根據撤銷結果顯示不同的安全狀態
    if [ ${#easyrsa_revoked[@]} -gt 0 ]; then
        echo -e "${GREEN}✓ 證書撤銷狀態: 完整${NC}"
        echo -e "${GREEN}  • 證書已在本地 PKI 系統中撤銷${NC}"
        echo -e "${GREEN}  • 證書撤銷列表 (CRL) 已更新${NC}"
        echo -e "${GREEN}  • VPN 端點已應用最新的 CRL${NC}"
        echo -e "${GREEN}  • 用戶無法再使用被撤銷的證書連接${NC}"
    else
        echo -e "${RED}⚠ 證書撤銷狀態: 不完整${NC}"
        echo -e "${RED}  • 證書未在本地 PKI 系統中撤銷${NC}"
        echo -e "${RED}  • 用戶可能仍然可以使用現有證書連接${NC}"
        echo -e "${YELLOW}  • 需要手動完成撤銷操作${NC}"
    fi
    
    echo -e ""
    echo -e "${CYAN}後續確認步驟：${NC}"
    echo -e "${BLUE}1.${NC} 監控 VPN 連接日誌，確認用戶無法連接"
    echo -e "${BLUE}2.${NC} 檢查 AWS CloudWatch 中的 VPN 日誌"
    echo -e "${BLUE}3.${NC} 確認生產環境中沒有來自此用戶的活動"
    echo -e "${BLUE}4.${NC} 更新團隊的訪問權限文檔"
    
    # 如果需要手動完成撤銷，顯示具體步驟
    if [ ${#easyrsa_failed[@]} -gt 0 ] || [ ${#easyrsa_revoked[@]} -eq 0 ]; then
        echo -e ""
        echo -e "${RED}⚠ 需要手動完成的操作：${NC}"
        echo -e "${YELLOW}5.${NC} 完成證書撤銷（關鍵安全步驟）："
        echo -e "   ${BLUE}a.${NC} 進入目錄: ${CYAN}cd $EASYRSA_DIR_REVOKE${NC}"
        echo -e "   ${BLUE}b.${NC} 撤銷證書: ${CYAN}./easyrsa revoke $username${NC}"
        echo -e "   ${BLUE}c.${NC} 生成 CRL: ${CYAN}./easyrsa gen-crl${NC}"
        echo -e "   ${BLUE}d.${NC} 導入 CRL: ${CYAN}aws ec2 import-client-vpn-client-certificate-revocation-list --client-vpn-endpoint-id $endpoint_id --certificate-revocation-list fileb://pki/crl.pem --region $aws_region${NC}"
    fi
    
    echo -e ""
    echo -e "${CYAN}安全建議：${NC}"
    echo -e "${BLUE}•${NC} 持續監控異常訪問嘗試"
    echo -e "${BLUE}•${NC} 定期審計 VPN 用戶權限"
    echo -e "${BLUE}•${NC} 保留撤銷記錄以備審計"
    echo -e "${BLUE}•${NC} 如需重新授權，請重新生成證書"
    echo -e "${BLUE}•${NC} 確認證書撤銷列表 (CRL) 定期更新"
    echo -e ""
    
    # 顯示不同的完成狀態
    if [ ${#easyrsa_revoked[@]} -gt 0 ]; then
        echo -e "${GREEN}操作完成！用戶已被安全地撤銷 VPN 訪問權限。${NC}"
    else
        echo -e "${YELLOW}操作部分完成。請執行上述手動步驟以確保完整的安全撤銷。${NC}"
        echo -e "${RED}在完成手動步驟之前，用戶可能仍然可以連接 VPN！${NC}"
    fi
    
    echo -e ""
    echo -e "${YELLOW}如果發現任何問題，請立即聯繫安全團隊${NC}"
    echo -e ""
}

# 確認操作
confirm_revocation() {
    echo -e "\\n${RED}========================================${NC}"
    echo -e "${RED}           最終確認                     ${NC}"
    echo -e "${RED}========================================${NC}"
    echo -e ""
    echo -e "${RED}您即將撤銷以下用戶的 VPN 訪問權限：${NC}"
    echo -e "  用戶名: ${YELLOW}$username${NC}"
    echo -e "  原因: ${YELLOW}$revocation_reason${NC}"
    echo -e "  影響的證書: ${YELLOW}${#user_cert_arns[@]} 個${NC}"
    echo -e ""
    echo -e "${RED}此操作將會：${NC}"
    echo -e "${RED}  • 刪除用戶的客戶端證書${NC}"
    echo -e "${RED}  • 斷開用戶的當前連接${NC}"
    echo -e "${RED}  • 阻止用戶未來的連接${NC}"
    echo -e "${RED}  • 可能影響用戶的 IAM 權限${NC}"
    echo -e ""
    echo -e "${RED}此操作無法撤銷！${NC}"
    echo -e ""
    
    local final_confirm
    read_secure_input "確認撤銷? 請輸入 'REVOKE' 來確認: " final_confirm # 不使用驗證函數，因為需要精確匹配 'REVOKE'
    
    if [ "$final_confirm" != "REVOKE" ]; then
        echo -e "${BLUE}撤銷操作已取消${NC}"
        log_revocation_message "用戶取消了 $username 的撤銷操作"
        exit 0
    fi
    
    log_revocation_message "用戶確認撤銷 $username 的訪問權限"
}

# 主函數
main() {
    # 環境操作驗證
    if ! env_validate_operation "REVOKE_ACCESS"; then
        return 1
    fi
    
    # 記錄操作開始
    log_env_action "REVOKE_ACCESS_START" "開始撤銷用戶訪問權限"
    
    # 顯示歡迎訊息
    show_welcome
    
    # 執行撤銷步驟
    check_revocation_prerequisites
    get_revocation_info
    find_user_certificates
    
    # 最終確認
    confirm_revocation
    
    # 執行撤銷操作
    check_current_connections
    revoke_certificates
    check_iam_permissions
    generate_revocation_report
    
    # 顯示最終指示
    show_final_instructions
    
    log_env_action "REVOKE_ACCESS_COMPLETE" "訪問權限撤銷操作完成"
}

# 記錄腳本啟動
log_revocation_message "訪問權限撤銷腳本已啟動"

# 執行主程序
main