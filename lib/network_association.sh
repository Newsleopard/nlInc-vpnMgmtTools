#!/bin/bash

# lib/network_association.sh
# VPN 網路關聯相關函式庫
# 包含子網路關聯、路由設定和授權規則管理功能

# 確保已載入核心函式
if [ -z "$LOG_FILE_CORE" ]; then
    echo "錯誤: 核心函式庫未載入。請先載入 core_functions.sh"
    exit 1
fi

# 關聯目標網絡到 VPN 端點
# 參數: $1 = endpoint_id, $2 = subnet_id, $3 = aws_region, $4 = security_group_id (可選)
_associate_target_network_ec() {
    local endpoint_id="$1"
    local subnet_id="$2"
    local aws_region="$3"
    local security_group_id="$4"
    
    # 參數驗證
    if [ -z "$endpoint_id" ] || [ -z "$subnet_id" ] || [ -z "$aws_region" ]; then
        echo -e "${RED}錯誤: _associate_target_network_ec 缺少必要參數${NC}" >&2
        log_message_core "錯誤: _associate_target_network_ec 缺少必要參數"
        return 1
    fi
    
    if ! validate_endpoint_id "$endpoint_id"; then
        echo -e "${RED}錯誤: 端點 ID 格式無效${NC}" >&2
        return 1
    fi
    
    if ! validate_subnet_id "$subnet_id"; then
        echo -e "${RED}錯誤: 子網路 ID 格式無效${NC}" >&2
        return 1
    fi
    
    if ! validate_aws_region "$aws_region"; then
        return 1
    fi
    
    log_message_core "開始關聯目標網絡: 端點=$endpoint_id, 子網路=$subnet_id"
    
    echo -e "${BLUE}正在關聯子網路到 VPN 端點...${NC}" >&2
    echo -e "${YELLOW}端點 ID: $endpoint_id${NC}" >&2
    echo -e "${YELLOW}子網路 ID: $subnet_id${NC}" >&2
    echo -e "${YELLOW}AWS 區域: $aws_region${NC}" >&2
    
    # 構建 AWS CLI 命令 (注意: associate-client-vpn-target-network 不支持 --security-groups 參數)
    local associate_cmd="aws ec2 associate-client-vpn-target-network \
        --client-vpn-endpoint-id $endpoint_id \
        --subnet-id $subnet_id \
        --region $aws_region"
    
    # 注意: 安全群組在 VPN 端點創建時已指定，子網路關聯時無需重複指定
    if [ -n "$security_group_id" ]; then
        echo -e "${YELLOW}安全群組 ID: $security_group_id (已在端點創建時配置)${NC}" >&2
    fi
    
    # 執行關聯命令
    local associate_output
    associate_output=$(eval "$associate_cmd" 2>&1)
    local associate_status=$?
    
    if [ $associate_status -ne 0 ]; then
        echo -e "${RED}錯誤: 關聯子網路失敗${NC}" >&2
        echo -e "${RED}AWS CLI 輸出: $associate_output${NC}" >&2
        log_message_core "錯誤: 關聯子網路失敗. 輸出: $associate_output"
        return 1
    fi
    
    # 提取關聯 ID
    local association_id
    if command -v jq >/dev/null 2>&1; then
        association_id=$(echo "$associate_output" | jq -r '.AssociationId' 2>/dev/null)
    else
        # 備用提取方法
        association_id=$(echo "$associate_output" | grep -o '"AssociationId": "[^"]*"' | sed 's/"AssociationId": "\([^"]*\)"/\1/')
    fi
    
    if [ -z "$association_id" ] || [ "$association_id" = "null" ]; then
        echo -e "${YELLOW}⚠️ 無法提取關聯 ID，但關聯可能成功${NC}" >&2
        log_message_core "警告: 無法提取關聯 ID. 輸出: $associate_output"
    else
        echo -e "${GREEN}✓ 子網路關聯成功${NC}" >&2
        echo -e "${GREEN}關聯 ID: $association_id${NC}" >&2
        log_message_core "子網路關聯成功: 關聯ID=$association_id"
    fi
    
    return 0
}

