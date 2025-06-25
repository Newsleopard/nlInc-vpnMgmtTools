#!/bin/bash

# lib/endpoint_operations.sh
# VPN 端點操作相關函式庫
# 包含端點創建、刪除、狀態監控等核心功能

# 確保已載入核心函式
if [ -z "$LOG_FILE_CORE" ]; then
    echo "錯誤: 核心函式庫未載入。請先載入 core_functions.sh"
    exit 1
fi

# 創建 AWS Client VPN 端點
# 參數: $1 = vpn_cidr, $2 = server_cert_arn, $3 = client_cert_arn, $4 = vpn_name, $5 = aws_region
# 返回: endpoint_id
_create_aws_client_vpn_endpoint_ec() {
    local vpn_cidr="$1"
    local server_cert_arn="$2"
    local client_cert_arn="$3"
    local vpn_name="$4"
    local aws_region="$5"
    
    # 參數驗證
    if [ -z "$vpn_cidr" ] || [ -z "$server_cert_arn" ] || [ -z "$client_cert_arn" ] || [ -z "$vpn_name" ] || [ -z "$aws_region" ]; then
        echo -e "${RED}錯誤: _create_aws_client_vpn_endpoint_ec 缺少必要參數${NC}" >&2
        log_message_core "錯誤: _create_aws_client_vpn_endpoint_ec 缺少必要參數"
        return 1
    fi
    
    log_message_core "開始創建 AWS Client VPN 端點 - CIDR: $vpn_cidr, 名稱: $vpn_name"
    
    echo -e "${BLUE}正在創建 Client VPN 端點...${NC}" >&2
    echo -e "${YELLOW}VPN CIDR: $vpn_cidr${NC}" >&2
    echo -e "${YELLOW}VPN 名稱: $vpn_name${NC}" >&2
    echo -e "${YELLOW}AWS 區域: $aws_region${NC}" >&2
    
    # 創建 CloudWatch 日誌群組（如果不存在）
    local log_group_name="/aws/clientvpn/$vpn_name"
    echo -e "${BLUE}檢查並創建 CloudWatch 日誌群組: $log_group_name${NC}" >&2
    
    if ! aws logs describe-log-groups --log-group-name-prefix "$log_group_name" --region "$aws_region" --query 'logGroups[?logGroupName==`'$log_group_name'`]' --output text | grep -q "$log_group_name"; then
        echo -e "${BLUE}創建 CloudWatch 日誌群組...${NC}" >&2
        if aws logs create-log-group --log-group-name "$log_group_name" --region "$aws_region" 2>/dev/null; then
            echo -e "${GREEN}✓ CloudWatch 日誌群組已創建${NC}" >&2
        else
            echo -e "${YELLOW}⚠️ 無法創建 CloudWatch 日誌群組，將禁用日誌記錄${NC}" >&2
            log_group_name=""
        fi
    else
        echo -e "${GREEN}✓ CloudWatch 日誌群組已存在${NC}" >&2
    fi
    
    # 準備連接日誌選項
    local connection_log_options
    if [ -n "$log_group_name" ]; then
        connection_log_options="Enabled=true,CloudwatchLogGroup=$log_group_name"
    else
        connection_log_options="Enabled=false"
    fi
    
    # 執行 AWS CLI 創建端點命令
    local create_output
    create_output=$(aws ec2 create-client-vpn-endpoint \
        --client-cidr-block "$vpn_cidr" \
        --server-certificate-arn "$server_cert_arn" \
        --authentication-options Type=certificate-authentication,MutualAuthentication="{ClientRootCertificateChainArn=$client_cert_arn}" \
        --connection-log-options "$connection_log_options" \
        --description "Client VPN Endpoint - $vpn_name" \
        --tag-specifications ResourceType=client-vpn-endpoint,Tags='[{Key=Name,Value='$vpn_name'},{Key=ManagedBy,Value=nlInc-vpnMgmtTools}]' \
        --region "$aws_region" 2>&1)
    
    local create_status=$?
    
    if [ $create_status -ne 0 ]; then
        echo -e "${RED}錯誤: 創建 Client VPN 端點失敗${NC}" >&2
        echo -e "${RED}AWS CLI 輸出: $create_output${NC}" >&2
        log_message_core "錯誤: 創建 Client VPN 端點失敗. 輸出: $create_output"
        return 1
    fi
    
    # 提取端點 ID
    local endpoint_id
    if command -v jq >/dev/null 2>&1; then
        endpoint_id=$(echo "$create_output" | jq -r '.ClientVpnEndpointId' 2>/dev/null)
    else
        # 備用提取方法
        endpoint_id=$(echo "$create_output" | grep -o '"ClientVpnEndpointId": "[^"]*"' | sed 's/"ClientVpnEndpointId": "\([^"]*\)"/\1/')
    fi
    
    # 驗證端點 ID
    if [ -z "$endpoint_id" ] || [ "$endpoint_id" = "null" ]; then
        echo -e "${RED}錯誤: 無法從創建輸出中提取端點 ID${NC}" >&2
        echo -e "${RED}創建輸出: $create_output${NC}" >&2
        log_message_core "錯誤: 無法提取端點 ID. 創建輸出: $create_output"
        return 1
    fi
    
    if ! validate_endpoint_id "$endpoint_id"; then
        echo -e "${RED}錯誤: 提取的端點 ID 格式無效: $endpoint_id${NC}" >&2
        log_message_core "錯誤: 端點 ID 格式無效: $endpoint_id"
        return 1
    fi
    
    echo -e "${GREEN}✓ Client VPN 端點創建成功${NC}" >&2
    echo -e "${GREEN}端點 ID: $endpoint_id${NC}" >&2
    
    log_message_core "Client VPN 端點創建成功: $endpoint_id"
    echo "$endpoint_id"
    return 0
}

