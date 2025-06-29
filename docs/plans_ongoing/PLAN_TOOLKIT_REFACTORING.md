# VPN Environment Toolkit Refactoring Plan

## Overview

This document outlines the plan to remove the `vpn_env.sh` environment switching toolkit and refactor all scripts to use direct AWS profile selection, following the pattern established in `team_member_setup.sh`.

## Current Problems with vpn_env.sh

- **Hidden State**: The `.current_env` file creates invisible state that users must remember
- **Complex Dependencies**: Scripts depend on environment manager libraries that add complexity
- **Error Prone**: Easy to forget which environment is active, leading to operations in wrong environment
- **Inconsistent**: Some scripts (like `team_member_setup.sh`) already use direct profile selection
- **Maintenance Overhead**: Multiple libraries (`env_manager.sh`, `env_core.sh`, `enhanced_confirmation.sh`) need coordination

## Target Architecture

### Direct Profile Selection Pattern

Each script will independently:

1. **Detect Available AWS Profiles** - Scan `~/.aws/config` and `~/.aws/credentials`
2. **Map Profiles to Environments** - Use naming conventions and account ID validation
3. **Interactive Selection** - Present profile menu to users with environment context
4. **Validate Profile** - Confirm profile matches expected environment via account ID
5. **Load Configuration** - Read environment-specific config files based on selection

### Benefits

- ✅ **Explicit**: Users always choose environment/profile at runtime
- ✅ **Safe**: No hidden state, no accidental wrong-environment operations
- ✅ **Simple**: Each script is self-contained with minimal dependencies
- ✅ **Consistent**: All scripts work the same way
- ✅ **Flexible**: Easy to add new profiles/environments

## Implementation Phases

### Phase 1: Create New Profile Selection Library

**File**: `lib/profile_selector.sh`

Extract and refactor functions from `env_core.sh`:
- `detect_available_profiles()` - Find AWS profiles
- `map_profile_to_environment()` - Use naming conventions (staging, prod, production)
- `validate_profile_account()` - Check account ID matches environment
- `select_profile_interactive()` - Show interactive menu
- `get_profile_for_environment()` - Get profile for specific environment

**Key Features**:
- No state persistence (no `.current_env` file)
- Environment detection via account ID validation
- Smart profile recommendations based on naming
- Clear error messages and validation

### Phase 2: Refactor Admin Scripts

Update each admin script to use the new pattern:

#### Scripts to Update:
- `admin-tools/aws_vpn_admin.sh`
- `admin-tools/setup_csr_s3_bucket.sh` 
- `admin-tools/manage_vpn_users.sh`
- `admin-tools/sign_csr.sh`
- `admin-tools/process_csr_batch.sh`
- `admin-tools/revoke_member_access.sh`
- `admin-tools/employee_offboarding.sh`
- `admin-tools/publish_endpoints.sh`

#### Changes for Each Script:
1. **Remove** `source "$PARENT_DIR/lib/env_manager.sh"`
2. **Add** `source "$PARENT_DIR/lib/profile_selector.sh"`
3. **Add** command line parameters:
   - `--profile PROFILE_NAME` - Specify profile directly
   - `--environment ENV` - Target specific environment
4. **Add** profile selection at startup if not specified
5. **Replace** all `env_*` function calls with new equivalents
6. **Update** config file loading to use selected environment

#### Example Before/After:

**Before** (`admin-tools/aws_vpn_admin.sh`):
```bash
source "$PARENT_DIR/lib/env_manager.sh"
env_init_for_script "aws_vpn_admin.sh"
# Uses $CURRENT_ENVIRONMENT from .current_env
```

**After**:
```bash
source "$PARENT_DIR/lib/profile_selector.sh"

# Parse command line arguments
AWS_PROFILE=""
TARGET_ENVIRONMENT=""
while [[ $# -gt 0 ]]; do
    case $1 in
        --profile) AWS_PROFILE="$2"; shift 2 ;;
        --environment) TARGET_ENVIRONMENT="$2"; shift 2 ;;
        *) break ;;
    esac
done

# Select profile if not specified
if [[ -z "$AWS_PROFILE" ]]; then
    AWS_PROFILE=$(select_profile_interactive "$TARGET_ENVIRONMENT")
fi

# Validate and load configuration
validate_profile_account "$AWS_PROFILE" "$TARGET_ENVIRONMENT"
load_environment_config "$TARGET_ENVIRONMENT"
```

### Phase 3: Refactor Deployment Scripts

#### `scripts/deploy.sh`
- ✅ **Already supports profile selection** - Uses `get_env_profile()` function
- **Enhance** to show interactive profile selection menu
- **Add** `--profile` parameter support
- **Update** to use new profile selector library

#### `scripts/setup-parameters.sh`
- ✅ **Already supports `--env` parameter**
- **Update** to use new profile selection library
- **Enhance** interactive mode with profile selection menu

### Phase 4: Update Configuration Loading

**Current State**: Scripts rely on `$CURRENT_ENVIRONMENT` from `.current_env`

**Target State**: Configuration loaded based on runtime profile selection

#### Changes:
1. **Remove** dependency on `.current_env` file
2. **Determine** environment from selected AWS profile + account ID validation
3. **Load** config files dynamically:
   - `configs/{environment}/{environment}.env`
   - `configs/{environment}/vpn_endpoint.conf`