# 設定授權規則和路由
# 參數: $1 = endpoint_id, $2 = vpc_cidr, $3 = subnet_id, $4 = aws_region
_setup_authorization_and_routes_ec() {
    local endpoint_id="$1"
    local vpc_cidr="$2" # 主要 VPC 的 CIDR，用於初始授權
    local subnet_id="$3" # 主要子網路 ID，用於初始路由
    local aws_region="$4"
    
    # 參數驗證
    if [ -z "$endpoint_id" ] || [ -z "$vpc_cidr" ] || [ -z "$aws_region" ]; then
        echo -e "${RED}錯誤: _setup_authorization_and_routes_ec 缺少必要參數${NC}" >&2
        log_message_core "錯誤: _setup_authorization_and_routes_ec 缺少必要參數"
        return 1
    fi
    
    if ! validate_endpoint_id "$endpoint_id"; then
        echo -e "${RED}錯誤: 端點 ID 格式無效${NC}" >&2
        return 1
    fi
    
    if ! validate_aws_region "$aws_region"; then
        return 1
    fi
    
    log_message_core "開始設定授權規則和路由: 端點=$endpoint_id, VPC_CIDR=$vpc_cidr"
    
    echo -e "${BLUE}正在設定 VPN 授權規則和路由...${NC}" >&2
    echo -e "${YELLOW}端點 ID: $endpoint_id${NC}" >&2
    echo -e "${YELLOW}VPC CIDR: $vpc_cidr${NC}" >&2
    echo -e "${YELLOW}子網路 ID: $subnet_id${NC}" >&2
    
    # 設定授權規則 - 允許所有用戶訪問 VPC
    echo -e "${CYAN}設定授權規則...${NC}" >&2
    local auth_output
    auth_output=$(aws ec2 authorize-client-vpn-ingress \
        --client-vpn-endpoint-id "$endpoint_id" \
        --target-network-cidr "$vpc_cidr" \
        --authorize-all-groups \
        --description "Allow access to VPC $vpc_cidr" \
        --region "$aws_region" 2>&1)
    
    local auth_status=$?
    
    if [ $auth_status -ne 0 ]; then
        echo -e "${RED}錯誤: 設定授權規則失敗${NC}" >&2
        echo -e "${RED}AWS CLI 輸出: $auth_output${NC}" >&2
        log_message_core "錯誤: 設定授權規則失敗. 輸出: $auth_output"
        return 1
    fi
    
    echo -e "${GREEN}✓ 授權規則設定成功${NC}" >&2
    log_message_core "授權規則設定成功: VPC CIDR=$vpc_cidr"
    
    # 設定路由規則 - 如果提供了子網路 ID
    if [ -n "$subnet_id" ]; then
        echo -e "${CYAN}檢查並設定路由規則...${NC}" >&2
        
        # 首先檢查路由是否已存在
        local existing_routes
        existing_routes=$(aws ec2 describe-client-vpn-routes \
            --client-vpn-endpoint-id "$endpoint_id" \
            --region "$aws_region" \
            --query "Routes[?DestinationCidr=='$vpc_cidr'].DestinationCidr" \
            --output text 2>/dev/null)
        
        if [ -n "$existing_routes" ] && [ "$existing_routes" != "None" ]; then
            echo -e "${GREEN}✓ 路由已存在: $vpc_cidr (AWS 自動建立)${NC}" >&2
            log_message_core "路由已存在，跳過創建: 目標=$vpc_cidr"
        else
            echo -e "${CYAN}創建新路由規則...${NC}" >&2
            local route_output
            route_output=$(aws ec2 create-client-vpn-route \
                --client-vpn-endpoint-id "$endpoint_id" \
                --destination-cidr-block "$vpc_cidr" \
                --target-vpc-subnet-id "$subnet_id" \
                --description "Route to VPC $vpc_cidr via subnet $subnet_id" \
                --region "$aws_region" 2>&1)
            
            local route_status=$?
            
            if [ $route_status -ne 0 ]; then
                # 檢查是否是重複路由錯誤
                if echo "$route_output" | grep -q "InvalidClientVpnDuplicateRoute"; then
                    echo -e "${GREEN}✓ 路由已存在 (重複路由檢測)${NC}" >&2
                    log_message_core "路由已存在，AWS 報告重複: 目標=$vpc_cidr"
                else
                    echo -e "${RED}錯誤: 設定路由規則失敗${NC}" >&2
                    echo -e "${RED}AWS CLI 輸出: $route_output${NC}" >&2
                    log_message_core "錯誤: 設定路由規則失敗. 輸出: $route_output"
                    return 1
                fi
            else
                echo -e "${GREEN}✓ 路由規則設定成功${NC}" >&2
                log_message_core "路由規則設定成功: 目標=$vpc_cidr, 子網路=$subnet_id"
            fi
        fi
    else
        echo -e "${YELLOW}⚠️ 沒有提供子網路 ID，跳過路由規則設定${NC}" >&2
        log_message_core "警告: 沒有提供子網路 ID，跳過路由規則設定"
    fi
    
    # 設定網際網路訪問授權（可選）
    echo -e "${CYAN}設定網際網路訪問授權...${NC}" >&2
    local internet_auth_output
    internet_auth_output=$(aws ec2 authorize-client-vpn-ingress \
        --client-vpn-endpoint-id "$endpoint_id" \
        --target-network-cidr "0.0.0.0/0" \
        --authorize-all-groups \
        --description "Allow internet access" \
        --region "$aws_region" 2>&1)
    
    local internet_auth_status=$?
    
    if [ $internet_auth_status -ne 0 ]; then
        echo -e "${YELLOW}⚠️ 設定網際網路訪問授權失敗（這是正常的，可能不需要）${NC}" >&2
        echo -e "${YELLOW}輸出: $internet_auth_output${NC}" >&2
        log_message_core "警告: 設定網際網路訪問授權失敗（可能不需要）"
    else
        echo -e "${GREEN}✓ 網際網路訪問授權設定成功${NC}" >&2
        log_message_core "網際網路訪問授權設定成功"
    fi
    
    return 0
}

