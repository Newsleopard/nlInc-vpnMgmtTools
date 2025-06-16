#!/bin/bash

# VPN 子網路關聯與解除關聯管理腳本
# 用途：專門管理 AWS Client VPN 端點的子網路關聯與解除關聯操作
# 作者：VPN 管理員
# 版本：1.0

# 全域變數
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 載入環境管理器 (必須第一個載入)
source "$SCRIPT_DIR/../lib/env_manager.sh"

# 初始化環境
if ! env_init_for_script "vpn_subnet_manager.sh"; then
    echo -e "${RED}錯誤: 無法初始化環境管理器${NC}"
    exit 1
fi

# 驗證 AWS Profile 整合
echo -e "${BLUE}正在驗證 AWS Profile 設定...${NC}"
if ! env_validate_profile_integration "$CURRENT_ENVIRONMENT" "true"; then
    echo -e "${YELLOW}警告: AWS Profile 設定可能有問題，但繼續執行管理員工具${NC}"
fi

# 設定環境特定路徑
env_setup_paths

# 環境感知的配置檔案
CONFIG_FILE="$VPN_ENDPOINT_CONFIG_FILE"
LOG_FILE="$VPN_ADMIN_LOG_FILE"

# 載入核心函式庫
source "$SCRIPT_DIR/../lib/core_functions.sh"
source "$SCRIPT_DIR/../lib/aws_setup.sh"
source "$SCRIPT_DIR/../lib/endpoint_management.sh"

# 顯示腳本標題和基本資訊
show_script_header() {
    clear
    show_env_aware_header "VPN 子網路關聯管理工具"
    
    # 顯示 AWS Profile 資訊
    local current_profile
    current_profile=$(env_get_profile "$CURRENT_ENVIRONMENT" 2>/dev/null)
    if [[ -n "$current_profile" ]]; then
        # 獲取 AWS 帳戶資訊
        if command -v aws &> /dev/null && aws configure list-profiles | grep -q "^$current_profile$"; then
            local account_id region_info
            account_id=$(aws sts get-caller-identity --profile "$current_profile" --query 'Account' --output text 2>/dev/null || echo "未知")
            region_info=$(aws configure get region --profile "$current_profile" 2>/dev/null || echo "未設定")
            
            echo -e "${CYAN}AWS 配置狀態:${NC}"
            echo -e "  Profile: ${YELLOW}$current_profile${NC}"
            echo -e "  帳戶 ID: ${YELLOW}$account_id${NC}"  
            echo -e "  區域: ${YELLOW}$region_info${NC}"
        else
            echo -e "${CYAN}AWS 配置狀態:${NC}"
            echo -e "  Profile: ${YELLOW}$current_profile${NC} ${RED}(未配置)${NC}"
        fi
    else
        echo -e "${CYAN}AWS 配置狀態:${NC}"
        echo -e "  Profile: ${YELLOW}未設定${NC}"
    fi
    echo -e ""
}

# 顯示主選單
show_main_menu() {
    show_script_header
    
    echo -e "${BLUE}選擇操作：${NC}"
    echo -e "  ${GREEN}1.${NC} 查看 VPN 端點及其關聯的子網路"
    echo -e "  ${GREEN}2.${NC} 關聯子網路到 VPN 端點"
    echo -e "  ${GREEN}3.${NC} 解除 VPN 端點的子網路/VPC 關聯"
    echo -e "  ${GREEN}4.${NC} 查看可用的子網路列表"
    echo -e "  ${GREEN}5.${NC} 系統健康檢查"
    echo -e "  ${YELLOW}E.${NC} 環境管理"
    echo -e "  ${RED}Q.${NC} 退出"
    echo -e ""
}

# 查看 VPN 端點及其關聯的子網路
view_endpoints_and_associations() {
    echo -e "\n${CYAN}=== 查看 VPN 端點及其關聯的子網路 ===${NC}"
    
    # 驗證基本配置
    if ! validate_main_config "$CONFIG_FILE"; then
        echo -e "\n${YELLOW}按任意鍵返回主選單...${NC}"
        read -n 1
        return 1
    fi
    
    echo -e "${BLUE}當前配置的端點 ID: $ENDPOINT_ID${NC}"
    echo -e "${BLUE}當前 AWS 區域: $AWS_REGION${NC}"
    echo ""
    
    # 檢查端點是否存在
    local endpoint_status
    endpoint_status=$(aws ec2 describe-client-vpn-endpoints \
        --client-vpn-endpoint-ids "$ENDPOINT_ID" \
        --region "$AWS_REGION" \
        --query 'ClientVpnEndpoints[0].Status.Code' \
        --output text 2>/dev/null)
    
    if [ $? -ne 0 ] || [ "$endpoint_status" = "None" ] || [ -z "$endpoint_status" ]; then
        echo -e "${RED}錯誤: 端點 $ENDPOINT_ID 不存在或無法訪問${NC}"
        echo -e "\n${YELLOW}按任意鍵返回主選單...${NC}"
        read -n 1
        return 1
    fi
    
    echo -e "${GREEN}端點狀態: $endpoint_status${NC}"
    echo ""
    
    # 顯示關聯的網絡
    echo -e "${CYAN}關聯的網絡:${NC}"
    view_associated_networks_lib "$AWS_REGION" "$ENDPOINT_ID"
    
    echo -e "\n${YELLOW}按任意鍵返回主選單...${NC}"
    read -n 1
}

