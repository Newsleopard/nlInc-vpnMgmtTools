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

AWS Client VPN 管理工具套件是一個專為 macOS 設計的自動化解決方案，用於管理 AWS Client VPN 連接和團隊成員的訪問權限。本套件包含四個核心腳本：

### 工具組件
1. **aws_vpn_admin.sh** - 管理員主控台
2. **team_member_setup.sh** - 團隊成員設置工具
3. **revoke_member_access.sh** - 權限撤銷工具
4. **employee_offboarding.sh** - 離職處理系統

### 主要功能
- 自動建立和管理 AWS Client VPN 端點
- 為團隊成員生成和管理個人 VPN 證書
- 安全撤銷訪問權限
- 全面的離職安全處理
- 詳細的審計日誌和報告

---

## 系統要求

### 硬體要求
- macOS 10.15+ (Catalina 或更新版本)
- 至少 4GB RAM
- 2GB 可用磁碟空間
- 穩定的網路連接

### 軟體依賴
本套件會自動安裝以下工具，但您也可以手動預先安裝：

- **Homebrew** - macOS 套件管理器
- **AWS CLI** - AWS 命令列工具
- **jq** - JSON 處理工具
- **Easy-RSA** - 證書管理工具
- **OpenSSL** - 加密工具
- **curl** - 數據傳輸工具

### AWS 權限要求

#### 管理員權限
使用管理員腳本需要以下 AWS 權限：
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
                "iam:*", 
                "sts:GetCallerIdentity",
                "s3:ListAllMyBuckets",
                "cloudtrail:LookupEvents",
                "cloudtrail:DescribeTrails"
            ],
            "Resource": "*"
        },
        {
            "Sid": "SpecificHighPrivilegeScripts",
            "Effect": "Allow",
            "Action": [
                "iam:DeleteUser",
                "iam:DeleteAccessKey",
                "iam:RemoveUserFromGroup",
                "iam:DetachUserPolicy",
                "iam:DeleteLoginProfile",
                "acm:DeleteCertificate"
            ],
            "Resource": "*"
        }
    ]
}
```
**注意：** `employee_offboarding.sh` 腳本執行的操作範圍很廣，可能需要非常高的 AWS 權限。執行此腳本的 IAM 使用者/角色應被嚴格控制，並僅授予執行其任務所必需的最小權限。

#### 團隊成員權限
團隊成員 (`team_member_setup.sh` 的執行者) 需要以下最小權限：
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
                "acm:ListCertificates",
                "acm:AddTagsToCertificate"
            ],
            "Resource": "*"
        }
    ]
}
```

---

## 初始設置

### 1. 下載和準備

1. **下載工具套件**
   ```bash
   # 創建工作目錄
   mkdir -p ~/aws-vpn-tools
   cd ~/aws-vpn-tools
   
   # 下載所有腳本文件到此目錄
   ```

2. **設置執行權限**
   ```bash
   chmod +x *.sh
   ```

3. **驗證檔案完整性**
   ```bash
   ls -la *.sh
   ```
   應該看到以下檔案：
   - aws_vpn_admin.sh
   - team_member_setup.sh
   - revoke_member_access.sh
   - employee_offboarding.sh

### 2. AWS 配置

1. **獲取 AWS 訪問金鑰**
   - 登入 AWS 控制台
   - 前往 IAM > 用戶 > 安全憑證
   - 建立新的訪問金鑰

2. **配置 AWS CLI**
   ```bash
   aws configure
   ```
   輸入：
   - AWS Access Key ID
   - AWS Secret Access Key
   - Default region (例如：ap-northeast-1)
   - Default output format: json

3. **驗證配置**
   ```bash
   aws sts get-caller-identity
   ```

### 3. 網路準備

確保您有以下資訊：
- 目標 VPC ID
- 子網路 ID (私有子網路)
- VPC CIDR 範圍
- 計劃的 VPN CIDR 範圍 (不可與 VPC 衝突)

---

## 檔案系統影響

### 📁 執行後的本地端變更總覽

本工具套件會在您的本地系統創建多個檔案和目錄。了解這些變更有助於您：
- 管理敏感檔案的安全性
- 進行系統備份和恢復
- 在需要時完全移除工具

### 🔧 **aws_vpn_admin.sh 的檔案影響**

#### 創建的目錄結構：
```
專案根目錄/
├── .vpn_config                    # ⚠️ 主配置檔案 (敏感)
├── vpn_admin.log                  # 操作日誌
├── lib/                          # 函式庫目錄
│   └── *.log                     # 各種庫函式日誌
├── certificates/                  # 🔒 證書目錄 (高度敏感)
│   └── pki/
│       ├── ca.crt                # CA 證書
│       ├── private/
│       │   ├── ca.key            # 🔐 CA 私鑰 (極度敏感)
│       │   ├── server.key        # 🔐 伺服器私鑰
│       │   └── admin.key         # 🔐 管理員私鑰
│       └── issued/
│           ├── server.crt        # 伺服器證書
│           └── admin.crt         # 管理員證書
├── configs/                       # 管理員 VPN 配置
│   ├── admin-config-base.ovpn    # 基礎配置
│   └── admin-config.ovpn         # 🔒 完整配置 (含私鑰)
└── team-configs/                  # 團隊分發檔案
    ├── team-config-base.ovpn     # 基礎配置
    ├── ca.crt                    # CA 證書副本
    ├── ca.key                    # 🔐 CA 私鑰副本
    └── team-setup-info.txt       # 設置資訊
```

#### 自動安裝的軟體工具：
```bash
# 透過 Homebrew 安裝：
/opt/homebrew/bin/brew            # Homebrew (Apple Silicon)
/usr/local/bin/brew               # Homebrew (Intel Mac)
├── aws                          # AWS CLI
├── jq                           # JSON 處理器
└── easyrsa                      # 證書管理工具
```

### 👥 **team_member_setup.sh 的檔案影響**

#### AWS 配置變更：
```bash
~/.aws/
├── credentials                   # 🔐 AWS 認證資訊 (極度敏感)
└── config                       # AWS 配置設定
```

