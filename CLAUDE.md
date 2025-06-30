# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is an AWS Client VPN dual-environment management toolkit designed for macOS, developed by [Newsleopard 電子豹](https://newsleopard.com). It provides a comprehensive solution for managing VPN endpoints, certificates, and user access across Staging and Production environments with strict environment isolation and enhanced security for production operations.

**Original Author**: [CT Yeh](https://github.com/ctyeh) (ct@newsleopard.tw)  
**Company**: [Newsleopard 電子豹](https://newsleopard.com)  
**Status**: Reference Implementation (Open Source)

## Key Architecture Components

- **Dual Environment Architecture**: Complete separation between Staging (🟡) and Production (🔴) environments
- **Direct Profile Selection**: Explicit AWS profile selection with cross-account validation (replaces stateful environment switching)
- **Modular Library Design**: Core functionality split across `lib/` directory with specialized libraries
- **Profile Selector Library**: New `lib/profile_selector.sh` provides intelligent profile detection and interactive selection
- **Enhanced Security**: Cross-account validation prevents wrong-environment operations, with enhanced production confirmations

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

The `team_member_setup.sh` script automatically configures advanced DNS, routing, and cost optimization features in the generated OpenVPN configuration files to ensure seamless access to AWS services through the VPN tunnel.

#### Cost Optimization Configuration

**Automatic Idle Timeout (54 minutes):**
```
inactive 3240  # 54 minutes in seconds
```

**Benefits:**
- **Cost Savings**: Automatically disconnects idle VPN sessions at 54 minutes, perfectly aligned with AWS hourly billing
- **Mathematical Guarantee**: 54 minutes + 5-minute detection delay = 59 minutes maximum (within first billing hour)
- **User Experience**: Sufficient time for active work sessions while preventing forgotten connections
- **AWS Billing Optimization**: Prevents $0.10/hour charges from extending into second billing hour

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
- `profile_selector.sh` - **NEW** Direct AWS profile selection and validation (replaces env_manager.sh)
- `env_core.sh` - Legacy profile utilities (minimal, mostly deprecated)
- `aws_setup.sh` - AWS CLI setup and configuration
- `cert_management.sh` - Certificate generation and management
- `endpoint_management.sh` - VPN endpoint operations
- `endpoint_creation.sh` - VPN endpoint creation logic
- `enhanced_confirmation.sh` - Security confirmation prompts

### New Profile Selection Functions (lib/profile_selector.sh)
- `select_and_validate_profile()` - Main function for profile selection and validation
- `aws_with_selected_profile()` - Wrapper for AWS CLI commands with selected profile
- `detect_available_profiles()` - Scan and detect available AWS profiles
- `map_profile_to_environment()` - Map profile names to environments using naming conventions
- `validate_profile_account()` - Cross-account validation with account ID verification
- `select_profile_interactive()` - Interactive profile selection with environment recommendations
- `load_environment_config()` - Load environment-specific configuration files

### Legacy Functions (deprecated)
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
./admin-tools/sign_csr.sh --upload-s3 test.csr

# Test admin can manage users
./admin-tools/manage_vpn_users.sh list
```

The new admin now has full access to:
- Sign and upload certificates via S3
- Manage VPN user permissions
- All environment switching and management operations

## Lambda Function Development

### TypeScript Compilation for CDK

All Lambda functions use TypeScript and require proper compilation for CDK deployment:

**Build Process:**
```bash
# Manual build (if needed)
cd lambda/slack-handler && ./build.sh
cd lambda/vpn-control && ./build.sh
cd lambda/vpn-monitor && ./build.sh
cd lambda/shared && npx tsc

# Automatic build during deployment
./scripts/deploy.sh staging  # Automatically builds all Lambda functions and shared layer
```

**Important Notes:**
- Each Lambda function has a `build.sh` script that ensures TypeScript compiles to the correct directory structure for CDK
- CDK expects `dist/index.js` but TypeScript creates nested directories like `dist/slack-handler/index.js`
- The shared layer compiles correctly to `dist/` without needing a build script
- **Note**: If npm cache issues occur during builds, use `sudo chown -R $(whoami):$(id -gn) ~/.npm` to fix permissions
- Source code changes are automatically applied during deployment via CDK environment variables
- The deploy script now automatically builds all Lambda functions and the shared layer before CDK deployment
- Always use the deploy script rather than manual CDK commands to ensure proper compilation

**File Structure After Build:**
```
lambda/
├── slack-handler/dist/
│   ├── index.js          # Main handler (required by CDK)
│   ├── index.d.ts        # TypeScript declarations
│   └── shared/           # Compiled shared modules
├── vpn-control/dist/
│   ├── index.js          # Main handler (required by CDK)
│   ├── index.d.ts        # TypeScript declarations
│   └── shared/           # Compiled shared modules
├── vpn-monitor/dist/
│   ├── index.js          # Main handler (required by CDK)
│   ├── index.d.ts        # TypeScript declarations
│   └── shared/           # Compiled shared modules
└── shared/dist/          # Lambda Layer content
    ├── logger.js
    ├── slack.js
    ├── stateStore.js
    ├── types.js
    └── vpnManager.js
```

### Lambda and SSM Configuration Strategy

This serverless application uses a best-practice approach to configuration, separating the function's identity from its operational parameters.

- **SSM Parameter Store for Dynamic Configuration**: All operational parameters (VPN endpoint IDs, idle timeouts, Slack tokens) are stored in SSM. Lambda functions fetch these values **at runtime** on every invocation. This allows for real-time configuration changes without needing to redeploy the function.

- **Lambda Environment Variables for Static Context**: Environment variables (e.g., `APP_ENV`) are set during deployment to give the function its **bootstrap identity**. The function reads `process.env.APP_ENV` (`staging` or `production`) to know which set of SSM parameters to query. This makes the Lambda code itself environment-agnostic.

### Cost Optimization: 54-Minute Idle Threshold (Updated June 2025)

The VPN monitoring system has been optimized for maximum cost efficiency with AWS's hourly billing model:

**Key Optimization Details:**
- **Idle Threshold**: Updated from 60 minutes to **54 minutes** for optimal cost savings
- **Monitoring Interval**: VPN Monitor Lambda runs every 5 minutes via CloudWatch Events
- **Mathematical Guarantee**: 54 minutes + 5-minute detection delay = 59 minutes maximum (within first billing hour)
- **Cost Impact**: Prevents potential $0.10 charges from crossing billing hour boundaries

**Implementation Locations:**
```typescript
// Lambda source code (fallback defaults)
const IDLE_MINUTES = Number(process.env.IDLE_MINUTES || 54);

// CDK deployment (primary configuration)
IDLE_MINUTES: '54'

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

## Recent Updates (June 2025)

### Cost Optimization Enhancement

**54-Minute Idle Threshold Implementation:**
- Updated all Lambda source code from 60-minute to 54-minute default idle threshold
- Maintained consistency across CDK deployment, SSM parameters, and source code
- Updated test files and documentation to reflect the optimization
- Provides mathematical guarantee of cost savings with AWS hourly billing model

**Files Updated:**
- `lambda/vpn-monitor/index.ts` - Main monitoring logic
- `lambda/shared/stateStore.ts` - Default configuration values
- `lambda/shared/slack.ts` - Help text and notifications
- All test files in `lambda/__tests__/` - Test configurations
- `README.md` - Documentation updates
- `CLAUDE.md` - Technical documentation

**Impact:**
- 100% guarantee of VPN closure within first billing hour
- Eliminates risk of $0.10 additional charges from timing edge cases
- Maintains user experience while maximizing cost efficiency
- Annual savings potential: $684-$1,368 across dual environments

This optimization builds on the existing cost management system while providing mathematical certainty for cost control in AWS's hourly billing model.
