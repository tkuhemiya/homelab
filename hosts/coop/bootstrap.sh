#!/usr/bin/env bash
# coop: k0s controller + worker (later). Run as root from the repo checkout; safe to re-run.
set -euo pipefail
cd "$(dirname "$0")"

../common/bootstrap.sh
../common/vector.sh
