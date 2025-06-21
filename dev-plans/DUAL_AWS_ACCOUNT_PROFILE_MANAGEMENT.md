# Dual AWS Account Profile Management Plan

## Overview

This document outlines the comprehensive plan for implementing dual AWS account profile management in the VPN management toolkit. The system will handle two separate AWS accounts (staging and production environments) where every team member has two local AWS profiles, with intelligent profile awareness and validation.

## Related Documentation

- **Zero-Touch Workflow**: See `ZERO_TOUCH_WORKFLOW_REFERENCE.md` for the technical specification of the implemented zero-touch VPN workflow that this dual AWS account system will enhance.
- **Environment Management**: This plan builds upon the existing environment management system documented in `CLAUDE.md`.

## Current State Analysis

### Existing Architecture
- **Single Environment Focus**: Current scripts assume one active AWS environment
- **Basic Profile Support**: Limited AWS profile handling via `--profile` parameters
- **Environment Detection**: Basic environment detection from CA certificates and file paths
- **Configuration Management**: Environment-specific configurations in `configs/staging/` and `configs/production/`
- **Environment Manager Integration**: Existing `lib/env_manager.sh` system used by admin tools
- **Partial Implementation**: `lib/env_core.sh` already contains some profile detection functions

### Current Implementation Status
**Already Implemented:**
- `detect_available_aws_profiles()` in `lib/env_core.sh` - Lists and validates AWS profiles
- `detect_environment_from_profile()` - Maps profile names to environments  
- `validate_aws_profile_config()` - Validates profile configuration
- Profile selection in `team_member_setup.sh` using `SELECTED_AWS_PROFILE`
- Environment manager system in admin tools

**Missing Implementation:**
- Standardized profile variable naming across all scripts
- Profile persistence in configuration files
- AWS CLI command updates with `--profile` parameter
- Integration between profile management and environment manager
- S3 zero-touch workflow profile awareness
- Cross-account validation and safety measures

### Key Files to Modify
1. **`team_member_setup.sh`** - Main user-facing script requiring profile intelligence
2. **`lib/env_core.sh`** - Core environment management functions
3. **`admin-tools/aws_vpn_admin.sh`** - Admin console requiring profile awareness
4. **`admin-tools/sign_csr.sh`** - CSR signing with environment-specific profiles
5. **`admin-tools/setup_csr_s3_bucket.sh`** - S3 bucket setup with profile validation
6. **`admin-tools/revoke_member_access.sh`** - Member access revocation with profile awareness
7. **`admin-tools/employee_offboarding.sh`** - Employee offboarding with cross-account cleanup
8. **`admin-tools/publish_endpoints.sh`** - Endpoint publishing with environment-specific profiles

## Technical Requirements

### 1. AWS Profile Structure
Each team member will maintain two AWS profiles:
```
~/.aws/credentials:
[default]  # or [staging]
aws_access_key_id = AKIA...
aws_secret_access_key = ...

[production]  # or [prod]
aws_access_key_id = AKIA...
aws_secret_access_key = ...
```

### 2. Profile Naming Conventions
- **Staging Environment**: `default`, `staging`, or `stage`
- **Production Environment**: `production`, `prod`, or `prd`
- **Auto-detection**: Smart mapping based on common naming patterns

### 3. Environment-Profile Mapping
```
staging → [default, staging, stage]
production → [production, prod, prd]
```

### 4. Standardized Variable Naming
- **Primary**: `AWS_PROFILE` (standard AWS CLI environment variable)
- **Environment Override**: `ENV_AWS_PROFILE` (environment-specific override)
- **Legacy Support**: `SELECTED_AWS_PROFILE` (backward compatibility)

### 5. Profile Detection Priority Order
1. Existing configuration files (`configs/staging/staging.env`, `configs/production/production.env`)
2. AWS CLI default profile
3. Profile name pattern matching
4. User manual selection
5. Fallback to environment-based defaults

## Implementation Plan

### Phase 1: Core Profile Management Functions

#### 1.1 Enhanced Profile Detection (`lib/env_core.sh`)
```bash
# Enhanced existing functions:
detect_available_aws_profiles()          # Already exists - enhance with validation
detect_environment_from_profile()        # Already exists - enhance mapping logic
validate_aws_profile_config()            # Already exists - add environment validation

# New functions to add:
map_environment_to_profiles()
validate_profile_environment_match()
select_aws_profile_for_environment()
load_profile_from_config()
save_profile_to_config()

# Integration functions:
integrate_with_env_manager()
aws_with_profile()                       # Wrapper for AWS CLI commands
```

