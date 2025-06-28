#!/bin/bash

# Build script for slack-handler Lambda function
# Ensures consistent TypeScript compilation for CDK deployment

set -e

echo "Building slack-handler Lambda function..."

# Clean previous build
rm -rf dist/

# Compile TypeScript
npx tsc

# Ensure files are in the correct location for CDK
if [ -f "dist/slack-handler/index.js" ]; then
    echo "Moving compiled files to correct CDK location..."
    mv dist/slack-handler/index.js dist/index.js
    mv dist/slack-handler/index.d.ts dist/index.d.ts
    rmdir dist/slack-handler/
fi

echo "✅ slack-handler build completed successfully"
echo "📁 Output: dist/index.js, dist/index.d.ts"