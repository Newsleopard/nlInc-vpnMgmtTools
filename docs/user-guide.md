# VPN 使用者指南 - 工程團隊適用

本指南協助工程團隊成員設定並使用 AWS Client VPN 系統來安全存取公司資源。

## 🎯 本指南適用對象

- 軟體工程師
- QA 工程師
- DevOps 團隊成員
- 任何需要 VPN 存取 AWS 資源的人員

## 📊 VPN Setup Workflow

```mermaid
flowchart TD
    Start([User Needs VPN Access]) --> Check{Check
Permissions}
    Check -->|Has Permissions| Init[Run team_member_setup.sh --init]
    Check -->|No Permissions| Contact[Contact Administrator]
    Contact --> Admin[Admin Grants Permissions]
    Admin --> Init

    Init --> Generate[Generate CSR & Private Key]
    Generate --> Upload[Upload CSR to S3]
    Upload --> Wait[Wait for Admin Approval]

    Wait --> AdminSign[Admin Signs Certificate]
    AdminSign --> UploadCert[Admin Uploads Certificate to S3]
    UploadCert --> Resume[Run team_member_setup.sh --resume]

    Resume --> Download[Download Signed Certificate]
    Download --> Config[Generate VPN Config Files]
    Config --> Import[Import to VPN Client]
    Import --> Connect[Connect to VPN]
    Connect --> End([VPN Access Ready])

    style Start fill:#e1f5fe
    style End fill:#c8e6c9
    style Wait fill:#fff9c4
    style AdminSign fill:#ffccbc
```

## 📋 系統需求

開始之前，請確認您具備：

- macOS 10.15+ (Catalina 或更新版本)
- 具有 VPN 權限的 AWS IAM 使用者帳戶
- Slack 工作區存取權限
- 已安裝 OpenVPN client 或 AWS VPN Client

## 🚀 初始設定（一次性）

### 步驟 1：檢查您的權限

```bash
./team_member_setup.sh --check-permissions
```

如果出現權限錯誤，請聯繫您的 VPN 管理員。

### 步驟 2：產生 VPN 憑證

```bash
# 自動偵測並選擇 AWS profile（推薦）
./team_member_setup.sh --init

# 或指定特定 profile（可選）
./team_member_setup.sh --init --profile staging
./team_member_setup.sh --init --profile production
```

腳本會：
1. **自動偵測**您系統中所有可用的 AWS profiles
2. **顯示互動式選單**讓您選擇要使用的 profile
3. **自動判斷環境**（staging 或 production）基於 profile 名稱

腳本將會：

1. 從 S3 下載 CA 憑證
2. 產生您的私鑰（留在本地）
3. 建立憑證簽署要求 (CSR)
4. 上傳 CSR 等待管理員批准

### 步驟 3：等待管理員批准

您將看到類似訊息：

```text
⏸️  設定暫停，等待管理員簽署您的憑證...
使用者名稱： john.doe
CSR 位置： s3://vpn-csr-exchange/csr/john.doe.csr
```

通知您的 VPN 管理員 CSR 已就緒並告之 CSR 檔案名稱。

### 步驟 4：完成設定

一旦獲得批准（管理員將通知您）：

```bash
# 自動使用之前選擇的 profile（推薦）
./team_member_setup.sh --resume

# 或指定特定 profile（可選）
./team_member_setup.sh --resume --profile staging
```

這將下載您的已簽署憑證並產生 VPN 配置檔案(`.ovpn`)。

### 使用 VPN 客戶端連接

