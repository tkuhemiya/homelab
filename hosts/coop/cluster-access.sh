#!/usr/bin/env bash
# k0sctl runs on coop and logs in as root on every node, coop included. Tailscale SSH
# only answers connections from other machines, so coop logging in to itself falls
# through to plain OpenSSH, which needs a key. Run as root; safe to re-run.
set -euo pipefail

USER_NAME=${AGENT_USER:-themiya}
home=$(getent passwd "$USER_NAME" | cut -d: -f6)
key=$home/.ssh/id_ed25519

[ -f "$key" ] ||
  runuser -u "$USER_NAME" -- ssh-keygen -q -t ed25519 -N '' -C "$USER_NAME@$(hostname) k0sctl" -f "$key"

install -d -m 700 /root/.ssh
touch /root/.ssh/authorized_keys
chmod 600 /root/.ssh/authorized_keys
grep -qxF "$(cat "$key.pub")" /root/.ssh/authorized_keys || cat "$key.pub" >> /root/.ssh/authorized_keys

# Trust the nodes' host keys now, so k0sctl never stops at the yes/no prompt.
# bird may be switched off; that's fine, run this again when it's up.
for host in coop bird; do
  runuser -u "$USER_NAME" -- sh -c "ssh-keygen -F $host >/dev/null 2>&1 || ssh-keyscan -T 5 $host 2>/dev/null >> '$home/.ssh/known_hosts'" || true
done
