#!/bin/bash

# lib/cert_management.sh
# 憑證管理相關函式庫
# 包含 Easy-RSA 初始化、CA/伺服器/客戶端憑證生成、憑證匯入 AWS ACM 等功能

# 確保已載入核心函式
if [ -z "$LOG_FILE_CORE" ]; then
    echo "錯誤: 核心函式庫未載入。請先載入 core_functions.sh"
    exit 1
fi

# 初始化 Easy-RSA 環境 (庫函式版本)
# 參數: $1 = SCRIPT_DIR, $2 = EASYRSA_DIR
initialize_easyrsa_lib() {
    local script_dir="$1"
    local easyrsa_dir="$2"

    # 參數驗證
    if [ -z "$script_dir" ] || [ ! -d "$script_dir" ]; then
        echo -e "${RED}錯誤: 腳本目錄參數無效${NC}"
        log_message_core "錯誤: initialize_easyrsa_lib 調用時腳本目錄參數無效: $script_dir"
        return 1
    fi
    if [ -z "$easyrsa_dir" ]; then # 不檢查目錄是否存在，因為此函式會創建它
        echo -e "${RED}錯誤: EasyRSA 目錄參數為空${NC}"
        log_message_core "錯誤: initialize_easyrsa_lib 調用時 EasyRSA 目錄參數為空"
        return 1
    fi

    log_message_core "開始初始化 Easy-RSA 環境 (lib) - 目標目錄: $easyrsa_dir"

    # 創建 EasyRSA 目錄
    mkdir -p "$easyrsa_dir"

    # 複製 Easy-RSA 檔案
    cp -r "$script_dir/easy-rsa/*" "$easyrsa_dir"

    # 設置權限
    chmod -R 700 "$easyrsa_dir"

    log_message_core "Easy-RSA 環境初始化完成於 $easyrsa_dir"
    return 0
}

# 生成 CA 憑證 (庫函式版本)
# 參數: $1 = EASYRSA_DIR, $2 = CA_NAME (可選, 預設 "NL-VPN-CA")
generate_ca_certificate_lib() {
    local easyrsa_dir="$1"
    local ca_name="${2:-NL-VPN-CA}" # 如果 $2 未提供或為空，則使用預設值

    # 參數驗證
    if [ -z "$easyrsa_dir" ] || [ ! -d "$easyrsa_dir/pki" ]; then # 檢查 pki 是否存在，表示已初始化
        echo -e "${RED}錯誤: EasyRSA 目錄未初始化或無效${NC}"
        log_message_core "錯誤: generate_ca_certificate_lib 調用時 EasyRSA 目錄未初始化或無效: $easyrsa_dir"
        return 1
    fi
    if ! validate_username "$ca_name"; then # 使用 validate_username 進行基本名稱驗證
        log_message_core "錯誤: generate_ca_certificate_lib - CA 名稱無效: '$ca_name'"
        # validate_username 應已處理特定錯誤的記錄和輸出
        return 1
    fi

    log_message_core "開始生成 CA 憑證 (lib) - CA 名稱: $ca_name, EasyRSA 目錄: $easyrsa_dir"

    # 生成 CA 證書
    if [ ! -f "$easyrsa_dir/pki/ca.crt" ]; then
        echo -e "${BLUE}生成 CA 證書...${NC}"
        if ! (yes "" | "$easyrsa_dir/easyrsa" --batch build-ca nopass); then
            handle_error "生成 CA 證書失敗。" "$?" 1
        fi
        # 驗證 CA 檔案是否已生成
        if [ ! -f "$easyrsa_dir/pki/ca.crt" ] || [ ! -f "$easyrsa_dir/pki/private/ca.key" ]; then
            handle_error "CA 證書 (pki/ca.crt 或 pki/private/ca.key) 生成後未找到。" "" 1
        fi
        echo -e "${GREEN}CA 證書生成成功。${NC}"
    else
        echo -e "${YELLOW}CA 證書 (pki/ca.crt) 已存在。${NC}"
    fi

    # 更新配置文件中的 CA ARN
    echo "CA_CERT_ARN='$(aws acm import-certificate --certificate fileb://$easyrsa_dir/pki/ca.crt --private-key fileb://$easyrsa_dir/pki/private/ca.key --region $AWS_REGION --output text --query CertificateArn)'" >> "$script_dir/vpn_config"
    log_message_core "CA 憑證 ARN 已更新到配置文件: $script_dir/vpn_config"

    echo -e "${GREEN}CA 憑證生成流程完成！${NC}"
    log_message "VPN CA 證書已生成"

    return 0
}

