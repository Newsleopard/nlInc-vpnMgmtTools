# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is an AWS Client VPN dual-environment management toolkit designed for macOS, developed by [Newsleopard 電子豹](https://newsleopard.com). It provides a comprehensive solution for managing VPN endpoints, certificates, and user access across Staging and Production environments with strict environment isolation and enhanced security for production operations.

**Original Author**: [CT Yeh](https://github.com/ctyeh) (ct@newsleopard.tw)
**Company**: [Newsleopard 電子豹](https://newsleopard.com)
**Status**: Reference Implementation (Open Source)

## Quick Reference - Most Common Commands

```bash
# Build & Deploy
npm run build                           # Build all Lambda functions
npm run deploy:staging                  # Deploy to staging
npm run deploy:production               # Deploy to production
npm run deploy:both                     # Deploy to both environments
./scripts/deploy.sh both --secure-parameters  # Full deployment with SSM setup

# Lambda Development (from lambda/ directory)
cd lambda && npm test                   # Run all tests
cd lambda && npm run test:watch         # Run tests in watch mode
cd lambda && npm run build              # Build all Lambda functions
cd lambda && npm run build:shared       # Build shared layer only

# Admin Operations
./admin-tools/aws_vpn_admin.sh                    # Interactive admin console
./admin-tools/manage_vpn_users.sh add username    # Add VPN user
./admin-tools/manage_vpn_users.sh list            # List all VPN users

# Team Member Setup
./team_member_setup.sh --init                     # Start VPN setup (zero-touch)
./team_member_setup.sh --resume                   # Complete VPN setup

# Testing
./tests/test_profile_management.sh                # Test profile management
./tests/test_team_member_setup.sh                 # Test team setup workflow
./tests/test_admin_tools.sh                       # Test admin tools

# AWS Profile Verification
aws configure list-profiles                       # List available profiles
aws sts get-caller-identity --profile staging     # Verify staging profile
aws sts get-caller-identity --profile production  # Verify production profile
```

## Key Architecture Components

### Three-Tier Architecture

1. **Bash Admin Tools Layer** (`admin-tools/`, `lib/`, `team_member_setup.sh`)
   - Certificate management and CSR signing
   - User permission management via IAM policies
   - VPN endpoint creation and configuration
   - S3-based zero-touch workflow for certificate exchange

2. **Serverless Automation Layer** (`lambda/`, `cdklib/`)
   - **Lambda Functions**: Slack command handler, VPN control, idle monitoring
   - **CDK Infrastructure**: API Gateway, EventBridge rules, Lambda layers
   - **SSM Parameter Store**: Runtime configuration (VPN endpoints, Slack tokens, thresholds)

3. **AWS Infrastructure**
   - Client VPN endpoints with certificate-based authentication
   - Dedicated security groups per environment
   - S3 bucket for certificate exchange (`vpn-csr-exchange`)
   - CloudWatch Events for idle timeout monitoring

### Core Design Principles

- **Dual Environment Isolation**: Complete separation between Staging (🟡) and Production (🔴) environments
- **Direct Profile Selection**: Explicit AWS profile selection with cross-account validation (replaces stateful environment switching)
- **Modular Library Design**: Core functionality split across `lib/` directory with specialized libraries
- **Profile Selector Library**: `lib/profile_selector.sh` provides intelligent profile detection and interactive selection
- **Enhanced Security**: Cross-account validation prevents wrong-environment operations, with enhanced production confirmations
- **Cost Optimization**: 100-minute client-side idle timeout with traffic threshold ensures automatic disconnection when VPN is not actively used

## Environment Configuration

Each environment has its own configuration structure:

- `configs/staging/staging.env` - Staging environment settings
- `configs/production/production.env` - Production environment settings  
- Environment-specific directories for certs, logs, and user configs
- `lib/profile_selector.sh` - Direct AWS profile selection (replaces stateful environment tracking)

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
AWS_ACCOUNT_ID="YOUR_ACCOUNT_ID"  # Replace with actual account ID for this environment

# S3 bucket name for zero-touch workflow (unified across all environments)
# Note: All environments now use the same bucket name: "vpn-csr-exchange"
```

### Profile Operations
```bash
# View available AWS profiles
aws configure list-profiles

# Use specific profile with admin tools
./admin-tools/aws_vpn_admin.sh --profile staging
./admin-tools/aws_vpn_admin.sh --profile production

# Use environment-aware selection (interactive)
./admin-tools/aws_vpn_admin.sh --environment staging

# Interactive profile selection (shows smart menu)
./admin-tools/aws_vpn_admin.sh
```

**Interactive Profile Selection Features:**
- Smart menu with environment mapping and recommendations  
- Star (⭐) highlighting for environment-matched profiles
- Account ID and region display for verification
- Cross-account validation prevents wrong-environment operations
- User-friendly error handling and guidance

## Common Development Commands

### Environment Management (Updated)

**New Direct Profile Selection System:**
```bash
# All scripts now support direct profile and environment parameters
./admin-tools/aws_vpn_admin.sh --profile staging --environment staging
./admin-tools/aws_vpn_admin.sh --profile prod --environment prod

# Interactive profile selection (recommended)
./admin-tools/aws_vpn_admin.sh  # Shows profile selection menu

# Deployment with specific profiles
./scripts/deploy.sh --staging-profile default --production-profile prod both
```

**Legacy Environment Switching (Deprecated):**
```bash
# Old stateful system (moved to deprecated/)
# ./admin-tools/vpn_env.sh switch production  # NO LONGER RECOMMENDED
# ./enhanced_env_selector.sh                  # NO LONGER NEEDED
```

### Admin Operations

```bash
# Main admin console with direct profile selection
./admin-tools/aws_vpn_admin.sh --profile prod --environment prod
./admin-tools/aws_vpn_admin.sh  # Interactive profile selection

# Team member setup (S3-only zero-touch workflow)
./team_member_setup.sh                    # Initialize VPN setup (default: --init)
./team_member_setup.sh --init             # Download config from S3, generate & upload CSR
./team_member_setup.sh --resume           # Download signed cert from S3, complete setup
./team_member_setup.sh --check-permissions # Check S3 access permissions

# Optional: Use custom S3 bucket
./team_member_setup.sh --bucket my-bucket # Use custom S3 bucket name

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
# Sign individual CSR with zero-touch delivery (username only - recommended)
./admin-tools/sign_csr.sh --upload-s3 john             # Just username, auto-download CSR from S3
./admin-tools/sign_csr.sh --upload-s3 john.csr         # Also works with .csr extension
./admin-tools/sign_csr.sh -e production john.csr       # Traditional local signing

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

The `team_member_setup.sh` script automatically configures advanced DNS, routing, and cost optimization features in the generated OpenVPN configuration files to ensure seamless access to AWS services through the VPN tunnel.

#### Cost Optimization Configuration

**Automatic Idle Timeout (100 minutes):**
```
inactive 6000 10000  # 100 minutes, 10KB traffic threshold
```

**Benefits:**
- **Cost Savings**: Automatically disconnects idle VPN sessions after 100 minutes of inactivity
- **Traffic-Based Detection**: 10KB threshold ensures keepalive packets don't reset the timer
- **User Experience**: Generous timeout for work sessions while preventing forgotten connections
- **Smart Detection**: Only actual data traffic (SSH, HTTP, etc.) resets the timer, not protocol overhead

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

## Core Bash Library Functions

The `lib/` directory contains modular bash libraries that provide core functionality for admin tools and setup scripts. All scripts source these libraries for consistent behavior.

### Library Overview

| Library | Purpose | Key Functions |
|---------|---------|---------------|
| `profile_selector.sh` | AWS profile management | `select_and_validate_profile()`, `aws_with_selected_profile()` |
| `core_functions.sh` | Utilities and logging | `log_operation()`, `validate_environment()`, `check_dependencies()` |
| `cert_management.sh` | Certificate operations | `generate_client_cert()`, `sign_csr()`, `validate_certificate()` |
| `endpoint_management.sh` | VPN endpoint CRUD | `create_vpn_endpoint()`, `modify_vpn_endpoint()`, `delete_vpn_endpoint()` |
| `endpoint_creation.sh` | VPN endpoint creation | `setup_vpn_infrastructure()`, `configure_client_vpn()` |
| `security_group_operations.sh` | Security group management | `create_client_vpn_sg()`, `authorize_service_access()` |
| `network_association.sh` | VPC/subnet operations | `associate_vpn_network()`, `configure_routing()` |
| `enhanced_confirmation.sh` | Production safeguards | `require_enhanced_confirmation()`, `production_warning()` |
| `aws_setup.sh` | AWS CLI setup | `install_aws_cli()`, `configure_aws_profile()` |

### Profile Selection Functions (lib/profile_selector.sh)

**Primary Functions:**

- `select_and_validate_profile()` - Main entry point for profile selection with cross-account validation
- `aws_with_selected_profile()` - Execute AWS CLI commands with the selected profile (replacement for `aws` command)
- `detect_available_profiles()` - Scan `~/.aws/config` and detect all configured profiles
- `map_profile_to_environment()` - Map profile names to environments using naming conventions (e.g., "staging" → staging)
- `validate_profile_account()` - Verify profile's AWS account ID matches target environment
- `select_profile_interactive()` - Display interactive menu for profile selection with recommendations
- `load_environment_config()` - Load environment-specific `.env` files

**Usage Example:**

```bash
#!/bin/bash
source "lib/profile_selector.sh"

# Interactive profile selection with validation
select_and_validate_profile "staging"

# Execute AWS commands with selected profile
aws_with_selected_profile ec2 describe-vpcs
aws_with_selected_profile s3 ls

# Check if profile is set
if [[ -n "$SELECTED_AWS_PROFILE" ]]; then
    echo "Using profile: $SELECTED_AWS_PROFILE"
fi
```

### Core Functions (lib/core_functions.sh)

**Logging and Output:**

- `log_operation()` - Centralized logging with timestamps and severity levels
- `print_success()`, `print_error()`, `print_warning()`, `print_info()` - Colored console output
- `create_log_entry()` - Write to environment-specific log files

**Validation:**

- `validate_environment()` - Check if environment is valid (staging/production)
- `check_dependencies()` - Verify required tools are installed (aws, jq, openssl, etc.)
- `validate_vpc_configuration()` - Check VPC, subnet, and network configuration
- `validate_certificate()` - Verify certificate validity and expiration

**AWS Utilities:**

- `get_vpc_cidr()` - Get VPC CIDR block
- `get_subnet_id()` - Get subnet ID from VPC
- `check_vpn_endpoint_exists()` - Verify VPN endpoint existence

### Certificate Management (lib/cert_management.sh)

**Key Functions:**

- `initialize_easy_rsa()` - Set up Easy-RSA PKI infrastructure
- `generate_ca_certificate()` - Create CA cert and private key
- `generate_client_cert()` - Generate client certificate and private key
- `sign_csr()` - Sign Certificate Signing Request
- `upload_certs_to_acm()` - Upload certificates to AWS Certificate Manager
- `revoke_certificate()` - Revoke client certificate and update CRL

### Endpoint Management (lib/endpoint_management.sh)

**Key Functions:**

- `create_vpn_endpoint()` - Create new Client VPN endpoint
- `modify_vpn_endpoint()` - Update endpoint configuration
- `delete_vpn_endpoint()` - Remove VPN endpoint and cleanup resources
- `associate_target_network()` - Associate VPN endpoint with VPC subnet
- `create_authorization_rule()` - Create authorization rules for VPN access
- `export_client_config()` - Generate OpenVPN configuration file

### Legacy Functions (Deprecated)

- `aws_with_env_profile()` - Use `aws_with_selected_profile()` instead
- `env_validate_profile_integration()` - Use `validate_profile_account()` instead
- `select_aws_profile_for_environment()` - Use `select_profile_interactive()` instead

## Environment-Specific Behavior

- **Staging Environment**: Standard operations, simplified confirmations, used for development and testing
- **Production Environment**: Enhanced security, multi-step confirmations, audit logging, requires explicit confirmation for all operations
- All operations automatically adapt behavior based on current environment context

## File Structure Impact

Scripts create/modify files in environment-specific locations:

- Certificates: `certs/{staging|production}/`
- Configurations: `configs/{staging|production}/`
- Logs: `logs/{staging|production}/`
- Direct profile selection: No state files (stateless operation)

### Configuration File Organization

Following AWS best practices, the toolkit separates user-configurable settings from auto-generated runtime information:

**User-Configurable Settings (`.env` files):**
- `configs/{staging|production}/{environment}.env` - Environment-specific user settings
- Contains VPC_ID, SUBNET_ID, VPN_CIDR, AWS_REGION, etc.
- Version-controlled and manually editable

**Auto-Generated Runtime Data (`.conf` files):**
- `configs/{staging|production}/vpn_endpoint.conf` - System-generated VPN data
- Contains ENDPOINT_ID, CLIENT_VPN_SECURITY_GROUP_ID, certificate ARNs, etc.
- Automatically managed by the toolkit, not manually editable

This separation ensures:
- Clear distinction between configuration and runtime data
- Prevents accidental modification of auto-generated values
- Simplifies version control and environment management
- Follows AWS infrastructure-as-code best practices

## Security Considerations

### AWS Client VPN Security Group Best Practices

The toolkit implements **dedicated Client VPN security group architecture**, following AWS security best practices for enterprise-grade access control:

- **🛡️ Dedicated Security Groups**: Automatically creates isolated security groups for VPN users (`client-vpn-sg-{environment}`)
- **🔒 Least Privilege Access**: VPN users are segregated from other network traffic with precise service-level access control
- **📋 Centralized Management**: Single security group controls all VPN user access permissions, simplifying administration
- **🎯 Source-Based Authorization**: Uses security group references instead of CIDR blocks for better security and flexibility
- **🔧 Auto-Generated Configuration**: `CLIENT_VPN_SECURITY_GROUP_ID` is automatically saved to `vpn_endpoint.conf` (not user-editable `.env` files)
- **🌐 Environment Isolation**: Separate security groups for staging and production environments
- **📊 Audit-Friendly**: Simplified security auditing and compliance verification through dedicated VPN security groups

### Service Access Control Examples

The toolkit automatically generates AWS CLI commands for secure service access:

```bash
# Database Services (MySQL/RDS, Redis)
aws ec2 authorize-security-group-ingress --group-id sg-503f5e1b --source-group ${CLIENT_VPN_SECURITY_GROUP_ID}

# Big Data Services (HBase, Phoenix Query Server)  
aws ec2 authorize-security-group-ingress --group-id sg-503f5e1b --source-group ${CLIENT_VPN_SECURITY_GROUP_ID}

# Container Services (EKS API Server)
aws ec2 authorize-security-group-ingress --group-id sg-0d59c6a9f577eb225 --source-group ${CLIENT_VPN_SECURITY_GROUP_ID}
```

### Additional Security Measures

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
3. **Admin Signs**: `./admin-tools/sign_csr.sh --upload-s3 username` (just username, no .csr needed)
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
**Solution**: Admin must grant S3 permissions: `./admin-tools/manage_vpn_users.sh add USERNAME`

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
3. **Profile Verification**: Verify AWS profile configuration with `aws configure list-profiles` and `aws sts get-caller-identity --profile PROFILE` before operations
4. **Policy Updates**: Regularly review and update IAM policies in `iam-policies/` directory
5. **Access Logging**: Monitor S3 bucket access logs for suspicious activity

## Important Notes

- **Always verify AWS profile** before operations using `aws sts get-caller-identity --profile PROFILE`
- **Profile Configuration Required**: Each environment needs proper AWS profile configuration in `configs/{env}/{env}.env`
- **Account ID Validation**: Set correct `AWS_ACCOUNT_ID` in each environment config
- **Tool Separation**: Use `setup_csr_s3_bucket.sh` for infrastructure, `manage_vpn_users.sh` for user management
- **Permission Diagnostics**: Use `--check-permissions` options to troubleshoot access issues
- Production operations have additional safety checks and confirmations
- The toolkit is specifically designed for macOS environments
- All scripts use bash and include Chinese language prompts and documentation
- Configuration issues (especially fake endpoint IDs) can be resolved using tools in `admin-tools/tools/`
- Zero-touch workflow requires proper S3 bucket setup and IAM policies
- **Parameter Format**: All JSON parameters must be compact (no spaces) to pass validation patterns (e.g., `{"key":"value"}` not `{"key": "value"}`)
- **Parameter Setup**: The `setup-parameters.sh` script automatically creates parameters in the correct format
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

# Test profile selection with admin tools
./admin-tools/aws_vpn_admin.sh --profile staging --help
./admin-tools/aws_vpn_admin.sh --profile production --help

# View profile status
aws configure list-profiles
aws sts get-caller-identity --profile staging
aws sts get-caller-identity --profile production
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
./admin-tools/sign_csr.sh --upload-s3 testuser    # Just username, no .csr needed

# Test admin can manage users
./admin-tools/manage_vpn_users.sh list
```

The new admin now has full access to:
- Sign and upload certificates via S3
- Manage VPN user permissions
- All environment switching and management operations

## Lambda Function Development

### TypeScript Compilation and Build Process

All Lambda functions use TypeScript and require proper compilation for CDK deployment. The build system uses npm workspaces to manage dependencies across multiple Lambda functions and a shared layer.

**Recommended Build Commands:**
```bash
# From project root
npm run build                    # Build all Lambda functions (runs lambda/npm build)
npm run deploy:staging           # Build and deploy to staging
npm run deploy:both              # Build and deploy to both environments

# From lambda/ directory
cd lambda
npm run build                    # Build shared layer + all functions
npm run build:shared             # Build shared layer only
npm run build:slack-handler      # Build specific function
npm test                         # Run all tests
npm run test:watch               # Run tests in watch mode
npm run test:coverage            # Generate coverage report
```

**Manual Build (if needed):**

```bash
cd lambda/slack-handler && ./build.sh
cd lambda/vpn-control && ./build.sh
cd lambda/vpn-monitor && ./build.sh
cd lambda/shared && npx tsc
```

**Important Build Notes:**

- Each Lambda function has a `build.sh` script that ensures correct directory structure for CDK
- CDK expects `dist/index.js` but TypeScript creates nested directories - build scripts handle this
- The shared layer (`lambda/shared/`) compiles to `dist/` and is deployed as a Lambda Layer
- **Troubleshooting**: If npm cache issues occur, use `sudo chown -R $(whoami):$(id -gn) ~/.npm`
- Always use `./scripts/deploy.sh` rather than manual `cdk deploy` to ensure proper compilation
- The deploy script automatically builds all functions before CDK deployment

**Lambda Directory Structure:**
```
lambda/
├── shared/                    # Shared utilities (Lambda Layer)
│   ├── logger.ts             # Centralized logging
│   ├── slack.ts              # Slack API utilities
│   ├── stateStore.ts         # DynamoDB state management
│   ├── types.ts              # Shared TypeScript types
│   ├── vpnManager.ts         # VPN control operations
│   └── dist/                 # Compiled layer (deployed to Lambda)
├── slack-handler/            # Slack command endpoint
│   ├── index.ts              # Main handler
│   ├── build.sh              # Build script
│   └── dist/index.js         # Compiled output (required by CDK)
├── vpn-control/              # VPN control operations
│   ├── index.ts
│   ├── build.sh
│   └── dist/index.js
├── vpn-monitor/              # Idle timeout monitoring
│   ├── index.ts
│   ├── build.sh
│   └── dist/index.js
├── __tests__/                # Jest unit tests
└── package.json              # Workspace configuration
```

### CDK Stack Structure

The infrastructure is defined in AWS CDK (TypeScript) with two main stacks:

**Main Stack** (`cdklib/lib/vpn-automation-stack.ts`):
- API Gateway REST API with Slack webhook endpoint
- Lambda functions (slack-handler, vpn-control, vpn-monitor)
- Lambda Layer with shared utilities
- EventBridge rule for 5-minute monitoring interval
- DynamoDB table for VPN state tracking
- IAM roles and permissions

**Secure Parameters Stack** (`cdklib/lib/secure-parameter-management-stack.ts`):
- SSM Parameter Store parameters (with KMS encryption)
- Slack tokens, VPN endpoint IDs, configuration
- Deployed separately with `--secure-parameters` flag

**Deployment Commands:**

```bash
# Deploy everything with SSM parameters
./scripts/deploy.sh both --secure-parameters

# Deploy specific environment
./scripts/deploy.sh staging --staging-profile default
./scripts/deploy.sh production --production-profile prod

# Check deployment status
./scripts/deploy.sh status

# View CDK diff before deployment
cd cdklib && cdk diff VpnAutomation-staging
```

### Lambda and SSM Configuration Strategy

This serverless application uses a best-practice approach to configuration, separating the function's identity from its operational parameters.

- **SSM Parameter Store for Dynamic Configuration**: All operational parameters (VPN endpoint IDs, idle timeouts, Slack tokens) are stored in SSM. Lambda functions fetch these values **at runtime** on every invocation. This allows for real-time configuration changes without needing to redeploy the function.

- **Lambda Environment Variables for Static Context**: Environment variables (e.g., `APP_ENV`) are set during deployment to give the function its **bootstrap identity**. The function reads `process.env.APP_ENV` (`staging` or `production`) to know which set of SSM parameters to query. This makes the Lambda code itself environment-agnostic.

**SSM Parameter Hierarchy:**

```
/vpn/{environment}/
├── slack/
│   ├── bot_token           # Slack bot OAuth token
│   ├── signing_secret      # Request signature verification
│   └── api_key             # API key for Lambda invocations
├── vpn/
│   ├── endpoint_id         # Client VPN endpoint ID
│   └── region              # AWS region
├── cost/
│   └── optimization_config # { "idleTimeoutMinutes": 54 }
└── cross_account/
    └── production_api_url  # Staging-to-production routing (staging only)
```

### Cost Optimization: Dual-Layer Idle Detection

The VPN system uses a dual-layer idle detection approach for cost optimization:

**Key Optimization Details:**
- **Client-Side Idle Timeout**: 100 minutes with 10KB traffic threshold in OpenVPN config
- **Server-Side Monitoring**: VPN Monitor Lambda runs every 5 minutes via CloudWatch Events
- **Traffic-Based Detection**: Only actual data traffic resets the timer (keepalive packets ignored)
- **Cost Impact**: Prevents charges from forgotten VPN connections

**Implementation Locations:**
```bash
# OpenVPN client config (primary - client-side)
inactive 6000 10000  # 100 minutes, 10KB threshold

# Lambda source code (server-side monitoring)
const IDLE_MINUTES = Number(process.env.IDLE_MINUTES || 54);

// SSM Parameter Store (runtime configuration)
/vpn/{environment}/cost/optimization_config: { "idleTimeoutMinutes": 54 }
```

**Configuration Hierarchy:**
1. **CDK Environment Variable** (primary): Set during deployment
2. **SSM Parameter Store** (runtime): Can be updated without redeployment  
3. **Source Code Default** (fallback): Used if environment variable missing

This optimization ensures 100% cost efficiency while maintaining system reliability and user experience.

### Slack App Request URL Maintenance

The Slack App's Request URL for the `/vpn` command is highly stable due to the smart-routing architecture. It only needs to be updated in one specific scenario:

- **When to Update**: You MUST update the URL if the **`staging` API Gateway is completely destroyed and recreated** (e.g., via `cdk destroy` followed by a new deployment). This action generates a new, unique API Gateway URL.

- **When NOT to Update**: You DO NOT need to update the URL for most common operations, including:
    - Redeploying Lambda function code.
    - Redeploying the `production` environment stack.
    - Changing any configuration values in SSM.

**Update Process**:
1. Run `./scripts/deploy.sh status` to get the new `staging` API Gateway URL.
2. Go to your Slack App settings (`https://api.slack.com/apps/.../slash-commands`), edit the `/vpn` command, and paste the new URL into the **Request URL** field.

## Recent Updates (January 2026)

### Automated VPN Schedule & Enhanced Idle Detection

**Weekday Auto-Open (10:00 AM Taiwan Time):**
- VPN endpoint automatically opens at 10:00 AM on weekdays (Mon-Fri)
- EventBridge scheduled rule triggers vpn-control Lambda
- Slack notification sent when VPN auto-opens
- No manual intervention needed for daily VPN startup

**Business Hours Protection (10:00 AM - 5:00 PM):**
- Server-side auto-close is disabled during business hours
- Prevents accidental VPN closure during work time
- After 5:00 PM, idle detection resumes

**Weekend Soft-Close (Friday 8:00 PM):**
- VPN automatically closes on Friday evening (soft close)
- Respects active connections - if users are connected, delays 30 minutes and retries
- Continues retrying every 30 minutes until all connections end
- Slack notifications include: connection count, usernames, next retry time
- Prevents weekend charges from forgotten connections

**100-Minute Traffic-Based Client Idle Timeout:**
- OpenVPN client config uses `inactive 6000 10000` (100 minutes, 10KB threshold)
- Traffic threshold ensures keepalive packets don't reset the timer
- Only real usage (SSH, HTTP, database queries) resets the 100-minute timer

**Daily Schedule Flow (Weekdays):**
```
10:00 - VPN auto-opens (EventBridge trigger)
10:00-17:00 - Business hours protection (no auto-close)
17:00 - Server idle detection starts
17:00 + 100 min = 18:40 - Client auto-disconnects (if no traffic)
18:40 + 54 min = 19:34 - Server auto-closes endpoint (if no connections)
```

**Weekly Schedule Flow:**
```
Mon-Thu: 10:00 open → idle detection closes (typically ~19:30)
Friday:  10:00 open → 20:00 soft-close (respects active connections)
Sat-Sun: Closed (no auto-open)
```

**Soft Close Behavior:**
- When scheduled close triggers and users are connected:
  1. Delays 30 minutes, sends Slack notification with usernames
  2. Retries check every 30 minutes
  3. Closes only when no active connections remain
  4. SSM parameter stores pending close state
  5. vpn-monitor Lambda handles retries (every 5 min check)

**Files Updated:**
- `lambda/vpn-control/index.ts` - Auto-open and soft-close handlers
- `lambda/vpn-monitor/index.ts` - Business hours + pending close retry
- `lambda/shared/vpnManager.ts` - Connection details with usernames
- `lambda/shared/stateStore.ts` - deleteParameter for pending close
- `lambda/shared/slack.ts` - Updated help text with soft close info
- `lambda/shared/types.ts` - VpnConnectionDetail interface
- `cdklib/lib/vpn-automation-stack.ts` - EventBridge rules (open, weekend soft-close)
- `team_member_setup.sh` - Client config (100-min idle)
- `lib/endpoint_management.sh` - Admin config

**Cost Structure (AWS Client VPN us-east-1):**

| 計費項目 | 費率 | 說明 |
|---------|------|------|
| Endpoint Association | $0.10/hour/subnet | 固定成本，與使用者數無關 |
| Client Connection | $0.05/hour/connection | 按同時連線數計費 |

**成本計算公式：**
```
每日成本 = ($0.10 × 運行小時 × subnet數) + ($0.05 × 運行小時 × 平均同時連線數)
每月成本 = 每日成本 × 22 工作日
```

**Quick Cost Reference (typical ~10hr/day, 1 subnet):**

| 同時連線數 | 每日成本 | 每月成本 (22天) | 適用情境 |
|-----------|---------|----------------|---------|
| 1 | $1.50 | $33 / NT$1,050 | 單人或輪流使用 |
| 2 | $2.00 | $44 / NT$1,400 | 小團隊 (4人以下) |
| 3 | $2.50 | $55 / NT$1,750 | 中型團隊 (6人以下) |
| 4 | $3.00 | $66 / NT$2,100 | 較大團隊 (8人以下) |
| 5 | $3.50 | $77 / NT$2,450 | 大型團隊 (10人以下) |

**Current Estimate (4 users, 2 concurrent avg):**
- Typical daily: ~$2.00 (endpoint ~10hr + 2 connections)
- Monthly (22 workdays): ~$44 / NT$1,400

**Cost Optimization Features:**
- Weekend soft-close: Saves ~$4.80/weekend (48hr × $0.10), respects active connections
- Idle detection: Closes VPN when no traffic (client 100min + server 54min)
- Soft close: Never interrupts active users, delays until connections end
- Estimated monthly savings vs 24/7: ~$48 (66% reduction)

**Comparison with Pritunl (t3.medium):**
- Pritunl: ~$20-25/month (固定成本，不隨使用者數增加)
- AWS VPN 損益平衡點：約 1 位同時連線時成本相近
- 混合方案：Staging 用 Pritunl ($15), Production 用 AWS VPN ($44) = $59/month
