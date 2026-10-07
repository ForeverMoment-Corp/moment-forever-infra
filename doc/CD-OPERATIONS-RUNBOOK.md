# CD Operations Runbook

This runbook documents the **current real CD setup** for Moment Forever, not just the ideal GitOps model.

Use this file when you want to answer:

- what is manual vs automated today,
- which credentials are needed and why,
- how Argo CD Image Updater really fits in the chain,
- what to check when a new image exists but the deployment did not happen.

---

## 1) Current deployment model at a glance

### What is manual today

These parts are installed/configured manually on the EC2/Kubernetes side:

1. Kubernetes cluster itself
2. Argo CD
3. Argo CD Image Updater
4. Argo CD repo access configuration
5. Image Updater credentials/secrets
6. Ingress controller (required for Ingress resources to work)

### What is automated today

After the above is in place, the application delivery chain is automated:

1. Developer pushes code to app repo
2. GitHub Actions CI builds/tests image
3. CI pushes immutable SHA tag to Docker Hub
4. Argo CD Image Updater checks Docker Hub
5. Image Updater commits updated `newTag` to this infra repo
6. Argo CD detects the infra repo commit
7. Argo CD reconciles Kubernetes
8. Kubernetes rolls out new pods

So the current model is:

- **manual control-plane setup**
- **automated day-to-day application delivery**

---

## 2) Current dev access points

For the single-EC2 dev setup using Elastic IP `15.134.55.225`:

- App entry: `http://api.15.134.55.225.nip.io`
- Argo CD UI: `http://argocd.15.134.55.225.nip.io`
- Kubernetes Dashboard: `http://dashboard.15.134.55.225.nip.io` — login needs a bearer token: `kubectl -n kubernetes-dashboard create token admin-user`. That ServiceAccount is bound to `cluster-admin`, so the token grants full cluster control; it is reachable from the public internet over plain HTTP, so rotate/avoid sharing it like a root credential.

These hosts depend on:

- nginx ingress controller being installed and healthy
- EC2 security group allowing inbound HTTP
- the ingress controller service being reachable from the Elastic IP

---

## 3) Ownership boundary: who does what

| Layer | Owned by | Responsibility |
|---|---|---|
| App repos (`platform`, `booking`, `payment`, `gateway`) | CI | build, test, Docker image publish |
| Infra repo (`moment-forever-infra`) | CD | desired Kubernetes state |
| Argo CD | Sync engine | apply Git state to cluster |
| Argo CD Image Updater | CD helper | detect new image tag and commit tag change to infra repo |
| Kubernetes | Runtime | run pods, services, ingress, rollouts |

Important rule:

- **CI never deploys directly**
- **CD never builds images**

---

## 4) Required credentials and why they exist

There are three separate credential needs in the CD chain.

### A. Argo CD repo read access

Purpose:

- lets Argo CD read the infra repo

Needed when:

- infra repo is private

Typical location:

- Secret/config inside `argocd` namespace

What breaks if this is missing:

- Argo app shows repo access/authentication errors
- sync never starts

### B. Image Updater Git write-back access

Purpose:

- lets Image Updater commit new `kustomization.yaml` tags back to this infra repo

Needed because:

- updater does not deploy directly,
- it changes Git and lets Argo deploy that Git commit

Typical location:

- Secret in `argocd` namespace used by `argocd-image-updater`

What breaks if this is missing:

- updater sees the new image
- but no infra repo commit is created

### C. Docker Hub registry access

Purpose:

- lets Image Updater inspect image tags reliably

May be needed when:

- Docker Hub rate-limits anonymous reads
- registry is private

Typical location:

- registry credential secret/config for Image Updater

What breaks if this is missing:

- updater logs show registry auth or tag fetch issues
- no candidate image tag is selected

---

## 5) Current GitOps chain in exact order

This is the exact sequence to debug, always in this order:

1. **GitHub Actions succeeded**
2. **Docker Hub has the new SHA image**
3. **Image Updater detected that SHA**
4. **Image Updater committed new `newTag` into infra repo**
5. **Argo CD detected the infra repo commit**
6. **Argo CD synced successfully**
7. **Kubernetes rolled out pods using the new image**
8. **Pods became healthy**

If you debug out of order, you waste time.

---

## 6) Manual setup inventory checklist

This checklist documents what must already exist outside Git for the current setup to work.

### Cluster / control plane

- Kubernetes cluster installed
- `argocd` namespace exists
- Argo CD installed
- Argo CD Image Updater installed
- ingress controller installed

### Argo / CD configuration

- infra repo registered or reachable by Argo CD
- Image Updater running in `argocd` namespace
- Image Updater Git write credentials configured
- Image Updater registry access configured if needed

### Infra manifests

- root app applied
- child apps created successfully
- shared infra, ingress, and service apps synced

---

## 7) Fast verification commands

### 7.1 Argo control plane health

```powershell
kubectl get pods -n argocd
kubectl get applications -n argocd
kubectl get ingress -n argocd
```

### 7.2 Dev workload health

```powershell
kubectl get pods -n moment-forever-dev
kubectl get deploy,svc,ingress -n moment-forever-dev
```

