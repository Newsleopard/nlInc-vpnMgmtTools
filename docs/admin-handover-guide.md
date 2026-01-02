# VPN 管理員交接指南

本指南提供 VPN 系統管理員之間的完整交接流程，確保安全、順暢的權限轉移。

## 🎯 適用情況

- 管理員職務異動
- 團隊成員離職
- 系統維護權限轉移
- 緊急情況下的權限委派

## 📋 交接前準備清單

### 既有管理員準備事項

- [ ] 確認專案目錄完整且最新
- [ ] 驗證所有憑證檔案存在且有效
- [ ] 確認 AWS 設定檔案正確配置
- [ ] 準備新任管理員的聯絡方式（電話號碼）
- [ ] 清理不必要的暫存檔案和日誌

### 新任管理員準備事項

- [ ] 安裝必要工具：aws-cli、openssl、jq
- [ ] 建立基本的 AWS profiles（可以是空的，稍後配置）
- [ ] 準備安全的工作環境（加密磁碟、防毒軟體）
- [ ] 預留至少 1 小時的完整時間進行交接

## 🔄 交接執行流程

### 第一階段：既有管理員匯出

```bash
# 既有管理員執行
cd /path/to/vpn-project
./admin-tools/admin-handover-export.sh
```

**腳本會自動執行：**
1. 檢查必要工具
2. 收集所有重要檔案
3. 要求設定加密密碼（至少 8 位元）
4. 建立加密的交接包
5. 顯示傳遞說明

**產出檔案：**
- `vpn-handover-YYYYMMDD-HHMMSS.tar.gz.enc`

### 第二階段：安全傳遞

#### 選項 A：實體傳遞（推薦）

1. **密碼傳遞**
   - 透過電話或面對面告知解密密碼
   - 絕不可使用 Email、Slack、微信等線上方式
   - 確認新任管理員正確記錄密碼

2. **檔案傳遞**
   - 將交接包複製到加密的 USB 隨身碟
   - 親自交給新任管理員
   - 或透過公司內部安全文件傳遞系統

#### 選項 B：雲端臨時存放

```bash
# 既有管理員上傳到 S3 臨時位置
aws s3 cp vpn-handover-*.tar.gz.enc s3://your-temp-bucket/handover/ \
  --expires "$(date -d '+7 days' -Iseconds)"

# 提供下載連結給新任管理員
aws s3 presign s3://your-temp-bucket/handover/vpn-handover-*.tar.gz.enc \
  --expires-in 604800  # 7 天
```

### 第三階段：新任管理員匯入

```bash
# 新任管理員執行
cd /path/to/vpn-project
./admin-tools/admin-handover-import.sh vpn-handover-YYYYMMDD-HHMMSS.tar.gz.enc
```

**腳本會自動執行：**
1. 檢查必要工具和環境
2. 驗證 AWS 設定
3. 解密交接包
4. 恢復所有檔案（自動備份現有檔案）
5. 驗證憑證完整性
6. 測試系統連線
7. 顯示環境狀態摘要

## 📁 交接檔案清單

### 必要憑證檔案
```
certs/staging/pki/
├── ca.crt                    # Staging CA 憑證
├── private/ca.key           # Staging CA 私鑰 🔒
├── issued/server.crt        # Staging 伺服器憑證
└── private/server.key       # Staging 伺服器私鑰 🔒

certs/production/pki/
├── ca.crt                   # Production CA 憑證
├── private/ca.key          # Production CA 私鑰 🔒
├── issued/server.crt       # Production 伺服器憑證
└── private/server.key      # Production 伺服器私鑰 🔒
```

### 設定檔案
```
configs/staging/
├── staging.env             # Staging 環境設定 🔒
└── vpn_endpoint.conf       # Staging VPN 端點資訊

configs/production/
├── production.env         # Production 環境設定 🔒
└── vpn_endpoint.conf      # Production VPN 端點資訊
```

### 其他重要檔案
```
iam-policies/              # IAM 政策檔案
.gitignore                # Git 忽略規則
```

**🔒 標記表示包含敏感資訊的檔案**

## 🔐 安全注意事項

### 密碼安全
- **絕對不可**透過以下方式傳遞密碼：
  - Email、Slack、微信等即時通訊
  - 簡訊或文字訊息
  - 共享文件或筆記應用程式
  - 任何可能被記錄的線上平台

