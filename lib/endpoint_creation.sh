#!/bin/bash

# 載入核心函式庫和依賴模組
# Check if core_functions.sh exists before sourcing
if [ -f "$(dirname "${BASH_SOURCE[0]}")/core_functions.sh" ]; then
    source "$(dirname "${BASH_SOURCE[0]}")/core_functions.sh"
elif [ -f "./lib/core_functions.sh" ]; then
    source "./lib/core_functions.sh"
fi
# cert_management.sh 已經在主腳本中載入，這裡不需要重複載入
# aws_setup.sh 同樣在主腳本中載入

# 獲取 VPC、子網路和 VPN 詳細資訊 (庫函式版本)
# 參數: $1 = AWS_REGION
# 返回: JSON 格式 {"vpc_id": "vpc-xxx", "subnet_id": "subnet-xxx", "vpn_cidr": "172.16.0.0/22", "vpn_name": "Production-VPN", "security_groups": "sg-xxx sg-yyy"}
get_vpc_subnet_vpn_details_lib() {
    local aws_region="$1"

    # 載入環境管理器以獲取環境變數
    local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    local project_root="$(dirname "$script_dir")"
    if [ -f "$script_dir/env_manager.sh" ]; then
        source "$script_dir/env_manager.sh"
        load_current_env  # 載入當前環境
        
        # 載入環境配置檔案以獲取 ENV_DISPLAY_NAME
        local env_file="$project_root/configs/${CURRENT_ENVIRONMENT}/${CURRENT_ENVIRONMENT}.env"
        if [ -f "$env_file" ]; then
            source "$env_file"
        fi
    fi

    # 參數驗證
    if ! validate_aws_region "$aws_region"; then
        return 1
    fi

    log_message_core "開始獲取 VPC/子網路/VPN 詳細資訊 (lib) - Region: $aws_region"

    # 提示使用者選擇 VPC
    echo -e "\\n${BLUE}選擇網絡設定...${NC}" >&2
    
    echo -e "${YELLOW}可用的 VPCs:${NC}" >&2
    aws ec2 describe-vpcs --region "$aws_region" | jq -r '.Vpcs[] | "VPC ID: \(.VpcId), CIDR: \(.CidrBlock), 名稱: \(if .Tags then (.Tags[] | select(.Key=="Name") | .Value) else "無名稱" end)"' >&2
    
    local vpc_id
    while true; do
        echo -n "請輸入要連接的 VPC ID: " >&2
        read vpc_id
        if aws ec2 describe-vpcs --vpc-ids "$vpc_id" --region "$aws_region" >/dev/null 2>&1; then
            break
        else
            echo -e "${RED}VPC ID '$vpc_id' 無效或不存在於區域 '$aws_region'。請重試。${NC}" >&2
        fi
    done
    
    # 顯示選定 VPC 中的子網路
    echo -e "\\n${YELLOW}VPC $vpc_id 中的子網路:${NC}" >&2
    local subnet_list
    subnet_list=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=$vpc_id" --region "$aws_region" 2>/dev/null | \
      jq -r '.Subnets[] | "子網路 ID: \(.SubnetId), 可用區: \(.AvailabilityZone), CIDR: \(.CidrBlock)"' 2>/dev/null)
    
    if [ -z "$subnet_list" ]; then
        echo -e "${YELLOW}無法獲取子網路列表或此 VPC 沒有子網路。${NC}" >&2
        echo -e "${BLUE}您可以手動輸入子網路 ID，或輸入 'skip' 跳過此步驟。${NC}" >&2
    else
        echo "$subnet_list" >&2
        echo -e "${BLUE}請從上述列表中選擇一個子網路 ID，或輸入 'skip' 跳過此步驟。${NC}" >&2
    fi
    
    local subnet_id
    local max_attempts=5
    local attempts=0
    while [ $attempts -lt $max_attempts ]; do
        echo -n "請輸入要關聯的子網路 ID (或輸入 'skip' 跳過): " >&2
        read subnet_id
        
        # 允許跳過
        if [ "$subnet_id" = "skip" ]; then
            echo -e "${YELLOW}跳過子網路關聯步驟。您稍後可以手動關聯子網路。${NC}" >&2
            subnet_id=""
            break
        fi
        
        # 驗證子網路 ID 格式
        if [[ ! "$subnet_id" =~ ^subnet-[0-9a-f]{8,17}$ ]]; then
            echo -e "${RED}子網路 ID 格式無效。正確格式應為 'subnet-xxxxxxxxx'。${NC}" >&2
            attempts=$((attempts + 1))
            continue
        fi
        
        # 驗證子網路是否存在
        if aws ec2 describe-subnets --subnet-ids "$subnet_id" --filters "Name=vpc-id,Values=$vpc_id" --region "$aws_region" >/dev/null 2>&1; then
            echo -e "${GREEN}✓ 子網路 ID 驗證成功${NC}" >&2
            break
        else
            echo -e "${RED}子網路 ID '$subnet_id' 無效、不存在於 VPC '$vpc_id' 或區域 '$aws_region'。${NC}" >&2
            attempts=$((attempts + 1))
            if [ $attempts -lt $max_attempts ]; then
                echo -e "${YELLOW}請重試 ($attempts/$max_attempts) 或輸入 'skip' 跳過。${NC}" >&2
            fi
        fi
    done
    
    if [ $attempts -eq $max_attempts ] && [ "$subnet_id" != "skip" ] && [ -n "$subnet_id" ]; then
        echo -e "${RED}已達到最大嘗試次數。將跳過子網路關聯步驟。${NC}" >&2
        subnet_id=""
    fi
    
    # 獲取 Security Groups
    echo -e "\\n${YELLOW}VPC $vpc_id 中的 Security Groups:${NC}" >&2
    local sg_list
    sg_list=$(aws ec2 describe-security-groups --filters "Name=vpc-id,Values=$vpc_id" --region "$aws_region" 2>/dev/null | \
      jq -r '.SecurityGroups[] | "SG ID: \(.GroupId), 名稱: \(.GroupName), 描述: \(.Description)"' 2>/dev/null)
    
    if [ -z "$sg_list" ]; then
        echo -e "${YELLOW}無法獲取 Security Groups 列表或此 VPC 沒有 Security Groups。${NC}" >&2
    else
        echo "$sg_list" >&2
    fi
    
    echo -e "${BLUE}請選擇要關聯的 Security Groups (多個請用空格分隔)，或按 Enter 跳過使用預設值:${NC}" >&2
    local security_groups
    echo -n "Security Group IDs: " >&2
    read security_groups
    
    # 驗證 Security Group IDs 格式
    if [ -n "$security_groups" ]; then
        local sg_array=($security_groups)
        local valid_sgs=""
        for sg in "${sg_array[@]}"; do
            if [[ "$sg" =~ ^sg-[0-9a-f]{8,17}$ ]]; then
                # 驗證 Security Group 是否存在於指定 VPC
                if aws ec2 describe-security-groups --group-ids "$sg" --filters "Name=vpc-id,Values=$vpc_id" --region "$aws_region" >/dev/null 2>&1; then
                    valid_sgs="$valid_sgs $sg"
                else
                    echo -e "${YELLOW}警告: Security Group '$sg' 不存在於 VPC '$vpc_id'，將忽略${NC}" >&2
                fi
            else
                echo -e "${YELLOW}警告: Security Group ID '$sg' 格式無效，將忽略${NC}" >&2
            fi
        done
        security_groups=$(echo $valid_sgs | xargs)  # 去除多餘空格
    fi
    
    if [ -n "$security_groups" ]; then
        echo -e "${GREEN}✓ 將使用 Security Groups: $security_groups${NC}" >&2
    else
        echo -e "${YELLOW}將使用預設 Security Groups 設定${NC}" >&2
    fi

    # 獲取 VPN 設定
    local default_vpn_cidr="172.16.0.0/22"
    local vpn_cidr
    echo -n "請輸入 VPN CIDR (預設: $default_vpn_cidr): " >&2
    read vpn_cidr
    vpn_cidr=${vpn_cidr:-$default_vpn_cidr}
    
    # 使用環境名稱作為預設 VPN 名稱
    local default_vpn_name
    if [ -n "$ENV_DISPLAY_NAME" ]; then
        # 將顯示名稱轉換為適合的 VPN 名稱格式
        default_vpn_name="$(echo "$ENV_DISPLAY_NAME" | sed 's/Environment//' | sed 's/^ *//' | sed 's/ *$//' | tr ' ' '_')_VPN"
    elif [ -n "$CURRENT_ENVIRONMENT" ]; then
        # 使用環境名稱的首字母大寫版本
        default_vpn_name="$(echo "$CURRENT_ENVIRONMENT" | sed 's/.*/\u&/')_VPN"
    else
        default_vpn_name="Production-VPN"
    fi
    
    local vpn_name
    echo -n "請輸入 VPN 端點名稱 (預設: $default_vpn_name): " >&2
    read vpn_name
    vpn_name=${vpn_name:-$default_vpn_name}

    # 驗證輸入 (subnet_id 可以為空，因為允許跳過)
    if [ -z "$vpc_id" ] || [ -z "$vpn_cidr" ] || [ -z "$vpn_name" ]; then
        echo -e "${RED}錯誤: 獲取的詳細資訊不完整${NC}" >&2
        log_message_core "錯誤: get_vpc_subnet_vpn_details_lib - 詳細資訊不完整"
        return 1
    fi

    # 生成 JSON 回應
    local result_json
    if command -v jq >/dev/null 2>&1; then
        result_json=$(jq -n \
            --arg vpc_id "$vpc_id" \
            --arg subnet_id "$subnet_id" \
            --arg vpn_cidr "$vpn_cidr" \
            --arg vpn_name "$vpn_name" \
            --arg security_groups "$security_groups" \
            '{vpc_id: $vpc_id, subnet_id: $subnet_id, vpn_cidr: $vpn_cidr, vpn_name: $vpn_name, security_groups: $security_groups}')
    else
        # 備用方法：手動構建 JSON
        result_json="{\"vpc_id\":\"$vpc_id\",\"subnet_id\":\"$subnet_id\",\"vpn_cidr\":\"$vpn_cidr\",\"vpn_name\":\"$vpn_name\",\"security_groups\":\"$security_groups\"}"
    fi

    log_message_core "VPC/子網路詳細資訊獲取完成: VPC=$vpc_id, Subnet=$subnet_id, VPN_CIDR=$vpn_cidr, VPN_Name=$vpn_name, SecurityGroups=$security_groups"
    
    echo "$result_json"
    return 0
}