# 生成伺服器憑證 (庫函式版本)
# 參數: $1 = EASYRSA_DIR, $2 = SERVER_NAME (可選, 預設 "server")
generate_server_certificate_lib() {
    local easyrsa_dir="$1"
    local server_name="${2:-server}"

    # 參數驗證
    if [ -z "$easyrsa_dir" ] || [ ! -d "$easyrsa_dir/pki" ]; then
        echo -e "${RED}錯誤: EasyRSA 目錄未初始化或無效${NC}"
        log_message_core "錯誤: generate_server_certificate_lib 調用時 EasyRSA 目錄未初始化或無效: $easyrsa_dir"
        return 1
    fi
    if ! validate_username "$server_name"; then # 使用 validate_username 進行基本名稱驗證
        log_message_core "錯誤: generate_server_certificate_lib - 伺服器名稱無效: '$server_name'"
        return 1
    fi

    log_message_core "開始生成伺服器憑證 (lib) - 名稱: $server_name, 目錄: $easyrsa_dir"

    # 生成伺服器證書
    if [ ! -f "$easyrsa_dir/pki/issued/server.crt" ]; then
        echo -e "${BLUE}生成伺服器證書...${NC}"
        # 檢查 CA 證書是否存在
        if [ ! -f "$easyrsa_dir/pki/ca.crt" ] || [ ! -f "$easyrsa_dir/pki/private/ca.key" ]; then
            handle_error "無法生成伺服器證書，因為 CA 證書 (pki/ca.crt 或 pki/private/ca.key) 不存在。" "" 1
        fi
        if ! (yes "" | "$easyrsa_dir/easyrsa" --batch build-server-full server nopass); then
            handle_error "生成伺服器證書失敗。" "$?" 1
        fi
        # 驗證伺服器證書檔案是否已生成
        if [ ! -f "$easyrsa_dir/pki/issued/server.crt" ] || [ ! -f "$easyrsa_dir/pki/private/server.key" ]; then
            handle_error "伺服器證書 (pki/issued/server.crt 或 pki/private/server.key) 生成後未找到。" "" 1
        fi
        echo -e "${GREEN}伺服器證書生成成功。${NC}"
    else
        echo -e "${YELLOW}伺服器證書 (pki/issued/server.crt) 已存在。${NC}"
    fi

    # 更新配置文件中的伺服器憑證 ARN
    echo "SERVER_CERT_ARN='$(aws acm import-certificate --certificate fileb://$easyrsa_dir/pki/issued/server.crt --private-key fileb://$easyrsa_dir/pki/private/server.key --certificate-chain fileb://$easyrsa_dir/pki/ca.crt --region $AWS_REGION --output text --query CertificateArn)'" >> "$script_dir/vpn_config"
    log_message_core "伺服器憑證 ARN 已更新到配置文件: $script_dir/vpn_config"

    echo -e "${GREEN}伺服器憑證生成流程完成！${NC}"
    log_message "VPN 伺服器證書已生成"

    return 0
}

