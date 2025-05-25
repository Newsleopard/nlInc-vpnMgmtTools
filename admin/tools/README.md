# VPN Management Tools

This directory contains specialized tools for VPN management and troubleshooting.

## Available Tools

### 🔍 `debug_vpn_creation.sh`
**Purpose**: Comprehensive VPN endpoint creation diagnostic tool

**Features**:
- AWS CLI configuration validation
- VPC/Subnet accessibility checks  
- Certificate status verification
- Existing endpoint conflict detection
- JSON parameter format validation
- AWS CLI command preview

**Usage**:
```bash
cd /path/to/nlInc-vpnMgmtTools
./admin/tools/debug_vpn_creation.sh
```

**When to use**:
- VPN endpoint creation fails
- AWS CLI returns exit code 254
- Need to validate configuration before creation
- Troubleshooting certificate or network issues

### 🔧 `fix_vpn_config.sh`
**Purpose**: Automated configuration repair tool

**Features**:
- Automatic subnet configuration fixes
- Certificate validity checks and replacement
- Conflicting resource cleanup
- Configuration backup and validation

**Usage**:
```bash
cd /path/to/nlInc-vpnMgmtTools
./admin/tools/fix_vpn_config.sh
```

**When to use**:
- Subnet IDs become invalid
- Certificates expire or become inaccessible
- Conflicting VPN endpoints exist
- Need to clean up orphaned CloudWatch log groups

## Installation

These tools are ready to use and require no additional installation. They depend on:
- AWS CLI configured with appropriate permissions
- jq (JSON processor) - usually pre-installed on macOS
- Bash shell

## Configuration

Both tools read configuration from:
```
configs/staging/vpn_endpoint.conf
```

Ensure this file contains valid:
- VPC_ID
- SUBNET_ID  
- VPN_CIDR
- SERVER_CERT_ARN
- CLIENT_CERT_ARN
- VPN_NAME

## Exit Codes

- **0**: Success
- **1**: Configuration or validation error
- **254**: AWS CLI parameter parsing error (the original issue these tools were designed to fix)

## Troubleshooting

If you encounter issues:

1. Run the diagnostic tool first: `./admin/tools/debug_vpn_creation.sh`
2. If issues are found, run the fix tool: `./admin/tools/fix_vpn_config.sh`
3. Re-run diagnostics to confirm fixes
4. Proceed with normal VPN endpoint creation

## Maintenance

- Review and update certificate ARNs when certificates are renewed
- Update subnet IDs if network topology changes
- Clean up old backup configuration files periodically

## Related Files

- Main VPN creation logic: `lib/endpoint_creation.sh`
- Configuration templates: `configs/template.env.example`
- Main setup script: `team_member_setup.sh`
