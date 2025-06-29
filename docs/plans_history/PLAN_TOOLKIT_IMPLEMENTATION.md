# VPN Environment Toolkit Implementation Guide

## Overview

This document provides detailed step-by-step implementation instructions for refactoring the VPN toolkit to remove `vpn_env.sh` and implement direct AWS profile selection, as outlined in `PLAN_TOOLKIT_REFACTORING.md`.

## Pre-Implementation Checklist

### 1. Backup Current State
```bash
# Create implementation branch
git checkout -b toolkit-refactoring
git add .
git commit -m "Pre-refactoring state backup"

# Tag current working state
git tag -a "pre-refactoring-backup" -m "Working state before toolkit refactoring"
```

### 2. Document Current Workflow
```bash
# Test and document current functionality
./admin-tools/vpn_env.sh status
./admin-tools/aws_vpn_admin.sh  
./scripts/deploy.sh staging
# Note: Document any issues or dependencies discovered
```

### 3. Analyze Current Dependencies
```bash
# Find all files that use env_manager.sh
grep -r "env_manager.sh" . --include="*.sh"
grep -r "env_core.sh" . --include="*.sh"
grep -r "CURRENT_ENVIRONMENT" . --include="*.sh"
```

## Phase 1: Create Profile Selection Library

### Step 1.1: Create `lib/profile_selector.sh`

```bash
# Create the new profile selector library
touch lib/profile_selector.sh
```

