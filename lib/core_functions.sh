#!/bin/bash

# 顏色設定
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# 全域變數
SCRIPT_DIR_CORE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)" # SCRIPT_DIR_CORE 指向 lib 的上一層目錄
LOG_FILE_CORE="$SCRIPT_DIR_CORE/vpn_admin.log"

# 記錄函數
log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S'): $1" >> "$LOG_FILE_CORE"
}

# 核心日誌函數 (用於庫函數)
log_message_core() {
    echo "$(date '+%Y-%m-%d %H:%M:%S'): $1" >> "$LOG_FILE_CORE"
}

# 輸入驗證函數
validate_vpc_id() {
    local vpc_id="$1"
    if [[ ! "$vpc_id" =~ ^vpc-[0-9a-f]{8,17}$ ]]; then
        return 1
    fi
    return 0
}

validate_subnet_id() {
    local subnet_id="$1"
    if [[ ! "$subnet_id" =~ ^subnet-[0-9a-f]{8,17}$ ]]; then
        return 1
    fi
    return 0
}

validate_endpoint_id() {
    local endpoint_id="$1"
    if [[ ! "$endpoint_id" =~ ^cvpn-endpoint-[0-9a-f]{8,17}$ ]]; then
        return 1
    fi
    return 0
}

validate_aws_region() {
    local region="$1"
    # AWS 區域格式: us-east-1, eu-west-1, ap-southeast-1 等
    if [[ ! "$region" =~ ^[a-z]{2}-[a-z]+-[0-9]+$ ]]; then
        return 1
    fi
    return 0
}

validate_cidr_block() {
    local cidr="$1"
    # 簡單的 CIDR 格式驗證
    if [[ ! "$cidr" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}/[0-9]{1,2}$ ]]; then
        return 1
    fi
    # 進一步驗證 IP 和掩碼範圍
    local ip_part="$(echo "$cidr" | cut -d'/' -f1)"
    local mask_part="$(echo "$cidr" | cut -d'/' -f2)"
    
    # 驗證掩碼範圍 (0-32)
    if [ "$mask_part" -lt 0 ] || [ "$mask_part" -gt 32 ]; then
        return 1
    fi
    
    # 驗證 IP 地址的每個部分 (0-255)
    IFS='.' read -ra IP_PARTS <<< "$ip_part"
    for part in "${IP_PARTS[@]}"; do
        if [ "$part" -lt 0 ] || [ "$part" -gt 255 ]; then
            return 1
        fi
    done
    
    return 0
}

validate_username() {
    local username="$1"
    # 只允許字母、數字、連字符和底線，長度 3-32
    if [[ ! "$username" =~ ^[a-zA-Z0-9_-]{3,32}$ ]]; then
        return 1
    fi
    return 0
}

validate_certificate_arn() {
    local cert_arn="$1"
    # AWS 證書 ARN 格式
    if [[ ! "$cert_arn" =~ ^arn:aws:acm:[a-z0-9-]+:[0-9]{12}:certificate/[0-9a-f-]{36}$ ]]; then
        return 1
    fi
    return 0
}

# 驗證 AWS Access Key ID
validate_aws_access_key_id() {
    local access_key_id="$1"
    
    if [ -z "$access_key_id" ]; then
        echo -e "${RED}錯誤: AWS Access Key ID 不能為空${NC}"
        log_message_core "錯誤: AWS Access Key ID 為空"
        return 1
    fi
    
    # AWS Access Key ID 格式：20個字元，以AKIA開頭（對於標準用戶）或ASIA開頭（臨時憑證）
    if [[ ! "$access_key_id" =~ ^(AKIA|ASIA)[A-Z0-9]{16}$ ]]; then
        echo -e "${RED}錯誤: AWS Access Key ID 格式無效 (應為 20 個字元，以 AKIA 或 ASIA 開頭)${NC}"
        log_message_core "錯誤: AWS Access Key ID 格式無效: $access_key_id"
        return 1
    fi
    
    return 0
}

# 驗證 AWS Secret Access Key
validate_aws_secret_access_key() {
    local secret_key="$1"
    
    if [ -z "$secret_key" ]; then
        echo -e "${RED}錯誤: AWS Secret Access Key 不能為空${NC}"
        log_message_core "錯誤: AWS Secret Access Key 為空"
        return 1
    fi
    
    # AWS Secret Access Key 格式：40個字元的base64編碼格式，可能包含填充字符
    # 支援標準格式（40字符）和包含填充字符的格式（最多44字符）
    if [[ ! "$secret_key" =~ ^[A-Za-z0-9+/]{40}={0,4}$ ]]; then
        echo -e "${RED}錯誤: AWS Secret Access Key 格式無效 (應為 40 個字元的 base64 格式，可包含填充字符)${NC}"
        log_message_core "錯誤: AWS Secret Access Key 格式無效"
        return 1
    fi
    
    return 0
}

