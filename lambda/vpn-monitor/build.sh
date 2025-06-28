#!/bin/bash

# Build script for vpn-monitor Lambda function
# Ensures consistent TypeScript compilation for CDK deployment

set -e

echo "Building vpn-monitor Lambda function..."

# Clean previous build
rm -rf dist/

# Compile TypeScript
npx tsc

# Ensure files are in the correct location for CDK
if [ -f "dist/vpn-monitor/index.js" ]; then
    echo "Moving compiled files to correct CDK location..."
    mv dist/vpn-monitor/index.js dist/index.js
    mv dist/vpn-monitor/index.d.ts dist/index.d.ts
    rmdir dist/vpn-monitor/
fi

echo "✅ vpn-monitor build completed successfully"
echo "📁 Output: dist/index.js, dist/index.d.ts"