#### Example Configuration Loading:
```bash
load_environment_config() {
    local environment="$1"
    local config_file="$PROJECT_ROOT/configs/${environment}/${environment}.env"
    local endpoint_config="$PROJECT_ROOT/configs/${environment}/vpn_endpoint.conf"
    
    if [[ ! -f "$config_file" ]]; then
        echo "Error: Environment config not found: $config_file"
        return 1
    fi
    
    source "$config_file"
    [[ -f "$endpoint_config" ]] && source "$endpoint_config"
    
    # Set global variables for script use
    VPN_CONFIG_DIR="$PROJECT_ROOT/configs/${environment}"
    VPN_LOG_DIR="$PROJECT_ROOT/logs/${environment}"
    # ... etc
}
```

### Phase 5: Cleanup and File Removal

#### Files to Remove:
- `admin-tools/vpn_env.sh` - Environment switching script
- `lib/env_manager.sh` - Environment state management
- `enhanced_env_selector.sh` - Interactive environment selector
- `.current_env` - State file (also remove from `.gitignore`)

#### Files to Refactor:
- `lib/env_core.sh` - Keep only profile detection/validation functions
- `lib/enhanced_confirmation.sh` - Simplify or remove if unused

#### Files to Keep (Minimal Changes):
- `lib/core_functions.sh` - Basic utilities remain useful
- `lib/cert_management.sh` - Certificate functions unaffected
- `lib/aws_setup.sh` - AWS CLI setup functions useful

## Migration Guide

### For Users

#### Before (with vpn_env.sh):
```bash
# Switch environment first
./admin-tools/vpn_env.sh switch production

# Then run admin tools (uses switched environment)
./admin-tools/aws_vpn_admin.sh
```

#### After (direct selection):
```bash
# Option 1: Interactive selection
./admin-tools/aws_vpn_admin.sh
# Shows menu:
# Select AWS Profile:
# 1) staging (Account: YOUR_STAGING_ACCOUNT_ID, Region: us-east-1)
# 2) production (Account: YOUR_PRODUCTION_ACCOUNT_ID, Region: us-east-1)  
# Enter choice [1-2]: 2

# Option 2: Direct specification
./admin-tools/aws_vpn_admin.sh --profile production

# Option 3: Environment-based
./admin-tools/aws_vpn_admin.sh --environment production
```

### For Developers

#### Profile Detection Pattern:
```bash
# Detect available profiles
available_profiles=($(aws configure list-profiles))

# Map profiles to environments based on naming
for profile in "${available_profiles[@]}"; do
    case "$profile" in
        *staging*|*dev*) environment="staging" ;;
        *prod*|*production*) environment="production" ;;
        default) environment="staging" ;; # fallback
    esac
done

# Validate account ID matches expected environment
validate_profile_account "$profile" "$environment"
```

## Implementation Timeline

### Week 1: Foundation
- [ ] Create `lib/profile_selector.sh` with core functions
- [ ] Test profile detection and validation logic
- [ ] Update `team_member_setup.sh` to use new library (validation)

### Week 2: Admin Tools
- [ ] Refactor 3-4 admin scripts (`aws_vpn_admin.sh`, `setup_csr_s3_bucket.sh`, etc.)
- [ ] Test functionality with both interactive and command-line modes
- [ ] Update documentation and help messages

### Week 3: Deployment Scripts  
- [ ] Update `scripts/deploy.sh` with enhanced profile selection
- [ ] Update `scripts/setup-parameters.sh` integration
- [ ] Test multi-environment deployment workflows

### Week 4: Cleanup and Testing
- [ ] Remove old files (`vpn_env.sh`, `env_manager.sh`, etc.)
- [ ] Update all documentation and README files
- [ ] Comprehensive testing of all workflows
- [ ] Update `CLAUDE.md` with new patterns

## Risk Mitigation

### Backwards Compatibility
- **Keep old scripts** during transition period with deprecation warnings
- **Provide migration script** to help users update their workflows
- **Document changes** clearly in changelog

### Testing Strategy
- **Test each script individually** with both interactive and CLI modes
- **Test profile validation** with correct and incorrect account IDs
- **Test configuration loading** for all environments
- **Verify no functionality regression** compared to current system

### Rollback Plan
- **Keep old files** in a `deprecated/` directory temporarily
- **Tag current state** in git before starting refactoring
- **Create restore script** if needed for emergency rollback

## Success Metrics

- ✅ All admin scripts work without `vpn_env.sh`
- ✅ Profile selection is intuitive and reliable
- ✅ No accidental wrong-environment operations
- ✅ Reduced codebase complexity (fewer files, clearer dependencies)
- ✅ Consistent user experience across all scripts
- ✅ Comprehensive documentation and examples

## Future Enhancements

### Profile Management
- **Auto-discovery** of new environments
- **Profile validation** against known account IDs
- **Smart defaults** based on user history

### Configuration
- **Global config file** for profile mappings
- **Environment templates** for easy setup
- **Validation tools** for configuration consistency

### Developer Experience
- **Tab completion** for profile names
- **Status indicators** in terminal prompt
- **Integration** with popular terminal themes

---

*This plan transforms the VPN toolkit from a stateful, complex system to a simple, explicit, and safe direct-selection model that follows modern CLI best practices.*