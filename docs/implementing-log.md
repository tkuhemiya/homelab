# Implementation log

A running record of what was decided, what broke, how it was fixed, and why. Newest
phase at the bottom. Written as raw material for a blog post, so it keeps the dead
ends and the reasoning, not just the final state.

Each entry is tagged:

- **Decision**: a choice, with the reasoning behind it.
- **Problem**: something that broke, how it was found, and the fix.
- **Lesson**: something worth remembering beyond this lab.

---

## 2026-10-19: Starting point

The plan began as one design doc ([design.md](design.md)): a single k0s cluster across
every machine, agents running on bare metal beside it, free provider tiers plugged in
as burst capacity, and everything inside a Tailscale tailnet. A second doc
([free-resources.md](free-resources.md)) lists the free tiers available.

The machines:

| Node | What it is |
|---|---|
| coop | 6 cores / 8 GB at home, Ubuntu 26.04 |
| bird | 4 cores / 8 GB at home |
| vp1, vp2 | 2 cores / ~950 MB cloud VPSes, Ubuntu 26.04, 4 GB swap file + zram |

**Decision: shrink the cluster to coop and bird.** The design originally had all four
machines in k0s. Answering its open questions changed that:

- coop is on 24/7.
- bird is switched off and on almost daily.
- vp1 and vp2 stay plain systemd hosts. The cluster uses their services
  (CLIProxyAPI, Gatus) as external services.
- No free cloud VMs join the cluster.

Why: a 1 GB VPS can't spare memory for a kubelet, and the services on the VPSes must
survive home outages, which works better outside the cluster. So everything has to fit
on coop alone, and bird is bonus capacity.

**Decision: how the work is done.** The point of the lab is to learn the parts. So:

- I (the human) run the steps myself, and the AI assistant explains, checks and
  debugs. Later I handed some steps over to the assistant entirely.
- **Every component is done by hand on one machine first, then written into a
  script.** Doing it by hand first shows what goes wrong, so the script captures real
  lessons instead of guesses.
- Every script must be safe to run again. "Change the config, re-run the script" is
  the whole update process.

---

## 2026-10-20: Phase 1, Foundation

### The repo

**Decision: public GitHub repo** (`tkuhemiya/homelab`). Public repos get unlimited
GitHub Actions minutes. The cost is that hostnames, tailnet IPs and the service layout
are visible, which is acceptable because no secrets are ever committed: configs are
templates, and the values come from Doppler at install time. `.gitignore` blocks
rendered configs, `.env` files and kubeconfigs as a safety net.

The design docs moved into `docs/`.

### Burst jobs stay off the tailnet

**Decision: burst jobs never join the tailnet.** The first draft of the tailnet policy
had a `tag:burst` rule that let burst jobs reach only the LLM gateway. I questioned
why a job running on Modal's hardware would need to reach my network at all. The
answer: it doesn't, by default. The lab always initiates (submit, poll, fetch results)
through each provider's API, and the job only talks to the public internet.

Joining the tailnet would only matter if a job needed something that exists only
inside it, such as the LLM gateway. I couldn't think of a real use case, so it's out.
A job that needs an LLM uses a free API key directly.

**Lesson:** a tailnet policy only controls traffic *inside* the tailnet. It does nothing
to a job's normal internet access.

### Tailnet policy: open, not locked down

**Decision: no access restrictions inside the tailnet.** The first draft followed
least-privilege thinking: tags per role, agents limited to some machines, SSH rules
per tag. I chose to keep everything open instead:

> I trust my agents enough to do things correctly. If not, I would not be running them
> with this amount of access. This is a decision I have taken and I own up to it.

The tailnet edge is the security boundary. Inside it, every device of mine reaches
every other, and agents get the same access I have. Tailscale identity is per device,
so an agent and a service on the same machine look identical, and under this model
that doesn't matter.

**Lesson: "open" still needs a policy.** There's no "no policy" option. Every tailnet
has one, and Tailscale SSH denies everything unless a rule allows it. The final policy
is about 10 lines:

```hujson
{
  "grants": [{"src": ["*"], "dst": ["*"], "ip": ["*"]}],
  "ssh": [{"action": "accept", "src": ["autogroup:member"], "dst": ["autogroup:self"],
           "users": ["autogroup:nonroot", "root"]}],
}
```

**Decision: no tags.** Tags only exist so rules can target groups of machines, and an
open policy has no such rules. They come back in Phase 2 only because the Tailscale
Kubernetes operator requires them. The catch with untagged machines is that their
login expires after 180 days, which would silently drop a server off the tailnet. Fix:
"Disable key expiry" on each server in the admin console.

**Decision: Tailnet Lock comes last.** Once it's on, every new device has to be signed
in by hand, which would slow down setup.

### Tailscale SSH

**Problem: `tailscale up` doesn't turn on Tailscale SSH.** I assumed it did. Checking
`tailscale debug prefs` on each server showed `"RunSSH": false`. It needs a separate
`sudo tailscale set --ssh`. Until then, `ssh coop` was ordinary SSH with keys, just
over the tailnet address.

**Problem: `ssh vp1` from coop failed** with "tailnet policy does not permit you to SSH
as user themiya". There were two causes, one hidden behind the other:

1. **Wrong username.** On coop I'm `themiya`, so a plain `ssh vp1` logs in as
   `themiya`, and only `ubuntu` exists on the VPSes. Fix: a `~/.ssh/config` on coop
   with `User ubuntu` for vp1 and vp2.
2. **Tailscale's default policy uses "check" mode for SSH**, which means a browser
   login every 12 hours. With the right username, the assistant got a login link
   instead of a shell. An agent can't click a link, so "check" mode rules out agents
   hopping between machines. Fix: the open policy above, with `"action": "accept"`.

**Problem: the Mac was reaching the VPSes over the public internet.** The Mac's
`~/.ssh/config` had vp1 and vp2 set to their **public** IPs, so those connections
bypassed Tailscale entirely and used ordinary SSH. That showed up as
`Connection to 129.159.20.115 closed`. Fix: `HostName vp1` / `HostName vp2`, so the
connection goes through the tailnet. Check with
`ssh -v vp2 true 2>&1 | grep "remote software version"`, which should mention
Tailscale.

### Secrets: Doppler

**Decision: Doppler for third-party secrets; tailnet identity for everything
internal.** It's hosted, so it keeps working through home outages. The free plan
allows read-only service tokens per config.

**Decision: one `prd` config shared by every host.** The first plan was a config per
trust zone (home, vp1, vp2, agents), using branch configs that inherit shared secrets.
It was tedious to set up, and with open access inside the tailnet, splitting secrets
by zone wasn't buying much. Final setup: one `homelab` project, one `prd` config, and
**one read-only service token per host**. A token per host costs nothing and means a
single host's access can be revoked without touching the others.

**Lesson: a personal login and a service token behave differently.** On the Mac,
`doppler secrets` failed with "You must specify a config". Logged in as yourself, you
can see every config, so the CLI asks which one. A service token is tied to exactly one
config, so on the servers no config name is needed. Fix for the repo folder:
`doppler setup --project homelab --config prd`.

**Problem: the token install command looked frozen.** `read -rs DT` waits for input
without showing a prompt or echoing what you paste, so it looks hung. Fix: use a
visible prompt, and set the token in a separate step:

```sh
read -rsp "Doppler token: " DT; echo
sudo doppler configure set token="$DT" --scope /
unset DT
```

`--scope /` makes the token apply in every directory. `sudo` stores it in root's
config, because the services that need it run as root.

### Bootstrap scripts

Layout: `hosts/common/*.sh` for shared pieces, and `hosts/<node>/bootstrap.sh` calling
whichever pieces that machine needs. Each server clones the repo to `/root/homelab`
(the scripts run as root anyway) and runs its own bootstrap script. To update:
`sudo git -C /root/homelab pull && sudo /root/homelab/hosts/<node>/bootstrap.sh`.

### earlyoom on the VPSes

Why it's needed: with ~950 MB of RAM, Linux's own out-of-memory killer steps in very
late, after the box has slowed to a crawl, and sometimes kills the wrong process, such
as `tailscaled`, which cuts off access to the server.

**Problem: the default settings act far too late with a large swap file.** earlyoom acts
only when free RAM *and* free swap are both below their thresholds. The default swap
threshold is 10%, and these VPSes have a 4 GB swap file, so earlyoom would wait until
about 3.6 GB of slow disk swap was used. Fix: `-s 50`.

Final settings:

```
EARLYOOM_ARGS="-r 3600 -m 10 -s 50 --prefer (^|/)(node|claude|codex|opencode)$ --avoid (^|/)(sshd|systemd|tailscaled|gatus|beszel|beszel-agent|cli-proxy-api)$"
```

Agents are killed first; SSH, Tailscale and the lab services are protected.

**Lesson: no quotes inside `EARLYOOM_ARGS`.** systemd passes the line to earlyoom
without stripping quotes, so quotes would become part of the regex.

coop turned out to have earlyoom preinstalled. That's left alone for now. Once k0s
runs there, it needs the k0s processes on its avoid list or to be turned off, since
Kubernetes handles memory pressure itself by evicting pods.

### Removing Docker from vp1

vp1 had Docker installed, with a stopped `obsidian-livesync` (CouchDB) container and a
`hello-world` leftover. I no longer use LiveSync, so Docker, its images and its apt
repository were removed. The container's data folder (`~/livesync/data`) turned out
not to exist, so no notes database was lost. Only `docker-compose.yml` and
`obsidian.ini` remained.

### Log shipping: Vector to Axiom

Why: if a server breaks, its logs are often the first thing you lose. Axiom's free tier
keeps 30 days and takes 500 GB a month. Vector (~30 MB of RAM) reads the systemd
journal and sends every line, tagged with the host name.

**Problem: Vector started fine, but no logs arrived.** Vector's log showed
`Unauthorized` and `token not supported`, and it dropped the logs. The debugging path:

1. Checked the token file. It was correct: root-only, the right length and an `xaat-`
   (API token) prefix.
2. Sent a `curl` request with the same token to the same Axiom endpoint. **It worked
   (200).** So the token and the endpoint were fine; the problem was Vector.
3. Ran Vector with debug logging. It showed the exact URL, the same one curl had used.
   Still 401.
4. Pointed a throwaway Vector at a tiny local HTTP server and printed what it sent
   (token masked). The Authorization header was `Bearer ${AXI...`, len=21: **Vector was
   sending the literal text `${AXIOM_TOKEN}`, not the token.**
