#!/bin/bash

# AWS Client VPN 管理員主腳本 for macOS
# 用途：建立、管理和刪除 AWS Client VPN 端點
# 作者：VPN 管理員
# 版本：1.0

# 顏色設定
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# 全域變數
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/.vpn_config"
LOG_FILE="$SCRIPT_DIR/vpn_admin.log"

# 阻止腳本在出錯時繼續執行
set -e

# 記錄函數
log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S'): $1" >> $LOG_FILE
}

# 顯示主選單
show_menu() {
    clear
    echo -e "${CYAN}========================================================${NC}"
    echo -e "${CYAN}           AWS Client VPN 管理員控制台                ${NC}"
    echo -e "${CYAN}========================================================${NC}"
    echo -e ""
    echo -e "${BLUE}選擇操作：${NC}"
    echo -e "  ${GREEN}1.${NC} 建立新的 VPN 端點"
    echo -e "  ${GREEN}2.${NC} 查看現有 VPN 端點"
    echo -e "  ${GREEN}3.${NC} 管理 VPN 端點設定"
    echo -e "  ${GREEN}4.${NC} 刪除 VPN 端點"
    echo -e "  ${GREEN}5.${NC} 查看連接日誌"
    echo -e "  ${GREEN}6.${NC} 匯出團隊成員設定檔"
    echo -e "  ${GREEN}7.${NC} 查看管理員指南"
    echo -e "  ${GREEN}8.${NC} 系統健康檢查"
    echo -e "  ${RED}9.${NC} 退出"
    echo -e ""
    echo -e "${CYAN}========================================================${NC}"
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

# 設定 AWS 配置
setup_aws_config() {
    echo -e "\n${YELLOW}設定 AWS 配置...${NC}"
    
    if [ ! -f ~/.aws/credentials ] || [ ! -f ~/.aws/config ]; then
        echo -e "${YELLOW}請提供您的 AWS 管理員帳戶資訊：${NC}"
        
        read -p "請輸入 AWS Access Key ID: " aws_access_key
        read -s -p "請輸入 AWS Secret Access Key: " aws_secret_key
        echo
        read -p "請輸入 AWS 區域 (例如 ap-northeast-1): " aws_region
        
        # 創建配置目錄和文件
        mkdir -p ~/.aws
        
        # 寫入認證
        cat > ~/.aws/credentials << EOF
[default]
aws_access_key_id = $aws_access_key
aws_secret_access_key = $aws_secret_key
EOF
        
        # 寫入配置
        cat > ~/.aws/config << EOF
[default]
region = $aws_region
output = json
EOF
        
        echo -e "${GREEN}AWS 配置已完成！${NC}"
    else
        echo -e "${GREEN}✓ AWS 已配置${NC}"
        aws_region=$(aws configure get region)
    fi
    
    # 保存配置到本地文件
    echo "AWS_REGION=$aws_region" > $CONFIG_FILE
    log_message "AWS 配置已更新，區域: $aws_region"
}

# 生成證書
generate_certificates() {
    echo -e "\n${YELLOW}生成 VPN 證書...${NC}"
    
    # 創建工作目錄
    cert_dir="$SCRIPT_DIR/certificates"
    mkdir -p $cert_dir
    cd $cert_dir
    
    # 初始化 PKI
    if [ ! -d "pki" ]; then
        echo -e "${BLUE}初始化 PKI...${NC}"
        easyrsa init-pki
        
        # 設置變數
        echo "set_var EASYRSA_REQ_CN \"VPN CA\"" > vars
        echo "set_var EASYRSA_KEY_SIZE 2048" >> vars
        echo "set_var EASYRSA_ALGO rsa" >> vars
        echo "set_var EASYRSA_CA_EXPIRE 3650" >> vars
        echo "set_var EASYRSA_CERT_EXPIRE 365" >> vars
    fi
    
    # 生成 CA 證書
    if [ ! -f "pki/ca.crt" ]; then
        echo -e "${BLUE}生成 CA 證書...${NC}"
        yes "" | easyrsa build-ca nopass
    fi
    
    # 生成伺服器證書
    if [ ! -f "pki/issued/server.crt" ]; then
        echo -e "${BLUE}生成伺服器證書...${NC}"
        yes "" | easyrsa build-server-full server nopass
    fi
    
    echo -e "${GREEN}證書生成完成！${NC}"
    log_message "VPN 證書已生成"
}

# 建立 VPN 端點
create_vpn_endpoint() {
    echo -e "\n${CYAN}=== 建立新的 VPN 端點 ===${NC}"
    
    # 載入配置
    if [ -f $CONFIG_FILE ]; then
        source $CONFIG_FILE
    else
        setup_aws_config
        source $CONFIG_FILE
    fi
    
    # 檢查證書
    if [ ! -f "$SCRIPT_DIR/certificates/pki/ca.crt" ]; then
        generate_certificates
    fi
    
    # 導入證書到 ACM
    echo -e "${BLUE}導入證書到 AWS Certificate Manager...${NC}"
    
    cert_dir="$SCRIPT_DIR/certificates"
    
    # 導入伺服器證書
    server_cert=$(aws acm import-certificate \
      --certificate fileb://$cert_dir/pki/issued/server.crt \
      --private-key fileb://$cert_dir/pki/private/server.key \
      --certificate-chain fileb://$cert_dir/pki/ca.crt \
      --region $AWS_REGION \
      --tags Key=Name,Value="VPN-Server-Cert" Key=Purpose,Value="ClientVPN")
    
    server_cert_arn=$(echo $server_cert | jq -r '.CertificateArn')
    
    # 導入 CA 證書作為客戶端證書
    client_cert=$(aws acm import-certificate \
      --certificate fileb://$cert_dir/pki/ca.crt \
      --private-key fileb://$cert_dir/pki/private/ca.key \
      --region $AWS_REGION \
      --tags Key=Name,Value="VPN-Client-CA" Key=Purpose,Value="ClientVPN")
    
    client_cert_arn=$(echo $client_cert | jq -r '.CertificateArn')
    
    # 獲取網絡資訊
    echo -e "\n${BLUE}選擇網絡設定...${NC}"
    
    # 列出 VPCs
    echo -e "${YELLOW}可用的 VPCs:${NC}"
    aws ec2 describe-vpcs --region $AWS_REGION | jq -r '.Vpcs[] | "VPC ID: \(.VpcId), CIDR: \(.CidrBlock), 名稱: \(if .Tags then (.Tags[] | select(.Key=="Name") | .Value) else "無名稱" end)"'
    
    read -p "請輸入要連接的 VPC ID: " vpc_id
    
    # 獲取 VPC CIDR
    vpc_cidr=$(aws ec2 describe-vpcs --vpc-ids $vpc_id --region $AWS_REGION | jq -r '.Vpcs[0].CidrBlock')
    
    # 列出子網路
    echo -e "\n${YELLOW}VPC $vpc_id 中的子網路:${NC}"
    aws ec2 describe-subnets --filters "Name=vpc-id,Values=$vpc_id" --region $AWS_REGION | \
      jq -r '.Subnets[] | "子網路 ID: \(.SubnetId), 可用區: \(.AvailabilityZone), CIDR: \(.CidrBlock)"'
    
    read -p "請輸入要關聯的子網路 ID: " subnet_id
    
    # VPN CIDR 設定
    default_vpn_cidr="172.16.0.0/22"
    read -p "請輸入 VPN CIDR (預設: $default_vpn_cidr): " vpn_cidr
    vpn_cidr=${vpn_cidr:-$default_vpn_cidr}
    
    # VPN 端點名稱
    read -p "請輸入 VPN 端點名稱 (預設: Production-VPN): " vpn_name
    vpn_name=${vpn_name:-"Production-VPN"}
    
    # 創建 CloudWatch 日誌群組
    log_group_name="/aws/clientvpn/$vpn_name"
    echo -e "${BLUE}創建 CloudWatch 日誌群組...${NC}"
    aws logs create-log-group --log-group-name $log_group_name --region $AWS_REGION 2>/dev/null || true
    
    # 創建 Client VPN 端點
    echo -e "${BLUE}創建 Client VPN 端點...${NC}"
    endpoint_result=$(aws ec2 create-client-vpn-endpoint \
      --client-cidr-block $vpn_cidr \
      --server-certificate-arn $server_cert_arn \
      --authentication-options Type=certificate-authentication,MutualAuthentication={ClientRootCertificateChainArn=$client_cert_arn} \
      --connection-log-options Enabled=true,CloudwatchLogGroup=$log_group_name \
      --split-tunnel \
      --dns-servers 8.8.8.8 8.8.4.4 \
      --region $AWS_REGION \
      --tag-specifications "ResourceType=client-vpn-endpoint,Tags=[{Key=Name,Value=$vpn_name},{Key=Purpose,Value=ProductionDebug}]")
    
    endpoint_id=$(echo $endpoint_result | jq -r '.ClientVpnEndpointId')
    
    echo -e "${BLUE}端點 ID: $endpoint_id${NC}"
    
    # 等待端點可用
    echo -e "${BLUE}等待 VPN 端點可用...${NC}"
    aws ec2 wait client-vpn-endpoint-available --client-vpn-endpoint-id $endpoint_id --region $AWS_REGION
    
    # 關聯子網路
    echo -e "${BLUE}關聯子網路...${NC}"
    aws ec2 associate-client-vpn-target-network \
      --client-vpn-endpoint-id $endpoint_id \
      --subnet-id $subnet_id \
      --region $AWS_REGION
    
    # 添加授權規則
    echo -e "${BLUE}添加授權規則...${NC}"
    aws ec2 authorize-client-vpn-ingress \
      --client-vpn-endpoint-id $endpoint_id \
      --target-network-cidr $vpc_cidr \
      --authorize-all-groups \
      --region $AWS_REGION
    
    # 創建路由
    echo -e "${BLUE}創建路由...${NC}"
    aws ec2 create-client-vpn-route \
      --client-vpn-endpoint-id $endpoint_id \
      --destination-cidr-block "0.0.0.0/0" \
      --target-vpc-subnet-id $subnet_id \
      --region $AWS_REGION
    
    # 保存端點資訊
    echo "ENDPOINT_ID=$endpoint_id" >> $CONFIG_FILE
    echo "VPC_ID=$vpc_id" >> $CONFIG_FILE
    echo "VPC_CIDR=$vpc_cidr" >> $CONFIG_FILE
    echo "SUBNET_ID=$subnet_id" >> $CONFIG_FILE
    echo "VPN_CIDR=$vpn_cidr" >> $CONFIG_FILE
    echo "VPN_NAME=$vpn_name" >> $CONFIG_FILE
    echo "SERVER_CERT_ARN=$server_cert_arn" >> $CONFIG_FILE
    echo "CLIENT_CERT_ARN=$client_cert_arn" >> $CONFIG_FILE
    
    echo -e "${GREEN}VPN 端點建立完成！${NC}"
    echo -e "端點 ID: ${BLUE}$endpoint_id${NC}"
    
    log_message "VPN 端點已建立: $endpoint_id"
    
    # 生成管理員配置檔案
    generate_admin_config
    
    echo -e "\n${YELLOW}按任意鍵繼續...${NC}"
    read -n 1
}

# 生成管理員配置檔案
generate_admin_config() {
    echo -e "\n${BLUE}生成管理員配置檔案...${NC}"
    
    source $CONFIG_FILE
    
    # 下載配置
    mkdir -p "$SCRIPT_DIR/configs"
    aws ec2 export-client-vpn-client-configuration \
      --client-vpn-endpoint-id $ENDPOINT_ID \
      --region $AWS_REGION \
      --output text > "$SCRIPT_DIR/configs/admin-config-base.ovpn"
    
    # 修改配置文件
    cp "$SCRIPT_DIR/configs/admin-config-base.ovpn" "$SCRIPT_DIR/configs/admin-config.ovpn"
    echo "reneg-sec 0" >> "$SCRIPT_DIR/configs/admin-config.ovpn"
    
    # 生成管理員證書
    cert_dir="$SCRIPT_DIR/certificates"
    cd $cert_dir
    
    if [ ! -f "pki/issued/admin.crt" ]; then
        echo -e "${BLUE}生成管理員證書...${NC}"
        yes "" | easyrsa build-client-full admin nopass
    fi
    
    # 添加證書到配置文件
    echo "<cert>" >> "$SCRIPT_DIR/configs/admin-config.ovpn"
    cat $cert_dir/pki/issued/admin.crt >> "$SCRIPT_DIR/configs/admin-config.ovpn"
    echo "</cert>" >> "$SCRIPT_DIR/configs/admin-config.ovpn"
    
    echo "<key>" >> "$SCRIPT_DIR/configs/admin-config.ovpn"
    cat $cert_dir/pki/private/admin.key >> "$SCRIPT_DIR/configs/admin-config.ovpn"
    echo "</key>" >> "$SCRIPT_DIR/configs/admin-config.ovpn"
    
    echo -e "${GREEN}管理員配置檔案已生成: $SCRIPT_DIR/configs/admin-config.ovpn${NC}"
}

# 查看現有 VPN 端點
list_vpn_endpoints() {
    echo -e "\n${CYAN}=== 現有 VPN 端點 ===${NC}"
    
    source $CONFIG_FILE 2>/dev/null || { echo -e "${RED}未找到配置文件${NC}"; return; }
    
    endpoints=$(aws ec2 describe-client-vpn-endpoints --region $AWS_REGION)
    
    echo $endpoints | jq -r '.ClientVpnEndpoints[] | 
    "端點 ID: \(.ClientVpnEndpointId)
    狀態: \(.Status.Code)
    名稱: \(.Tags[]? | select(.Key=="Name") | .Value // "無名稱")
    CIDR: \(.ClientCidrBlock)
    DNS: \(.DnsName)
    創建時間: \(.CreationTime)
    ----------------------------------------"'
    
    echo -e "\n${YELLOW}按任意鍵繼續...${NC}"
    read -n 1
}

# 管理 VPN 端點設定
manage_vpn_settings() {
    echo -e "\n${CYAN}=== 管理 VPN 端點設定 ===${NC}"
    
    source $CONFIG_FILE 2>/dev/null || { echo -e "${RED}未找到配置文件${NC}"; return; }
    
    if [ -z "$ENDPOINT_ID" ]; then
        echo -e "${RED}未找到已配置的端點 ID${NC}"
        return
    fi
    
    echo -e "${BLUE}當前端點 ID: $ENDPOINT_ID${NC}"
    echo -e ""
    echo -e "管理選項："
    echo -e "  ${GREEN}1.${NC} 添加授權規則"
    echo -e "  ${GREEN}2.${NC} 移除授權規則"
    echo -e "  ${GREEN}3.${NC} 查看路由表"
    echo -e "  ${GREEN}4.${NC} 添加路由"
    echo -e "  ${GREEN}5.${NC} 查看關聯的網絡"
    echo -e "  ${GREEN}6.${NC} 關聯新子網路"
    echo -e "  ${GREEN}7.${NC} 返回主選單"
    
    read -p "請選擇操作 (1-7): " choice
    
    case $choice in
        1)
            read -p "請輸入要授權的 CIDR 範圍: " auth_cidr
            aws ec2 authorize-client-vpn-ingress \
              --client-vpn-endpoint-id $ENDPOINT_ID \
              --target-network-cidr $auth_cidr \
              --authorize-all-groups \
              --region $AWS_REGION
            echo -e "${GREEN}授權規則已添加${NC}"
            ;;
        2)
            # 列出現有授權規則
            aws ec2 describe-client-vpn-authorization-rules \
              --client-vpn-endpoint-id $ENDPOINT_ID \
              --region $AWS_REGION | jq -r '.AuthorizationRules[] | "CIDR: \(.DestinationCidr), 狀態: \(.Status.Code)"'
            
            read -p "請輸入要移除的 CIDR 範圍: " revoke_cidr
            aws ec2 revoke-client-vpn-ingress \
              --client-vpn-endpoint-id $ENDPOINT_ID \
              --target-network-cidr $revoke_cidr \
              --revoke-all-groups \
              --region $AWS_REGION
            echo -e "${GREEN}授權規則已移除${NC}"
            ;;
        3)
            echo -e "${BLUE}路由表:${NC}"
            aws ec2 describe-client-vpn-routes \
              --client-vpn-endpoint-id $ENDPOINT_ID \
              --region $AWS_REGION | jq -r '.Routes[] | "目標: \(.DestinationCidr), 狀態: \(.Status.Code), 來源: \(.Origin)"'
            ;;
        4)
            read -p "請輸入目標 CIDR: " dest_cidr
            read -p "請輸入目標子網路 ID: " target_subnet
            aws ec2 create-client-vpn-route \
              --client-vpn-endpoint-id $ENDPOINT_ID \
              --destination-cidr-block $dest_cidr \
              --target-vpc-subnet-id $target_subnet \
              --region $AWS_REGION
            echo -e "${GREEN}路由已添加${NC}"
            ;;
        5)
            echo -e "${BLUE}關聯的網絡:${NC}"
            aws ec2 describe-client-vpn-target-networks \
              --client-vpn-endpoint-id $ENDPOINT_ID \
              --region $AWS_REGION | jq -r '.ClientVpnTargetNetworks[] | "子網路 ID: \(.TargetNetworkId), 狀態: \(.Status.Code)"'
            ;;
        6)
            read -p "請輸入要關聯的子網路 ID: " new_subnet
            aws ec2 associate-client-vpn-target-network \
              --client-vpn-endpoint-id $ENDPOINT_ID \
              --subnet-id $new_subnet \
              --region $AWS_REGION
            echo -e "${GREEN}子網路已關聯${NC}"
            ;;
        7)
            return
            ;;
        *)
            echo -e "${RED}無效選擇${NC}"
            ;;
    esac
    
    echo -e "\n${YELLOW}按任意鍵繼續...${NC}"
    read -n 1
}

