#!/bin/bash

# AWS Client VPN 管理員主腳本 for macOS
# 用途：建立、管理和刪除 AWS Client VPN 端點
# 作者：VPN 管理員
# 版本：1.0

# 全域變數
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 載入環境管理器 (必須第一個載入)
source "$SCRIPT_DIR/../lib/env_manager.sh"

# 初始化環境
if ! env_init_for_script "aws_vpn_admin.sh"; then
    echo -e "${RED}錯誤: 無法初始化環境管理器${NC}"
    exit 1
fi

# 驗證 AWS Profile 整合
echo -e "${BLUE}正在驗證 AWS Profile 設定...${NC}"
if ! env_validate_profile_integration "$CURRENT_ENVIRONMENT" "true"; then
    echo -e "${YELLOW}警告: AWS Profile 設定可能有問題，但繼續執行管理員工具${NC}"
fi

# 設定環境特定路徑
env_setup_paths

# 環境感知的配置檔案
# For creation: use environment config (.env) for user-configurable values
# For management: use endpoint config (.conf) for auto-generated values
ENV_CONFIG_FILE="$VPN_CONFIG_DIR/${CURRENT_ENVIRONMENT}.env"
ENDPOINT_CONFIG_FILE="$VPN_ENDPOINT_CONFIG_FILE"
CONFIG_FILE="$ENV_CONFIG_FILE"  # Primary config for creation process
LOG_FILE="$VPN_ADMIN_LOG_FILE"

# 載入核心函式庫
source "$SCRIPT_DIR/../lib/core_functions.sh"
source "$SCRIPT_DIR/../lib/aws_setup.sh"
source "$SCRIPT_DIR/../lib/cert_management.sh"
source "$SCRIPT_DIR/../lib/endpoint_creation.sh"
source "$SCRIPT_DIR/../lib/endpoint_management.sh"

# S3 零接觸支援函數
upload_public_assets_to_s3() {
    local bucket_name="${1:-vpn-csr-exchange}"
    
    # 檢查是否有 publish_endpoints.sh 工具
    local publish_script="$SCRIPT_DIR/publish_endpoints.sh"
    if [ -x "$publish_script" ]; then
        echo -e "${BLUE}正在更新 S3 公用資產...${NC}"
        if "$publish_script" -b "$bucket_name" -e "$CURRENT_ENV" --force; then
            echo -e "${GREEN}✓ S3 公用資產已更新${NC}"
            return 0
        else
            echo -e "${YELLOW}⚠ S3 資產更新失敗${NC}"
            return 1
        fi
    else
        echo -e "${YELLOW}⚠ 找不到 publish_endpoints.sh，跳過 S3 更新${NC}"
        return 1
    fi
}

# 不使用 set -e，改用手動錯誤處理以避免程式意外退出

# 顯示主選單
show_menu() {
    clear
    show_env_aware_header "AWS Client VPN 管理員控制台"
    
    # 顯示 AWS Profile 資訊
    local current_profile
    current_profile=$(env_get_profile "$CURRENT_ENVIRONMENT" 2>/dev/null)
    if [[ -n "$current_profile" ]]; then
        # 獲取 AWS 帳戶資訊
        if command -v aws &> /dev/null && aws configure list-profiles | grep -q "^$current_profile$"; then
            local account_id region
            account_id=$(aws sts get-caller-identity --profile "$current_profile" --query Account --output text 2>/dev/null)
            region=$(aws configure get region --profile "$current_profile" 2>/dev/null)
            
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
            echo -e "  Profile: ${RED}$current_profile (不存在)${NC}"
        fi
    else
        echo -e "${CYAN}AWS 配置狀態:${NC}"
        echo -e "  Profile: ${YELLOW}未設定${NC}"
    fi
    echo -e ""
    
    echo -e "${BLUE}選擇操作：${NC}"
    echo -e "  ${GREEN}1.${NC} 建立新的 VPN 端點"
    echo -e "  ${GREEN}2.${NC} 查看現有 VPN 端點"
    echo -e "  ${GREEN}3.${NC} 管理 VPN 端點設定"
    echo -e "  ${GREEN}4.${NC} 刪除 VPN 端點"
    echo -e "  ${GREEN}5.${NC} 查看連接日誌"
    echo -e "  ${GREEN}6.${NC} 匯出團隊成員設定檔"
    echo -e "  ${GREEN}7.${NC} 查看管理員指南"
    echo -e "  ${GREEN}8.${NC} 系統健康檢查"
    echo -e "  ${GREEN}9.${NC} 多 VPC 管理"
    echo -e "  ${YELLOW}E.${NC} 環境管理"
    echo -e "  ${YELLOW}P.${NC} Profile 管理"
    echo -e "  ${RED}10.${NC} 退出"
    echo -e ""
    echo -e "${CYAN}========================================================${NC}"
}