5. `vector --help` showed the reason: **Vector 0.60 no longer fills in `${VARS}` in its
   config by default.** It needs
   `VECTOR_DANGEROUSLY_ALLOW_ENV_VAR_INTERPOLATION=true`.

Fix: add that line to `/etc/default/vector` next to the token. "Dangerously" refers to
secrets leaking into configs by accident; here, pulling the token in is the point.

**Lesson:** when a credential "doesn't work", first prove whether the credential is bad
or the client is sending something else. A `curl` with the same credential separates
the two in one command. Capturing the client's real request settles it.

**Mistake:** while debugging, one command printed about half of the Axiom token into
the assistant's output. It's an ingest-only token, but making a new one is cheap.

**Also learned:**

- The Vector package already adds its user to the `systemd-journal` group, so no
  manual step is needed to give it journal access.
- Axiom's query error "invalid field: message" only meant no data had arrived yet.
  A field doesn't exist until the first event that has it.

**Decision: on coop, Vector runs on the host, not just in Kubernetes.** coop will have
two log sources:

- **The host's journal:** k0s, kubelet, containerd, sshd, tailscaled and agents.
  Collected by this host-level Vector.
- **Pod logs:** files in `/var/log/pods/`. Collected by a Vector DaemonSet in Phase 2.

Host logs must not depend on the cluster: when k0s breaks, its own error messages are
what you need, and a collector inside the cluster dies with it. It's the same reasoning
as running agents outside the cluster. Inside the cluster, Vector is better for pods,
because it can label each line with its pod and namespace.

Final `hosts/common/vector.sh`: installs Vector, copies `vector.yaml` from git, writes
`/etc/default/vector` (token plus the interpolation setting, root-only) and restarts
the service.

### LLM gateway: CLIProxyAPI on vp2

One Go program on vp2 holds all LLM keys and logins and serves them to the tailnet as
OpenAI-, Claude- and Gemini-style APIs at `http://vp2:8317`. It's on vp2 so it survives
home outages.

Done by hand first:

- Downloaded the pinned release (8.0.35, the build without plugin support) and checked
  it against the release's published checksum.
- It runs as its own system user, `cliproxy`, not as root, with a systemd service
  that limits it to writing only its own data folder.
- It uses about 70 MB of RAM.

**Decision: listen on the tailnet IP only.** vp2 faces the internet, so the gateway binds
to `100.86.79.18`, not to every interface. Checked: the public IP doesn't answer on 8317.

**Problem: at boot, the tailnet IP may not exist yet,** so binding to it fails. Fix:
`Restart=always` and `RestartSec=5`, so it keeps retrying until Tailscale is up.

**Decision: no client API keys.** With an empty `api-keys` list, CLIProxyAPI accepts
requests without authentication, which matches the open-tailnet decision. Any OpenAI
client can use it with base URL `http://vp2:8317/v1` and any key.

**Problem: `install` can't read from a pipe.** The first version of the script did
`doppler secrets substitute tmpl | install ... /dev/stdin dest` and failed with
`install: No such file or directory`. Fix: render to a file in a private temp folder
(0700), then `install` that file.

**Decision: the config template turns providers on only when their key exists.** The
template is a Go template rendered by `doppler secrets substitute`. Each provider
block is wrapped in `{{ if .GROQ_API_KEY }} … {{ end }}`, so a provider appears only once
its key is in Doppler.

**Testing method:** to prove the script works on a clean machine, the manual install
was removed completely (program, user, config, service) and the bootstrap was run on
the clean server, then run a second time. A config with fake keys was also checked on
a spare port to confirm the with-keys layout parses.

**Web control panel.** At first the panel was turned off, because at startup the server
tried to create `/etc/cliproxyapi/static` and got "permission denied". Then I decided I
wanted the web interface after all. Setting it up by hand showed what it needs:

- A **management key** (stored in Doppler as `CLIPROXY_MANAGEMENT_KEY`).
- `allow-remote: true`, since management otherwise only accepts connections from vp2
  itself. It's still tailnet-only.
- **A config file the server can write to.** On startup the server replaces the
  plaintext key in the file with a bcrypt hash, the panel saves edits back to the file,
  and the panel's page is downloaded into `static/` next to the config. So the config
  moved from `/etc/cliproxyapi/` to `/var/lib/cliproxyapi/config.yaml`, owned by the
  service.

The panel is at `http://vp2:8317/management.html`.

**Problem: keys added through the panel didn't work, and would have been lost.** I
added Groq and OpenRouter keys in the panel. Both showed "Models 0", `/v1/models` was
empty, and requests failed with "unknown provider". Two things were wrong:

1. **CLIProxyAPI only sends requests to an OpenAI-compatible provider for models listed
   explicitly.** It doesn't fetch the provider's model list itself.
2. **The bootstrap script regenerates the config from git**, so anything added in the
   panel is wiped on the next run.

Fix: the keys were copied into Doppler (`GROQ_API_KEY`, `OPENROUTER_API_KEY`). Each
provider's live `/models` list was checked, and the models went into the template with
short names: `gpt-oss-120b`, `gpt-oss-20b` and `qwen3.8-27b` on Groq; six free models
on OpenRouter (`nemotron-3-ultra`, `nemotron-3-super`, `minimax-m3.1-flash`,
`gemma-4-31b`, `north-mini-code`, `inkling`). Result, from the Mac through the gateway:

```
gpt-oss-20b (Groq):             hello from the lab
nemotron-3-super (OpenRouter):  hello from the lab
```

**Lesson: decide what the source of truth is for each setting.** Here, git plus Doppler
own the config. The panel is for viewing usage and for subscription logins, which are
stored as files in `auths/` that the script never touches.

**Decision: fetch model lists automatically instead of maintaining them by hand.**
Having to list every model by hand surprised me, so I checked CLIProxyAPI's source.
The server builds the model list for OpenAI-compatible providers only from its
config. The web panel has a model-discovery button, but it's a one-time pick saved
into the config, which the bootstrap script then overwrites. The explicit list exists
because it doubles as a routing table (short aliases, several upstream models pooled
under one name) and because some providers have hundreds of models.

Three options were considered: the script fetches the models; the panel owns the
providers (no git or Doppler, so lost if vp2 is rebuilt); or keep editing by hand.
I chose the first, because it keeps git plus Doppler as the source of truth:

- `cli-proxy-api-providers.json`: one entry per provider, with its type, base URL,
  the Doppler secret holding its key, and optional `include`/`exclude` regexes
  (OpenRouter: only `:free` models, minus safety classifiers; Groq: no Whisper,
  guard or Orpheus models).
- `upstreams/` (first written in Python, then rewritten in Go with only the standard
  library; the bootstrap compiles it on vp2): for each provider whose key exists, asks its
  `/models` endpoint, filters the list, and writes the `api-keys:` section. Aliases
  are generated: `nvidia/nemotron-3-super-120b-a12b:free` becomes
  `nemotron-3-super-120b-a12b`.
- `cli-proxy-api-render.sh`: base template plus generated providers. It restarts the
  service only if the result changed, comparing against a root-only copy of the last
  render, because the live file has the management key hashed into it.
- A daily systemd timer (`cli-proxy-api-refresh`) re-runs the render, so models that
  disappear upstream drop out by themselves.

Adding a provider is now: one entry in the JSON, its key in Doppler, re-run the
bootstrap script.

**Problem: Groq returned 403 to the script but not to curl.** Groq's edge blocks
Python's default `Python-urllib` user agent. Fix: send a custom `User-Agent`.

**Decision: rewrite the generator in Go.** I prefer Go for the lab's own tools, and the
BurstJob operator will be Go anyway. It uses only the standard library and is
compiled on vp2 by the bootstrap (`apt install golang-go`, `go build`). Before the
Python version was removed, both versions were run against the live providers and
produced byte-identical output, so the switch was verified, not assumed.

**Lesson: a 403 that only happens from code is often the user agent.** Compare the
request headers with a working curl before suspecting the key.

**Problem (avoided): systemd leaves `$HOME` unset for root services,** and the Doppler
CLI looks for its token under `$HOME`. The timer's service sets `Environment=HOME=/root`.

**Decision: if a fetch fails, keep the old config.** If a provider or Doppler can't be
reached, the generator exits with an error before anything is installed, so a network
blip never replaces a working config with an empty one. Both cases were tested by
pointing the script at a dead proxy (`HTTPS_PROXY=http://127.0.0.1:9`): the config
stayed byte-identical and the service kept running.

Result: 20 models, 4 from Groq and 16 free from OpenRouter, and both providers
answered a test request through the gateway. The aliases changed in the process
(`nemotron-3-super` is now `nemotron-3-super-120b-a12b`).

### Uptime monitoring: Gatus on vp1

Gatus checks the lab's services on a schedule and sends alerts. It runs on vp1 so it
stays up when the home internet goes down. Its UI is at `http://vp1:8080`, tailnet
only.

**Decision: alerts go to ntfy.** That means push notifications to the ntfy phone app
through a topic on the public ntfy.sh server. No account is needed. The topic name
is random and works as the password, stored in Doppler as `NTFY_TOPIC`. Telegram,
Discord and email were the alternatives; ntfy needs one secret and no signup.

**Problem: Gatus has no Linux binaries,** only a Docker image, and Docker had just been
removed from vp1. Decision: build it from source with Go (`go install
github.com/TwiN/gatus/v5@v5.37.0`), the same approach as the model-list generator.

**Problem: the first build ran 20+ minutes and then failed with `no space left on
device`,** with 31 GB free on disk. The cause: **on Ubuntu 26.04, `/tmp` is a 476 MB
RAM-backed filesystem (tmpfs)**, and Go writes its temporary build files there,
including the linker's output for a 50 MB program. Fix: `GOTMPDIR=/var/tmp/go-build`,
on disk. Because Go caches compiled packages, the retry finished in 49 seconds.

Other things learned from the build:

- Gatus pulls in a lot (AWS SDK, Google APIs, OpenTelemetry, a pure-Go SQLite). On a
  1 GB, 2-core VPS, a cold build is slow and peaked at about 1.3 GB of swap.
  `GOFLAGS=-p=1` (one package at a time) keeps memory use bounded; earlyoom never
  had to act.
- **`go version -m <binary>` prints the module version a Go binary was built from.**
  The script uses it to skip the build when the right version is already installed.
