#!/usr/bin/env bash
# earlyoom for the 1 GB VPSes: kill an agent before the box thrashes,
# and never kill the things that keep it reachable.
set -euo pipefail

apt-get install -y earlyoom
cat > /etc/default/earlyoom <<'EOF'
EARLYOOM_ARGS="-r 3600 -m 10 -s 50 --prefer (^|/)(node|claude|codex|opencode)$ --avoid (^|/)(sshd|systemd|tailscaled|gatus|beszel|beszel-agent|cli-proxy-api)$"
EOF
systemctl enable earlyoom
systemctl restart earlyoom
