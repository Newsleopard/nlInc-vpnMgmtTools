# VPN 管理員指南

本指南為 VPN 管理員提供管理 AWS Client VPN 系統、使用者和憑證的程序和工具。

## 📑 目錄

- [本指南適用對象](#-本指南適用對象)
- [管理員工作流程](#-管理員工作流程)
- [管理員職責](#-管理員職責)
- [新管理員快速入門](#-新管理員快速入門)
- [使用者管理](#-使用者管理)
- [憑證管理](#-憑證管理)
- [VPN 端點管理](#-vpn-端點管理)
- [監控和報告](#-監控和報告)
- [事件響應](#-事件響應)
- [管理工具參考](#️-管理工具參考)
- [成本管理](#-成本管理)
- [排程管理](#-排程管理)
- [安全最佳實踐](#-安全最佳實踐)
- [管理程序](#-管理程序)
- [管理員交接](#-管理員交接)
- [取得協助](#-取得協助)

## 🎯 本指南適用對象

- VPN 系統管理員
- 安全團隊成員
- IT 營運人員
- 管理存取權限的團隊主管

## 📈 管理員工作流程

### 憑證管理流程

```mermaid
flowchart LR
    subgraph User Side
        U1[User Generates CSR] --> U2[Uploads CSR to S3]
        U2 --> U3[Notifies Admin]
    end

    subgraph Admin Side
        U3 --> A1{Review CSR}
        A1 -->|Approve| A2[Sign Certificate]
        A1 -->|Reject| A3[Notify User]
        A2 --> A4[Upload Cert to S3]
        A4 --> A5[Notify User]
    end

    subgraph User Completion
        A5 --> U4[User Downloads Cert]
        U4 --> U5[Configure VPN]
        U5 --> U6[Connect to VPN]
    end

    style U1 fill:#e3f2fd
    style A2 fill:#ffecb3
    style U6 fill:#c8e6c9
```

### 使用者入職流程

```mermaid
flowchart TD
    Start([New Employee]) --> CreateUser{IAM User\nExists?}

    CreateUser -->|No| CreateIAM[Create IAM User]
    CreateUser -->|Yes| CheckPerms
    CreateIAM --> CheckPerms[Check Permissions]

    CheckPerms --> GrantPerms[Grant VPN Permissions]
    GrantPerms --> InitS3[Setup S3 Access]

    InitS3 --> NotifyUser[Notify User to\nStart Setup]
    NotifyUser --> UserGen[User Generates CSR]

    UserGen --> AdminSign[Admin Signs Cert]
    AdminSign --> TestConn[User Tests Connection]

    TestConn --> VerifySG{Security Groups\nCorrect?}
    VerifySG -->|No| UpdateSG[Update Security Groups]
    VerifySG -->|Yes| Complete
    UpdateSG --> Complete([Access Ready])

    style Start fill:#e1f5fe
    style Complete fill:#c8e6c9
    style AdminSign fill:#fff9c4
```

## 📋 管理員職責

### 核心職責
1. **使用者管理** - 新增/移除 VPN 存取權限
2. **憑證管理** - 簽署 CSR、撤銷憑證
3. **系統監控** - 追蹤使用情況、成本和健康狀態
4. **事件響應** - 處理安全事件和服務中斷

### 所需的 AWS 權限
- EC2 VPN 端點管理
- IAM 使用者和政策管理
- S3 存取（憑證交換）
- SSM Parameter Store 存取
- CloudWatch 日誌和指標

## 🚀 新管理員快速入門

### 1. 設定管理員存取
```bash
# 設定 AWS 設定檔
aws configure --profile staging
aws configure --profile production

# 驗證存取
aws sts get-caller-identity --profile staging
aws sts get-caller-identity --profile production
```

### 2. 啟動管理控制台
```bash
# 自動偵測並選擇 AWS profile（推薦）
./admin-tools/aws_vpn_admin.sh

# 或指定特定 profile（可選）
./admin-tools/aws_vpn_admin.sh --profile staging
```

### 3. 驗證系統存取
```bash
# 測試基本 VPN 管理功能（自動選擇 profile）
./admin-tools/aws_vpn_admin.sh

# 或指定特定 profile
./admin-tools/aws_vpn_admin.sh --profile staging
```

**註：** S3 憑證交換系統的初始部署和基礎設施設定請參閱 [部署指南](deployment-guide.md)。

## 👥 使用者管理

### 新增使用者

#### 步驟 1：授予 AWS 權限
```bash
# 為現有使用者新增 VPN 權限
./admin-tools/manage_vpn_users.sh add john.doe --profile staging

# 建立具有 VPN 存取權的新 IAM 使用者
./admin-tools/manage_vpn_users.sh add jane.smith --create-user --profile staging
```

#### 步驟 2：處理憑證請求
當使用者提交 CSR 時：
```bash
# 簽署憑證並上傳至 S3（僅需使用者名稱，無需 .csr 副檔名）
./admin-tools/sign_csr.sh --upload-s3 username --profile staging
```

#### 步驟 3：驗證存取
```bash
# 檢查使用者權限
./admin-tools/manage_vpn_users.sh status john.doe --profile staging

# 列出所有 VPN 使用者
./admin-tools/manage_vpn_users.sh list --profile staging
```

### 批次使用者操作

建立 `users.txt`：

```text
john.doe
jane.smith
bob.wilson
```

新增多個使用者：
```bash
./admin-tools/manage_vpn_users.sh batch-add users.txt --profile staging
```

### 移除使用者存取

#### 標準移除
```bash
# 僅移除 VPN 權限
./admin-tools/manage_vpn_users.sh remove john.doe --profile staging

# 撤銷憑證
./admin-tools/revoke_member_access.sh john.doe --profile staging
```

#### 完整離職
⚠️ **警告**：這將永久刪除 IAM 使用者和所有存取權
```bash
./admin-tools/employee_offboarding.sh --profile production
```

## 📜 憑證管理

### 憑證生命週期管理

```mermaid
stateDiagram-v2
    [*] --> Generated: User creates CSR
    Generated --> Pending: CSR uploaded to S3
    Pending --> Signed: Admin approves
    Pending --> Rejected: Admin rejects
    Signed --> Active: User downloads & configures
    Active --> Expiring: < 30 days remaining
    Expiring --> Renewed: User renews cert
    Active --> Revoked: Admin revokes
    Expiring --> Expired: No action taken
    Expired --> [*]
    Revoked --> [*]
    Rejected --> Generated: User resubmits
    Renewed --> Active: New cert active

    note right of Active: Valid for 1 year
    note right of Revoked: User loses access
```

### 憑證工作流程

1. **使用者產生 CSR** → 上傳至 S3
2. **管理員簽署憑證** → 上傳至 S3
3. **使用者下載憑證** → 設定 VPN

### 簽署憑證

#### 個別簽署
```bash
# 簽署 CSR（僅需使用者名稱，自動從 S3 下載 CSR）
./admin-tools/sign_csr.sh --upload-s3 username --profile staging
```

#### 批次處理
```bash
# 監控並自動簽署新的 CSR
./admin-tools/process_csr_batch.sh monitor -e staging

# 處理所有待處理的 CSR
./admin-tools/process_csr_batch.sh download -e staging
./admin-tools/process_csr_batch.sh process -e staging
./admin-tools/process_csr_batch.sh upload --auto-upload
```

### 憑證撤銷
```bash
# 互動式撤銷
./admin-tools/revoke_member_access.sh

# 特定使用者
./admin-tools/revoke_member_access.sh john.doe --profile staging
```

## 🔧 VPN 端點管理

⏱️ **重要時間提醒**：由於 AWS 子網路關聯和安全群組設定流程，VPN 端點操作（開啟/關聯）可能需要最多 **10 分鐘**才能完成。請始終預留充足的時間讓操作完成。

### VPN 操作流程

```mermaid
sequenceDiagram
    participant User
    participant Slack
    participant Lambda
    participant VPN
    participant Monitor

    User->>Slack: /vpn open staging
    Slack->>Lambda: Process command
    Lambda->>VPN: Associate subnets
    VPN-->>Lambda: Status: Associating
    Lambda-->>Slack: VPN opening...
    Slack-->>User: 🟪 Opening VPN

    Note over VPN: Up to 10 minutes

    VPN-->>Lambda: Status: Associated
    Lambda-->>Slack: VPN ready
    Slack-->>User: 🟢 VPN Open

    User->>VPN: Connect client
    VPN-->>User: Connected

    Note over Monitor: Every 5 minutes
    Monitor->>VPN: Check idle time
    Monitor->>VPN: If idle > 30min
    Monitor->>VPN: Disassociate
    Monitor->>Slack: Send notification
    Slack-->>User: 💰 Auto-closed
```

### 使用管理控制台
```bash
# 自動選擇 profile（推薦）
./admin-tools/aws_vpn_admin.sh

# 或指定特定 profile
./admin-tools/aws_vpn_admin.sh --profile staging
```

選單選項：
1. **建立 VPN 端點** - 設定新 VPN
2. **檢視端點** - 檢查狀態
3. **管理團隊成員** - 使用者操作
4. **產生用戶端設定** - 建立 .ovpn 檔案
5. **刪除端點** - 移除 VPN

### 手動端點操作

#### 建立端點
```bash
# 透過管理控制台（建議）
./admin-tools/aws_vpn_admin.sh
# 選擇選項 1
```

#### 修復常見問題
```bash
# 修復端點 ID 不符
./admin-tools/tools/fix_endpoint_id.sh

# 修復網際網路存取
./admin-tools/tools/fix_internet_access.sh

# 驗證設定
./admin-tools/tools/validate_config.sh
```

## 📊 監控和報告

### 每日監控任務

#### 檢查系統健康狀態
```bash
# VPN 狀態概覽
./admin-tools/aws_vpn_admin.sh

# 活動連線
aws ec2 describe-client-vpn-connections \
  --client-vpn-endpoint-id cvpn-endpoint-xxxxx \
  --profile staging
```

#### 成本監控
```bash
# 產生成本分析
./admin-tools/run-vpn-analysis.sh --profile staging

# 透過 Slack 檢視
/vpn savings staging
/vpn costs daily
```

### 自動化報告

#### 設定每週報告
```bash
# 排程每週分析
crontab -e
# 新增：0 9 * * MON /path/to/admin-tools/run-vpn-analysis.sh --format markdown
```

### CloudWatch 監控

檢視 Lambda 日誌：
```bash
# Slack 處理程式日誌
aws logs tail /aws/lambda/vpn-slack-handler-staging --follow --profile staging

# 監控錯誤
aws logs filter-log-events \
  --log-group-name /aws/lambda/vpn-control-staging \
  --filter-pattern "ERROR" \
  --profile staging
```

## 🚨 事件響應

### VPN 服務中斷

1. **檢查端點狀態**：
```bash
aws ec2 describe-client-vpn-endpoints --profile staging
```

2. **透過 Slack 重新啟動 VPN**：
```text
/vpn open staging
```

⏱️ **注意**：請預留最多 10 分鐘讓 VPN 端點完全關聯並可用。

3. **檢查 Lambda 函數**：
```bash
./scripts/deploy.sh status
```

4. **緊急重新部署**：
```bash
./scripts/deploy.sh staging --secure-parameters
```

### 安全事件

1. **立即行動**：
```bash
# 撤銷受損憑證
./admin-tools/revoke_member_access.sh compromised-user --profile production

# 中斷所有使用者連線
/vpn close production
```

2. **調查**：
```bash
# 檢查存取日誌
aws cloudtrail lookup-events \
  --lookup-attributes AttributeKey=EventName,AttributeValue=AuthorizeClientVpnIngress \
  --profile production
```

3. **復原**：
- 重新產生憑證
- 更新安全群組
- 通知受影響的使用者

### 成本異常

1. **檢查自動關閉狀態**：
```
/vpn admin cooldown staging
```

2. **必要時強制關閉**：
```
/vpn admin force-close staging
```

3. **調整閒置逾時**：
```bash
aws ssm put-parameter \
  --name "/vpn/staging/cost/optimization_config" \
  --value '{"idleTimeoutMinutes":30}' \
  --overwrite \
  --profile staging
```

## 🛠️ 管理工具參考

### 必要工具

| 工具 | 用途 | 使用方式 |
|------|---------|-------|
| `aws_vpn_admin.sh` | 主要管理控制台 | `./admin-tools/aws_vpn_admin.sh --profile staging` |
| `manage_vpn_users.sh` | 使用者管理 | `./admin-tools/manage_vpn_users.sh add user` |
| `sign_csr.sh` | 憑證簽署 | `./admin-tools/sign_csr.sh --upload-s3 username` |
| `setup_csr_s3_bucket.sh` | S3 設定 | `./admin-tools/setup_csr_s3_bucket.sh --publish-assets` |
| `run-vpn-analysis.sh` | 成本分析 | `./admin-tools/run-vpn-analysis.sh --profile staging` |

### 診斷工具

| 工具 | 用途 | 使用時機 |
|------|---------|-------------|
| `validate_config.sh` | 檢查設定 | 設定問題 |
| `fix_endpoint_id.sh` | 修復端點不符 | ID 錯誤 |
| `fix_internet_access.sh` | 修復路由 | 無法透過 VPN 上網 |
| `debug_vpn_creation.sh` | 除錯建立 | 端點建立失敗 |

## 💰 成本管理

### 成本最佳化功能

- **自動關閉**：閒置 100 分鐘（無實際流量）後自動斷線
- **工作時間保護**：防止在工作時間關閉
- **管理員覆寫**：維護期間停用自動關閉

### 管理自動關閉

```bash
# 停用自動關閉 24 小時
/vpn admin noclose staging

# 重新啟用自動關閉
/vpn admin autoclose staging

# 檢查冷卻狀態
/vpn admin cooldown staging
```

### 成本分析
```bash
# 月度成本報告
./admin-tools/run-vpn-analysis.sh --start-date 2025-01-01 --end-date 2025-01-31

# 比較環境
/vpn costs cumulative
```

## ⏰ 排程管理

VPN 系統具備自動排程功能，管理員可透過 Slack 命令動態控制自動開啟和自動關閉行為。

### 排程功能概覽

| 功能 | 說明 | 預設狀態 |
|------|------|----------|
| **自動開啟 (Auto-Open)** | 平日 9:30 台灣時間自動開啟 VPN | Production=啟用, Staging=停用 |
| **自動關閉 (Auto-Close)** | 伺服器端閒置 30 分鐘後自動關閉（客戶端 100 分鐘 + 伺服器端 30 分鐘） | 停用 |
| **營業時間保護** | 9:30-17:30 期間不自動關閉 | 啟用 |
| **週末軟關閉** | 週五 20:00，尊重活躍連線（30 分鐘重試） | 啟用 |

### Slack 排程命令

#### 基本命令

```text
/vpn schedule on staging       # 啟用所有自動排程
/vpn schedule off staging      # 停用所有自動排程（永久）
/vpn schedule off staging 2h   # 停用 2 小時後自動恢復
/vpn schedule check staging    # 檢查目前排程狀態
/vpn schedule help             # 顯示排程命令說明
```

#### 細粒度控制

```text
/vpn schedule open on staging   # 僅啟用自動開啟
/vpn schedule open off staging  # 僅停用自動開啟
/vpn schedule close on staging  # 僅啟用自動關閉
/vpn schedule close off staging # 僅停用自動關閉
```

### 常見使用情境

#### 情境 1：維護期間停用自動排程

進行系統維護時，暫時停用自動排程以避免干擾：

```text
# 停用 4 小時進行維護
/vpn schedule off production 4h

# 維護完成後手動恢復（如果需要提前恢復）
/vpn schedule on production
```

#### 情境 2：週末或假日停用自動開啟

假日期間不需要自動開啟 VPN：

```text
# 停用自動開啟 3 天
/vpn schedule open off staging 3d

# 或永久停用直到手動恢復
/vpn schedule open off staging
```

#### 情境 3：長時間作業停用自動關閉

進行長時間資料處理時，防止 VPN 被自動關閉：

```text
# 停用自動關閉 8 小時
/vpn schedule close off production 8h
```

### 持續時間格式

| 格式 | 說明 | 範例 |
|------|------|------|
| `Nh` | N 小時 | `2h`, `24h` |
| `Nd` | N 天 | `1d`, `7d` |

### 排程狀態檢查

執行 `/vpn schedule check staging` 會顯示：

```text
📅 VPN 排程狀態 | VPN Schedule Status
環境 | Environment: staging

🌅 自動開啟 | Auto-Open: ✅ 啟用 | Enabled
   下次排程時間 | Next scheduled: 2026-01-05 09:30 (Mon)

🔄 自動關閉 | Auto-Close: ⏸️ 停用 | Disabled
   剩餘時間 | Remaining: 1h 30m
   將於 | Re-enables at: 2026-01-03 15:00

🛡️ 營業時間保護 | Business Hours Protection: ✅ 啟用 | Enabled
   時段 | Hours: 09:30 - 17:30 (Asia/Taipei)

🌙 週末軟關閉 | Weekend Soft-Close: ✅ 啟用 | Enabled
   時間 | Time: 週五 20:00 (尊重活躍連線)

最後修改 | Last modified: 2026-01-03 13:30 by admin_user
```

### 排程狀態儲存

排程狀態儲存在 AWS Parameter Store：

```text
/vpn/automation/schedule/{environment}/state
```

狀態包含：
- 自動開啟/關閉的啟用狀態
- 最後修改時間和修改者
- 到期時間（如果設定了持續時間）

### 疑難排解

#### 排程命令無回應

1. 確認您有該環境的管理權限
2. 檢查 Lambda 函數日誌：
   ```bash
   aws logs tail /aws/lambda/vpn-slack-handler-staging --follow --profile staging
   ```

#### 排程狀態不正確

1. 檢查 Parameter Store 中的狀態：
   ```bash
   aws ssm get-parameter \
     --name "/vpn/automation/schedule/staging/state" \
     --profile staging
   ```

2. 如需重置，可手動更新 Parameter Store 或執行：
   ```text
   /vpn schedule on staging
   ```

#### 自動排程未按預期執行

1. 確認排程已啟用：`/vpn schedule check staging`
2. 檢查 VPN Monitor Lambda 日誌
3. 確認 EventBridge 規則正常運作

## 🕐 閒置偵測與軟關閉

### 閒置偵測運作方式

VPN Monitor Lambda 每 5 分鐘執行一次：
1. 從 AWS EC2 API 取得活躍連線
2. 比較目前流量位元組與上次快照
3. 判斷連線是否有實際流量或處於閒置狀態

### 閾值設定

| 參數 | 預設值 | 說明 |
|------|--------|------|
| `IDLE_MINUTES` | 30 | 一般閒置偵測閾值 |
| `SOFT_CLOSE_IDLE_THRESHOLD_MINUTES` | 60 | 軟關閉閒置閾值 |
| `COOLDOWN_MINUTES` | 30 | 防止快速開關循環 |

### 軟關閉（週末/排程）

軟關閉由排程事件觸發（如週五 20:00）。與強制關閉不同：

1. **檢查活躍連線** - 關閉前先確認
2. **有連線則延遲** - 每 30 分鐘重試一次
3. **監控流量狀態** - 閒置連線（60+ 分鐘）會被關閉
4. **傳送 Slack 通知** - 奇數次重試時通知（1, 3, 5...）

### Slack 通知類型

**有活躍流量的連線：**
```
⏳ VPN production close delayed again

👥 Connections: 1
👤 Users: username
📊 Traffic Status: active
🔄 Retry Attempt: #3
⏰ Next Check: 2026/1/17 下午8:30:00
💡 Note: Respecting active connections with recent traffic
```

**閒置連線被關閉：**
```
🌙 VPN production soft close completed

📍 Environment: production
🕤 Time: 2026/1/17 下午8:30:00
👤 Users Disconnected: username
⏱️ Idle Duration: 65min (threshold: 60min)
💡 Note: Closed idle connections after 60+ minutes of inactivity
```

**一般閒置偵測關閉：**
```
💰 Auto VPN Cost Optimization

🚀 Environment: Production
📊 Idle Duration: 35 minutes (threshold: 30min)
💵 Waste Prevented: ~$0.80 saved
🔧 Action Taken: Subnets auto-disassociated
📱 Re-enable: /vpn open production
```

### 手動驗證連線狀態

```bash
# 檢查實際連線
aws ec2 describe-client-vpn-connections \
  --client-vpn-endpoint-id cvpn-endpoint-XXXXX \
  --filters "Name=status,Values=active" \
  --profile production \
  --output table

# 檢查待處理關閉狀態
aws ssm get-parameter \
  --name "/vpn/production/automation/pending_close" \
  --profile production \
  --query 'Parameter.Value' \
  --output text
```

## 🔒 安全最佳實踐

### 憑證安全
1. **CA 金鑰保護**
   - 離線儲存於加密儲存空間
   - 絕不提交至儲存庫
   - 限制 2-3 位管理員存取

2. **憑證生命週期**
   - 設定 1 年到期
   - 追蹤到期日期
   - 每 2-3 年輪換 CA

### 存取控制
1. **最小權限原則**
   - 授予最少必要權限
   - 定期存取檢視（每月）
   - 移除未使用的帳戶

2. **環境分離**
   - 每個環境使用不同憑證
   - 建議使用獨立的 AWS 帳戶
   - 禁止跨環境存取

### 稽核與合規
1. **啟用 CloudTrail**
2. **定期安全稽核**
3. **記錄所有存取變更**
4. **維護撤銷清單**

## 📋 管理程序

### 每日任務（5 分鐘）

- [ ] 檢查 VPN 端點狀態
- [ ] 處理待處理的 CSR
- [ ] 檢視錯誤日誌

### 每週任務（15 分鐘）

- [ ] 產生使用報告
- [ ] 檢視使用者權限
- [ ] 檢查憑證到期

### 每月任務（30 分鐘）

- [ ] 完整存取稽核
- [ ] 成本分析檢視
- [ ] 更新文件
- [ ] 測試災難復原

## 🔄 管理員交接

當需要將 VPN 系統管理權限轉移給其他管理員時，請使用專門的交接工具和流程：

### 管理員交接工具

```bash
# 既有管理員匯出系統設定和憑證
./admin-tools/admin-handover-export.sh

# 新任管理員匯入設定檔案
./admin-tools/admin-handover-import.sh vpn-handover-YYYYMMDD-HHMMSS.tar.gz.enc
```

### 適用情況
- 管理員職務異動或離職
- 新管理員加入團隊
- 緊急情況下的權限委派
- 系統維護權限轉移

### 完整交接流程
詳細的交接步驟、安全注意事項和驗證檢查清單，請參閱：

📖 **[管理員交接指南](admin-handover-guide.md)**

該指南包含：
- 交接前準備事項
- 安全的檔案和密碼傳遞方式
- 自動化交接工具使用說明
- 交接驗證檢查清單
- 常見問題排解

## 🆘 取得協助

### 內部資源
- Slack：#vpn-admin 頻道
- Wiki：內部 VPN 文件
- 團隊：security@company.com

### 外部資源
- [AWS Client VPN 文件](https://docs.aws.amazon.com/vpn/latest/clientvpn-admin/)
- [GitHub Issues](https://github.com/your-org/vpn-toolkit/issues)
- AWS 支援控制台

---

**部署相關：**請參閱[部署指南](deployment-guide.md)
**架構相關：**請參閱[架構文件](architecture.md)