# 建立 VPN 端點
create_vpn_endpoint() {
    echo -e "\\n${CYAN}=== 建立新的 VPN 端點 ===${NC}"
    
    # 設定專案根目錄路徑
    local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    local PROJECT_ROOT="$(dirname "$script_dir")"
    
    # 環境操作驗證
    if ! env_validate_operation "CREATE_ENDPOINT"; then
        return 1
    fi
    
    # 記錄操作開始
    log_env_action "CREATE_ENDPOINT_START" "開始建立 VPN 端點"
    
    # 載入配置或執行初始設定
    if [ -f "$CONFIG_FILE" ]; then
        if ! load_config_core "$CONFIG_FILE"; then
            echo -e "${RED}載入配置文件失敗${NC}"
            return 1
        fi
    else
        setup_aws_config_lib "$CONFIG_FILE" # 使用庫函數避免衝突
        if ! load_config_core "$CONFIG_FILE"; then
            echo -e "${RED}設定後載入配置文件失敗${NC}"
            return 1
        fi
    fi

    if [ -z "$AWS_REGION" ]; then
        echo -e "${RED}AWS 地區未設定。請檢查 .vpn_config 或重新執行設定。${NC}"
        return 1
    fi
    
    # 1. 生成證書 (如果不存在) - 使用環境感知路徑
    if [ ! -f "$VPN_CERT_DIR/pki/ca.crt" ]; then
        generate_certificates_lib "$VPN_CERT_DIR" "$CONFIG_FILE"
        if [ $? -ne 0 ]; then
            echo -e "${RED}證書生成失敗。中止操作。${NC}"
            return 1
        fi
    fi
    
    # 2. 導入證書到 ACM - 使用環境感知路徑
    local acm_arns_result
    acm_arns_result=$(import_certificates_to_acm_lib "$VPN_CERT_DIR" "$AWS_REGION")
    if [ $? -ne 0 ]; then
        echo -e "${RED}導入證書到 ACM 失敗。中止操作。${NC}"
        return 1
    fi
    
    local main_server_cert_arn # 更清楚的命名以避免與 CONFIG_FILE 中的變數衝突
    local main_client_cert_arn
    
    # 解析 JSON 回應中的證書 ARN
    # import_certificates_to_acm_lib 現在返回 JSON 格式
    # 例如: {"server_cert_arn": "arn1", "client_cert_arn": "arn2"}
    
    # 記錄用於調試的 ACM 結果
    log_message "ACM 導入結果: $acm_arns_result"
    
    if command -v jq >/dev/null 2>&1; then
        # 如果系統有 jq，使用 jq 解析
        if ! main_server_cert_arn=$(echo "$acm_arns_result" | jq -r '.server_cert_arn' 2>/dev/null); then
            echo -e "${RED}錯誤: 無法使用 jq 解析伺服器證書 ARN${NC}" >&2
            echo -e "${YELLOW}ACM 導入原始結果: $acm_arns_result${NC}" >&2
            handle_error "無法從 ACM 導入結果中解析伺服器證書 ARN。"
            return 1
        fi
        if ! main_client_cert_arn=$(echo "$acm_arns_result" | jq -r '.client_cert_arn' 2>/dev/null); then
            echo -e "${RED}錯誤: 無法使用 jq 解析客戶端證書 ARN${NC}" >&2
            echo -e "${YELLOW}ACM 導入原始結果: $acm_arns_result${NC}" >&2
            handle_error "無法從 ACM 導入結果中解析客戶端證書 ARN。"
            return 1
        fi
    else
        # 備用解析方法：使用 sed 和 grep 從 JSON 中提取 ARN
        main_server_cert_arn=$(echo "$acm_arns_result" | grep -o '"server_cert_arn":"[^"]*"' | sed 's/"server_cert_arn":"\([^"]*\)"/\1/')
        main_client_cert_arn=$(echo "$acm_arns_result" | grep -o '"client_cert_arn":"[^"]*"' | sed 's/"client_cert_arn":"\([^"]*\)"/\1/')
        
        # 使用通用驗證函數進行錯誤檢查
        if ! validate_json_parse_result "$main_server_cert_arn" "伺服器證書 ARN" "validate_certificate_arn"; then
            echo -e "${YELLOW}ACM 導入原始結果: $acm_arns_result${NC}" >&2
            return 1
        fi
        
        if ! validate_json_parse_result "$main_client_cert_arn" "客戶端證書 ARN" "validate_certificate_arn"; then
            echo -e "${YELLOW}ACM 導入原始結果: $acm_arns_result${NC}" >&2
            return 1
        fi
    fi

    if [ -z "$main_server_cert_arn" ] || [ "$main_server_cert_arn" == "null" ] || \
       [ -z "$main_client_cert_arn" ] || [ "$main_client_cert_arn" == "null" ]; then
        handle_error "從 ACM 導入結果中獲取的證書 ARN 無效。"
        return 1
    fi

    # 更新配置文件
    # 這裡假設有一個函式可以更新 CONFIG_FILE 中的 ARN 值
    # update_config_arns "$CONFIG_FILE" "$main_server_cert_arn" "$main_client_cert_arn"

    log_message "ACM Server Cert ARN: $main_server_cert_arn"
    log_message "ACM Client Cert ARN: $main_client_cert_arn"

    # 3. 調用庫函式創建端點
    # 將 ARNs 作為參數傳遞
    # create_vpn_endpoint_lib 會處理網絡資訊提示、端點創建、關聯、授權、路由和保存配置
    # 使用環境配置中的 VPC 和子網路設定，不再需要使用者互動選擇
    local vpc_id subnet_id vpn_cidr vpn_name security_groups
    
    # 從環境配置獲取網路設定
    vpc_id="$VPC_ID"
    subnet_id="$SUBNET_ID"
    vpn_cidr="$VPN_CIDR"
    vpn_name="$VPN_NAME"
    
    # 驗證環境配置中的網路設定是否有效
    echo -e "\\n${BLUE}驗證環境配置中的網路設定...${NC}"
    
    # 驗證 VPC 是否存在
    if ! aws ec2 describe-vpcs --vpc-ids "$vpc_id" --region "$AWS_REGION" >/dev/null 2>&1; then
        handle_error "環境配置中的 VPC ID '$vpc_id' 無效或不存在於區域 '$AWS_REGION'。請檢查 VPC_ID 設定。"
        return 1
    fi
    
    # 驗證子網路是否存在且屬於指定的 VPC
    local subnet_vpc_id
    if ! subnet_vpc_id=$(aws ec2 describe-subnets --subnet-ids "$subnet_id" --region "$AWS_REGION" --query 'Subnets[0].VpcId' --output text 2>/dev/null); then
        handle_error "環境配置中的子網路 ID '$subnet_id' 無效或不存在於區域 '$AWS_REGION'。請檢查 SUBNET_ID 設定。"
        return 1
    fi
    
    if [ "$subnet_vpc_id" != "$vpc_id" ]; then
        handle_error "子網路 '$subnet_id' 不屬於 VPC '$vpc_id'。請檢查環境配置中的 VPC_ID 和 SUBNET_ID 設定。"
        return 1
    fi
    
    echo -e "${GREEN}✓ VPC ID: $vpc_id${NC}"
    echo -e "${GREEN}✓ 子網路 ID: $subnet_id${NC}"
    echo -e "${GREEN}✓ VPN CIDR: $vpn_cidr${NC}"
    echo -e "${GREEN}✓ VPN 名稱: $vpn_name${NC}"
    
    # 創建專用的 Client VPN 安全群組
    echo -e "\\n${BLUE}正在設定 Client VPN 專用安全群組...${NC}"
    
    # 載入 endpoint_creation.sh 以使用安全群組創建函式
    local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    local lib_dir="$(dirname "$script_dir")/lib"
    if [ -f "$lib_dir/endpoint_creation.sh" ]; then
        source "$lib_dir/endpoint_creation.sh"
    else
        echo -e "${RED}錯誤: 無法載入 endpoint_creation.sh 庫${NC}"
        return 1
    fi
    
    # 創建專用安全群組
    local client_vpn_sg_id
    client_vpn_sg_id=$(create_dedicated_client_vpn_security_group "$vpc_id" "$AWS_REGION" "$CURRENT_ENVIRONMENT")
    
    if [ $? -ne 0 ] || [ -z "$client_vpn_sg_id" ]; then
        echo -e "${RED}錯誤: 無法創建專用的 Client VPN 安全群組${NC}"
        echo -e "${YELLOW}回退到環境配置中的安全群組設定...${NC}"
        
        # 回退到環境配置獲取 security_groups (可選參數)
        security_groups="${VPN_SECURITY_GROUPS:-}"
        if [ -n "$security_groups" ]; then
            echo -e "${GREEN}✓ Security Groups: $security_groups${NC}"
        else
            echo -e "${GREEN}✓ Security Groups: 無 (使用 AWS 預設)${NC}"
        fi
    else
        # 使用新創建的專用安全群組
        security_groups="$client_vpn_sg_id"
        echo -e "${GREEN}✓ 已創建並將使用專用 Client VPN 安全群組: $client_vpn_sg_id${NC}"
        echo -e "${GREEN}✓ Security Groups: $security_groups${NC}"
        
        # 立即保存 CLIENT_VPN_SECURITY_GROUP_ID 到 VPN 端點配置文件 (.conf)
        local vpn_endpoint_conf="$PROJECT_ROOT/configs/${CURRENT_ENVIRONMENT}/vpn_endpoint.conf"
        if [ -f "$vpn_endpoint_conf" ]; then
            update_config "$vpn_endpoint_conf" "CLIENT_VPN_SECURITY_GROUP_ID" "$client_vpn_sg_id"
            echo -e "${GREEN}✓ CLIENT_VPN_SECURITY_GROUP_ID 已保存到 vpn_endpoint.conf: $client_vpn_sg_id${NC}"
        else
            echo -e "${YELLOW}警告: vpn_endpoint.conf 不存在，將保存到主配置文件${NC}"
            update_config "$CONFIG_FILE" "CLIENT_VPN_SECURITY_GROUP_ID" "$client_vpn_sg_id"
        fi
    fi

    # 更新配置文件
    update_config "$CONFIG_FILE" "VPC_ID" "$vpc_id"
    update_config "$CONFIG_FILE" "SUBNET_ID" "$subnet_id"
    update_config "$CONFIG_FILE" "VPN_CIDR" "$vpn_cidr"
    update_config "$CONFIG_FILE" "VPN_NAME" "$vpn_name"
    update_config "$CONFIG_FILE" "SECURITY_GROUPS" "$security_groups"
    # Certificate ARNs will be saved to vpn_endpoint.conf by the endpoint creation function

    # 呼叫核心創建函式
    echo -e "\\n${CYAN}=== 開始創建 VPN 端點 ===${NC}"
    local creation_output
    if ! creation_output=$(create_vpn_endpoint_lib "$CONFIG_FILE" "$AWS_REGION" "$vpc_id" "$subnet_id" "$vpn_cidr" "$vpn_name" "$main_server_cert_arn" "$main_client_cert_arn" "$security_groups"); then # Pass all required args
        echo -e "${RED}VPN 端點創建過程中發生錯誤。${NC}" # Bug fix item 5
        log_message "VPN 端點創建過程中發生錯誤。"
        return 1
    fi
    # Extract just the endpoint ID from the output, ignoring console messages
    if [[ "$creation_output" =~ ENDPOINT_ID_RESULT=([a-zA-Z0-9-]+) ]]; then
        export ENDPOINT_ID="${BASH_REMATCH[1]}"
    else
        # Fallback: try to extract using grep and cut
        export ENDPOINT_ID=$(echo "$creation_output" | grep "ENDPOINT_ID_RESULT=" | tail -1 | cut -d'=' -f2)
    fi
    
    # Validate that we extracted a valid endpoint ID
    if [[ -z "$ENDPOINT_ID" || ! "$ENDPOINT_ID" =~ ^cvpn-endpoint-[a-f0-9]{17}$ ]]; then
        log_message "錯誤: 無法從函數輸出中提取有效的 ENDPOINT_ID"
        log_message "原始輸出: $creation_output"
        return 1
    fi
    
    # 保存 ENDPOINT_ID 到配置文件
    update_config "$CONFIG_FILE" "ENDPOINT_ID" "$ENDPOINT_ID"
    
    # 同時更新環境配置文件中的 ENDPOINT_ID
    local env_config_file="$CONFIG_DIR/${CURRENT_ENVIRONMENT}.env"
    if [ -f "$env_config_file" ]; then
        update_config "$env_config_file" "ENDPOINT_ID" "$ENDPOINT_ID"
        echo -e "${GREEN}✓ ENDPOINT_ID 已保存到環境配置: $ENDPOINT_ID${NC}"
        
        # 同時確保 CLIENT_VPN_SECURITY_GROUP_ID 保存到 vpn_endpoint.conf (如果存在且尚未保存)
        if [ -n "$client_vpn_sg_id" ]; then
            local vpn_endpoint_conf="$PROJECT_ROOT/configs/${CURRENT_ENVIRONMENT}/vpn_endpoint.conf"
            if [ -f "$vpn_endpoint_conf" ]; then
                # 檢查是否已經保存過
                if ! grep -q "CLIENT_VPN_SECURITY_GROUP_ID=\"$client_vpn_sg_id\"" "$vpn_endpoint_conf"; then
                    update_config "$vpn_endpoint_conf" "CLIENT_VPN_SECURITY_GROUP_ID" "$client_vpn_sg_id"
                    echo -e "${GREEN}✓ CLIENT_VPN_SECURITY_GROUP_ID 已確認保存到 vpn_endpoint.conf${NC}"
                fi
            fi
        fi
    fi

    # 重新載入配置以獲取新創建的 ENDPOINT_ID
    if ! load_config_core "$CONFIG_FILE"; then
        echo -e "${RED}錯誤：無法重新載入更新的配置文件${NC}"
        return 1
    fi

    if [ -z "$ENDPOINT_ID" ]; then
        echo -e "${RED}錯誤：未能從配置文件中讀取新創建的 ENDPOINT_ID。${NC}"
        return 1
    fi
    
    # 4. 調用庫函式來處理額外的 VPC 關聯
    # AWS_REGION 和 ENDPOINT_ID 應該在 source "$CONFIG_FILE" 後可用
    if [ -n "$ENDPOINT_ID" ] && [ -n "$AWS_REGION" ]; then
        associate_additional_vpc_lib "$CONFIG_FILE" "$AWS_REGION" "$ENDPOINT_ID"
        if [ $? -ne 0 ]; then
            echo -e "${RED}關聯額外 VPC 過程中發生錯誤。${NC}"
            # 根據需要決定是否中止或繼續
        fi
        # associate_additional_vpc_lib 會更新 CONFIG_FILE，所以重新 source
        if ! load_config_core "$CONFIG_FILE"; then
            echo -e "${RED}錯誤：無法重新載入配置文件${NC}"
            return 1
        fi
        # 需要確保 ENDPOINT_ID 已正確設定
        if [ -z "$ENDPOINT_ID" ]; then
            echo -e "${RED}錯誤：ENDPOINT_ID 未設定${NC}"
            return 1
        fi
    else
        echo -e "${RED}錯誤：ENDPOINT_ID 或 AWS_REGION 未設定，無法進行額外 VPC 關聯。${NC}"
        # 這是嚴重錯誤，可能表示主端點創建失敗
        return 1
    fi
    
    # 主端點創建和額外 VPC 關聯完成後，日誌和管理員配置生成仍然需要
    log_message "VPN 端點 $ENDPOINT_ID 相關操作完成 (主體創建和額外 VPC 關聯由 lib 完成)"
    
    # 生成管理員配置檔案 (使用庫函式) - 使用環境感知路徑
    generate_admin_config_lib "$VPN_CERT_DIR" "$CONFIG_FILE"
    local admin_config_result=$?
    log_operation_result "生成管理員配置檔案" "$admin_config_result" "aws_vpn_admin.sh"
    
    if [ "$admin_config_result" -ne 0 ]; then
        echo -e "${RED}生成管理員配置檔案過程中發生錯誤。${NC}"
    fi
    
    # Note: Security group configuration is now handled during endpoint creation
    # Skip duplicate prompt to avoid repeating discovery process
    log_message "Security group configuration completed during endpoint creation"
    
    # 最終提醒：安全群組配置腳本
    echo -e "\n${CYAN}========================================================${NC}"
    echo -e "${GREEN}🎉 VPN 端點創建流程已完成！${NC}"
    echo -e "${CYAN}========================================================${NC}"
    echo
    echo -e "${YELLOW}📋 下一步操作：${NC}"
    echo -e "1️⃣ ${BLUE}檢查生成的腳本${NC}：${YELLOW}security_group_commands_${CURRENT_ENVIRONMENT}.sh${NC}"
    echo -e "2️⃣ ${BLUE}編輯並執行腳本${NC}：配置服務訪問權限"
    echo -e "3️⃣ ${BLUE}生成客戶端證書${NC}：使用 ${CYAN}./team_member_setup.sh${NC}"
    echo -e "4️⃣ ${BLUE}測試 VPN 連接${NC}：驗證設定是否正確"
    echo
    echo -e "${GREEN}✅ VPN 端點 ID：${BLUE}$ENDPOINT_ID${NC}"
    echo -e "${GREEN}✅ VPN 安全群組：${BLUE}$client_vpn_sg_id${NC}"
    echo -e "${CYAN}========================================================${NC}"
    
    echo -e "\\n${YELLOW}按任意鍵繼續...${NC}"
    read -n 1
}