# 生成客戶端憑證 (庫函式版本)
# 參數: $1 = EASYRSA_DIR, $2 = CLIENT_NAME
generate_client_certificate_lib() {
    local easyrsa_dir="$1"
    local client_name="$2"

    # 參數驗證
    if [ -z "$easyrsa_dir" ] || [ ! -d "$easyrsa_dir/pki" ]; then
        echo -e "${RED}錯誤: EasyRSA 目錄未初始化或無效${NC}"
        log_message_core "錯誤: generate_client_certificate_lib 調用時 EasyRSA 目錄未初始化或無效: $easyrsa_dir"
        return 1
    fi
    
    # 使用 read_secure_input 和 validate_username 獲取和驗證客戶端名稱
    if [ -z "$client_name" ]; then
        read_secure_input "請輸入客戶端憑證名稱 (例如: team_member_A): " client_name "validate_username" || return 1
    elif ! validate_username "$client_name"; then
        log_message_core "錯誤: generate_client_certificate_lib - 提供的客戶端名稱無效: '$client_name'"
        return 1
    fi

    log_message_core "開始生成客戶端憑證 (lib) - 名稱: $client_name, 目錄: $easyrsa_dir"

    # 生成客戶端證書
    if [ ! -f "$easyrsa_dir/pki/issued/$client_name.crt" ]; then
        echo -e "${BLUE}生成客戶端證書...${NC}"
        # 檢查 CA 證書是否存在
        if [ ! -f "$easyrsa_dir/pki/ca.crt" ] || [ ! -f "$easyrsa_dir/pki/private/ca.key" ]; then
            handle_error "無法生成客戶端證書，因為 CA 證書 (pki/ca.crt 或 pki/private/ca.key) 不存在。" "" 1
        fi
        if ! (yes "" | "$easyrsa_dir/easyrsa" --batch build-client-full "$client_name" nopass); then
            handle_error "生成客戶端證書失敗。" "$?" 1
        fi
        # 驗證客戶端證書檔案是否已生成
        if [ ! -f "$easyrsa_dir/pki/issued/$client_name.crt" ] || [ ! -f "$easyrsa_dir/pki/private/$client_name.key" ]; then
            handle_error "客戶端證書 (pki/issued/$client_name.crt 或 pki/private/$client_name.key) 生成後未找到。" "" 1
        fi
        echo -e "${GREEN}客戶端證書生成成功。${NC}"
    else
        echo -e "${YELLOW}客戶端證書 (pki/issued/$client_name.crt) 已存在。${NC}"
    fi

    # 更新配置文件中的客戶端憑證 ARN
    echo "CLIENT_CERT_ARN_${client_name}='$(aws acm import-certificate --certificate fileb://$easyrsa_dir/pki/issued/$client_name.crt --private-key fileb://$easyrsa_dir/pki/private/$client_name.key --region $AWS_REGION --output text --query CertificateArn)'" >> "$script_dir/vpn_config"
    log_message_core "客戶端憑證 ARN 已更新到配置文件: $script_dir/vpn_config"

    echo -e "${GREEN}客戶端憑證生成流程完成！${NC}"
    log_message "VPN 客戶端證書已生成"

    return 0
}

