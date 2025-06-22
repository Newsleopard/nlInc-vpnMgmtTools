# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is an AWS Client VPN dual-environment management toolkit designed for macOS. It provides a comprehensive solution for managing VPN endpoints, certificates, and user access across Staging and Production environments with strict environment isolation and enhanced security for production operations.

## Key Architecture Components

- **Dual Environment Architecture**: Complete separation between Staging (🟡) and Production (🔴) environments
- **Dual AWS Profile Management**: Intelligent profile detection, cross-account validation, and automatic profile switching
- **Modular Library Design**: Core functionality split across `lib/` directory with specialized libraries
- **Environment Manager**: Centralized environment switching and health monitoring via `lib/env_manager.sh`
- **Enhanced Security**: Production operations require multi-factor confirmation and additional security checks

## Environment Configuration

Each environment has its own configuration structure:

- `configs/staging/staging.env` - Staging environment settings
- `configs/production/production.env` - Production environment settings  
- `.current_env` - Tracks currently active environment
- Environment-specific directories for certs, logs, and user configs

## AWS Profile Management

The toolkit includes comprehensive dual AWS profile management with the following features:

### Profile Detection and Validation
- **Automatic Detection**: Intelligently detects available AWS profiles and suggests appropriate ones for each environment
- **Cross-Account Validation**: Prevents accidental operations in wrong AWS accounts by validating account IDs
- **Smart Recommendations**: Suggests profiles based on naming conventions (e.g., "staging", "production", "prod")
- **Configuration Persistence**: Saves and loads profile preferences from environment configurations

### Profile Configuration
Each environment configuration supports these AWS profile variables:

```bash
# Environment-specific AWS Profile (optional, uses auto-detection if empty)
ENV_AWS_PROFILE=""

# Suggested profile names for auto-recommendation
SUGGESTED_PROFILES="staging,company-staging,dev-staging"

# Account ID for cross-account validation (required)
AWS_ACCOUNT_ID="123456789012"  # Replace with actual account ID for this environment

# S3 bucket name for zero-touch workflow (unified across all environments)
# Note: All environments now use the same bucket name: "vpn-csr-exchange"
```

### Profile Operations
```bash
# View current AWS profile status
./vpn_env.sh status

# Set specific profile for current environment
./admin-tools/aws_vpn_admin.sh --set-profile my-staging-profile

# Reset to automatic profile detection
./admin-tools/aws_vpn_admin.sh --reset-profile

# View detailed profile information
./admin-tools/aws_vpn_admin.sh --profile-status
```

## Common Development Commands

### Environment Management

```bash
# View current environment status
./vpn_env.sh status

# Switch to staging environment
./vpn_env.sh switch staging

# Switch to production (requires confirmation)
./vpn_env.sh switch production

# Interactive environment selector
./enhanced_env_selector.sh
```

### Admin Operations

```bash
# Main admin console (environment-aware)
./admin-tools/aws_vpn_admin.sh

# Team member setup (secure CSR workflow)
# Zero-Touch Workflow (Recommended)
./team_member_setup.sh --init             # Download config from S3, generate & upload CSR
./team_member_setup.sh --resume           # Download signed cert from S3, complete setup

# Traditional CSR Workflow (Legacy)
./team_member_setup.sh                    # Generate CSR locally (Phase 1)  
./team_member_setup.sh --resume-cert      # Resume with local signed cert (Phase 2)

# Override Options for Special Cases
./team_member_setup.sh --no-s3            # Disable S3 integration
./team_member_setup.sh --bucket my-bucket # Use custom S3 bucket
./team_member_setup.sh --ca-path /path    # Use local CA certificate
./team_member_setup.sh --endpoint-id ID   # Override endpoint ID

# Revoke user access
./admin-tools/revoke_member_access.sh

# Employee offboarding
./admin-tools/employee_offboarding.sh
```

### Infrastructure Setup (S3 Bucket and IAM Policies)

