# AWS Client VPN 雙環境管理自動化系統

## 系統概述

AWS Client VPN 雙環境管理自動化系統是一個專為企業設計的全方位 VPN 管理解決方案。本系統結合了基礎設施即代碼（IaC）、無伺服器架構和智能成本優化，為企業提供安全、高效且經濟的 VPN 管理框架。

### 🎯 核心目標

- **環境隔離**：徹底分離 Staging（測試）和 Production（正式）環境，確保營運安全
- **成本優化**：透過智能監控自動關閉閒置 VPN，年度可節省超過 50% 的 VPN 成本
- **零接觸管理**：採用 S3 安全交換機制，實現證書簽發全自動化流程
- **企業級安全**：實施 AWS 最佳實踐，包含專屬安全群組、KMS 加密和多重身份驗證

### 💰 投資回報率（ROI）

基於典型企業使用場景（5 位工程師，每日使用 5 小時）：

| 項目 | 傳統 24/7 運行 | 自動化系統 | 年度節省 |
|------|---------------|-----------|----------|
| 月度成本 | $132.30 | $56.70 | $75.60 (57%) |
| 年度成本 | $1,587.60 | $680.40 | **$907.20** |

**投資回報期：< 1 個月**

### 🏗️ 系統架構特色

1. **雙環境管理**
   - Staging 環境：開發測試、功能驗證
   - Production 環境：正式營運、嚴格管控

2. **無伺服器架構**
   - AWS Lambda 函數處理所有業務邏輯
   - API Gateway 提供 RESTful 介面
   - SSM Parameter Store 管理配置參數

3. **Slack 整合**
   - 直覺的聊天機器人介面
   - 單一指令管理雙環境
   - 即時狀態通知和警報

4. **智能成本優化**
   - 54 分鐘閒置自動關閉（已優化）
   - 營業時間保護機制
   - 詳細成本追蹤報告

## 🚀 快速開始

### 系統需求

- macOS 10.15+ (Catalina 或更新版本)
- AWS CLI v2 已配置雙環境 profiles
- Node.js 20+ 和 npm
- Slack 工作區管理權限

### 三步驟部署

```bash
# 1. 部署基礎設施
./scripts/deploy.sh both --secure-parameters

# 2. 配置系統參數
./scripts/setup-parameters.sh --all --secure --auto-read \
  --slack-webhook "YOUR_WEBHOOK_URL" \
  --slack-secret "YOUR_SIGNING_SECRET" \
  --slack-bot-token "YOUR_BOT_TOKEN"

# 3. 配置 Slack App
# 將 Staging API URL 設定到 Slack App 的 Request URL
```

### 日常使用

**團隊成員 VPN 設置：**
```bash
./team_member_setup.sh --init    # 開始設置流程
./team_member_setup.sh --resume  # 完成證書安裝
```

**Slack 指令操作：**
```
/vpn open staging      # 開啟測試環境 VPN
/vpn close production  # 關閉正式環境 VPN
/vpn check staging     # 檢查 VPN 狀態
/vpn savings staging   # 查看成本節省報告
```

## 📚 完整文件導覽

本系統提供四份詳細文件，涵蓋不同使用者群體的需求：

### 👥 [使用者手冊](docs/user-manual.md)
適合團隊成員閱讀，包含：
- VPN 客戶端設置步驟
- 證書申請和安裝流程
- Slack 指令使用說明
- 常見問題解答

### 👨‍💼 [管理員手冊](docs/admin-manual.md)
適合系統管理員閱讀，包含：
- 證書簽發管理流程
- 團隊成員權限管理
- 環境切換和管理
- 安全最佳實踐

### 🔧 [維護部署手冊](docs/maintenance-deployment-manual.md)
適合 DevOps 工程師閱讀，包含：
- 系統架構詳解
- CDK 部署流程
- Lambda 函數開發
- 故障排除指南

### 📖 [系統技術詳解](docs/technical-reference.md)
適合技術人員深入了解，包含：
- AWS Client VPN 原理
- 網路架構設計
- 安全群組配置
- 成本優化算法

## 🛡️ 安全特性

- **證書管理**：CA 私鑰永不離開管理員系統
- **加密存儲**：所有敏感參數使用 KMS 加密
- **存取控制**：IAM 角色實施最小權限原則
- **審計追蹤**：完整的 CloudTrail 和 CloudWatch 日誌
- **環境隔離**：跨帳戶驗證防止誤操作

## 🎯 主要效益

### 經濟效益
- 年度節省超過 $900（57% 成本降低）
- 自動化運作無需人工干預
- 可預測的月度 VPN 成本

### 營運效益
- 零維護成本的全自動運行
- 即時 VPN 啟用和關閉
- 統一的雙環境管理介面

### 安全效益
- 減少人為操作錯誤
- 自動關閉降低攻擊面暴露時間
- 完整的操作審計記錄

## 🔄 系統元件

### Shell Scripts 工具集
- 環境管理：`vpn_env.sh`
- 管理員控制台：`aws_vpn_admin.sh`
- 團隊設置：`team_member_setup.sh`
- 診斷修復：`tools/` 目錄下多個工具

### Lambda 函數
- `slack-handler`：處理 Slack 指令
- `vpn-control`：執行 VPN 操作
- `vpn-monitor`：監控和自動關閉

### 基礎設施
- VPC 和子網路配置
- Client VPN 端點
- 安全群組和 NACL
- S3 證書交換桶

## 🤝 貢獻指南

歡迎提交問題報告和功能建議：
- Issue 追蹤：GitHub Issues
- 文件改進：提交 Pull Request
- 功能討論：Slack #vpn-automation 頻道

## 📄 授權

本專案採用內部專有授權，僅供組織內部使用。

---

**版本**：3.0  
**最後更新**：2025-06-29  
**維護團隊**：DevOps Team

> 💡 **提示**：如需快速上手，請先閱讀[使用者手冊](docs/user-manual.md)。如需深入了解系統架構，請參考[系統技術詳解](docs/technical-reference.md)。