# 驗證 IP 地址
validate_ip_address() {
    local ip="$1"
    
    if [ -z "$ip" ]; then
        echo -e "${RED}錯誤: IP 地址不能為空${NC}"
        log_message_core "錯誤: IP 地址為空"
        return 1
    fi
    
    # 使用正則表達式檢查 IPv4 格式
    local ip_regex='^([0-9]{1,3}\.){3}[0-9]{1,3}$'
    if [[ ! "$ip" =~ $ip_regex ]]; then
        echo -e "${RED}錯誤: IP 地址格式無效: $ip${NC}"
        log_message_core "錯誤: IP 地址格式無效: $ip"
        return 1
    fi
    
    # 檢查每個八位組是否在有效範圍內 (0-255)
    IFS='.' read -ra octets <<< "$ip"
    for octet in "${octets[@]}"; do
        if [ "$octet" -gt 255 ]; then
            echo -e "${RED}錯誤: IP 地址八位組超出範圍 (0-255): $ip${NC}"
            log_message_core "錯誤: IP 地址八位組超出範圍: $ip"
            return 1
        fi
    done
    
    return 0
}

# 驗證 Yes/No 選擇
validate_yes_no() {
    local input="$1"
    
    # 允許空值，視為 No
    if [ -z "$input" ]; then
        return 0
    fi
    
    if [[ ! "$input" =~ ^[YyNn]$ ]]; then
        echo -e "${RED}錯誤: 請輸入 y 或 n${NC}"
        log_message_core "錯誤: Yes/No 驗證失敗，輸入: $input"
        return 1
    fi
    
    return 0
}

# 驗證菜單選擇（範圍）
validate_menu_choice() {
    local choice="$1"
    local min="$2"
    local max="$3"
    
    if [ -z "$choice" ]; then
        echo -e "${RED}錯誤: 請輸入選擇${NC}"
        log_message_core "錯誤: 菜單選擇為空"
        return 1
    fi
    
    # 檢查是否為數字
    if ! [[ "$choice" =~ ^[0-9]+$ ]]; then
        echo -e "${RED}錯誤: 請輸入有效的數字${NC}"
        log_message_core "錯誤: 菜單選擇非數字: $choice"
        return 1
    fi
    
    # 檢查範圍
    if [ "$choice" -lt "$min" ] || [ "$choice" -gt "$max" ]; then
        echo -e "${RED}錯誤: 請輸入 $min 到 $max 之間的數字${NC}"
        log_message_core "錯誤: 菜單選擇超出範圍: $choice (範圍: $min-$max)"
        return 1
    fi
    
    return 0
}

# 驗證使用者名稱（允許空值）
validate_username_allow_empty() {
    local username="$1"
    
    # 允許空值
    if [ -z "$username" ]; then
        return 0
    fi
    
    # 如果不為空，則使用標準使用者名稱驗證
    validate_username "$username"
}

# 驗證 JSON 解析結果的通用函數
# 參數:
# $1: 解析結果值
# $2: 欄位名稱 (用於錯誤訊息)
# $3: (可選) 額外的驗證函數名稱
validate_json_parse_result() {
    local value="$1"
    local field_name="$2"
    local validation_func="$3"
    
    if [ -z "$value" ]; then
        echo -e "${RED}錯誤: ${field_name}解析失敗 - 結果為空${NC}"
        log_message_core "錯誤: ${field_name}解析失敗 - 結果為空"
        return 1
    fi
    
    # 檢查是否包含意外的空白字符（可能表示解析錯誤）
    if [[ "$value" =~ [[:space:]] ]] && [[ "$field_name" != *"名稱"* ]]; then
        echo -e "${RED}錯誤: ${field_name}包含意外的空白字符，可能解析失敗: '$value'${NC}"
        log_message_core "錯誤: ${field_name}包含意外的空白字符: '$value'"
        return 1
    fi
    
    # 檢查是否為 "null"（JSON null 值被錯誤解析為字符串）
    if [ "$value" == "null" ]; then
        echo -e "${RED}錯誤: ${field_name}解析結果為 null${NC}"
        log_message_core "錯誤: ${field_name}解析結果為 null"
        return 1
    fi
    
    # 如果提供了額外的驗證函數，則調用它
    if [ -n "$validation_func" ] && command -v "$validation_func" >/dev/null 2>&1; then
        if ! $validation_func "$value"; then
            echo -e "${RED}錯誤: ${field_name}格式驗證失敗: $value${NC}"
            log_message_core "錯誤: ${field_name}格式驗證失敗: $value"
            return 1
        fi
    fi
    
    return 0
}

