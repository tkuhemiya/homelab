#!/usr/bin/env bash
# Strip cloud-image packages the VPSes don't need. Run as root; safe to re-run.
set -euo pipefail

# rpcbind listens on :111 on every interface; only NFS (nfs-common) needs it.
DEBIAN_FRONTEND=noninteractive apt-get purge -y rpcbind nfs-common
DEBIAN_FRONTEND=noninteractive apt-get autoremove -y
