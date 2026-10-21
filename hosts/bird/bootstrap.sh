#!/usr/bin/env bash
# bird: k0s worker that may drop out (later). Run as root from the repo checkout; safe to re-run.
set -euo pipefail
cd "$(dirname "$0")"

../common/bootstrap.sh
../common/vector.sh
../common/agents.sh