1. **下載 VPN 客戶端**：
   - **AWS VPN Client** (推薦)：
     - 下載：[AWS VPN Client](https://aws.amazon.com/vpn/client-vpn-download/)
     - 支援 macOS、Windows、Linux
   - **OpenVPN Connect**：
     - macOS：從 App Store 或 [OpenVPN 官網](https://openvpn.net/client-connect-vpn-for-mac-os/)
     - 其他平台：[OpenVPN 下載頁面](https://openvpn.net/vpn-client/)

2. **匯入配置**：
   - 在 `downloads/` 資料夾中找到 `.ovpn` 檔案
   - 匯入到您的 VPN 客戶端

3. **連接**：
   - 在 VPN 客戶端中選擇配置檔
   - 點擊連接

4. **自動斷線**：VPN 在靜置 54 分鐘後會自動斷線以節省成本

## 💻 日常 VPN 使用

### 使用 Slack 命令（推薦）

#### 啟動 VPN

```text
/vpn open staging     # 連接到 staging 環境
/vpn open production  # 連接到 production 環境
```

⏱️ **等待時間**：`/vpn open` 命令可能需要長達 **10 分鐘**才能完成，因為 AWS 需要配置 VPN 端點連接。您將在此過程中在 Slack 中看到狀態更新。

#### 停止 VPN

```text
/vpn close staging
/vpn close production
```

#### 檢查狀態

```text
/vpn check staging
/vpn check production
```

#### 檢視成本節省

```text
/vpn savings staging
```

## 🔧 疑難排解

### 常見問題與解決方案

#### “VPN endpoint is closed”

首先透過 Slack 開啟 VPN 端點：

```text
/vpn open staging
```

⏱️ **等待“🟢 Open”狀態**（最長 10 分鐘），然後連接您的 VPN 客戶端。AWS 需要時間來關聯子網路並配置端點。

#### "Connection timed out"

1. 檢查 VPN 端點狀態：`/vpn check staging`
2. 確保您的網路連線穩定
3. 嘗試斷線重連

#### "Certificate expired"

更新您的憑證：

```bash
./team_member_setup.sh --renew --profile staging
```

#### "Access denied to specific service"

聯絡管理員驗證您的安全群組權限。

### 取得協助

1. **Slack 支援**：在 #vpn-support 頻道發文
2. **檢查狀態**：`/vpn check [environment]`
3. **聯絡管理員**：聯繫 VPN 管理員

## ⚡ 快速參考

### 基本 Slack 命令

| 命令 | 用途 | 範例 |
|---------|---------|---------|
| `/vpn open [env]` | 啟動 VPN | `/vpn open staging` |
| `/vpn close [env]` | 停止 VPN | `/vpn close staging` |
| `/vpn check [env]` | 檢查狀態 | `/vpn check production` |
| `/vpn help` | 顯示所有命令 | `/vpn help` |

### 環境名稱

- `staging` (別名：`stage`, `dev`)
- `production` (別名：`prod`)

### 檔案位置

```text
certs/
├── staging/          # Staging 憑證
│   ├── ca.crt       # CA 憑證
│   ├── user.crt     # 您的憑證
│   └── user.key     # 您的私鑰 (請妥善保管！)
└── production/      # Production 憑證

downloads/
├── staging-vpn-config.ovpn    # Staging VPN 配置
└── production-vpn-config.ovpn  # Production VPN 配置
```

## 🔒 安全最佳實務

1. **保護您的私鑰**
   - 絕不分享 `.key` 檔案
   - 在安全位置保留本地備份
   - 如有洩露立即回報

2. **VPN 使用**
   - 僅在需要時連接
   - 完成後斷線
   - 不要分享 VPN 存取權限

3. **環境分離**
   - 使用 staging 進行開發/測試
   - 僅在必要時使用 production
   - 遵循變更管理程序

## 📊 成本優化

系統自動管理成本：

- 在靜置 54 分鐘後關閉空閒 VPN
- 追蹤使用情況和節省
- 防止 24/7 VPN 費用

檢視您團隊的節省：

```text
/vpn savings staging
/vpn costs daily
```

## 🆘 緊急程序

### 遺失私鑰

1. 立即通知管理員
2. 要求撤銷憑證
3. 產生新憑證

### 無法存取關鍵服務

1. 檢查 VPN 連線狀態
2. 驗證您在正確的環境中
3. 聯絡管理員獲得緊急存取

### 懷疑安全侵害

1. 立即斷開 VPN
2. 通知安全團隊
3. 更改 AWS 憑據
4. 要求新憑證

---

**需要管理員協助？** 聯絡您的 VPN 管理員或在 #vpn-support 發文
**需要技術細節？** 請參考 [架構文件](architecture.md)
