# AWS Profile 故障排除指南

本指南提供雙 AWS Profile 管理系統常見問題的診斷和解決方案。

## 目錄

1. [快速診斷](#快速診斷)
2. [Profile 檢測問題](#profile-檢測問題)
3. [跨帳戶驗證錯誤](#跨帳戶驗證錯誤)
4. [環境切換失敗](#環境切換失敗)
5. [S3 存儲桶訪問問題](#s3-存儲桶訪問問題)
6. [零接觸工作流程問題](#零接觸工作流程問題)
7. [進階診斷工具](#進階診斷工具)
8. [常見錯誤訊息](#常見錯誤訊息)

## 快速診斷

### 第一步：檢查系統狀態

```bash
# 檢查當前環境和 profile 狀態
./vpn_env.sh status

# 檢查可用的 AWS profiles
aws configure list-profiles

# 測試 AWS 連接
aws sts get-caller-identity --profile staging
aws sts get-caller-identity --profile production
```

### 第二步：執行自動化測試

```bash
# 執行完整的 profile 管理測試
./tests/test_profile_management.sh

# 檢查測試結果和報告
ls -la tests/*test_results*.txt
```

### 第三步：檢查環境配置

```bash
# 驗證環境配置檔案
source configs/staging/staging.env && echo "Staging config OK"
source configs/production/production.env && echo "Production config OK"

# 檢查必要變數
grep -E "(ENV_AWS_PROFILE|ACCOUNT_ID|S3_BUCKET)" configs/*/staging.env configs/*/production.env
```

## Profile 檢測問題

### 問題：系統無法自動檢測 AWS profiles

**症狀**:
```
錯誤: 無法檢測到適當的 AWS profile
Warning: AWS Profile 設定可能有問題
```

**診斷步驟**:

1. **檢查 AWS CLI 安裝**:
   ```bash
   aws --version
   aws configure list-profiles
   ```

2. **檢查 profiles 檔案**:
   ```bash
   ls -la ~/.aws/
   cat ~/.aws/config
   cat ~/.aws/credentials
   ```

3. **測試 profile 功能**:
   ```bash
   aws configure get region --profile staging
   aws configure get region --profile production
   ```

**解決方案**:

1. **建立缺失的 profiles**:
   ```bash
   aws configure --profile staging
   aws configure --profile production
   ```

2. **修復權限問題**:
   ```bash
   chmod 600 ~/.aws/credentials
   chmod 644 ~/.aws/config
   ```

3. **手動指定 profile**:
   ```bash
   # 編輯環境配置檔案
   echo 'ENV_AWS_PROFILE="staging"' >> configs/staging/staging.env
   echo 'ENV_AWS_PROFILE="production"' >> configs/production/production.env
   ```

### 問題：Profile 命名不符合約定

**症狀**:
```
警告: 找不到建議的 profile 名稱
可用的 profiles: default, my-aws-account
```

**解決方案**:

1. **更新建議的 profile 清單**:
   ```bash
   # 編輯 configs/staging/staging.env
   SUGGESTED_PROFILES="default,my-aws-account,custom-staging"
   
   # 編輯 configs/production/production.env  
   SUGGESTED_PROFILES="default,my-aws-account,custom-production"
   ```

2. **重新命名現有 profiles**:
   ```bash
   # 備份現有配置
   cp ~/.aws/config ~/.aws/config.backup
   cp ~/.aws/credentials ~/.aws/credentials.backup
   
   # 手動編輯檔案或使用 AWS CLI 重新配置
   aws configure --profile staging
   aws configure --profile production
   ```

## 跨帳戶驗證錯誤

### 問題：帳戶 ID 不匹配警告

**症狀**:
```
警告: AWS Profile 與環境不匹配
當前帳戶: 123456789012, 預期帳戶: 987654321098
狀態: ⚠ 有效但可能不匹配環境
```

**診斷步驟**:

1. **確認當前帳戶 ID**:
   ```bash
   aws sts get-caller-identity --profile staging --query Account --output text
   aws sts get-caller-identity --profile production --query Account --output text
   ```

2. **檢查配置檔案中的帳戶 ID**:
   ```bash
   grep ACCOUNT_ID configs/staging/staging.env
   grep ACCOUNT_ID configs/production/production.env
   ```

**解決方案**:

1. **更新配置檔案中的帳戶 ID**:
   ```bash
   # 取得實際帳戶 ID
   STAGING_ACCOUNT=$(aws sts get-caller-identity --profile staging --query Account --output text)
   PRODUCTION_ACCOUNT=$(aws sts get-caller-identity --profile production --query Account --output text)
   
   # 更新配置檔案
   sed -i.bak "s/STAGING_ACCOUNT_ID=.*/STAGING_ACCOUNT_ID=\"$STAGING_ACCOUNT\"/" configs/staging/staging.env
   sed -i.bak "s/PRODUCTION_ACCOUNT_ID=.*/PRODUCTION_ACCOUNT_ID=\"$PRODUCTION_ACCOUNT\"/" configs/production/production.env
   ```

2. **驗證修復**:
   ```bash
   ./vpn_env.sh switch staging
   ./vpn_env.sh status
   ```

### 問題：使用錯誤的 AWS 帳戶

**症狀**:
```
錯誤: AWS Profile 設定有問題，無法安全執行操作
跨帳戶操作防護已啟動
```

**解決方案**:

1. **確認目標環境**:
   ```bash
   ./vpn_env.sh status
   echo "當前環境: $CURRENT_ENVIRONMENT"
   ```

2. **切換到正確的環境**:
   ```bash
   ./vpn_env.sh switch staging    # 或 production
   ```

3. **手動選擇正確的 profile**:
   ```bash
   ./admin-tools/aws_vpn_admin.sh --set-profile correct-profile-name
   ```

## 環境切換失敗

### 問題：無法切換到目標環境

**症狀**:
```
錯誤: 無法初始化環境管理器
環境切換失敗
```

**診斷步驟**:

1. **檢查環境配置檔案**:
   ```bash
   ls -la configs/staging/staging.env
   ls -la configs/production/production.env
   ```

2. **驗證配置檔案語法**:
   ```bash
   bash -n configs/staging/staging.env
   bash -n configs/production/production.env
   ```

3. **檢查檔案權限**:
   ```bash
   ls -la configs/staging/staging.env
   ls -la configs/production/production.env
   ```

**解決方案**:

1. **修復檔案權限**:
   ```bash
   chmod 644 configs/staging/staging.env
   chmod 644 configs/production/production.env
   ```

2. **重新創建配置檔案**:
   ```bash
   # 備份現有檔案
   cp configs/staging/staging.env configs/staging/staging.env.backup
   
   # 檢查語法錯誤並修復
   source configs/staging/staging.env
   ```

3. **強制重新初始化**:
   ```bash
   rm .current_env
   ./vpn_env.sh switch staging --force-init
   ```

## S3 存儲桶訪問問題

### 問題：無法訪問 S3 存儲桶

**症狀**:
```
無法訪問 S3 存儲桶: staging-vpn-csr-exchange
Access Denied 或 NoSuchBucket 錯誤
```

**診斷步驟**:

1. **檢查存儲桶是否存在**:
   ```bash
   aws s3 ls --profile staging
   aws s3 ls --profile production
   ```

2. **測試存儲桶訪問權限**:
   ```bash
   aws s3 ls s3://staging-vpn-csr-exchange --profile staging
   aws s3 ls s3://production-vpn-csr-exchange --profile production
   ```

3. **檢查 IAM 權限**:
   ```bash
   aws iam list-attached-user-policies --user-name your-username --profile staging
   ```

**解決方案**:

1. **建立缺失的 S3 存儲桶**:
   ```bash
   ./admin-tools/setup_csr_s3_bucket.sh --publish-assets
   ```

2. **檢查和修復 IAM 政策**:
   ```bash
   ./admin-tools/setup_csr_s3_bucket.sh --create-users
   ./admin-tools/setup_csr_s3_bucket.sh --list-users
   ```

3. **使用自定義存儲桶名稱**:
   ```bash
   # 更新環境配置
   echo 'STAGING_S3_BUCKET="my-custom-staging-bucket"' >> configs/staging/staging.env
   echo 'PRODUCTION_S3_BUCKET="my-custom-production-bucket"' >> configs/production/production.env
   ```

## 零接觸工作流程問題

### 問題：團隊成員無法下載配置

**症狀**:
```
無法從 S3 下載 CA 證書
無法獲取端點配置資訊
```

**診斷步驟**:

1. **檢查公共資產是否已發布**:
   ```bash
   aws s3 ls s3://staging-vpn-csr-exchange/public/ --profile staging
   ```

2. **驗證檔案內容**:
   ```bash
   aws s3 cp s3://staging-vpn-csr-exchange/public/ca.crt /tmp/test-ca.crt --profile staging
   openssl x509 -in /tmp/test-ca.crt -text -noout
   ```

**解決方案**:

1. **重新發布公共資產**:
   ```bash
   ./admin-tools/publish_endpoints.sh
   ./admin-tools/publish_endpoints.sh -e staging --force
   ./admin-tools/publish_endpoints.sh -e production --force
   ```

2. **檢查端點配置**:
   ```bash
   aws s3 cp s3://staging-vpn-csr-exchange/public/vpn_endpoints.json /tmp/endpoints.json --profile staging
   cat /tmp/endpoints.json | jq .
   ```

### 問題：CSR 上傳失敗

**症狀**:
```
無法上傳 CSR 到 S3
Access Denied when uploading CSR
```

**解決方案**:

1. **檢查用戶 IAM 權限**:
   ```bash
   ./admin-tools/setup_csr_s3_bucket.sh --list-users
   ```

2. **重新建立 IAM 政策**:
   ```bash
   ./admin-tools/setup_csr_s3_bucket.sh --create-users
   ```

3. **使用傳統工作流程**:
   ```bash
   ./team_member_setup.sh --no-s3
   ```

## 進階診斷工具

### 啟用詳細日誌模式

```bash
# 設定詳細模式環境變數
export VERBOSE_MODE=true
export DEBUG_PROFILE=true

# 重新執行有問題的操作
./vpn_env.sh switch staging -v
./admin-tools/aws_vpn_admin.sh --verbose
```

### 檢查系統日誌

```bash
# 檢查環境特定日誌
tail -f logs/staging/*.log
tail -f logs/production/*.log

# 搜尋特定錯誤
grep -r "ERROR\|FAIL" logs/
grep -r "Profile" logs/ | tail -20
```

### 手動測試 Profile 函數

```bash
# 載入函數庫
source lib/env_manager.sh
source lib/core_functions.sh

# 手動測試函數
detect_available_aws_profiles
map_environment_to_profiles "staging"
validate_profile_matches_environment "staging" "staging"
```

### 建立診斷報告

```bash
# 建立完整的診斷報告
{
    echo "=== 系統狀態 ==="
    ./vpn_env.sh status
    echo ""
    
    echo "=== AWS Profiles ==="
    aws configure list-profiles
    echo ""
    
    echo "=== AWS 身份 ==="
    aws sts get-caller-identity --profile staging 2>&1
    aws sts get-caller-identity --profile production 2>&1
    echo ""
    
    echo "=== 環境配置 ==="
    grep -E "(ENV_AWS_PROFILE|ACCOUNT_ID)" configs/*/staging.env configs/*/production.env
    echo ""
    
    echo "=== 測試結果 ==="
    ./tests/test_profile_management.sh 2>&1 | tail -10
    
} > diagnostic_report_$(date +%Y%m%d_%H%M%S).txt

echo "診斷報告已建立: diagnostic_report_*.txt"
```

## 常見錯誤訊息

### "AWS Profile 設定有問題"

**原因**: Profile 未正確配置或帳戶 ID 不匹配
**解決**: 檢查 AWS profile 配置和帳戶 ID 設定

### "無法初始化環境管理器"

**原因**: 環境配置檔案損壞或權限問題
**解決**: 檢查配置檔案語法和權限

### "跨帳戶操作防護已啟動"

**原因**: 嘗試在錯誤的 AWS 帳戶執行操作
**解決**: 切換到正確的環境和 profile

### "找不到建議的 profile 名稱"

**原因**: Profile 命名不符合系統期望
**解決**: 更新 SUGGESTED_PROFILES 配置或重新命名 profiles

### "S3 存儲桶訪問失敗"

**原因**: S3 存儲桶不存在或權限不足
**解決**: 重新建立 S3 存儲桶和 IAM 政策

## 預防措施

### 定期維護檢查

```bash
# 每週執行一次檢查
./tests/test_profile_management.sh
./tests/test_team_member_setup.sh
./tests/test_admin_tools.sh

# 檢查日誌大小並清理
find logs/ -name "*.log" -size +10M
```

### 備份重要配置

```bash
# 備份 AWS 配置
cp -r ~/.aws ~/.aws.backup.$(date +%Y%m%d)

# 備份環境配置
tar czf env_configs_backup_$(date +%Y%m%d).tar.gz configs/
```

### 定期更新帳戶 ID

```bash
# 定期驗證帳戶 ID 是否正確
STAGING_ACCOUNT=$(aws sts get-caller-identity --profile staging --query Account --output text)
PRODUCTION_ACCOUNT=$(aws sts get-caller-identity --profile production --query Account --output text)

echo "Staging Account: $STAGING_ACCOUNT"
echo "Production Account: $PRODUCTION_ACCOUNT"
```

## 獲取進一步支援

如果問題持續存在：

1. **收集完整的診斷資訊** (使用上述診斷報告腳本)
2. **檢查測試結果** 並提供測試報告檔案
3. **記錄具體的錯誤訊息** 和復現步驟
4. **聯絡系統管理員** 並提供診斷報告

---

## 快速參考

### 常用診斷命令
```bash
./vpn_env.sh status                               # 檢查狀態
aws configure list-profiles                       # 列出 profiles
./tests/test_profile_management.sh               # 執行測試
grep -E "(ENV_AWS_PROFILE|ACCOUNT_ID)" configs/*/*.env  # 檢查配置
```

### 常用修復命令
```bash
./admin-tools/aws_vpn_admin.sh --set-profile PROFILE    # 設定 profile
./admin-tools/setup_csr_s3_bucket.sh --create-users     # 修復 S3 權限
./admin-tools/publish_endpoints.sh --force              # 重新發布資產
rm .current_env && ./vpn_env.sh switch ENV              # 重置環境
```

這個故障排除指南應該能解決大部分 AWS Profile 相關的問題。如果遇到未涵蓋的問題，請建立新的診斷報告並聯絡支援團隊。