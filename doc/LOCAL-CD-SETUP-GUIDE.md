# Local CD setup guide (Kubernetes + Argo CD)

This guide helps you run CD locally for learning.

You can use either:

1. **Docker Desktop Kubernetes** (easiest on Windows), or
2. **kind** cluster.

---

## 0) Prerequisites

Install these tools:

- Docker Desktop
- kubectl
- argocd CLI
- (optional) kind

Verify:

```powershell
kubectl version --client
argocd version --client
docker version
```

---

## 1) Create local Kubernetes cluster

## Option A: Docker Desktop Kubernetes

1. Open Docker Desktop.
2. Settings -> Kubernetes -> Enable Kubernetes.
3. Wait until Kubernetes status is healthy.

## Option B: kind

```powershell
kind create cluster --name moment-forever-dev
kubectl cluster-info --context kind-moment-forever-dev
```

---

## 2) Install Argo CD in cluster

```powershell
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
kubectl -n argocd rollout status deploy/argocd-server
```

---

## 3) Access Argo CD UI

Port-forward Argo server:

```powershell
kubectl port-forward svc/argocd-server -n argocd 8085:443
```

Open:

- https://localhost:8085

Get initial admin password:

```powershell
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | %{ [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($_)) }
```

Login username:

- `admin`

---

## 4) Register infra repo in Argo CD

Argo must have access to your infra repository.

If repo is public, Argo can usually read directly.

If private, add repo credentials in Argo CD:

```powershell
argocd repo add https://github.com/groote123/moment-forever-infra.git --username <github-username> --password <github-token-or-password>
```

> Better practice: use PAT/token, not password.

---

## 5) Bootstrap this infra repo into Argo

Apply two files:

```powershell
kubectl apply -f argocd/app-project.yaml
kubectl apply -f argocd/root-application.yaml
```

What happens next:

1. Root app appears.
2. Root app creates child apps.
3. Child apps deploy platform/booking/payment/gateway into `moment-forever-dev`.

---

## 6) Install Argo CD Image Updater (optional but recommended)

Image Updater automates SHA tag updates into this infra repo.

Typical install:

```powershell
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj-labs/argocd-image-updater/stable/manifests/install.yaml
```

You also need to configure:

- registry credentials for Docker Hub,
- git write credentials for infra repo commits.

Because setup differs by security model, keep these as placeholders in local setup:

- Docker registry credential secret for updater
- Git credential secret for updater write-back

---

## 7) Local verification checklist

1. Argo UI opens and root app is healthy.
2. Child apps exist (platform/booking/payment/gateway).
3. Namespace `moment-forever-dev` exists.
4. Deployments and services are created.
5. Edit one image tag in `clusters/dev/platform/kustomization.yaml`, commit, push.
6. Argo syncs and rollout updates platform pods.

---

## 8) Common beginner issues

1. **App shows OutOfSync forever**
   - Check repo URL, branch, and path in Application manifests.
2. **Permission denied reading private repo**
   - Add repo credentials in Argo CD.
3. **Image updater not updating**
   - Check image updater logs and ensure annotations + credentials are correct.
4. **Pods crash after deploy**
   - Validate service env variables/secrets and correct app ports.

---

## 9) What to do after local success

1. Create separate `stage` and `prod` folders under `clusters/`.
2. Use separate namespaces and Argo apps per environment.
3. Add stronger policies/resources/secrets management.
4. Add ingress and TLS for gateway in non-local environments.

---

## 10) Deeper setup: connect Argo CD Image Updater properly

For local learning, you can run without Image Updater first.

When ready, configure these three integrations:

## A. Docker registry credentials

Image Updater must authenticate to Docker Hub if required/rate-limited.

Typical approach:

- create secret in `argocd` namespace
- reference secret in Image Updater config

## B. Git write credentials

If updater writes back to Git, it needs commit permission to infra repo.

Typical approach:

- create PAT with repo write scope
- store as Kubernetes secret in `argocd` namespace
- configure updater to use it

## C. Commit identity

Set bot username/email for update commits so history is clear.

---

## 11) Suggested local learning sequence (very practical)

1. Bootstrap Argo CD with root app.
2. Confirm all 4 apps sync successfully.
3. Manually change one image tag in `kustomization.yaml`.
4. Watch rollout in Argo UI.
5. Install Image Updater.
6. Push a new app commit so CI publishes a new SHA image.
7. Confirm updater commits new SHA to infra repo.
8. Confirm Argo deploys that updated SHA.

If you can complete these 8 steps, your CI->CD chain is working end-to-end.

---

## 12) Recommended command checklist during troubleshooting

```powershell
kubectl get ns
kubectl get applications -n argocd
kubectl get pods -n argocd
kubectl get pods -n moment-forever-dev
kubectl describe application moment-forever-platform-dev -n argocd
kubectl logs -n argocd deploy/argocd-application-controller --tail=200
kubectl logs -n argocd deploy/argocd-image-updater --tail=200
```

Use these before guessing.