# 匯入憑證到 AWS ACM (庫函式版本)
# 參數: $1 = EASYRSA_DIR, $2 = CERT_TYPE ("server" 或 "client"), $3 = CERT_NAME, $4 = AWS_REGION, $5 = CONFIG_FILE
import_certificate_to_acm_lib() {
    local easyrsa_dir="$1"
    local cert_type="$2"
    local cert_name="$3"
    local aws_region="$4"
    local config_file="$5"

    # 參數驗證
    if [ -z "$easyrsa_dir" ] || [ ! -d "$easyrsa_dir/pki" ]; then
        echo -e "${RED}錯誤: EasyRSA 目錄未初始化或無效${NC}"
        log_message_core "錯誤: import_certificate_to_acm_lib - EasyRSA 目錄無效: $easyrsa_dir"
        return 1
    fi
    if [[ "$cert_type" != "server" && "$cert_type" != "client" ]]; then
        echo -e "${RED}錯誤: 憑證類型參數無效，必須是 'server' 或 'client'${NC}"
        log_message_core "錯誤: import_certificate_to_acm_lib - 憑證類型無效: $cert_type"
        return 1
    fi
    if ! validate_username "$cert_name"; then # 假設 cert_name 遵循 username 格式
        log_message_core "錯誤: import_certificate_to_acm_lib - 憑證名稱無效: '$cert_name'"
        return 1
    fi
    if ! validate_aws_region "$aws_region"; then
        return 1
    fi
    if [ -z "$config_file" ] || [ ! -f "$config_file" ]; then
        echo -e "${RED}錯誤: 配置文件不存在${NC}"
        log_message_core "錯誤: import_certificate_to_acm_lib - 配置文件不存在: $config_file"
        return 1
    fi

    log_message_core "開始匯入 $cert_type 憑證 '$cert_name' 到 AWS ACM (lib) - Region: $aws_region"

    local cert_file="$easyrsa_dir/pki/issued/$cert_name.crt"
    local key_file="$easyrsa_dir/pki/private/$cert_name.key"
    local ca_cert_file="$easyrsa_dir/pki/ca.crt"

    # 檢查憑證檔案
    if [ ! -f "$cert_file" ]; then
        handle_error "憑證檔案 ($cert_file) 不存在，無法匯入 ACM。" "" 1
    fi
    if [ ! -f "$key_file" ]; then
        handle_error "私鑰檔案 ($key_file) 不存在，無法匯入 ACM。" "" 1
    fi
    if [ "$cert_type" == "server" ] && [ ! -f "$ca_cert_file" ]; then
        handle_error "CA 證書檔案 ($ca_cert_file) 不存在（作為伺服器證書鏈），無法匯入 ACM。" "" 1
    fi

    local import_output
    local cert_arn

    if [ "$cert_type" == "server" ]; then
        echo -e "${BLUE}正在導入伺服器證書 (server.crt) 到 ACM...${NC}"
        import_output=$(aws acm import-certificate \\
          --certificate "fileb://$cert_file" \\
          --private-key "fileb://$key_file" \\
          --certificate-chain "fileb://$ca_cert_file" \\
          --region "$aws_region" \\
          --tags Key=Name,Value="VPN-Server-Cert-${SERVER_CERT_NAME_PREFIX:-default}" Key=Purpose,Value="ClientVPN" Key=ManagedBy,Value="nlInc-vpnMgmtTools" 2>&1)
    else
        echo -e "${BLUE}正在導入客戶端 CA 證書 (ca.crt) 到 ACM...${NC}"
        import_output=$(aws acm import-certificate \\
          --certificate "fileb://$cert_file" \\
          --private-key "fileb://$key_file" \\
          --region "$aws_region" \\
          --tags Key=Name,Value="VPN-Client-CA-${SERVER_CERT_NAME_PREFIX:-default}" Key=Purpose,Value="ClientVPN" Key=ManagedBy,Value="nlInc-vpnMgmtTools" 2>&1)
    fi

    local import_status=$?

    if [ $import_status -ne 0 ] || ! cert_arn=$(echo "$import_output" | jq -r '.CertificateArn'); then
        # jq 可能因為 import_output 不是有效的 JSON 而失敗 (如果 aws cli 命令本身失敗)
        # 所以先檢查 $?
        log_message "導入憑證到 ACM 失敗。AWS CLI 輸出: $import_output"
        handle_error "導入憑證到 ACM 失敗。請檢查日誌和 AWS CLI 輸出。" "$import_status" 1
        return 1 # 確保在 handle_error 未終止時函數也返回錯誤
    fi

    # 根據憑證類型更新配置文件中的 ARN
    if [ "$cert_type" == "server" ]; then
        echo "SERVER_CERT_ARN='$cert_arn'" >> "$config_file"
        log_message_core "伺服器憑證 ARN ($cert_arn) 已更新到配置文件 $config_file"
    elif [ "$cert_type" == "client" ]; then
        # 對於客戶端憑證，我們可能需要一個不同的機制來存儲多個 ARN，
        # 或者，如果 VPN 端點只使用一個客戶端根 CA，則可能不需要單獨匯入客戶端憑證到 ACM。
        # 目前假設 Client VPN 使用 CA 憑證進行客戶端驗證，而不是單獨的客戶端憑證 ARN。
        # 如果需要，這裡可以添加邏輯來處理客戶端憑證 ARN。
        # 例如: echo "CLIENT_CERT_ARN_${cert_name}='$cert_arn'" >> "$config_file"
        # 但更常見的是，Client VPN 端點會配置一個 Client Root Certificate ARN。
        # 此處假設我們主要匯入的是伺服器憑證和客戶端根 CA (如果需要的話)。
        # 如果是匯入客戶端根 CA，則 cert_name 可能是 CA 的名稱。
        # 為了簡化，我們假設這裡主要處理伺服器憑證。
        # 如果要匯入客戶端根 CA，則 cert_name 應為 CA 名稱，cert_type 可能需要調整或添加新類型。
        # 暫時，我們只記錄客戶端憑證的匯入，但不更新特定的單一 CLIENT_CERT_ARN 到主配置文件。
        log_message_core "客戶端憑證 '$cert_name' 的 ARN 是 $cert_arn (注意: Client VPN 通常使用 Client Root CA ARN)"
    fi

    echo -e "${GREEN}憑證 '$cert_name' 成功匯入到 ACM。ARN: $cert_arn${NC}"
    log_message_core "憑證 '$cert_name' 成功匯入到 ACM。ARN: $cert_arn"
    return 0
}

