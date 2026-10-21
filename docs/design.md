# Homelab: squeezed-compute design

*19 Oct 2026 · @gg*

## Goals and principles

One k0s cluster spans all four machines. Agents run on bare metal beside it. Free provider tiers sit behind two front doors, one for compute and one for LLMs.

- **Learn the parts, not the tools.** Use k0s, build the cluster by hand, and swap components one at a time to see what each does.
- **Squeeze free compute.** Every free tier is a backend you can plug in on demand, never something you depend on permanently.
- **No overhead layers.** No Incus, no Proxmox, no Talos. Every node stays a normal SSH-able Linux box.
- **Tailnet only.** Nothing is exposed publicly, and tailnet identity is the credential for everything inside it. Burst jobs never join it: they run on the provider's hardware, and the lab only calls out to them.
- **GitHub is the source of truth.** Everything is declared in the homelab repo, with no self-hosted git.
- **Messy is fine.** Kubernetes and eBPF experiments can run at the same time; the RAM budget is the only hard limit.

## Machines and roles

coop holds the control plane and the heavy lifting, bird is a worker that can drop out, and the always-on VPSes carry what must survive a home outage. RAM is the binding constraint: about 18 GB total, 16 GB of it at home.

| Node | CPU / RAM | k0s role | Also runs (outside k0s) |
| --- | --- | --- | --- |
| coop | 6 cores / 8 GB | Controller + worker (`--enable-worker`) | Agents, T3 Code, k0sctl, Dozzle |
| bird | 4 cores / 8 GB | Worker that may drop out | Agents, T3 Code |
| vp1 | 2 cores / 1 GB | Not in k0s | Gatus, Beszel hub, earlyoom |
| vp2 | 2 cores / 1 GB | Not in k0s | CLIProxyAPI, earlyoom |

The cluster is just coop and bird. vp1 and vp2 stay plain systemd hosts with too little RAM to share with a kubelet; the cluster consumes their services (CLIProxyAPI, Gatus) as external services through selectorless Services and EndpointSlices. No free cloud VMs join the cluster.

Everything you run lives in the tailnet. Bursts, LLM calls and telemetry go out to free providers, and GitHub drives what runs.

## External services on vp1 and vp2

These run as plain systemd services outside k0s. Each VPS has a `hosts/<node>/bootstrap.sh` that installs them, and you re-run it to apply changes. Only configs that can't be rebuilt from the web UI belong in git.

| Node | Service | Configured by | In git? | Notes |
| --- | --- | --- | --- | --- |
| vp1 | Gatus | YAML file (endpoints, alerts, Healthchecks ping URL) | Yes, as a template; alert tokens in Doppler | Losing this means losing your uptime rules and alerts |
| vp1 | Beszel hub | Web UI (systems, users, alerts) | No, back up its data directory | Holds state in an embedded SQLite database, so it isn't reproducible from git |
| vp1, vp2 | Beszel agent | Hub address and key, set in a small env file | Key in Doppler | The key comes from the hub's UI when you add a system |
| vp1, vp2 | earlyoom | Flags in `/etc/default/earlyoom` | Yes, one line | Set by the bootstrap script |
| vp1, vp2 | Tailscale | Joined once by hand with an auth key | No | Not in any script; the auth key is single-use |
| vp2 | CLIProxyAPI | YAML file (upstreams, API keys, accounts) | Yes, as a template; keys in Doppler | OAuth token files written at login are state and stay off git |
| vp1 | Healthchecks.io | Web UI (SaaS, no host) | No | Gatus pings it using the URL in its config |

In short: Beszel and Healthchecks can be set up once in their web UIs. Gatus and CLIProxyAPI need their YAML files in git, since those files hold the alert rules and routing. Those files are committed as templates, and each bootstrap script fills in the secrets from Doppler using that VPS's read-only Doppler token (see Secrets and identity).

## k0s cluster

