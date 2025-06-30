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

### 環境與 Profile 管理

#### 使用直接 Profile 選擇
新的系統採用直接 AWS profile 選擇方式，消除隱藏狀態，提升安全性：

```bash
# 明確指定 AWS profile
./admin-tools/aws_vpn_admin.sh --profile staging
./admin-tools/aws_vpn_admin.sh --profile production

# 指定環境，自動選擇對應 profile
./admin-tools/aws_vpn_admin.sh --environment staging
./admin-tools/aws_vpn_admin.sh --environment production

# 互動式選擇（顯示可用 profiles 和建議）
./admin-tools/aws_vpn_admin.sh
```

#### Profile 狀態查看
```bash
# 查看當前可用的 AWS profiles
aws configure list-profiles

# 驗證 profile 設定
aws sts get-caller-identity --profile staging
aws sts get-caller-identity --profile production
```

#### 互動式 Profile 選擇
當不指定 `--profile` 參數時，系統會顯示智能選擇選單：

```
=== AWS Profile Selection ===

 1) ⭐ staging (Env: staging, Account: 123456789012, Region: us-east-1)
 2)   production (Env: prod, Account: 987654321098, Region: us-east-1)  
 3)   default (Env: unknown, Account: 555666777888, Region: us-west-2)

⭐ = Recommended for environment: staging

Select AWS Profile [1-3]: 
```

**選單特色：**
- **⭐ 星號標示**：推薦的環境對應 profiles
- **環境對應**：自動顯示 profile 對應的環境
- **帳戶資訊**：顯示 AWS 帳戶 ID 避免誤操作
- **區域資訊**：顯示 AWS 區域設定

**安全驗證：**
- 自動驗證所選 profile 的帳戶 ID 是否符合環境設定
- 防止在錯誤的 AWS 帳戶中執行操作
- 顯示警告若缺少帳戶驗證設定

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
# ⚠️ 重要：此工具執行高風險操作，尚未在實際環境完整測試
./admin-tools/employee_offboarding.sh --profile production --environment production
```

**安全警告和確認流程**:
- ⚠️ 腳本會顯示多重警告和風險提醒
- 🔒 需要輸入 'I-UNDERSTAND-THE-RISKS' 確認風險
- 🛡️ 緊急操作需要輸入 'CONFIRM' 確認
- 📋 提供詳細的操作檢查清單

**完整的離職流程包括**:
- 🚫 撤銷所有環境的 VPN 存取
- 🗑️ 永久刪除 IAM 用戶和權限
- 🧹 清理 S3 證書檔案
- 📊 生成詳細離職報告
- 🔐 多重安全確認機制

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

## Lambda 預熱系統管理

### 預熱機制概述

系統實作了智能 Lambda 預熱機制，確保 Slack 指令的快速響應（< 1 秒）：

**預熱時程表：**
- **營業時間**（9:00-18:00 台灣時間，週一至週五）：每 3 分鐘
- **非營業時間**（18:00-9:00 台灣時間，週一至週五）：每 15 分鐘
- **週末**（週六日全天）：每 30 分鐘

**涵蓋的 Lambda 函數：**
- `slack-handler` - Slack 指令處理
- `vpn-control` - VPN 操作控制
- `vpn-monitor` - VPN 監控和自動關閉

### 預熱狀態監控

#### 檢查預熱規則狀態
```bash
# 查看所有預熱規則
aws events list-rules --name-prefix "*Warming*" --profile staging

# 檢查特定規則詳情
aws events describe-rule --name "BusinessHoursWarmingRule" --profile staging

# 查看規則目標
aws events list-targets-by-rule --rule "BusinessHoursWarmingRule" --profile staging
```

#### 監控預熱效果
```bash
# 查看 Lambda 調用次數（包含預熱）
aws cloudwatch get-metric-statistics \
  --namespace AWS/Lambda \
  --metric-name Invocations \
  --dimensions Name=FunctionName,Value=vpn-slack-handler-staging \
  --start-time $(date -u -d '1 day ago' +%Y-%m-%dT%H:%M:%SZ) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%SZ) \
  --period 3600 \
  --statistics Sum \
  --profile staging

