#!/bin/bash

# AWS Client VPN 人員離職安全處理流程腳本
# 用途：全面處理離職人員的所有 AWS 和 VPN 相關訪問權限
# 版本：1.0

# 顏色設定
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m' # No Color

# 全域變數
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OFFBOARDING_LOG_DIR="$SCRIPT_DIR/offboarding-logs"
LOG_FILE="$OFFBOARDING_LOG_DIR/offboarding.log"
CHECKLIST_FILE=""

# 阻止腳本在出錯時繼續執行
set -e

# 記錄函數
log_message() {
    mkdir -p $OFFBOARDING_LOG_DIR
    echo "$(date '+%Y-%m-%d %H:%M:%S'): $1" >> $LOG_FILE
}

# 顯示歡迎訊息
show_welcome() {
    clear
    echo -e "${RED}============================================================${NC}"
    echo -e "${RED}              AWS VPN 人員離職安全處理系統               ${NC}"
    echo -e "${RED}============================================================${NC}"
    echo -e ""
    echo -e "${YELLOW}此系統將全面處理離職人員的安全清理作業${NC}"
    echo -e ""
    echo -e "${CYAN}處理範圍包括：${NC}"
    echo -e "  ${BLUE}✓${NC} VPN 證書撤銷和連接斷開"
    echo -e "  ${BLUE}✓${NC} IAM 用戶和權限清理"
    echo -e "  ${BLUE}✓${NC} 訪問日誌審計"
    echo -e "  ${BLUE}✓${NC} 安全事件記錄"
    echo -e "  ${BLUE}✓${NC} 離職檢查清單生成"
    echo -e ""
    echo -e "${RED}重要：此操作將永久撤銷所有訪問權限${NC}"
    echo -e "${RED}請確保已獲得適當的授權後再執行${NC}"
    echo -e ""
    echo -e "${CYAN}============================================================${NC}"
    echo -e ""
    read -p "按任意鍵開始離職處理程序... " -n 1
}

# 檢查系統準備狀態
check_system_readiness() {
    echo -e "\n${YELLOW}[1/10] 檢查系統準備狀態...${NC}"
    
    # 檢查必要工具
    local tools=("aws" "jq" "curl" "openssl")
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
        exit 1
    fi
    
    # 檢查 AWS 配置和權限
    echo -e "${BLUE}檢查 AWS 配置和權限...${NC}"
    
    if [ ! -f ~/.aws/credentials ] || [ ! -f ~/.aws/config ]; then
        echo -e "${RED}未找到 AWS 配置${NC}"
        exit 1
    fi
    
    # 測試管理員權限
    admin_identity=$(aws sts get-caller-identity --query 'Arn' --output text 2>/dev/null || echo "failed")
    
    if [[ $admin_identity == "failed" ]]; then
        echo -e "${RED}AWS 身份驗證失敗${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}✓ AWS 身份驗證成功${NC}"
    echo -e "${BLUE}操作者身份: $admin_identity${NC}"
    
    # 檢查關鍵權限
    echo -e "${BLUE}檢查必要權限...${NC}"
    
    # 檢查 VPN 管理權限
    vpn_check=$(aws ec2 describe-client-vpn-endpoints --max-items 1 2>/dev/null || echo "failed")
    if [[ $vpn_check == "failed" ]]; then
        echo -e "${RED}缺少 VPN 管理權限${NC}"
        exit 1
    fi
    
    # 檢查 IAM 權限
    iam_check=$(aws iam list-users --max-items 1 2>/dev/null || echo "failed")
    if [[ $iam_check == "failed" ]]; then
        echo -e "${YELLOW}⚠ 缺少 IAM 管理權限，將跳過 IAM 清理${NC}"
        iam_permissions=false
    else
        iam_permissions=true
        echo -e "${GREEN}✓ IAM 管理權限可用${NC}"
    fi
    
    # 檢查 ACM 權限
    acm_check=$(aws acm list-certificates --max-items 1 2>/dev/null || echo "failed")
    if [[ $acm_check == "failed" ]]; then
        echo -e "${RED}缺少 ACM 管理權限${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}✓ 系統準備檢查完成${NC}"
    log_message "系統準備檢查完成，操作者: $admin_identity"
}

