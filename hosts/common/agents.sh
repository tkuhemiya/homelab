#!/usr/bin/env bash
# Coding agents (Claude Code, Codex, Cursor) and the T3 Code server, for one user.
# T3 Code is published on the tailnet at https://<host>.<tailnet>.ts.net through
# Tailscale Serve. Run as root; safe to re-run. Logging in to each agent is manual.
set -euo pipefail
cd "$(dirname "$0")"

AGENT_USER=${AGENT_USER:-themiya}
uid=$(id -u "$AGENT_USER")

command -v tmux >/dev/null && command -v gh >/dev/null || apt-get install -y tmux gh

# Keep the user's systemd manager (and so the T3 service) running with nobody
# logged in, and let the user manage Tailscale Serve (`t3 pair --tailscale`).
loginctl enable-linger "$AGENT_USER"
tailscale set --operator="$AGENT_USER"
for _ in $(seq 30); do [ -S "/run/user/$uid/bus" ] && break; sleep 1; done

runuser -u "$AGENT_USER" -- env -i HOME="$(getent passwd "$AGENT_USER" | cut -d: -f6)" \
  USER="$AGENT_USER" XDG_RUNTIME_DIR="/run/user/$uid" \
  DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$uid/bus" \
  PATH="/usr/local/bin:/usr/bin:/bin" bash -s < agents-user.sh

# T3 listens on 127.0.0.1:3773; Serve adds HTTPS on the tailnet name.
tailscale serve --bg --https=443 http://127.0.0.1:3773
