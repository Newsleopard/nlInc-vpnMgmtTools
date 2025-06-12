#!/bin/bash

# lib/endpoint_management.sh
# VPN 端點管理相關函式庫
# 包含端點列表、配置生成、團隊設定等功能

# 確保已載入核心函式
if [ -z "$LOG_FILE_CORE" ]; then
    echo "錯誤: 核心函式庫未載入。請先載入 core_functions.sh"
    exit 1
fi

# 確保已載入憑證管理函式庫 (需要 generate_admin_certificate_lib)
if ! command -v generate_admin_certificate_lib >/dev/null 2>&1; then
    SCRIPT_DIR_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    if [ -f "$SCRIPT_DIR_LIB/cert_management.sh" ]; then
        source "$SCRIPT_DIR_LIB/cert_management.sh"
    else
        echo "錯誤: 憑證管理函式庫未載入且無法找到 cert_management.sh"
        exit 1
    fi
fi

# 查看端點關聯的網絡 (庫函式版本)
# 參數: $1 = AWS_REGION, $2 = ENDPOINT_ID
view_associated_networks_lib() {
    local aws_region="$1"
    local endpoint_id="$2"
    
    if [ -z "$aws_region" ] || [ -z "$endpoint_id" ]; then
        echo -e "${RED}錯誤: AWS 區域和端點 ID 不能為空${NC}"
        return 1
    fi
    
    # 獲取關聯的網絡
    local target_networks_json associated_subnets_count
    target_networks_json=$(aws ec2 describe-client-vpn-target-networks --client-vpn-endpoint-id "$endpoint_id" --region "$aws_region" 2>/dev/null)
    
    if [ $? -eq 0 ] && [ -n "$target_networks_json" ]; then
        if command -v jq >/dev/null 2>&1; then
            # 使用 jq 解析
            if ! associated_subnets_count=$(echo "$target_networks_json" | jq '.ClientVpnTargetNetworks | length' 2>/dev/null); then
                # 備用解析方法：使用 grep 統計子網數
                associated_subnets_count=$(echo "$target_networks_json" | grep -c '"TargetNetworkId"' || echo "0")
            fi
            
            if [ "$associated_subnets_count" -gt 0 ]; then
                echo "$target_networks_json" | jq -r '.ClientVpnTargetNetworks[] | "  - 子網路 ID: \(.TargetNetworkId), VPC ID: \(.VpcId), 狀態: \(.Status.Code)"'
            else
                echo "  未關聯任何子網路"
            fi
        else
            # 無 jq 時的備用解析方法
            if echo "$target_networks_json" | grep -q '"TargetNetworkId"'; then
                echo "$target_networks_json" | grep -o '"TargetNetworkId":"[^"]*"' | sed 's/"TargetNetworkId":"\([^"]*\)"/  - 子網路 ID: \1/'
            else
                echo "  未關聯任何子網路"
            fi
        fi
    else
        echo "  無法獲取關聯網絡資訊或端點不存在"
    fi
    
    return 0
}

# 查看路由表 (庫函式版本)
# 參數: $1 = AWS_REGION, $2 = ENDPOINT_ID
view_route_table_lib() {
    local aws_region="$1"
    local endpoint_id="$2"
    
    if [ -z "$aws_region" ] || [ -z "$endpoint_id" ]; then
        echo -e "${RED}錯誤: AWS 區域和端點 ID 不能為空${NC}"
        return 1
    fi
    
    # 參數驗證
    if ! validate_aws_region "$aws_region"; then
        return 1
    fi
    
    if ! validate_endpoint_id "$endpoint_id"; then
        return 1
    fi
    
    log_message_core "開始查看路由表 (lib) - Endpoint: $endpoint_id, Region: $aws_region"
    
    echo -e "${BLUE}查看端點路由表...${NC}"
    echo -e "${BLUE}端點 ID: $endpoint_id${NC}"
    echo -e "${BLUE}AWS 區域: $aws_region${NC}"
    
    # 獲取路由表資訊
    local routes_json
    routes_json=$(aws ec2 describe-client-vpn-routes --client-vpn-endpoint-id "$endpoint_id" --region "$aws_region" 2>/dev/null)
    
    if [ $? -ne 0 ]; then
        echo -e "${RED}錯誤: 無法獲取路由表資訊。請檢查端點 ID 和 AWS 憑證。${NC}"
        log_message_core "錯誤: AWS CLI 調用失敗 - describe-client-vpn-routes"
        return 1
    fi
    
    if [ -z "$routes_json" ]; then
        echo -e "${YELLOW}目前沒有路由規則。${NC}"
        log_message_core "查看路由表完成 - 無路由規則存在"
        return 0
    fi
    
    # 解析並顯示路由資訊
    if command -v jq >/dev/null 2>&1; then
        # 使用 jq 解析
        local routes_count
        routes_count=$(echo "$routes_json" | jq '.Routes | length' 2>/dev/null || echo "0")
        
        if [ "$routes_count" -gt 0 ]; then
            echo -e "\n${GREEN}找到 $routes_count 個路由規則:${NC}"
            echo "$routes_json" | jq -r '.Routes[] | "目的地 CIDR: \(.DestinationCidr), 目標子網路: \(.TargetSubnet // "N/A"), 狀態: \(.Status.Code), 描述: \(.Description // "無描述")"'
        else
            echo -e "${YELLOW}目前沒有路由規則。${NC}"
        fi
    else
        # 無 jq 時的備用解析方法
        if echo "$routes_json" | grep -q '"DestinationCidr"'; then
            echo -e "\n${GREEN}路由規則:${NC}"
            echo "$routes_json" | grep -o '"DestinationCidr":"[^"]*"' | sed 's/"DestinationCidr":"//g' | sed 's/"//g' | while read -r cidr; do
                echo "  - 目的地 CIDR: $cidr"
            done
        else
            echo -e "${YELLOW}目前沒有路由規則。${NC}"
        fi
    fi
    
    log_message_core "查看路由表完成"
    return 0
}

