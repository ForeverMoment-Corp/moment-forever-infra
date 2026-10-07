# Moment Forever Infra (CD / GitOps Repo)

This folder is a **CD (Continuous Delivery) GitOps repository structure** for:

- platform
- booking
- payment
- gateway

It is intentionally separate from application code repositories.

---

## Why this repo exists

- App repos do **CI** (build, test, docker push).
- This infra repo does **CD intent** (Kubernetes desired state).
- Argo CD watches this repo and applies changes to cluster.
- Argo CD Image Updater can update image tags automatically to new commit SHA tags.

---

## Folder structure

```text
moment-forever-infra/
  argocd/
    app-project.yaml
    root-application.yaml
    applications/
      platform.yaml
      booking.yaml
      payment.yaml
      gateway.yaml
  clusters/
    dev/
      namespace.yaml
      argocd/
        kustomization.yaml
        ingress.yaml
      platform/
        kustomization.yaml
        deployment.yaml
        service.yaml
      booking/
        kustomization.yaml
        deployment.yaml
        service.yaml
      payment/
        kustomization.yaml
        deployment.yaml
        service.yaml
      gateway/
        kustomization.yaml
        deployment.yaml
        service.yaml
```

---

## Bootstrap steps (first-time setup)

1. Create a GitHub repository named `moment-forever-infra`.
2. Copy these files into that repository.
3. Update these placeholders:
   - `https://github.com/groote123/moment-forever-infra.git` (if repo URL differs)
   - `targetRevision: main` (if branch differs)
   - `server: https://kubernetes.default.svc` (if using external cluster registration model)
4. Apply Argo bootstrap manifests (from your Argo CD control plane context):
   - `argocd/app-project.yaml`
   - `argocd/root-application.yaml`
5. Root app creates child apps (platform/booking/payment/gateway).
6. Child apps deploy workloads in `moment-forever-dev` namespace.

---

## How image updates happen (recommended)

This repo is prepared for **Argo CD Image Updater**:

- Each Argo Application has image updater annotations.
- Each service `kustomization.yaml` declares image name + tag.
- Image updater can write new SHA tag into git.
- Argo CD syncs updated manifests automatically.

This is the clean CI->CD handoff:

- CI pushes image `groote123/<service>:<commit-sha>`.
- Image updater updates this repo with that new SHA.
- Argo CD applies the change to cluster.

---

## Current dev ingress hosts

For the current single-EC2 dev setup that uses Elastic IP `15.134.55.225`, the repo now exposes:

- app gateway: `http://api.15.134.55.225.nip.io`
- Argo CD UI: `http://argocd.15.134.55.225.nip.io`
- Kubernetes Dashboard: `http://dashboard.15.134.55.225.nip.io`

These use `nip.io` so you can test host-based ingress without buying a domain.

> **Dashboard access is full cluster-admin by explicit choice.** The `admin-user`
> ServiceAccount in `clusters/dev/dashboard/admin-user.yaml` is bound to the
> built-in `cluster-admin` ClusterRole, and the Dashboard is reachable from the
> public internet over plain HTTP. Anyone with the bearer token has complete
> control of the cluster. Get a login token with:
> `kubectl -n kubernetes-dashboard create token admin-user`
> Treat that token like a root password; do not commit it or share it outside the team.

---

## Important notes

- No deployment commands are kept in application CI workflows.
- No `kubectl` from app repos.
- CD state changes happen in this infra repo only.
- Comments in every YAML are intentionally verbose for learning.

---

## Extra beginner docs

- `doc/FILE-BY-FILE-EXPLANATION.md`
- `doc/ARGOCD-KUBERNETES-BASICS.md`
- `doc/LOCAL-CD-SETUP-GUIDE.md`
- `doc/CD-OPERATIONS-RUNBOOK.md` (current real setup, credentials, and troubleshooting)
- `doc/EC2-K3S-BOOTSTRAP-GUIDE.md` (when to run bootstrap, from where, what each script does, and recovery steps)
- `doc/DEVOPS-TERMINOLOGY-GLOSSARY.md`
- `doc/KUBERNETES-ARGOCD-DEEP-DIVE-RUNBOOK.md` (in-depth commands + debugging)