# 查看現有 VPN 端點
list_vpn_endpoints() {
    echo -e "\\n${CYAN}=== 現有 VPN 端點 ===${NC}"
    
    # 驗證配置
    if ! validate_main_config "$CONFIG_FILE"; then
        echo -e "\\n${YELLOW}按任意鍵繼續...${NC}"
        read -n 1
        return 1
    fi
    
    # 調用庫函式
    list_vpn_endpoints_lib "$AWS_REGION" "$CONFIG_FILE"
    local result=$?
    
    log_operation_result "查看現有 VPN 端點" "$result" "aws_vpn_admin.sh"
    
    if [ "$result" -ne 0 ]; then
        echo -e "${RED}查看端點列表過程中發生錯誤。${NC}"
    fi
    
    echo -e "\\n${YELLOW}按任意鍵繼續...${NC}"
    read -n 1
}

# 管理 VPN 端點設定
manage_vpn_settings() {
    echo -e "\n${CYAN}=== 管理 VPN 端點設定 ===${NC}"
    
    # 使用統一的端點操作驗證 (use endpoint config for existing endpoints)
    if ! validate_endpoint_operation "$ENDPOINT_CONFIG_FILE"; then
        echo -e "\\n${YELLOW}按任意鍵繼續...${NC}"
        read -n 1
        return 1
    fi
    
    echo -e "${BLUE}當前端點 ID: $ENDPOINT_ID${NC}"
    echo -e ""
    echo -e "管理選項："
    echo -e "  ${GREEN}1.${NC} 添加授權規則"
    echo -e "  ${GREEN}2.${NC} 移除授權規則"
    echo -e "  ${GREEN}3.${NC} 查看路由表"
    echo -e "  ${GREEN}4.${NC} 添加路由"
    echo -e "  ${GREEN}5.${NC} 查看關聯的網絡"
    echo -e "  ${GREEN}6.${NC} 關聯新子網路"
    echo -e "  ${GREEN}7.${NC} 返回主選單"
    
    read -p "請選擇操作 (1-7): " choice
    
    case "$choice" in
        1)
            # Option 1: Add Authorization Rule (uses library function)
            echo -e "\\n${BLUE}=== 添加授權規則 (透過 lib) ===${NC}"
            add_authorization_rule_lib "$AWS_REGION" "$ENDPOINT_ID"
            local result_add_auth=$?
            log_operation_result "添加授權規則" "$result_add_auth" "aws_vpn_admin.sh"
            ;;
        2)
            # Option 2: Remove Authorization Rule (uses library function)
            echo -e "\\n${BLUE}=== 移除授權規則 (透過 lib) ===${NC}"
            remove_authorization_rule_lib "$AWS_REGION" "$ENDPOINT_ID"
            local result_remove_auth=$?
            log_operation_result "移除授權規則" "$result_remove_auth" "aws_vpn_admin.sh"
            ;;
        3)
            # Option 3: View Route Table (uses library function)
            echo -e "\\n${BLUE}=== 查看路由表 (透過 lib) ===${NC}"
            view_route_table_lib "$AWS_REGION" "$ENDPOINT_ID"
            # Library function handles its own logging and success/failure messages.
            ;;
        4)
            # Option 4: Add Route (uses library function)
            echo -e "\\n${BLUE}=== 添加路由 (透過 lib) ===${NC}"
            add_route_lib "$AWS_REGION" "$ENDPOINT_ID"
            local result_add_route=$?
            log_operation_result "添加路由" "$result_add_route" "aws_vpn_admin.sh"
            ;;
        5)
            # Option 5: View Associated Networks (uses library function)
            echo -e "\\n${BLUE}=== 查看關聯的網絡 (透過 lib) ===${NC}"
            view_associated_networks_lib "$AWS_REGION" "$ENDPOINT_ID"
            # Library function handles its own logging and success/failure messages.
            ;;
        6)
            # Option 6: Associate new subnet to endpoint (uses library function)
            echo -e "\\n${BLUE}=== 關聯新子網路到端點 (透過 lib) ===${NC}"
            echo -e "${YELLOW}提示: 此選項用於將端點直接關聯到一個子網路。${NC}"
            echo -e "${YELLOW}這通常用於擴展到同一 VPC 中的不同可用區，或在初始關聯失敗時重試。${NC}"
            echo -e "${YELLOW}此操作不會自動更新多 VPC 配置或為新子網路的 VPC 添加授權/路由。${NC}"
            echo -e "${YELLOW}對於關聯到 *不同* VPC 並進行完整配置，請使用 '多 VPC 管理' -> '添加 VPC 到現有端點' 選項。${NC}"
            
            view_associated_networks_lib "$AWS_REGION" "$ENDPOINT_ID" # Show current associations
            
            associate_subnet_to_endpoint_lib "$AWS_REGION" "$ENDPOINT_ID"
            local result_assoc_subnet=$?
            log_operation_result "子網路關聯" "$result_assoc_subnet" "aws_vpn_admin.sh"
            
            if [ "$result_assoc_subnet" -eq 0 ]; then
                echo -e "${GREEN}子網路關聯操作成功完成。${NC}"
            else
                echo -e "${RED}子網路關聯過程中發生錯誤。請檢查上面的日誌。${NC}"
            fi
            ;;
        7)
            return
            ;;
        *)
            echo -e "${RED}無效選擇${NC}"
            ;;
    esac
    
    echo -e "\\n${YELLOW}按任意鍵繼續...${NC}"
    read -n 1
}