```bash
# Initial infrastructure setup - create S3 bucket and IAM policies
./admin-tools/setup_csr_s3_bucket.sh                   # Complete setup with default options
./admin-tools/setup_csr_s3_bucket.sh --publish-assets  # Setup and publish CA cert/endpoint configs

# Infrastructure management
./admin-tools/setup_csr_s3_bucket.sh --create-policies # Create/update IAM policies only
./admin-tools/setup_csr_s3_bucket.sh --list-policies   # Check IAM policy status
./admin-tools/setup_csr_s3_bucket.sh --cleanup         # Remove bucket and policies

# Publish/update public assets (CA cert and endpoint configs)
./admin-tools/publish_endpoints.sh                     # Publish all environments
./admin-tools/publish_endpoints.sh -e production       # Publish specific environment
```

### VPN User Management (Separate Tool)

```bash
# User Management Operations (Primary tool for user management)
./admin-tools/manage_vpn_users.sh list                 # List all users with VPN permissions
./admin-tools/manage_vpn_users.sh add username         # Add new user and assign VPN permissions
./admin-tools/manage_vpn_users.sh add username --create-user  # Create user if not exists
./admin-tools/manage_vpn_users.sh remove username      # Remove user's VPN permissions
./admin-tools/manage_vpn_users.sh status username      # Check user's permission status

# Permission Diagnostics
./team_member_setup.sh --check-permissions             # Check current user's S3 permissions
./admin-tools/manage_vpn_users.sh check-permissions username  # Check specific user permissions

# Batch User Management
./admin-tools/manage_vpn_users.sh batch-add users.txt  # Add multiple users from file
```

### CSR Processing (Zero-Touch Workflow)

```bash
# Sign individual CSR with zero-touch delivery
./admin-tools/sign_csr.sh --upload-s3 user.csr         # Sign and auto-upload to S3
./admin-tools/sign_csr.sh -e production user.csr       # Traditional local signing

# Batch process CSRs from S3 (Admin efficiency)
./admin-tools/process_csr_batch.sh download -e production    # Download CSRs from S3
./admin-tools/process_csr_batch.sh process -e production     # Sign all CSRs
./admin-tools/process_csr_batch.sh upload --auto-upload      # Upload certificates to S3
./admin-tools/process_csr_batch.sh monitor -e staging        # Auto-monitor and process
```

### Diagnostic and Repair Tools

```bash
# Debug VPN creation issues
./admin-tools/tools/debug_vpn_creation.sh

# Fix common configuration problems
./admin-tools/tools/fix_vpn_config.sh

# Validate and auto-fix configurations
./admin-tools/tools/validate_config.sh

# Fix endpoint ID issues
./admin-tools/tools/fix_endpoint_id.sh
```

## Advanced VPN Configuration Features

### Automatic DNS Split Configuration

The `team_member_setup.sh` script automatically configures advanced DNS and routing features in the generated OpenVPN configuration files to ensure seamless access to AWS services through the VPN tunnel.

#### DNS Configuration Features

**Split DNS Configuration:**
```
dhcp-option DNS-priority 1
dhcp-option DOMAIN internal
dhcp-option DOMAIN {region}.compute.internal
dhcp-option DOMAIN ec2.internal
dhcp-option DOMAIN {region}.elb.amazonaws.com
dhcp-option DOMAIN {region}.rds.amazonaws.com
dhcp-option DOMAIN {region}.s3.amazonaws.com
dhcp-option DOMAIN *.amazonaws.com
```

**What this enables:**
- **AWS Service Resolution**: Ensures AWS service endpoints resolve through VPC DNS
- **Regional Awareness**: Automatically configures region-specific domains (e.g., `us-east-1.compute.internal`)
- **EC2 Instance Discovery**: Allows resolution of EC2 private DNS names
- **Service Integration**: Direct access to RDS, ELB, S3, and other AWS services via internal endpoints
- **DNS Priority**: Sets VPN DNS as primary for AWS domains while preserving local DNS for other domains

#### Advanced Routing Configuration

**Metadata Service Access:**
```
route 169.254.169.254 255.255.255.255  # EC2 metadata service
route 169.254.169.253 255.255.255.255  # VPC DNS resolver
```