# 驗證 AWS 設定檔
validate_aws_profile() {
    local profile_name="$1"
    
    if [ -z "$profile_name" ]; then
        echo -e "${RED}錯誤: AWS 設定檔名稱不能為空${NC}"
        log_message_core "錯誤: AWS 設定檔名稱為空"
        return 1
    fi
    
    # 檢查設定檔是否存在
    if ! aws configure list-profiles | grep -qw "$profile_name"; then
        echo -e "${RED}錯誤: 找不到指定的 AWS 設定檔: $profile_name${NC}"
        log_message_core "錯誤: 找不到指定的 AWS 設定檔: $profile_name"
        return 1
    fi
    
    return 0
}

# 驗證 EC2 實例 ID
validate_instance_id() {
    local instance_id="$1"
    
    if [[ ! "$instance_id" =~ ^i-[0-9a-f]{17}$ ]]; then
        echo -e "${RED}錯誤: 無效的 EC2 實例 ID 格式: $instance_id${NC}"
        log_message_core "錯誤: 無效的 EC2 實例 ID 格式: $instance_id"
        return 1
    fi
    
    return 0
}

# 驗證安全組 ID
validate_security_group_id() {
    local sg_id="$1"
    
    if [[ ! "$sg_id" =~ ^sg-[0-9a-f]{8,17}$ ]]; then
        echo -e "${RED}錯誤: 無效的安全組 ID 格式: $sg_id${NC}"
        log_message_core "錯誤: 無效的安全組 ID 格式: $sg_id"
        return 1
    fi
    
    return 0
}

# 驗證子網路的可用性
validate_subnet_availability() {
    local subnet_id="$1"
    
    # 檢查子網路是否存在
    local subnet_exists
    subnet_exists=$(aws ec2 describe-subnets --subnet-ids "$subnet_id" --query "Subnets[0].SubnetId" --output text 2>/dev/null)
    
    if [ "$subnet_exists" == "None" ]; then
        echo -e "${RED}錯誤: 找不到指定的子網路: $subnet_id${NC}"
        log_message_core "錯誤: 找不到指定的子網路: $subnet_id"
        return 1
    fi
    
    # 檢查子網路是否可用
    local subnet_state
    subnet_state=$(aws ec2 describe-subnets --subnet-ids "$subnet_id" --query "Subnets[0].State" --output text 2>/dev/null)
    
    if [ "$subnet_state" != "available" ]; then
        echo -e "${RED}錯誤: 子網路 $subnet_id 當前狀態為 $subnet_state，無法使用${NC}"
        log_message_core "錯誤: 子網路 $subnet_id 當前狀態為 $subnet_state"
        return 1
    fi
    
    return 0
}

# 驗證 VPC 的可用性
validate_vpc_availability() {
    local vpc_id="$1"
    
    # 檢查 VPC 是否存在
    local vpc_exists
    vpc_exists=$(aws ec2 describe-vpcs --vpc-ids "$vpc_id" --query "Vpcs[0].VpcId" --output text 2>/dev/null)
    
    if [ "$vpc_exists" == "None" ]; then
        echo -e "${RED}錯誤: 找不到指定的 VPC: $vpc_id${NC}"
        log_message_core "錯誤: 找不到指定的 VPC: $vpc_id"
        return 1
    fi
    
    # 檢查 VPC 是否可用
    local vpc_state
    vpc_state=$(aws ec2 describe-vpcs --vpc-ids "$vpc_id" --query "Vpcs[0].State" --output text 2>/dev/null)
    
    if [ "$vpc_state" != "available" ]; then
        echo -e "${RED}錯誤: VPC $vpc_id 當前狀態為 $vpc_state，無法使用${NC}"
        log_message_core "錯誤: VPC $vpc_id 當前狀態為 $vpc_state"
        return 1
    fi
    
    return 0
}

# 驗證端點的可用性
validate_endpoint_availability() {
    local endpoint_id="$1"
    
    # 檢查端點是否存在
    local endpoint_exists
    endpoint_exists=$(aws ec2 describe-vpn-connections --vpn-connection-ids "$endpoint_id" --query "VpnConnections[0].VpnConnectionId" --output text 2>/dev/null)
    
    if [ "$endpoint_exists" == "None" ]; then
        echo -e "${RED}錯誤: 找不到指定的端點: $endpoint_id${NC}"
        log_message_core "錯誤: 找不到指定的端點: $endpoint_id"
        return 1
    fi
    
    # 檢查端點是否可用
    local endpoint_state
    endpoint_state=$(aws ec2 describe-vpn-connections --vpn-connection-ids "$endpoint_id" --query "VpnConnections[0].State" --output text 2>/dev/null)
    
    if [ "$endpoint_state" != "available" ]; then
        echo -e "${RED}錯誤: 端點 $endpoint_id 當前狀態為 $endpoint_state，無法使用${NC}"
        log_message_core "錯誤: 端點 $endpoint_id 當前狀態為 $endpoint_state"
        return 1
    fi
    
    return 0
}

