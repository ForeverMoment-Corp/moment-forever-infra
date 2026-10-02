# Kubernetes + Argo CD Deep Dive Runbook

Audience: junior engineers with minimal DevOps background  
Style: practical, command-heavy, and architecture-first

---

## 1) Big picture in one page

You currently have this delivery chain:

1. Developer pushes code to app repo (platform/booking/payment/gateway).
2. GitHub Actions CI builds/tests and pushes Docker image with commit SHA tag.
3. Argo CD Image Updater checks Docker registry tags.
4. Image Updater updates infra repo `kustomization.yaml` with new SHA.
5. Argo CD notices infra repo commit and reconciles cluster.
6. Kubernetes rolls out new pods with new image.

Important split:

- **CI** creates artifact (image).
- **CD** deploys artifact (through infra repo + Argo CD).

---

## 2) Core Kubernetes concepts (no jargon version)

### Cluster

The full Kubernetes system:
- control plane (API server, scheduler, controllers, etcd)
- worker nodes (machines where pods run)

### Namespace

A logical partition inside cluster.  
Your dev environment is `moment-forever-dev`.

### Pod

Smallest running unit (your container + runtime metadata).

### Deployment

A controller that says:
- how many pod copies to run,
- which image/version to use,
- how to update safely.

### Service

Stable internal network endpoint for pods.

### ConfigMap

Non-sensitive key/value config (hosts, ports, feature flags).

### Secret

Sensitive key/value config (passwords, tokens, keys).

---

## 3) Argo CD concepts in plain English

### Argo CD Application

An Argo object that tells Argo:
- repo URL
- branch/tag (`targetRevision`)
- path in repo
- destination cluster/namespace

### Root Application (App-of-Apps)

A parent app that points to folder containing child app YAML files.  
Your root app: `moment-forever-root`.

### Reconciliation

Continuous loop:

- read desired state from Git
- compare with live cluster state
- apply fixes (sync) if drift exists

### Argo CD Image Updater

Side component that:
- watches image tags in registry,
- chooses new allowed tag,
- commits tag update into infra repo,
- lets Argo CD deploy that commit.

---

## 4) How YAML files are read end-to-end

### 4.1 Bootstrap manifests

You run:

```powershell
kubectl apply -f argocd/app-project.yaml
kubectl apply -f argocd/root-application.yaml
```

What happens:

1. `kubectl` reads local file and sends object to Kubernetes API.
2. Argo CD controller sees new Argo `Application`.
3. Argo reads `repoURL + targetRevision + path`.

### 4.2 Root app loading child apps

`root-application.yaml` path points to:

- `argocd/applications`

So Argo loads:
- `platform.yaml`
- `booking.yaml`
- `payment.yaml`
- `gateway.yaml`

### 4.3 Child apps loading deployment manifests

Each child app points to:

- `clusters/dev/<service>`

Argo renders kustomization and applies:
- `configmap.yaml`
- `secret.yaml`
- `deployment.yaml`
- `service.yaml`

### 4.4 Kustomize image replacement

In each `kustomization.yaml`, `images:` block controls image tag.  
Image Updater commits new SHA into `newTag`.

---

## 5) YAML syntax guide (for beginners)

### 5.1 Indentation matters

YAML uses spaces (not tabs).  
Wrong indent = invalid manifest.

Example:

```yaml
spec:
  template:
    spec:
      containers:
        - name: platform
          image: groote123/moment-forever-platform:abc123
```

### 5.2 Lists vs maps

Map (key/value):

```yaml
metadata:
  name: platform
```

List (array):

```yaml
ports:
  - containerPort: 8080
  - containerPort: 8081
```

### 5.3 String vs number vs boolean

```yaml
replicas: 2          # number
enabled: true        # boolean
name: "platform"     # string
```

### 5.4 Multi-document YAML

You can store multiple resources in one file using `---`.

### 5.5 Common mistakes