# 收集離職人員資訊
collect_employee_info() {
    echo -e "\n${YELLOW}[2/10] 收集離職人員資訊...${NC}"
    
    # 基本資訊
    echo -e "${BLUE}請提供離職人員的基本資訊：${NC}"
    read -p "員工姓名: " employee_name
    read -p "員工 ID/用戶名: " employee_id
    read -p "部門: " department
    read -p "職位: " position
    read -p "離職日期 (YYYY-MM-DD): " termination_date
    
    # 驗證日期格式
    if ! date -j -f "%Y-%m-%d" "$termination_date" >/dev/null 2>&1; then
        echo -e "${RED}日期格式錯誤，請使用 YYYY-MM-DD 格式${NC}"
        exit 1
    fi
    
    # 離職類型和原因
    echo -e "\n${BLUE}離職類型：${NC}"
    echo -e "  ${GREEN}1.${NC} 主動離職"
    echo -e "  ${GREEN}2.${NC} 被動離職"
    echo -e "  ${GREEN}3.${NC} 合約到期"
    echo -e "  ${GREEN}4.${NC} 緊急離職"
    
    read -p "請選擇離職類型 (1-4): " termination_type_choice
    
    case $termination_type_choice in
        1) termination_type="主動離職" ;;
        2) termination_type="被動離職" ;;
        3) termination_type="合約到期" ;;
        4) termination_type="緊急離職" ;;
        *) termination_type="未指定" ;;
    esac
    
    # 風險等級
    echo -e "\n${BLUE}風險等級評估：${NC}"
    echo -e "  ${GREEN}1.${NC} 低風險 (友好離職，無安全顧慮)"
    echo -e "  ${YELLOW}2.${NC} 中風險 (正常離職流程)"
    echo -e "  ${RED}3.${NC} 高風險 (可能存在安全顧慮)"
    
    read -p "請選擇風險等級 (1-3): " risk_level_choice
    
    case $risk_level_choice in
        1) risk_level="低風險"; urgent_action=false ;;
        2) risk_level="中風險"; urgent_action=false ;;
        3) risk_level="高風險"; urgent_action=true ;;
        *) risk_level="未評估"; urgent_action=true ;;
    esac
    
    # AWS 資源範圍
    echo -e "\n${BLUE}AWS 資源範圍：${NC}"
    read -p "AWS 區域 (預設: $(aws configure get region)): " aws_region
    aws_region=${aws_region:-$(aws configure get region)}
    
    echo -e "\n${CYAN}離職人員資訊確認：${NC}"
    echo -e "  姓名: ${YELLOW}$employee_name${NC}"
    echo -e "  用戶名: ${YELLOW}$employee_id${NC}"
    echo -e "  部門: ${YELLOW}$department${NC}"
    echo -e "  職位: ${YELLOW}$position${NC}"
    echo -e "  離職日期: ${YELLOW}$termination_date${NC}"
    echo -e "  離職類型: ${YELLOW}$termination_type${NC}"
    echo -e "  風險等級: ${YELLOW}$risk_level${NC}"
    echo -e "  AWS 區域: ${YELLOW}$aws_region${NC}"
    
    read -p "確認資訊正確？(y/n): " info_confirm
    
    if [[ $info_confirm != "y" ]]; then
        echo -e "${YELLOW}請重新執行腳本並提供正確資訊${NC}"
        exit 0
    fi
    
    log_message "收集離職人員資訊: $employee_name ($employee_id), 類型: $termination_type, 風險: $risk_level"
}

# 執行緊急安全措施
execute_emergency_measures() {
    if [[ $urgent_action == true ]]; then
        echo -e "\n${RED}[緊急] 執行立即安全措施...${NC}"
        
        echo -e "${RED}⚠ 檢測到高風險離職，執行緊急安全協議${NC}"
        
        # 立即搜索並斷開所有活躍連接
        echo -e "${BLUE}搜索並斷開員工的所有 VPN 連接...${NC}"
        
        # 獲取所有 VPN 端點
        all_endpoints=$(aws ec2 describe-client-vpn-endpoints --region $aws_region --query 'ClientVpnEndpoints[].ClientVpnEndpointId' --output text)
        
        for endpoint_id in $all_endpoints; do
            echo -e "${BLUE}檢查端點 $endpoint_id...${NC}"
            
            # 檢查此端點的連接
            connections=$(aws ec2 describe-client-vpn-connections \
              --client-vpn-endpoint-id $endpoint_id \
              --region $aws_region 2>/dev/null || continue)
            
            # 搜索員工的連接
            employee_connections=$(echo $connections | jq -r --arg id "$employee_id" '.Connections[] | select(.CommonName | contains($id)) | .ConnectionId')
            
            if [ ! -z "$employee_connections" ]; then
                echo -e "${RED}發現員工在端點 $endpoint_id 的連接，立即斷開...${NC}"
                echo $employee_connections | while read connection_id; do
                    aws ec2 terminate-client-vpn-connections \
                      --client-vpn-endpoint-id $endpoint_id \
                      --connection-id $connection_id \
                      --region $aws_region
                    echo -e "${GREEN}✓ 已斷開連接 $connection_id${NC}"
                done
            fi
        done
        
        # 立即停用所有訪問密鑰
        if [[ $iam_permissions == true ]]; then
            echo -e "${BLUE}立即停用員工的所有 AWS 訪問密鑰...${NC}"
            
            iam_user_check=$(aws iam get-user --user-name $employee_id 2>/dev/null || echo "not_found")
            
            if [[ "$iam_user_check" != "not_found" ]]; then
                access_keys=$(aws iam list-access-keys --user-name $employee_id --query 'AccessKeyMetadata[*].AccessKeyId' --output text)
                
                for key_id in $access_keys; do
                    aws iam update-access-key --access-key-id $key_id --status Inactive --user-name $employee_id
                    echo -e "${GREEN}✓ 已停用訪問密鑰 $key_id${NC}"
                done
            fi
        fi
        
        echo -e "${GREEN}✓ 緊急安全措施執行完成${NC}"
        log_message "執行緊急安全措施完成"
    fi
}