# 輔助函式：提示網絡詳細資訊
_prompt_network_details_ec() {
    local aws_region="$1"
    # 使用 declare -g 將變數宣告為全域，以便主調用函式可以訪問
    # 或者，函式可以 echo 結果，由主調用者捕獲
    # 這裡我們選擇 echo 組合字串，由主調用者解析

    echo -e "\\n${BLUE}選擇網絡設定...${NC}"
    
    echo -e "${YELLOW}可用的 VPCs:${NC}"
    aws ec2 describe-vpcs --region "$aws_region" | jq -r '.Vpcs[] | "VPC ID: \(.VpcId), CIDR: \(.CidrBlock), 名稱: \(if .Tags then (.Tags[] | select(.Key=="Name") | .Value) else "無名稱" end)"'
    
    local vpc_id
    while true; do
        read -p "請輸入要連接的 VPC ID: " vpc_id
        if aws ec2 describe-vpcs --vpc-ids "$vpc_id" --region "$aws_region" &>/dev/null; then
            break
        else
            echo -e "${RED}VPC ID '$vpc_id' 無效或不存在於區域 '$aws_region'。請重試。${NC}" # vpc_id and aws_region are variables
        fi
    done
    
    local vpc_cidr
    vpc_cidr=$(aws ec2 describe-vpcs --vpc-ids "$vpc_id" --region "$aws_region" | jq -r '.Vpcs[0].CidrBlock')
    
    echo -e "\\n${YELLOW}VPC $vpc_id 中的子網路:${NC}" # vpc_id is a variable
    local subnet_list
    subnet_list=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=$vpc_id" --region "$aws_region" 2>/dev/null | \
      jq -r '.Subnets[] | "子網路 ID: \(.SubnetId), 可用區: \(.AvailabilityZone), CIDR: \(.CidrBlock)"' 2>/dev/null)
    
    if [ -z "$subnet_list" ]; then
        echo -e "${YELLOW}無法獲取子網路列表或此 VPC 沒有子網路。${NC}"
        echo -e "${BLUE}您可以手動輸入子網路 ID，或輸入 'skip' 跳過此步驟。${NC}"
    else
        echo "$subnet_list"
        echo -e "${BLUE}請從上述列表中選擇一個子網路 ID，或輸入 'skip' 跳過此步驟。${NC}"
    fi
    
    local subnet_id
    local max_attempts=5
    local attempts=0
    while [ $attempts -lt $max_attempts ]; do
        read -p "請輸入要關聯的子網路 ID (或輸入 'skip' 跳過): " subnet_id
        
        # 允許跳過
        if [ "$subnet_id" = "skip" ]; then
            echo -e "${YELLOW}跳過子網路關聯步驟。您稍後可以手動關聯子網路。${NC}"
            subnet_id=""
            break
        fi
        
        # 驗證子網路 ID 格式
        if [[ ! "$subnet_id" =~ ^subnet-[0-9a-f]{8,17}$ ]]; then
            echo -e "${RED}子網路 ID 格式無效。正確格式應為 'subnet-xxxxxxxxx'。${NC}"
            attempts=$((attempts + 1))
            continue
        fi
        
        # 驗證子網路是否存在
        if aws ec2 describe-subnets --subnet-ids "$subnet_id" --filters "Name=vpc-id,Values=$vpc_id" --region "$aws_region" &>/dev/null; then
            echo -e "${GREEN}✓ 子網路 ID 驗證成功${NC}"
            break
        else
            echo -e "${RED}子網路 ID '$subnet_id' 無效、不存在於 VPC '$vpc_id' 或區域 '$aws_region'。${NC}" # subnet_id, vpc_id, aws_region are variables
            attempts=$((attempts + 1))
            if [ $attempts -lt $max_attempts ]; then
                echo -e "${YELLOW}請重試 ($attempts/$max_attempts) 或輸入 'skip' 跳過。${NC}"
            fi
        fi
    done
    
    if [ $attempts -eq $max_attempts ] && [ "$subnet_id" != "skip" ] && [ -n "$subnet_id" ]; then
        echo -e "${RED}已達到最大嘗試次數。將跳過子網路關聯步驟。${NC}"
        subnet_id=""
    fi
    
    local default_vpn_cidr="172.16.0.0/22"
    read -p "請輸入 VPN CIDR (預設: $default_vpn_cidr): " vpn_cidr
    vpn_cidr=${vpn_cidr:-$default_vpn_cidr}
    
    read -p "請輸入 VPN 端點名稱 (預設: Production-VPN): " vpn_name
    vpn_name=${vpn_name:-"Production-VPN"}

    cat << EOF
{
  "vpc_id": "$vpc_id",
  "vpc_cidr": "$vpc_cidr",
  "subnet_id": "$subnet_id",
  "vpn_cidr": "$vpn_cidr",
  "vpn_name": "$vpn_name"
}
EOF
}

