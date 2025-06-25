#!/bin/bash

# lib/security_group_operations.sh
# Client VPN 安全群組管理相關函式庫
# 包含專用安全群組創建、更新和命令生成功能

# 確保已載入核心函式
if [ -z "$LOG_FILE_CORE" ]; then
    echo "錯誤: 核心函式庫未載入。請先載入 core_functions.sh"
    exit 1
fi

# 輔助函式：創建專用的 Client VPN 安全群組
# 參數: $1 = VPC ID, $2 = AWS REGION, $3 = ENVIRONMENT (staging/production)
# 返回: 安全群組 ID 或錯誤
create_dedicated_client_vpn_security_group() {
    local vpc_id="$1"
    local aws_region="$2"
    local environment="$3"
    
    # 參數驗證
    if [ -z "$vpc_id" ] || [ -z "$aws_region" ] || [ -z "$environment" ]; then
        echo -e "${RED}錯誤: create_dedicated_client_vpn_security_group 缺少必要參數${NC}" >&2
        return 1
    fi
    
    # 驗證 VPC 存在
    if ! aws ec2 describe-vpcs --vpc-ids "$vpc_id" --region "$aws_region" >/dev/null 2>&1; then
        echo -e "${RED}錯誤: VPC '$vpc_id' 不存在於區域 '$aws_region'${NC}" >&2
        return 1
    fi
    
    # 生成安全群組名稱和描述
    local sg_name="client-vpn-sg-${environment}"
    local sg_description="Dedicated security group for Client VPN users - ${environment} environment"
    
    echo -e "${BLUE}正在創建專用的 Client VPN 安全群組...${NC}" >&2
    echo -e "${YELLOW}安全群組名稱: $sg_name${NC}" >&2
    echo -e "${YELLOW}VPC ID: $vpc_id${NC}" >&2
    echo -e "${YELLOW}區域: $aws_region${NC}" >&2
    
    # 檢查是否已存在同名安全群組
    local existing_sg_id
    existing_sg_id=$(aws ec2 describe-security-groups \
        --filters "Name=group-name,Values=$sg_name" "Name=vpc-id,Values=$vpc_id" \
        --region "$aws_region" \
        --query 'SecurityGroups[0].GroupId' \
        --output text 2>/dev/null)
    
    if [ "$existing_sg_id" != "None" ] && [ -n "$existing_sg_id" ]; then
        echo -e "${YELLOW}警告: 安全群組 '$sg_name' 已存在 (ID: $existing_sg_id)${NC}" >&2
        echo -e "${GREEN}✓ 使用現有的安全群組: $existing_sg_id${NC}" >&2
        echo "$existing_sg_id"
        return 0
    fi
    
    # 創建安全群組
    local sg_result
    sg_result=$(aws ec2 create-security-group \
        --group-name "$sg_name" \
        --description "$sg_description" \
        --vpc-id "$vpc_id" \
        --region "$aws_region" \
        --output text 2>&1)
    
    if [ $? -ne 0 ]; then
        echo -e "${RED}錯誤: 創建安全群組失敗${NC}" >&2
        echo -e "${RED}AWS 回應: $sg_result${NC}" >&2
        return 1
    fi
    
    # 提取安全群組 ID
    local new_sg_id
    new_sg_id=$(echo "$sg_result" | grep -o 'sg-[0-9a-f]*' | head -1)
    
    if [ -z "$new_sg_id" ]; then
        echo -e "${RED}錯誤: 無法提取新創建的安全群組 ID${NC}" >&2
        echo -e "${RED}創建結果: $sg_result${NC}" >&2
        return 1
    fi
    
    echo -e "${GREEN}✓ 專用 Client VPN 安全群組創建成功${NC}" >&2
    echo -e "${GREEN}  安全群組 ID: $new_sg_id${NC}" >&2
    echo -e "${GREEN}  名稱: $sg_name${NC}" >&2
    
    # 添加預設標籤
    aws ec2 create-tags \
        --resources "$new_sg_id" \
        --tags Key=Name,Value="$sg_name" \
               Key=Purpose,Value="ClientVPN" \
               Key=Environment,Value="$environment" \
               Key=ManagedBy,Value="nlInc-vpnMgmtTools" \
        --region "$aws_region" >/dev/null 2>&1
    
    # 配置安全群組規則 - 允許所有出站流量
    echo -e "${BLUE}正在配置安全群組規則...${NC}" >&2
    
    # 刪除預設的出站規則（如果存在）
    aws ec2 revoke-security-group-egress \
        --group-id "$new_sg_id" \
        --protocol -1 \
        --cidr 0.0.0.0/0 \
        --region "$aws_region" >/dev/null 2>&1
    
    # 添加允許所有出站流量的規則
    local egress_result
    egress_result=$(aws ec2 authorize-security-group-egress \
        --group-id "$new_sg_id" \
        --protocol -1 \
        --cidr 0.0.0.0/0 \
        --region "$aws_region" 2>&1)
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓ 出站規則配置成功${NC}" >&2
    else
        echo -e "${YELLOW}警告: 配置出站規則時出現問題: $egress_result${NC}" >&2
    fi
    
    log_message_core "專用 Client VPN 安全群組創建成功: $new_sg_id (環境: $environment)"
    echo "$new_sg_id"
    return 0
}