**Features:**
- Scan `~/.aws/credentials` for available profiles (✓ exists)
- Map profile names to environments using naming conventions (✓ exists, needs enhancement)
- Validate profile permissions for target environment (enhance existing)
- Interactive profile selection with confirmation (✓ exists)
- Integration with existing environment manager system
- AWS CLI command wrapper for consistent profile usage

#### 1.2 Enhanced Profile Validation System
```bash
# Enhanced validation functions:
validate_aws_profile_config()           # Already exists - enhance
test_profile_permissions()
verify_profile_environment_access()
validate_profile_matches_environment()  # Cross-account validation
validate_s3_profile_access()           # S3-specific validation
```

**Validation Checks:**
- Profile exists in AWS credentials (✓ exists)
- Profile has valid AWS credentials (✓ exists)
- Profile has permissions for target environment operations
- Profile can access environment-specific resources (S3 buckets, VPN endpoints)
- Cross-account access prevention
- Environment-specific permission validation
- S3 bucket access validation for zero-touch workflow

**Cross-Account Validation:**
```bash
validate_profile_matches_environment() {
    local profile=$1
    local environment=$2
    local account_id=$(aws sts get-caller-identity --profile "$profile" --query Account --output text)
    
    case "$environment" in
        staging)
            [[ "$account_id" == "$STAGING_ACCOUNT_ID" ]] || return 1
            ;;
        production)
            [[ "$account_id" == "$PRODUCTION_ACCOUNT_ID" ]] || return 1
            ;;
    esac
}
```

#### 1.3 Smart Profile Selection Logic
```bash
# Enhanced selection algorithm:
1. Check existing configuration files for saved profile
2. Detect target environment (staging/production)
3. Scan available AWS profiles
4. Map profiles to environments based on naming conventions
5. Validate profile permissions and cross-account access
6. Present user with intelligent defaults
7. Allow manual override if needed
8. Save selection to environment configuration
```

#### 1.4 Environment Manager Integration
```bash
# Integration with lib/env_manager.sh:
integrate_profile_with_env_manager() {
    local environment=$1
    local profile=$2
    
    # Update environment manager with profile information
    env_set_profile "$environment" "$profile"
    
    # Validate integration
    env_validate_profile_integration "$environment" "$profile"
}
```

#### 1.5 AWS CLI Wrapper System
```bash
# Consistent AWS CLI usage across all scripts:
aws_with_profile() {
    local profile="${AWS_PROFILE:-${ENV_AWS_PROFILE:-default}}"
    aws "$@" --profile "$profile"
}

# Usage example:
aws_with_profile ec2 describe-client-vpn-endpoints --region "$AWS_REGION"
```

### Phase 2: User Experience Enhancements

#### 2.1 Interactive Profile Selection
When multiple valid profiles exist for an environment:
```
🔧 AWS Profile Selection for Production Environment
═══════════════════════════════════════════════════

Available profiles for production environment:
  1. production (✓ validated)
  2. prod-admin (✓ validated)  
  3. my-prod-profile (✓ validated)

Recommended: production (matches naming convention)

Please select a profile [1-3]: 1
✓ Selected profile: production
```

#### 2.2 Environment Safety Warnings
For production environment operations:
```
⚠️  PRODUCTION ENVIRONMENT WARNING ⚠️
══════════════════════════════════════

You are about to perform operations in the PRODUCTION environment.
This will affect live systems and real user data.

Environment: 🔴 Production
AWS Profile: production
AWS Account: 123456789012
Region: us-east-1

Are you absolutely sure you want to continue? (type 'CONFIRM'): CONFIRM
```

#### 2.3 Profile Persistence
- Save selected profile in environment-specific configuration
- Remember user preferences for future sessions
- Allow easy profile switching

### Phase 3: Script-Specific Implementations

#### 3.1 Enhanced `team_member_setup.sh`
**Smart State Detection with Profile Awareness:**
```bash
# Enhanced initialization flow:
1. Detect current environment state
2. Check for existing AWS profiles
3. Map profiles to target environment
4. Validate profile permissions
5. Present intelligent defaults
6. Save profile selection for session
```

