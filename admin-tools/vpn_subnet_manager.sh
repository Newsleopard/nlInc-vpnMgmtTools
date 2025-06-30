#!/bin/bash

# VPN 子網路關聯與解除關聯管理腳本
# 用途：專門管理 AWS Client VPN 端點的子網路關聯與解除關聯操作
# 作者：VPN 管理員
# 版本：1.1 (直接 Profile 選擇版本)

# 全域變數
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARENT_DIR="$(dirname "$SCRIPT_DIR")"

# Parse command line arguments
AWS_PROFILE=""
TARGET_ENVIRONMENT=""

# Parse command line arguments for help
for arg in "$@"; do
    if [[ "$arg" == "-h" || "$arg" == "--help" ]]; then
        cat << 'EOF'
用法: $0 [選項]

選項:
  -p, --profile PROFILE     AWS CLI profile
  -e, --environment ENV     目標環境 (staging/production)
  -h, --help               顯示此幫助訊息

功能說明:
  此工具專門管理 AWS Client VPN 端點的子網路關聯與解除關聯操作
EOF
        exit 0
    fi
done

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --profile|-p)
            AWS_PROFILE="$2"
            shift 2
            ;;
        --environment|-e)
            TARGET_ENVIRONMENT="$2"
            shift 2
            ;;
        --help|-h)
            # Already handled above
            shift
            ;;
        -*)
            echo "Unknown option: $1"
            exit 1
            ;;
        *)
            shift
            ;;
    esac
done

# 載入新的 Profile Selector (替代 env_manager.sh)
source "$PARENT_DIR/lib/profile_selector.sh"

# 載入環境核心函式 (用於顯示功能)
source "$PARENT_DIR/lib/env_core.sh"

# Select and validate profile
if ! select_and_validate_profile --profile "$AWS_PROFILE" --environment "$TARGET_ENVIRONMENT"; then
    echo -e "${RED}錯誤: Profile 選擇失敗${NC}"
    exit 1
fi

# 環境感知的配置檔案
CONFIG_FILE="$VPN_CONFIG_DIR/vpn_endpoint.conf"
LOG_FILE="$VPN_ADMIN_LOG_FILE"

# 載入核心函式庫
source "$SCRIPT_DIR/../lib/core_functions.sh"
source "$SCRIPT_DIR/../lib/env_core.sh"
source "$SCRIPT_DIR/../lib/aws_setup.sh"
source "$SCRIPT_DIR/../lib/endpoint_management.sh"

