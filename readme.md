# AWS Client VPN 管理工具套件完整使用說明書

## 目錄
1. [概述](#概述)
2. [系統要求](#系統要求)
3. [初始設置](#初始設置)
4. [工具介紹](#工具介紹)
5. [詳細使用指南](#詳細使用指南)
6. [故障排除](#故障排除)
7. [安全最佳實踐](#安全最佳實踐)
8. [常見問題](#常見問題)
9. [維護和監控](#維護和監控)
10. [附錄](#附錄)

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
                "sts:GetCallerIdentity"
            ],
            "Resource": "*"
        }
    ]
}
```

#### 團隊成員權限
團隊成員需要以下最小權限：
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

### 訪問控制

1. **最小權限原則**
   - 僅授予必要的 AWS 權限
   - 定期審查用戶權限
   - 使用 IAM 角色和群組

2. **網路分段**
   - 限制 VPN 可訪問的資源
   - 使用安全組控制流量
   - 實施網路監控

### 監控和審計

1. **連接監控**
   - 啟用 VPN 連接日誌
   - 設置異常連接警報
   - 定期檢查連接模式

2. **審計追蹤**
   - 保留所有操作日誌
   - 定期審查權限變更
   - 建立事件回應程序

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

---

## 維護和監控

### 定期維護任務

#### 每週任務
- [ ] 檢查 VPN 端點健康狀態
- [ ] 審查連接日誌
- [ ] 驗證備份完整性

#### 每月任務
- [ ] 更新團隊成員清單
- [ ] 檢查證書過期狀態
- [ ] 審查安全組規則
- [ ] 測試應急響應程序

#### 每季任務
- [ ] 全面權限審計
- [ ] 更新安全政策
- [ ] 效能優化評估
- [ ] 災難恢復測試

### 監控指標

1. **連接指標**
   - 同時連接數
   - 連接成功率
   - 平均連接時間

2. **安全指標**
   - 失敗登入次數
   - 異常連接模式
   - 證書使用狀況

3. **效能指標**
   - 網路延遲
   - 頻寬使用
   - 端點可用性

### 自動化監控設置

```bash
# 設置每日健康檢查
crontab -e

# 添加以下行：
0 9 * * * /path/to/aws_vpn_admin.sh health-check
0 18 * * * /path/to/check_certificate_expiry.sh
```

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
```

---

## 版本歷史

- **v1.0** (2024-05) - 初始版本發布
  - 基本 VPN 管理功能
  - 團隊成員設置
  - 權限撤銷
  - 離職處理

---

## 支援和反饋

如有問題或建議，請聯繫：
- IT 支援團隊：it-support@company.com
- 文檔反饋：docs@company.com

**最後更新：** 2024年5月
**文檔版本：** 1.0
**適用工具版本：** 1.0