# 提示更新現有安全群組以允許 VPN 訪問
# 參數: $1 = CLIENT_VPN_SECURITY_GROUP_ID, $2 = AWS_REGION, $3 = ENV_NAME
prompt_update_existing_security_groups() {
    local client_vpn_sg_id="$1"
    local aws_region="$2"
    local env_name="$3"
    
    # 參數驗證
    if [ -z "$client_vpn_sg_id" ] || [ -z "$aws_region" ] || [ -z "$env_name" ]; then
        echo -e "${RED}錯誤: prompt_update_existing_security_groups 缺少必要參數${NC}" >&2
        return 1
    fi
    
    echo -e "\n${CYAN}=== Client VPN 安全群組設定完成 ===${NC}" >&2
    echo -e "${GREEN}✓ 已創建專用的 Client VPN 安全群組: $client_vpn_sg_id${NC}" >&2
    echo -e "${BLUE}該安全群組已配置為允許所有出站流量，提供基本的網路連接能力。${NC}" >&2
    log_message_core "Client VPN 安全群組創建完成: $client_vpn_sg_id"
    
    echo -e "\n${YELLOW}=== 下一步：自動配置 VPN 服務訪問權限 ===${NC}" >&2
    echo -e "${BLUE}正在使用 manage_vpn_service_access.sh 自動發現並配置服務訪問...${NC}" >&2
    log_message_core "開始自動配置 VPN 服務訪問權限: client_vpn_sg_id=$client_vpn_sg_id, region=$aws_region"
    
    # 獲取專案根目錄和 VPN 服務訪問腳本路徑
    local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    local project_root="$(dirname "$script_dir")"
    local vpn_service_script="$project_root/admin-tools/manage_vpn_service_access.sh"
    
    # 檢查 VPN 服務訪問管理腳本是否存在
    if [ ! -f "$vpn_service_script" ]; then
        log_message_core "警告: manage_vpn_service_access.sh 不存在，回退到手動配置"
        echo -e "${YELLOW}⚠️  VPN 服務訪問管理腳本不存在，請手動配置安全群組規則${NC}" >&2
        echo -e "${BLUE}預期路徑: $vpn_service_script${NC}" >&2
        echo -e "${YELLOW}請稍後手動運行: ./admin-tools/manage_vpn_service_access.sh create $client_vpn_sg_id --region $aws_region${NC}" >&2
        return 1
    fi
    
    echo -e "\n${CYAN}=== 自動 VPN 服務訪問配置 ===${NC}" >&2
    
    # 步驟 1: 服務發現和預覽
    echo -e "\n${YELLOW}🔍 步驟 1: 發現當前環境中的服務...${NC}" >&2
    log_message_core "執行服務發現: $vpn_service_script discover --region $aws_region"
    
    if ! "$vpn_service_script" discover --region "$aws_region"; then
        log_message_core "警告: VPN 服務發現失敗，回退到手動配置"
        echo -e "${YELLOW}⚠️  服務發現失敗，建議稍後手動運行：${NC}" >&2
        echo -e "${BLUE}$vpn_service_script discover --region $aws_region${NC}" >&2
        return 1
    fi
    
    # 步驟 2: 預覽即將創建的規則
    echo -e "\n${YELLOW}🔍 步驟 2: 預覽即將創建的 VPN 服務訪問規則...${NC}" >&2
    log_message_core "執行規則預覽: $vpn_service_script create $client_vpn_sg_id --region $aws_region --dry-run"
    
    if ! "$vpn_service_script" create "$client_vpn_sg_id" --region "$aws_region" --dry-run; then
        log_message_core "警告: VPN 服務訪問規則預覽失敗，繼續手動配置"
        echo -e "${YELLOW}⚠️  規則預覽失敗，建議稍後手動運行：${NC}" >&2
        echo -e "${BLUE}$vpn_service_script create $client_vpn_sg_id --region $aws_region${NC}" >&2
        return 1
    fi
    
    # 步驟 3: 詢問用戶是否執行自動配置
    echo -e "\n${CYAN}🚀 步驟 3: 是否自動執行上述 VPN 服務訪問規則配置？${NC}" >&2
    echo -e "${YELLOW}[y] 是，自動配置所有服務訪問規則${NC}" >&2
    echo -e "${YELLOW}[n] 否，稍後手動配置${NC}" >&2
    echo -e "${YELLOW}[s] 跳過，我會自己處理${NC}" >&2
    
    local choice
    local max_attempts=3
    local attempts=0
    
    while [ $attempts -lt $max_attempts ]; do
        echo -n "請選擇 [y/n/s]: " >&2
        read choice
        case "$choice" in
            [Yy]* )
                echo -e "\n${GREEN}✅ 開始自動配置 VPN 服務訪問規則...${NC}" >&2
                log_message_core "用戶選擇自動配置，開始執行: $vpn_service_script create $client_vpn_sg_id --region $aws_region"
                
                if "$vpn_service_script" create "$client_vpn_sg_id" --region "$aws_region"; then
                    echo -e "\n${GREEN}🎉 VPN 服務訪問規則配置完成！${NC}" >&2
                    log_message_core "VPN 服務訪問規則自動配置成功"
                    
                    echo -e "\n${CYAN}=== 配置摘要 ===${NC}" >&2
                    echo -e "${GREEN}• 已自動發現並配置所有服務安全群組${NC}" >&2
                    echo -e "${GREEN}• VPN 用戶現在可以訪問 MySQL/RDS、Redis、HBase、EKS 等服務${NC}" >&2
                    echo -e "${GREEN}• 遵循最小權限原則，安全且高效${NC}" >&2
                    
                    # 顯示如何撤銷規則的資訊
                    echo -e "\n${BLUE}💡 如需撤銷 VPN 訪問規則，請運行：${NC}" >&2
                    echo -e "${DIM}$vpn_service_script remove $client_vpn_sg_id --region $aws_region${NC}" >&2
                    
                    log_message_core "VPN 服務訪問配置完成，提供撤銷指令: remove $client_vpn_sg_id --region $aws_region"
                    return 0
                else
                    echo -e "\n${RED}❌ VPN 服務訪問規則配置失敗${NC}" >&2
                    log_message_core "VPN 服務訪問規則自動配置失敗"
                    echo -e "${YELLOW}請稍後手動運行以下命令：${NC}" >&2
                    echo -e "${BLUE}$vpn_service_script create $client_vpn_sg_id --region $aws_region${NC}" >&2
                    return 1
                fi
                ;;
            [Nn]* )
                echo -e "\n${YELLOW}⏭️  跳過自動配置，稍後請手動運行：${NC}" >&2
                echo -e "${BLUE}$vpn_service_script create $client_vpn_sg_id --region $aws_region${NC}" >&2
                log_message_core "用戶選擇跳過自動配置，提供手動配置指令"
                return 0
                ;;
            [Ss]* )
                echo -e "\n${BLUE}✅ 用戶選擇自行處理 VPN 服務訪問配置${NC}" >&2
                log_message_core "用戶選擇自行處理 VPN 服務訪問配置"
                return 0
                ;;
            * )
                echo -e "${RED}請輸入 y、n 或 s${NC}" >&2
                attempts=$((attempts + 1))
                if [ $attempts -eq $max_attempts ]; then
                    echo -e "${YELLOW}輸入次數過多，默認跳過自動配置${NC}" >&2
                    log_message_core "用戶輸入次數過多，默認跳過自動配置"
                    return 0
                fi
                ;;
        esac
    done
    
    # 顯示增強的安全優勢說明
    echo -e "\n${CYAN}=== 自動化 VPN 服務訪問的安全優勢 ===${NC}" >&2
    echo -e "${BLUE}這種自動化方法更清潔且更安全，因為：${NC}" >&2
    echo -e "${GREEN}• Client VPN 用戶被隔離在專用安全群組中${NC}" >&2
    echo -e "${GREEN}• 自動發現服務，無需維護硬編碼安全群組 ID${NC}" >&2
    echo -e "${GREEN}• 支援 dry-run 預覽，避免意外配置${NC}" >&2
    echo -e "${GREEN}• 遵循最小權限原則，具有更好的安全姿態${NC}" >&2
    echo -e "${GREEN}• 更容易審計和故障排除${NC}" >&2
    echo -e "${GREEN}• 支援跨環境使用（staging/production）${NC}" >&2
    echo -e "${GREEN}• 可輕鬆撤銷所有 VPN 訪問規則${NC}" >&2
    
    # 提供額外的管理指令
    echo -e "\n${BLUE}💡 常用 VPN 服務訪問管理指令：${NC}" >&2
    echo -e "${DIM}# 發現服務${NC}" >&2
    echo -e "${DIM}$vpn_service_script discover --region $aws_region${NC}" >&2
    echo -e "${DIM}# 創建 VPN 訪問規則${NC}" >&2  
    echo -e "${DIM}$vpn_service_script create $client_vpn_sg_id --region $aws_region${NC}" >&2
    echo -e "${DIM}# 撤銷 VPN 訪問規則${NC}" >&2
    echo -e "${DIM}$vpn_service_script remove $client_vpn_sg_id --region $aws_region${NC}" >&2
    
    log_message_core "VPN 服務訪問權限配置步驟完成"
    return 0
}

