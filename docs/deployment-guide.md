# DevOps 部署指南

本指南為 DevOps 工程師提供部署、維護和排除 AWS Client VPN 管理系統的綜合指示。

## 🎯 本指南適用對象

- DevOps 工程師
- 基礎設施工程師
- 系統管理員
- 平台工程師

## 📋 系統概覽

### 架構元件
- **基礎設施**: AWS CDK v2 (TypeScript)
- **執行環境**: Node.js 20.x Lambda 函數
- **API**: 透過 API Gateway 的 REST API
- **排程**: EventBridge (CloudWatch Events)
- **狀態**: SSM Parameter Store
- **監控**: CloudWatch Logs/Metrics

### 雙環境設計
- **Staging**: 開發和測試
- **Production**: 線上運作
- 環境間完全隔離

## 🚀 初始部署

### 先決條件

#### 1. 系統要求
```bash
# 驗證安裝
node --version      # 要求: v20.x+
npm --version       # 要求: v10.x+
aws --version       # 要求: v2.x
cdk --version       # 要求: v2.x

# 必要時安裝 CDK
npm install -g aws-cdk
```

#### 2. AWS 帳戶設定
```bash
# 設定 AWS 設定檔
aws configure --profile staging
aws configure --profile production

# 驗證認證
aws sts get-caller-identity --profile staging
aws sts get-caller-identity --profile production
```

#### 3. 帳戶設定

編輯環境設定：
```bash
# configs/staging/staging.env
AWS_ACCOUNT_ID="YOUR_STAGING_ACCOUNT_ID"
AWS_REGION="us-east-1"
ENV_AWS_PROFILE="staging"

# configs/production/production.env
AWS_ACCOUNT_ID="YOUR_PRODUCTION_ACCOUNT_ID"
AWS_REGION="us-east-1"
ENV_AWS_PROFILE="production"
```

### CDK Bootstrap

每個帳戶的首次設定：
```bash
cd cdklib

# Bootstrap staging 帳戶
AWS_PROFILE=staging cdk bootstrap

# Bootstrap production 帳戶
AWS_PROFILE=production cdk bootstrap
```

### 部署基礎設施

#### 完整部署
```bash
# 部署兩個環境
./scripts/deploy.sh both --secure-parameters \
  --staging-profile staging \
  --production-profile production

# 檢查部署狀態
./scripts/deploy.sh status
```

#### 單一環境
```bash
# 僅部署 staging
./scripts/deploy.sh staging --secure-parameters

# 僅部署 production
./scripts/deploy.sh production --secure-parameters
```

### 設定 Slack 整合

#### 1. 建立 Slack 應用程式
- 前往 https://api.slack.com/apps
- 建立新應用程式
- 新增 OAuth 範圍：`chat:write`、`commands`、`incoming-webhook`

#### 2. 將認證資料儲存在 SSM
```bash
# 儲存 Slack 設定
aws ssm put-parameter \
  --name "/vpn/slack/bot_token" \
  --value "xoxb-your-bot-token" \
  --type "SecureString" \
  --profile staging

aws ssm put-parameter \
  --name "/vpn/slack/signing_secret" \
  --value "your-signing-secret" \
  --type "SecureString" \
  --profile staging

aws ssm put-parameter \
  --name "/vpn/slack/webhook_url" \
  --value "https://hooks.slack.com/services/YOUR/WEBHOOK" \
  --type "SecureString" \
  --profile staging
```

#### 3. 設定斜線命令
- 命令：`/vpn`
- 請求 URL：您的 staging API Gateway URL（來自部署輸出）
- 方法：POST

### S3 憑證交換系統設定

#### 何時需要執行

**必須執行的情況：**

1. **🚀 初次系統部署**（一次性，最重要）
   ```bash
   ./admin-tools/setup_csr_s3_bucket.sh --publish-assets
   ```

2. **🔑 CA 憑證更新後**
   ```bash
   # 重新生成或更新 CA 憑證後
   ./admin-tools/setup_csr_s3_bucket.sh --publish-assets
   ```

3. **🔧 VPN 端點變更後**
   ```bash
   # 建立新端點或修改端點設定後
   ./admin-tools/setup_csr_s3_bucket.sh --publish-assets
   ```

4. **🌍 環境設定變更後**
   - 新增環境或修改現有環境配置時

#### 此步驟的功能

**建立零接觸工作流程基礎設施：**
- 建立 S3 儲存桶 (`vpn-csr-exchange`)
- 設定 IAM 政策（團隊成員和管理員）
- **發佈公共資產**供團隊成員自動下載：
  - `public/ca.crt` - CA 憑證（所有使用者需要）
  - `public/vpn_endpoints.json` - 各環境的 VPN 端點 ID 和區域

#### 驗證設定

