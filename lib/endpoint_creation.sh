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
# 返回: JSON 格式 {"vpc_id": "vpc-xxx", "subnet_id": "subnet-xxx", "vpn_cidr": "172.16.0.0/22", "vpn_name": "Production-VPN"}
get_vpc_subnet_vpn_details_lib() {
    local aws_region="$1"

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
    
    # 獲取 VPN 設定
    local default_vpn_cidr="172.16.0.0/22"
    local vpn_cidr
    echo -n "請輸入 VPN CIDR (預設: $default_vpn_cidr): " >&2
    read vpn_cidr
    vpn_cidr=${vpn_cidr:-$default_vpn_cidr}
    
    local vpn_name
    echo -n "請輸入 VPN 端點名稱 (預設: Production-VPN): " >&2
    read vpn_name
    vpn_name=${vpn_name:-Production-VPN}

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
            '{vpc_id: $vpc_id, subnet_id: $subnet_id, vpn_cidr: $vpn_cidr, vpn_name: $vpn_name}')
    else
        # 備用方法：手動構建 JSON
        result_json="{\"vpc_id\":\"$vpc_id\",\"subnet_id\":\"$subnet_id\",\"vpn_cidr\":\"$vpn_cidr\",\"vpn_name\":\"$vpn_name\"}"
    fi

    log_message_core "VPC/子網路詳細資訊獲取完成: VPC=$vpc_id, Subnet=$subnet_id, VPN_CIDR=$vpn_cidr, VPN_Name=$vpn_name"
    
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
      jq -r '.Subnets[] | "子網路 ID: \\(.SubnetId), 可用區: \\(.AvailabilityZone), CIDR: \\(.CidrBlock)"' 2>/dev/null)
    
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

# 輔助函式：創建 AWS Client VPN 端點實體
_create_aws_client_vpn_endpoint_ec() {
    local vpn_cidr="$1"
    local server_cert_arn="$2"
    local client_cert_arn="$3"
    local vpn_name="$4"
    local aws_region="$5"

    # 清理 VPN 名稱以用於日誌群組 (只允許字母、數字、連字符和斜線)
    local clean_log_name=$(echo "$vpn_name" | sed 's/[^a-zA-Z0-9/_-]/-/g' | sed 's/--*/-/g' | sed 's/^-\|-$//g')
    local log_group_name="/aws/clientvpn/$clean_log_name"
    echo -e "${BLUE}創建 CloudWatch 日誌群組: $log_group_name${NC}"
    
    # 檢查日誌群組是否已存在
    if ! aws logs describe-log-groups --log-group-name-prefix "$log_group_name" --region "$aws_region" --query "logGroups[?logGroupName=='$log_group_name']" --output text | grep -q "$log_group_name"; then
        echo -e "${YELLOW}日誌群組不存在，正在創建...${NC}"
        if aws logs create-log-group --log-group-name "$log_group_name" --region "$aws_region" 2>/dev/null; then
            echo -e "${GREEN}✓ 日誌群組創建成功${NC}"
        else
            echo -e "${YELLOW}日誌群組創建失敗，但這不會影響 VPN 端點創建${NC}"
            echo -e "${YELLOW}嘗試不使用日誌群組創建 VPN 端點...${NC}"
            log_group_name=""
        fi
    else
        echo -e "${GREEN}✓ 日誌群組已存在${NC}"
    fi
    
    echo -e "${BLUE}創建 Client VPN 端點...${NC}"
    echo -e "${YELLOW}使用參數:${NC}"
    echo -e "  VPN CIDR: $vpn_cidr"
    echo -e "  伺服器憑證 ARN: $server_cert_arn"
    echo -e "  客戶端憑證 ARN: $client_cert_arn"
    echo -e "  VPN 名稱: $vpn_name"
    echo -e "  AWS 區域: $aws_region"
    
    # 執行調試檢查
    echo -e "\n${BLUE}執行預檢查...${NC}"
    if ! debug_aws_cli_params "$vpn_cidr" "$server_cert_arn" "$client_cert_arn" "$vpn_name" "$aws_region"; then
        echo -e "${RED}預檢查失敗，無法繼續創建 VPN 端點${NC}"
        return 1
    fi
    
    local endpoint_result exit_code
    
    # 清理 VPN 名稱中的特殊字符以用於標籤
    local clean_vpn_name=$(echo "$vpn_name" | sed 's/[^a-zA-Z0-9-]/_/g')
    
    echo -e "${BLUE}執行 AWS CLI 命令創建 VPN 端點...${NC}"
    
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
        echo -e "${GREEN}啟用 CloudWatch 日誌記錄${NC}"
    else
        log_options='{
            "Enabled": false
        }'
        echo -e "${YELLOW}禁用 CloudWatch 日誌記錄${NC}"
    fi
    
    # 建構 tag-specifications JSON
    tag_specs='[{
        "ResourceType": "client-vpn-endpoint",
        "Tags": [
            {"Key": "Name", "Value": "'$clean_vpn_name'"},
            {"Key": "Purpose", "Value": "VPNManagement"}
        ]
    }]'
    
    echo -e "${YELLOW}創建參數預覽:${NC}"
    echo "VPN CIDR: $vpn_cidr"
    echo "伺服器證書: $server_cert_arn"
    echo "客戶端證書: $client_cert_arn"
    echo "日誌群組: $log_group_name"
    echo "VPN 名稱: $clean_vpn_name"
    
    # 執行創建命令
    if [ -n "$log_group_name" ]; then
        endpoint_result=$(aws ec2 create-client-vpn-endpoint \
          --client-cidr-block "$vpn_cidr" \
          --server-certificate-arn "$server_cert_arn" \
          --authentication-options "$auth_options" \
          --connection-log-options "$log_options" \
          --transport-protocol tcp \
          --split-tunnel \
          --dns-servers 8.8.8.8 8.8.4.4 \
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
          --dns-servers 8.8.8.8 8.8.4.4 \
          --region "$aws_region" \
          --tag-specifications "$tag_specs" 2>&1)
    fi
    exit_code=$?
    
    # 檢查 AWS CLI 命令是否成功執行
    if [ $exit_code -ne 0 ]; then
        echo -e "${RED}AWS CLI 命令執行失敗 (exit code: $exit_code)${NC}"
        echo -e "${RED}錯誤輸出:${NC}"
        echo "$endpoint_result"
        log_message_core "錯誤: VPN 端點創建失敗 - AWS CLI 錯誤 (exit code: $exit_code)"
        return 1
    fi
    
    # 檢查輸出是否為空
    if [ -z "$endpoint_result" ]; then
        echo -e "${RED}AWS CLI 命令沒有返回任何輸出${NC}"
        log_message_core "錯誤: VPN 端點創建失敗 - 無輸出"
        return 1
    fi
    
    # 記錄原始輸出用於調試
    echo -e "${YELLOW}AWS CLI 原始輸出:${NC}"
    echo "$endpoint_result"
    
    # 嘗試修復可能的 JSON 格式問題
    # 有時候 AWS CLI 可能在 JSON 前面加入一些額外字符
    cleaned_result=$(echo "$endpoint_result" | sed '1{/^[[:space:]]*$/d;}' | grep -E '^\s*\{' | head -1)
    if [ -n "$cleaned_result" ]; then
        # 從找到的第一個 { 開始提取 JSON
        json_start_line=$(echo "$endpoint_result" | grep -n '^[[:space:]]*{' | head -1 | cut -d: -f1)
        if [ -n "$json_start_line" ]; then
            cleaned_result=$(echo "$endpoint_result" | tail -n +$json_start_line)
            echo -e "${YELLOW}清理後的 JSON:${NC}"
            echo "$cleaned_result"
        else
            cleaned_result="$endpoint_result"
        fi
    else
        cleaned_result="$endpoint_result"
    fi
    
    # 檢查清理後的輸出是否為有效的 JSON
    if ! echo "$cleaned_result" | jq empty 2>/dev/null; then
        echo -e "${RED}AWS CLI 返回的不是有效的 JSON 格式${NC}"
        echo -e "${RED}嘗試使用備用解析方法...${NC}"
        
        # 嘗試使用 grep 和 sed 提取端點 ID
        endpoint_id=$(echo "$endpoint_result" | grep -o '"ClientVpnEndpointId"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*"ClientVpnEndpointId"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')
        
        if [ -n "$endpoint_id" ] && [ "$endpoint_id" != "null" ]; then
            echo -e "${GREEN}✓ 使用備用方法成功提取端點 ID: $endpoint_id${NC}"
            echo "$endpoint_id"
            return 0
        else
            echo -e "${RED}備用解析方法也失敗${NC}"
            echo -e "${RED}原始輸出: $endpoint_result${NC}"
            log_message_core "錯誤: VPN 端點創建失敗 - JSON 解析失敗"
            return 1
        fi
    fi
    
    local endpoint_id
    if ! endpoint_id=$(echo "$cleaned_result" | jq -r '.ClientVpnEndpointId' 2>/dev/null); then
        echo -e "${RED}無法從響應中解析端點 ID${NC}"
        echo -e "${RED}響應內容: $cleaned_result${NC}"
        log_message_core "錯誤: VPN 端點創建失敗 - 端點 ID 解析失敗"
        return 1
    fi

    if [ -z "$endpoint_id" ] || [ "$endpoint_id" == "null" ]; then
        echo -e "${RED}創建 Client VPN 端點後未能獲取有效的 Endpoint ID${NC}"
        echo -e "${RED}響應內容: $cleaned_result${NC}"
        log_message_core "錯誤: VPN 端點創建失敗 - 端點 ID 為空或 null"
        return 1
    fi
    
    echo -e "${GREEN}✓ VPN 端點創建成功，ID: $endpoint_id${NC}"
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
    aws ec2 associate-client-vpn-target-network \
      --client-vpn-endpoint-id "$endpoint_id" \
      --subnet-id "$subnet_id" \
      --region "$aws_region"
    # 可以加入錯誤檢查
}

# 輔助函式：設定授權和路由
_setup_authorization_and_routes_ec() {
    local endpoint_id="$1"
    local vpc_cidr="$2" # 主要 VPC 的 CIDR，用於初始授權
    local subnet_id="$3" # 主要子網路 ID，用於初始路由
    local aws_region="$4"

    echo -e "${BLUE}添加授權規則 (允許訪問主要 VPC)...${NC}"
    aws ec2 authorize-client-vpn-ingress \
      --client-vpn-endpoint-id "$endpoint_id" \
      --target-network-cidr "$vpc_cidr" \
      --authorize-all-groups \
      --region "$aws_region"
    # 可以加入錯誤檢查

    echo -e "${BLUE}創建路由 (允許所有流量通過 VPN 到主要子網路)...${NC}"
    aws ec2 create-client-vpn-route \
      --client-vpn-endpoint-id "$endpoint_id" \
      --destination-cidr-block "0.0.0.0/0" \
      --target-vpc-subnet-id "$subnet_id" \
      --region "$aws_region"
    # 可以加入錯誤檢查
}

