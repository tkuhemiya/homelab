#!/usr/bin/env bash
# k0sctl, kubectl and the flux CLI on coop, pinned and checked against the published
# checksums. Run as root; safe to re-run, and a version bump here upgrades in place.
set -euo pipefail

K0SCTL=v0.33.1
FLUX=2.10.0
KUBECTL=v1.36.4   # the cluster's version; kubectl may differ from it by one minor

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fetch() { curl -fsSL --retry 3 -o "$2" "$1"; }

if [ "$(k0sctl version 2>/dev/null | awk '/^version:/ {print $2}')" != "$K0SCTL" ]; then
  base=https://github.com/k0sproject/k0sctl/releases/download/$K0SCTL
  fetch "$base/k0sctl-linux-amd64" "$tmp/k0sctl-linux-amd64"
  fetch "$base/checksums.txt" "$tmp/sums"
  (cd "$tmp" && grep -E '[ *]k0sctl-linux-amd64$' sums | sha256sum -c -)
  install -m 0755 "$tmp/k0sctl-linux-amd64" /usr/local/bin/k0sctl
fi

if [ "$(kubectl version --client -o json 2>/dev/null | grep -m1 '"gitVersion"' | cut -d'"' -f4)" != "$KUBECTL" ]; then
  base=https://dl.k8s.io/release/$KUBECTL/bin/linux/amd64
  fetch "$base/kubectl" "$tmp/kubectl"
  fetch "$base/kubectl.sha256" "$tmp/kubectl.sha256"
  echo "$(cat "$tmp/kubectl.sha256")  $tmp/kubectl" | sha256sum -c -
  install -m 0755 "$tmp/kubectl" /usr/local/bin/kubectl
fi

if [ "$(flux --version 2>/dev/null | awk '{print $3}')" != "$FLUX" ]; then
  base=https://github.com/fluxcd/flux2/releases/download/v$FLUX
  fetch "$base/flux_${FLUX}_linux_amd64.tar.gz" "$tmp/flux.tar.gz"
  fetch "$base/flux_${FLUX}_checksums.txt" "$tmp/sums"
  (cd "$tmp" && grep -E "[ *]flux_${FLUX}_linux_amd64.tar.gz\$" sums | sed 's/flux_.*tar.gz/flux.tar.gz/' | sha256sum -c -)
  tar -xzf "$tmp/flux.tar.gz" -C "$tmp" flux
  install -m 0755 "$tmp/flux" /usr/local/bin/flux
fi
