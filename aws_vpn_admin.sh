#!/bin/bash

# AWS Client VPN 管理員主腳本 for macOS
# 用途：建立、管理和刪除 AWS Client VPN 端點
# 作者：VPN 管理員
# 版本：1.0

# 全域變數
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 載入環境管理器 (必須第一個載入)
source "$SCRIPT_DIR/lib/env_manager.sh"

# 初始化環境
if ! env_init_for_script "aws_vpn_admin.sh"; then
    echo -e "${RED}錯誤: 無法初始化環境管理器${NC}"
    exit 1
fi

# 設定環境特定路徑
env_setup_paths

# 環境感知的配置檔案
CONFIG_FILE="$VPN_ENDPOINT_CONFIG_FILE"
LOG_FILE="$VPN_ADMIN_LOG_FILE"

# 載入核心函式庫
source "$SCRIPT_DIR/lib/core_functions.sh"
source "$SCRIPT_DIR/lib/aws_setup.sh"
source "$SCRIPT_DIR/lib/cert_management.sh"
source "$SCRIPT_DIR/lib/endpoint_creation.sh"
source "$SCRIPT_DIR/lib/endpoint_management.sh"

# 阻止腳本在出錯時繼續執行
set -e

# 顯示主選單
show_menu() {
    clear
    show_env_aware_header "AWS Client VPN 管理員控制台"
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
    echo -e "  ${RED}10.${NC} 退出"
    echo -e ""
    echo -e "${CYAN}========================================================${NC}"
}