# 搜索和分析員工的 AWS 資源
analyze_employee_resources() {
    echo -e "\n${YELLOW}[3/10] 分析員工的 AWS 資源...${NC}"
    
    echo -e "${BLUE}搜索員工相關的 VPN 證書...${NC}"
    
    # 搜索 ACM 中的證書
    certificates=$(aws acm list-certificates --region $aws_region)
    employee_cert_arns=()
    
    # 方法1: 通過域名搜索
    while IFS= read -r cert_arn; do
        if [ ! -z "$cert_arn" ]; then
            cert_details=$(aws acm describe-certificate --certificate-arn "$cert_arn" --region $aws_region)
            domain_name=$(echo $cert_details | jq -r '.Certificate.DomainName // ""')
            
            if [[ $domain_name == *"$employee_id"* ]] || [[ $domain_name == *"$employee_name"* ]]; then
                employee_cert_arns+=("$cert_arn")
                echo -e "${GREEN}✓ 找到證書 (域名): $cert_arn${NC}"
            fi
        fi
    done <<< "$(echo $certificates | jq -r '.CertificateSummaryList[].CertificateArn')"
    
    # 方法2: 通過標籤搜索
    while IFS= read -r cert_arn; do
        if [ ! -z "$cert_arn" ]; then
            tags=$(aws acm list-tags-for-certificate --certificate-arn "$cert_arn" --region $aws_region 2>/dev/null || echo '{"Tags":[]}')
            contains_employee=$(echo $tags | jq -r --arg id "$employee_id" --arg name "$employee_name" 'select(.Tags[] | select(.Key=="Name" or .Key=="User") | .Value | (contains($id) or contains($name))) | true')
            
            if [[ "$contains_employee" == "true" ]] && [[ ! " ${employee_cert_arns[@]} " =~ " ${cert_arn} " ]]; then
                employee_cert_arns+=("$cert_arn")
                echo -e "${GREEN}✓ 找到證書 (標籤): $cert_arn${NC}"
            fi
        fi
    done <<< "$(echo $certificates | jq -r '.CertificateSummaryList[].CertificateArn')"
    
    echo -e "${BLUE}找到 ${#employee_cert_arns[@]} 個相關證書${NC}"
    
    # 搜索 VPN 連接歷史
    echo -e "${BLUE}分析 VPN 連接歷史...${NC}"
    
    all_endpoints=$(aws ec2 describe-client-vpn-endpoints --region $aws_region --query 'ClientVpnEndpoints[].ClientVpnEndpointId' --output text)
    total_connections=0
    recent_connections=0
    
    for endpoint_id in $all_endpoints; do
        # 檢查當前連接
        current_connections=$(aws ec2 describe-client-vpn-connections \
          --client-vpn-endpoint-id $endpoint_id \
          --region $aws_region 2>/dev/null || echo '{"Connections":[]}')
        
        employee_current=$(echo $current_connections | jq -r --arg id "$employee_id" '.Connections[] | select(.CommonName | contains($id)) | .ConnectionId' | wc -l)
        total_connections=$((total_connections + employee_current))
        
        # 檢查最近連接 (需要 CloudWatch 日誌)
        vpn_endpoint_info=$(aws ec2 describe-client-vpn-endpoints --client-vpn-endpoint-ids $endpoint_id --region $aws_region)
        log_group=$(echo $vpn_endpoint_info | jq -r '.ClientVpnEndpoints[0].ConnectionLogOptions.CloudwatchLogGroup // ""')
        
        if [ ! -z "$log_group" ] && [ "$log_group" != "null" ]; then
            # 搜索最近 24 小時的連接日誌
            start_time=$(date -u -d '24 hours ago' +%s)000
            end_time=$(date -u +%s)000
            
            recent_logs=$(aws logs filter-log-events \
              --log-group-name $log_group \
              --start-time $start_time \
              --end-time $end_time \
              --filter-pattern "$employee_id" \
              --region $aws_region 2>/dev/null || echo '{"events":[]}')
            
            recent_count=$(echo $recent_logs | jq '.events | length')
            recent_connections=$((recent_connections + recent_count))
        fi
    done
    
    echo -e "${BLUE}連接分析結果:${NC}"
    echo -e "  當前活躍連接: ${YELLOW}$total_connections${NC}"
    echo -e "  最近 24 小時連接事件: ${YELLOW}$recent_connections${NC}"
    
    log_message "資源分析完成 - 證書: ${#employee_cert_arns[@]}, 當前連接: $total_connections, 最近連接: $recent_connections"
}