#### 本地檔案創建：
```
專案目錄/
├── .user_vpn_config             # ⚠️ 用戶配置 (敏感)
├── user_vpn_setup.log           # 用戶設置日誌
├── user-certificates/           # 🔒 用戶證書目錄 (高度敏感)
│   ├── ca.crt                  # CA 證書
│   ├── [username].crt          # 用戶證書
│   └── [username].key          # 🔐 用戶私鑰 (極度敏感)
└── vpn-config/                 # VPN 配置檔案
    ├── client-config-base.ovpn # 基礎配置
    └── [username]-config.ovpn  # 🔒 個人 VPN 配置 (含私鑰)
```

#### 系統應用程式安裝：
```bash
/Applications/AWS VPN Client.app  # AWS VPN 客戶端應用程式
~/Downloads/AWS_VPN_Client.pkg    # 安裝包檔案 (可刪除)
```

### 🚫 **revoke_member_access.sh 的檔案影響**

#### 創建的日誌檔案：
```
專案目錄/
└── revocation-logs/              # 撤銷日誌目錄
    ├── revocation.log           # 撤銷操作日誌
    └── [username]_revocation_[timestamp].log  # 📋 個別撤銷報告
```

**注意：** 此腳本僅創建日誌檔案，不安裝軟體或修改系統配置。

### 🏢 **employee_offboarding.sh 的檔案影響**

#### 創建的審計檔案：
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

### ⚙️ **系統設定變更**

#### Homebrew 環境變更：
```bash
# 首次安裝 Homebrew 時的變更：
/opt/homebrew/                   # Apple Silicon Mac 安裝位置
/usr/local/                      # Intel Mac 安裝位置

# Shell 配置檔案可能的變更：
~/.zshrc                        # 可能添加 Homebrew PATH
~/.bash_profile                 # 可能添加 Homebrew PATH
```

#### 網路配置影響：
```bash
# 安裝 AWS VPN Client 後：
# - 系統偏好設定中會出現 VPN 連接選項
# - 連接時會暫時修改網路路由表
# - 可能影響 DNS 設定 (連接期間)
```

### 🔒 **檔案權限和安全設定**

所有敏感檔案會自動設置適當權限：

```bash
# 配置檔案權限 (僅所有者可讀寫)
chmod 600 .vpn_config
chmod 600 .user_vpn_config
chmod 600 ~/.aws/credentials

# 證書和私鑰權限 (僅所有者可讀寫)
chmod 600 certificates/pki/private/*.key
chmod 600 user-certificates/*.key
chmod 600 *.ovpn                          # VPN 配置含私鑰

# 目錄權限 (僅所有者可存取)
chmod 700 certificates/
chmod 700 user-certificates/
chmod 700 revocation-logs/
chmod 700 offboarding-logs/

# 日誌檔案權限
chmod 600 *.log
chmod 600 *-logs/*.txt
```

### 📊 **磁碟空間使用估算**

```bash
證書檔案：              ~5MB
日誌檔案：              ~50MB (取決於使用量)
VPN 配置檔案：          ~1MB
軟體工具：
  ├── Homebrew：        ~500MB
  ├── AWS CLI：         ~200MB
  ├── jq：             ~5MB
  ├── Easy-RSA：       ~10MB
  └── AWS VPN Client：  ~100MB

總計估算：              ~871MB
```

### ⚠️ **重要安全提醒**

#### 🔐 極度敏感檔案 (需特別保護)：
- `certificates/pki/private/ca.key` - CA 私鑰
- `user-certificates/*.key` - 用戶私鑰
- `~/.aws/credentials` - AWS 認證資訊
- `*.ovpn` - 含私鑰的 VPN 配置檔案

#### 📋 敏感檔案 (需適當保護)：
- `.vpn_config` - VPN 端點配置
- `.user_vpn_config` - 用戶配置
- `certificates/pki/ca.crt` - CA 證書

#### 💡 安全建議：
1. **定期備份**：將敏感檔案備份到加密儲存裝置
2. **存取控制**：確保檔案權限設定正確 (已自動設定)
3. **定期輪換**：定期更新證書和 AWS 認證
4. **安全刪除**：移除檔案時使用安全刪除方法

---

## AWS 雲端資源影響

### ☁️ 執行後的AWS變更總覽

本工具套件會在您的AWS帳戶中創建、修改或刪除多種AWS資源。了解這些變更有助於您：
- 管理AWS成本和資源配額
- 進行安全審計和合規檢查
- 規劃災難恢復和備份策略
- 在需要時完全清理AWS資源

### 🔧 **aws_vpn_admin.sh 的AWS資源影響**

#### 創建的核心AWS服務：

##### 1. **AWS Certificate Manager (ACM) 證書**
```bash
# 伺服器證書
資源ARN: arn:aws:acm:region:account:certificate/[server-cert-id]
用途: VPN端點的伺服器身份驗證
標籤:
  - Name: "VPN-Server-Cert"
  - Purpose: "ClientVPN"
  - ManagedBy: "nlInc-vpnMgmtTools"

# 客戶端CA證書  
資源ARN: arn:aws:acm:region:account:certificate/[client-ca-cert-id]
用途: 客戶端證書驗證的根CA
標籤: 同上，Name為"VPN-Client-CA"
```

##### 2. **EC2 Client VPN 端點**
```bash
# 主要VPN端點
資源ID: cvpn-endpoint-[random-id]
配置:
  - ClientCidrBlock: 172.16.0.0/22 (預設，可自定)
  - ServerCertificateArn: [伺服器證書ARN]
  - 認證方式: 相互TLS證書認證
  - 分割通道: 啟用
  - DNS伺服器: 8.8.8.8, 8.8.4.4
  - 連接日誌: 啟用
標籤:
  - Name: [用戶指定的VPN名稱]
  - Purpose: "ProductionDebug"
```