# 添加路由 (庫函式版本)
# 參數: $1 = AWS_REGION, $2 = ENDPOINT_ID
add_route_lib() {
    local aws_region="$1"
    local endpoint_id="$2"
    
    if [ -z "$aws_region" ] || [ -z "$endpoint_id" ]; then
        echo -e "${RED}錯誤: AWS 區域和端點 ID 不能為空${NC}"
        return 1
    fi
    
    # 參數驗證
    if ! validate_aws_region "$aws_region"; then
        return 1
    fi
    
    if ! validate_endpoint_id "$endpoint_id"; then
        return 1
    fi
    
    log_message_core "開始添加路由 (lib) - Endpoint: $endpoint_id, Region: $aws_region"
    
    echo -e "${BLUE}添加新路由到端點...${NC}"
    echo -e "${BLUE}端點 ID: $endpoint_id${NC}"
    echo -e "${BLUE}AWS 區域: $aws_region${NC}"
    
    # 獲取端點關聯的子網路資訊
    local target_networks_json
    target_networks_json=$(aws ec2 describe-client-vpn-target-networks --client-vpn-endpoint-id "$endpoint_id" --region "$aws_region" 2>/dev/null)
    
    if [ $? -ne 0 ] || [ -z "$target_networks_json" ]; then
        echo -e "${RED}錯誤: 無法獲取端點關聯的網絡資訊。${NC}"
        log_message_core "錯誤: 無法獲取端點關聯的網絡資訊"
        return 1
    fi
    
    # 顯示可用的子網路
    echo -e "\n${YELLOW}可用的目標子網路:${NC}"
    if command -v jq >/dev/null 2>&1; then
        echo "$target_networks_json" | jq -r '.ClientVpnTargetNetworks[] | "  - 子網路 ID: \(.TargetNetworkId), VPC ID: \(.VpcId)"'
    else
        echo "$target_networks_json" | grep -o '"TargetNetworkId":"[^"]*"' | sed 's/"TargetNetworkId":"//g' | sed 's/"//g' | while read -r subnet; do
            echo "  - 子網路 ID: $subnet"
        done
    fi
    
    # 詢問路由詳細資訊
    echo -e "\n${YELLOW}請輸入路由資訊:${NC}"
    
    local destination_cidr
    while true; do
        read -p "目的地 CIDR (例如: 10.0.0.0/16, 0.0.0.0/0): " destination_cidr
        if [[ "$destination_cidr" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}/[0-9]{1,2}$ ]]; then
            break
        else
            echo -e "${RED}錯誤: 請輸入有效的 CIDR 格式 (例如: 10.0.0.0/16)${NC}"
        fi
    done
    
    local target_subnet_id
    read -p "目標子網路 ID: " target_subnet_id
    
    if [ -z "$target_subnet_id" ]; then
        echo -e "${RED}錯誤: 目標子網路 ID 不能為空${NC}"
        return 1
    fi
    
    # 可選的描述
    local description
    read -p "路由描述 (可選): " description
    
    # 檢查路由是否已存在
    local existing_routes
    existing_routes=$(aws ec2 describe-client-vpn-routes \
        --client-vpn-endpoint-id "$endpoint_id" \
        --region "$aws_region" \
        --query "Routes[?DestinationCidr=='$destination_cidr'].DestinationCidr" \
        --output text 2>/dev/null || echo "")
    
    if [ -n "$existing_routes" ] && [ "$existing_routes" != "None" ]; then
        echo -e "${YELLOW}警告: 路由 ($destination_cidr) 已存在${NC}"
        read -p "是否要繼續? (y/N): " confirm_add
        if [[ ! "$confirm_add" =~ ^[Yy]$ ]]; then
            echo -e "${YELLOW}操作已取消${NC}"
            return 0
        fi
    fi
    
    # 創建路由
    echo -e "\n${BLUE}創建路由...${NC}"
    local route_cmd="aws ec2 create-client-vpn-route --client-vpn-endpoint-id $endpoint_id --destination-cidr-block $destination_cidr --target-vpc-subnet-id $target_subnet_id --region $aws_region"
    
    if [ -n "$description" ]; then
        route_cmd="$route_cmd --description \"$description\""
    fi
    
    log_message_core "執行路由創建命令: $route_cmd"
    
    local route_result
    if [ -n "$description" ]; then
        route_result=$(aws ec2 create-client-vpn-route \
            --client-vpn-endpoint-id "$endpoint_id" \
            --destination-cidr-block "$destination_cidr" \
            --target-vpc-subnet-id "$target_subnet_id" \
            --description "$description" \
            --region "$aws_region" 2>&1)
    else
        route_result=$(aws ec2 create-client-vpn-route \
            --client-vpn-endpoint-id "$endpoint_id" \
            --destination-cidr-block "$destination_cidr" \
            --target-vpc-subnet-id "$target_subnet_id" \
            --region "$aws_region" 2>&1)
    fi
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓ 路由創建成功${NC}"
        echo -e "  目的地 CIDR: $destination_cidr"
        echo -e "  目標子網路: $target_subnet_id"
        if [ -n "$description" ]; then
            echo -e "  描述: $description"
        fi
        log_message_core "路由創建成功: $destination_cidr -> $target_subnet_id"
    else
        echo -e "${RED}✗ 路由創建失敗:${NC}"
        echo "$route_result"
        log_message_core "錯誤: 路由創建失敗 - $route_result"
        return 1
    fi
    
    log_message_core "添加路由完成"
    return 0
}

