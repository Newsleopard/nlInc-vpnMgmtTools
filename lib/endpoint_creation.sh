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
    
    # 創建專用的 Client VPN 安全群組
    echo -e "\\n${BLUE}正在設定 Client VPN 專用安全群組...${NC}" >&2
    
    # 從當前環境獲取環境名稱
    local environment_name="$CURRENT_ENVIRONMENT"
    if [ -z "$environment_name" ]; then
        environment_name="default"
    fi
    
    # 創建專用安全群組
    local client_vpn_sg_id
    client_vpn_sg_id=$(create_dedicated_client_vpn_security_group "$vpc_id" "$aws_region" "$environment_name")
    
    if [ $? -ne 0 ] || [ -z "$client_vpn_sg_id" ]; then
        echo -e "${RED}錯誤: 無法創建專用的 Client VPN 安全群組${NC}" >&2
        echo -e "${YELLOW}回退到手動選擇安全群組模式...${NC}" >&2
        
        # 回退到原有的手動選擇模式
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
        
        # 在手動選擇模式下，如果用戶選擇了security groups，使用第一個作為client_vpn_sg_id
        if [ -n "$security_groups" ]; then
            client_vpn_sg_id=$(echo $security_groups | awk '{print $1}')
        else
            client_vpn_sg_id=""
        fi
    else
        # 使用新創建的專用安全群組
        security_groups="$client_vpn_sg_id"
        echo -e "${GREEN}✓ 已創建並將使用專用 Client VPN 安全群組: $client_vpn_sg_id${NC}" >&2
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
            --arg client_vpn_sg_id "$client_vpn_sg_id" \
            '{vpc_id: $vpc_id, subnet_id: $subnet_id, vpn_cidr: $vpn_cidr, vpn_name: $vpn_name, security_groups: $security_groups, client_vpn_sg_id: $client_vpn_sg_id}')
    else
        # 備用方法：手動構建 JSON
        result_json="{\"vpc_id\":\"$vpc_id\",\"subnet_id\":\"$subnet_id\",\"vpn_cidr\":\"$vpn_cidr\",\"vpn_name\":\"$vpn_name\",\"security_groups\":\"$security_groups\",\"client_vpn_sg_id\":\"$client_vpn_sg_id\"}"
    fi

    log_message_core "VPC/子網路詳細資訊獲取完成: VPC=$vpc_id, Subnet=$subnet_id, VPN_CIDR=$vpn_cidr, VPN_Name=$vpn_name, SecurityGroups=$security_groups, ClientVpnSgId=$client_vpn_sg_id"
    
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

# 輔助函式：立即保存端點基本配置 (防止後續步驟失敗)
# 參數: $1=config_file, $2=endpoint_id, $3=sg_id, $4=server_cert_arn, $5=ca_cert_arn, $6=vpc_id, $7=subnet_id, $8=vpn_cidr, $9=vpn_name, $10=vpc_cidr
# 注意: $5 是 CA 證書 ARN (來自 import_certificates_to_acm_lib 的 client_cert_arn)
save_initial_endpoint_config() {
    local config_file="$1"
    local endpoint_id="$2"
    local sg_id="$3"
    local server_cert_arn="$4"
    local ca_cert_arn="$5"
    local vpc_id="$6"
    local subnet_id="$7"
    local vpn_cidr="$8"
    local vpn_name="$9"
    local vpc_cidr="${10}"
    
    # 參數驗證
    if [ -z "$config_file" ] || [ -z "$endpoint_id" ]; then
        log_message_core "錯誤: save_initial_endpoint_config 缺少必要參數"
        return 1
    fi
    
    # 創建端點配置文件內容
    cat > "$config_file" << EOF
# VPN Endpoint Specific Configuration
# Contains only endpoint-specific and certificate management settings
# Basic network config moved to ${CURRENT_ENVIRONMENT:-staging}.env to eliminate duplication
# Updated: $(date '+%Y年 %m月%d日')

# ====================================================================
# CERTIFICATE MANAGEMENT CONFIGURATION
# ====================================================================

# EasyRSA 工具配置
EASYRSA_DIR=/opt/homebrew/opt/easy-rsa/libexec
SERVER_CERT_NAME_PREFIX=server
CLIENT_CERT_NAME_PREFIX=client

# ====================================================================
# VPN ENDPOINT CONFIGURATION - AUTO-GENERATED
# ====================================================================

# VPN Endpoint ID (generated when endpoint is created)
ENDPOINT_ID="$endpoint_id"

# Dedicated Client VPN Security Group ID (auto-generated during endpoint creation)
CLIENT_VPN_SECURITY_GROUP_ID="${sg_id:-}"

# ====================================================================
# CERTIFICATE ARNs - AUTO-GENERATED/IMPORTED
# ====================================================================

# AWS Certificate Manager ARNs (generated during certificate import)
CA_CERT_ARN="$ca_cert_arn"
SERVER_CERT_ARN="$server_cert_arn"
CLIENT_CERT_ARN=""
CLIENT_CERT_ARN_admin=""

# ====================================================================
# VPC RUNTIME CONFIGURATION
# ====================================================================

# VPC 實際 CIDR（從 AWS 查詢得到，與 VPN_CIDR 不同）
VPC_CIDR="${vpc_cidr:-}"

# 多 VPC 配置
MULTI_VPC_COUNT=0
VPC_ID="${vpc_id:-}"
SUBNET_ID="${subnet_id:-}"
VPN_CIDR="${vpn_cidr:-}"
VPN_NAME=${vpn_name:-}
SECURITY_GROUPS="${sg_id:-}"
EOF
    
    return $?
}

