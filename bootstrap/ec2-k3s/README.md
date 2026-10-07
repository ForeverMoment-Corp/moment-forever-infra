# EC2 bootstrap for Moment Forever dev cluster

This folder contains the **actual EC2 bootstrap scripts** for the current recommended setup:

- **OS:** Ubuntu 22.04 LTS or 24.04 LTS
- **Kubernetes:** single-node **k3s**
- **Ingress:** NGINX Ingress Controller
- **GitOps:** Argo CD + Argo CD Image Updater
- **Hosts:** `nip.io` hostnames based on the EC2 public IP

---

## What this bootstrap installs

1. host prerequisites
2. k3s with Traefik disabled
3. NGINX Ingress Controller
4. Argo CD
5. Argo CD repository access for the infra repo
6. Argo CD Image Updater
7. Docker Hub registry credentials for Image Updater
8. the Moment Forever root Argo application

After that, Argo CD manages the rest from Git.

---

## Before you run it

### 1. Clone this infra repo on the EC2 machine

The scripts expect to run from this repository checkout.

### 2. Make sure your infra changes are already pushed

Argo CD reads the **remote** Git repository, not your unpushed local changes.

The bootstrap script checks that local `HEAD` matches `origin/main` (or your configured branch) and will stop if it does not.

### 3. Fill the environment file

```bash
cd bootstrap/ec2-k3s
cp env.example .env
vi .env
```

Required secrets:

- `GITHUB_USERNAME`
- `GITHUB_TOKEN`
- `DOCKERHUB_USERNAME`
- `DOCKERHUB_TOKEN`

### 4. Open the EC2 security group

At minimum:

- TCP 22 for SSH
- TCP 80 for app ingress and Argo UI
- TCP 443 for future TLS or HTTPS ingress

If you want remote `kubectl` to talk to the k3s API later, also open:

- TCP 6443 (restricted to your IP, not the world)

---

## Run everything

From the repo root:

```bash
cd bootstrap/ec2-k3s
chmod +x ./*.sh
./bootstrap-all.sh
```

Or run step by step:

```bash
./00-prepare-host.sh
./10-install-k3s.sh
./20-install-nginx-ingress.sh
./30-install-argocd.sh
./40-configure-argocd-repo-access.sh
./50-install-image-updater.sh
./60-bootstrap-moment-forever.sh
```

For a more detailed operator guide, read:

- `doc/EC2-K3S-BOOTSTRAP-GUIDE.md`

---

## What URLs you should get

With the current Elastic IP `15.134.55.225`:

- app: `http://api.15.134.55.225.nip.io`
- Argo CD: `http://argocd.15.134.55.225.nip.io`
- Kubernetes Dashboard: `http://dashboard.15.134.55.225.nip.io` (get a login token with `kubectl -n kubernetes-dashboard create token admin-user`; that token is cluster-admin, treat it like a root password)

---

## Notes about small EC2 instances

These scripts are designed to **install successfully** on a small EC2 machine, but all workloads may not stay healthy together on a free-tier sized instance because your stack includes:

- 4 Java microservices
- 3 Postgres databases
- Kafka
- Redis
- MongoDB
- Consul
- Argo CD
- Image Updater

So the bootstrap should complete, but workload health on a tiny instance is still limited by RAM/CPU.
