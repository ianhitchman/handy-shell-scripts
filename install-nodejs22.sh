#!/bin/bash

set -e

echo "🔍 Checking for latest Node.js v22 version..."

# Fetch and parse the latest v22 version using jq
LATEST_VERSION=$(curl -s https://nodejs.org/dist/index.json | jq -r '.[] | select(.version | test("^v22")) | .version' | head -n 1)

VERSION_NUMBER=${LATEST_VERSION#v}

if [ -z "$LATEST_VERSION" ]; then
  echo "❌ Failed to fetch latest Node.js v22 version."
  exit 1
fi

echo "✅ Latest v22 version is $LATEST_VERSION"

TARBALL="node-${LATEST_VERSION}-linux-x64.tar.xz"
URL="https://nodejs.org/dist/${LATEST_VERSION}/${TARBALL}"

cd /usr/local/src

echo "📥 Downloading $TARBALL..."
curl -O "$URL"

echo "📦 Extracting..."
tar -xf "$TARBALL"

echo "🧹 Removing existing /usr/local/node22 (if any)..."
rm -rf /usr/local/node22

echo "📁 Moving new version to /usr/local/node22..."
mv "node-${LATEST_VERSION}-linux-x64" /usr/local/node22

echo "🔗 Updating symlinks..."
ln -sf /usr/local/node22/bin/node /usr/local/bin/node
ln -sf /usr/local/node22/bin/npm /usr/local/bin/npm

echo "✅ Node.js $(node -v) installed successfully."
echo "🧹 Cleaning up..."
rm -f "$TARBALL"