# 刪除 VPN 端點
delete_vpn_endpoint() {
    echo -e "\\n${CYAN}=== 刪除 VPN 端點 ===${NC}"
    log_message "開始刪除 VPN 端點 (主腳本)"

    # 使用統一的端點操作驗證 (已包含 load_config_core 和對 AWS_REGION, ENDPOINT_ID 的檢查)
    if ! validate_endpoint_operation "$ENDPOINT_CONFIG_FILE"; then
        echo -e "\\n${YELLOW}按任意鍵繼續...${NC}"
        read -n 1 -s
        return 1
    fi
    
    # VPN_NAME 的檢查仍然需要，因為它不是 validate_endpoint_operation 的一部分
    if [ -z "$VPN_NAME" ]; then
        echo -e "${YELLOW}警告: VPN_NAME 未在配置中找到。CloudWatch 日誌群組可能無法自動刪除。${NC}"
        log_message "警告: 嘗試刪除 VPN 但 VPN_NAME 未配置。"
        # 允許繼續，lib 函式會處理 VPN_NAME 缺失的情況
    fi

    # 🚨 安全確認：顯示即將刪除的資源信息
    echo -e "\\n${RED}⚠️ 警告：您即將刪除以下 VPN 端點和相關資源：${NC}"
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}環境:${NC} ${CURRENT_ENVIRONMENT}"
    echo -e "${CYAN}端點 ID:${NC} ${ENDPOINT_ID}"
    echo -e "${CYAN}VPN 名稱:${NC} ${VPN_NAME:-未知}"
    echo -e "${CYAN}AWS 區域:${NC} ${AWS_REGION}"
    if [ -n "$CLIENT_VPN_SECURITY_GROUP_ID" ]; then
        echo -e "${CYAN}安全群組:${NC} ${CLIENT_VPN_SECURITY_GROUP_ID}"
    fi
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    
    echo -e "\\n${RED}🔥 此操作將會刪除以下資源：${NC}"
    echo -e "  ${RED}•${NC} VPN 端點及其所有配置"
    echo -e "  ${RED}•${NC} 子網路關聯和路由"
    echo -e "  ${RED}•${NC} 授權規則"
    echo -e "  ${RED}•${NC} CloudWatch 日誌群組"
    echo -e "  ${RED}•${NC} 專用 Client VPN 安全群組"
    echo -e "  ${RED}•${NC} 配置文件中的相關設定"
    
    echo -e "\\n${YELLOW}⚠️ 注意：此操作不可逆轉！${NC}"
    echo -e "${YELLOW}⚠️ 所有連接的用戶將立即斷線！${NC}"
    echo -e "${YELLOW}⚠️ VPN 證書不會被刪除（需要手動管理）${NC}"
    
    # 第一層確認：基本確認
    echo -e "\\n${RED}第一步確認：${NC}您確定要刪除此 VPN 端點嗎？"
    local first_confirm
    while true; do
        echo -n "請輸入 'yes' 以繼續，或 'no' 取消: "
        read -t 30 first_confirm
        case "$first_confirm" in
            yes|YES)
                echo -e "${YELLOW}✓ 第一步確認通過${NC}"
                break
                ;;
            no|NO|"")
                echo -e "${GREEN}✓ 取消刪除操作${NC}"
                echo -e "\\n${YELLOW}按任意鍵繼續...${NC}"
                read -n 1 -s
                return 0
                ;;
            *)
                echo -e "${RED}請輸入 'yes' 或 'no'${NC}"
                ;;
        esac
    done
    
    # 第二層確認：環境特定確認（生產環境需要額外確認）
    if [ "$CURRENT_ENVIRONMENT" = "production" ]; then
        echo -e "\\n${RED}⚠️ 生產環境額外確認：${NC}"
        echo -e "${RED}您正在刪除 ${YELLOW}生產環境${RED} 的 VPN 端點！${NC}"
        echo -e "${RED}這可能會影響正在工作的團隊成員！${NC}"
        
        local prod_confirm
        while true; do
            echo -n "請輸入 'DELETE-PRODUCTION-VPN' 以確認刪除生產環境 VPN: "
            read -t 60 prod_confirm
            if [ "$prod_confirm" = "DELETE-PRODUCTION-VPN" ]; then
                echo -e "${YELLOW}✓ 生產環境確認通過${NC}"
                break
            elif [ -z "$prod_confirm" ]; then
                echo -e "${GREEN}✓ 超時，取消刪除操作${NC}"
                echo -e "\\n${YELLOW}按任意鍵繼續...${NC}"
                read -n 1 -s
                return 0
            else
                echo -e "${RED}輸入不正確，請重試或按 Ctrl+C 取消${NC}"
            fi
        done
    fi
    
    # 第三層確認：最終確認
    echo -e "\\n${RED}最終確認：${NC}請再次確認您要刪除此 VPN 端點"
    echo -e "${CYAN}端點 ID: ${ENDPOINT_ID}${NC}"
    local final_confirm
    while true; do
        echo -n "輸入端點 ID 的最後 8 個字符以確認刪除: "
        read -t 30 final_confirm
        local expected_suffix="${ENDPOINT_ID: -8}"
        if [ "$final_confirm" = "$expected_suffix" ]; then
            echo -e "${YELLOW}✓ 最終確認通過，開始刪除...${NC}"
            break
        elif [ -z "$final_confirm" ]; then
            echo -e "${GREEN}✓ 超時，取消刪除操作${NC}"
            echo -e "\\n${YELLOW}按任意鍵繼續...${NC}"
            read -n 1 -s
            return 0
        else
            echo -e "${RED}輸入不正確（期望: $expected_suffix），請重試或按 Ctrl+C 取消${NC}"
        fi
    done
    
    echo -e "\\n${CYAN}🚀 所有確認完成，開始執行刪除操作...${NC}"
    log_message "用戶通過所有確認，開始刪除 VPN 端點: $ENDPOINT_ID"

    # 調用庫函式
    # 參數: aws_region, endpoint_id, vpn_name (用於日誌群組), config_file_path
    terminate_vpn_endpoint_lib "$AWS_REGION" "$ENDPOINT_ID" "$VPN_NAME" "$ENDPOINT_CONFIG_FILE"
    local result=$?

    # 使用統一的日誌記錄
    log_operation_result "VPN 端點刪除" "$result" "aws_vpn_admin.sh"

    if [ "$result" -eq 0 ]; then
        echo -e "\\n${GREEN}🎉 VPN 端點刪除操作成功完成！${NC}"
        echo -e "${GREEN}✅ 所有相關資源已清理完畢${NC}"
        echo -e "${BLUE}💡 提醒：VPN 證書仍保留在 ACM 中，如需要可手動刪除${NC}"
        log_message "VPN 端點刪除成功完成: $ENDPOINT_ID"
    else
        echo -e "\\n${RED}❌ VPN 端點刪除過程中發生錯誤${NC}"
        echo -e "${YELLOW}⚠️ 請檢查上面的詳細日誌以了解具體問題${NC}"
        echo -e "${BLUE}💡 提示：部分資源可能已刪除，請檢查 AWS 控制台確認狀態${NC}"
        log_message "VPN 端點刪除過程中發生錯誤: $ENDPOINT_ID"
    fi
    
    echo -e "\\n${YELLOW}按任意鍵繼續...${NC}"
    read -n 1 -s
}

