#!/bin/bash

# 載入核心函式庫以使用顏色和日誌
source "$(dirname "${BASH_SOURCE[0]}")/core_functions.sh"

# 生成證書
# 需要主腳本傳遞 SCRIPT_DIR 變數
generate_certificates_lib() {
    local main_script_dir="$1" # 接收主腳本的 SCRIPT_DIR

    echo -e "\n${YELLOW}生成 VPN 證書...${NC}"
    
    # 創建工作目錄
    local cert_dir="$main_script_dir/certificates"
    mkdir -p "$cert_dir"
    
    # 儲存當前目錄並切換
    local current_pwd=$(pwd)
    cd "$cert_dir"
    
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
        if ! (yes "" | easyrsa build-ca nopass); then
            handle_error "生成 CA 證書失敗。" "$?" 1
        fi
        # 驗證 CA 檔案是否已生成
        if [ ! -f "pki/ca.crt" ] || [ ! -f "pki/private/ca.key" ]; then
            handle_error "CA 證書 (pki/ca.crt 或 pki/private/ca.key) 生成後未找到。" "" 1
        fi
        echo -e "${GREEN}CA 證書生成成功。${NC}"
    else
        echo -e "${YELLOW}CA 證書 (pki/ca.crt) 已存在。${NC}"
    fi
    
    # 生成伺服器證書
    if [ ! -f "pki/issued/server.crt" ]; then
        echo -e "${BLUE}生成伺服器證書...${NC}"
        # 檢查 CA 證書是否存在
        if [ ! -f "pki/ca.crt" ] || [ ! -f "pki/private/ca.key" ]; then
            handle_error "無法生成伺服器證書，因為 CA 證書 (pki/ca.crt 或 pki/private/ca.key) 不存在。" "" 1
        fi
        if ! (yes "" | easyrsa build-server-full server nopass); then
            handle_error "生成伺服器證書失敗。" "$?" 1
        fi
        # 驗證伺服器證書檔案是否已生成
        if [ ! -f "pki/issued/server.crt" ] || [ ! -f "pki/private/server.key" ]; then
            handle_error "伺服器證書 (pki/issued/server.crt 或 pki/private/server.key) 生成後未找到。" "" 1
        fi
        echo -e "${GREEN}伺服器證書生成成功。${NC}"
    else
        echo -e "${YELLOW}伺服器證書 (pki/issued/server.crt) 已存在。${NC}"
    fi
    
    echo -e "${GREEN}證書生成流程完成！${NC}"
    log_message "VPN 證書已生成"

    # 返回原始目錄
    cd "$current_pwd"
}

# 生成管理員證書 (用於 admin config)
# 需要主腳本傳遞 SCRIPT_DIR 變數
generate_admin_certificate_lib() {
    local main_script_dir="$1" # 接收主腳本的 SCRIPT_DIR
    local cert_dir="$main_script_dir/certificates"

    # 儲存當前目錄並切換
    local current_pwd=$(pwd)
    cd "$cert_dir"

    if [ ! -f "pki/issued/admin.crt" ]; then
        echo -e "${BLUE}生成管理員證書 (admin.crt)...${NC}"
        # 檢查 CA 證書是否存在
        if [ ! -f "pki/ca.crt" ] || [ ! -f "pki/private/ca.key" ]; then
            handle_error "無法生成管理員證書，因為 CA 證書 (pki/ca.crt 或 pki/private/ca.key) 不存在。" "" 1
        fi
        if ! (yes "" | easyrsa build-client-full admin nopass); then
            handle_error "生成管理員證書失敗。" "$?" 1
        fi
        # 驗證管理員證書檔案是否已生成
        if [ ! -f "pki/issued/admin.crt" ] || [ ! -f "pki/private/admin.key" ]; then
            handle_error "管理員證書 (pki/issued/admin.crt 或 pki/private/admin.key) 生成後未找到。" "" 1
        fi
        log_message "管理員證書 (admin.crt) 已生成"
        echo -e "${GREEN}管理員證書生成成功。${NC}"
    else
        echo -e "${YELLOW}管理員證書 (pki/issued/admin.crt) 已存在。${NC}"
    fi

    # 返回原始目錄
    cd "$current_pwd"
}

