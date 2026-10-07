# EC2 k3s Bootstrap Guide

This document explains how to use the EC2 bootstrap scripts added under:

```text
bootstrap/ec2-k3s/
```

It is written for the **current Moment Forever dev setup**:

- fresh **Ubuntu 22.04 LTS** EC2 machine
- **single-node k3s**
- **NGINX Ingress Controller**
- **Argo CD**
- **Argo CD Image Updater**
- infra repo used as GitOps source of truth

---

## 1) When do we need to run these scripts?

Run these scripts when:

1. you create a **fresh EC2 machine**
2. you create a **new Kubernetes cluster** on that machine
3. your dev cluster is lost and you want to **rebuild it**
4. you want to recreate the **Argo CD + Image Updater** control plane cleanly

Do **not** run this bootstrap for normal day-to-day deployments.

Normal deployments after setup are already automated by:

1. GitHub Actions CI
2. Docker Hub image push
3. Argo CD Image Updater commit to infra repo
4. Argo CD reconciliation

So this bootstrap is mainly a:

- **first-time setup tool**
- **cluster rebuild tool**
- **disaster recovery tool**

---

## 2) From which path should we run it?

These scripts must be run from the **infra repo checkout on the EC2 machine**.

Recommended path:

```bash
cd <your-cloned-infra-repo>/bootstrap/ec2-k3s
```

Example:

```bash
cd ~/moment-forever-infra/bootstrap/ec2-k3s
```

or if you cloned under `/opt`:

```bash
cd /opt/moment-forever-infra/bootstrap/ec2-k3s
```

Important:

- the scripts assume they are inside the **infra repo**
- they refer to files like:
  - `argocd/root-application.yaml`
  - `argocd/app-project.yaml`
  - `clusters/dev/...`
- so do **not** copy only the script files elsewhere and run them from a random folder

---

## 3) What should be ready before running?

Before running the bootstrap:

### EC2 side

- Ubuntu **22.04 LTS**
- internet access from the VM
- enough disk space
- outbound HTTPS allowed

### AWS security group

Open at least:

- **22** for SSH
- **80** for ingress/app/Argo UI
- **443** for future TLS/HTTPS

Optional:

- **6443** if you want to access the Kubernetes API remotely from your laptop

### Git side

Make sure this infra repo is:

- cloned on the EC2 machine
- updated with latest changes
- already **committed and pushed**

Why?

Because Argo CD reads the **remote Git repo**, not your local uncommitted changes.

The bootstrap checks this and stops if local `HEAD` is not aligned with remote branch.

### Secrets side

You must fill these values in `.env`:

- `GITHUB_USERNAME`
- `GITHUB_TOKEN`
- `DOCKERHUB_USERNAME`
- `DOCKERHUB_TOKEN`

---

## 4) What does the bootstrap install?

The scripts install and configure the following:

1. host prerequisites (`curl`, `git`, `jq`, etc.)
2. **k3s** with **Traefik disabled**
3. **NGINX Ingress Controller**
4. **Argo CD**
5. Argo CD repo credential for the infra repo
6. **Argo CD Image Updater**
7. Docker Hub registry credential for Image Updater
8. the **Moment Forever root Argo application**

After that, Argo CD takes over and starts managing the applications from Git.

---

## 5) What hostnames/URLs does this expect?

Current dev setup uses:

- Elastic IP: `15.134.55.225`
- app host: `api.15.134.55.225.nip.io`
- Argo UI host: `argocd.15.134.55.225.nip.io`

These are based on `nip.io`, so you do not need to buy a domain just for testing.

---

## 6) Which file should we edit first?

Go to:

```bash
cd bootstrap/ec2-k3s
cp env.example .env
vi .env
```

Fill all required values before running anything.

The scripts read:

```text
bootstrap/ec2-k3s/.env
```

If a required value is missing, the script stops early with an error.

---

## 7) How do we run everything?

### Full run

From:

```bash
bootstrap/ec2-k3s/
```

run:

```bash
chmod +x ./*.sh
./bootstrap-all.sh
```

