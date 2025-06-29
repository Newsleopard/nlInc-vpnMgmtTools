#!/bin/bash

# Test script for Profile Selector Library
source ./lib/profile_selector.sh

echo "=== Testing Profile Selector Library ==="

echo "1. Testing profile detection..."
profiles=($(detect_available_profiles))
echo "Found ${#profiles[@]} profiles: ${profiles[*]}"

if [[ ${#profiles[@]} -eq 0 ]]; then
    echo "❌ No profiles found - this might be expected if AWS CLI is not configured"
else
    echo "✅ Profile detection working"
fi

echo ""
echo "2. Testing environment mapping..."
for profile in "${profiles[@]}"; do
    env=$(map_profile_to_environment "$profile")
    echo "  $profile -> ${env:-"unknown"}"
done

echo ""
echo "3. Testing account ID retrieval..."
for profile in "${profiles[@]}"; do
    account=$(get_profile_account_id "$profile" 2>/dev/null || echo "failed")
    echo "  $profile -> $account"
done

echo ""
echo "4. Testing configuration loading..."
if load_environment_config "staging"; then
    echo "  ✅ Staging config loaded successfully"
    echo "  VPN_CONFIG_DIR: $VPN_CONFIG_DIR"
    echo "  VPN_LOG_DIR: $VPN_LOG_DIR"
    echo "  VPN_CERT_DIR: $VPN_CERT_DIR"
else
    echo "  ❌ Failed to load staging config"
fi

echo ""
echo "5. Testing project root detection..."
echo "  PROJECT_ROOT: $PROJECT_ROOT"
if [[ -n "$PROJECT_ROOT" && -d "$PROJECT_ROOT" ]]; then
    echo "  ✅ Project root detected correctly"
else
    echo "  ❌ Project root not detected"
fi

echo ""
echo "6. Testing function exports..."
declare -f detect_available_profiles &>/dev/null && echo "  ✅ detect_available_profiles exported" || echo "  ❌ detect_available_profiles not exported"
declare -f map_profile_to_environment &>/dev/null && echo "  ✅ map_profile_to_environment exported" || echo "  ❌ map_profile_to_environment not exported"
declare -f select_and_validate_profile &>/dev/null && echo "  ✅ select_and_validate_profile exported" || echo "  ❌ select_and_validate_profile not exported"

echo ""
echo "=== Test Complete ==="
echo ""
echo "Manual test available:"
echo "  source lib/profile_selector.sh"
echo "  select_and_validate_profile --interactive"