# 分析 Lambda 執行時間改善
aws cloudwatch get-metric-statistics \
  --namespace AWS/Lambda \
  --metric-name Duration \
  --dimensions Name=FunctionName,Value=vpn-slack-handler-staging \
  --start-time $(date -u -d '1 day ago' +%Y-%m-%dT%H:%M:%SZ) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%SZ) \
  --period 3600 \
  --statistics Average,Maximum \
  --profile staging
```

### 預熱成本管理

#### 成本估算
```bash
# 每月預熱調用次數計算：
# 營業時間：20次/小時 × 9小時 × 22工作日 = 3,960次
# 非營業時間：4次/小時 × 15小時 × 22工作日 = 1,320次
# 週末：2次/小時 × 48小時 × 8天 = 768次
# 總計：6,048次/月 × 3個函數 = 18,144次/月
# 預估成本：$8-12/月
```

#### 成本效益分析
```bash
# 查看預熱日誌中的成本資訊
aws logs filter-log-events \
  --log-group-name /aws/lambda/vpn-slack-handler-staging \
  --filter-pattern "Warming request received" \
  --start-time $(date -d '1 day ago' +%s)000 \
  --profile staging
```

### 預熱配置調整

#### 修改預熱頻率

如需調整預熱頻率，編輯 `cdklib/lib/vpn-automation-stack.ts`：

```typescript
// 營業時間預熱（目前：每 3 分鐘）
const businessHoursWarmingRule = new events.Rule(this, 'BusinessHoursWarmingRule', {
  schedule: events.Schedule.expression('rate(5 minutes)'), // 改為 5 分鐘
  description: `Business hours Lambda warming for ${environment} environment`,
  enabled: true
});
```

#### 啟用/停用預熱

```bash
# 停用營業時間預熱
aws events disable-rule --name "BusinessHoursWarmingRule" --profile staging

# 重新啟用
aws events enable-rule --name "BusinessHoursWarmingRule" --profile staging

# 檢查規則狀態
aws events describe-rule --name "BusinessHoursWarmingRule" --profile staging
```

### 預熱故障排除

#### 常見問題

**1. 預熱調用失敗**
```bash
# 檢查 Lambda 錯誤
aws logs filter-log-events \
  --log-group-name /aws/lambda/vpn-slack-handler-staging \
  --filter-pattern "ERROR" \
  --start-time $(date -d '1 hour ago' +%s)000 \
  --profile staging
```

**2. 預熱頻率過高**
```bash
# 檢查調用頻率
aws cloudwatch get-metric-statistics \
  --namespace AWS/Lambda \
  --metric-name Invocations \
  --dimensions Name=FunctionName,Value=vpn-slack-handler-staging \
  --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%SZ) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%SZ) \
  --period 300 \
  --statistics Sum \
  --profile staging
```

**3. 預熱成本過高**
```bash
# 分析預熱相關的計費時間
aws logs filter-log-events \
  --log-group-name /aws/lambda/vpn-slack-handler-staging \
  --filter-pattern "REPORT" \
  --start-time $(date -d '1 day ago' +%s)000 \
  --profile staging | grep "Billed Duration"
```

#### 效能驗證

**預期效能指標：**
- **冷啟動時間**：1,500-3,000ms
- **預熱啟動時間**：50-200ms  
- **Slack 指令響應**：< 1 秒
- **改善幅度**：90-95% 延遲降低

**驗證指令：**
```bash
# 測試 Slack 指令響應時間
time curl -X POST "YOUR_API_GATEWAY_URL" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "command=/vpn&text=check staging"
```

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

## 管理工具完整參考

### 🎯 工具分類概覽

本系統提供 15+ 個專業管理工具，分為以下類別：

| 類別 | 工具數量 | 主要用途 |
|------|----------|----------|
| **核心管理** | 3 個 | VPN 端點管理、用戶管理、主控制台 |
| **證書管理** | 4 個 | CSR 簽發、證書撤銷、S3 交換設置 |
| **用戶管理** | 3 個 | 權限管理、離職處理、服務存取 |
| **網路管理** | 2 個 | 子網路管理、端點發布 |
| **監控分析** | 3 個 | VPN 分析、追蹤報告、日誌管理 |
| **診斷工具** | 1 個 | AWS Profile 驗證 |

---

## 🔧 核心管理工具

### 1. aws_vpn_admin.sh - 主管理控制台

**用途**: AWS Client VPN 的主要管理介面，提供互動式選單操作

**功能特色**:
- 🎛️ 互動式主選單介面
- 🔄 支援雙環境管理 (staging/production)
- 📊 整合所有 VPN 管理功能
- 🎯 直接 AWS Profile 選擇

**使用方法**:
```bash
# 基本啟動
./admin-tools/aws_vpn_admin.sh