**File Content** (`lib/profile_selector.sh`):
```bash
#!/bin/bash

# VPN Toolkit Profile Selection Library
# Replaces env_manager.sh with direct profile selection

# Global variables
declare -g SELECTED_AWS_PROFILE=""
declare -g SELECTED_ENVIRONMENT=""
declare -g PROJECT_ROOT=""

# Initialize project root
if [[ -z "$PROJECT_ROOT" ]]; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
fi

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Detect available AWS profiles from configuration
detect_available_profiles() {
    local profiles=()
    
    # Get profiles from AWS CLI
    if command -v aws &> /dev/null; then
        while IFS= read -r profile; do
            [[ -n "$profile" ]] && profiles+=("$profile")
        done < <(aws configure list-profiles 2>/dev/null)
    fi
    
    # Fallback: Parse ~/.aws/config manually
    if [[ ${#profiles[@]} -eq 0 && -f ~/.aws/config ]]; then
        while IFS= read -r line; do
            if [[ $line =~ ^\[profile\ (.+)\]$ ]]; then
                profiles+=("${BASH_REMATCH[1]}")
            elif [[ $line =~ ^\[default\]$ ]]; then
                profiles+=("default")
            fi
        done < ~/.aws/config
    fi
    
    # Remove duplicates and sort
    printf '%s\n' "${profiles[@]}" | sort -u
}

# Map profile name to environment based on naming conventions
map_profile_to_environment() {
    local profile="$1"
    
    case "${profile,,}" in
        *staging*|*dev*|*test*)
            echo "staging"
            ;;
        *prod*|*production*)
            echo "production"
            ;;
        default)
            echo "staging"  # Default fallback
            ;;
        *)
            # Unknown profile - try to detect via account ID
            echo ""
            ;;
    esac
}

# Get account ID for a profile
get_profile_account_id() {
    local profile="$1"
    
    if [[ -z "$profile" ]]; then
        return 1
    fi
    
    local account_id
    account_id=$(aws sts get-caller-identity --profile "$profile" --query 'Account' --output text 2>/dev/null)
    
    if [[ $? -eq 0 && -n "$account_id" ]]; then
        echo "$account_id"
        return 0
    fi
    
    return 1
}

# Get region for a profile
get_profile_region() {
    local profile="$1"
    
    if [[ -z "$profile" ]]; then
        return 1
    fi
    
    local region
    region=$(aws configure get region --profile "$profile" 2>/dev/null)
    
    if [[ -n "$region" ]]; then
        echo "$region"
    else
        echo "us-east-1"  # Default fallback
    fi
}

# Validate profile matches expected environment
validate_profile_account() {
    local profile="$1"
    local expected_environment="$2"
    
    log_info "Validating profile '$profile' for environment '$expected_environment'"
    
    # Get account ID from profile
    local account_id
    account_id=$(get_profile_account_id "$profile")
    
    if [[ $? -ne 0 ]]; then
        log_error "Failed to get account ID for profile '$profile'"
        log_error "Please check your AWS credentials and profile configuration"
        return 1
    fi
    
    # Load expected account ID from environment config
    local config_file="$PROJECT_ROOT/configs/${expected_environment}/${expected_environment}.env"
    
    if [[ ! -f "$config_file" ]]; then
        log_error "Environment config not found: $config_file"
        return 1
    fi
    
    local expected_account_id
    expected_account_id=$(grep "^AWS_ACCOUNT_ID=" "$config_file" | cut -d'=' -f2 | tr -d '"')
    
    if [[ -z "$expected_account_id" ]]; then
        log_warning "AWS_ACCOUNT_ID not found in $config_file"
        log_warning "Skipping account validation (consider adding AWS_ACCOUNT_ID to config)"
        return 0
    fi
    
    if [[ "$account_id" != "$expected_account_id" ]]; then
        log_error "Account ID mismatch!"
        log_error "Profile '$profile' account: $account_id"
        log_error "Expected for '$expected_environment': $expected_account_id"
        log_error "This could lead to operations in the wrong AWS account"
        return 1
    fi
    
    log_success "Profile validation passed: $profile -> $expected_environment (Account: $account_id)"
    return 0
}

# Interactive profile selection menu
select_profile_interactive() {
    local target_environment="$1"
    local profiles=($(detect_available_profiles))
    
    if [[ ${#profiles[@]} -eq 0 ]]; then
        log_error "No AWS profiles found"
        log_error "Please configure AWS profiles using: aws configure --profile <profile-name>"
        return 1
    fi
    
    echo ""
    echo "=== AWS Profile Selection ==="
    echo ""
    
    # Build profile menu with environment and account info
    declare -a profile_info=()
    local index=1
    
    for profile in "${profiles[@]}"; do
        local environment=$(map_profile_to_environment "$profile")
        local account_id=$(get_profile_account_id "$profile" 2>/dev/null || echo "unknown")
        local region=$(get_profile_region "$profile")
        
        # Highlight profiles that match target environment
        local highlight=""
        if [[ -n "$target_environment" && "$environment" == "$target_environment" ]]; then
            highlight="⭐ "
        fi
        
        local display_env="${environment:-"unknown"}"
        profile_info+=("$profile")
        printf "%2d) %s%s (Env: %s, Account: %s, Region: %s)\n" \
               "$index" "$highlight" "$profile" "$display_env" "$account_id" "$region"
        ((index++))
    done
    
    echo ""
    if [[ -n "$target_environment" ]]; then
        echo "⭐ = Recommended for environment: $target_environment"
        echo ""
    fi
    
    # Get user selection
    local choice
    while true; do
        read -p "Select AWS Profile [1-${#profiles[@]}]: " choice
        
        if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "${#profiles[@]}" ]; then
            break
        else
            log_error "Invalid selection. Please enter a number between 1 and ${#profiles[@]}"
        fi
    done
    
    local selected_profile="${profile_info[$((choice-1))]}"
    echo "$selected_profile"
}

# Get profile for specific environment (non-interactive)
get_profile_for_environment() {
    local target_environment="$1"
    local profiles=($(detect_available_profiles))
    
    # Look for profiles that match the target environment
    for profile in "${profiles[@]}"; do
        local environment=$(map_profile_to_environment "$profile")
        if [[ "$environment" == "$target_environment" ]]; then
            echo "$profile"
            return 0
        fi
    done
    
    # No direct match found
    return 1
}

# Load environment configuration files
load_environment_config() {
    local environment="$1"
    
    if [[ -z "$environment" ]]; then
        log_error "Environment not specified for config loading"
        return 1
    fi
    
    local config_file="$PROJECT_ROOT/configs/${environment}/${environment}.env"
    local endpoint_config="$PROJECT_ROOT/configs/${environment}/vpn_endpoint.conf"
    
    # Load main environment config
    if [[ ! -f "$config_file" ]]; then
        log_error "Environment config not found: $config_file"
        return 1
    fi
    
    log_info "Loading environment config: $config_file"
    source "$config_file"
    
    # Load endpoint config if it exists
    if [[ -f "$endpoint_config" ]]; then
        log_info "Loading endpoint config: $endpoint_config"
        source "$endpoint_config"
    else
        log_warning "Endpoint config not found: $endpoint_config"
    fi
    
    # Set global variables for script use
    export VPN_CONFIG_DIR="$PROJECT_ROOT/configs/${environment}"
    export VPN_LOG_DIR="$PROJECT_ROOT/logs/${environment}"
    export VPN_CERT_DIR="$PROJECT_ROOT/certs/${environment}"
    export CURRENT_ENVIRONMENT="$environment"  # For backwards compatibility
    
    # Create directories if they don't exist
    mkdir -p "$VPN_LOG_DIR" "$VPN_CERT_DIR"
    
    log_success "Environment configuration loaded: $environment"
    return 0
}

# Main profile selection function
# Usage: select_and_validate_profile [--profile PROFILE] [--environment ENV] [--interactive]
select_and_validate_profile() {
    local specified_profile=""
    local target_environment=""
    local force_interactive=false
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --profile)
                specified_profile="$2"
                shift 2
                ;;
            --environment)
                target_environment="$2"
                shift 2
                ;;
            --interactive)
                force_interactive=true
                shift
                ;;
            *)
                # Unknown option, pass through
                break
                ;;
        esac
    done
    
    local selected_profile=""
    
    # Determine profile selection method
    if [[ -n "$specified_profile" ]]; then
        # Profile specified directly
        selected_profile="$specified_profile"
        log_info "Using specified profile: $selected_profile"
        
        # Derive environment if not specified
        if [[ -z "$target_environment" ]]; then
            target_environment=$(map_profile_to_environment "$selected_profile")
            if [[ -z "$target_environment" ]]; then
                log_error "Cannot determine environment for profile: $selected_profile"
                return 1
            fi
            log_info "Detected environment: $target_environment"
        fi
        
    elif [[ -n "$target_environment" && "$force_interactive" != true ]]; then
        # Environment specified, try to find matching profile
        selected_profile=$(get_profile_for_environment "$target_environment")
        
        if [[ $? -ne 0 ]]; then
            log_warning "No profile found for environment: $target_environment"
            log_info "Falling back to interactive selection"
            selected_profile=$(select_profile_interactive "$target_environment")
        else
            log_info "Auto-selected profile for $target_environment: $selected_profile"
        fi
        
    else
        # Interactive selection
        selected_profile=$(select_profile_interactive "$target_environment")
        
        # Derive environment if not specified
        if [[ -z "$target_environment" ]]; then
            target_environment=$(map_profile_to_environment "$selected_profile")
            if [[ -z "$target_environment" ]]; then
                log_error "Cannot determine environment for profile: $selected_profile"
                return 1
            fi
        fi
    fi
    
    # Validate selection
    if [[ -z "$selected_profile" ]]; then
        log_error "No profile selected"
        return 1
    fi
    
    # Validate profile against environment
    if ! validate_profile_account "$selected_profile" "$target_environment"; then
        return 1
    fi
    
    # Load environment configuration
    if ! load_environment_config "$target_environment"; then
        return 1
    fi
    
    # Set global variables
    export SELECTED_AWS_PROFILE="$selected_profile"
    export SELECTED_ENVIRONMENT="$target_environment"
    export AWS_PROFILE="$selected_profile"  # For AWS CLI
    
    log_success "Profile selection complete"
    log_success "AWS Profile: $selected_profile"
    log_success "Environment: $target_environment"
    
    return 0
}

# AWS CLI wrapper that uses selected profile
aws_with_selected_profile() {
    if [[ -z "$SELECTED_AWS_PROFILE" ]]; then
        log_error "No AWS profile selected. Call select_and_validate_profile first."
        return 1
    fi
    
    aws --profile "$SELECTED_AWS_PROFILE" "$@"
}

# Show current selection status
show_profile_status() {
    echo ""
    echo "=== Current Profile Status ==="
    echo "AWS Profile: ${SELECTED_AWS_PROFILE:-"Not selected"}"
    echo "Environment: ${SELECTED_ENVIRONMENT:-"Not determined"}"
    echo "Project Root: ${PROJECT_ROOT}"
    
    if [[ -n "$SELECTED_AWS_PROFILE" ]]; then
        local account_id=$(get_profile_account_id "$SELECTED_AWS_PROFILE" 2>/dev/null || echo "unknown")
        local region=$(get_profile_region "$SELECTED_AWS_PROFILE")
        echo "Account ID: $account_id"
        echo "Region: $region"
    fi
    echo ""
}

# Export functions for use in other scripts
export -f detect_available_profiles
export -f map_profile_to_environment
export -f get_profile_account_id
export -f get_profile_region
export -f validate_profile_account
export -f select_profile_interactive
export -f get_profile_for_environment
export -f load_environment_config
export -f select_and_validate_profile
export -f aws_with_selected_profile
export -f show_profile_status
export -f log_info log_success log_warning log_error
```