**New Command Line Options:**
```bash
./team_member_setup.sh --environment staging --profile staging-user
./team_member_setup.sh --environment production --profile prod-user
./team_member_setup.sh --auto-detect  # Smart environment detection
```

#### 3.2 Enhanced Admin Scripts
**Profile-aware admin operations:**
- Automatic profile selection based on current environment
- Profile validation before destructive operations
- Enhanced confirmation for production operations
- Audit logging with profile information

#### 3.3 S3 Integration Updates
**Environment-specific S3 operations:**
- Use appropriate profile for S3 bucket access
- Validate S3 permissions before operations
- Support for environment-specific S3 buckets
- Cross-environment access validation

**Zero-Touch Workflow S3 Profile Handling:**
```bash
# Enhanced S3 operations for zero-touch workflow:
s3_upload_with_profile() {
    local file_path=$1
    local s3_path=$2
    local profile="${AWS_PROFILE:-${ENV_AWS_PROFILE:-default}}"
    
    # Validate S3 access before upload
    validate_s3_profile_access "$profile" "$S3_BUCKET"
    
    aws s3 cp "$file_path" "$s3_path" --profile "$profile"
}

s3_download_with_profile() {
    local s3_path=$1
    local local_path=$2
    local profile="${AWS_PROFILE:-${ENV_AWS_PROFILE:-default}}"
    
    aws s3 cp "$s3_path" "$local_path" --profile "$profile"
}
```

**S3 Profile Validation:**
- Validate bucket access permissions
- Check environment-specific bucket policies
- Prevent cross-environment S3 operations
- Enhanced error handling for S3 profile issues

### Phase 4: Safety and Security Features

#### 4.1 Production Safety Measures
```bash
# Enhanced confirmation system:
confirm_production_operation() {
    echo "⚠️  PRODUCTION ENVIRONMENT OPERATION ⚠️"
    echo "Operation: $1"
    echo "AWS Profile: $SELECTED_AWS_PROFILE"
    echo "AWS Account: $(aws sts get-caller-identity --query Account --output text)"
    
    read -p "Type 'PRODUCTION' to confirm: " confirmation
    [[ "$confirmation" == "PRODUCTION" ]] || return 1
    
    read -p "Are you absolutely sure? (y/N): " final_confirm
    [[ "$final_confirm" =~ ^[Yy]$ ]] || return 1
}
```

#### 4.2 Profile Isolation
- Prevent accidental cross-environment operations
- Validate profile matches target environment
- Clear separation of staging and production workflows
- Audit trail for all profile usage

#### 4.3 Permission Validation
```bash
# Enhanced pre-operation checks:
validate_profile_permissions() {
    local profile="$1"
    local environment="$2"
    
    # Test basic AWS connectivity
    aws sts get-caller-identity --profile "$profile" >/dev/null
    
    # Validate account matches environment
    validate_profile_matches_environment "$profile" "$environment"
    
    # Test environment-specific permissions
    case "$environment" in
        staging)
            # Validate staging-specific permissions
            aws ec2 describe-client-vpn-endpoints --profile "$profile" --region "$AWS_REGION" >/dev/null
            aws s3 ls "s3://vpn-csr-exchange" --profile "$profile" >/dev/null
            ;;
        production)
            # Validate production-specific permissions
            aws ec2 describe-client-vpn-endpoints --profile "$profile" --region "$AWS_REGION" >/dev/null
            aws s3 ls "s3://vpn-csr-exchange" --profile "$profile" >/dev/null
            ;;
    esac
}

# Enhanced error recovery:
handle_profile_permission_failure() {
    local profile=$1
    local environment=$2
    local error_type=$3
    
    case "$error_type" in
        "account_mismatch")
            echo "❌ Profile '$profile' belongs to wrong AWS account for $environment"
            suggest_correct_profiles "$environment"
            ;;
        "insufficient_permissions")
            echo "❌ Profile '$profile' lacks required permissions for $environment"
            suggest_permission_fixes "$profile" "$environment"
            ;;
        "network_error")
            echo "❌ Network connectivity issues with profile '$profile'"
            suggest_connectivity_fixes
            ;;
    esac
}
```

## User Interface Design

### 1. Profile Selection Interface
```
🔧 AWS Profile and Environment Setup
══════════════════════════════════════

Detected environments:
  📁 staging (configs/staging/staging.env found)
  📁 production (configs/production/production.env found)

Available AWS profiles:
  👤 default → staging environment (✓ validated)
  👤 production → production environment (✓ validated)
  👤 my-profile → unknown environment (⚠️  needs validation)

Smart recommendation:
  Environment: staging
  AWS Profile: default
  Reason: Profile permissions validated for staging operations

Continue with recommendation? (Y/n): Y
```