# 生成安全群組配置命令文件
# 參數: $1 = CLIENT_VPN_SECURITY_GROUP_ID, $2 = AWS_REGION, $3 = ENV_NAME
generate_security_group_commands_file() {
    local client_vpn_sg_id="$1"
    local aws_region="$2"
    local env_name="$3"
    
    # 參數驗證
    if [ -z "$client_vpn_sg_id" ] || [ -z "$aws_region" ] || [ -z "$env_name" ]; then
        echo -e "${RED}錯誤: generate_security_group_commands_file 缺少必要參數${NC}" >&2
        return 1
    fi
    
    local commands_file="security_group_commands_${env_name}.sh"
    
    cat > "$commands_file" << EOF
#!/bin/bash
# 
# Client VPN 安全群組配置命令
# 環境: $env_name
# 生成時間: $(date)
# VPN 安全群組 ID: $client_vpn_sg_id
#
# 使用說明:
# 1. 檢查並修改下方命令中的目標安全群組 ID (sg-xxxxxxxxx)
# 2. 根據需要啟用或停用特定服務的訪問
# 3. 執行此腳本: bash $commands_file
#

# 顏色定義
GREEN='\\033[0;32m'
BLUE='\\033[0;34m'
RED='\\033[0;31m'
YELLOW='\\033[1;33m'
NC='\\033[0m' # No Color

echo -e "\${BLUE}配置 Client VPN 安全群組訪問權限...\${NC}"
echo -e "\${YELLOW}VPN 安全群組 ID: $client_vpn_sg_id\${NC}"
echo

# =============================================================================
# 資料庫服務 (MySQL/RDS, PostgreSQL, Redis 等)
# =============================================================================
echo -e "\${CYAN}配置資料庫服務訪問...\${NC}"

# MySQL/RDS (Port 3306)
# 請將 sg-TARGET_DB_SG_ID 替換為您的資料庫安全群組 ID
echo "# MySQL/RDS 訪問"
echo "aws ec2 authorize-security-group-ingress \\\\"
echo "  --group-id sg-TARGET_DB_SG_ID \\\\"
echo "  --protocol tcp \\\\"
echo "  --port 3306 \\\\"
echo "  --source-group $client_vpn_sg_id \\\\"
echo "  --region $aws_region"
echo

# PostgreSQL (Port 5432)
echo "# PostgreSQL 訪問"
echo "aws ec2 authorize-security-group-ingress \\\\"
echo "  --group-id sg-TARGET_POSTGRES_SG_ID \\\\"
echo "  --protocol tcp \\\\"
echo "  --port 5432 \\\\"
echo "  --source-group $client_vpn_sg_id \\\\"
echo "  --region $aws_region"
echo

# Redis (Port 6379)
echo "# Redis 訪問"
echo "aws ec2 authorize-security-group-ingress \\\\"
echo "  --group-id sg-TARGET_REDIS_SG_ID \\\\"
echo "  --protocol tcp \\\\"
echo "  --port 6379 \\\\"
echo "  --source-group $client_vpn_sg_id \\\\"
echo "  --region $aws_region"
echo

# =============================================================================
# Web 服務 (HTTP/HTTPS, 應用程式伺服器等)
# =============================================================================
echo -e "\${CYAN}配置 Web 服務訪問...\${NC}"

# HTTP (Port 80)
echo "# HTTP 訪問"
echo "aws ec2 authorize-security-group-ingress \\\\"
echo "  --group-id sg-TARGET_WEB_SG_ID \\\\"
echo "  --protocol tcp \\\\"
echo "  --port 80 \\\\"
echo "  --source-group $client_vpn_sg_id \\\\"
echo "  --region $aws_region"
echo

# HTTPS (Port 443)
echo "# HTTPS 訪問"
echo "aws ec2 authorize-security-group-ingress \\\\"
echo "  --group-id sg-TARGET_WEB_SG_ID \\\\"
echo "  --protocol tcp \\\\"
echo "  --port 443 \\\\"
echo "  --source-group $client_vpn_sg_id \\\\"
echo "  --region $aws_region"
echo

# =============================================================================
# 容器和編排服務
# =============================================================================
echo -e "\${CYAN}配置容器服務訪問...\${NC}"

# EKS API Server (通常是 Port 443，但也可能是其他端口)
echo "# EKS API Server 訪問"
echo "aws ec2 authorize-security-group-ingress \\\\"
echo "  --group-id sg-TARGET_EKS_SG_ID \\\\"
echo "  --protocol tcp \\\\"
echo "  --port 443 \\\\"
echo "  --source-group $client_vpn_sg_id \\\\"
echo "  --region $aws_region"
echo

# =============================================================================
# 大數據和分析服務
# =============================================================================
echo -e "\${CYAN}配置大數據服務訪問...\${NC}"

# HBase (Port 16000, 16010, 16020, 16030)
echo "# HBase Master 訪問"
echo "aws ec2 authorize-security-group-ingress \\\\"
echo "  --group-id sg-TARGET_HBASE_SG_ID \\\\"
echo "  --protocol tcp \\\\"
echo "  --port 16000 \\\\"
echo "  --source-group $client_vpn_sg_id \\\\"
echo "  --region $aws_region"
echo

echo "# HBase RegionServer 訪問"
echo "aws ec2 authorize-security-group-ingress \\\\"
echo "  --group-id sg-TARGET_HBASE_SG_ID \\\\"
echo "  --protocol tcp \\\\"
echo "  --port 16020 \\\\"
echo "  --source-group $client_vpn_sg_id \\\\"
echo "  --region $aws_region"
echo

# Phoenix Query Server (Port 8765)
echo "# Phoenix Query Server 訪問"
echo "aws ec2 authorize-security-group-ingress \\\\"
echo "  --group-id sg-TARGET_PHOENIX_SG_ID \\\\"
echo "  --protocol tcp \\\\"
echo "  --port 8765 \\\\"
echo "  --source-group $client_vpn_sg_id \\\\"
echo "  --region $aws_region"
echo

# =============================================================================
# 自定義服務端口
# =============================================================================
echo -e "\${CYAN}配置自定義服務訪問...\${NC}"

# 示例：自定義應用程式 (Port 8080)
echo "# 自定義應用程式訪問 (範例)"
echo "aws ec2 authorize-security-group-ingress \\\\"
echo "  --group-id sg-TARGET_APP_SG_ID \\\\"
echo "  --protocol tcp \\\\"
echo "  --port 8080 \\\\"
echo "  --source-group $client_vpn_sg_id \\\\"
echo "  --region $aws_region"
echo

echo -e "\${GREEN}配置完成！\${NC}"
echo -e "\${YELLOW}注意: 請將 sg-TARGET_*_SG_ID 替換為實際的安全群組 ID\${NC}"
echo -e "\${BLUE}執行前請仔細檢查每個命令\${NC}"

EOF

    # 設置執行權限
    chmod +x "$commands_file"
    
    log_message_core "安全群組配置命令文件已生成: $commands_file"
    return 0
}

