#!/bin/bash

# Build script for vpn-control Lambda function
# Ensures consistent TypeScript compilation for CDK deployment

set -e

echo "Building vpn-control Lambda function..."

# Clean previous build
rm -rf dist/

# Compile TypeScript
npx tsc

# Ensure files are in the correct location for CDK
if [ -f "dist/vpn-control/index.js" ]; then
    echo "Moving compiled files to correct CDK location..."
    mv dist/vpn-control/index.js dist/index.js
    mv dist/vpn-control/index.d.ts dist/index.d.ts
    rmdir dist/vpn-control/
fi

echo "✅ vpn-control build completed successfully"
echo "📁 Output: dist/index.js, dist/index.d.ts"