# 刪除 VPN 端點
delete_vpn_endpoint() {
    echo -e "\n${CYAN}=== 刪除 VPN 端點 ===${NC}"
    
    source $CONFIG_FILE 2>/dev/null || { echo -e "${RED}未找到配置文件${NC}"; return; }
    
    if [ -z "$ENDPOINT_ID" ]; then
        echo -e "${RED}未找到已配置的端點 ID${NC}"
        return
    fi
    
    echo -e "${RED}警告: 您即將刪除 VPN 端點 $ENDPOINT_ID${NC}"
    echo -e "${RED}此操作將會：${NC}"
    echo -e "${RED}  - 斷開所有用戶連接${NC}"
    echo -e "${RED}  - 刪除所有路由和授權規則${NC}"
    echo -e "${RED}  - 無法復原${NC}"
    
    read -p "確認刪除? 請輸入 'DELETE' 來確認: " confirm
    
    if [ "$confirm" != "DELETE" ]; then
        echo -e "${BLUE}刪除操作已取消${NC}"
        return
    fi
    
    echo -e "${BLUE}正在刪除 VPN 端點...${NC}"
    
    # 解除關聯的網絡
    target_networks=$(aws ec2 describe-client-vpn-target-networks \
      --client-vpn-endpoint-id $ENDPOINT_ID \
      --region $AWS_REGION | jq -r '.ClientVpnTargetNetworks[].AssociationId')
    
    for association_id in $target_networks; do
        echo -e "${BLUE}解除關聯 $association_id...${NC}"
        aws ec2 disassociate-client-vpn-target-network \
          --client-vpn-endpoint-id $ENDPOINT_ID \
          --association-id $association_id \
          --region $AWS_REGION
        
        # 等待解除關聯完成
        aws ec2 wait client-vpn-target-network-disassociated \
          --client-vpn-endpoint-id $ENDPOINT_ID \
          --association-id $association_id \
          --region $AWS_REGION
    done
    
    # 刪除端點
    aws ec2 delete-client-vpn-endpoint \
      --client-vpn-endpoint-id $ENDPOINT_ID \
      --region $AWS_REGION
    
    # 刪除證書
    if [ ! -z "$SERVER_CERT_ARN" ]; then
        echo -e "${BLUE}刪除伺服器證書...${NC}"
        aws acm delete-certificate --certificate-arn $SERVER_CERT_ARN --region $AWS_REGION 2>/dev/null || true
    fi
    
    if [ ! -z "$CLIENT_CERT_ARN" ]; then
        echo -e "${BLUE}刪除客戶端證書...${NC}"
        aws acm delete-certificate --certificate-arn $CLIENT_CERT_ARN --region $AWS_REGION 2>/dev/null || true
    fi
    
    # 刪除 CloudWatch 日誌群組
    if [ ! -z "$VPN_NAME" ]; then
        log_group_name="/aws/clientvpn/$VPN_NAME"
        echo -e "${BLUE}刪除 CloudWatch 日誌群組...${NC}"
        aws logs delete-log-group --log-group-name $log_group_name --region $AWS_REGION 2>/dev/null || true
    fi
    
    # 清理配置文件
    > $CONFIG_FILE
    
    echo -e "${GREEN}VPN 端點已完全刪除${NC}"
    log_message "VPN 端點已刪除: $ENDPOINT_ID"
    
    echo -e "\n${YELLOW}按任意鍵繼續...${NC}"
    read -n 1
}

