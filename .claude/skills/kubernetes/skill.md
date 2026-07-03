---
name: kubernetes-masterclass
description: Kubernetes manifests, debugging, RBAC, Gateway API, and K8s patterns for masterclass demos on Yandex Managed Kubernetes.
metadata:
  type: skill
  topic: kubernetes
---

# Kubernetes skill — masterclass context

## Cluster: Yandex Managed Kubernetes

```bash
# Получить kubeconfig
yc managed-kubernetes cluster get-credentials <cluster-name> --external --force
kubectl config current-context
kubectl get nodes
```

## Standard manifest patterns

**Deployment with proper labels and probes:**
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: myapp
  labels:
    app.kubernetes.io/name: myapp
spec:
  replicas: 1
  selector:
    matchLabels:
      app.kubernetes.io/name: myapp
  template:
    metadata:
      labels:
        app.kubernetes.io/name: myapp
    spec:
      containers:
        - name: myapp
          image: nginx:1.27
          ports:
            - containerPort: 80
          resources:
            requests: { cpu: 100m, memory: 128Mi }
            limits:   { cpu: 200m, memory: 256Mi }
          readinessProbe:
            httpGet: { path: /, port: 80 }
            initialDelaySeconds: 5
          livenessProbe:
            httpGet: { path: /, port: 80 }
            initialDelaySeconds: 15
```

**Gateway API HTTPRoute (preferred over Ingress):**
```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: myapp
  namespace: demo
spec:
  parentRefs:
    - name: public
      namespace: infra
  hostnames:
    - myapp.example.com
  rules:
    - matches:
        - path: { type: PathPrefix, value: / }
      backendRefs:
        - name: myapp
          port: 80
          weight: 1   # явно — избегает diff в ArgoCD
```

## Debugging commands for demos

```bash
# Быстрая диагностика
kubectl get events -n <ns> --sort-by='.lastTimestamp' | tail -20
kubectl describe pod <pod> -n <ns>
kubectl logs <pod> -n <ns> --previous   # если pod рестартовал
kubectl exec -it <pod> -n <ns> -- sh

# Проверить RBAC
kubectl auth can-i create pods --as=system:serviceaccount:<ns>:<sa>

# Gateway API
kubectl get httproute,gateway -A
kubectl describe httproute <name> -n <ns>  # проверить status.parents
```

## Namespaces for masterclass

Standard layout:
- `infra` — platform components (Gateway, cert-manager, operators)
- `argocd` — ArgoCD itself
- `demo-dev` / `demo-prod` — student workloads
- `monitoring` — Prometheus/Grafana (if topic includes observability)

## Resource quotas for multi-student envs

```yaml
apiVersion: v1
kind: ResourceQuota
metadata:
  name: student-quota
  namespace: student-ns
spec:
  hard:
    pods: "10"
    requests.cpu: "2"
    requests.memory: 4Gi
    limits.cpu: "4"
    limits.memory: 8Gi
```
