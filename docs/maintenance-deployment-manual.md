# AWS Client VPN 維護部署手冊

## 目錄

1. [系統架構總覽](#系統架構總覽)
2. [部署前準備](#部署前準備)
3. [基礎設施部署](#基礎設施部署)
4. [Lambda 函數開發](#lambda-函數開發)
5. [CDK 部署管理](#cdk-部署管理)
6. [系統配置管理](#系統配置管理)
7. [監控與日誌](#監控與日誌)
8. [維護作業](#維護作業)
9. [故障排除指南](#故障排除指南)
10. [災難復原](#災難復原)
11. [效能優化](#效能優化)
12. [安全加固](#安全加固)

## 系統架構總覽

### 架構圖

```mermaid
graph TB
    subgraph "Slack Interface"
        A[Slack Commands] --> B[Slack App]
    end
    
    subgraph "API Layer"
        B --> C[API Gateway Staging]
        B --> D[API Gateway Production]
    end
    
    subgraph "Lambda Functions"
        C --> E[slack-handler-staging]
        D --> F[slack-handler-production]
        E --> G[vpn-control-staging]
        F --> H[vpn-control-production]
        I[vpn-monitor-staging]
        J[vpn-monitor-production]
    end
    
    subgraph "Data Store"
        K[SSM Parameter Store]
        L[S3 Buckets]
    end
    
    subgraph "VPN Infrastructure"
        M[Client VPN Endpoints]
        N[VPC/Subnets]
        O[Security Groups]
    end
    
    G --> K
    H --> K
    I --> K
    J --> K
    G --> M
    H --> M
```

### 技術堆疊

- **基礎設施即代碼**: AWS CDK v2 (TypeScript)
- **運行時**: Node.js 20.x
- **Lambda 層**: 共享程式碼和依賴
- **API**: REST API via API Gateway
- **狀態管理**: SSM Parameter Store
- **監控**: CloudWatch Logs/Metrics
- **安全**: KMS, IAM, Security Groups

### 雙環境架構

系統採用完全隔離的雙環境設計：

| 特性 | Staging | Production |
|------|---------|------------|
| AWS 帳戶 | 獨立帳戶 | 獨立帳戶 |
| API Gateway | 獨立端點 | 獨立端點 |
| Lambda 函數 | 獨立部署 | 獨立部署 |
| VPN 端點 | 測試用 | 正式用 |
| 參數存儲 | 環境隔離 | 環境隔離 |
| 監控告警 | 寬鬆閾值 | 嚴格閾值 |

## 部署前準備

### 1. 環境需求

```bash
# 檢查 Node.js 版本
node --version  # 需要 v20.x 或更高

# 檢查 npm 版本
npm --version   # 需要 v10.x 或更高

# 檢查 AWS CLI
aws --version   # 需要 v2.x

# 檢查 CDK
cdk --version   # 需要 v2.x
```

### 2. AWS 帳戶設置

#### 配置 AWS Profiles
```bash
# Production 環境
aws configure --profile prod
# 輸入 Access Key ID, Secret Access Key, Region, Output format

# Staging 環境
aws configure --profile staging
# 輸入相應的認證資訊
```

#### 驗證配置
```bash
# 測試 Production profile
aws sts get-caller-identity --profile prod

# 測試 Staging profile
aws sts get-caller-identity --profile staging
```

### 3. CDK Bootstrap

每個 AWS 帳戶需要執行一次 bootstrap：

```bash
# Bootstrap Production 帳戶
cd cdklib
AWS_PROFILE=prod cdk bootstrap

# Bootstrap Staging 帳戶
AWS_PROFILE=staging cdk bootstrap
```

### 4. 準備 Slack 資訊

收集以下資訊：
- Slack Webhook URL
- Slack Signing Secret（32字元十六進位）
- Slack Bot Token（xoxb- 開頭）

## 基礎設施部署

### 完整部署流程

#### 1. 自動化部署（推薦）

```bash
# 部署雙環境
./scripts/deploy.sh both --secure-parameters

# 查看部署狀態
./scripts/deploy.sh status
```

#### 2. 配置系統參數

```bash
# 設定所有參數
./scripts/setup-parameters.sh --all --secure --auto-read \
  --slack-webhook "https://hooks.slack.com/services/YOUR/WEBHOOK" \
  --slack-secret "your-32-char-hex-secret" \
  --slack-bot-token "xoxb-your-bot-token"
```

#### 3. 單環境部署

```bash
# 只部署 Staging
./scripts/deploy.sh staging --secure-parameters

# 只部署 Production
./scripts/deploy.sh production --secure-parameters
```

### CDK Stack 結構

```typescript
// 主要 Stack 定義
export class VpnCostAutomationStack extends cdk.Stack {
  constructor(scope: Construct, id: string, props: VpnStackProps) {
    // KMS 金鑰
    const kmsKey = new kms.Key(this, 'ParameterStoreKey');
    
    // Lambda 層
    const sharedLayer = new lambda.LayerVersion(this, 'SharedLayer');
    
    // Lambda 函數
    const slackHandler = new lambda.Function(this, 'SlackHandler');
    const vpnControl = new lambda.Function(this, 'VpnControl');
    const vpnMonitor = new lambda.Function(this, 'VpnMonitor');
    
    // API Gateway
    const api = new apigateway.RestApi(this, 'VpnApi');
  }
}
```

### 部署驗證

```bash
# 檢查 CloudFormation Stack
aws cloudformation describe-stacks \
  --stack-name VpnCostAutomationStack-staging \
  --profile staging

# 測試 API 端點
curl -X POST https://your-api-gateway-url/slack \
  -H "Content-Type: application/json" \
  -d '{"text":"test"}'
```

## Lambda 函數開發

### 專案結構

```
lambda/
├── slack-handler/       # Slack 指令處理
│   ├── index.ts        # 主要處理邏輯
│   ├── build.sh        # 編譯腳本
│   └── dist/           # 編譯輸出
├── vpn-control/        # VPN 操作控制
│   ├── index.ts
│   ├── build.sh
│   └── dist/
├── vpn-monitor/        # 自動監控
│   ├── index.ts
│   ├── build.sh
│   └── dist/
└── shared/             # 共享層
    ├── logger.ts       # 日誌工具
    ├── slack.ts        # Slack 工具
    ├── stateStore.ts   # 狀態管理
    ├── types.ts        # TypeScript 類型
    └── vpnManager.ts   # VPN 管理
```

### 開發流程

#### 1. 修改程式碼

```typescript
// 範例：修改閒置時間門檻
// lambda/vpn-monitor/index.ts
const IDLE_MINUTES = Number(process.env.IDLE_MINUTES || 54);
```

#### 2. 本地編譯

```bash
# 編譯單一函數
cd lambda/slack-handler
./build.sh

# 編譯所有函數
cd lambda
for dir in */; do
  if [ -f "$dir/build.sh" ]; then
    (cd "$dir" && ./build.sh)
  fi
done
```

#### 3. 部署更新

```bash
# 部署到 Staging 測試
./scripts/deploy.sh staging

# 確認無誤後部署到 Production
./scripts/deploy.sh production
```

### Lambda 層管理

共享層包含所有共用程式碼：

```typescript
// 使用共享層
import { VpnCommandRequest } from '/opt/nodejs/types';
import * as vpnManager from '/opt/nodejs/vpnManager';
import * as slack from '/opt/nodejs/slack';
```

更新共享層：
```bash
cd lambda/shared
npm install
npx tsc
# 層會在下次部署時自動更新
```

### 環境變數配置

Lambda 函數使用的環境變數：

| 變數名 | 用途 | 範例值 |
|--------|------|--------|
| `ENVIRONMENT` | 環境標識 | staging/production |
| `APP_ENV` | 應用環境 | staging/production |
| `IDLE_MINUTES` | 閒置門檻 | 54 |
| `COOLDOWN_MINUTES` | 冷卻期 | 30 |
| `LOG_LEVEL` | 日誌等級 | INFO/DEBUG |

## CDK 部署管理

### 部署腳本詳解

`deploy.sh` 提供完整的部署管理功能：

#### 基本操作
```bash
# 查看幫助
./scripts/deploy.sh --help

# 部署狀態
./scripts/deploy.sh status

# 驗證路由
./scripts/deploy.sh validate-routing
```

#### 進階選項
```bash
# 跳過編譯（快速部署）
./scripts/deploy.sh staging --skip-build

# 強制重新編譯
./scripts/deploy.sh production --force-build

# 詳細輸出
./scripts/deploy.sh both --verbose
```

### CDK 配置

#### cdk.json 設定
```json
{
  "app": "npx ts-node --prefer-ts-exts bin/vpn-cost-automation.ts",
  "context": {
    "@aws-cdk/core:enableStackNameDuplicates": false,
    "@aws-cdk/core:stackRelativeExports": true
  }
}
```

#### Stack 命名慣例
- Staging: `VpnCostAutomationStack-staging`
- Production: `VpnCostAutomationStack-production`
- 安全參數: `VpnSecureParametersStack-{env}`

### 部署故障處理

#### CDK 部署失敗
```bash
# 查看詳細錯誤
cdk deploy --profile staging --verbose

# 清理失敗的 Stack
aws cloudformation delete-stack \
  --stack-name VpnCostAutomationStack-staging \
  --profile staging
```

#### 回滾部署
```bash
# 查看部署歷史
aws cloudformation list-stack-resources \
  --stack-name VpnCostAutomationStack-production \
  --profile prod

# 手動回滾
cdk deploy --rollback \
  --profile prod
```

## 系統配置管理

### SSM Parameter Store 架構

參數命名規範：
```
/vpn/{environment}/{category}/{parameter}
```

關鍵參數：

| 參數路徑 | 用途 | 類型 |
|----------|------|------|
| `/vpn/slack/signing_secret` | Slack 驗證 | SecureString |
| `/vpn/slack/bot_token` | Slack Bot | SecureString |
| `/vpn/slack/webhook` | Slack Webhook | SecureString |
| `/vpn/{env}/endpoint/conf` | VPN 配置 | String |
| `/vpn/state/last_manual_activity` | 活動時間 | String |

### 參數管理操作

#### 查看參數
```bash
# 列出所有參數
aws ssm describe-parameters \
  --profile staging \
  --query "Parameters[?starts_with(Name, '/vpn/')]"

# 讀取特定參數
aws ssm get-parameter \
  --name "/vpn/staging/endpoint/conf" \
  --profile staging
```

#### 更新參數
```bash
# 更新一般參數
aws ssm put-parameter \
  --name "/vpn/staging/cost/optimization_config" \
  --value '{"idleTimeoutMinutes":54}' \
  --type String \
  --overwrite \
  --profile staging

# 更新加密參數
aws ssm put-parameter \
  --name "/vpn/slack/signing_secret" \
  --value "your-secret" \
  --type SecureString \
  --key-id alias/vpn-parameter-store-staging \
  --overwrite \
  --profile staging
```

### 配置驗證

```bash
# 驗證所有配置
./admin-tools/tools/validate_config.sh

# 檢查參數完整性
./scripts/setup-parameters.sh --validate
```

## 監控與日誌

### CloudWatch Logs

#### 日誌群組結構
```
/aws/lambda/vpn-slack-handler-{environment}
/aws/lambda/vpn-control-{environment}
/aws/lambda/vpn-monitor-{environment}
```

#### 查看即時日誌
```bash
# Slack Handler 日誌
aws logs tail /aws/lambda/vpn-slack-handler-staging \
  --follow \
  --profile staging

# 搜尋特定錯誤
aws logs filter-log-events \
  --log-group-name /aws/lambda/vpn-control-production \
  --filter-pattern "ERROR" \
  --profile prod
```

### CloudWatch Metrics

#### 自定義指標
- `VPN/Automation/VpnOpenOperations`
- `VPN/Automation/VpnCloseOperations`
- `VPN/Automation/AutoCloseTriggered`
- `VPN/Automation/CostSaved`

#### 創建告警
```bash
aws cloudwatch put-metric-alarm \
  --alarm-name "VPN-High-Error-Rate" \
  --alarm-description "Alert on high Lambda error rate" \
  --metric-name Errors \
  --namespace AWS/Lambda \
  --statistic Sum \
  --period 300 \
  --threshold 10 \
  --comparison-operator GreaterThanThreshold \
  --evaluation-periods 2 \
  --profile prod
```

### 日誌分析查詢

#### CloudWatch Insights 查詢範例

```sql
-- 查找所有錯誤
fields @timestamp, @message
| filter @message like /ERROR/
| sort @timestamp desc
| limit 100

-- 統計每小時操作次數
stats count() by bin(1h) as hour
| filter @message like /VPN operation/

-- 分析成本節省
fields @timestamp, @message
| filter @message like /Cost saved/
| parse @message /Cost saved: \$(?<saved>\d+\.\d+)/
| stats sum(saved) by bin(1d)
```

## 維護作業

### 定期維護清單

#### 每日檢查
- [ ] 檢查 Lambda 錯誤率
- [ ] 確認自動關閉功能正常
- [ ] 審查異常 Slack 指令

#### 每週任務
- [ ] 分析成本節省報告
- [ ] 檢查證書有效期
- [ ] 清理過期日誌

#### 每月任務
- [ ] 更新 Lambda 函數依賴
- [ ] 審查 IAM 權限
- [ ] 效能分析和優化

### 更新作業

#### 更新 Lambda 函數程式碼
```bash
# 1. 修改程式碼
# 2. 本地測試
# 3. 部署到 Staging
./scripts/deploy.sh staging

# 4. 測試驗證
# 5. 部署到 Production
./scripts/deploy.sh production
```

#### 更新依賴套件
```bash
# 更新共享層
cd lambda/shared
npm update
npm audit fix

# 更新各函數
cd ../slack-handler
npm update
```

#### 更新 CDK
```bash
cd cdklib
npm update aws-cdk-lib
npm update @types/node
```

### 備份策略

#### 配置備份
```bash
# 備份 SSM 參數
aws ssm get-parameters-by-path \
  --path "/vpn" \
  --recursive \
  --with-decryption \
  --profile prod > backup/ssm-params-$(date +%Y%m%d).json
```

#### 程式碼備份
- 使用 Git 版本控制
- 定期推送到遠端儲存庫
- 標記重要版本

## 故障排除指南

### Lambda 函數問題

#### 問題：函數逾時
**症狀**：Slack 指令無回應

**診斷**：
```bash
# 檢查函數配置
aws lambda get-function-configuration \
  --function-name vpn-slack-handler-staging \
  --profile staging
```

**解決方案**：
- 增加函數逾時設定
- 優化程式碼效能
- 檢查網路連線

#### 問題：權限錯誤
**症狀**：AccessDenied 錯誤

**診斷**：
```bash
# 檢查執行角色
aws iam get-role \
  --role-name VpnCostAutomationStack-staging-SlackHandlerRole \
  --profile staging
```

**解決方案**：
- 更新 IAM 政策
- 檢查資源權限
- 驗證跨帳戶存取

### API Gateway 問題

#### 問題：502 Bad Gateway
**可能原因**：
- Lambda 函數錯誤
- 整合配置錯誤
- 逾時設定太短

**解決步驟**：
1. 檢查 Lambda 日誌
2. 測試 Lambda 函數獨立運行
3. 驗證 API Gateway 整合設定

### VPN 端點問題

#### 問題：端點 ID 不匹配
```bash
# 自動修復
./admin-tools/tools/fix_endpoint_id.sh

# 手動更新
aws ssm put-parameter \
  --name "/vpn/staging/endpoint/conf" \
  --value '{"ENDPOINT_ID":"cvpn-endpoint-xxxxx","SUBNET_ID":"subnet-xxxxx"}' \
  --overwrite \
  --profile staging
```

## 災難復原

### 備份和恢復策略

#### 1. 配置備份
```bash
# 自動備份腳本
#!/bin/bash
DATE=$(date +%Y%m%d-%H%M%S)
BACKUP_DIR="backups/$DATE"
mkdir -p $BACKUP_DIR

# 備份 SSM 參數
aws ssm get-parameters-by-path \
  --path "/vpn" \
  --recursive \
  --with-decryption \
  --profile prod > $BACKUP_DIR/ssm-params.json

# 備份 Lambda 函數配置
for func in vpn-slack-handler vpn-control vpn-monitor; do
  aws lambda get-function \
    --function-name $func-production \
    --profile prod > $BACKUP_DIR/$func-config.json
done
```

#### 2. 恢復程序
```bash
# 恢復 SSM 參數
cat backup/ssm-params.json | jq -r '.Parameters[] | 
  "aws ssm put-parameter --name \(.Name) --value \(.Value) --type \(.Type) --overwrite"' | 
  bash

# 重新部署基礎設施
./scripts/deploy.sh production --secure-parameters
```

### RTO 和 RPO 目標

| 組件 | RTO | RPO | 恢復方法 |
|------|-----|-----|----------|
| Lambda 函數 | 5 分鐘 | 0 | 重新部署 |
| API Gateway | 5 分鐘 | 0 | CDK 部署 |
| SSM 參數 | 10 分鐘 | 1 小時 | 從備份恢復 |
| VPN 端點 | 30 分鐘 | N/A | 重新創建 |

### 應急計劃

#### 完全系統故障
1. 通知所有相關人員
2. 啟用手動 VPN 管理流程
3. 從備份恢復配置
4. 重新部署所有組件
5. 驗證系統功能

#### 部分功能故障
1. 識別受影響組件
2. 隔離問題範圍
3. 執行針對性修復
4. 監控恢復情況

## 效能優化

### Lambda 冷啟動優化

#### 1. 預留並發
```typescript
// CDK 配置
const slackHandler = new lambda.Function(this, 'SlackHandler', {
  reservedConcurrentExecutions: 5,
  // 其他配置...
});
```

#### 2. 記憶體優化
```bash
# 增加記憶體配置
aws lambda update-function-configuration \
  --function-name vpn-slack-handler-production \
  --memory-size 512 \
  --profile prod
```

### 程式碼優化

#### 1. 連線重用
```typescript
// 在 handler 外部初始化
const ec2Client = new EC2Client({});

export const handler = async (event: any) => {
  // 重用 client
};
```

#### 2. 快取策略
```typescript
// 快取參數
let cachedParams: any = null;
let cacheExpiry = 0;

async function getParameters() {
  if (cachedParams && Date.now() < cacheExpiry) {
    return cachedParams;
  }
  // 獲取新參數
  cachedParams = await fetchParameters();
  cacheExpiry = Date.now() + 300000; // 5分鐘
  return cachedParams;
}
```

### 成本優化

#### 1. Lambda 成本
- 調整記憶體配置
- 優化執行時間
- 使用 ARM 架構

#### 2. CloudWatch 成本
- 設定日誌保留期
- 減少詳細監控
- 優化日誌輸出

## 安全加固

### IAM 最佳實踐

#### 1. 最小權限原則
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ec2:DescribeClientVpnEndpoints",
        "ec2:AssociateClientVpnTargetNetwork",
        "ec2:DisassociateClientVpnTargetNetwork"
      ],
      "Resource": "arn:aws:ec2:*:*:client-vpn-endpoint/*",
      "Condition": {
        "StringEquals": {
          "aws:RequestedRegion": "${aws:PrincipalTag/AllowedRegion}"
        }
      }
    }
  ]
}
```

#### 2. 角色分離
- Lambda 執行角色
- 部署角色
- 管理員角色

### 網路安全

#### 1. VPC 配置
```typescript
// Lambda VPC 配置
const lambdaSecurityGroup = new ec2.SecurityGroup(this, 'LambdaSG', {
  vpc: vpc,
  allowAllOutbound: false
});

// 只允許必要的出站流量
lambdaSecurityGroup.addEgressRule(
  ec2.Peer.ipv4('10.0.0.0/16'),
  ec2.Port.tcp(443),
  'Allow HTTPS to VPC'
);
```

#### 2. API Gateway 安全
- 啟用 API 金鑰
- 設定使用計劃
- 實施速率限制

### 審計和合規

#### 1. CloudTrail 配置
```bash
# 確保 CloudTrail 已啟用
aws cloudtrail describe-trails --profile prod

# 查看 API 調用
aws cloudtrail lookup-events \
  --lookup-attributes AttributeKey=EventName,AttributeValue=AssociateClientVpnTargetNetwork \
  --profile prod
```

#### 2. 合規檢查
- 定期安全掃描
- 依賴漏洞檢查
- 配置合規驗證

---

## 附錄

### 有用的腳本

#### 健康檢查腳本
```bash
#!/bin/bash
# health_check.sh

echo "=== VPN System Health Check ==="

# 檢查 Lambda 函數
for env in staging production; do
  echo "Checking $env environment..."
  
  # 檢查函數狀態
  aws lambda get-function \
    --function-name vpn-slack-handler-$env \
    --profile $env \
    --query 'Configuration.State' \
    --output text
done

# 檢查 API Gateway
aws apigateway get-rest-apis \
  --profile staging \
  --query 'items[?name==`VpnApi`]'
```

#### 日誌分析腳本
```bash
#!/bin/bash
# analyze_logs.sh

# 統計錯誤數量
aws logs filter-log-events \
  --log-group-name /aws/lambda/vpn-control-production \
  --filter-pattern "[ERROR]" \
  --start-time $(date -u -d '1 hour ago' +%s)000 \
  --profile prod | jq '.events | length'
```

### 常用命令速查

```bash
# 部署
./scripts/deploy.sh both --secure-parameters

# 查看日誌
aws logs tail /aws/lambda/vpn-slack-handler-staging --follow

# 更新參數
./scripts/setup-parameters.sh --env staging --secure

# 診斷問題
./admin-tools/tools/debug_vpn_creation.sh

# 分析效能
./admin-tools/run-vpn-analysis.sh staging
```

---

**文件版本**：1.0  
**最後更新**：2025-06-29  
**適用系統版本**：3.0+