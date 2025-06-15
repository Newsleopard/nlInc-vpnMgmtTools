# 雙 AWS Profile 設定指南

本指南將引導您完成雙 AWS 帳戶 Profile 管理系統的設定，讓您能夠安全地在 Staging 和 Production 環境之間進行操作。

## 目錄

1. [概述](#概述)
2. [前置要求](#前置要求)
3. [AWS Profile 設定](#aws-profile-設定)
4. [環境配置](#環境配置)
5. [管理員設定](#管理員設定)
6. [團隊成員設定](#團隊成員設定)
7. [日常操作](#日常操作)
8. [故障排除](#故障排除)

## 概述

雙 AWS Profile 管理系統提供以下功能：

### 🎯 核心功能
- **環境隔離**: 完全分離 Staging 和 Production 環境
- **自動 Profile 選擇**: 根據環境智能推薦和選擇 AWS Profile
- **跨帳戶驗證**: 防止在錯誤帳戶中執行操作
- **零接觸工作流程**: 自動化證書交換和配置下載
- **安全控制**: Production 環境需要額外確認

### 🏗️ 架構優勢
- **一致性**: 所有工具使用統一的 profile 管理
- **可追蹤性**: 完整的操作日誌和審計追蹤
- **靈活性**: 支援自定義 profile 命名約定
- **安全性**: 多層安全檢查和確認機制

## 前置要求

### 系統要求
- **作業系統**: macOS (已測試)
- **必要工具**:
  - AWS CLI v2
  - jq (JSON 處理器)
  - OpenSSL
  - Git

### 權限要求
- 兩個 AWS 帳戶的管理員權限 (Staging & Production)
- IAM 權限創建和管理：
  - VPN 端點
  - S3 存儲桶
  - ACM 證書
  - IAM 用戶和政策

## AWS Profile 設定

### 1. 設定 AWS Profiles

建議的 Profile 命名約定：

```bash
# Staging 環境
aws configure --profile staging
# 或
aws configure --profile company-staging
aws configure --profile dev-staging

# Production 環境  
aws configure --profile production
# 或
aws configure --profile company-production  
aws configure --profile prod
```

### 2. 驗證 Profile 設定

```bash
# 檢查可用的 profiles
aws configure list-profiles

# 測試每個 profile
aws sts get-caller-identity --profile staging
aws sts get-caller-identity --profile production
```

### 3. Profile 最佳實務

**命名約定建議**:
- 包含環境名稱: `staging`, `production`, `prod`
- 可選公司前綴: `company-staging`, `myorg-prod`
- 避免模糊命名: `test`, `dev` (除非明確對應 staging)

**安全設定**:
```bash
# 設定 region
aws configure set region us-east-1 --profile staging
aws configure set region us-east-1 --profile production

# 設定輸出格式
aws configure set output json --profile staging
aws configure set output json --profile production
```

## 環境配置

### 1. 更新環境配置檔案

#### Staging 環境 (`configs/staging/staging.env`)

```bash
# === AWS Profile 設定 ===
# 環境特定 AWS Profile (可選，留空使用自動檢測)
ENV_AWS_PROFILE=""

# 建議的 Profile 名稱 (用於自動推薦)
SUGGESTED_PROFILES="staging,company-staging,dev-staging"

# === 帳戶驗證 ===
# Staging AWS 帳戶 ID (12位數字)
STAGING_ACCOUNT_ID="123456789012"

# === S3 配置 (零接觸工作流程) ===
# Staging S3 存儲桶名稱
STAGING_S3_BUCKET="staging-vpn-csr-exchange"

# === VPN 設定 ===
ENDPOINT_ID="cvpn-endpoint-staging123"
AWS_REGION="us-east-1"

# ... 其他現有配置 ...
```

#### Production 環境 (`configs/production/production.env`)

```bash
# === AWS Profile 設定 ===
# 環境特定 AWS Profile (可選，留空使用自動檢測)
ENV_AWS_PROFILE=""

# 建議的 Profile 名稱 (用於自動推薦)
SUGGESTED_PROFILES="production,company-production,prod"

# === 帳戶驗證 ===  
# Production AWS 帳戶 ID (12位數字)
PRODUCTION_ACCOUNT_ID="987654321098"

# === S3 配置 (零接觸工作流程) ===
# Production S3 存儲桶名稱
PRODUCTION_S3_BUCKET="production-vpn-csr-exchange"

# === VPN 設定 ===
ENDPOINT_ID="cvpn-endpoint-prod456"
AWS_REGION="us-east-1"

# ... 其他現有配置 ...
```

### 2. 設定 Profile 偏好

如果您有固定的 profile 偏好，可以直接設定：

```bash
# 設定 staging 環境使用特定 profile
./vpn_env.sh switch staging
./admin-tools/aws_vpn_admin.sh --set-profile company-staging

# 設定 production 環境使用特定 profile  
./vpn_env.sh switch production
./admin-tools/aws_vpn_admin.sh --set-profile company-production
```

## 管理員設定

### 1. 初始化零接觸工作流程

#### 建立 S3 存儲桶和 IAM 政策

```bash
# 切換到 staging 環境
./vpn_env.sh switch staging

# 建立 staging S3 存儲桶和 IAM 設定
./admin-tools/setup_csr_s3_bucket.sh --publish-assets --create-users

# 切換到 production 環境  
./vpn_env.sh switch production

# 建立 production S3 存儲桶和 IAM 設定
./admin-tools/setup_csr_s3_bucket.sh --publish-assets --create-users
```

#### 發布公共資產

```bash
# 發布所有環境的 CA 證書和端點資訊
./admin-tools/publish_endpoints.sh

# 或分別發布
./admin-tools/publish_endpoints.sh -e staging
./admin-tools/publish_endpoints.sh -e production
```

### 2. 管理工具使用

所有管理工具現在都支援環境感知操作：

```bash
# 環境狀態檢查
./vpn_env.sh status

# 簽署 CSR (自動使用當前環境的 profile)
./admin-tools/sign_csr.sh --upload-s3 user.csr

# 批次處理 CSR
./admin-tools/process_csr_batch.sh download -e staging
./admin-tools/process_csr_batch.sh process -e staging  
./admin-tools/process_csr_batch.sh upload --auto-upload

# 撤銷用戶訪問
./admin-tools/revoke_member_access.sh

# 人員離職處理
./admin-tools/employee_offboarding.sh
```

### 3. 環境切換和 Profile 驗證

```bash
# 檢查當前環境和 profile 狀態
./vpn_env.sh status

# 安全切換環境 (會自動驗證 profile)
./vpn_env.sh switch staging   # 提示選擇或確認 staging profile
./vpn_env.sh switch production # 需要額外確認，提示選擇 production profile

# 手動設定 profile (進階用戶)
./admin-tools/aws_vpn_admin.sh --set-profile my-custom-profile
```

## 團隊成員設定

### 1. 零接觸工作流程 (建議)

#### 第一步：初始化設定
```bash
# 自動下載 CA 證書和端點配置，生成並上傳 CSR
./team_member_setup.sh --init

# 可選：指定特定環境
./team_member_setup.sh --init -e staging
./team_member_setup.sh --init -e production
```

#### 第二步：等待管理員簽署

管理員會收到通知並簽署您的 CSR：
```bash
# 管理員執行 (自動上傳到 S3)
./admin-tools/sign_csr.sh --upload-s3 username.csr
```

#### 第三步：完成設定
```bash
# 自動下載簽署的證書並完成 VPN 設定
./team_member_setup.sh --resume
```

### 2. 傳統工作流程 (備用)

如果零接觸工作流程不可用：

```bash
# 生成 CSR 
./team_member_setup.sh

# 等待管理員提供簽署的證書

# 使用簽署的證書完成設定
./team_member_setup.sh --resume-cert
```

### 3. 環境特定設定

```bash
# 為特定環境設定 VPN
./team_member_setup.sh --init -e staging
./team_member_setup.sh --init -e production

# 使用自定義 S3 存儲桶
./team_member_setup.sh --init --bucket my-custom-bucket

# 停用 S3 功能 (使用傳統方式)
./team_member_setup.sh --no-s3
```

## 日常操作

### 1. 環境檢查和狀態

```bash
# 檢查當前環境和 AWS profile 狀態
./vpn_env.sh status

# 詳細的 profile 資訊
./admin-tools/aws_vpn_admin.sh --profile-status
```

### 2. 環境切換

```bash
# 切換環境 (自動處理 profile)
./vpn_env.sh switch staging
./vpn_env.sh switch production

# 使用環境選擇器 (互動式)
./enhanced_env_selector.sh
```

### 3. Profile 管理

```bash
# 檢視當前 profile 設定
./admin-tools/aws_vpn_admin.sh --show-profile

# 更換 profile
./admin-tools/aws_vpn_admin.sh --set-profile new-profile-name

# 重設為自動偵測
./admin-tools/aws_vpn_admin.sh --reset-profile
```

### 4. 管理操作

```bash
# 所有管理工具現在都支援自動 profile 檢測
./admin-tools/aws_vpn_admin.sh       # 主要管理控制台
./admin-tools/sign_csr.sh user.csr   # 使用當前環境的 profile
./admin-tools/process_csr_batch.sh monitor  # 監控模式
```

## 故障排除

### 常見問題

#### 1. Profile 未自動檢測

**症狀**: 系統無法自動選擇正確的 AWS profile

**解決方案**:
```bash
# 檢查可用的 profiles
aws configure list-profiles

# 手動設定 profile
./admin-tools/aws_vpn_admin.sh --set-profile correct-profile-name

# 驗證 profile 是否正確
aws sts get-caller-identity --profile correct-profile-name
```

#### 2. 跨帳戶操作錯誤

**症狀**: 警告訊息顯示 profile 不匹配環境

**解決方案**:
```bash
# 檢查帳戶 ID 配置
grep ACCOUNT_ID configs/*/staging.env configs/*/production.env

# 確認當前 AWS 帳戶
aws sts get-caller-identity --profile your-profile

# 更新配置檔案中的 ACCOUNT_ID
```

#### 3. S3 存儲桶訪問問題

**症狀**: 無法訪問 S3 存儲桶進行零接觸操作

**解決方案**:
```bash
# 檢查 S3 存儲桶權限
aws s3 ls s3://your-bucket-name --profile your-profile

# 重新建立 S3 存儲桶設定
./admin-tools/setup_csr_s3_bucket.sh --create-users

# 檢查 IAM 政策
./admin-tools/setup_csr_s3_bucket.sh --list-users
```

#### 4. 環境切換失敗

**症狀**: 無法切換到目標環境

**解決方案**:
```bash
# 檢查環境配置檔案
ls -la configs/staging/ configs/production/

# 驗證配置檔案格式
source configs/staging/staging.env && echo "Staging config OK"
source configs/production/production.env && echo "Production config OK"

# 重新初始化環境
./vpn_env.sh switch staging --force-init
```

### 進階診斷

#### 啟用詳細日誌

```bash
# 設定詳細模式
export VERBOSE_MODE=true

# 檢查日誌檔案
tail -f logs/staging/*.log
tail -f logs/production/*.log
```

#### Profile 驗證測試

```bash
# 執行 profile 管理測試
./tests/test_profile_management.sh

# 執行 admin tools 整合測試  
./tests/test_admin_tools.sh

# 執行 team member setup 測試
./tests/test_team_member_setup.sh
```

#### 手動 Profile 配置

如果自動檢測持續失敗：

```bash
# 編輯環境配置，直接指定 profile
# configs/staging/staging.env
ENV_AWS_PROFILE="your-staging-profile"

# configs/production/production.env  
ENV_AWS_PROFILE="your-production-profile"
```

### 獲取支援

如果問題持續存在：

1. **收集診斷資訊**:
   ```bash
   ./vpn_env.sh status > debug_info.txt
   aws configure list-profiles >> debug_info.txt
   ```

2. **檢查日誌**:
   ```bash
   find logs/ -name "*.log" -mtime -1 -exec tail -20 {} \;
   ```

3. **執行測試套件**:
   ```bash
   ./tests/test_profile_management.sh
   ```

4. **聯絡管理員** 提供上述資訊

---

## 附錄

### A. 環境配置範本

#### Staging 環境完整配置
```bash
# configs/staging/staging.env

# === 基本環境設定 ===
ENVIRONMENT_NAME="staging"
ENVIRONMENT_TYPE="staging"

# === AWS Profile 設定 ===
ENV_AWS_PROFILE=""
SUGGESTED_PROFILES="staging,company-staging,dev-staging"

# === 帳戶驗證 ===
STAGING_ACCOUNT_ID="123456789012"

# === S3 配置 ===
STAGING_S3_BUCKET="staging-vpn-csr-exchange"

# === VPN 設定 ===
ENDPOINT_ID="cvpn-endpoint-staging123"
AWS_REGION="us-east-1"
VPN_CIDR="10.0.0.0/16"

# === 安全設定 ===
REQUIRE_CONFIRMATION="false"
LOG_LEVEL="INFO"
```

#### Production 環境完整配置
```bash
# configs/production/production.env

# === 基本環境設定 ===
ENVIRONMENT_NAME="production"
ENVIRONMENT_TYPE="production"

# === AWS Profile 設定 ===
ENV_AWS_PROFILE=""
SUGGESTED_PROFILES="production,company-production,prod"

# === 帳戶驗證 ===
PRODUCTION_ACCOUNT_ID="987654321098"

# === S3 配置 ===
PRODUCTION_S3_BUCKET="production-vpn-csr-exchange"

# === VPN 設定 ===
ENDPOINT_ID="cvpn-endpoint-prod456"
AWS_REGION="us-east-1"
VPN_CIDR="10.1.0.0/16"

# === 安全設定 ===
REQUIRE_CONFIRMATION="true"
LOG_LEVEL="WARN"
```

### B. 快速參考命令

```bash
# 環境操作
./vpn_env.sh status                    # 檢查狀態
./vpn_env.sh switch <env>             # 切換環境

# Profile 管理
./admin-tools/aws_vpn_admin.sh --show-profile    # 顯示當前 profile
./admin-tools/aws_vpn_admin.sh --set-profile     # 設定 profile

# 零接觸工作流程
./team_member_setup.sh --init         # 初始化
./team_member_setup.sh --resume       # 完成設定
./admin-tools/sign_csr.sh --upload-s3 # 簽署並上傳

# 管理操作
./admin-tools/setup_csr_s3_bucket.sh --publish-assets  # 建立 S3
./admin-tools/publish_endpoints.sh                     # 發布端點資訊
./admin-tools/process_csr_batch.sh monitor            # 批次監控
```

這個設定指南應該能幫助您完成雙 AWS Profile 管理系統的完整配置。如有任何問題，請參考故障排除章節或聯絡系統管理員。