# 查看連接日誌
view_connection_logs() {
    echo -e "\\n${CYAN}=== 查看連接日誌 ===${NC}"
    
    # 使用統一的配置驗證 (已包含 load_config_core)
    if ! validate_main_config "$CONFIG_FILE"; then
        echo -e "\\n${YELLOW}按任意鍵繼續...${NC}"
        read -n 1
        return 1
    fi
    
    # 檢查 VPN_NAME 是否存在
    if [ -z "$VPN_NAME" ]; then
        echo -e "${RED}未找到 VPN 名稱 (VPN_NAME)，無法查看日誌。${NC}"
        log_message "錯誤：嘗試查看日誌但 VPN_NAME 未配置。"
        echo -e "\\n${YELLOW}按任意鍵繼續...${NC}"
        read -n 1
        return 1
    fi
    
    local log_group_name="/aws/clientvpn/$VPN_NAME"
    
    echo -e "${BLUE}查看最近的連接日誌...${NC}"
    
    # 獲取最近 1 小時的日誌
    # macOS 兼容的日期計算
    if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS (BSD date)
        start_time=$(date -u -v-1H +%s)000
        end_time=$(date -u +%s)000
    else
        # Linux (GNU date)
        start_time=$(date -u -d '1 hour ago' +%s)000
        end_time=$(date -u +%s)000
    fi
    
    aws logs filter-log-events \
      --log-group-name "$log_group_name" \
      --start-time "$start_time" \
      --end-time "$end_time" \
      --region "$AWS_REGION" | jq -r '.events[] | "\(.timestamp | strftime("%Y-%m-%d %H:%M:%S")): \(.message)"' | tail -20
    
    echo -e "\\n${YELLOW}按任意鍵繼續...${NC}"
    read -n 1
}

# 匯出團隊成員設定檔
export_team_config() {
    echo -e "\\n${CYAN}=== 匯出團隊成員設定檔 ===${NC}"
    
    # 使用統一的端點操作驗證 (已包含 load_config_core 和對 ENDPOINT_ID 的檢查)
    if ! validate_endpoint_operation "$ENDPOINT_CONFIG_FILE"; then
        echo -e "\\n${YELLOW}按任意鍵繼續...${NC}"
        read -n 1
        return 1
    fi
    
    # 調用庫函式
    export_team_config_lib "$SCRIPT_DIR" "$ENDPOINT_CONFIG_FILE"
    local result=$?
    
    log_operation_result "匯出團隊成員設定檔" "$result" "aws_vpn_admin.sh"
    
    if [ "$result" -ne 0 ]; then
        echo -e "${RED}匯出團隊設定檔過程中發生錯誤。${NC}"
    fi
    
    echo -e "\\n${YELLOW}按任意鍵繼續...${NC}"
    read -n 1
}