### Step 1.2: Test Profile Selector Library

```bash
# Make the library executable
chmod +x lib/profile_selector.sh

# Test the library directly
source lib/profile_selector.sh

# Test profile detection
echo "Available profiles:"
detect_available_profiles

# Test interactive selection
echo "Testing interactive selection:"
select_and_validate_profile --interactive
```

### Step 1.3: Validate Core Functions

Create a test script to validate functionality:

```bash
# Create test script
cat > test_profile_selector.sh << 'EOF'
#!/bin/bash

source ./lib/profile_selector.sh

echo "=== Testing Profile Selector Library ==="

echo "1. Testing profile detection..."
profiles=($(detect_available_profiles))
echo "Found ${#profiles[@]} profiles: ${profiles[*]}"

echo "2. Testing environment mapping..."
for profile in "${profiles[@]}"; do
    env=$(map_profile_to_environment "$profile")
    echo "  $profile -> ${env:-"unknown"}"
done

echo "3. Testing account ID retrieval..."
for profile in "${profiles[@]}"; do
    account=$(get_profile_account_id "$profile" 2>/dev/null || echo "failed")
    echo "  $profile -> $account"
done

echo "4. Testing configuration loading..."
if load_environment_config "staging"; then
    echo "  Staging config loaded successfully"
    echo "  VPN_CONFIG_DIR: $VPN_CONFIG_DIR"
else
    echo "  Failed to load staging config"
fi

echo "=== Test Complete ==="
EOF

chmod +x test_profile_selector.sh
./test_profile_selector.sh
```