# 建立 VPN 端點
create_vpn_endpoint() {
    echo -e "\\n${CYAN}=== 建立新的 VPN 端點 ===${NC}"
    
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
        generate_certificates_lib "$VPN_CERT_DIR"
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
    if command -v jq >/dev/null 2>&1; then
        # 如果系統有 jq，使用 jq 解析
        if ! main_server_cert_arn=$(echo "$acm_arns_result" | jq -r '.server_cert_arn' 2>/dev/null); then
            handle_error "無法從 ACM 導入結果中解析伺服器證書 ARN。"
            return 1
        fi
        if ! main_client_cert_arn=$(echo "$acm_arns_result" | jq -r '.client_cert_arn' 2>/dev/null); then
            handle_error "無法從 ACM 導入結果中解析客戶端證書 ARN。"
            return 1
        fi
    else
        # 備用解析方法：使用 sed 和 grep 從 JSON 中提取 ARN
        main_server_cert_arn=$(echo "$acm_arns_result" | grep -o '"server_cert_arn":"[^"]*"' | sed 's/"server_cert_arn":"\([^"]*\)"/\1/')
        main_client_cert_arn=$(echo "$acm_arns_result" | grep -o '"client_cert_arn":"[^"]*"' | sed 's/"client_cert_arn":"\([^"]*\)"/\1/')
        
        # 使用通用驗證函數進行錯誤檢查
        if ! validate_json_parse_result "$main_server_cert_arn" "伺服器證書 ARN" "validate_certificate_arn"; then
            return 1
        fi
        
        if ! validate_json_parse_result "$main_client_cert_arn" "客戶端證書 ARN" "validate_certificate_arn"; then
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
    # 提示使用者選擇 VPC 和子網路，並獲取 VPN 設定資訊
    # get_vpc_subnet_vpn_details_lib 現在返回 JSON
    local vpn_details_json
    if ! vpn_details_json=$(get_vpc_subnet_vpn_details_lib "$AWS_REGION"); then
        handle_error "獲取 VPC/子網路詳細資訊失敗。"
        return 1
    fi

    local vpc_id subnet_id vpn_cidr vpn_name
    
    # 解析 VPC 詳細資訊 JSON
    if command -v jq >/dev/null 2>&1; then
        # 如果系統有 jq，使用 jq 解析
        if ! vpc_id=$(echo "$vpn_details_json" | jq -r '.vpc_id' 2>/dev/null); then
            handle_error "無法從詳細資訊中解析 VPC ID。"
            return 1
        fi
        if ! subnet_id=$(echo "$vpn_details_json" | jq -r '.subnet_id' 2>/dev/null); then
            handle_error "無法從詳細資訊中解析子網路 ID。"
            return 1
        fi
        if ! vpn_cidr=$(echo "$vpn_details_json" | jq -r '.vpn_cidr' 2>/dev/null); then
            handle_error "無法從詳細資訊中解析 VPN CIDR。"
            return 1
        fi
        if ! vpn_name=$(echo "$vpn_details_json" | jq -r '.vpn_name' 2>/dev/null); then
            handle_error "無法從詳細資訊中解析 VPN 名稱。"
            return 1
        fi
    else
        # 備用解析方法：使用 sed 和 grep 從 JSON 中提取值
        vpc_id=$(echo "$vpn_details_json" | grep -o '"vpc_id":"[^"]*"' | sed 's/"vpc_id":"\([^"]*\)"/\1/')
        subnet_id=$(echo "$vpn_details_json" | grep -o '"subnet_id":"[^"]*"' | sed 's/"subnet_id":"\([^"]*\)"/\1/')
        vpn_cidr=$(echo "$vpn_details_json" | grep -o '"vpn_cidr":"[^"]*"' | sed 's/"vpn_cidr":"\([^"]*\)"/\1/')
        vpn_name=$(echo "$vpn_details_json" | grep -o '"vpn_name":"[^"]*"' | sed 's/"vpn_name":"\([^"]*\)"/\1/')
        
        # 使用通用驗證函數進行錯誤檢查，並提供適當的驗證函數
        if ! validate_json_parse_result "$vpc_id" "VPC ID" "validate_vpc_id"; then
            return 1
        fi
        
        if ! validate_json_parse_result "$subnet_id" "子網路 ID" "validate_subnet_id"; then
            return 1
        fi
        
        if ! validate_json_parse_result "$vpn_cidr" "VPN CIDR" "validate_cidr_block"; then
            return 1
        fi
        
        # VPN 名稱允許包含空白字符，所以不使用額外驗證函數
        if ! validate_json_parse_result "$vpn_name" "VPN 名稱"; then
            return 1
        fi
    fi

    if [ -z "$vpc_id" ] || [ "$vpc_id" == "null" ] || \
       [ -z "$subnet_id" ] || [ "$subnet_id" == "null" ] || \
       [ -z "$vpn_cidr" ] || [ "$vpn_cidr" == "null" ] || \
       [ -z "$vpn_name" ] || [ "$vpn_name" == "null" ]; then
        handle_error "從 get_vpc_subnet_vpn_details_lib 獲取的詳細資訊無效。"
        return 1
    fi

    echo -e "${BLUE}選定的 VPC ID: $vpc_id${NC}"
    echo -e "${BLUE}選定的子網路 ID: $subnet_id${NC}"
    echo -e "${BLUE}VPN CIDR: $vpn_cidr${NC}"
    echo -e "${BLUE}VPN 名稱: $vpn_name${NC}"

    # 更新配置文件
    update_config "$CONFIG_FILE" "VPC_ID" "$vpc_id"
    update_config "$CONFIG_FILE" "SUBNET_ID" "$subnet_id"
    update_config "$CONFIG_FILE" "VPN_CIDR" "$vpn_cidr"
    update_config "$CONFIG_FILE" "VPN_NAME" "$vpn_name"
    update_config "$CONFIG_FILE" "SERVER_CERT_ARN" "$main_server_cert_arn" # 使用已獲取的 ARN
    update_config "$CONFIG_FILE" "CLIENT_CERT_ARN" "$main_client_cert_arn" # 使用已獲取的 ARN

    # 呼叫核心創建函式
    echo -e "\\n${CYAN}=== 開始創建 VPN 端點 ===${NC}"
    local creation_output
    if ! creation_output=$(create_vpn_endpoint_lib "$CONFIG_FILE" "$AWS_REGION" "$vpc_id" "$subnet_id" "$vpn_cidr" "$main_server_cert_arn" "$main_client_cert_arn" "$vpn_name"); then # Pass all required args
        echo -e "${RED}VPN 端點創建過程中發生錯誤。${NC}" # Bug fix item 5
        log_message "VPN 端點創建過程中發生錯誤。"
        return 1
    fi
    # create_vpn_endpoint_lib 應該返回 ENDPOINT_ID
    export ENDPOINT_ID="$creation_output" # 直接賦值，不再需要 cut

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
    
    # 使用統一的端點操作驗證
    if ! validate_endpoint_operation "$CONFIG_FILE"; then
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
    if ! validate_endpoint_operation "$CONFIG_FILE"; then
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

    # 調用庫函式
    # 參數: aws_region, endpoint_id, vpn_name (用於日誌群組), config_file_path
    terminate_vpn_endpoint_lib "$AWS_REGION" "$ENDPOINT_ID" "$VPN_NAME" "$CONFIG_FILE"
    local result=$?

    # 使用統一的日誌記錄
    log_operation_result "VPN 端點刪除" "$result" "aws_vpn_admin.sh"

    if [ "$result" -eq 0 ]; then
        echo -e "${GREEN}VPN 端點刪除操作成功完成。${NC}"
        # 庫函式已清理配置文件
    else
        echo -e "${RED}VPN 端點刪除過程中發生錯誤。請檢查上面的日誌。${NC}"
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
      --region "$AWS_REGION" | jq -r '.events[] | "\\(.timestamp | strftime("%Y-%m-%d %H:%M:%S")): \\(.message)"' | tail -20
    
    echo -e "\\n${YELLOW}按任意鍵繼續...${NC}"
    read -n 1
}