### 2. Environment Switching Interface
```
🔄 Environment Switch Request
════════════════════════════════

Current: 🟡 Staging (profile: default)
Target:  🔴 Production (profile: production)

This will switch your working environment to PRODUCTION.
All subsequent operations will affect the production environment.

Profile validation results:
  ✓ AWS credentials valid
  ✓ Production environment permissions confirmed
  ✓ VPN endpoint access verified
  ✓ S3 bucket permissions validated

Type 'SWITCH' to confirm environment change: SWITCH
✓ Environment switched to production
```

## Error Handling and Recovery

### 1. Profile Validation Failures
```bash
handle_profile_validation_failure() {
    echo "❌ Profile validation failed: $1"
    echo ""
    echo "Possible solutions:"
    echo "  1. Check AWS credentials configuration"
    echo "  2. Verify profile has necessary permissions"
    echo "  3. Contact administrator for access"
    echo "  4. Use a different profile"
    echo ""
    echo "Would you like to:"
    echo "  1. Try a different profile"
    echo "  2. Reconfigure AWS credentials"
    echo "  3. Exit and contact administrator"
}
```

### 2. Environment Mismatch Detection
```bash
detect_environment_mismatch() {
    local selected_profile="$1"
    local target_environment="$2"
    
    if ! profile_matches_environment "$selected_profile" "$target_environment"; then
        echo "⚠️  ENVIRONMENT MISMATCH WARNING"
        echo "Selected profile '$selected_profile' may not be appropriate"
        echo "for target environment '$target_environment'"
        echo ""
        echo "Continue anyway? (y/N): "
    fi
}
```

## Testing Strategy

### 1. Profile Detection Tests
- Test profile scanning from `~/.aws/credentials`
- Validate environment mapping logic
- Test edge cases (missing profiles, invalid credentials)

### 2. Permission Validation Tests
- Test AWS connectivity with different profiles
- Validate environment-specific permissions
- Test cross-environment access prevention

### 3. User Experience Tests
- Test profile selection workflow
- Validate confirmation dialogs
- Test error handling and recovery

### 4. Integration Tests
- Test with existing VPN management workflows
- Validate S3 integration with multiple profiles
- Test admin operations across environments

## Migration Strategy

### 1. Backward Compatibility
- Maintain compatibility with existing single-profile setups
- Graceful fallback for users with only one AWS profile
- Preserve existing configuration files and workflows
- Support legacy `SELECTED_AWS_PROFILE` variable naming

### 2. Gradual Rollout
1. **Phase 1**: Update `lib/env_core.sh` with enhanced profile management functions
2. **Phase 2**: Integrate with `lib/env_manager.sh` for admin tools
3. **Phase 3**: Update all admin tools to use profile-aware AWS commands
4. **Phase 4**: Enhance `team_member_setup.sh` with full dual-profile support
5. **Phase 5**: Add safety features and validation

### 3. User Migration Support
- Documentation for setting up dual AWS profiles
- Migration scripts for existing single-profile users
- Training materials for new dual-environment workflow

#### 3.1 Migration Script for Existing Users
```bash
#!/bin/bash
# migrate_to_dual_profile.sh
migrate_existing_user() {
    local current_profile=$(aws configure list-profiles | head -1)
    local environment=$(detect_current_environment)
    
    echo "Migrating from single profile setup..."
    echo "Current profile: $current_profile"
    echo "Detected environment: $environment"
    
    # Save current profile to environment config
    save_profile_to_config "$environment" "$current_profile"
    
    # Guide user through second profile setup
    setup_second_environment_profile "$environment"
}
```

#### 3.2 Configuration File Migration
```bash
# Automatically update existing config files:
migrate_config_files() {
    # Add AWS_PROFILE to existing environment configs
    for env_config in configs/*/*.env; do
        if [ -f "$env_config" ] && ! grep -q "AWS_PROFILE" "$env_config"; then
            local env_name=$(basename $(dirname "$env_config"))
            local default_profile=$(get_env_default_profile "$env_name")
            echo "AWS_PROFILE=$default_profile" >> "$env_config"
        fi
    done
}
```

## Documentation Updates

