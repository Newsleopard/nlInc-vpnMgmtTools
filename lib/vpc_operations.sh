#!/bin/bash

# lib/vpc_operations.sh
# VPC 和網路操作相關函式庫
# 包含 VPC、子網路發現、驗證和相關網路操作功能

# 確保已載入核心函式
if [ -z "$LOG_FILE_CORE" ]; then
    echo "錯誤: 核心函式庫未載入。請先載入 core_functions.sh"
    exit 1
fi

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
            else
                echo -e "${RED}達到最大嘗試次數。跳過子網路關聯步驟。${NC}" >&2
                subnet_id=""
                break
            fi
        fi
    done
    
    # 獲取 VPC CIDR
    local vpc_cidr
    vpc_cidr=$(aws ec2 describe-vpcs --vpc-ids "$vpc_id" --region "$aws_region" | jq -r '.Vpcs[0].CidrBlock' 2>/dev/null)
    if [ -z "$vpc_cidr" ] || [ "$vpc_cidr" = "null" ]; then
        echo -e "${YELLOW}警告: 無法獲取 VPC CIDR，使用預設值。${NC}" >&2
        vpc_cidr="10.0.0.0/16"  # 預設值
    fi
    
    # VPN 設定 - 使用環境變數或互動式輸入
    local vpn_cidr vpn_name
    if [ -n "$VPN_CIDR" ] && [ -n "$VPN_NAME" ]; then
        # 使用環境配置中的值
        vpn_cidr="$VPN_CIDR"
        vpn_name="$VPN_NAME"
        echo -e "${GREEN}✓ 使用環境配置中的 VPN 設定${NC}" >&2
        echo -e "${GREEN}  VPN CIDR: $vpn_cidr${NC}" >&2
        echo -e "${GREEN}  VPN 名稱: $vpn_name${NC}" >&2
    else
        # 互動式輸入
        echo -e "\\n${BLUE}設定 VPN 配置...${NC}" >&2
        
        # VPN CIDR 輸入
        while true; do
            echo -n "請輸入 VPN 客戶端 IP 範圍 (CIDR 格式，例如: 172.16.0.0/22): " >&2
            read vpn_cidr
            if [[ "$vpn_cidr" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}/[0-9]{1,2}$ ]]; then
                break
            else
                echo -e "${RED}無效的 CIDR 格式。請使用類似 '172.16.0.0/22' 的格式。${NC}" >&2
            fi
        done
        
        # VPN 名稱輸入
        echo -n "請輸入 VPN 端點名稱 (例如: My-VPN): " >&2
        read vpn_name
        if [ -z "$vpn_name" ]; then
            vpn_name="ClientVPN-$(date +%Y%m%d)"
            echo -e "${YELLOW}使用預設名稱: $vpn_name${NC}" >&2
        fi
    fi
    
    # 安全群組處理 - 使用環境變數或留空
    local security_groups="${SECURITY_GROUPS:-}"
    
    # 建構並返回 JSON 結果
    local result_json
    if command -v jq >/dev/null 2>&1; then
        result_json=$(jq -n \
            --arg vpc_id "$vpc_id" \
            --arg subnet_id "$subnet_id" \
            --arg vpc_cidr "$vpc_cidr" \
            --arg vpn_cidr "$vpn_cidr" \
            --arg vpn_name "$vpn_name" \
            --arg security_groups "$security_groups" \
            '{vpc_id: $vpc_id, subnet_id: $subnet_id, vpc_cidr: $vpc_cidr, vpn_cidr: $vpn_cidr, vpn_name: $vpn_name, security_groups: $security_groups}')
    else
        # 備用 JSON 生成
        result_json='{"vpc_id":"'$vpc_id'","subnet_id":"'$subnet_id'","vpc_cidr":"'$vpc_cidr'","vpn_cidr":"'$vpn_cidr'","vpn_name":"'$vpn_name'","security_groups":"'$security_groups'"}'
    fi
    
    log_message_core "VPC/子網路/VPN 詳細資訊獲取完成 (lib): $result_json"
    echo "$result_json"
    return 0
}

