#!/bin/bash

# lib/endpoint_management.sh
# VPN 端點管理相關函式庫
# 包含端點列表、配置生成、團隊設定等功能

# 確保已載入核心函式
if [ -z "$LOG_FILE_CORE" ]; then
    echo "錯誤: 核心函式庫未載入。請先載入 core_functions.sh"
    exit 1
fi

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
                echo "$target_networks_json" | jq -r '.ClientVpnTargetNetworks[] | "    - 子網路 ID: \\(.TargetNetworkId), VPC ID: \\(.VpcId), 狀態: \\(.Status.Code)"'
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
    
    # 檢查必要變數
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
    if ! aws ec2 export-client-vpn-client-configuration \\
      --client-vpn-endpoint-id "$ENDPOINT_ID" \\
      --region "$AWS_REGION" \\
      --output text > "$script_dir/configs/admin-config-base.ovpn" 2>/dev/null; then
        echo -e "${RED}錯誤: 無法下載 VPN 客戶端配置${NC}"
        log_message_core "錯誤: AWS CLI 調用失敗 - export-client-vpn-client-configuration"
        return 1
    fi
    
    # 修改配置文件
    cp "$script_dir/configs/admin-config-base.ovpn" "$script_dir/configs/admin-config.ovpn"
    echo "reneg-sec 0" >> "$script_dir/configs/admin-config.ovpn"
    
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
    if ! aws ec2 export-client-vpn-client-configuration \\
      --client-vpn-endpoint-id "$ENDPOINT_ID" \\
      --region "$AWS_REGION" \\
      --output text > "$script_dir/team-configs/team-config-base.ovpn" 2>/dev/null; then
        echo -e "${RED}錯誤: 無法下載 VPN 客戶端配置${NC}"
        log_message_core "錯誤: AWS CLI 調用失敗 - export-client-vpn-client-configuration"
        return 1
    fi
    
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