##### 3. **CloudWatch Logs 日誌群組**
```bash
# VPN連接日誌
日誌群組名稱: /aws/clientvpn/[VPN_NAME]
保留政策: 永久保留 (除非手動設定)
用途: 記錄所有VPN連接活動
```

##### 4. **VPN 網路關聯**
```bash
# 每個關聯的子網路一個
關聯ID: cvpn-assoc-[random-id]
關聯目標:
  - 主要VPC子網路: subnet-[primary-id]
  - 額外VPC子網路: subnet-[additional-ids] (如果配置)
狀態: "associated"
```

##### 5. **VPN 授權規則**
```bash
# 主要VPC訪問授權
目標網路: [主要VPC的CIDR範圍]
授權對象: 所有群組 (AllowAllGroups)
狀態: "active"

# 額外VPC授權 (如果配置多VPC)
目標網路: [額外VPC的CIDR範圍]
授權對象: 所有群組
```

##### 6. **VPN 路由表**
```bash
# 預設網際網路路由
目標CIDR: 0.0.0.0/0
目標子網路: subnet-[primary-id]
來源: "add-route"

# VPC特定路由 (如果需要)
目標CIDR: [VPC_CIDR範圍]
目標子網路: subnet-[target-id]
```

### 👥 **team_member_setup.sh 的AWS資源影響**

#### 創建的AWS資源：

##### 1. **個人客戶端ACM證書**
```bash
# 每個團隊成員一個證書
資源ARN: arn:aws:acm:region:account:certificate/[user-cert-id]
證書內容:
  - 客戶端證書: [用戶的.crt檔案]
  - 私鑰: [用戶的.key檔案]
  - 證書鏈: [CA證書]
標籤:
  - Name: "VPN-Client-[USERNAME]"
  - Purpose: "ClientVPN"
  - User: "[USERNAME]"
  - CreatedBy: "[執行者]"
```

#### 查詢的AWS服務 (無修改)：
- **EC2 Client VPN**: 驗證端點存在和狀態
- **EC2 Client VPN**: 下載客戶端配置範本

### 🚫 **revoke_member_access.sh 的AWS資源影響**

#### 刪除/修改的AWS資源：

##### 1. **ACM證書操作**
```bash
# 優先操作：刪除證書
aws acm delete-certificate --certificate-arn [user-cert-arn]

# 備用操作：標記為已撤銷 (如果刪除失敗)
新增標籤:
  - Status: "Revoked"
  - RevokedBy: "[操作者用戶名]"
  - RevokedDate: "[ISO時間戳]"
  - Reason: "[撤銷原因]"
```

##### 2. **VPN連接管理**
```bash
# 強制斷開用戶連接
操作: terminate-client-vpn-connections
目標: 所有匹配用戶ID的活躍連接
效果: 立即斷開，用戶無法重新連接
```

##### 3. **IAM用戶處理** (可選，需要權限)
```bash
# 訪問密鑰管理
1. 停用所有訪問密鑰 (Status: Inactive)
2. 刪除所有訪問密鑰

# 政策和權限清理
1. 分離所有附加的管理政策
2. 刪除所有內嵌政策
3. 從所有IAM群組移除用戶

# 帳戶清理
1. 刪除登入設定檔
2. 停用所有MFA設備
3. 最終刪除IAM用戶 (如果選擇)
```

### 🏢 **employee_offboarding.sh 的AWS資源影響**

#### 最廣泛的AWS操作 (高權限要求)：

##### 1. **緊急安全措施**
```bash
# 全域VPN連接掃描和終止
操作範圍: 所有Client VPN端點
搜索條件: 包含員工ID的連接
執行動作: 立即終止所有匹配的連接
影響: 可能影響多個VPN端點的連接
```

##### 2. **全面證書撤銷**
```bash
# 批量證書搜索和處理
搜索方式:
  - 域名匹配 (DomainName包含員工信息)
  - 標籤匹配 (Name/User標籤包含員工信息)
處理動作:
  - 刪除所有匹配的ACM證書
  - 為無法刪除的證書添加撤銷標記
```

##### 3. **完整IAM清理**
```bash
# 徹底的身份和訪問管理清理
立即操作:
  - 停用所有訪問密鑰
  - 分離所有政策 (管理和內嵌)
  - 從所有IAM群組移除
  - 刪除登入設定檔和MFA設備
最終操作:
  - 完全刪除IAM用戶帳戶
```

##### 4. **資源審計和掃描**
```bash
# S3存儲桶審計
掃描範圍: 帳戶內所有S3存儲桶
搜索條件: 存儲桶名稱包含員工信息
報告內容: 潛在的員工相關資源

# EC2實例審計
搜索條件: Owner標籤匹配員工信息
狀態檢查: running, stopped實例
報告內容: 需要人工檢查的實例清單

# 殘留證書檢查
掃描範圍: 當前區域的所有ACM證書
檢查內容: 域名和標籤中的員工信息
```

##### 5. **審計日誌收集**
```bash
# CloudTrail事件查詢
時間範圍: 最近30天
過濾條件: 員工相關的API調用
輸出格式: JSON格式的事件記錄

# VPN連接日誌分析
數據來源: 所有VPN端點的CloudWatch日誌
分析內容: 員工的連接模式和時間
統計資料: 連接次數、持續時間、時間分佈
```

---

## 💰 AWS成本影響分析

### 新增的計費資源：

#### 1. **Client VPN端點費用**
```bash
計費結構:
├── 端點費用: $0.10/小時 (24/7運行)
├── 連接費用: $0.05/小時/每個活躍連接
└── 數據傳輸: 標準AWS出站數據傳輸費率

月費用估算 (單一端點):
├── 基礎端點費用: ~$72/月
├── 10個用戶連接: ~$360/月 (假設每天8小時使用)
├── 數據傳輸費用: 依實際使用量計算
└── 總計估算: $432-500/月 (不含數據傳輸)
```

#### 2. **CloudWatch Logs費用**
```bash
計費項目:
├── 日誌攝取: $0.50/GB
├── 日誌儲存: $0.03/GB/月  
└── 日誌查詢: $0.005/GB掃描的數據

月費用估算:
├── 每用戶日誌量: ~100MB/月
├── 10個用戶: ~$0.50攝取 + $0.03儲存
└── 總計估算: ~$1-5/月
```