**Benefits:**
- **EC2 Metadata Access**: Applications can access EC2 instance metadata and user data
- **IAM Role Integration**: EC2 instances can assume roles and retrieve temporary credentials
- **VPC DNS Resolution**: Ensures all AWS internal DNS queries go through VPC resolver
- **Service Discovery**: Enables applications to discover and connect to VPC-internal services

#### Security and Performance Benefits

**Network Isolation:**
- Routes only necessary AWS traffic through VPN tunnel
- Preserves local internet connectivity for non-AWS traffic
- Reduces VPN bandwidth usage by not tunneling all traffic

**Service Reliability:**
- Uses AWS internal network paths for better performance
- Avoids public internet routing for internal AWS communication
- Reduces latency for AWS service access

**Development Environment Parity:**
- Matches production VPC DNS behavior
- Enables consistent service discovery across environments
- Supports containerized applications expecting AWS metadata access

## Core Library Functions

The `lib/` directory contains modular libraries:

- `core_functions.sh` - Basic utilities, logging, validation functions, AWS CLI wrappers
- `env_manager.sh` - Environment switching, health checks, and profile management
- `env_core.sh` - Core profile management functions and cross-account validation
- `aws_setup.sh` - AWS CLI setup and configuration
- `cert_management.sh` - Certificate generation and management
- `endpoint_management.sh` - VPN endpoint operations
- `endpoint_creation.sh` - VPN endpoint creation logic
- `enhanced_confirmation.sh` - Security confirmation prompts

### Key Profile Management Functions
- `aws_with_profile()` - Wrapper for AWS CLI commands with automatic profile selection
- `aws_with_env_profile()` - Environment-aware AWS CLI wrapper
- `validate_profile_matches_environment()` - Cross-account validation
- `env_validate_profile_integration()` - Comprehensive profile-environment validation
- `select_aws_profile_for_environment()` - Interactive profile selection with smart recommendations

## Environment-Specific Behavior

- **Staging Environment**: Standard operations, simplified confirmations, used for development and testing
- **Production Environment**: Enhanced security, multi-step confirmations, audit logging, requires explicit confirmation for all operations
- All operations automatically adapt behavior based on current environment context

## File Structure Impact

Scripts create/modify files in environment-specific locations:

- Certificates: `certs/{staging|production}/`
- Configurations: `configs/{staging|production}/`
- Logs: `logs/{staging|production}/`
- Current environment state: `.current_env`

## Security Considerations

- **CA Private Key Isolation**: Zero-touch workflow ensures CA private keys never leave admin systems
- **S3 Encrypted Exchange**: All CSR/certificate exchanges use KMS-encrypted S3 storage
- **Dual AWS Profile Management**: Cross-account validation prevents accidental operations in wrong AWS accounts
- **Profile-Aware Operations**: All admin tools validate AWS profile matches target environment
- **Account ID Verification**: Automatic verification of AWS account IDs to prevent cross-account mistakes
- Production environment operations require enhanced confirmation
- Certificate private keys have restricted file permissions (600)
- Environment isolation prevents cross-contamination
- All admin operations are logged with timestamps
- AWS credentials are managed per environment (staging uses default profile, production uses prod profile)
- IAM policies enforce least-privilege access to S3 resources

## Dependencies

The toolkit requires and will auto-install:

- Homebrew (macOS package manager)
- AWS CLI
- jq (JSON processor)
- Easy-RSA (certificate management)
- OpenSSL

## Testing

The toolkit now includes comprehensive automated tests in the `tests/` directory:

### Test Scripts
- `test_profile_management.sh` - Tests all profile management functions, AWS wrappers, and configuration integration
- `test_team_member_setup.sh` - Tests team member setup workflow with dual profile configuration
- `test_admin_tools.sh` - Tests all admin tools for profile integration and environment awareness

### Running Tests
```bash
# Run all profile management tests
./tests/test_profile_management.sh

# Test team member setup integration
./tests/test_team_member_setup.sh

# Test admin tools profile integration
./tests/test_admin_tools.sh
```