# 輔助函式：提示網絡詳細資訊
_prompt_network_details_ec() {
    local aws_region="$1"
    # 使用 declare -g 將變數宣告為全域，以便主調用函式可以訪問
    # 或者，函式可以 echo 結果，由主調用者捕獲

    # 直接調用已有的函式並解析結果
    local network_details_json
    network_details_json=$(get_vpc_subnet_vpn_details_lib "$aws_region")
    local get_details_status=$?
    
    if [ $get_details_status -ne 0 ] || [ -z "$network_details_json" ]; then
        echo -e "${RED}獲取網絡詳細資訊失敗。${NC}" >&2
        return 1
    fi
    
    # 解析 JSON 結果並設定全域變數
    if command -v jq >/dev/null 2>&1; then
        declare -g ec_vpc_id=$(echo "$network_details_json" | jq -r '.vpc_id' 2>/dev/null)
        declare -g ec_subnet_id=$(echo "$network_details_json" | jq -r '.subnet_id' 2>/dev/null)
        declare -g ec_vpc_cidr=$(echo "$network_details_json" | jq -r '.vpc_cidr' 2>/dev/null)
        declare -g ec_vpn_cidr=$(echo "$network_details_json" | jq -r '.vpn_cidr' 2>/dev/null)
        declare -g ec_vpn_name=$(echo "$network_details_json" | jq -r '.vpn_name' 2>/dev/null)
        declare -g ec_security_groups=$(echo "$network_details_json" | jq -r '.security_groups' 2>/dev/null)
    else
        # 備用解析方法
        declare -g ec_vpc_id=$(echo "$network_details_json" | grep -o '"vpc_id":"[^"]*"' | sed 's/"vpc_id":"\([^"]*\)"/\1/')
        declare -g ec_subnet_id=$(echo "$network_details_json" | grep -o '"subnet_id":"[^"]*"' | sed 's/"subnet_id":"\([^"]*\)"/\1/')
        declare -g ec_vpc_cidr=$(echo "$network_details_json" | grep -o '"vpc_cidr":"[^"]*"' | sed 's/"vpc_cidr":"\([^"]*\)"/\1/')
        declare -g ec_vpn_cidr=$(echo "$network_details_json" | grep -o '"vpn_cidr":"[^"]*"' | sed 's/"vpn_cidr":"\([^"]*\)"/\1/')
        declare -g ec_vpn_name=$(echo "$network_details_json" | grep -o '"vpn_name":"[^"]*"' | sed 's/"vpn_name":"\([^"]*\)"/\1/')
        declare -g ec_security_groups=$(echo "$network_details_json" | grep -o '"security_groups":"[^"]*"' | sed 's/"security_groups":"\([^"]*\)"/\1/')
    fi
    
    # 驗證解析結果
    if [ -z "$ec_vpc_id" ] || [ "$ec_vpc_id" = "null" ]; then
        echo -e "${RED}錯誤: 無法解析 VPC ID${NC}" >&2
        return 1
    fi
    
    log_message_core "_prompt_network_details_ec 完成 - VPC: $ec_vpc_id, Subnet: $ec_subnet_id"
    return 0
}

# 驗證 VPC 和子網路配置
# 參數: $1 = VPC_ID, $2 = SUBNET_ID, $3 = AWS_REGION
validate_vpc_subnet_config() {
    local vpc_id="$1"
    local subnet_id="$2"
    local aws_region="$3"
    
    # 參數驗證
    if [ -z "$vpc_id" ] || [ -z "$aws_region" ]; then
        echo -e "${RED}錯誤: VPC ID 和 AWS 區域為必要參數${NC}" >&2
        return 1
    fi
    
    if ! validate_aws_region "$aws_region"; then
        return 1
    fi
    
    if ! validate_vpc_id "$vpc_id"; then
        echo -e "${RED}錯誤: VPC ID 格式無效${NC}" >&2
        return 1
    fi
    
    # 驗證 VPC 是否存在
    if ! aws ec2 describe-vpcs --vpc-ids "$vpc_id" --region "$aws_region" >/dev/null 2>&1; then
        echo -e "${RED}錯誤: VPC '$vpc_id' 不存在於區域 '$aws_region'${NC}" >&2
        return 1
    fi
    
    # 如果提供了子網路 ID，驗證子網路
    if [ -n "$subnet_id" ]; then
        if ! validate_subnet_id "$subnet_id"; then
            echo -e "${RED}錯誤: 子網路 ID 格式無效${NC}" >&2
            return 1
        fi
        
        # 驗證子網路是否存在且屬於指定的 VPC
        local subnet_vpc_id
        if ! subnet_vpc_id=$(aws ec2 describe-subnets --subnet-ids "$subnet_id" --region "$aws_region" --query 'Subnets[0].VpcId' --output text 2>/dev/null); then
            echo -e "${RED}錯誤: 子網路 '$subnet_id' 不存在於區域 '$aws_region'${NC}" >&2
            return 1
        fi
        
        if [ "$subnet_vpc_id" != "$vpc_id" ]; then
            echo -e "${RED}錯誤: 子網路 '$subnet_id' 不屬於 VPC '$vpc_id'${NC}" >&2
            return 1
        fi
    fi
    
    log_message_core "VPC/子網路配置驗證成功: VPC=$vpc_id, Subnet=$subnet_id"
    return 0
}

# 獲取 VPC 的 CIDR 區塊
# 參數: $1 = VPC_ID, $2 = AWS_REGION
# 返回: VPC CIDR 字串
get_vpc_cidr() {
    local vpc_id="$1"
    local aws_region="$2"
    
    if [ -z "$vpc_id" ] || [ -z "$aws_region" ]; then
        echo -e "${RED}錯誤: VPC ID 和 AWS 區域為必要參數${NC}" >&2
        return 1
    fi
    
    local vpc_cidr
    vpc_cidr=$(aws ec2 describe-vpcs --vpc-ids "$vpc_id" --region "$aws_region" --query 'Vpcs[0].CidrBlock' --output text 2>/dev/null)
    
    if [ -z "$vpc_cidr" ] || [ "$vpc_cidr" = "None" ] || [ "$vpc_cidr" = "null" ]; then
        echo -e "${RED}錯誤: 無法獲取 VPC '$vpc_id' 的 CIDR${NC}" >&2
        return 1
    fi
    
    echo "$vpc_cidr"
    return 0
}