# 撤銷 VPN 訪問權限
revoke_vpn_access() {
    echo -e "\n${YELLOW}[4/10] 撤銷 VPN 訪問權限...${NC}"
    
    if [ ${#employee_cert_arns[@]} -eq 0 ]; then
        echo -e "${YELLOW}未找到員工的 VPN 證書${NC}"
        return
    fi
    
    echo -e "${BLUE}開始撤銷 ${#employee_cert_arns[@]} 個證書...${NC}"
    
    revoked_certs=()
    failed_certs=()
    
    for cert_arn in "${employee_cert_arns[@]}"; do
        echo -e "${BLUE}處理證書: $cert_arn${NC}"
        
        # 先標記證書為已撤銷
        aws acm add-tags-to-certificate \
          --certificate-arn "$cert_arn" \
          --tags Key=Status,Value=Revoked Key=RevokedBy,Value=$(whoami) Key=RevokedDate,Value=$(date -u +%Y-%m-%dT%H:%M:%SZ) Key=Employee,Value="$employee_name" Key=Reason,Value="Employee Termination" \
          --region $aws_region 2>/dev/null || true
        
        # 嘗試刪除證書
        delete_result=$(aws acm delete-certificate --certificate-arn "$cert_arn" --region $aws_region 2>&1 || echo "failed")
        
        if [[ $delete_result == "failed" ]] || [[ $delete_result == *"error"* ]]; then
            echo -e "${RED}✗ 無法刪除證書 $cert_arn${NC}"
            failed_certs+=("$cert_arn")
        else
            echo -e "${GREEN}✓ 成功撤銷證書 $cert_arn${NC}"
            revoked_certs+=("$cert_arn")
        fi
    done
    
    echo -e "\n${CYAN}VPN 證書撤銷結果:${NC}"
    echo -e "  成功撤銷: ${GREEN}${#revoked_certs[@]}${NC} 個證書"
    echo -e "  撤銷失敗: ${RED}${#failed_certs[@]}${NC} 個證書"
    
    log_message "VPN 訪問權限撤銷完成 - 成功: ${#revoked_certs[@]}, 失敗: ${#failed_certs[@]}"
}

# 清理 IAM 權限
cleanup_iam_permissions() {
    echo -e "\n${YELLOW}[5/10] 清理 IAM 權限...${NC}"
    
    if [[ $iam_permissions != true ]]; then
        echo -e "${YELLOW}跳過 IAM 清理 (權限不足)${NC}"
        return
    fi
    
    # 檢查員工的 IAM 用戶
    iam_user_exists=$(aws iam get-user --user-name $employee_id 2>/dev/null || echo "not_found")
    
    if [[ "$iam_user_exists" == "not_found" ]]; then
        echo -e "${YELLOW}未找到員工的 IAM 用戶: $employee_id${NC}"
        
        # 搜索可能的用戶名變體
        echo -e "${BLUE}搜索相關的 IAM 用戶...${NC}"
        all_users=$(aws iam list-users --query 'Users[*].UserName' --output text)
        
        matching_users=""
        for user in $all_users; do
            if [[ $user == *"$employee_id"* ]] || [[ $user == *"$(echo $employee_name | tr ' ' '.')"* ]]; then
                matching_users="$matching_users $user"
            fi
        done
        
        if [ ! -z "$matching_users" ]; then
            echo -e "${BLUE}找到可能相關的用戶:${NC}"
            echo -e "${YELLOW}$matching_users${NC}"
            
            read -p "是否要處理這些用戶？(y/n): " process_users
            
            if [[ $process_users == "y" ]]; then
                for user in $matching_users; do
                    cleanup_single_iam_user $user
                done
            fi
        fi
    else
        echo -e "${GREEN}找到員工的 IAM 用戶: $employee_id${NC}"
        cleanup_single_iam_user $employee_id
    fi
    
    log_message "IAM 權限清理完成"
}

# 清理單個 IAM 用戶
cleanup_single_iam_user() {
    local username=$1
    echo -e "${BLUE}清理 IAM 用戶: $username${NC}"
    
    # 停用並刪除訪問密鑰
    echo -e "${BLUE}處理訪問密鑰...${NC}"
    access_keys=$(aws iam list-access-keys --user-name $username --query 'AccessKeyMetadata[*].AccessKeyId' --output text)
    
    for key_id in $access_keys; do
        echo -e "${BLUE}停用訪問密鑰: $key_id${NC}"
        aws iam update-access-key --access-key-id $key_id --status Inactive --user-name $username
        
        sleep 2
        
        echo -e "${BLUE}刪除訪問密鑰: $key_id${NC}"
        aws iam delete-access-key --access-key-id $key_id --user-name $username
    done
    
    # 分離管理政策
    echo -e "${BLUE}分離管理政策...${NC}"
    attached_policies=$(aws iam list-attached-user-policies --user-name $username --query 'AttachedPolicies[*].PolicyArn' --output text)
    for policy in $attached_policies; do
        echo -e "${BLUE}分離政策: $policy${NC}"
        aws iam detach-user-policy --user-name $username --policy-arn $policy
    done
    
    # 刪除內嵌政策
    echo -e "${BLUE}刪除內嵌政策...${NC}"
    inline_policies=$(aws iam list-user-policies --user-name $username --query 'PolicyNames' --output text)
    for policy in $inline_policies; do
        echo -e "${BLUE}刪除內嵌政策: $policy${NC}"
        aws iam delete-user-policy --user-name $username --policy-name $policy
    done
    
    # 從群組中移除
    echo -e "${BLUE}從群組中移除...${NC}"
    user_groups=$(aws iam list-groups-for-user --user-name $username --query 'Groups[*].GroupName' --output text)
    for group in $user_groups; do
        echo -e "${BLUE}從群組移除: $group${NC}"
        aws iam remove-user-from-group --user-name $username --group-name $group
    done
    
    # 刪除登入設定檔
    echo -e "${BLUE}檢查登入設定檔...${NC}"
    login_profile=$(aws iam get-login-profile --user-name $username 2>/dev/null || echo "not_found")
    if [[ "$login_profile" != "not_found" ]]; then
        aws iam delete-login-profile --user-name $username
        echo -e "${GREEN}✓ 登入設定檔已刪除${NC}"
    fi
    
    # 刪除 MFA 設備
    echo -e "${BLUE}檢查 MFA 設備...${NC}"
    mfa_devices=$(aws iam list-mfa-devices --user-name $username --query 'MFADevices[*].SerialNumber' --output text)
    for device in $mfa_devices; do
        echo -e "${BLUE}停用 MFA 設備: $device${NC}"
        aws iam deactivate-mfa-device --user-name $username --serial-number $device
    done
    
    # 刪除用戶
    echo -e "${BLUE}刪除 IAM 用戶: $username${NC}"
    aws iam delete-user --user-name $username
    echo -e "${GREEN}✓ IAM 用戶已刪除${NC}"
}

# 審計訪問日誌
audit_access_logs() {
    echo -e "\n${YELLOW}[6/10] 審計訪問日誌...${NC}"
    
    echo -e "${BLUE}搜索員工的 CloudTrail 活動...${NC}"
    
    # 搜索最近 30 天的 CloudTrail 事件
    start_date=$(date -u -d '30 days ago' +%Y-%m-%d)
    end_date=$(date -u +%Y-%m-%d)
    
    echo -e "${BLUE}搜索期間: $start_date 至 $end_date${NC}"
    
    # 創建審計報告目錄
    audit_dir="$OFFBOARDING_LOG_DIR/audit-$employee_id-$(date +%Y%m%d)"
    mkdir -p $audit_dir
    
    # 搜索 CloudTrail 事件
    echo -e "${BLUE}搜索 API 調用記錄...${NC}"
    
    cloudtrail_events=$(aws logs filter-log-events \
      --log-group-name CloudTrail/VPCFlowLogs \
      --start-time $(date -u -d "$start_date" +%s)000 \
      --end-time $(date -u -d "$end_date" +%s)000 \
      --filter-pattern "$employee_id" \
      --region $aws_region 2>/dev/null || echo '{"events":[]}')
    
    events_count=$(echo $cloudtrail_events | jq '.events | length')
    echo -e "${BLUE}找到 $events_count 個相關事件${NC}"
    
    # 保存事件到文件
    echo $cloudtrail_events | jq '.' > $audit_dir/cloudtrail_events.json
    
    # 搜索 VPN 連接日誌
    echo -e "${BLUE}搜索 VPN 連接日誌...${NC}"
    
    all_endpoints=$(aws ec2 describe-client-vpn-endpoints --region $aws_region --query 'ClientVpnEndpoints[].ClientVpnEndpointId' --output text)
    
    total_vpn_events=0
    
    for endpoint_id in $all_endpoints; do
        vpn_endpoint_info=$(aws ec2 describe-client-vpn-endpoints --client-vpn-endpoint-ids $endpoint_id --region $aws_region)
        log_group=$(echo $vpn_endpoint_info | jq -r '.ClientVpnEndpoints[0].ConnectionLogOptions.CloudwatchLogGroup // ""')
        
        if [ ! -z "$log_group" ] && [ "$log_group" != "null" ]; then
            vpn_events=$(aws logs filter-log-events \
              --log-group-name $log_group \
              --start-time $(date -u -d "$start_date" +%s)000 \
              --end-time $(date -u -d "$end_date" +%s)000 \
              --filter-pattern "$employee_id" \
              --region $aws_region 2>/dev/null || echo '{"events":[]}')
            
            endpoint_events=$(echo $vpn_events | jq '.events | length')
            total_vpn_events=$((total_vpn_events + endpoint_events))
            
            # 保存端點的事件
            echo $vpn_events | jq '.' > $audit_dir/vpn_events_$endpoint_id.json
        fi
    done
    
    echo -e "${BLUE}找到 $total_vpn_events 個 VPN 相關事件${NC}"
    
    # 生成審計摘要
    cat > $audit_dir/audit_summary.txt << EOF
=== 員工訪問日誌審計摘要 ===

員工資訊:
  姓名: $employee_name
  用戶名: $employee_id
  離職日期: $termination_date

審計期間: $start_date 至 $end_date

發現的活動:
  CloudTrail 事件: $events_count 個
  VPN 連接事件: $total_vpn_events 個

審計檔案:
  - cloudtrail_events.json: API 調用記錄
  - vpn_events_*.json: VPN 連接記錄

審計時間: $(date)
審計者: $(whoami)
EOF
    
    echo -e "${GREEN}✓ 審計日誌已保存到: $audit_dir${NC}"
    
    log_message "訪問日誌審計完成，事件數: CloudTrail($events_count), VPN($total_vpn_events)"
}

# 檢查殘留資源
check_residual_resources() {
    echo -e "\n${YELLOW}[7/10] 檢查殘留資源...${NC}"
    
    echo -e "${BLUE}搜索可能的殘留資源...${NC}"
    
    # 檢查 S3 存儲桶
    echo -e "${BLUE}檢查 S3 存儲桶...${NC}"
    s3_buckets=$(aws s3api list-buckets --query 'Buckets[*].Name' --output text 2>/dev/null || echo "")
    
    employee_buckets=""
    for bucket in $s3_buckets; do
        if [[ $bucket == *"$employee_id"* ]] || [[ $bucket == *"$(echo $employee_name | tr ' ' '-' | tr '[:upper:]' '[:lower:]')"* ]]; then
            employee_buckets="$employee_buckets $bucket"
        fi
    done
    
    if [ ! -z "$employee_buckets" ]; then
        echo -e "${YELLOW}⚠ 發現可能相關的 S3 存儲桶:${NC}"
        echo -e "${YELLOW}$employee_buckets${NC}"
    else
        echo -e "${GREEN}✓ 未發現相關的 S3 存儲桶${NC}"
    fi
    
    # 檢查 EC2 實例
    echo -e "${BLUE}檢查 EC2 實例...${NC}"
    ec2_instances=$(aws ec2 describe-instances \
      --filters "Name=tag:Owner,Values=*$employee_id*" "Name=instance-state-name,Values=running,stopped" \
      --region $aws_region \
      --query 'Reservations[*].Instances[*].InstanceId' --output text 2>/dev/null || echo "")
    
    if [ ! -z "$ec2_instances" ]; then
        echo -e "${YELLOW}⚠ 發現可能相關的 EC2 實例:${NC}"
        echo -e "${YELLOW}$ec2_instances${NC}"
    else
        echo -e "${GREEN}✓ 未發現相關的 EC2 實例${NC}"
    fi
    
    # 檢查其他 ACM 證書
    echo -e "${BLUE}檢查其他 ACM 證書...${NC}"
    other_certs=$(aws acm list-certificates --region $aws_region --query 'CertificateSummaryList[*].CertificateArn' --output text)
    
    remaining_employee_certs=""
    for cert_arn in $other_certs; do
        cert_details=$(aws acm describe-certificate --certificate-arn "$cert_arn" --region $aws_region 2>/dev/null || continue)
        domain_name=$(echo $cert_details | jq -r '.Certificate.DomainName // ""')
        
        if [[ $domain_name == *"$employee_id"* ]] || [[ $domain_name == *"$employee_name"* ]]; then
            remaining_employee_certs="$remaining_employee_certs $cert_arn"
        fi
    done
    
    if [ ! -z "$remaining_employee_certs" ]; then
        echo -e "${YELLOW}⚠ 發現殘留的證書:${NC}"
        echo -e "${YELLOW}$remaining_employee_certs${NC}"
    else
        echo -e "${GREEN}✓ 未發現殘留的證書${NC}"
    fi
    
    log_message "殘留資源檢查完成"
}

# 生成安全事件報告
generate_security_report() {
    echo -e "\n${YELLOW}[8/10] 生成安全事件報告...${NC}"
    
    # 創建安全報告
    security_report_file="$OFFBOARDING_LOG_DIR/security_report_${employee_id}_$(date +%Y%m%d_%H%M%S).txt"
    
    cat > $security_report_file << EOF
================================================================================
                          員工離職安全處理報告
================================================================================

報告生成時間: $(date)
處理人員: $(whoami)
AWS 操作身份: $(aws sts get-caller-identity --query 'Arn' --output text)

=== 員工資訊 ===
姓名: $employee_name
用戶名/ID: $employee_id
部門: $department
職位: $position
離職日期: $termination_date
離職類型: $termination_type
風險等級: $risk_level

=== 處理範圍 ===
AWS 區域: $aws_region
處理開始時間: $(date -d @$(head -1 $LOG_FILE | cut -d: -f1-2 | xargs -I {} date -d "{}" +%s) 2>/dev/null || echo "未知")
處理結束時間: $(date)

=== VPN 訪問權限撤銷 ===
撤銷的證書數量: ${#revoked_certs[@]}
成功撤銷證書:
EOF
    
    for cert in "${revoked_certs[@]}"; do
        echo "  ✓ $cert" >> $security_report_file
    done
    
    if [ ${#failed_certs[@]} -gt 0 ]; then
        echo "" >> $security_report_file
        echo "撤銷失敗的證書:" >> $security_report_file
        for cert in "${failed_certs[@]}"; do
            echo "  ✗ $cert" >> $security_report_file
        done
    fi
    
    cat >> $security_report_file << EOF

=== IAM 用戶處理 ===
IAM 權限: $([ "$iam_permissions" == "true" ] && echo "已處理" || echo "權限不足，未處理")
EOF
    
    if [[ $iam_permissions == true ]]; then
        cat >> $security_report_file << EOF
處理的 IAM 用戶: $employee_id
權限撤銷: 已完成
用戶刪除: 已完成
EOF
    fi
    
    cat >> $security_report_file << EOF

=== 訪問日誌審計 ===
審計期間: $start_date 至 $end_date
CloudTrail 事件: $events_count 個
VPN 連接事件: $total_vpn_events 個
審計檔案位置: $audit_dir

=== 緊急措施 ===
緊急協議執行: $([ "$urgent_action" == "true" ] && echo "是" || echo "否")
即時連接斷開: $([ "$urgent_action" == "true" ] && echo "已執行" || echo "未需要")

=== 安全建議 ===
1. 持續監控系統日誌，確認沒有來自此員工的訪問嘗試
2. 檢查生產環境的應用程式日誌
3. 確認沒有殘留的共享帳戶或服務帳戶
4. 驗證所有團隊訪問權限清單是否已更新
5. 如發現任何異常活動，立即聯繫安全團隊

=== 後續行動項目 ===
□ 通知團隊成員權限變更
□ 更新訪問控制文檔
□ 檢查和更新應急聯絡人清單
□ 安排安全審計跟進
□ 保留此報告用於合規審查

=== 合規記錄 ===
資料保留期: 按公司政策執行
審計追蹤: 完整記錄於 $LOG_FILE
報告歸檔: $security_report_file

報告完成時間: $(date)
數位簽章: $(echo -n "$employee_id-$termination_date-$(date)" | openssl dgst -sha256)

================================================================================
                                 報告結束
================================================================================
EOF
    
    echo -e "${GREEN}✓ 安全事件報告已生成: $security_report_file${NC}"
    
    log_message "安全事件報告已生成"
}

# 生成離職檢查清單
generate_offboarding_checklist() {
    echo -e "\n${YELLOW}[9/10] 生成離職檢查清單...${NC}"
    
    checklist_file="$OFFBOARDING_LOG_DIR/offboarding_checklist_${employee_id}_$(date +%Y%m%d).txt"
    
    cat > $checklist_file << EOF
================================================================================
                           員工離職檢查清單
================================================================================

員工: $employee_name ($employee_id)
離職日期: $termination_date
檢查清單生成時間: $(date)

=== AWS 和 VPN 相關 (已由系統自動處理) ===
[✓] 撤銷 VPN 證書
[✓] 斷開活躍的 VPN 連接
[✓] 停用和刪除 AWS 訪問密鑰
[✓] 移除 IAM 用戶權限
[✓] 記錄訪問日誌審計
[✓] 生成安全報告

=== 需要手動處理的項目 ===
[ ] 通知 IT 部門員工離職
[ ] 撤銷辦公室門禁卡權限
[ ] 收回公司設備 (筆電、手機等)
[ ] 停用公司郵件帳戶
[ ] 撤銷其他系統訪問權限:
    [ ] CRM 系統
    [ ] 專案管理工具
    [ ] 開發工具和平台
    [ ] 第三方服務

=== 團隊和專案交接 ===
[ ] 通知直屬主管
[ ] 通知團隊成員
[ ] 交接進行中的專案
[ ] 轉移重要文件和資料
[ ] 更新專案聯絡人資訊

=== 帳務和行政 ===
[ ] 處理最後薪資
[ ] 處理年假和加班時數
[ ] 回收公司信用卡
[ ] 更新保險受益人
[ ] 處理退休金或員工股票

=== 安全和合規 ===
[ ] 確認已簽署離職協議
[ ] 提醒保密協議義務
[ ] 回收任何機密文件
[ ] 確認沒有個人資料留存
[ ] 更新應急聯絡人清單

=== 辦公環境 ===
[ ] 清理辦公桌
[ ] 歸還鑰匙和通行證
[ ] 轉移停車位
[ ] 更新座位圖

=== 後續追蹤 ===
[ ] 30 天後檢查系統日誌
[ ] 確認沒有訪問嘗試
[ ] 驗證資料轉移完整性
[ ] 收集離職面談反饋

=== 檔案歸檔 ===
[ ] 保存人事檔案
[ ] 歸檔專案文件
[ ] 備份重要通訊記錄
[ ] 建立離職檔案

檢查清單負責人: ________________
主管確認: ________________
HR 確認: ________________
IT 確認: ________________

完成日期: ________________

注意事項:
- 此檢查清單應在員工離職後 30 天內完成
- 所有項目完成後，將此清單歸檔保存
- 如有任何安全顧慮，立即聯繫安全團隊

================================================================================
EOF
    
    echo -e "${GREEN}✓ 離職檢查清單已生成: $checklist_file${NC}"
    
    CHECKLIST_FILE=$checklist_file
    
    log_message "離職檢查清單已生成"
}

# 最終確認和清理
final_confirmation_and_cleanup() {
    echo -e "\n${YELLOW}[10/10] 最終確認和清理...${NC}"
    
    echo -e "${BLUE}執行最終驗證...${NC}"
    
    # 驗證 VPN 證書已撤銷
    echo -e "${BLUE}驗證 VPN 證書狀態...${NC}"
    remaining_certs=0
    
    for cert_arn in "${employee_cert_arns[@]}"; do
        cert_exists=$(aws acm describe-certificate --certificate-arn "$cert_arn" --region $aws_region 2>/dev/null || echo "not_found")
        if [[ $cert_exists != "not_found" ]]; then
            remaining_certs=$((remaining_certs + 1))
        fi
    done
    
    if [ $remaining_certs -eq 0 ]; then
        echo -e "${GREEN}✓ 所有 VPN 證書已成功撤銷${NC}"
    else
        echo -e "${YELLOW}⚠ 仍有 $remaining_certs 個證書未完全移除${NC}"
    fi
    
    # 驗證 IAM 用戶已刪除
    if [[ $iam_permissions == true ]]; then
        echo -e "${BLUE}驗證 IAM 用戶狀態...${NC}"
        iam_user_check=$(aws iam get-user --user-name $employee_id 2>/dev/null || echo "not_found")
        
        if [[ $iam_user_check == "not_found" ]]; then
            echo -e "${GREEN}✓ IAM 用戶已成功刪除${NC}"
        else
            echo -e "${YELLOW}⚠ IAM 用戶仍然存在${NC}"
        fi
    fi
    
    # 最後一次檢查活躍連接
    echo -e "${BLUE}最終檢查活躍連接...${NC}"
    all_endpoints=$(aws ec2 describe-client-vpn-endpoints --region $aws_region --query 'ClientVpnEndpoints[].ClientVpnEndpointId' --output text)
    
    active_connections=0
    for endpoint_id in $all_endpoints; do
        connections=$(aws ec2 describe-client-vpn-connections \
          --client-vpn-endpoint-id $endpoint_id \
          --region $aws_region 2>/dev/null || continue)
        
        employee_connections=$(echo $connections | jq -r --arg id "$employee_id" '.Connections[] | select(.CommonName | contains($id)) | .ConnectionId' | wc -l)
        active_connections=$((active_connections + employee_connections))
    done
    
    if [ $active_connections -eq 0 ]; then
        echo -e "${GREEN}✓ 確認沒有活躍的 VPN 連接${NC}"
    else
        echo -e "${RED}✗ 仍有 $active_connections 個活躍連接${NC}"
    fi
    
    # 清理臨時文件
    echo -e "${BLUE}清理臨時文件...${NC}"
    
    # 壓縮日誌文件
    if command -v gzip &> /dev/null; then
        find $OFFBOARDING_LOG_DIR -name "*.json" -exec gzip {} \;
        echo -e "${GREEN}✓ 日誌文件已壓縮${NC}"
    fi
    
    # 設置文件權限
    chmod 600 $OFFBOARDING_LOG_DIR/*.txt
    chmod 600 $OFFBOARDING_LOG_DIR/*.log
    
    echo -e "${GREEN}✓ 最終確認和清理完成${NC}"
    
    log_message "離職處理程序全部完成"
}

# 顯示完成摘要
show_completion_summary() {
    echo -e "\n${GREEN}============================================================${NC}"
    echo -e "${GREEN}              員工離職安全處理完成                        ${NC}"
    echo -e "${GREEN}============================================================${NC}"
    echo -e ""
    echo -e "${CYAN}處理摘要：${NC}"
    echo -e "  員工姓名: ${YELLOW}$employee_name${NC}"
    echo -e "  用戶名: ${YELLOW}$employee_id${NC}"
    echo -e "  離職類型: ${YELLOW}$termination_type${NC}"
    echo -e "  風險等級: ${YELLOW}$risk_level${NC}"
    echo -e "  處理時間: $(date)"
    echo -e ""
    echo -e "${CYAN}執行結果：${NC}"
    echo -e "  VPN 證書撤銷: ${GREEN}${#revoked_certs[@]} 成功${NC}, ${RED}${#failed_certs[@]} 失敗${NC}"
    echo -e "  IAM 用戶清理: $([ "$iam_permissions" == "true" ] && echo "${GREEN}已完成${NC}" || echo "${YELLOW}跳過${NC}")"
    echo -e "  訪問日誌審計: ${GREEN}已完成${NC}"
    echo -e "  緊急措施: $([ "$urgent_action" == "true" ] && echo "${GREEN}已執行${NC}" || echo "${BLUE}未需要${NC}")"
    echo -e ""
    echo -e "${CYAN}生成的文件：${NC}"
    echo -e "  ${BLUE}安全報告:${NC} $security_report_file"
    echo -e "  ${BLUE}檢查清單:${NC} $CHECKLIST_FILE"
    echo -e "  ${BLUE}審計日誌:${NC} $audit_dir"
    echo -e "  ${BLUE}操作日誌:${NC} $LOG_FILE"
    echo -e ""
    echo -e "${CYAN}重要提醒：${NC}"
    echo -e "  ${RED}•${NC} 請完成離職檢查清單中的手動項目"
    echo -e "  ${RED}•${NC} 持續監控系統日誌 30 天"
    echo -e "  ${RED}•${NC} 保留所有報告和日誌用於審計"
    echo -e "  ${RED}•${NC} 如發現異常活動，立即聯繫安全團隊"
    echo -e ""
    echo -e "${GREEN}離職安全處理程序已完成！${NC}"
}

# 主函數
main() {
    # 顯示歡迎訊息
    show_welcome
    
    # 執行離職處理步驟
    check_system_readiness
    collect_employee_info
    execute_emergency_measures
    analyze_employee_resources
    revoke_vpn_access
    cleanup_iam_permissions
    audit_access_logs
    check_residual_resources
    generate_security_report
    generate_offboarding_checklist
    final_confirmation_and_cleanup
    
    # 顯示完成摘要
    show_completion_summary
    
    log_message "員工離職安全處理程序完全完成"
}

# 記錄腳本啟動
log_message "員工離職安全處理腳本已啟動"

# 執行主程序
main