- **建議的密碼傳遞方式**：
  - 面對面口頭告知
  - 電話語音通話（確認接聽者身份）
  - 公司內部加密通訊系統（如有）

### 檔案安全
- 交接包使用 AES-256-CBC 加密
- 包含 SHA256 檢查碼驗證完整性
- 建議使用加密 USB 隨身碟傳遞
- 交接完成後立即刪除所有臨時檔案

### 存取權限
- **職務異動情況**：離職或轉調的管理員應立即撤銷其系統存取權
- **多管理員環境**：如為管理員擴增或權限分享，既有管理員可保持存取權
- **權限審核**：定期檢視所有管理員帳號的必要性和權限範圍
- 新任管理員應儘速更改可更改的共享密碼（如 Slack App 簽署密鑰）
- 考慮在適當時機重新產生 CA 憑證（特別是離職情況）

## ✅ 交接驗證檢查清單

### 新任管理員驗證項目

#### 基本功能測試
- [ ] 成功執行 `./admin-tools/aws_vpn_admin.sh`
- [ ] 能夠檢視兩個環境的 VPN 端點狀態
- [ ] 能夠存取 S3 憑證交換儲存桶
- [ ] 驗證 CA 憑證和私鑰配對正確

#### 憑證管理功能
- [ ] 成功簽署測試憑證
- [ ] 能夠上傳憑證到 S3
- [ ] 能夠從 S3 下載用戶 CSR

#### AWS 存取權限
- [ ] Staging 環境 AWS 操作正常
- [ ] Production 環境 AWS 操作正常
- [ ] VPN 端點管理權限正常
- [ ] IAM 使用者管理權限正常

#### 系統管理功能
- [ ] 能夠新增/移除 VPN 使用者
- [ ] Slack 整合功能運作正常
- [ ] Lambda 函數狀態查看正常
- [ ] 成本監控和報告功能正常

### 既有管理員驗證項目
- [ ] 確認新任管理員成功完成所有基本功能測試
- [ ] 協助解決任何技術問題
- [ ] 提供必要的背景知識和操作經驗
- [ ] 確認交接檔案已安全刪除

## 🆘 常見問題與解決方案

### Q1: 解密時提示密碼錯誤
**解決方案：**
1. 確認密碼輸入正確（注意大小寫）
2. 聯繫既有管理員再次確認密碼
3. 檢查檔案是否在傳輸過程中損壞

### Q2: 憑證驗證失敗
**解決方案：**
1. 檢查憑證檔案是否完整
2. 驗證憑證和私鑰是否配對
3. 確認檔案權限設定正確（私鑰應為 600）

### Q3: AWS 連線測試失敗
**解決方案：**
1. 檢查 AWS CLI 設定：`aws configure list`
2. 驗證 AWS credentials：`aws sts get-caller-identity`
3. 確認 IAM 權限設定正確

### Q4: VPN 端點存取失敗
**解決方案：**
1. 檢查端點 ID 是否正確
2. 確認 AWS Region 設定
3. 驗證 EC2 VPN 相關權限

## 📞 緊急支援聯絡

### 技術支援
- **主要聯絡人**：ct@newsleopard.tw
- **Slack 頻道**：#vpn-support
- **文件位置**：專案根目錄 `docs/` 資料夾

### 緊急情況處理
1. **立即聯繫既有管理員**（如仍可聯繫）
2. **查看系統日誌**：`logs/` 目錄
3. **檢查 AWS CloudWatch**：Lambda 函數日誌
4. **聯繫技術支援團隊**

## 📚 後續學習資源

### 必讀文件
- [使用者指南](user-guide.md) - 了解使用者體驗
- [管理員指南](admin-guide.md) - 日常管理操作
- [架構文件](architecture.md) - 系統技術細節
- [部署指南](deployment-guide.md) - 系統部署維護

### 建議學習順序
1. 熟悉基本的 VPN 端點管理
2. 學習憑證簽署和管理流程
3. 了解成本優化機制
4. 掌握故障排除技巧
5. 深入學習系統架構

---

## ⚠️ 重要提醒

- 此交接過程涉及高度敏感的安全資料
- 務必嚴格遵循安全程序
- 如有任何疑慮，請立即聯繫技術支援
- 完成交接後請儘速刪除所有臨時檔案

**最後更新**：2026-01-02
**版本**：1.1