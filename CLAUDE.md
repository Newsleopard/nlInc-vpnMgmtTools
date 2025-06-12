# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is an AWS Client VPN dual-environment management toolkit designed for macOS. It provides a comprehensive solution for managing VPN endpoints, certificates, and user access across Staging and Production environments with strict environment isolation and enhanced security for production operations.

## Key Architecture Components

- **Dual Environment Architecture**: Complete separation between Staging (🟡) and Production (🔴) environments
- **Modular Library Design**: Core functionality split across `lib/` directory with specialized libraries
- **Environment Manager**: Centralized environment switching and health monitoring via `lib/env_manager.sh`
- **Enhanced Security**: Production operations require multi-factor confirmation and additional security checks

## Environment Configuration

Each environment has its own configuration structure:

- `configs/staging/staging.env` - Staging environment settings
- `configs/production/production.env` - Production environment settings  
- `.current_env` - Tracks currently active environment
- Environment-specific directories for certs, logs, and user configs

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

### Secure CSR Management (Zero-Touch Workflow)

```bash
# Setup S3 bucket for zero-touch CSR exchange
./admin-tools/setup_csr_s3_bucket.sh --publish-assets    # Create bucket and publish initial assets
./admin-tools/setup_csr_s3_bucket.sh --create-users     # Also create IAM policies

# Publish/update public assets (CA cert and endpoint configs)
./admin-tools/publish_endpoints.sh                      # Publish all environments
./admin-tools/publish_endpoints.sh -e production        # Publish specific environment

# Sign individual CSR with zero-touch delivery
./admin-tools/sign_csr.sh --upload-s3 user.csr         # Sign and auto-upload to S3
./admin-tools/sign_csr.sh -e production user.csr       # Traditional local signing

# Batch process CSRs from S3 (Admin efficiency)
./admin-tools/process_csr_batch.sh download -e production    # Download CSRs from S3
./admin-tools/process_csr_batch.sh process -e production     # Sign all CSRs
./admin-tools/process_csr_batch.sh upload --auto-upload      # Upload certificates to S3
./admin-tools/process_csr_batch.sh monitor -e staging        # Auto-monitor and process

# S3 bucket management
./admin-tools/setup_csr_s3_bucket.sh --list-users      # List IAM users with CSR policies
./admin-tools/setup_csr_s3_bucket.sh --cleanup         # Remove bucket and policies
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

- `core_functions.sh` - Basic utilities, logging, validation functions
- `env_manager.sh` - Environment switching and health checks
- `aws_setup.sh` - AWS CLI setup and configuration
- `cert_management.sh` - Certificate generation and management
- `endpoint_management.sh` - VPN endpoint operations
- `endpoint_creation.sh` - VPN endpoint creation logic
- `enhanced_confirmation.sh` - Security confirmation prompts

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

Currently no automated test framework is present. The `tests/` directory exists but is empty. Manual testing is performed through the diagnostic tools in `admin-tools/tools/`.

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

## Important Notes

- Always verify current environment before operations using `./vpn_env.sh status`
- Production operations have additional safety checks and confirmations
- The toolkit is specifically designed for macOS environments
- All scripts use bash and include Chinese language prompts and documentation
- Configuration issues (especially fake endpoint IDs) can be resolved using tools in `admin-tools/tools/`
- Zero-touch workflow requires proper S3 bucket setup and IAM policies