# 顯示腳本標題和基本資訊
show_script_header() {
    clear
    show_team_env_header "VPN 子網路關聯管理工具"
    
    # 顯示 AWS Profile 資訊
    local current_profile="$SELECTED_AWS_PROFILE"
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
    echo -e "  ${YELLOW}E.${NC} 環境資訊 (Profile 資訊)"
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
        --profile "$SELECTED_AWS_PROFILE" \
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
    subnets_json=$(aws ec2 describe-subnets --profile "$SELECTED_AWS_PROFILE" --region "$AWS_REGION" 2>/dev/null)
    
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
                vpc_name=$(aws ec2 describe-vpcs --profile "$SELECTED_AWS_PROFILE" --vpc-ids "$vpc_id" --region "$AWS_REGION" \
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
    
    local has_issues=false
    
    # 檢查 AWS Profile 配置
    echo -e "${BLUE}檢查 AWS Profile 配置...${NC}"
    if [[ -n "$SELECTED_AWS_PROFILE" ]]; then
        if aws configure list-profiles 2>/dev/null | grep -q "^$SELECTED_AWS_PROFILE$"; then
            echo -e "${GREEN}✓ AWS Profile 已配置: $SELECTED_AWS_PROFILE${NC}"
            
            # 檢查 AWS 連接
            if aws sts get-caller-identity --profile "$SELECTED_AWS_PROFILE" &>/dev/null; then
                local account_id=$(aws sts get-caller-identity --profile "$SELECTED_AWS_PROFILE" --query 'Account' --output text 2>/dev/null)
                echo -e "${GREEN}✓ AWS 連接正常 (帳戶: $account_id)${NC}"
            else
                echo -e "${RED}✗ AWS 連接失敗${NC}"
                has_issues=true
            fi
        else
            echo -e "${RED}✗ AWS Profile 未找到: $SELECTED_AWS_PROFILE${NC}"
            has_issues=true
        fi
    else
        echo -e "${RED}✗ 未設置 AWS Profile${NC}"
        has_issues=true
    fi
    
    # 檢查環境配置
    echo -e "\n${BLUE}檢查環境配置...${NC}"
    if [[ -n "$SELECTED_ENVIRONMENT" ]]; then
        echo -e "${GREEN}✓ 當前環境: $SELECTED_ENVIRONMENT${NC}"
        
        # 檢查配置文件
        if [[ -f "$CONFIG_FILE" ]]; then
            echo -e "${GREEN}✓ VPN 端點配置文件存在${NC}"
            
            # 檢查端點 ID
            if [[ -n "$ENDPOINT_ID" ]]; then
                echo -e "${GREEN}✓ 端點 ID 已配置: $ENDPOINT_ID${NC}"
            else
                echo -e "${RED}✗ 端點 ID 未配置${NC}"
                has_issues=true
            fi
            
            # 檢查區域
            if [[ -n "$AWS_REGION" ]]; then
                echo -e "${GREEN}✓ AWS 區域已配置: $AWS_REGION${NC}"
            else
                echo -e "${RED}✗ AWS 區域未配置${NC}"
                has_issues=true
            fi
        else
            echo -e "${RED}✗ VPN 端點配置文件不存在: $CONFIG_FILE${NC}"
            has_issues=true
        fi
    else
        echo -e "${RED}✗ 未設置環境${NC}"
        has_issues=true
    fi
    
    # 檢查必要的工具
    echo -e "\n${BLUE}檢查必要工具...${NC}"
    local tools=("aws" "jq" "openssl")
    for tool in "${tools[@]}"; do
        if command -v "$tool" &>/dev/null; then
            echo -e "${GREEN}✓ $tool 已安裝${NC}"
        else
            echo -e "${RED}✗ $tool 未安裝${NC}"
            has_issues=true
        fi
    done
    
    # 檢查目錄結構
    echo -e "\n${BLUE}檢查目錄結構...${NC}"
    local dirs=("$VPN_CONFIG_DIR" "$VPN_CERT_DIR" "$VPN_LOG_DIR")
    for dir in "${dirs[@]}"; do
        if [[ -d "$dir" ]]; then
            echo -e "${GREEN}✓ 目錄存在: $(basename "$dir")${NC}"
        else
            echo -e "${YELLOW}⚠ 目錄不存在: $dir${NC}"
            # 不算作嚴重問題，因為可能會自動創建
        fi
    done
    
    # 總結
    echo -e "\n${CYAN}=== 健康檢查總結 ===${NC}"
    if [ "$has_issues" = false ]; then
        echo -e "${GREEN}✓ 系統健康檢查完成，一切正常${NC}"
    else
        echo -e "${YELLOW}⚠ 系統健康檢查發現一些問題，請檢查上面的報告${NC}"
    fi
    
    echo -e "\n${YELLOW}按任意鍵返回主選單...${NC}"
    read -n 1
}

# 環境管理 (已棄用)
manage_environment() {
    echo -e "\n${CYAN}=== 環境管理 ===${NC}"
    echo -e "${YELLOW}環境管理功能已更新為直接 Profile 選擇模式${NC}"
    echo -e ""
    echo -e "當前環境資訊:"
    echo -e "  環境: ${GREEN}${SELECTED_ENVIRONMENT}${NC}"
    echo -e "  AWS Profile: ${GREEN}${SELECTED_AWS_PROFILE}${NC}"
    echo -e "  AWS 帳戶: ${GREEN}$(aws sts get-caller-identity --profile "$SELECTED_AWS_PROFILE" --query 'Account' --output text 2>/dev/null)${NC}"
    echo -e "  區域: ${GREEN}${AWS_REGION}${NC}"
    echo -e ""
    echo -e "${BLUE}提示:${NC} 要切換環境，請重新執行腳本並選擇不同的 AWS Profile"
    echo -e ""
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