This runs everything in order.

### Step-by-step run

If you prefer more control:

```bash
./00-prepare-host.sh
./10-install-k3s.sh
./20-install-nginx-ingress.sh
./30-install-argocd.sh
./40-configure-argocd-repo-access.sh
./50-install-image-updater.sh
./60-bootstrap-moment-forever.sh
```

This is useful when debugging or rerunning only the failed stage.

---

## 8) What does each script do?

### `00-prepare-host.sh`

Purpose:

- validates Ubuntu 22.04
- installs required base packages
- warns if VM is too small

Use when:

- first time on fresh EC2

### `10-install-k3s.sh`

Purpose:

- installs single-node k3s
- disables Traefik
- prepares kubeconfig for the login user

Use when:

- Kubernetes is not installed yet

### `20-install-nginx-ingress.sh`

Purpose:

- installs NGINX Ingress Controller

Use when:

- k3s is already installed
- your manifests expect `ingressClassName: nginx`

### `30-install-argocd.sh`

Purpose:

- installs Argo CD in namespace `argocd`
- sets `server.insecure=true` for the current no-TLS ingress setup

Use when:

- Argo CD is not installed yet

### `40-configure-argocd-repo-access.sh`

Purpose:

- creates/updates repo credentials so Argo CD can read the infra repo

Use when:

- Git access needs to be configured or rotated

### `50-install-image-updater.sh`

Purpose:

- installs Argo CD Image Updater
- configures Docker Hub auth
- configures registry access

Use when:

- Image Updater is not installed yet
- Docker Hub credentials changed

### `60-bootstrap-moment-forever.sh`

Purpose:

- applies:
  - `argocd/app-project.yaml`
  - `argocd/root-application.yaml`
- waits for child applications to appear

Use when:

- Argo CD is installed and ready
- infra repo contents are already pushed to GitHub

### `bootstrap-all.sh`

Purpose:

- runs all steps in the correct order

Use when:

- starting from scratch

---

## 9) What does success look like?

At the end, you should have:

- k3s running
- nginx ingress running
- Argo CD pods running in `argocd`
- Image Updater pod running in `argocd`
- Argo `Application` resources created
- app ingress and Argo ingress created

Expected URLs:

- app: `http://api.15.134.55.225.nip.io`
- Argo CD: `http://argocd.15.134.55.225.nip.io`
- Kubernetes Dashboard: `http://dashboard.15.134.55.225.nip.io` (login token: `kubectl -n kubernetes-dashboard create token admin-user` — this token has full cluster-admin rights, so treat it like a root password)

Useful checks:

```bash
kubectl get nodes
kubectl get pods -n argocd
kubectl get applications -n argocd
kubectl get pods -n moment-forever-dev
kubectl get pods -n kubernetes-dashboard
kubectl get ingress -A
```

---

## 10) If we get stuck, what should we do first?

Do not rerun everything blindly.

First identify **which stage failed**:

1. host preparation
2. k3s install
3. nginx ingress install
4. Argo CD install
5. repo credential setup
6. Image Updater install
7. Moment Forever bootstrap

Then rerun only that script after fixing the root cause.

---

## 11) Troubleshooting by stage

### Problem: `00-prepare-host.sh` fails

Check:

- are you really on Ubuntu 22.04?
- does the VM have outbound internet?
- can `apt-get update` work?

Useful commands:

```bash
cat /etc/os-release
ping -c 2 google.com
sudo apt-get update
```

### Problem: `10-install-k3s.sh` fails

Check:

- does k3s service start?
- does port 6443 conflict with anything?

Useful commands:

```bash
sudo systemctl status k3s --no-pager
sudo journalctl -u k3s -n 200 --no-pager
kubectl get nodes
```

### Problem: `20-install-nginx-ingress.sh` fails

Check:

- are ingress controller pods starting?
- is there enough CPU/memory?

Useful commands:

```bash
kubectl get pods -n ingress-nginx
kubectl describe deploy ingress-nginx-controller -n ingress-nginx
kubectl logs -n ingress-nginx deploy/ingress-nginx-controller --tail=200
```

