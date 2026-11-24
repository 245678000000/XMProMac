#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

CLT_FW="/Library/Developer/CommandLineTools/Library/Developer/Frameworks"
CLT_LIB="/Library/Developer/CommandLineTools/Library/Developer/usr/lib"

swift test --enable-swift-testing \
  -Xswiftc -F -Xswiftc "$CLT_FW" \
  -Xlinker -F -Xlinker "$CLT_FW" \
  -Xlinker -rpath -Xlinker "$CLT_FW" \
  -Xlinker -rpath -Xlinker "$CLT_LIB"