# 輔助函式：創建專用的 Client VPN 安全群組
# 參數: $1 = VPC ID, $2 = AWS REGION, $3 = ENVIRONMENT (staging/production)
# 返回: 安全群組 ID 或錯誤
create_dedicated_client_vpn_security_group() {
    local vpc_id="$1"
    local aws_region="$2"
    local environment="$3"
    
    # 參數驗證
    if [ -z "$vpc_id" ] || [ -z "$aws_region" ] || [ -z "$environment" ]; then
        echo -e "${RED}錯誤: create_dedicated_client_vpn_security_group 缺少必要參數${NC}" >&2
        return 1
    fi
    
    # 驗證 VPC 存在
    if ! aws ec2 describe-vpcs --vpc-ids "$vpc_id" --region "$aws_region" >/dev/null 2>&1; then
        echo -e "${RED}錯誤: VPC '$vpc_id' 不存在於區域 '$aws_region'${NC}" >&2
        return 1
    fi
    
    # 生成安全群組名稱和描述
    local sg_name="client-vpn-sg-${environment}"
    local sg_description="Dedicated security group for Client VPN users - ${environment} environment"
    
    echo -e "${BLUE}正在創建專用的 Client VPN 安全群組...${NC}" >&2
    echo -e "${YELLOW}安全群組名稱: $sg_name${NC}" >&2
    echo -e "${YELLOW}VPC ID: $vpc_id${NC}" >&2
    echo -e "${YELLOW}區域: $aws_region${NC}" >&2
    
    # 檢查是否已存在同名安全群組
    local existing_sg_id
    existing_sg_id=$(aws ec2 describe-security-groups \
        --filters "Name=group-name,Values=$sg_name" "Name=vpc-id,Values=$vpc_id" \
        --region "$aws_region" \
        --query 'SecurityGroups[0].GroupId' \
        --output text 2>/dev/null)
    
    if [ "$existing_sg_id" != "None" ] && [ -n "$existing_sg_id" ]; then
        echo -e "${YELLOW}警告: 安全群組 '$sg_name' 已存在 (ID: $existing_sg_id)${NC}" >&2
        echo -e "${BLUE}是否要使用現有的安全群組？ (y/n): ${NC}" >&2
        read -r use_existing
        if [[ "$use_existing" =~ ^[Yy]$ ]]; then
            echo "$existing_sg_id"
            return 0
        else
            echo -e "${YELLOW}請手動刪除現有安全群組或選擇不同的名稱${NC}" >&2
            return 1
        fi
    fi
    
    # 創建安全群組
    local sg_result
    sg_result=$(aws ec2 create-security-group \
        --group-name "$sg_name" \
        --description "$sg_description" \
        --vpc-id "$vpc_id" \
        --region "$aws_region" \
        --output text 2>&1)
    
    if [ $? -ne 0 ]; then
        echo -e "${RED}錯誤: 創建安全群組失敗${NC}" >&2
        echo -e "${RED}AWS 回應: $sg_result${NC}" >&2
        return 1
    fi
    
    # 提取安全群組 ID
    local new_sg_id
    new_sg_id=$(echo "$sg_result" | grep -o 'sg-[0-9a-f]*' | head -1)
    
    if [ -z "$new_sg_id" ]; then
        echo -e "${RED}錯誤: 無法提取新創建的安全群組 ID${NC}" >&2
        return 1
    fi
    
    echo -e "${GREEN}✓ 安全群組創建成功: $new_sg_id${NC}" >&2
    
    # 設定標籤
    aws ec2 create-tags \
        --resources "$new_sg_id" \
        --tags Key=Name,Value="$sg_name" \
               Key=Environment,Value="$environment" \
               Key=Purpose,Value="Client-VPN" \
               Key=ManagedBy,Value="VPN-Management-Toolkit" \
        --region "$aws_region" >/dev/null 2>&1
    
    # 配置安全群組規則 - 允許所有出站流量
    echo -e "${BLUE}正在配置安全群組規則...${NC}" >&2
    
    # 刪除預設的出站規則（如果存在）
    aws ec2 revoke-security-group-egress \
        --group-id "$new_sg_id" \
        --protocol -1 \
        --cidr 0.0.0.0/0 \
        --region "$aws_region" >/dev/null 2>&1
    
    # 添加允許所有出站流量的規則
    local egress_result
    egress_result=$(aws ec2 authorize-security-group-egress \
        --group-id "$new_sg_id" \
        --protocol -1 \
        --cidr 0.0.0.0/0 \
        --region "$aws_region" 2>&1)
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓ 出站規則配置成功 (允許所有流量)${NC}" >&2
    else
        echo -e "${YELLOW}警告: 配置出站規則時出現問題: $egress_result${NC}" >&2
    fi
    
    # 返回安全群組 ID
    echo "$new_sg_id"
    return 0
}