## Phase 2: Refactor Admin Scripts

### Step 2.1: Update `admin-tools/aws_vpn_admin.sh`

#### Current State Analysis
```bash
# Identify current dependencies
grep -n "env_manager\|env_core\|CURRENT_ENVIRONMENT" admin-tools/aws_vpn_admin.sh
```

#### Implementation Steps

**Before modification, backup the original:**
```bash
cp admin-tools/aws_vpn_admin.sh admin-tools/aws_vpn_admin.sh.backup
```

**Update the script header:**
```bash
# Replace this section at the top of aws_vpn_admin.sh
# OLD:
# source "$PARENT_DIR/lib/env_manager.sh"
# env_init_for_script "aws_vpn_admin.sh"

# NEW:
source "$PARENT_DIR/lib/profile_selector.sh"

# Parse command line arguments
AWS_PROFILE=""
TARGET_ENVIRONMENT=""
SHOW_HELP=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --profile)
            AWS_PROFILE="$2"
            shift 2
            ;;
        --environment|-e)
            TARGET_ENVIRONMENT="$2"
            shift 2
            ;;
        --help|-h)
            SHOW_HELP=true
            shift
            ;;
        *)
            break
            ;;
    esac
done

# Show help if requested
if [[ "$SHOW_HELP" == true ]]; then
    cat << EOF
Usage: $0 [OPTIONS]

Options:
    --profile PROFILE     Use specific AWS profile
    --environment ENV     Target environment (staging|production)
    --help               Show this help message

Examples:
    $0                              # Interactive profile selection
    $0 --profile production         # Use production profile
    $0 --environment staging        # Target staging environment
    $0 --profile prod --environment production

EOF
    exit 0
fi

# Select and validate profile
if ! select_and_validate_profile --profile "$AWS_PROFILE" --environment "$TARGET_ENVIRONMENT"; then
    log_error "Profile selection failed"
    exit 1
fi
```