# 等待 Client VPN 端點變為可用狀態
# 參數: $1 = endpoint_id, $2 = aws_region
_wait_for_client_vpn_endpoint_available() {
    local endpoint_id="$1"
    local aws_region="$2"
    local max_wait_time=600  # 最大等待時間（秒）- 增加到10分鐘
    local check_interval=15  # 檢查間隔（秒）- 減少頻率
    local elapsed_time=0
    
    # 參數驗證
    if [ -z "$endpoint_id" ] || [ -z "$aws_region" ]; then
        echo -e "${RED}錯誤: _wait_for_client_vpn_endpoint_available 缺少必要參數${NC}" >&2
        return 1
    fi
    
    if ! validate_endpoint_id "$endpoint_id"; then
        echo -e "${RED}錯誤: 端點 ID 格式無效${NC}" >&2
        return 1
    fi
    
    echo -e "${BLUE}等待 VPN 端點變為可用狀態...${NC}" >&2
    echo -e "${YELLOW}端點 ID: $endpoint_id${NC}" >&2
    echo -e "${YELLOW}最大等待時間: ${max_wait_time}秒${NC}" >&2
    
    while [ $elapsed_time -lt $max_wait_time ]; do
        # 檢查端點狀態
        local status
        status=$(aws ec2 describe-client-vpn-endpoints \
            --client-vpn-endpoint-ids "$endpoint_id" \
            --region "$aws_region" \
            --query 'ClientVpnEndpoints[0].Status.Code' \
            --output text 2>/dev/null)
        
        local status_check=$?
        
        if [ $status_check -ne 0 ]; then
            echo -e "${RED}錯誤: 無法檢查端點狀態${NC}" >&2
            log_message_core "錯誤: 無法檢查端點 $endpoint_id 的狀態"
            return 1
        fi
        
        echo -e "${CYAN}當前狀態: $status (等待時間: ${elapsed_time}s/${max_wait_time}s)${NC}" >&2
        
        case "$status" in
            "available")
                echo -e "${GREEN}✓ VPN 端點已變為可用狀態${NC}" >&2
                log_message_core "VPN 端點 $endpoint_id 已變為可用狀態"
                return 0
                ;;
            "pending-associate")
                echo -e "${YELLOW}端點狀態: 等待關聯${NC}" >&2
                ;;
            "pending")
                echo -e "${YELLOW}端點狀態: 創建中${NC}" >&2
                ;;
            "deleting")
                echo -e "${RED}錯誤: 端點正在被刪除${NC}" >&2
                log_message_core "錯誤: 端點 $endpoint_id 正在被刪除"
                return 1
                ;;
            "deleted")
                echo -e "${RED}錯誤: 端點已被刪除${NC}" >&2
                log_message_core "錯誤: 端點 $endpoint_id 已被刪除"
                return 1
                ;;
            *)
                echo -e "${YELLOW}端點狀態: $status${NC}" >&2
                ;;
        esac
        
        # 等待檢查間隔
        sleep $check_interval
        elapsed_time=$((elapsed_time + check_interval))
    done
    
    # 超時
    echo -e "${RED}錯誤: 等待端點可用超時（${max_wait_time}秒）${NC}" >&2
    echo -e "${RED}最後狀態: $status${NC}" >&2
    log_message_core "錯誤: 等待端點 $endpoint_id 可用超時"
    return 1
}

