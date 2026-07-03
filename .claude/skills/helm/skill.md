---
name: helm-masterclass
description: Helm chart authoring, values design, templating patterns, and chart structure for masterclass demos. Use when creating or reviewing Helm charts for educational environments.
metadata:
  type: skill
  topic: helm
---

# Helm skill — masterclass context

## Chart structure for demos

```
charts/<name>/
├── Chart.yaml          # name, version, appVersion, description
├── values.yaml         # defaults + comments explaining each key
├── templates/
│   ├── _helpers.tpl    # common labels, fullname
│   ├── deployment.yaml
│   ├── service.yaml
│   ├── httproute.yaml  # Gateway API (preferred over Ingress in YC demos)
│   └── NOTES.txt       # post-install instructions for students
└── .helmignore
```

## Key patterns

**Labels helper (always use):**
```yaml
# _helpers.tpl
{{- define "app.labels" -}}
app.kubernetes.io/name: {{ .Chart.Name }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Chart.AppVersion }}
{{- end }}
```

**values.yaml structure:**
```yaml
# Образ приложения
image:
  repository: nginx
  tag: "1.27"
  pullPolicy: IfNotPresent

# Масштабирование
replicaCount: 1

# Ресурсы для лабораторного стенда
resources:
  requests:
    cpu: 100m
    memory: 128Mi
  limits:
    cpu: 200m
    memory: 256Mi

# Публикация через Gateway API
httproute:
  enabled: true
  hostname: ""          # заполняется в terraform.tfvars через helm_release
  gatewayName: public
  gatewayNamespace: infra
```

## Umbrella chart (prod pattern from mc-argocd)

```yaml
# Chart.yaml
apiVersion: v2
name: myapp
version: 0.1.0
dependencies:
  - name: nginx
    version: "18.x.x"
    repository: https://charts.bitnami.com/bitnami
```

Run `helm dependency update` before `helm install`.

## Common pitfalls in YC demos

- bitnami charts after Aug 2025: use `docker.io/bitnamilegacy/` images
- HTTPRoute cross-namespace: needs ReferenceGrant or same namespace as Gateway
- helm-secrets with SOPS: `secrets://values-secret.enc.yaml` in ArgoCD valueFiles
