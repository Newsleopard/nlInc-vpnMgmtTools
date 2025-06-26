#!/bin/bash

# Pre-deployment validation script
# Validates all prerequisites before deployment

set -e

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_status() { echo -e "${BLUE}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

validate_dependencies() {
    print_status "Validating dependencies..."
    
    # Check CDK dependencies
    if [ ! -d "$PROJECT_ROOT/cdklib/node_modules" ]; then
        print_error "CDK dependencies not installed"
        print_status "Run: cd cdklib && npm install"
        return 1
    fi
    
    # Check Lambda dependencies
    if [ ! -d "$PROJECT_ROOT/lambda/node_modules" ]; then
        print_error "Lambda dependencies not installed"
        print_status "Run: cd lambda && npm install"
        return 1
    fi
    
    print_success "Dependencies validated"
}

validate_aws_profiles() {
    print_status "Validating AWS profiles..."
    
    local staging_profile=${STAGING_PROFILE:-"default"}
    local production_profile=${PRODUCTION_PROFILE:-"prod"}
    
    # Test staging profile
    if ! aws sts get-caller-identity --profile "$staging_profile" &> /dev/null; then
        print_error "Staging AWS profile '$staging_profile' not configured"
        return 1
    fi
    
    # Test production profile
    if ! aws sts get-caller-identity --profile "$production_profile" &> /dev/null; then
        print_error "Production AWS profile '$production_profile' not configured"
        return 1
    fi
    
    print_success "AWS profiles validated"
}

validate_configurations() {
    print_status "Validating environment configurations..."
    
    # Check staging config
    if [ ! -f "$PROJECT_ROOT/configs/staging/staging.env" ]; then
        print_error "Staging configuration not found"
        return 1
    fi
    
    # Check production config
    if [ ! -f "$PROJECT_ROOT/configs/prod/prod.env" ]; then
        print_error "Production configuration not found"
        return 1
    fi
    
    print_success "Configurations validated"
}

main() {
    print_status "🔍 Pre-deployment validation starting..."
    
    validate_dependencies || exit 1
    validate_aws_profiles || exit 1
    validate_configurations || exit 1
    
    print_success "✅ All validations passed - ready for deployment"
}

main "$@"
