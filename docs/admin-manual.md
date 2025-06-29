# AWS Client VPN 管理員手冊

## 目錄

1. [管理員職責概述](#管理員職責概述)
2. [環境管理](#環境管理)
3. [證書管理](#證書管理)
4. [使用者權限管理](#使用者權限管理)
5. [VPN 端點管理](#vpn-端點管理)
6. [S3 證書交換系統](#s3-證書交換系統)
7. [Slack 管理指令](#slack-管理指令)
8. [監控與報告](#監控與報告)
9. [故障處理](#故障處理)
10. [安全最佳實踐](#安全最佳實踐)
11. [管理工具參考](#管理工具參考)

## 管理員職責概述

作為 AWS Client VPN 系統管理員，您的主要職責包括：

### 核心職責

1. **證書管理**
   - 簽發團隊成員的證書請求
   - 撤銷離職員工的證書
   - 維護 CA 證書安全

2. **使用者管理**
   - 新增和移除使用者權限
   - 管理 IAM 政策分配
   - 處理權限問題

3. **環境維護**
   - 管理 Staging 和 Production 環境
   - 監控系統健康狀態
   - 處理故障和異常

4. **成本控制**
   - 監控 VPN 使用情況
   - 優化成本設定
   - 生成成本報告

### 權限要求

管理員需要以下 AWS 權限：
- EC2 VPN 端點管理權限
- ACM 證書管理權限
- IAM 使用者和政策管理權限
- S3 存取權限（證書交換桶）
- CloudWatch 日誌讀取權限

## 環境管理

### 環境架構

系統支援兩個獨立環境：

```
環境結構：
├── Staging (測試環境) 🟡
│   ├── 用途：開發、測試、驗證
│   ├── 安全等級：標準
│   └── 確認要求：簡化
│
└── Production (正式環境) 🔴
    ├── 用途：正式營運
    ├── 安全等級：最高
    └── 確認要求：多重確認
```

### 環境切換操作

#### 查看當前環境
```bash
./admin-tools/vpn_env.sh status
```

輸出範例：
```
=== VPN Environment Status ===
Current Environment: staging
AWS Profile: staging-vpn-admin
Account ID: 123456789012
Region: us-east-1
Health: ✅ Healthy
```

#### 切換環境
```bash
# 切換到 Staging
./admin-tools/vpn_env.sh switch staging

# 切換到 Production（需要額外確認）
./admin-tools/vpn_env.sh switch production
```

#### 使用互動式選擇器
```bash
./enhanced_env_selector.sh
```

### AWS Profile 管理

系統支援智能 AWS Profile 管理：

#### 設定環境專用 Profile
```bash
# 為當前環境設定特定 Profile
./admin-tools/aws_vpn_admin.sh --set-profile my-staging-profile

# 重置為自動檢測
./admin-tools/aws_vpn_admin.sh --reset-profile

# 查看 Profile 狀態
./admin-tools/aws_vpn_admin.sh --profile-status
```

#### Profile 配置建議
```bash
# ~/.aws/credentials
[staging-vpn-admin]
aws_access_key_id = AKIA...
aws_secret_access_key = ...

[production-vpn-admin]
aws_access_key_id = AKIA...
aws_secret_access_key = ...
```

## 證書管理

### 證書架構概述

```
證書層級：
├── CA 證書（根證書）
│   ├── 用途：簽發客戶端證書
│   ├── 有效期：通常 10 年
│   └── 私鑰：必須嚴格保護
│
└── 客戶端證書
    ├── 用途：使用者身份驗證
    ├── 有效期：通常 1 年
    └── 私鑰：使用者自行保管
```

### 簽發證書流程

#### 1. 單一證書簽發

當團隊成員提交 CSR 後：

```bash
# 傳統本地簽發
./admin-tools/sign_csr.sh -e staging username.csr

# 零接觸流程（自動上傳到 S3）
./admin-tools/sign_csr.sh --upload-s3 username.csr
```

#### 2. 批次證書處理

處理多個 CSR 請求：

```bash
# 下載所有待處理的 CSR
./admin-tools/process_csr_batch.sh download -e production

# 批次簽發證書
./admin-tools/process_csr_batch.sh process -e production

# 上傳簽發的證書
./admin-tools/process_csr_batch.sh upload --auto-upload
```

#### 3. 自動監控模式

持續監控並自動處理新的 CSR：

```bash
# 啟動監控模式（每 30 秒檢查一次）
./admin-tools/process_csr_batch.sh monitor -e staging

# 自定義檢查間隔（秒）
./admin-tools/process_csr_batch.sh monitor -e staging -i 60
```

### 證書撤銷

#### 撤銷單一使用者
```bash
./admin-tools/revoke_member_access.sh
```

系統會：
1. 列出所有使用者供選擇
2. 撤銷選定使用者的證書
3. 斷開其現有 VPN 連線
4. 從 ACM 移除證書
5. 更新撤銷列表

#### 員工離職處理
```bash
./admin-tools/employee_offboarding.sh username
```

完整的離職流程包括：
- 撤銷所有環境的 VPN 存取
- 移除 IAM 權限
- 清理 S3 證書檔案
- 生成離職報告

### CA 證書管理

#### 查看 CA 證書狀態
```bash
# 在管理控制台中選擇「查看證書狀態」
./admin-tools/aws_vpn_admin.sh
```

#### 備份 CA 證書
```bash
# 手動備份 CA 證書和私鑰
cp -r certs/ca-bundle /secure/backup/location/
```

⚠️ **重要**：CA 私鑰必須離線保存在安全位置！

## 使用者權限管理

### IAM 政策架構

系統使用兩個主要 IAM 政策：

1. **VPN-CSR-TeamMember-Policy**
   - 基本 S3 存取權限
   - 可上傳 CSR、下載證書
   - 無管理權限

2. **VPN-CSR-Admin-Policy**
   - 完整 S3 管理權限
   - 可簽發和管理證書
   - 系統管理權限

### 新增使用者

#### 新增單一使用者
```bash
# 新增現有 AWS 使用者
./admin-tools/manage_vpn_users.sh add john.doe

# 創建新使用者並分配權限
./admin-tools/manage_vpn_users.sh add jane.smith --create-user
```

#### 批次新增使用者

1. 創建使用者清單檔案 `users.txt`：
```
john.doe
jane.smith
# 可以包含註解
bob.wilson
alice.chen
```

2. 執行批次新增：
```bash
./admin-tools/manage_vpn_users.sh batch-add users.txt
```

### 權限管理操作

#### 查看使用者清單
```bash
# 列出所有 VPN 使用者
./admin-tools/manage_vpn_users.sh list
```

輸出範例：
```
=== VPN Users List ===
Environment: staging
AWS Profile: staging-vpn-admin

TeamMember Policy Users (3):
- john.doe
- jane.smith
- bob.wilson

Admin Policy Users (2):
- admin1
- admin2
```

#### 檢查使用者權限
```bash
# 檢查特定使用者
./admin-tools/manage_vpn_users.sh status john.doe

# 測試使用者的 S3 權限
./admin-tools/manage_vpn_users.sh check-permissions john.doe
```

#### 移除使用者權限
```bash
# 只移除 VPN 權限
./admin-tools/manage_vpn_users.sh remove john.doe

# 完全移除使用者（謹慎使用）
./admin-tools/employee_offboarding.sh john.doe
```

### 新增管理員

當需要新增管理員時：

1. 編輯 `admin-tools/setup_csr_s3_bucket.sh`：
```bash
VPN_ADMIN_USERS=(
    "ct"
    "new-admin"  # 新增管理員
)
```

2. 更新 S3 桶政策：
```bash
./admin-tools/setup_csr_s3_bucket.sh
```

## VPN 端點管理

### 管理控制台

啟動管理控制台：
```bash
./admin-tools/aws_vpn_admin.sh
```

主選單功能：
1. 創建新的 VPN 端點
2. 查看現有 VPN 端點
3. 管理團隊成員
4. 查看證書狀態
5. 生成客戶端配置
6. 設定 AWS Profile
7. 刪除 VPN 端點

### 創建 VPN 端點

選擇「創建新的 VPN 端點」後，系統會：

1. **環境確認**
   - 顯示當前環境（Staging/Production）
   - Production 需要多重確認

2. **網路配置**
   - 選擇 VPC
   - 選擇子網路
   - 設定客戶端 CIDR（預設：172.16.0.0/22）

3. **證書配置**
   - 自動使用環境對應的證書
   - 驗證證書有效性

4. **安全群組**
   - 自動創建專用安全群組
   - 配置基本出站規則

### 端點健康檢查

```bash
# 全面分析 VPN 配置
./admin-tools/run-vpn-analysis.sh staging

# 生成詳細報告
./admin-tools/run-vpn-analysis.sh production
```

報告內容包括：
- 端點狀態和配置
- 安全群組規則分析
- 服務存取權限矩陣
- 改善建議

### 修復常見問題

#### 端點 ID 不匹配
```bash
./admin-tools/tools/fix_endpoint_id.sh
```

#### 網際網路存取問題
```bash
# 修復所有端點
./admin-tools/tools/fix_internet_access.sh

# 修復特定端點
./admin-tools/tools/fix_internet_access.sh cvpn-endpoint-xxxxx
```

#### 配置驗證和修復
```bash
./admin-tools/tools/validate_config.sh
```

## S3 證書交換系統

### 初始設置

設置 S3 證書交換系統：

```bash
# 基本設置
./admin-tools/setup_csr_s3_bucket.sh

# 設置並發布公開資源
./admin-tools/setup_csr_s3_bucket.sh --publish-assets
```

### S3 桶結構

```
vpn-csr-exchange/
├── public/                 # 公開可讀
│   ├── ca.crt             # CA 證書
│   └── vpn_endpoints.json # 端點配置
├── csr/                   # 使用者上傳 CSR
│   └── {username}.csr
├── cert/                  # 管理員上傳證書
│   └── {username}.crt
└── log/                   # 審計日誌
    └── processed/
```

### 權限管理

#### 更新 IAM 政策
```bash
# 只更新政策
./admin-tools/setup_csr_s3_bucket.sh --create-policies

# 檢查政策狀態
./admin-tools/setup_csr_s3_bucket.sh --list-policies
```

#### 發布端點資訊
```bash
# 發布所有環境
./admin-tools/publish_endpoints.sh

# 發布特定環境
./admin-tools/publish_endpoints.sh -e production
```

### 監控 S3 活動

透過 CloudTrail 監控：
- CSR 上傳事件
- 證書下載事件
- 異常存取嘗試

## Slack 管理指令

### 管理員專用指令

#### 1. 停用自動關閉（24小時）
```
/vpn admin noclose staging
/vpn admin noclose production
```

用途：維護期間防止 VPN 自動關閉

#### 2. 重新啟用自動關閉
```
/vpn admin autoclose staging
/vpn admin autoclose production
```

#### 3. 檢查冷卻狀態
```
/vpn admin cooldown staging
```

顯示冷卻期剩餘時間

#### 4. 強制關閉（繞過保護）
```
/vpn admin force-close staging
```

⚠️ 謹慎使用：會繞過所有安全檢查

### 成本管理指令

#### 查看節省報告
```
/vpn savings staging
/vpn savings production
```

#### 成本分析
```
/vpn costs daily       # 每日成本細分
/vpn costs cumulative  # 累積成本統計
```

### 管理通知設定

Slack 通知包括：
- VPN 開啟/關閉通知
- 自動優化通知
- 系統警報
- 成本報告

## 監控與報告

### CloudWatch 監控

系統自動發送以下指標：

1. **操作指標**
   - VpnOpenOperations
   - VpnCloseOperations
   - VpnOperationErrors
   - VpnOperationBlocked

2. **成本指標**
   - IdleTimeDetected
   - AutoCloseTriggered
   - CostSaved

3. **系統指標**
   - LambdaErrors
   - CrossAccountRoutingErrors

### 日誌分析

#### 查看 Lambda 日誌
```bash
# 查看 slack-handler 日誌
aws logs tail /aws/lambda/vpn-slack-handler-staging --follow

# 查看 vpn-monitor 日誌
aws logs tail /aws/lambda/vpn-monitor-production --follow
```

#### 重要日誌模式
- `ERROR` - 系統錯誤
- `WARN` - 警告訊息
- `Cost Optimization` - 成本優化事件
- `Security Alert` - 安全警報

### 定期報告

建議定期生成以下報告：

1. **週報**
   - VPN 使用統計
   - 成本節省總結
   - 異常活動摘要

2. **月報**
   - 使用者活動分析
   - 成本趨勢圖表
   - 系統健康狀態

## 故障處理

### 常見問題處理

#### 1. Lambda 函數錯誤

**症狀**：Slack 指令無回應或逾時

**診斷步驟**：
```bash
# 檢查部署狀態
./scripts/deploy.sh status

# 查看錯誤日誌
aws logs tail /aws/lambda/vpn-slack-handler-staging
```

**解決方案**：
```bash
# 重新部署受影響的環境
./scripts/deploy.sh staging --secure-parameters
```

#### 2. 跨帳戶路由失敗

**症狀**：Production 指令失敗

**診斷步驟**：
```bash
# 驗證路由配置
./scripts/deploy.sh validate-routing
```

**解決方案**：
```bash
# 更新路由配置
./scripts/deploy.sh staging --secure-parameters
```

#### 3. VPN 端點異常

**症狀**：無法連接或頻繁斷線

**診斷步驟**：
```bash
# 執行完整診斷
./admin-tools/tools/debug_vpn_creation.sh

# 分析端點配置
./admin-tools/run-vpn-analysis.sh
```

### 緊急處理程序

#### 1. 安全事件
1. 立即停用受影響的證書
2. 通知所有相關人員
3. 審查存取日誌
4. 更新安全政策

#### 2. 系統故障
1. 切換到備用方案
2. 收集診斷資訊
3. 聯繫 AWS 支援
4. 準備故障報告

#### 3. 成本異常
1. 檢查自動關閉功能
2. 審查使用模式
3. 調整閒置門檻
4. 實施使用政策

## 安全最佳實踐

### 證書安全

1. **CA 私鑰管理**
   - 離線存儲在加密裝置
   - 限制存取人員
   - 定期輪換

2. **證書簽發流程**
   - 驗證申請者身份
   - 記錄所有簽發活動
   - 設定合理有效期

3. **撤銷管理**
   - 及時處理離職
   - 維護撤銷列表
   - 定期審查活躍證書

### 存取控制

1. **最小權限原則**
   - 只授予必要權限
   - 定期審查權限
   - 移除未使用帳號

2. **環境隔離**
   - 嚴格分離環境權限
   - 使用不同 AWS 帳戶
   - 實施跨帳戶驗證

3. **審計追蹤**
   - 啟用 CloudTrail
   - 保存所有日誌
   - 定期審查活動

### 操作安全

1. **變更管理**
   - 記錄所有變更
   - 測試後再部署
   - 準備回滾計劃

2. **備份策略**
   - 定期備份配置
   - 測試恢復程序
   - 異地備份重要資料

3. **監控告警**
   - 設定關鍵指標告警
   - 及時響應異常
   - 定期檢討閾值

## 管理工具參考

### 環境管理工具

| 工具 | 用途 | 常用選項 |
|------|------|----------|
| `vpn_env.sh` | 環境管理 | `status`, `switch`, `selector` |
| `enhanced_env_selector.sh` | 互動式選擇 | - |

### 證書管理工具

| 工具 | 用途 | 常用選項 |
|------|------|----------|
| `sign_csr.sh` | 簽發證書 | `-e`, `--upload-s3` |
| `process_csr_batch.sh` | 批次處理 | `download`, `process`, `upload`, `monitor` |
| `revoke_member_access.sh` | 撤銷證書 | - |

### 使用者管理工具

| 工具 | 用途 | 常用選項 |
|------|------|----------|
| `manage_vpn_users.sh` | 使用者管理 | `list`, `add`, `remove`, `status` |
| `employee_offboarding.sh` | 離職處理 | - |

### 診斷修復工具

| 工具 | 用途 | 使用時機 |
|------|------|----------|
| `debug_vpn_creation.sh` | 診斷創建問題 | VPN 創建失敗 |
| `fix_endpoint_id.sh` | 修復端點 ID | ID 不匹配錯誤 |
| `fix_internet_access.sh` | 修復網路存取 | 無法存取網際網路 |
| `validate_config.sh` | 驗證配置 | 定期檢查 |

### 分析報告工具

| 工具 | 用途 | 輸出格式 |
|------|------|----------|
| `run-vpn-analysis.sh` | 全面分析 | Markdown, JSON |

---

## 附錄

### 快速參考卡

#### 日常操作流程
1. 早上檢查系統狀態
2. 處理待簽發的證書
3. 檢視成本報告
4. 處理使用者請求
5. 晚上確認自動關閉正常

#### 緊急聯絡
- AWS 支援：[AWS Support Console](https://console.aws.amazon.com/support/)
- 內部支援：Slack #vpn-emergency
- 值班電話：查看值班表

#### 有用的別名
```bash
# 加入到 ~/.bashrc 或 ~/.zshrc
alias vpn-status='./admin-tools/vpn_env.sh status'
alias vpn-staging='./admin-tools/vpn_env.sh switch staging'
alias vpn-prod='./admin-tools/vpn_env.sh switch production'
alias vpn-admin='./admin-tools/aws_vpn_admin.sh'
```

---

**文件版本**：1.0  
**最後更新**：2025-06-29  
**適用系統版本**：3.0+