### 1. User Documentation
- Setup guide for dual AWS profiles
- Workflow documentation for environment switching
- Troubleshooting guide for profile-related issues

### 2. Administrator Documentation
- Configuration guide for dual-environment setup
- Security considerations for production access
- Monitoring and audit trail setup

### 3. Developer Documentation
- API documentation for new profile management functions
- Integration guide for extending profile support
- Testing procedures for profile-aware features

## Success Metrics

### 1. User Experience Metrics
- Reduction in profile-related configuration errors
- Time to complete initial setup
- User satisfaction with environment switching

### 2. Security Metrics
- Prevention of cross-environment accidents
- Successful profile validation rate
- Audit trail completeness

### 3. Operational Metrics
- Support ticket reduction for AWS profile issues
- Successful dual-environment deployments
- Error rate in environment operations

## Implementation Timeline

### Week 1-2: Core Infrastructure (Updated Priority)
- Enhance existing `lib/env_core.sh` profile management functions
- Implement AWS CLI wrapper system (`aws_with_profile`)
- Integrate profile management with `lib/env_manager.sh`
- Add profile persistence to configuration files

### Week 3-4: Admin Tools Integration
- Update `lib/env_manager.sh` to support profile-aware operations
- Modify all admin tools to use `aws_with_profile` wrapper
- Add profile validation to admin tool prerequisites
- Implement cross-account validation

### Week 5-6: User Experience & S3 Integration
- Enhance `team_member_setup.sh` with improved profile support
- Update zero-touch workflow S3 operations with profile awareness
- Implement enhanced error handling and recovery
- Add migration support for existing users

### Week 7-8: Safety Features & Documentation
- Implement production safety measures and confirmations
- Add comprehensive testing across all scenarios
- Create migration scripts and user documentation
- Performance optimization and security audit

## Admin Tools Impact Analysis

### Current State Assessment

The dual AWS account profile management implementation will significantly affect existing admin tools, with varying degrees of impact based on their current AWS profile handling:

### 🔴 **High Impact** (Major Changes Required):

#### 1. **`admin-tools/revoke_member_access.sh`**
- **Current State**: Uses default AWS CLI with no profile awareness
- **AWS Operations**: VPN endpoints, ACM certificates, IAM users, CloudWatch logs
- **Changes Needed**: 
  - Add `--profile $ENV_AWS_PROFILE` to all AWS CLI commands
  - Implement environment-based profile selection
  - Update prerequisite checks to validate profile permissions
  - Environment-specific resource cleanup

#### 2. **`admin-tools/employee_offboarding.sh`**
- **Current State**: Uses default AWS CLI for comprehensive resource cleanup
- **AWS Operations**: VPN, ACM, IAM, CloudTrail, CloudWatch, S3, EC2 discovery
- **Changes Needed**:
  - Update ALL AWS CLI commands across multiple services
  - Add cross-account resource discovery logic
  - Environment-specific IAM cleanup with appropriate profiles
  - Enhanced audit logging with profile information

#### 3. **`admin-tools/aws_vpn_admin.sh`** (Main Admin Console)
- **Current State**: Central coordinator using default AWS CLI
- **AWS Operations**: VPN management, certificate import, network operations
- **Changes Needed**:
  - Environment-specific profile selection for all operations
  - Pass profile parameters to library functions
  - Update configuration validation to include profile checks
  - Profile-aware menu system and operation logging

### 🟡 **Medium Impact** (Enhancement of Existing Features):

#### 4. **`admin-tools/setup_csr_s3_bucket.sh`**
- **Current State**: Already has `--profile` parameter support
- **AWS Operations**: S3 bucket management, IAM policy creation
- **Changes Needed**:
  - Add environment-based default profile selection
  - Integrate with environment manager for automatic profile detection
  - Environment-specific bucket configuration

#### 5. **`admin-tools/publish_endpoints.sh`**
- **Current State**: Already supports `--profile` parameter
- **AWS Operations**: S3 object upload, environment configuration reading
- **Changes Needed**:
  - Environment-based profile defaults
  - Automatic profile selection based on target environment
  - Multi-environment publishing with appropriate profiles

### 🟢 **Low Impact** (Minor Enhancements):

#### 6. **`admin-tools/sign_csr.sh`**
- **Current State**: Already has profile support with `--profile` option
- **AWS Operations**: Limited AWS operations, mainly certificate handling
- **Changes Needed**:
  - Add environment-based profile defaults
  - Minor integration with environment manager