The whole cluster is described in one k0sctl YAML in homelab and bootstrapped over SSH. It starts on k0s defaults and replaces one component at a time.

### Bootstrap

- `k0sctl apply` reaches every node over its Tailscale address. Re-running it is how you add nodes or upgrade.
- coop runs the controller with `--enable-worker` because it's the steadier home machine. Set kubelet CPU and memory reservations so pods can't starve the control plane.
- Use a single controller. etcd needs three members for quorum, and there are only two cluster nodes.

### When a node goes down

- **bird drops out (worker):** within about a minute it's marked NotReady. After 5 minutes (the default toleration) its pods are evicted and rescheduled onto other nodes. When bird comes back, its kubelet re-registers on its own and new pods can land there again. Pods that already moved stay put unless a descheduler rebalances them.
- Shorten that 5-minute wait for stateless apps with `tolerationSeconds` on the not-ready and unreachable tolerations.
- Keep stateful pods off bird. A local volume can't follow its pod to another node.
- **coop drops out (controller):** pods on other nodes keep running and serving, but nothing gets rescheduled, Flux stops reconciling and `kubectl` doesn't answer. When coop returns, the control plane picks up where it left off and reconciles any drift.
- **Home internet drops:** coop and bird both vanish. vp1 and vp2 are outside the cluster, so CLIProxyAPI on vp2 keeps working and Gatus on vp1 alerts you.
- **Protect etcd:** an old machine losing power mid-write is how etcd gets corrupted. Schedule k0s backup to R2 and practise one restore.

### Tailscale gotchas, each one a lesson

- Pin node IPs and the CNI to `tailscale0`; otherwise nodes advertise their LAN or public addresses.
- Tailscale's MTU is 1280, so the pod overlay inside it needs a smaller MTU or large packets silently disappear.
- Konnectivity, which k0s ships by default, is what lets the controller reach kubelets on workers behind NAT.
- Expose services to the tailnet with the Tailscale Kubernetes operator. Each exposed service becomes a tailnet device, and the free plan caps tagged resources at 50.

### Component-swap learning path

1. Run k0s defaults: kube-router CNI, CoreDNS, metrics-server, konnectivity.
2. Swap the CNI to Calico and learn IPAM, BGP versus VXLAN, and network policy.
3. Swap the CNI to Cilium on coop and bird to learn eBPF datapaths, Hubble and kube-proxy replacement.
4. Add storage: local-path first, then something replicated across coop and bird.
5. Add ingress and service mesh (Linkerd is light enough for this hardware).
6. Package with Helm, Timoni or plain Kustomize, applied by Flux.

## eBPF

eBPF fits in five places here. Two pay off from day one: a record of what agents do on your hosts, and a firewall for the public-facing VPSes.

| Where | What | Why it matters here | Runs on |
| --- | --- | --- | --- |
| Agent audit | Tetragon: process exec, file and network events | Agents have full access. This records every command, file write and connection they make, so you can see what happened after the fact | coop, bird (host or k0s DaemonSet) |
| VPS firewall | Your own XDP program (aya or cilium/ebpf) that drops new inbound connections on the public interface except Tailscale's WireGuard port | vp1 and vp2 face the internet. Dropping scanner traffic at the driver costs almost no CPU. Prototype the rules in nftables first | vp1, vp2 |
| Networking | Cilium as CNI: kube-proxy replacement, network policy, Hubble flow logs | The deepest look at how Kubernetes networking works | coop, bird |
| Zero-code telemetry | Grafana Beyla (now OpenTelemetry eBPF Instrumentation) for request metrics and traces, plus an eBPF profiler | Uses the free Grafana Cloud traces and profiles quotas without instrumenting any code | coop, bird |
| Egress meter | A small eBPF program that counts bytes per process or cgroup | Guards tight egress allowances, and can feed the dispatcher's ledger | Any node |

For ad-hoc questions ("what's eating memory", "which process opened this socket"), use bpftrace and the bcc tools. Liz Rice's *Learning eBPF* is the companion book for the custom programs.