# 查看現有 VPN 端點 (庫函式版本)
# 參數: $1 = AWS_REGION, $2 = CONFIG_FILE
list_vpn_endpoints_lib() {
    local aws_region="$1"
    local config_file="$2"
    
    # 參數驗證
    if ! validate_aws_region "$aws_region"; then
        # validate_aws_region 應已處理錯誤記錄和輸出
        return 1
    fi
    
    if [ -z "$config_file" ] || [ ! -f "$config_file" ]; then
        echo -e "${RED}錯誤: 配置文件不存在或路徑為空${NC}"
        log_message_core "錯誤: list_vpn_endpoints_lib 調用時配置文件不存在: $config_file"
        return 1
    fi
    
    log_message_core "開始查看現有 VPN 端點 (lib)"
    
    local endpoints_json
    endpoints_json=$(aws ec2 describe-client-vpn-endpoints --region "$aws_region" 2>/dev/null)
    
    if [ $? -ne 0 ]; then
        echo -e "${RED}錯誤: 無法獲取 VPN 端點列表。請檢查 AWS 憑證和網絡連接。${NC}"
        log_message_core "錯誤: AWS CLI 調用失敗 - describe-client-vpn-endpoints"
        return 1
    fi
    
    if [ -z "$endpoints_json" ] || [ "$(echo "$endpoints_json" | jq '.ClientVpnEndpoints | length' 2>/dev/null || echo "$endpoints_json" | grep -c '"ClientVpnEndpointId"')" -eq 0 ]; then
        echo -e "${YELLOW}目前沒有 VPN 端點。${NC}"
        log_message_core "查看端點列表完成 - 無端點存在"
        return 0
    fi
    
    echo "$endpoints_json" | jq -c '.ClientVpnEndpoints[]' | while read -r endpoint; do
        local endpoint_id endpoint_name endpoint_status endpoint_cidr endpoint_dns endpoint_creation_time
        if ! endpoint_id=$(echo "$endpoint" | jq -r '.ClientVpnEndpointId' 2>/dev/null); then
            # 備用解析方法
            endpoint_id=$(echo "$endpoint" | grep -o '"ClientVpnEndpointId":"[^"]*"' | sed 's/"ClientVpnEndpointId":"//g' | sed 's/"//g')
        fi
        
        if ! endpoint_name=$(echo "$endpoint" | jq -r '.Tags[]? | select(.Key=="Name") | .Value // "無名稱"' 2>/dev/null); then
            # 備用解析方法
            endpoint_name=$(echo "$endpoint" | grep -A 10 '"Tags"' | grep -o '"Value":"[^"]*"' | sed 's/"Value":"//g' | sed 's/"//g' | head -1)
            endpoint_name="${endpoint_name:-無名稱}"
        fi
        endpoint_status=$(echo "$endpoint" | jq -r '.Status.Code')
        endpoint_cidr=$(echo "$endpoint" | jq -r '.ClientCidrBlock')
        endpoint_dns=$(echo "$endpoint" | jq -r '.DnsName')
        endpoint_creation_time=$(echo "$endpoint" | jq -r '.CreationTime')
        
        echo -e "端點 ID: ${BLUE}$endpoint_id${NC}"
        echo -e "  名稱: $endpoint_name"
        echo -e "  狀態: $endpoint_status"
        echo -e "  VPN CIDR: $endpoint_cidr"
        echo -e "  DNS 名稱: $endpoint_dns"
        echo -e "  創建時間: $endpoint_creation_time"
        
        # 獲取並顯示關聯的網絡 (VPCs/Subnets)
        local target_networks_json associated_subnets_count
        target_networks_json=$(aws ec2 describe-client-vpn-target-networks --client-vpn-endpoint-id "$endpoint_id" --region "$aws_region" 2>/dev/null)
        
        if [ $? -eq 0 ] && [ -n "$target_networks_json" ]; then
            if ! associated_subnets_count=$(echo "$target_networks_json" | jq '.ClientVpnTargetNetworks | length' 2>/dev/null); then
                # 備用解析方法：使用 grep 統計子網數
                associated_subnets_count=$(echo "$target_networks_json" | grep -c '"TargetNetworkId"' || echo "0")
            fi
            
            if [ "$associated_subnets_count" -gt 0 ]; then
                echo -e "  ${YELLOW}關聯的子網路 ($associated_subnets_count):${NC}"
                echo "$target_networks_json" | jq -r '.ClientVpnTargetNetworks[] | "    - 子網路 ID: \(.TargetNetworkId), VPC ID: \(.VpcId), 狀態: \(.Status.Code)"'
            else
                echo -e "  ${YELLOW}未關聯任何子網路${NC}"
            fi
        else
            echo -e "  ${YELLOW}無法獲取關聯網絡資訊${NC}"
        fi
        echo -e "${CYAN}----------------------------------------${NC}"
    done
    
    log_message_core "查看端點列表完成"
    return 0
}