# 預檢查函數：驗證 AWS CLI 參數
debug_aws_cli_params() {
    local vpn_cidr="$1"
    local server_cert_arn="$2"
    local client_cert_arn="$3"
    local vpn_name="$4"
    local aws_region="$5"
    
    echo -e "${BLUE}=== 開始 AWS CLI 參數預檢查 ===${NC}"
    local validation_errors=0
    
    # 1. 檢查 AWS CLI 可用性
    echo -e "${YELLOW}1. 檢查 AWS CLI 可用性${NC}"
    if ! command -v aws &> /dev/null; then
        echo -e "${RED}✗ AWS CLI 未安裝${NC}"
        ((validation_errors++))
    else
        local aws_version=$(aws --version 2>&1 | head -1)
        echo -e "${GREEN}✓ AWS CLI 可用: $aws_version${NC}"
    fi
    
    # 2. 檢查 AWS 身份驗證
    echo -e "${YELLOW}2. 檢查 AWS 身份驗證${NC}"
    local caller_identity
    if caller_identity=$(aws sts get-caller-identity --region "$aws_region" 2>/dev/null); then
        local account_id=$(echo "$caller_identity" | jq -r '.Account' 2>/dev/null || echo "無法解析")
        local user_arn=$(echo "$caller_identity" | jq -r '.Arn' 2>/dev/null || echo "無法解析")
        echo -e "${GREEN}✓ AWS 身份驗證成功${NC}"
        echo -e "    帳號 ID: $account_id"
        echo -e "    用戶 ARN: $user_arn"
    else
        echo -e "${RED}✗ AWS 身份驗證失敗${NC}"
        ((validation_errors++))
    fi
    
    # 3. 檢查 AWS 區域配置
    echo -e "${YELLOW}3. 檢查 AWS 區域配置${NC}"
    local config_region=$(aws configure get region 2>/dev/null || echo "未設置")
    echo -e "    配置區域: $config_region"
    echo -e "    指定區域: $aws_region"
    if [ -n "$aws_region" ]; then
        echo -e "${GREEN}✓ 區域參數有效${NC}"
    else
        echo -e "${RED}✗ 區域參數為空${NC}"
        ((validation_errors++))
    fi
    
    # 4. 檢查伺服器證書
    echo -e "${YELLOW}4. 檢查伺服器證書狀態${NC}"
    if [ -n "$server_cert_arn" ]; then
        if aws acm describe-certificate --certificate-arn "$server_cert_arn" --region "$aws_region" &>/dev/null; then
            local cert_status=$(aws acm describe-certificate --certificate-arn "$server_cert_arn" --region "$aws_region" --query 'Certificate.Status' --output text 2>/dev/null)
            echo -e "${GREEN}✓ 伺服器證書可訪問，狀態: $cert_status${NC}"
        else
            echo -e "${RED}✗ 伺服器證書不可訪問或不存在${NC}"
            echo -e "    ARN: $server_cert_arn"
            ((validation_errors++))
        fi
    else
        echo -e "${RED}✗ 伺服器證書 ARN 為空${NC}"
        ((validation_errors++))
    fi
    
    # 5. 檢查客戶端證書
    echo -e "${YELLOW}5. 檢查客戶端證書狀態${NC}"
    if [ -n "$client_cert_arn" ]; then
        if aws acm describe-certificate --certificate-arn "$client_cert_arn" --region "$aws_region" &>/dev/null; then
            local cert_status=$(aws acm describe-certificate --certificate-arn "$client_cert_arn" --region "$aws_region" --query 'Certificate.Status' --output text 2>/dev/null)
            echo -e "${GREEN}✓ 客戶端證書可訪問，狀態: $cert_status${NC}"
        else
            echo -e "${RED}✗ 客戶端證書不可訪問或不存在${NC}"
            echo -e "    ARN: $client_cert_arn"
            ((validation_errors++))
        fi
    else
        echo -e "${RED}✗ 客戶端證書 ARN 為空${NC}"
        ((validation_errors++))
    fi
    
    # 6. 檢查 VPN CIDR 格式
    echo -e "${YELLOW}6. 檢查 VPN CIDR 格式${NC}"
    if [[ "$vpn_cidr" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}/[0-9]{1,2}$ ]]; then
        echo -e "${GREEN}✓ VPN CIDR 格式有效: $vpn_cidr${NC}"
    else
        echo -e "${RED}✗ VPN CIDR 格式無效: $vpn_cidr${NC}"
        ((validation_errors++))
    fi
    
    # 7. 檢查 VPN 名稱
    echo -e "${YELLOW}7. 檢查 VPN 名稱${NC}"
    if [ -n "$vpn_name" ] && [ ${#vpn_name} -le 255 ]; then
        echo -e "${GREEN}✓ VPN 名稱有效: $vpn_name${NC}"
    else
        echo -e "${RED}✗ VPN 名稱無效或過長: $vpn_name${NC}"
        ((validation_errors++))
    fi
    
    # 8. 檢查 EC2 權限
    echo -e "${YELLOW}8. 檢查 EC2 權限${NC}"
    if aws ec2 describe-client-vpn-endpoints --region "$aws_region" --max-items 1 &>/dev/null; then
        echo -e "${GREEN}✓ EC2 Client VPN 權限正常${NC}"
    else
        echo -e "${RED}✗ 缺少 EC2 Client VPN 權限${NC}"
        ((validation_errors++))
    fi
    
    # 9. 檢查 jq 工具
    echo -e "${YELLOW}9. 檢查 jq 工具可用性${NC}"
    if command -v jq &> /dev/null; then
        echo -e "${GREEN}✓ jq 工具可用${NC}"
    else
        echo -e "${YELLOW}⚠ jq 工具不可用，可能影響 JSON 解析${NC}"
    fi
    
    echo -e "${BLUE}=== 預檢查完成 ===${NC}"
    
    if [ $validation_errors -eq 0 ]; then
        echo -e "${GREEN}✓ 所有預檢查通過，可以繼續創建 VPN 端點${NC}"
        return 0
    else
        echo -e "${RED}✗ 發現 $validation_errors 個驗證錯誤，無法繼續創建 VPN 端點${NC}"
        return 1
    fi
}

# 輔助函式：創建 AWS Client VPN 端點實體
_create_aws_client_vpn_endpoint_ec() {
    local vpn_cidr="$1"
    local server_cert_arn="$2"
    local client_cert_arn="$3"
    local vpn_name="$4"
    local aws_region="$5"
    local security_groups="$6"

    # 清理 VPN 名稱以用於日誌群組 (只允許字母、數字、連字符和斜線)
    local clean_log_name=$(echo "$vpn_name" | sed 's/[^a-zA-Z0-9/_-]/-/g' | sed 's/--*/-/g' | sed 's/^-\|-$//g')
    local log_group_name="/aws/clientvpn/$clean_log_name"
    echo -e "${BLUE}創建 CloudWatch 日誌群組: $log_group_name${NC}" >&2
    
    # 檢查日誌群組是否已存在
    if ! aws logs describe-log-groups --log-group-name-prefix "$log_group_name" --region "$aws_region" --query "logGroups[?logGroupName=='$log_group_name']" --output text | grep -q "$log_group_name"; then
        echo -e "${YELLOW}日誌群組不存在，正在創建...${NC}" >&2
        if aws logs create-log-group --log-group-name "$log_group_name" --region "$aws_region" 2>/dev/null; then
            echo -e "${GREEN}✓ 日誌群組創建成功${NC}" >&2
            
            # 設定 30 天保留期間
            echo -e "${BLUE}設定日誌保留期間為 30 天...${NC}" >&2
            if aws logs put-retention-policy \
                --log-group-name "$log_group_name" \
                --retention-in-days 30 \
                --region "$aws_region" 2>/dev/null; then
                echo -e "${GREEN}✓ 日誌保留期間設定完成 (30 天)${NC}" >&2
            else
                echo -e "${YELLOW}⚠ 無法設定日誌保留期間，但不影響 VPN 端點創建${NC}" >&2
            fi
        else
            echo -e "${YELLOW}日誌群組創建失敗，但這不會影響 VPN 端點創建${NC}" >&2
            echo -e "${YELLOW}嘗試不使用日誌群組創建 VPN 端點...${NC}" >&2
            log_group_name=""
        fi
    else
        echo -e "${GREEN}✓ 日誌群組已存在${NC}" >&2
        
        # 檢查並設定現有日誌群組的保留期間
        echo -e "${BLUE}檢查現有日誌群組的保留期間...${NC}" >&2
        local current_retention
        current_retention=$(aws logs describe-log-groups \
            --log-group-name-prefix "$log_group_name" \
            --region "$aws_region" \
            --query "logGroups[?logGroupName=='$log_group_name'].retentionInDays" \
            --output text 2>/dev/null)
        
        if [ -z "$current_retention" ] || [ "$current_retention" = "None" ] || [ "$current_retention" = "null" ]; then
            echo -e "${YELLOW}現有日誌群組無保留期間設定，正在設定為 30 天...${NC}" >&2
            if aws logs put-retention-policy \
                --log-group-name "$log_group_name" \
                --retention-in-days 30 \
                --region "$aws_region" 2>/dev/null; then
                echo -e "${GREEN}✓ 日誌保留期間設定完成 (30 天)${NC}" >&2
            else
                echo -e "${YELLOW}⚠ 無法設定日誌保留期間${NC}" >&2
            fi
        elif [ "$current_retention" != "30" ]; then
            echo -e "${YELLOW}現有保留期間: $current_retention 天，建議設定為 30 天${NC}" >&2
        else
            echo -e "${GREEN}✓ 日誌保留期間已設定為 30 天${NC}" >&2
        fi
    fi
    
    echo -e "${BLUE}創建 Client VPN 端點...${NC}" >&2
    echo -e "${YELLOW}使用參數:${NC}" >&2
    echo -e "  VPN CIDR: $vpn_cidr" >&2
    echo -e "  伺服器憑證 ARN: $server_cert_arn" >&2
    echo -e "  客戶端憑證 ARN: $client_cert_arn" >&2
    echo -e "  VPN 名稱: $vpn_name" >&2
    echo -e "  AWS 區域: $aws_region" >&2
    
    # 執行調試檢查
    echo -e "\n${BLUE}執行預檢查...${NC}" >&2
    if ! debug_aws_cli_params "$vpn_cidr" "$server_cert_arn" "$client_cert_arn" "$vpn_name" "$aws_region" >&2; then
        echo -e "${RED}預檢查失敗，無法繼續創建 VPN 端點${NC}" >&2
        return 1
    fi
    
    local endpoint_result exit_code
    
    # 清理 VPN 名稱中的特殊字符以用於標籤
    local clean_vpn_name=$(echo "$vpn_name" | sed 's/[^a-zA-Z0-9-]/_/g')
    
    echo -e "${BLUE}執行 AWS CLI 命令創建 VPN 端點...${NC}" >&2
    
    # 建構 authentication-options JSON
    auth_options='{
        "Type": "certificate-authentication",
        "MutualAuthentication": {
            "ClientRootCertificateChainArn": "'$client_cert_arn'"
        }
    }'
    
    # 建構 connection-log-options JSON (只有當日誌群組存在時才啟用)
    if [ -n "$log_group_name" ]; then
        log_options='{
            "Enabled": true,
            "CloudwatchLogGroup": "'$log_group_name'"
        }'
        echo -e "${GREEN}啟用 CloudWatch 日誌記錄${NC}" >&2
    else
        log_options='{
            "Enabled": false
        }'
        echo -e "${YELLOW}禁用 CloudWatch 日誌記錄${NC}" >&2
    fi
    
    # 建構 tag-specifications JSON
    tag_specs='[{
        "ResourceType": "client-vpn-endpoint",
        "Tags": [
            {"Key": "Name", "Value": "'$clean_vpn_name'"},
            {"Key": "Purpose", "Value": "VPNManagement"}
        ]
    }]'
    
    echo -e "${YELLOW}創建參數預覽:${NC}" >&2
    echo "VPN CIDR: $vpn_cidr" >&2
    echo "伺服器證書: $server_cert_arn" >&2
    echo "客戶端證書: $client_cert_arn" >&2
    echo "日誌群組: $log_group_name" >&2
    echo "VPN 名稱: $clean_vpn_name" >&2
    echo "Security Groups: ${security_groups:-無 (使用預設)}" >&2
    
    # 計算 VPC DNS 服務器 IP（VPC CIDR 的第二個 IP）
    local vpc_dns_server
    if [ -n "$vpc_id" ]; then
        local vpc_cidr_for_dns=$(aws ec2 describe-vpcs --vpc-ids "$vpc_id" --region "$aws_region" --query 'Vpcs[0].CidrBlock' --output text 2>/dev/null)
        if [ -n "$vpc_cidr_for_dns" ] && [ "$vpc_cidr_for_dns" != "None" ]; then
            # 提取網絡地址並計算 DNS 服務器 IP（網絡地址 + 2）
            local network=$(echo "$vpc_cidr_for_dns" | cut -d'/' -f1)
            local base_ip=$(echo "$network" | cut -d'.' -f1-3)
            local last_octet=$(echo "$network" | cut -d'.' -f4)
            vpc_dns_server="${base_ip}.$((last_octet + 2))"
            echo -e "${GREEN}✓ 計算出 VPC DNS 服務器: $vpc_dns_server${NC}" >&2
        else
            vpc_dns_server="192.168.0.2"  # 預設值
            echo -e "${YELLOW}⚠️ 無法獲取 VPC CIDR，使用預設 DNS: $vpc_dns_server${NC}" >&2
        fi
    else
        vpc_dns_server="192.168.0.2"  # 預設值
        echo -e "${YELLOW}⚠️ 未提供 VPC ID，使用預設 DNS: $vpc_dns_server${NC}" >&2
    fi

    # 顯示完整的 AWS CLI 命令預覽
    echo -e "\n${BLUE}=== AWS CLI 命令預覽 ===${NC}" >&2
    echo "aws ec2 create-client-vpn-endpoint \\" >&2
    echo "    --client-cidr-block '$vpn_cidr' \\" >&2
    echo "    --server-certificate-arn '$server_cert_arn' \\" >&2
    echo "    --authentication-options '$auth_options' \\" >&2
    echo "    --connection-log-options '$log_options' \\" >&2
    echo "    --transport-protocol tcp \\" >&2
    echo "    --split-tunnel \\" >&2
    echo "    --dns-servers $vpc_dns_server 8.8.4.4 \\" >&2
    if [ -n "$security_groups" ]; then
        echo "    --security-group-ids $security_groups \\" >&2
    fi
    echo "    --region '$aws_region' \\" >&2
    echo "    --tag-specifications '$tag_specs'" >&2
    echo -e "${BLUE}===========================================${NC}\n" >&2
    
    # 詳細記錄到日誌
    log_message_core "準備執行 VPN 端點創建命令"
    log_message_core "VPN CIDR: $vpn_cidr"
    log_message_core "伺服器證書 ARN: $server_cert_arn"
    log_message_core "客戶端證書 ARN: $client_cert_arn"
    log_message_core "VPN 名稱: $vpn_name"
    log_message_core "AWS 區域: $aws_region"
    log_message_core "Security Groups: ${security_groups:-無 (使用預設)}"
    
    echo -e "${BLUE}正在執行 AWS CLI 創建命令...${NC}" >&2
    local start_time=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${YELLOW}開始時間: $start_time${NC}" >&2
    
    # 執行創建命令
    if [ -n "$log_group_name" ]; then
        if [ -n "$security_groups" ]; then
            endpoint_result=$(aws ec2 create-client-vpn-endpoint \
              --client-cidr-block "$vpn_cidr" \
              --server-certificate-arn "$server_cert_arn" \
              --authentication-options "$auth_options" \
              --connection-log-options "$log_options" \
              --transport-protocol tcp \
              --split-tunnel \
              --dns-servers "$vpc_dns_server" 8.8.4.4 \
              --security-group-ids $security_groups \
              --region "$aws_region" \
              --tag-specifications "$tag_specs" 2>&1)
        else
            endpoint_result=$(aws ec2 create-client-vpn-endpoint \
              --client-cidr-block "$vpn_cidr" \
              --server-certificate-arn "$server_cert_arn" \
              --authentication-options "$auth_options" \
              --connection-log-options "$log_options" \
              --transport-protocol tcp \
              --split-tunnel \
              --dns-servers "$vpc_dns_server" 8.8.4.4 \
              --region "$aws_region" \
              --tag-specifications "$tag_specs" 2>&1)
        fi
    else
        if [ -n "$security_groups" ]; then
            endpoint_result=$(aws ec2 create-client-vpn-endpoint \
              --client-cidr-block "$vpn_cidr" \
              --server-certificate-arn "$server_cert_arn" \
              --authentication-options "$auth_options" \
              --connection-log-options "$log_options" \
              --transport-protocol tcp \
              --split-tunnel \
              --dns-servers "$vpc_dns_server" 8.8.4.4 \
              --security-group-ids $security_groups \
              --region "$aws_region" \
              --tag-specifications "$tag_specs" 2>&1)
        else
            endpoint_result=$(aws ec2 create-client-vpn-endpoint \
              --client-cidr-block "$vpn_cidr" \
              --server-certificate-arn "$server_cert_arn" \
              --authentication-options "$auth_options" \
              --connection-log-options "$log_options" \
              --transport-protocol tcp \
              --split-tunnel \
              --dns-servers "$vpc_dns_server" 8.8.4.4 \
              --region "$aws_region" \
              --tag-specifications "$tag_specs" 2>&1)
        fi
    fi
    exit_code=$?
    
    local end_time=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${YELLOW}結束時間: $end_time${NC}" >&2
    log_message_core "AWS CLI 命令執行完成，exit code: $exit_code，結束時間: $end_time"
    
    # 檢查 AWS CLI 命令是否成功執行
    if [ $exit_code -ne 0 ]; then
        echo -e "${RED}═══════════════════════════════════════${NC}" >&2
        echo -e "${RED}    AWS CLI 錯誤詳細診斷 (exit code: $exit_code)${NC}" >&2
        echo -e "${RED}═══════════════════════════════════════${NC}" >&2
        
        # 記錄完整的錯誤信息
        echo -e "${YELLOW}錯誤輸出:${NC}" >&2
        echo "$endpoint_result" >&2
        echo -e "" >&2
        
        # 環境診斷
        echo -e "${YELLOW}環境診斷信息:${NC}" >&2
        echo "  AWS CLI 版本: $(aws --version 2>&1 | head -1)" >&2
        echo "  當前區域: $(aws configure get region 2>/dev/null || echo '未設置')" >&2
        echo "  當前身份: $(aws sts get-caller-identity --query 'Arn' --output text 2>/dev/null || echo '無法獲取')" >&2
        echo "  當前時間: $(date)" >&2
        echo -e "" >&2
        
        # 參數驗證
        echo -e "${YELLOW}創建參數驗證:${NC}" >&2
        echo "  VPN CIDR: '$vpn_cidr'" >&2
        echo "  伺服器證書 ARN: '$server_cert_arn'" >&2
        echo "  客戶端證書 ARN: '$client_cert_arn'" >&2
        echo "  VPN 名稱: '$vpn_name'" >&2
        echo "  AWS 區域: '$aws_region'" >&2
        echo "  Security Groups: '${security_groups:-無 (使用預設)}'" >&2
        echo -e "" >&2
        
        # 檢查證書狀態
        echo -e "${YELLOW}檢查證書狀態:${NC}" >&2
        if aws acm describe-certificate --certificate-arn "$server_cert_arn" --region "$aws_region" &>/dev/null; then
            echo "  ✓ 伺服器證書可訪問" >&2
        else
            echo "  ✗ 伺服器證書不可訪問或不存在" >&2
        fi
        
        if aws acm describe-certificate --certificate-arn "$client_cert_arn" --region "$aws_region" &>/dev/null; then
            echo "  ✓ 客戶端證書可訪問" >&2
        else
            echo "  ✗ 客戶端證書不可訪問或不存在" >&2
        fi
        echo -e "" >&2
        
        # 檢查 JSON 格式
        echo -e "${YELLOW}檢查 JSON 參數格式:${NC}" >&2
        echo "  認證選項: $auth_options" >&2
        if echo "$auth_options" | jq . &>/dev/null; then
            echo "  ✓ 認證選項 JSON 格式有效" >&2
        else
            echo "  ✗ 認證選項 JSON 格式無效" >&2
        fi
        
        echo "  日誌選項: $log_options" >&2
        if echo "$log_options" | jq . &>/dev/null; then
            echo "  ✓ 日誌選項 JSON 格式有效" >&2
        else
            echo "  ✗ 日誌選項 JSON 格式無效" >&2
        fi
        
        echo "  標籤規格: $tag_specs" >&2
        if echo "$tag_specs" | jq . &>/dev/null; then
            echo "  ✓ 標籤規格 JSON 格式有效" >&2
        else
            echo "  ✗ 標籤規格 JSON 格式無效" >&2
        fi
        echo -e "" >&2
        
        echo -e "${RED}═══════════════════════════════════════${NC}" >&2
        
        log_message_core "錯誤: VPN 端點創建失敗 - AWS CLI 錯誤 (exit code: $exit_code) - 詳細診斷已輸出"
        
        # 保存完整診斷到文件
        {
            echo "=== VPN 端點創建失敗診斷報告 ==="
            echo "時間: $(date)"
            echo "Exit Code: $exit_code"
            echo "錯誤輸出: $endpoint_result"
            echo "AWS CLI 版本: $(aws --version 2>&1)"
            echo "當前區域: $(aws configure get region 2>/dev/null || echo '未設置')"
            echo "當前身份: $(aws sts get-caller-identity --query 'Arn' --output text 2>/dev/null || echo '無法獲取')"
            echo "VPN CIDR: $vpn_cidr"
            echo "伺服器證書 ARN: $server_cert_arn"
            echo "客戶端證書 ARN: $client_cert_arn"
            echo "認證選項: $auth_options"
            echo "日誌選項: $log_options"
            echo "標籤規格: $tag_specs"
        } >> "${LOG_FILE:-vpn_error_diagnostic.log}"
        
        return 1
    fi
    
    # 檢查輸出是否為空
    if [ -z "$endpoint_result" ]; then
        echo -e "${RED}AWS CLI 命令沒有返回任何輸出${NC}" >&2
        log_message_core "錯誤: VPN 端點創建失敗 - 無輸出"
        return 1
    fi
    
    # 記錄原始輸出用於調試
    echo -e "${YELLOW}AWS CLI 原始輸出:${NC}" >&2
    echo "$endpoint_result" >&2
    
    # 嘗試修復可能的 JSON 格式問題
    # 有時候 AWS CLI 可能在 JSON 前面加入一些額外字符
    cleaned_result=$(echo "$endpoint_result" | sed '1{/^[[:space:]]*$/d;}' | grep -E '^\s*\{' | head -1)
    if [ -n "$cleaned_result" ]; then
        # 從找到的第一個 { 開始提取 JSON
        json_start_line=$(echo "$endpoint_result" | grep -n '^[[:space:]]*{' | head -1 | cut -d: -f1)
        if [ -n "$json_start_line" ]; then
            cleaned_result=$(echo "$endpoint_result" | tail -n +$json_start_line)
            echo -e "${YELLOW}清理後的 JSON:${NC}" >&2
            echo "$cleaned_result" >&2
        else
            cleaned_result="$endpoint_result"
        fi
    else
        cleaned_result="$endpoint_result"
    fi
    
    # 檢查清理後的輸出是否為有效的 JSON
    if ! echo "$cleaned_result" | jq empty 2>/dev/null; then
        echo -e "${RED}AWS CLI 返回的不是有效的 JSON 格式${NC}" >&2
        echo -e "${RED}嘗試使用備用解析方法...${NC}" >&2
        
        # 嘗試使用 grep 和 sed 提取端點 ID
        endpoint_id=$(echo "$endpoint_result" | grep -o '"ClientVpnEndpointId"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*"ClientVpnEndpointId"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')
        
        if [ -n "$endpoint_id" ] && [ "$endpoint_id" != "null" ]; then
            echo -e "${GREEN}✓ 使用備用方法成功提取端點 ID: $endpoint_id${NC}" >&2
            echo "$endpoint_id"
            return 0
        else
            echo -e "${RED}備用解析方法也失敗${NC}" >&2
            echo -e "${RED}原始輸出: $endpoint_result${NC}" >&2
            log_message_core "錯誤: VPN 端點創建失敗 - JSON 解析失敗"
            return 1
        fi
    fi
    
    local endpoint_id
    if ! endpoint_id=$(echo "$cleaned_result" | jq -r '.ClientVpnEndpointId' 2>/dev/null); then
        echo -e "${RED}無法從響應中解析端點 ID${NC}" >&2
        echo -e "${RED}響應內容: $cleaned_result${NC}" >&2
        log_message_core "錯誤: VPN 端點創建失敗 - 端點 ID 解析失敗"
        return 1
    fi

    if [ -z "$endpoint_id" ] || [ "$endpoint_id" == "null" ]; then
        echo -e "${RED}創建 Client VPN 端點後未能獲取有效的 Endpoint ID${NC}" >&2
        echo -e "${RED}響應內容: $cleaned_result${NC}" >&2
        log_message_core "錯誤: VPN 端點創建失敗 - 端點 ID 為空或 null"
        return 1
    fi
    
    echo -e "${GREEN}✓ VPN 端點創建成功，ID: $endpoint_id${NC}" >&2
    log_message_core "VPN 端點創建成功，ID: $endpoint_id"
    echo "$endpoint_id"
    return 0
}