# 輔助函式：提示用戶更新現有安全群組以允許 Client VPN 訪問
# 參數: $1 = Client VPN Security Group ID, $2 = AWS REGION, $3 = Environment (optional)
prompt_update_existing_security_groups() {
    local client_vpn_sg_id="$1"
    local aws_region="$2"
    local env_name="$3"
    
    if [ -z "$client_vpn_sg_id" ] || [ -z "$aws_region" ]; then
        echo -e "${RED}錯誤: prompt_update_existing_security_groups 缺少必要參數${NC}" >&2
        log_message_core "錯誤: prompt_update_existing_security_groups 缺少必要參數 - client_vpn_sg_id='$client_vpn_sg_id', aws_region='$aws_region'"
        return 1
    fi
    
    echo -e "\\n${CYAN}=== Client VPN 安全群組設定完成 ===${NC}" >&2
    echo -e "${GREEN}✓ 已創建專用的 Client VPN 安全群組: $client_vpn_sg_id${NC}" >&2
    echo -e "${BLUE}該安全群組已配置為允許所有出站流量，提供基本的網路連接能力。${NC}" >&2
    log_message_core "Client VPN 安全群組創建完成: $client_vpn_sg_id"
    
    echo -e "\\n${YELLOW}=== 下一步：自動配置 VPN 服務訪問權限 ===${NC}" >&2
    echo -e "${BLUE}正在使用 manage_vpn_service_access.sh 自動發現並配置服務訪問...${NC}" >&2
    log_message_core "開始自動配置 VPN 服務訪問權限: client_vpn_sg_id=$client_vpn_sg_id, region=$aws_region"
    
    # 獲取專案根目錄和 VPN 服務訪問腳本路徑
    local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    local project_root="$(dirname "$script_dir")"
    local vpn_service_script="$project_root/admin-tools/manage_vpn_service_access.sh"
    
    # 檢查 VPN 服務訪問管理腳本是否存在
    if [ ! -f "$vpn_service_script" ]; then
        log_message_core "警告: manage_vpn_service_access.sh 不存在，回退到手動配置"
        echo -e "${YELLOW}⚠️  VPN 服務訪問管理腳本不存在，請手動配置安全群組規則${NC}" >&2
        echo -e "${BLUE}預期路徑: $vpn_service_script${NC}" >&2
        echo -e "${YELLOW}請稍後手動運行: ./admin-tools/manage_vpn_service_access.sh create $client_vpn_sg_id --region $aws_region${NC}" >&2
        return 1
    fi
    
    echo -e "\\n${CYAN}=== 自動 VPN 服務訪問配置 ===${NC}" >&2
    
    # 步驟 1: 服務發現和預覽
    echo -e "\\n${YELLOW}🔍 步驟 1: 發現當前環境中的服務...${NC}" >&2
    log_message_core "執行服務發現: $vpn_service_script discover --region $aws_region"
    
    if ! "$vpn_service_script" discover --region "$aws_region"; then
        log_message_core "警告: VPN 服務發現失敗，回退到手動配置"
        echo -e "${YELLOW}⚠️  服務發現失敗，建議稍後手動運行：${NC}" >&2
        echo -e "${BLUE}$vpn_service_script discover --region $aws_region${NC}" >&2
        return 1
    fi
    
    # 步驟 2: 預覽即將創建的規則
    echo -e "\\n${YELLOW}🔍 步驟 2: 預覽即將創建的 VPN 服務訪問規則...${NC}" >&2
    log_message_core "執行規則預覽: $vpn_service_script create $client_vpn_sg_id --region $aws_region --dry-run"
    
    if ! "$vpn_service_script" create "$client_vpn_sg_id" --region "$aws_region" --dry-run; then
        log_message_core "警告: VPN 服務訪問規則預覽失敗，繼續手動配置"
        echo -e "${YELLOW}⚠️  規則預覽失敗，建議稍後手動運行：${NC}" >&2
        echo -e "${BLUE}$vpn_service_script create $client_vpn_sg_id --region $aws_region${NC}" >&2
        return 1
    fi
    
    # 步驟 3: 詢問用戶是否執行自動配置
    echo -e "\\n${CYAN}🚀 步驟 3: 是否自動執行上述 VPN 服務訪問規則配置？${NC}" >&2
    echo -e "${YELLOW}[y] 是，自動配置所有服務訪問規則${NC}" >&2
    echo -e "${YELLOW}[n] 否，稍後手動配置${NC}" >&2
    echo -e "${YELLOW}[s] 跳過，我會自己處理${NC}" >&2
    
    local choice
    local max_attempts=3
    local attempts=0
    
    while [ $attempts -lt $max_attempts ]; do
        echo -n "請選擇 [y/n/s]: " >&2
        read choice
        case "$choice" in
            [Yy]* )
                echo -e "\\n${GREEN}✅ 開始自動配置 VPN 服務訪問規則...${NC}" >&2
                log_message_core "用戶選擇自動配置，開始執行: $vpn_service_script create $client_vpn_sg_id --region $aws_region"
                
                if "$vpn_service_script" create "$client_vpn_sg_id" --region "$aws_region"; then
                    echo -e "\\n${GREEN}🎉 VPN 服務訪問規則配置完成！${NC}" >&2
                    log_message_core "VPN 服務訪問規則自動配置成功"
                    
                    echo -e "\\n${CYAN}=== 配置摘要 ===${NC}" >&2
                    echo -e "${GREEN}• 已自動發現並配置所有服務安全群組${NC}" >&2
                    echo -e "${GREEN}• VPN 用戶現在可以訪問 MySQL/RDS、Redis、HBase、EKS 等服務${NC}" >&2
                    echo -e "${GREEN}• 遵循最小權限原則，安全且高效${NC}" >&2
                    
                    # 顯示如何撤銷規則的資訊
                    echo -e "\\n${BLUE}💡 如需撤銷 VPN 訪問規則，請運行：${NC}" >&2
                    echo -e "${DIM}$vpn_service_script remove $client_vpn_sg_id --region $aws_region${NC}" >&2
                    
                    log_message_core "VPN 服務訪問配置完成，提供撤銷指令: remove $client_vpn_sg_id --region $aws_region"
                    return 0
                else
                    echo -e "\\n${RED}❌ VPN 服務訪問規則配置失敗${NC}" >&2
                    log_message_core "VPN 服務訪問規則自動配置失敗"
                    echo -e "${YELLOW}請稍後手動運行以下命令：${NC}" >&2
                    echo -e "${BLUE}$vpn_service_script create $client_vpn_sg_id --region $aws_region${NC}" >&2
                    return 1
                fi
                ;;
            [Nn]* )
                echo -e "\\n${YELLOW}⏭️  跳過自動配置，稍後請手動運行：${NC}" >&2
                echo -e "${BLUE}$vpn_service_script create $client_vpn_sg_id --region $aws_region${NC}" >&2
                log_message_core "用戶選擇跳過自動配置，提供手動配置指令"
                return 0
                ;;
            [Ss]* )
                echo -e "\\n${BLUE}✅ 用戶選擇自行處理 VPN 服務訪問配置${NC}" >&2
                log_message_core "用戶選擇自行處理 VPN 服務訪問配置"
                return 0
                ;;
            * )
                echo -e "${RED}請輸入 y、n 或 s${NC}" >&2
                attempts=$((attempts + 1))
                if [ $attempts -eq $max_attempts ]; then
                    echo -e "${YELLOW}輸入次數過多，默認跳過自動配置${NC}" >&2
                    log_message_core "用戶輸入次數過多，默認跳過自動配置"
                    return 0
                fi
                ;;
        esac
    done
    
    # 顯示增強的安全優勢說明
    echo -e "\\n${CYAN}=== 自動化 VPN 服務訪問的安全優勢 ===${NC}" >&2
    echo -e "${BLUE}這種自動化方法更清潔且更安全，因為：${NC}" >&2
    echo -e "${GREEN}• Client VPN 用戶被隔離在專用安全群組中${NC}" >&2
    echo -e "${GREEN}• 自動發現服務，無需維護硬編碼安全群組 ID${NC}" >&2
    echo -e "${GREEN}• 支援 dry-run 預覽，避免意外配置${NC}" >&2
    echo -e "${GREEN}• 遵循最小權限原則，具有更好的安全姿態${NC}" >&2
    echo -e "${GREEN}• 更容易審計和故障排除${NC}" >&2
    echo -e "${GREEN}• 支援跨環境使用（staging/production）${NC}" >&2
    echo -e "${GREEN}• 可輕鬆撤銷所有 VPN 訪問規則${NC}" >&2
    
    # 提供額外的管理指令
    echo -e "\\n${BLUE}💡 常用 VPN 服務訪問管理指令：${NC}" >&2
    echo -e "${DIM}# 發現服務${NC}" >&2
    echo -e "${DIM}$vpn_service_script discover --region $aws_region${NC}" >&2
    echo -e "${DIM}# 創建 VPN 訪問規則${NC}" >&2  
    echo -e "${DIM}$vpn_service_script create $client_vpn_sg_id --region $aws_region${NC}" >&2
    echo -e "${DIM}# 撤銷 VPN 訪問規則${NC}" >&2
    echo -e "${DIM}$vpn_service_script remove $client_vpn_sg_id --region $aws_region${NC}" >&2
    
    log_message_core "VPN 服務訪問權限配置步驟完成"
    return 0
}

