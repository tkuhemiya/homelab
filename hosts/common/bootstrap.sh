#!/usr/bin/env bash
# Base setup for every lab host. Run as root; safe to re-run.
set -euo pipefail

if ! command -v doppler >/dev/null; then
  rm -f /etc/apt/sources.list.d/doppler-cli.list   # a half-finished earlier run breaks apt-get update
  apt-get update
  apt-get install -y ca-certificates curl gnupg
  curl -sLf --retry 3 --tlsv1.2 --proto "=https" \
    'https://packages.doppler.com/public/cli/gpg.DE2A7741A397C129.key' \
    | gpg --dearmor --yes -o /usr/share/keyrings/doppler-archive-keyring.gpg
  chmod 0644 /usr/share/keyrings/doppler-archive-keyring.gpg   # apt reads it as _apt
  echo "deb [signed-by=/usr/share/keyrings/doppler-archive-keyring.gpg] https://packages.doppler.com/public/cli/deb/debian any-version main" \
    > /etc/apt/sources.list.d/doppler-cli.list
  apt-get update
  apt-get install -y doppler
fi
