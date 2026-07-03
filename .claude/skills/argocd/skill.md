---
name: argocd-masterclass
description: ArgoCD GitOps patterns, ApplicationSets, AppProjects, sync waves, and SOPS for masterclass demos. Covers the full self-bootstrap pattern used in mc-argocd.
metadata:
  type: skill
  topic: argocd
---

# ArgoCD skill — masterclass context

## Installation (via Terraform + helm_release)

```hcl
# ArgoCD ставится через Terraform — студенты видят Infrastructure as Code
resource "helm_release" "argocd" {
  name             = "argocd"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  version          = "7.x.x"
  namespace        = "argocd"
  create_namespace = true

  values = [file("${path.module}/argocd-values.yaml")]
}
```

## Three-tier bootstrap pattern

```
Terraform
  └─► helm_release argocd            # ArgoCD itself
  └─► helm_release argocd-bootstrap  # bootstrap chart
        └─► AppProject infra
        └─► ApplicationSet infra → repo/infra/*
              └─► cert-manager
              └─► envoy-gateway
              └─► AppProject demo-dev + ApplicationSet apps-dev
              └─► AppProject demo-prod + ApplicationSet apps-prod
```

## ApplicationSet templates

**Directory generator (prod pattern — each dir is a chart):**
```yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: apps-prod
  namespace: argocd
spec:
  generators:
    - git:
        repoURL: https://github.com/org/repo.git
        revision: main
        directories:
          - path: apps/prod/*
  template:
    metadata:
      name: '{{path.basename}}-prod'
    spec:
      project: demo-prod
      source:
        repoURL: https://github.com/org/repo.git
        targetRevision: main
        path: '{{path}}'
      destination:
        server: https://kubernetes.default.svc
        namespace: demo-prod
      syncPolicy:
        automated:
          prune: true
          selfHeal: true
        syncOptions:
          - CreateNamespace=true
```

**Files generator (dev pattern — shared chart + per-app config.json):**
```yaml
generators:
  - git:
      repoURL: https://github.com/org/repo.git
      revision: main
      files:
        - path: apps/dev/*/config.json
template:
  metadata:
    name: '{{path.basename}}-dev'
  spec:
    source:
      path: charts/nginx-demo
      helm:
        valuesObject:
          replicaCount: '{{replicaCount}}'
```

## AppProject (security boundary)

```yaml
apiVersion: argoproj.io/v1alpha1
kind: AppProject
metadata:
  name: demo-dev
  namespace: argocd
  annotations:
    argocd.argoproj.io/sync-wave: "-1"   # создаётся раньше ApplicationSet
spec:
  sourceRepos:
    - https://github.com/org/repo.git
  destinations:
    - server: https://kubernetes.default.svc
      namespace: demo-dev
  namespaceResourceWhitelist:
    - group: "*"
      kind: "*"
```

## SOPS / helm-secrets

ArgoCD repo-server init-container installs `helm-secrets` plugin:
```yaml
# argocd-values.yaml
repoServer:
  initContainers:
    - name: install-helm-secrets
      image: alpine/helm:3.x
      command: [sh, -c, "helm plugin install https://github.com/jkroepke/helm-secrets"]
      volumeMounts:
        - name: helm-plugins
          mountPath: /helm-plugins
```

Encrypted values in Application:
```yaml
helm:
  valueFiles:
    - values.yaml
    - secrets://values-secret.enc.yaml
```

## Key debugging commands

```bash
argocd app list
argocd app get <name>
argocd app sync <name> --prune
kubectl -n argocd get applicationset,app,appproject
kubectl -n argocd logs deploy/argocd-applicationset-controller | tail -50
```