- Tabs instead of spaces
- Wrong nesting level
- Quoting booleans accidentally
- Using wrong apiVersion/kind pairing

---

## 6) Kubernetes commands you must know

## 6.1 Context and cluster

```powershell
kubectl config get-contexts
kubectl config current-context
kubectl cluster-info
kubectl get nodes -o wide
```

## 6.2 Namespaces and resources

```powershell
kubectl get ns
kubectl get all -n moment-forever-dev
kubectl get deploy,po,svc,cm,secret -n moment-forever-dev
```

## 6.3 Deep inspection

```powershell
kubectl describe deploy platform -n moment-forever-dev
kubectl describe pod <pod-name> -n moment-forever-dev
kubectl logs -n moment-forever-dev deploy/platform --tail=200
kubectl logs -n moment-forever-dev <pod-name> --previous
```

## 6.4 Rollouts

```powershell
kubectl rollout status deploy/platform -n moment-forever-dev
kubectl rollout history deploy/platform -n moment-forever-dev
kubectl rollout undo deploy/platform -n moment-forever-dev
```

## 6.5 Apply and diff

```powershell
kubectl apply -f clusters/dev/platform/deployment.yaml
kubectl diff -f clusters/dev/platform/deployment.yaml
```

In GitOps with Argo CD, prefer commit + sync over direct manual apply.

---

## 7) Argo CD commands you must know

Assuming you logged in:

```powershell
argocd login localhost:8085 --username admin --password <password> --insecure
```

### 7.1 App list and status

```powershell
argocd app list
argocd app get moment-forever-root
argocd app get moment-forever-platform-dev
```

### 7.2 Manual sync/refresh

```powershell
argocd app refresh moment-forever-platform-dev --hard
argocd app sync moment-forever-platform-dev
argocd app wait moment-forever-platform-dev --health --sync
```

### 7.3 App history

```powershell
argocd app history moment-forever-platform-dev
```

---

## 8) Image updater: how to verify it is really working

## 8.1 Check updater pod exists

```powershell
kubectl get pods -n argocd | Select-String image-updater
```

## 8.2 Read logs

```powershell
kubectl logs -n argocd deploy/argocd-image-updater --tail=300
```

Look for:
- app discovered
- registry tags fetched
- candidate tag selected
- kustomization updated
- git commit/push success

## 8.3 Confirm git write-back

Check infra repo commit history:
- new commit touches `clusters/dev/<service>/kustomization.yaml`
- `newTag` changed to latest SHA.

---

## 9) Debugging playbook (quick triage)

Use this exact order when something fails.

### Step A: Is Argo app healthy/synced?

```powershell
kubectl get applications -n argocd
argocd app get moment-forever-platform-dev
```

If OutOfSync:
- inspect `argocd app diff`
- check source path/repo/branch.

### Step B: Did image updater detect new SHA?

```powershell
kubectl logs -n argocd deploy/argocd-image-updater --tail=500
```

If no update attempt:
- check annotations in child app YAML
- check `allow-tags` regex
- check image repository name
- check registry auth/rate limit

### Step C: Did infra repo get commit?

Verify:
- commit exists
- file changed: `clusters/dev/<service>/kustomization.yaml`
- `newTag` equals expected SHA.

If no commit:
- updater missing git credentials
- write-back target misconfigured
- branch protection rejects push

### Step D: Did Argo sync that commit?

```powershell
argocd app history moment-forever-platform-dev
argocd app get moment-forever-platform-dev
```

Check comparedTo revision and sync status.

### Step E: Did Kubernetes rollout new pods?

```powershell
kubectl rollout status deploy/platform -n moment-forever-dev
kubectl get pods -n moment-forever-dev -l app=platform -o wide
kubectl describe deploy platform -n moment-forever-dev
```

Check image in running pod:

```powershell
kubectl get pod -n moment-forever-dev -l app=platform -o jsonpath="{.items[0].spec.containers[0].image}"
```

---

## 10) Debugging scenarios (with symptoms)