# 系統健康檢查
system_health_check() {
    echo -e "\\n${CYAN}=== 系統健康檢查 ===${NC}"
    
    # 使用統一的端點操作驗證 (已包含 load_config_core 和對 ENDPOINT_ID, AWS_REGION 的檢查)
    if ! validate_endpoint_operation "$ENDPOINT_CONFIG_FILE"; then
        echo -e "\\n${YELLOW}按任意鍵繼續...${NC}"
        read -n 1
        return 1
    fi
    
    echo -e "${BLUE}檢查 VPN 端點狀態...${NC}"
    endpoint_status=$(aws ec2 describe-client-vpn-endpoints \
      --client-vpn-endpoint-ids "$ENDPOINT_ID" \
      --region "$AWS_REGION" | jq -r '.ClientVpnEndpoints[0].Status.Code')
    
    if [ "$endpoint_status" == "available" ]; then
        echo -e "${GREEN}✓ VPN 端點狀態: 可用${NC}"
    else
        echo -e "${RED}✗ VPN 端點狀態: $endpoint_status${NC}"
    fi
    
    echo -e "${BLUE}檢查關聯的網絡...${NC}"
    target_networks_json=$(aws ec2 describe-client-vpn-target-networks \
      --client-vpn-endpoint-id "$ENDPOINT_ID" \
      --region "$AWS_REGION")
    
    if ! network_count=$(echo "$target_networks_json" | jq '.ClientVpnTargetNetworks | length' 2>/dev/null); then
        # 備用解析方法：使用 grep 統計網絡數量
        network_count=$(echo "$target_networks_json" | grep -c '"TargetNetworkId"' || echo "0")
    fi
    echo -e "${GREEN}✓ 總關聯的網絡數量: $network_count${NC}"

    if [ "$network_count" -gt 0 ]; then
        echo "$target_networks_json" | jq -r '
          .ClientVpnTargetNetworks[] |
          (
            "  - 子網路 ID: " + (.TargetNetworkId | tostring) + "\n" +
            "    VPC ID: " + (.VpcId | tostring) + "\n" +
            "    狀態: " + (.Status.Code | tostring) +
            (if (.Status.Code | tostring) != "associated" then " (問題!)" else "" end)
          )
        '
    else
        echo -e "  ${YELLOW}未關聯任何子網路${NC}"
    fi
    
    echo -e "\\n${BLUE}檢查授權規則...${NC}"
    auth_rules_json=$(aws ec2 describe-client-vpn-authorization-rules \
      --client-vpn-endpoint-id "$ENDPOINT_ID" \
      --region "$AWS_REGION")
    
    if ! auth_count=$(echo "$auth_rules_json" | jq '.AuthorizationRules | length' 2>/dev/null); then
        # 備用解析方法：使用 grep 統計授權規則數量
        auth_count=$(echo "$auth_rules_json" | grep -c '"DestinationCidr"' || echo "0")
    fi
    
    # 驗證解析結果
    if ! validate_json_parse_result "$auth_count" "授權規則數量"; then
        auth_count="未知"
    fi
    
    echo -e "${GREEN}✓ 授權規則數量: $auth_count${NC}"
    
    echo -e "${BLUE}檢查連接統計...${NC}"
    connections_json=$(aws ec2 describe-client-vpn-connections \
      --client-vpn-endpoint-id "$ENDPOINT_ID" \
      --region "$AWS_REGION")
    
    if ! connections=$(echo "$connections_json" | jq '.Connections | length' 2>/dev/null); then
        # 備用解析方法：使用 grep 統計連接數量
        connections=$(echo "$connections_json" | grep -c '"ConnectionId"' || echo "0")
    fi
    
    # 驗證解析結果
    if ! validate_json_parse_result "$connections" "連接數量"; then
        connections="未知"
    fi
    
    echo -e "${GREEN}✓ 目前連接數: $connections${NC}"
    
    echo -e "${BLUE}檢查證書狀態...${NC}"
    if [ ! -z "$SERVER_CERT_ARN" ]; then
        cert_status=$(aws acm describe-certificate \
          --certificate-arn "$SERVER_CERT_ARN" \
          --region "$AWS_REGION" | jq -r '.Certificate.Status')
        echo -e "${GREEN}✓ 伺服器證書狀態: $cert_status${NC}"
    fi
    
    echo -e "\\n${YELLOW}按任意鍵繼續...${NC}"
    read -n 1
}

# 添加 VPC 到現有端點
add_vpc_to_endpoint() {
    echo -e "\\n${CYAN}=== 添加 VPC 到現有端點 ===${NC}"
    
    # 使用統一的端點操作驗證
    if ! validate_endpoint_operation "$ENDPOINT_CONFIG_FILE"; then
        echo -e "\\n${YELLOW}按任意鍵繼續...${NC}"
        read -n 1
        return 1
    fi
    
    echo -e "${BLUE}當前端點 ID: $ENDPOINT_ID${NC}"
    echo -e "${BLUE}當前 AWS 區域: $AWS_REGION${NC}"

    # 調用庫函式來處理單一 VPC 的關聯
    associate_single_vpc_lib "$ENDPOINT_CONFIG_FILE" "$AWS_REGION" "$ENDPOINT_ID"
    local result=$?

    log_operation_result "VPC 添加" "$result" "aws_vpn_admin.sh"

    if [ "$result" -eq 0 ]; then
        echo -e "${GREEN}VPC 添加操作成功完成。${NC}"
        # 重新載入配置以確保任何更改都已反映
        if ! load_config_core "$ENDPOINT_CONFIG_FILE"; then # 使用統一函式
            echo -e "${RED}錯誤：無法重新載入更新的配置文件${NC}"
            # 即使重載失敗，也可能部分成功，所以不立即返回 1
        fi
    else
        echo -e "${RED}VPC 添加過程中發生錯誤。請檢查上面的日誌。${NC}"
    fi
    
    echo -e "\\n${YELLOW}按任意鍵繼續...${NC}"
    read -n 1
}

# 查看多 VPC 拓撲
show_multi_vpc_topology() {
    echo -e "\\n${CYAN}=== 多 VPC 網路拓撲 ===${NC}"
    
    # 使用統一的配置驗證
    if ! validate_main_config "$ENV_CONFIG_FILE"; then
        echo -e "\\n${YELLOW}按任意鍵繼續...${NC}"
        read -n 1
        return 1
    fi
    
    # 檢查所有必要的變數是否已從 CONFIG_FILE 加載
    # validate_main_config 已檢查 AWS_REGION
    # validate_endpoint_operation (如果適用) 會檢查 ENDPOINT_ID
    # 此處需要檢查其他特定於此函式的變數
    local required_vars_topology=("ENDPOINT_ID" "VPN_CIDR" "VPC_ID" "VPC_CIDR" "SUBNET_ID")
    for var_name in "${required_vars_topology[@]}"; do
        if [ -z "${!var_name}" ]; then
            echo -e "${RED}錯誤: 配置文件 .vpn_config 中缺少必要的變數 '$var_name'。${NC}"
            echo -e "\\n${YELLOW}按任意鍵繼續...${NC}"
            read -n 1
            return 1
        fi
    done

    # 調用庫函式
    show_multi_vpc_topology_lib "$ENDPOINT_CONFIG_FILE" "$AWS_REGION" "$ENDPOINT_ID" "$VPN_CIDR" "$VPC_ID" "$VPC_CIDR" "$SUBNET_ID"
    local result=$?

    log_operation_result "顯示多 VPC 拓撲" "$result" "aws_vpn_admin.sh"

    if [ "$result" -ne 0 ]; then
        echo -e "${RED}顯示多 VPC 拓撲過程中發生錯誤。${NC}"
    fi
    
    echo -e "\\n${YELLOW}按任意鍵繼續...${NC}"
    read -n 1
}