# 撤銷客戶端憑證 (庫函式版本)
# 參數: $1 = EASYRSA_DIR, $2 = CLIENT_NAME
revoke_client_certificate_lib() {
    local easyrsa_dir="$1"
    local client_name="$2"

    # 參數驗證
    if [ -z "$easyrsa_dir" ] || [ ! -d "$easyrsa_dir/pki" ]; then
        echo -e "${RED}錯誤: EasyRSA 目錄未初始化或無效${NC}"
        log_message_core "錯誤: revoke_client_certificate_lib - EasyRSA 目錄無效: $easyrsa_dir"
        return 1
    fi

    # 使用 read_secure_input 和 validate_username 獲取和驗證客戶端名稱
    if [ -z "$client_name" ]; then
        read_secure_input "請輸入要撤銷的客戶端憑證名稱: " client_name "validate_username" || return 1
    elif ! validate_username "$client_name"; then
        log_message_core "錯誤: revoke_client_certificate_lib - 提供的客戶端名稱無效: '$client_name'"
        return 1
    fi

    log_message_core "開始撤銷客戶端憑證 (lib) - 名稱: $client_name, 目錄: $easyrsa_dir"

    # 撤銷客戶端證書
    if "$easyrsa_dir/easyrsa" revoke "$client_name"; then
        echo -e "${GREEN}客戶端憑證撤銷成功。${NC}"
    else
        handle_error "撤銷客戶端憑證失敗。" "$?" 1
    fi

    # 生成 CRL
    if ! generate_crl_lib "$easyrsa_dir"; then
        handle_error "生成 CRL 失敗。" "$?" 1
    fi

    # 匯入 CRL 到 VPN 端點
    local endpoint_id
    endpoint_id=$(grep -Eo 'ENDPOINT_ID="[^"]+"' "$script_dir/vpn_config" | cut -d'"' -f2)
    if [ -n "$endpoint_id" ]; then
        if ! import_crl_to_vpn_endpoint_lib "$easyrsa_dir" "$endpoint_id" "$AWS_REGION"; then
            handle_error "匯入 CRL 到 VPN 端點失敗。" "$?" 1
        fi
    else
        echo -e "${YELLOW}未找到 ENDPOINT_ID，跳過 CRL 匯入到 VPN 端點。${NC}"
    fi

    echo -e "${GREEN}客戶端憑證 '$client_name' 撤銷成功。請重新生成 CRL 並上傳。${NC}"
    return 0
}

# 生成 CRL (憑證撤銷列表) (庫函式版本)
# 參數: $1 = EASYRSA_DIR
generate_crl_lib() {
    local easyrsa_dir="$1"

    # 參數驗證
    if [ -z "$easyrsa_dir" ] || [ ! -d "$easyrsa_dir/pki" ]; then
        echo -e "${RED}錯誤: EasyRSA 目錄未初始化或無效${NC}"
        log_message_core "錯誤: generate_crl_lib - EasyRSA 目錄無效: $easyrsa_dir"
        return 1
    fi

    log_message_core "開始生成 CRL (lib) - 目錄: $easyrsa_dir"

    # 生成 CRL
    if ! "$easyrsa_dir/easyrsa" gen-crl; then
        handle_error "生成 CRL 失敗。" "$?" 1
    fi

    echo -e "${GREEN}CRL 生成成功: $easyrsa_dir/pki/crl.pem${NC}"
    return 0
}