#### 3. **ACM證書費用**
```bash
證書類型和費用:
├── 公有SSL/TLS證書: 免費
├── 私有證書 (如使用ACM Private CA): $400/月起
└── 自簽證書 (本工具使用): 免費

總計: $0 (使用自簽證書)
```

#### 4. **總體月費用估算**
```bash
小型部署 (5用戶):
├── VPN端點和連接: ~$250/月
├── CloudWatch日誌: ~$2/月
├── 證書費用: $0
└── 總計: ~$252/月

中型部署 (20用戶):  
├── VPN端點和連接: ~$900/月
├── CloudWatch日誌: ~$8/月
├── 證書費用: $0
└── 總計: ~$908/月
```

### 成本優化建議：
- 定期檢查未使用的VPN連接
- 設定CloudWatch日誌的保留期限
- 監控數據傳輸使用量
- 考慮在非工作時間暫停VPN端點 (如果適用)

---

## 🔐 AWS安全和合規考量

### 高風險AWS操作清單：

#### 1. **IAM權限要求**
```json
{
  "高風險操作": {
    "iam:DeleteUser": "完全刪除IAM用戶",
    "iam:DeleteAccessKey": "刪除用戶訪問金鑰", 
    "acm:DeleteCertificate": "刪除SSL/TLS證書",
    "ec2:TerminateClientVpnConnections": "強制斷開VPN連接",
    "logs:DeleteLogGroup": "刪除日誌群組"
  },
  "安全建議": [
    "使用最小權限原則",
    "啟用多因素認證 (MFA)",
    "定期輪換訪問金鑰",
    "監控AWS CloudTrail日誌"
  ]
}
```

#### 2. **資源標籤治理**
```bash
# 所有創建的資源都包含一致的標籤
標準標籤集:
├── Purpose: "ClientVPN"
├── ManagedBy: "nlInc-vpnMgmtTools"
├── Environment: "Production" | "Staging" | "Development"
├── Owner: "[創建者IAM身份]"
├── CreatedDate: "[ISO時間戳]"
└── Project: "[專案代碼]"

好處:
├── 成本分配和追蹤
├── 資源生命週期管理
├── 安全審計和合規
└── 自動化清理政策
```

#### 3. **審計追蹤**
```bash
# CloudTrail記錄的關鍵事件
VPN管理事件:
├── CreateClientVpnEndpoint
├── DeleteClientVpnEndpoint
├── AssociateClientVpnTargetNetwork
├── DisassociateClientVpnTargetNetwork
├── AuthorizeClientVpnIngress
└── RevokeClientVpnIngress

證書管理事件:
├── ImportCertificate
├── DeleteCertificate
├── AddTagsToCertificate
└── ListCertificates

IAM管理事件:
├── DeleteUser
├── DeleteAccessKey
├── DetachUserPolicy
└── RemoveUserFromGroup
```

#### 4. **合規考量**
```bash
# 數據保護法規
GDPR合規:
├── 用戶數據的處理記錄
├── 數據刪除權 (被遺忘權)
├── 數據可攜性
└── 違規通知義務

SOC 2合規:
├── 訪問控制 (證書管理)
├── 監控和日誌記錄
├── 變更管理流程
└── 事件響應程序

ISO 27001合規:
├── 資訊安全管理
├── 風險評估和管理
├── 訪問權限管理
└── 持續改進
```

---

## 🗺️ AWS區域和可用性影響

### 區域綁定資源：

#### 1. **區域特定服務**
```bash
# 以下資源與特定AWS區域綁定
必須在同一區域:
├── Client VPN端點
├── ACM證書
├── CloudWatch日誌群組
├── VPC和子網路
├── 目標EC2實例
└── 安全群組

跨區域限制:
├── 證書無法跨區域使用
├── VPN端點無法關聯其他區域的VPC
├── 日誌分散在不同區域
└── 災難恢復需要每個區域獨立部署
```

#### 2. **多區域部署策略**
```bash
# 建議的多區域架構
主要區域 (ap-northeast-1):
├── 主要VPN端點
├── 生產環境VPC關聯
├── 主要用戶群組
└── 完整證書管理

災難恢復區域 (ap-southeast-1):
├── 備用VPN端點 (預先配置)
├── 相同的證書備份
├── 網路配置鏡像
└── 自動化故障轉移腳本

好處:
├── 提高可用性和容錯性
├── 更好的使用者體驗 (延遲優化)
├── 合規要求 (數據本地化)
└── 負載分散
```

---

## 🧹 AWS資源完整清理指南

### 清理AWS資源的順序：

#### 1. **準備階段**
```bash
# 記錄現有資源
aws ec2 describe-client-vpn-endpoints --region [region]
aws acm list-certificates --region [region]
aws logs describe-log-groups --log-group-name-prefix "/aws/clientvpn"

# 導出重要配置 (備份用)
aws ec2 export-client-vpn-client-configuration \
  --client-vpn-endpoint-id [endpoint-id] \
  --region [region] > backup-config.ovpn
```

#### 2. **斷開所有連接**
```bash
# 優雅斷開所有VPN連接
aws ec2 describe-client-vpn-connections \
  --client-vpn-endpoint-id [endpoint-id] \
  --region [region]

aws ec2 terminate-client-vpn-connections \
  --client-vpn-endpoint-id [endpoint-id] \
  --connection-ids [connection-id-list] \
  --region [region]
```

#### 3. **移除授權和路由**
```bash
# 刪除所有授權規則
aws ec2 describe-client-vpn-authorization-rules \
  --client-vpn-endpoint-id [endpoint-id] --region [region]

aws ec2 revoke-client-vpn-ingress \
  --client-vpn-endpoint-id [endpoint-id] \
  --target-network-cidr [cidr] \
  --revoke-all-groups --region [region]

# 刪除所有路由
aws ec2 describe-client-vpn-routes \
  --client-vpn-endpoint-id [endpoint-id] --region [region]

aws ec2 delete-client-vpn-route \
  --client-vpn-endpoint-id [endpoint-id] \
  --destination-cidr-block [cidr] \
  --target-vpc-subnet-id [subnet-id] \
  --region [region]
```

