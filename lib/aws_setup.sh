#!/bin/bash

# 載入核心函式庫以使用顏色和日誌
source "$(dirname "${BASH_SOURCE[0]}")/core_functions.sh"

# 設定 AWS 配置 (已棄用，建議使用 configure_aws_cli_lib)
# 需要主腳本傳遞 CONFIG_FILE 變數
setup_aws_config() {
    local main_config_file="$1" # 接收主腳本的 CONFIG_FILE 路徑

    echo -e "\\n${YELLOW}設定 AWS 配置...${NC}"
    
    if [ ! -f ~/.aws/credentials ] || [ ! -f ~/.aws/config ]; then
        echo -e "${YELLOW}請提供您的 AWS 管理員帳戶資訊：${NC}"
        
        local aws_access_key
        local aws_secret_key  
        local aws_region
        
        # 使用安全輸入驗證
        read_secure_input "請輸入 AWS Access Key ID: " aws_access_key "validate_aws_access_key_id" || return 1
        
        # 為敏感資料使用特殊處理
        echo -n "請輸入 AWS Secret Access Key: "
        read -s aws_secret_key
        echo
        if ! validate_aws_secret_access_key "$aws_secret_key"; then
            return 1
        fi
        
        read_secure_input "請輸入 AWS 區域 (例如 ap-northeast-1): " aws_region "validate_aws_region" || return 1
        
        # 創建配置目錄和文件
        mkdir -p ~/.aws
        
        # 寫入認證
        cat > ~/.aws/credentials << EOF
[default]
aws_access_key_id = ${aws_access_key}
aws_secret_access_key = ${aws_secret_key}
EOF
        
        # 寫入配置
        cat > ~/.aws/config << EOF
[default]
region = ${aws_region}
output = json
EOF
        
        echo -e "${BLUE}正在驗證 AWS 憑證...${NC}"
        if aws sts get-caller-identity --output text --query 'Arn' > /dev/null 2>&1; then
            echo -e "${GREEN}AWS 憑證驗證成功！${NC}"
            log_message_core "AWS 憑證驗證成功。"
            echo -e "${GREEN}AWS 配置已完成！${NC}"
        else
            log_message_core "AWS 憑證驗證失敗。"
            # 使用 core_functions.sh 中的 handle_error
            # 注意：handle_error 預設會退出腳本。如果不想退出，需要傳遞第三個參數 0。
            # 在設定階段，如果憑證無效，退出可能是合理的。
            handle_error "AWS 憑證無效或權限不足。請檢查您輸入的 Access Key ID、Secret Access Key 和區域是否正確，以及帳戶是否具有必要的權限。" "$?" 1
            # 如果 handle_error 終止了腳本，以下程式碼將不會執行
            # 如果選擇不終止，則需要額外的邏輯讓使用者重試或接受風險
            echo -e "${RED}AWS 配置失敗，憑證驗證未通過。${NC}"
            return 1 # 表示設定失敗
        fi
    else
        echo -e "${GREEN}✓ AWS 配置檔案已存在。${NC}"
        # 即使檔案存在，也嘗試獲取當前 region
        # 如果 aws configure get region 失敗，可能表示配置不完整或 aws cli 有問題
        current_region=$(aws configure get region 2>/dev/null)
        if [ -n "$current_region" ]; then
            aws_region="$current_region"
            echo -e "${BLUE}當前 AWS 區域設定為: ${aws_region}${NC}"
            # 建議：即使檔案存在，也應該提供一個選項來驗證憑證，或至少提示使用者憑證的有效性未在此處驗證
            # 根據第一階段計劃，暫不修改此處邏輯，但標記為未來改進
            # TODO: Offer to validate/update existing AWS credentials
        else
            # 如果無法獲取 region，可能需要重新設定
            log_message_core "警告：無法從現有 AWS 配置中獲取區域。可能需要重新設定。"
            echo -e "${YELLOW}警告：無法從現有 AWS 配置中獲取區域。建議檢查 ~/.aws/config 或重新執行設定。${NC}"
            # 這裡可以選擇提示使用者重新設定，或者直接使用一個預設值/空值，然後依賴 validate_main_config 捕捉
            # 為了安全起見，如果無法獲取 region，則不應盲目寫入 main_config_file
            # 可以讓使用者手動處理或在主腳本中提示
            echo -e "${RED}無法自動確定 AWS 區域。請手動檢查或重新執行設定。${NC}"
            return 1 # 表示設定不完整
        fi
    fi
    
    # 只有在成功獲取或設定 aws_region 後才保存
    if [ -n "$aws_region" ]; then
        echo "AWS_REGION=${aws_region}" > "$main_config_file"
        # Bug fix item 6: Add missing config variables
        local main_script_dir
        main_script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" # SCRIPT_DIR of the script calling this lib function
        echo "EASYRSA_DIR=/usr/local/share/easy-rsa" >> "$main_config_file"
        echo "CERT_OUTPUT_DIR=${main_script_dir}/certificates" >> "$main_config_file"
        echo "SERVER_CERT_NAME_PREFIX=server" >> "$main_config_file"
        echo "CLIENT_CERT_NAME_PREFIX=client" >> "$main_config_file"
        log_message_core "AWS 配置已更新，區域: ${aws_region} 及其他預設配置。"
    else
        log_message_core "錯誤：AWS 區域未能成功設定或獲取。"
        # 此情況應已被上面的 return 1 處理
    fi
}

# 檢查 AWS CLI 是否已安裝 (庫函式版本)
check_aws_cli_lib() {
    log_message_core "開始檢查 AWS CLI 是否已安裝 (lib)"
    if ! command -v aws &> /dev/null; then
        echo -e "${RED}錯誤: AWS CLI 未安裝或未在 PATH 中。請先安裝並配置 AWS CLI。${NC}"
        log_message_core "錯誤: AWS CLI 未安裝"
        return 1
    fi
    echo -e "${GREEN}AWS CLI 已安裝。${NC}"
    log_message_core "AWS CLI 已安裝"
    return 0
}

