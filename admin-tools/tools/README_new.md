# VPN Management Tools

This directory contains specialized tools for VPN management and troubleshooting.

## Available Tools

### 🆔 `fix_endpoint_id.sh` ⭐ NEW

**Purpose**: Automated VPN endpoint ID mismatch repair tool

**Features**:

- Automatically detect AWS authentication status
- List all available VPN endpoints in the region
- Validate endpoint ID in configuration files
- Interactive endpoint selection interface
- Automatic configuration backup and update
- Verify repair results

**Usage**:

```bash
cd /path/to/nlInc-vpnMgmtTools
# Ensure correct environment is set
./vpn_env.sh switch staging  # or production
# Run the repair tool
./admin/tools/fix_endpoint_id.sh
```

**When to use**:

- Getting "InvalidClientVpnEndpointId.NotFound" errors
- Configuration file endpoint ID doesn't match actual AWS resources
- Need to re-map to correct endpoint ID after manual changes

### 🔍 `simple_endpoint_fix.sh` ⭐ NEW

**Purpose**: Simplified diagnostic tool and manual repair guidance

**Features**:

- Display current configuration status
- Provide detailed manual repair steps
- List common diagnostic commands
- Automatic configuration file backup

**Usage**:

```bash
./admin/tools/simple_endpoint_fix.sh
```

**When to use**:

- Quick diagnosis of endpoint ID issues
- Get manual repair step guidance
- Network restrictions prevent automatic repair

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

### 🔧 `complete_vpn_setup.sh`

**Purpose**: Complete VPN endpoint setup and configuration tool

**Features**:

- Check endpoint status
- Configure subnet associations
- Set up authorization rules
- Validate setup completeness

## Quick Problem Resolution Guide

### Problem 1: "InvalidClientVpnEndpointId.NotFound" Error

**Symptoms**: Getting endpoint ID not found error when running VPN management operations

**Solution**:

1. Use `fix_endpoint_id.sh` for automatic repair
2. Or use `simple_endpoint_fix.sh` for manual repair guidance

### Problem 2: Endpoint exists but operations fail

**Symptoms**: Endpoint ID is correct but operations still fail

**Solution**:

1. Check AWS permissions
2. Verify endpoint status (available/pending etc.)
3. Use `complete_vpn_setup.sh` to reconfigure

### Problem 3: Configuration file corruption

**Symptoms**: Error loading configuration file

**Solution**:

1. Restore from backup files (all tools create automatic backups)
2. Use `fix_vpn_config.sh` to repair configuration

## Best Practices

1. **Always backup**: All tools automatically create backups, please preserve them
2. **Verify environment**: Ensure correct environment is set before running tools
3. **Check permissions**: Ensure sufficient AWS permissions
4. **Step by step**: Recommended to execute repair steps in order
5. **Verify results**: Use system health check to verify after repairs

## Installation

These tools are ready to use and require no additional installation. They depend on:

- AWS CLI configured with appropriate permissions
- jq (JSON processor) - usually pre-installed on macOS
- Bash shell

## Configuration

Both tools read configuration from:

```bash
configs/staging/staging.env
# or
configs/production/production.env
```

Ensure this file contains valid:

- VPC_ID
- SUBNET_ID  
- VPN_CIDR
- SERVER_CERT_ARN
- CLIENT_CERT_ARN
- VPN_NAME
- ENDPOINT_ID

## Exit Codes

- **0**: Success
- **1**: Configuration or validation error
- **254**: AWS CLI parameter parsing error (the original issue these tools were designed to fix)

## Troubleshooting

If you encounter issues:

1. Run the diagnostic tool first: `./admin/tools/debug_vpn_creation.sh`
2. If endpoint ID issues are found, run: `./admin/tools/fix_endpoint_id.sh`
3. If other issues are found, run the fix tool: `./admin/tools/fix_vpn_config.sh`
4. Re-run diagnostics to confirm fixes
5. Proceed with normal VPN endpoint creation

## Common Commands for Manual Diagnosis

```bash
# Check AWS authentication
aws sts get-caller-identity

# List all VPN endpoints in region
aws ec2 describe-client-vpn-endpoints --region us-east-1

# Check specific endpoint
aws ec2 describe-client-vpn-endpoints --client-vpn-endpoint-ids cvpn-endpoint-xxxxx --region us-east-1

# Test endpoint connectivity
aws ec2 describe-client-vpn-target-networks --client-vpn-endpoint-id cvpn-endpoint-xxxxx --region us-east-1
```

## Maintenance

- Review and update certificate ARNs when certificates are renewed
- Update subnet IDs if network topology changes
- Clean up old backup configuration files periodically
- Monitor AWS CloudWatch logs for VPN connection issues

## Security Considerations

- Tools automatically backup configuration files, please periodically clean old backups
- Avoid direct configuration modifications in production, test in staging first
- Repair operations may temporarily interrupt VPN service

## Related Files

- Main VPN creation logic: `lib/endpoint_creation.sh`
- Configuration templates: `configs/template.env.example`
- Main setup script: `team_member_setup.sh`
- Core functions: `lib/core_functions.sh`