# 匯入 CRL 到 Client VPN 端點 (庫函式版本)
# 參數: $1 = EASYRSA_DIR, $2 = ENDPOINT_ID, $3 = AWS_REGION
import_crl_to_vpn_endpoint_lib() {
    local easyrsa_dir="$1"
    local endpoint_id="$2"
    local aws_region="$3"
    local crl_file="$easyrsa_dir/pki/crl.pem"

    # 參數驗證
    if [ -z "$easyrsa_dir" ] || [ ! -f "$crl_file" ]; then
        echo -e "${RED}錯誤: CRL 文件不存在於 $crl_file ${NC}"
        log_message_core "錯誤: import_crl_to_vpn_endpoint_lib - CRL 文件不存在: $crl_file"
        return 1
    fi
    if ! validate_endpoint_id "$endpoint_id"; then
        return 1
    fi
    if ! validate_aws_region "$aws_region"; then
        return 1
    fi

    log_message_core "開始匯入 CRL 到 VPN 端點 (lib) - 端點: $endpoint_id, Region: $aws_region"

    # 匯入 CRL
    if aws ec2 import-client-vpn-client-certificate-revocation-list --client-vpn-endpoint-id "$endpoint_id" --region "$aws_region" --certificate-revocation-list fileb://"$crl_file" >/dev/null 2>&1; then
        echo -e "${GREEN}CRL 成功匯入到 VPN 端點 $endpoint_id${NC}"
    else
        handle_error "匯入 CRL 到 VPN 端點失敗。" "$?" 1
    fi

    return 0
}