# 輔助函式：關聯目標網絡
_associate_target_network_ec() {
    local endpoint_id="$1"
    local subnet_id="$2"
    local aws_region="$3"

    echo -e "${BLUE}關聯子網路...${NC}"
    log_message_core "開始關聯子網路: 端點 ID=$endpoint_id, 子網路 ID=$subnet_id, 區域=$aws_region"
    
    local start_time=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${YELLOW}開始時間: $start_time${NC}"
    log_message_core "AWS CLI 命令開始執行: associate-client-vpn-target-network, 開始時間: $start_time"
    
    # 執行 AWS CLI 命令並捕獲輸出和錯誤
    local result output error_output exit_code
    output=$(aws ec2 associate-client-vpn-target-network \
      --client-vpn-endpoint-id "$endpoint_id" \
      --subnet-id "$subnet_id" \
      --region "$aws_region" 2>&1)
    exit_code=$?
    
    local end_time=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${YELLOW}結束時間: $end_time${NC}"
    log_message_core "AWS CLI 命令執行完成: associate-client-vpn-target-network, exit code: $exit_code, 結束時間: $end_time"
    
    if [ $exit_code -eq 0 ]; then
        echo -e "${GREEN}✓ 子網路關聯成功${NC}"
        log_message_core "子網路關聯成功: $output"
        # 嘗試解析關聯 ID
        local association_id
        if association_id=$(echo "$output" | jq -r '.AssociationId' 2>/dev/null); then
            if [ -n "$association_id" ] && [ "$association_id" != "null" ]; then
                echo -e "${GREEN}關聯 ID: $association_id${NC}"
                log_message_core "關聯 ID: $association_id"
            fi
        fi
        return 0
    else
        echo -e "${RED}✗ 子網路關聯失敗${NC}"
        echo -e "${RED}錯誤輸出: $output${NC}"
        log_message_core "錯誤: 子網路關聯失敗 (exit code: $exit_code) - $output"
        
        # 保存詳細診斷信息
        {
            echo "=== 子網路關聯失敗診斷報告 ==="
            echo "時間: $(date)"
            echo "Exit Code: $exit_code"
            echo "端點 ID: $endpoint_id"
            echo "子網路 ID: $subnet_id"
            echo "AWS 區域: $aws_region"
            echo "錯誤輸出: $output"
            echo "AWS CLI 版本: $(aws --version 2>&1)"
            echo "當前身份: $(aws sts get-caller-identity --query 'Arn' --output text 2>/dev/null || echo '無法獲取')"
            echo "================================"
        } >> "${LOG_FILE:-vpn_error_diagnostic.log}"
        
        return 1
    fi
}

