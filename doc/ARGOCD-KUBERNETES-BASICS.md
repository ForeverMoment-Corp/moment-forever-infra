# Argo CD and Kubernetes basics (simple explanation)

If you are new to DevOps, read this first.

---

## 1) What is Kubernetes?

Kubernetes (K8s) is a platform that runs your containers reliably.

Think of it as a smart manager that:

- starts your services,
- restarts them if they crash,
- gives stable networking,
- scales replicas up/down,
- keeps real state close to the config you define.

### Key objects used in this repo

- **Namespace**: logical folder inside cluster (`moment-forever-dev`).
- **Deployment**: says how many pods to run and which image to use.
- **Service**: gives stable DNS + virtual IP for pods.

---

## 2) What is Argo CD?

Argo CD is a **GitOps controller** for Kubernetes.

GitOps means:

- Git repo is the source of truth.
- Argo continuously compares:
  - desired state in Git
  - live state in cluster
- If different, Argo syncs cluster to match Git.

In short: **you update Git, Argo updates Kubernetes**.

---

## 3) What is App-of-Apps and why root app?

Instead of creating many Argo apps manually, we use one root app:

- `argocd/root-application.yaml` = root app
- It points to `argocd/applications/`
- Child app files inside that folder are auto-managed

This pattern makes scaling easy:

- add new child app file -> root app auto-picks it
- one place to bootstrap all services

---

## 4) How Argo knows which repo to read

In `argocd/root-application.yaml`:

- `repoURL` tells Argo which git repository
- `targetRevision` tells branch/tag
- `path` tells folder path in repo

Example logic:

- repoURL = `moment-forever-infra`
- path = `argocd/applications`
- Argo reads all YAML in that path and creates child apps.

---

## 5) How child apps deploy each service

Each child app (platform/booking/payment/gateway):

- points to `clusters/dev/<service>`
- syncs deployment/service manifests in that path
- deploys into namespace `moment-forever-dev`

---

## 6) How new image SHA reaches cluster

Flow:

1. CI in app repo builds and pushes image: `image:<commit-sha>`.
2. Argo CD Image Updater detects new allowed tag.
3. It updates `kustomization.yaml` newTag in this infra repo.
4. Commit appears in infra repo history.
5. Argo CD sees git change and syncs cluster.

No manual `kubectl set image` needed.

---

## 7) Why this split is good

- CI remains simple and fast.
- CD remains centralized and auditable.
- Rollback is easy (git revert).
- Every change is visible in PR/commit history.

---

## 8) Deep-dive: full end-to-end flow for one commit

Let us follow one platform commit from code to cluster:

1. Developer pushes commit in platform app repo.
2. Platform CI runs (build/test/docker push).
3. CI pushes image:
   - `groote123/moment-forever-platform:<sha>`
4. Argo CD Image Updater scans Docker Hub.
5. It finds that `<sha>` is newer than current tag in infra repo.
6. It updates:
   - `clusters/dev/platform/kustomization.yaml`
   - `newTag: <sha>`
7. It commits that change to infra repo.
8. Argo CD detects infra repo commit.
9. Argo compares desired vs live state.
10. Argo applies updated manifests.
11. Kubernetes rollout updates platform deployment pods.
12. New pods become Ready, old pods terminate.

This is the clean GitOps lifecycle.

---

## 9) Argo CD sync status you will see in UI

- **Synced**: cluster state matches Git desired state.
- **OutOfSync**: cluster differs from Git.
- **Progressing**: sync started, rollout still in progress.
- **Healthy**: resource health checks are currently good.
- **Degraded**: resource exists but is unhealthy (for example crashing pod).
- **Missing**: resource expected in Git is not present live.

---

## 10) Difference between Argo CD and Image Updater

- **Argo CD**:
  - Reads Git and applies manifests.
  - Does not automatically discover newest image tags on its own.

- **Argo CD Image Updater**:
  - Watches container registry tags.
  - Decides if a new allowed tag should be used.
  - Writes updated tag back to Git (recommended mode).

Together:

- Image Updater changes Git,
- Argo CD deploys that Git change.

---

## 11) Why SHA tags are better than only latest

Using commit SHA tags gives:

- traceability (exact code commit for each running pod),
- safer rollback (just revert tag),
- better debugging (no ambiguity),
- consistent deployments across environments.

`latest` can still be used as convenience, but should not be the only deployment tag in serious environments.

