# File-by-file explanation (beginner friendly)

This document explains **what each file does** in `moment-forever-infra`.

---

## 1) High-level idea

This repository is a **GitOps CD repository**.

- Application repositories do CI (build, test, push Docker image).
- This infra repository stores desired Kubernetes state.
- Argo CD reads this repository and applies changes to Kubernetes.

---

## 2) Top-level files

| File | Why it exists |
|---|---|
| `README.md` | Main intro, folder map, and bootstrap overview for this repo. |

---

## 3) Argo CD control files (`argocd/`)

| File | Why it exists |
|---|---|
| `argocd/app-project.yaml` | Creates an Argo CD **AppProject** named `moment-forever` to define policy boundaries (allowed repo, allowed destination namespace, allowed resource kinds). |
| `argocd/root-application.yaml` | Creates the **root app (App-of-Apps)** named `moment-forever-root`. Argo watches this app, then loads all child app definitions from `argocd/applications/`. |

### Child app files (`argocd/applications/`)

| File | Why it exists |
|---|---|
| `platform.yaml` | Tells Argo how to deploy platform manifests from `clusters/dev/platform`. Also contains Image Updater annotations for platform image. |
| `booking.yaml` | Same pattern for booking service. |
| `payment.yaml` | Same pattern for payment service. |
| `gateway.yaml` | Same pattern for gateway service. |
| `ingress.yaml` | Tells Argo to deploy the app ingress resources from `clusters/dev/ingress`. |
| `argocd-ui.yaml` | Tells Argo to deploy the Argo CD UI ingress from `clusters/dev/argocd`. |
| `dashboard.yaml` | Tells Argo to deploy the Kubernetes Dashboard (manifest + admin ServiceAccount + ingress) from `clusters/dev/dashboard`. |

---

## 4) Kubernetes manifests (`clusters/dev/`)

| File | Why it exists |
|---|---|
| `clusters/dev/namespace.yaml` | Creates namespace `moment-forever-dev` for all dev services. |
| `clusters/dev/ingress/ingress.yaml` | Exposes the app gateway on the dev host `api.15.134.55.225.nip.io`. |
| `clusters/dev/argocd/ingress.yaml` | Exposes the Argo CD UI on the dev host `argocd.15.134.55.225.nip.io`. |
| `clusters/dev/dashboard/recommended.yaml` | Vendored upstream Kubernetes Dashboard v2.7.0 manifest (namespace, Deployment, Service, RBAC for the Dashboard's own service account). |
| `clusters/dev/dashboard/admin-user.yaml` | Creates the `admin-user` ServiceAccount and binds it to `cluster-admin` so the Dashboard login has full cluster access (explicit user choice — see security warning in `README.md`). |
| `clusters/dev/dashboard/ingress.yaml` | Exposes the Dashboard on the dev host `dashboard.15.134.55.225.nip.io`, proxying HTTPS to the Dashboard's self-signed backend. |

Each service folder has 3 files:

### Example: `clusters/dev/platform/`

| File | Why it exists |
|---|---|
| `kustomization.yaml` | Kustomize entry file. Lists resources (`deployment.yaml`, `service.yaml`) and the image name/tag managed by image updater. |
| `deployment.yaml` | Defines how platform pod runs (image, ports, probes, replicas). |
| `service.yaml` | Creates stable in-cluster network endpoint for platform pod(s). |

Same structure exists for:

- `clusters/dev/booking/`
- `clusters/dev/payment/`
- `clusters/dev/gateway/`
- `clusters/dev/ingress/`
- `clusters/dev/argocd/`
- `clusters/dev/dashboard/` (same idea, but 3 files: `recommended.yaml`, `admin-user.yaml`, `ingress.yaml` — no kustomize image-tag management since Dashboard isn't built by this project's CI)

---

## 5) How Argo CD reads these files

1. You apply `argocd/root-application.yaml`.
2. Argo creates app `moment-forever-root`.
3. Root app points to `argocd/applications` path.
4. Argo loads `platform.yaml`, `booking.yaml`, `payment.yaml`, `gateway.yaml`.
5. Each child app points to its own `clusters/dev/<service>` path.
6. Argo syncs those manifests to Kubernetes namespace `moment-forever-dev`.

---

## 6) How image SHA tag moves into this repo

This repo is prepared for **Argo CD Image Updater**:

1. CI pushes image like `groote123/moment-forever-platform:<sha>`.
2. Image Updater checks registry and finds newer SHA tag.
3. Based on annotations in `argocd/applications/*.yaml`, it updates:
   - `clusters/dev/<service>/kustomization.yaml` -> `newTag: <sha>`
4. That change is committed to this repo.
5. Argo CD detects git change and deploys the new image.

That is the GitOps loop.

---

## 7) What you usually edit day-to-day

- Change replica/resource/probe/service config -> edit `deployment.yaml` or `service.yaml`.
- Pin/fix image tag manually -> edit `kustomization.yaml`.
- Add a new microservice -> add new child app + service folder.

---

## 8) Change scenarios (real examples)

## Scenario A: Increase platform replicas from 1 to 3

1. Open `clusters/dev/platform/deployment.yaml`.
2. Change `replicas: 1` to `replicas: 3`.
3. Commit and push.
4. Argo sees Git change and creates more pods.

What to check after sync:

- `kubectl get pods -n moment-forever-dev`
- `kubectl get deploy platform -n moment-forever-dev`

## Scenario B: Temporarily pin booking image to older SHA

1. Open `clusters/dev/booking/kustomization.yaml`.
2. Set:
   - `newTag: <old-sha>`
3. Commit and push.
4. Argo rolls booking back to that image.

Why this is useful:

- Fast rollback without manual cluster edits.
- Full rollback history remains in Git.

## Scenario C: Add a new service (for example `notification`)

1. Create `clusters/dev/notification/` with:
   - `deployment.yaml`
   - `service.yaml`
   - `kustomization.yaml`
2. Add `argocd/applications/notification.yaml`.
3. Commit and push.
4. Root app creates child app automatically.

---

## 9) Files that usually need environment-specific values

These values are expected to differ between local/dev/stage/prod:

- `repoURL` in Argo Applications (if org/repo differs)
- image repositories/tags
- replicas
- resources (CPU/memory)
- probes (health endpoint path)
- namespace
- ingress/domain/tls (when you add ingress later)

---

## 10) Safety rules for beginners

1. Never hot-fix directly in cluster (`kubectl edit`) unless emergency.
2. Always commit desired state to Git first.
3. If Argo keeps reverting your manual change, that is normal GitOps behavior.
4. Keep CI and CD responsibilities separate:
   - CI builds artifacts
   - CD declares/deploys artifacts