# 生成管理員配置檔案 (庫函式版本)
# 參數: $1 = SCRIPT_DIR, $2 = CONFIG_FILE
generate_admin_config_lib() {
    local script_dir="$1"
    local config_file="$2"
    
    # 參數驗證
    if [ -z "$script_dir" ] || [ ! -d "$script_dir" ]; then
        echo -e "${RED}錯誤: 腳本目錄參數無效${NC}"
        log_message_core "錯誤: generate_admin_config_lib 調用時腳本目錄參數無效: $script_dir"
        return 1
    fi
    
    if [ -z "$config_file" ] || [ ! -f "$config_file" ]; then
        echo -e "${RED}錯誤: 配置文件不存在${NC}"
        log_message_core "錯誤: generate_admin_config_lib 調用時配置文件不存在: $config_file"
        return 1
    fi
    
    log_message_core "開始生成管理員配置檔案 (lib)"
    
    # 載入配置
    source "$config_file"
    
    # 調試輸出
    echo -e "${BLUE}調試: 配置文件已載入${NC}"
    echo -e "${BLUE}調試: ENDPOINT_ID = '$ENDPOINT_ID'${NC}"
    echo -e "${BLUE}調試: AWS_REGION = '$AWS_REGION'${NC}"
    
    # 檢查必要變數
    if [ -z "$ENDPOINT_ID" ]; then
        echo -e "${RED}錯誤: ENDPOINT_ID 變數為空${NC}"
        log_message_core "錯誤: generate_admin_config_lib - ENDPOINT_ID 變數為空"
        return 1
    fi
    
    if [ -z "$AWS_REGION" ]; then
        echo -e "${RED}錯誤: AWS_REGION 變數為空${NC}"
        log_message_core "錯誤: generate_admin_config_lib - AWS_REGION 變數為空"
        return 1
    fi
    
    if ! validate_endpoint_id "$ENDPOINT_ID"; then
        log_message_core "錯誤: generate_admin_config_lib - 來自配置文件的 ENDPOINT_ID 無效: '$ENDPOINT_ID'"
        # validate_endpoint_id 應已處理特定錯誤的記錄和輸出
        return 1
    fi
    if ! validate_aws_region "$AWS_REGION"; then
        log_message_core "錯誤: generate_admin_config_lib - 來自配置文件的 AWS_REGION 無效: '$AWS_REGION'"
        # validate_aws_region 應已處理特定錯誤的記錄和輸出
        return 1
    fi
    
    echo -e "${BLUE}生成管理員配置檔案...${NC}"
    
    # 創建配置目錄
    mkdir -p "$script_dir/configs"
    if [ $? -ne 0 ]; then
        echo -e "${RED}錯誤: 無法創建配置目錄${NC}"
        log_message_core "錯誤: 無法創建配置目錄: $script_dir/configs"
        return 1
    fi
    
    # 下載基本配置
    echo -e "${BLUE}下載 VPN 客戶端配置... (Endpoint: $ENDPOINT_ID, Region: $AWS_REGION)${NC}"
    log_message_core "嘗試下載 VPN 客戶端配置 - Endpoint: $ENDPOINT_ID, Region: $AWS_REGION"
    
    if ! aws ec2 export-client-vpn-client-configuration \
      --client-vpn-endpoint-id "$ENDPOINT_ID" \
      --region "$AWS_REGION" \
      --output text > "$script_dir/configs/admin-config-base.ovpn" 2>/dev/null; then
        echo -e "${RED}錯誤: 無法下載 VPN 客戶端配置${NC}"
        echo -e "${RED}檢查 ENDPOINT_ID ($ENDPOINT_ID) 和 AWS_REGION ($AWS_REGION) 是否正確${NC}"
        log_message_core "錯誤: AWS CLI 調用失敗 - export-client-vpn-client-configuration, Endpoint: $ENDPOINT_ID, Region: $AWS_REGION"
        return 1
    fi
    
    # 修改配置文件
    cp "$script_dir/configs/admin-config-base.ovpn" "$script_dir/configs/admin-config.ovpn"
    echo "reneg-sec 0" >> "$script_dir/configs/admin-config.ovpn"
    
    # 添加 AWS 域名分割 DNS 配置
    {
        echo ""
        echo "# AWS 域名分割 DNS 配置"
        echo "# 確保 AWS 內部服務域名通過 VPC DNS 解析"
        echo "dhcp-option DNS-priority 1"
        echo "dhcp-option DOMAIN internal"
        echo "dhcp-option DOMAIN $AWS_REGION.compute.internal"
        echo "dhcp-option DOMAIN ec2.internal"
        echo "dhcp-option DOMAIN $AWS_REGION.elb.amazonaws.com"
        echo "dhcp-option DOMAIN $AWS_REGION.rds.amazonaws.com"
        echo "dhcp-option DOMAIN $AWS_REGION.s3.amazonaws.com"
        echo "dhcp-option DOMAIN *.amazonaws.com"
        echo ""
        echo "# 路由配置：將 AWS 服務流量導向 VPN"
        echo "# EC2 metadata service"
        echo "route 169.254.169.254 255.255.255.255"
        echo "# VPC DNS resolver"
        echo "route 169.254.169.253 255.255.255.255"
    } >> "$script_dir/configs/admin-config.ovpn"
    
    # 生成管理員證書
    if ! generate_admin_certificate_lib "$script_dir"; then
        echo -e "${RED}錯誤: 生成管理員證書失敗${NC}"
        log_message_core "錯誤: generate_admin_certificate_lib 調用失敗"
        return 1
    fi
    
    local cert_dir="$VPN_CERT_DIR" # 使用環境感知路徑
    
    # 檢查證書文件是否存在
    if [ ! -f "$cert_dir/pki/issued/admin.crt" ] || [ ! -f "$cert_dir/pki/private/admin.key" ]; then
        echo -e "${RED}錯誤: 管理員證書文件不存在${NC}"
        log_message_core "錯誤: 管理員證書文件不存在"
        return 1
    fi
    
    # 添加證書到配置文件
    echo "<cert>" >> "$script_dir/configs/admin-config.ovpn"
    cat "$cert_dir/pki/issued/admin.crt" >> "$script_dir/configs/admin-config.ovpn"
    echo "</cert>" >> "$script_dir/configs/admin-config.ovpn"
    
    echo "<key>" >> "$script_dir/configs/admin-config.ovpn"
    cat "$cert_dir/pki/private/admin.key" >> "$script_dir/configs/admin-config.ovpn"
    echo "</key>" >> "$script_dir/configs/admin-config.ovpn"
    
    echo -e "${GREEN}管理員配置檔案已生成: $script_dir/configs/admin-config.ovpn${NC}"
    log_message_core "管理員配置檔案生成成功: $script_dir/configs/admin-config.ovpn"
    return 0
}