**Update function calls throughout the script:**
```bash
# Replace these patterns:
# OLD: env_validate_profile_integration
# NEW: validate_profile_account "$SELECTED_AWS_PROFILE" "$SELECTED_ENVIRONMENT"

# OLD: aws_with_env_profile
# NEW: aws_with_selected_profile

# OLD: $CURRENT_ENVIRONMENT
# NEW: $SELECTED_ENVIRONMENT

# OLD: env_get_current_profile
# NEW: echo "$SELECTED_AWS_PROFILE"
```

### Step 2.2: Update `admin-tools/setup_csr_s3_bucket.sh`

```bash
# Backup original
cp admin-tools/setup_csr_s3_bucket.sh admin-tools/setup_csr_s3_bucket.sh.backup

# Apply similar pattern to setup_csr_s3_bucket.sh
# Key changes:
# 1. Replace env_manager.sh with profile_selector.sh
# 2. Add --profile and --environment parameters
# 3. Update AWS CLI calls to use aws_with_selected_profile
# 4. Replace environment variables with selected values
```

**Template for argument parsing in setup_csr_s3_bucket.sh:**
```bash
# Add after script initialization
AWS_PROFILE=""
TARGET_ENVIRONMENT=""
PUBLISH_ASSETS=false
CREATE_POLICIES=false
LIST_POLICIES=false
CLEANUP_MODE=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --profile)
            AWS_PROFILE="$2"
            shift 2
            ;;
        --environment|-e)
            TARGET_ENVIRONMENT="$2"
            shift 2
            ;;
        --publish-assets)
            PUBLISH_ASSETS=true
            shift
            ;;
        --create-policies)
            CREATE_POLICIES=true
            shift
            ;;
        --list-policies)
            LIST_POLICIES=true
            shift
            ;;
        --cleanup)
            CLEANUP_MODE=true
            shift
            ;;
        --help|-h)
            show_help
            exit 0
            ;;
        *)
            break
            ;;
    esac
done

# Select and validate profile
if ! select_and_validate_profile --profile "$AWS_PROFILE" --environment "$TARGET_ENVIRONMENT"; then
    log_error "Profile selection failed"
    exit 1
fi
```

### Step 2.3: Update Remaining Admin Scripts

Apply the same pattern to all remaining admin scripts:

```bash
# Scripts to update with the same pattern:
scripts=(
    "admin-tools/manage_vpn_users.sh"
    "admin-tools/sign_csr.sh"
    "admin-tools/process_csr_batch.sh"
    "admin-tools/revoke_member_access.sh"
    "admin-tools/employee_offboarding.sh"
    "admin-tools/publish_endpoints.sh"
)

for script in "${scripts[@]}"; do
    echo "Updating $script..."
    
    # Backup original
    cp "$script" "${script}.backup"
    
    # Apply refactoring (manual process for each script)
    # 1. Replace source statement
    # 2. Add argument parsing
    # 3. Add profile selection
    # 4. Update function calls
    
    echo "  - Backup created: ${script}.backup"
    echo "  - Ready for manual refactoring"
done
```

## Phase 3: Refactor Deployment Scripts

### Step 3.1: Update `scripts/deploy.sh`

The deployment script already has some profile support. Enhance it:

```bash
# Backup original
cp scripts/deploy.sh scripts/deploy.sh.backup

# Key enhancements needed:
# 1. Use profile_selector.sh instead of env_core.sh
# 2. Add interactive profile selection menu
# 3. Improve --profile parameter handling
# 4. Enhance validation logic
```

**Update the profile detection section in deploy.sh:**
```bash
# Replace the existing profile detection with:
source "$PROJECT_ROOT/lib/profile_selector.sh"

# Function to get profile for environment with enhanced selection
get_env_profile() {
    local env="$1"
    local specified_profile="$2"
    
    if [[ -n "$specified_profile" ]]; then
        echo "$specified_profile"
        return 0
    fi
    
    # Try to auto-detect profile for environment
    local auto_profile
    auto_profile=$(get_profile_for_environment "$env")
    
    if [[ $? -eq 0 ]]; then
        echo "$auto_profile"
        return 0
    fi
    
    # Fall back to interactive selection
    log_info "No suitable profile found for environment: $env"
    select_profile_interactive "$env"
}
```

### Step 3.2: Update `scripts/setup-parameters.sh`

```bash
# Backup original
cp scripts/setup-parameters.sh scripts/setup-parameters.sh.backup

# Key changes:
# 1. Replace env_core.sh with profile_selector.sh
# 2. Enhance --env parameter to support profile selection
# 3. Add --profile parameter
# 4. Improve validation
```

## Phase 4: Update Configuration Loading

### Step 4.1: Remove `.current_env` Dependencies

```bash
# Find all references to .current_env
grep -r "\.current_env" . --include="*.sh"

# Remove .current_env from .gitignore if present
sed -i '/\.current_env/d' .gitignore 2>/dev/null || true

# Remove actual .current_env file if it exists
rm -f .current_env
```

### Step 4.2: Update Configuration Loading Pattern

Ensure all scripts use the new `load_environment_config` function:

```bash
# Pattern to replace in all scripts:
# OLD:
# source configs/$CURRENT_ENVIRONMENT/${CURRENT_ENVIRONMENT}.env

# NEW:
# load_environment_config "$SELECTED_ENVIRONMENT"
```

### Step 4.3: Create Configuration Validation Script

```bash
cat > admin-tools/validate-configs.sh << 'EOF'
#!/bin/bash

# Configuration Validation Script
# Ensures all environment configs are valid and complete

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARENT_DIR="$(dirname "$SCRIPT_DIR")"

source "$PARENT_DIR/lib/profile_selector.sh"

validate_environment_config() {
    local env="$1"
    local config_file="$PARENT_DIR/configs/${env}/${env}.env"
    
    log_info "Validating configuration for environment: $env"
    
    if [[ ! -f "$config_file" ]]; then
        log_error "Configuration file not found: $config_file"
        return 1
    fi
    
    # Check required variables
    local required_vars=(
        "AWS_ACCOUNT_ID"
        "AWS_REGION" 
        "VPC_ID"
        "SUBNET_ID"
        "VPN_CIDR"
    )
    
    local missing_vars=()
    
    for var in "${required_vars[@]}"; do
        local value=$(grep "^${var}=" "$config_file" | cut -d'=' -f2 | tr -d '"')
        if [[ -z "$value" ]]; then
            missing_vars+=("$var")
        else
            log_success "  $var: $value"
        fi
    done
    
    if [[ ${#missing_vars[@]} -gt 0 ]]; then
        log_error "Missing required variables: ${missing_vars[*]}"
        return 1
    fi
    
    log_success "Configuration validation passed for: $env"
    return 0
}

# Main execution
environments=("staging" "production")

for env in "${environments[@]}"; do
    echo ""
    validate_environment_config "$env"
done

echo ""
log_info "Configuration validation complete"
EOF

chmod +x admin-tools/validate-configs.sh
```

## Phase 5: Cleanup and File Removal

### Step 5.1: Deprecate Old Files

Create a deprecated directory and move old files:

