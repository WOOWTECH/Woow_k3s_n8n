# Woow_k3s_n8n — n8n Helm Chart for K3s/Kubernetes

[繁體中文](README_zh-TW.md)

Helm chart for [n8n](https://n8n.io) workflow automation on K3s/Kubernetes.
**One release per instance.** Every n8n on woow-k3s today was hand-applied
with `kubectl` and each has its own object names, labels, probes and
security settings, so this chart renders almost everything from values
instead of assuming a single fixed shape. The chart never creates a
Namespace or a Secret by default; it only references an `existingSecret`, so
it can adopt an already-running deployment without restarting it.

> **n8n-MCP moved out of this chart.** The AI-agent MCP sidecar and its nginx
> proxy are now their own chart/release per instance in
> [WOOWTECH/woow_n8n_mcp_server](https://github.com/WOOWTECH/woow_n8n_mcp_server).
>
> **Looking for another platform?**
> Docker/Podman Compose → [Woow_podman_n8n](https://github.com/WOOWTECH/Woow_podman_n8n) ·
> Home Assistant add-on → [Woow_ha_n8n](https://github.com/WOOWTECH/Woow_ha_n8n)

## Instances on woow-k3s

| Release | Namespace | URL | Values |
|---|---|---|---|
| `n8n` | `woowtech-odoo` | https://n8n.woowtech.io | [`deploy/woow-k3s/woowtech-odoo.yaml`](deploy/woow-k3s/woowtech-odoo.yaml) |
| `cindytech-n8n` | `cindytech` | https://cindytech1-n8n.woowtech.io | [`deploy/woow-k3s/cindytech.yaml`](deploy/woow-k3s/cindytech.yaml) |

Both namespaces are shared with other apps (Odoo, tunnels, ...) this chart
does not own; it only manages its own Deployment, Service and PVC in them.
Each instance file documents exactly how to reproduce and take over its live
release. `scripts/check-drift.sh` compares the chart against a running
release and the live objects.

## What the chart renders

| Template | Object | Toggle |
|---|---|---|
| `templates/deployment.yaml` | Deployment (n8n container + optional `fix-permissions` init container) | always |
| `templates/service.yaml` | Service | always |
| `templates/pvc.yaml` | PVC for `/home/node/.n8n` (SQLite + credentials) | always |
| `templates/secret.yaml` | Secret with `N8N_BASIC_AUTH_PASSWORD` / `N8N_ENCRYPTION_KEY` | `secrets.create` (default off) |
| `templates/tests/smoke.yaml` | `helm test` pod (`GET /healthz`) | `tests.enabled` |

There is no Namespace template: install with `--create-namespace` (or apply
the namespace yourself) if it does not already exist.

## Quick start

Always pass the context explicitly (`--kube-context` for helm, `--context` for kubectl).

### A. Let the chart create the Secret (fresh install / test)

```bash
helm --kube-context woow-k3s install n8n \
  https://github.com/WOOWTECH/Woow_k3s_n8n/archive/refs/heads/main.tar.gz \
  -n n8n --create-namespace \
  --set labels.selector.app=n8n \
  --set secrets.create=true \
  --set secrets.basicAuthPassword="$(openssl rand -base64 24)" \
  --set secrets.encryptionKey="$(openssl rand -hex 32)"
```

`labels.selector` has no default (see "Design decisions" below) - always set it.

### B. Manage the Secret outside Helm (how woow-k3s runs)

With the default `secrets.create=false`, the chart never renders or touches a
Secret, so no upgrade can ever overwrite a real key.

```bash
kubectl --context woow-k3s create namespace n8n
cp examples/secrets.example.yaml ~/secure/n8n-secrets.yaml   # fill every REPLACE_ME
kubectl --context woow-k3s apply -f ~/secure/n8n-secrets.yaml

git clone https://github.com/WOOWTECH/Woow_k3s_n8n.git && cd Woow_k3s_n8n
helm --kube-context woow-k3s install n8n . -n n8n \
  --set existingSecret=n8n-secrets --set labels.selector.app=n8n
```

### C. Test install (own namespace, disposable storage)

```bash
NS=ht-n8n
helm --kube-context woow-k3s install n8n . -n $NS --create-namespace \
  --set labels.selector.app=n8n \
  --set persistence.storageClassName=longhorn-delete \
  --set secrets.create=true \
  --set secrets.basicAuthPassword="$(openssl rand -base64 24)" \
  --set secrets.encryptionKey="$(openssl rand -hex 32)"
kubectl --context woow-k3s -n $NS rollout status deploy/n8n
helm --kube-context woow-k3s test n8n -n $NS --logs
```

### Adopt a running kubectl-applied n8n

```bash
helm --kube-context woow-k3s upgrade --install n8n . -n woowtech-odoo \
  -f deploy/woow-k3s/woowtech-odoo.yaml --take-ownership
```

See the instance file for the exact command for that release; it renders
identically to the current live objects, so nothing restarts.

## Key values

| Value | Default | Description |
|---|---|---|
| `namespace` | `""` (release namespace) | Only set to install into a namespace different from `-n` - **never** set this in a checked-in `deploy/woow-k3s/*.yaml` file, it silently overrides `-n` (see `values.yaml`) |
| `fullnameOverride` | `""` | Base name for the Deployment/Service/PVC (each object also has its own override) |
| `existingSecret` | `""` (required) | Secret with `N8N_BASIC_AUTH_PASSWORD` / `N8N_ENCRYPTION_KEY` |
| `secrets.create` | `false` | Render a Secret from `secrets.*` instead of using `existingSecret` |
| `keepOnUninstall` | `true` | `helm.sh/resource-policy: keep` on the PVC and any chart-created Secret |
| `labels.selector` | `{}` (required) | Deployment `matchLabels` / pod-template labels - fixed for the release's life |
| `strategy.type` | `RollingUpdate` | Or `Recreate` |
| `nodeSelector` / `podSecurityContext` / `containerSecurityContext` | `{}` | Raw pass-through maps |
| `probes.liveness` / `.readiness` / `.startup` | `{}` (disabled) | Raw k8s probe objects |
| `podAnnotations` | `{}` | Pod-template `metadata.annotations` (chart-managed only; see "Migrating" below) |
| `env` | basic-auth + timezone/host/port/protocol/webhook/... | Full, exactly-ordered container env list |
| `persistence.storageClassName` | `longhorn-delete` (test default) | `longhorn` on woow-k3s instances |
| `tests.enabled` | `true` | `helm test` smoke pod |

Full list: [`values.yaml`](values.yaml).

## Verify

```bash
helm --kube-context woow-k3s test n8n -n woowtech-odoo --logs   # GET /healthz (read-only)
kubectl --context woow-k3s -n woowtech-odoo exec deploy/n8n -- test -f /home/node/.n8n/database.sqlite

# Repo vs Helm release vs live objects (exit 0 = identical)
RELEASE=n8n NAMESPACE=woowtech-odoo scripts/check-drift.sh -f deploy/woow-k3s/woowtech-odoo.yaml
RELEASE=cindytech-n8n NAMESPACE=cindytech scripts/check-drift.sh -f deploy/woow-k3s/cindytech.yaml
```

## Uninstall

```bash
helm --kube-context woow-k3s uninstall n8n -n woowtech-odoo
```

This removes the Deployment and Service. The PVC carries `helm.sh/resource-policy: keep`
so workflow data and the SQLite database are never deleted; the existing
Secret is untouched either way because the chart never owns it. The
namespace is never rendered by this chart, so it is never deleted either.

## Migrating from the kubectl manifests

Every n8n on woow-k3s today is a plain `kubectl apply`. Rendered with the
matching instance values, this chart is field-for-field equivalent to the
running Deployment/Service/PVC. The only intentional differences:

1. The PVC gains `helm.sh/resource-policy: keep` (it had no keep policy under
   plain `kubectl apply`).
2. Helm's own release-tracking annotations/labels are added on adoption.
3. The container env list is generated in a fixed order (secret-backed vars
   first, then `extraEnv`); n8n does not care about env order.
4. Neither live Deployment's `spec.template.metadata.annotations` (both
   currently carry a `kubectl.kubernetes.io/restartedAt` timestamp left over
   from a manual `kubectl rollout restart`) is reproduced by default. It is
   transient operator metadata, not part of the desired pod spec, and
   Kubernetes/Helm merge annotation maps on apply rather than replacing them
   - so a take-over upgrade leaves it in place either way and never restarts
   the pod over it. Use `podAnnotations` if an instance needs the chart to
   actually manage a pod-template annotation.

> **Safety:** no `deploy/woow-k3s/*.yaml` file sets `namespace:` - the target
> namespace for every command above and in each instance file is controlled
> entirely by `-n`/`--namespace`. Never add a `namespace:` key to one of
> these files (see the warning next to `namespace` in `values.yaml`); doing
> so would make `-n` silently stop controlling object placement for that
> release, which is especially dangerous when rehearsing a take-over in a
> disposable test namespace with `-f` pointed at a real instance file.

An existing kubectl deployment can be adopted without restarting any pod:

```bash
helm --kube-context woow-k3s upgrade --install n8n . -n woowtech-odoo \
  -f deploy/woow-k3s/woowtech-odoo.yaml --take-ownership
```

## Design decisions

| Setting | Why |
|---|---|
| `labels.selector` has no default | Helm deep-merges map values; a non-empty default would silently union with an instance's own selector instead of being replaced by it |
| Most pod-spec knobs are raw pass-through maps (`toYaml`) | The two live instances differ in nearly every pod-spec detail (probes, securityContext, nodeSelector, strategy); typed values could not express both without constant chart changes |
| `secrets.create=false` by default | An upgrade can never overwrite a real credential |
| Keep policy on the PVC | `helm uninstall` can never delete workflow data or the encryption key's ciphertext |
| No Namespace template | Every current instance shares its namespace with other apps (Odoo, tunnels) this chart must never own |
| n8n-MCP in its own chart | One release per MCP instance, upgraded independently of n8n itself |
| `/healthz` smoke test, no auth header | Matches n8n's own liveness/readiness probes; the endpoint is not behind `N8N_BASIC_AUTH` |

## Related repositories

- [Woow_podman_n8n](https://github.com/WOOWTECH/Woow_podman_n8n): the same app on a single host with rootless Podman
- [Woow_ha_n8n](https://github.com/WOOWTECH/Woow_ha_n8n): Home Assistant add-on packaging
- [woow_n8n_mcp_server](https://github.com/WOOWTECH/woow_n8n_mcp_server): the n8n-MCP sidecar and its Helm chart

## Security

- No real secret is committed. `values.yaml` has empty secret values,
  `examples/secrets.example.yaml` has placeholders, `deploy/` holds no
  secrets, and CI enforces all three.
- Basic auth protects the UI and REST API; `/healthz` does not require it.

## License

Internal WoowTech deployment configuration.
