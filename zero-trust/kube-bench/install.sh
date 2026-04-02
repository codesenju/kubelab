#!/bin/bash
set -euo pipefail
VERSION=0.15.0

# Get OS
if [[ $(uname) == "Linux" ]]; then
  OS=linux
else
  OS=darwin
fi

# Get CPU Architecture
if [[ $(uname -m) == "x86_64" ]]; then
  ARCH="x86_64"
else
  ARCH="arm64"
fi

echo "Downloading binary file..."

curl -LOs https://github.com/aquasecurity/kube-bench/releases/download/v${VERSION}/kube-bench_${VERSION}_${OS}_${ARCH}.tar.gz

tar -xf kube-bench_${VERSION}_${OS}_${ARCH}.tar.gz
chmod +x kube-bench

echo "Installation complete!"