```bash
# Create deprecated directory
mkdir -p deprecated

# Move old files to deprecated
mv admin-tools/vpn_env.sh deprecated/ 2>/dev/null || true
mv lib/env_manager.sh deprecated/ 2>/dev/null || true
mv enhanced_env_selector.sh deprecated/ 2>/dev/null || true

# Create deprecation notice
cat > deprecated/README.md << 'EOF'
# Deprecated Files

These files have been replaced by the new direct profile selection system.

## Replaced Files:
- `vpn_env.sh` → Use `--profile` and `--environment` parameters in individual scripts
- `env_manager.sh` → Use `lib/profile_selector.sh`
- `enhanced_env_selector.sh` → Built into profile_selector.sh

## Migration Guide:
See PLAN_TOOLKIT_IMPLEMENTATION.md for migration instructions.

## Removal Timeline:
These files will be permanently removed after 2 weeks of testing the new system.
EOF
```

### Step 5.2: Update `lib/env_core.sh`

Keep only the useful functions and remove environment state management:

```bash
# Backup original
cp lib/env_core.sh lib/env_core.sh.backup

# Create minimal version with only AWS utilities
cat > lib/env_core.sh << 'EOF'
#!/bin/bash

# Core AWS utilities (minimal version)
# Most functionality moved to profile_selector.sh

# Function to get AWS CLI version
get_aws_cli_version() {
    aws --version 2>&1 | head -n1 | cut -d' ' -f1 | cut -d'/' -f2
}

# Function to check AWS CLI installation
check_aws_cli() {
    if ! command -v aws &> /dev/null; then
        echo "AWS CLI not found. Please install it first."
        return 1
    fi
    return 0
}

# Legacy wrapper for backwards compatibility
aws_with_profile() {
    local profile="$1"
    shift
    aws --profile "$profile" "$@"
}

# Export functions
export -f get_aws_cli_version
export -f check_aws_cli
export -f aws_with_profile
EOF
```

### Step 5.3: Clean Up Documentation

Update documentation to reflect new patterns:

```bash
# Update CLAUDE.md sections about environment management
# Replace vpn_env.sh instructions with new profile selection patterns

# Update any README files
# Update help messages in scripts
# Update error messages to reference new commands
```

## Testing and Validation

### Step 6.1: Create Comprehensive Test Suite

```bash
cat > test_refactored_toolkit.sh << 'EOF'
#!/bin/bash

# Comprehensive test suite for refactored toolkit

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/profile_selector.sh"

test_count=0
pass_count=0
fail_count=0

run_test() {
    local test_name="$1"
    local test_command="$2"
    
    ((test_count++))
    echo "Test $test_count: $test_name"
    
    if eval "$test_command" &>/dev/null; then
        echo "  ✅ PASS"
        ((pass_count++))
    else
        echo "  ❌ FAIL"
        ((fail_count++))
    fi
}

echo "=== Testing Refactored VPN Toolkit ==="

# Test profile detection
run_test "Profile detection" "detect_available_profiles | wc -l | grep -q '[0-9]'"

# Test configuration validation
run_test "Config validation" "./admin-tools/validate-configs.sh"

# Test admin script help
run_test "Admin script help" "./admin-tools/aws_vpn_admin.sh --help"

# Test deployment script help  
run_test "Deploy script help" "./scripts/deploy.sh --help"

# Test profile selector library
run_test "Profile selector functions" "declare -f select_and_validate_profile"

echo ""
echo "=== Test Results ==="
echo "Total Tests: $test_count"
echo "Passed: $pass_count"
echo "Failed: $fail_count"

if [[ $fail_count -eq 0 ]]; then
    echo "🎉 All tests passed!"
    exit 0
else
    echo "❌ Some tests failed. Please review the implementation."
    exit 1
fi
EOF

chmod +x test_refactored_toolkit.sh
```

### Step 6.2: Manual Testing Checklist

**Test each refactored script:**

```bash
# Test admin scripts
./admin-tools/aws_vpn_admin.sh --help
./admin-tools/aws_vpn_admin.sh --environment staging
./admin-tools/setup_csr_s3_bucket.sh --profile staging --list-policies

# Test deployment scripts
./scripts/deploy.sh --help
./scripts/deploy.sh staging --profile staging

# Test configuration loading
source lib/profile_selector.sh
select_and_validate_profile --environment staging
show_profile_status
```

