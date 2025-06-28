#!/bin/bash

# Build script for Lambda layer
# This script compiles TypeScript and creates proper layer structure

set -e

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

print_status() {
    echo -e "${YELLOW}==>${NC} $1"
}

print_success() {
    echo -e "${GREEN}✓${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
}

# Get script directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$SCRIPT_DIR"

print_status "Building shared Lambda layer..."

# Clean up old builds
rm -rf dist layer-package

# Compile TypeScript
print_status "Compiling TypeScript..."
npx tsc

# Create layer structure
print_status "Creating layer structure..."
mkdir -p layer-package/nodejs

# Copy compiled JavaScript files to nodejs directory
cp -r dist/* layer-package/nodejs/

# Copy package.json for dependencies (if needed)
if [ -f package.json ]; then
    cp package.json layer-package/nodejs/
fi

print_success "Layer build completed successfully"
print_status "Layer structure:"
find layer-package -type f -name "*.js" | sort