#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
mkdir -p .build/cache .build/module-cache
export CLANG_MODULE_CACHE_PATH="$PWD/.build/module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/module-cache"
taskSubcommand="$1"
shift
exec swift "$taskSubcommand" --disable-sandbox --cache-path "$PWD/.build/cache" --scratch-path "$PWD/.build" "$@"