# 匯出團隊成員設定檔 (庫函式版本)
# 參數: $1 = SCRIPT_DIR, $2 = CONFIG_FILE
export_team_config_lib() {
    local script_dir="$1"
    local config_file="$2"
    
    # 參數驗證
    if [ -z "$script_dir" ] || [ ! -d "$script_dir" ]; then
        echo -e "${RED}錯誤: 腳本目錄參數無效${NC}"
        log_message_core "錯誤: export_team_config_lib 調用時腳本目錄參數無效: $script_dir"
        return 1
    fi
    
    if [ -z "$config_file" ] || [ ! -f "$config_file" ]; then
        echo -e "${RED}錯誤: 配置文件不存在${NC}"
        log_message_core "錯誤: export_team_config_lib 調用時配置文件不存在: $config_file"
        return 1
    fi
    
    log_message_core "開始匯出團隊成員設定檔 (lib)"
    
    # 載入配置
    source "$config_file"
    
    # 檢查必要變數
    if ! validate_endpoint_id "$ENDPOINT_ID"; then
        log_message_core "錯誤: export_team_config_lib - 來自配置文件的 ENDPOINT_ID 無效: '$ENDPOINT_ID'"
        # validate_endpoint_id 應已處理特定錯誤的記錄和輸出
        return 1
    fi
    if ! validate_aws_region "$AWS_REGION"; then
        log_message_core "錯誤: export_team_config_lib - 來自配置文件的 AWS_REGION 無效: '$AWS_REGION'"
        # validate_aws_region 應已處理特定錯誤的記錄和輸出
        return 1
    fi
    
    echo -e "${BLUE}匯出團隊成員設定檔...${NC}"
    
    # 創建團隊配置目錄
    mkdir -p "$script_dir/team-configs"
    if [ $? -ne 0 ]; then
        echo -e "${RED}錯誤: 無法創建團隊配置目錄${NC}"
        log_message_core "錯誤: 無法創建團隊配置目錄: $script_dir/team-configs"
        return 1
    fi
    
    # 下載基本配置
    if ! aws ec2 export-client-vpn-client-configuration \
      --client-vpn-endpoint-id "$ENDPOINT_ID" \
      --region "$AWS_REGION" \
      --output text > "$script_dir/team-configs/team-config-base.ovpn" 2>/dev/null; then
        echo -e "${RED}錯誤: 無法下載 VPN 客戶端配置${NC}"
        log_message_core "錯誤: AWS CLI 調用失敗 - export-client-vpn-client-configuration"
        return 1
    fi
    
    # 添加 AWS 域名分割 DNS 配置到團隊基礎配置
    echo -e "${BLUE}配置 AWS 域名分割 DNS 到團隊基礎配置...${NC}"
    {
        echo ""
        echo "# AWS 域名分割 DNS 配置"
        echo "# 確保 AWS 內部服務域名通過 VPC DNS 解析"
        echo "dhcp-option DNS-priority 1"
        echo "dhcp-option DOMAIN internal"
        echo "dhcp-option DOMAIN $AWS_REGION.compute.internal"
        echo "dhcp-option DOMAIN ec2.internal"
        echo "dhcp-option DOMAIN $AWS_REGION.elb.amazonaws.com"
        echo "dhcp-option DOMAIN $AWS_REGION.rds.amazonaws.com"
        echo "dhcp-option DOMAIN $AWS_REGION.s3.amazonaws.com"
        echo "dhcp-option DOMAIN *.amazonaws.com"
        echo ""
        echo "# 路由配置：將 AWS 服務流量導向 VPN"
        echo "# EC2 metadata service"
        echo "route 169.254.169.254 255.255.255.255"
        echo "# VPC DNS resolver"
        echo "route 169.254.169.253 255.255.255.255"
    } >> "$script_dir/team-configs/team-config-base.ovpn"
    
    # 檢查證書文件是否存在 - 使用環境感知路徑
    if [ ! -f "$VPN_CERT_DIR/pki/ca.crt" ] || [ ! -f "$VPN_CERT_DIR/pki/private/ca.key" ]; then
        echo -e "${RED}錯誤: CA 證書文件不存在，請先生成證書${NC}"
        log_message_core "錯誤: CA 證書文件不存在"
        return 1
    fi
    
    # 複製 CA 證書到 team-configs 目錄 - 使用環境感知路徑
    cp "$VPN_CERT_DIR/pki/ca.crt" "$script_dir/team-configs/"
    cp "$VPN_CERT_DIR/pki/private/ca.key" "$script_dir/team-configs/"
    
    # 創建團隊成員資訊文件
    cat > "$script_dir/team-configs/team-setup-info.txt" << EOF
=== AWS Client VPN 團隊設定資訊 ===

VPN 端點 ID: $ENDPOINT_ID
AWS 區域: $AWS_REGION
VPN CIDR: $VPN_CIDR

主要 VPC 資訊:
  VPC ID: $VPC_ID
  VPC CIDR: $VPC_CIDR
  關聯子網路: $SUBNET_ID
EOF

    # 添加額外的 VPC 資訊
    if grep -q "MULTI_VPC_COUNT=" "$config_file"; then
        local multi_vpc_count
        multi_vpc_count=$(grep "MULTI_VPC_COUNT=" "$config_file" | cut -d'=' -f2)
        if [ "$multi_vpc_count" -gt 0 ]; then
            echo "" >> "$script_dir/team-configs/team-setup-info.txt"
            echo "額外關聯的 VPCs:" >> "$script_dir/team-configs/team-setup-info.txt"
            for ((i=1; i<=multi_vpc_count; i++)); do
                local vpc_info_var_name="MULTI_VPC_$i"
                local vpc_info_line
                # Ensure the variable name is correctly formed and used with eval or indirect expansion
                # However, direct sourcing of config should make these available.
                # Let's assume the config file is sourced correctly and variables are directly accessible.
                # This part might need adjustment based on how MULTI_VPC_X variables are actually stored/retrieved.
                # For now, using a robust way to get the value if it's set.
                vpc_info_line=$(grep "$vpc_info_var_name=" "$config_file" | cut -d'"' -f2)

                if [ ! -z "$vpc_info_line" ]; then
                    local extra_vpc_id extra_vpc_cidr extra_subnet_id
                    extra_vpc_id=$(echo "$vpc_info_line" | cut -d':' -f1)
                    extra_vpc_cidr=$(echo "$vpc_info_line" | cut -d':' -f2)
                    extra_subnet_id=$(echo "$vpc_info_line" | cut -d':' -f3)
                    
                    echo "  VPC $i:" >> "$script_dir/team-configs/team-setup-info.txt"
                    echo "    VPC ID: $extra_vpc_id" >> "$script_dir/team-configs/team-setup-info.txt"
                    echo "    VPC CIDR: $extra_vpc_cidr" >> "$script_dir/team-configs/team-setup-info.txt"
                    echo "    關聯子網路: $extra_subnet_id" >> "$script_dir/team-configs/team-setup-info.txt"
                fi
            done
        fi
    fi

    cat >> "$script_dir/team-configs/team-setup-info.txt" << EOF

設定檔案：
- team-config-base.ovpn: 基本 VPN 配置檔案
- ca.crt: CA 證書文件
- ca.key: CA 私鑰文件 (請安全保管)

使用說明：
1. 向新團隊成員提供 team_member_setup.sh 腳本
2. 提供上述端點 ID 和 ca.crt 文件
3. 不要分享 ca.key 文件，只給負責生成證書的管理員

生成時間: $(date)
EOF
    
    echo -e "${GREEN}團隊設定檔已匯出到 $script_dir/team-configs/${NC}"
    echo -e "${BLUE}請將以下檔案提供給團隊成員：${NC}"
    echo -e "  - team_member_setup.sh (團隊成員設定腳本)"
    echo -e "  - ca.crt (CA 證書)"
    echo -e "  - 端點 ID: $ENDPOINT_ID"
    
    log_message_core "團隊設定檔匯出成功: $script_dir/team-configs/"
    return 0
}