```bash
# 檢查公共資產是否存在
aws s3 ls s3://vpn-csr-exchange/public/ --profile staging

# 應該看到：
# ca.crt
# vpn_endpoints.json
```

#### 其他管理選項

```bash
# 僅建立/更新 IAM 政策
./admin-tools/setup_csr_s3_bucket.sh --create-policies

# 檢查 IAM 政策狀態
./admin-tools/setup_csr_s3_bucket.sh --list-policies

# 清理儲存桶和政策（謹慎使用）
./admin-tools/setup_csr_s3_bucket.sh --cleanup
```

## 🔧 Lambda 開發

### 專案結構
```
lambda/
├── slack-handler/     # 處理 Slack 命令
├── vpn-control/       # 執行 VPN 操作
├── vpn-monitor/       # 自動關閉監控
└── shared/            # 共享層代碼
```

### 構建流程

#### 手動構建
```bash
# 構建單一函數
cd lambda/slack-handler
./build.sh

# 構建所有函數
for dir in lambda/*/; do
  [ -f "$dir/build.sh" ] && (cd "$dir" && ./build.sh)
done
```

#### 部署變更
```bash
# 先在 staging 測試
./scripts/deploy.sh staging

# 然後部署至 production
./scripts/deploy.sh production
```

### 環境變數

Lambda 函數使用這些環境變數：

| 變數 | 用途 | 範例 |
|------|------|-------|
| `ENVIRONMENT` | 環境識別符 | staging/production |
| `APP_ENV` | 應用程式環境 | staging/production |
| `IDLE_MINUTES` | 自動關閉闾值 | 54 |
| `LOG_LEVEL` | 日誌詳細程度 | INFO/DEBUG |

## 📊 監控和日誌

### CloudWatch 日誌

#### 檢視即時日誌
```bash
# Slack 處理程式日誌
aws logs tail /aws/lambda/vpn-slack-handler-staging \
  --follow --profile staging

# VPN 控制日誌
aws logs tail /aws/lambda/vpn-control-staging \
  --follow --profile staging

# 監控日誌
aws logs tail /aws/lambda/vpn-monitor-staging \
  --follow --profile staging
```

#### 搜尋錯誤
```bash
aws logs filter-log-events \
  --log-group-name /aws/lambda/vpn-control-production \
  --filter-pattern "ERROR" \
  --start-time $(date -d '1 hour ago' +%s)000 \
  --profile production
```

### CloudWatch 指標

追蹤的自訂指標：
- `VPN/Automation/VpnOpenOperations`
- `VPN/Automation/VpnCloseOperations`
- `VPN/Automation/AutoCloseTriggered`
- `VPN/Automation/CostSaved`

#### 建立警告
```bash
aws cloudwatch put-metric-alarm \
  --alarm-name "VPN-High-Error-Rate" \
  --alarm-description "Alert on high Lambda errors" \
  --metric-name Errors \
  --namespace AWS/Lambda \
  --statistic Sum \
  --period 300 \
  --threshold 10 \
  --comparison-operator GreaterThanThreshold \
  --evaluation-periods 2 \
  --profile production
```

### Lambda 預熱系統

系統包含自動 Lambda 預熱以消除冷啟動：

#### 預熱排程
- **工作時間** (週一至週五 9-18 點)：每 3 分鐘
- **非工作時間** (週一至週五 18-9 點)：每 15 分鐘
- **週末**：每 30 分鐘

#### 監控預熱
```bash
# 檢查預熱規則
aws events list-rules --name-prefix "*Warming*" --profile staging

# 檢視預熱效果
aws logs filter-log-events \
  --log-group-name /aws/lambda/vpn-slack-handler-staging \
  --filter-pattern "Warming request received" \
  --profile staging
```

## 🛠️ 維護操作

### 更新 Lambda 代碼

1. **修改代碼** 在 `lambda/*/index.ts`
2. **構建** 函數
3. **部署** 至 staging
4. **測試** 功能
5. **部署** 至 production

```bash
# 完整更新流程
cd lambda/vpn-control
# 編輯 index.ts
./build.sh
cd ../..
./scripts/deploy.sh staging
# 透過 Slack 測試
./scripts/deploy.sh production
```

### 更新相依性

```bash
# 更新共享層
cd lambda/shared
npm update
npm audit fix

# 更新函數相依性
cd ../slack-handler
npm update
npm audit fix
```

### 設定更新

#### 更新 SSM 參數
```bash
# 更新設定
aws ssm put-parameter \
  --name "/vpn/staging/cost/optimization_config" \
  --value '{"idleTimeoutMinutes":54}' \
  --type String \
  --overwrite \
  --profile staging
```

#### 更新 CDK Stack
```bash
cd cdklib
npm update aws-cdk-lib
cdk deploy --profile staging
```

## 🚨 排除故障

### 常見問題

#### Lambda 逾時
**症狀**：Slack 命令逾時

