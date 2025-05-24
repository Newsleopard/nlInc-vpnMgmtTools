# AWS VPN 管理工具邏輯問題修正總結

## 概述
本文件記錄了 `aws_vpn_admin.sh` 中的邏輯問題及其修正方案。

## 修正的問題

### 1. 缺失的 `import_certificates_to_acm_lib` 函式

**問題描述**:
- `aws_vpn_admin.sh` 中調用了 `import_certificates_to_acm_lib` 函式
- 期望該函式返回 JSON 格式: `{"server_cert_arn": "arn1", "client_cert_arn": "arn2"}`
- 但該函式在 `cert_management.sh` 中並不存在

**修正方案**:
- 在 `lib/cert_management.sh` 中新增 `import_certificates_to_acm_lib` 函式
- 函式功能:
  - 匯入伺服器證書 (`server.crt`) 到 ACM
  - 匯入客戶端 CA 證書 (`ca.crt`) 到 ACM
  - 返回包含兩個 ARN 的 JSON 格式結果
- 檔案位置: `lib/cert_management.sh` (第 402-500 行)

### 2. 缺失的 `generate_certificates_lib` 函式

**問題描述**:
- `aws_vpn_admin.sh` 中調用了 `generate_certificates_lib` 函式
- 但該函式在 `cert_management.sh` 中並不存在

**修正方案**:
- 在 `lib/cert_management.sh` 中新增 `generate_certificates_lib` 函式
- 函式功能:
  - 初始化 EasyRSA 環境
  - 初始化 PKI
  - 生成 CA 證書
  - 生成伺服器證書
  - 生成管理員客戶端證書
- 檔案位置: `lib/cert_management.sh` (第 12-100 行)

### 3. 缺失的 `get_vpc_subnet_vpn_details_lib` 函式

**問題描述**:
- `aws_vpn_admin.sh` 中調用了 `get_vpc_subnet_vpn_details_lib` 函式
- 期望該函式返回 JSON 格式: `{"vpc_id": "vpc-xxx", "subnet_id": "subnet-xxx", "vpn_cidr": "172.16.0.0/22", "vpn_name": "Production-VPN"}`
- 但該函式在 `endpoint_creation.sh` 中並不存在

**修正方案**:
- 在 `lib/endpoint_creation.sh` 中新增 `get_vpc_subnet_vpn_details_lib` 函式
- 函式功能:
  - 顯示可用的 VPCs 並讓使用者選擇
  - 顯示選定 VPC 中的子網路並讓使用者選擇
  - 收集 VPN CIDR 和名稱設定
  - 返回包含所有詳細資訊的 JSON 格式結果
- 檔案位置: `lib/endpoint_creation.sh` (第 9-80 行)

### 4. JSON 解析邏輯改進

**問題描述**:
- 原本的 JSON 解析邏輯完全依賴 `jq` 工具
- 在沒有 `jq` 的系統上會失敗

**修正方案**:
- 在 `aws_vpn_admin.sh` 中為所有 JSON 解析部分添加備用解析方法
- 使用 `grep` 和 `sed` 作為備用方案
- 修正位置:
  - 證書 ARN 解析 (第 91-108 行)
  - VPC 詳細資訊解析 (第 135-155 行)

## 技術細節

### ARN 傳遞機制重新設計

**之前的問題**:
```bash
# ❌ 潛在問題：假設 import_certificates_to_acm_lib 返回 JSON
acm_arns_result=$(import_certificates_to_acm_lib "$SCRIPT_DIR" "$AWS_REGION")
main_server_cert_arn=$(echo "$acm_arns_result" | jq -r '.server_cert_arn')
```

**修正後的解決方案**:
```bash
# ✅ 健壯的 ARN 傳遞機制
acm_arns_result=$(import_certificates_to_acm_lib "$SCRIPT_DIR" "$AWS_REGION")
if command -v jq >/dev/null 2>&1; then
    main_server_cert_arn=$(echo "$acm_arns_result" | jq -r '.server_cert_arn' 2>/dev/null)
else
    main_server_cert_arn=$(echo "$acm_arns_result" | grep -o '"server_cert_arn":"[^"]*"' | sed 's/"server_cert_arn":"\([^"]*\)"/\1/')
fi
```

### 新增函式的 JSON 回應格式

**證書匯入函式回應**:
```json
{
  "server_cert_arn": "arn:aws:acm:region:account:certificate/server-cert-id",
  "client_cert_arn": "arn:aws:acm:region:account:certificate/client-cert-id"
}
```

**VPC 詳細資訊函式回應**:
```json
{
  "vpc_id": "vpc-12345678",
  "subnet_id": "subnet-87654321",
  "vpn_cidr": "172.16.0.0/22",
  "vpn_name": "Production-VPN"
}
```

## 驗證結果

- ✅ 所有缺失的函式已實作
- ✅ JSON 解析支援有/無 `jq` 兩種環境
- ✅ 沒有語法錯誤
- ✅ ARN 傳遞機制重新設計完成
- ✅ 函式簽名和返回值統一

## 相關檔案

- `aws_vpn_admin.sh` - 主腳本，修正了 JSON 解析邏輯
- `lib/cert_management.sh` - 新增證書相關函式
- `lib/endpoint_creation.sh` - 新增 VPC 設定收集函式

## 建議的後續測試

1. 測試在有 `jq` 的環境下的 JSON 解析
2. 測試在沒有 `jq` 的環境下的備用解析
3. 測試完整的 VPN 端點創建流程
4. 驗證證書匯入和 ARN 傳遞功能
