# AWS Client VPN 管理工具套件完整使用說明書

## 目錄
1. [概述](#概述)
2. [系統要求](#系統要求)
3. [初始設置](#初始設置)
4. [檔案系統影響](#檔案系統影響)
5. [工具介紹](#工具介紹)
6. [詳細使用指南](#詳細使用指南)
7. [故障排除](#故障排除)
8. [安全最佳實踐](#安全最佳實踐)
9. [常見問題](#常見問題)
10. [維護和監控](#維護和監控)
11. [完整移除指南](#完整移除指南)
12. [附錄](#附錄)

---

## 概述

AWS Client VPN 管理工具套件是一個專為 macOS 設計的模組化自動化解決方案，用於管理 AWS Client VPN 連接和團隊成員的訪問權限。本套件採用函式庫架構設計，提供企業級的 VPN 管理功能。

### 工具組件
1. **aws_vpn_admin.sh** - 管理員主控台（核心管理工具）
2. **team_member_setup.sh** - 團隊成員設置工具
3. **revoke_member_access.sh** - 權限撤銷工具
4. **employee_offboarding.sh** - 離職處理系統

### 函式庫架構
```
lib/
├── core_functions.sh        # 核心函式和工具
├── aws_setup.sh            # AWS 配置和設置
├── cert_management.sh      # 憑證管理功能
├── endpoint_creation.sh    # VPN 端點創建和管理
└── endpoint_management.sh  # 端點配置和團隊管理
```

### 主要功能
- 🚀 自動建立和管理 AWS Client VPN 端點
- 🔐 為團隊成員生成和管理個人 VPN 證書
- 🔒 安全撤銷訪問權限
- 👥 全面的離職安全處理
- 🌐 多 VPC 網路管理
- 📊 詳細的審計日誌和報告
- ⚡ 模組化設計，易於維護和擴展

---

## 系統要求

### 硬體要求
- macOS 10.15+ (Catalina 或更新版本)
- 至少 4GB RAM
- 2GB 可用磁碟空間
- 穩定的網路連接

### 軟體依賴
本套件會自動安裝以下工具：

- **Homebrew** - macOS 套件管理器
- **AWS CLI** - AWS 命令列工具
- **jq** - JSON 處理工具
- **Easy-RSA** - 證書管理工具
- **OpenSSL** - 加密工具

### AWS 權限要求

#### 管理員權限（執行 aws_vpn_admin.sh）
```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "ec2:*ClientVpn*",
                "acm:*",
                "logs:*",
                "sts:GetCallerIdentity",
                "ec2:DescribeVpcs",
                "ec2:DescribeSubnets",
                "ec2:DescribeAvailabilityZones"
            ],
            "Resource": "*"
        }
    ]
}
```

#### 團隊成員權限（執行 team_member_setup.sh）
```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "ec2:DescribeClientVpnEndpoints",
                "ec2:ExportClientVpnClientConfiguration",
                "acm:ImportCertificate",
                "acm:AddTagsToCertificate"
            ],
            "Resource": "*"
        }
    ]
}
```

#### 高權限操作（employee_offboarding.sh）
```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "iam:*",
                "acm:DeleteCertificate",
                "ec2:TerminateClientVpnConnections",
                "logs:FilterLogEvents",
                "s3:ListAllMyBuckets"
            ],
            "Resource": "*"
        }
    ]
}
```

---

## 初始設置

### 1. 下載和準備

```bash
# 創建工作目錄
mkdir -p ~/aws-vpn-tools
cd ~/aws-vpn-tools

# 確保目錄結構正確
# 應包含以下文件：
# ├── aws_vpn_admin.sh
# ├── team_member_setup.sh
# ├── revoke_member_access.sh
# ├── employee_offboarding.sh
# └── lib/
#     ├── core_functions.sh
#     ├── aws_setup.sh
#     ├── cert_management.sh
#     ├── endpoint_creation.sh
#     └── endpoint_management.sh

# 設置執行權限
chmod +x *.sh
chmod +x lib/*.sh
```

### 2. AWS 配置

管理員首次執行 `aws_vpn_admin.sh` 時，系統會自動引導 AWS 配置：

```bash
./aws_vpn_admin.sh
```

系統會提示輸入：
- AWS Access Key ID
- AWS Secret Access Key  
- Default region (例如：ap-northeast-1)

### 3. 驗證設置

```bash
# 驗證 AWS 配置
aws sts get-caller-identity

# 檢查 VPC 訪問權限
aws ec2 describe-vpcs
```

---

## 檔案系統影響

### 📁 執行後的本地端變更總覽

#### 🔧 **aws_vpn_admin.sh 的檔案影響**

```
專案根目錄/
├── .vpn_config                      # ⚠️ 主配置檔案 (敏感)
├── vpn_admin.log                    # 主操作日誌
├── lib/                            # 函式庫目錄
│   ├── core_functions.sh           # 核心函式庫
│   ├── aws_setup.sh               # AWS 設置函式
│   ├── cert_management.sh         # 憑證管理函式
│   ├── endpoint_creation.sh       # 端點創建函式
│   └── endpoint_management.sh     # 端點管理函式
├── certificates/                   # 🔒 證書目錄 (高度敏感)
│   └── pki/
│       ├── ca.crt                 # CA 證書
│       ├── private/
│       │   ├── ca.key            # 🔐 CA 私鑰 (極度敏感)
│       │   ├── server.key        # 🔐 伺服器私鑰
│       │   └── admin.key         # 🔐 管理員私鑰
│       └── issued/
│           ├── server.crt        # 伺服器證書
│           └── admin.crt         # 管理員證書
├── configs/                        # 管理員 VPN 配置
│   ├── admin-config-base.ovpn     # 基礎配置
│   └── admin-config.ovpn          # 🔒 完整配置 (含私鑰)
└── team-configs/                   # 團隊分發檔案
    ├── team-config-base.ovpn      # 基礎配置
    ├── ca.crt                     # CA 證書副本
    ├── ca.key                     # 🔐 CA 私鑰副本
    └── team-setup-info.txt        # 設置資訊
```

#### 👥 **team_member_setup.sh 的檔案影響**

```
專案目錄/
├── .user_vpn_config               # ⚠️ 用戶配置 (敏感)
├── user_vpn_setup.log            # 用戶設置日誌
├── user-certificates/            # 🔒 用戶證書目錄 (高度敏感)
│   ├── ca.crt                   # CA 證書
│   ├── [username].crt           # 用戶證書
│   └── [username].key           # 🔐 用戶私鑰 (極度敏感)
└── vpn-config/                  # VPN 配置檔案
    ├── client-config-base.ovpn  # 基礎配置
    └── [username]-config.ovpn   # 🔒 個人 VPN 配置 (含私鑰)
```

#### 🚫 **revoke_member_access.sh 的檔案影響**

```
專案目錄/
└── revocation-logs/              # 撤銷日誌目錄
    ├── revocation.log           # 撤銷操作日誌
    └── [username]_revocation_[timestamp].log  # 📋 個別撤銷報告
```

#### 🏢 **employee_offboarding.sh 的檔案影響**

```
專案目錄/
└── offboarding-logs/                           # 離職處理日誌目錄
    ├── offboarding.log                        # 主要離職日誌
    ├── security_report_[employee]_[timestamp].txt      # 📋 安全報告
    ├── offboarding_checklist_[employee]_[timestamp].txt # 📋 檢查清單
    └── audit-[employee_id]-[date]/            # 審計資料目錄
        ├── audit_summary.txt                 # 審計摘要
        ├── cloudtrail_events.json           # CloudTrail 事件記錄
        └── vpn_events_*.json                # VPN 事件日誌
```

### 🔒 **檔案權限和安全設定**

所有敏感檔案會自動設置適當權限：

```bash
# 配置檔案權限 (僅所有者可讀寫)
chmod 600 .vpn_config
chmod 600 .user_vpn_config

# 證書和私鑰權限 (僅所有者可讀寫)
chmod 600 certificates/pki/private/*.key
chmod 600 user-certificates/*.key
chmod 600 *.ovpn

# 目錄權限 (僅所有者可存取)
chmod 700 certificates/
chmod 700 user-certificates/
chmod 700 revocation-logs/
chmod 700 offboarding-logs/
```

---

## 工具介紹

### aws_vpn_admin.sh - 管理員主控台

**核心管理工具**，提供完整的 VPN 基礎設施管理功能。

**主要功能選單：**
1. **建立新的 VPN 端點** - 全自動端點創建流程
2. **查看現有 VPN 端點** - 列出所有端點和狀態
3. **管理 VPN 端點設定** - 授權規則、路由、網路關聯
4. **刪除 VPN 端點** - 安全清理所有相關資源
5. **查看連接日誌** - CloudWatch 日誌分析
6. **匯出團隊成員設定檔** - 為新成員準備設置文件
7. **查看管理員指南** - 內建使用指南
8. **系統健康檢查** - 端點和網路狀態檢查
9. **多 VPC 管理** - 跨 VPC 網路配置

**適用對象：** IT 管理員、DevOps 工程師

### team_member_setup.sh - 團隊成員設置工具

**六步驟設置流程：**
1. 檢查必要工具
2. 設定 AWS 配置
3. 設定用戶資訊
4. 生成個人客戶端證書
5. 導入證書到 ACM
6. 設置 VPN 客戶端

**特色功能：**
- 自動下載並安裝 AWS VPN Client
- 支援現有 AWS 配置複用
- 安全的證書生成和管理
- 完整的錯誤處理和驗證

**適用對象：** 新加入的團隊成員

### revoke_member_access.sh - 權限撤銷工具

**七步驟撤銷流程：**
1. 檢查必要工具和權限
2. 獲取撤銷資訊
3. 搜尋用戶證書
4. 檢查當前連接
5. 撤銷證書和權限
6. 檢查和移除 IAM 權限
7. 生成撤銷報告

**特色功能：**
- 智能證書搜索（域名和標籤）
- 即時斷開活躍連接
- 可選的 IAM 用戶處理
- 詳細的撤銷報告

**適用對象：** IT 管理員

### employee_offboarding.sh - 離職處理系統

**十步驟離職流程：**
1. 檢查系統準備狀態
2. 收集離職人員資訊
3. 執行緊急安全措施（高風險情況）
4. 分析員工的 AWS 資源
5. 撤銷 VPN 訪問權限
6. 清理 IAM 權限
7. 審計訪問日誌
8. 檢查殘留資源
9. 生成安全事件報告
10. 生成離職檢查清單

**特色功能：**
- 風險評估驅動的緊急措施
- 全面的資源搜索和清理
- 30天訪問日誌審計
- 完整的合規報告

**適用對象：** HR、IT 管理員、安全團隊

---

## 詳細使用指南

### 管理員首次設置

#### 步驟 1：建立 VPN 端點

```bash
# 執行管理員腳本
./aws_vpn_admin.sh

# 選擇選項 1：建立新的 VPN 端點
```

**系統會自動執行：**
1. **AWS 配置檢查** - 驗證憑證和權限
2. **證書生成** - 自動創建 CA、伺服器和管理員證書
3. **ACM 導入** - 將證書導入 AWS Certificate Manager
4. **網路配置** - 選擇 VPC 和子網路
5. **端點創建** - 建立 Client VPN 端點
6. **授權設置** - 配置訪問規則
7. **多 VPC 關聯**（可選）- 關聯額外的 VPC

**配置範例：**
```
VPN CIDR: 172.16.0.0/22 (可自定義)
DNS 伺服器: 8.8.8.8, 8.8.4.4
分割通道: 啟用
連接日誌: 啟用 (CloudWatch)
```

#### 步驟 2：測試管理員連接

1. **配置文件位置**
   ```
   configs/admin-config.ovpn
   ```

2. **AWS VPN 客戶端設置**
   - 應用程式會自動安裝
   - 導入 `admin-config.ovpn`
   - 連接名稱：Admin VPN

3. **連接測試**
   ```bash
   # 連接後測試私有資源訪問
   ping [私有IP]
   ```

#### 步驟 3：準備團隊設定

```bash
# 在管理員控制台選擇選項 6
# 系統會生成：
team-configs/
├── team_member_setup.sh      # 團隊成員腳本
├── ca.crt                    # CA 證書
├── team-setup-info.txt       # 設置資訊
└── team-config-base.ovpn     # 基礎配置
```

### 團隊成員設置流程

#### 新成員加入流程

1. **管理員提供文件**
   ```bash
   # 新成員應收到：
   ├── team_member_setup.sh
   ├── ca.crt
   └── VPN 端點 ID
   ```

2. **執行設置**
   ```bash
   ./team_member_setup.sh
   ```

3. **自動化流程**
   - AWS 配置設置或復用
   - 用戶資訊收集
   - 個人證書生成
   - ACM 證書導入
   - VPN 客戶端安裝
   - 配置文件生成

4. **連接測試**
   - 使用 AWS VPN 客戶端
   - 導入個人配置檔案
   - 測試生產環境連接

### 權限管理流程

#### 撤銷用戶訪問

```bash
./revoke_member_access.sh
```

**互動式流程：**
1. 輸入用戶名
2. 選擇 VPN 端點
3. 指定撤銷原因
4. 確認操作（需輸入 'REVOKE'）

**系統執行：**
- 搜索用戶證書（域名和標籤匹配）
- 斷開活躍連接
- 刪除 ACM 證書
- 處理 IAM 權限（可選）
- 生成撤銷報告

#### 離職處理流程

```bash
./employee_offboarding.sh
```

**資訊收集：**
- 員工基本資訊
- 離職類型和風險等級
- AWS 資源範圍

**執行流程：**
- 緊急措施（高風險）
- 全面資源清理
- 訪問日誌審計
- 合規報告生成

---

## 故障排除

### 常見問題和解決方案

#### 1. 模組載入錯誤

**問題：** `錯誤: 核心函式庫未載入`

**原因：** lib 目錄不存在或函式庫文件缺失

**解決方案：**
```bash
# 檢查目錄結構
ls -la lib/

# 確認權限
chmod +x lib/*.sh

# 檢查函式庫文件
ls -la lib/core_functions.sh
```

#### 2. AWS 權限錯誤

**問題：** `AccessDenied` 錯誤

**解決方案：**
```bash
# 檢查當前身份
aws sts get-caller-identity

# 測試權限
aws ec2 describe-client-vpn-endpoints
aws acm list-certificates

# 檢查區域設定
aws configure get region
```

#### 3. 證書生成失敗

**問題：** PKI 初始化失敗

**解決方案：**
```bash
# 檢查目錄權限
chmod 700 certificates/

# 清理並重新初始化
rm -rf certificates/pki
cd certificates/
./easyrsa init-pki
```

#### 4. 配置文件問題

**問題：** `.vpn_config` 文件損壞或缺失

**解決方案：**
```bash
# 檢查配置文件
cat .vpn_config

# 重新運行 AWS 配置
./aws_vpn_admin.sh
# 選擇重新配置 AWS 設定
```

#### 5. VPN 連接失敗

**問題：** 無法連接到 VPN

**診斷步驟：**
```bash
# 檢查端點狀態
aws ec2 describe-client-vpn-endpoints --client-vpn-endpoint-ids cvpn-xxxxxx

# 檢查授權規則
aws ec2 describe-client-vpn-authorization-rules --client-vpn-endpoint-id cvpn-xxxxxx

# 檢查路由
aws ec2 describe-client-vpn-routes --client-vpn-endpoint-id cvpn-xxxxxx
```

### 日誌文件分析

```bash
# 主日誌文件
tail -f vpn_admin.log

# 特定操作日誌
tail -f user_vpn_setup.log
tail -f revocation-logs/revocation.log
tail -f offboarding-logs/offboarding.log

# 系統日誌
grep "ERROR" *.log
grep "WARN" *.log
```

---

## 安全最佳實踐

### 證書安全管理

1. **證書輪換策略**
   ```bash
   # 建議輪換週期
   CA 證書: 每 2 年
   伺服器證書: 每年
   客戶端證書: 每 6 個月
   ```

2. **私鑰保護**
   - 所有 .key 文件自動設為 600 權限
   - CA 私鑰應額外備份到安全位置
   - 考慮使用硬體安全模組（HSM）

3. **證書備份**
   ```bash
   # 創建加密備份
   tar -czf vpn-certs-$(date +%Y%m%d).tar.gz certificates/
   gpg --symmetric --cipher-algo AES256 vpn-certs-$(date +%Y%m%d).tar.gz
   
   # 安全刪除原始 tar 文件
   rm vpn-certs-$(date +%Y%m%d).tar.gz
   ```

### 訪問控制

1. **最小權限原則**
   - 使用專用的 IAM 角色
   - 定期審查 AWS 權限
   - 實施多因素認證

2. **網路分段**
   ```bash
   # 建議的 CIDR 分配
   VPN 客戶端: 172.16.0.0/22
   生產環境: 10.0.0.0/16
   測試環境: 10.1.0.0/16
   ```

3. **監控和審計**
   - 啟用 CloudTrail 詳細記錄
   - 設置 CloudWatch 警報
   - 定期檢查連接日誌

### 配置文件安全

```bash
# 檢查敏感文件權限
find . -name "*.config" -o -name "*.key" -o -name "*.ovpn" | xargs ls -la

# 定期權限檢查腳本
#!/bin/bash
echo "=== 敏感文件權限檢查 ==="
for file in .vpn_config .user_vpn_config; do
    if [ -f "$file" ]; then
        perms=$(stat -f "%Lp" "$file" 2>/dev/null || stat -c "%a" "$file")
        [ "$perms" = "600" ] && echo "✓ $file" || echo "✗ $file ($perms)"
    fi
done
```

---

## 維護和監控

### 定期維護任務

#### 每週檢查清單
- [ ] 檢查所有 VPN 端點狀態
- [ ] 審查新的連接日誌
- [ ] 驗證證書過期日期
- [ ] 檢查 AWS 成本使用情況

#### 每月檢查清單
- [ ] 更新團隊成員清單
- [ ] 審查 IAM 權限
- [ ] 檢查多 VPC 網路配置
- [ ] 備份配置和證書文件

#### 每季檢查清單
- [ ] 全面安全審計
- [ ] 更新 AWS 權限政策
- [ ] 證書輪換計劃
- [ ] 災難恢復測試

### 自動化監控

```bash
# 健康檢查腳本範例
#!/bin/bash
source lib/core_functions.sh

echo "=== VPN 系統健康檢查 ==="

# 檢查端點狀態
if [ -f .vpn_config ]; then
    source .vpn_config
    aws ec2 describe-client-vpn-endpoints \
        --client-vpn-endpoint-ids "$ENDPOINT_ID" \
        --region "$AWS_REGION" \
        --query 'ClientVpnEndpoints[0].Status.Code' \
        --output text
fi

# 檢查證書過期
if [ -d certificates/pki/issued/ ]; then
    for cert in certificates/pki/issued/*.crt; do
        echo "檢查證書: $cert"
        openssl x509 -in "$cert" -noout -dates
    done
fi
```

---

## AWS 資源和成本管理

### 創建的 AWS 資源

#### Core Resources
```bash
# Client VPN 端點
Resource: cvpn-endpoint-xxxxxxx
Monthly Cost: ~$72 + $0.05/hour per connection

# ACM 證書 (免費)
- 伺服器證書: arn:aws:acm:region:account:certificate/xxxxx
- 客戶端 CA 證書: arn:aws:acm:region:account:certificate/xxxxx

# CloudWatch 日誌群組
Log Group: /aws/clientvpn/[VPN_NAME]
Monthly Cost: ~$0.50/GB ingested
```

#### 網路資源
```bash
# 目標網路關聯
每個子網路關聯: cvpn-assoc-xxxxxxx

# 授權規則
主要 VPC 訪問: [VPC_CIDR]
額外 VPC 訪問: [Additional_VPC_CIDRs]

# 路由規則
預設路由: 0.0.0.0/0 -> primary_subnet
VPC 路由: [VPC_CIDR] -> target_subnet
```

### 成本優化建議

1. **連接管理**
   ```bash
   # 監控活躍連接
   aws ec2 describe-client-vpn-connections \
       --client-vpn-endpoint-id cvpn-xxxxxx \
       --query 'Connections[?Status.Code==`active`]' \
       --output table
   ```

2. **日誌保留**
   ```bash
   # 設置日誌保留期限（降低成本）
   aws logs put-retention-policy \
       --log-group-name "/aws/clientvpn/[VPN_NAME]" \
       --retention-in-days 30
   ```

---

## 完整移除指南

### 1. 停止所有服務

```bash
# 斷開所有 VPN 連接
# 在 AWS VPN Client 中手動斷開

# 或查看並終止活躍連接
aws ec2 describe-client-vpn-connections \
    --client-vpn-endpoint-id cvpn-xxxxxx \
    --region [region]

aws ec2 terminate-client-vpn-connections \
    --client-vpn-endpoint-id cvpn-xxxxxx \
    --connection-ids [connection-ids] \
    --region [region]
```

### 2. 使用工具清理 AWS 資源

```bash
# 使用管理員工具清理
./aws_vpn_admin.sh
# 選擇選項 4: 刪除 VPN 端點

# 或手動清理
aws ec2 delete-client-vpn-endpoint \
    --client-vpn-endpoint-id cvpn-xxxxxx \
    --region [region]

aws acm delete-certificate \
    --certificate-arn [certificate-arn] \
    --region [region]
```

### 3. 清理本地文件

```bash
# 安全刪除敏感目錄
rm -rf certificates/
rm -rf user-certificates/
rm -rf configs/
rm -rf team-configs/
rm -rf *-logs/

# 刪除配置文件
rm -f .vpn_config
rm -f .user_vpn_config

# 刪除日誌文件
rm -f *.log
```

### 4. 移除應用程式

```bash
# 移除 AWS VPN Client
sudo rm -rf "/Applications/AWS VPN Client.app"

# 清理下載文件
rm -f ~/Downloads/AWS_VPN_Client.pkg

# 可選：移除 Homebrew 工具
brew uninstall awscli jq easy-rsa
```

---

## 附錄

### A. 配置文件範例

#### .vpn_config 結構
```bash
AWS_REGION=ap-northeast-1
ENDPOINT_ID=cvpn-endpoint-xxxxxxxxxxxxx
VPN_CIDR=172.16.0.0/22
VPN_NAME=Production-VPN
SERVER_CERT_ARN=arn:aws:acm:region:account:certificate/xxxxx
CLIENT_CERT_ARN=arn:aws:acm:region:account:certificate/xxxxx
VPC_ID=vpc-xxxxxxxxxxxxx
VPC_CIDR=10.0.0.0/16
SUBNET_ID=subnet-xxxxxxxxxxxxx
MULTI_VPC_COUNT=1
MULTI_VPC_1="vpc-yyyyy:10.1.0.0/16:subnet-yyyyy:cvpn-assoc-yyyyy"
EASYRSA_DIR=/usr/local/share/easy-rsa
CERT_OUTPUT_DIR=./certificates
SERVER_CERT_NAME_PREFIX=server
CLIENT_CERT_NAME_PREFIX=client
```

### B. 函式庫說明

#### core_functions.sh
- 輸入驗證函數
- 錯誤處理機制
- 日誌記錄功能
- 檔案權限管理
- 跨平台兼容性

#### aws_setup.sh
- AWS CLI 配置
- VPC/子網路選擇
- 區域和權限驗證

#### cert_management.sh
- Easy-RSA 初始化
- 證書生成和管理
- ACM 導入/撤銷
- CRL 管理

#### endpoint_creation.sh
- VPN 端點創建
- 網路關聯管理
- 多 VPC 支援
- 授權和路由配置

#### endpoint_management.sh
- 端點列表和狀態
- 團隊配置生成
- 配置文件管理

### C. 常用 AWS CLI 命令

```bash
# VPN 端點管理
aws ec2 describe-client-vpn-endpoints
aws ec2 create-client-vpn-endpoint [parameters]
aws ec2 delete-client-vpn-endpoint --client-vpn-endpoint-id cvpn-xxxxx

# 網路關聯
aws ec2 associate-client-vpn-target-network [parameters]
aws ec2 disassociate-client-vpn-target-network [parameters]

# 授權管理
aws ec2 authorize-client-vpn-ingress [parameters]
aws ec2 revoke-client-vpn-ingress [parameters]

# 連接管理
aws ec2 describe-client-vpn-connections
aws ec2 terminate-client-vpn-connections [parameters]

# 證書管理
aws acm list-certificates
aws acm import-certificate [parameters]
aws acm delete-certificate --certificate-arn [arn]
```

### D. 緊急聯絡範本

```
=== VPN 緊急聯絡資訊 ===

AWS 資源:
端點 ID: cvpn-endpoint-xxxxxxxxxxxxx
區域: ap-northeast-1
VPC ID: vpc-xxxxxxxxxxxxx

緊急程序:
1. 立即聯繫 IT 管理員
2. 使用 revoke_member_access.sh 撤銷權限
3. 如無法聯繫，執行 employee_offboarding.sh
4. 記錄所有操作到事件日誌
```

---

**最後更新：** 2024年12月  
**文檔版本：** 2.0  
**適用工具版本：** 2.0  
**架構：** 模組化函式庫設計