**檢查**：
```bash
aws lambda get-function-configuration \
  --function-name vpn-slack-handler-staging \
  --query Timeout \
  --profile staging
```

**修復**：在 CDK 設定中增加逾時時間

#### 權限錯誤
**症狀**：日誌中出現 AccessDenied

**檢查**：
```bash
aws iam get-role-policy \
  --role-name VpnCostAutomationStack-staging-SlackHandlerRole \
  --policy-name DefaultPolicy \
  --profile staging
```

**修復**：在 CDK 中更新 IAM 政策

#### API Gateway 502 錯誤
**症狀**：Bad Gateway 響應

**檢查**：
1. Lambda 函數日誌
2. API Gateway 整合設定
3. Lambda 函數健康狀態

**修復**：
```bash
# 重新部署 API Gateway
./scripts/deploy.sh staging --force-update-api
```

### 緊急程序

#### 系統完全故障
1. **通知相關人員**
2. **檢查 AWS 服務健康狀態**
3. **檢視 CloudWatch 日誌**
4. **必要時重新部署**：
```bash
./scripts/deploy.sh both --secure-parameters --force
```

#### 回滾部署
```bash
# 列出之前的部署
aws cloudformation list-stack-resources \
  --stack-name VpnCostAutomationStack-staging \
  --profile staging

# 回滾至前一版本
cdk deploy --rollback --profile staging
```

## 🔄 災難復原

### 備份策略

#### 自動化備份
```bash
#!/bin/bash
# backup.sh
DATE=$(date +%Y%m%d-%H%M%S)
BACKUP_DIR="backups/$DATE"
mkdir -p $BACKUP_DIR

# 備份 SSM 參數
aws ssm get-parameters-by-path \
  --path "/vpn" \
  --recursive \
  --with-decryption \
  --profile production > $BACKUP_DIR/ssm-params.json

# 備份 Lambda 設定
for func in vpn-slack-handler vpn-control vpn-monitor; do
  aws lambda get-function \
    --function-name $func-production \
    --profile production > $BACKUP_DIR/$func.json
done
```

### 復原程序

#### 從備份復原
```bash
# 復原 SSM 參數
cat backup/ssm-params.json | jq -r '.Parameters[] |
  "aws ssm put-parameter --name \(.Name) --value \(.Value) --type \(.Type) --overwrite"' |
  bash

# 重新部署基礎設施
./scripts/deploy.sh production --secure-parameters
```

### RTO/RPO 目標

| 元件 | RTO | RPO |
|------|-----|-----|
| Lambda 函數 | 5 分鐘 | 0 |
| API Gateway | 5 分鐘 | 0 |
| SSM 參數 | 10 分鐘 | 1 小時 |
| VPN 端點 | 30 分鐘 | N/A |

## 🚀 效能最佳化

### Lambda 最佳化

#### 記憶體設定
```typescript
// CDK 中的最佳設定
const slackHandler = new lambda.Function(this, 'SlackHandler', {
  memorySize: 512,  // 對 I/O 操作的平衡設定
  timeout: Duration.seconds(30),
  reservedConcurrentExecutions: 5
});
```

#### 代碼最佳化
- 在處理程式外初始化 SDK 客戶端
- 快取經常存取的數據
- 使用連線池

### 成本最佳化

#### 監控成本
```bash
# Lambda 調用成本
aws cloudwatch get-metric-statistics \
  --namespace AWS/Lambda \
  --metric-name Invocations \
  --dimensions Name=FunctionName,Value=vpn-slack-handler-staging \
  --start-time $(date -u -d '30 days ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 86400 \
  --statistics Sum \
  --profile staging
```

#### 降低成本
- 調整 Lambda 記憶體配置
- 最佳化預熱頻率
- 設定適當的日誌保留期限

## 📋 維護清單

### 每日
- [ ] 檢查 CloudWatch 錯誤日誌
- [ ] 驗證自動關閉功能
- [ ] 監控 Lambda 錯誤

### 每週
- [ ] 檢視 Lambda 效能指標
- [ ] 檢查成本趋勢
- [ ] 必要時更新相依性

### 每月
- [ ] 完整系統健康檢查
- [ ] 安全更新
- [ ] 文件更新
- [ ] 備份驗證

## 🆘 支援資源

### 內部
- Slack：#devops 頻道
- Wiki：基礎設施文件
- Runbook：緊急程序

### 外部
- [AWS CDK 文件](https://docs.aws.amazon.com/cdk/)
- [Lambda 最佳實踐](https://docs.aws.amazon.com/lambda/latest/dg/best-practices.html)
- [GitHub Issues](https://github.com/your-org/vpn-toolkit/issues)

---

**管理任務：**請參閱[管理員指南](admin-guide.md)
**架構相關：**請參閱[架構文件](architecture.md)