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

## Implementation Plan

### Phase 1: Core Profile Management Functions

#### 1.1 Enhanced Profile Detection (`lib/env_core.sh`)
```bash
# New functions to add:
detect_available_aws_profiles()
map_environment_to_profiles()
validate_profile_environment_match()
select_aws_profile_for_environment()
```

**Features:**
- Scan `~/.aws/credentials` for available profiles
- Map profile names to environments using naming conventions
- Validate profile permissions for target environment
- Interactive profile selection with confirmation

#### 1.2 Profile Validation System
```bash
# Validation functions:
validate_aws_profile_config()
test_profile_permissions()
verify_profile_environment_access()
```

**Validation Checks:**
- Profile exists in AWS credentials
- Profile has valid AWS credentials
- Profile has permissions for target environment operations
- Profile can access environment-specific resources (S3 buckets, VPN endpoints)

#### 1.3 Smart Profile Selection Logic
```bash
# Selection algorithm:
1. Detect target environment (staging/production)
2. Scan available AWS profiles
3. Map profiles to environments based on naming conventions
4. Validate profile permissions
5. Present user with intelligent defaults
6. Allow manual override if needed
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
# Pre-operation checks:
validate_profile_permissions() {
    local profile="$1"
    local environment="$2"
    
    # Test basic AWS connectivity
    aws sts get-caller-identity --profile "$profile" >/dev/null
    
    # Test environment-specific permissions
    case "$environment" in
        staging)
            # Validate staging-specific permissions
            ;;
        production)
            # Validate production-specific permissions
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

### 2. Gradual Rollout
1. **Phase 1**: Deploy core profile management functions
2. **Phase 2**: Update `team_member_setup.sh` with smart detection
3. **Phase 3**: Enhance admin tools with profile awareness
4. **Phase 4**: Add advanced safety features and validation

### 3. User Migration Guide
- Documentation for setting up dual AWS profiles
- Migration scripts for existing single-profile users
- Training materials for new dual-environment workflow

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

### Week 1-2: Core Infrastructure
- Implement profile detection and validation functions
- Create environment mapping logic
- Add basic profile selection interface

### Week 3-4: User Experience
- Enhance `team_member_setup.sh` with smart detection
- Implement interactive profile selection
- Add safety confirmations for production

### Week 5-6: Admin Tools Enhancement
- Update admin scripts with profile awareness
- Implement S3 integration improvements
- Add comprehensive error handling

### Week 7-8: Testing and Documentation
- Comprehensive testing across all scenarios
- Documentation updates and user guides
- Performance optimization and bug fixes

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

# New pattern required:
aws ec2 describe-client-vpn-endpoints --region "$AWS_REGION" --profile "$ENV_AWS_PROFILE"
aws acm list-certificates --region "$AWS_REGION" --profile "$ENV_AWS_PROFILE"
aws iam get-user --user-name "$username" --profile "$ENV_AWS_PROFILE"
```

#### **Environment Configuration Updates**
Each environment will need AWS profile specification:
```bash
# configs/staging/staging.env
AWS_REGION=us-east-1
AWS_PROFILE=default  # or staging
ENDPOINT_ID=cvpn-endpoint-123...

# configs/production/production.env  
AWS_REGION=us-east-1
AWS_PROFILE=production  # or prod
ENDPOINT_ID=cvpn-endpoint-456...
```

#### **Profile Validation Integration**
All admin tools will need enhanced prerequisite checks:
```bash
# New prerequisite check pattern
check_admin_prerequisites() {
    # Existing checks...
    check_prerequisites
    
    # New profile validation
    validate_aws_profile_for_environment "$ENV_AWS_PROFILE" "$CURRENT_ENV"
    
    # Enhanced environment validation
    validate_profile_permissions "$ENV_AWS_PROFILE" "$CURRENT_ENV"
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

## Conclusion

This dual AWS account profile management system will provide:

1. **Intelligent Profile Management**: Smart detection and validation of AWS profiles
2. **Enhanced User Experience**: Intuitive environment and profile selection
3. **Production Safety**: Multiple confirmation layers for production operations
4. **Seamless Integration**: Compatible with existing zero-touch workflows
5. **Comprehensive Validation**: Thorough permission and access validation
6. **Administrative Excellence**: Profile-aware admin tools with enhanced security and audit capabilities

The implementation will be backward compatible while providing significant improvements in usability, safety, and operational efficiency for dual-environment VPN management across all user-facing and administrative functions.