# 驗證路由表 ID
validate_route_table_id() {
    local route_table_id="$1"
    
    if [[ ! "$route_table_id" =~ ^rtb-[0-9a-f]{8,17}$ ]]; then
        echo -e "${RED}錯誤: 無效的路由表 ID 格式: $route_table_id${NC}"
        log_message_core "錯誤: 無效的路由表 ID 格式: $route_table_id"
        return 1
    fi
    
    return 0
}

# 驗證 NAT 網關 ID
validate_nat_gateway_id() {
    local nat_gateway_id="$1"
    
    if [[ ! "$nat_gateway_id" =~ ^nat-[0-9a-f]{8,17}$ ]]; then
        echo -e "${RED}錯誤: 無效的 NAT 網關 ID 格式: $nat_gateway_id${NC}"
        log_message_core "錯誤: 無效的 NAT 網關 ID 格式: $nat_gateway_id"
        return 1
    fi
    
    return 0
}

# 驗證 VPC Peering 連接 ID
validate_vpc_peering_connection_id() {
    local peering_connection_id="$1"
    
    if [[ ! "$peering_connection_id" =~ ^pcx-[0-9a-f]{8,17}$ ]]; then
        echo -e "${RED}錯誤: 無效的 VPC Peering 連接 ID 格式: $peering_connection_id${NC}"
        log_message_core "錯誤: 無效的 VPC Peering 連接 ID 格式: $peering_connection_id"
        return 1
    fi
    
    return 0
}

# 驗證 Transit Gateway ID
validate_transit_gateway_id() {
    local transit_gateway_id="$1"
    
    if [[ ! "$transit_gateway_id" =~ ^tgw-[0-9a-f]{8,17}$ ]]; then
        echo -e "${RED}錯誤: 無效的 Transit Gateway ID 格式: $transit_gateway_id${NC}"
        log_message_core "錯誤: 無效的 Transit Gateway ID 格式: $transit_gateway_id"
        return 1
    fi
    
    return 0
}

# 驗證 VPN 連接 ID
validate_vpn_connection_id() {
    local vpn_connection_id="$1"
    
    if [[ ! "$vpn_connection_id" =~ ^vpn-[0-9a-f]{8,17}$ ]]; then
        echo -e "${RED}錯誤: 無效的 VPN 連接 ID 格式: $vpn_connection_id${NC}"
        log_message_core "錯誤: 無效的 VPN 連接 ID 格式: $vpn_connection_id"
        return 1
    fi
    
    return 0
}

# 驗證 VPN 客戶端配置文件
validate_vpn_client_config() {
    local config_file="$1"
    
    if [ ! -f "$config_file" ]; then
        echo -e "${RED}錯誤: 找不到 VPN 客戶端配置文件: $config_file${NC}"
        log_message_core "錯誤: 找不到 VPN 客戶端配置文件: $config_file"
        return 1
    fi
    
    # 檢查文件內容是否為有效的配置（簡單檢查是否包含 "client" 和 "remote" 行）
    if ! grep -qE '^(client|remote)' "$config_file"; then
        echo -e "${RED}錯誤: 無效的 VPN 客戶端配置文件格式: $config_file${NC}"
        log_message_core "錯誤: 無效的 VPN 客戶端配置文件格式: $config_file"
        return 1
    fi
    
    return 0
}

# 驗證 OpenVPN 版本
validate_openvpn_version() {
    local required_version="2.4"
    
    # 嘗試獲取當前安裝的 OpenVPN 版本
    local installed_version
    installed_version=$(openvpn --version | head -n 1 | awk '{print $2}' | sed 's/[^0-9.]*//g')
    
    if [ -z "$installed_version" ]; then
        echo -e "${RED}錯誤: 無法檢測到 OpenVPN 安裝版本${NC}"
        log_message_core "錯誤: 無法檢測到 OpenVPN 安裝版本"
        return 1
    fi
    
    # 比較版本號
    if ! dpkg --compare-versions "$installed_version" ge "$required_version"; then
        echo -e "${RED}錯誤: OpenVPN 版本過舊，請升級到 $required_version 或更高版本${NC}"
        log_message_core "錯誤: OpenVPN 版本過舊: $installed_version"
        return 1
    fi
    
    return 0
}

