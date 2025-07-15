# AWS Client VPN 雙環境管理自動化系統

> **🎯 Project Status**: This is a **reference implementation** shared for educational and inspiration purposes. While the code is production-tested and fully functional, this repository is not actively maintained. Feel free to fork, adapt, and build upon this work for your own needs.

## 🌟 Why We Built This

At [Newsleopard 電子豹](https://newsleopard.com), we believe in building efficient, cost-effective infrastructure solutions. This AWS Client VPN automation system was born from our real-world need to:

- **Reduce AWS costs** by 57% through intelligent automation
- **Eliminate human error** in VPN management
- **Scale securely** across multiple environments
- **Share knowledge** with the broader AWS community

We're open-sourcing this complete, production-tested solution to help other teams solve similar challenges and demonstrate modern AWS automation patterns.

### 💡 Developer-Friendly VPN Solution

**Is your small team facing these challenges?**

❌ Need secure access to AWS resources (RDS, ElastiCache, Private EKS)  
❌ No DevOps engineer, developers unfamiliar with VPN setup  
❌ Commercial VPNs can't access AWS internal resources  
❌ Manual AWS VPN setup is complex and easy to forget turning off (wasting money)  

**We built a developer-friendly AWS Client VPN automation system using familiar technologies:**

#### ✅ Tech Stack You Already Know
🔹 **AWS CDK + TypeScript** - No need to learn complex network configurations  
🔹 **Lambda + API Gateway** - Solve infrastructure problems with serverless  
🔹 **One-click deployment** - `./scripts/deploy.sh` completes the setup  
🔹 **Slack integration** - `/vpn open staging` for zero-friction team collaboration  

#### 💰 Tailored for Small Teams
🔹 **Automatic cost optimization** - Auto-shutdown after 54 minutes idle, save $900+ annually  
🔹 **Zero maintenance burden** - Set up once, use long-term  
🔹 **Dual environment management** - Complete staging/production isolation  
🔹 **Comprehensive documentation** - Detailed guides from setup to usage  

#### 🎯 Perfect for These Teams
👥 3-15 person development teams  
🏢 No dedicated DevOps/SysAdmin  
☁️ Need access to AWS internal resources  
🏠 Remote or hybrid work models  
💰 Budget-conscious but technically capable  

#### 🤔 Why Not Use Other Solutions?
- **Self-hosted OpenVPN** ➜ Requires learning Linux, networking, certificate management
- **Commercial VPN services** ➜ Cannot access AWS internal resources
- **Manual AWS VPN setup** ➜ Complex + easy to forget shutdown = 💸
- **This solution** ➜ Use your existing skills to solve all problems ✅

**Key Innovations:**

- 🎯 **54-minute idle optimization** - mathematically perfect for AWS hourly billing
- 🔄 **Dual-environment architecture** - complete staging/production isolation  
- 💰 **True cost savings calculation** - prevents 24/7 waste from human forgetfulness
- 🤖 **Slack-native operations** - DevOps teams love the UX
- ⚡ **Lambda warming system** - sub-1-second Slack command response guaranteed
- 🔐 **Direct profile selection** - explicit AWS profile management eliminates hidden state

---

## 系統概述

AWS Client VPN 雙環境管理自動化系統是一個專為企業設計的全方位 VPN 管理解決方案。本系統結合了基礎設施即代碼（IaC）、無伺服器架構和智能成本優化，為企業提供安全、高效且經濟的 VPN 管理框架。

### 🎯 核心目標

- **環境隔離**：徹底分離 Staging（測試）和 Production（正式）環境，確保營運安全
- **成本優化**：透過智能監控自動關閉閒置 VPN，年度可節省超過 50% 的 VPN 成本
- **零接觸管理**：採用 S3 安全交換機制，實現證書簽發全自動化流程
- **企業級安全**：實施 AWS 最佳實踐，包含專屬安全群組、KMS 加密和多重身份驗證

### 💰 投資回報率（ROI）

#### 與自建 VPN 解決方案比較

**自建 Pritunl VPN Server 成本（參考）：**
- 硬體配置：EC2 Spot t3.medium + 30GB SSD
- 月度成本：$33.07 × 2 環境 = $66.14/月
- 年度成本：$793.68
- 管理負擔：需要手動維護、安全更新、監控

**AWS Client VPN 自動化系統成本分析：**

基於實際使用場景（典型小型開發團隊，實際使用頻率）：
- **Staging 環境**：主要用於整合測試、AWS 服務升級、新功能更新（每次1-2人使用）
- **Production 環境**：僅用於功能升級和除錯（每次1-2人使用）

**成本計算詳解：**
```
AWS定價：
- 端點關聯費用：$0.10/小時/子網路
- 活躍連線費用：$0.05/小時/連線

實際使用估算：
- 雙環境各 1 個子網路關聯
- 平均每日使用 6 小時（考慮兩環境交替使用）
- 每月工作日 21 天
- AWS 按小時計費（不足 1 小時按 1 小時計算）

理論最佳情況：
• 端點關聯費用：
  每環境：6小時/天 × 21工作日 = 126小時/月/環境
  雙環境總計：126小時 × $0.10 × 2環境 = $25.20/月

• 連線費用：
  平均 1.5 人同時連線 × 126小時 × $0.05 = $9.45/月

• 理論月度成本：$25.20 + $9.45 = $34.65/月
• 理論年度成本：$34.65 × 12 = $415.80

實務保守估計（考慮實際使用變數）：
• 額外緩衝因子：
  - 週末偶爾使用：+20%
  - 系統測試和維護：+15%
  - 使用量季節性波動：+10%
  - AWS 計費四捨五入：+5%
  
• 保守年度成本：$415.80 × 1.64 = $680.40
```

| 項目 | 自建 Pritunl | 傳統 AWS VPN 24/7 | AWS VPN 自動化系統<br/>（理論/保守） | 年度對比節省 |
|------|-------------|------------------|------------------|-------------|
| 月度成本 | $66.14 | $132.30 | $34.65 / $56.70 | vs 自建：$9.44~$31.49<br/>vs 傳統：$75.60~$97.65 |
| 年度成本 | $793.68 | $1,587.60 | $415.80 / $680.40 | vs 自建：$113.28~$377.88<br/>vs 傳統：$907.20~$1,171.80 |
| 管理成本 | 高（手動維護） | 中（手動開關） | 低（全自動） | 節省工時成本 |
| 可用性 | 99.5%（自維護） | 99.95%（AWS） | 99.95%（AWS） | 更高穩定性 |

**實際效益分析：**

**選擇 AWS VPN 自動化系統的優勢：**

📊 **相比自建 Pritunl 方案：**
- 年度節省 $113.28~$377.88（理論最佳 $415.80，保守估計 $680.40 vs $793.68）
- 同時獲得企業級優勢：
  - AWS 托管可用性：99.95% vs 99.5%
  - 零維護負擔：無需工程師手動維護、安全更新
  - 內建高可用性：跨 AZ 冗餘，無單點故障
  - 專業技術支援：AWS 24/7 支援

🚀 **相比傳統 AWS VPN 24/7 運行：**
- 年度節省 $907.20~$1,171.80（57%~74% 成本降低）
- 智能自動化：54 分鐘閒置自動關閉
- 工作流整合：Slack 指令操作，提升團隊效率
- 完整審計：詳細使用記錄和成本分析

💼 **總體價值主張：**
- **最佳成本效率**：相比傳統 VPN 大幅節省
- **運維零負擔**：完全自動化管理
- **企業級穩定性**：AWS 基礎設施保障
- **開發體驗優化**：Slack 整合，即時操作

**投資回報期：立即獲益**

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

5. **Lambda 預熱系統**
   - 消除冷啟動延遲，確保快速響應
   - 智能時程：營業時間每3分鐘，非營業時間每15分鐘
   - Slack 指令響應時間 < 1 秒保證

## 🚀 快速開始

**⚠️ Important**: This is a reference implementation. Please fork and adapt for your needs.

**📋 New User Setup**: See [維護部署手冊](docs/maintenance-deployment-manual.md#新用戶快速設置) for detailed configuration instructions including account ID replacement.

### 系統需求

- macOS 10.15+ (Catalina 或更新版本)
- AWS CLI v2 已配置雙環境 profiles
- Node.js 20+ 和 npm
- Slack 工作區管理權限

### 三步驟部署

```bash
# 1. 部署基礎設施（使用明確的 AWS Profile）
./scripts/deploy.sh both --secure-parameters --staging-profile default --production-profile prod

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
# 使用直接 profile 選擇
./team_member_setup.sh --init --profile staging    # 開始設置流程（指定環境）
./team_member_setup.sh --resume --profile staging  # 完成證書安裝

# 或使用互動式選擇
./team_member_setup.sh --init    # 互動式選擇 AWS profile
./team_member_setup.sh --resume  # 互動式選擇 AWS profile
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
- 配置管理：`lib/profile_selector.sh`（直接 AWS profile 選擇）
- 管理員控制台：`aws_vpn_admin.sh`（支援 `--profile` 和 `--environment` 參數）
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

歡迎提交問題報告和功能建議！

### 如何貢獻
- **問題回報**：使用 [GitHub Issues](https://github.com/ctyeh/aws-client-vpn-automation/issues)
- **功能建議**：提交 [Feature Request](https://github.com/ctyeh/aws-client-vpn-automation/issues/new)
- **程式碼貢獻**：提交 [Pull Request](https://github.com/ctyeh/aws-client-vpn-automation/pulls)
- **文件改進**：協助改善文件和範例

### 開發指南
請參閱 [CONTRIBUTING.md](CONTRIBUTING.md) 了解詳細的貢獻指南。

### 社群支援
- 📖 [文件](docs/)
- 💬 [GitHub Discussions](https://github.com/ctyeh/aws-client-vpn-automation/discussions)
- 🐛 [問題追蹤](https://github.com/ctyeh/aws-client-vpn-automation/issues)
- 🔒 [安全政策](SECURITY.md)

## 📄 授權

本專案採用 MIT 授權條款，歡迎自由使用、修改和分發。詳見 [LICENSE](LICENSE) 文件。

---

**版本**：3.0  
**最後更新**：2025-06-29  
**原始開發**：[Newsleopard 電子豹](https://newsleopard.com) - [CT Yeh](https://github.com/ctyeh)  
**維護狀態**：Reference Implementation (Community Forks Welcome)

> 💡 **提示**：如需快速上手，請先閱讀[使用者手冊](docs/user-manual.md)。如需深入了解系統架構，請參考[系統技術詳解](docs/technical-reference.md)。

---

**Built with ❤️ by [Newsleopard 電子豹](https://newsleopard.com)** - Sharing knowledge with the AWS community