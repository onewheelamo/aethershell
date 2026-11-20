#!/usr/bin/env bash
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE/as-core"
cargo build --release
cp -f target/release/as-core ../../core/as-core
chmod +x ../../core/as-core
echo "Built dev/core/as-core ($(du -h ../../core/as-core | cut -f1))"