# 關聯一個 VPC 到端點 (用於多 VPC 場景)
# 參數: $1 = main_config_file, $2 = aws_region, $3 = endpoint_id, $4 = target_vpc_id, $5 = target_subnet_id, $6 = security_group_id (可選)
_associate_one_vpc_to_endpoint_lib() {
    local main_config_file="$1"
    local arg_aws_region="$2"
    local arg_endpoint_id="$3"
    local target_vpc_id="$4"
    local target_subnet_id="$5"
    local security_group_id="$6"
    
    # 參數驗證
    if [ -z "$main_config_file" ] || [ -z "$arg_aws_region" ] || [ -z "$arg_endpoint_id" ] || [ -z "$target_vpc_id" ] || [ -z "$target_subnet_id" ]; then
        echo -e "${RED}錯誤: _associate_one_vpc_to_endpoint_lib 缺少必要參數${NC}" >&2
        log_message_core "錯誤: _associate_one_vpc_to_endpoint_lib 缺少必要參數"
        return 1
    fi
    
    if ! validate_endpoint_id "$arg_endpoint_id"; then
        echo -e "${RED}錯誤: 端點 ID 格式無效${NC}" >&2
        return 1
    fi
    
    if ! validate_vpc_id "$target_vpc_id"; then
        echo -e "${RED}錯誤: VPC ID 格式無效${NC}" >&2
        return 1
    fi
    
    if ! validate_subnet_id "$target_subnet_id"; then
        echo -e "${RED}錯誤: 子網路 ID 格式無效${NC}" >&2
        return 1
    fi
    
    if ! validate_aws_region "$arg_aws_region"; then
        return 1
    fi
    
    log_message_core "開始關聯 VPC 到端點 (lib): 端點=$arg_endpoint_id, VPC=$target_vpc_id, 子網路=$target_subnet_id"
    
    echo -e "${CYAN}=== 關聯 VPC 到現有 VPN 端點 ===${NC}"
    echo -e "${YELLOW}端點 ID: $arg_endpoint_id${NC}"
    echo -e "${YELLOW}目標 VPC: $target_vpc_id${NC}"
    echo -e "${YELLOW}目標子網路: $target_subnet_id${NC}"
    echo -e "${YELLOW}AWS 區域: $arg_aws_region${NC}"
    
    # 獲取目標 VPC 的 CIDR
    echo -e "\n${CYAN}步驟 1: 獲取目標 VPC 資訊${NC}"
    local target_vpc_cidr
    
    # 載入 VPC 操作函式庫
    local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    if [ -f "$script_dir/vpc_operations.sh" ]; then
        source "$script_dir/vpc_operations.sh"
        
        if command -v get_vpc_cidr >/dev/null 2>&1; then
            target_vpc_cidr=$(get_vpc_cidr "$target_vpc_id" "$arg_aws_region")
            if [ $? -ne 0 ] || [ -z "$target_vpc_cidr" ]; then
                echo -e "${RED}錯誤: 無法獲取目標 VPC CIDR${NC}"
                return 1
            fi
        else
            # 備用方法
            target_vpc_cidr=$(aws ec2 describe-vpcs --vpc-ids "$target_vpc_id" --region "$arg_aws_region" --query 'Vpcs[0].CidrBlock' --output text 2>/dev/null)
            if [ -z "$target_vpc_cidr" ] || [ "$target_vpc_cidr" = "None" ]; then
                echo -e "${RED}錯誤: 無法獲取目標 VPC CIDR${NC}"
                return 1
            fi
        fi
    else
        echo -e "${YELLOW}⚠️ VPC 操作函式庫不可用，使用直接 AWS CLI${NC}"
        target_vpc_cidr=$(aws ec2 describe-vpcs --vpc-ids "$target_vpc_id" --region "$arg_aws_region" --query 'Vpcs[0].CidrBlock' --output text 2>/dev/null)
        if [ -z "$target_vpc_cidr" ] || [ "$target_vpc_cidr" = "None" ]; then
            echo -e "${RED}錯誤: 無法獲取目標 VPC CIDR${NC}"
            return 1
        fi
    fi
    
    echo -e "${GREEN}✓ 目標 VPC CIDR: $target_vpc_cidr${NC}"
    
    # 步驟 2: 關聯子網路
    echo -e "\n${CYAN}步驟 2: 關聯目標子網路${NC}"
    if ! _associate_target_network_ec "$arg_endpoint_id" "$target_subnet_id" "$arg_aws_region" "$security_group_id"; then
        echo -e "${RED}錯誤: 關聯目標子網路失敗${NC}"
        return 1
    fi
    
    # 步驟 3: 設定授權和路由
    echo -e "\n${CYAN}步驟 3: 設定授權和路由${NC}"
    if ! _setup_authorization_and_routes_ec "$arg_endpoint_id" "$target_vpc_cidr" "$target_subnet_id" "$arg_aws_region"; then
        echo -e "${RED}錯誤: 設定授權和路由失敗${NC}"
        return 1
    fi
    
    # 步驟 4: 更新配置文件（如果需要）
    echo -e "\n${CYAN}步驟 4: 更新配置記錄${NC}"
    local endpoint_config_file="${main_config_file%/*}/vpn_endpoint.conf"
    
    if [ -f "$endpoint_config_file" ]; then
        # 載入配置管理函式庫
        if [ -f "$script_dir/endpoint_config.sh" ]; then
            source "$script_dir/endpoint_config.sh"
            
            if command -v update_config_value >/dev/null 2>&1; then
                # 更新多 VPC 計數
                local current_count
                current_count=$(grep "^MULTI_VPC_COUNT=" "$endpoint_config_file" | cut -d'=' -f2 | tr -d '"' || echo "0")
                current_count=${current_count:-0}
                new_count=$((current_count + 1))
                
                update_config_value "$endpoint_config_file" "MULTI_VPC_COUNT" "$new_count"
                
                # 記錄新的 VPC 資訊
                echo "# Additional VPC $new_count - Added $(date)" >> "$endpoint_config_file"
                echo "ADDITIONAL_VPC_${new_count}_ID=\"$target_vpc_id\"" >> "$endpoint_config_file"
                echo "ADDITIONAL_VPC_${new_count}_SUBNET_ID=\"$target_subnet_id\"" >> "$endpoint_config_file"
                echo "ADDITIONAL_VPC_${new_count}_CIDR=\"$target_vpc_cidr\"" >> "$endpoint_config_file"
                echo "" >> "$endpoint_config_file"
                
                echo -e "${GREEN}✓ 配置文件已更新${NC}"
                log_message_core "多 VPC 配置已更新: VPC=$target_vpc_id, 計數=$new_count"
            else
                echo -e "${YELLOW}⚠️ 配置更新函式不可用${NC}"
            fi
        else
            echo -e "${YELLOW}⚠️ 配置管理函式庫不可用${NC}"
        fi
    else
        echo -e "${YELLOW}⚠️ 端點配置文件不存在: $endpoint_config_file${NC}"
    fi
    
    echo -e "\n${GREEN}=== VPC 關聯完成 ===${NC}"
    echo -e "${GREEN}目標 VPC ($target_vpc_id) 已成功關聯到 VPN 端點${NC}"
    log_message_core "VPC 關聯完成: VPC=$target_vpc_id, 端點=$arg_endpoint_id"
    
    return 0
}