# 關聯子網路到 VPN 端點
associate_subnet() {
    echo -e "\n${CYAN}=== 關聯子網路到 VPN 端點 ===${NC}"
    
    # 使用統一的端點操作驗證
    if ! validate_endpoint_operation "$CONFIG_FILE"; then
        echo -e "\n${YELLOW}按任意鍵返回主選單...${NC}"
        read -n 1
        return 1
    fi
    
    echo -e "${BLUE}當前端點 ID: $ENDPOINT_ID${NC}"
    echo -e "${BLUE}當前 AWS 區域: $AWS_REGION${NC}"
    echo ""
    
    # 調用庫函式進行關聯
    associate_subnet_to_endpoint_lib "$AWS_REGION" "$ENDPOINT_ID"
    local result=$?
    
    log_operation_result "子網路關聯" "$result" "vpn_subnet_manager.sh"
    
    if [ "$result" -eq 0 ]; then
        echo -e "${GREEN}子網路關聯操作成功完成。${NC}"
    else
        echo -e "${RED}子網路關聯過程中發生錯誤。請檢查上面的日誌。${NC}"
    fi
    
    echo -e "\n${YELLOW}按任意鍵返回主選單...${NC}"
    read -n 1
}

# 解除 VPN 端點的子網路/VPC 關聯
disassociate_subnet() {
    echo -e "\n${CYAN}=== 解除 VPN 端點的子網路/VPC 關聯 ===${NC}"
    
    # 使用統一的端點操作驗證
    if ! validate_endpoint_operation "$CONFIG_FILE"; then
        echo -e "\n${YELLOW}按任意鍵返回主選單...${NC}"
        read -n 1
        return 1
    fi
    
    echo -e "${BLUE}當前端點 ID: $ENDPOINT_ID${NC}"
    echo -e "${BLUE}當前 AWS 區域: $AWS_REGION${NC}"
    echo ""
    
    # 調用庫函式來處理 VPC 的解除關聯
    disassociate_vpc_lib "$CONFIG_FILE" "$AWS_REGION" "$ENDPOINT_ID"
    local result=$?
    
    log_operation_result "VPC 解除關聯" "$result" "vpn_subnet_manager.sh"
    
    if [ "$result" -eq 0 ]; then
        echo -e "${GREEN}VPC 解除關聯操作成功完成。${NC}"
        # 重新載入配置以確保任何更改都已反映
        if ! load_config_core "$CONFIG_FILE"; then
             echo -e "${RED}錯誤：無法重新載入更新的配置文件${NC}"
        fi
    else
        echo -e "${RED}VPC 解除關聯過程中發生錯誤。請檢查上面的日誌。${NC}"
    fi
    
    echo -e "\n${YELLOW}按任意鍵返回主選單...${NC}"
    read -n 1
}

