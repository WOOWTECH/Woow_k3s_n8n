# Woow_k3s_n8n — n8n Helm Chart（K3s/Kubernetes）

[English](README.md)

給 [n8n](https://n8n.io) 工作流程自動化用的 Helm chart，跑在 K3s/Kubernetes 上。
**一個 release 對應一個實例。** woow-k3s 上現有的每個 n8n 都是用 `kubectl apply`
手動佈署的，物件名稱、labels、探針、安全性設定各自不同，所以這個 chart 幾乎所有
東西都從 values 產生，而不是假設單一固定的形狀。Chart 預設不建立 Namespace 也不
建立 Secret，只會參照一個既有的 `existingSecret`，因此可以接管已經在跑的佈署而
不重啟它。

> **n8n-MCP 已經搬出這個 chart。** AI agent 用的 MCP sidecar 跟它的 nginx proxy
> 現在是每個實例各自獨立的 chart/release，在
> [WOOWTECH/woow_n8n_mcp_server](https://github.com/WOOWTECH/woow_n8n_mcp_server)。
>
> **要找其他平台版本？**
> Docker/Podman Compose → [Woow_podman_n8n](https://github.com/WOOWTECH/Woow_podman_n8n) ·
> Home Assistant add-on → [Woow_ha_n8n](https://github.com/WOOWTECH/Woow_ha_n8n)

## woow-k3s 上的實例

| Release | Namespace | 網址 | Values |
|---|---|---|---|
| `n8n` | `woowtech-odoo` | https://n8n.woowtech.io | [`deploy/woow-k3s/woowtech-odoo.yaml`](deploy/woow-k3s/woowtech-odoo.yaml) |
| `cindytech-n8n` | `cindytech` | https://cindytech1-n8n.woowtech.io | [`deploy/woow-k3s/cindytech.yaml`](deploy/woow-k3s/cindytech.yaml) |

這兩個 namespace 都跟其他 app（Odoo、tunnel...）共用，這個 chart 不會去管它們，
只管自己的 Deployment、Service、PVC。每份實例 values 檔都寫清楚怎麼重現、怎麼
接管對應的正式 release。`scripts/check-drift.sh` 可以比對 chart 跟正在跑的
release、以及正式物件之間有沒有差異。

## Chart 會渲染什麼

| Template | 物件 | 開關 |
|---|---|---|
| `templates/deployment.yaml` | Deployment（n8n 容器 + 可選的 `fix-permissions` initContainer） | 一定渲染 |
| `templates/service.yaml` | Service | 一定渲染 |
| `templates/pvc.yaml` | `/home/node/.n8n` 用的 PVC（SQLite + 憑證） | 一定渲染 |
| `templates/secret.yaml` | 內含 `N8N_BASIC_AUTH_PASSWORD` / `N8N_ENCRYPTION_KEY` 的 Secret | `secrets.create`（預設關） |
| `templates/tests/smoke.yaml` | `helm test` pod（`GET /healthz`） | `tests.enabled` |

沒有 Namespace template：如果 namespace 還不存在，安裝時要自己加
`--create-namespace`（或先手動建立）。

## 快速開始

務必明確指定 context（helm 用 `--kube-context`，kubectl 用 `--context`）。

### A. 讓 chart 建立 Secret（新裝 / 測試用）

```bash
helm --kube-context woow-k3s install n8n \
  https://github.com/WOOWTECH/Woow_k3s_n8n/archive/refs/heads/main.tar.gz \
  -n n8n --create-namespace \
  --set labels.selector.app=n8n \
  --set secrets.create=true \
  --set secrets.basicAuthPassword="$(openssl rand -base64 24)" \
  --set secrets.encryptionKey="$(openssl rand -hex 32)"
```

`labels.selector`沒有預設值（原因見下方「設計決策」），一定要自己設定。

### B. Secret 在 Helm 之外自行管理（woow-k3s 的做法）

預設 `secrets.create=false`，chart 完全不會渲染或碰 Secret，所以 upgrade 永遠
不會不小心把真的金鑰蓋掉。

```bash
kubectl --context woow-k3s create namespace n8n
cp examples/secrets.example.yaml ~/secure/n8n-secrets.yaml   # 把每個 REPLACE_ME 填好
kubectl --context woow-k3s apply -f ~/secure/n8n-secrets.yaml

git clone https://github.com/WOOWTECH/Woow_k3s_n8n.git && cd Woow_k3s_n8n
helm --kube-context woow-k3s install n8n . -n n8n \
  --set existingSecret=n8n-secrets --set labels.selector.app=n8n
```

### C. 測試安裝（自己的 namespace、可拋棄的儲存）

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

### 接管正在跑的 kubectl 佈署

```bash
helm --kube-context woow-k3s upgrade --install n8n . -n woowtech-odoo \
  -f deploy/woow-k3s/woowtech-odoo.yaml --take-ownership
```

該 release 的確切指令請看對應的實例 values 檔；渲染結果跟目前正式物件完全一致，
不會重啟任何 pod。

## 主要 values

| Value | 預設 | 說明 |
|---|---|---|
| `namespace` | `""`（release namespace） | 只有要裝到跟 `-n` 不同的 namespace 時才需要設 - **絕對不要**在已提交的 `deploy/woow-k3s/*.yaml` 裡設定這個值，它會悄悄蓋過 `-n`（見 `values.yaml` 裡的警告） |
| `fullnameOverride` | `""` | Deployment/Service/PVC 的基礎名稱（各物件也各自有自己的覆寫） |
| `existingSecret` | `""`（必填） | 內含 `N8N_BASIC_AUTH_PASSWORD` / `N8N_ENCRYPTION_KEY` 的 Secret |
| `secrets.create` | `false` | 從 `secrets.*` 渲染 Secret，取代使用 `existingSecret` |
| `keepOnUninstall` | `true` | 在 PVC 跟任何 chart 建立的 Secret 上加 `helm.sh/resource-policy: keep` |
| `labels.selector` | `{}`（必填） | Deployment 的 `matchLabels` / pod-template labels，release 存續期間固定不變 |
| `strategy.type` | `RollingUpdate` | 或 `Recreate` |
| `nodeSelector` / `podSecurityContext` / `containerSecurityContext` | `{}` | 原封不動透傳的 map |
| `probes.liveness` / `.readiness` / `.startup` | `{}`（關閉） | 原封不動的 k8s probe 物件 |
| `podAnnotations` | `{}` | Pod-template 的 `metadata.annotations`；兩個線上實例都在這裡設自己的 `kubectl.kubernetes.io/restartedAt`（見下方「從 kubectl manifest 遷移」） |
| `env` | basic-auth + 時區/host/port/protocol/webhook/... | 完整、順序固定的容器環境變數清單 |
| `persistence.storageClassName` | `longhorn-delete`（測試預設） | woow-k3s 正式實例用 `longhorn` |
| `tests.enabled` | `true` | `helm test` smoke pod |

完整清單見 [`values.yaml`](values.yaml)。

## 驗證

```bash
helm --kube-context woow-k3s test n8n -n woowtech-odoo --logs   # GET /healthz（唯讀）
kubectl --context woow-k3s -n woowtech-odoo exec deploy/n8n -- test -f /home/node/.n8n/database.sqlite

# 比對 repo、Helm release、正式物件（exit 0 = 完全一致）
RELEASE=n8n NAMESPACE=woowtech-odoo scripts/check-drift.sh -f deploy/woow-k3s/woowtech-odoo.yaml
RELEASE=cindytech-n8n NAMESPACE=cindytech scripts/check-drift.sh -f deploy/woow-k3s/cindytech.yaml
```

## 解除安裝

```bash
helm --kube-context woow-k3s uninstall n8n -n woowtech-odoo
```

這只會移除 Deployment 跟 Service。PVC 帶有 `helm.sh/resource-policy: keep`，
所以工作流程資料跟 SQLite 資料庫不會被刪；既有的 Secret 本來就不是 chart 管的，
不論如何都不會動到。這個 chart 從不渲染 namespace，所以也不會被刪除。

## 從 kubectl manifest 遷移

woow-k3s 上現有的每個 n8n 都是純 `kubectl apply`。搭配對應的實例 values 渲染，
這個 chart 跟目前正在跑的 Deployment/Service/PVC 逐欄位相同。唯一刻意的差異：

1. PVC 會多一個 `helm.sh/resource-policy: keep`（純 `kubectl apply` 時沒有這個
   keep policy）。這只動到 PVC 的 metadata，不碰 pod template，所以接管時
   還是不會重啟任何東西。
2. 接管後會加上 Helm 自己的 release 追蹤 metadata：`meta.helm.sh/release-name`
   與 `-namespace` annotation，以及 `app.kubernetes.io/managed-by: Helm`（會蓋掉
   `cindytech` 那組物件現在帶的 `app.kubernetes.io/managed-by: kubectl`）。
   只動到物件的 metadata，selector 跟 pod template 都不會變，所以不會重啟。

除此之外沒有別的差異。pod template 是逐字重現的，其中兩個細節特別容易漏掉：

- **環境變數順序。** 每個實例檔案的 `env` 是照線上容器的實際順序列出的。
  Kubernetes 會照 pod template 寫下來的樣子做雜湊，光是重排順序就會讓
  ReplicaSet 重建。
- **`kubectl.kubernetes.io/restartedAt`。** `kubectl rollout restart` 會把這個
  annotation 寫進**儲存起來的** pod template，所以它本來就是線上 pod-template
  雜湊的一部分。每個實例檔案都用 `podAnnotations` 帶著它的 Deployment 目前
  那個時間戳。日後只要有人再跑一次 `kubectl rollout restart`，就要把新的時間戳
  複製回那個檔案 - 在那之前 `scripts/check-drift.sh` 會一直回報 drift。

> **安全性：** 沒有任何 `deploy/woow-k3s/*.yaml` 檔案會設定 `namespace:` -
> 上面每一條指令、每個實例檔案的目標 namespace，完全是由 `-n`/`--namespace`
> 決定。絕對不要在這些檔案裡加上 `namespace:` 這個 key（見 `values.yaml`
> 裡 `namespace` 旁的警告）；一旦加了，那個 release 就不再由 `-n` 控制物件
> 要放到哪裡 - 在拿正式實例的檔案去 `-f` 一個拋棄式測試 namespace 做接管
> 演練時，這特別危險。

現有的 kubectl 佈署可以直接接管而不重啟任何 pod：

```bash
helm --kube-context woow-k3s upgrade --install n8n . -n woowtech-odoo \
  -f deploy/woow-k3s/woowtech-odoo.yaml --take-ownership
```

## 設計決策

| 設定 | 原因 |
|---|---|
| `labels.selector` 沒有預設值 | Helm 對 map 型別的 values 會做深層合併；如果給非空的預設值，會偷偷跟實例自己的 selector 聯集，而不是被它取代 |
| 大部分 pod-spec 的開關都是原封不動透傳的 map（`toYaml`） | 兩個正式實例在幾乎每個 pod-spec 細節（探針、securityContext、nodeSelector、strategy）都不一樣；型別化的 values 沒辦法同時表達兩者，還要一直改 chart |
| 預設 `secrets.create=false` | upgrade 永遠不會不小心蓋掉真的憑證 |
| PVC 上的 keep policy | `helm uninstall` 永遠不會刪掉工作流程資料或加密金鑰的密文 |
| 沒有 Namespace template | 現有每個實例都跟其他 app（Odoo、tunnel）共用 namespace，這個 chart 絕對不能去管它 |
| n8n-MCP 獨立成自己的 chart | 每個 MCP 實例各自一個 release，跟 n8n 本身分開升級 |
| smoke test 打 `/healthz`、不帶認證 | 跟 n8n 自己的 liveness/readiness 探針一致；這個端點本來就不在 `N8N_BASIC_AUTH` 保護範圍內 |

## 相關 repo

- [Woow_podman_n8n](https://github.com/WOOWTECH/Woow_podman_n8n)：同一套 app 用 rootless Podman 跑在單機上
- [Woow_ha_n8n](https://github.com/WOOWTECH/Woow_ha_n8n)：Home Assistant add-on 包裝
- [woow_n8n_mcp_server](https://github.com/WOOWTECH/woow_n8n_mcp_server)：n8n-MCP sidecar 跟它的 Helm chart

## 安全性

- 沒有提交任何真的 secret。`values.yaml` 的 secret 欄位都是空的，
  `examples/secrets.example.yaml` 都是佔位符，`deploy/` 底下不放 secret，
  CI 會檢查這三件事。
- Basic auth 保護 UI 跟 REST API；`/healthz` 不需要帶認證。

## 授權

WoowTech 內部佈署設定，僅供內部使用。