# 驗證 AWS CLI 配置
validate_aws_cli_configuration() {
    # 檢查 AWS CLI 是否已配置
    local aws_access_key_id
    local aws_secret_access_key
    local aws_region
    
    aws_access_key_id=$(aws configure get aws_access_key_id)
    aws_secret_access_key=$(aws configure get aws_secret_access_key)
    aws_region=$(aws configure get region)
    
    if [ -z "$aws_access_key_id" ] || [ -z "$aws_secret_access_key" ] || [ -z "$aws_region" ]; then
        echo -e "${RED}錯誤: AWS CLI 尚未正確配置，請運行 'aws configure' 進行配置${NC}"
        log_message_core "錯誤: AWS CLI 尚未正確配置"
        return 1
    fi
    
    return 0
}

# 檢查必要工具
check_prerequisites() {
    echo -e "\\n${YELLOW}檢查必要工具...${NC}"
    
    local tools=("brew" "aws" "jq" "easyrsa")
    local missing_tools=()
    
    for tool in "${tools[@]}"; do
        if ! command -v "$tool" &> /dev/null; then # Quoted $tool
            missing_tools+=("$tool")
        else
            echo -e "${GREEN}✓ $tool 已安裝${NC}" # $tool is safe here as it's from a predefined list
        fi
    done
    
    if [ ${#missing_tools[@]} -gt 0 ]; then
        echo -e "${RED}缺少必要工具: ${missing_tools[*]}${NC}"
        echo -e "${YELLOW}正在安裝缺少的工具...${NC}"
        
        # 安裝缺少的工具
        if [[ " ${missing_tools[*]} " =~ " brew " ]]; then # No need to quote here, it's a fixed string comparison
            echo -e "${BLUE}安裝 Homebrew...${NC}"
            /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install.sh)"
        fi
        
        for tool in "${missing_tools[@]}"; do
            if [[ "$tool" != "brew" ]]; then
                echo -e "${BLUE}安裝 $tool...${NC}" # $tool is safe here
                case "$tool" in # Quoted $tool
                    "aws")
                        brew install awscli
                        ;;
                    "jq")
                        brew install jq
                        ;;
                    "easyrsa")
                        brew install easy-rsa
                        ;;
                esac
            fi
        done
    fi
    
    echo -e "${GREEN}所有必要工具已準備就緒！${NC}"
}

# 載入配置文件的統一函式
load_config_core() {
    local config_file="$1"
    
    if [ -z "$config_file" ]; then
        echo -e "${RED}錯誤：未提供配置文件路徑${NC}" >&2
        return 1
    fi
    
    if [ ! -f "$config_file" ]; then
        echo -e "${RED}錯誤：配置文件 \"$config_file\" 不存在${NC}" >&2 # Quoted $config_file
        return 1
    fi
    
    # 載入配置文件
    source "$config_file"
    return 0
}