### Implementation Requirements by Script:

#### **AWS CLI Command Pattern Updates**
```bash
# Current pattern across admin tools:
aws ec2 describe-client-vpn-endpoints --region "$AWS_REGION"
aws acm list-certificates --region "$AWS_REGION"
aws iam get-user --user-name "$username"

# Recommended new pattern using wrapper function:
aws_with_profile ec2 describe-client-vpn-endpoints --region "$AWS_REGION"
aws_with_profile acm list-certificates --region "$AWS_REGION"
aws_with_profile iam get-user --user-name "$username"

# Alternative direct pattern:
aws ec2 describe-client-vpn-endpoints --region "$AWS_REGION" --profile "${AWS_PROFILE:-default}"
aws acm list-certificates --region "$AWS_REGION" --profile "${AWS_PROFILE:-default}"
aws iam get-user --user-name "$username" --profile "${AWS_PROFILE:-default}"
```

#### **AWS CLI Wrapper Implementation**
```bash
# Add to lib/core_functions.sh:
aws_with_profile() {
    local profile="${AWS_PROFILE:-${ENV_AWS_PROFILE:-default}}"
    
    # Validate profile exists before use
    if ! aws configure list-profiles | grep -q "^$profile$"; then
        echo "Error: AWS profile '$profile' not found" >&2
        return 1
    fi
    
    # Execute AWS command with profile
    aws "$@" --profile "$profile"
}

# Enhanced version with environment validation:
aws_with_env_profile() {
    local environment="${1:-$CURRENT_ENV}"
    local profile=$(get_env_profile "$environment")
    
    # Validate profile matches environment
    validate_profile_matches_environment "$profile" "$environment" || return 1
    
    # Execute AWS command
    AWS_PROFILE="$profile" aws "${@:2}" --profile "$profile"
}
```

#### **Environment Configuration Updates**
Each environment will need AWS profile specification:
```bash
# configs/staging/staging.env
AWS_REGION=us-east-1
AWS_PROFILE=default  # or staging
ENV_AWS_PROFILE=staging  # Environment-specific override
STAGING_ACCOUNT_ID=111111111111  # For validation
# S3_BUCKET=vpn-csr-exchange  # Unified bucket name for all environments
ENDPOINT_ID=cvpn-endpoint-123...
VPN_NAME=staging-vpn

# configs/production/production.env  
AWS_REGION=us-east-1
AWS_PROFILE=production  # or prod
ENV_AWS_PROFILE=production  # Environment-specific override
PRODUCTION_ACCOUNT_ID=222222222222  # For validation
# S3_BUCKET=vpn-csr-exchange  # Unified bucket name for all environments
ENDPOINT_ID=cvpn-endpoint-456...
VPN_NAME=production-vpn
```

#### **Configuration Loading Priority**
```bash
# Enhanced configuration loading in lib/env_core.sh:
load_environment_profile() {
    local environment=$1
    local config_file="configs/$environment/$environment.env"
    
    if [ -f "$config_file" ]; then
        source "$config_file"
        
        # Set AWS_PROFILE with priority order:
        # 1. ENV_AWS_PROFILE (environment-specific)
        # 2. AWS_PROFILE (from config)
        # 3. Environment default
        export AWS_PROFILE="${ENV_AWS_PROFILE:-${AWS_PROFILE:-$(get_env_default_profile "$environment")}}"
    fi
}
```

#### **Profile Validation Integration**
All admin tools will need enhanced prerequisite checks:
```bash
# Enhanced prerequisite check pattern
check_admin_prerequisites() {
    # Existing checks...
    check_prerequisites
    
    # Load environment configuration with profile
    load_environment_profile "$CURRENT_ENV"
    
    # Validate profile configuration
    validate_aws_profile_config "$AWS_PROFILE" || {
        echo "Error: AWS profile '$AWS_PROFILE' validation failed"
        return 1
    }
    
    # Cross-account validation
    validate_profile_matches_environment "$AWS_PROFILE" "$CURRENT_ENV" || {
        echo "Error: Profile '$AWS_PROFILE' does not match environment '$CURRENT_ENV'"
        return 1
    }
    
    # Enhanced environment validation
    validate_profile_permissions "$AWS_PROFILE" "$CURRENT_ENV" || {
        echo "Error: Profile '$AWS_PROFILE' lacks required permissions for '$CURRENT_ENV'"
        return 1
    }
}

# Environment manager integration
env_validate_profile_integration() {
    local environment=$1
    local profile=$2
    
    # Ensure environment manager is aware of profile
    env_set_profile "$environment" "$profile"
    
    # Validate the integration
    local current_profile=$(env_get_profile "$environment")
    [ "$current_profile" = "$profile" ] || return 1
}
```

