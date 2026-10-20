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

### Trimming the VPS images

Both VPSes had `rpcbind` listening on port 111 on every interface, pulled in by
`nfs-common`, and neither machine has NFS mounts. Both packages were removed. The
removal is scripted in `hosts/common/vps-trim.sh`.

---

## Still open

- Gatus on vp1 with a Healthchecks.io ping (step 8): its first checks are "is the
  gateway up" and "does a real model answer".
- Agents on every node, then Tailnet Lock (step 9).
- bird: run its bootstrap (Doppler token, Vector) next time it's on.
- On coop, earlyoom vs Kubernetes memory handling (Phase 2).
- Pod logs: Vector DaemonSet (Phase 2).