#### 4. **解除網路關聯**
```bash
# 解除所有子網路關聯
aws ec2 describe-client-vpn-target-networks \
  --client-vpn-endpoint-id [endpoint-id] --region [region]

aws ec2 disassociate-client-vpn-target-network \
  --client-vpn-endpoint-id [endpoint-id] \
  --association-id [association-id] \
  --region [region]

# 等待解除關聯完成
aws ec2 wait client-vpn-target-network-disassociated \
  --client-vpn-endpoint-id [endpoint-id] \
  --association-ids [association-id] \
  --region [region]
```

#### 5. **刪除VPN端點**
```bash
# 刪除VPN端點
aws ec2 delete-client-vpn-endpoint \
  --client-vpn-endpoint-id [endpoint-id] \
  --region [region]

# 等待刪除完成
aws ec2 wait client-vpn-endpoint-deleted \
  --client-vpn-endpoint-ids [endpoint-id] \
  --region [region]
```

#### 6. **清理證書和日誌**
```bash
# 刪除ACM證書
aws acm delete-certificate \
  --certificate-arn [certificate-arn] \
  --region [region]

# 刪除CloudWatch日誌群組
aws logs delete-log-group \
  --log-group-name "/aws/clientvpn/[vpn-name]" \
  --region [region]
```

#### 7. **驗證清理完整性**
```bash
# 確認所有資源已清理
aws ec2 describe-client-vpn-endpoints --region [region]
aws acm list-certificates --region [region] | grep VPN
aws logs describe-log-groups --log-group-name-prefix "/aws/clientvpn"

# 檢查相關費用
aws ce get-cost-and-usage \
  --time-period Start=2024-01-01,End=2024-01-31 \
  --granularity MONTHLY \
  --metrics BlendedCost \
  --group-by Type=DIMENSION,Key=SERVICE
```

---

## 📊 AWS資源監控和警報

### 建議的CloudWatch警報：

#### 1. **成本監控**
```bash
# VPN端點成本警報
aws cloudwatch put-metric-alarm \
  --alarm-name "VPN-Cost-Alert" \
  --alarm-description "VPN monthly cost exceeds threshold" \
  --metric-name EstimatedCharges \
  --namespace AWS/Billing \
  --statistic Maximum \
  --period 86400 \
  --threshold 500 \
  --comparison-operator GreaterThanThreshold
```

#### 2. **連接監控**
```bash
# 異常連接數警報
aws cloudwatch put-metric-alarm \
  --alarm-name "VPN-Connection-Spike" \
  --alarm-description "Unusual number of VPN connections" \
  --metric-name ActiveConnections \
  --namespace AWS/ClientVPN \
  --statistic Sum \
  --period 300 \
  --threshold 50 \
  --comparison-operator GreaterThanThreshold
```

#### 3. **安全監控**
```bash
# 證書即將過期警報
aws cloudwatch put-metric-alarm \
  --alarm-name "Certificate-Expiry-Warning" \
  --alarm-description "SSL certificate expiring soon" \
  --metric-name DaysToExpiry \
  --namespace AWS/CertificateManager \
  --statistic Minimum \
  --period 86400 \
  --threshold 30 \
  --comparison-operator LessThanThreshold
```

---

## 工具介紹

### aws_vpn_admin.sh - 管理員主控台

**用途：** VPN 基礎設施的建立、管理和維護

**主要功能：**
- 建立新的 VPN 端點
- 管理現有端點設定
- 查看連接日誌
- 匯出團隊設定
- 系統健康檢查
- 刪除 VPN 端點

**適用對象：** IT 管理員、DevOps 工程師

### team_member_setup.sh - 團隊成員設置工具

**用途：** 為新團隊成員設置 VPN 訪問

**主要功能：**
- 生成個人客戶端證書
- 導入證書到 AWS ACM
- 下載和配置 VPN 客戶端
- 建立個人配置檔案

**適用對象：** 新加入的團隊成員
**作業系統相容性：** 此腳本中的 AWS VPN Client 軟體下載和安裝步驟目前主要針對 macOS (.pkg)。其他作業系統的使用者可能需要手動下載並安裝適用其系統的 AWS VPN Client，或自行調整腳本中的相關安裝指令。

### revoke_member_access.sh - 權限撤銷工具

**用途：** 撤銷特定成員的 VPN 訪問權限

**主要功能：**
- 搜索和撤銷用戶證書
- 斷開活躍連接
- 處理 IAM 權限
- 生成撤銷報告

**適用對象：** IT 管理員

### employee_offboarding.sh - 離職處理系統

**用途：** 全面處理離職員工的安全清理

**主要功能：**
- 緊急安全措施
- 全面權限撤銷
- 訪問日誌審計
- 安全報告生成
- 離職檢查清單

**適用對象：** HR、IT 管理員、安全團隊

---

## 詳細使用指南

### 管理員首次設置

#### 步驟 1：建立 VPN 端點

1. **執行管理員腳本**
   ```bash
   ./aws_vpn_admin.sh
   ```

2. **選擇選項 1：建立新的 VPN 端點**

3. **按照提示輸入資訊：**
   - 確認 AWS 配置
   - 選擇目標 VPC
   - 選擇關聯的子網路
   - 設定 VPN CIDR 範圍
   - 命名 VPN 端點

4. **等待建立完成**
   - 系統會自動生成證書
   - 創建 VPN 端點
   - 配置網路關聯
   - 設置授權規則

5. **記錄重要資訊**
   - VPN 端點 ID
   - 管理員配置檔案位置
   - 團隊設定檔案位置

#### 步驟 2：測試管理員連接

1. **安裝 AWS VPN 客戶端**
   - 腳本會自動下載安裝

