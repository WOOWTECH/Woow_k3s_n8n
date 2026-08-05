# Woow_k3s_n8n — n8n 的 K3s/Kubernetes Helm Chart

[English](README.md)

在 K3s/Kubernetes 上部署 [n8n](https://n8n.io) 工作流程自動化平台的 Helm chart,
並可選配 [n8n-MCP](https://github.com/czlonkowski/n8n-mcp) 部署,供 AI Agent 管理工作流程。

> **要用其他平台部署?**
> Docker/Podman Compose → [Woow_podman_n8n](https://github.com/WOOWTECH/Woow_podman_n8n) ·
> Home Assistant add-on → [Woow_ha_n8n](https://github.com/WOOWTECH/Woow_ha_n8n)

## 架構

| 元件 | 映像 | Service | NodePort |
|---|---|---|---|
| n8n | `n8nio/n8n:latest` | `n8n:5678` | `30678` |
| n8n-MCP(選配) | `ghcr.io/czlonkowski/n8n-mcp:latest` | `n8n-mcp:3000` | `30300` |

- 儲存:SQLite 存於 `local-path` PVC(5Gi)— 單副本、`Recreate` 策略
- n8n-MCP 以 init container 等待 n8n 就緒後,以 HTTP 提供 MCP 服務

## 快速開始

```bash
# 直接以倉庫 tarball 安裝(免 clone)
helm install n8n https://github.com/WOOWTECH/Woow_k3s_n8n/archive/refs/heads/main.tar.gz

# 或 clone 後安裝
git clone https://github.com/WOOWTECH/Woow_k3s_n8n.git
cd Woow_k3s_n8n
helm install n8n .
```

> **非測試環境部署前務必更換密鑰:**
>
> ```bash
> helm install n8n . \
>   --set secrets.basicAuthPassword="$(openssl rand -base64 24)" \
>   --set secrets.encryptionKey="$(openssl rand -hex 32)" \
>   --set secrets.mcpAuthToken="$(openssl rand -hex 32)"
> ```
> `secrets.n8nApiKey` 需事後在 n8n 介面產生
> (Settings → API → Create API Key),再以 `helm upgrade` 帶入。

完成後開啟 `http://<node-ip>:30678`(預設帳號 `admin`/你設定的密碼)。

## 主要設定值

| 設定 | 預設 | 說明 |
|---|---|---|
| `namespace.create` / `namespace.name` | `true` / `n8n` | 目標 namespace |
| `n8n.image.tag` | `latest` | n8n 版本 |
| `n8n.service.type` / `nodePort` | `NodePort` / `30678` | n8n 對外方式 |
| `n8n.persistence.size` | `5Gi` | 資料 PVC(`local-path`) |
| `n8n.config.*` | 見 `values.yaml` | 環境變數(host、protocol、webhook URL…) |
| `mcp.enabled` | `true` | 是否部署 n8n-MCP |
| `mcp.service.nodePort` | `30300` | MCP 端點 NodePort |
| `secrets.*` | `changeme-…` | Basic-auth 密碼、加密金鑰、API 金鑰 |

完整清單:[`values.yaml`](values.yaml)

## 驗證

```bash
kubectl get pods -n n8n          # 兩個 pod 均 Running/Ready
curl http://<node-ip>:30678/healthz
```

## 移除

```bash
helm uninstall n8n
# Helm 會保留 PVC;確定不要資料後再刪:
kubectl delete pvc -n n8n n8n-data mcp-logs
```

## 從舊 Kustomize 部署遷移

本倉庫取代已封存的
[Woow_n8n_docker_compose_all](https://github.com/WOOWTECH/Woow_n8n_docker_compose_all)
`k3s` 分支。Chart 預設渲染結果與原 manifests 資源等價
(名稱、namespace、標籤、埠、PVC 皆相同),既有部署可交由 Helm 接管或維持原狀;
原始 Kustomize 檔案保留在本倉庫的 git 歷史中。

## 授權

MIT