# 主要的端點創建函式
# 參數: main_config_file, aws_region, vpc_id, subnet_id, vpn_cidr, server_cert_arn, client_cert_arn, vpn_name
create_vpn_endpoint_lib() {
    local main_config_file="$1"
    local aws_region="$2"
    local vpc_id="$3"
    local subnet_id="$4"
    local vpn_cidr="$5"
    local arg_server_cert_arn="$6"
    local arg_client_cert_arn="$7"
    local vpn_name="$8"

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
    endpoint_id=$(_create_aws_client_vpn_endpoint_ec "$vpn_cidr" "$arg_server_cert_arn" "$arg_client_cert_arn" "$vpn_name" "$aws_region")
    if [ $? -ne 0 ] || [ -z "$endpoint_id" ] || [ "$endpoint_id" == "null" ]; then
        echo -e "${RED}創建 VPN 端點失敗。中止。${NC}"
        return 1
    fi
    echo -e "${BLUE}端點 ID: $endpoint_id${NC}" # endpoint_id is a variable

    # 等待端點可用
    echo -e "${BLUE}等待 VPN 端點可用...${NC}"
    if ! aws ec2 wait client-vpn-endpoint-available --client-vpn-endpoint-id "$endpoint_id" --region "$aws_region"; then
        echo -e "${RED}等待 VPN 端點可用時發生錯誤或超時。${NC}"
        # 可以考慮是否需要刪除部分創建的資源
        return 1
    fi

    # 關聯子網路
    _associate_target_network_ec "$endpoint_id" "$subnet_id" "$aws_region"

    # 添加授權規則和路由
    _setup_authorization_and_routes_ec "$endpoint_id" "$vpc_cidr" "$subnet_id" "$aws_region"

    # 保存配置
    echo -e "${BLUE}保存配置到 \"$main_config_file\"...${NC}" # Quoted $main_config_file
    # 注意：AWS_REGION 應該已經在 config file 中了，如果 setup_aws_config 被調用過
    # 如果是首次創建，確保 AWS_REGION 也被寫入
    echo "ENDPOINT_ID=$endpoint_id" > "$main_config_file" # 覆蓋舊配置
    echo "AWS_REGION=$aws_region" >> "$main_config_file" # 使用傳入的 aws_region 參數
    echo "VPN_CIDR=$vpn_cidr" >> "$main_config_file"
    echo "VPN_NAME=$vpn_name" >> "$main_config_file"
    echo "SERVER_CERT_ARN=$arg_server_cert_arn" >> "$main_config_file" # 使用傳入的 ARN
    echo "CLIENT_CERT_ARN=$arg_client_cert_arn" >> "$main_config_file" # 使用傳入的 ARN
    echo "VPC_ID=$vpc_id" >> "$main_config_file"
    echo "VPC_CIDR=$vpc_cidr" >> "$main_config_file"
    echo "SUBNET_ID=$subnet_id" >> "$main_config_file"
    echo "MULTI_VPC_COUNT=0" >> "$main_config_file"

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
      jq -r '.Subnets[] | "子網路 ID: \\(.SubnetId), 可用區: \\(.AvailabilityZone), CIDR: \\(.CidrBlock), 類型: \\(if .MapPublicIpOnLaunch then "公有" else "私有" end)"'
    
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
    local association_result
    association_result=$(aws ec2 associate-client-vpn-target-network \
      --client-vpn-endpoint-id "$arg_endpoint_id" \
      --subnet-id "$subnet_to_associate_id" \
      --region "$arg_aws_region" 2>&1)
    
    if [ $? -ne 0 ]; then
        echo -e "${RED}關聯子網路 \"$subnet_to_associate_id\" 失敗: $association_result${NC}" # Quoted variable, association_result is a variable
        return 1
    fi
    
    local new_association_id
    new_association_id=$(echo "$association_result" | jq -r '.AssociationId')
    if [ -z "$new_association_id" ] || [ "$new_association_id" == "null" ]; then
        echo -e "${RED}關聯子網路後未能獲取 Association ID: $association_result${NC}" # association_result is a variable
        return 1
    fi
    echo -e "${BLUE}關聯 ID: $new_association_id${NC}" # new_association_id is a variable
    
    echo -e "${BLUE}添加授權規則...${NC}"
    if ! aws ec2 authorize-client-vpn-ingress \
      --client-vpn-endpoint-id "$arg_endpoint_id" \
      --target-network-cidr "$vpc_to_add_cidr" \
      --authorize-all-groups \
      --region "$arg_aws_region"; then
        echo -e "${RED}為 CIDR \"$vpc_to_add_cidr\" 添加授權規則失敗。${NC}" # Quoted variable
        return 1 
    fi
      
    local add_route_for_vpc
    read -p "是否為此 VPC ($vpc_to_add_id) 添加路由? (y/n): " add_route_for_vpc
    if [[ "$add_route_for_vpc" == "y" ]]; then
        echo -e "${BLUE}添加到 VPC \"$vpc_to_add_id\" 的路由...${NC}" # Quoted variable
        if ! aws ec2 create-client-vpn-route \
          --client-vpn-endpoint-id "$arg_endpoint_id" \
          --destination-cidr-block "$vpc_to_add_cidr" \
          --target-vpc-subnet-id "$subnet_to_associate_id" \
          --region "$arg_aws_region"; then
            echo -e "${RED}為 VPC \"$vpc_to_add_id\" (CIDR \"$vpc_to_add_cidr\") 創建路由到子網路 \"$subnet_to_associate_id\" 失敗。${NC}" # Quoted variables
        else
            echo -e "${GREEN}路由已添加${NC}"
        fi
    fi
    
    if [ ! -f "$main_config_file" ]; then
        echo -e "${RED}錯誤: 配置文件 \"$main_config_file\" 未找到，無法更新多 VPC 資訊。${NC}" # Quoted variable
        return 1
    fi

    local current_count
    current_count_line=$(grep "MULTI_VPC_COUNT=" "$main_config_file")
    if [ -z "$current_count_line" ]; then
        echo "MULTI_VPC_COUNT=0" >> "$main_config_file"
        current_count=0
    else
        current_count=$(echo "$current_count_line" | cut -d'=' -f2)
        if ! [[ "$current_count" =~ ^[0-9]+$ ]]; then
            log_message_core "警告: MULTI_VPC_COUNT in \"$main_config_file\" is not a valid number: '$current_count'. Resetting to 0." # Quoted variables
            echo -e "${YELLOW}警告: 配置文件中的 MULTI_VPC_COUNT 無效 ('$current_count')。將其重置為 0。${NC}" # current_count is a variable
            current_count=0
        fi
    fi

    local new_count=$((current_count + 1))
    local temp_config_file_assoc_one
    temp_config_file_assoc_one=$(mktemp "${main_config_file}.tmp_assoc_one.XXXXXX")
    trap "rm -f '$temp_config_file_assoc_one'" EXIT
    grep -v "MULTI_VPC_COUNT=" "$main_config_file" > "$temp_config_file_assoc_one"
    echo "MULTI_VPC_COUNT=$new_count" >> "$temp_config_file_assoc_one"
    mv "$temp_config_file_assoc_one" "$main_config_file"
    
    echo "MULTI_VPC_${new_count}=\"$vpc_to_add_id:$vpc_to_add_cidr:$subnet_to_associate_id:$new_association_id\"" >> "$main_config_file"
    
    log_message_core "單一 VPC \"$vpc_to_add_id\" 已成功關聯到端點 \"$arg_endpoint_id\" (lib)" # Quoted variables
    echo -e "${GREEN}VPC \"$vpc_to_add_id\" 已成功關聯到端點${NC}" # Quoted variable
    return 0
}


# 函式：關聯額外的 VPCs 到現有端點 (用於初始端點創建流程)
# 參數: main_config_file, aws_region, endpoint_id
associate_additional_vpc_lib() { # Renamed for clarity (plural)
    local main_config_file="$1"
    local arg_aws_region="$2"
    local arg_endpoint_id="$3"

    echo -e "\\n${CYAN}=== 關聯額外的 VPCs (來自 lib) ===${NC}"

    if [ -z "$arg_aws_region" ] || [ -z "$arg_endpoint_id" ] || [ -z "$main_config_file" ]; then
        echo -e "${RED}錯誤: associate_additional_vpc_lib 需要 main_config_file, aws_region 和 endpoint_id。${NC}"
        return 1
    fi

    while true; do
        read -p "是否要關聯一個額外的 VPC? (y/n): " add_another_vpc
        if [[ "$add_another_vpc" != "y" ]]; then
            break
        fi
        
        _associate_one_vpc_to_endpoint_lib "$main_config_file" "$arg_aws_region" "$arg_endpoint_id"
        local result=$?
        if [ $result -ne 0 ]; then
            echo -e "${RED}關聯 VPC 失敗。請檢查上述錯誤。${NC}"
            read -p "是否嘗試關聯另一個不同的 VPC? (y/n): " try_again
            if [[ "$try_again" != "y" ]]; then
                # Do not return 1 here, as the main endpoint creation might still be considered successful
                # The calling function (create_vpn_endpoint in main script) will decide overall success
                echo -e "${YELLOW}中止關聯額外的 VPCs。${NC}"
                break 
            fi
        fi
    done
    echo -e "${BLUE}完成額外 VPC 關聯流程。${NC}"
    return 0 # Always returns 0 from this function, individual failures handled above
}

# 函式：關聯一個指定的 VPC 到現有端點 (公開函式, 用於 'Add VPC to Endpoint' 選單)
# 參數: main_config_file, aws_region, endpoint_id
associate_single_vpc_lib() {
    local main_config_file="$1"
    local arg_aws_region="$2"
    local arg_endpoint_id="$3"

    echo -e "\\n${CYAN}=== 關聯單一 VPC (來自 lib) ===${NC}"

    if [ -z "$arg_aws_region" ] || [ -z "$arg_endpoint_id" ] || [ -z "$main_config_file" ]; then
        echo -e "${RED}錯誤: associate_single_vpc_lib 需要 main_config_file, aws_region 和 endpoint_id。${NC}"
        return 1
    fi
    
    _associate_one_vpc_to_endpoint_lib "$main_config_file" "$arg_aws_region" "$arg_endpoint_id"
    local result=$?
    
    if [ $result -eq 0 ]; then
        log_message_core "單一 VPC 關聯操作成功 (lib) for endpoint \"$arg_endpoint_id\"." # Quoted variable
        echo -e "${GREEN}單一 VPC 關聯操作成功完成 (lib)。${NC}"
    else
        log_message_core "錯誤: 單一 VPC 關聯操作失敗 (lib) for endpoint \"$arg_endpoint_id\"." # Quoted variable
        echo -e "${RED}單一 VPC 關聯過程中發生錯誤 (lib)。${NC}"
    fi
    return $result
}

# 函式：從端點解除 VPC 關聯
# 參數: main_config_file, aws_region, endpoint_id
disassociate_vpc_lib() {
    local main_config_file="$1"
    local arg_aws_region="$2"
    local arg_endpoint_id="$3"

    echo -e "\\n${CYAN}=== 從端點解除 VPC 關聯 (來自 lib) ===${NC}"

    if [ -z "$arg_aws_region" ] || [ -z "$arg_endpoint_id" ] || [ -z "$main_config_file" ]; then
        echo -e "${RED}錯誤: disassociate_vpc_lib 需要 main_config_file, aws_region 和 endpoint_id。${NC}"
        return 1
    fi
    if [ ! -f "$main_config_file" ]; then
        echo -e "${RED}錯誤: 配置文件 \"$main_config_file\" 未找到。${NC}" # Quoted variable
        return 1
    fi

    echo -e "${BLUE}當前關聯的網絡 (端點: \"$arg_endpoint_id\"):${NC}" # Quoted variable
    local networks_json
    networks_json=$(aws ec2 describe-client-vpn-target-networks \
      --client-vpn-endpoint-id "$arg_endpoint_id" \
      --region "$arg_aws_region" 2>/dev/null)

    if [ $? -ne 0 ] || [ -z "$networks_json" ] || [ "$(echo "$networks_json" | jq '.ClientVpnTargetNetworks | length')" -eq 0 ]; then
        echo -e "${YELLOW}端點 \"$arg_endpoint_id\" 沒有關聯的網絡。${NC}" # Quoted variable
        return 0 # Not an error, just nothing to do.
    fi
    
    echo "$networks_json" | jq -r '.ClientVpnTargetNetworks[] | "  關聯 ID: \\(.AssociationId), 子網路 ID: \\(.TargetNetworkId), VPC ID: \\(.VpcId), 狀態: \\(.Status.Code)"'
    
    local association_id_to_remove
    read -p "請輸入要移除的關聯 ID: " association_id_to_remove

    # Validate association_id exists for this endpoint
    local target_subnet_for_assoc
    target_subnet_for_assoc=$(echo "$networks_json" | jq -r --arg assoc_id "$association_id_to_remove" '.ClientVpnTargetNetworks[] | select(.AssociationId == $assoc_id) | .TargetNetworkId')

    if [ -z "$target_subnet_for_assoc" ] || [ "$target_subnet_for_assoc" == "null" ]; then
        echo -e "${RED}錯誤: 關聯 ID '$association_id_to_remove' 無效或不屬於此端點。${NC}" # association_id_to_remove is a variable
        return 1
    fi

    echo -e "${YELLOW}警告: 移除 VPC 關聯 (ID: \"$association_id_to_remove\", 子網路: \"$target_subnet_for_assoc\") 將斷開所有通過該子網路的連接。${NC}" # Quoted variables
    read -p "確認移除關聯? (y/n): " confirm_disassociate
    
    if [[ "$confirm_disassociate" != "y" ]]; then
        echo -e "${BLUE}操作已取消。${NC}"
        return 0
    fi
    
    echo -e "${BLUE}正在移除 VPC 關聯 (ID: \"$association_id_to_remove\")...${NC}" # Quoted variable
    if ! aws ec2 disassociate-client-vpn-target-network \
      --client-vpn-endpoint-id "$arg_endpoint_id" \
      --association-id "$association_id_to_remove" \
      --region "$arg_aws_region"; then
        echo -e "${RED}解除關聯 \"$association_id_to_remove\" 失敗。${NC}" # Quoted variable
        return 1
    fi
    
    echo -e "${BLUE}等待解除關聯完成...${NC}"
    if ! aws ec2 wait client-vpn-target-network-disassociated \
      --client-vpn-endpoint-id "$arg_endpoint_id" \
      --association-id "$association_id_to_remove" \
      --region "$arg_aws_region"; then
        echo -e "${RED}等待解除關聯 \"$association_id_to_remove\" 完成時發生錯誤或超時。${NC}" # Quoted variable
        # Proceed with config update, but log this issue.
        log_message_core "警告: 等待解除關聯 \"$association_id_to_remove\" 完成時發生錯誤或超時。" # Quoted variable
    fi
    echo -e "${GREEN}關聯 \"$association_id_to_remove\" 已成功解除。${NC}" # Quoted variable

    read -p "是否也移除相關的授權規則? (y/n): " remove_auth_rules
    if [[ "$remove_auth_rules" == "y" ]]; then
        echo -e "\\n${YELLOW}端點 \"$arg_endpoint_id\" 的現有授權規則:${NC}" # Quoted variable
        aws ec2 describe-client-vpn-authorization-rules \
          --client-vpn-endpoint-id "$arg_endpoint_id" \
          --region "$arg_aws_region" | jq -r '.AuthorizationRules[] | "  CIDR: \\(.DestinationCidr), 狀態: \\(.Status.Code)"'
        
        local auth_cidr_to_revoke
        read -p "請輸入要移除的授權規則 CIDR (如果適用): " auth_cidr_to_revoke
        if [ -n "$auth_cidr_to_revoke" ]; then
            echo -e "${BLUE}正在移除授權規則 \"$auth_cidr_to_revoke\"...${NC}" # Quoted variable
            if aws ec2 revoke-client-vpn-ingress \
              --client-vpn-endpoint-id "$arg_endpoint_id" \
              --target-network-cidr "$auth_cidr_to_revoke" \
              --revoke-all-groups \
              --region "$arg_aws_region"; then
                echo -e "${GREEN}授權規則 \"$auth_cidr_to_revoke\" 已移除。${NC}" # Quoted variable
                log_message_core "授權規則 \"$auth_cidr_to_revoke\" 已從端點 \"$arg_endpoint_id\" 移除 (lib)。" # Quoted variables
            else
                echo -e "${RED}移除授權規則 \"$auth_cidr_to_revoke\" 失敗。${NC}" # Quoted variable
            fi
        else
            echo -e "${BLUE}未指定要移除的授權規則 CIDR，跳過此步驟。${NC}"
        fi
    fi
    
    echo -e "${BLUE}正在更新配置文件 \"$main_config_file\"...${NC}" # Quoted variable
    local current_multi_vpc_count_line
    current_multi_vpc_count_line=$(grep "MULTI_VPC_COUNT=" "$main_config_file")
    local current_multi_vpc_count
    if [ -z "$current_multi_vpc_count_line" ]; then
        current_multi_vpc_count=0
    else
        current_multi_vpc_count=$(echo "$current_multi_vpc_count_line" | cut -d'=' -f2)
        if ! [[ "$current_multi_vpc_count" =~ ^[0-9]+$ ]]; then
             log_message_core "警告: 配置文件中的 MULTI_VPC_COUNT 無效 ('$current_multi_vpc_count')。視為 0." # current_multi_vpc_count is a variable
             current_multi_vpc_count=0
        fi
    fi

    if [ "$current_multi_vpc_count" -eq 0 ]; then
        echo -e "${YELLOW}配置文件中沒有 MULTI_VPC 條目，無需更新。${NC}"
        log_message_core "VPC 關聯 \"$association_id_to_remove\" 已從端點 \"$arg_endpoint_id\" 解除 (lib)。配置文件無需更新。" # Quoted variables
        return 0
    fi

    local temp_config_file_disassoc
    temp_config_file_disassoc=$(mktemp "${main_config_file}.tmp_disassoc.XXXXXX")
    trap "rm -f '$temp_config_file_disassoc'" EXIT
    # Copy lines that are NOT MULTI_VPC_COUNT and NOT MULTI_VPC_i
    grep -v "^MULTI_VPC_COUNT=" "$main_config_file" | grep -v "^MULTI_VPC_[0-9]\+=" > "$temp_config_file_disassoc"

    local new_vpc_idx=0
    local found_and_removed_from_config=false

    for (( i=1; i<=$current_multi_vpc_count; i++ )); do
        local vpc_entry_line
        vpc_entry_line=$(grep "^MULTI_VPC_$i=" "$main_config_file")
        if [ -n "$vpc_entry_line" ]; then
            local vpc_entry_value
            vpc_entry_value=$(echo "$vpc_entry_line" | cut -d'"' -f2)
            local entry_association_id
            entry_association_id=$(echo "$vpc_entry_value" | cut -d':' -f4)

            if [ "$entry_association_id" == "$association_id_to_remove" ]; then
                found_and_removed_from_config=true
                log_message_core "從配置文件中移除與關聯 ID \"$association_id_to_remove\" 匹配的條目: $vpc_entry_line" # Quoted variable, vpc_entry_line is a variable
            else
                new_vpc_idx=$((new_vpc_idx + 1))
                echo "MULTI_VPC_${new_vpc_idx}=\"$vpc_entry_value\"" >> "$temp_config_file_disassoc"
            fi
        fi
    done

    echo "MULTI_VPC_COUNT=$new_vpc_idx" >> "$temp_config_file_disassoc"
    mv "$temp_config_file_disassoc" "$main_config_file"

    if $found_and_removed_from_config; then
        echo -e "${GREEN}配置文件已更新。新的 MULTI_VPC_COUNT 為 $new_vpc_idx。${NC}" # new_vpc_idx is a number
    else
        echo -e "${YELLOW}未在配置文件中找到與關聯 ID \"$association_id_to_remove\" 匹配的條目。配置文件可能已手動更改或條目不存在。${NC}" # Quoted variable
    fi
    
    log_message_core "VPC 關聯 \"$association_id_to_remove\" 已從端點 \"$arg_endpoint_id\" 解除並更新配置文件 (lib)。" # Quoted variables
    echo -e "${GREEN}VPC 關聯解除操作完成。${NC}"
    return 0
}

