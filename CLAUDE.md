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
./admin/aws_vpn_admin.sh

# Team member setup
./team_member_setup.sh

# Revoke user access
./admin/revoke_member_access.sh

# Employee offboarding
./admin/employee_offboarding.sh
```

### Diagnostic and Repair Tools

```bash
# Debug VPN creation issues
./admin/tools/debug_vpn_creation.sh

# Fix common configuration problems
./admin/tools/fix_vpn_config.sh

# Validate and auto-fix configurations
./admin/tools/validate_config.sh

# Fix endpoint ID issues
./admin/tools/fix_endpoint_id.sh
```

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

- Production environment operations require enhanced confirmation
- Certificate private keys have restricted file permissions (600)
- Environment isolation prevents cross-contamination
- All admin operations are logged with timestamps
- AWS credentials are managed per environment (staging uses default profile, production uses prod profile)

## Dependencies

The toolkit requires and will auto-install:

- Homebrew (macOS package manager)
- AWS CLI
- jq (JSON processor)
- Easy-RSA (certificate management)
- OpenSSL

## Testing

Currently no automated test framework is present. The `tests/` directory exists but is empty. Manual testing is performed through the diagnostic tools in `admin/tools/`.

## Important Notes

- Always verify current environment before operations using `./vpn_env.sh status`
- Production operations have additional safety checks and confirmations
- The toolkit is specifically designed for macOS environments
- All scripts use bash and include Chinese language prompts and documentation
- Configuration issues (especially fake endpoint IDs) can be resolved using tools in `admin/tools/`
