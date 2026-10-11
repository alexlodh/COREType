#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
bash scripts/swift-env.sh build --product CoreChecks -c debug
binary_dir=$(bash scripts/swift-env.sh build -c debug --show-bin-path)
"$binary_dir/CoreChecks"
