#!/usr/bin/env bash
# coop: k0s controller + worker, and where k0sctl and flux run. Run as root from the repo checkout; safe to re-run.
set -euo pipefail
cd "$(dirname "$0")"

../common/bootstrap.sh
../common/vector.sh
../common/agents.sh
./cluster-tools.sh
./cluster-access.sh
