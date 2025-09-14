# AWS Client VPN Management Toolkit

A comprehensive dual-environment VPN management system combining infrastructure-as-code, serverless architecture, and intelligent cost optimization for enterprise AWS environments.

## 🎯 What This Does

Automates AWS Client VPN management across staging and production environments with:

- **Slack-controlled VPN operations** - Open/close VPN with simple commands
- **Intelligent cost optimization** - Automatically closes idle VPNs (54-minute threshold)
- **Zero-touch certificate workflow** - Automated CSR/certificate exchange via S3
- **Dual-environment isolation** - Complete separation between staging and production

## 💰 Cost Savings

**Compared to 24/7 VPN operation:**

- Annual savings: **$900-1,200** (57-74% reduction)
- Monthly cost: **$35-57** vs traditional **$132**
- Auto-shutdown prevents forgotten connections from incurring charges

## 🚀 Quick Start

### For Team Members

Need VPN access? See [**User Guide**](docs/user-guide.md)

```bash
./team_member_setup.sh --init --profile staging
```

### For Administrators

Managing VPN and users? See [**Admin Guide**](docs/admin-guide.md)

```bash
./admin-tools/aws_vpn_admin.sh --profile staging
```

### For DevOps

Deploying the system? See [**Deployment Guide**](docs/deployment-guide.md)

```bash
./scripts/deploy.sh both --secure-parameters
```

## 📚 Documentation Hub

Choose the guide that matches your role:

| Guide | Audience | Purpose |
|-------|----------|---------|
| [**User Guide**](docs/user-guide.md) | Engineering Team Members | VPN setup, daily usage, troubleshooting |
| [**Admin Guide**](docs/admin-guide.md) | VPN Administrators | User management, certificates, monitoring |
| [**Deployment Guide**](docs/deployment-guide.md) | DevOps Developers | System deployment, maintenance, recovery |
| [**Architecture**](docs/architecture.md) | Technical Deep Dive | System design, security, algorithms |

## 🛠️ Key Features

### Slack Integration

```text
/vpn open staging      # Start VPN
/vpn close production  # Stop VPN
/vpn check staging     # Check status
/vpn savings staging   # View cost savings
```

### Security Features

- 🔐 Certificate-based authentication
- 🛡️ Dedicated security groups per environment
- 🔑 KMS-encrypted secrets in SSM
- 📝 Complete audit trails via CloudTrail

### Automation

- ⚡ Lambda-powered serverless architecture
- 🔄 Auto-close after 54 minutes idle
- 📊 Real-time cost tracking
- 🚀 < 1 second Slack response time

## 🏗️ System Architecture

```text
Slack → API Gateway → Lambda Functions → AWS Client VPN
                           ↓
                    SSM Parameter Store
```

**Components:**

- **Dual AWS Environments**: Staging + Production isolation
- **Serverless Backend**: Lambda + API Gateway + EventBridge
- **Smart Monitoring**: Auto-shutdown with cost optimization
- **Secure Storage**: S3 for certificates, SSM for configuration

## 📋 Prerequisites

- macOS 10.15+ (Catalina or newer)
- AWS CLI v2 configured with dual profiles
- Node.js 20+ and npm
- Slack workspace admin access

## ⚡ Installation

### 1. Clone and Configure

```bash
git clone https://github.com/your-org/aws-client-vpn-toolkit.git
cd aws-client-vpn-toolkit

# Configure AWS profiles
aws configure --profile staging
aws configure --profile production
```

### 2. Deploy Infrastructure

```bash
./scripts/deploy.sh both --secure-parameters \
  --staging-profile staging \
  --production-profile production
```

### 3. Configure Slack

Get the API Gateway URL from deployment output and configure in Slack App settings.

## 🔧 Common Operations

### Team Member Onboarding

```bash
# Admin: Add user permissions
./admin-tools/manage_vpn_users.sh add username --profile staging

# User: Setup VPN access
./team_member_setup.sh --init --profile staging
```

### Daily VPN Usage

```bash
# Via Slack (recommended)
/vpn open staging
/vpn close staging

# Check status
/vpn check staging
```

### Cost Monitoring

```bash
# View savings report
/vpn savings staging

# Detailed analysis
./admin-tools/run-vpn-analysis.sh --profile staging
```

## 🆘 Support

- **Documentation**: See guides above for your role
- **Issues**: [GitHub Issues](https://github.com/your-org/aws-client-vpn-toolkit/issues)
- **Slack Support**: #vpn-support channel

## 📄 License

MIT License - See [LICENSE](LICENSE) file

## 🏢 About

Built by [Newsleopard 電子豹](https://newsleopard.com) - Enterprise AWS solutions

---

**Version**: 3.0 | **Status**: Production Ready | **Last Updated**: 2025-01-14