# 移除 VPC 關聯
remove_vpc_association() {
    echo -e "\\n${CYAN}=== 移除 VPC 關聯 ===${NC}"
    
    # 使用統一的端點操作驗證
    if ! validate_endpoint_operation "$ENDPOINT_CONFIG_FILE"; then
        echo -e "\\n${YELLOW}按任意鍵繼續...${NC}"
        read -n 1
        return 1
    fi
    
    echo -e "${BLUE}當前端點 ID: $ENDPOINT_ID${NC}"
    echo -e "${BLUE}當前 AWS 區域: $AWS_REGION${NC}"

    # 調用庫函式來處理 VPC 的解除關聯
    disassociate_vpc_lib "$ENDPOINT_CONFIG_FILE" "$AWS_REGION" "$ENDPOINT_ID"
    local result=$?

    log_operation_result "VPC 解除關聯" "$result" "aws_vpn_admin.sh"

    if [ "$result" -eq 0 ]; then
        echo -e "${GREEN}VPC 解除關聯操作成功完成。${NC}"
        # 重新載入配置以確保任何更改都已反映
        if ! load_config_core "$ENDPOINT_CONFIG_FILE"; then # 使用統一函式
             echo -e "${RED}錯誤：無法重新載入更新的配置文件${NC}"
        fi
    else
        echo -e "${RED}VPC 解除關聯過程中發生錯誤。請檢查上面的日誌。${NC}"
    fi
    
    echo -e "\\n${YELLOW}按任意鍵繼續...${NC}"
    read -n 1
}

# 批量管理 VPC 授權規則
manage_batch_vpc_auth() {
    echo -e "\\n${CYAN}=== 批量管理 VPC 授權規則 ===${NC}"
    
    # 使用統一的端點操作驗證
    if ! validate_endpoint_operation "$ENDPOINT_CONFIG_FILE"; then
        echo -e "\\n${YELLOW}按任意鍵返回多 VPC 管理選單...${NC}"
        read -n 1 -s
        return 1
    fi

    # 調用庫函式
    manage_batch_vpc_auth_lib "$AWS_REGION" "$ENDPOINT_ID"
    local result=$?

    log_operation_result "批量管理 VPC 授權規則" "$result" "aws_vpn_admin.sh"

    if [ "$result" -ne 0 ]; then
        echo -e "${RED}批量管理 VPC 授權規則過程中發生錯誤或操作未成功。${NC}"
    fi
    
    echo -e "\\n${YELLOW}按任意鍵返回多 VPC 管理選單...${NC}"
    read -n 1 -s
}

# 多 VPC 管理主函數
manage_multi_vpc() {
    # 在進入循環前，先做一次配置檢查，確保 AWS_REGION 等基本配置存在
    if ! validate_main_config "$ENV_CONFIG_FILE"; then
        echo -e "\\n${YELLOW}按任意鍵返回主選單...${NC}"
        read -n 1
        return 1
    fi

    while true; do
        echo -e "\\n${CYAN}=== 多 VPC 管理 ===${NC}"
        echo -e ""
        echo -e "${BLUE}選擇操作：${NC}"
        echo -e "  ${GREEN}1.${NC} 發現可用的 VPCs"
        echo -e "  ${GREEN}2.${NC} 添加 VPC 到現有端點"
        echo -e "  ${GREEN}3.${NC} 查看多 VPC 網路拓撲"
        echo -e "  ${GREEN}4.${NC} 移除 VPC 關聯"
        echo -e "  ${GREEN}5.${NC} 批量管理授權規則"
        echo -e "  ${GREEN}6.${NC} 跨 VPC 路由管理"
        echo -e "  ${GREEN}7.${NC} 返回主選單"
        echo -e ""
        
        read -p "請選擇操作 (1-7): " choice
        
        case "$choice" in
            1)
                # discover_available_vpcs_core 已移至 core_functions.sh
                # AWS_REGION 應該已經由 validate_main_config 載入
                discover_available_vpcs_core "$AWS_REGION"
                echo -e "\\n${YELLOW}按任意鍵繼續...${NC}"
                read -n 1
                ;;
            2)
                add_vpc_to_endpoint
                ;;
            3)
                show_multi_vpc_topology
                ;;
            4)
                remove_vpc_association
                ;;
            5)
                manage_batch_vpc_auth
                ;;
            6)
                manage_cross_vpc_routes
                ;;
            7)
                return
                ;;
            *)
                echo -e "${RED}無效選擇${NC}"
                sleep 1
                ;;
        esac
    done
}

# 跨 VPC 路由管理
manage_cross_vpc_routes() {
    echo -e "\\n${CYAN}=== 跨 VPC 路由管理 ===${NC}"
    
    # 使用統一的端點操作驗證
    if ! validate_endpoint_operation "$ENDPOINT_CONFIG_FILE"; then
        echo -e "\\n${YELLOW}按任意鍵返回多 VPC 管理選單...${NC}"
        read -n 1 -s
        return 1
    fi

    # 調用庫函式來處理路由管理
    manage_routes_lib "$AWS_REGION" "$ENDPOINT_ID"
    local result=$?

    log_operation_result "跨 VPC 路由管理" "$result" "aws_vpn_admin.sh"
    
    if [ "$result" -ne 0 ]; then
        echo -e "${RED}跨 VPC 路由管理過程中發生內部錯誤。${NC}"
    fi
    
    echo -e "\\n${YELLOW}按任意鍵返回多 VPC 管理選單...${NC}"
    read -n 1 -s
}

# 顯示管理員指南
show_admin_guide() {
    echo -e "\\n${CYAN}=== 管理員指南 ===${NC}"
    echo -e ""
    echo -e "${BLUE}1. 建立 VPN 端點後的步驟：${NC}"
    echo -e "   - 確認端點狀態為 'available'"
    echo -e "   - 測試管理員配置檔案連接"
    echo -e "   - 匯出團隊成員設定檔"
    echo -e ""
    echo -e "${BLUE}2. 管理團隊成員：${NC}"
    echo -e "   - 使用 team_member_setup.sh 讓新成員加入"
    echo -e "   - 使用 revoke_member_access.sh 撤銷訪問權限"
    echo -e "   - 使用 employee_offboarding.sh 處理離職人員"
    echo -e ""
    echo -e "${BLUE}3. 安全最佳實踐：${NC}"
    echo -e "   - 定期檢查連接日誌"
    echo -e "   - 為每個用戶創建獨立證書"
    echo -e "   - 實施最小權限原則"
    echo -e "   - 定期輪換證書"
    echo -e ""
    echo -e "${BLUE}4. 故障排除：${NC}"
    echo -e "   - 檢查端點和網絡關聯狀態"
    echo -e "   - 查看 CloudWatch 日誌"
    echo -e "   - 驗證授權規則設定"
    echo -e ""
    echo -e "${BLUE}5. 備份和恢復：${NC}"
    echo -e "   - 定期備份證書文件"
    echo -e "   - 記錄所有配置參數"
    echo -e "   - 保存端點設定資訊"
    
    echo -e "\\n${YELLOW}按任意鍵繼續...${NC}"
    read -n 1
}