# 指定 AWS Profile
./admin-tools/aws_vpn_admin.sh --profile staging

# 指定環境
./admin-tools/aws_vpn_admin.sh --environment production --profile prod

# 查看幫助
./admin-tools/aws_vpn_admin.sh --help
```

**主選單功能**:
1. **創建新的 VPN 端點** - 建立新環境的 VPN
2. **查看現有 VPN 端點** - 檢視端點狀態和配置
3. **管理團隊成員** - 用戶權限和證書管理
4. **查看證書狀態** - 檢查證書有效性
5. **生成客戶端配置** - 產生 .ovpn 配置檔
6. **設定 AWS Profile** - 切換工作環境
7. **刪除 VPN 端點** - 清理不需要的端點

**適用場景**:
- 🆕 新管理員入門操作
- 🔄 日常 VPN 管理任務
- 🎯 需要圖形化介面的操作
- 📋 系統狀態總覽檢查

### 2. manage_vpn_users.sh - 用戶權限管理

**用途**: 統一管理 VPN 用戶權限和 IAM 政策

**核心功能**:
- 👤 添加/移除用戶 VPN 權限
- 📋 批量用戶管理
- 🔍 權限狀態檢查
- 🛡️ S3 存取權限驗證

**使用方法**:
```bash
# 添加單一用戶
./admin-tools/manage_vpn_users.sh add john

# 添加用戶並自動創建 IAM 用戶
./admin-tools/manage_vpn_users.sh add jane --create-user

# 移除用戶權限
./admin-tools/manage_vpn_users.sh remove old-employee

# 列出所有 VPN 用戶
./admin-tools/manage_vpn_users.sh list

# 檢查用戶狀態
./admin-tools/manage_vpn_users.sh status john

# 批量添加用戶
./admin-tools/manage_vpn_users.sh batch-add users.txt

# 檢查用戶 S3 權限
./admin-tools/manage_vpn_users.sh check-permissions john

# 指定環境和 Profile
./admin-tools/manage_vpn_users.sh add john --environment staging --profile staging
```

**批量用戶文件格式**:
```
# users.txt 範例
john.doe
jane.smith
mike.wilson
# 註解行會被忽略
```

**選項參數**:
- `-e, --environment ENV`: 目標環境 (staging/production)
- `-p, --profile PROFILE`: AWS CLI profile
- `-b, --bucket-name NAME`: S3 存儲桶名稱
- `--create-user`: 自動創建不存在的 IAM 用戶
- `--dry-run`: 預覽操作但不執行
- `-v, --verbose`: 顯示詳細輸出

**適用場景**:
- 👥 新員工入職權限設置
- 🚪 員工離職權限清理
- 📊 定期權限審計
- 🔄 批量用戶管理

### 3. vpn_subnet_manager.sh - 子網路管理

**用途**: 管理 VPN 端點的子網路關聯和網路配置

**核心功能**:
- 🌐 子網路關聯/取消關聯
- 📊 網路狀態監控
- 🔧 路由表管理
- 🛡️ 安全群組配置

**使用方法**:
```bash
# 關聯子網路到 VPN 端點
./admin-tools/vpn_subnet_manager.sh associate --subnet-id subnet-12345 --profile staging

# 取消子網路關聯
./admin-tools/vpn_subnet_manager.sh disassociate --subnet-id subnet-12345 --profile staging