# 匯入多個憑證到 ACM 並返回 JSON 格式的 ARN (庫函式版本)
# 參數: $1 = SCRIPT_DIR, $2 = AWS_REGION
# 返回: JSON 格式 {"server_cert_arn": "arn1", "client_cert_arn": "arn2"}
import_certificates_to_acm_lib() {
    local script_dir="$1"
    local aws_region="$2"
    local easyrsa_dir="$script_dir/certificates"

    # 參數驗證
    if [ -z "$script_dir" ] || [ ! -d "$script_dir" ]; then
        echo -e "${RED}錯誤: 腳本目錄參數無效${NC}" >&2
        log_message_core "錯誤: import_certificates_to_acm_lib - 腳本目錄無效: $script_dir"
        return 1
    fi
    if ! validate_aws_region "$aws_region"; then
        return 1
    fi
    if [ ! -d "$easyrsa_dir/pki" ]; then
        echo -e "${RED}錯誤: EasyRSA PKI 目錄不存在於 $easyrsa_dir${NC}" >&2
        log_message_core "錯誤: import_certificates_to_acm_lib - PKI 目錄不存在: $easyrsa_dir/pki"
        return 1
    fi

    log_message_core "開始匯入憑證到 AWS ACM (lib) - Region: $aws_region"

    local server_cert_file="$easyrsa_dir/pki/issued/server.crt"
    local server_key_file="$easyrsa_dir/pki/private/server.key"
    local ca_cert_file="$easyrsa_dir/pki/ca.crt"
    local ca_key_file="$easyrsa_dir/pki/private/ca.key"

    # 檢查必要的憑證檔案
    if [ ! -f "$server_cert_file" ]; then
        echo -e "${RED}錯誤: 伺服器憑證檔案不存在: $server_cert_file${NC}" >&2
        log_message_core "錯誤: 伺服器憑證檔案不存在: $server_cert_file"
        return 1
    fi
    if [ ! -f "$server_key_file" ]; then
        echo -e "${RED}錯誤: 伺服器私鑰檔案不存在: $server_key_file${NC}" >&2
        log_message_core "錯誤: 伺服器私鑰檔案不存在: $server_key_file"
        return 1
    fi
    if [ ! -f "$ca_cert_file" ]; then
        echo -e "${RED}錯誤: CA 憑證檔案不存在: $ca_cert_file${NC}" >&2
        log_message_core "錯誤: CA 憑證檔案不存在: $ca_cert_file"
        return 1
    fi
    if [ ! -f "$ca_key_file" ]; then
        echo -e "${RED}錯誤: CA 私鑰檔案不存在: $ca_key_file${NC}" >&2
        log_message_core "錯誤: CA 私鑰檔案不存在: $ca_key_file"
        return 1
    fi

    echo -e "${BLUE}正在匯入伺服器憑證到 ACM...${NC}"
    local server_import_output
    server_import_output=$(aws acm import-certificate \
      --certificate "fileb://$server_cert_file" \
      --private-key "fileb://$server_key_file" \
      --certificate-chain "fileb://$ca_cert_file" \
      --region "$aws_region" \
      --tags Key=Name,Value="VPN-Server-Cert" Key=Purpose,Value="ClientVPN" Key=ManagedBy,Value="nlInc-vpnMgmtTools" 2>&1)

    local server_import_status=$?
    local server_cert_arn=""

    if [ $server_import_status -ne 0 ] || ! server_cert_arn=$(echo "$server_import_output" | jq -r '.CertificateArn' 2>/dev/null); then
        echo -e "${RED}錯誤: 匯入伺服器憑證到 ACM 失敗${NC}" >&2
        log_message_core "錯誤: 匯入伺服器憑證失敗. AWS CLI 輸出: $server_import_output"
        return 1
    fi

    echo -e "${BLUE}正在匯入客戶端 CA 憑證到 ACM...${NC}"
    local client_import_output
    client_import_output=$(aws acm import-certificate \
      --certificate "fileb://$ca_cert_file" \
      --private-key "fileb://$ca_key_file" \
      --region "$aws_region" \
      --tags Key=Name,Value="VPN-Client-CA" Key=Purpose,Value="ClientVPN" Key=ManagedBy,Value="nlInc-vpnMgmtTools" 2>&1)

    local client_import_status=$?
    local client_cert_arn=""

    if [ $client_import_status -ne 0 ] || ! client_cert_arn=$(echo "$client_import_output" | jq -r '.CertificateArn' 2>/dev/null); then
        echo -e "${RED}錯誤: 匯入客戶端 CA 憑證到 ACM 失敗${NC}" >&2
        log_message_core "錯誤: 匯入客戶端 CA 憑證失敗. AWS CLI 輸出: $client_import_output"
        return 1
    fi

    # 驗證 ARN 格式
    if [ -z "$server_cert_arn" ] || [ "$server_cert_arn" == "null" ]; then
        echo -e "${RED}錯誤: 無效的伺服器憑證 ARN${NC}" >&2
        log_message_core "錯誤: 無效的伺服器憑證 ARN: $server_cert_arn"
        return 1
    fi
    if [ -z "$client_cert_arn" ] || [ "$client_cert_arn" == "null" ]; then
        echo -e "${RED}錯誤: 無效的客戶端 CA 憑證 ARN${NC}" >&2
        log_message_core "錯誤: 無效的客戶端 CA 憑證 ARN: $client_cert_arn"
        return 1
    fi

    echo -e "${GREEN}憑證匯入成功！${NC}"
    echo -e "${GREEN}伺服器憑證 ARN: $server_cert_arn${NC}"
    echo -e "${GREEN}客戶端 CA 憑證 ARN: $client_cert_arn${NC}"

    log_message_core "伺服器憑證 ARN: $server_cert_arn"
    log_message_core "客戶端 CA 憑證 ARN: $client_cert_arn"

    # 返回 JSON 格式的結果
    local result_json
    result_json=$(jq -n \
        --arg server_arn "$server_cert_arn" \
        --arg client_arn "$client_cert_arn" \
        '{server_cert_arn: $server_arn, client_cert_arn: $client_arn}')

    echo "$result_json"
    return 0
}