# 輔助函式：創建 AWS Client VPN 端點實體
_create_aws_client_vpn_endpoint_ec() {
    local vpn_cidr="$1"
    local server_cert_arn="$2"
    local client_cert_arn="$3"
    local vpn_name="$4"
    local aws_region="$5"
    local security_groups="$6"
    local vpc_id="$7"

    # 參數驗證
    if [ -z "$vpn_cidr" ] || [ -z "$server_cert_arn" ] || [ -z "$client_cert_arn" ] || [ -z "$vpn_name" ] || [ -z "$aws_region" ]; then
        echo -e "${RED}錯誤: _create_aws_client_vpn_endpoint_ec 缺少必要參數${NC}" >&2
        return 1
    fi
    
    # 清理 VPN 名稱以用於日誌群組 (只允許字母、數字、連字符和斜線)
    local clean_log_name=$(echo "$vpn_name" | sed 's/[^a-zA-Z0-9/_-]/-/g' | sed 's/--*/-/g' | sed 's/^-\|-$//g')
    local log_group_name="/aws/clientvpn/$clean_log_name"
    echo -e "${BLUE}創建 CloudWatch 日誌群組: $log_group_name${NC}" >&2
    
    # TEMPORARY FIX: Skip CloudWatch logging to isolate the issue
    echo -e "${YELLOW}暫時跳過 CloudWatch 日誌設定以便排除問題${NC}" >&2
    log_group_name=""
    
    # 檢查日誌群組是否已存在 (已跳過)
    if false; then  # Disabled for debugging
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
    auth_options=$(jq -n \
        --arg cert_arn "$client_cert_arn" \
        '{
            "Type": "certificate-authentication",
            "MutualAuthentication": {
                "ClientRootCertificateChainArn": $cert_arn
            }
        }')
    
    # 建構 connection-log-options JSON (只有當日誌群組存在時才啟用)
    if [ -n "$log_group_name" ]; then
        log_options=$(jq -n \
            --arg log_group "$log_group_name" \
            '{
                "Enabled": true,
                "CloudwatchLogGroup": $log_group
            }')
        echo -e "${GREEN}啟用 CloudWatch 日誌記錄${NC}" >&2
    else
        log_options=$(jq -n \
            '{
                "Enabled": false
            }')
        echo -e "${YELLOW}禁用 CloudWatch 日誌記錄${NC}" >&2
    fi
    
    # 建構 tag-specifications JSON
    tag_specs=$(jq -n \
        --arg vpn_name "$clean_vpn_name" \
        '[{
            "ResourceType": "client-vpn-endpoint",
            "Tags": [
                {"Key": "Name", "Value": $vpn_name},
                {"Key": "Purpose", "Value": "VPNManagement"}
            ]
        }]')
    
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
    
    # Debug: Show the exact JSON parameters
    echo -e "${YELLOW}Debug - JSON Parameters:${NC}" >&2
    echo "auth_options: $auth_options" >&2
    echo "log_options: $log_options" >&2
    echo "tag_specs: $tag_specs" >&2
    
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
              --vpc-id "$vpc_id" \
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
              --vpc-id "$vpc_id" \
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