# 統一的配置驗證函式
validate_main_config() {
    local config_file="$1"
    
    if [ -z "$config_file" ]; then
        echo -e "${RED}錯誤：未提供配置文件路徑${NC}" >&2
        return 1
    fi
    
    if ! load_config_core "$config_file"; then
        return 1
    fi
    
    # 檢查基本必要變數 - 只驗證實際使用的變數
    local required_vars_main=("AWS_REGION")
    local missing_vars=()
    for var in "${required_vars_main[@]}"; do
        if [ -z "${!var}" ]; then
            missing_vars+=("$var")
        fi
    done

    if [ ${#missing_vars[@]} -gt 0 ]; then
        echo -e "${RED}錯誤：主配置文件 (\"$config_file\") 中缺少以下必要變數: ${missing_vars[*]}${NC}" >&2 # Quoted $config_file
        log_message_core "錯誤：主配置文件 (\"$config_file\") 中缺少以下必要變數: ${missing_vars[*]}" # Quoted $config_file
        return 1
    fi
    
    echo -e "${GREEN}主配置文件 (\"$config_file\") 驗證通過。${NC}" # Quoted $config_file
    log_message_core "主配置文件 (\"$config_file\") 驗證通過。" # Quoted $config_file
    return 0
}

# 檢查端點相關操作的必要參數 (通常在主設定檔已載入後呼叫)
validate_endpoint_operation() {
    # 注意：此函數預期主設定檔已被成功載入且 AWS_REGION 已驗證
    # validate_main_config 應該在此之前被呼叫
    
    local required_vars_endpoint=("ENDPOINT_ID" "SERVER_CERT_ARN") # SERVER_CERT_ARN 也常與端點操作相關
    local missing_vars_endpoint=()

    for var in "${required_vars_endpoint[@]}"; do
        if [ -z "${!var}" ]; then
            missing_vars_endpoint+=("$var")
        fi
    done

    if [ ${#missing_vars_endpoint[@]} -gt 0 ]; then
        echo -e "${RED}錯誤：執行端點操作前，以下必要變數未在配置中設定或載入: ${missing_vars_endpoint[*]}${NC}" >&2
        log_message_core "錯誤：執行端點操作前，以下必要變數未在配置中設定或載入: ${missing_vars_endpoint[*]}" 
        return 1
    fi
    
    return 0
}

# 驗證文件路徑
validate_file_path() {
    local file_path="$1"
    
    if [ -z "$file_path" ]; then
        echo -e "${RED}錯誤: 文件路徑不能為空${NC}"
        log_message_core "錯誤: 文件路徑為空"
        return 1
    fi
    
    # 檢查路徑格式（基本檢查，避免明顯的惡意輸入）
    if [[ "$file_path" =~ \.\./\.\. ]] || [[ "$file_path" =~ [[:cntrl:]] ]]; then
        echo -e "${RED}錯誤: 文件路徑包含不安全的字符${NC}"
        log_message_core "錯誤: 文件路徑包含不安全的字符: $file_path"
        return 1
    fi
    
    # 檢查文件是否存在
    if [ ! -f "$file_path" ]; then
        echo -e "${RED}錯誤: 文件不存在: $file_path${NC}"
        log_message_core "錯誤: 文件不存在: $file_path"
        return 1
    fi
    
    # 檢查文件是否可讀
    if [ ! -r "$file_path" ]; then
        echo -e "${RED}錯誤: 文件無法讀取: $file_path${NC}"
        log_message_core "錯誤: 文件無法讀取: $file_path"
        return 1
    fi
    
    return 0
}

# 驗證文件路徑（允許空值）
validate_file_path_allow_empty() {
    local file_path="$1"
    
    # 允許空值
    if [ -z "$file_path" ]; then
        return 0
    fi
    
    # 如果不為空，則使用標準文件路徑驗證
    validate_file_path "$file_path"
}

# 通用錯誤處理函數
# 參數:
# $1: 錯誤訊息
# $2: (可選) AWS CLI 指令的退出碼 (如果適用)
# $3: (可選) 是否終止腳本 (預設: 1 表示終止)
handle_error() {
    local error_message="$1"
    local exit_code="${2:-}" # 如果提供了指令的退出碼
    local terminate_script="${3:-1}" # 預設終止腳本

    echo -e "${RED}錯誤: $error_message${NC}" >&2
    log_message_core "錯誤: $error_message"

    if [ -n "$exit_code" ] && [ "$exit_code" -ne 0 ]; then
        log_message_core "相關指令退出碼: $exit_code"
    fi

    if [ "$terminate_script" -eq 1 ]; then
        echo -e "${RED}腳本執行已終止。請檢查日誌 (\"$LOG_FILE_CORE\") 以獲取更多詳細資訊。${NC}" >&2 # Quoted $LOG_FILE_CORE
        log_message_core "腳本執行已終止。"
        exit 1
    fi
}

# 檢查端點相關操作的必要參數
validate_endpoint_operation_config_file_arg() { # 重新命名以避免與上面的衝突，如果需要傳遞 config_file
    local config_file="$1"
    
    # 這裡的邏輯與 validate_endpoint_operation 類似，但它接收 config_file 作為參數
    # 實際上，validate_endpoint_operation 應該在 config_file 已被 source 後調用
    # 所以這個函數可能多餘，或者需要重新思考其用途
    # 暫時保留結構，但標记為待檢視
    # TODO: Review if this function is still needed or how it should integrate with validate_endpoint_operation
    if ! validate_main_config "$config_file"; then # 確保主設定檔有效
        return 1
    fi
    
    # 載入設定檔以檢查 ENDPOINT_ID
    # 但 validate_main_config 已經 source 過了，所以這裡不需要再次 source
    # source "$config_file" 

    local required_vars_endpoint_arg=("ENDPOINT_ID" "SERVER_CERT_ARN")
    local missing_vars_endpoint_arg=()

    for var in "${required_vars_endpoint_arg[@]}"; do
        if [ -z "${!var}" ]; then # 檢查已 source 的變數
            missing_vars_endpoint_arg+=("$var")
        fi
    done

    if [ ${#missing_vars_endpoint_arg[@]} -gt 0 ]; then
        echo -e "${RED}錯誤 (來自 \"$config_file\")：執行端點操作前，以下必要變數未設定: ${missing_vars_endpoint_arg[*]}${NC}" >&2 # Quoted $config_file
        log_message_core "錯誤 (來自 \"$config_file\")：執行端點操作前，以下必要變數未設定: ${missing_vars_endpoint_arg[*]}" # Quoted $config_file
        return 1
    fi
    
    return 0
}


# 統一的日誌記錄函式
log_operation_result() {
    local operation="$1"
    local result="$2"
    local caller="${3:-main script}"
    
    if [ -z "$operation" ] || [ -z "$result" ]; then
        log_message_core "錯誤：log_operation_result 調用時缺少參數"
        return 1
    fi
    
    if [ "$result" -eq 0 ]; then
        log_message_core "${operation}操作成功 (由 $caller 調用)" # $operation and $caller are likely safe but can be quoted if strictness is paramount
    else
        log_message_core "錯誤: ${operation}操作失敗 (返回碼 $result, 由 $caller 調用)" # Same as above
    fi
}

# 發現可用的 VPCs (從主腳本移到核心函式)
discover_available_vpcs_core() {
    local aws_region="$1"
    
    if [ -z "$aws_region" ]; then
        echo -e "${RED}錯誤：未提供 AWS 區域${NC}" >&2
        return 1
    fi
    
    echo -e "\\n${CYAN}=== 發現可用的 VPCs ===${NC}"
    echo -e "${BLUE}掃描 \"$aws_region\" 區域中的 VPCs...${NC}" # Quoted $aws_region
    
    # 獲取所有 VPCs
    local vpcs_json
    vpcs_json=$(aws ec2 describe-vpcs --region "$aws_region" 2>/dev/null)
    
    if [ $? -ne 0 ]; then
        echo -e "${RED}無法獲取 VPC 資訊。請檢查 AWS 憑證和權限。${NC}"
        return 1
    fi
    
    local vpc_count
    if ! vpc_count=$(echo "$vpcs_json" | jq '.Vpcs | length' 2>/dev/null); then
        # 備用解析方法：使用 grep 統計 VPC 數量
        vpc_count=$(echo "$vpcs_json" | grep -c '"VpcId"' || echo "0")
    fi
    
    if [ "$vpc_count" -eq 0 ]; then
        echo -e "${YELLOW}在 \"$aws_region\" 區域中未找到任何 VPC。${NC}" # Quoted $aws_region
        return 0
    fi
    
    echo -e "${GREEN}找到 $vpc_count 個 VPC(s)：${NC}\\
" # $vpc_count is a number, safe
    
    # 顯示 VPC 詳細資訊
    echo "$vpcs_json" | jq -r '.Vpcs[] | 
    "VPC ID: \\(.VpcId)
CIDR: \\(.CidrBlock)
名稱: \\(.Tags[]? | select(.Key=="Name") | .Value // "未命名")
狀態: \\(.State)
預設: \\(if .IsDefault then "是" else "否" end)
----------------------------------------"'
    
    return 0
}

# 統一的配置更新函式
update_config() {
    local config_file="$1"
    local param_name="$2"
    local param_value="$3"
    
    if [ -z "$config_file" ] || [ -z "$param_name" ]; then
        echo -e "${RED}錯誤：update_config 缺少必要參數${NC}" >&2
        log_message_core "錯誤：update_config 調用缺少必要參數"
        return 1
    fi
    
    # 如果配置文件不存在，創建一個新的
    if [ ! -f "$config_file" ]; then
        echo "# VPN 管理配置文件" > "$config_file"
        log_message_core "創建新的配置文件: $config_file"
    fi
    
    # 使用 sed 更新或添加參數
    if grep -q "^${param_name}=" "$config_file"; then
        # 參數已存在，更新值
        if [ "$(uname)" = "Darwin" ]; then
            # macOS 版本的 sed
            sed -i '' "s|^${param_name}=.*|${param_name}=\"${param_value}\"|" "$config_file"
        else
            # Linux 版本的 sed
            sed -i "s|^${param_name}=.*|${param_name}=\"${param_value}\"|" "$config_file"
        fi
        log_message_core "更新配置參數: ${param_name}=${param_value}"
    else
        # 參數不存在，添加到文件末尾
        echo "${param_name}=\"${param_value}\"" >> "$config_file"
        log_message_core "添加新配置參數: ${param_name}=${param_value}"
    fi
    
    echo -e "${GREEN}已更新配置：${param_name}=${param_value}${NC}"
    return 0
}

# 安全輸入函數
# 參數:
# $1: 提示信息
# $2: 變數名稱 (會設置到這個變數中)
# $3: 驗證函數名稱
# $4-$6: (可選) 驗證函數的額外參數
read_secure_input() {
    local prompt="$1"
    local var_name="$2"
    local validation_func="$3"
    local validation_arg1="$4"
    local validation_arg2="$5"
    local validation_arg3="$6"
    
    if [ -z "$prompt" ] || [ -z "$var_name" ]; then
        log_message_core "錯誤: read_secure_input 調用缺少必要參數"
        return 1
    fi
    
    local input_value
    local attempts=0
    local max_attempts=3
    
    while [ $attempts -lt $max_attempts ]; do
        echo -n -e "${prompt}"
        read -r input_value
        
        # 基本清理：去除前後空白
        input_value=$(echo "$input_value" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        
        # 如果提供了驗證函數，則執行驗證
        if [ -n "$validation_func" ] && command -v "$validation_func" >/dev/null 2>&1; then
            # 根據參數數量調用驗證函數
            if [ -n "$validation_arg3" ]; then
                if $validation_func "$input_value" "$validation_arg1" "$validation_arg2" "$validation_arg3"; then
                    # 設置變數到指定的變數名
                    eval "$var_name=\"$input_value\""
                    log_message_core "安全輸入驗證成功: $var_name"
                    return 0
                fi
            elif [ -n "$validation_arg2" ]; then
                if $validation_func "$input_value" "$validation_arg1" "$validation_arg2"; then
                    eval "$var_name=\"$input_value\""
                    log_message_core "安全輸入驗證成功: $var_name"
                    return 0
                fi
            elif [ -n "$validation_arg1" ]; then
                if $validation_func "$input_value" "$validation_arg1"; then
                    eval "$var_name=\"$input_value\""
                    log_message_core "安全輸入驗證成功: $var_name"
                    return 0
                fi
            else
                if $validation_func "$input_value"; then
                    eval "$var_name=\"$input_value\""
                    log_message_core "安全輸入驗證成功: $var_name"
                    return 0
                fi
            fi
            
            # 驗證失敗
            attempts=$((attempts + 1))
            if [ $attempts -lt $max_attempts ]; then
                echo -e "${YELLOW}輸入驗證失敗，請重試 ($attempts/$max_attempts)${NC}"
            fi
        else
            # 沒有驗證函數，直接接受輸入
            eval "$var_name=\"$input_value\""
            log_message_core "安全輸入接受（無驗證）: $var_name"
            return 0
        fi
    done
    
    # 達到最大嘗試次數
    echo -e "${RED}錯誤: 達到最大輸入嘗試次數 ($max_attempts)${NC}"
    log_message_core "錯誤: read_secure_input 達到最大嘗試次數: $var_name"
    return 1
}

# 安全隱藏輸入函數（用於密碼等敏感信息）
# 參數:
# $1: 提示信息
# $2: 變數名稱 (會設置到這個變數中)
# $3: 驗證函數名稱
read_secure_hidden_input() {
    local prompt="$1"
    local var_name="$2"
    local validation_func="$3"
    
    if [ -z "$prompt" ] || [ -z "$var_name" ]; then
        log_message_core "錯誤: read_secure_hidden_input 調用缺少必要參數"
        return 1
    fi
    
    local input_value
    local attempts=0
    local max_attempts=3
    
    while [ $attempts -lt $max_attempts ]; do
        echo -n -e "${prompt}"
        read -s -r input_value
        echo  # 換行，因為 -s 選項不會自動換行
        
        # 基本清理：去除前後空白
        input_value=$(echo "$input_value" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        
        # 如果提供了驗證函數，則執行驗證
        if [ -n "$validation_func" ] && command -v "$validation_func" >/dev/null 2>&1; then
            if $validation_func "$input_value"; then
                # 設置變數到指定的變數名
                eval "$var_name=\"$input_value\""
                log_message_core "安全隱藏輸入驗證成功: $var_name"
                return 0
            fi
            
            # 驗證失敗
            attempts=$((attempts + 1))
            if [ $attempts -lt $max_attempts ]; then
                echo -e "${YELLOW}輸入驗證失敗，請重試 ($attempts/$max_attempts)${NC}"
            fi
        else
            # 沒有驗證函數，直接接受輸入
            eval "$var_name=\"$input_value\""
            log_message_core "安全隱藏輸入接受（無驗證）: $var_name"
            return 0
        fi
    done
    
    # 達到最大嘗試次數
    echo -e "${RED}錯誤: 達到最大輸入嘗試次數 ($max_attempts)${NC}"
    log_message_core "錯誤: read_secure_hidden_input 達到最大嘗試次數: $var_name"
    return 1
}