# 生成完整的證書集合 (庫函式版本)
# 參數: $1 = SCRIPT_DIR
# 功能: 初始化 EasyRSA、生成 CA、伺服器和客戶端證書
generate_certificates_lib() {
    local script_dir="$1"
    local easyrsa_dir="$script_dir/certificates"

    # 參數驗證
    if [ -z "$script_dir" ] || [ ! -d "$script_dir" ]; then
        echo -e "${RED}錯誤: 腳本目錄參數無效${NC}" >&2
        log_message_core "錯誤: generate_certificates_lib - 腳本目錄無效: $script_dir"
        return 1
    fi

    log_message_core "開始生成完整證書集合 (lib) - 目標目錄: $easyrsa_dir"

    # 檢查是否已經存在證書
    if [ -f "$easyrsa_dir/pki/ca.crt" ] && [ -f "$easyrsa_dir/pki/issued/server.crt" ]; then
        echo -e "${YELLOW}證書已存在，跳過生成步驟。${NC}"
        log_message_core "證書已存在，跳過生成步驟"
        return 0
    fi

    # 1. 初始化 EasyRSA 環境
    echo -e "${BLUE}初始化 EasyRSA 環境...${NC}"
    if ! initialize_easyrsa_lib "$script_dir" "$easyrsa_dir"; then
        echo -e "${RED}錯誤: EasyRSA 環境初始化失敗${NC}" >&2
        return 1
    fi

    # 檢查 EasyRSA 是否正確初始化
    if [ ! -f "$easyrsa_dir/easyrsa" ]; then
        echo -e "${RED}錯誤: EasyRSA 腳本未正確複製${NC}" >&2
        log_message_core "錯誤: EasyRSA 腳本未在 $easyrsa_dir 中找到"
        return 1
    fi

    # 2. 初始化 PKI
    echo -e "${BLUE}初始化 PKI...${NC}"
    cd "$easyrsa_dir" || {
        echo -e "${RED}錯誤: 無法切換到 EasyRSA 目錄${NC}" >&2
        log_message_core "錯誤: 無法切換到目錄 $easyrsa_dir"
        return 1
    }

    if ! ./easyrsa init-pki; then
        echo -e "${RED}錯誤: PKI 初始化失敗${NC}" >&2
        log_message_core "錯誤: PKI 初始化失敗"
        cd - >/dev/null
        return 1
    fi

    # 3. 生成 CA 證書
    echo -e "${BLUE}生成 CA 證書...${NC}"
    if ! generate_ca_certificate_lib "$easyrsa_dir" "NL-VPN-CA"; then
        echo -e "${RED}錯誤: CA 證書生成失敗${NC}" >&2
        cd - >/dev/null
        return 1
    fi

    # 4. 生成伺服器證書
    echo -e "${BLUE}生成伺服器證書...${NC}"
    if ! generate_server_certificate_lib "$easyrsa_dir" "server"; then
        echo -e "${RED}錯誤: 伺服器證書生成失敗${NC}" >&2
        cd - >/dev/null
        return 1
    fi

    # 5. 生成預設管理員客戶端證書
    echo -e "${BLUE}生成管理員客戶端證書...${NC}"
    if ! generate_client_certificate_lib "$easyrsa_dir" "admin"; then
        echo -e "${RED}錯誤: 管理員客戶端證書生成失敗${NC}" >&2
        cd - >/dev/null
        return 1
    fi

    cd - >/dev/null

    # 驗證所有必要的證書檔案都已生成
    local required_files=(
        "$easyrsa_dir/pki/ca.crt"
        "$easyrsa_dir/pki/private/ca.key"
        "$easyrsa_dir/pki/issued/server.crt"
        "$easyrsa_dir/pki/private/server.key"
        "$easyrsa_dir/pki/issued/admin.crt"
        "$easyrsa_dir/pki/private/admin.key"
    )

    for file in "${required_files[@]}"; do
        if [ ! -f "$file" ]; then
            echo -e "${RED}錯誤: 必要的證書檔案未生成: $file${NC}" >&2
            log_message_core "錯誤: 證書檔案未生成: $file"
            return 1
        fi
    done

    echo -e "${GREEN}所有證書生成成功！${NC}"
    echo -e "${GREEN}CA 證書: $easyrsa_dir/pki/ca.crt${NC}"
    echo -e "${GREEN}伺服器證書: $easyrsa_dir/pki/issued/server.crt${NC}"
    echo -e "${GREEN}管理員證書: $easyrsa_dir/pki/issued/admin.crt${NC}"

    log_message_core "完整證書集合生成完成"
    return 0
}
