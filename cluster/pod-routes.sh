#!/usr/bin/env bash
# Publish each node's pod range as a Tailscale subnet route, so pods on different
# nodes reach each other without a tunnel (Tailscale drops IP-in-IP). Run on coop as
# the user that has kubectl access, after `k0sctl apply`; safe to re-run.
#
# A new or changed route has to be approved once in the Tailscale admin console,
# unless the tailnet policy has an autoApprovers rule for 10.244.0.0/16.
set -euo pipefail

status=0
# `ssh -n` below: without it ssh reads the loop's input and swallows the remaining nodes.
while read -r node cidr; do
  if [ -z "$cidr" ]; then
    echo "$node: no podCIDR yet" >&2
    status=1
    continue
  fi
  echo "$node advertises $cidr"
  ssh -n -o ConnectTimeout=10 "root@$node" \
    "tailscale set --advertise-routes=$cidr --accept-routes --snat-subnet-routes=false" ||
    { echo "$node: could not be reached, run this again when it is up" >&2; status=1; }
done < <(kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.name} {.spec.podCIDR}{"\n"}{end}')
exit $status
