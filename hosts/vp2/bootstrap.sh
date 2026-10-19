#!/usr/bin/env bash
# vp2: CLIProxyAPI. Run as root from the repo checkout; safe to re-run.
set -euo pipefail
cd "$(dirname "$0")"

../common/bootstrap.sh
../common/earlyoom.sh
../common/vector.sh
./cli-proxy-api.sh