# 列出所有關聯的子網路
./admin-tools/vpn_subnet_manager.sh list --profile staging

# 檢查子網路狀態
./admin-tools/vpn_subnet_manager.sh status --subnet-id subnet-12345 --profile staging
```

---

## 📜 證書管理工具

### 4. sign_csr.sh - 證書簽發工具

**用途**: 簽發客戶端證書請求 (CSR) 並管理證書生命週期

**核心功能**:
- ✍️ CSR 簽發和證書生成
- 📤 自動上傳到 S3 交換桶
- 🔍 批量處理和監控
- 📋 簽發記錄追蹤

**使用方法**:
```bash
# 簽發單一用戶證書
./admin-tools/sign_csr.sh john

# 簽發並上傳到 S3
./admin-tools/sign_csr.sh john --upload-s3

# 指定環境
./admin-tools/sign_csr.sh john -e staging

# 批量處理模式
./admin-tools/sign_csr.sh --batch-mode

# 監控待處理的 CSR
./admin-tools/sign_csr.sh --monitor

# 下載所有待處理 CSR
./admin-tools/sign_csr.sh --download-all

# 上傳所有已簽發證書
./admin-tools/sign_csr.sh --upload-all
```

**工作流程**:
1. **下載 CSR**: 從 S3 下載用戶提交的 CSR
2. **驗證 CSR**: 檢查 CSR 格式和內容
3. **簽發證書**: 使用 CA 私鑰簽發證書
4. **上傳證書**: 將簽發的證書上傳到 S3
5. **記錄日誌**: 記錄簽發操作和狀態

**適用場景**:
- 📝 處理新用戶證書申請
- 🔄 批量證書簽發
- 📊 證書簽發狀態監控
- 🔧 證書管理自動化

### 5. setup_csr_s3_bucket.sh - S3 交換桶設置

**用途**: 創建和配置用於安全 CSR 交換的 S3 存儲桶

**核心功能**:
- 🪣 S3 存儲桶創建和配置
- 🛡️ IAM 政策管理
- 📤 公開資源發布
- 🧹 清理和維護

**使用方法**:
```bash
# 基本桶設置
./admin-tools/setup_csr_s3_bucket.sh

# 指定桶名稱和區域
./admin-tools/setup_csr_s3_bucket.sh --bucket-name my-vpn-csr --region us-west-2

# 只創建 IAM 政策
./admin-tools/setup_csr_s3_bucket.sh --create-policies

# 列出現有政策
./admin-tools/setup_csr_s3_bucket.sh --list-policies

# 發布公開資源
./admin-tools/setup_csr_s3_bucket.sh --publish-assets

# 清理模式
./admin-tools/setup_csr_s3_bucket.sh --cleanup

# 詳細輸出
./admin-tools/setup_csr_s3_bucket.sh --verbose
```

**S3 桶結構**:
```
vpn-csr-exchange/
├── public/                 # 公開可讀資源
│   ├── ca.crt             # CA 證書
│   └── vpn_endpoints.json # 端點配置
├── csr/                   # 用戶上傳 CSR
│   └── {username}.csr
├── cert/                  # 管理員上傳證書
│   └── {username}.crt
└── log/                   # 審計日誌
    └── processed/
```

### 6. revoke_member_access.sh - 證書撤銷工具

**用途**: 撤銷用戶證書並清理相關存取權限

**核心功能**:
- 🚫 證書撤銷和 CRL 更新
- 🧹 S3 檔案清理
- 📋 撤銷記錄追蹤
- 🔔 通知機制

**使用方法**:
```bash
# 撤銷用戶證書
./admin-tools/revoke_member_access.sh john

# 指定環境
./admin-tools/revoke_member_access.sh john --environment staging

# 強制撤銷（跳過確認）
./admin-tools/revoke_member_access.sh john --force

# 只清理 S3 檔案
./admin-tools/revoke_member_access.sh john --s3-only
```

### 7. publish_endpoints.sh - 端點資訊發布

**用途**: 發布 VPN 端點資訊到 S3 供客戶端下載

**核心功能**:
- 📤 端點配置發布
- 🔄 多環境同步
- 📋 配置驗證
- 🔍 狀態檢查

**使用方法**:
```bash
# 發布所有環境端點資訊
./admin-tools/publish_endpoints.sh

