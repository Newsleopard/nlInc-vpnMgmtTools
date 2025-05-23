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

# 檢查必要工具
check_prerequisites() {
    echo -e "\n${YELLOW}檢查必要工具...${NC}"
    
    local tools=("brew" "aws" "jq" "easyrsa")
    local missing_tools=()
    
    for tool in "${tools[@]}"; do
        if ! command -v $tool &> /dev/null; then
            missing_tools+=($tool)
        else
            echo -e "${GREEN}✓ $tool 已安裝${NC}"
        fi
    done
    
    if [ ${#missing_tools[@]} -gt 0 ]; then
        echo -e "${RED}缺少必要工具: ${missing_tools[*]}${NC}"
        echo -e "${YELLOW}正在安裝缺少的工具...${NC}"
        
        # 安裝缺少的工具
        if [[ " ${missing_tools[*]} " =~ " brew " ]]; then
            echo -e "${BLUE}安裝 Homebrew...${NC}"
            /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install.sh)"
        fi
        
        for tool in "${missing_tools[@]}"; do
            if [[ "$tool" != "brew" ]]; then
                echo -e "${BLUE}安裝 $tool...${NC}"
                case $tool in
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
        echo -e "${RED}錯誤：配置文件 $config_file 不存在${NC}" >&2
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
    
    # 檢查基本必要變數
    local required_vars_main=("AWS_REGION" "EASYRSA_DIR" "CERT_OUTPUT_DIR" "SERVER_CERT_NAME_PREFIX" "CLIENT_CERT_NAME_PREFIX")
    local missing_vars=()
    for var in "${required_vars_main[@]}"; do
        if [ -z "${!var}" ]; then
            missing_vars+=("$var")
        fi
    done

    if [ ${#missing_vars[@]} -gt 0 ]; then
        echo -e "${RED}錯誤：主配置文件 ($config_file) 中缺少以下必要變數: ${missing_vars[*]}${NC}" >&2
        log_message "錯誤：主配置文件 ($config_file) 中缺少必要變數: ${missing_vars[*]}"
        return 1
    fi
    
    echo -e "${GREEN}主配置文件 ($config_file) 驗證通過。${NC}"
    log_message "主配置文件 ($config_file) 驗證通過。"
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
        log_message "錯誤：執行端點操作前，以下必要變數未在配置中設定或載入: ${missing_vars_endpoint[*]}"
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
    log_message "錯誤: $error_message"

    if [ -n "$exit_code" ] && [ "$exit_code" -ne 0 ]; then
        log_message "相關指令退出碼: $exit_code"
    fi

    if [ "$terminate_script" -eq 1 ]; then
        echo -e "${RED}腳本執行已終止。請檢查日誌 ($LOG_FILE_CORE) 以獲取更多詳細資訊。${NC}" >&2
        log_message "腳本執行已終止。"
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
        echo -e "${RED}錯誤 (來自 $config_file)：執行端點操作前，以下必要變數未設定: ${missing_vars_endpoint_arg[*]}${NC}" >&2
        log_message "錯誤 (來自 $config_file)：執行端點操作前，以下必要變數未設定: ${missing_vars_endpoint_arg[*]}"
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
        log_message "錯誤：log_operation_result 調用時缺少參數"
        return 1
    fi
    
    if [ "$result" -eq 0 ]; then
        log_message "${operation}操作成功 (由 $caller 調用)"
    else
        log_message "錯誤: ${operation}操作失敗 (返回碼 $result, 由 $caller 調用)"
    fi
}

# 發現可用的 VPCs (從主腳本移到核心函式)
discover_available_vpcs_core() {
    local aws_region="$1"
    
    if [ -z "$aws_region" ]; then
        echo -e "${RED}錯誤：未提供 AWS 區域${NC}" >&2
        return 1
    fi
    
    echo -e "\n${CYAN}=== 發現可用的 VPCs ===${NC}"
    echo -e "${BLUE}掃描 $aws_region 區域中的 VPCs...${NC}"
    
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
        echo -e "${YELLOW}在 $aws_region 區域中未找到任何 VPC。${NC}"
        return 0
    fi
    
    echo -e "${GREEN}找到 $vpc_count 個 VPC(s)：${NC}\n"
    
    # 顯示 VPC 詳細資訊
    echo "$vpcs_json" | jq -r '.Vpcs[] | 
    "VPC ID: \(.VpcId)
CIDR: \(.CidrBlock)
名稱: \(.Tags[]? | select(.Key=="Name") | .Value // "未命名")
狀態: \(.State)
預設: \(if .IsDefault then "是" else "否" end)
----------------------------------------"'
    
    return 0
}
