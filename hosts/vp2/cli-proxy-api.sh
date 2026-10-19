#!/usr/bin/env bash
# CLIProxyAPI: the tailnet's LLM gateway, http://vp2:8317.
# Upstream keys come from Doppler prd; re-run after adding one. Run as root; safe to re-run.
set -euo pipefail
cd "$(dirname "$0")"

VERSION=8.0.35
tmp=$(mktemp -d)   # 0700: safe for the rendered config too
trap 'rm -rf "$tmp"' EXIT

installed=$(cli-proxy-api --help 2>&1 | sed -n 's/^CLIProxyAPI Version: \([^,]*\),.*/\1/p' || true)
if [ "$installed" != "$VERSION" ]; then
  base=https://github.com/router-for-me/CLIProxyAPI/releases/download/v$VERSION
  tarball=CLIProxyAPI_${VERSION}_linux_amd64_no-plugin.tar.gz
  curl -fsSL -o "$tmp/$tarball" "$base/$tarball"
  curl -fsSL -o "$tmp/checksums.txt" "$base/checksums.txt"
  (cd "$tmp" && grep " $tarball\$" checksums.txt | sha256sum -c --quiet)
  tar xzf "$tmp/$tarball" -C "$tmp" cli-proxy-api
  install -m 0755 "$tmp/cli-proxy-api" /usr/local/bin/cli-proxy-api
fi

id cliproxy >/dev/null 2>&1 ||
  useradd --system --home-dir /var/lib/cliproxyapi --create-home --shell /usr/sbin/nologin cliproxy
install -d -o cliproxy -g cliproxy -m 0750 /var/lib/cliproxyapi
install -d -o cliproxy -g cliproxy -m 0700 /var/lib/cliproxyapi/auths

# The config lives in the service's own writable dir, not /etc: on startup the
# server rewrites it (hashing the management key), the web UI saves edits to it,
# and it downloads the UI into static/ next to it.
# (install can't read from a pipe, so render to a private temp file first.)
doppler secrets substitute cli-proxy-api.yaml.tmpl > "$tmp/config.yaml"
install -o cliproxy -g cliproxy -m 0600 "$tmp/config.yaml" /var/lib/cliproxyapi/config.yaml

install -m 0644 cli-proxy-api.service /etc/systemd/system/cli-proxy-api.service
systemctl daemon-reload
systemctl enable cli-proxy-api
systemctl restart cli-proxy-api