2. **導入管理員配置**
   - 開啟 AWS VPN 客戶端
   - 添加配置檔案：`configs/admin-config.ovpn`
   - 設定檔名稱：Admin VPN

3. **測試連接**
   - 連接到 VPN
   - 測試 ping 私有資源
   - 確認連接日誌

#### 步驟 3：準備團隊設定

1. **匯出團隊設定檔**
   - 選擇選項 6：匯出團隊成員設定檔

2. **分發給團隊成員**
   - team_member_setup.sh
   - ca.crt 文件
   - VPN 端點 ID

### 團隊成員設置流程

#### 為新成員設置 VPN 訪問

1. **提供必要文件**
   ```bash
   # 團隊成員應該收到：
   # - team_member_setup.sh
   # - ca.crt
   # - VPN 端點 ID
   ```

2. **執行設置腳本**
   ```bash
   ./team_member_setup.sh
   ```

3. **按照提示完成設置**
   - 輸入 AWS 認證資訊
   - 輸入 VPN 端點 ID
   - 設定用戶名
   - 生成個人證書

4. **測試連接**
   - 使用 AWS VPN 客戶端
   - 導入個人配置檔案
   - 測試連接到生產環境

### 權限撤銷流程

#### 撤銷特定成員的訪問權限

1. **執行撤銷腳本**
   ```bash
   ./revoke_member_access.sh
   ```

2. **提供用戶資訊**
   - 用戶名
   - VPN 端點 ID
   - 撤銷原因

3. **確認撤銷操作**
   - 檢查要撤銷的證書
   - 輸入 'REVOKE' 確認

4. **驗證撤銷結果**
   - 檢查撤銷報告
   - 確認用戶無法連接

### 離職處理流程

#### 全面處理離職員工

1. **準備離職資訊**
   - 員工姓名和 ID
   - 離職日期和類型
   - 風險等級評估

2. **執行離職腳本**
   ```bash
   ./employee_offboarding.sh
   ```

3. **按照十步驟流程**
   - 系統檢查
   - 資訊收集
   - 緊急措施（如需要）
   - 資源分析
   - VPN 撤銷
   - IAM 清理
   - 日誌審計
   - 殘留檢查
   - 報告生成
   - 最終確認

4. **完成手動檢查清單**
   - 使用生成的檢查清單
   - 完成所有離職項目
   - 保留文檔用於審計

---

## 故障排除

### 常見問題和解決方案

#### 1. AWS 權限錯誤

**問題：** `AccessDenied` 錯誤
```
An error occurred (AccessDenied) when calling the DescribeClientVpnEndpoints operation
```

**解決方案：**
1. 檢查 AWS 認證配置
   ```bash
   aws sts get-caller-identity
   ```

2. 確認 IAM 權限
   - 檢查用戶政策
   - 確認資源權限

3. 檢查區域設定
   ```bash
   aws configure get region
   ```

#### 2. 證書生成失敗

**問題：** Easy-RSA 證書生成錯誤

**解決方案：**
1. 檢查 Easy-RSA 安裝
   ```bash
   which easyrsa
   easyrsa version
   ```

2. 清理並重新初始化
   ```bash
   rm -rf pki
   easyrsa init-pki
   ```

3. 檢查權限
   ```bash
   chmod 755 certificates/
   ```

#### 3. VPN 連接失敗

**問題：** 無法連接到 VPN

**解決方案：**
1. 檢查端點狀態
   ```bash
   aws ec2 describe-client-vpn-endpoints --client-vpn-endpoint-ids cvpn-xxxxxx
   ```

2. 驗證配置檔案
   - 檢查證書是否正確嵌入
   - 確認端點 URL 正確

3. 檢查網路連接
   - 測試到 443 端口的連接
   - 檢查防火牆設定

#### 4. 腳本執行錯誤

**問題：** 腳本中途停止執行

**解決方案：**
1. 檢查腳本權限
   ```bash
   chmod +x *.sh
   ```

2. 查看錯誤日誌
   ```bash
   tail -f vpn_admin.log
   ```

3. 單步驟執行
   - 使用 bash -x 調試
   ```bash
   bash -x aws_vpn_admin.sh
   ```

### 日誌文件位置

- **管理員日誌：** `vpn_admin.log`
- **團隊成員日誌：** `user_vpn_setup.log`
- **撤銷日誌：** `revocation-logs/revocation.log`
- **離職日誌：** `offboarding-logs/offboarding.log`

---

## 安全最佳實踐

### 證書管理

1. **證書輪換**
   - 定期更新 CA 證書 (每年)
   - 輪換客戶端證書 (每 6 個月)
   - 立即撤銷洩露的證書

2. **安全儲存**
   - 加密儲存私鑰文件
   - 限制 CA 私鑰訪問
   - 使用安全的備份策略
   - **用戶端私鑰安全：** `team_member_setup.sh` 會產生用戶端憑證，其中包括一個私鑰檔案 (`.key`)。此私鑰會嵌入到 `.ovpn` 設定檔中以便分發。使用者應被告知這些 `.ovpn` 檔案和獨立的 `.key` 檔案（如果產生）的敏感性。建議使用者在成功設定 VPN 連線後，妥善保管這些檔案，並考慮從本地電腦上刪除原始的 `.key` 檔案副本（如果組織策略允許且已有安全備份），以降低洩漏風險。

3. **檔案權限管理**
   - 系統自動設置敏感檔案權限為 `600` (僅所有者可讀寫)
   - 證書目錄權限設為 `700` (僅所有者可存取)
   - 定期檢查檔案權限是否被意外更改
   ```bash
   # 檢查敏感檔案權限
   find . -name "*.key" -exec ls -la {} \;
   find . -name "*.ovpn" -exec ls -la {} \;
   ```

### 訪問控制

1. **最小權限原則**
   - 僅授予必要的 AWS 權限
   - 定期審查用戶權限
   - 使用 IAM 角色和群組

2. **網路分段**
   - 限制 VPN 可訪問的資源
   - 使用安全組控制流量
   - 實施網路監控

### 敏感檔案備份策略