# 設定 AWS CLI 配置 (庫函式版本)
# 參數: $1 = AWS_ACCESS_KEY_ID, $2 = AWS_SECRET_ACCESS_KEY, $3 = AWS_REGION
configure_aws_cli_lib() {
    local aws_access_key_id="$1"
    local aws_secret_access_key="$2"
    local aws_region="$3"

    log_message_core "開始設定 AWS CLI 配置 (lib)"

    # 使用 read_secure_input 獲取敏感資訊
    if [ -z "$aws_access_key_id" ]; then
        read_secure_input "請輸入 AWS Access Key ID: " aws_access_key_id "validate_aws_access_key_id" || return 1 # 假設有 validate_aws_access_key_id
    fi
    if [ -z "$aws_secret_access_key" ]; then
        read_secure_input "請輸入 AWS Secret Access Key: " aws_secret_access_key "validate_aws_secret_access_key" || return 1 # 假設有 validate_aws_secret_access_key
    fi
    if [ -z "$aws_region" ]; then
        read_secure_input "請輸入 AWS 區域 (例如 us-east-1): " aws_region "validate_aws_region" || return 1
    fi

    echo -e "${BLUE}設定 AWS CLI 配置...${NC}"
    aws configure set aws_access_key_id "$aws_access_key_id"
    aws configure set aws_secret_access_key "$aws_secret_access_key"
    aws configure set default.region "$aws_region"
    aws configure set default.output json

    if [ $? -eq 0 ]; then
        echo -e "${GREEN}AWS CLI 配置成功。${NC}"
        log_message_core "AWS CLI 配置成功"
        return 0
    else
        echo -e "${RED}錯誤: AWS CLI 配置失敗。${NC}"
        log_message_core "錯誤: AWS CLI 配置失敗"
        return 1
    fi
}

# 選擇 VPC 和子網路 (庫函式版本)
# 參數: $1 = AWS_REGION, $2 = CONFIG_FILE
select_vpc_subnet_lib() {
    local aws_region="$1"
    local config_file="$2"

    # 參數驗證
    if ! validate_aws_region "$aws_region"; then
        # validate_aws_region 應已處理錯誤記錄和輸出
        return 1
    fi

    if [ -z "$config_file" ]; then
        echo -e "${RED}錯誤: 配置文件路徑為空${NC}"
        log_message_core "錯誤: select_vpc_subnet_lib 調用時配置文件路徑為空"
        return 1
    fi

    log_message_core "開始選擇 VPC 和子網路 (lib) - Region: $aws_region"

    echo -e "${BLUE}正在檢索 VPC 列表...${NC}"
    local vpcs
vpcs=$(aws ec2 describe-vpcs --region "$aws_region" --query "Vpcs[*].{ID:VpcId,Name:Tags[?Key=='Name']|[0].Value}" --output text)
    if [ $? -ne 0 ] || [ -z "$vpcs" ]; then
        echo -e "${RED}錯誤: 無法檢索 VPC 列表，或該區域沒有 VPC。${NC}"
        log_message_core "錯誤: select_vpc_subnet_lib - 無法檢索 VPC 列表或無 VPC。 Region: $aws_region"
        return 1
    fi

    echo -e "${CYAN}可用的 VPCs:${NC}"
    echo "$vpcs"
    echo "------------------------------------"

    local selected_vpc_id
    read_secure_input "請輸入要使用的 VPC ID: " selected_vpc_id "validate_vpc_id" || return 1

    echo -e "${BLUE}正在檢索子網路列表 (VPC: $selected_vpc_id)...${NC}"
    local subnets
subnets=$(aws ec2 describe-subnets --region "$aws_region" --filters "Name=vpc-id,Values=$selected_vpc_id" --query "Subnets[*].{ID:SubnetId,AZ:AvailabilityZone,CIDR:CidrBlock,Name:Tags[?Key=='Name']|[0].Value}" --output text)
    if [ $? -ne 0 ] || [ -z "$subnets" ]; then
        echo -e "${RED}錯誤: 無法檢索子網路列表，或該 VPC 沒有子網路。${NC}"
        log_message_core "錯誤: select_vpc_subnet_lib - 無法檢索子網路列表或無子網路。VPC ID: $selected_vpc_id"
        return 1
    fi

    echo -e "${CYAN}VPC '$selected_vpc_id' 中可用的子網路:${NC}"
    echo "$subnets"
    echo "------------------------------------"

    local client_subnet_id
    local server_subnet_id

    read_secure_input "請輸入 Client VPN 的子網路 ID: " client_subnet_id "validate_subnet_id" || return 1
    read_secure_input "請輸入 Server (EC2) 的子網路 ID (通常與 Client VPN 子網路相同或在同一 VPC): " server_subnet_id "validate_subnet_id" || return 1

    # 將選擇的 VPC 和子網路 ID 寫入配置文件
    echo "VPC_ID='${selected_vpc_id}'" >> "$config_file"
    echo "CLIENT_VPN_SUBNET_ID='${client_subnet_id}'" >> "$config_file"
    echo "SERVER_EC2_SUBNET_ID='${server_subnet_id}'" >> "$config_file"

    echo -e "${GREEN}VPC 和子網路選擇已保存到 '$config_file'${NC}"
    log_message_core "VPC 和子網路選擇已保存到 '$config_file' (VPC: $selected_vpc_id, ClientSubnet: $client_subnet_id, ServerSubnet: $server_subnet_id)"
    return 0
}
