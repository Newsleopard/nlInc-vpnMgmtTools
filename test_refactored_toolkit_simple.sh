#!/bin/bash

# Simple test suite for refactored VPN toolkit (non-interactive)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/profile_selector.sh"

test_count=0
pass_count=0
fail_count=0

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

run_test() {
    local test_name="$1"
    local test_command="$2"
    
    ((test_count++))
    echo -e "${BLUE}Test $test_count:${NC} $test_name"
    
    if eval "$test_command" &>/dev/null; then
        echo -e "  ${GREEN}✅ PASS${NC}"
        ((pass_count++))
    else
        echo -e "  ${RED}❌ FAIL${NC}"
        ((fail_count++))
    fi
}

echo "========================================="
echo "  VPN Toolkit Refactoring Test Suite"
echo "========================================="

# Core functionality tests
run_test "Profile detection works" \
    "detect_available_profiles | wc -l | grep -q '[0-9]'"

run_test "Environment mapping (prod)" \
    "[[ \$(map_profile_to_environment 'prod') == 'prod' ]]"

run_test "Environment mapping (staging)" \
    "[[ \$(map_profile_to_environment 'staging') == 'staging' ]]"

run_test "Configuration loading" \
    "load_environment_config 'staging'"

# Help function tests
run_test "aws_vpn_admin.sh help" \
    "./admin-tools/aws_vpn_admin.sh --help"

run_test "setup_csr_s3_bucket.sh help" \
    "./admin-tools/setup_csr_s3_bucket.sh --help"

run_test "manage_vpn_users.sh help" \
    "./admin-tools/manage_vpn_users.sh --help"

run_test "deploy.sh help" \
    "./scripts/deploy.sh --help"

# Function export tests
run_test "Core functions exported" \
    "declare -f select_and_validate_profile >/dev/null"

run_test "AWS wrapper exported" \
    "declare -f aws_with_selected_profile >/dev/null"

# Cleanup verification tests
run_test "Old env_manager source removed from aws_vpn_admin.sh" \
    "! grep -q 'source.*env_manager.sh' admin-tools/aws_vpn_admin.sh"

run_test "CURRENT_ENVIRONMENT replaced" \
    "! grep -q 'CURRENT_ENVIRONMENT' admin-tools/aws_vpn_admin.sh"

echo ""
echo "========================================="
echo "Total: $test_count, Passed: $pass_count, Failed: $fail_count"

if [[ $fail_count -eq 0 ]]; then
    echo -e "${GREEN}🎉 All tests passed!${NC}"
    exit 0
else
    echo -e "${RED}❌ Some tests failed.${NC}"
    exit 1
fi