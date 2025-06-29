#!/bin/bash

# Comprehensive test suite for refactored VPN toolkit
# Tests all major scripts with the new profile selection system

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/profile_selector.sh"

# Test configuration
test_count=0
pass_count=0
fail_count=0
verbose=false

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_test_header() {
    echo ""
    echo "========================================="
    echo "  VPN Toolkit Refactoring Test Suite"
    echo "========================================="
    echo ""
}

run_test() {
    local test_name="$1"
    local test_command="$2"
    local expected_exit_code="${3:-0}"
    
    ((test_count++))
    echo -e "${BLUE}Test $test_count:${NC} $test_name"
    
    if [[ "$verbose" == true ]]; then
        echo "  Command: $test_command"
    fi
    
    # Run the test command
    local output
    local exit_code
    if [[ "$verbose" == true ]]; then
        output=$(eval "$test_command" 2>&1)
        exit_code=$?
        echo "  Output: $output"
    else
        output=$(eval "$test_command" 2>&1)
        exit_code=$?
    fi
    
    # Check result
    if [[ $exit_code -eq $expected_exit_code ]]; then
        echo -e "  ${GREEN}✅ PASS${NC}"
        ((pass_count++))
    else
        echo -e "  ${RED}❌ FAIL${NC} (Expected exit code $expected_exit_code, got $exit_code)"
        if [[ "$verbose" != true ]]; then
            echo "  Output: $output"
        fi
        ((fail_count++))
    fi
}

run_interactive_test() {
    local test_name="$1"
    local test_command="$2"
    
    ((test_count++))
    echo -e "${BLUE}Test $test_count (Interactive):${NC} $test_name"
    echo "  Command: $test_command"
    echo -e "  ${YELLOW}⏳ Manual verification required${NC}"
    
    read -p "  Press Enter to run this test, or 's' to skip: " -n 1 -r
    echo
    
    if [[ $REPLY =~ ^[Ss]$ ]]; then
        echo -e "  ${YELLOW}⏭️  SKIPPED${NC}"
        return
    fi
    
    # Run the interactive test
    echo "  Running: $test_command"
    if eval "$test_command"; then
        read -p "  Did the test pass correctly? (y/n): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            echo -e "  ${GREEN}✅ PASS${NC}"
            ((pass_count++))
        else
            echo -e "  ${RED}❌ FAIL${NC}"
            ((fail_count++))
        fi
    else
        echo -e "  ${RED}❌ FAIL${NC} (Command failed)"
        ((fail_count++))
    fi
}

show_test_results() {
    echo ""
    echo "========================================="
    echo "           Test Results Summary"
    echo "========================================="
    echo "Total Tests: $test_count"
    echo -e "Passed: ${GREEN}$pass_count${NC}"
    echo -e "Failed: ${RED}$fail_count${NC}"
    
    if [[ $fail_count -eq 0 ]]; then
        echo ""
        echo -e "${GREEN}🎉 All tests passed! Toolkit refactoring is successful.${NC}"
        return 0
    else
        echo ""
        echo -e "${RED}❌ Some tests failed. Please review the implementation.${NC}"
        return 1
    fi
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -v|--verbose)
            verbose=true
            shift
            ;;
        -h|--help)
            cat << EOF
VPN Toolkit Refactoring Test Suite

用法: $0 [OPTIONS]

Options:
  -v, --verbose    顯示詳細測試輸出
  -h, --help      顯示此幫助訊息

此測試套件會驗證 VPN 工具包重構後的功能，包括：
- Profile 選擇庫基本功能
- 管理員腳本的新參數支援
- 部署腳本增強功能
- 配置載入和驗證

EOF
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Start testing
print_test_header

echo "Testing Profile Selection Library..."

# Test 1: Profile detection
run_test "Profile detection functionality" \
    "source lib/profile_selector.sh && detect_available_profiles | wc -l | grep -q '[0-9]'"

# Test 2: Environment mapping
run_test "Environment mapping (prod profile)" \
    "source lib/profile_selector.sh && [[ \$(map_profile_to_environment 'prod') == 'prod' ]]"

# Test 3: Environment mapping
run_test "Environment mapping (staging profile)" \
    "source lib/profile_selector.sh && [[ \$(map_profile_to_environment 'staging') == 'staging' ]]"

# Test 4: Configuration validation
run_test "Staging configuration loading" \
    "source lib/profile_selector.sh && load_environment_config 'staging'"

# Test 5: Help functions work
echo ""
echo "Testing Admin Scripts Help Functions..."

run_test "aws_vpn_admin.sh help" \
    "./admin-tools/aws_vpn_admin.sh --help"

run_test "setup_csr_s3_bucket.sh help" \
    "./admin-tools/setup_csr_s3_bucket.sh --help"

run_test "manage_vpn_users.sh help" \
    "./admin-tools/manage_vpn_users.sh --help"

run_test "sign_csr.sh help" \
    "./admin-tools/sign_csr.sh --help"

# Test 6: Deployment script
echo ""
echo "Testing Deployment Scripts..."

run_test "deploy.sh help" \
    "./scripts/deploy.sh --help"

run_test "setup-parameters.sh help" \
    "./scripts/setup-parameters.sh --help"

# Test 7: Profile selector functions are exported
echo ""
echo "Testing Function Exports..."

run_test "Profile selector functions exported" \
    "source lib/profile_selector.sh && declare -f select_and_validate_profile >/dev/null"

run_test "AWS wrapper function exported" \
    "source lib/profile_selector.sh && declare -f aws_with_selected_profile >/dev/null"

# Interactive tests (require user input)
echo ""
echo "Interactive Tests (require manual verification)..."

if command -v aws &> /dev/null; then
    run_interactive_test "Profile selection interactive menu" \
        "source lib/profile_selector.sh && select_profile_interactive"
    
    run_interactive_test "Admin script with profile selection" \
        "./admin-tools/aws_vpn_admin.sh --environment staging"
else
    echo -e "${YELLOW}⏭️  AWS CLI not available, skipping interactive tests${NC}"
fi

# Test cleanup verification
echo ""
echo "Testing Cleanup Verification..."

run_test "Old environment manager not loaded" \
    "! grep -q 'env_manager.sh' admin-tools/aws_vpn_admin.sh"

run_test "CURRENT_ENVIRONMENT replaced with SELECTED_ENVIRONMENT" \
    "! grep -q 'CURRENT_ENVIRONMENT' admin-tools/aws_vpn_admin.sh"

run_test "Environment state file not referenced" \
    "! grep -q '\\.current_env' admin-tools/aws_vpn_admin.sh"

# Show final results
show_test_results