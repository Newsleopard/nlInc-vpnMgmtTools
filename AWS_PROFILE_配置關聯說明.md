# AWS Profile 與環境設置檔關聯說明

## 概述

本文件詳細說明 `configs/staging/staging.env` 和 `configs/production/production.env` 設置檔與 AWS Profile 的關聯關係，以及 `vpn_admin.sh` 在建立 VPN endpoint 時的優先順序。

## 關聯關係

### 1. 設置檔結構

環境設置檔位於：
- `configs/staging/staging.env` - Staging 環境設定
- `configs/production/production.env` - Production 環境設定

### 2. AWS Profile 設定方式

在環境設置檔中，AWS Profile 可以透過以下變數設定：

```bash
# 主要 AWS Profile 設定（建議使用）
AWS_PROFILE=staging-vpn-admin

# 環境特定覆寫設定（進階用法）
ENV_AWS_PROFILE=staging

# AWS 區域設定
AWS_REGION=ap-northeast-1
```

### 3. Profile 優先順序

系統載入 AWS Profile 的優先順序：

1. **環境設置檔中的 `ENV_AWS_PROFILE`** - 最高優先權
2. **環境設置檔中的 `AWS_PROFILE`** - 標準設定
3. **系統預設對應** - 如果設置檔不存在或未設定：
   - staging 環境 → `default` profile
   - production 環境 → `production` profile
4. **AWS CLI 預設 profile** - 系統回退選項

## VPN Endpoint 建立流程

### vpn_admin.sh 執行順序

當 `vpn_admin.sh` 建立 VPN endpoint 時，執行以下步驟：

```bash
1. 載入環境管理器 (env_manager.sh)
   ↓
2. 初始化當前環境設定
   ↓
3. 載入環境設置檔 (staging.env 或 production.env)
   ↓
4. 設定 AWS_PROFILE 環境變數
   ↓
5. 驗證 AWS Profile 設定和權限
   ↓
6. 執行 AWS CLI 命令建立 VPN endpoint
```

### 關鍵機制

1. **環境自動載入**: 腳本啟動時自動載入當前環境的設置檔
2. **Profile 驗證**: 執行前驗證 AWS Profile 是否存在且有效
3. **權限檢查**: 確認 Profile 有足夠權限執行 VPN 相關操作
4. **跨帳戶保護**: 防止在錯誤的 AWS 帳戶中執行操作

## 設定範例

### Staging 環境範例

```bash
# configs/staging/staging.env
ENV_NAME=staging
ENV_DISPLAY_NAME="Staging Environment"
AWS_REGION=ap-northeast-1
AWS_PROFILE=staging-vpn-admin
VPN_CIDR=172.16.0.0/22
VPN_NAME=Staging-VPN
PRIMARY_VPC_ID=vpc-staging123
```

### Production 環境範例

```bash
# configs/production/production.env
ENV_NAME=production
ENV_DISPLAY_NAME="Production Environment"
AWS_REGION=ap-northeast-1
AWS_PROFILE=production-vpn-admin
VPN_CIDR=172.20.0.0/22
VPN_NAME=Production-VPN
PRIMARY_VPC_ID=vpc-prod456
```

## AWS Profile 管理

### 檢視當前設定

```bash
# 檢視當前環境狀態
./vpn_env.sh status

# 檢視所有環境的 Profile 設定
./admin-tools/aws_vpn_admin.sh
# 選擇 "AWS Profile 管理" → "查看所有環境的 Profile 設定"
```

### 設定 AWS Profile

```bash
# 透過環境管理器設定
./vpn_env.sh selector
# 或
./admin-tools/aws_vpn_admin.sh
# 選擇 "AWS Profile 管理" → "設定當前環境的 AWS Profile"
```

### 驗證設定

```bash
# 驗證 Profile 整合
./admin-tools/aws_vpn_admin.sh
# 選擇 "AWS Profile 管理" → "驗證 Profile 整合"
```

## 安全考量

### 1. 帳戶隔離

- Staging 和 Production 環境應使用不同的 AWS 帳戶
- 每個環境的 AWS Profile 應對應正確的帳戶

### 2. 權限最小化

- Staging Profile 僅需 Staging 環境的權限
- Production Profile 應有額外的安全限制

### 3. 驗證機制

- 系統會在執行前驗證 Profile 有效性
- 可設定帳戶 ID 驗證避免跨帳戶操作

## 常見問題

### Q: 如何確認當前使用的 AWS Profile？

A: 執行 `./vpn_env.sh status` 查看當前環境和對應的 AWS Profile。

### Q: 如何切換環境？

A: 使用 `./vpn_env.sh switch staging` 或 `./vpn_env.sh switch production`。

### Q: AWS CLI 命令會使用哪個 Profile？

A: 系統會自動設定 `AWS_PROFILE` 環境變數，所有 AWS CLI 命令都會使用該 Profile。

### Q: 如何處理 Profile 不存在的錯誤？

A: 使用 AWS Profile 管理功能重新設定，或確認 AWS CLI 配置正確。

## 結論

環境設置檔與 AWS Profile 的關聯確保了：

1. **環境隔離**: 不同環境使用不同的 AWS 帳戶和 Profile
2. **操作安全**: 防止在錯誤環境中執行操作
3. **設定統一**: 所有相關工具都使用相同的 Profile 設定
4. **管理便利**: 透過設置檔集中管理環境特定的設定

透過此機制，`vpn_admin.sh` 在建立 VPN endpoint 時會優先參考環境設置檔中的 AWS Profile 設定，確保在正確的 AWS 環境中執行操作。