# 發布特定環境
./admin-tools/publish_endpoints.sh --environment staging

# 驗證發布內容
./admin-tools/publish_endpoints.sh --verify

# 強制更新
./admin-tools/publish_endpoints.sh --force-update
```

---

## 👥 用戶管理工具

### 8. employee_offboarding.sh - 員工離職處理

**用途**: 完整的員工離職流程，包含所有 VPN 相關清理

**⚠️ 重要安全警告**: 此工具執行高風險操作，包括永久刪除 IAM 用戶、撤銷證書和斷開 VPN 連接。**尚未在實際 AWS 用戶上進行完整測試**，建議在生產環境使用前進行充分驗證。

**核心功能**:
- 🚪 完整離職流程自動化
- 🧹 多系統權限清理
- 📋 離職檢查清單
- 📊 離職報告生成
- 🛡️ 多重安全確認機制

**使用方法**:
```bash
# 互動式離職流程（推薦）
./admin-tools/employee_offboarding.sh

# 指定 AWS Profile 和環境
./admin-tools/employee_offboarding.sh --profile production --environment production

# 指定特定環境
./admin-tools/employee_offboarding.sh --environment staging
```

**安全確認流程**:
1. **初始警告**: 顯示腳本風險和未測試狀態
2. **環境確認**: 驗證 AWS Profile 和環境設定
3. **操作確認**: 需要輸入 'I-UNDERSTAND-THE-RISKS' 繼續
4. **緊急操作確認**: 高風險操作需要輸入 'CONFIRM'
5. **不可逆操作提醒**: 每個關鍵步驟都有確認提示

**離職檢查清單**:
- ✅ 撤銷 VPN 證書
- ✅ 移除 IAM 權限
- ✅ 清理 S3 檔案
- ✅ 更新 CRL
- ✅ 記錄審計日誌
- ✅ 發送通知

### 9. manage_vpn_service_access.sh - 服務存取管理

**用途**: 管理 VPN 服務的細粒度存取控制

**核心功能**:
- 🎯 動態服務發現和存取控制
- 🛡️ 安全群組自動化管理
- 📊 存取權限審計和報告
- 🔄 批量權限更新和追蹤

**使用方法**:
```bash
# 發現 VPC 中的可用服務
./admin-tools/manage_vpn_service_access.sh discover --profile staging

# 顯示已發現的服務
./admin-tools/manage_vpn_service_access.sh display-services --profile staging

# 創建 VPN 到服務的存取規則
./admin-tools/manage_vpn_service_access.sh create sg-1234567890abcdef0 --profile staging

# 移除 VPN 服務存取規則
./admin-tools/manage_vpn_service_access.sh remove sg-1234567890abcdef0 --profile staging

# 生成 VPN 追蹤報告
./admin-tools/manage_vpn_service_access.sh report --profile staging

# 清理追蹤檔案和發現快取
./admin-tools/manage_vpn_service_access.sh clean --profile staging

# 指定 AWS Profile 和環境
./admin-tools/manage_vpn_service_access.sh discover --profile production --environment production
```

**主要操作類型**:
- `discover`: 掃描 VPC 並發現可用的 AWS 服務
- `display-services`: 顯示之前發現的服務清單
- `create`: 建立 VPN 到已發現服務的存取規則
- `remove`: 移除 VPN 服務存取規則並更新追蹤
- `report`: 生成人類可讀的 VPN 追蹤報告
- `clean`: 清理追蹤檔案和發現快取

---

## 📊 監控分析工具

### 10. run-vpn-analysis.sh - VPN 全面分析

**用途**: 生成詳細的 VPN 使用分析報告

**核心功能**:
- 📈 使用統計分析
- 💰 成本分析報告
- 🔍 效能指標監控
- 📋 多格式報告輸出

**使用方法**:
```bash
# 生成完整分析報告
./admin-tools/run-vpn-analysis.sh