### 7.3 Image Updater health

```powershell
kubectl logs -n argocd deploy/argocd-image-updater --tail=300
```

### 7.4 Argo application status

```powershell
argocd app list
argocd app get moment-forever-platform-dev
argocd app get moment-forever-booking-dev
argocd app get moment-forever-payment-dev
argocd app get moment-forever-gateway-dev
```

---

## 8) Troubleshooting: new image exists but deployment did not happen

This is the most important operational checklist in the current system.

## Step 1: Did GitHub Actions publish the SHA image?

Check the app repo workflow first.

Expected:

- build/test passed
- Docker push succeeded
- image exists as `groote123/<service>:<commit-sha>`

If this failed:

- this is **not** an Argo problem yet

## Step 2: Did Docker Hub actually get the tag?

Confirm the exact SHA tag exists in Docker Hub.

If missing:

- CI push step failed
- wrong Docker Hub repo name may be used

## Step 3: Did Image Updater notice the new tag?

```powershell
kubectl logs -n argocd deploy/argocd-image-updater --tail=500
```

Look for:

- app discovered
- registry tags fetched
- allowed tag matched regex
- candidate tag selected

If not:

- child app annotations may be wrong
- image repo name may be wrong
- `allow-tags` regex may not match
- Docker Hub auth/rate-limit issue may exist

## Step 4: Did Image Updater create an infra repo commit?

Check infra repo history and changed files.

Expected:

- new commit exists
- `clusters/dev/<service>/kustomization.yaml` changed
- `newTag` equals the new commit SHA

If not:

- Git write-back credentials are wrong/missing
- write-back target is wrong
- branch protection blocked the push

## Step 5: Did Argo CD see that infra repo commit?

```powershell
argocd app history moment-forever-platform-dev
argocd app get moment-forever-platform-dev
```

Look for:

- latest revision matches the new infra repo commit
- app is `Synced` or at least `OutOfSync` with known revision

If not:

- app may point to wrong repo/path/branch
- Argo repo polling/webhook may be delayed
- repo read credentials may be broken

## Step 6: Did Kubernetes roll out the new image?

```powershell
kubectl rollout status deploy/platform -n moment-forever-dev
kubectl get pods -n moment-forever-dev -l app=platform -o wide
kubectl get pod -n moment-forever-dev -l app=platform -o jsonpath="{.items[0].spec.containers[0].image}"
```

If the old image is still running:

- Argo may not have synced successfully
- rollout may be paused or failing

## Step 7: Did pods fail after rollout?

```powershell
kubectl describe deploy platform -n moment-forever-dev
kubectl logs -n moment-forever-dev deploy/platform --tail=200
kubectl logs -n moment-forever-dev <pod-name> --previous
```

Common causes:

- missing env var
- bad secret/config value
- probe failure
- service dependency unavailable

---

## 9) “Which secret/config is likely broken?” map

| Symptom | Likely problem |
|---|---|
| Argo app cannot sync repo | Argo repo read credential |
| Image Updater sees app but cannot commit | Git write-back credential |
| Image Updater cannot inspect tags | Docker Hub credential / rate limit |
| Pod starts with wrong DB/JWT/env config | app ConfigMap/Secret in `moment-forever-dev` |

---

## 10) Commands for the most common failure points

### A. Check child app annotations quickly

```powershell
kubectl get application moment-forever-platform-dev -n argocd -o yaml
```

Verify these annotations exist and are correct:

- `argocd-image-updater.argoproj.io/image-list`
- `argocd-image-updater.argoproj.io/<alias>.allow-tags`
- `argocd-image-updater.argoproj.io/<alias>.update-strategy`
- `argocd-image-updater.argoproj.io/write-back-method`
- `argocd-image-updater.argoproj.io/write-back-target`

### B. Check running image in pod

```powershell
kubectl get pod -n moment-forever-dev -l app=platform -o jsonpath="{.items[0].spec.containers[0].image}"
```

### C. Check kustomize tag in Git-synced manifest

```powershell
kubectl get application moment-forever-platform-dev -n argocd -o yaml | Select-String "targetRevision|path"
```

Then verify the matching file in Git:

- `clusters/dev/platform/kustomization.yaml`

### D. Check ingress reachability

```powershell
kubectl get ingress -A
kubectl describe ingress moment-forever -n moment-forever-dev
kubectl describe ingress argocd-server -n argocd
```

---

## 11) Rebuild/recovery notes for the current model

Today, the **application delivery path is automated**, but the **CD control plane install is still manual**.

So if the EC2 or cluster is rebuilt, the expected recovery order is:

1. install Kubernetes
2. install ingress controller
3. install Argo CD
4. install Argo CD Image Updater
5. restore Argo repo access
6. restore Image Updater credentials
7. apply:

```powershell
kubectl apply -f argocd/app-project.yaml
kubectl apply -f argocd/root-application.yaml
```

After that, Argo should recreate the managed applications from Git.

---

## 12) What this runbook does **not** automate yet

This runbook documents the current system, but does not yet convert it into full bootstrap-as-code for:

- Argo CD installation
- Image Updater installation
- repo/registry credentials
- ingress controller installation

That is a later hardening phase.