# 輔助函式：設定授權和路由
_setup_authorization_and_routes_ec() {
    local endpoint_id="$1"
    local vpc_cidr="$2" # 主要 VPC 的 CIDR，用於初始授權
    local subnet_id="$3" # 主要子網路 ID，用於初始路由
    local aws_region="$4"

    echo -e "${BLUE}添加授權規則 (允許訪問主要 VPC)...${NC}"
    log_message_core "開始添加授權規則: 端點 ID=$endpoint_id, VPC CIDR=$vpc_cidr, 區域=$aws_region"
    
    local start_time=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${YELLOW}授權規則開始時間: $start_time${NC}"
    log_message_core "AWS CLI 命令開始執行: authorize-client-vpn-ingress, 開始時間: $start_time"
    
    # 執行授權規則 AWS CLI 命令並捕獲輸出和錯誤
    local auth_output auth_exit_code
    auth_output=$(aws ec2 authorize-client-vpn-ingress \
      --client-vpn-endpoint-id "$endpoint_id" \
      --target-network-cidr "$vpc_cidr" \
      --authorize-all-groups \
      --region "$aws_region" 2>&1)
    auth_exit_code=$?
    
    local auth_end_time=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${YELLOW}授權規則結束時間: $auth_end_time${NC}"
    log_message_core "AWS CLI 命令執行完成: authorize-client-vpn-ingress, exit code: $auth_exit_code, 結束時間: $auth_end_time"
    
    if [ $auth_exit_code -eq 0 ]; then
        echo -e "${GREEN}✓ 授權規則添加成功${NC}"
        log_message_core "授權規則添加成功: $auth_output"
    else
        echo -e "${RED}✗ 授權規則添加失敗${NC}"
        echo -e "${RED}錯誤輸出: $auth_output${NC}"
        log_message_core "錯誤: 授權規則添加失敗 (exit code: $auth_exit_code) - $auth_output"
        
        # 保存詳細診斷信息
        {
            echo "=== 授權規則添加失敗診斷報告 ==="
            echo "時間: $(date)"
            echo "Exit Code: $auth_exit_code"
            echo "端點 ID: $endpoint_id"
            echo "VPC CIDR: $vpc_cidr"
            echo "AWS 區域: $aws_region"
            echo "錯誤輸出: $auth_output"
            echo "AWS CLI 版本: $(aws --version 2>&1)"
            echo "當前身份: $(aws sts get-caller-identity --query 'Arn' --output text 2>/dev/null || echo '無法獲取')"
            echo "============================="
        } >> "${LOG_FILE:-vpn_error_diagnostic.log}"
        
        return 1
    fi

    echo -e "${BLUE}創建路由 (允許所有流量通過 VPN 到主要子網路)...${NC}"
    log_message_core "開始創建路由: 端點 ID=$endpoint_id, 子網路 ID=$subnet_id, 區域=$aws_region"
    
    local route_start_time=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${YELLOW}路由創建開始時間: $route_start_time${NC}"
    log_message_core "AWS CLI 命令開始執行: create-client-vpn-route, 開始時間: $route_start_time"
    
    # 執行路由創建 AWS CLI 命令並捕獲輸出和錯誤
    local route_output route_exit_code
    route_output=$(aws ec2 create-client-vpn-route \
      --client-vpn-endpoint-id "$endpoint_id" \
      --destination-cidr-block "0.0.0.0/0" \
      --target-vpc-subnet-id "$subnet_id" \
      --region "$aws_region" 2>&1)
    route_exit_code=$?
    
    local route_end_time=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${YELLOW}路由創建結束時間: $route_end_time${NC}"
    log_message_core "AWS CLI 命令執行完成: create-client-vpn-route, exit code: $route_exit_code, 結束時間: $route_end_time"
    
    if [ $route_exit_code -eq 0 ]; then
        echo -e "${GREEN}✓ 路由創建成功${NC}"
        log_message_core "路由創建成功: $route_output"
    else
        echo -e "${RED}✗ 路由創建失敗${NC}"
        echo -e "${RED}錯誤輸出: $route_output${NC}"
        log_message_core "錯誤: 路由創建失敗 (exit code: $route_exit_code) - $route_output"
        
        # 保存詳細診斷信息
        {
            echo "=== 路由創建失敗診斷報告 ==="
            echo "時間: $(date)"
            echo "Exit Code: $route_exit_code"
            echo "端點 ID: $endpoint_id"
            echo "目標子網路 ID: $subnet_id"
            echo "目標 CIDR: 0.0.0.0/0"
            echo "AWS 區域: $aws_region"
            echo "錯誤輸出: $route_output"
            echo "AWS CLI 版本: $(aws --version 2>&1)"
            echo "當前身份: $(aws sts get-caller-identity --query 'Arn' --output text 2>/dev/null || echo '無法獲取')"
            echo "========================="
        } >> "${LOG_FILE:-vpn_error_diagnostic.log}"
        
        return 1
    fi
    
    return 0
}

# 等待 VPN 端點變為可用狀態的輔助函數
# 參數: endpoint_id, aws_region
# 返回: 0 如果成功，1 如果失敗或超時
_wait_for_client_vpn_endpoint_available() {
    local endpoint_id="$1"
    local aws_region="$2"
    local max_wait_time=300  # 最大等待時間（秒）
    local wait_interval=15   # 檢查間隔（秒）
    local elapsed_time=0
    
    echo -e "${BLUE}等待端點 $endpoint_id 變為可用狀態...${NC}"
    
    while [ $elapsed_time -lt $max_wait_time ]; do
        local endpoint_status
        endpoint_status=$(aws ec2 describe-client-vpn-endpoints \
            --client-vpn-endpoint-ids "$endpoint_id" \
            --region "$aws_region" \
            --query 'ClientVpnEndpoints[0].Status.Code' \
            --output text 2>/dev/null)
        
        if [ $? -ne 0 ]; then
            echo -e "${RED}無法查詢端點狀態${NC}"
            return 1
        fi
        
        case "$endpoint_status" in
            "available")
                echo -e "${GREEN}✓ 端點已可用${NC}"
                return 0
                ;;
            "pending-associate"|"pending")
                echo -e "${YELLOW}端點狀態: $endpoint_status，合埋，因為可能沒有VPC，繼續往下走...${NC}"
                return 0
                ;;
            "deleted"|"deleting")
                echo -e "${RED}端點已被刪除或正在刪除${NC}"
                return 1
                ;;
            *)
                echo -e "${YELLOW}端點狀態: $endpoint_status，繼續等待... (${elapsed_time}s/${max_wait_time}s)${NC}"
                ;;
        esac
        
        sleep $wait_interval
        elapsed_time=$((elapsed_time + wait_interval))
    done
    
    echo -e "${RED}等待端點可用超時 (${max_wait_time}秒)${NC}"
    return 1
}