# 查看連接日誌
view_connection_logs() {
    echo -e "\n${CYAN}=== 查看連接日誌 ===${NC}"
    
    source $CONFIG_FILE 2>/dev/null || { echo -e "${RED}未找到配置文件${NC}"; return; }
    
    if [ -z "$VPN_NAME" ]; then
        echo -e "${RED}未找到 VPN 名稱${NC}"
        return
    fi
    
    log_group_name="/aws/clientvpn/$VPN_NAME"
    
    echo -e "${BLUE}查看最近的連接日誌...${NC}"
    
    # 獲取最近 1 小時的日誌
    start_time=$(date -u -d '1 hour ago' +%s)000
    end_time=$(date -u +%s)000
    
    aws logs filter-log-events \
      --log-group-name $log_group_name \
      --start-time $start_time \
      --end-time $end_time \
      --region $AWS_REGION | jq -r '.events[] | "\(.timestamp | strftime("%Y-%m-%d %H:%M:%S")): \(.message)"' | tail -20
    
    echo -e "\n${YELLOW}按任意鍵繼續...${NC}"
    read -n 1
}

# 匯出團隊成員設定檔
export_team_config() {
    echo -e "\n${CYAN}=== 匯出團隊成員設定檔 ===${NC}"
    
    source $CONFIG_FILE 2>/dev/null || { echo -e "${RED}未找到配置文件${NC}"; return; }
    
    if [ -z "$ENDPOINT_ID" ]; then
        echo -e "${RED}未找到端點 ID${NC}"
        return
    fi
    
    # 下載基本配置
    mkdir -p "$SCRIPT_DIR/team-configs"
    aws ec2 export-client-vpn-client-configuration \
      --client-vpn-endpoint-id $ENDPOINT_ID \
      --region $AWS_REGION \
      --output text > "$SCRIPT_DIR/team-configs/team-config-base.ovpn"
    
    # 複製 CA 證書到 team-configs 目錄
    cp "$SCRIPT_DIR/certificates/pki/ca.crt" "$SCRIPT_DIR/team-configs/"
    cp "$SCRIPT_DIR/certificates/pki/private/ca.key" "$SCRIPT_DIR/team-configs/"
    
    # 創建團隊成員資訊文件
    cat > "$SCRIPT_DIR/team-configs/team-setup-info.txt" << EOF
=== AWS Client VPN 團隊設定資訊 ===

VPN 端點 ID: $ENDPOINT_ID
AWS 區域: $AWS_REGION
VPN CIDR: $VPN_CIDR
VPC ID: $VPC_ID
VPC CIDR: $VPC_CIDR

設定檔案：
- team-config-base.ovpn: 基本 VPN 配置檔案
- ca.crt: CA 證書文件
- ca.key: CA 私鑰文件 (請安全保管)

使用說明：
1. 向新團隊成員提供 team_member_setup.sh 腳本
2. 提供上述端點 ID 和 ca.crt 文件
3. 不要分享 ca.key 文件，只給負責生成證書的管理員

生成時間: $(date)
EOF
    
    echo -e "${GREEN}團隊設定檔已匯出到 $SCRIPT_DIR/team-configs/${NC}"
    echo -e "${BLUE}請將以下檔案提供給團隊成員：${NC}"
    echo -e "  - team_member_setup.sh (團隊成員設定腳本)"
    echo -e "  - ca.crt (CA 證書)"
    echo -e "  - 端點 ID: $ENDPOINT_ID"
    
    echo -e "\n${YELLOW}按任意鍵繼續...${NC}"
    read -n 1
}

