# VPN User Guide for Engineering Teams

This guide helps engineering team members set up and use the AWS Client VPN system for secure access to company resources.

## 🎯 Who This Guide Is For

- Software Engineers
- QA Engineers
- DevOps Team Members
- Anyone needing VPN access to AWS resources

## 📊 VPN Setup Workflow

```mermaid
flowchart TD
    Start([User Needs VPN Access]) --> Check{Check
Permissions}
    Check -->|Has Permissions| Init[Run team_member_setup.sh --init]
    Check -->|No Permissions| Contact[Contact Administrator]
    Contact --> Admin[Admin Grants Permissions]
    Admin --> Init

    Init --> Generate[Generate CSR & Private Key]
    Generate --> Upload[Upload CSR to S3]
    Upload --> Wait[Wait for Admin Approval]

    Wait --> AdminSign[Admin Signs Certificate]
    AdminSign --> UploadCert[Admin Uploads Certificate to S3]
    UploadCert --> Resume[Run team_member_setup.sh --resume]

    Resume --> Download[Download Signed Certificate]
    Download --> Config[Generate VPN Config Files]
    Config --> Import[Import to VPN Client]
    Import --> Connect[Connect to VPN]
    Connect --> End([VPN Access Ready])

    style Start fill:#e1f5fe
    style End fill:#c8e6c9
    style Wait fill:#fff9c4
    style AdminSign fill:#ffccbc
```

## 📋 Prerequisites

Before starting, ensure you have:

- macOS 10.15+ (Catalina or newer)
- AWS IAM user account with VPN permissions
- Slack workspace access
- OpenVPN client or AWS VPN Client installed

## 🚀 Initial Setup (One-Time)

### Step 1: Check Your Permissions

```bash
./team_member_setup.sh --check-permissions
```

If you see permission errors, contact your VPN administrator.

### Step 2: Generate VPN Certificate

```bash
# For staging environment
./team_member_setup.sh --init --profile staging

# For production environment
./team_member_setup.sh --init --profile production
```

The script will:

1. Download CA certificate from S3
2. Generate your private key (kept locally)
3. Create certificate signing request (CSR)
4. Upload CSR for admin approval

### Step 3: Wait for Admin Approval

You'll see a message like:

```text
⏸️  Setup paused, waiting for admin to sign your certificate...
Username: john.doe
CSR Location: s3://vpn-csr-exchange/csr/john.doe.csr
```

Notify your VPN administrator that your CSR is ready.

### Step 4: Complete Setup

Once approved (admin will notify you):

```bash
./team_member_setup.sh --resume --profile staging
```

This downloads your signed certificate and generates VPN configuration files.

## 💻 Daily VPN Usage

### Using Slack Commands (Recommended)

#### Start VPN

```text
/vpn open staging     # Connect to staging environment
/vpn open production  # Connect to production environment
```

⏱️ **Wait Time**: The `/vpn open` command may take up to **10 minutes** to complete as AWS provisions the VPN endpoint connections. You'll see status updates in Slack during this process.

#### Stop VPN

```text
/vpn close staging
/vpn close production
```

#### Check Status

```text
/vpn check staging
/vpn check production
```

#### View Cost Savings

```text
/vpn savings staging
```

### Connecting with VPN Client

1. **Import Configuration**:
   - Find `.ovpn` file in `downloads/` folder
   - Import into your VPN client

2. **Connect**:
   - Select the profile in your VPN client
   - Click Connect

3. **Auto-Disconnect**: VPN automatically disconnects after 54 minutes of inactivity to save costs

## 🔧 Troubleshooting

### Common Issues and Solutions

#### "VPN endpoint is closed"

First open the VPN endpoint via Slack:

```text
/vpn open staging
```

⏱️ **Wait for "🟢 Open" status** (up to 10 minutes), then connect your VPN client. AWS needs time to associate subnets and configure the endpoint.

#### "Connection timed out"

1. Check VPN endpoint status: `/vpn check staging`
2. Ensure you're on stable internet
3. Try disconnecting and reconnecting

#### "Certificate expired"

Renew your certificate:

```bash
./team_member_setup.sh --renew --profile staging
```

#### "Access denied to specific service"

Contact admin to verify your security group permissions.

### Getting Help

1. **Slack Support**: Post in #vpn-support channel
2. **Check Status**: `/vpn check [environment]`
3. **Admin Contact**: Reach out to VPN administrators

## ⚡ Quick Reference

### Essential Slack Commands

| Command | Purpose | Example |
|---------|---------|---------|
| `/vpn open [env]` | Start VPN | `/vpn open staging` |
| `/vpn close [env]` | Stop VPN | `/vpn close staging` |
| `/vpn check [env]` | Check status | `/vpn check production` |
| `/vpn help` | Show all commands | `/vpn help` |

### Environment Names

- `staging` (aliases: `stage`, `dev`)
- `production` (aliases: `prod`)

### File Locations

```text
certs/
├── staging/          # Staging certificates
│   ├── ca.crt       # CA certificate
│   ├── user.crt     # Your certificate
│   └── user.key     # Your private key (keep safe!)
└── production/      # Production certificates

downloads/
├── staging-vpn-config.ovpn    # Staging VPN config
└── production-vpn-config.ovpn  # Production VPN config
```

## 🔒 Security Best Practices

1. **Protect Your Private Key**
   - Never share `.key` files
   - Keep local backups in secure location
   - Report immediately if compromised

2. **VPN Usage**
   - Only connect when needed
   - Disconnect when finished
   - Don't share VPN access

3. **Environment Separation**
   - Use staging for development/testing
   - Only use production when necessary
   - Follow change management procedures

## 📊 Cost Optimization

The system automatically manages costs by:

- Closing idle VPNs after 54 minutes
- Tracking usage and savings
- Preventing 24/7 VPN charges

View your team's savings:

```text
/vpn savings staging
/vpn costs daily
```

## 🆘 Emergency Procedures

### Lost Private Key

1. Notify administrator immediately
2. Request certificate revocation
3. Generate new certificate

### Can't Access Critical Service

1. Check VPN connection status
2. Verify you're in correct environment
3. Contact admin for urgent access

### Suspected Security Breach

1. Disconnect VPN immediately
2. Notify security team
3. Change AWS credentials
4. Request new certificates

---

**Need Admin Help?** Contact your VPN administrator or post in #vpn-support
**Need Technical Details?** See [Architecture Documentation](architecture.md)
