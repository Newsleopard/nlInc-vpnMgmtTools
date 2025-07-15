# AWS Client VPN Automation

[![MIT License](https://img.shields.io/badge/License-MIT-green.svg)](https://choosealicense.com/licenses/mit/)


> **Reference Implementation** - Production-tested AWS Client VPN automation system with 57% cost reduction

> **🎯 Project Status**: This is a **reference implementation** shared for educational and inspiration purposes. While the code is production-tested and fully functional, this repository is not actively maintained. Feel free to fork, adapt, and build upon this work for your own needs.

📖 **完整繁體中文檔**: See [README.md](../README.md) for comprehensive Chinese documentation

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

## 🚀 Quick Start

1. **Fork this repository** for your own use
2. **Follow the setup guide** in the main README
3. **Adapt for your needs** - it's designed to be customizable
4. **Share your improvements** with the community

## 📊 Real Impact

- **Cost Reduction**: 57% savings on AWS VPN costs
- **Time Savings**: Zero-touch VPN management
- **Risk Reduction**: Automated security best practices
- **Team Efficiency**: Slack-native operations

---

**⭐ Star this repo if it helps you build better AWS infrastructure!**