# 關聯單一 VPC 到現有端點 (庫函式版本)
# 參數: $1 = CONFIG_FILE, $2 = AWS_REGION, $3 = ENDPOINT_ID
associate_single_vpc_lib() {
    local config_file="$1"
    local aws_region="$2"
    local endpoint_id="$3"
    
    # 參數驗證
    if [ -z "$config_file" ] || [ ! -f "$config_file" ]; then
        echo -e "${RED}錯誤: 配置文件不存在或路徑為空${NC}"
        log_message_core "錯誤: associate_single_vpc_lib 調用時配置文件不存在: $config_file"
        return 1
    fi
    
    if ! validate_aws_region "$aws_region"; then
        return 1
    fi
    
    if ! validate_endpoint_id "$endpoint_id"; then
        return 1
    fi
    
    log_message_core "開始關聯單一 VPC 到端點 (lib) - Endpoint: $endpoint_id, Region: $aws_region"
    
    # 確保已載入 endpoint_creation.sh 函數庫
    local script_dir_lib="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    if ! command -v _associate_one_vpc_to_endpoint_lib >/dev/null 2>&1; then
        if [ -f "$script_dir_lib/endpoint_creation.sh" ]; then
            source "$script_dir_lib/endpoint_creation.sh"
        else
            echo -e "${RED}錯誤: 無法找到 endpoint_creation.sh 函數庫${NC}"
            log_message_core "錯誤: associate_single_vpc_lib 無法載入 endpoint_creation.sh"
            return 1
        fi
    fi
    
    # 調用內部函數進行 VPC 關聯
    if ! _associate_one_vpc_to_endpoint_lib "$config_file" "$aws_region" "$endpoint_id"; then
        echo -e "${RED}錯誤: VPC 關聯失敗${NC}"
        log_message_core "錯誤: associate_single_vpc_lib - _associate_one_vpc_to_endpoint_lib 調用失敗"
        return 1
    fi
    
    echo -e "${GREEN}✓ VPC 關聯成功完成${NC}"
    log_message_core "VPC 關聯成功完成"
    return 0
}

# 關聯額外的 VPC 到現有端點 (庫函式版本)
# 參數: $1 = CONFIG_FILE, $2 = AWS_REGION, $3 = ENDPOINT_ID
associate_additional_vpc_lib() {
    local config_file="$1"
    local aws_region="$2"
    local endpoint_id="$3"
    
    # 參數驗證
    if [ -z "$config_file" ] || [ ! -f "$config_file" ]; then
        echo -e "${RED}錯誤: 配置文件不存在或路徑為空${NC}"
        log_message_core "錯誤: associate_additional_vpc_lib 調用時配置文件不存在: $config_file"
        return 1
    fi
    
    if ! validate_aws_region "$aws_region"; then
        return 1
    fi
    
    if ! validate_endpoint_id "$endpoint_id"; then
        return 1
    fi
    
    log_message_core "開始關聯額外 VPC 到端點 (lib) - Endpoint: $endpoint_id, Region: $aws_region"
    
    echo -e "\\n${CYAN}=== 關聯額外 VPC 到 VPN 端點 ===${NC}"
    echo -e "${BLUE}端點 ID: $endpoint_id${NC}"
    echo -e "${BLUE}AWS 區域: $aws_region${NC}"
    
    # 顯示當前已關聯的網絡
    echo -e "\\n${YELLOW}當前已關聯的網絡:${NC}"
    view_associated_networks_lib "$aws_region" "$endpoint_id"
    
    # 詢問用戶是否要添加額外的 VPC
    echo -e "\\n${YELLOW}是否要關聯額外的 VPC? (y/n)${NC}"
    read -r add_more_vpcs
    
    local additional_vpc_count=0
    
    while [[ "$add_more_vpcs" =~ ^[Yy]$ ]]; do
        echo -e "\\n${BLUE}關聯第 $((additional_vpc_count + 1)) 個額外 VPC...${NC}"
        
        # 確保已載入 endpoint_creation.sh 函數庫
        local script_dir_lib="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
        if ! command -v _associate_one_vpc_to_endpoint_lib >/dev/null 2>&1; then
            if [ -f "$script_dir_lib/endpoint_creation.sh" ]; then
                source "$script_dir_lib/endpoint_creation.sh"
            else
                echo -e "${RED}錯誤: 無法找到 endpoint_creation.sh 函數庫${NC}"
                log_message_core "錯誤: associate_additional_vpc_lib 無法載入 endpoint_creation.sh"
                return 1
            fi
        fi
        
        # 調用內部函數進行單個 VPC 關聯
        if _associate_one_vpc_to_endpoint_lib "$config_file" "$aws_region" "$endpoint_id"; then
            additional_vpc_count=$((additional_vpc_count + 1))
            echo -e "${GREEN}✓ 第 $additional_vpc_count 個 VPC 關聯成功${NC}"
            
            # 更新配置文件中的額外 VPC 計數
            update_config "$config_file" "MULTI_VPC_COUNT" "$additional_vpc_count"
            
        else
            echo -e "${RED}✗ VPC 關聯失敗${NC}"
            log_message_core "錯誤: associate_additional_vpc_lib - 第 $((additional_vpc_count + 1)) 個 VPC 關聯失敗"
        fi
        
        # 詢問是否繼續添加更多 VPC
        echo -e "\\n${YELLOW}是否要關聯更多 VPC? (y/n)${NC}"
        read -r add_more_vpcs
    done
    
    if [ $additional_vpc_count -gt 0 ]; then
        echo -e "\\n${GREEN}✓ 總共成功關聯了 $additional_vpc_count 個額外 VPC${NC}"
        log_message_core "額外 VPC 關聯完成，總計: $additional_vpc_count"
    else
        echo -e "\\n${YELLOW}未關聯任何額外 VPC${NC}"
        log_message_core "用戶選擇不關聯額外 VPC"
    fi
    
    return 0
}