- A debugging mistake: `pkill -f "while sleep 2"` killed my own command, because the
  command's own text contained that pattern.

What it checks:

| Check | How | Alerts |
|---|---|---|
| LLM gateway up | `GET http://vp2:8317/v1/models`, 200 and at least one model | yes, after 3 failures |
| A real model answers | `POST` a chat completion to `gpt-oss-20b` every 30 min (spares free quota) | yes, after 2 failures |
| coop, vp2 reachable | TCP connect to port 22 over the tailnet | yes |
| bird reachable | same, every 5 min | no, since bird is off most days |
| Healthchecks.io ping | added once `HEALTHCHECKS_PING_URL` exists in Doppler | (Healthchecks alerts if pings stop) |

Gatus listens on vp1's tailnet IP only, using the same restart-until-Tailscale-is-up
service setup as CLIProxyAPI. It uses about 30 MB of RAM. The config is a Go template
rendered from Doppler, and the Healthchecks section only appears once its URL exists.

**First real catch.** On its first run, Gatus reported coop unreachable. It wasn't a
bug: `tailscale status` showed coop offline for 33 minutes, and coop didn't answer
from the Mac either. The monitoring caught an outage within minutes of going live.

Tested like the others: the manual install was removed (binary, user, config), then
the bootstrap ran on the clean server (96 s with Go's build cache warm), then again
(30 s). The UI answers on the tailnet and not on vp1's public IP.

**Why coop went down.** coop's journal for that boot simply stops at 06:30 local time
(01:00 UTC), in the middle of routine background tasks. There's no shutdown
sequence, no kernel error, no memory pressure (92% of RAM free, swap unused) and
the load was near zero. A system that shuts itself down logs it, so it didn't:
the power was cut or the machine was stopped from outside. `systemd-detect-virt`
shows coop is a **KVM virtual machine**, so the cause is at the layer below it,
either the host stopping the VM or the host losing power. Nothing inside coop
can say which.

**Lesson:** a journal that just stops, with no shutdown lines, means "killed from
outside", not "crashed".

The alert loop worked end to end: coop was down at 06:30, the ntfy alert went out
at 07:08 (three failed checks after Gatus first started), and the "resolved"
notification came at 07:30 when coop was switched back on.

**Healthchecks.io.** I created a check (5-minute period, 10-minute grace) and put its
ping URL in Doppler as `HEALTHCHECKS_PING_URL`. Re-running the vp1 bootstrap added the
`healthchecks-ping` check to Gatus, and the first ping succeeded. If vp1 or Gatus dies,
the pings stop and Healthchecks emails me. That's the "who watches the watcher" piece.

**Decision: check less often.** The first intervals (1 minute for the gateway and SSH)
felt like too much for a homelab. Checks cost almost nothing, but finding out within
minutes isn't worth much here either. What the interval really sets is how quickly I
hear about an outage, roughly the interval times the failure threshold. New schedule:

| Check | Was | Now | Alerts after about |
|---|---|---|---|
| gateway `/v1/models` | 1 min | 2 h | 6 h (3 failures) |
| real model call | 30 min | 2 h | 4 h (2 failures) |
| coop, vp2 SSH | 1 min | 10 min | 30 min |
| bird SSH | 5 min | 30 min | never |
| Healthchecks ping | 5 min | 30 min | depends on Healthchecks' grace period |

That's about 400 checks a day instead of about 4,900, and 12 model calls instead of 48.
The Healthchecks check's period had to be raised to match, or it would alert on every
gap between pings.

### Trimming the VPS images

Both VPSes had `rpcbind` listening on port 111 on every interface, pulled in by
`nfs-common`, and neither machine has NFS mounts. Both packages were removed. The
removal is scripted in `hosts/common/vps-trim.sh`.

---

### Agents and T3 Code on coop and bird

**Decision: agents only on coop and bird.** vp1 and vp2 have about 500 MB free, and a
Node-based agent takes a few hundred MB, so they'd compete with Gatus and the gateway.
The agents are Claude Code, Codex and the Cursor CLI (`agent`), all from their vendors'
own installers into `~/.local/bin`. None of them need Node any more.

What was already there: Claude Code on both, logged in. coop already ran a T3 Code
server as a systemd user service, put there by the Mac's desktop app over SSH. bird
had an old T3 build from source (from July), which I moved aside and replaced with the
official nightly.

**Researching how to run T3 Code on a server.** There are three ways to reach a remote
T3 Code:

1. **Desktop-managed SSH:** the Mac app connects over SSH, starts a server there and
   forwards the port. No setup at all, but only that one desktop app can use it; the
   phone and the web app can't.
2. **T3 Connect:** T3's hosted relay, signed in with a T3 account. It works through NAT
   without port forwarding, but that's a problem the tailnet already solves, and it
   adds an outside account in the path.
3. **Direct pairing over the tailnet:** run the server as a background service and pair
   each device once with a one-time link.

**Decision: option 3, with Tailscale Serve for HTTPS.** Each server stays on
`127.0.0.1:3773`, and `tailscale serve --bg --https=443 http://127.0.0.1:3773`
publishes it as `https://bird.tailff3296.ts.net`, with a real Let's Encrypt certificate
from Tailscale and reachable only inside the tailnet. HTTPS matters because the hosted
web app (app.t3.codes) only connects to HTTPS servers. Pairing is a one-time link per
device that you paste into **Settings → Connections → Add environment**; for coop this
adds a second route to the machine the Mac already knows over SSH.

"Connecting the instances to each other" turned out not to be a thing: T3 servers don't
talk to each other. The client does: one app pairs with every server, shows them all
side by side, and can spread new threads across them (Load balancing in Settings).

How it runs:

- `t3 service install` writes a **systemd user service** (`~/.config/systemd/user/t3code.service`).
  User services normally stop when you log out, so the script turns on **lingering**
  (`loginctl enable-linger`), which keeps the user's systemd running from boot.
- Running the user half from a root script: `runuser` plus a hand-built environment,
  in particular `XDG_RUNTIME_DIR` and `DBUS_SESSION_BUS_ADDRESS`, without which
  `systemctl --user` can't find the user's systemd.
- `tailscale set --operator=themiya` lets the user manage Serve, so `t3 pair --tailscale`
  works without sudo.
- **The script only installs what's missing.** Every tool updates itself, and T3's
  update button updates every connected server, so the script doesn't fight them.
  Re-running it took 2 seconds and didn't restart anything.

Logging in is the one thing that can't be scripted: `codex login --device-auth` and
`agent login` each give a link and a code to approve in a browser.

**bird thought it was coop.** Its Tailscale name was `bird`, but `hostname` said `coop`:
bird was set up from a copy of coop's disk. Before renaming I checked the things a clone
copies that break a Kubernetes cluster: `/etc/machine-id`, the MAC address and the SSH
host keys. All three were different, so only the name needed fixing (`hostnamectl
set-hostname bird` and the `127.0.1.1` line in `/etc/hosts`). Tailscale keeps the OS
hostname it read at startup until `tailscaled` restarts; I restarted it with a
`systemd-run` timer so my own SSH session over Tailscale wasn't cut off mid-command.
bird's bootstrap now sets the name.

**Pairing permissions.** T3 gives each paired device a set of permissions (scopes):
viewing threads, running tasks, managing providers, reading files and so on. The Mac's
route to coop had only four of them (`orchestration:read/operate`, `terminal:operate`,
`relay:read`), so "Update all" failed with `missing required scope: providers:manage`.
Pairings from newer versions get every scope by default (bird's did). Fix: update coop's
server from the command line (`t3 update --yes`), then pair the Mac again with a fresh
`t3 pair --tailscale` link. Pairing the same machine again replaces its old grant.
I want every device to have full access, the same stance as the tailnet policy.

Skipping Codex logins for now: no Codex subscription. It stays installed, unused.

### bird's bootstrap

bird got its Doppler token and its full bootstrap (Doppler, Vector, agents, hostname).
Two problems, both from a half-finished first attempt:

- **My mistake:** I passed the token with `umask 077` set in the same command, and the
  bootstrap started from that command inherited it. So the Doppler apt key
  (`/usr/share/keyrings/doppler-archive-keyring.gpg`) was written readable only by root,
  and apt, which checks signatures as the unprivileged `_apt` user, rejected the repository
  as "not signed". **A umask set in a shell leaks into everything started from it,
  including sudo.** Fix: the script now runs `chmod 0644` on the key itself.
- **The failed run left the Doppler apt source behind** without a usable key, so the
  script's first `apt-get update` failed on every retry. Fix: the script removes that
  file before it starts. A script that's "safe to re-run" also has to survive its own
  half-finished runs.

Vector on bird passed its Axiom health check, and a second bootstrap run changed nothing.

**Decision: no Tailnet Lock.** It would stop a compromised Tailscale account, or Tailscale
itself, from adding devices to the tailnet. But every new device, including the ones the
Kubernetes operator will create, would need signing by a trusted device. I'd rather not
add that complexity; MFA on the login is enough for this lab. That closes Phase 1.

### Checking Phase 1 against its own test

Phase 1's "done when" is: every node ships logs off-lab, and an agent on any node can
reach every other node. I'd called it done without running the second half. When I ran
it, two of six SSH paths failed:

- **coop → bird: `Permission denied (publickey)`.** Tailscale SSH had been switched on by
  hand on coop, vp1 and vp2, but never on bird, and no script did it. So the connection
  fell through to plain OpenSSH, which wants a key. Fix: `tailscale set --ssh` is now in
  `hosts/common/bootstrap.sh`.
  - **Tailscale refuses to do this from inside an SSH session over the tailnet,** because
    it reroutes port 22 and cuts that session. `--accept-risk=lose-ssh` allows it; I ran
    bird's bootstrap detached with `systemd-run` so the cut didn't kill the script.
- **bird → vp1/vp2: `Connection closed`.** bird logged in as `themiya`, which doesn't exist
  on the VPSes. coop only worked because of a hand-written `~/.ssh/config`. That's now in
  `agents-user.sh`.

**Running detached found a real bug.** `systemd-run` starts with no `$HOME`, so Doppler
failed. But `vector.sh` wrote `AXIOM_TOKEN=` (empty) anyway and Vector stopped starting.
Under `set -e`, **a failing command inside `echo "$(...)"` doesn't stop the script**:
only the `echo`'s exit status counts. Fix: fetch the token into a variable first, where
a failure does stop the script.

**Lesson:** "done" means the test in the roadmap passed, not that every step ran. All six
paths now work, and all four bootstraps re-run with exit 0.

## 2026-10-21: Phase 2, the k0s cluster

### Getting coop and bird into a cluster

k0sctl runs on coop and reads one file, `cluster/k0sctl.yaml`. k0sctl is the installer
and kubectl is the client: k0sctl reaches the machines over SSH to install and change
k0s, and kubectl talks to the API server to run things inside it. If the cluster is
broken, kubectl can't help but k0sctl still can.

**Problem: coop couldn't SSH to itself.** k0sctl connects to every host as root,
including coop. `ssh root@coop` from coop failed with `Permission denied (publickey)`
while `ssh root@bird` worked. Tailscale SSH only takes over connections that arrive
from another machine; a machine connecting to itself goes to the normal OpenSSH
server, which wants a key. Fix: an ed25519 key for `themiya` on coop, added to root's
`authorized_keys`. This belongs in coop's bootstrap script.

**Decision: pin everything to tailnet addresses.** `privateAddress` and
`--node-ip` use the 100.x addresses. Without them each node advertises its own
network, 10.77.20.2 for coop and 192.168.1.11 for bird, and the two can't reach each
other. Other settings, each for a reason:

- A single controller, because etcd needs three members for quorum and there are two nodes.
- `noTaints` on coop, so ordinary pods can run on the controller too.
- Reservations of 500m CPU and 1 GiB for Kubernetes's own components, and the same again
  for the operating system, so pods can't starve the machine or the agents.
- `failSwapOn: false`, so the nodes keep their 4 GB swap files.

`k0sctl apply` took 4m13s, installed k0s v1.36.4 and both nodes showed Ready.

### The first problem: pods on bird couldn't reach coop

**Symptom.** CoreDNS and the konnectivity agent on bird stayed at 0/1, and
`kubectl logs` for a pod on bird timed out. Node-to-node traffic was fine.

**Diagnosis.** kube-router's default for pods on different subnets is IP-in-IP, which
puts the pod's packet inside a new IP packet addressed node to node. tcpdump showed
those packets leaving bird on `tailscale0` and never arriving on coop. Tailscale only
carries TCP, UDP and ICMP, so it drops IP protocol 4.

**Fix.** kube-router can wrap pod packets in UDP instead, called FOU. Two lines under
`kuberouter.extraArgs`, `overlay-encap: fou` and `overlay-encap-port: "5555"`, and
every pod was Ready. Pod-to-pod ping across the nodes then averaged 101.9 ms, against
103.8 ms node to node, so the wrapping itself costs no latency anyone can measure.

**Lesson:** changing the spec of a DaemonSet makes Kubernetes replace its pods on its
own. I also ran `kubectl rollout restart` and it only rolled them a second time.

### What k0s actually is

k0s is one 252 MB binary. On start it unpacks 396 MB of programs into
`/var/lib/k0s/bin`: kube-apiserver, kube-controller-manager, kube-scheduler, etcd,
konnectivity-server, kubelet, containerd, runc and a pinned iptables. On coop, `k0s`
runs the control plane as ordinary child processes, so `kubectl get pods` can't show
them. Everything else, CoreDNS, kube-router, kube-proxy, the konnectivity agent and
metrics-server, is a container image run as a pod. kubeadm clusters run the control
plane as static pods instead. k0s's way keeps the API server up when containerd is
broken, and costs you kubectl for debugging it.

### A correction to the design: coop and bird are not in the same place

I had assumed both machines were at home. coop is a server in Korea and bird is in
Sri Lanka on home Wi-Fi, 105 ms apart over a direct Tailscale path. The design's
"16 GB at home" and "home internet drops and both vanish" were wrong, and a Sri Lanka
outage now takes out only bird. The latency matters for apps: each round trip across
the two sites costs 105 ms, so chatty apps should stay on one node, and DNS lookups
should be answered on the node that asks.

### Choosing the pod network

I first leaned towards Cilium, for the eBPF learning. Then I asked for the setup with
the best performance for the least resources, ignoring the learning goal, and the
answer changed.

- **Latency is set by the path, not the plugin.** The 105 ms is Korea to Sri Lanka.
  Per-packet costs in any plugin are microseconds.
- **Memory is where the plugins differ.** Measured on coop: kube-router 69 MiB and
  kube-proxy 38 MiB. I estimate Cilium at 100 to 200 MiB per node on top of that. This
  is an estimate; I haven't installed it.
- **Cilium's strength is thousands of pods.** At two nodes, iptables isn't a
  bottleneck, so it would cost the most memory and return nothing measurable.

**Decision: keep kube-router, turn its overlay off and let Tailscale carry pod
traffic as subnet routes.** Each node advertises its own pod range, the other node
accepts it, and the pod packet goes straight into WireGuard with no extra wrapper.
The eBPF projects don't depend on this choice: Tetragon, the XDP firewall and the
egress meter are all in Phase 5, and Cilium is still a Phase 4 swap.

### Pod ranges as Tailscale subnet routes

Per node, from Kubernetes' own `spec.podCIDR`: coop `10.244.0.0/24`, bird
`10.244.1.0/24`. Settings, applied by hand on both: `--advertise-routes` for its own
range, `--accept-routes` because Linux ignores subnet routes by default, and
`--snat-subnet-routes=false` so pods see the real sender instead of the router's
address. I approved the two routes once in the admin console. An approval covers one
address block, not ports or pods.

WireGuard drops any packet whose source isn't on the sender's allowed list. A pod
packet leaving bird has a 10.244.1.x source, and coop only accepts it because the
approved route puts that block on bird's list.

**Test, with the overlay still on:**

- bird's host to a coop pod: works, 103 ms, and tcpdump on coop shows the real source
  address, `100.109.203.74`, so SNAT really is off.
- The Mac to a pod on either node: works.
- coop's host to a pod on bird: **fails.**
- Largest unfragmented ping: 1,172 bytes of data, which is a 1,200-byte packet. That's
  the `mtu: 1200` we set for the overlay.

**Why coop to bird's pod fails.** tcpdump on bird shows the request arriving over
`tailscale0` and the pod answering, but the answer leaves through kube-router's old
tunnel `tun-...`. kube-router adds a policy rule, `from 10.244.1.0/24 lookup 77`, and
that rule is checked before Tailscale's own routing table. Replies from pods take the
old tunnel, and the request and reply travel different paths. The Mac works because
the tunnel table has no entry for it. This is exactly what turning the overlay off
should fix.

**Fix and result.** `cluster/k0sctl.yaml` now has `enable-overlay: "false"` and `mtu: 1280`.
After `k0sctl apply`, the kube-router pods restarted with the new flag, and the old
tunnel interfaces and the table 77 rule were gone from both nodes. Same tests again:

- Both directions between a node and a pod on the other node work, at 114 to 117 ms.
- Pod to pod across nodes works in both directions, 105 ms average.
- Throughput with iperf3, bird to coop, 10 seconds. Node to node over plain Tailscale:
  4.8 Mbit/s with one stream, 8.9 with four. Pod to pod with no tunnel: 7.7 with one
  stream, 7.7 with four. The pod network adds nothing measurable. The ceiling is the
  link, about 8 to 9 Mbit/s up from Sri Lanka. I never measured the FOU overlay, so
  there's no before and after, only this.

**Problem: the MTU change didn't take effect.** The node's CNI file
`/etc/cni/net.d/10-kuberouter.conflist` still says 1200 even though the ConfigMap says
1280. kube-router's init container only copies the file when it doesn't exist, so a
config change never reaches a node that already has one. A fresh cluster would get
1280. Fixing it on these nodes means deleting the file, restarting kube-router and
recreating the pods.

### Flux

Flux is a set of controllers that run in the cluster, fetch the Git repository about
once a minute and make the cluster match it. Nothing pushes to the cluster, so it works
behind NAT. It also reverts manual `kubectl` edits to objects it manages, and deletes
objects whose files were deleted from the repo. Two objects do the work: a
`GitRepository` says where to fetch from, and a `Kustomization` says which folder to
apply.

**Steps.**

1. Installed the `flux` CLI v2.10.0 on coop, checking the release's SHA-256.
2. `flux check --pre` passed: it wants Kubernetes 1.35 or newer and the cluster is 1.36.4.
3. `flux bootstrap github` into `flux/clusters/homelab`, using the GitHub login `gh`
   already had on coop, so no new token was created. It commits Flux's own manifests
   to the repo, installs them, adds a read-only deploy key to the repo and applies
   a sync that points back at the same repo. From then on Flux manages itself, so a
   Flux upgrade is a normal commit.

**Decision: three controllers, not four.** I dropped the notification controller with
`--components`, since alerts already go through Gatus and ntfy. One flag brings it back.
The three idle at 16, 30 and 23 MiB, about 70 MiB together.

**Problem: Flux put its controllers on bird.** `kustomize-controller` landed there.
bird is off most days, and when coop is down Flux can do nothing anyway because the API
server lives there. From bird each API call also costs 105 ms. A patch in
`flux-system/kustomization.yaml` now pins every Flux Deployment to coop. It lives in the
Kustomization, not in the generated `gotk-components.yaml`, so a Flux upgrade keeps it.

**Layout.** `flux/clusters/homelab/` holds Flux's own files plus one `Kustomization`
per area. `apps.yaml` points at `flux/apps/`. An `infrastructure.yaml` comes with the
first infrastructure component, the Tailscale operator, because an empty folder isn't a
valid Kustomization. The first test app is `whoami`, a tiny web server that prints which
pod answered, with two replicas spread over both nodes.

## Still open

- Gatus version bumps rebuild from source (about 20 minutes cold on vp1). If that gets
  annoying, build it in GitHub Actions instead.
- coop runs as a KVM virtual machine: find out what stopped it on 2026-10-20 (host power
  loss or the host stopping the VM), and set the VM to start automatically when the host boots.
- On coop, earlyoom vs Kubernetes memory handling (Phase 2).
- Keep DNS and chatty traffic on one site: node-local DNS caching, and zone labels for Korea and Sri Lanka.
- A WebAssembly experiment: Wasmer next to runc through a containerd shim and a RuntimeClass. Same small Rust HTTP service as a container and as `.wasm`, compare cold start, memory and requests per second.
- Add the Tailscale route settings and coop's self-SSH key to the bootstrap scripts once the network works.
- Pod logs: Vector DaemonSet (Phase 2).