# 導入證書到 ACM
# 需要 SCRIPT_DIR, AWS_REGION
# 返回 server_cert_arn 和 client_cert_arn
import_certificates_to_acm_lib() {
    local main_script_dir="$1"
    local aws_region="$2"
    local cert_dir="$main_script_dir/certificates"

    echo -e "\n${BLUE}導入證書到 AWS Certificate Manager...${NC}"

    # 檢查伺服器證書相關檔案
    local server_cert_file="$cert_dir/pki/issued/server.crt"
    local server_key_file="$cert_dir/pki/private/server.key"
    local ca_cert_file_for_server_chain="$cert_dir/pki/ca.crt"

    if [ ! -f "$server_cert_file" ]; then
        handle_error "伺服器證書檔案 ($server_cert_file) 不存在，無法匯入 ACM。" "" 1
    fi
    if [ ! -f "$server_key_file" ]; then
        handle_error "伺服器私鑰檔案 ($server_key_file) 不存在，無法匯入 ACM。" "" 1
    fi
    if [ ! -f "$ca_cert_file_for_server_chain" ]; then
        handle_error "CA 證書檔案 ($ca_cert_file_for_server_chain) 不存在（作為伺服器證書鏈），無法匯入 ACM。" "" 1
    fi

    echo -e "${BLUE}正在導入伺服器證書 (server.crt) 到 ACM...${NC}"
    local server_cert_output
    local server_cert_arn
    server_cert_output=$(aws acm import-certificate \
      --certificate "fileb://$server_cert_file" \
      --private-key "fileb://$server_key_file" \
      --certificate-chain "fileb://$ca_cert_file_for_server_chain" \
      --region "$aws_region" \
      --tags Key=Name,Value="VPN-Server-Cert-${SERVER_CERT_NAME_PREFIX:-default}" Key=Purpose,Value="ClientVPN" Key=ManagedBy,Value="nlInc-vpnMgmtTools" 2>&1)
    local import_server_status=$?
    
    if [ $import_server_status -ne 0 ] || ! server_cert_arn=$(echo "$server_cert_output" | jq -r '.CertificateArn'); then
        # jq 可能因為 server_cert_output 不是有效的 JSON 而失敗 (如果 aws cli 命令本身失敗)
        # 所以先檢查 $?
        log_message "導入伺服器證書到 ACM 失敗。AWS CLI 輸出: $server_cert_output"
        handle_error "導入伺服器證書到 ACM 失敗。請檢查日誌和 AWS CLI 輸出。" "$import_server_status" 1
        return 1 # 確保在 handle_error 未終止時函數也返回錯誤
    fi
    echo -e "${GREEN}伺服器證書成功導入 ACM。ARN: $server_cert_arn${NC}"
    log_message "伺服器證書成功導入 ACM。ARN: $server_cert_arn"

    # 檢查客戶端 CA 證書相關檔案
    local client_ca_cert_file="$cert_dir/pki/ca.crt"
    local client_ca_key_file="$cert_dir/pki/private/ca.key"

    if [ ! -f "$client_ca_cert_file" ]; then
        handle_error "客戶端 CA 證書檔案 ($client_ca_cert_file) 不存在，無法匯入 ACM。" "" 1
    fi
    if [ ! -f "$client_ca_key_file" ]; then
        handle_error "客戶端 CA 私鑰檔案 ($client_ca_key_file) 不存在，無法匯入 ACM。" "" 1
    fi

    echo -e "${BLUE}正在導入客戶端 CA 證書 (ca.crt) 到 ACM...${NC}"
    local client_cert_output
    local client_cert_arn
    client_cert_output=$(aws acm import-certificate \
      --certificate "fileb://$client_ca_cert_file" \
      --private-key "fileb://$client_ca_key_file" \
      --region "$aws_region" \
      --tags Key=Name,Value="VPN-Client-CA-${SERVER_CERT_NAME_PREFIX:-default}" Key=Purpose,Value="ClientVPN" Key=ManagedBy,Value="nlInc-vpnMgmtTools" 2>&1)
    local import_client_ca_status=$?

    if [ $import_client_ca_status -ne 0 ] || ! client_cert_arn=$(echo "$client_cert_output" | jq -r '.CertificateArn'); then
        log_message "導入客戶端 CA 證書到 ACM 失敗。AWS CLI 輸出: $client_cert_output"
        handle_error "導入客戶端 CA 證書到 ACM 失敗。請檢查日誌和 AWS CLI 輸出。" "$import_client_ca_status" 1
        return 1
    fi
    echo -e "${GREEN}客戶端 CA 證書成功導入 ACM。ARN: $client_cert_arn${NC}"
    log_message "客戶端 CA 證書成功導入 ACM。ARN: $client_cert_arn"

    # 函式成功時，echo 兩個 ARN，用分號分隔，主腳本可以解析
    echo "${server_cert_arn};${client_cert_arn}"
    return 0
}
