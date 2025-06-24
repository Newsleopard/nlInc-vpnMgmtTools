#!/bin/bash

# lib/endpoint_utils.sh
# VPN 端點工具函式庫
# 包含調試、驗證和輔助功能

# 確保已載入核心函式
if [ -z "$LOG_FILE_CORE" ]; then
    echo "錯誤: 核心函式庫未載入。請先載入 core_functions.sh"
    exit 1
fi

# 載入所有端點相關的模組
load_endpoint_modules() {
    local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    local modules=(
        "vpc_operations.sh"
        "security_group_operations.sh"
        "endpoint_config.sh"
        "endpoint_operations.sh"
        "network_association.sh"
    )
    
    local loaded_modules=()
    local failed_modules=()
    
    for module in "${modules[@]}"; do
        local module_path="$script_dir/$module"
        if [ -f "$module_path" ]; then
            if source "$module_path"; then
                loaded_modules+=("$module")
                log_message_core "成功載入模組: $module"
            else
                failed_modules+=("$module")
                echo -e "${YELLOW}警告: 載入模組失敗: $module${NC}" >&2
            fi
        else
            failed_modules+=("$module")
            echo -e "${YELLOW}警告: 模組檔案不存在: $module_path${NC}" >&2
        fi
    done
    
    echo -e "${GREEN}成功載入 ${#loaded_modules[@]} 個模組${NC}" >&2
    if [ ${#failed_modules[@]} -gt 0 ]; then
        echo -e "${YELLOW}無法載入 ${#failed_modules[@]} 個模組: ${failed_modules[*]}${NC}" >&2
        return 1
    fi
    
    return 0
}

# 驗證端點操作的前置條件
# 參數: $1 = config_file_path
validate_endpoint_operation() {
    local config_file="$1"
    
    if [ -z "$config_file" ]; then
        echo -e "${RED}錯誤: validate_endpoint_operation 需要配置文件路徑${NC}" >&2
        return 1
    fi
    
    # 載入配置管理模組
    local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    if [ -f "$script_dir/endpoint_config.sh" ]; then
        source "$script_dir/endpoint_config.sh"
        
        # 載入並驗證配置
        if command -v load_endpoint_config >/dev/null 2>&1; then
            if ! load_endpoint_config "$config_file"; then
                echo -e "${RED}錯誤: 無法載入配置文件: $config_file${NC}" >&2
                return 1
            fi
        fi
        
        if command -v validate_endpoint_config >/dev/null 2>&1; then
            if ! validate_endpoint_config "$config_file"; then
                echo -e "${RED}錯誤: 配置文件驗證失敗${NC}" >&2
                return 1
            fi
        fi
    else
        echo -e "${YELLOW}警告: 配置管理模組不可用，跳過配置驗證${NC}" >&2
        # 嘗試直接載入配置文件
        if [ -f "$config_file" ]; then
            source "$config_file"
        else
            echo -e "${RED}錯誤: 配置文件不存在: $config_file${NC}" >&2
            return 1
        fi
    fi
    
    # 檢查必要變數
    if [ -z "$ENDPOINT_ID" ]; then
        echo -e "${RED}錯誤: ENDPOINT_ID 未在配置中找到${NC}" >&2
        return 1
    fi
    
    if [ -z "$AWS_REGION" ]; then
        echo -e "${RED}錯誤: AWS_REGION 未設定${NC}" >&2
        return 1
    fi
    
    # 驗證端點是否存在
    local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    if [ -f "$script_dir/endpoint_operations.sh" ]; then
        source "$script_dir/endpoint_operations.sh"
        
        if command -v check_endpoint_status >/dev/null 2>&1; then
            local endpoint_status
            endpoint_status=$(check_endpoint_status "$ENDPOINT_ID" "$AWS_REGION")
            
            if [ "$endpoint_status" = "not-found" ]; then
                echo -e "${RED}錯誤: VPN 端點 '$ENDPOINT_ID' 不存在${NC}" >&2
                return 1
            fi
            
            echo -e "${GREEN}✓ VPN 端點存在，狀態: $endpoint_status${NC}" >&2
        fi
    fi
    
    log_message_core "端點操作前置條件驗證通過: $ENDPOINT_ID"
    return 0
}

# 記錄操作結果
# 參數: $1 = operation_name, $2 = result_code, $3 = caller_script
log_operation_result() {
    local operation_name="$1"
    local result_code="$2"
    local caller_script="${3:-unknown}"
    
    if [ -z "$operation_name" ] || [ -z "$result_code" ]; then
        log_message_core "警告: log_operation_result 參數不完整"
        return 1
    fi
    
    if [ "$result_code" -eq 0 ]; then
        log_message_core "操作成功: $operation_name (呼叫者: $caller_script)"
        echo -e "${GREEN}✓ $operation_name 完成${NC}" >&2
    else
        log_message_core "操作失敗: $operation_name (呼叫者: $caller_script, 錯誤碼: $result_code)"
        echo -e "${RED}✗ $operation_name 失敗 (錯誤碼: $result_code)${NC}" >&2
    fi
    
    return 0
}

# 顯示端點資訊摘要
# 參數: $1 = config_file_path
show_endpoint_summary() {
    local config_file="$1"
    
    if [ -z "$config_file" ] || [ ! -f "$config_file" ]; then
        echo -e "${RED}錯誤: 配置文件不存在: $config_file${NC}" >&2
        return 1
    fi
    
    # 載入配置
    source "$config_file"
    
    echo -e "${CYAN}=== VPN 端點資訊摘要 ===${NC}"
    echo -e "${BLUE}端點 ID:${NC} ${ENDPOINT_ID:-未設定}"
    echo -e "${BLUE}VPN 名稱:${NC} ${VPN_NAME:-未設定}"
    echo -e "${BLUE}VPN CIDR:${NC} ${VPN_CIDR:-未設定}"
    echo -e "${BLUE}VPC ID:${NC} ${VPC_ID:-未設定}"
    echo -e "${BLUE}子網路 ID:${NC} ${SUBNET_ID:-未設定}"
    echo -e "${BLUE}AWS 區域:${NC} ${AWS_REGION:-未設定}"
    echo -e "${BLUE}專用安全群組:${NC} ${CLIENT_VPN_SECURITY_GROUP_ID:-未設定}"
    
    echo -e "\n${CYAN}證書資訊:${NC}"
    echo -e "${BLUE}伺服器證書 ARN:${NC} ${SERVER_CERT_ARN:0:50}${SERVER_CERT_ARN:50:+...}"
    echo -e "${BLUE}CA 證書 ARN:${NC} ${CA_CERT_ARN:0:50}${CA_CERT_ARN:50:+...}"
    echo -e "${BLUE}客戶端證書 ARN:${NC} ${CLIENT_CERT_ARN:-未設定}"
    echo -e "${BLUE}管理員證書 ARN:${NC} ${CLIENT_CERT_ARN_admin:-未設定}"
    
    echo -e "\n${CYAN}多 VPC 配置:${NC}"
    echo -e "${BLUE}額外 VPC 數量:${NC} ${MULTI_VPC_COUNT:-0}"
    
    return 0
}

# 檢查所有模組可用性
check_module_availability() {
    local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    local modules=(
        "vpc_operations.sh"
        "security_group_operations.sh"
        "endpoint_config.sh"
        "endpoint_operations.sh"
        "network_association.sh"
    )
    
    echo -e "${CYAN}=== 檢查模組可用性 ===${NC}"
    
    local available_count=0
    local total_count=${#modules[@]}
    
    for module in "${modules[@]}"; do
        local module_path="$script_dir/$module"
        if [ -f "$module_path" ]; then
            echo -e "${GREEN}✓ $module${NC}"
            available_count=$((available_count + 1))
        else
            echo -e "${RED}✗ $module (檔案不存在)${NC}"
        fi
    done
    
    echo -e "\n${BLUE}可用模組: $available_count/$total_count${NC}"
    
    if [ $available_count -eq $total_count ]; then
        echo -e "${GREEN}所有模組都可用${NC}"
        return 0
    else
        echo -e "${YELLOW}部分模組不可用${NC}"
        return 1
    fi
}

# 執行端點健康檢查
# 參數: $1 = config_file_path
run_endpoint_health_check() {
    local config_file="$1"
    
    if [ -z "$config_file" ] || [ ! -f "$config_file" ]; then
        echo -e "${RED}錯誤: 配置文件不存在: $config_file${NC}" >&2
        return 1
    fi
    
    echo -e "${CYAN}=== VPN 端點健康檢查 ===${NC}"
    
    # 載入配置
    source "$config_file"
    
    if [ -z "$ENDPOINT_ID" ] || [ -z "$AWS_REGION" ]; then
        echo -e "${RED}✗ 配置不完整：缺少 ENDPOINT_ID 或 AWS_REGION${NC}"
        return 1
    fi
    
    # 載入模組
    local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    
    # 檢查端點狀態
    echo -e "${BLUE}檢查端點狀態...${NC}"
    if [ -f "$script_dir/endpoint_operations.sh" ]; then
        source "$script_dir/endpoint_operations.sh"
        
        if command -v check_endpoint_status >/dev/null 2>&1; then
            local status
            status=$(check_endpoint_status "$ENDPOINT_ID" "$AWS_REGION")
            
            if [ "$status" = "not-found" ]; then
                echo -e "${RED}✗ 端點不存在${NC}"
                return 1
            else
                echo -e "${GREEN}✓ 端點狀態: $status${NC}"
            fi
        fi
    fi
    
    # 檢查網路關聯
    echo -e "${BLUE}檢查網路關聯...${NC}"
    if [ -f "$script_dir/network_association.sh" ]; then
        source "$script_dir/network_association.sh"
        
        if command -v check_network_associations >/dev/null 2>&1; then
            if check_network_associations "$ENDPOINT_ID" "$AWS_REGION" >/dev/null 2>&1; then
                echo -e "${GREEN}✓ 網路關聯正常${NC}"
            else
                echo -e "${YELLOW}⚠️ 網路關聯檢查失敗${NC}"
            fi
        fi
    fi
    
    # 檢查授權規則
    echo -e "${BLUE}檢查授權規則...${NC}"
    if [ -f "$script_dir/network_association.sh" ]; then
        source "$script_dir/network_association.sh"
        
        if command -v check_authorization_rules >/dev/null 2>&1; then
            if check_authorization_rules "$ENDPOINT_ID" "$AWS_REGION" >/dev/null 2>&1; then
                echo -e "${GREEN}✓ 授權規則正常${NC}"
            else
                echo -e "${YELLOW}⚠️ 授權規則檢查失敗${NC}"
            fi
        fi
    fi
    
    echo -e "${GREEN}健康檢查完成${NC}"
    return 0
}

# 清理臨時文件和備份
# 參數: $1 = base_directory (可選)
cleanup_temp_files() {
    local base_dir="${1:-.}"
    
    echo -e "${BLUE}清理臨時文件...${NC}"
    
    # 清理安全群組命令文件
    if ls security_group_commands_*.sh >/dev/null 2>&1; then
        echo -e "${YELLOW}發現安全群組命令文件，是否刪除？ (y/n): ${NC}"
        read -r cleanup_sg_files
        if [[ "$cleanup_sg_files" =~ ^[Yy]$ ]]; then
            rm -f security_group_commands_*.sh
            echo -e "${GREEN}✓ 安全群組命令文件已清理${NC}"
        fi
    fi
    
    # 清理舊的配置備份（保留最近5個）
    if ls "$base_dir"/**/*.backup.* >/dev/null 2>&1; then
        echo -e "${BLUE}清理舊的配置備份...${NC}"
        find "$base_dir" -name "*.backup.*" -type f -print | head -n -5 | xargs rm -f 2>/dev/null || true
        echo -e "${GREEN}✓ 舊配置備份已清理${NC}"
    fi
    
    # 清理臨時日誌
    if ls /tmp/vpn_*.log >/dev/null 2>&1; then
        echo -e "${BLUE}清理臨時日誌文件...${NC}"
        rm -f /tmp/vpn_*.log
        echo -e "${GREEN}✓ 臨時日誌已清理${NC}"
    fi
    
    log_message_core "臨時文件清理完成"
    return 0
}

# 驗證 JSON 解析結果
# 參數: $1 = parsed_value, $2 = field_description, $3 = validation_function (可選)
validate_json_parse_result() {
    local parsed_value="$1"
    local field_description="$2"
    local validation_function="$3"
    
    if [ -z "$parsed_value" ] || [ "$parsed_value" = "null" ]; then
        echo -e "${RED}錯誤: 無法解析 $field_description${NC}" >&2
        return 1
    fi
    
    # 如果提供了驗證函式，使用它進行額外驗證
    if [ -n "$validation_function" ] && command -v "$validation_function" >/dev/null 2>&1; then
        if ! "$validation_function" "$parsed_value"; then
            echo -e "${RED}錯誤: $field_description 驗證失敗: $parsed_value${NC}" >&2
            return 1
        fi
    fi
    
    return 0
}

# 等待用戶確認
# 參數: $1 = prompt_message, $2 = default_answer (y/n, 可選)
wait_for_confirmation() {
    local prompt_message="$1"
    local default_answer="$2"
    
    if [ -z "$prompt_message" ]; then
        prompt_message="是否繼續？"
    fi
    
    local prompt_suffix=""
    if [ "$default_answer" = "y" ]; then
        prompt_suffix=" (Y/n)"
    elif [ "$default_answer" = "n" ]; then
        prompt_suffix=" (y/N)"
    else
        prompt_suffix=" (y/n)"
    fi
    
    echo -e "${YELLOW}$prompt_message$prompt_suffix: ${NC}"
    read -r user_input
    
    # 處理預設答案
    if [ -z "$user_input" ] && [ -n "$default_answer" ]; then
        user_input="$default_answer"
    fi
    
    if [[ "$user_input" =~ ^[Yy]$ ]]; then
        return 0
    else
        return 1
    fi
}