# 輔助函式：生成安全群組配置指令文件
# 參數: $1 = Client VPN Security Group ID, $2 = AWS REGION, $3 = Environment
generate_security_group_commands_file() {
    local client_vpn_sg_id="$1"
    local aws_region="$2"
    local environment="$3"
    
    if [ -z "$client_vpn_sg_id" ] || [ -z "$aws_region" ] || [ -z "$environment" ]; then
        echo -e "${RED}錯誤: generate_security_group_commands_file 缺少必要參數${NC}" >&2
        return 1
    fi
    
    # 生成文件名（包含環境和時間戳）
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local filename="vpn_security_group_setup_${environment}_${timestamp}.sh"
    local output_file="${TOOL_ROOT:-$(pwd)}/${filename}"
    
    echo -e "${BLUE}正在生成安全群組配置指令文件: $filename${NC}" >&2
    
    # 創建腳本文件頭部
    cat > "$output_file" << 'HEADER_EOF'
#!/bin/bash
# VPN 安全群組配置指令
# 此腳本包含創建 VPN 端點後需要執行的安全群組更新指令
# 即使控制台日誌消失，您也可以使用此腳本來配置服務訪問權限
HEADER_EOF

    # 添加動態內容
    cat >> "$output_file" << EOF
# 生成時間: $(date)
# 環境: $environment
# Client VPN 安全群組 ID: $client_vpn_sg_id
# AWS 區域: $aws_region

set -e

echo "=== 安全群組更新指令 ==="
echo "請執行以下 AWS CLI 指令來配置服務訪問權限："
echo ""

# MySQL/RDS 訪問
aws ec2 authorize-security-group-ingress \\
    --group-id sg-503f5e1b \\
    --protocol tcp \\
    --port 3306 \\
    --source-group $client_vpn_sg_id \\
    --region $aws_region

# HBase Master Web UI
aws ec2 authorize-security-group-ingress \\
    --group-id sg-503f5e1b \\
    --protocol tcp \\
    --port 16010 \\
    --source-group $client_vpn_sg_id \\
    --region $aws_region

# HBase RegionServer
aws ec2 authorize-security-group-ingress \\
    --group-id sg-503f5e1b \\
    --protocol tcp \\
    --port 16020 \\
    --source-group $client_vpn_sg_id \\
    --region $aws_region

# Custom HBase port (8765)
aws ec2 authorize-security-group-ingress \\
    --group-id sg-503f5e1b \\
    --protocol tcp \\
    --port 8765 \\
    --source-group $client_vpn_sg_id \\
    --region $aws_region

# Redis 訪問
aws ec2 authorize-security-group-ingress \\
    --group-id sg-503f5e1b \\
    --protocol tcp \\
    --port 6379 \\
    --source-group $client_vpn_sg_id \\
    --region $aws_region

# EKS API server 訪問
aws ec2 authorize-security-group-ingress \\
    --group-id sg-0d59c6a9f577eb225 \\
    --protocol tcp \\
    --port 443 \\
    --source-group $client_vpn_sg_id \\
    --region $aws_region

# Phoenix Query Server (預設端口)
aws ec2 authorize-security-group-ingress \\
    --group-id sg-503f5e1b \\
    --protocol tcp \\
    --port 8765 \\
    --source-group $client_vpn_sg_id \\
    --region $aws_region

# Phoenix Query Server (替代端口)
aws ec2 authorize-security-group-ingress \\
    --group-id sg-503f5e1b \\
    --protocol tcp \\
    --port 8000 \\
    --source-group $client_vpn_sg_id \\
    --region $aws_region

# Phoenix Web UI
aws ec2 authorize-security-group-ingress \\
    --group-id sg-503f5e1b \\
    --protocol tcp \\
    --port 8080 \\
    --source-group $client_vpn_sg_id \\
    --region $aws_region

echo ""
echo "=== 安全優勢 ==="
echo "這種方法更清潔且更安全，因為："
echo "• Client VPN 用戶被隔離在專用安全群組中"
echo "• 您可以通過修改一個安全群組輕鬆管理 Client VPN 訪問"
echo "• 遵循最小權限原則，具有更好的安全姿態"
echo "• 更容易審計和故障排除"
echo ""
echo "請將上述指令複製並執行，以完成 VPN 用戶的服務訪問配置。"
EOF

    # 設置文件為可執行
    chmod +x "$output_file"
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓ 安全群組配置指令文件已生成: $filename${NC}" >&2
        echo -e "${YELLOW}📁 文件位置: $output_file${NC}" >&2
        echo -e "${BLUE}💡 您可以稍後執行此腳本來配置安全群組規則：${NC}" >&2
        echo -e "${CYAN}   ./$filename${NC}" >&2
        
        # 返回文件路徑供其他函數使用
        echo "$output_file"
        return 0
    else
        echo -e "${RED}錯誤: 生成安全群組配置指令文件失敗${NC}" >&2
        return 1
    fi
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
    endpoint_id=$(_create_aws_client_vpn_endpoint_ec "$vpn_cidr" "$arg_server_cert_arn" "$arg_client_cert_arn" "$vpn_name" "$aws_region" "$security_groups" "$vpc_id")
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

    # 立即保存端點配置以防後續步驟失敗
    echo -e "${BLUE}保存端點基本配置...${NC}"
    log_message_core "立即保存端點基本配置: $endpoint_id"
    
    local endpoint_config_file="${main_config_file%/*}/vpn_endpoint.conf"
    if save_initial_endpoint_config "$endpoint_config_file" "$endpoint_id" "$client_vpn_sg_id" "$arg_server_cert_arn" "$arg_client_cert_arn" "$vpc_id" "$subnet_id" "$vpn_cidr" "$vpn_name" "$vpc_cidr"; then
        echo -e "${GREEN}✓ 端點基本配置已保存${NC}"
        log_message_core "端點基本配置保存成功: $endpoint_config_file"
    else
        echo -e "${YELLOW}⚠️ 端點基本配置保存失敗，但繼續執行${NC}"
        log_message_core "警告: 端點基本配置保存失敗，但繼續執行"
    fi

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
            
            # 更新需要修改的配置項 (僅限用戶可配置設定)
            case "$key" in
                "AWS_REGION") echo "AWS_REGION=$aws_region" >> "$temp_config" ;;
                "VPN_CIDR") echo "VPN_CIDR=$vpn_cidr" >> "$temp_config" ;;
                "VPN_NAME") echo "VPN_NAME=$vpn_name" >> "$temp_config" ;;
                "VPC_ID") echo "VPC_ID=$vpc_id" >> "$temp_config" ;;
                "SUBNET_ID") echo "SUBNET_ID=$subnet_id" >> "$temp_config" ;;
                # 跳過自動生成的運行時數據 - 這些會保存到 .conf 文件
                "ENDPOINT_ID"|"SERVER_CERT_ARN"|"CLIENT_CERT_ARN"|"VPC_CIDR"|"MULTI_VPC_COUNT"|"CLIENT_VPN_SECURITY_GROUP_ID"|"SECURITY_GROUPS") 
                    echo "$key=$value" >> "$temp_config" ;;
                *) echo "$key=$value" >> "$temp_config" ;;
            esac
        done < "$main_config_file"
        config_updated=true
    fi
    
    # 如果配置文件不存在或某些必需的用戶可配置項缺失，添加它們
    # 注意：僅添加用戶可配置設定，運行時數據會保存到 .conf 文件
    if ! grep -q "^AWS_REGION=" "$temp_config" 2>/dev/null; then
        echo "AWS_REGION=$aws_region" >> "$temp_config"
    fi
    if ! grep -q "^VPN_CIDR=" "$temp_config" 2>/dev/null; then
        echo "VPN_CIDR=$vpn_cidr" >> "$temp_config"
    fi
    if ! grep -q "^VPN_NAME=" "$temp_config" 2>/dev/null; then
        echo "VPN_NAME=$vpn_name" >> "$temp_config"
    fi
    if ! grep -q "^VPC_ID=" "$temp_config" 2>/dev/null; then
        echo "VPC_ID=$vpc_id" >> "$temp_config"
    fi
    if ! grep -q "^SUBNET_ID=" "$temp_config" 2>/dev/null; then
        echo "SUBNET_ID=$subnet_id" >> "$temp_config"
    fi
    
    # 原子性地替換配置文件
    mv "$temp_config" "$main_config_file"
    echo -e "${GREEN}✓ 配置已安全更新，現有設置得到保留${NC}"
    
    # 更新 vpn_endpoint.conf 文件 (補充完整配置)
    local endpoint_config_file="${main_config_file%/*}/vpn_endpoint.conf"
    echo -e "${BLUE}更新端點運行時配置文件 \"$endpoint_config_file\"...${NC}"
    
    # 使用更新函數補充完整配置 (基本配置已在早期保存)
    if save_initial_endpoint_config "$endpoint_config_file" "$endpoint_id" "$client_vpn_sg_id" "$arg_server_cert_arn" "$arg_client_cert_arn" "$vpc_id" "$subnet_id" "$vpn_cidr" "$vpn_name" "$vpc_cidr"; then
        echo -e "${GREEN}✓ 端點運行時配置文件已完成更新${NC}"
        log_message_core "端點運行時配置文件最終更新成功: $endpoint_config_file"
    else
        echo -e "${YELLOW}⚠️ 端點運行時配置文件最終更新失敗${NC}"
        log_message_core "警告: 端點運行時配置文件最終更新失敗，但基本配置已保存"
    fi

    # 可選：匯入管理員證書到 ACM（Fix 3）
    echo -e "\n${CYAN}=== 可選步驟：匯入管理員證書到 ACM ===${NC}"
    log_message_core "開始可選管理員證書匯入"
    
    # 確保載入了證書管理函式庫
    local lib_dir="$(dirname "${BASH_SOURCE[0]}")"
    if [ -f "$lib_dir/cert_management.sh" ]; then
        source "$lib_dir/cert_management.sh"
    fi
    
    if command -v import_admin_certificate_to_acm_lib >/dev/null 2>&1; then
        # 獲取證書目錄
        local cert_dir=""
        # 從環境變數或配置獲取證書目錄
        if [ -n "$VPN_CERT_DIR" ]; then
            cert_dir="$VPN_CERT_DIR"
        elif [ -n "$CERT_DIR" ]; then
            cert_dir="$CERT_DIR"
        else
            # 回退到預設路徑
            cert_dir="./certs/${CURRENT_ENVIRONMENT:-staging}"
        fi
        
        echo -e "${BLUE}嘗試可選的管理員證書匯入...${NC}"
        if import_admin_certificate_to_acm_lib "$cert_dir" "$aws_region" "$endpoint_config_file"; then
            echo -e "${GREEN}✓ 管理員證書已成功匯入到 ACM${NC}"
            log_message_core "管理員證書已成功匯入到 ACM"
        else
            echo -e "${YELLOW}ℹ️ 管理員證書匯入跳過或失敗（不影響 VPN 功能）${NC}"
            log_message_core "管理員證書匯入跳過或失敗（不影響 VPN 功能）"
        fi
    else
        echo -e "${YELLOW}ℹ️ 管理員證書匯入函式不可用，跳過此步驟${NC}"
        log_message_core "管理員證書匯入函式不可用，跳過此步驟"
    fi

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
            echo -e "${RED}子網路 ID '$subnet_to_associate_id' 無效、不存在於 VPC '$vpc_to_add_id' 或區域 '$arg_aws_region'。${NC}" # subnet_id, vpc_id, aws_region are variables
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
        echo -e "${GREEN}✓ VPN 端點刪除成功${NC}"
        log_message_core "VPN 端點刪除成功: $endpoint_id"
    else
        echo -e "${RED}✗ VPN 端點刪除失敗${NC}"
        echo -e "${RED}錯誤輸出: $delete_output${NC}"
        log_message_core "錯誤: VPN 端點刪除失敗 (exit code: $delete_exit_code) - $delete_output"
        
        # 保存詳細診斷信息
        {
            echo "=== VPN 端點刪除失敗診斷報告 ==="
            echo "時間: $(date)"
            echo "Exit Code: $delete_exit_code"
            echo "端點 ID: $endpoint_id"
            echo "AWS 區域: $aws_region"
            echo "錯誤輸出: $delete_output"
            echo "AWS CLI 版本: $(aws --version 2>&1)"
            echo "當前身份: $(aws sts get-caller-identity --query 'Arn' --output text 2>/dev/null || echo '無法獲取')"
            echo "========================="
        } >> "${LOG_FILE:-vpn_error_diagnostic.log}"
        
        return 1
    fi
    
    # 步驟 3.5: 清理 VPN 服務訪問權限
    echo -e "\\n${YELLOW}步驟 3.5: 清理 VPN 服務訪問權限...${NC}"
    log_message_core "開始清理 VPN 服務訪問權限: $endpoint_id"
    
    # 嘗試從配置文件獲取 CLIENT_VPN_SECURITY_GROUP_ID
    local client_vpn_sg_id=""
    
    # 檢查多個可能的配置文件位置
    local config_files=(
        "${config_file_path}"
        "${config_file_path%/*}/vpn_endpoint.conf"
        "${config_file_path%/*}/${CURRENT_ENVIRONMENT:-staging}.env"
    )
    
    # 如果 config_file_path 為空，嘗試從當前目錄推斷
    if [ -z "$config_file_path" ]; then
        local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
        local project_root="$(dirname "$script_dir")"
        
        # 嘗試從環境管理器獲取當前環境
        if [ -f "$script_dir/env_manager.sh" ]; then
            source "$script_dir/env_manager.sh"
            load_current_env 2>/dev/null || true
        fi
        
        local current_env="${CURRENT_ENVIRONMENT:-staging}"
        config_files+=(
            "$project_root/configs/$current_env/vpn_endpoint.conf"
            "$project_root/configs/$current_env/${current_env}.env"
        )
    fi
    
    echo -e "${BLUE}正在搜索 CLIENT_VPN_SECURITY_GROUP_ID...${NC}"
    for config_file in "${config_files[@]}"; do
        if [[ -f "$config_file" ]] && grep -q "CLIENT_VPN_SECURITY_GROUP_ID=" "$config_file" 2>/dev/null; then
            client_vpn_sg_id=$(grep "CLIENT_VPN_SECURITY_GROUP_ID=" "$config_file" | head -1 | cut -d'=' -f2 | tr -d '"' | tr -d "'" | xargs)
            if [[ -n "$client_vpn_sg_id" && "$client_vpn_sg_id" != "null" && "$client_vpn_sg_id" != '""' ]]; then
                echo -e "${BLUE}✓ 找到 CLIENT_VPN_SECURITY_GROUP_ID: $client_vpn_sg_id${NC}"
                echo -e "${DIM}  來源: $(basename "$config_file")${NC}"
                log_message_core "找到 CLIENT_VPN_SECURITY_GROUP_ID: $client_vpn_sg_id (來源: $config_file)"
                break
            fi
        fi
    done
    
    if [[ -n "$client_vpn_sg_id" && "$client_vpn_sg_id" != "null" && "$client_vpn_sg_id" != '""' ]]; then
        # 調用 manage_vpn_service_access.sh 來移除 VPN 訪問規則
        local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
        local project_root="$(dirname "$script_dir")"
        local access_script="$project_root/admin-tools/manage_vpn_service_access.sh"
        
        if [[ -f "$access_script" && -x "$access_script" ]]; then
            echo -e "${BLUE}正在使用 manage_vpn_service_access.sh 清理服務訪問權限...${NC}"
            log_message_core "執行 VPN 服務訪問清理: $access_script remove $client_vpn_sg_id --region $aws_region"
            
            # 首先預覽要移除的規則
            echo -e "${DIM}預覽要移除的規則...${NC}"
            if "$access_script" remove "$client_vpn_sg_id" --region "$aws_region" --dry-run 2>/dev/null; then
                echo -e "${YELLOW}執行實際的規則移除...${NC}"
                if "$access_script" remove "$client_vpn_sg_id" --region "$aws_region"; then
                    echo -e "${GREEN}✓ VPN 服務訪問權限清理成功${NC}"
                    log_message_core "VPN 服務訪問權限清理成功: $client_vpn_sg_id"
                else
                    echo -e "${YELLOW}⚠️ VPN 服務訪問權限清理失敗或無需清理${NC}"
                    log_message_core "警告: VPN 服務訪問權限清理失敗: $client_vpn_sg_id"
                fi
            else
                echo -e "${YELLOW}⚠️ 無法預覽要移除的規則，跳過服務訪問清理${NC}"
                log_message_core "警告: 無法預覽 VPN 服務訪問規則，跳過清理"
            fi
        else
            echo -e "${YELLOW}⚠️ 找不到 manage_vpn_service_access.sh 工具，跳過服務訪問權限清理${NC}"
            echo -e "${DIM}預期位置: $access_script${NC}"
            log_message_core "警告: manage_vpn_service_access.sh 工具不存在，跳過服務訪問清理"
            
            # 提供手動清理指令
            echo -e "${BLUE}💡 如需手動清理，請稍後運行：${NC}"
            echo -e "${DIM}./admin-tools/manage_vpn_service_access.sh remove $client_vpn_sg_id --region $aws_region${NC}"
        fi
    else
        echo -e "${YELLOW}⚠️ 未找到有效的 CLIENT_VPN_SECURITY_GROUP_ID，跳過服務訪問權限清理${NC}"
        log_message_core "警告: 無法獲取有效的 CLIENT_VPN_SECURITY_GROUP_ID，跳過服務訪問權限清理"
        
        # 提供查找和手動清理的建議
        echo -e "${BLUE}💡 如果存在 VPN 服務訪問規則，您可以：${NC}"
        echo -e "${DIM}1. 檢查配置文件是否包含 CLIENT_VPN_SECURITY_GROUP_ID${NC}"
        echo -e "${DIM}2. 手動運行: ./admin-tools/manage_vpn_service_access.sh discover --region $aws_region${NC}"
        echo -e "${DIM}3. 使用發現的安全群組 ID 手動清理規則${NC}"
    fi
    
    # 步驟 4: 刪除專用的 Client VPN 安全群組 (如果存在)
    if [[ -n "$client_vpn_sg_id" && "$client_vpn_sg_id" != "null" && "$client_vpn_sg_id" != '""' ]]; then
        echo -e "\\n${YELLOW}步驟 4: 刪除專用的 Client VPN 安全群組...${NC}"
        log_message_core "開始刪除專用 Client VPN 安全群組: $client_vpn_sg_id"
        
        # 檢查安全群組是否存在
        local sg_exists
        sg_exists=$(aws ec2 describe-security-groups \
            --group-ids "$client_vpn_sg_id" \
            --region "$aws_region" \
            --query 'SecurityGroups[0].GroupId' \
            --output text 2>/dev/null)
        
        if [[ "$sg_exists" == "$client_vpn_sg_id" ]]; then
            # 檢查安全群組是否為專用的 Client VPN 群組
            local sg_purpose
            sg_purpose=$(aws ec2 describe-security-groups \
                --group-ids "$client_vpn_sg_id" \
                --region "$aws_region" \
                --query 'SecurityGroups[0].Tags[?Key==`Purpose`].Value' \
                --output text 2>/dev/null)
            
            if [[ "$sg_purpose" == "Client-VPN" ]]; then
                echo -e "${BLUE}正在刪除專用 Client VPN 安全群組: $client_vpn_sg_id${NC}"
                
                local delete_sg_result
                delete_sg_result=$(aws ec2 delete-security-group \
                    --group-id "$client_vpn_sg_id" \
                    --region "$aws_region" 2>&1)
                local delete_sg_exit_code=$?
                
                if [ $delete_sg_exit_code -eq 0 ]; then
                    echo -e "${GREEN}✓ 專用 Client VPN 安全群組刪除成功${NC}"
                    log_message_core "專用 Client VPN 安全群組刪除成功: $client_vpn_sg_id"
                else
                    echo -e "${YELLOW}⚠️ 專用 Client VPN 安全群組刪除失敗${NC}"
                    echo -e "${DIM}錯誤: $delete_sg_result${NC}"
                    log_message_core "警告: 專用 Client VPN 安全群組刪除失敗: $client_vpn_sg_id - $delete_sg_result"
                    
                    # 可能是因為還有其他資源在使用，提供建議
                    echo -e "${BLUE}💡 可能的解決方案：${NC}"
                    echo -e "${DIM}1. 檢查是否有其他資源仍在使用此安全群組${NC}"
                    echo -e "${DIM}2. 稍後手動刪除: aws ec2 delete-security-group --group-id $client_vpn_sg_id --region $aws_region${NC}"
                fi
            else
                echo -e "${YELLOW}⚠️ 安全群組 $client_vpn_sg_id 不是專用的 Client VPN 群組，跳過刪除${NC}"
                log_message_core "跳過刪除安全群組 $client_vpn_sg_id - 不是專用 Client VPN 群組 (Purpose: $sg_purpose)"
            fi
        else
            echo -e "${YELLOW}⚠️ 安全群組 $client_vpn_sg_id 不存在或已被刪除${NC}"
            log_message_core "安全群組不存在或已被刪除: $client_vpn_sg_id"
        fi
    else
        echo -e "\\n${YELLOW}步驟 4: 跳過安全群組刪除 (未找到有效的 CLIENT_VPN_SECURITY_GROUP_ID)${NC}"
        log_message_core "跳過專用 Client VPN 安全群組刪除 - 未找到有效 ID"
    fi

    # 步驟 5: 刪除 ACM 證書 (如果存在)
    echo -e "\\n${YELLOW}步驟 5: 刪除 ACM 證書...${NC}"
    log_message_core "開始刪除 ACM 證書"
    
    # 收集需要刪除的證書 ARN
    local cert_arns_to_delete=()
    
    # 檢查並收集證書 ARN
    for config_file in "${config_files[@]}"; do
        if [ -f "$config_file" ]; then
            # 收集 SERVER_CERT_ARN
            local server_arn=$(grep "^SERVER_CERT_ARN=" "$config_file" 2>/dev/null | cut -d'=' -f2 | tr -d '"' | tr -d "'" | xargs)
            if [[ -n "$server_arn" && "$server_arn" != "null" && "$server_arn" != '""' ]]; then
                cert_arns_to_delete+=("$server_arn")
                echo -e "${BLUE}  找到服務器證書 ARN: $server_arn${NC}"
            fi
            
            # 收集 CA_CERT_ARN
            local ca_arn=$(grep "^CA_CERT_ARN=" "$config_file" 2>/dev/null | cut -d'=' -f2 | tr -d '"' | tr -d "'" | xargs)
            if [[ -n "$ca_arn" && "$ca_arn" != "null" && "$ca_arn" != '""' ]]; then
                cert_arns_to_delete+=("$ca_arn")
                echo -e "${BLUE}  找到 CA 證書 ARN: $ca_arn${NC}"
            fi
            
            # 收集 CLIENT_CERT_ARN (如果存在)
            local client_arn=$(grep "^CLIENT_CERT_ARN=" "$config_file" 2>/dev/null | cut -d'=' -f2 | tr -d '"' | tr -d "'" | xargs)
            if [[ -n "$client_arn" && "$client_arn" != "null" && "$client_arn" != '""' ]]; then
                cert_arns_to_delete+=("$client_arn")
                echo -e "${BLUE}  找到客戶端證書 ARN: $client_arn${NC}"
            fi
            
            # 收集 CLIENT_CERT_ARN_admin (如果存在)
            local admin_arn=$(grep "^CLIENT_CERT_ARN_admin=" "$config_file" 2>/dev/null | cut -d'=' -f2 | tr -d '"' | tr -d "'" | xargs)
            if [[ -n "$admin_arn" && "$admin_arn" != "null" && "$admin_arn" != '""' ]]; then
                cert_arns_to_delete+=("$admin_arn")
                echo -e "${BLUE}  找到管理員證書 ARN: $admin_arn${NC}"
            fi
        fi
    done
    
    # 刪除找到的證書
    if [ ${#cert_arns_to_delete[@]} -gt 0 ]; then
        echo -e "${BLUE}正在刪除 ${#cert_arns_to_delete[@]} 個 ACM 證書...${NC}"
        
        for cert_arn in "${cert_arns_to_delete[@]}"; do
            echo -e "${YELLOW}  刪除證書: $cert_arn${NC}"
            
            local delete_cert_result
            delete_cert_result=$(aws acm delete-certificate \
                --certificate-arn "$cert_arn" \
                --region "$aws_region" 2>&1)
            local delete_cert_exit_code=$?
            
            if [ $delete_cert_exit_code -eq 0 ]; then
                echo -e "${GREEN}  ✓ 證書刪除成功${NC}"
                log_message_core "ACM 證書刪除成功: $cert_arn"
            else
                echo -e "${YELLOW}  ⚠️ 證書刪除失敗或已被刪除${NC}"
                echo -e "${DIM}    錯誤: $delete_cert_result${NC}"
                log_message_core "警告: ACM 證書刪除失敗: $cert_arn - $delete_cert_result"
                
                # 可能是證書正在使用中或已被刪除，提供建議
                if echo "$delete_cert_result" | grep -q "ResourceInUseException"; then
                    echo -e "${BLUE}    💡 證書可能仍在使用中，將在資源釋放後自動清理${NC}"
                elif echo "$delete_cert_result" | grep -q "ResourceNotFoundException"; then
                    echo -e "${BLUE}    💡 證書已不存在，可能已被刪除${NC}"
                else
                    echo -e "${BLUE}    💡 稍後手動刪除: aws acm delete-certificate --certificate-arn $cert_arn --region $aws_region${NC}"
                fi
            fi
        done
        
        echo -e "${GREEN}✓ ACM 證書清理完成${NC}"
        log_message_core "ACM 證書清理完成，處理了 ${#cert_arns_to_delete[@]} 個證書"
    else
        echo -e "${YELLOW}⚠️ 未找到需要刪除的 ACM 證書${NC}"
        log_message_core "未找到需要刪除的 ACM 證書"
    fi

    # 步驟 6: 刪除日誌群組 (如果存在)
    if [ -n "$log_group_name" ]; then
        echo -e "\\n${YELLOW}步驟 6: 刪除日誌群組...${NC}"
        log_message_core "開始刪除 CloudWatch 日誌群組: $log_group_name"
        
        aws logs delete-log-group \
            --log-group-name "$log_group_name" \
            --region "$aws_region" >/dev/null 2>&1
        
        if [ $? -eq 0 ]; then
            echo -e "${GREEN}✓ 日誌群組刪除成功${NC}"
            log_message_core "日誌群組刪除成功: $log_group_name"
        else
            echo -e "${RED}✗ 日誌群組刪除失敗${NC}"
            log_message_core "錯誤: 日誌群組刪除失敗: $log_group_name"
        fi
    fi

    # 步驟 7: 更新配置文件
    if [ -f "$config_file_path" ]; then
        echo -e "\\n${YELLOW}步驟 7: 更新配置文件...${NC}"
        log_message_core "開始更新配置文件: $config_file_path"
        
        # 創建臨時文件來安全地更新配置
        local temp_config=$(mktemp)
        local config_updated=false
        
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
            
            # 更新需要修改的配置項 (清空已刪除資源的 ID)
            case "$key" in
                "ENDPOINT_ID") echo "ENDPOINT_ID=" >> "$temp_config" ;; # 清空端點 ID
                "CLIENT_VPN_SECURITY_GROUP_ID") echo "CLIENT_VPN_SECURITY_GROUP_ID=" >> "$temp_config" ;; # 清空已刪除的安全群組 ID
                "SERVER_CERT_ARN") echo "SERVER_CERT_ARN=" >> "$temp_config" ;; # 清空服務器證書 ARN
                "CA_CERT_ARN") echo "CA_CERT_ARN=" >> "$temp_config" ;; # 清空 CA 證書 ARN
                "CLIENT_CERT_ARN") echo "CLIENT_CERT_ARN=" >> "$temp_config" ;; # 清空客戶端證書 ARN  
                "CLIENT_CERT_ARN_admin") echo "CLIENT_CERT_ARN_admin=" >> "$temp_config" ;; # 清空管理員證書 ARN
                "VPC_CIDR") echo "VPC_CIDR=" >> "$temp_config" ;; # 清空 VPC CIDR
                "SECURITY_GROUPS") echo "SECURITY_GROUPS=" >> "$temp_config" ;; # 清空安全群組列表
                *) echo "$key=$value" >> "$temp_config" ;; # 保留其他設定
            esac
        done < "$config_file_path"
        
        # 原子性地替換配置文件
        mv "$temp_config" "$config_file_path"
        echo -e "${GREEN}✓ 配置已安全更新，現有設置得到保留${NC}"
        log_message_core "配置文件更新成功: $config_file_path"
    else
        echo -e "${YELLOW}警告: 配置文件 $config_file_path 不存在，無法更新${NC}"
    fi

    echo -e "${GREEN}VPN 端點及相關資源刪除完成！${NC}"
    return 0
}