# 查看可用的子網路列表
view_available_subnets() {
    echo -e "\n${CYAN}=== 查看可用的子網路列表 ===${NC}"
    
    # 驗證基本配置
    if ! validate_main_config "$CONFIG_FILE"; then
        echo -e "\n${YELLOW}按任意鍵返回主選單...${NC}"
        read -n 1
        return 1
    fi
    
    echo -e "${BLUE}當前 AWS 區域: $AWS_REGION${NC}"
    echo ""
    
    # 獲取可用的子網路
    echo -e "${BLUE}正在獲取可用的子網路...${NC}"
    local subnets_json
    subnets_json=$(aws ec2 describe-subnets --region "$AWS_REGION" 2>/dev/null)
    
    if [ $? -ne 0 ] || [ -z "$subnets_json" ]; then
        echo -e "${RED}錯誤: 無法獲取子網路列表。請檢查 AWS 憑證和區域設定。${NC}"
        echo -e "\n${YELLOW}按任意鍵返回主選單...${NC}"
        read -n 1
        return 1
    fi
    
    # 解析並顯示可用子網路
    if command -v jq >/dev/null 2>&1; then
        local subnet_count
        subnet_count=$(echo "$subnets_json" | jq '.Subnets | length' 2>/dev/null)
        
        if [ -n "$subnet_count" ] && [ "$subnet_count" -gt 0 ]; then
            echo -e "${BLUE}找到 $subnet_count 個可用子網路:${NC}"
            echo ""
            
            # 按 VPC 分組顯示子網路
            local vpcs
            vpcs=$(echo "$subnets_json" | jq -r '.Subnets[].VpcId' | sort -u)
            
            for vpc_id in $vpcs; do
                local vpc_name
                vpc_name=$(aws ec2 describe-vpcs --vpc-ids "$vpc_id" --region "$AWS_REGION" \
                    --query "Vpcs[0].Tags[?Key=='Name'].Value" --output text 2>/dev/null || echo "未命名")
                
                echo -e "${YELLOW}VPC: $vpc_id${NC} ${CYAN}($vpc_name)${NC}"
                
                echo "$subnets_json" | jq -r --arg vpc "$vpc_id" '
                    .Subnets[] | 
                    select(.VpcId == $vpc) | 
                    "  子網路 ID: \(.SubnetId)
    CIDR: \(.CidrBlock)
    可用區: \(.AvailabilityZone)
    名稱: \(.Tags[]? | select(.Key=="Name") | .Value // "未命名")
    狀態: \(.State)
"'
                echo ""
            done
        else
            echo -e "${YELLOW}未找到可用的子網路${NC}"
        fi
    else
        echo -e "${YELLOW}警告: 未安裝 jq，將使用基本顯示方式${NC}"
        echo "$subnets_json" | grep -E '"SubnetId"|"VpcId"|"CidrBlock"|"AvailabilityZone"'
    fi
    
    echo -e "\n${YELLOW}按任意鍵返回主選單...${NC}"
    read -n 1
}

# 執行系統健康檢查
perform_health_check() {
    echo -e "\n${CYAN}=== 系統健康檢查 ===${NC}"
    
    # 調用核心函式的健康檢查
    system_health_check_core "$CURRENT_ENVIRONMENT"
    local result=$?
    
    if [ "$result" -eq 0 ]; then
        echo -e "${GREEN}✓ 系統健康檢查完成${NC}"
    else
        echo -e "${YELLOW}⚠ 系統健康檢查發現一些問題，請檢查上面的報告${NC}"
    fi
    
    echo -e "\n${YELLOW}按任意鍵返回主選單...${NC}"
    read -n 1
}

# 環境管理
manage_environment() {
    echo -e "\n${CYAN}=== 環境管理 ===${NC}"
    "$SCRIPT_DIR/../vpn_env.sh"
    echo -e "\n${YELLOW}按任意鍵返回主選單...${NC}"
    read -n 1
}

# 顯示幫助信息
show_help() {
    cat << 'EOF'
VPN 子網路關聯管理工具 - 幫助信息

用途：
    專門管理 AWS Client VPN 端點的子網路關聯與解除關聯操作

主要功能：
    1. 查看 VPN 端點及其關聯的子網路
    2. 關聯子網路到 VPN 端點
    3. 解除 VPN 端點的子網路/VPC 關聯
    4. 查看可用的子網路列表
    5. 系統健康檢查

使用說明：
    1. 確保已正確配置 AWS Profile 和環境
    2. 確保 VPN 端點配置文件存在且有效
    3. 選擇對應的操作選項
    4. 按照提示完成操作

注意事項：
    - 解除關聯操作會影響用戶的 VPN 連接
    - Production 環境操作需要額外確認
    - 所有操作都會記錄到日誌文件中

EOF
}

# 錯誤處理函數
handle_script_error() {
    local error_msg="$1"
    echo -e "${RED}錯誤: $error_msg${NC}"
    log_message_core "vpn_subnet_manager.sh 錯誤: $error_msg"
    echo -e "\n${YELLOW}按任意鍵返回主選單...${NC}"
    read -n 1
}

# 主函數
main() {
    # 檢查參數
    if [ "$1" = "--help" ] || [ "$1" = "-h" ]; then
        show_help
        exit 0
    fi
    
    # 初始日誌記錄
    log_message_core "VPN 子網路管理工具啟動 - 環境: $CURRENT_ENVIRONMENT"
    
    # 主循環
    while true; do
        show_main_menu
        read -p "請選擇操作 (1-5, E, Q): " choice
        
        case "$choice" in
            1)
                view_endpoints_and_associations
                ;;
            2)
                associate_subnet
                ;;
            3)
                disassociate_subnet
                ;;
            4)
                view_available_subnets
                ;;
            5)
                perform_health_check
                ;;
            E|e)
                manage_environment
                ;;
            Q|q)
                echo -e "${BLUE}正在退出...${NC}"
                log_message_core "VPN 子網路管理工具正常退出"
                exit 0
                ;;
            *)
                echo -e "${RED}無效選擇，請輸入 1-5, E 或 Q${NC}"
                sleep 2
                ;;
        esac
    done
}

# 不使用 set -e，改用手動錯誤處理以避免程式意外退出

# 啟動主函數
main "$@"