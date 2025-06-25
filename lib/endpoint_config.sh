#!/bin/bash

# lib/endpoint_config.sh
# VPN 端點配置管理相關函式庫
# 包含配置文件創建、更新和驗證功能

# 確保已載入核心函式
if [ -z "$LOG_FILE_CORE" ]; then
    echo "錯誤: 核心函式庫未載入。請先載入 core_functions.sh"
    exit 1
fi

# 輔助函式：立即保存端點基本配置 (防止後續步驟失敗)
# 參數: $1=config_file, $2=endpoint_id, $3=sg_id, $4=server_cert_arn, $5=ca_cert_arn, $6=vpc_id, $7=subnet_id, $8=vpn_cidr, $9=vpn_name, $10=vpc_cidr
# 注意: $5 是 CA 證書 ARN (來自 import_certificates_to_acm_lib 的 client_cert_arn)
save_initial_endpoint_config() {
    local config_file="$1"
    local endpoint_id="$2"
    local sg_id="$3"
    local server_cert_arn="$4"
    local ca_cert_arn="$5"  # Fix 1: 正確映射 CA 證書 ARN
    local vpc_id="$6"
    local subnet_id="$7"
    local vpn_cidr="$8"
    local vpn_name="$9"
    local vpc_cidr="${10}"
    
    # 參數驗證
    if [ -z "$config_file" ] || [ -z "$endpoint_id" ] || [ -z "$server_cert_arn" ] || [ -z "$ca_cert_arn" ]; then
        echo -e "${RED}錯誤: save_initial_endpoint_config 缺少必要參數${NC}" >&2
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
CLIENT_VPN_SECURITY_GROUP_ID="$sg_id"

# ====================================================================
# CERTIFICATE ARNs - AUTO-GENERATED/IMPORTED
# ====================================================================

# AWS Certificate Manager ARNs (generated during certificate import)
CA_CERT_ARN="$ca_cert_arn"
SERVER_CERT_ARN="$server_cert_arn"
CLIENT_CERT_ARN="$ca_cert_arn"
CLIENT_CERT_ARN_admin="$ca_cert_arn"

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

# 預檢查函數：驗證 AWS CLI 參數
debug_aws_cli_params() {
    local vpn_cidr="$1"
    local server_cert_arn="$2"
    local client_cert_arn="$3"
    local vpn_name="$4"
    local vpc_id="$5"
    local subnet_id="$6"
    local aws_region="$7"
    
    echo -e "${CYAN}=== AWS CLI 參數預檢查 ===${NC}"
    
    # 顯示即將使用的參數
    echo -e "${BLUE}VPN 配置參數:${NC}"
    echo -e "  VPN CIDR: ${YELLOW}$vpn_cidr${NC}"
    echo -e "  VPN 名稱: ${YELLOW}$vpn_name${NC}"
    echo -e "  VPC ID: ${YELLOW}$vpc_id${NC}"
    echo -e "  子網路 ID: ${YELLOW}$subnet_id${NC}"
    echo -e "  AWS 區域: ${YELLOW}$aws_region${NC}"
    
    echo -e "${BLUE}證書 ARN:${NC}"
    echo -e "  伺服器證書: ${YELLOW}${server_cert_arn:0:50}...${NC}"
    echo -e "  客戶端證書: ${YELLOW}${client_cert_arn:0:50}...${NC}"
    
    # 基本參數驗證
    local validation_errors=0
    
    # CIDR 格式驗證
    if [[ ! "$vpn_cidr" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}/[0-9]{1,2}$ ]]; then
        echo -e "${RED}✗ VPN CIDR 格式無效: $vpn_cidr${NC}"
        validation_errors=$((validation_errors + 1))
    else
        echo -e "${GREEN}✓ VPN CIDR 格式有效${NC}"
    fi
    
    # ARN 格式驗證
    if [[ ! "$server_cert_arn" =~ ^arn:aws:acm: ]]; then
        echo -e "${RED}✗ 伺服器證書 ARN 格式無效${NC}"
        validation_errors=$((validation_errors + 1))
    else
        echo -e "${GREEN}✓ 伺服器證書 ARN 格式有效${NC}"
    fi
    
    if [[ ! "$client_cert_arn" =~ ^arn:aws:acm: ]]; then
        echo -e "${RED}✗ 客戶端證書 ARN 格式無效${NC}"
        validation_errors=$((validation_errors + 1))
    else
        echo -e "${GREEN}✓ 客戶端證書 ARN 格式有效${NC}"
    fi
    
    # VPC/子網路 ID 格式驗證
    if ! validate_vpc_id "$vpc_id"; then
        echo -e "${RED}✗ VPC ID 格式無效: $vpc_id${NC}"
        validation_errors=$((validation_errors + 1))
    else
        echo -e "${GREEN}✓ VPC ID 格式有效${NC}"
    fi
    
    if [ -n "$subnet_id" ] && ! validate_subnet_id "$subnet_id"; then
        echo -e "${RED}✗ 子網路 ID 格式無效: $subnet_id${NC}"
        validation_errors=$((validation_errors + 1))
    elif [ -n "$subnet_id" ]; then
        echo -e "${GREEN}✓ 子網路 ID 格式有效${NC}"
    fi
    
    # AWS 區域驗證
    if ! validate_aws_region "$aws_region"; then
        echo -e "${RED}✗ AWS 區域無效: $aws_region${NC}"
        validation_errors=$((validation_errors + 1))
    else
        echo -e "${GREEN}✓ AWS 區域有效${NC}"
    fi
    
    echo -e "${CYAN}預檢查完成${NC}"
    
    if [ $validation_errors -gt 0 ]; then
        echo -e "${RED}發現 $validation_errors 個驗證錯誤，建議修正後再繼續${NC}"
        return 1
    else
        echo -e "${GREEN}所有參數驗證通過${NC}"
        return 0
    fi
}

