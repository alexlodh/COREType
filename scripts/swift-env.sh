#!/bin/bash
# Keep all compiler/SwiftPM caches inside this project.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/cache .build/config .build/security .build/modules
export CLANG_MODULE_CACHE_PATH="$PWD/.build/modules"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/modules"
swift "$@" --build-system native --disable-sandbox --cache-path .build/cache --config-path .build/config --security-path .build/security --scratch-path .build
