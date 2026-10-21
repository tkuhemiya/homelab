#!/usr/bin/env bash
# Vector: ship the systemd journal to Axiom (dataset "homelab").
# Needs AXIOM_TOKEN in Doppler prd. Run as root; safe to re-run.
set -euo pipefail
cd "$(dirname "$0")"

if ! command -v vector >/dev/null; then
  bash -c "$(curl -L https://setup.vector.dev)"
  apt-get install -y vector
fi

install -m 0644 vector.yaml /etc/vector/vector.yaml

# Vector >= 0.60 only expands ${VARS} in its config when this flag is set.
# Fetch first: a failure inside echo "$(...)" wouldn't stop the script under set -e.
token=$(doppler secrets get AXIOM_TOKEN --plain)
umask 077
{
  echo "AXIOM_TOKEN=$token"
  echo "VECTOR_DANGEROUSLY_ALLOW_ENV_VAR_INTERPOLATION=true"
} > /etc/default/vector

systemctl enable vector
systemctl restart vector