## LLM gateway

CLIProxyAPI runs as a systemd service on vp2 as the single LLM endpoint for the tailnet, so it survives home outages. It replaces LiteLLM because it's one Go binary and covers both subscriptions and free API keys.

- **Subscriptions:** it turns Claude Code, Codex, Gemini/Antigravity and Grok OAuth logins into OpenAI-, Claude- and Gemini-compatible APIs, with round-robin across multiple accounts.
- **Free tiers:** Groq, Gemini API keys and OpenRouter `:free` models are added as OpenAI-compatible upstreams in its config.
- **Usage tracking:** the core no longer ships usage stats. Add a companion such as CPA Usage Keeper if you want per-account dashboards.
- **Consumers:** agents, the burst dispatcher and anything in k0s, at `http://vp2:8317`. It listens on vp2's tailnet IP only and needs no client key, in line with open access inside the tailnet.
- **Setup:** `hosts/vp2/cli-proxy-api.sh` installs a pinned release. Providers are listed in `cli-proxy-api-providers.json`, each with its Doppler key name and a model filter. A provider is turned on when its key exists in Doppler `prd`, and its models are fetched from the provider's `/models` endpoint at install time and again by a daily timer.
- **Web UI:** `http://vp2:8317/management.html`, for usage and subscription logins. Config edits made there are overwritten by the next render.
- **Caveat:** routing consumer subscriptions through a proxy can conflict with some providers' terms. Treat those accounts as at risk and keep the free API-key tiers as fallback.

### LLM observability

Decision: Langfuse Cloud on the free Hobby tier for coding-agent and dispatcher traces. Prompts, responses and tool outputs leave the lab. Self-hosting is ruled out at this RAM budget. Claude Code on coop and bird sends traces through the Langfuse Claude Code plugin, and Langfuse keys live in Doppler.

## Burst dispatcher

One interface sends a job to whichever free provider has headroom. It starts as a CLI plus an MCP server and grows into a BurstJob CRD with its own controller.

**Contract.** Every backend implements four calls: `submit(job) → handle`, `status`, `logs` and `cancel`. A job declares its image or code, its resource needs (GPU yes/no, CPU, memory) and a max runtime.

| Backend | Use for | Free allowance | Driven by |
| --- | --- | --- | --- |
| Modal | GPU jobs and endpoints | $30/month credit | Python SDK |
| Kaggle | Long batch GPU work | P100, 30+ h/week | Kernels API (push, poll, pull output) |
| HF ZeroGPU Spaces | Demo inference endpoints | 2 Spaces | Gradio API |
| Cloud Run Jobs | Containers up to the free limit | 180k vCPU-s, 360k GiB-s/month | gcloud / REST |
| Azure Container Apps | Containers (rotation partner) | 180k vCPU-s, 360k GiB-s/month | az / REST |
| IBM Code Engine | Containers (rotation partner) | 100k vCPU-s, 200k GB-s/month | ibmcloud / REST |
| Cloudflare Workers | Short JS functions | 100k requests/day | wrangler |
| Val Town | Small crons and glue | 100k runs/day | REST |

**Stage 1: burst CLI and MCP server.** It's installed on every agent host and keeps no local state, so losing a node loses nothing. Agents call it through MCP; you call it from the shell. A quota ledger records usage per provider per period and picks the backend with the most headroom. A free Turso or Cloudflare D1 database fits the theme as the ledger's store.

**Stage 2: BurstJob CRD and controller.** Write it with kubebuilder and client-go. Flux or an agent applies a BurstJob; the controller reconciles it onto a provider and writes status conditions and a log link back. A finalizer cancels the remote run when the object is deleted. This is the main Kubernetes-internals project in the lab.

**Outside the tailnet.** Burst jobs never join the tailnet. The lab always initiates: it submits, polls and fetches results through each provider's API. A job that needs an LLM uses a free API key from Doppler directly, not CLIProxyAPI.

