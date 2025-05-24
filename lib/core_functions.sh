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
    
    # AWS Secret Access Key 格式：40個字元，base64編碼格式
    if [[ ! "$secret_key" =~ ^[A-Za-z0-9+/]{40}$ ]]; then
        echo -e "${RED}錯誤: AWS Secret Access Key 格式無效 (應為 40 個字元的 base64 格式)${NC}"
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

# 驗證檔案是否存在且可讀
validate_file_exists_readable() {
    local file_path="$1"
    
    if [ -z "$file_path" ]; then
        echo -e "${RED}錯誤: 檔案路徑不能為空${NC}"
        log_message_core "錯誤: 檔案路徑為空"
        return 1
    fi
    
    if [ ! -f "$file_path" ]; then
        echo -e "${RED}錯誤: 檔案不存在: $file_path${NC}"
        log_message_core "錯誤: 檔案不存在: $file_path"
        return 1
    fi
    
    if [ ! -r "$file_path" ]; then
        echo -e "${RED}錯誤: 檔案無法讀取: $file_path${NC}"
        log_message_core "錯誤: 檔案無法讀取: $file_path"
        return 1
    fi
    
    return 0
}

# 驗證路徑是否可寫（允許空值）
validate_path_writable_allow_empty() {
    local path="$1"
    
    # 允許空值
    if [ -z "$path" ]; then
        return 0
    fi
    
    local dir_path
    dir_path=$(dirname "$path")
    
    if [ ! -d "$dir_path" ]; then
        echo -e "${RED}錯誤: 目錄不存在: $dir_path${NC}"
        log_message_core "錯誤: 目錄不存在: $dir_path"
        return 1
    fi
    
    if [ ! -w "$dir_path" ]; then
        echo -e "${RED}錯誤: 目錄無法寫入: $dir_path${NC}"
        log_message_core "錯誤: 目錄無法寫入: $dir_path"
        return 1
    fi
    
    return 0
}

# 安全輸入讀取函數
read_secure_input() {
    local prompt="$1"
    local var_name="$2"
    local validation_func="$3"
    local max_attempts="${4:-3}"
    
    local attempt=1
    while [ $attempt -le $max_attempts ]; do
        echo -n "$prompt"
        read -r input_value
        
        # 檢查輸入是否為空
        if [ -z "$input_value" ]; then
            echo -e "${RED}錯誤: 輸入不能為空${NC}"
            ((attempt++))
            continue
        fi
        
        # 如果提供了驗證函數，則進行驗證
        if [ -n "$validation_func" ]; then
            if $validation_func "$input_value"; then
                printf -v "$var_name" '%s' "$input_value"
                return 0
            else
                echo -e "${RED}錯誤: 輸入格式無效${NC}"
                ((attempt++))
                continue
            fi
        else
            printf -v "$var_name" '%s' "$input_value"
            return 0
        fi
    done
    
    echo -e "${RED}錯誤: 達到最大嘗試次數，退出${NC}"
    return 1
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
    # 暫時保留結構，但標記為待檢視
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
    vpc_count=$(echo "$vpcs_json" | jq '.Vpcs | length')
    
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
