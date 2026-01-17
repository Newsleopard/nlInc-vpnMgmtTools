# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

AWS Client VPN dual-environment management toolkit for macOS by [Newsleopard](https://newsleopard.com). Manages VPN endpoints, certificates, and user access across Staging and Production environments with strict isolation and enhanced security.

**Author**: [CT Yeh](https://github.com/ctyeh) | **Status**: Reference Implementation (Open Source)

## Quick Reference Commands

```bash
# Build & Deploy
npm run build                           # Build all Lambda functions
npm run deploy:staging                  # Deploy to staging
npm run deploy:production               # Deploy to production
./scripts/deploy.sh both --secure-parameters  # Full deployment with SSM

# Lambda Development (from lambda/ directory)
cd lambda && npm test                   # Run all tests
cd lambda && npm run build              # Build all Lambda functions

# Admin Operations
./admin-tools/aws_vpn_admin.sh                    # Interactive admin console
./admin-tools/manage_vpn_users.sh add username    # Add VPN user
./admin-tools/manage_vpn_users.sh list            # List all VPN users

# Team Member Setup
./team_member_setup.sh --init                     # Start VPN setup
./team_member_setup.sh --resume                   # Complete VPN setup

# AWS Profile Verification
aws sts get-caller-identity --profile staging
aws sts get-caller-identity --profile production
```

## Architecture

### Three-Tier Design

1. **Bash Admin Tools** (`admin-tools/`, `lib/`, `team_member_setup.sh`)
   - Certificate management, CSR signing, user permissions, S3-based zero-touch workflow

2. **Serverless Layer** (`lambda/`, `cdklib/`)
   - Lambda: Slack handler, VPN control, idle monitoring
   - CDK: API Gateway, EventBridge, Lambda layers
   - SSM: Runtime config (endpoints, tokens, thresholds)

3. **AWS Infrastructure**
   - Client VPN endpoints with certificate auth
   - Dedicated security groups per environment
   - S3 bucket for certificate exchange (`vpn-csr-exchange`)

### Core Principles

- **Dual Environment Isolation**: Complete Staging/Production separation
- **Direct Profile Selection**: Explicit AWS profile with cross-account validation
- **Cost Optimization**: 100-min client-side + 30-min server-side idle timeout

## Configuration

**Environment configs:**
- `configs/staging/staging.env` - Staging settings
- `configs/production/production.env` - Production settings
- `configs/{env}/vpn_endpoint.conf` - Auto-generated runtime data

**AWS Profile variables in .env:**
```bash
AWS_ACCOUNT_ID="YOUR_ACCOUNT_ID"  # Required for cross-account validation
ENV_AWS_PROFILE=""                 # Optional, uses auto-detection if empty
```

## Admin Operations

```bash
# Profile selection
./admin-tools/aws_vpn_admin.sh --profile staging --environment staging
./admin-tools/aws_vpn_admin.sh  # Interactive selection

# Infrastructure setup
./admin-tools/setup_csr_s3_bucket.sh --publish-assets

# User management
./admin-tools/manage_vpn_users.sh add username
./admin-tools/manage_vpn_users.sh remove username
./admin-tools/manage_vpn_users.sh list

# CSR signing (zero-touch)
./admin-tools/sign_csr.sh --upload-s3 username

# Diagnostics
./admin-tools/tools/debug_vpn_creation.sh
./admin-tools/tools/fix_vpn_config.sh
```

## Zero-Touch Workflow

1. Admin: `./admin-tools/setup_csr_s3_bucket.sh --publish-assets`
2. Team member: `./team_member_setup.sh --init`
3. Admin: `./admin-tools/sign_csr.sh --upload-s3 username`
4. Team member: `./team_member_setup.sh --resume`

**S3 structure:** `public/` (CA cert, configs), `csr/` (user CSRs), `cert/` (signed certs)

## Lambda Development

**Directory structure:**
```
lambda/
├── shared/           # Lambda Layer (logger, slack, vpnManager, types)
├── slack-handler/    # Slack command endpoint
├── vpn-control/      # VPN control operations
├── vpn-monitor/      # Idle timeout monitoring
└── __tests__/        # Jest unit tests
```

**Build notes:**
- Each function has `build.sh` for CDK-compatible output
- Always use `./scripts/deploy.sh` for proper compilation
- TypeScript compiles to `dist/index.js`

**SSM Parameter hierarchy:**
```
/vpn/{environment}/
├── slack/bot_token, signing_secret, api_key
├── vpn/endpoint_id, region
├── cost/optimization_config
└── cross_account/production_api_url (staging only)
```

## VPN Schedule (Production)

| Time | Behavior |
|------|----------|
| 10:00 AM weekdays | Auto-open |
| 10AM-5PM | Business hours protection (no auto-close) |
| After 5PM | Idle detection active (30 min → close) |
| Friday 8PM | Soft-close (waits for connections, closes idle after 60 min) |
| Weekends | No auto-open |

### Idle Detection (Dual-Layer)

| Layer | Timeout | Trigger |
|-------|---------|---------|
| Client-side | 100 min | macOS VPN config idle timeout |
| Server-side | 30 min | Lambda monitor checks every 5 min |
| Soft-close idle | 60 min | Closes idle connections during weekend close |

**Traffic-based detection:** Only actual network traffic resets the idle timer. Keep-alive packets don't count.

### Soft-Close Behavior

When Friday 8PM close is triggered with active connections:
1. System checks if connections have recent traffic
2. If **active traffic**: delays 30 min and retries (Slack: ⏳ close delayed)
3. If **idle 60+ minutes**: proceeds with close (Slack: 🌙 soft close completed)
4. Normal idle close sends: 💰 Auto VPN Cost Optimization

## Core Libraries (`lib/`)

| Library | Purpose |
|---------|---------|
| `profile_selector.sh` | AWS profile management, `select_and_validate_profile()` |
| `core_functions.sh` | Logging, validation, utilities |
| `cert_management.sh` | Certificate operations |
| `endpoint_management.sh` | VPN endpoint CRUD |
| `security_group_operations.sh` | Security group management |

## Security

- **Dedicated security groups** per environment (`client-vpn-sg-{env}`)
- **CA private key isolation** - never leaves admin systems
- **S3 encrypted exchange** with KMS
- **Cross-account validation** prevents wrong-environment operations
- **Enhanced production confirmations** for destructive operations
- Certificate private keys: mode 600

## File Structure

```
certs/{staging|production}/      # Certificates
configs/{staging|production}/    # Environment configs
logs/{staging|production}/       # Operation logs
admin-tools/                     # Admin scripts
lib/                             # Shared bash libraries
lambda/                          # Lambda functions
cdklib/                          # CDK infrastructure
```

## Important Notes

- Verify AWS profile before operations: `aws sts get-caller-identity --profile PROFILE`
- JSON parameters must be compact: `{"key":"value"}` (no spaces)
- Production operations require enhanced confirmation
- macOS only; scripts include Chinese language prompts
- Config issues: use tools in `admin-tools/tools/`
- Profile troubleshooting: see `docs/DUAL_AWS_PROFILE_SETUP_GUIDE.md`

## Adding Administrators

1. Edit `admin-tools/setup_csr_s3_bucket.sh` - add username to `VPN_ADMIN_USERS` array
2. Run `./admin-tools/setup_csr_s3_bucket.sh` to update S3 policy
3. New admin configures AWS profiles and tests with `./admin-tools/manage_vpn_users.sh list`

## Cost Reference

**AWS Client VPN pricing:**
- Endpoint: $0.10/hour/subnet
- Connection: $0.05/hour/connection

**Typical (10hr/day, 2 concurrent):** ~$44/month

**Savings from idle detection:** ~66% vs 24/7 operation
