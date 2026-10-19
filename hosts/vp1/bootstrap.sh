#!/usr/bin/env bash
# vp1: Gatus, Beszel hub. Run as root from the repo checkout; safe to re-run.
set -euo pipefail
cd "$(dirname "$0")"

../common/bootstrap.sh
../common/vps-trim.sh
../common/earlyoom.sh
../common/vector.sh