# 顯示手動安全群組配置示例
_show_manual_security_group_examples() {
    local client_vpn_sg_id="$1"
    
    echo -e "${CYAN}手動配置示例:${NC}"
    echo
    echo -e "${YELLOW}1. 資料庫服務 (MySQL/RDS, Redis):${NC}"
    echo "   aws ec2 authorize-security-group-ingress --group-id sg-YOUR_DB_SG_ID --source-group $client_vpn_sg_id"
    echo
    echo -e "${YELLOW}2. Web 服務:${NC}"
    echo "   aws ec2 authorize-security-group-ingress --group-id sg-YOUR_WEB_SG_ID --source-group $client_vpn_sg_id"
    echo
    echo -e "${YELLOW}3. 容器服務 (EKS):${NC}"
    echo "   aws ec2 authorize-security-group-ingress --group-id sg-YOUR_EKS_SG_ID --source-group $client_vpn_sg_id"
    echo
}

# 刪除專用 Client VPN 安全群組
# 參數: $1 = SECURITY_GROUP_ID, $2 = AWS_REGION
delete_client_vpn_security_group() {
    local sg_id="$1"
    local aws_region="$2"
    
    # 參數驗證
    if [ -z "$sg_id" ] || [ -z "$aws_region" ]; then
        echo -e "${RED}錯誤: delete_client_vpn_security_group 缺少必要參數${NC}" >&2
        return 1
    fi
    
    # 驗證安全群組存在
    if ! aws ec2 describe-security-groups --group-ids "$sg_id" --region "$aws_region" >/dev/null 2>&1; then
        echo -e "${YELLOW}警告: 安全群組 '$sg_id' 不存在或已被刪除${NC}" >&2
        return 0
    fi
    
    echo -e "${BLUE}正在刪除 Client VPN 專用安全群組: $sg_id${NC}" >&2
    
    # 嘗試刪除安全群組
    if aws ec2 delete-security-group --group-id "$sg_id" --region "$aws_region" >/dev/null 2>&1; then
        echo -e "${GREEN}✓ 安全群組 '$sg_id' 已成功刪除${NC}" >&2
        log_message_core "Client VPN 專用安全群組已刪除: $sg_id"
        return 0
    else
        echo -e "${YELLOW}⚠️ 無法刪除安全群組 '$sg_id'（可能仍被其他資源使用）${NC}" >&2
        log_message_core "警告: 無法刪除安全群組 $sg_id，可能仍被其他資源使用"
        return 1
    fi
}