# 主要的端點創建函式
# 參數: main_config_file, aws_region, vpc_id, subnet_id, vpn_cidr, server_cert_arn, client_cert_arn, vpn_name, security_groups
create_vpn_endpoint_lib() {
    local main_config_file="$1"
    local aws_region="$2"
    local vpc_id="$3"
    local subnet_id="$4"
    local vpn_cidr="$5"
    local arg_server_cert_arn="$6"
    local arg_client_cert_arn="$7"
    local vpn_name="$8"
    local security_groups="$9"

    echo -e "\\n${CYAN}=== 建立新的 VPN 端點 (來自 lib) ===${NC}"

    # 載入配置 (確保其他配置變數可用)
    if [ -f "$main_config_file" ]; then
        source "$main_config_file" # 這會載入配置變數
    else
        echo -e "${RED}錯誤: 配置文件 \"$main_config_file\" 未找到。請先執行 AWS 配置。${NC}" # Quoted $main_config_file
        return 1
    fi

    # 使用傳入的 AWS_REGION 參數
    if [ -z "$aws_region" ]; then
        echo -e "${RED}錯誤: AWS_REGION 未提供。${NC}"
        return 1
    fi

    # 1. 檢查/生成證書 (已在主腳本 create_vpn_endpoint 中處理，這裡假設已完成)
    # 2. 導入證書到 ACM (已在主腳本 create_vpn_endpoint 中處理，並傳入 ARNs)
    #    這裡假設 server_cert_arn 和 client_cert_arn 已經作為全域變數或參數傳入
    #    為了模組化，最好是作為參數傳入 create_vpn_endpoint_lib

    # 為了演示，我們假設 server_cert_arn 和 client_cert_arn 是從主腳本的環境中讀取的
    # 在實際使用中，主腳本的 create_vpn_endpoint 應該調用 cert_management 的函式獲取 ARNs，
    # 然後將這些 ARNs 傳遞給 create_vpn_endpoint_lib

    # 使用傳入的參數
    if [ -z "$arg_server_cert_arn" ] || [ -z "$arg_client_cert_arn" ]; then
        echo -e "${RED}錯誤: 伺服器或客戶端證書 ARN 未提供給 create_vpn_endpoint_lib。${NC}"
        return 1
    fi

    # 驗證傳入的網絡參數
    if [ -z "$vpc_id" ] || [ -z "$subnet_id" ] || [ -z "$vpn_cidr" ] || [ -z "$vpn_name" ]; then
        echo -e "${RED}錯誤: 網絡參數 (vpc_id, subnet_id, vpn_cidr, vpn_name) 未完整提供。${NC}"
        return 1
    fi

    # 獲取 VPC CIDR 用於授權規則
    local vpc_cidr
    vpc_cidr=$(aws ec2 describe-vpcs --vpc-ids "$vpc_id" --region "$aws_region" --query 'Vpcs[0].CidrBlock' --output text)
    if [ -z "$vpc_cidr" ] || [ "$vpc_cidr" == "None" ]; then
        echo -e "${RED}錯誤: 無法獲取 VPC $vpc_id 的 CIDR。${NC}"
        return 1
    fi

    # 創建 Client VPN 端點
    local endpoint_id
    endpoint_id=$(_create_aws_client_vpn_endpoint_ec "$vpn_cidr" "$arg_server_cert_arn" "$arg_client_cert_arn" "$vpn_name" "$aws_region" "$security_groups")
    if [ $? -ne 0 ] || [ -z "$endpoint_id" ] || [ "$endpoint_id" == "null" ]; then
        echo -e "${RED}創建 VPN 端點失敗。中止。${NC}"
        return 1
    fi
    echo -e "${BLUE}端點 ID: $endpoint_id${NC}" # endpoint_id is a variable

    # 等待端點可用
    echo -e "${BLUE}等待 VPN 端點可用...${NC}"
    log_message_core "開始等待 VPN 端點可用: $endpoint_id"
    if ! _wait_for_client_vpn_endpoint_available "$endpoint_id" "$aws_region"; then
        echo -e "${RED}等待 VPN 端點可用時發生錯誤或超時。${NC}"
        log_message_core "錯誤: 等待 VPN 端點可用失敗或超時: $endpoint_id"
        # 可以考慮是否需要刪除部分創建的資源
        return 1
    fi
    log_message_core "VPN 端點已可用: $endpoint_id"

    # 關聯子網路
    echo -e "\n${CYAN}=== 步驟：關聯子網路到 VPN 端點 ===${NC}"
    log_message_core "開始執行關聯子網路步驟: 端點=$endpoint_id, 子網路=$subnet_id"
    if ! _associate_target_network_ec "$endpoint_id" "$subnet_id" "$aws_region"; then
        echo -e "${RED}關聯子網路失敗，VPN 端點創建過程終止。${NC}"
        log_message_core "錯誤: 關聯子網路失敗，VPN 端點創建過程終止"
        return 1
    fi
    log_message_core "關聯子網路步驟完成成功"

    # 添加授權規則和路由
    echo -e "\n${CYAN}=== 步驟：設置授權規則和路由 ===${NC}"
    log_message_core "開始執行設置授權規則和路由步驟: 端點=$endpoint_id, VPC CIDR=$vpc_cidr"
    if ! _setup_authorization_and_routes_ec "$endpoint_id" "$vpc_cidr" "$subnet_id" "$aws_region"; then
        echo -e "${RED}設置授權規則和路由失敗，VPN 端點創建過程終止。${NC}"
        log_message_core "錯誤: 設置授權規則和路由失敗，VPN 端點創建過程終止"
        return 1
    fi
    log_message_core "設置授權規則和路由步驟完成成功"

    # 保存配置 - 使用安全的配置更新方法，保留現有設置
    echo -e "${BLUE}保存配置到 \"$main_config_file\"...${NC}" # Quoted $main_config_file
    
    # 創建臨時文件來安全地更新配置
    local temp_config=$(mktemp)
    local config_updated=false
    
    # 如果配置文件存在，讀取並更新現有配置
    if [ -f "$main_config_file" ]; then
        while IFS= read -r line; do
            # 保留空行和註釋
            if [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]]; then
                echo "$line" >> "$temp_config"
                continue
            fi
            
            # 解析配置行
            if [[ "$line" =~ ^([^=]+)=(.*)$ ]]; then
                local key="${BASH_REMATCH[1]}"
                local value="${BASH_REMATCH[2]}"
            else
                # 非標準格式的行，直接保留
                echo "$line" >> "$temp_config"
                continue
            fi
            
            # 更新需要修改的配置項
            case "$key" in
                "ENDPOINT_ID") echo "ENDPOINT_ID=$endpoint_id" >> "$temp_config" ;;
                "AWS_REGION") echo "AWS_REGION=$aws_region" >> "$temp_config" ;;
                "VPN_CIDR") echo "VPN_CIDR=$vpn_cidr" >> "$temp_config" ;;
                "VPN_NAME") echo "VPN_NAME=$vpn_name" >> "$temp_config" ;;
                "SERVER_CERT_ARN") echo "SERVER_CERT_ARN=$arg_server_cert_arn" >> "$temp_config" ;;
                "CLIENT_CERT_ARN") echo "CLIENT_CERT_ARN=$arg_client_cert_arn" >> "$temp_config" ;;
                "VPC_ID") echo "VPC_ID=$vpc_id" >> "$temp_config" ;;
                "VPC_CIDR") echo "VPC_CIDR=$vpc_cidr" >> "$temp_config" ;;
                "SUBNET_ID") echo "SUBNET_ID=$subnet_id" >> "$temp_config" ;;
                "MULTI_VPC_COUNT") echo "MULTI_VPC_COUNT=0" >> "$temp_config" ;;
                *) echo "$key=$value" >> "$temp_config" ;;
            esac
        done < "$main_config_file"
        config_updated=true
    fi
    
    # 如果配置文件不存在或某些必需的配置項缺失，添加它們
    if [ ! -f "$main_config_file" ] || ! grep -q "^ENDPOINT_ID=" "$temp_config" 2>/dev/null; then
        echo "ENDPOINT_ID=$endpoint_id" >> "$temp_config"
    fi
    if ! grep -q "^AWS_REGION=" "$temp_config" 2>/dev/null; then
        echo "AWS_REGION=$aws_region" >> "$temp_config"
    fi
    if ! grep -q "^VPN_CIDR=" "$temp_config" 2>/dev/null; then
        echo "VPN_CIDR=$vpn_cidr" >> "$temp_config"
    fi
    if ! grep -q "^VPN_NAME=" "$temp_config" 2>/dev/null; then
        echo "VPN_NAME=$vpn_name" >> "$temp_config"
    fi
    if ! grep -q "^SERVER_CERT_ARN=" "$temp_config" 2>/dev/null; then
        echo "SERVER_CERT_ARN=$arg_server_cert_arn" >> "$temp_config"
    fi
    if ! grep -q "^CLIENT_CERT_ARN=" "$temp_config" 2>/dev/null; then
        echo "CLIENT_CERT_ARN=$arg_client_cert_arn" >> "$temp_config"
    fi
    if ! grep -q "^VPC_ID=" "$temp_config" 2>/dev/null; then
        echo "VPC_ID=$vpc_id" >> "$temp_config"
    fi
    if ! grep -q "^VPC_CIDR=" "$temp_config" 2>/dev/null; then
        echo "VPC_CIDR=$vpc_cidr" >> "$temp_config"
    fi
    if ! grep -q "^SUBNET_ID=" "$temp_config" 2>/dev/null; then
        echo "SUBNET_ID=$subnet_id" >> "$temp_config"
    fi
    if ! grep -q "^MULTI_VPC_COUNT=" "$temp_config" 2>/dev/null; then
        echo "MULTI_VPC_COUNT=0" >> "$temp_config"
    fi
    
    # 原子性地替換配置文件
    mv "$temp_config" "$main_config_file"
    echo -e "${GREEN}✓ 配置已安全更新，現有設置得到保留${NC}"

    log_message_core "VPN 端點已建立 (lib): $endpoint_id" # Use log_message_core, endpoint_id is a variable
    echo -e "${GREEN}VPN 端點建立完成！${NC}"
    echo -e "端點 ID: ${BLUE}$endpoint_id${NC}" # endpoint_id is a variable

    # 返回 endpoint_id, vpc_id, vpc_cidr, subnet_id, vpn_cidr, vpn_name 以便主腳本後續使用 (例如多VPC關聯)
    # 或者讓主腳本重新 source config file
    # 這裡我們假設主腳本會重新 source config file 或直接使用這些變數 (如果它們是全域的)
    # 為了清晰，返回主要資訊
    echo "ENDPOINT_ID_RESULT=$endpoint_id"
    # 主腳本可以 `eval $(create_vpn_endpoint_lib ...)` 來獲取這個變數
    # 或者，更好的是，主腳本在調用後 source $CONFIG_FILE
}