# 指定時間範圍
./admin-tools/run-vpn-analysis.sh --start-date 2025-06-01 --end-date 2025-06-30

# 指定輸出格式
./admin-tools/run-vpn-analysis.sh --format json

# 只分析成本
./admin-tools/run-vpn-analysis.sh --cost-only

# 生成 Markdown 報告
./admin-tools/run-vpn-analysis.sh --format markdown --output report.md
```

**報告內容**:
- 📊 連線統計和趨勢
- 💰 成本分析和節省
- 👥 用戶使用模式
- ⚡ 效能指標
- 🔧 優化建議

### 11. vpn_tracking_report.sh - VPN 追蹤報告

**用途**: 生成 VPN 使用追蹤和合規報告

**核心功能**:
- 📋 使用記錄追蹤
- 🔍 合規性檢查
- 📊 定期報告生成
- 📤 自動報告發送

**使用方法**:
```bash
# 生成月度追蹤報告
./admin-tools/vpn_tracking_report.sh --monthly

# 生成週度報告
./admin-tools/vpn_tracking_report.sh --weekly

# 指定用戶報告
./admin-tools/vpn_tracking_report.sh --user john

# 合規性檢查
./admin-tools/vpn_tracking_report.sh --compliance-check
```

### 12. set_log_retention.sh - 日誌保留管理

**用途**: 管理 CloudWatch 日誌群組的保留政策

**核心功能**:
- 📅 日誌保留期設定
- 💰 儲存成本優化
- 🔄 批量日誌群組管理
- 📊 保留政策審計

**使用方法**:
```bash
# 設定所有 VPN 相關日誌保留期
./admin-tools/set_log_retention.sh --days 30

# 設定特定日誌群組
./admin-tools/set_log_retention.sh --log-group /aws/lambda/vpn-monitor --days 14

# 列出所有日誌群組
./admin-tools/set_log_retention.sh --list

# 審計保留政策
./admin-tools/set_log_retention.sh --audit
```

---

## 🔧 診斷工具

### 13. validate_aws_profile_config.sh - AWS Profile 驗證

**用途**: 驗證 AWS CLI Profile 配置的正確性

**核心功能**:
- ✅ Profile 配置驗證
- 🔑 憑證有效性檢查
- 🌐 區域設定驗證
- 🛡️ 權限檢查

**使用方法**:
```bash
# 驗證預設 Profile
./admin-tools/validate_aws_profile_config.sh

# 驗證特定 Profile
./admin-tools/validate_aws_profile_config.sh --profile staging

# 詳細驗證報告
./admin-tools/validate_aws_profile_config.sh --verbose

# 檢查所有 Profile
./admin-tools/validate_aws_profile_config.sh --all-profiles
```

**驗證項目**:
- ✅ Profile 存在性
- ✅ 憑證有效性
- ✅ 區域設定
- ✅ 基本 AWS 權限
- ✅ VPN 相關權限

---

## 🎯 工具使用最佳實踐

### 日常管理工作流程

#### 🌅 每日檢查 (5 分鐘)
```bash
# 1. 檢查系統狀態
./admin-tools/aws_vpn_admin.sh --profile staging

# 2. 處理待簽發證書
./admin-tools/sign_csr.sh --monitor

# 3. 檢查用戶權限狀態
./admin-tools/manage_vpn_users.sh list
```

#### 📅 每週維護 (15 分鐘)
```bash
# 1. 生成使用分析報告
./admin-tools/run-vpn-analysis.sh --format markdown

# 2. 檢查日誌保留政策
./admin-tools/set_log_retention.sh --audit

# 3. 驗證 AWS Profile 配置
./admin-tools/validate_aws_profile_config.sh --all-profiles
```

#### 📊 每月審計 (30 分鐘)
```bash
# 1. 生成月度追蹤報告
./admin-tools/vpn_tracking_report.sh --monthly

# 2. 權限審計
./admin-tools/manage_vpn_service_access.sh audit