### Implementation Priority:

1. **Phase 1** (Critical): `aws_vpn_admin.sh` - Central admin console affects all operations
2. **Phase 2** (Security): `revoke_member_access.sh`, `employee_offboarding.sh` - Security-critical operations
3. **Phase 3** (Enhancement): `setup_csr_s3_bucket.sh`, `publish_endpoints.sh` - Already partially profile-aware
4. **Phase 4** (Completion): `sign_csr.sh` and other batch processing tools

### Key Benefits of Admin Tools Updates:

- **Security Isolation**: Proper separation between staging and production operations
- **Operational Safety**: Clear indication of which AWS account is being used for admin operations
- **Audit Trail**: Better tracking of which profile performed which administrative actions
- **Error Prevention**: Prevent accidental cross-environment administrative operations
- **Consistency**: Unified profile handling across all administrative functions

### Backward Compatibility Strategy:

- Maintain support for existing single-profile setups
- Graceful fallback when only one AWS profile is available
- Environment detection will default to existing behavior when profile mapping is ambiguous
- Existing configuration files will continue to work with automatic profile detection
- Support legacy `SELECTED_AWS_PROFILE` variable for existing scripts
- Automatic migration of existing configurations to include profile settings

### Enhanced Error Recovery:

```bash
# Comprehensive error handling for profile issues
handle_profile_error() {
    local error_type=$1
    local profile=$2
    local environment=$3
    
    case "$error_type" in
        "profile_not_found")
            echo "❌ AWS profile '$profile' not found"
            echo "Available profiles:"
            aws configure list-profiles
            offer_profile_setup_wizard
            ;;
        "account_mismatch")
            echo "❌ Profile '$profile' connects to wrong AWS account for $environment"
            echo "Expected account: $(get_expected_account_id "$environment")"
            echo "Actual account: $(aws sts get-caller-identity --profile "$profile" --query Account --output text)"
            suggest_correct_profiles "$environment"
            ;;
        "permission_denied")
            echo "❌ Profile '$profile' lacks permissions for $environment operations"
            suggest_permission_troubleshooting "$profile" "$environment"
            ;;
        "network_error")
            echo "❌ Network connectivity issues"
            suggest_network_troubleshooting
            ;;
    esac
}

# Profile setup wizard for error recovery
offer_profile_setup_wizard() {
    echo ""
    echo "Would you like to:"
    echo "  1. Configure AWS credentials for this profile"
    echo "  2. Select a different existing profile"
    echo "  3. Set up dual AWS account profiles"
    echo "  4. Exit and configure manually"
    
    read -p "Choose option (1-4): " choice
    case "$choice" in
        1) aws configure --profile "$profile" ;;
        2) select_alternative_profile ;;
        3) run_dual_profile_setup_wizard ;;
        4) exit 1 ;;
    esac
}
```

### Enhanced Audit Trail:

- Log all AWS operations with profile information
- Track profile switches and environment changes
- Record cross-account validation results
- Maintain audit trail for compliance purposes

```bash
# Enhanced logging with profile information
log_aws_operation() {
    local operation=$1
    local profile=$2
    local environment=$3
    local result=$4
    
    log_message "AWS_OPERATION: $operation | PROFILE: $profile | ENV: $environment | RESULT: $result | ACCOUNT: $(aws sts get-caller-identity --profile "$profile" --query Account --output text 2>/dev/null || echo 'unknown')"
}
```

## Conclusion

This dual AWS account profile management system will provide:

1. **Intelligent Profile Management**: Smart detection and validation of AWS profiles
2. **Enhanced User Experience**: Intuitive environment and profile selection
3. **Production Safety**: Multiple confirmation layers for production operations
4. **Seamless Integration**: Compatible with existing zero-touch workflows
5. **Comprehensive Validation**: Thorough permission and access validation
6. **Administrative Excellence**: Profile-aware admin tools with enhanced security and audit capabilities

The implementation will be backward compatible while providing significant improvements in usability, safety, and operational efficiency for dual-environment VPN management across all user-facing and administrative functions.
