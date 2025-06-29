# AWS Client VPN 使用者手冊

## 目錄

1. [簡介](#簡介)
2. [系統需求](#系統需求)
3. [初次設置流程](#初次設置流程)
4. [證書申請與管理](#證書申請與管理)
5. [VPN 客戶端配置](#vpn-客戶端配置)
6. [Slack 指令使用](#slack-指令使用)
7. [日常操作指南](#日常操作指南)
8. [故障排除](#故障排除)
9. [安全注意事項](#安全注意事項)
10. [常見問題解答](#常見問題解答)

## 簡介

歡迎使用 AWS Client VPN 雙環境管理系統！本手冊將引導您完成 VPN 設置、使用和管理的全部流程。

### 什麼是 Client VPN？

AWS Client VPN 是一種託管的客戶端 VPN 服務，讓您能夠安全地存取 AWS 資源和內部網路資源。透過本系統，您可以：

- 安全連接到公司的 AWS 環境
- 存取內部資料庫、應用程式和服務
- 在 Staging 和 Production 環境間切換
- 透過 Slack 輕鬆管理 VPN 連線

### 雙環境架構

本系統支援兩個獨立的環境：

- **Staging (測試環境) 🟡**：用於開發、測試和驗證
- **Production (正式環境) 🔴**：用於正式營運服務

## 系統需求

### 硬體需求
- macOS 10.15 (Catalina) 或更新版本
- 至少 4GB RAM
- 穩定的網路連線

### 軟體需求
- OpenVPN 客戶端或 AWS VPN Client
- Slack 桌面版或網頁版
- Terminal (終端機) 應用程式

### 必要權限
- AWS IAM 使用者帳號
- S3 存取權限（用於證書交換）
- Slack 工作區成員資格

## 初次設置流程

### 步驟總覽

```mermaid
graph LR
    A[開始] --> B[檢查權限]
    B --> C[生成證書請求]
    C --> D[等待管理員簽署]
    D --> E[下載並安裝證書]
    E --> F[配置 VPN 客戶端]
    F --> G[完成]
```

### 詳細步驟

#### 1. 檢查您的權限

首次使用前，請確認您有必要的權限：

```bash
# 檢查 S3 存取權限
./team_member_setup.sh --check-permissions
```

如果顯示權限不足，請聯繫管理員為您開通權限。

#### 2. 啟動設置程序

```bash
# 使用零接觸工作流程（推薦）
./team_member_setup.sh --init
```

系統會自動：
- 從 S3 下載 CA 證書
- 生成您的私鑰（保存在本地）
- 創建證書簽署請求（CSR）
- 上傳 CSR 到 S3

#### 3. 等待證書簽署

設置程序會暫停並顯示類似訊息：
```
⏸️  設置已暫停，等待管理員簽署您的證書...

請通知管理員您的 CSR 已準備好：
使用者名稱: your-username
CSR 位置: s3://vpn-csr-exchange/csr/your-username.csr

當管理員簽署完成後，請執行以下命令繼續：
./team_member_setup.sh --resume
```

#### 4. 完成設置

當管理員通知您證書已簽署後：

```bash
# 恢復設置流程
./team_member_setup.sh --resume
```

系統會自動：
- 從 S3 下載已簽署的證書
- 驗證證書有效性
- 生成 VPN 配置檔案
- 匯入證書到 AWS ACM

## 證書申請與管理

### 證書基礎知識

VPN 連線需要三個關鍵元件：

1. **CA 證書**：證書頒發機構的根證書
2. **客戶端證書**：您的個人證書（由 CA 簽署）
3. **私鑰**：配對您客戶端證書的私鑰

### 證書檔案位置

設置完成後，您的證書檔案會保存在：

```
certs/
├── staging/              # Staging 環境證書
│   ├── ca.crt           # CA 證書
│   ├── username.crt     # 您的客戶端證書
│   └── username.key     # 您的私鑰（請妥善保管！）
└── production/          # Production 環境證書
    ├── ca.crt
    ├── username.crt
    └── username.key
```

### 證書安全性

⚠️ **重要安全提示**：
- 私鑰檔案（.key）**絕對不要**分享給任何人
- 私鑰檔案權限已自動設為 600（僅您可讀寫）
- 定期備份您的證書到安全位置
- 如果私鑰洩露，立即通知管理員撤銷證書

## VPN 客戶端配置

### 選擇 VPN 客戶端

您可以使用以下任一客戶端：

1. **AWS VPN Client**（推薦）
   - 下載：[AWS VPN Client](https://aws.amazon.com/vpn/client-vpn-download/)
   - 原生支援 AWS Client VPN
   - 提供最佳相容性

2. **OpenVPN Connect**
   - 下載：[OpenVPN Connect](https://openvpn.net/vpn-client/)
   - 開源且廣泛使用
   - 支援進階配置選項

### 導入配置檔案

設置完成後，系統會生成 `.ovpn` 配置檔案：

```
downloads/
├── staging-vpn-config.ovpn      # Staging 環境配置
└── production-vpn-config.ovpn   # Production 環境配置
```

#### AWS VPN Client 導入步驟

1. 開啟 AWS VPN Client
2. 點擊 **File** → **Manage Profiles**
3. 點擊 **Add Profile**
4. 選擇對應的 `.ovpn` 檔案
5. 輸入易記的名稱（如 "Company Staging VPN"）

#### OpenVPN Connect 導入步驟

1. 開啟 OpenVPN Connect
2. 點擊 **+** 按鈕
3. 選擇 **Import Profile** → **FILE**
4. 選擇對應的 `.ovpn` 檔案
5. 點擊 **ADD**

### 進階 DNS 和路由配置

系統自動配置了智能 DNS 分流和路由，讓您能夠：

- 解析 AWS 內部服務域名（如 RDS、ElastiCache）
- 存取 EC2 實例的私有 DNS
- 連接到 EKS 集群 API
- 使用 EC2 metadata 服務

這些配置已包含在 `.ovpn` 檔案中，無需手動設定。

## Slack 指令使用

### 基本指令格式

```
/vpn <動作> <環境>
```

### 核心指令

#### 1. 開啟 VPN
```
/vpn open staging       # 開啟測試環境 VPN
/vpn open production    # 開啟正式環境 VPN
```

別名支援：
- `start`、`enable`、`on` 都等同於 `open`

#### 2. 關閉 VPN
```
/vpn close staging      # 關閉測試環境 VPN
/vpn close production   # 關閉正式環境 VPN
```

別名支援：
- `stop`、`disable`、`off` 都等同於 `close`

#### 3. 檢查狀態
```
/vpn check staging      # 檢查測試環境狀態
/vpn check production   # 檢查正式環境狀態
```

別名支援：
- `status`、`state`、`info` 都等同於 `check`

#### 4. 成本報告
```
/vpn savings staging    # 查看環境成本節省
/vpn costs daily        # 每日成本分析
/vpn costs cumulative   # 累積成本統計
```

#### 5. 幫助資訊
```
/vpn help              # 顯示完整指令說明
```

### 環境別名

為了方便使用，系統支援環境別名：

- `staging` = `stage`、`dev`
- `production` = `prod`

### Slack 回應說明

#### 成功回應範例
```
📶 VPN open completed for 🔧 Staging
Status: 🟢 Open
Active Connections: 0
```

#### 操作進行中回應
```
🟡 VPN Operation In Progress | VPN 操作進行中
Environment: Staging
Current Status: VPN subnets are currently associating
Action Required: Please wait for association to complete
Tip: Use /vpn check staging to monitor progress
```

#### 錯誤回應範例
```
❌ VPN open failed for 🔧 Staging
Error: VPN endpoint validation failed
```

## 日常操作指南

### 典型工作流程

#### 早上開始工作
1. 開啟 Slack
2. 執行 `/vpn open staging` 開啟測試環境
3. 在 VPN 客戶端連接到 "Company Staging VPN"
4. 開始您的開發工作

#### 需要存取正式環境
1. 執行 `/vpn check production` 確認狀態
2. 如果關閉，執行 `/vpn open production`
3. 在 VPN 客戶端切換到 "Company Production VPN"
4. 完成後記得關閉：`/vpn close production`

#### 下班前
1. 檢查您的 VPN 狀態
2. 如果忘記關閉也不用擔心 - 系統會在閒置 54 分鐘後自動關閉

### 系統效能優化

#### 快速響應保證

系統採用 Lambda 預熱技術，確保 Slack 指令的快速響應：

**響應時間保證：**
- **Slack 指令響應**：< 1 秒
- **VPN 操作完成**：通常 30-60 秒
- **狀態查詢**：< 3 秒

**預熱機制：**
- **營業時間**（9:00-18:00）：系統每 3 分鐘自動預熱
- **非營業時間**：每 15 分鐘預熱
- **週末**：每 30 分鐘預熱

**使用者體驗：**
- 無需等待系統「暖機」
- 指令執行立即回應
- 背景自動優化，使用者無感

### 自動成本優化

系統包含智能成本優化功能：

- **自動關閉**：閒置超過 54 分鐘自動關閉 VPN
- **成本節省**：防止 VPN 24/7 運行造成的浪費
- **即時重啟**：需要時可立即重新開啟
- **預熱成本**：月度約 $8-12，但節省 VPN 成本 $75+/月

當 VPN 被自動關閉時，您會收到 Slack 通知：
```
💰 Auto-Cost Optimization 🟡 staging
📊 Idle Time: 61 minutes (threshold: 54min)
💵 Waste Prevented: ~$1.20 saved
📱 Re-enable: Use /vpn open staging when needed
```

### 最佳實踐

1. **環境選擇**
   - 日常開發使用 Staging 環境
   - 只在必要時連接 Production 環境

2. **連線管理**
   - 不使用時關閉 VPN 連線
   - 利用自動關閉功能節省成本

3. **安全意識**
   - 在公共 WiFi 時始終使用 VPN
   - 定期檢查證書有效期
   - 保護好您的私鑰檔案

## 故障排除

### 常見問題

#### 1. 無法連接到 VPN

**症狀**：VPN 客戶端顯示連線失敗

**解決方案**：
```bash
# 檢查 VPN 狀態
/vpn check staging

# 如果顯示 Closed，先開啟 VPN
/vpn open staging

# 等待狀態變為 Open 後再連接
```

#### 2. 權限被拒絕錯誤

**症狀**：執行指令時顯示 "Access denied"

**解決方案**：
- 檢查您是否有該環境的權限
- Production 環境需要特殊授權
- 聯繫管理員確認權限設定

#### 3. 證書相關錯誤

**症狀**：VPN 客戶端報告證書錯誤

**解決方案**：
```bash
# 重新生成配置檔案
./team_member_setup.sh --regenerate-config

# 如果證書過期，需要重新申請
./team_member_setup.sh --renew
```

#### 4. VPN 自動斷線

**症狀**：連線一段時間後自動斷開

**可能原因**：
- VPN 被自動成本優化系統關閉
- 網路連線不穩定
- 客戶端逾時設定

**解決方案**：
- 檢查 Slack 是否有自動關閉通知
- 確認網路連線穩定
- 調整客戶端保持連線設定

### 診斷工具

系統提供多個診斷工具：

```bash
# 驗證本地配置
./admin-tools/tools/validate_config.sh

# 分析 VPN 連線問題
./admin-tools/run-vpn-analysis.sh
```

### 獲取協助

如果問題持續存在：

1. 收集錯誤訊息和截圖
2. 記錄問題發生的時間和環境
3. 聯繫管理員或在 Slack #vpn-support 頻道求助

## 安全注意事項

### 證書安全

1. **私鑰保護**
   - 永遠不要分享您的私鑰（.key 檔案）
   - 不要將私鑰上傳到任何地方
   - 使用強密碼保護您的電腦

2. **證書存儲**
   - 證書檔案應保存在安全位置
   - 定期備份到加密儲存裝置
   - 遺失時立即通知管理員

3. **連線安全**
   - 只從可信任的網路連接 VPN
   - 使用強密碼保護您的裝置
   - 啟用螢幕鎖定和自動登出

### 使用規範

1. **合規使用**
   - VPN 僅供工作用途
   - 不得用於下載非法內容
   - 遵守公司安全政策

2. **環境隔離**
   - 不要在 Production 環境進行測試
   - 謹慎操作生產資料
   - 遵循變更管理流程

3. **監控與審計**
   - 所有 VPN 活動都會被記錄
   - 定期審查存取日誌
   - 配合安全審計要求

## 常見問題解答

### Q1: 為什麼 VPN 會自動關閉？

**A**: 系統包含成本優化功能，當 VPN 閒置超過 54 分鐘會自動關閉以節省成本。這可以防止忘記關閉 VPN 造成的不必要費用。

### Q2: 我可以同時連接兩個環境嗎？

**A**: 不行。您一次只能連接到一個環境（Staging 或 Production）。如需切換環境，請先斷開當前連線。

### Q3: 證書的有效期是多久？

**A**: 客戶端證書通常有效期為 1 年。系統會在證書即將過期前 30 天開始提醒您更新。

### Q4: 如果私鑰洩露了怎麼辦？

**A**: 立即執行以下步驟：
1. 通知管理員撤銷現有證書
2. 刪除本地所有證書檔案
3. 重新執行設置流程申請新證書

### Q5: 為什麼我看不到某些內部服務？

**A**: 請確認：
1. VPN 已正確連接
2. 您連接到正確的環境
3. 您有該服務的存取權限
4. 安全群組規則允許存取

### Q6: 可以在手機上使用 VPN 嗎？

**A**: 目前系統主要支援 macOS。行動裝置支援正在規劃中。

### Q7: 如何查看我的 VPN 使用統計？

**A**: 使用以下 Slack 指令：
- `/vpn savings staging` - 查看成本節省
- `/vpn costs daily` - 每日使用統計
- `/vpn costs cumulative` - 累積統計

### Q8: VPN 連線速度很慢怎麼辦？

**A**: 嘗試以下方法：
1. 檢查您的網路連線品質
2. 選擇離您較近的 AWS 區域
3. 避免在尖峰時段使用
4. 聯繫管理員優化路由設定

---

## 聯絡資訊

- **技術支援**：GitHub Issues
- **緊急問題**：ct@newsleopard.tw
- **文件更新**：提交 PR 到 GitHub

---

**文件版本**：1.0  
**最後更新**：2025-06-29  
**適用系統版本**：3.0+  
**開發團隊**：[Newsleopard 電子豹](https://newsleopard.com)