### Test Results
All tests generate detailed reports with success rates and recommendations. Tests validate:
- Function existence and availability
- AWS profile detection and validation
- Cross-account safety mechanisms
- Environment-aware configurations
- Error handling and security checks

## Zero-Touch VPN Workflow

### Overview
The zero-touch workflow eliminates manual file transfers between admins and team members by using S3 as a secure exchange mechanism. Team members can automatically download CA certificates and endpoint configurations, while administrators can sign and deliver certificates without direct interaction.

### Benefits
- **🔐 Enhanced Security**: CA private keys never leave admin workstations
- **⚡ Self-Service**: Team members can initiate setup without admin intervention  
- **🚀 Scalability**: Supports large teams with minimal admin overhead
- **📋 Audit Trail**: Complete S3/CloudTrail logging of all certificate exchanges
- **🔄 Automation**: Batch processing and monitoring modes for efficiency
- **☁️ Zero Configuration**: Automatic download of CA certs and endpoint configs

### Workflow Steps
1. **Admin Setup**: `./admin-tools/setup_csr_s3_bucket.sh --publish-assets`
2. **Team Member Init**: `./team_member_setup.sh --init` 
3. **Admin Signs**: `./admin-tools/sign_csr.sh --upload-s3 user.csr`
4. **Team Member Complete**: `./team_member_setup.sh --resume`

### S3 Bucket Structure
- `public/ca.crt` - CA certificate (world-readable in bucket)
- `public/vpn_endpoints.json` - Endpoint IDs and regions by environment
- `csr/username.csr` - User-uploaded CSRs (PUT-only for users)
- `cert/username.crt` - Admin-signed certificates (GET-only for users)
- `log/` - Optional audit copies of processed CSRs/certificates

## VPN User Management and Permissions

### Overview
The toolkit provides comprehensive user management capabilities for VPN access, including automated IAM policy management, permission diagnostics, and scalable user onboarding/offboarding workflows.

### User Permission Architecture
- **IAM Policy-Based**: Uses `VPN-CSR-TeamMember-Policy` for team members and `VPN-CSR-Admin-Policy` for administrators
- **S3 Resource-Based**: Controls access to specific S3 paths (`csr/`, `cert/`, `public/`)
- **Environment-Aware**: Automatically applies correct permissions based on current environment
- **Cross-Account Validation**: Prevents accidental operations in wrong AWS accounts

### New User Onboarding Workflow

#### For Administrators:
1. **Initial Infrastructure Setup** (one-time):
   ```bash
   ./admin-tools/setup_csr_s3_bucket.sh --publish-assets
   ```

2. **Add New User** (using dedicated user management tool):
   ```bash
   # Option 1: Add existing AWS user
   ./admin-tools/manage_vpn_users.sh add username
   
   # Option 2: Create new user and assign permissions
   ./admin-tools/manage_vpn_users.sh add username --create-user
   ```

3. **Verify User Setup**:
   ```bash
   ./admin-tools/manage_vpn_users.sh status username
   ./admin-tools/manage_vpn_users.sh list
   ```

#### For Team Members:
1. **Permission Check** (recommended first step):
   ```bash
   ./team_member_setup.sh --check-permissions
   ```

2. **VPN Setup**:
   ```bash
   # If permissions check passes
   ./team_member_setup.sh --init
   
   # Wait for admin to sign certificate, then
   ./team_member_setup.sh --resume
   ```

### Permission Troubleshooting

#### Common Issues and Solutions:

**Issue**: `AccessDenied` when uploading CSR to S3
**Solutions**:
1. **Admin fixes**: `./admin-tools/manage_vpn_users.sh add USERNAME`
2. **User workaround**: `./team_member_setup.sh --no-s3` (traditional mode)

**Issue**: User not found in AWS
**Solution**: `./admin-tools/manage_vpn_users.sh add USERNAME --create-user`

**Issue**: Permissions appear correct but still failing
**Solutions**:
1. Check policy status: `./admin-tools/setup_csr_s3_bucket.sh --list-policies`
2. Check user status: `./admin-tools/manage_vpn_users.sh status USERNAME`
3. Test permissions: `./admin-tools/manage_vpn_users.sh check-permissions USERNAME`