**Guardrails.** Set budget alerts on GCP, Azure and AWS before the first run, keep the ledger conservative, and check each provider's terms (for example, multiple accounts or crypto workloads).

## Agents

Claude Code, Codex and the Cursor CLI are installed directly on coop and bird, outside k0s, with full access, and T3 Code drives them. They are both the workers and the management interface for the lab. vp1 and vp2 get no agents: with about 500 MB free, an agent would compete with Gatus and CLIProxyAPI.

- **Why outside the cluster:** an agent can fix the cluster when the cluster is broken.
- **Access:** each agent host reaches the Kubernetes API through the Tailscale API server proxy with full admin access, and gets k0sctl, the burst CLI and its MCP server, `gh`, the CLIProxyAPI endpoint and the host's Doppler token.
- **Sessions:** use persistent sessions (zmx, tmux or mosh) so long runs survive disconnects. Use Tailscale SSH to get in from anywhere.
- **Setup:** `hosts/common/agents.sh` installs each agent with its vendor's installer for the main user, plus the T3 Code CLI (nightly channel, matching the desktop app) as a systemd user service with lingering. Each tool updates itself; the script only installs what's missing. Logging in to each agent is a one-time manual step.
- **T3 Code across machines:** each server listens on `127.0.0.1:3773` and Tailscale Serve publishes it as `https://coop.tailff3296.ts.net` and `https://bird.tailff3296.ts.net`, tailnet only with a real certificate. Servers don't connect to each other; each client (the Mac's desktop app, the phone app, app.t3.codes) pairs once with each server and then sees all of them, and can load-balance new threads across them. No T3 Connect account is needed, since the tailnet already provides the reachability.
- **Optional isolation later:** for throwaway tasks, smolvm, gondolin or Cloudflare's sandbox SDK can give an agent a disposable sandbox without a hypervisor layer on the host.
- **Workflow:** agents change infrastructure by pushing to homelab and Flux applies it. This is history, not a safety rail. You can roll back any change.

## Secrets and identity

Inside the tailnet, the caller's Tailscale identity is the credential, so most secrets never need to exist. Third-party credentials live in Doppler. Git holds templates that reference secrets, never the secret values.

### 1. Internal access: tailnet identity, zero secrets

| Access | Mechanism | Replaces |
| --- | --- | --- |
| Node to node | Tailscale SSH, with tailnet policy rules per tag | SSH keys |
| Kubernetes API | Tailscale operator API server proxy in auth mode. Your tailnet identity is bound to cluster-admin, for you and agents alike | Admin kubeconfigs on agent hosts |
| Your own services (burst MCP server, dispatcher API) | `tailscale serve` identity headers plus app capabilities in grants (for example `can_submit_gpu`) | API tokens |
| Web UIs (Beszel, Grafana) | tsidp as the OIDC provider | Per-app passwords |

Turn on Tailnet Lock and MFA on the identity provider, since the tailnet is now the root of trust.

### 2. LLM keys: CLIProxyAPI on vp2

Upstream LLM keys stay in CLIProxyAPI's config (rendered from Doppler, as below), and agents reach it over the tailnet. Aperture by Tailscale is worth trying alongside it for per-agent audit logs of API-key traffic; it's in beta and doesn't cover subscription OAuth.

### 3. Third-party credentials: Doppler

GitHub, Modal, GCP, Groq, Gatus alert tokens, the Beszel agent key and Langfuse keys live in Doppler. It's hosted, so it keeps working through home outages.

