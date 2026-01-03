# AWS Client VPN 管理工具套件

一套結合基礎架構即程式碼、無伺服器架構和智慧成本優化的企業級 AWS 雙環境 VPN 管理系統。

## 🎯 功能介紹

跨 staging 和 production 環境自動化 AWS Client VPN 管理，具備以下功能：

- **Slack 控制 VPN 操作** - 透過簡單指令開啟/關閉 VPN
- **智慧成本優化** - 自動關閉閒置 VPN（100分鐘無流量自動斷線）
- **零接觸憑證工作流程** - 透過 S3 自動化 CSR/憑證交換
- **雙環境隔離** - staging 和 production 完全分離

## 💰 成本節省

**相較於 24/7 VPN 運作：**

- 年度節省：**$900-1,200**（減少 57-74%）
- 月度成本：**$35-57** vs 傳統 **$132**
- 自動關閉防止忘記斷線而產生費用

## 🚀 快速開始

### 團隊成員

需要 VPN 存取權限？請參考 [**使用者指南**](docs/user-guide.md)

```bash
./team_member_setup.sh --init --profile staging
```

### 系統管理員

管理 VPN 和使用者？請參考 [**管理員指南**](docs/admin-guide.md)

```bash
./admin-tools/aws_vpn_admin.sh --profile staging
```

### DevOps 工程師

部署系統？請參考 [**部署指南**](docs/deployment-guide.md)

```bash
./scripts/deploy.sh both --secure-parameters
```

## 📚 文件導覽中心

選擇符合您角色的指南：

| 指南 | 對象 | 用途 |
|-------|----------|---------|
| [**使用者指南**](docs/user-guide.md) | 工程團隊成員 | VPN 設定、日常使用、疑難排解 |
| [**管理員指南**](docs/admin-guide.md) | VPN 系統管理員 | 使用者管理、憑證管理、監控 |
| [**管理員交接指南**](docs/admin-handover-guide.md) | 系統管理員 | 管理員權限轉移、安全交接流程 |
| [**部署指南**](docs/deployment-guide.md) | DevOps 開發者 | 系統部署、維護、復原 |
| [**架構文件**](docs/architecture.md) | 技術深度解析 | 系統設計、安全性、演算法 |

## 🛠️ 主要功能

### Slack 整合

```text
/vpn open staging      # 啟動 VPN
/vpn close production  # 關閉 VPN
/vpn check staging     # 檢查狀態
/vpn savings staging   # 檢視成本節省
```

### 排程管理 | Schedule Management

```text
/vpn schedule on staging       # 啟用自動排程 | Enable auto-schedule
/vpn schedule off staging      # 停用自動排程 | Disable auto-schedule
/vpn schedule off staging 2h   # 停用 2 小時 | Disable for 2 hours
/vpn schedule check staging    # 檢查排程狀態 | Check schedule status
/vpn schedule open on staging  # 僅啟用自動開啟 | Enable auto-open only
/vpn schedule close off staging # 停用自動關閉 | Disable auto-close only
/vpn schedule help             # 排程指令說明 | Schedule command help
```

### 安全功能

- 🔐 憑證式身份驗證
- 🛡️ 每個環境專用安全群組
- 🔑 SSM 中的 KMS 加密機密
- 📝 透過 CloudTrail 完整稽核追蹤

### 自動化

- ⚡ Lambda 驅動的無伺服器架構
- 🌅 平日自動開啟 VPN（週一至週五 9:30 台灣時間，Production 預設啟用）
- 🔄 雙層閒置偵測：客戶端 100 分鐘 + 伺服器端 30 分鐘
- 🛡️ 營業時間保護（9:30-17:30 不自動關閉）
- 🌙 週末軟關閉（週五 20:00，尊重活躍連線）
- ⏰ Slack 排程管理（可動態啟用/停用自動排程）
- 📊 即時成本追蹤
- 🚀 < 1 秒 Slack 回應時間

> **環境差異**：Production 預設自動開啟，Staging 預設關閉需手動啟用

## 🏗️ 系統架構

```text
Slack → API Gateway → Lambda Functions → AWS Client VPN
                           ↓
                    SSM Parameter Store
```

**組件：**

- **雙 AWS 環境**：Staging + Production 隔離
- **無伺服器後端**：Lambda + API Gateway + EventBridge
- **智慧監控**：具成本優化的自動關閉
- **安全儲存**：憑證使用 S3，設定使用 SSM

## 📋 系統需求

- macOS 10.15+ (Catalina 或更新版本)
- 已設定雙設定檔的 AWS CLI v2
- Node.js 20+ 和 npm
- Slack 工作區管理員權限

## ⚡ 安裝

### 1. 複製與設定

```bash
git clone https://github.com/your-org/aws-client-vpn-toolkit.git
cd aws-client-vpn-toolkit

# 設定 AWS 設定檔
aws configure --profile staging
aws configure --profile production
```

### 2. 部署基礎架構

```bash
./scripts/deploy.sh both --secure-parameters \
  --staging-profile staging \
  --production-profile production
```

### 3. 設定 Slack

從部署輸出取得 API Gateway URL 並在 Slack App 設定中配置。

## 🔧 常見操作

### 團隊成員上線

```bash
# 管理員：新增使用者權限
./admin-tools/manage_vpn_users.sh add username --profile staging

# 使用者：設定 VPN 存取
./team_member_setup.sh --init --profile staging
```

### 日常 VPN 使用

```bash
# 透過 Slack（推薦）
/vpn open staging
/vpn close staging

# 檢查狀態
/vpn check staging
```

### 成本監控

```bash
# 檢視節省報告
/vpn savings staging

# 詳細分析
./admin-tools/run-vpn-analysis.sh --profile staging
```

## 🆘 支援

- **文件**：請參考上方符合您角色的指南
- **問題回報**：[GitHub Issues](https://github.com/your-org/aws-client-vpn-toolkit/issues)
- **Slack 支援**：#vpn-support 頻道

## 📄 授權

MIT License - 請參閱 [LICENSE](LICENSE) 檔案

## 🏢 關於

由 [Newsleopard 電子豹](https://newsleopard.com) 建置 - 企業級 AWS 解決方案

---

**版本**：3.3 | **狀態**：已可用於正式環境 | **最後更新**：2026-01-03