# 函式：管理 VPN 端點的路由 (跨 VPC)
# 參數: main_config_file (not strictly needed if AWS_REGION and ENDPOINT_ID are passed), aws_region, endpoint_id
manage_routes_lib() {
    # local main_config_file="$1" # Not directly used, but kept for consistency if needed later
    local arg_aws_region="$1" # Shifted parameters as main_config_file is not used
    local arg_endpoint_id="$2"

    echo -e "\\n${CYAN}=== 跨 VPC 路由管理 (來自 lib) ===${NC}"

    if [ -z "$arg_aws_region" ] || [ -z "$arg_endpoint_id" ]; then
        echo -e "${RED}錯誤: manage_routes_lib 需要 aws_region 和 endpoint_id。${NC}"
        return 1
    fi

    echo -e "${BLUE}當前端點 ID: \"$arg_endpoint_id\"${NC}" # Quoted variable
    echo -e "${BLUE}當前 AWS 區域: \"$arg_aws_region\"${NC}" # Quoted variable
    echo -e ""
    echo -e "路由管理選項："
    echo -e "  ${GREEN}1.${NC} 列出所有路由 (顯示目標 VPC)"
    echo -e "  ${GREEN}2.${NC} 為特定 VPC 添加路由"
    echo -e "  ${GREEN}3.${NC} 刪除路由"
    echo -e "  ${GREEN}4.${NC} 返回"

    local route_choice_lib
    read -p "請選擇操作 (1-4): " route_choice_lib

    case $route_choice_lib in
        1)
            echo -e "\\n${BLUE}VPN 端點 \"$arg_endpoint_id\" 的路由表:${NC}" # Quoted variable
            local routes_json_lib
            routes_json_lib=$(aws ec2 describe-client-vpn-routes \
              --client-vpn-endpoint-id "$arg_endpoint_id" \
              --region "$arg_aws_region" 2>/dev/null)
            
            local routes_count_lib
            if ! routes_count_lib=$(echo "$routes_json_lib" | jq '.Routes | length' 2>/dev/null); then
                # 備用解析方法：使用 grep 統計路由數量
                routes_count_lib=$(echo "$routes_json_lib" | grep -c '"DestinationCidr"' || echo "0")
            fi
            
            if [ $? -ne 0 ] || [ -z "$routes_json_lib" ] || [ "$routes_count_lib" -eq 0 ]; then
                echo -e "${YELLOW}此端點沒有配置路由。${NC}"
            else
                echo "$routes_json_lib" | jq -c '.Routes[]' | while IFS= read -r route; do
                    local dest_cidr_lib target_subnet_lib status_lib origin_lib type_lib target_vpc_id_lib subnet_info_lib
                    dest_cidr_lib=$(echo "$route" | jq -r '.DestinationCidr')
                    target_subnet_lib=$(echo "$route" | jq -r '.TargetSubnet // .TargetVpcSubnetId') 
                    status_lib=$(echo "$route" | jq -r '.Status.Code')
                    origin_lib=$(echo "$route" | jq -r '.Origin')
                    type_lib=$(echo "$route" | jq -r '.Type')

                    target_vpc_id_lib="N/A"
                    if [ "$target_subnet_lib" != "null" ] && [ ! -z "$target_subnet_lib" ]; then
                        subnet_info_lib=$(aws ec2 describe-subnets --subnet-ids "$target_subnet_lib" --region "$arg_aws_region" 2>/dev/null)
                        if [ $? -eq 0 ] && [ ! -z "$subnet_info_lib" ] && [ "$(echo "$subnet_info_lib" | jq '.Subnets | length')" -gt 0 ]; then
                           target_vpc_id_lib=$(echo "$subnet_info_lib" | jq -r '.Subnets[0].VpcId')
                        else
                           target_vpc_id_lib="無法獲取 (子網路 $target_subnet_lib)" # target_subnet_lib is a variable
                        fi
                    fi
                    
                    echo -e "  目標 CIDR: ${YELLOW}$dest_cidr_lib${NC}" # dest_cidr_lib is a variable
                    echo -e "    目標子網路: $target_subnet_lib" # target_subnet_lib is a variable
                    echo -e "    目標 VPC ID: $target_vpc_id_lib" # target_vpc_id_lib is a variable
                    echo -e "    狀態: $status_lib" # status_lib is a variable
                    echo -e "    來源: $origin_lib" # origin_lib is a variable
                    echo -e "    類型: $type_lib" # type_lib is a variable
                    echo -e "    ------------------------------------"
                done
            fi
            ;;
        2)
            echo -e "\\n${BLUE}為特定 VPC 添加路由...${NC}"
            discover_available_vpcs_core "$arg_aws_region" # Uses core function
            
            local target_vpc_id_for_route_lib vpc_info_for_route_lib target_vpc_cidr_for_route_lib
            read -p "請輸入目標 VPC ID (路由將指向此 VPC 中的一個已關聯子網路): " target_vpc_id_for_route_lib
            
            vpc_info_for_route_lib=$(aws ec2 describe-vpcs --vpc-ids "$target_vpc_id_for_route_lib" --region "$arg_aws_region" 2>/dev/null)
            if [ $? -ne 0 ]; then
                echo -e "${RED}無法找到 VPC: \"$target_vpc_id_for_route_lib\"${NC}" # Quoted variable
            else
                target_vpc_cidr_for_route_lib=$(echo "$vpc_info_for_route_lib" | jq -r '.Vpcs[0].CidrBlock')
                echo -e "${BLUE}目標 VPC (\"$target_vpc_id_for_route_lib\") 的 CIDR: \"$target_vpc_cidr_for_route_lib\"${NC}" # Quoted variables

                echo -e "\\n${YELLOW}VPC \"$target_vpc_id_for_route_lib\" 中已關聯到 VPN 端點 \"$arg_endpoint_id\" 的子網路:${NC}" # Quoted variables
                
                local associated_subnets_in_vpc_json_lib
                associated_subnets_in_vpc_json_lib=$(aws ec2 describe-client-vpn-target-networks \
                    --client-vpn-endpoint-id "$arg_endpoint_id" \
                    --filters "Name=vpc-id,Values=$target_vpc_id_for_route_lib" \
                    --region "$arg_aws_region" 2>/dev/null)

                if [ $? -ne 0 ] || [ -z "$associated_subnets_in_vpc_json_lib" ] || [ "$(echo "$associated_subnets_in_vpc_json_lib" | jq '.ClientVpnTargetNetworks | length')" -eq 0 ]; then
                    echo -e "${RED}VPC \"$target_vpc_id_for_route_lib\" 中沒有已關聯到此 VPN 端點的子網路。請先關聯子網路。${NC}" # Quoted variable
                else
                    echo "$associated_subnets_in_vpc_json_lib" | jq -r '.ClientVpnTargetNetworks[] | .TargetNetworkId' | while IFS= read -r assoc_subnet_id_lib; do
                        local subnet_details_lib
                        subnet_details_lib=$(aws ec2 describe-subnets --subnet-ids "$assoc_subnet_id_lib" --region "$arg_aws_region" | jq -r '.Subnets[0] | "  - 子網路 ID: \\(.SubnetId), CIDR: \\(.CidrBlock), 可用區: \\(.AvailabilityZone)"')
                        echo "$subnet_details_lib"
                    done
                    
                    local route_target_subnet_id_lib is_valid_subnet_lib route_dest_cidr_lib
                    read -p "請輸入目標子網路 ID (用於此路由，必須是上面列出的子網路之一): " route_target_subnet_id_lib
                    
                    # 驗證子網路 ID 是否存在於關聯列表中，含備用方法
                    if ! is_valid_subnet_lib=$(echo "$associated_subnets_in_vpc_json_lib" | jq -e --arg sn "$route_target_subnet_id_lib" '.ClientVpnTargetNetworks[] | select(.TargetNetworkId == $sn)' 2>/dev/null); then
                        # 備用驗證方法：使用 grep 檢查子網路 ID 是否存在
                        if echo "$associated_subnets_in_vpc_json_lib" | grep -q "\"TargetNetworkId\":\"$route_target_subnet_id_lib\""; then
                            is_valid_subnet_lib="found" # 非空值表示找到
                        else
                            is_valid_subnet_lib=""
                        fi
                    fi
                    
                    if [ -z "$is_valid_subnet_lib" ]; then
                        echo -e "${RED}選擇的子網路 \"$route_target_subnet_id_lib\" 無效或未關聯到此 VPC/端點。${NC}" # Quoted variable
                    else
                        read -p "請輸入目標 CIDR (預設為 VPC CIDR \"$target_vpc_cidr_for_route_lib\", 或輸入 0.0.0.0/0 以路由所有流量): " route_dest_cidr_lib
                        route_dest_cidr_lib=${route_dest_cidr_lib:-$target_vpc_cidr_for_route_lib}

                        echo -e "${BLUE}正在添加路由: \"$route_dest_cidr_lib\" -> \"$route_target_subnet_id_lib\"...${NC}" # Quoted variables
                        if aws ec2 create-client-vpn-route \
                          --client-vpn-endpoint-id "$arg_endpoint_id" \
                          --destination-cidr-block "$route_dest_cidr_lib" \
                          --target-vpc-subnet-id "$route_target_subnet_id_lib" \
                          --description "Route to $target_vpc_id_for_route_lib via $route_target_subnet_id_lib" \
                          --region "$arg_aws_region"; then
                            echo -e "${GREEN}路由已添加。${NC}"
                            log_message_core "路由已添加 (lib): \"$route_dest_cidr_lib\" -> \"$route_target_subnet_id_lib\" for endpoint \"$arg_endpoint_id\"" # Quoted variables
                        else
                            echo -e "${RED}添加路由失敗。${NC}"
                            log_message_core "錯誤: 添加路由失敗 (lib): \"$route_dest_cidr_lib\" -> \"$route_target_subnet_id_lib\" for endpoint \"$arg_endpoint_id\"" # Quoted variables
                        fi
                    fi
                fi
            fi
            ;;
        3)
            echo -e "\\n${BLUE}刪除路由...${NC}"
            local routes_json_del_lib
            routes_json_del_lib=$(aws ec2 describe-client-vpn-routes \
              --client-vpn-endpoint-id "$arg_endpoint_id" \
              --region "$arg_aws_region" 2>/dev/null)
            
            local routes_del_count_lib
            if ! routes_del_count_lib=$(echo "$routes_json_del_lib" | jq '.Routes | length' 2>/dev/null); then
                # 備用解析方法：使用 grep 統計路由數量
                routes_del_count_lib=$(echo "$routes_json_del_lib" | grep -c '"DestinationCidr"' || echo "0")
            fi
            
            if [ $? -ne 0 ] || [ -z "$routes_json_del_lib" ] || [ "$routes_del_count_lib" -eq 0 ]; then
                echo -e "${YELLOW}此端點沒有配置路由可供刪除。${NC}"
            else
                echo -e "${YELLOW}現有路由:${NC}"
                echo "$routes_json_del_lib" | jq -r '.Routes[] | "  目標 CIDR: \\(.DestinationCidr), 目標子網路: \\(.TargetSubnet // .TargetVpcSubnetId), 狀態: \\(.Status.Code), 來源: \\(.Origin)"'
                
                local del_dest_cidr_lib del_target_subnet_id_lib
                read -p "請輸入要刪除路由的目標 CIDR: " del_dest_cidr_lib
                read -p "請輸入要刪除路由的目標子網路 ID: " del_target_subnet_id_lib

                if [ -z "$del_dest_cidr_lib" ]; then
                    echo -e "${RED}目標 CIDR 不能为空。${NC}"
                elif [ -z "$del_target_subnet_id_lib" ]; then
                    echo -e "${RED}刪除 Client VPN 路由需要目標子網路 ID。${NC}"
                else
                    echo -e "${BLUE}正在刪除路由: \"$del_dest_cidr_lib\" (目標子網路: \"$del_target_subnet_id_lib\")...${NC}" # Quoted variables
                    local route_to_delete_info_lib origin_of_route_to_delete_lib
                    route_to_delete_info_lib=$(echo "$routes_json_del_lib" | jq -r --arg dc "$del_dest_cidr_lib" --arg ts "$del_target_subnet_id_lib" '.Routes[] | select(.DestinationCidr == $dc and (.TargetSubnet // .TargetVpcSubnetId) == $ts)')
                    
                    if [ -z "$route_to_delete_info_lib" ]; then
                        echo -e "${RED}找不到匹配的路由: CIDR \"$del_dest_cidr_lib\", 子網路 \"$del_target_subnet_id_lib\" ${NC}" # Quoted variables
                    else
                        origin_of_route_to_delete_lib=$(echo "$route_to_delete_info_lib" | jq -r '.Origin')
                        # Routes with origin 'associate' (from subnet association) or 'add-route' (manually added) can be deleted.
                        # 'local' routes (VPN client CIDR) cannot be deleted.
                        if [ "$origin_of_route_to_delete_lib" == "associate" ] || [ "$origin_of_route_to_delete_lib" == "add-route" ]; then
                             if aws ec2 delete-client-vpn-route \
                                --client-vpn-endpoint-id "$arg_endpoint_id" \
                                --destination-cidr-block "$del_dest_cidr_lib" \
                                --target-vpc-subnet-id "$del_target_subnet_id_lib" \
                                --region "$arg_aws_region"; then
                                echo -e "${GREEN}路由已刪除。${NC}"
                                log_message_core "路由已刪除 (lib): \"$del_dest_cidr_lib\" (目標子網路: \"$del_target_subnet_id_lib\") from endpoint \"$arg_endpoint_id\"" # Quoted variables
                             else
                                echo -e "${RED}刪除路由失敗。${NC}"
                                log_message_core "錯誤: 刪除路由失敗 (lib): \"$del_dest_cidr_lib\" (目標子網路: \"$del_target_subnet_id_lib\") from endpoint \"$arg_endpoint_id\"" # Quoted variables
                             fi
                        else
                             echo -e "${RED}無法刪除此路由。來源為 '$origin_of_route_to_delete_lib'。通常只有手動添加的路由 ('add-route') 或因子網路關聯而創建的路由 ('associate') 可以刪除。${NC}" # origin_of_route_to_delete_lib is a variable
                             echo -e "${YELLOW}提示: 'local' 路由 (VPN Client CIDR) 不能被刪除。${NC}"
                        fi
                    fi
                fi
            fi
            ;;
        4)
            return 0 # Success, returning to caller
            ;;
        *)
            echo -e "${RED}無效選擇${NC}"
            ;;
    esac
    
    # For options 1, 2, 3, after execution, they will fall through here.
    # The main script's manage_cross_vpc_routes will handle the "press any key"
    return 0 # Indicate successful execution of a menu item or return from menu
}