**Validate functionality:**

1. **Profile Detection**: Can detect all AWS profiles
2. **Environment Mapping**: Correctly maps profiles to environments
3. **Account Validation**: Validates account IDs correctly
4. **Interactive Selection**: Shows clear menu with all options
5. **Configuration Loading**: Loads correct environment configs
6. **AWS CLI Integration**: All AWS commands use correct profile
7. **Error Handling**: Clear error messages for all failure cases

### Step 6.3: Performance Testing

```bash
# Test selection speed
time (source lib/profile_selector.sh && detect_available_profiles)

# Test configuration loading speed
time (source lib/profile_selector.sh && load_environment_config "staging")

# Test admin script startup time
time ./admin-tools/aws_vpn_admin.sh --profile staging --help
```

## Rollback Procedures

### Emergency Rollback

```bash
# Quick rollback script
cat > emergency_rollback.sh << 'EOF'
#!/bin/bash

echo "🚨 Emergency Rollback - Restoring Original Files"

# Restore from backups
for backup in $(find . -name "*.backup" -type f); do
    original="${backup%.backup}"
    echo "Restoring: $original"
    cp "$backup" "$original"
done

# Restore deprecated files
if [[ -d deprecated ]]; then
    echo "Restoring deprecated files..."
    cp deprecated/vpn_env.sh admin-tools/ 2>/dev/null || true
    cp deprecated/env_manager.sh lib/ 2>/dev/null || true
    cp deprecated/enhanced_env_selector.sh . 2>/dev/null || true
fi

echo "✅ Rollback complete. Please test functionality."
EOF

chmod +x emergency_rollback.sh
```

### Gradual Rollback

```bash
# Rollback individual scripts as needed
rollback_script() {
    local script="$1"
    if [[ -f "${script}.backup" ]]; then
        cp "${script}.backup" "$script"
        echo "Rolled back: $script"
    else
        echo "No backup found for: $script"
    fi
}

# Usage:
# rollback_script "admin-tools/aws_vpn_admin.sh"
```

## Success Validation

### Key Success Metrics

1. **✅ No vpn_env.sh usage required**
2. **✅ All admin scripts accept --profile and --environment parameters**
3. **✅ Interactive profile selection works in all scripts**
4. **✅ Account validation prevents wrong-environment operations**
5. **✅ No hidden state files (.current_env)**
6. **✅ Consistent user experience across all scripts**
7. **✅ No functionality regression**
8. **✅ Improved error messages and help documentation**

### Final Verification Commands

```bash
# Verify no old dependencies remain
echo "Checking for old dependencies..."
grep -r "env_manager.sh" . --include="*.sh" && echo "❌ Found env_manager.sh usage" || echo "✅ No env_manager.sh usage"
grep -r "\.current_env" . --include="*.sh" && echo "❌ Found .current_env usage" || echo "✅ No .current_env usage"

# Verify new functionality works
echo "Testing new functionality..."
./test_refactored_toolkit.sh

# Check all scripts have help
for script in admin-tools/*.sh scripts/*.sh; do
    if [[ -x "$script" ]]; then
        echo "Testing help for: $script"
        "$script" --help &>/dev/null && echo "  ✅ Help available" || echo "  ❌ Help missing"
    fi
done

echo "🎉 Toolkit refactoring validation complete!"
```

## Timeline Summary

- **Week 1**: Create profile_selector.sh and test core functionality
- **Week 2**: Refactor 3-4 admin scripts and test thoroughly
- **Week 3**: Update deployment scripts and configuration loading
- **Week 4**: Complete refactoring, testing, and documentation

**Total Effort**: ~20-30 hours of implementation + testing
**Risk Level**: Medium (can be rolled back at any point)
**Benefits**: Simplified, safer, more maintainable VPN toolkit

---

*This implementation guide provides step-by-step instructions to transform the VPN toolkit from a stateful to a stateless, explicit profile selection system.*