#!/bin/bash

# lib/endpoint_creation.sh (Refactored)
# VPN 端點創建和管理主要函式庫
# 重構為模組化架構，使用專門的函式庫模組

# 載入核心函式庫和依賴模組
# Check if core_functions.sh exists before sourcing
if [ -f "$(dirname "${BASH_SOURCE[0]}")/core_functions.sh" ]; then
    source "$(dirname "${BASH_SOURCE[0]}")/core_functions.sh"
elif [ -f "./lib/core_functions.sh" ]; then
    source "./lib/core_functions.sh"
fi

# 載入所有端點相關模組
_load_endpoint_modules() {
    # 更強健的腳本目錄解析
    local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    
    # 如果當前在 lib 目錄中，直接使用當前目錄
    if [[ "$script_dir" == */lib ]]; then
        script_dir="$script_dir"
    # 如果當前不在 lib 目錄中，查找 lib 目錄
    elif [ -d "$script_dir/lib" ]; then
        script_dir="$script_dir/lib"
    # 最後，嘗試相對於當前腳本的 lib 目錄
    else
        script_dir="$(dirname "$script_dir")/lib"
    fi
    
    local modules=(
        "endpoint_utils.sh"
        "vpc_operations.sh"
        "security_group_operations.sh"
        "endpoint_config.sh"
        "endpoint_operations.sh"
        "network_association.sh"
    )
    
    local module_path
    for module in "${modules[@]}"; do
        module_path="$script_dir/$module"
        if [ -f "$module_path" ]; then
            source "$module_path"
        else
            echo -e "${YELLOW}警告: 模組檔案不存在: $module_path${NC}" >&2
        fi
    done
}

# 初始化模組載入
_load_endpoint_modules

# cert_management.sh 已經在主腳本中載入，這裡不需要重複載入
# aws_setup.sh 同樣在主腳本中載入

# ============================================================================
# 主要公開函式 - 保持原有接口不變
# ============================================================================

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
        load_current_env
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
        vpc_cidr="10.0.0.0/16"
    fi
    
    # VPN 設定 - 使用環境變數或互動式輸入
    local vpn_cidr vpn_name
    if [ -n "$VPN_CIDR" ] && [ -n "$VPN_NAME" ]; then
        vpn_cidr="$VPN_CIDR"
        vpn_name="$VPN_NAME"
        echo -e "${GREEN}✓ 使用環境配置中的 VPN 設定${NC}" >&2
        echo -e "${GREEN}  VPN CIDR: $vpn_cidr${NC}" >&2
        echo -e "${GREEN}  VPN 名稱: $vpn_name${NC}" >&2
    else
        echo -e "\\n${BLUE}設定 VPN 配置...${NC}" >&2
        
        while true; do
            echo -n "請輸入 VPN 客戶端 IP 範圍 (CIDR 格式，例如: 172.16.0.0/22): " >&2
            read vpn_cidr
            if [[ "$vpn_cidr" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}/[0-9]{1,2}$ ]]; then
                break
            else
                echo -e "${RED}無效的 CIDR 格式。請使用類似 '172.16.0.0/22' 的格式。${NC}" >&2
            fi
        done
        
        echo -n "請輸入 VPN 端點名稱 (例如: My-VPN): " >&2
        read vpn_name
        if [ -z "$vpn_name" ]; then
            vpn_name="ClientVPN-$(date +%Y%m%d)"
            echo -e "${YELLOW}使用預設名稱: $vpn_name${NC}" >&2
        fi
    fi
    
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
        result_json='{"vpc_id":"'$vpc_id'","subnet_id":"'$subnet_id'","vpc_cidr":"'$vpc_cidr'","vpn_cidr":"'$vpn_cidr'","vpn_name":"'$vpn_name'","security_groups":"'$security_groups'"}'
    fi
    
    log_message_core "VPC/子網路/VPN 詳細資訊獲取完成 (lib): $result_json"
    echo "$result_json"
    return 0
}

# Note: _prompt_network_details_ec is loaded from vpc_operations.sh module