### Problem: `30-install-argocd.sh` fails

Check:

- are Argo CD pods healthy?
- did `argocd-server` restart correctly after `server.insecure=true` patch?

Useful commands:

```bash
kubectl get pods -n argocd
kubectl describe deploy argocd-server -n argocd
kubectl logs -n argocd deploy/argocd-server --tail=200
kubectl get configmap argocd-cmd-params-cm -n argocd -o yaml
```

### Problem: `40-configure-argocd-repo-access.sh` fails

Check:

- is `GITHUB_USERNAME` correct?
- is `GITHUB_TOKEN` valid?
- does token have repo access?

Useful commands:

```bash
kubectl get secret moment-forever-infra-repo -n argocd -o yaml
```

### Problem: `50-install-image-updater.sh` fails

Check:

- does the deployment exist?
- are Docker Hub credentials valid?

Useful commands:

```bash
kubectl get pods -n argocd | grep image-updater
kubectl logs -n argocd deploy/argocd-image-updater --tail=300
kubectl get configmap argocd-image-updater-config -n argocd -o yaml
kubectl get secret dockerhub-secret -n argocd -o yaml
```

### Problem: `60-bootstrap-moment-forever.sh` fails

Check:

- did you push latest infra changes to GitHub?
- do all app manifests point to the correct repo URL and branch?
- can Argo CD read the repo?

Useful commands:

```bash
git status
git fetch origin
git rev-parse HEAD
git rev-parse origin/main
kubectl get applications -n argocd
kubectl describe application moment-forever-root -n argocd
kubectl logs -n argocd deploy/argocd-repo-server --tail=200
```

---

## 12) Common mistakes to avoid

1. **Running from the wrong folder**
   - always run from `bootstrap/ec2-k3s`

2. **Forgetting to fill `.env`**
   - script will fail on missing secrets

3. **Not pushing infra repo before bootstrap**
   - Argo reads remote Git, not your unpushed local files

4. **Wrong GitHub PAT permissions**
   - Argo read or Image Updater write-back will fail

5. **Security group does not allow port 80**
   - ingress hosts will not open

6. **Tiny EC2 instance**
   - bootstrap may install successfully, but workloads may remain unstable

---

## 13) If app or Argo URL does not open

Check:

```bash
kubectl get ingress -A
kubectl describe ingress moment-forever -n moment-forever-dev
kubectl describe ingress argocd-server -n argocd
kubectl get svc -n ingress-nginx
kubectl get pods -n ingress-nginx
```

Also check:

- EC2 public IP is still `15.134.55.225`
- security group allows inbound 80
- nginx ingress controller is running

---

## 14) When should we rerun the bootstrap?

Rerun **full bootstrap** only when:

- cluster is rebuilt
- EC2 is recreated
- you intentionally want a clean cluster reinstall

Rerun **single scripts** when:

- credentials rotated
- Image Updater config changed
- Argo CD was removed
- ingress controller was removed

Examples:

- changed GitHub token → rerun `40-configure-argocd-repo-access.sh`
- changed Docker Hub token → rerun `50-install-image-updater.sh`
- changed infra repo app structure → rerun `60-bootstrap-moment-forever.sh`

---

## 15) Best recovery path if something fails mid-way

Recommended recovery approach:

1. read the error carefully
2. identify the stage
3. fix the missing prerequisite
4. rerun that stage
5. continue with the next stage

Avoid:

- deleting random resources without knowing why
- changing manifests directly in-cluster without updating Git
- rerunning every script repeatedly without checking logs

---

## 16) Final quick-start checklist

```bash
cd <infra-repo>/bootstrap/ec2-k3s
cp env.example .env
vi .env
chmod +x ./*.sh
./bootstrap-all.sh
```

Then verify:

```bash
kubectl get pods -n argocd
kubectl get applications -n argocd
kubectl get pods -n moment-forever-dev
kubectl get ingress -A
```

Expected browser URLs:

- `http://api.15.134.55.225.nip.io`
- `http://argocd.15.134.55.225.nip.io`