# 3. 成本分析
./admin-tools/run-vpn-analysis.sh --cost-only
```

### 緊急情況處理

#### 🚨 員工緊急離職
```bash
# 立即撤銷所有存取權限
./admin-tools/employee_offboarding.sh username --emergency
```

#### 🔧 系統故障診斷
```bash
# 1. 驗證 AWS 配置
./admin-tools/validate_aws_profile_config.sh --verbose

# 2. 檢查 VPN 端點狀態
./admin-tools/aws_vpn_admin.sh

# 3. 檢查用戶權限
./admin-tools/manage_vpn_users.sh check-permissions username
```

### 安全最佳實踐

#### 🛡️ 定期安全檢查
- **每日**: 監控證書簽發活動
- **每週**: 審計用戶權限變更
- **每月**: 完整權限審計
- **每季**: 證書有效期檢查

#### 🔐 權限管理原則
- **最小權限**: 只授予必要的存取權限
- **定期審計**: 定期檢查和清理權限
- **職責分離**: 管理員和用戶權限分離
- **審計追蹤**: 記錄所有權限變更

---

## 📋 快速參考

### 常用指令速查

| 任務 | 指令 |
|------|------|
| 添加新用戶 | `./admin-tools/manage_vpn_users.sh add username --profile staging` |
| 簽發證書 | `./admin-tools/sign_csr.sh username --upload-s3 --profile staging` |
| 員工離職 ⚠️ | `./admin-tools/employee_offboarding.sh --profile production` |
| 系統狀態 | `./admin-tools/aws_vpn_admin.sh --profile staging` |
| 服務發現 | `./admin-tools/manage_vpn_service_access.sh discover --profile staging` |
| 生成報告 | `./admin-tools/run-vpn-analysis.sh --profile staging` |
| 權限檢查 | `./admin-tools/manage_vpn_users.sh check-permissions username --profile staging` |

⚠️ **注意**: `employee_offboarding.sh` 執行高風險操作，尚未在實際環境完整測試

### 故障排除快速指南

| 問題 | 解決方案 |
|------|----------|
| 證書簽發失敗 | 檢查 CA 證書和私鑰路徑 |
| 用戶無法連線 | 驗證用戶權限和證書狀態 |
| S3 上傳失敗 | 檢查 S3 桶權限和 IAM 政策 |
| AWS Profile 錯誤 | 運行 `validate_aws_profile_config.sh` |
| 成本異常 | 檢查自動關閉功能和閒置時間 |

---

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
alias vpn-admin-staging='./admin-tools/aws_vpn_admin.sh --profile staging'
alias vpn-admin-prod='./admin-tools/aws_vpn_admin.sh --profile production'
alias vpn-admin='./admin-tools/aws_vpn_admin.sh'
alias vpn-profiles='aws configure list-profiles'
```

---

---

## 📅 最新更新記錄

### 2025-06-30 - 管理工具系統更新

#### ✅ 已修復的工具
1. **manage_vpn_service_access.sh**
   - 修復 `env_manager.sh` 缺失錯誤
   - 更新至新的 Profile Selector 系統
   - 支援直接 AWS Profile 選擇
   - 改善環境變數處理

2. **employee_offboarding.sh**
   - 新增多重安全警告機制
   - 更新 Profile Selector 整合
   - 增強風險確認流程
   - 添加 'I-UNDERSTAND-THE-RISKS' 確認

3. **setup-parameters.sh** (Scripts)
   - 修復參數解析衝突問題
   - 支援非互動式 Profile 指定
   - 改善參數傳遞機制
   - 更新環境驗證邏輯

#### 🔧 技術改善
- 所有工具現在使用統一的 Profile Selector 系統
- 移除對已廢棄 `env_manager.sh` 的依賴
- 統一環境變數命名 (`SELECTED_ENVIRONMENT`)
- 改善 AWS CLI 調用的 Profile 處理

#### ⚠️ 重要提醒
- `employee_offboarding.sh` 包含未在實際環境測試的高風險操作
- 所有管理工具現在需要明確的 AWS Profile 選擇
- 建議在生產環境使用前先在測試環境驗證

---

**文件版本**：1.1  
**最後更新**：2025-06-30  
**適用系統版本**：3.1+  
**開發團隊**：[Newsleopard 電子豹](https://newsleopard.com)