# 檢查網路關聯狀態
# 參數: $1 = endpoint_id, $2 = aws_region
check_network_associations() {
    local endpoint_id="$1"
    local aws_region="$2"
    
    if [ -z "$endpoint_id" ] || [ -z "$aws_region" ]; then
        echo -e "${RED}錯誤: check_network_associations 缺少必要參數${NC}" >&2
        return 1
    fi
    
    if ! validate_endpoint_id "$endpoint_id"; then
        echo -e "${RED}錯誤: 端點 ID 格式無效${NC}" >&2
        return 1
    fi
    
    echo -e "${BLUE}檢查網路關聯狀態...${NC}"
    
    local associations
    associations=$(aws ec2 describe-client-vpn-target-networks \
        --client-vpn-endpoint-id "$endpoint_id" \
        --region "$aws_region" \
        --output table 2>/dev/null)
    
    if [ $? -ne 0 ]; then
        echo -e "${RED}錯誤: 無法檢查網路關聯狀態${NC}"
        return 1
    fi
    
    echo "$associations"
    return 0
}

# 檢查授權規則
# 參數: $1 = endpoint_id, $2 = aws_region
check_authorization_rules() {
    local endpoint_id="$1"
    local aws_region="$2"
    
    if [ -z "$endpoint_id" ] || [ -z "$aws_region" ]; then
        echo -e "${RED}錯誤: check_authorization_rules 缺少必要參數${NC}" >&2
        return 1
    fi
    
    if ! validate_endpoint_id "$endpoint_id"; then
        echo -e "${RED}錯誤: 端點 ID 格式無效${NC}" >&2
        return 1
    fi
    
    echo -e "${BLUE}檢查授權規則...${NC}"
    
    local auth_rules
    auth_rules=$(aws ec2 describe-client-vpn-authorization-rules \
        --client-vpn-endpoint-id "$endpoint_id" \
        --region "$aws_region" \
        --output table 2>/dev/null)
    
    if [ $? -ne 0 ]; then
        echo -e "${RED}錯誤: 無法檢查授權規則${NC}"
        return 1
    fi
    
    echo "$auth_rules"
    return 0
}