# 系統健康檢查
system_health_check() {
    echo -e "\n${CYAN}=== 系統健康檢查 ===${NC}"
    
    source $CONFIG_FILE 2>/dev/null || { echo -e "${RED}未找到配置文件${NC}"; return; }
    
    if [ -z "$ENDPOINT_ID" ]; then
        echo -e "${RED}未找到端點 ID${NC}"
        return
    fi
    
    echo -e "${BLUE}檢查 VPN 端點狀態...${NC}"
    endpoint_status=$(aws ec2 describe-client-vpn-endpoints \
      --client-vpn-endpoint-ids $ENDPOINT_ID \
      --region $AWS_REGION | jq -r '.ClientVpnEndpoints[0].Status.Code')
    
    if [ "$endpoint_status" == "available" ]; then
        echo -e "${GREEN}✓ VPN 端點狀態: 可用${NC}"
    else
        echo -e "${RED}✗ VPN 端點狀態: $endpoint_status${NC}"
    fi
    
    echo -e "${BLUE}檢查關聯的網絡...${NC}"
    network_count=$(aws ec2 describe-client-vpn-target-networks \
      --client-vpn-endpoint-id $ENDPOINT_ID \
      --region $AWS_REGION | jq '.ClientVpnTargetNetworks | length')
    
    echo -e "${GREEN}✓ 關聯的網絡數量: $network_count${NC}"
    
    echo -e "${BLUE}檢查授權規則...${NC}"
    auth_count=$(aws ec2 describe-client-vpn-authorization-rules \
      --client-vpn-endpoint-id $ENDPOINT_ID \
      --region $AWS_REGION | jq '.AuthorizationRules | length')
    
    echo -e "${GREEN}✓ 授權規則數量: $auth_count${NC}"
    
    echo -e "${BLUE}檢查連接統計...${NC}"
    connections=$(aws ec2 describe-client-vpn-connections \
      --client-vpn-endpoint-id $ENDPOINT_ID \
      --region $AWS_REGION | jq '.Connections | length')
    
    echo -e "${GREEN}✓ 目前連接數: $connections${NC}"
    
    echo -e "${BLUE}檢查證書狀態...${NC}"
    if [ ! -z "$SERVER_CERT_ARN" ]; then
        cert_status=$(aws acm describe-certificate \
          --certificate-arn $SERVER_CERT_ARN \
          --region $AWS_REGION | jq -r '.Certificate.Status')
        echo -e "${GREEN}✓ 伺服器證書狀態: $cert_status${NC}"
    fi
    
    echo -e "\n${YELLOW}按任意鍵繼續...${NC}"
    read -n 1
}