# AWS Profile 管理
manage_aws_profiles() {
    while true; do
        clear
        show_env_aware_header "AWS Profile 管理"
        
        # 顯示當前環境的 profile 狀態
        echo -e "${CYAN}當前環境 Profile 狀態:${NC}"
        env_get_profile "$CURRENT_ENVIRONMENT" true
        echo ""
        
        echo -e "${BLUE}Profile 管理選項:${NC}"
        echo -e "  ${GREEN}1.${NC} 設定當前環境的 AWS Profile"
        echo -e "  ${GREEN}2.${NC} 驗證 Profile 整合"
        echo -e "  ${GREEN}3.${NC} 查看所有環境的 Profile 設定"
        echo -e "  ${GREEN}4.${NC} 切換環境並設定 Profile"
        echo -e "  ${GREEN}5.${NC} Profile 診斷與修復"
        echo -e "  ${YELLOW}6.${NC} 返回主選單"
        echo ""
        echo -e "${CYAN}========================================================${NC}"
        
        read -p "請選擇操作 (1-6): " profile_choice
        
        case "$profile_choice" in
            1)
                # 設定當前環境的 AWS Profile
                echo -e "\n${CYAN}=== 設定 $CURRENT_ENVIRONMENT 環境的 AWS Profile ===${NC}"
                local selected_profile
                selected_profile=$(select_aws_profile_for_environment "$CURRENT_ENVIRONMENT")
                if [[ $? -eq 0 ]] && [[ -n "$selected_profile" ]]; then
                    env_set_profile "$CURRENT_ENVIRONMENT" "$selected_profile"
                    echo -e "\n${GREEN}✅ Profile 設定完成${NC}"
                else
                    echo -e "\n${YELLOW}Profile 設定已取消${NC}"
                fi
                echo -e "\n${YELLOW}按任意鍵繼續...${NC}"
                read -n 1
                ;;
            2)
                # 驗證 Profile 整合
                echo -e "\n${CYAN}=== 驗證 Profile 整合 ===${NC}"
                env_validate_profile_integration "$CURRENT_ENVIRONMENT" true
                echo -e "\n${YELLOW}按任意鍵繼續...${NC}"
                read -n 1
                ;;
            3)
                # 查看所有環境的 Profile 設定
                echo -e "\n${CYAN}=== 所有環境的 Profile 設定 ===${NC}"
                for env_dir in "$SCRIPT_DIR/../configs"/*; do
                    if [[ -d "$env_dir" ]]; then
                        local env_name=$(basename "$env_dir")
                        local env_file="$env_dir/${env_name}.env"
                        if [[ -f "$env_file" ]]; then
                            source "$env_file"
                            echo -e "\n${ENV_ICON:-⚪} ${ENV_DISPLAY_NAME:-$env_name}:"
                            env_get_profile "$env_name" true 2>/dev/null || echo -e "  ${YELLOW}未設定 Profile${NC}"
                        fi
                    fi
                done
                echo -e "\n${YELLOW}按任意鍵繼續...${NC}"
                read -n 1
                ;;
            4)
                # 切換環境並設定 Profile
                echo -e "\n${CYAN}=== 切換環境並設定 Profile ===${NC}"
                echo -e "可用環境:"
                echo -e "  1) staging - Staging Environment 🟡"
                echo -e "  2) production - Production Environment 🔴"
                echo ""
                read -p "請選擇目標環境 (1-2): " env_choice
                
                local target_env=""
                case "$env_choice" in
                    1) target_env="staging" ;;
                    2) target_env="production" ;;
                    *)
                        echo -e "${RED}無效選擇${NC}"
                        sleep 1
                        continue
                        ;;
                esac
                
                if env_switch_with_profile "$target_env"; then
                    echo -e "\n${GREEN}✅ 環境切換並 Profile 設定完成${NC}"
                    echo -e "請重新啟動管理員工具以使用新環境"
                    echo -e "\n${YELLOW}按任意鍵返回主選單...${NC}"
                    read -n 1
                    return 0
                else
                    echo -e "\n${RED}環境切換失敗${NC}"
                    echo -e "\n${YELLOW}按任意鍵繼續...${NC}"
                    read -n 1
                fi
                ;;
            5)
                # Profile 診斷與修復
                echo -e "\n${CYAN}=== Profile 診斷與修復 ===${NC}"
                echo -e "${BLUE}檢查所有環境的 Profile 健康狀態...${NC}"
                
                for env_dir in "$SCRIPT_DIR/../configs"/*; do
                    if [[ -d "$env_dir" ]]; then
                        local env_name=$(basename "$env_dir")
                        local env_file="$env_dir/${env_name}.env"
                        if [[ -f "$env_file" ]]; then
                            echo -e "\n=== $env_name 環境 ==="
                            env_validate_profile_integration "$env_name" true
                        fi
                    fi
                done
                
                echo -e "\n${YELLOW}按任意鍵繼續...${NC}"
                read -n 1
                ;;
            6)
                return 0
                ;;
            *)
                echo -e "${RED}無效選擇，請重試。${NC}"
                sleep 1
                ;;
        esac
    done
}

# 主函數
main() {
    # 檢查必要工具
    check_prerequisites # 來自 core_functions.sh
    
    # 確保有配置，如果沒有則引導設定
    # CONFIG_FILE 變數在腳本頂部定義
    if [ ! -f "$CONFIG_FILE" ]; then
        echo -e "${YELLOW}未找到配置文件 ($CONFIG_FILE)。正在引導初始設定...${NC}"
        # setup_aws_config_lib 來自 aws_setup.sh, 它會創建 CONFIG_FILE
        if ! setup_aws_config_lib "$CONFIG_FILE"; then
            echo -e "${RED}AWS 配置設定失敗。無法繼續。${NC}"
            exit 1
        fi
        echo -e "${GREEN}配置文件已創建。${NC}"
    fi
    
    # 驗證基本配置 (如 AWS_REGION)
    # 這也會通過 load_config_core 載入配置
    if ! validate_main_config "$CONFIG_FILE"; then
        echo -e "${RED}配置文件驗證失敗。請檢查 $CONFIG_FILE 或重新執行設定。${NC}"
        # 如果 validate_main_config 失敗，它已經打印了具體錯誤
        # 此處可以選擇是否引導用戶重新設定或直接退出
        # 例如，詢問用戶是否要重新設定
        read -p "是否要嘗試重新設定 AWS 配置? (y/n): " reconfigure_choice
        if [[ "$reconfigure_choice" == "y" || "$reconfigure_choice" == "Y" ]]; then
            if ! setup_aws_config_lib "$CONFIG_FILE"; then
                echo -e "${RED}AWS 配置設定失敗。無法繼續。${NC}"
                exit 1
            fi
            echo -e "${GREEN}配置已更新。請重新啟動腳本。${NC}"
            exit 0
        else
            echo -e "${YELLOW}腳本將退出。${NC}"
            exit 1
        fi
    fi

    # 主循環
    while true; do
        show_menu
        read -p "請選擇操作 (1-10, E, P): " choice
        
        case "$choice" in
            1)
                create_vpn_endpoint
                ;;
            2)
                list_vpn_endpoints
                ;;
            3)
                manage_vpn_settings
                ;;
            4)
                delete_vpn_endpoint
                ;;
            5)
                view_connection_logs
                ;;
            6)
                export_team_config
                ;;
            7)
                show_admin_guide
                ;;
            8)
                system_health_check
                ;;
            9)
                manage_multi_vpc
                ;;
            E|e)
                echo -e "\n${CYAN}=== 環境管理 ===${NC}"
                "$SCRIPT_DIR/../vpn_env.sh"
                echo -e "\n${YELLOW}按任意鍵返回主選單...${NC}"
                read -n 1
                ;;
            P|p)
                manage_aws_profiles
                ;;
            10)
                echo -e "${BLUE}正在退出...${NC}"
                exit 0
                ;;
            *)
                echo -e "${RED}無效選擇，請重試。${NC}"
                sleep 1
                ;;
        esac
    done
}

# 執行主函數
main "$@"