- **Layout:** one `homelab` project with a single `prd` config shared by every host. Each host gets its own read-only service token for that config, so one host's access can be revoked without touching the others.
- **Hosts:** the service token is stored once per host in root-only Doppler CLI config. Bootstrap scripts render `*.tmpl` configs from git with `doppler secrets substitute` into 0600 files, or start services with `doppler run --`.
- **k0s:** External Secrets Operator with its Doppler provider syncs the `prd` config into Kubernetes Secrets. Its service token is the one Secret created by hand. ESO keeps you portable if you move off Doppler later.
- **Agents:** they use the host's token, always through `doppler run -- <cmd>`, so secret values reach the subprocess's environment and never the transcript. This matters because Langfuse traces send tool outputs off the lab. Claude Code deny rules on `doppler secrets get`, `printenv` and `env` add a speed bump.
- **Free-plan limits to accept:** service tokens are static, so rotate them by hand. The activity log keeps only 3 days, and OIDC identities need the Team plan.

### Open inside the tailnet

Access inside the tailnet is deliberately open. Every device you own can reach and SSH into every other one, and agents get the same full access you have. This is a choice: the tailnet edge is the boundary, and nothing inside it restricts agents. Tailscale identity is per device, so an agent and Gatus on coop are both "coop", and that's fine under this model.

- **Later learning project:** setec, Tailscale's tailnet-native secrets server, granted per tag in the tailnet policy. It needs an AWS KMS key or a TPM to unlock its storage, and if its host goes down, services can't fetch secrets when they restart.

## Observability and uptime

Collectors stay tiny, and data leaves the lab, so you can still see what broke after you break it.

| Need | Tool | Where it runs | Sink |
| --- | --- | --- | --- |
| Uptime of tailnet services | Gatus, built from source (`hosts/vp1/gatus.sh`) | vp1, UI at `http://vp1:8080` | Its own page plus ntfy push alerts |
| Is the watcher alive | Healthchecks.io dead-man check pinged by Gatus | Free SaaS | Email or push |
| Host metrics | Beszel agent + hub | Agents on all nodes, hub on vp1 | Beszel hub |
| Logs | Vector or fluent-bit | All nodes; a DaemonSet in k0s | Axiom (500 GB/month ingest) |
| Cluster metrics and traces | Grafana Alloy | coop and bird only | Grafana Cloud free tier |
| Quick container logs | Dozzle | coop, on demand | None |
| Memory pressure | earlyoom | vp1, vp2 | Logs |

Burst jobs send their logs to the same Axiom dataset, tagged with the provider and the BurstJob name.

## homelab repo

The homelab repo on GitHub holds everything: host setup, the cluster definition, Flux-managed apps and the dispatcher's code. Secrets are never committed: configs are templates filled from Doppler, and internal access uses tailnet identity.

```text
homelab/
  hosts/            # per-node setup outside k0s: tailscale, earlyoom, agents, CLIProxyAPI, Gatus
  cluster/
    k0sctl.yaml     # node list, roles, k0s config
  flux/
    infrastructure/ # CNI, tailscale-operator, storage, observability
    apps/           # workloads and experiments, one folder each
  burst/
    cli/            # burst CLI + MCP server, backend adapters, quota ledger
    operator/       # BurstJob CRD + controller (kubebuilder)
  ebpf/             # XDP firewall, egress meter, other eBPF programs
  docs/             # this design, runbooks
```

Flow: you or an agent push to `main`. Flux reconciles `flux/` into k0s, `k0sctl apply` handles `cluster/` changes, and each VPS is set up by its own `hosts/<node>/bootstrap.sh`, which you re-run after changing its configs. GitHub Actions (unlimited minutes on public repos) lints manifests, builds images and pushes them to GHCR.

## Roadmap

Five phases, each finished when its "done when" holds. Phases 3 and 4 can run in parallel.

1. **Foundation.** Create the homelab repo and the Doppler project with a single `prd` config and one service token per host. Write the tailnet policy (open between your devices, Tailscale SSH without browser re-auth) and turn on Tailnet Lock. Set up earlyoom on the small nodes, and log shipping to Axiom. Put agents on every node, CLIProxyAPI on vp2, and Gatus with its Healthchecks.io ping on vp1, all installed by their bootstrap scripts.
   - **Done when:** every node ships logs off-lab, and an agent on any node can reach every other node.
