# Per-user half of agents.sh, run as the agent user. Installs what's missing and
# leaves the rest alone: every tool here updates itself (T3 through its update button).
set -euo pipefail
export PATH="$HOME/.local/bin:$PATH"

# T3 Code from the nightly channel, the same train as the desktop app.
t3 --version >/dev/null 2>&1 || curl -fsSL https://t3.codes/install.sh | T3CODE_CHANNEL=nightly sh
command -v claude >/dev/null || curl -fsSL https://claude.ai/install.sh | bash
command -v codex >/dev/null || curl -fsSL https://releases.openai.com/codex/install.sh | sh
command -v agent >/dev/null || curl -fsS https://cursor.com/install | bash

# The VPSes' login user is ubuntu, not ours.
mkdir -p ~/.ssh && chmod 700 ~/.ssh
grep -qx 'Host vp1 vp2' ~/.ssh/config 2>/dev/null || printf 'Host vp1 vp2\n  User ubuntu\n' >> ~/.ssh/config

systemctl --user is-active --quiet t3code.service || t3 service install