# 輔助函式：關聯單一 VPC 到現有端點 (內部使用)
# 參數: main_config_file, aws_region, endpoint_id
_associate_one_vpc_to_endpoint_lib() {
    local main_config_file="$1"
    local arg_aws_region="$2"
    local arg_endpoint_id="$3"

    echo -e "\\n${BLUE}準備關聯一個 VPC...${NC}"
    discover_available_vpcs_core "$arg_aws_region"
    
    local vpc_to_add_id
    read -p "請輸入要添加的 VPC ID: " vpc_to_add_id
    
    local vpc_to_add_info
    vpc_to_add_info=$(aws ec2 describe-vpcs --vpc-ids "$vpc_to_add_id" --region "$arg_aws_region" 2>/dev/null)
    if [ $? -ne 0 ]; then
        echo -e "${RED}無法找到 VPC: \"$vpc_to_add_id\" 在區域 \"$arg_aws_region\" ${NC}" # Quoted variables
        return 1 
    fi
    
    local vpc_to_add_cidr
    vpc_to_add_cidr=$(echo "$vpc_to_add_info" | jq -r '.Vpcs[0].CidrBlock')
    echo -e "${BLUE}VPC CIDR: $vpc_to_add_cidr${NC}" # vpc_to_add_cidr is a variable
    
    echo -e "\\n${YELLOW}VPC \"$vpc_to_add_id\" 中的子網路:${NC}" # Quoted variable
    aws ec2 describe-subnets --filters "Name=vpc-id,Values=$vpc_to_add_id" --region "$arg_aws_region" | \
      jq -r '.Subnets[] | "子網路 ID: \(.SubnetId), 可用區: \(.AvailabilityZone), CIDR: \(.CidrBlock), 類型: \(if .MapPublicIpOnLaunch then "公有" else "私有" end)"'
    
    local subnet_to_associate_id
    local max_attempts=5
    local attempts=0
    while [ $attempts -lt $max_attempts ]; do
        read -p "請輸入要關聯的子網路 ID (或輸入 'skip' 跳過): " subnet_to_associate_id
        
        # 允許跳過
        if [ "$subnet_to_associate_id" = "skip" ]; then
            echo -e "${YELLOW}跳過子網路關聯步驟。${NC}"
            return 0
        fi
        
        # 驗證子網路 ID 格式
        if [[ ! "$subnet_to_associate_id" =~ ^subnet-[0-9a-f]{8,17}$ ]]; then
            echo -e "${RED}子網路 ID 格式無效。正確格式應為 'subnet-xxxxxxxxx'。${NC}"
            attempts=$((attempts + 1))
            continue
        fi
        
        # 驗證子網路是否存在
        if aws ec2 describe-subnets --subnet-ids "$subnet_to_associate_id" --filters "Name=vpc-id,Values=$vpc_to_add_id" --region "$arg_aws_region" &>/dev/null; then
            echo -e "${GREEN}✓ 子網路 ID 驗證成功${NC}"
            break
        else
            echo -e "${RED}子網路 ID '$subnet_to_associate_id' 無效、不存在於 VPC '$vpc_to_add_id' 或區域 '$arg_aws_region'。${NC}"
            attempts=$((attempts + 1))
            if [ $attempts -lt $max_attempts ]; then
                echo -e "${YELLOW}請重試 ($attempts/$max_attempts) 或輸入 'skip' 跳過。${NC}"
            fi
        fi
    done
    
    if [ $attempts -eq $max_attempts ]; then
        echo -e "${RED}已達到最大嘗試次數。操作取消。${NC}"
        return 1
    fi
    
    echo -e "${BLUE}關聯子網路到 VPN 端點...${NC}"
    log_message_core "開始執行 AWS CLI 命令: associate-client-vpn-target-network"
    log_message_core "命令參數: endpoint_id=$arg_endpoint_id, subnet_id=$subnet_to_associate_id, region=$arg_aws_region"
    
    local start_time=$(date '+%Y-%m-%d %H:%M:%S')
    local association_result output exit_code
    output=$(aws ec2 associate-client-vpn-target-network \
      --client-vpn-endpoint-id "$arg_endpoint_id" \
      --subnet-id "$subnet_to_associate_id" \
      --region "$arg_aws_region" 2>&1)
    exit_code=$?
    local end_time=$(date '+%Y-%m-%d %H:%M:%S')
    
    log_message_core "AWS CLI 命令執行完成: associate-client-vpn-target-network, exit code: $exit_code, 結束時間: $end_time"
    
    if [ $exit_code -ne 0 ]; then
        echo -e "${RED}關聯子網路 \"$subnet_to_associate_id\" 失敗${NC}"
        log_message_core "錯誤: AWS CLI 命令失敗: associate-client-vpn-target-network"
        log_message_core "錯誤輸出: $output"
        
        # 保存詳細的診斷信息到錯誤日誌文件
        local error_log_file="/tmp/vpn_associate_subnet_error_$(date +%Y%m%d_%H%M%S).log"
        cat > "$error_log_file" << EOF
=== VPN 端點子網路關聯失敗診斷報告 ===
時間: $(date)
函數: _associate_one_vpc_to_endpoint_lib

參數信息:
- VPN Endpoint ID: $arg_endpoint_id
- Subnet ID: $subnet_to_associate_id  
- AWS Region: $arg_aws_region

AWS CLI 命令: 
aws ec2 associate-client-vpn-target-network --client-vpn-endpoint-id "$arg_endpoint_id" --subnet-id "$subnet_to_associate_id" --region "$arg_aws_region"

執行時間:
- 開始時間: $start_time
- 結束時間: $end_time
- Exit Code: $exit_code

錯誤輸出:
$output

建議檢查項目:
1. VPN 端點是否存在且狀態正常
2. 子網路是否存在且可用
3. IAM 權限是否充足
4. 網路配置是否正確
5. AWS 服務狀態是否正常
EOF
        
        log_message_core "錯誤診斷報告已保存到: $error_log_file"
        echo -e "${RED}詳細錯誤信息已記錄到: $error_log_file${NC}"
        return 1
    fi
    
    association_result="$output"
    
    local new_association_id
    new_association_id=$(echo "$association_result" | jq -r '.AssociationId')
    if [ -z "$new_association_id" ] || [ "$new_association_id" == "null" ]; then
        echo -e "${RED}關聯子網路後未能獲取 Association ID: $association_result${NC}" # association_result is a variable
        return 1
    fi
    echo -e "${BLUE}關聯 ID: $new_association_id${NC}" # new_association_id is a variable
    
    echo -e "${BLUE}添加授權規則...${NC}"
    log_message_core "開始執行 AWS CLI 命令: authorize-client-vpn-ingress"
    log_message_core "命令參數: endpoint_id=$arg_endpoint_id, target_network_cidr=$vpc_to_add_cidr, region=$arg_aws_region"
    
    local auth_start_time=$(date '+%Y-%m-%d %H:%M:%S')
    local auth_output auth_exit_code
    auth_output=$(aws ec2 authorize-client-vpn-ingress \
      --client-vpn-endpoint-id "$arg_endpoint_id" \
      --target-network-cidr "$vpc_to_add_cidr" \
      --authorize-all-groups \
      --region "$arg_aws_region" 2>&1)
    auth_exit_code=$?
    local auth_end_time=$(date '+%Y-%m-%d %H:%M:%S')
    
    log_message_core "AWS CLI 命令執行完成: authorize-client-vpn-ingress, exit code: $auth_exit_code, 結束時間: $auth_end_time"
    
    if [ $auth_exit_code -ne 0 ]; then
        echo -e "${RED}為 CIDR \"$vpc_to_add_cidr\" 添加授權規則失敗${NC}"
        log_message_core "錯誤: AWS CLI 命令失敗: authorize-client-vpn-ingress"
        log_message_core "錯誤輸出: $auth_output"
        
        # 保存詳細的診斷信息到錯誤日誌文件
        local auth_error_log_file="/tmp/vpn_authorize_ingress_error_$(date +%Y%m%d_%H%M%S).log"
        cat > "$auth_error_log_file" << EOF
=== VPN 端點授權規則添加失敗診斷報告 ===
時間: $(date)
函數: _associate_one_vpc_to_endpoint_lib

參數信息:
- VPN Endpoint ID: $arg_endpoint_id
- Target Network CIDR: $vpc_to_add_cidr
- AWS Region: $arg_aws_region

AWS CLI 命令:
aws ec2 authorize-client-vpn-ingress --client-vpn-endpoint-id "$arg_endpoint_id" --target-network-cidr "$vpc_to_add_cidr" --authorize-all-groups --region "$arg_aws_region"

執行時間:
- 開始時間: $auth_start_time
- 結束時間: $auth_end_time
- Exit Code: $auth_exit_code

錯誤輸出:
$auth_output

建議檢查項目:
1. VPN 端點是否存在且狀態正常
2. 授權規則是否已存在（重複添加）
3. CIDR 格式是否正確
4. IAM 權限是否充足
5. AWS 服務狀態是否正常
EOF
        
        log_message_core "錯誤診斷報告已保存到: $auth_error_log_file"
        echo -e "${RED}詳細錯誤信息已記錄到: $auth_error_log_file${NC}"
        return 1 
    fi
    

    
    echo -e "${BLUE}創建路由 (允許所有流量通過 VPN 到主要子網路)...${NC}"
    log_message_core "開始創建路由: 端點 ID=$endpoint_id, 子網路 ID=$subnet_id, 區域=$aws_region"
    
    local route_start_time=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${YELLOW}路由創建開始時間: $route_start_time${NC}"
    log_message_core "AWS CLI 命令開始執行: create-client-vpn-route, 開始時間: $route_start_time"
    
    # 執行路由創建 AWS CLI 命令並捕獲輸出和錯誤
    local route_output route_exit_code
    route_output=$(aws ec2 create-client-vpn-route \
      --client-vpn-endpoint-id "$endpoint_id" \
      --destination-cidr-block "0.0.0.0/0" \
      --target-vpc-subnet-id "$subnet_id" \
      --region "$aws_region" 2>&1)
    route_exit_code=$?
    
    local route_end_time=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${YELLOW}路由創建結束時間: $route_end_time${NC}"
    log_message_core "AWS CLI 命令執行完成: create-client-vpn-route, exit code: $route_exit_code, 結束時間: $route_end_time"
    
    if [ $route_exit_code -eq 0 ]; then
        echo -e "${GREEN}✓ 路由創建成功${NC}"
        log_message_core "路由創建成功: $route_output"
    else
        echo -e "${RED}✗ 路由創建失敗${NC}"
        echo -e "${RED}錯誤輸出: $route_output${NC}"
        log_message_core "錯誤: 路由創建失敗 (exit code: $route_exit_code) - $route_output"
        
        # 保存詳細診斷信息
        {
            echo "=== 路由創建失敗診斷報告 ==="
            echo "時間: $(date)"
            echo "Exit Code: $route_exit_code"
            echo "端點 ID: $endpoint_id"
            echo "目標子網路 ID: $subnet_id"
            echo "目標 CIDR: 0.0.0.0/0"
            echo "AWS 區域: $aws_region"
            echo "錯誤輸出: $route_output"
            echo "AWS CLI 版本: $(aws --version 2>&1)"
            echo "當前身份: $(aws sts get-caller-identity --query 'Arn' --output text 2>/dev/null || echo '無法獲取')"
            echo "========================="
        } >> "${LOG_FILE:-vpn_error_diagnostic.log}"
        
        return 1
    fi
    
    return 0
}

