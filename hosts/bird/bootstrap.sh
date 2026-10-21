#!/usr/bin/env bash
# bird: k0s worker that may drop out (later). Run as root from the repo checkout; safe to re-run.
set -euo pipefail
cd "$(dirname "$0")"

# bird started as a clone of coop's disk and kept the name "coop".
hostnamectl set-hostname bird
sed -i "s/^127\.0\.1\.1.*/127.0.1.1 bird/" /etc/hosts

../common/bootstrap.sh
../common/vector.sh
../common/agents.sh