# 載入端點配置文件
# 參數: $1 = config_file_path
load_endpoint_config() {
    local config_file="$1"
    
    if [ -z "$config_file" ]; then
        echo -e "${RED}錯誤: 配置文件路徑為空${NC}" >&2
        return 1
    fi
    
    if [ ! -f "$config_file" ]; then
        echo -e "${RED}錯誤: 配置文件不存在: $config_file${NC}" >&2
        return 1
    fi
    
    # 載入配置文件
    source "$config_file"
    
    # 驗證關鍵變數是否已載入
    if [ -z "$ENDPOINT_ID" ]; then
        echo -e "${YELLOW}警告: ENDPOINT_ID 未在配置文件中找到${NC}" >&2
    fi
    
    log_message_core "端點配置已載入: $config_file"
    return 0
}

# 驗證端點配置完整性
# 參數: $1 = config_file_path
validate_endpoint_config() {
    local config_file="$1"
    
    if [ -z "$config_file" ]; then
        echo -e "${RED}錯誤: 配置文件路徑為空${NC}" >&2
        return 1
    fi
    
    if [ ! -f "$config_file" ]; then
        echo -e "${RED}錯誤: 配置文件不存在: $config_file${NC}" >&2
        return 1
    fi
    
    # 檢查必要的配置項目
    local required_vars=("ENDPOINT_ID" "SERVER_CERT_ARN" "CA_CERT_ARN")
    local missing_vars=()
    
    # 臨時載入配置文件來檢查變數
    local temp_config
    temp_config=$(mktemp)
    cp "$config_file" "$temp_config"
    source "$temp_config"
    
    for var in "${required_vars[@]}"; do
        if [ -z "${!var}" ]; then
            missing_vars+=("$var")
        fi
    done
    
    rm -f "$temp_config"
    
    if [ ${#missing_vars[@]} -gt 0 ]; then
        echo -e "${RED}錯誤: 配置文件缺少必要變數: ${missing_vars[*]}${NC}" >&2
        return 1
    fi
    
    echo -e "${GREEN}✓ 端點配置驗證通過${NC}"
    log_message_core "端點配置驗證通過: $config_file"
    return 0
}

# 更新配置文件中的特定值
# 參數: $1 = config_file, $2 = variable_name, $3 = new_value
update_config_value() {
    local config_file="$1"
    local var_name="$2"
    local new_value="$3"
    
    if [ -z "$config_file" ] || [ -z "$var_name" ]; then
        echo -e "${RED}錯誤: update_config_value 缺少必要參數${NC}" >&2
        return 1
    fi
    
    if [ ! -f "$config_file" ]; then
        echo -e "${RED}錯誤: 配置文件不存在: $config_file${NC}" >&2
        return 1
    fi
    
    # 檢查變數是否已存在
    if grep -q "^${var_name}=" "$config_file"; then
        # 更新現有變數
        if [[ "$OSTYPE" == "darwin"* ]]; then
            # macOS
            sed -i '' "s|^${var_name}=.*|${var_name}=\"${new_value}\"|" "$config_file"
        else
            # Linux
            sed -i "s|^${var_name}=.*|${var_name}=\"${new_value}\"|" "$config_file"
        fi
        log_message_core "已更新配置變數: $var_name = $new_value"
    else
        # 添加新變數
        echo "${var_name}=\"${new_value}\"" >> "$config_file"
        log_message_core "已添加配置變數: $var_name = $new_value"
    fi
    
    return 0
}

# 清空配置文件中的特定變數
# 參數: $1 = config_file, $2 = variable_names (array or space-separated string)
clear_config_values() {
    local config_file="$1"
    shift
    local var_names=("$@")
    
    if [ -z "$config_file" ]; then
        echo -e "${RED}錯誤: clear_config_values 缺少配置文件參數${NC}" >&2
        return 1
    fi
    
    if [ ! -f "$config_file" ]; then
        echo -e "${RED}錯誤: 配置文件不存在: $config_file${NC}" >&2
        return 1
    fi
    
    for var_name in "${var_names[@]}"; do
        if grep -q "^${var_name}=" "$config_file"; then
            # 清空現有變數值
            if [[ "$OSTYPE" == "darwin"* ]]; then
                # macOS
                sed -i '' "s|^${var_name}=.*|${var_name}=\"\"|" "$config_file"
            else
                # Linux
                sed -i "s|^${var_name}=.*|${var_name}=\"\"|" "$config_file"
            fi
            log_message_core "已清空配置變數: $var_name"
        fi
    done
    
    return 0
}

# 創建配置文件備份
# 參數: $1 = config_file
backup_config_file() {
    local config_file="$1"
    
    if [ -z "$config_file" ]; then
        echo -e "${RED}錯誤: backup_config_file 缺少配置文件參數${NC}" >&2
        return 1
    fi
    
    if [ ! -f "$config_file" ]; then
        echo -e "${YELLOW}警告: 配置文件不存在，無法備份: $config_file${NC}" >&2
        return 1
    fi
    
    local backup_file="${config_file}.backup.$(date +%Y%m%d_%H%M%S)"
    
    if cp "$config_file" "$backup_file"; then
        echo -e "${GREEN}✓ 配置文件已備份: $backup_file${NC}"
        log_message_core "配置文件已備份: $backup_file"
        return 0
    else
        echo -e "${RED}錯誤: 無法備份配置文件${NC}" >&2
        return 1
    fi
}