# 函式：顯示多 VPC 網路拓撲
# 參數: main_config_file, aws_region, endpoint_id, vpn_cidr (from config), 
#       primary_vpc_id (from config), primary_vpc_cidr (from config), primary_subnet_id (from config)
show_multi_vpc_topology_lib() {
    local main_config_file="$1"
    local arg_aws_region="$2"
    local arg_endpoint_id="$3"
    local arg_vpn_cidr="$4"
    local arg_primary_vpc_id="$5"
    local arg_primary_vpc_cidr="$6"
    local arg_primary_subnet_id="$7"

    echo -e "\\n${CYAN}=== 多 VPC 網路拓撲 (來自 lib) ===${NC}"

    if [ -z "$main_config_file" ] || [ -z "$arg_aws_region" ] || [ -z "$arg_endpoint_id" ] || \
       [ -z "$arg_vpn_cidr" ] || [ -z "$arg_primary_vpc_id" ] || [ -z "$arg_primary_vpc_cidr" ] || \
       [ -z "$arg_primary_subnet_id" ]; then
        echo -e "${RED}錯誤: show_multi_vpc_topology_lib 需要所有配置參數。${NC}"
        return 1
    fi
    if [ ! -f "$main_config_file" ]; then
        echo -e "${RED}錯誤: 配置文件 \"$main_config_file\" 未找到。${NC}" # Quoted variable
        return 1
    fi

    echo -e "${BLUE}VPN 端點: \"$arg_endpoint_id\"${NC}" # Quoted variable
    echo -e "${BLUE}VPN CIDR: \"$arg_vpn_cidr\"${NC}" # Quoted variable
    echo -e ""
    
    # 顯示主要 VPC
    echo -e "${YELLOW}主要 VPC:${NC}"
    echo -e "  VPC ID: \"$arg_primary_vpc_id\"" # Quoted variable
    echo -e "  CIDR: \"$arg_primary_vpc_cidr\"" # Quoted variable
    echo -e "  子網路: \"$arg_primary_subnet_id\"" # Quoted variable
    echo -e ""
    
    # 顯示額外的 VPCs
    local multi_vpc_count_line
    multi_vpc_count_line=$(grep "MULTI_VPC_COUNT=" "$main_config_file")
    local multi_vpc_count=0
    if [ -n "$multi_vpc_count_line" ]; then
        multi_vpc_count=$(echo "$multi_vpc_count_line" | cut -d'=' -f2)
        if ! [[ "$multi_vpc_count" =~ ^[0-9]+$ ]]; then
            log_message_core "警告: 配置文件中的 MULTI_VPC_COUNT 無效 ('$multi_vpc_count')。視為 0." # multi_vpc_count is a variable
            multi_vpc_count=0
        fi
    fi
        
    if [ "$multi_vpc_count" -gt 0 ]; then
        echo -e "${YELLOW}額外的 VPCs ($multi_vpc_count):${NC}" # multi_vpc_count is a number
        
        for ((i=1; i<=$multi_vpc_count; i++)); do
            local vpc_info_line vpc_info vpc_id vpc_cidr subnet_id association_id
            vpc_info_line=$(grep "MULTI_VPC_$i=" "$main_config_file")
            if [ -n "$vpc_info_line" ]; then
                vpc_info=$(echo "$vpc_info_line" | cut -d'"' -f2)
                if [ -n "$vpc_info" ]; then
                    vpc_id=$(echo "$vpc_info" | cut -d':' -f1)
                    vpc_cidr=$(echo "$vpc_info" | cut -d':' -f2)
                    subnet_id=$(echo "$vpc_info" | cut -d':' -f3)
                    association_id=$(echo "$vpc_info" | cut -d':' -f4)
                    
                    echo -e "  VPC $i:" # i is a number
                    echo -e "    VPC ID: \"$vpc_id\"" # Quoted variable
                    echo -e "    CIDR: \"$vpc_cidr\"" # Quoted variable
                    echo -e "    子網路: \"$subnet_id\"" # Quoted variable
                    echo -e "    關聯 ID: \"$association_id\"" # Quoted variable
                    echo -e ""
                fi
            fi
        done
    else
        echo -e "${YELLOW}目前僅關聯主要 VPC${NC}"
    fi
    
    # 顯示當前連接統計
    echo -e "${BLUE}關聯網路統計:${NC}"
    local network_count_lib
    local network_count_json_lib
    network_count_json_lib=$(aws ec2 describe-client-vpn-target-networks \
      --client-vpn-endpoint-id "$arg_endpoint_id" \
      --region "$arg_aws_region")
    
    if ! network_count_lib=$(echo "$network_count_json_lib" | jq '.ClientVpnTargetNetworks | length' 2>/dev/null); then
        # 備用解析方法：使用 grep 統計網絡數量
        network_count_lib=$(echo "$network_count_json_lib" | grep -c '"TargetNetworkId"' || echo "0")
    fi
    
    # 驗證解析結果
    if validate_json_parse_result "$network_count_lib" "網絡數量"; then
        echo -e "  總關聯網路數: $network_count_lib"
    else
        echo -e "  ${RED}無法獲取關聯網路統計。${NC}"
    fi
    
    # 顯示授權規則
    echo -e "\\n${BLUE}授權規則:${NC}"
    if ! aws ec2 describe-client-vpn-authorization-rules \
      --client-vpn-endpoint-id "$arg_endpoint_id" \
      --region "$arg_aws_region" | jq -r '.AuthorizationRules[] | "  CIDR: \\(.DestinationCidr), 狀態: \\(.Status.Code)"'; then
        echo -e "  ${RED}無法獲取授權規則。${NC}"
    fi
    
    log_message_core "已顯示端點 \"$arg_endpoint_id\" 的多 VPC 拓撲 (lib)" # Quoted variable
    return 0
}

