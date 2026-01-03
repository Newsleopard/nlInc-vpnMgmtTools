# AWS Client VPN Dual-Environment Management Toolkit

[![MIT License](https://img.shields.io/badge/License-MIT-green.svg)](https://choosealicense.com/licenses/mit/)
[![Node.js](https://img.shields.io/badge/Node.js-20+-green.svg)](https://nodejs.org/)
[![AWS CDK](https://img.shields.io/badge/AWS%20CDK-v2-orange.svg)](https://aws.amazon.com/cdk/)
[![TypeScript](https://img.shields.io/badge/TypeScript-5+-blue.svg)](https://www.typescriptlang.org/)

> **Reference Implementation** - Production-tested AWS Client VPN automation system with 57% cost reduction and enterprise-grade security

> **🎯 Project Status**: This is a **reference implementation** shared for educational and inspiration purposes. While the code is production-tested and fully functional, this repository is not actively maintained. Feel free to fork, adapt, and build upon this work for your own needs.

📖 **完整繁體中文檔**: See [README.md](../README.md) for comprehensive Chinese documentation

## 🌟 Why We Built This

At [Newsleopard 電子豹](https://newsleopard.com), we believe in building efficient, cost-effective infrastructure solutions. This AWS Client VPN automation system was born from our real-world need to:

- **Reduce AWS costs** by 57% through intelligent automation
- **Eliminate human error** in VPN management
- **Scale securely** across multiple environments
- **Share knowledge** with the broader AWS community

We're open-sourcing this complete, production-tested solution to help other teams solve similar challenges and demonstrate modern AWS automation patterns.

## 🏗️ System Architecture

### High-Level Overview

```
┌─────────────────────────────────────────────────────────┐
│                     Slack Interface                      │
├─────────────────────────────────────────────────────────┤
│                    API Gateway (REST)                    │
├─────────────────────────────────────────────────────────┤
│                   Lambda Functions                       │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐             │
│  │  Slack   │  │   VPN    │  │   VPN    │             │
│  │ Handler  │→ │ Control  │  │ Monitor  │             │
│  └──────────┘  └──────────┘  └──────────┘             │
├─────────────────────────────────────────────────────────┤
│              AWS Services Layer                          │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐             │
│  │   SSM    │  │    EC2   │  │CloudWatch│             │
│  │Parameter │  │  Client  │  │  Events  │             │
│  │  Store   │  │   VPN    │  │          │             │
│  └──────────┘  └──────────┘  └──────────┘             │
└─────────────────────────────────────────────────────────┘
```

### Tech Stack

- **Infrastructure**: AWS CDK v2 (TypeScript)
- **Runtime**: Node.js 20.x Lambda Functions
- **API**: REST API via API Gateway
- **Scheduling**: EventBridge (CloudWatch Events)
- **Configuration**: SSM Parameter Store with KMS encryption
- **Security**: IAM roles, Security Groups, Certificate-based authentication
- **Monitoring**: CloudWatch Logs/Metrics with cost tracking

### Dual Environment Design

- **🟡 Staging Environment**: Development and testing with simplified confirmations
- **🔴 Production Environment**: Enhanced security, multi-step confirmations, audit logging
- **Complete Isolation**: Separate AWS profiles, configurations, certificates, and logs
- **Cross-Account Validation**: Prevents accidental operations in wrong environments

## 💡 Developer-Friendly VPN Solution

**Is your small team facing these challenges?**

❌ Need secure access to AWS resources (RDS, ElastiCache, Private EKS)  
❌ No DevOps engineer, developers unfamiliar with VPN setup  
❌ Commercial VPNs can't access AWS internal resources  
❌ Manual AWS VPN setup is complex and easy to forget turning off (wasting money)  

**We built a developer-friendly AWS Client VPN automation system using familiar technologies:**

### ✅ Tech Stack You Already Know

🔹 **AWS CDK + TypeScript** - No need to learn complex network configurations  
🔹 **Lambda + API Gateway** - Solve infrastructure problems with serverless  
🔹 **One-click deployment** - `./scripts/deploy.sh` completes the setup  
🔹 **Slack integration** - `/vpn open staging` for zero-friction team collaboration  

### 💰 Tailored for Small Teams

🔹 **Automatic cost optimization** - Auto-shutdown after 100 minutes idle (traffic-based detection)  
🔹 **Zero maintenance burden** - Set up once, use long-term  
🔹 **Dual environment management** - Complete staging/production isolation  
🔹 **Comprehensive documentation** - Detailed guides from setup to usage  

### 🎯 Perfect for These Teams

👥 3-15 person development teams  
🏢 No dedicated DevOps/SysAdmin  
☁️ Need access to AWS internal resources  
🏠 Remote or hybrid work models  
💰 Budget-conscious but technically capable  

### 🤔 Why Not Use Other Solutions?

- **Self-hosted OpenVPN** ➜ Requires learning Linux, networking, certificate management
- **Commercial VPN services** ➜ Cannot access AWS internal resources
- **Manual AWS VPN setup** ➜ Complex + easy to forget shutdown = 💸
- **This solution** ➜ Use your existing skills to solve all problems ✅

## 🚀 Key Features & Innovations

### 🎯 100-Minute Traffic-Based Idle Detection

**Smart Cost Optimization:**

- **Client-Side Idle Timeout**: 100 minutes with 10KB traffic threshold
- **Traffic-Based Detection**: Keepalive packets don't reset the timer
- **Server-Side Monitoring**: 5-minute CloudWatch Events for endpoint management
- **Reliable Detection**: Only actual usage (SSH, HTTP, etc.) resets the timer

```bash
# OpenVPN client config
inactive 6000 10000  # 100 minutes, 10KB threshold
# Keepalive packets (~50 bytes) won't prevent idle detection
```

### 🔄 Zero-Touch Certificate Workflow

**Secure, Automated Certificate Management:**

1. **Team Member**: `./team_member_setup.sh --init` (generates CSR, uploads to S3)
2. **S3 Exchange**: Encrypted CSR/certificate exchange via dedicated S3 bucket
3. **Admin Signs**: `./admin-tools/sign_csr.sh --upload-s3 username` (just username, auto-downloads CSR)
4. **Team Member**: `./team_member_setup.sh --resume` (downloads signed cert, configures VPN)

**Benefits:**
- 🔐 CA private keys never leave admin workstations
- ⚡ Self-service setup for team members
- 📋 Complete audit trail via CloudTrail
- 🚀 Scales to large teams with minimal admin overhead

### 🤖 Slack-Native Operations

**Zero-Friction Team Collaboration:**

```bash
/vpn open staging      # Start VPN with sub-1-second response
/vpn close production  # Stop VPN with confirmation
/vpn check staging     # Status with cost tracking
/vpn savings staging   # Detailed cost analysis
```

**Features:**
- ⚡ Lambda warming ensures <1-second response times
- 🔒 Environment-aware confirmations (enhanced for production)
- 📊 Real-time cost tracking and savings reports
- 🎯 Smart routing between staging and production APIs

### 🛡️ Enterprise Security Features

**Comprehensive Security Architecture:**

- **🔐 Certificate-Based Authentication**: Easy-RSA generated certificates with proper key management
- **🛡️ Dedicated Security Groups**: Isolated VPN user security groups with least-privilege access
- **🔑 KMS-Encrypted Secrets**: All sensitive data encrypted in SSM Parameter Store
- **📝 Complete Audit Trail**: CloudTrail logging of all VPN operations
- **🌐 Cross-Account Validation**: Prevents accidental operations in wrong AWS accounts
- **🎯 Environment Isolation**: Complete separation between staging and production

### 🌐 Advanced Network Configuration

**Automatic DNS and Routing Optimization:**

```bash
# DNS configuration for AWS service access
dhcp-option DOMAIN {region}.compute.internal
dhcp-option DOMAIN *.amazonaws.com

# Metadata service access
route 169.254.169.254 255.255.255.255  # EC2 metadata
route 169.254.169.253 255.255.255.255  # VPC DNS resolver
```

**Benefits:**
- 🔍 AWS service resolution through VPC DNS
- 🌐 Regional awareness for optimal routing
- 📊 EC2 metadata and IAM role access
- 🎯 Split-tunnel configuration preserves local internet access

## 📋 System Requirements

### Prerequisites

- **Operating System**: macOS 10.15+ (Catalina or newer)
- **Node.js**: v20.0.0 or higher
- **AWS CLI**: v2.x with configured profiles
- **Dependencies**: Automatically installed via Homebrew
  - jq (JSON processor)
  - Easy-RSA (certificate management)
  - OpenSSL

### AWS Requirements

- **Dual AWS Profiles**: Separate profiles for staging and production
- **VPC Configuration**: Existing VPC with subnets for VPN endpoint
- **IAM Permissions**: Admin access for initial setup, managed policies for users
- **Slack Integration**: Slack workspace admin permissions

## 🚀 Quick Start Guide

### 1. Initial Setup

```bash
# Clone and enter repository
git clone https://github.com/your-org/aws-client-vpn-toolkit.git
cd aws-client-vpn-toolkit

# Configure AWS profiles
aws configure --profile staging
aws configure --profile production

# Verify profiles
aws sts get-caller-identity --profile staging
aws sts get-caller-identity --profile production
```

### 2. Environment Configuration

```bash
# Configure environment settings
# Edit configs/staging/staging.env
# Edit configs/production/production.env
# Set VPC_ID, SUBNET_ID, AWS_ACCOUNT_ID for each environment
```

### 3. Deploy Infrastructure

```bash
# Deploy both environments with secure parameters
./scripts/deploy.sh both --secure-parameters \
  --staging-profile staging \
  --production-profile production

# Deploy individual environments
./scripts/deploy.sh staging --staging-profile staging
./scripts/deploy.sh production --production-profile production
```

### 4. Setup S3 Infrastructure

```bash
# Create S3 bucket and IAM policies for zero-touch workflow
./admin-tools/setup_csr_s3_bucket.sh --publish-assets

# Verify setup
./admin-tools/setup_csr_s3_bucket.sh --list-policies
```

### 5. Configure Slack Integration

```bash
# Get API Gateway URL from deployment output
./scripts/deploy.sh status

# Configure Slack app with the staging API Gateway URL
# The smart routing system handles both environments
```

## 📚 Usage Examples

### For Team Members (VPN Users)

```bash
# Check permissions
./team_member_setup.sh --check-permissions

# Setup VPN access (zero-touch workflow)
./team_member_setup.sh --init --profile staging
# Wait for admin approval, then:
./team_member_setup.sh --resume --profile staging

# Use via Slack (recommended)
/vpn open staging
/vpn close staging
/vpn check staging
```

### For VPN Administrators

```bash
# User management
./admin-tools/manage_vpn_users.sh add username --profile staging
./admin-tools/manage_vpn_users.sh list --profile staging
./admin-tools/manage_vpn_users.sh remove username --profile staging

# Certificate management (just username, no .csr needed)
./admin-tools/sign_csr.sh --upload-s3 username --profile staging
./admin-tools/process_csr_batch.sh monitor --environment staging

# VPN administration
./admin-tools/aws_vpn_admin.sh --profile staging --environment staging
```

### For DevOps Engineers

```bash
# Infrastructure management
./scripts/deploy.sh staging --staging-profile staging
./scripts/deploy.sh production --production-profile production

# Monitoring and diagnostics
./admin-tools/tools/debug_vpn_creation.sh --profile staging
./admin-tools/tools/validate_config.sh --profile staging
./admin-tools/run-vpn-analysis.sh --profile staging

# Cost analysis
./admin-tools/tools/cost-analysis.sh --profile staging
```

## 💰 Cost Optimization Details

### Automatic Cost Management

**Traditional VPN Costs (24/7):**
- Monthly: $132 (24 hours × 30 days × $0.18/hour)
- Annual: $1,584

**With Automation (Typical Usage):**
- Monthly: $35-57 (reduced hours with auto-shutdown)
- Annual: $420-684
- **Savings: $900-1,200 annually (57-74% reduction)**

### 54-Minute Algorithm Breakdown

```typescript
// Cost optimization configuration
const CONFIG = {
  IDLE_THRESHOLD: 54,    // Minutes before auto-shutdown
  MONITOR_INTERVAL: 5,   // CloudWatch Events frequency
  MAX_RUNTIME: 59,       // Mathematical guarantee: 54 + 5
  BILLING_HOUR: 60       // AWS hourly billing cycle
};

// Guarantees: MAX_RUNTIME < BILLING_HOUR
// Result: No VPN connection crosses billing hour boundary
```

## 🔧 Administration & Maintenance

### User Lifecycle Management

```bash
# New user onboarding
./admin-tools/manage_vpn_users.sh add newuser --create-user --profile staging

# User offboarding
./admin-tools/manage_vpn_users.sh remove olduser --profile staging
./admin-tools/employee_offboarding.sh olduser --profile staging

# Batch operations
./admin-tools/manage_vpn_users.sh batch-add users.txt --profile staging
```

### Certificate Management

```bash
# Individual certificate signing (just username, no .csr needed)
./admin-tools/sign_csr.sh --upload-s3 username --profile staging

# Batch certificate processing
./admin-tools/process_csr_batch.sh download --environment staging
./admin-tools/process_csr_batch.sh process --environment staging
./admin-tools/process_csr_batch.sh upload --auto-upload --environment staging

# Automated monitoring
./admin-tools/process_csr_batch.sh monitor --environment staging
```

### System Monitoring

```bash
# VPN status and cost tracking
/vpn check staging          # Via Slack
/vpn savings staging        # Cost analysis via Slack

# Administrative monitoring
./admin-tools/run-vpn-analysis.sh --profile staging
./admin-tools/tools/debug_vpn_creation.sh --profile staging
```

## 🛡️ Security Best Practices

### Certificate Security

- **CA Private Key Isolation**: Never leaves admin workstations
- **S3 Encrypted Exchange**: KMS-encrypted CSR/certificate storage
- **Certificate Permissions**: Restrictive file permissions (600)
- **Audit Trail**: Complete CloudTrail logging

### Access Control

- **Dedicated Security Groups**: Isolated VPN user security groups
- **Least Privilege IAM**: Minimal required permissions
- **Environment Validation**: Cross-account ID verification
- **Profile-Aware Operations**: Explicit AWS profile validation

### Production Safeguards

- **Enhanced Confirmations**: Multi-step production confirmations
- **Audit Logging**: Detailed operation logging
- **Environment Isolation**: Complete staging/production separation
- **Safe Defaults**: Conservative timeout and security settings

### Additional Resources

- [**CONTRIBUTING.md**](../docs/development/CONTRIBUTING.md) - Contribution guidelines
- [**SECURITY.md**](../docs/development/SECURITY.md) - Security policy and reporting
- [**CODE_OF_CONDUCT.md**](../docs/development/CODE_OF_CONDUCT.md) - Community guidelines

## 🔧 Troubleshooting

### Common Issues

**Issue**: AccessDenied when uploading CSR to S3  
**Solution**: `./admin-tools/manage_vpn_users.sh add USERNAME --profile staging`

**Issue**: Profile detection fails  
**Solution**: Check AWS profile configuration with `aws configure list-profiles`

**Issue**: VPN connection fails  
**Solution**: Run diagnostics with `./admin-tools/tools/debug_vpn_creation.sh --profile staging`

**Issue**: Certificate validation errors  
**Solution**: Use validation tool `./admin-tools/tools/validate_config.sh --profile staging`

### Diagnostic Tools

```bash
# Permission diagnostics
./team_member_setup.sh --check-permissions --profile staging
./admin-tools/manage_vpn_users.sh check-permissions username --profile staging

# System diagnostics
./admin-tools/tools/debug_vpn_creation.sh --profile staging
./admin-tools/tools/fix_vpn_config.sh --profile staging
./admin-tools/tools/validate_config.sh --profile staging
```

## 📊 Real Impact

### Measured Benefits

- **💰 Cost Reduction**: 57% savings on AWS VPN costs ($900-1,200 annually)
- **⏱️ Time Savings**: Zero-touch VPN management eliminates manual operations
- **🛡️ Risk Reduction**: Automated security best practices prevent human error
- **👥 Team Efficiency**: Slack-native operations improve developer experience
- **📈 Scalability**: Supports teams from 3-50+ members with minimal admin overhead

### Cost Analysis Example

```bash
# Traditional Manual VPN (24/7)
24 hours/day × 30 days × $0.18/hour = $132/month = $1,584/year

# Automated VPN (Typical Usage Pattern)
8 hours/day × 22 workdays × $0.18/hour = $32/month = $384/year
Plus idle prevention saves additional $300-600/year

# Total Savings: $900-1,200 annually (57-74% reduction)
```

## 🏢 About This Project

### Project Origin

This AWS Client VPN automation system was built by [Newsleopard 電子豹](https://newsleopard.com) as a production solution for managing secure access to AWS resources across dual environments. We've open-sourced this complete, battle-tested implementation to help other teams solve similar challenges.

### Author & Contributors

- **Original Author**: [CT Yeh](https://github.com/ctyeh) (ct@newsleopard.tw)
- **Company**: [Newsleopard 電子豹](https://newsleopard.com)
- **Contributors**: Newsleopard Team

### License & Usage

- **License**: MIT License - see [LICENSE](LICENSE) file
- **Status**: Reference Implementation (Open Source)
- **Maintenance**: Not actively maintained - designed for forking and adaptation

## 🚀 Getting Started

1. **Fork this repository** for your own use
2. **Review the documentation guides** that match your role
3. **Follow the setup instructions** in the deployment guide
4. **Adapt the configuration** for your AWS environment
5. **Deploy and test** in staging first
6. **Share your improvements** with the community

## 🆘 Support

- **📖 Documentation**: Use the role-specific guides listed above
- **🐛 Issues**: [GitHub Issues](https://github.com/Newsleopard/nlInc-vpnMgmtTools/issues) for bugs and feature requests
- **💬 Community**: Star the repo and share your experience
- **🔧 Technical**: Review diagnostic tools and troubleshooting sections

---

**⭐ Star this repo if it helps you build better AWS infrastructure!**

**Version**: 3.0 | **Status**: Production-Ready Reference Implementation | **Last Updated**: 2025-01-14