2. **k0s on defaults.** Bring up coop as controller plus worker, and bird as a worker, through k0sctl. vp1 and vp2 stay outside the cluster. Install Flux and the Tailscale operator.
   - **Done when:** a test app is reachable on the tailnet only, and Gatus on vp1 alerts when you stop it.
3. **Burst stage 1.** Build the burst CLI with Modal and Cloud Run Jobs adapters first, then the quota ledger and the MCP server.
   - **Done when:** an agent launches a GPU job on Modal through MCP and gets its logs back.
4. **Component swaps.** Move the CNI to Calico, then Cilium, then add storage and Linkerd, with one write-up per swap in `docs/`.
   - **Done when:** each swap can be explained, and rolled back, from the repo.
5. **Burst stage 2 and eBPF.** Write the BurstJob operator and build the eBPF projects.
   - **Done when:** `kubectl apply -f burstjob.yaml` runs on a free provider and reports status back.

## From your stars

About 40 of your stars slot directly into this design. They also point to two interests worth building around: eBPF and agent sandboxes.

| Area | Starred projects | Where they fit |
| --- | --- | --- |
| Cluster internals | containerd, client-go, kubebuilder, kind, kubie, timoni, pulumi-kubernetes | containerd work; BurstJob operator; local test clusters; packaging |
| Networking and eBPF | cilium, cilium/ebpf, aya, bcc, learning-ebpf, ubpf, katran, pingora, linkerd2 | CNI swap path; eBPF side projects on coop (custom XDP/tc programs, metrics) |
| Orchestration | run-ai, fake-gpu-operator, llm-d, dynamo, LMCache | fake-gpu-operator lets k0s advertise simulated GPUs, so you can build GPU scheduling and the BurstJob path without a GPU |
| Small-node survival | earlyoom, beszel, dozzle, litestream, unregistry | OOM control, light monitoring, SQLite backups to R2, pushing images straight to nodes with no registry |
| Agent sandboxes and tools | smolvm, gondolin, cloudflare/sandbox-sdk, flue, executor, cua, pi, openchamber, plannotator | Disposable agent environments; executor is a candidate for exposing the burst API and other integrations to agents |
| Agent sessions | zmx, mosh, sshx | Persistent and shareable agent terminals |
| LLM routing | CLIProxyAPI, catwalk | Gateway and model catalog |
| Infra as code | alchemy, effect-aws, floci, vercel-labs/emulate | Provisioning burst backends in TypeScript; testing adapters against local emulators instead of real quotas |
| Storage and data | rustfs, s2, honker, cowsql, pocketbase | Self-hosted S3 on coop; SQLite-backed queues for the ledger |

Language choice for the dispatcher. Your stars lean towards Effect (effect-smol, alchemy, effect-aws) and Go. A natural split is the CLI, ledger and MCP server in TypeScript with Effect, and the operator in Go with kubebuilder.

## Open questions

- [x] Are coop and bird on 24/7? coop is on 24/7; bird is powered off most days and back on almost daily.
- [x] Which free cloud VMs are actually in play? Neither; no cloud VMs join the cluster.
- [x] How much disk do vp1 and vp2 have? About 45 GB each, with 32 GB and 38 GB free (Oct 2026).
- [x] Should vp1 and vp2 join k0s? No; they stay plain systemd hosts, reached through selectorless Services and EndpointSlices.
- [ ] Dispatcher language: TypeScript with Effect for the CLI, or Go everywhere?
- [ ] Which agent accounts go through CLIProxyAPI, given the terms caveat?
- [ ] Where do backups of the Beszel data directory and CLIProxyAPI's OAuth token files go? R2 is already planned for etcd.
- [x] Do agents get restricted access? No; they get full access, the same as you (see Open inside the tailnet).
- [ ] Does CLIProxyAPI emit OpenTelemetry or usage events itself, or does CPA Usage Keeper have to supply them?
