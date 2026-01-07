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
- 📊 即時成本追蹤
- 🚀 < 1 秒 Slack 回應時間

## 📅 VPN 自動化排程詳解 | Automation Schedule

### 每日排程流程 (Production)

```
┌─────────────────────────────────────────────────────────────────────────────┐
│  時間軸 (台灣時間 UTC+8)                                                      │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  10:00 ──┬── ⏰ 自動開啟 (Auto-Open)                                         │
│          │   VPN 端點開始關聯，約 5-10 分鐘完成                                 │
│          │                                                                  │
│  10:00 ──┼── 🛡️ 營業時間保護開始 (Business Hours Start)                      │
│    ↓     │   此期間不會自動關閉 VPN                                            │
│          │                                                                  │
│  17:00 ──┼── 🛡️ 營業時間保護結束 (Business Hours End)                        │
│          │   閒置偵測開始生效                                                  │
│          │                                                                  │
│  17:00+  │   ⏱️ 閒置偵測 (Idle Detection)                                    │
│    ↓     │   • 客戶端：100 分鐘無流量自動斷線                                    │
│          │   • 伺服器端：30 分鐘無連線自動關閉                                   │
│          │                                                                  │
│  ~19:10 ─┴── 🔴 自動關閉 (典型情境)                                           │
│              假設 17:00 後無使用，約 19:10 關閉                                 │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 週末排程 (Friday)

```
週五 20:00 ── 🌙 週末軟關閉 (Weekend Soft-Close)
              │
              ├── 無連線 → 立即關閉
              │
              └── 有連線 → 等待 30 分鐘後重試
                          持續重試直到所有連線結束
                          Slack 通知包含連線中的使用者名單
```

### 環境差異 | Environment Differences

| 設定 | Production | Staging |
|------|------------|---------|
| 自動開啟 (Auto-Open) | ✅ 預設啟用 | ❌ 預設關閉 |
| 自動關閉 (Auto-Close) | ✅ 預設啟用 | ✅ 預設啟用 |
| 營業時間保護 | ✅ 10:00-17:00 | ❌ 停用 |
| 週末軟關閉 | ✅ 週五 20:00 | ✅ 週五 20:00 |

### 完整行為矩陣 | Complete Behavior Matrix

| 時段 | Production | Staging |
|------|------------|---------|
| **平日 10:00 AM** | ⏰ 自動開啟 | ❌ 需手動開啟 |
| **平日 10AM-5PM** | 🛡️ 營業時間保護 (不自動關閉) | ⏱️ 閒置偵測立即生效 |
| **平日 5PM+** | ⏱️ 閒置偵測 (30分鐘→關閉) | ⏱️ 閒置偵測 (30分鐘→關閉) |
| **週五 8:00 PM** | 🌙 軟關閉 (等待連線結束) | 🌙 軟關閉 (等待連線結束) |
| **週六/週日** | ❌ 無自動開啟，手動開啟後閒置偵測生效 | ❌ 無自動開啟，手動開啟後閒置偵測生效 |

**主要差異：**
- **Production**: 有營業時間保護 (10AM-5PM) - 工作時間內即使閒置也不會自動關閉
- **Staging**: 無營業時間保護 - 閒置偵測 24/7 運作，閒置 30 分鐘後立即關閉

### 手動指令與自動排程的互動 | Manual vs Automatic

```
┌─────────────────────────────────────────────────────────────────┐
│  情境：自動開啟後，手動關閉再開啟                                    │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  10:00    ⏰ 自動開啟 (無手動活動記錄)                              │
│           │                                                     │
│  11:00    │  /vpn close prod (記錄手動活動 11:00)                 │
│           │  VPN 關閉                                            │
│           │                                                     │
│  11:30    │  /vpn open prod (記錄手動活動 11:30)                  │
│           │  VPN 開啟                                            │
│           │                                                     │
│  11:30-11:45  ⏸️ 15 分鐘寬限期 (Grace Period)                    │
│           │     此期間不會自動關閉                                  │
│           │                                                     │
│  11:45+   │  ✅ 正常閒置偵測恢復                                   │
│           │     (但仍受營業時間保護)                                │
│           │                                                     │
│  17:00+   └── 營業時間結束，閒置偵測完全生效                         │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 閒置偵測機制 | Idle Detection

**雙層保護設計：**

| 層級 | 觸發條件 | 超時時間 | 行為 |
|------|----------|----------|------|
| 客戶端 | 100 分鐘無實際流量 (10KB 閾值) | 100 分鐘 | OpenVPN 客戶端自動斷線 |
| 伺服器端 | 30 分鐘無任何連線 | 30 分鐘 | Lambda 自動關閉 VPN 端點 |

**重要說明：**
- 客戶端 keepalive 封包不會重置計時器
- 只有實際資料傳輸 (SSH、HTTP、資料庫查詢等) 才會重置計時器
- 伺服器端偵測每 3 分鐘執行一次檢查

### 保護機制總覽 | Protection Mechanisms

| 保護機制 | 適用範圍 | 說明 |
|----------|----------|------|
| 🛡️ 營業時間保護 | 僅自動關閉 | 10:00-17:00 期間不會自動關閉 |
| ⏸️ 15 分鐘寬限期 | 僅自動關閉 | 手動操作後 15 分鐘內不會自動關閉 |
| 🌙 週末軟關閉 | 週五 20:00 | 有連線時等待，不強制斷線 |
| 🔒 手動指令 | 永遠生效 | 手動 `/vpn close` 不受任何保護限制 |

### 排程控制指令 | Schedule Control Commands

```bash
# 檢視排程狀態
/vpn schedule status prod

# 啟用/停用所有自動排程
/vpn schedule on prod
/vpn schedule off prod

# 暫時停用 (指定時間後自動恢復)
/vpn schedule off prod 2h    # 停用 2 小時
/vpn schedule off prod 30m   # 停用 30 分鐘

# 個別控制自動開啟/關閉
/vpn schedule open on prod   # 僅啟用自動開啟
/vpn schedule open off prod  # 僅停用自動開啟
/vpn schedule close on prod  # 僅啟用自動關閉
/vpn schedule close off prod # 僅停用自動關閉
```

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

## 🏛️ 合規性 (Compliance)

合規性是指符合法規和行業標準的要求。

### 什麼時候合規性變得關鍵：

**1. 行業監管要求**
- 金融業：需符合 PCI DSS、SOX 法案
- 醫療業：需符合 HIPAA 規範
- 政府機構：需符合 FedRAMP、FISMA

**2. 客戶合約要求**
- 大企業客戶要求 SOC 2 Type II 認證
- 國際客戶要求 ISO 27001 認證
- 歐盟客戶要求 GDPR 合規

**3. 公司發展階段**
- 準備 IPO 上市
- 尋求大型投資
- 擴展到受監管市場

### Pritunl vs AWS Client VPN 在合規性的差異：

| 項目 | Pritunl VPN (自建) | AWS Client VPN |
|------|-------------------|----------------|
| 合規認證 | ❌ 需要自己負責所有合規文件 | ✅ AWS 已通過 SOC 1/2/3、ISO 27001、PCI DSS |
| 安全稽核 | ❌ 需要自己進行安全稽核 | ✅ 提供合規報告和文件 |
| 第三方認證 | ❌ 沒有第三方認證背書 | ✅ 共同責任模型，AWS 負責基礎設施合規 |

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

**版本**：3.4 | **狀態**：已可用於正式環境 | **最後更新**：2026-01-05