# 顯示管理員指南
show_admin_guide() {
    echo -e "\n${CYAN}=== 管理員指南 ===${NC}"
    echo -e ""
    echo -e "${BLUE}1. 建立 VPN 端點後的步驟：${NC}"
    echo -e "   - 確認端點狀態為 'available'"
    echo -e "   - 測試管理員配置檔案連接"
    echo -e "   - 匯出團隊成員設定檔"
    echo -e ""
    echo -e "${BLUE}2. 管理團隊成員：${NC}"
    echo -e "   - 使用 team_member_setup.sh 讓新成員加入"
    echo -e "   - 使用 revoke_member_access.sh 撤銷訪問權限"
    echo -e "   - 使用 employee_offboarding.sh 處理離職人員"
    echo -e ""
    echo -e "${BLUE}3. 安全最佳實踐：${NC}"
    echo -e "   - 定期檢查連接日誌"
    echo -e "   - 為每個用戶創建獨立證書"
    echo -e "   - 實施最小權限原則"
    echo -e "   - 定期輪換證書"
    echo -e ""
    echo -e "${BLUE}4. 故障排除：${NC}"
    echo -e "   - 檢查端點和網絡關聯狀態"
    echo -e "   - 查看 CloudWatch 日誌"
    echo -e "   - 驗證授權規則設定"
    echo -e ""
    echo -e "${BLUE}5. 備份和恢復：${NC}"
    echo -e "   - 定期備份證書文件"
    echo -e "   - 記錄所有配置參數"
    echo -e "   - 保存端點設定資訊"
    
    echo -e "\n${YELLOW}按任意鍵繼續...${NC}"
    read -n 1
}

# 主函數
main() {
    # 檢查必要工具
    check_prerequisites
    
    # 確保有配置
    if [ ! -f $CONFIG_FILE ]; then
        setup_aws_config
    fi
    
    # 主循環
    while true; do
        show_menu
        read -p "請選擇操作 (1-9): " choice
        
        case $choice in
            1)
                create_vpn_endpoint
                ;;
            2)
                list_vpn_endpoints
                ;;
            3)
                manage_vpn_settings
                ;;
            4)
                delete_vpn_endpoint
                ;;
            5)
                view_connection_logs
                ;;
            6)
                export_team_config
                ;;
            7)
                show_admin_guide
                ;;
            8)
                system_health_check
                ;;
            9)
                echo -e "\n${GREEN}感謝使用 AWS VPN 管理工具！${NC}"
                log_message "管理工具已退出"
                exit 0
                ;;
            *)
                echo -e "${RED}無效選擇，請重新選擇${NC}"
                sleep 1
                ;;
        esac
    done
}

# 記錄腳本啟動
log_message "AWS VPN 管理工具已啟動"

# 執行主程序
main