# 顯示多 VPC 拓撲 (庫函式版本)
# 參數: $1 = CONFIG_FILE, $2 = AWS_REGION, $3 = ENDPOINT_ID, $4 = VPN_CIDR (主), $5 = VPC_ID (主), $6 = VPC_CIDR (主), $7 = SUBNET_ID (主)
show_multi_vpc_topology_lib() {
    local config_file="$1"
    local aws_region="$2"
    local endpoint_id="$3"
    local main_vpn_cidr="$4" # 主 VPN CIDR (來自配置)
    local main_vpc_id="$5"   # 主 VPC ID (來自配置)
    local main_vpc_cidr="$6" # 主 VPC CIDR (來自配置)
    local main_subnet_id="$7" # 主 Subnet ID (來自配置)

    log_message_core "開始顯示多 VPC 拓撲 (lib) - Endpoint: $endpoint_id, Region: $aws_region"

    # 參數驗證
    if [ -z "$config_file" ] || [ ! -f "$config_file" ]; then
        echo -e "${RED}錯誤: 配置文件不存在或路徑為空: $config_file${NC}"
        log_message_core "錯誤: show_multi_vpc_topology_lib - 配置文件不存在: $config_file"
        return 1
    fi
    if ! validate_aws_region "$aws_region"; then return 1; fi
    if ! validate_endpoint_id "$endpoint_id"; then return 1; fi
    if ! validate_cidr_block "$main_vpn_cidr"; then echo -e "${RED}錯誤: 主 VPN CIDR 無效: $main_vpn_cidr${NC}"; return 1; fi
    if ! validate_vpc_id "$main_vpc_id"; then echo -e "${RED}錯誤: 主 VPC ID 無效: $main_vpc_id${NC}"; return 1; fi
    if ! validate_cidr_block "$main_vpc_cidr"; then echo -e "${RED}錯誤: 主 VPC CIDR 無效: $main_vpc_cidr${NC}"; return 1; fi
    if ! validate_subnet_id "$main_subnet_id"; then echo -e "${RED}錯誤: 主 Subnet ID 無效: $main_subnet_id${NC}"; return 1; fi

    echo -e "\\n${CYAN}=== VPN 端點 ($endpoint_id) 網路拓撲 ===${NC}"
    echo -e "${BLUE}AWS 區域: $aws_region${NC}"
    echo -e "${BLUE}VPN 用戶端 CIDR: $main_vpn_cidr${NC}"

    # 顯示主 VPC 資訊
    echo -e "\\n${YELLOW}--- 主 VPC (來自配置) ---${NC}"
    local main_vpc_name
    main_vpc_name=$(aws ec2 describe-vpcs --vpc-ids "$main_vpc_id" --region "$aws_region" --query "Vpcs[0].Tags[?Key=='Name'].Value" --output text 2>/dev/null || echo "N/A")
    echo -e "  VPC ID: ${GREEN}$main_vpc_id${NC} (名稱: ${main_vpc_name:-未命名})"
    echo -e "  VPC CIDR: $main_vpc_cidr"
    echo -e "  關聯子網路 (主): ${GREEN}$main_subnet_id${NC}"
    local main_subnet_cidr main_subnet_az
    main_subnet_cidr=$(aws ec2 describe-subnets --subnet-ids "$main_subnet_id" --region "$aws_region" --query "Subnets[0].CidrBlock" --output text 2>/dev/null || echo "N/A")
    main_subnet_az=$(aws ec2 describe-subnets --subnet-ids "$main_subnet_id" --region "$aws_region" --query "Subnets[0].AvailabilityZone" --output text 2>/dev/null || echo "N/A")
    echo -e "    子網路 CIDR: $main_subnet_cidr"
    echo -e "    可用區域: $main_subnet_az"

    # 獲取並顯示所有與此端點關聯的目標網絡
    echo -e "\\n${YELLOW}--- 所有已關聯的目標網路 (來自 AWS API) ---${NC}"
    local target_networks_json
    target_networks_json=$(aws ec2 describe-client-vpn-target-networks --client-vpn-endpoint-id "$endpoint_id" --region "$aws_region" 2>/dev/null)

    if [ $? -ne 0 ] || [ -z "$target_networks_json" ]; then
        echo -e "${RED}無法獲取端點關聯的目標網路資訊。${NC}"
        log_message_core "錯誤: show_multi_vpc_topology_lib - 無法獲取 describe-client-vpn-target-networks"
        # 即使無法獲取 API 的關聯網路，也繼續執行，因為主 VPC 資訊已顯示
    else
        local associated_networks_count
        associated_networks_count=$(echo "$target_networks_json" | jq '.ClientVpnTargetNetworks | length' 2>/dev/null || echo "$target_networks_json" | grep -c '"TargetNetworkId"')

        if [ "$associated_networks_count" -eq 0 ]; then
            echo -e "${YELLOW}此 VPN 端點目前未直接關聯任何目標網路 (除了可能的主 VPC 配置)。${NC}"
        else
            echo -e "${BLUE}找到 $associated_networks_count 個已關聯的目標網路:${NC}"
            echo -e "  ----------------------------------------"
            
            # 使用簡化的 jq 處理，逐個字段提取
            echo "$target_networks_json" | jq -c '.ClientVpnTargetNetworks[]' | while read -r network; do
                local association_id vpc_id target_network_id status_code status_message security_groups
                
                association_id=$(echo "$network" | jq -r '.AssociationId // "N/A"')
                vpc_id=$(echo "$network" | jq -r '.VpcId // "N/A"')
                target_network_id=$(echo "$network" | jq -r '.TargetNetworkId // "N/A"')
                status_code=$(echo "$network" | jq -r '.Status.Code // "N/A"')
                status_message=$(echo "$network" | jq -r '.Status.Message // "N/A"')
                
                # 處理安全群組
                if echo "$network" | jq -e '.SecurityGroupIds' >/dev/null 2>&1; then
                    security_groups=$(echo "$network" | jq -r '.SecurityGroupIds | join(", ")')
                else
                    security_groups="N/A"
                fi
                
                echo -e "  關聯 ID: $association_id"
                echo -e "  VPC ID: $vpc_id"
                echo -e "  目標子網路 ID: $target_network_id"
                echo -e "  狀態: $status_code (訊息: $status_message)"
                echo -e "  安全群組: $security_groups"
                
                # 獲取 VPC 詳細資訊
                if validate_vpc_id "$vpc_id" && [ "$vpc_id" != "N/A" ]; then
                    local vpc_name_api vpc_cidr_api
                    vpc_name_api=$(aws ec2 describe-vpcs --vpc-ids "$vpc_id" --region "$aws_region" --query "Vpcs[0].Tags[?Key=='Name'].Value" --output text 2>/dev/null || echo "N/A")
                    vpc_cidr_api=$(aws ec2 describe-vpcs --vpc-ids "$vpc_id" --region "$aws_region" --query "Vpcs[0].CidrBlock" --output text 2>/dev/null || echo "N/A")
                    echo -e "    VPC 名稱 (API): ${vpc_name_api:-未命名}"
                    echo -e "    VPC CIDR (API): $vpc_cidr_api"
                fi
                
                # 獲取子網路詳細資訊
                if validate_subnet_id "$target_network_id" && [ "$target_network_id" != "N/A" ]; then
                    local subnet_cidr_api subnet_az_api
                    subnet_cidr_api=$(aws ec2 describe-subnets --subnet-ids "$target_network_id" --region "$aws_region" --query "Subnets[0].CidrBlock" --output text 2>/dev/null || echo "N/A")
                    subnet_az_api=$(aws ec2 describe-subnets --subnet-ids "$target_network_id" --region "$aws_region" --query "Subnets[0].AvailabilityZone" --output text 2>/dev/null || echo "N/A")
                    echo -e "    子網路 CIDR (API): $subnet_cidr_api"
                    echo -e "    可用區域 (API): $subnet_az_api"
                fi
                
                echo -e "  ----------------------------------------"
            done
        fi
    fi
    
    # 檢查配置文件中是否有 MULTI_VPC_COUNT 和相關的 MULTI_VPC_X 變數
    # 這部分可以顯示配置中定義的、但可能尚未通過 API 驗證的額外 VPC
    if grep -q "MULTI_VPC_COUNT=" "$config_file"; then
        local multi_vpc_count_config
        multi_vpc_count_config=$(grep "MULTI_VPC_COUNT=" "$config_file" | head -n 1 | cut -d'=' -f2 | tr -d '"')
        
        if [[ "$multi_vpc_count_config" =~ ^[0-9]+$ ]] && [ "$multi_vpc_count_config" -gt 0 ]; then
            echo -e "\\n${YELLOW}--- 配置文件中定義的額外 VPCs ---${NC}"
            for ((i=1; i<=multi_vpc_count_config; i++)); do
                local vpc_var_name="MULTI_VPC_${i}"
                local vpc_info_line
                # 從已 source 的環境中讀取變數值，而不是直接 grep 文件
                # 這需要 config_file 已經被 source，或者在此函數開始時 source
                # 假設 aws_vpn_admin.sh 在調用此 lib 函數前已 source 了 config_file
                # 或者，我們可以在此函數開始時 source config_file，但要注意變數覆蓋
                # 為了安全，我們還是 grep 文件，因為 lib 函數不應該假設外部狀態
                vpc_info_line=$(grep "^${vpc_var_name}=" "$config_file" | head -n 1 | cut -d'=' -f2 | tr -d '"')

                if [ -n "$vpc_info_line" ]; then
                    local extra_vpc_id extra_vpc_cidr extra_subnet_id
                    extra_vpc_id=$(echo "$vpc_info_line" | cut -d':' -f1)
                    extra_vpc_cidr=$(echo "$vpc_info_line" | cut -d':' -f2)
                    extra_subnet_id=$(echo "$vpc_info_line" | cut -d':' -f3)

                    echo -e "  ${BLUE}額外 VPC $i (來自配置):${NC}"
                    if validate_vpc_id "$extra_vpc_id"; then
                        local extra_vpc_name_cfg
                        extra_vpc_name_cfg=$(aws ec2 describe-vpcs --vpc-ids "$extra_vpc_id" --region "$aws_region" --query "Vpcs[0].Tags[?Key=='Name'].Value" --output text 2>/dev/null || echo "N/A")
                        echo -e "    VPC ID: ${GREEN}$extra_vpc_id${NC} (名稱: ${extra_vpc_name_cfg:-未命名})"
                    else
                        echo -e "    VPC ID: ${RED}$extra_vpc_id (格式無效)${NC}"
                    fi
                    echo -e "    VPC CIDR: $extra_vpc_cidr"
                    if validate_subnet_id "$extra_subnet_id"; then
                        local extra_subnet_cidr_cfg extra_subnet_az_cfg
                        extra_subnet_cidr_cfg=$(aws ec2 describe-subnets --subnet-ids "$extra_subnet_id" --region "$aws_region" --query "Subnets[0].CidrBlock" --output text 2>/dev/null || echo "N/A")
                        extra_subnet_az_cfg=$(aws ec2 describe-subnets --subnet-ids "$extra_subnet_id" --region "$aws_region" --query "Subnets[0].AvailabilityZone" --output text 2>/dev/null || echo "N/A")
                        echo -e "    關聯子網路: ${GREEN}$extra_subnet_id${NC}"
                        echo -e "      子網路 CIDR: $extra_subnet_cidr_cfg"
                        echo -e "      可用區域: $extra_subnet_az_cfg"
                    else
                         echo -e "    關聯子網路: ${RED}$extra_subnet_id (格式無效)${NC}"
                    fi
                else
                    echo -e "  ${YELLOW}警告: 配置文件中 MULTI_VPC_$i 的條目格式不正確或為空。${NC}"
                fi
            done
        fi
    fi

    log_message_core "顯示多 VPC 拓撲完成"
    return 0
}
