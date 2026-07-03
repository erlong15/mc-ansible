---
name: go-masterclass
description: Go patterns for Kubernetes operators, CLI tools, and demo applications in masterclass contexts. Covers operator-sdk, controller-runtime, and Go best practices.
metadata:
  type: skill
  topic: go
---

# Go skill — masterclass context

## Typical Go use cases in masterclasses

1. **K8s operators** — custom controllers with controller-runtime
2. **CLI demo tools** — simple tools demonstrating API interaction
3. **Demo microservices** — HTTP servers for showing K8s features

## Minimal HTTP server for K8s demos

```go
package main

import (
    "fmt"
    "log"
    "net/http"
    "os"
)

func main() {
    port := os.Getenv("PORT")
    if port == "" {
        port = "8080"
    }

    http.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
        hostname, _ := os.Hostname()
        fmt.Fprintf(w, "Hello from %s\n", hostname)
    })

    http.HandleFunc("/health", func(w http.ResponseWriter, r *http.Request) {
        w.WriteHeader(http.StatusOK)
    })

    log.Printf("Listening on :%s", port)
    log.Fatal(http.ListenAndServe(":"+port, nil))
}
```

## Dockerfile (multi-stage, distroless)

```dockerfile
FROM golang:1.23-alpine AS builder
WORKDIR /app
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 go build -o /app/server .

FROM gcr.io/distroless/static:nonroot
COPY --from=builder /app/server /server
EXPOSE 8080
USER nonroot:nonroot
ENTRYPOINT ["/server"]
```

## Kubernetes operator (controller-runtime)

```go
// Reconciler для демо custom resource
func (r *DemoReconciler) Reconcile(ctx context.Context, req ctrl.Request) (ctrl.Result, error) {
    log := log.FromContext(ctx)

    demo := &demov1.Demo{}
    if err := r.Get(ctx, req.NamespacedName, demo); err != nil {
        return ctrl.Result{}, client.IgnoreNotFound(err)
    }

    // Создать или обновить Deployment
    deploy := r.deploymentForDemo(demo)
    if err := ctrl.SetControllerReference(demo, deploy, r.Scheme); err != nil {
        return ctrl.Result{}, err
    }

    found := &appsv1.Deployment{}
    err := r.Get(ctx, types.NamespacedName{Name: deploy.Name, Namespace: deploy.Namespace}, found)
    if errors.IsNotFound(err) {
        log.Info("Creating Deployment", "name", deploy.Name)
        return ctrl.Result{}, r.Create(ctx, deploy)
    }

    return ctrl.Result{}, nil
}
```

## Common commands for demo

```bash
# Сборка и запуск локально
go build ./... && ./server

# Тесты
go test ./... -v

# Линтер
golangci-lint run

# Сборка образа и пуш в YC Container Registry
docker build -t cr.yandex/<registry-id>/demo:latest .
docker push cr.yandex/<registry-id>/demo:latest

# Operator SDK scaffold
operator-sdk init --domain example.com --repo github.com/org/demo-operator
operator-sdk create api --group demo --version v1 --kind Demo --resource --controller
```

## Go modules for K8s operators

```
go.mod dependencies:
  sigs.k8s.io/controller-runtime v0.18.x
  k8s.io/apimachinery v0.31.x
  k8s.io/client-go v0.31.x
```
