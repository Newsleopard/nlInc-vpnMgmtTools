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
        echo -e "${BLUE}是否要使用現有的安全群組？ (y/n): ${NC}" >&2
        read -r use_existing
        if [[ "$use_existing" =~ ^[Yy]$ ]]; then
            echo "$existing_sg_id"
            return 0
        else
            echo -e "${YELLOW}請手動刪除現有安全群組或選擇不同的名稱${NC}" >&2
            return 1
        fi
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
    
    echo -e "\n${CYAN}=== 配置現有服務的安全群組 ===${NC}"
    echo -e "${BLUE}現在您需要更新現有服務的安全群組，以允許 VPN 用戶訪問。${NC}"
    echo -e "${BLUE}我們已為您創建了專用的 Client VPN 安全群組: ${YELLOW}$client_vpn_sg_id${NC}"
    echo
    echo -e "${YELLOW}推薦做法：${NC}"
    echo -e "1. ${GREEN}安全最佳實務${NC}: 使用安全群組引用而非 CIDR 區塊"
    echo -e "2. ${GREEN}集中化管理${NC}: 所有 VPN 用戶共享同一安全群組 ID"
    echo -e "3. ${GREEN}審計友好${NC}: 易於追蹤和管理 VPN 用戶權限"
    echo
    echo -e "${CYAN}示例命令（您需要根據實際服務調整目標安全群組 ID）：${NC}"
    echo
    
    # 生成示例命令並保存到文件
    local commands_file="security_group_commands_${env_name}.sh"
    echo -e "${BLUE}正在生成安全群組配置命令文件: $commands_file${NC}"
    
    if generate_security_group_commands_file "$client_vpn_sg_id" "$aws_region" "$env_name"; then
        echo -e "${GREEN}✓ 安全群組配置命令已保存到: $commands_file${NC}"
        echo -e "${BLUE}請檢查並執行該文件中的命令來配置服務訪問權限。${NC}"
    else
        echo -e "${YELLOW}⚠️ 無法生成命令文件，以下是手動配置示例：${NC}"
        _show_manual_security_group_examples "$client_vpn_sg_id"
    fi
    
    echo
    echo -e "${YELLOW}完成服務配置後，VPN 用戶將能夠訪問您授權的服務。${NC}"
    echo -e "${BLUE}按 Enter 繼續...${NC}"
    read
    
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