#!/bin/bash

# VPN Toolkit Profile Selection Library
# Replaces env_manager.sh with direct profile selection

# Global variables
SELECTED_AWS_PROFILE=""
SELECTED_ENVIRONMENT=""
PROJECT_ROOT=""

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
    local profile_lower=$(echo "$profile" | tr '[:upper:]' '[:lower:]')
    
    case "$profile_lower" in
        *staging*|*dev*|*test*)
            echo "staging"
            ;;
        *prod*|*production*)
            echo "prod"  # Map to "prod" to match directory structure
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
    local get_id_result=$?
    
    if [[ $get_id_result -ne 0 ]]; then
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
    
    echo "" >&2
    echo "=== AWS Profile Selection ===" >&2
    echo "" >&2
    
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
               "$index" "$highlight" "$profile" "$display_env" "$account_id" "$region" >&2
        ((index++))
    done
    
    echo "" >&2
    if [[ -n "$target_environment" ]]; then
        echo "⭐ = Recommended for environment: $target_environment" >&2
        echo "" >&2
    fi
    
    # Get user selection
    local choice
    while true; do
        echo -n "Select AWS Profile [1-${#profiles[@]}]: " >&2
        read choice
        
        if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "${#profiles[@]}" ]; then
            break
        else
            echo -e "${RED}[ERROR]${NC} Invalid selection. Please enter a number between 1 and ${#profiles[@]}" >&2
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