1. **加密備份**
   ```bash
   # 建議的備份腳本範例
   tar -czf vpn_backup_$(date +%Y%m%d).tar.gz \
       .vpn_config certificates/ configs/ \
       --exclude="*.log"
   
   # 加密備份檔案
   gpg --symmetric --cipher-algo AES256 vpn_backup_$(date +%Y%m%d).tar.gz
   ```

2. **離線儲存**
   - 將加密備份儲存到離線媒體
   - 定期測試備份恢復程序
   - 在安全地點保存備份

### 監控和審計

1. **連接監控**
   - 啟用 VPN 連接日誌
   - 設置異常連接警報
   - 定期檢查連接模式

2. **審計追蹤**
   - 保留所有操作日誌
   - 定期審查權限變更
   - 建立事件回應程序

3. **檔案完整性監控**
   ```bash
   # 建議定期檢查重要檔案的完整性
   find . -name "*.key" -o -name "*.crt" -o -name ".vpn_config" | \
   xargs shasum -a 256 > file_checksums.txt
   ```

### 應急響應

1. **安全事件**
   - 立即斷開可疑連接
   - 撤銷相關證書
   - 通知安全團隊

2. **洩露響應**
   - 評估洩露範圍
   - 重新生成受影響證書
   - 更新訪問控制

---

## 常見問題

### Q: 可以同時建立多個 VPN 端點嗎？
A: 是的，可以為不同環境或團隊建立多個端點。每個端點使用不同的 CIDR 範圍和證書。

### Q: 如何處理證書過期？
A: 證書過期前 30 天會在日誌中警告。需要重新生成證書並分發給用戶。

### Q: 可以限制特定用戶只能訪問特定資源嗎？
A: 可以。通過 VPN 端點的授權規則和安全組來控制訪問範圍。

### Q: 如何備份 VPN 配置？
A: 備份以下文件：
- 所有證書文件
- VPN 端點配置
- 用戶清單
- 配置文件

### Q: 支援多因素認證嗎？
A: 目前使用證書認證。可以在 AWS 端配置 SAML 或其他認證方式。

### Q: 如何監控 VPN 使用量？
A: 通過 CloudWatch 監控連接數量、流量和連接時間。

### Q: 工具會佔用多少磁碟空間？
A: 約 871MB，包括：
- 證書和配置檔案：~56MB
- 軟體工具：~815MB (Homebrew、AWS CLI、VPN Client 等)

### Q: 如何確保檔案安全？
A: 工具會自動設置適當的檔案權限，所有敏感檔案僅所有者可存取。建議定期備份到加密儲存裝置。

---

## 維護和監控

### 定期維護任務

#### 每週任務
- [ ] 檢查 VPN 端點健康狀態
- [ ] 審查連接日誌
- [ ] 驗證備份完整性
- [ ] 檢查敏感檔案權限

#### 每月任務
- [ ] 更新團隊成員清單
- [ ] 檢查證書過期狀態
- [ ] 審查安全組規則
- [ ] 測試應急響應程序
- [ ] 清理過期日誌檔案

#### 每季任務
- [ ] 全面權限審計
- [ ] 更新安全政策
- [ ] 效能優化評估
- [ ] 災難恢復測試
- [ ] 檔案完整性檢查

### 監控指標

1. **連接指標**
   - 同時連接數
   - 連接成功率
   - 平均連接時間

2. **安全指標**
   - 失敗登入次數
   - 異常連接模式
   - 證書使用狀況

3. **系統指標**
   - 磁碟空間使用
   - 日誌檔案大小
   - 備份狀態

### 自動化監控設置

```bash
# 設置每日健康檢查
crontab -e

# 添加以下行：
0 9 * * * /path/to/aws_vpn_admin.sh health-check
0 18 * * * /path/to/check_certificate_expiry.sh
0 2 * * 0 /path/to/backup_vpn_configs.sh  # 每週備份
```

---

## 完整移除指南

如果您需要完全移除此工具套件及其所有影響，請按照以下步驟：

### 1. 停止所有 VPN 連接
```bash
# 在 AWS VPN Client 中斷開所有連接
# 或使用命令列 (如果支援)
sudo pkill -f "AWS VPN Client"
```

### 2. 刪除專案檔案和資料
```bash
# 切換到專案目錄的上層
cd /path/to/parent/directory

# 安全刪除整個專案目錄 (包含所有敏感檔案)
rm -rf aws-vpn-tools/

# 或使用安全刪除 (如果可用)
srm -rf aws-vpn-tools/  # macOS
```

### 3. 移除 AWS 配置 (謹慎操作)
```bash
# ⚠️ 注意：這會刪除所有 AWS CLI 配置
# 如果您使用 AWS CLI 進行其他用途，請先備份

# 檢查現有配置
aws configure list-profiles

# 僅刪除特定 profile (推薦)
aws configure remove-profile [profile_name]

# 或完全移除 AWS 配置 (謹慎)
rm -rf ~/.aws/
```

### 4. 移除已安裝的應用程式
```bash
# 移除 AWS VPN Client
sudo rm -rf "/Applications/AWS VPN Client.app"

# 清理 Downloads 中的安裝檔案
rm -f ~/Downloads/AWS_VPN_Client.pkg
```

### 5. 移除 Homebrew 安裝的工具 (可選)
```bash
# 如果這些工具僅為此專案安裝，可以移除：
brew uninstall awscli
brew uninstall jq
brew uninstall easy-rsa

# 檢查其他依賴的應用程式
brew uses awscli
brew uses jq
```

### 6. 清理系統設定
```bash
# 檢查並清理 shell 配置檔案中的 PATH 修改
# (Homebrew 安裝時可能添加的)
nano ~/.zshrc      # 或 ~/.bash_profile
# 移除 Homebrew 相關的 PATH 設定 (如果不再需要)

# 重新載入 shell 配置
source ~/.zshrc
```