# 匯出團隊成員設定檔
export_team_config() {
    echo -e "\\n${CYAN}=== 匯出團隊成員設定檔 ===${NC}"
    
    # 使用統一的端點操作驗證 (已包含 load_config_core 和對 ENDPOINT_ID 的檢查)
    if ! validate_endpoint_operation "$CONFIG_FILE"; then
        echo -e "\\n${YELLOW}按任意鍵繼續...${NC}"
        read -n 1
        return 1
    fi
    
    # 調用庫函式
    export_team_config_lib "$SCRIPT_DIR" "$CONFIG_FILE"
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
    if ! validate_endpoint_operation "$CONFIG_FILE"; then
        echo -e "\\n${YELLOW}按任意鍵繼續...${NC}"
        read -n 1
        return 1
    fi
    
    echo -e "${BLUE}檢查 VPN 端點狀態...${NC}"
    endpoint_status=$(aws ec2 describe-client-vpn-endpoints \\
      --client-vpn-endpoint-ids "$ENDPOINT_ID" \\
      --region "$AWS_REGION" | jq -r '.ClientVpnEndpoints[0].Status.Code')
    
    if [ "$endpoint_status" == "available" ]; then
        echo -e "${GREEN}✓ VPN 端點狀態: 可用${NC}"
    else
        echo -e "${RED}✗ VPN 端點狀態: $endpoint_status${NC}"
    fi
    
    echo -e "${BLUE}檢查關聯的網絡...${NC}"
    target_networks_json=$(aws ec2 describe-client-vpn-target-networks \\
      --client-vpn-endpoint-id "$ENDPOINT_ID" \\
      --region "$AWS_REGION")
    
    if ! network_count=$(echo "$target_networks_json" | jq '.ClientVpnTargetNetworks | length' 2>/dev/null); then
        # 備用解析方法：使用 grep 統計網絡數量
        network_count=$(echo "$target_networks_json" | grep -c '"TargetNetworkId"' || echo "0")
    fi
    echo -e "${GREEN}✓ 總關聯的網絡數量: $network_count${NC}"

    if [ "$network_count" -gt 0 ]; then
        echo "$target_networks_json" | jq -r '.ClientVpnTargetNetworks[] | 
        "  - 子網路 ID: \\(.TargetNetworkId)\n    VPC ID: \\(.VpcId)\n    狀態: \\(.Status.Code) \\(if .Status.Code != "associated" then "(問題!)" else "" end)"'
    else
        echo -e "  ${YELLOW}未關聯任何子網路${NC}"
    fi
    
    echo -e "\\n${BLUE}檢查授權規則...${NC}"
    auth_rules_json=$(aws ec2 describe-client-vpn-authorization-rules \\
      --client-vpn-endpoint-id "$ENDPOINT_ID" \\
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
    connections_json=$(aws ec2 describe-client-vpn-connections \\
      --client-vpn-endpoint-id "$ENDPOINT_ID" \\
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
        cert_status=$(aws acm describe-certificate \\
          --certificate-arn "$SERVER_CERT_ARN" \\
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
    if ! validate_endpoint_operation "$CONFIG_FILE"; then
        echo -e "\\n${YELLOW}按任意鍵繼續...${NC}"
        read -n 1
        return 1
    fi
    
    echo -e "${BLUE}當前端點 ID: $ENDPOINT_ID${NC}"
    echo -e "${BLUE}當前 AWS 區域: $AWS_REGION${NC}"

    # 調用庫函式來處理單一 VPC 的關聯
    associate_single_vpc_lib "$CONFIG_FILE" "$AWS_REGION" "$ENDPOINT_ID"
    local result=$?

    log_operation_result "VPC 添加" "$result" "aws_vpn_admin.sh"

    if [ "$result" -eq 0 ]; then
        echo -e "${GREEN}VPC 添加操作成功完成。${NC}"
        # 重新載入配置以確保任何更改都已反映
        if ! load_config_core "$CONFIG_FILE"; then # 使用統一函式
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
    if ! validate_main_config "$CONFIG_FILE"; then
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
    show_multi_vpc_topology_lib "$CONFIG_FILE" "$AWS_REGION" "$ENDPOINT_ID" "$VPN_CIDR" "$VPC_ID" "$VPC_CIDR" "$SUBNET_ID"
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
    if ! validate_endpoint_operation "$CONFIG_FILE"; then
        echo -e "\\n${YELLOW}按任意鍵繼續...${NC}"
        read -n 1
        return 1
    fi
    
    echo -e "${BLUE}當前端點 ID: $ENDPOINT_ID${NC}"
    echo -e "${BLUE}當前 AWS 區域: $AWS_REGION${NC}"

    # 調用庫函式來處理 VPC 的解除關聯
    disassociate_vpc_lib "$CONFIG_FILE" "$AWS_REGION" "$ENDPOINT_ID"
    local result=$?

    log_operation_result "VPC 解除關聯" "$result" "aws_vpn_admin.sh"

    if [ "$result" -eq 0 ]; then
        echo -e "${GREEN}VPC 解除關聯操作成功完成。${NC}"
        # 重新載入配置以確保任何更改都已反映
        if ! load_config_core "$CONFIG_FILE"; then # 使用統一函式
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
    if ! validate_endpoint_operation "$CONFIG_FILE"; then
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
    if ! validate_main_config "$CONFIG_FILE"; then
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
    if ! validate_endpoint_operation "$CONFIG_FILE"; then
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
        read -p "請選擇操作 (1-10, E): " choice
        
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
                "$SCRIPT_DIR/vpn_env.sh"
                echo -e "\n${YELLOW}按任意鍵返回主選單...${NC}"
                read -n 1
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