# Note: debug_aws_cli_params is loaded from endpoint_config.sh module

# Note: save_initial_endpoint_config is loaded from endpoint_config.sh module

# Note: create_dedicated_client_vpn_security_group is loaded from security_group_operations.sh module

# Note: prompt_update_existing_security_groups is loaded from security_group_operations.sh module

# Note: generate_security_group_commands_file is loaded from security_group_operations.sh module

# Note: _create_aws_client_vpn_endpoint_ec is loaded from endpoint_operations.sh module

# Note: _associate_target_network_ec is loaded from network_association.sh module

# Note: _setup_authorization_and_routes_ec is loaded from network_association.sh module

# Note: _wait_for_client_vpn_endpoint_available is loaded from endpoint_operations.sh module

# ============================================================================
# 主要工作流程函式
# ============================================================================

# 創建完整的 VPN 端點 (庫函式版本)
# 參數: $1 = main_config_file, $2 = aws_region, $3 = vpc_id, $4 = subnet_id, $5 = vpn_cidr, $6 = vpn_name, $7 = server_cert_arn, $8 = client_cert_arn, $9 = security_groups (可選)
create_vpn_endpoint_lib() {
    local main_config_file="$1"
    local aws_region="$2"
    local vpc_id="$3"
    local subnet_id="$4"
    local vpn_cidr="$5"
    local vpn_name="$6"
    local arg_server_cert_arn="$7"  # 避免與配置檔案中的變數衝突
    local arg_client_cert_arn="$8"  # 避免與配置檔案中的變數衝突
    local security_groups="$9"

    # 參數驗證
    if [ -z "$main_config_file" ] || [ -z "$aws_region" ] || [ -z "$vpc_id" ] || [ -z "$vpn_cidr" ] || [ -z "$vpn_name" ] || [ -z "$arg_server_cert_arn" ] || [ -z "$arg_client_cert_arn" ]; then
        echo -e "${RED}錯誤: create_vpn_endpoint_lib 缺少必要參數${NC}" >&2
        log_message_core "錯誤: create_vpn_endpoint_lib 缺少必要參數"
        return 1
    fi

    log_message_core "開始創建 VPN 端點 (lib): CIDR=$vpn_cidr, 名稱=$vpn_name, 區域=$aws_region"

    echo -e "${CYAN}=== 開始創建 VPN 端點 ===${NC}"
    echo -e "${YELLOW}VPN 名稱: $vpn_name${NC}"
    echo -e "${YELLOW}VPN CIDR: $vpn_cidr${NC}"
    echo -e "${YELLOW}VPC ID: $vpc_id${NC}"
    echo -e "${YELLOW}子網路 ID: $subnet_id${NC}"
    echo -e "${YELLOW}AWS 區域: $aws_region${NC}"

    # 獲取 VPC CIDR
    local vpc_cidr
    vpc_cidr=$(get_vpc_cidr "$vpc_id" "$aws_region")
    if [ $? -ne 0 ] || [ -z "$vpc_cidr" ]; then
        echo -e "${RED}錯誤: 無法獲取 VPC CIDR${NC}"
        return 1
    fi
    echo -e "${GREEN}✓ VPC CIDR: $vpc_cidr${NC}"

    # 預檢查 AWS CLI 參數
    echo -e "\n${CYAN}=== 預檢查參數 ===${NC}"
    if ! debug_aws_cli_params "$vpn_cidr" "$arg_server_cert_arn" "$arg_client_cert_arn" "$vpn_name" "$vpc_id" "$subnet_id" "$aws_region"; then
        echo -e "${YELLOW}⚠️ 參數預檢查發現問題，但將繼續執行${NC}"
        log_message_core "警告: 參數預檢查發現問題"
    fi

    # 創建專用的 Client VPN 安全群組
    echo -e "\n${CYAN}=== 步驟：創建專用安全群組 ===${NC}"
    local client_vpn_sg_id
    client_vpn_sg_id=$(create_dedicated_client_vpn_security_group "$vpc_id" "$aws_region" "${CURRENT_ENVIRONMENT:-staging}")
    
    if [ $? -ne 0 ] || [ -z "$client_vpn_sg_id" ]; then
        echo -e "${RED}錯誤: 無法創建專用的 Client VPN 安全群組${NC}"
        return 1
    fi
    echo -e "${GREEN}✓ 專用安全群組已創建: $client_vpn_sg_id${NC}"

    # 步驟 1: 創建 VPN 端點
    echo -e "\n${CYAN}=== 步驟：創建 VPN 端點 ===${NC}"
    
    # 調試：檢查關鍵函數是否可用
    if ! command -v _create_aws_client_vpn_endpoint_ec >/dev/null 2>&1; then
        echo -e "${RED}錯誤: _create_aws_client_vpn_endpoint_ec 函數不可用，模組載入失敗${NC}"
        log_message_core "錯誤: _create_aws_client_vpn_endpoint_ec 函數不可用，模組載入失敗"
        return 1
    fi
    
    local endpoint_id
    local endpoint_creation_output
    
    # 捕獲函數返回值 (只捕獲 stdout，讓 stderr 正常顯示)
    if endpoint_id=$(_create_aws_client_vpn_endpoint_ec "$vpn_cidr" "$arg_server_cert_arn" "$arg_client_cert_arn" "$vpn_name" "$aws_region"); then
        # 清理可能包含的多餘輸出，只保留端點 ID
        endpoint_id=$(echo "$endpoint_id" | grep -o 'cvpn-endpoint-[0-9a-f]\{17\}' | head -1)
        
        if [ -n "$endpoint_id" ] && [[ "$endpoint_id" =~ ^cvpn-endpoint-[0-9a-f]{17}$ ]]; then
            echo -e "${GREEN}✓ VPN 端點創建成功: $endpoint_id${NC}"
            log_message_core "Client VPN 端點創建成功: $endpoint_id"
        else
            echo -e "${RED}錯誤: VPN 端點創建返回了無效的端點 ID: $endpoint_id${NC}"
            log_message_core "錯誤: VPN 端點創建返回了無效的端點 ID: $endpoint_id"
            return 1
        fi
    else
        echo -e "${RED}錯誤: VPN 端點創建失敗${NC}"
        log_message_core "錯誤: VPN 端點創建失敗"
        return 1
    fi

    # 立即保存基本配置 (防止後續步驟失敗導致信息丟失)
    local endpoint_config_file="${main_config_file%/*}/vpn_endpoint.conf"
    echo -e "${BLUE}立即保存端點基本配置到 \"$endpoint_config_file\"...${NC}"
    
    if save_initial_endpoint_config "$endpoint_config_file" "$endpoint_id" "$client_vpn_sg_id" "$arg_server_cert_arn" "$arg_client_cert_arn" "$vpc_id" "$subnet_id" "$vpn_cidr" "$vpn_name" "$vpc_cidr"; then
        echo -e "${GREEN}✓ 端點基本配置已保存${NC}"
        log_message_core "端點基本配置保存成功: $endpoint_config_file"
    else
        echo -e "${YELLOW}⚠️ 端點基本配置保存失敗，但繼續執行${NC}"
        log_message_core "警告: 端點基本配置保存失敗，但繼續執行"
    fi

    # 關聯子網路 (如果提供了子網路 ID) - 必須在等待可用之前完成
    if [ -n "$subnet_id" ]; then
        echo -e "\n${CYAN}=== 步驟：關聯子網路到 VPN 端點 ===${NC}"
        log_message_core "開始執行關聯子網路步驟: 端點=$endpoint_id, 子網路=$subnet_id"
        
        if ! _associate_target_network_ec "$endpoint_id" "$subnet_id" "$aws_region" "$client_vpn_sg_id"; then
            echo -e "${RED}錯誤: 關聯子網路失敗${NC}"
            log_message_core "錯誤: 關聯子網路失敗"
            return 1
        fi
        echo -e "${GREEN}✓ 子網路關聯成功${NC}"
        log_message_core "子網路關聯成功"
    else
        echo -e "${YELLOW}⚠️ 未提供子網路 ID，跳過子網路關聯步驟${NC}"
        log_message_core "警告: 未提供子網路 ID，跳過子網路關聯步驟"
    fi

    # 檢查端點狀態並決定是否等待
    echo -e "\n${CYAN}=== 步驟：檢查端點狀態 ===${NC}"
    local current_status
    current_status=$(aws ec2 describe-client-vpn-endpoints \
        --client-vpn-endpoint-ids "$endpoint_id" \
        --region "$aws_region" \
        --query 'ClientVpnEndpoints[0].Status.Code' \
        --output text 2>/dev/null)
    
    echo -e "${YELLOW}當前端點狀態: $current_status${NC}"
    
    if [ "$current_status" = "available" ]; then
        echo -e "${GREEN}✓ 端點已可用，繼續配置${NC}"
    elif [ "$current_status" = "pending-associate" ]; then
        echo -e "${YELLOW}⚠️ 端點仍在關聯中，但可以繼續配置授權規則${NC}"
        echo -e "${BLUE}註: 端點將在後台完成可用狀態轉換${NC}"
    else
        echo -e "${YELLOW}⚠️ 端點狀態: $current_status，嘗試繼續配置${NC}"
    fi

    # 設定授權規則和路由（不等待端點完全可用）
    echo -e "\n${CYAN}=== 步驟：設定授權規則和路由 ===${NC}"
    log_message_core "開始執行授權和路由設定步驟"
    
    if ! _setup_authorization_and_routes_ec "$endpoint_id" "$vpc_cidr" "$subnet_id" "$aws_region"; then
        echo -e "${RED}錯誤: 設定授權規則和路由失敗${NC}"
        log_message_core "錯誤: 設定授權規則和路由失敗"
        return 1
    fi
    echo -e "${GREEN}✓ 授權規則和路由設定成功${NC}"
    log_message_core "授權規則和路由設定成功"

    # 提示配置現有服務的安全群組
    echo -e "\n${CYAN}=== 步驟：配置服務訪問權限 ===${NC}"
    log_message_core "開始執行安全群組配置提示"
    
    if ! prompt_update_existing_security_groups "$client_vpn_sg_id" "$aws_region" "${CURRENT_ENVIRONMENT:-staging}"; then
        echo -e "${YELLOW}⚠️ 安全群組配置提示失敗，但這不影響 VPN 功能${NC}"
        log_message_core "警告: 安全群組配置提示失敗"
    fi

    # 更新最終配置文件
    echo -e "\n${CYAN}=== 步驟：更新最終配置 ===${NC}"
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

    # 最終狀態檢查（純資訊用途）
    echo -e "\n${CYAN}=== 最終狀態檢查 ===${NC}"
    local final_status
    final_status=$(aws ec2 describe-client-vpn-endpoints \
        --client-vpn-endpoint-ids "$endpoint_id" \
        --region "$aws_region" \
        --query 'ClientVpnEndpoints[0].Status.Code' \
        --output text 2>/dev/null)
    
    case "$final_status" in
        "available")
            echo -e "${GREEN}✓ 端點已完全可用並可接受客戶端連接${NC}"
            ;;
        "pending-associate")
            echo -e "${YELLOW}ℹ️ 端點仍在完成關聯過程，將在幾分鐘內變為可用${NC}"
            ;;
        *)
            echo -e "${YELLOW}ℹ️ 端點狀態: $final_status${NC}"
            ;;
    esac

    # 提供安全群組配置腳本說明
    echo -e "\n${CYAN}=== 📋 重要：安全群組配置 ===${NC}"
    local sg_commands_file="security_group_commands_${CURRENT_ENVIRONMENT:-staging}.sh"
    
    if [ -f "$sg_commands_file" ]; then
        echo -e "${GREEN}✓ 已自動生成安全群組配置腳本：${YELLOW}$sg_commands_file${NC}"
        echo -e "${BLUE}📝 此腳本包含 AWS CLI 命令，用於配置現有服務訪問權限${NC}"
        echo
        echo -e "${YELLOW}🔧 使用說明：${NC}"
        echo -e "  1️⃣ ${CYAN}編輯腳本${NC}：將 ${YELLOW}sg-TARGET_*_SG_ID${NC} 替換為您實際的安全群組 ID"
        echo -e "  2️⃣ ${CYAN}啟用服務${NC}：註釋掉不需要的服務，保留需要的服務"
        echo -e "  3️⃣ ${CYAN}執行腳本${NC}：${GREEN}bash $sg_commands_file${NC}"
        echo
        echo -e "${BLUE}💡 腳本功能：${NC}"
        echo -e "  • 🔐 使用安全群組引用（AWS 最佳實務）"
        echo -e "  • 🎯 預配置常見服務端口（MySQL、PostgreSQL、Redis、HTTP/HTTPS 等）"
        echo -e "  • 🛡️ 集中化 VPN 用戶權限管理"
        echo
        echo -e "${YELLOW}⚠️ 注意：${NC}不執行此腳本，VPN 用戶將無法訪問您的內部服務"
        echo -e "${GREEN}✅ VPN 端點本身已完成設定，可立即用於基本網路連接${NC}"
    else
        echo -e "${YELLOW}⚠️ 未找到安全群組配置腳本，您需要手動配置服務訪問權限${NC}"
        echo -e "${BLUE}💡 手動配置範例：${NC}"
        echo -e "  ${CYAN}aws ec2 authorize-security-group-ingress \\\\${NC}"
        echo -e "  ${CYAN}    --group-id sg-YOUR_SERVICE_SG_ID \\\\${NC}"
        echo -e "  ${CYAN}    --source-group $client_vpn_sg_id \\\\${NC}"
        echo -e "  ${CYAN}    --protocol tcp --port 80 --region $aws_region${NC}"
    fi

    log_message_core "VPN 端點已建立 (lib): $endpoint_id, 狀態: $final_status"
    echo -e "\n${GREEN}🎉 VPN 端點建立完成！${NC}"
    echo -e "📍 端點 ID: ${BLUE}$endpoint_id${NC}"
    echo -e "🔐 VPN 安全群組: ${BLUE}$client_vpn_sg_id${NC}"
    echo -e "${BLUE}註: 如果端點還未完全可用，請等待幾分鐘讓 AWS 完成後台配置${NC}"

    # 輸出結果標記供 admin 腳本提取
    echo "ENDPOINT_ID_RESULT=$endpoint_id"

    return 0
}