### 7. 清理網路設定
```bash
# VPN Client 移除後，網路設定通常會自動清理
# 但可以檢查是否有殘留的 VPN 介面或路由
ifconfig | grep -E "(utun|tun)"
netstat -rn | grep -E "(utun|tun)"
```

### 8. AWS 雲端資源清理
```bash
# ⚠️ 重要：同時清理 AWS 上的相關資源
# 使用 aws_vpn_admin.sh 的刪除功能，或手動清理：

# 刪除 Client VPN 端點
aws ec2 delete-client-vpn-endpoint --client-vpn-endpoint-id cvpn-xxxxxx

# 刪除 ACM 證書
aws acm delete-certificate --certificate-arn arn:aws:acm:...

# 刪除 CloudWatch 日誌群組
aws logs delete-log-group --log-group-name /aws/clientvpn/...
```

### 9. 驗證移除完整性
```bash
# 檢查是否還有殘留檔案
find / -name "*vpn*" -type f 2>/dev/null | grep -v "/System/"
find / -name "*aws-vpn*" 2>/dev/null

# 檢查是否還有相關程序
ps aux | grep -i vpn
ps aux | grep -i aws

# 檢查網路連接
lsof -i | grep -i vpn
```

### 10. 安全確認
```bash
# 確認敏感資料已安全移除
# (這些檔案應該在步驟 2 中已被刪除)
ls -la ~/.aws/ 2>/dev/null || echo "AWS 配置已移除"
ls -la /Applications/ | grep -i vpn || echo "VPN 應用程式已移除"
```

### 完整移除檢查清單
- [ ] 斷開所有 VPN 連接
- [ ] 刪除專案目錄和所有檔案
- [ ] 移除或重新配置 AWS CLI 設定
- [ ] 移除 AWS VPN Client 應用程式
- [ ] 移除不需要的 Homebrew 工具
- [ ] 清理 shell 配置檔案
- [ ] 檢查網路設定
- [ ] 清理 AWS 雲端資源
- [ ] 驗證沒有殘留檔案或程序
- [ ] 確認敏感資料已安全移除

**注意：** 完整移除後，如果需要重新使用 VPN 功能，您需要重新執行完整的設置程序。

---

## 附錄

### A. 配置文件範例

#### VPN 客戶端配置文件結構
```
client
dev tun
proto udp
remote cvpn-endpoint-xxx.prod.clientvpn.ap-northeast-1.amazonaws.com 443
remote-random-hostname
resolv-retry infinite
nobind
persist-key
persist-tun
remote-cert-tls server
cipher AES-256-GCM
verb 3
reneg-sec 0

<cert>
-----BEGIN CERTIFICATE-----
[證書內容]
-----END CERTIFICATE-----
</cert>

<key>
-----BEGIN PRIVATE KEY-----
[私鑰內容]
-----END PRIVATE KEY-----
</key>
```

### B. AWS CLI 命令參考

#### 常用 VPN 管理命令
```bash
# 列出所有 VPN 端點
aws ec2 describe-client-vpn-endpoints

# 查看特定端點詳情
aws ec2 describe-client-vpn-endpoints --client-vpn-endpoint-ids cvpn-xxxxx

# 查看當前連接
aws ec2 describe-client-vpn-connections --client-vpn-endpoint-id cvpn-xxxxx

# 下載客戶端配置
aws ec2 export-client-vpn-client-configuration --client-vpn-endpoint-id cvpn-xxxxx

# 查看授權規則
aws ec2 describe-client-vpn-authorization-rules --client-vpn-endpoint-id cvpn-xxxxx

# 查看路由
aws ec2 describe-client-vpn-routes --client-vpn-endpoint-id cvpn-xxxxx
```

### C. 緊急聯絡資訊範本

```
=== VPN 緊急聯絡資訊 ===

IT 管理員: [姓名] - [電話] - [郵件]
安全團隊: [姓名] - [電話] - [郵件]
AWS 支援: [案例 ID] - [支援等級]

緊急程序:
1. 立即聯繫 IT 管理員
2. 如無法聯繫，聯繫安全團隊
3. 記錄事件詳情
4. 執行應急響應程序
```

### D. 故障排除檢查清單

```
□ 檢查 AWS 認證配置
□ 驗證 IAM 權限
□ 確認網路連接
□ 檢查端點狀態
□ 驗證證書有效性
□ 查看連接日誌
□ 測試 DNS 解析
□ 確認安全組規則
□ 檢查路由表
□ 驗證客戶端配置
□ 檢查檔案權限
□ 驗證磁碟空間
```

### E. 檔案權限快速檢查腳本

```bash
#!/bin/bash
# 檔案權限檢查腳本

echo "=== VPN 工具檔案權限檢查 ==="

# 檢查配置檔案
for file in .vpn_config .user_vpn_config; do
    if [ -f "$file" ]; then
        perms=$(stat -f "%Lp" "$file")
        if [ "$perms" = "600" ]; then
            echo "✓ $file: 權限正確 ($perms)"
        else
            echo "✗ $file: 權限不安全 ($perms), 應為 600"
        fi
    fi
done

# 檢查證書檔案
find . -name "*.key" -o -name "*.crt" | while read file; do
    perms=$(stat -f "%Lp" "$file")
    if [ "$perms" = "600" ]; then
        echo "✓ $file: 權限正確 ($perms)"
    else
        echo "✗ $file: 權限不安全 ($perms), 應為 600"
    fi
done

# 檢查敏感目錄
for dir in certificates user-certificates; do
    if [ -d "$dir" ]; then
        perms=$(stat -f "%Lp" "$dir")
        if [ "$perms" = "700" ]; then
            echo "✓ $dir/: 權限正確 ($perms)"
        else
            echo "✗ $dir/: 權限不安全 ($perms), 應為 700"
        fi
    fi
done
```

---

## 版本歷史

- **v1.0** (2024-05) - 初始版本發布
  - 基本 VPN 管理功能
  - 團隊成員設置
  - 權限撤銷
  - 離職處理
  - 完整的檔案系統影響說明

---

**最後更新：** 2024年5月
**文檔版本：** 1.1
**適用工具版本：** 1.0