# 函式：批量管理 VPC 授權規則
# 參數: aws_region, endpoint_id
manage_batch_vpc_auth_lib() {
    local arg_aws_region="$1"
    local arg_endpoint_id="$2"

    echo -e "\\n${CYAN}=== 批量管理 VPC 授權規則 (來自 lib) ===${NC}"

    if [ -z "$arg_aws_region" ] || [ -z "$arg_endpoint_id" ]; then
        echo -e "${RED}錯誤: manage_batch_vpc_auth_lib 需要 aws_region 和 endpoint_id。${NC}"
        return 1
    fi

    echo -e "${BLUE}當前端點 ID: $arg_endpoint_id${NC}" # Quoted variable
    echo -e "${BLUE}當前 AWS 區域: $arg_aws_region${NC}" # Quoted variable
    echo -e ""
    echo -e "批量操作選項："
    echo -e "  ${GREEN}1.${NC} 為所有關聯 VPC 添加相同授權規則 (通常指授權訪問目標網路 CIDR)"
    echo -e "  ${GREEN}2.${NC} 移除特定 CIDR 的所有授權規則"
    echo -e "  ${GREEN}3.${NC} 查看所有授權規則總覽"
    echo -e "  ${GREEN}4.${NC} 返回"
    
    local choice_lib
    read -p "請選擇操作 (1-4): " choice_lib
    
    case $choice_lib in
        1)
            local auth_cidr_lib
            read -p "請輸入要添加的授權規則的目標網路 CIDR (例如，一個 VPC 的 CIDR 或 0.0.0.0/0): " auth_cidr_lib
            if [ -z "$auth_cidr_lib" ]; then
                echo -e "${RED}目標網路 CIDR 不可為空。${NC}"
                return 1 # Indicate failure or loop back
            fi
            
            # Client VPN 授權規則是針對整個端點的，而不是針對特定關聯的 VPC。
            # "為所有關聯 VPC 添加相同授權規則" 通常意味著授權客戶端訪問某個目標網路。
            # 如果目標是授權訪問 *每個* 關聯 VPC 的 CIDR，則需要遍歷每個 VPC 並單獨添加。
            # 目前 AWS CLI `authorize-client-vpn-ingress` 的 `--target-network-cidr` 是指目標網路，
            # `--authorize-all-groups` 允許所有客戶端組訪問該目標。
            # 這裡我們假設用戶想要為端點添加一個通用的授權規則。

            echo -e "${BLUE}正在為端點 \"$arg_endpoint_id\" 添加授權規則以訪問目標網路 \"$auth_cidr_lib\"...${NC}" # Quoted variables
            read -p "確認添加? (y/n): " confirm_lib
            if [[ "$confirm_lib" == "y" ]]; then
                if aws ec2 authorize-client-vpn-ingress \
                  --client-vpn-endpoint-id "$arg_endpoint_id" \
                  --target-network-cidr "$auth_cidr_lib" \
                  --authorize-all-groups \
                  --description "Batch auth rule added via script lib" \
                  --region "$arg_aws_region"; then
                    echo -e "${GREEN}授權規則已添加: \"$auth_cidr_lib\" ${NC}" # Quoted variable
                    log_message_core "授權規則已添加 (lib): \"$auth_cidr_lib\" for endpoint \"$arg_endpoint_id\"" # Quoted variables
                else
                    echo -e "${RED}添加授權規則 \"$auth_cidr_lib\" 失敗。${NC}" # Quoted variable
                    log_message_core "錯誤: 添加授權規則失敗 (lib): \"$auth_cidr_lib\" for endpoint \"$arg_endpoint_id\"" # Quoted variables
                fi
            else
                echo -e "${BLUE}操作已取消。${NC}"
            fi
            ;;
        2)
            echo -e "\\n${BLUE}現有的授權規則 (端點: \"$arg_endpoint_id\"):${NC}" # Quoted variable
            local auth_rules_json_lib
            auth_rules_json_lib=$(aws ec2 describe-client-vpn-authorization-rules \
              --client-vpn-endpoint-id "$arg_endpoint_id" \
              --region "$arg_aws_region" 2>/dev/null)

            local auth_rules_count_lib
            if ! auth_rules_count_lib=$(echo "$auth_rules_json_lib" | jq '.AuthorizationRules | length' 2>/dev/null); then
                # 備用解析方法：使用 grep 統計授權規則數量
                auth_rules_count_lib=$(echo "$auth_rules_json_lib" | grep -c '"DestinationCidr"' || echo "0")
            fi

            if [ $? -ne 0 ] || [ -z "$auth_rules_json_lib" ] || [ "$auth_rules_count_lib" -eq 0 ]; then
                echo -e "${YELLOW}端點 \"$arg_endpoint_id\" 沒有配置授權規則。${NC}" # Quoted variable
            else
                echo "$auth_rules_json_lib" | jq -r '.AuthorizationRules[] | "  目標 CIDR: \\(.DestinationCidr), 狀態: \\(.Status.Code), 描述: \\(.Description // "N/A")"'
                
                local revoke_cidr_lib
                read -p "請輸入要移除授權規則的目標網路 CIDR: " revoke_cidr_lib
                if [ -z "$revoke_cidr_lib" ]; then
                    echo -e "${RED}目標網路 CIDR 不可為空。${NC}"
                    return 1 # Indicate failure or loop back
                fi

                # 驗證該規則是否存在，含備用方法
                local rule_exists_lib
                if ! rule_exists_lib=$(echo "$auth_rules_json_lib" | jq -e --arg rc "$revoke_cidr_lib" '.AuthorizationRules[] | select(.DestinationCidr == $rc)' 2>/dev/null); then
                    # 備用驗證方法：使用 grep 檢查 CIDR 是否存在
                    if echo "$auth_rules_json_lib" | grep -q "\"DestinationCidr\":\"$revoke_cidr_lib\""; then
                        rule_exists_lib="found" # 非空值表示找到
                    else
                        rule_exists_lib=""
                    fi
                fi
                if [ -z "$rule_exists_lib" ]; then
                    echo -e "${RED}找不到目標 CIDR 為 '$revoke_cidr_lib' 的授權規則。${NC}" # revoke_cidr_lib is a variable
                else
                    echo -e "${YELLOW}警告: 您即將移除目標 CIDR 為 '$revoke_cidr_lib' 的授權規則。${NC}" # revoke_cidr_lib is a variable
                    read -p "確認移除? (y/n): " confirm_revoke_lib
                    if [[ "$confirm_revoke_lib" == "y" ]]; then
                        if aws ec2 revoke-client-vpn-ingress \
                          --client-vpn-endpoint-id "$arg_endpoint_id" \
                          --target-network-cidr "$revoke_cidr_lib" \
                          --revoke-all-groups \
                          --region "$arg_aws_region"; then
                            echo -e "${GREEN}授權規則 \"$revoke_cidr_lib\" 已移除。${NC}" # Quoted variable
                            log_message_core "授權規則已移除 (lib): \"$revoke_cidr_lib\" from endpoint \"$arg_endpoint_id\"" # Quoted variables
                        else
                            echo -e "${RED}移除授權規則 \"$revoke_cidr_lib\" 失敗。${NC}" # Quoted variable
                            log_message_core "錯誤: 移除授權規則失敗 (lib): \"$revoke_cidr_lib\" from endpoint \"$arg_endpoint_id\"" # Quoted variables
                        fi
                    else
                        echo -e "${BLUE}操作已取消。${NC}"
                    fi
                fi
            fi
            ;;
        3)
            echo -e "\\n${BLUE}所有授權規則總覽 (端點: \"$arg_endpoint_id\"):${NC}" # Quoted variable
            local auth_rules_overview_lib
            auth_rules_overview_lib=$(aws ec2 describe-client-vpn-authorization-rules \
              --client-vpn-endpoint-id "$arg_endpoint_id" \
              --region "$arg_aws_region" 2>/dev/null)

            local auth_overview_count_lib
            if ! auth_overview_count_lib=$(echo "$auth_rules_overview_lib" | jq '.AuthorizationRules | length' 2>/dev/null); then
                # 備用解析方法：使用 grep 統計授權規則數量
                auth_overview_count_lib=$(echo "$auth_rules_overview_lib" | grep -c '"DestinationCidr"' || echo "0")
            fi

            if [ $? -ne 0 ] || [ -z "$auth_rules_overview_lib" ] || [ "$auth_overview_count_lib" -eq 0 ]; then
                echo -e "${YELLOW}端點 \"$arg_endpoint_id\" 沒有配置授權規則。${NC}" # Quoted variable
            else
                echo "$auth_rules_overview_lib" | jq -r '.AuthorizationRules[] | 
                "  目標 CIDR: \\(.DestinationCidr)
    狀態: \\(.Status.Code)
    描述: \\(.Description // "無描述")
    群組 ID: \\(.GroupId // "所有群組")
    ----------------------------------------"'
            fi
            ;;
        4)
            return 0 # Success, returning to caller
            ;;
        *)
            echo -e "${RED}無效選擇${NC}"
            ;;
    esac
    return 0 # Indicate successful execution of a menu item
}

# 函式：添加授權規則到 VPN 端點
# 參數: aws_region, endpoint_id
add_authorization_rule_lib() {
    local arg_aws_region="$1"
    local arg_endpoint_id="$2"

    echo -e "\n${CYAN}=== 添加授權規則 (來自 lib) ===${NC}"

    if [ -z "$arg_aws_region" ] || [ -z "$arg_endpoint_id" ]; then
        echo -e "${RED}錯誤: add_authorization_rule_lib 需要 aws_region 和 endpoint_id。${NC}"
        return 1
    fi

    echo -e "${BLUE}當前端點 ID: $arg_endpoint_id${NC}"
    echo -e "${BLUE}當前 AWS 區域: $arg_aws_region${NC}"
    
    local auth_cidr_lib
    read -p "請輸入要授權的目標網路 CIDR 範圍 (例如 10.0.0.0/16 或 0.0.0.0/0): " auth_cidr_lib
    if [ -z "$auth_cidr_lib" ]; then
        echo -e "${RED}目標網路 CIDR 不可為空。${NC}"
        return 1
    fi

    local auth_desc_lib
    read -p "請輸入此授權規則的描述 (可選): " auth_desc_lib

    echo -e "${BLUE}正在為端點 $arg_endpoint_id 添加授權規則以訪問目標網路 $auth_cidr_lib...${NC}"
    if aws ec2 authorize-client-vpn-ingress \
      --client-vpn-endpoint-id "$arg_endpoint_id" \
      --target-network-cidr "$auth_cidr_lib" \
      --authorize-all-groups \
      ${auth_desc_lib:+"--description"} ${auth_desc_lib:+"$auth_desc_lib"} \
      --region "$arg_aws_region"; then
        echo -e "${GREEN}授權規則已成功添加: $auth_cidr_lib ${NC}"
        log_message_core "授權規則已添加 (lib): $auth_cidr_lib for endpoint $arg_endpoint_id"
        return 0
    else
        echo -e "${RED}添加授權規則 $auth_cidr_lib 失敗。${NC}"
        log_message_core "錯誤: 添加授權規則失敗 (lib): $auth_cidr_lib for endpoint $arg_endpoint_id"
        return 1
    fi
}

# 函式：移除 VPN 端點的授權規則
# 參數: aws_region, endpoint_id
remove_authorization_rule_lib() {
    local arg_aws_region="$1"
    local arg_endpoint_id="$2"

    echo -e "\n${CYAN}=== 移除授權規則 (來自 lib) ===${NC}"

    if [ -z "$arg_aws_region" ] || [ -z "$arg_endpoint_id" ]; then
        echo -e "${RED}錯誤: remove_authorization_rule_lib 需要 aws_region 和 endpoint_id。${NC}"
        return 1
    fi

    echo -e "${BLUE}當前端點 ID: $arg_endpoint_id${NC}"
    echo -e "${BLUE}當前 AWS 區域: $arg_aws_region${NC}"

    echo -e "\n${BLUE}現有的授權規則:${NC}"
    local auth_rules_json_lib
    auth_rules_json_lib=$(aws ec2 describe-client-vpn-authorization-rules \
        --client-vpn-endpoint-id "$arg_endpoint_id" \
        --region "$arg_aws_region" 2>/dev/null)

    local auth_rules_lib_count
    if ! auth_rules_lib_count=$(echo "$auth_rules_json_lib" | jq '.AuthorizationRules | length' 2>/dev/null); then
        # 備用解析方法：使用 grep 統計授權規則數量
        auth_rules_lib_count=$(echo "$auth_rules_json_lib" | grep -c '"DestinationCidr"' || echo "0")
    fi

    if [ $? -eq 0 ] && [ -n "$auth_rules_json_lib" ] && [ "$auth_rules_lib_count" -gt 0 ]; then
        echo "$auth_rules_json_lib" | jq -r '.AuthorizationRules[] | "  目標 CIDR: \\(.DestinationCidr), 狀態: \\(.Status.Code), 描述: \\(.Description // "N/A")"'
        
        local revoke_cidr_lib
        read -p "請輸入要移除授權規則的目標網路 CIDR: " revoke_cidr_lib
        if [ -z "$revoke_cidr_lib" ]; then
            echo -e "${RED}目標網路 CIDR 不可為空。${NC}"
            return 1 # Indicate failure or loop back
        fi

        # 驗證該規則是否存在，含備用方法
        local rule_exists_lib
        if ! rule_exists_lib=$(echo "$auth_rules_json_lib" | jq -e --arg rc "$revoke_cidr_lib" '.AuthorizationRules[] | select(.DestinationCidr == $rc)' 2>/dev/null); then
            # 備用驗證方法：使用 grep 檢查 CIDR 是否存在
            if echo "$auth_rules_json_lib" | grep -q "\"DestinationCidr\":\"$revoke_cidr_lib\""; then
                rule_exists_lib="found" # 非空值表示找到
            else
                rule_exists_lib=""
            fi
        fi
        if [ -z "$rule_exists_lib" ]; then
            echo -e "${RED}找不到目標 CIDR 為 '$revoke_cidr_lib' 的授權規則。${NC}" # revoke_cidr_lib is a variable
        else
            echo -e "${YELLOW}警告: 您即將移除目標 CIDR 為 '$revoke_cidr_lib' 的授權規則。${NC}" # revoke_cidr_lib is a variable
            read -p "確認移除? (y/n): " confirm_revoke_lib
            if [[ "$confirm_revoke_lib" == "y" ]]; then
                if aws ec2 revoke-client-vpn-ingress \
                  --client-vpn-endpoint-id "$arg_endpoint_id" \
                  --target-network-cidr "$revoke_cidr_lib" \
                  --revoke-all-groups \
                  --region "$arg_aws_region"; then
                    echo -e "${GREEN}授權規則 \"$revoke_cidr_lib\" 已移除。${NC}" # Quoted variable
                    log_message_core "授權規則已移除 (lib): $revoke_cidr_lib from endpoint $arg_endpoint_id" # Quoted variables
                else
                    echo -e "${RED}移除授權規則 \"$revoke_cidr_lib\" 失敗。${NC}" # Quoted variable
                    log_message_core "錯誤: 移除授權規則失敗 (lib): $revoke_cidr_lib from endpoint $arg_endpoint_id" # Quoted variables
                fi
            else
                echo -e "${BLUE}操作已取消。${NC}"
            fi
        fi
    else
        echo -e "${YELLOW}端點 $arg_endpoint_id 沒有配置授權規則，或無法獲取資訊。${NC}"
    fi
}

