# DevOps terminology glossary (plain English)

This glossary explains common terms used in CI/CD, Kubernetes, and Argo CD.

---

## A

**Application (Argo CD)**  
An Argo object that tells Argo:
- which Git repo to read,
- which folder/path to use,
- where to deploy in Kubernetes.

**App-of-Apps**  
A parent Argo application that points to child application YAML files.  
It is a scalable way to manage many services.

---

## C

**CD (Continuous Delivery/Deployment)**  
The process of taking built artifacts and safely rolling them to environments.

**CI (Continuous Integration)**  
The process of validating code with build/tests and producing artifacts (images/packages).

**Controller**  
A Kubernetes control loop that keeps actual state equal to desired state.

---

## D

**Deployment**  
A Kubernetes resource that manages pods and rolling updates.

**Desired State**  
What your YAML says should exist.

---

## G

**GitOps**  
Operating infrastructure/app deployment through Git commits as source of truth.

---

## H

**Health Check**  
A probe that tells Kubernetes whether app is alive and ready to receive traffic.

---

## I

**Image Tag**  
Label attached to Docker image version (for example `latest` or commit SHA).

**Immutable Tag**  
A tag that should represent one exact build forever (commit SHA is typical).

**Ingress**  
Kubernetes resource that exposes HTTP/HTTPS routes from outside cluster to services.

---

## K

**Kubernetes (K8s)**  
Container orchestration platform for running/scaling/self-healing services.

**Kustomize**  
A Kubernetes-native templating/patching tool using `kustomization.yaml`.

---

## N

**Namespace**  
Logical boundary inside cluster to group resources and isolate environments.

---

## P

**Pod**  
Smallest deployable unit in Kubernetes; contains one or more containers.

**Prune**  
Argo sync option to delete resources removed from Git desired state.

---

## R

**Replica**  
One running copy of a pod. `replicas: 3` means three copies.

**Rollback**  
Moving to an older known-good version/config.

---

## S

**Self-heal**  
Argo feature that corrects live drift by re-applying Git desired state.

**Service (Kubernetes)**  
Stable network endpoint for pods (DNS + virtual IP).

**Sync (Argo CD)**  
Action where Argo applies Git manifests to cluster.

---

## T

**targetRevision**  
Git branch/tag/commit Argo should read (for example `main`).

---

## U

**Upstream / Downstream in pipeline**  
- Upstream: earlier step (CI image build)
- Downstream: later step (CD deploy)