# 關聯一個 VPC 到端點 (用於多 VPC 場景)
_associate_one_vpc_to_endpoint_lib() {
    # 直接調用網路關聯模組中的函式
    if command -v _associate_one_vpc_to_endpoint_lib >/dev/null 2>&1; then
        _associate_one_vpc_to_endpoint_lib "$@"
    else
        echo -e "${RED}錯誤: 網路關聯模組未正確載入${NC}" >&2
        return 1
    fi
}

# Note: terminate_vpn_endpoint_lib function is implemented in endpoint_operations.sh module

# ============================================================================
# 模組檢查和診斷函式
# ============================================================================

# 檢查所有模組是否正確載入
check_module_status() {
    echo -e "${CYAN}=== 檢查模組載入狀態 ===${NC}"
    
    # 使用 endpoint_utils.sh 中的函式
    if command -v check_module_availability >/dev/null 2>&1; then
        check_module_availability
    else
        echo -e "${RED}錯誤: 無法檢查模組狀態，工具模組未正確載入${NC}"
        return 1
    fi
}

# Note: validate_endpoint_operation function is implemented in endpoint_utils.sh module

# ============================================================================
# 向後兼容性函式 (保持原有接口)
# ============================================================================

# 這些函式保持原有的名稱和接口，以確保現有腳本不會出錯
# 如果需要，可以在這裡添加其他向後兼容性函式

log_message_core "endpoint_creation.sh (重構版本) 載入完成"