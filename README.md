# Woow_k3s_n8n — n8n Helm Chart for K3s/Kubernetes

[繁體中文](README_zh-TW.md)

Helm chart deploying [n8n](https://n8n.io) workflow automation on K3s/Kubernetes,
with an optional [n8n-MCP](https://github.com/czlonkowski/n8n-mcp) deployment for
AI-agent workflow management.

> **Looking for another platform?**
> Docker/Podman Compose → [Woow_podman_n8n](https://github.com/WOOWTECH/Woow_podman_n8n) ·
> Home Assistant add-on → [Woow_ha_n8n](https://github.com/WOOWTECH/Woow_ha_n8n)

## Architecture

| Component | Image | Service | NodePort |
|---|---|---|---|
| n8n | `n8nio/n8n:latest` | `n8n:5678` | `30678` |
| n8n-MCP (optional) | `ghcr.io/czlonkowski/n8n-mcp:latest` | `n8n-mcp:3000` | `30300` |

- Storage: SQLite on a `local-path` PVC (5Gi) — single replica, `Recreate` strategy
- n8n-MCP waits for n8n via an init container, then serves MCP over HTTP

## Quick start

```bash
# Install straight from the repo tarball (no clone needed)
helm install n8n https://github.com/WOOWTECH/Woow_k3s_n8n/archive/refs/heads/main.tar.gz

# Or from a local clone
git clone https://github.com/WOOWTECH/Woow_k3s_n8n.git
cd Woow_k3s_n8n
helm install n8n .
```

> **Change the secrets before any non-test deployment:**
>
> ```bash
> helm install n8n . \
>   --set secrets.basicAuthPassword="$(openssl rand -base64 24)" \
>   --set secrets.encryptionKey="$(openssl rand -hex 32)" \
>   --set secrets.mcpAuthToken="$(openssl rand -hex 32)"
> ```
> `secrets.n8nApiKey` is generated later in the n8n UI
> (Settings → API → Create API Key), then applied with `helm upgrade`.

Then open `http://<node-ip>:30678` (default login `admin` / the password you set).

## Key values

| Value | Default | Description |
|---|---|---|
| `namespace.create` / `namespace.name` | `true` / `n8n` | Target namespace |
| `n8n.image.tag` | `latest` | n8n version |
| `n8n.service.type` / `nodePort` | `NodePort` / `30678` | How n8n is exposed |
| `n8n.persistence.size` | `5Gi` | Data PVC (`local-path`) |
| `n8n.config.*` | see `values.yaml` | Env vars (host, protocol, webhook URL…) |
| `mcp.enabled` | `true` | Deploy the n8n-MCP server |
| `mcp.service.nodePort` | `30300` | MCP endpoint NodePort |
| `secrets.*` | `changeme-…` | Basic-auth password, encryption key, API keys |

Full list: [`values.yaml`](values.yaml)

## Verify

```bash
kubectl get pods -n n8n          # both pods Running/Ready
curl http://<node-ip>:30678/healthz
```

## Uninstall

```bash
helm uninstall n8n
# PVCs are kept by Helm; remove them (and your data!) with:
kubectl delete pvc -n n8n n8n-data mcp-logs
```

## Migrating from the old Kustomize deployment

This repository replaces the `k3s` branch of the archived
[Woow_n8n_docker_compose_all](https://github.com/WOOWTECH/Woow_n8n_docker_compose_all)
repo. The chart's default rendering is resource-equivalent to those manifests
(same names, namespace, labels, ports, PVCs), so an existing deployment can be
adopted by Helm or simply left as-is; the original Kustomize files remain
available in this repo's git history.

## License

MIT