# 函式：查看 VPN 端點的路由表
# 參數: aws_region, endpoint_id
view_route_table_lib() {
    local arg_aws_region="$1"
    local arg_endpoint_id="$2"

    echo -e "\n${CYAN}=== 查看路由表 (來自 lib) ===${NC}"

    if [ -z "$arg_aws_region" ] || [ -z "$arg_endpoint_id" ]; then
        echo -e "${RED}錯誤: view_route_table_lib 需要 aws_region 和 endpoint_id。${NC}"
        return 1
    fi

    echo -e "${BLUE}當前端點 ID: $arg_endpoint_id${NC}"
    echo -e "${BLUE}當前 AWS 區域: $arg_aws_region${NC}"
    echo -e "\n${BLUE}路由表:${NC}"

    local routes_json_lib
    routes_json_lib=$(aws ec2 describe-client-vpn-routes \
        --client-vpn-endpoint-id "$arg_endpoint_id" \
        --region "$arg_aws_region" 2>/dev/null)

    if [ $? -ne 0 ] || [ -z "$routes_json_lib" ] || [ "$(echo "$routes_json_lib" | jq '.Routes | length')" -eq 0 ]; then
        echo -e "${YELLOW}此端點沒有配置路由。${NC}"
        log_message_core "端點 $arg_endpoint_id 沒有配置路由 (lib)。"
        return 0 # Not an error, just no routes to show
    fi

    echo "$routes_json_lib" | jq -r '.Routes[] | 
    "  目標 CIDR: \\(.DestinationCidr)
    目標子網路: \\(.TargetSubnet // .TargetVpcSubnetId)
    狀態: \\(.Status.Code)
    來源: \\(.Origin)
    類型: \\(.Type // "N/A")
    描述: \\(.Description // "無描述")
    ------------------------------------"'
    
    log_message_core "已顯示端點 $arg_endpoint_id 的路由表 (lib)。"
    return 0
}

# 函式：添加路由到 VPN 端點
# 參數: aws_region, endpoint_id
add_route_lib() {
    local arg_aws_region="$1"
    local arg_endpoint_id="$2"

    echo -e "\n${CYAN}=== 添加路由 (來自 lib) ===${NC}"

    if [ -z "$arg_aws_region" ] || [ -z "$arg_endpoint_id" ]; then
        echo -e "${RED}錯誤: add_route_lib 需要 aws_region 和 endpoint_id。${NC}"
        return 1
    fi

    echo -e "${BLUE}當前端點 ID: $arg_endpoint_id${NC}"
    echo -e "${BLUE}當前 AWS 區域: $arg_aws_region${NC}"

    local dest_cidr_lib
    read -p "請輸入目標網路 CIDR (例如 10.1.0.0/16 或 0.0.0.0/0): " dest_cidr_lib
    if [ -z "$dest_cidr_lib" ]; then
        echo -e "${RED}目標網路 CIDR 不可為空。${NC}"
        return 1
    fi

    # 列出已關聯的子網路以供選擇
    echo -e "\n${YELLOW}端點 $arg_endpoint_id 已關聯的子網路:${NC}"
    local associated_subnets_json
    associated_subnets_json=$(aws ec2 describe-client-vpn-target-networks \
        --client-vpn-endpoint-id "$arg_endpoint_id" \
        --region "$arg_aws_region" 2>/dev/null)

    if [ $? -ne 0 ] || [ -z "$associated_subnets_json" ] || [ "$(echo "$associated_subnets_json" | jq '.ClientVpnTargetNetworks | length')" -eq 0 ]; then
        echo -e "${RED}端點 $arg_endpoint_id 沒有已關聯的子網路。無法添加路由。請先關聯子網路。${NC}"
        return 1
    fi
    
    echo "$associated_subnets_json" | jq -r '.ClientVpnTargetNetworks[] | 
    "  子網路 ID: \\(.TargetNetworkId) (VPC ID: \\(.VpcId), 狀態: \\(.Status.Code))"'

    local target_subnet_lib
    read -p "請輸入目標子網路 ID (必須是上面列出的已關聯子網路之一): " target_subnet_lib
    if [ -z "$target_subnet_lib" ]; then
        echo -e "${RED}目標子網路 ID 不可為空。${NC}"
        return 1
    fi

    # 驗證選擇的子網路是否已關聯，含備用方法
    local is_valid_subnet_lib
    if ! is_valid_subnet_lib=$(echo "$associated_subnets_json" | jq -e --arg sn "$target_subnet_lib" '.ClientVpnTargetNetworks[] | select(.TargetNetworkId == $sn)' 2>/dev/null); then
        # 備用驗證方法：使用 grep 檢查子網路 ID 是否存在
        if echo "$associated_subnets_json" | grep -q "\"TargetNetworkId\":\"$target_subnet_lib\""; then
            is_valid_subnet_lib="found" # 非空值表示找到
        else
            is_valid_subnet_lib=""
        fi
    fi
    
    if [ -z "$is_valid_subnet_lib" ]; then
        echo -e "${RED}選擇的子網路 $target_subnet_lib 無效或未關聯到此端點。${NC}"
        return 1
    fi
    
    local route_desc_lib
    read -p "請輸入此路由的描述 (可選): " route_desc_lib

    echo -e "${BLUE}正在為端點 $arg_endpoint_id 添加路由: $dest_cidr_lib -> $target_subnet_lib...${NC}" # Quoted variables
    if aws ec2 create-client-vpn-route \
      --client-vpn-endpoint-id "$arg_endpoint_id" \
      --destination-cidr-block "$dest_cidr_lib" \
      --target-vpc-subnet-id "$target_subnet_lib" \
      ${route_desc_lib:+"--description"} ${route_desc_lib:+"$route_desc_lib"} \
      --region "$arg_aws_region"; then
        echo -e "${GREEN}路由已成功添加: $dest_cidr_lib -> $target_subnet_lib ${NC}"
        log_message_core "路由已添加 (lib): $dest_cidr_lib -> $target_subnet_lib for endpoint $arg_endpoint_id"
        return 0
    else
        echo -e "${RED}添加路由 $dest_cidr_lib -> $target_subnet_lib 失敗。${NC}"
        log_message_core "錯誤: 添加路由失敗 (lib): $dest_cidr_lib -> $target_subnet_lib for endpoint $arg_endpoint_id"
        return 1
    fi
}

# 函式：移除 VPN 端點的路由
# 參數: aws_region, endpoint_id
remove_route_lib() {
    local arg_aws_region="$1"
    local arg_endpoint_id="$2"

    echo -e "\n${CYAN}=== 移除路由 (來自 lib) ===${NC}"

    if [ -z "$arg_aws_region" ] || [ -z "$arg_endpoint_id" ]; then
        echo -e "${RED}錯誤: remove_route_lib 需要 aws_region 和 endpoint_id。${NC}"
        return 1
    fi

    echo -e "${BLUE}當前端點 ID: $arg_endpoint_id${NC}"
    echo -e "${BLUE}當前 AWS 區域: $arg_aws_region${NC}"

    local routes_json_del_lib
    routes_json_del_lib=$(aws ec2 describe-client-vpn-routes \
        --client-vpn-endpoint-id "$arg_endpoint_id" \
        --region "$arg_aws_region" 2>/dev/null)
    
    if [ $? -ne 0 ] || [ -z "$routes_json_del_lib" ] || [ "$(echo "$routes_json_del_lib" | jq '.Routes | length')" -eq 0 ]; then
        echo -e "${YELLOW}此端點沒有配置路由可供刪除。${NC}"
        log_message_core "端點 $arg_endpoint_id 沒有配置路由可供刪除 (lib)。"
        return 0 # Not an error, just nothing to do
    fi

    echo -e "\n${YELLOW}現有路由:${NC}"
    echo "$routes_json_del_lib" | jq -r '.Routes[] | 
    "  目標 CIDR: \\(.DestinationCidr)
    目標子網路: \\(.TargetSubnet // .TargetVpcSubnetId)
    狀態: \\(.Status.Code)
    來源: \\(.Origin)
    描述: \\(.Description // "無描述")
    ------------------------------------"'
    
    local del_dest_cidr_lib del_target_subnet_id_lib
    read -p "請輸入要刪除路由的目標 CIDR: " del_dest_cidr_lib
    if [ -z "$del_dest_cidr_lib" ]; then
        echo -e "${RED}目標 CIDR 不可為空。${NC}"
        return 1
    fi

    read -p "請輸入要刪除路由的目標子網路 ID (如果路由是針對特定子網路的): " del_target_subnet_id_lib
    # Note: delete-client-vpn-route requires --target-vpc-subnet-id for routes that have one.
    # For routes like 0.0.0.0/0 that might not be directly tied to a *specific* subnet in the same way,
    # the API still expects it if the route was created with it.
    # If the route was created without a specific target subnet (e.g. some system routes), this might differ.
    # However, Client VPN routes are typically to a subnet.

    if [ -z "$del_target_subnet_id_lib" ]; then
        echo -e "${RED}目標子網路 ID 不可為空。Client VPN 路由刪除需要目標子網路 ID。${NC}"
        return 1
    fi

    echo -e "${BLUE}正在刪除路由: $del_dest_cidr_lib (目標子網路: $del_target_subnet_id_lib)...${NC}" # Quoted variables
    local route_to_delete_info_lib origin_of_route_to_delete_lib
    route_to_delete_info_lib=$(echo "$routes_json_del_lib" | jq -r --arg dc "$del_dest_cidr_lib" --arg ts "$del_target_subnet_id_lib" '.Routes[] | select(.DestinationCidr == $dc and (.TargetSubnet // .TargetVpcSubnetId) == $ts)')
    
    if [ -z "$route_to_delete_info_lib" ]; then
        echo -e "${RED}找不到匹配的路由: CIDR $del_dest_cidr_lib, 子網路 $del_target_subnet_id_lib ${NC}"
        log_message_core "錯誤: 找不到要刪除的路由 (lib): $del_dest_cidr_lib, 子網路 $del_target_subnet_id_lib for endpoint $arg_endpoint_id"
        return 1
    fi

    origin_of_route_to_delete_lib=$(echo "$route_to_delete_info_lib" | jq -r '.Origin')
    
    if [ "$origin_of_route_to_delete_lib" == "associate" ] || [ "$origin_of_route_to_delete_lib" == "add-route" ]; then
        if aws ec2 delete-client-vpn-route \
            --client-vpn-endpoint-id "$arg_endpoint_id" \
            --destination-cidr-block "$del_dest_cidr_lib" \
            --target-vpc-subnet-id "$del_target_subnet_id_lib" \
            --region "$arg_aws_region"; then
            echo -e "${GREEN}路由已成功刪除。${NC}"
            log_message_core "路由已刪除 (lib): $del_dest_cidr_lib (目標子網路: $del_target_subnet_id_lib) from endpoint $arg_endpoint_id"
            return 0
        else
            echo -e "${RED}刪除路由失敗。${NC}"
            log_message_core "錯誤: 刪除路由失敗 (lib): $del_dest_cidr_lib (目標子網路: $del_target_subnet_id_lib) from endpoint $arg_endpoint_id"
            return 1
        fi
    else
        echo -e "${RED}無法刪除此路由。來源為 '$origin_of_route_to_delete_lib'。${NC}"
        echo -e "${YELLOW}提示: 通常只有手動添加的路由 ('add-route') 或因子網路關聯而創建的路由 ('associate') 可以刪除。 'local' 路由 (VPN Client CIDR) 不能被刪除。${NC}"
        log_message_core "錯誤: 無法刪除路由 (lib)，來源為 '$origin_of_route_to_delete_lib': $del_dest_cidr_lib for endpoint $arg_endpoint_id"
        return 1
    fi
}

# 函式：下載 VPN 客戶端配置文件
# 參數: aws_region, endpoint_id, vpn_name, script_dir
download_client_config_lib() {
    local arg_aws_region="$1"
    local arg_endpoint_id="$2"
    local arg_vpn_name="$3" # VPN_NAME from config, used for filename
    local arg_script_dir="$4" # SCRIPT_DIR for path

    echo -e "\n${CYAN}=== 下載客戶端配置文件 (來自 lib) ===${NC}"

    if [ -z "$arg_aws_region" ] || [ -z "$arg_endpoint_id" ] || [ -z "$arg_vpn_name" ] || [ -z "$arg_script_dir" ]; then
        echo -e "${RED}錯誤: download_client_config_lib 需要 aws_region, endpoint_id, vpn_name, 和 script_dir。${NC}"
        return 1
    fi

    echo -e "${BLUE}當前端點 ID: $arg_endpoint_id${NC}"
    echo -e "${BLUE}當前 AWS 區域: $arg_aws_region${NC}"

    local client_config_file_name_lib="${arg_vpn_name}_client_config.ovpn"
    local client_config_path_lib="${arg_script_dir}/${client_config_file_name_lib}"

    echo -e "${BLUE}正在下載客戶端配置文件到: $client_config_path_lib...${NC}"
    
    local client_config_content_lib
    client_config_content_lib=$(aws ec2 export-client-vpn-client-configuration \
        --client-vpn-endpoint-id "$arg_endpoint_id" \
        --region "$arg_aws_region" \
        --output text 2>&1) # Capture stdout and stderr

    if [ $? -ne 0 ]; then
        echo -e "${RED}下載客戶端配置文件失敗。錯誤訊息:${NC}"
        echo -e "${RED}$client_config_content_lib${NC}" # Display error from AWS CLI
        log_message_core "錯誤: 下載客戶端配置文件失敗 (lib) for endpoint $arg_endpoint_id. AWS CLI error: $client_config_content_lib"
        return 1
    fi

    if [ -z "$client_config_content_lib" ]; then
        echo -e "${RED}下載客戶端配置文件失敗: AWS CLI 未返回任何內容。${NC}"
        log_message_core "錯誤: 下載客戶端配置文件失敗 (lib) - AWS CLI 未返回任何內容 for endpoint $arg_endpoint_id."
        return 1
    fi

    # 檢查是否包含 "remote " 字樣，作為一個簡單的驗證
    if ! echo "$client_config_content_lib" | grep -q "remote "; then
        echo -e "${RED}下載的客戶端配置文件內容似乎無效 (未找到 'remote ' 指令)。${NC}"
        echo -e "${YELLOW}AWS CLI 輸出:${NC}"
        echo "$client_config_content_lib" # Display potentially problematic content
        log_message_core "錯誤: 下載的客戶端配置文件內容無效 (lib) for endpoint $arg_endpoint_id."
        return 1
    fi

    echo "$client_config_content_lib" > "$client_config_path_lib"
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}客戶端配置文件已成功下載到: $client_config_path_lib${NC}"
        echo -e "${YELLOW}請將此文件分發給需要連接 VPN 的用戶。${NC}"
        log_message_core "客戶端配置文件已下載 (lib): $client_config_path_lib for endpoint $arg_endpoint_id"
        return 0
    else
        echo -e "${RED}將客戶端配置文件保存到 $client_config_path_lib 失敗。${NC}"
        log_message_core "錯誤: 保存客戶端配置文件失敗 (lib): $client_config_path_lib for endpoint $arg_endpoint_id"
        return 1
    fi
}

# 函式：終止 VPN 端點並清理資源
# 參數: aws_region, endpoint_id, vpn_name (for log group), config_file_path
terminate_vpn_endpoint_lib() {
    local arg_aws_region="$1"
    local arg_endpoint_id="$2"
    local arg_vpn_name="$3" # Used for CloudWatch log group name
    local arg_config_file_path="$4"

    echo -e "\n${CYAN}=== 終止 VPN 端點 (來自 lib) ===${NC}"
    log_message_core "開始終止 VPN 端點 $arg_endpoint_id (lib)"

    if [ -z "$arg_aws_region" ] || [ -z "$arg_endpoint_id" ] || [ -z "$arg_vpn_name" ] || [ -z "$arg_config_file_path" ]; then
        echo -e "${RED}錯誤: terminate_vpn_endpoint_lib 需要 aws_region, endpoint_id, vpn_name, 和 config_file_path。${NC}"
        log_message_core "錯誤: terminate_vpn_endpoint_lib 缺少必要參數。"
        return 1
    fi

    echo -e "${YELLOW}警告: 此操作將永久刪除 VPN 端點 $arg_endpoint_id 及其相關資源。${NC}"
    read -p "您確定要繼續嗎? (yes/no): " confirmation
    if [[ "$confirmation" != "yes" ]]; then
        echo -e "${BLUE}操作已取消。${NC}"
        log_message_core "終止 VPN 端點 $arg_endpoint_id 操作已取消 (lib)。"
        return 1
    fi

    # 1. Disassociate all target networks
    echo -e "\n${BLUE}正在解除目標網路關聯...${NC}"
    local target_networks_json
    target_networks_json=$(aws ec2 describe-client-vpn-target-networks \
        --client-vpn-endpoint-id "$arg_endpoint_id" \
        --region "$arg_aws_region" 2>/dev/null)

    if [ $? -eq 0 ] && [ -n "$target_networks_json" ] && [ "$(echo "$target_networks_json" | jq '.ClientVpnTargetNetworks | length')" -gt 0 ]; then
        echo "$target_networks_json" | jq -r '.ClientVpnTargetNetworks[].AssociationId' | while IFS= read -r assoc_id; do
            echo -e "${BLUE}  正在解除關聯 ID: $assoc_id...${NC}"
            if aws ec2 disassociate-client-vpn-target-network \
                --client-vpn-endpoint-id "$arg_endpoint_id" \
                --association-id "$assoc_id" \
                --region "$arg_aws_region"; then
                echo -e "${GREEN}    關聯 $assoc_id 已成功發起解除。${NC}"
                log_message_core "已發起解除目標網路關聯 $assoc_id for endpoint $arg_endpoint_id (lib)"
                echo -e "${BLUE}    等待關聯 $assoc_id 解除完成...${NC}"
                if ! aws ec2 wait client-vpn-target-network-disassociated \
                    --client-vpn-endpoint-id "$arg_endpoint_id" \
                    --association-ids "$assoc_id" \
                    --region "$arg_aws_region"; then
                    echo -e "${YELLOW}    等待解除關聯 $assoc_id 完成時發生錯誤或超時。繼續執行...${NC}"
                    log_message_core "警告: 等待解除關聯 $assoc_id 完成時發生錯誤或超時 for endpoint $arg_endpoint_id (lib)"
                else
                    echo -e "${GREEN}    關聯 $assoc_id 已成功解除。${NC}"
                fi
            else
                echo -e "${RED}    解除關聯 $assoc_id 失敗。${NC}"
                log_message_core "錯誤: 解除目標網路關聯 $assoc_id 失敗 for endpoint $arg_endpoint_id (lib)"
            fi
        done
    else
        echo -e "${YELLOW}沒有找到與端點 $arg_endpoint_id 關聯的目標網路，或無法獲取資訊。${NC}"
    fi

    # 2. Delete all authorization rules
    echo -e "\n${BLUE}正在刪除授權規則...${NC}"
    local auth_rules_json
    auth_rules_json=$(aws ec2 describe-client-vpn-authorization-rules \
        --client-vpn-endpoint-id "$arg_endpoint_id" \
        --region "$arg_aws_region" 2>/dev/null)

    local auth_rules_count
    if ! auth_rules_count=$(echo "$auth_rules_json" | jq '.AuthorizationRules | length' 2>/dev/null); then
        # 備用解析方法：使用 grep 統計授權規則數量
        auth_rules_count=$(echo "$auth_rules_json" | grep -c '"DestinationCidr"' || echo "0")
    fi

    if [ $? -eq 0 ] && [ -n "$auth_rules_json" ] && [ "$auth_rules_count" -gt 0 ]; then
        # 提取所有CIDR並處理
        if command -v jq >/dev/null 2>&1; then
            echo "$auth_rules_json" | jq -r '.AuthorizationRules[].DestinationCidr' | while IFS= read -r cidr; do
                echo -e "${BLUE}  正在撤銷對 CIDR $cidr 的授權...${NC}"
                if aws ec2 revoke-client-vpn-ingress \
                    --client-vpn-endpoint-id "$arg_endpoint_id" \
                    --target-network-cidr "$cidr" \
                    --revoke-all-groups \
                    --region "$arg_aws_region"; then
                    echo -e "${GREEN}    已成功撤銷對 CIDR $cidr 的授權。${NC}"
                    log_message_core "已撤銷對 CIDR $cidr 的授權 for endpoint $arg_endpoint_id (lib)"
                else
                    echo -e "${RED}    撤銷對 CIDR $cidr 的授權失敗。${NC}"
                    log_message_core "錯誤: 撤銷對 CIDR $cidr 的授權失敗 for endpoint $arg_endpoint_id (lib)"
                fi
            done
        else
            # 備用解析方法：使用 grep 和 sed 提取 CIDR
            echo "$auth_rules_json" | grep -o '"DestinationCidr":"[^"]*"' | sed 's/"DestinationCidr":"//g' | sed 's/"//g' | while IFS= read -r cidr; do
                if [ -n "$cidr" ]; then
                    echo -e "${BLUE}  正在撤銷對 CIDR $cidr 的授權...${NC}" # Quoted variable
                    if aws ec2 revoke-client-vpn-ingress \
                        --client-vpn-endpoint-id "$arg_endpoint_id" \
                        --target-network-cidr "$cidr" \
                        --revoke-all-groups \
                        --region "$arg_aws_region"; then
                        echo -e "${GREEN}    已成功撤銷對 CIDR $cidr 的授權。${NC}"
                        log_message_core "已撤銷對 CIDR $cidr 的授權 (lib) for endpoint $arg_endpoint_id"
                    else
                        echo -e "${RED}    撤銷對 CIDR $cidr 的授權失敗。${NC}"
                        log_message_core "錯誤: 撤銷對 CIDR $cidr 的授權失敗 (lib) for endpoint $arg_endpoint_id"
                    fi
                fi
            done
        fi
    else
        echo -e "${YELLOW}沒有找到與端點 $arg_endpoint_id 相關的授權規則，或無法獲取資訊。${NC}"
    fi

    # 3. Delete all manually added routes (origin 'add-route' or 'associate')
    echo -e "\n${BLUE}正在刪除路由...${NC}"
    local routes_json
    routes_json=$(aws ec2 describe-client-vpn-routes \
        --client-vpn-endpoint-id "$arg_endpoint_id" \
        --region "$arg_aws_region" 2>/dev/null)

    local routes_count
    if ! routes_count=$(echo "$routes_json" | jq '.Routes | length' 2>/dev/null); then
        # 備用解析方法：使用 grep 統計路由數量
        routes_count=$(echo "$routes_json" | grep -c '"DestinationCidr"' || echo "0")
    fi

    if [ $? -eq 0 ] && [ -n "$routes_json" ] && [ "$routes_count" -gt 0 ]; then
        # 驗證路由數量解析結果
        if validate_json_parse_result "$routes_count" "路由數量"; then
            # 嘗試使用 jq 處理路由條目
            if command -v jq >/dev/null 2>&1 && echo "$routes_json" | jq -c '.Routes[]' >/dev/null 2>&1; then
                echo "$routes_json" | jq -c '.Routes[]' | while IFS= read -r route_entry; do
                    local dest_cidr target_subnet origin
                    
                    # 提取路由欄位，含備用方法
                    if ! dest_cidr=$(echo "$route_entry" | jq -r '.DestinationCidr' 2>/dev/null); then
                        dest_cidr=$(echo "$route_entry" | grep -o '"DestinationCidr":"[^"]*"' | sed 's/"DestinationCidr":"//g' | sed 's/"//g')
                    fi
                    
                    if ! target_subnet=$(echo "$route_entry" | jq -r '.TargetSubnet // .TargetVpcSubnetId' 2>/dev/null); then
                        # 備用驗證：先嘗試 TargetSubnet，再嘗試 TargetVpcSubnetId
                        target_subnet=$(echo "$route_entry" | grep -o '"TargetSubnet":"[^"]*"' | sed 's/"TargetSubnet":"//g' | sed 's/"//g')
                        if [ -z "$target_subnet" ] || [ "$target_subnet" == "null" ]; then
                            target_subnet=$(echo "$route_entry" | grep -o '"TargetVpcSubnetId":"[^"]*"' | sed 's/"TargetVpcSubnetId":"//g' | sed 's/"//g')
                        fi
                    fi
                    
                    if ! origin=$(echo "$route_entry" | jq -r '.Origin' 2>/dev/null); then
                        origin=$(echo "$route_entry" | grep -o '"Origin":"[^"]*"' | sed 's/"Origin":"//g' | sed 's/"//g')
                    fi

                    # 驗證提取的欄位
                    if [ -n "$dest_cidr" ] && [ -n "$target_subnet" ] && [ -n "$origin" ] && \
                       [ "$dest_cidr" != "null" ] && [ "$target_subnet" != "null" ] && [ "$origin" != "null" ]; then
                        if [ "$origin" == "add-route" ] || [ "$origin" == "associate" ]; then
                            echo -e "${BLUE}  正在刪除路由: $dest_cidr -> $target_subnet (來源: $origin)...${NC}"
                            if aws ec2 delete-client-vpn-route \
                                --client-vpn-endpoint-id "$arg_endpoint_id" \
                                --destination-cidr-block "$dest_cidr" \
                                --target-vpc-subnet-id "$target_subnet" \
                                --region "$arg_aws_region"; then
                                echo -e "${GREEN}    路由 $dest_cidr -> $target_subnet 已成功刪除。${NC}"
                                log_message_core "路由 $dest_cidr -> $target_subnet 已刪除 for endpoint $arg_endpoint_id (lib)"
                            else
                                echo -e "${RED}    刪除路由 $dest_cidr -> $target_subnet 失敗。${NC}"
                                log_message_core "錯誤: 刪除路由 $dest_cidr -> $target_subnet 失敗 for endpoint $arg_endpoint_id (lib)"
                            fi
                        else
                            echo -e "${YELLOW}  跳過路由: $dest_cidr -> $target_subnet (來源: $origin, 不可刪除)。${NC}"
                        fi
                    else
                        echo -e "${YELLOW}  跳過路由條目：無法解析必要欄位 (CIDR: $dest_cidr, 子網路: $target_subnet, 來源: $origin)。${NC}"
                        log_message_core "警告: 跳過路由條目，無法解析必要欄位 for endpoint $arg_endpoint_id (lib)"
                    fi
                done
            else
                # 完全備用方法：使用 grep 和 sed 逐一處理路由
                echo -e "${YELLOW}  使用備用方法處理路由...${NC}"
                echo "$routes_json" | grep -o '{[^}]*"DestinationCidr"[^}]*}' | while IFS= read -r route_line; do
                    local dest_cidr target_subnet origin
                    
                    dest_cidr=$(echo "$route_line" | grep -o '"DestinationCidr":"[^"]*"' | sed 's/"DestinationCidr":"//g' | sed 's/"//g')
                    target_subnet=$(echo "$route_line" | grep -o '"TargetSubnet":"[^"]*"' | sed 's/"TargetSubnet":"//g' | sed 's/"//g')
                    if [ -z "$target_subnet" ] || [ "$target_subnet" == "null" ]; then
                        target_subnet=$(echo "$route_line" | grep -o '"TargetVpcSubnetId":"[^"]*"' | sed 's/"TargetVpcSubnetId":"//g' | sed 's/"//g')
                    fi
                    origin=$(echo "$route_line" | grep -o '"Origin":"[^"]*"' | sed 's/"Origin":"//g' | sed 's/"//g')
                    
                    if [ -n "$dest_cidr" ] && [ -n "$target_subnet" ] && [ -n "$origin" ] && \
                       [ "$dest_cidr" != "null" ] && [ "$target_subnet" != "null" ] && [ "$origin" != "null" ]; then
                        if [ "$origin" == "add-route" ] || [ "$origin" == "associate" ]; then
                            echo -e "${BLUE}  正在刪除路由 (備用): $dest_cidr -> $target_subnet (來源: $origin)...${NC}"
                            if aws ec2 delete-client-vpn-route \
                                --client-vpn-endpoint-id "$arg_endpoint_id" \
                                --destination-cidr-block "$dest_cidr" \
                                --target-vpc-subnet-id "$target_subnet" \
                                --region "$arg_aws_region"; then
                                echo -e "${GREEN}    路由 $dest_cidr -> $target_subnet 已成功刪除。${NC}"
                                log_message_core "路由 $dest_cidr -> $target_subnet 已刪除 (備用方法) for endpoint $arg_endpoint_id (lib)"
                            else
                                echo -e "${RED}    刪除路由 $dest_cidr -> $target_subnet 失敗。${NC}"
                                log_message_core "錯誤: 刪除路由 $dest_cidr -> $target_subnet 失敗 (備用方法) for endpoint $arg_endpoint_id (lib)"
                            fi
                        else
                            echo -e "${YELLOW}  跳過路由 (備用): $dest_cidr -> $target_subnet (來源: $origin, 不可刪除)。${NC}"
                        fi
                    else
                        echo -e "${YELLOW}  跳過路由條目 (備用)：無法解析必要欄位。${NC}"
                    fi
                done
            fi
        else
            echo -e "${RED}無法驗證路由數量，跳過路由刪除步驟。${NC}"
            log_message_core "錯誤: 無法驗證路由數量 for endpoint $arg_endpoint_id (lib)"
        fi
    else
        echo -e "${YELLOW}沒有找到與端點 $arg_endpoint_id 相關的路由，或無法獲取資訊。${NC}"
    fi

    # 4. Delete the Client VPN endpoint
    echo -e "\n${BLUE}正在刪除 Client VPN 端點 $arg_endpoint_id...${NC}"
    if aws ec2 delete-client-vpn-endpoint \
        --client-vpn-endpoint-id "$arg_endpoint_id" \
        --region "$arg_aws_region"; then
        echo -e "${GREEN}  刪除端點 $arg_endpoint_id 的請求已成功發送。${NC}"
        log_message_core "已發起刪除 Client VPN 端點 $arg_endpoint_id (lib)"
        echo -e "${BLUE}  等待端點 $arg_endpoint_id 刪除完成...${NC}"
        if ! aws ec2 wait client-vpn-endpoint-deleted \
            --client-vpn-endpoint-ids "$arg_endpoint_id" \
            --region "$arg_aws_region"; then
            echo -e "${RED}  等待端點 $arg_endpoint_id 刪除完成時發生錯誤或超時。請手動確認。${NC}"
            log_message_core "錯誤: 等待端點 $arg_endpoint_id 刪除完成時發生錯誤或超時 (lib)"
            # Do not return error here, proceed to config cleanup
        else
            echo -e "${GREEN}  端點 $arg_endpoint_id 已成功刪除。${NC}"
        fi
    else
        echo -e "${RED}  刪除 Client VPN 端點 $arg_endpoint_id 失敗。${NC}"
        log_message_core "錯誤: 刪除 Client VPN 端點 $arg_endpoint_id 失敗 (lib)"
        # Even if endpoint deletion fails, attempt to clean config, but return error at the end.
        local endpoint_deletion_failed=true
    fi

    # 5. Optionally, offer to delete CloudWatch log group
    local clean_vpn_name=$(echo "$arg_vpn_name" | sed 's/[^a-zA-Z0-9/_-]/-/g' | sed 's/--*/-/g' | sed 's/^-\|-$//g')
    local log_group_name="/aws/clientvpn/$clean_vpn_name"
    read -p "是否要刪除 CloudWatch 日誌群組 $log_group_name? (yes/no): " delete_log_group_confirmation
    if [[ "$delete_log_group_confirmation" == "yes" ]]; then
        echo -e "${BLUE}正在刪除 CloudWatch 日誌群組 $log_group_name...${NC}"
        if aws logs delete-log-group --log-group-name "$log_group_name" --region "$arg_aws_region"; then
            echo -e "${GREEN}  CloudWatch 日誌群組 $log_group_name 已成功刪除。${NC}"
            log_message_core "CloudWatch 日誌群組 $log_group_name 已刪除 (lib)"
        else
            echo -e "${RED}  刪除 CloudWatch 日誌群組 $log_group_name 失敗。它可能不存在或發生其他錯誤。${NC}"
            log_message_core "錯誤: 刪除 CloudWatch 日誌群組 $log_group_name 失敗 (lib)"
        fi
    else
        echo -e "${BLUE}跳過刪除 CloudWatch 日誌群組。${NC}"
    fi

    # 6. Update config file
    if [ -f "$arg_config_file_path" ]; then
        echo -e "\n${BLUE}正在清理配置文件 $arg_config_file_path...${NC}"
        local temp_conf_terminate
        temp_conf_terminate=$(mktemp "${arg_config_file_path}.tmp_terminate.XXXXXX")
        trap "rm -f '$temp_conf_terminate'" EXIT
        
        # Keep lines that are NOT the ones we want to remove
        grep -E -v '^(ENDPOINT_ID|VPN_CIDR|VPN_NAME|SERVER_CERT_ARN|CLIENT_CERT_ARN|VPC_ID|VPC_CIDR|SUBNET_ID|MULTI_VPC_COUNT|MULTI_VPC_[0-9]+)=' "$arg_config_file_path" > "$temp_conf_terminate"
        
        if mv "$temp_conf_terminate" "$arg_config_file_path"; then
            echo -e "${GREEN}  配置文件已成功清理。${NC}"
            log_message_core "配置文件 $arg_config_file_path 已清理 (lib)"
        else
            echo -e "${RED}  清理配置文件 $arg_config_file_path 失敗。臨時文件可能保留在 $temp_conf_terminate。${NC}"
            log_message_core "錯誤: 清理配置文件 $arg_config_file_path 失敗 (lib)"
        fi
    else
        echo -e "${YELLOW}配置文件 $arg_config_file_path 未找到，跳過清理。${NC}"
    fi

    if [ "$endpoint_deletion_failed" = true ]; then
        echo -e "\n${RED}VPN 端點終止過程中發生一個或多個錯誤。請檢查日誌。${NC}"
        return 1
    fi

    echo -e "\n${GREEN}VPN 端點 $arg_endpoint_id 及其相關資源（根據選擇）已成功終止和清理。${NC}"
    log_message_core "VPN 端點 $arg_endpoint_id 已成功終止和清理 (lib)"
    return 0
}

# 函式：查看 VPN 端點關聯的網絡
# 參數: aws_region, endpoint_id
view_associated_networks_lib() {
    local arg_aws_region="$1"
    local arg_endpoint_id="$2"

    echo -e "\n${CYAN}=== 查看關聯的網絡 (來自 lib) ===${NC}"

    if [ -z "$arg_aws_region" ] || [ -z "$arg_endpoint_id" ]; then
        echo -e "${RED}錯誤: view_associated_networks_lib 需要 aws_region 和 endpoint_id。${NC}"
        log_message_core "錯誤: view_associated_networks_lib 缺少必要參數。"
        return 1
    fi

    echo -e "${BLUE}當前端點 ID: $arg_endpoint_id${NC}"
    echo -e "${BLUE}當前 AWS 區域: $arg_aws_region${NC}"
    echo -e "\n${BLUE}關聯的網絡:${NC}"

    local networks_json_lib
    networks_json_lib=$(aws ec2 describe-client-vpn-target-networks \
        --client-vpn-endpoint-id "$arg_endpoint_id" \
        --region "$arg_aws_region" 2>/dev/null)

    if [ $? -ne 0 ]; then
        echo -e "${RED}無法獲取關聯的網絡資訊。${NC}"
        log_message_core "錯誤: 無法獲取端點 $arg_endpoint_id 的關聯網絡資訊 (lib)。"
        return 1
    fi

    if [ -z "$networks_json_lib" ] || [ "$(echo "$networks_json_lib" | jq '.ClientVpnTargetNetworks | length')" -eq 0 ]; then
        echo -e "${YELLOW}此端點沒有關聯的網絡。${NC}"
        log_message_core "端點 $arg_endpoint_id 沒有關聯的網絡 (lib)。"
        return 0 # Not an error, just nothing to do.
    fi

    echo "$networks_json_lib" | jq -r '.ClientVpnTargetNetworks[] | 
    "  子網路 ID: \\(.TargetNetworkId)
    VPC ID: \\(.VpcId)
    關聯 ID: \\(.AssociationId)
    狀態: \\(.Status.Code)
    安全群組: \\(.SecurityGroups[]? // "N/A") 
    執行緒: \\(.ClientVpnThreads // "N/A")
    ------------------------------------"'
    # Note: .SecurityGroups is an array, might need better formatting if multiple.
    # .ClientVpnThreads might not be available or relevant for all views.

    log_message_core "已顯示端點 $arg_endpoint_id 的關聯網絡 (lib)。"
    return 0
}

# 調試函數：測試 AWS CLI 參數
debug_aws_cli_params() {
    local vpn_cidr="$1"
    local server_cert_arn="$2"
    local client_cert_arn="$3"
    local vpn_name="$4"
    local aws_region="$5"
    
    echo -e "${CYAN}=== AWS CLI 參數調試 ===${NC}"
    echo -e "VPN CIDR: $vpn_cidr"
    echo -e "伺服器憑證 ARN: $server_cert_arn"
    echo -e "客戶端憑證 ARN: $client_cert_arn"
    echo -e "VPN 名稱: $vpn_name"
    echo -e "AWS 區域: $aws_region"
    
    # 測試 AWS 連線
    echo -e "\n${BLUE}測試 AWS 連線...${NC}"
    if aws sts get-caller-identity --region "$aws_region" >/dev/null 2>&1; then
        echo -e "${GREEN}✓ AWS 連線正常${NC}"
    else
        echo -e "${RED}✗ AWS 連線失敗${NC}"
        return 1
    fi
    
    # 驗證憑證 ARN
    echo -e "\n${BLUE}驗證伺服器憑證...${NC}"
    if aws acm describe-certificate --certificate-arn "$server_cert_arn" --region "$aws_region" >/dev/null 2>&1; then
        echo -e "${GREEN}✓ 伺服器憑證有效${NC}"
    else
        echo -e "${RED}✗ 伺服器憑證無效或無權限訪問${NC}"
        return 1
    fi
    
    echo -e "\n${BLUE}驗證客戶端憑證...${NC}"
    if aws acm describe-certificate --certificate-arn "$client_cert_arn" --region "$aws_region" >/dev/null 2>&1; then
        echo -e "${GREEN}✓ 客戶端憑證有效${NC}"
    else
        echo -e "${RED}✗ 客戶端憑證無效或無權限訪問${NC}"
        return 1
    fi
    
    # 測試 VPC 端點創建權限
    echo -e "\n${BLUE}測試 Client VPN 權限...${NC}"
    if aws ec2 describe-client-vpn-endpoints --region "$aws_region" >/dev/null 2>&1; then
        echo -e "${GREEN}✓ Client VPN 讀取權限正常${NC}"
    else
        echo -e "${RED}✗ Client VPN 權限不足${NC}"
        return 1
    fi
    
    return 0
}
