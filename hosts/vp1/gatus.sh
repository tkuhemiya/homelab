#!/usr/bin/env bash
# Gatus: uptime checks with ntfy alerts, UI at http://vp1:8080 (tailnet only).
# Built from source: Gatus ships no Linux binaries, only a Docker image.
# Run as root; safe to re-run.
set -euo pipefail
cd "$(dirname "$0")"

VERSION=v5.37.0

command -v go >/dev/null || apt-get install -y golang-go
installed=$(go version -m /usr/local/bin/gatus 2>/dev/null | awk '$1 == "mod" {print $3}' || true)
if [ "$installed" != "$VERSION" ]; then
  # A cold build takes ~20 minutes on a 1 GB / 2-core VPS; -p=1 keeps memory down.
  # /tmp is a 476 MB RAM disk on Ubuntu 26.04, too small for Go's linker: use disk.
  mkdir -p /var/tmp/go-build
  GOBIN=/usr/local/bin GOTMPDIR=/var/tmp/go-build CGO_ENABLED=0 GOFLAGS=-p=1 \
    go install -trimpath "github.com/TwiN/gatus/v5@$VERSION"
fi

id gatus >/dev/null 2>&1 ||
  useradd --system --home-dir /var/lib/gatus --create-home --shell /usr/sbin/nologin gatus
install -d -o root -g gatus -m 0750 /etc/gatus

# Config holds the ntfy topic (and Healthchecks URL): readable by root and gatus only.
# (install can't read from a pipe, so render to a private temp file first.)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
doppler secrets substitute gatus.yaml.tmpl > "$tmp/config.yaml"
install -o root -g gatus -m 0640 "$tmp/config.yaml" /etc/gatus/config.yaml

install -m 0644 gatus.service /etc/systemd/system/gatus.service
systemctl daemon-reload
systemctl enable gatus
systemctl restart gatus