# 刪除 VPN 端點 (庫函式版本)
# 參數: $1 = aws_region, $2 = endpoint_id, $3 = vpn_name, $4 = config_file (可選)
terminate_vpn_endpoint_lib() {
    local aws_region="$1"
    local endpoint_id="$2"
    local vpn_name="$3"
    local config_file="$4"
    
    # 參數驗證
    if [ -z "$aws_region" ] || [ -z "$endpoint_id" ]; then
        echo -e "${RED}錯誤: terminate_vpn_endpoint_lib 缺少必要參數${NC}" >&2
        log_message_core "錯誤: terminate_vpn_endpoint_lib 缺少必要參數"
        return 1
    fi
    
    if ! validate_endpoint_id "$endpoint_id"; then
        echo -e "${RED}錯誤: 端點 ID 格式無效: $endpoint_id${NC}" >&2
        return 1
    fi
    
    if ! validate_aws_region "$aws_region"; then
        return 1
    fi
    
    log_message_core "開始刪除 VPN 端點 (lib): $endpoint_id"
    
    echo -e "${CYAN}=== 開始刪除 VPN 端點 ===${NC}"
    echo -e "${YELLOW}端點 ID: $endpoint_id${NC}"
    echo -e "${YELLOW}VPN 名稱: ${vpn_name:-未知}${NC}"
    echo -e "${YELLOW}AWS 區域: $aws_region${NC}"
    
    # 步驟 1: 檢查端點是否存在
    echo -e "\n${CYAN}步驟 1: 檢查端點狀態${NC}"
    local endpoint_status
    endpoint_status=$(aws ec2 describe-client-vpn-endpoints \
        --client-vpn-endpoint-ids "$endpoint_id" \
        --region "$aws_region" \
        --query 'ClientVpnEndpoints[0].Status.Code' \
        --output text 2>/dev/null)
    
    if [ $? -ne 0 ] || [ "$endpoint_status" = "None" ] || [ -z "$endpoint_status" ]; then
        echo -e "${YELLOW}⚠️ 端點不存在或已被刪除: $endpoint_id${NC}"
        log_message_core "端點不存在或已被刪除: $endpoint_id"
        # 繼續執行清理步驟
    else
        echo -e "${GREEN}✓ 端點存在，狀態: $endpoint_status${NC}"
        
        # 步驟 2: 取消關聯所有目標網絡
        echo -e "\n${CYAN}步驟 2: 取消關聯目標網絡${NC}"
        local target_networks
        target_networks=$(aws ec2 describe-client-vpn-target-networks \
            --client-vpn-endpoint-id "$endpoint_id" \
            --region "$aws_region" \
            --query 'ClientVpnTargetNetworks[*].AssociationId' \
            --output text 2>/dev/null)
        
        if [ -n "$target_networks" ] && [ "$target_networks" != "None" ]; then
            echo -e "${BLUE}發現關聯的目標網絡，正在取消關聯...${NC}"
            for association_id in $target_networks; do
                echo -e "${YELLOW}  取消關聯: $association_id${NC}"
                if aws ec2 disassociate-client-vpn-target-network \
                    --client-vpn-endpoint-id "$endpoint_id" \
                    --association-id "$association_id" \
                    --region "$aws_region" >/dev/null 2>&1; then
                    echo -e "${GREEN}  ✓ 成功取消關聯: $association_id${NC}"
                else
                    echo -e "${YELLOW}  ⚠️ 無法取消關聯: $association_id（可能已被取消）${NC}"
                fi
            done
            
            # 等待取消關聯完成
            echo -e "${BLUE}等待取消關聯完成...${NC}"
            sleep 10
        else
            echo -e "${GREEN}✓ 沒有關聯的目標網絡${NC}"
        fi
        
        # 步驟 3: 刪除授權規則
        echo -e "\n${CYAN}步驟 3: 刪除授權規則${NC}"
        local auth_rules
        auth_rules=$(aws ec2 describe-client-vpn-authorization-rules \
            --client-vpn-endpoint-id "$endpoint_id" \
            --region "$aws_region" \
            --query 'AuthorizationRules[?Status.Code!=`revoking` && Status.Code!=`revoked`].[DestinationCidr,GroupId]' \
            --output text 2>/dev/null)
        
        if [ -n "$auth_rules" ] && [ "$auth_rules" != "None" ]; then
            echo -e "${BLUE}發現授權規則，正在刪除...${NC}"
            echo "$auth_rules" | while read -r dest_cidr group_id; do
                if [ -n "$dest_cidr" ]; then
                    echo -e "${YELLOW}  刪除授權規則: $dest_cidr${NC}"
                    local revoke_cmd="aws ec2 revoke-client-vpn-authorization --client-vpn-endpoint-id $endpoint_id --target-network-cidr $dest_cidr --region $aws_region"
                    if [ -n "$group_id" ] && [ "$group_id" != "None" ]; then
                        revoke_cmd="$revoke_cmd --access-group-id $group_id"
                    fi
                    
                    if eval "$revoke_cmd" >/dev/null 2>&1; then
                        echo -e "${GREEN}  ✓ 成功刪除授權規則: $dest_cidr${NC}"
                    else
                        echo -e "${YELLOW}  ⚠️ 無法刪除授權規則: $dest_cidr（可能已被刪除）${NC}"
                    fi
                fi
            done
            
            # 等待授權規則刪除完成
            echo -e "${BLUE}等待授權規則刪除完成...${NC}"
            sleep 10
        else
            echo -e "${GREEN}✓ 沒有授權規則需要刪除${NC}"
        fi
        
        # 步驟 4: 刪除端點
        echo -e "\n${CYAN}步驟 4: 刪除 VPN 端點${NC}"
        if aws ec2 delete-client-vpn-endpoint \
            --client-vpn-endpoint-id "$endpoint_id" \
            --region "$aws_region" >/dev/null 2>&1; then
            echo -e "${GREEN}✓ VPN 端點刪除命令已發送${NC}"
            log_message_core "VPN 端點刪除命令已發送: $endpoint_id"
        else
            echo -e "${YELLOW}⚠️ VPN 端點刪除命令失敗（端點可能已被刪除）${NC}"
            log_message_core "警告: VPN 端點刪除命令失敗: $endpoint_id"
        fi
    fi
    
    # 步驟 5: 刪除 ACM 證書 (Fix 2)
    echo -e "\n${CYAN}步驟 5: 刪除 ACM 證書${NC}"
    
    # 從配置文件收集證書 ARN
    local cert_arns_to_delete=()
    
    if [ -n "$config_file" ] && [ -f "$config_file" ]; then
        echo -e "${BLUE}從配置文件收集證書 ARN: $config_file${NC}"
        
        # 臨時載入配置文件
        local temp_config
        temp_config=$(mktemp)
        cp "$config_file" "$temp_config"
        source "$temp_config"
        
        # 收集所有證書 ARN
        [ -n "$SERVER_CERT_ARN" ] && cert_arns_to_delete+=("$SERVER_CERT_ARN")
        [ -n "$CA_CERT_ARN" ] && cert_arns_to_delete+=("$CA_CERT_ARN")
        [ -n "$CLIENT_CERT_ARN" ] && cert_arns_to_delete+=("$CLIENT_CERT_ARN")
        [ -n "$CLIENT_CERT_ARN_admin" ] && cert_arns_to_delete+=("$CLIENT_CERT_ARN_admin")
        
        rm -f "$temp_config"
    else
        echo -e "${YELLOW}⚠️ 配置文件不存在或未提供，跳過自動證書刪除${NC}"
        log_message_core "警告: 配置文件不存在，跳過自動證書刪除"
    fi
    
    # 刪除收集到的證書
    if [ ${#cert_arns_to_delete[@]} -gt 0 ]; then
        for cert_arn in "${cert_arns_to_delete[@]}"; do
            if [ -n "$cert_arn" ] && [[ "$cert_arn" =~ ^arn:aws:acm: ]]; then
                echo -e "${YELLOW}  刪除證書: ${cert_arn:0:50}...${NC}"
                if aws acm delete-certificate --certificate-arn "$cert_arn" --region "$aws_region" >/dev/null 2>&1; then
                    echo -e "${GREEN}  ✓ 證書刪除成功${NC}"
                    log_message_core "證書刪除成功: $cert_arn"
                else
                    echo -e "${YELLOW}  ⚠️ 證書刪除失敗（可能已被刪除或被其他資源使用）${NC}"
                    log_message_core "警告: 證書刪除失敗: $cert_arn"
                fi
            fi
        done
    else
        echo -e "${GREEN}✓ 沒有證書需要刪除${NC}"
    fi
    
    # 步驟 6: 刪除專用安全群組 (來自原始程式碼)
    echo -e "\n${CYAN}步驟 6: 清理專用安全群組${NC}"
    
    local client_vpn_sg_id=""
    if [ -n "$config_file" ] && [ -f "$config_file" ]; then
        # 從配置文件獲取安全群組 ID
        client_vpn_sg_id=$(grep -o 'CLIENT_VPN_SECURITY_GROUP_ID="[^"]*"' "$config_file" 2>/dev/null | cut -d'"' -f2)
    fi
    
    if [ -n "$client_vpn_sg_id" ]; then
        echo -e "${BLUE}發現專用安全群組: $client_vpn_sg_id${NC}"
        
        # 載入安全群組操作函式庫
        local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
        if [ -f "$script_dir/security_group_operations.sh" ]; then
            source "$script_dir/security_group_operations.sh"
            
            if command -v delete_client_vpn_security_group >/dev/null 2>&1; then
                delete_client_vpn_security_group "$client_vpn_sg_id" "$aws_region"
            else
                echo -e "${YELLOW}⚠️ 安全群組刪除函式不可用${NC}"
            fi
        else
            echo -e "${YELLOW}⚠️ 安全群組操作函式庫不可用，手動檢查安全群組: $client_vpn_sg_id${NC}"
        fi
    else
        echo -e "${GREEN}✓ 沒有專用安全群組需要清理${NC}"
    fi
    
    # 步驟 7: 清理配置文件
    echo -e "\n${CYAN}步驟 7: 清理配置文件${NC}"
    
    if [ -n "$config_file" ] && [ -f "$config_file" ]; then
        echo -e "${BLUE}清理配置文件: $config_file${NC}"
        
        # 載入配置管理函式庫
        local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
        if [ -f "$script_dir/endpoint_config.sh" ]; then
            source "$script_dir/endpoint_config.sh"
            
            if command -v clear_config_values >/dev/null 2>&1; then
                # 清空關鍵配置值
                clear_config_values "$config_file" \
                    "ENDPOINT_ID" \
                    "CLIENT_VPN_SECURITY_GROUP_ID" \
                    "SERVER_CERT_ARN" \
                    "CA_CERT_ARN" \
                    "CLIENT_CERT_ARN" \
                    "CLIENT_CERT_ARN_admin" \
                    "VPC_CIDR" \
                    "SECURITY_GROUPS"
                echo -e "${GREEN}✓ 配置文件已清理${NC}"
            else
                echo -e "${YELLOW}⚠️ 配置清理函式不可用${NC}"
            fi
        else
            echo -e "${YELLOW}⚠️ 配置管理函式庫不可用${NC}"
        fi
    else
        echo -e "${GREEN}✓ 沒有配置文件需要清理${NC}"
    fi
    
    echo -e "\n${GREEN}=== VPN 端點刪除流程完成 ===${NC}"
    log_message_core "VPN 端點刪除流程完成: $endpoint_id"
    
    return 0
}

# 檢查端點狀態
# 參數: $1 = endpoint_id, $2 = aws_region
check_endpoint_status() {
    local endpoint_id="$1"
    local aws_region="$2"
    
    if [ -z "$endpoint_id" ] || [ -z "$aws_region" ]; then
        echo -e "${RED}錯誤: check_endpoint_status 缺少必要參數${NC}" >&2
        return 1
    fi
    
    if ! validate_endpoint_id "$endpoint_id"; then
        echo -e "${RED}錯誤: 端點 ID 格式無效${NC}" >&2
        return 1
    fi
    
    local status
    status=$(aws ec2 describe-client-vpn-endpoints \
        --client-vpn-endpoint-ids "$endpoint_id" \
        --region "$aws_region" \
        --query 'ClientVpnEndpoints[0].Status.Code' \
        --output text 2>/dev/null)
    
    if [ $? -ne 0 ] || [ "$status" = "None" ] || [ -z "$status" ]; then
        echo "not-found"
        return 1
    fi
    
    echo "$status"
    return 0
}