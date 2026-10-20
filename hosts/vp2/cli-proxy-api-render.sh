#!/usr/bin/env bash
# Render CLIProxyAPI's config (base template + live model lists) and restart the
# service if the result changed. Pass --restart to restart regardless.
# Run as root, by cli-proxy-api.sh and by the daily cli-proxy-api-refresh timer.
set -euo pipefail
cd "$(dirname "$0")"

tmp=$(mktemp -d)   # 0700: the rendered config holds keys
trap 'rm -rf "$tmp"' EXIT

doppler secrets substitute cli-proxy-api.yaml.tmpl > "$tmp/config.yaml"
doppler run -- python3 cli-proxy-api-upstreams.py >> "$tmp/config.yaml"

# The live config can't be compared directly (the server hashes the management key
# in it on startup), so compare against a root-only copy of the last render.
last=/var/lib/cliproxyapi/.last-render
if ! cmp -s "$tmp/config.yaml" "$last" || [ "${1:-}" = --restart ]; then
  # (install can't read from a pipe, hence the temp file.)
  install -o cliproxy -g cliproxy -m 0600 "$tmp/config.yaml" /var/lib/cliproxyapi/config.yaml
  install -o root -g root -m 0600 "$tmp/config.yaml" "$last"
  systemctl restart cli-proxy-api
  echo "cli-proxy-api: config rendered, service restarted"
fi