# 函式：完整刪除 VPN 端點及所有相關資源
# 參數: aws_region, endpoint_id, vpn_name, config_file_path
terminate_vpn_endpoint_lib() {
    local aws_region="$1"
    local endpoint_id="$2"
    local vpn_name="$3"
    local config_file_path="$4"

    echo -e "\\n${CYAN}=== 刪除 VPN 端點及所有相關資源 (來自 lib) ===${NC}"
    
    if [ -z "$aws_region" ] || [ -z "$endpoint_id" ]; then
        echo -e "${RED}錯誤: terminate_vpn_endpoint_lib 需要 aws_region 和 endpoint_id。${NC}"
        return 1
    fi

    echo -e "${BLUE}當前端點 ID: $endpoint_id${NC}"
    echo -e "${BLUE}當前 AWS 區域: $aws_region${NC}"
    echo -e "${BLUE}VPN 名稱: ${vpn_name:-未提供}${NC}"

    # 步驟 0: 驗證端點是否存在
    echo -e "\\n${YELLOW}步驟 0: 驗證端點存在性...${NC}"
    log_message_core "開始驗證 VPN 端點存在性: $endpoint_id"
    
    local endpoint_check
    endpoint_check=$(aws ec2 describe-client-vpn-endpoints \
        --client-vpn-endpoint-ids "$endpoint_id" \
        --region "$aws_region" 2>&1)
    local check_exit_code=$?
    
    if [ $check_exit_code -ne 0 ]; then
        if echo "$endpoint_check" | grep -q "InvalidClientVpnEndpointId.NotFound"; then
            echo -e "${RED}✗ 端點 ID '$endpoint_id' 不存在${NC}"
            echo -e "${YELLOW}錯誤詳情: $endpoint_check${NC}"
            echo ""
            echo -e "${BLUE}可能的解決方案:${NC}"
            echo -e "1. 檢查端點 ID 是否正確"
            echo -e "2. 確認是否在正確的 AWS 區域"
            echo -e "3. 使用修復工具檢查配置: ./admin-tools/tools/fix_endpoint_id.sh"
            echo -e "4. 查看所有可用端點: aws ec2 describe-client-vpn-endpoints --region $aws_region"
            log_message_core "錯誤: VPN 端點不存在: $endpoint_id"
            return 1
        else
            echo -e "${RED}✗ 無法驗證端點存在性${NC}"
            echo -e "${RED}錯誤: $endpoint_check${NC}"
            log_message_core "錯誤: 無法驗證端點存在性: $endpoint_check"
            return 1
        fi
    fi
    
    local endpoint_status
    endpoint_status=$(echo "$endpoint_check" | jq -r '.ClientVpnEndpoints[0].Status.Code' 2>/dev/null)
    
    if [ -z "$endpoint_status" ] || [ "$endpoint_status" = "null" ]; then
        echo -e "${RED}✗ 無法獲取端點狀態${NC}"
        return 1
    fi
    
    echo -e "${GREEN}✓ 端點驗證成功，當前狀態: $endpoint_status${NC}"
    log_message_core "端點驗證成功: $endpoint_id, 狀態: $endpoint_status"

    # 步驟 1: 刪除所有授權規則
    echo -e "\\n${YELLOW}步驟 1: 刪除所有授權規則...${NC}"
    log_message_core "開始刪除 VPN 端點的所有授權規則: $endpoint_id"
    
    local auth_rules_json
    auth_rules_json=$(aws ec2 describe-client-vpn-authorization-rules \
        --client-vpn-endpoint-id "$endpoint_id" \
        --region "$aws_region" 2>/dev/null)
    
    if [ $? -eq 0 ] && [ -n "$auth_rules_json" ]; then
        local auth_rules_count
        auth_rules_count=$(echo "$auth_rules_json" | jq '.AuthorizationRules | length' 2>/dev/null)
        
        if [ -n "$auth_rules_count" ] && [ "$auth_rules_count" -gt 0 ]; then
            echo -e "${BLUE}找到 $auth_rules_count 個授權規則，正在刪除...${NC}"
            
            # 刪除除了默認規則外的所有授權規則
            echo "$auth_rules_json" | jq -r '.AuthorizationRules[] | select(.Status.Code != "revoking") | "\(.TargetNetworkCidr)"' | while read -r cidr; do
                if [ -n "$cidr" ] && [ "$cidr" != "null" ]; then
                    echo -e "${YELLOW}刪除授權規則: $cidr${NC}"
                    aws ec2 revoke-client-vpn-ingress \
                        --client-vpn-endpoint-id "$endpoint_id" \
                        --target-network-cidr "$cidr" \
                        --revoke-all-groups \
                        --region "$aws_region" 2>/dev/null || {
                        echo -e "${YELLOW}警告: 無法刪除授權規則 $cidr (可能已被刪除)${NC}"
                    }
                fi
            done
        else
            echo -e "${GREEN}沒有授權規則需要刪除${NC}"
        fi
    else
        echo -e "${YELLOW}警告: 無法獲取授權規則信息，繼續進行${NC}"
    fi

    # 步驟 2: 解除所有 VPC 關聯
    echo -e "\\n${YELLOW}步驟 2: 解除所有 VPC 關聯...${NC}"
    log_message_core "開始解除 VPN 端點的所有 VPC 關聯: $endpoint_id"
    
    local networks_json
    networks_json=$(aws ec2 describe-client-vpn-target-networks \
        --client-vpn-endpoint-id "$endpoint_id" \
        --region "$aws_region" 2>/dev/null)
    
    if [ $? -eq 0 ] && [ -n "$networks_json" ]; then
        local networks_count
        networks_count=$(echo "$networks_json" | jq '.ClientVpnTargetNetworks | length' 2>/dev/null)
        
        if [ -n "$networks_count" ] && [ "$networks_count" -gt 0 ]; then
            echo -e "${BLUE}找到 $networks_count 個網絡關聯，正在解除...${NC}"
            
            # 解除所有網絡關聯
            echo "$networks_json" | jq -r '.ClientVpnTargetNetworks[] | select(.Status.Code != "disassociating" and .Status.Code != "disassociated") | "\(.AssociationId)"' | while read -r assoc_id; do
                if [ -n "$assoc_id" ] && [ "$assoc_id" != "null" ]; then
                    echo -e "${YELLOW}解除關聯: $assoc_id${NC}"
                    aws ec2 disassociate-client-vpn-target-network \
                        --client-vpn-endpoint-id "$endpoint_id" \
                        --association-id "$assoc_id" \
                        --region "$aws_region" >/dev/null 2>&1 || {
                        echo -e "${YELLOW}警告: 無法解除關聯 $assoc_id (可能已被解除)${NC}"
                    }
                fi
            done
            
            # 等待所有關聯解除完成
            echo -e "${BLUE}等待所有關聯解除完成...${NC}"
            local wait_attempts=0
            local max_wait_attempts=30
            
            while [ $wait_attempts -lt $max_wait_attempts ]; do
                local current_networks
                current_networks=$(aws ec2 describe-client-vpn-target-networks \
                    --client-vpn-endpoint-id "$endpoint_id" \
                    --region "$aws_region" \
                    --query 'ClientVpnTargetNetworks[?Status.Code!=`disassociated`] | length(@)' \
                    --output text 2>/dev/null)
                
                if [ "$current_networks" = "0" ]; then
                    echo -e "${GREEN}所有關聯已成功解除${NC}"
                    break
                fi
                
                echo -e "${YELLOW}仍有 $current_networks 個關聯尚未解除，等待中... ($((wait_attempts + 1))/$max_wait_attempts)${NC}"
                sleep 10
                ((wait_attempts++))
            done
            
            if [ $wait_attempts -eq $max_wait_attempts ]; then
                echo -e "${YELLOW}警告: 等待關聯解除超時，繼續進行端點刪除${NC}"
            fi
        else
            echo -e "${GREEN}沒有網絡關聯需要解除${NC}"
        fi
    else
        echo -e "${YELLOW}警告: 無法獲取網絡關聯信息，繼續進行${NC}"
    fi

    # 步驟 3: 刪除 VPN 端點
    echo -e "\\n${YELLOW}步驟 3: 刪除 VPN 端點...${NC}"
    log_message_core "開始刪除 VPN 端點: $endpoint_id"
    
    echo -e "${BLUE}正在刪除 VPN 端點 $endpoint_id...${NC}"
    
    local delete_output delete_exit_code
    delete_output=$(aws ec2 delete-client-vpn-endpoint \
        --client-vpn-endpoint-id "$endpoint_id" \
        --region "$aws_region" 2>&1)
    delete_exit_code=$?
    
    if [ $delete_exit_code -eq 0 ]; then
        echo -e "${GREEN}✓ VPN 端點刪除命令已成功執行${NC}"
        log_message_core "VPN 端點刪除命令成功: $endpoint_id"
        
        # 等待端點刪除完成
        echo -e "${BLUE}等待端點刪除完成...${NC}"
        local delete_wait_attempts=0
        local max_delete_attempts=20
        
        while [ $delete_wait_attempts -lt $max_delete_attempts ]; do
            local endpoint_status
            endpoint_status=$(aws ec2 describe-client-vpn-endpoints \
                --client-vpn-endpoint-ids "$endpoint_id" \
                --region "$aws_region" \
                --query 'ClientVpnEndpoints[0].Status.Code' \
                --output text 2>/dev/null)
            
            if [ $? -ne 0 ] || [ "$endpoint_status" = "None" ] || [ -z "$endpoint_status" ]; then
                echo -e "${GREEN}✓ VPN 端點已成功刪除${NC}"
                break
            fi
            
            if [ "$endpoint_status" = "deleted" ]; then
                echo -e "${GREEN}✓ VPN 端點狀態確認為已刪除${NC}"
                break
            fi
            
            echo -e "${YELLOW}端點狀態: $endpoint_status，等待中... ($((delete_wait_attempts + 1))/$max_delete_attempts)${NC}"
            sleep 15
            ((delete_wait_attempts++))
        done
    else
        echo -e "${RED}✗ VPN 端點刪除失敗${NC}"
        echo -e "${RED}錯誤信息: $delete_output${NC}"
        log_message_core "錯誤: VPN 端點刪除失敗: $delete_output"
        return 1
    fi

    # 步驟 4: 刪除 CloudWatch 日誌組（如果提供了 VPN 名稱）
    if [ -n "$vpn_name" ] && [ "$vpn_name" != "null" ]; then
        echo -e "\\n${YELLOW}步驟 4: 刪除 CloudWatch 日誌組...${NC}"
        log_message_core "開始刪除 CloudWatch 日誌組: /aws/clientvpn/$vpn_name"
        
        local log_group_name="/aws/clientvpn/$vpn_name"
        
        # 檢查日誌組是否存在
        local log_group_exists
        log_group_exists=$(aws logs describe-log-groups \
            --log-group-name-prefix "$log_group_name" \
            --query "logGroups[?logGroupName=='$log_group_name'] | length(@)" \
            --output text 2>/dev/null)
        
        if [ "$log_group_exists" = "1" ]; then
            echo -e "${BLUE}正在刪除日誌組: $log_group_name${NC}"
            
            local log_delete_output log_delete_exit_code
            log_delete_output=$(aws logs delete-log-group \
                --log-group-name "$log_group_name" 2>&1)
            log_delete_exit_code=$?
            
            if [ $log_delete_exit_code -eq 0 ]; then
                echo -e "${GREEN}✓ CloudWatch 日誌組已成功刪除${NC}"
                log_message_core "CloudWatch 日誌組刪除成功: $log_group_name"
            else
                echo -e "${YELLOW}警告: 無法刪除 CloudWatch 日誌組: $log_delete_output${NC}"
                log_message_core "警告: CloudWatch 日誌組刪除失敗: $log_delete_output"
            fi
        else
            echo -e "${GREEN}沒有找到對應的 CloudWatch 日誌組${NC}"
        fi
    else
        echo -e "\\n${YELLOW}步驟 4: 跳過日誌組刪除（未提供 VPN 名稱）${NC}"
    fi

    # 步驟 5: 清理配置文件
    if [ -n "$config_file_path" ] && [ -f "$config_file_path" ]; then
        echo -e "\\n${YELLOW}步驟 5: 清理配置文件...${NC}"
        log_message_core "開始清理配置文件: $config_file_path"
        
        # 備份當前配置
        local config_backup="${config_file_path}.backup_$(date +%Y%m%d_%H%M%S)"
        cp "$config_file_path" "$config_backup"
        echo -e "${BLUE}配置文件已備份到: $config_backup${NC}"
        
        # 創建清理後的配置文件
        local temp_config
        temp_config=$(mktemp)
        
        # 保留基本配置，清除端點相關信息
        while IFS= read -r line; do
            if [[ "$line" =~ ^VPN_ENDPOINT_ID= ]]; then
                echo "VPN_ENDPOINT_ID="
            elif [[ "$line" =~ ^MULTI_VPC_COUNT= ]]; then
                echo "MULTI_VPC_COUNT=0"
            elif [[ "$line" =~ ^MULTI_VPC_[0-9]+= ]]; then
                # 跳過多 VPC 條目
                continue
            else
                echo "$line"
            fi
        done < "$config_file_path" > "$temp_config"
        
        mv "$temp_config" "$config_file_path"
        echo -e "${GREEN}✓ 配置文件已清理${NC}"
        log_message_core "配置文件清理完成: $config_file_path"
    else
        echo -e "\\n${YELLOW}步驟 5: 跳過配置文件清理（文件不存在或未提供路徑）${NC}"
    fi

    echo -e "\\n${GREEN}=== VPN 端點刪除完成 ===${NC}"
    echo -e "${GREEN}所有相關資源已成功清理${NC}"
    log_message_core "VPN 端點完整刪除操作完成: $endpoint_id"
    
    return 0
}