## Scenario 1: Image pushed, but no infra commit

Symptoms:
- Docker Hub has new SHA image.
- Infra repo unchanged.

Checks:
1. Updater logs for auth/tag selection errors.
2. Child app annotations:
   - image-list
   - allow-tags regex
   - write-back-method git
   - write-back-target kustomization
3. Git write credentials in updater.

Fix ideas:
- correct annotations
- correct registry image name
- grant repo write permissions/token

## Scenario 2: Infra commit exists, but app not updated

Symptoms:
- `kustomization.yaml` has new tag.
- cluster still running old pods.

Checks:
1. Argo app sync status.
2. Argo app history and operation errors.
3. Kubernetes events on Deployment/ReplicaSet.

Fix ideas:
- manual app sync
- inspect failed resources
- confirm app points to correct path

## Scenario 3: Pod restart loop after new deployment

Symptoms:
- `CrashLoopBackOff`
- rollout stuck

Checks:
```powershell
kubectl describe pod <pod> -n moment-forever-dev
kubectl logs <pod> -n moment-forever-dev --previous
```

Common causes:
- missing env var
- DB not reachable
- bad secret value
- wrong port/path in probe

---

## 11) Verify ConfigMap/Secret loading (critical)

### 11.1 Confirm resources exist

```powershell
kubectl get cm,secret -n moment-forever-dev
```

### 11.2 Confirm deployment references

```powershell
kubectl get deploy platform -n moment-forever-dev -o yaml | Select-String "envFrom|configMapRef|secretRef" -Context 0,3
```

### 11.3 Confirm env inside running pod

```powershell
kubectl exec -n moment-forever-dev deploy/platform -- printenv | Select-String "CONSUL_HOST|POSTGRES_HOST|SPRING_DATASOURCE_USERNAME"
```

If variable missing:
- wrong secret key name
- wrong configmap name
- deployment not rolled after manifest change

### 11.4 Detect secret reference errors quickly

```powershell
kubectl describe pod <pod-name> -n moment-forever-dev
```

Look for:
- `CreateContainerConfigError`
- `secret "<name>" not found`
- `couldn't find key ... in Secret ...`

---

## 12) Your file ownership map (what to edit where)

### App repositories

Edit:
- application code
- tests
- CI workflow

Do not edit for deployment:
- live cluster objects directly (unless emergency)

### Infra repository

Edit:
- `argocd/root-application.yaml`
- `argocd/applications/*.yaml`
- `clusters/dev/*/(configmap|secret|deployment|service|kustomization).yaml`

This repo is deployment source of truth.

---

## 13) Recommended secure progression path

Current (learning):
- Secrets in plain YAML (`stringData`).

Next level:
1. Move secrets to SealedSecrets or SOPS.
2. Or use External Secrets Operator + cloud secret manager.
3. Keep only secret references in Git, not clear-text values.

---

## 14) Minimal daily command set (memorize this)

```powershell
# 1) Is Argo healthy?
kubectl get applications -n argocd

# 2) Did updater run?
kubectl logs -n argocd deploy/argocd-image-updater --tail=200

# 3) Are app pods healthy?
kubectl get pods -n moment-forever-dev

# 4) What image is running?
kubectl get pod -n moment-forever-dev -l app=platform -o jsonpath="{.items[0].spec.containers[0].image}"

# 5) Why is rollout failing?
kubectl describe deploy platform -n moment-forever-dev
kubectl logs -n moment-forever-dev deploy/platform --tail=200
```

If you can run these 5 checks confidently, you can debug most day-1/day-2 issues quickly.

---

## 15) Final mental model (keep this)

When debugging, ask in this order:

1. Was new image built and pushed?
2. Did updater detect it?
3. Did updater commit infra tag change?
4. Did Argo sync that commit?
5. Did Kubernetes rollout new pod?
6. Did pod start with correct config/secret?

This linear chain prevents random guessing and saves hours.

