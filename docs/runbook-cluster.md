# Cluster runbook

Building or rebuilding the k0s cluster on coop and bird. Run everything on coop as
`themiya`, except step 1, which runs as root on each host.

1. **Hosts.** From a checkout of this repo on each host, as root:
   `hosts/coop/bootstrap.sh` and `hosts/bird/bootstrap.sh`. On coop this also installs
   k0sctl, kubectl and flux at pinned versions, and gives coop the SSH key it needs to log
   in to itself as root.
2. **Cluster.** `k0sctl apply --config cluster/k0sctl.yaml`, about four minutes. Then
   `k0sctl kubeconfig --config cluster/k0sctl.yaml > ~/.kube/config && chmod 600 ~/.kube/config`.
3. **Pod routes.** `cluster/pod-routes.sh`, then approve the two new routes once in the
   Tailscale admin console (Machines, then each node, then Edit route settings). A rebuilt
   cluster can hand out different ranges, so check the approvals match. An `autoApprovers`
   rule for `10.244.0.0/16` in the tailnet policy would remove this step.
4. **Flux.**
   ```bash
   GITHUB_TOKEN=$(gh auth token) flux bootstrap github --owner=tkuhemiya \
     --repository=homelab --branch=main --path=flux/clusters/homelab --personal \
     --components=source-controller,kustomize-controller,helm-controller
   ```
   It commits to the repo and finds what's already there, so running it again is safe.
5. **The one secret created by hand.** In Doppler, project `homelab`, config `prd`, create
   a read-only service token named `k0s`. Then:
   ```bash
   printf 'Doppler token: '; stty -echo; read -r T; stty echo; echo
   printf %s "$T" | kubectl -n external-secrets create secret generic doppler-token \
     --from-file=dopplerToken=/dev/stdin
   unset T
   ```
   External Secrets then fills in every other Secret from Doppler. If a sync looks stuck,
   force it with `kubectl -n <ns> annotate externalsecret <name> force-sync="$(date +%s)" --overwrite`.
6. **Check.** `flux get kustomizations` shows all ready, `kubectl get clustersecretstore,externalsecret -A`
   shows `Valid` and `SecretSynced`, and `https://whoami.tailff3296.ts.net` answers.

## Changing the cluster

Edit on the Mac, push, `git pull` on coop, then `k0sctl apply` for anything under
`cluster/`. Flux picks up everything under `flux/` by itself.

**Network settings don't reach nodes that already have them.** kube-router writes its CNI
file `/etc/cni/net.d/10-kuberouter.conflist` only if it doesn't exist, so a changed `mtu`
needs these on each node: delete that file, delete the kube-router pod, then restart
every pod that uses the pod network so it gets the new setting.

## bird is switched off most days

It shows `NotReady` while off, and rejoins by itself when it boots. Its pods get
rescheduled after five minutes. `cluster/pod-routes.sh` can't reach it while it's off:
run it again when it's up.