### Batch User Management

For large teams, use batch operations:

1. **Create user list file** (`users.txt`):
   ```
   john.smith
   jane.doe
   team.lead
   # Comments are supported
   contractor.name
   ```

2. **Batch add users**:
   ```bash
   ./admin-tools/manage_vpn_users.sh batch-add users.txt
   ```

### User Offboarding

```bash
# Remove VPN permissions (recommended)
./admin-tools/manage_vpn_users.sh remove username

# Complete user removal (use with caution)
./admin-tools/employee_offboarding.sh username
```

### Security Best Practices

1. **Regular Audits**: Use `./admin-tools/manage_vpn_users.sh list` to review active users
2. **Permission Validation**: Run `./team_member_setup.sh --check-permissions` before VPN setup
3. **Environment Isolation**: Verify environment with `./vpn_env.sh status` before user operations
4. **Policy Updates**: Regularly review and update IAM policies in `iam-policies/` directory
5. **Access Logging**: Monitor S3 bucket access logs for suspicious activity

## Important Notes

- **Always verify current environment and AWS profile** before operations using `./vpn_env.sh status`
- **Profile Configuration Required**: Each environment needs proper AWS profile configuration in `configs/{env}/{env}.env`
- **Account ID Validation**: Set correct `AWS_ACCOUNT_ID` in each environment config
- **Tool Separation**: Use `setup_csr_s3_bucket.sh` for infrastructure, `manage_vpn_users.sh` for user management
- **Permission Diagnostics**: Use `--check-permissions` options to troubleshoot access issues
- Production operations have additional safety checks and confirmations
- The toolkit is specifically designed for macOS environments
- All scripts use bash and include Chinese language prompts and documentation
- Configuration issues (especially fake endpoint IDs) can be resolved using tools in `admin-tools/tools/`
- Zero-touch workflow requires proper S3 bucket setup and IAM policies
- **Profile Troubleshooting**: If profile detection fails, see `docs/DUAL_AWS_PROFILE_SETUP_GUIDE.md` for troubleshooting steps

## Quick Profile Setup Commands

```bash
# Initial setup - configure your AWS profiles
aws configure --profile staging     # Configure staging profile
aws configure --profile production  # Configure production profile

# Verify profiles work
aws sts get-caller-identity --profile staging
aws sts get-caller-identity --profile production

# Update environment configs with account IDs
# Edit configs/staging/staging.env and configs/production/production.env
# Set AWS_ACCOUNT_ID for each environment

# Test environment switching with profile validation
./vpn_env.sh switch staging
./vpn_env.sh switch production

# View current status (shows environment + profile info)
./vpn_env.sh status
```

## Adding New Administrators

When a new admin joins the team, follow these steps to grant them full VPN management access:

### 1. Add Admin to Configuration
Edit `admin-tools/setup_csr_s3_bucket.sh` and add the new admin username to the VPN_ADMIN_USERS array:

```bash
# VPN 管理員用戶列表 (可根據需要修改)
VPN_ADMIN_USERS=(
    "ct"
    "new-admin-username"  # Add new admin here
)
```

### 2. Update S3 Bucket Policy
```bash
# Re-run setup to update S3 bucket policy with new admin
./admin-tools/setup_csr_s3_bucket.sh
```

### 3. New Admin AWS Profile Setup
The new admin should configure their AWS profiles:
```bash
# Configure AWS CLI with admin credentials
aws configure --profile staging
aws configure --profile production

# Test the profiles work
aws sts get-caller-identity --profile staging
aws sts get-caller-identity --profile production
```

### 4. Verify Admin Access
```bash
# Test admin can sign CSRs and upload to S3
./admin-tools/sign_csr.sh --upload-s3 test.csr

# Test admin can manage users
./admin-tools/manage_vpn_users.sh list
```

The new admin now has full access to:
- Sign and upload certificates via S3
- Manage VPN user permissions
- All environment switching and management operations
