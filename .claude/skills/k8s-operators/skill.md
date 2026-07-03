---
name: k8s-operators-masterclass
description: Kubernetes operators patterns — CRD design, controller-runtime reconcilers, operator-sdk scaffolding, and educational demo operators.
metadata:
  type: skill
  topic: k8s-operators
---

# K8s Operators skill — masterclass context

## What to teach

1. **Problem**: managing stateful apps (databases, message queues) with kubectl is manual and error-prone.
2. **Solution**: Operator = CRD (custom resource) + Controller (reconciliation loop).
3. **Demo flow**: scaffold → define CRD → implement reconciler → deploy → show self-healing.

## CRD design for demos

Keep it simple — 1-2 fields in spec, 1-2 in status:

```yaml
apiVersion: demo.example.com/v1
kind: AppInstance
metadata:
  name: my-app
spec:
  replicas: 2        # желаемое количество реплик
  image: nginx:1.27  # образ приложения
status:
  readyReplicas: 2
  phase: Running
```

## Operator scaffold (operator-sdk)

```bash
# Создать проект
mkdir demo-operator && cd demo-operator
operator-sdk init \
  --domain example.com \
  --repo github.com/org/demo-operator

# Добавить API + controller
operator-sdk create api \
  --group demo \
  --version v1 \
  --kind AppInstance \
  --resource \
  --controller

# Сгенерировать CRD manifests
make generate
make manifests
```

## Reconciler structure

```go
func (r *AppInstanceReconciler) Reconcile(ctx context.Context, req ctrl.Request) (ctrl.Result, error) {
    // 1. Получить custom resource
    instance := &demov1.AppInstance{}
    if err := r.Get(ctx, req.NamespacedName, instance); err != nil {
        return ctrl.Result{}, client.IgnoreNotFound(err)
    }

    // 2. Определить желаемое состояние
    desired := r.buildDeployment(instance)

    // 3. Создать или обновить
    found := &appsv1.Deployment{}
    err := r.Get(ctx, client.ObjectKeyFromObject(desired), found)
    if apierrors.IsNotFound(err) {
        return ctrl.Result{}, r.Create(ctx, desired)
    }
    // patch если нужно обновить
    patch := client.MergeFrom(found.DeepCopy())
    found.Spec = desired.Spec
    return ctrl.Result{}, r.Patch(ctx, found, patch)
}
```

## Deploy operator to cluster

```bash
# Собрать и запушить образ
make docker-build docker-push IMG=cr.yandex/<registry-id>/demo-operator:latest

# Задеплоить CRDs и controller
make deploy IMG=cr.yandex/<registry-id>/demo-operator:latest

# Проверить
kubectl get crd appinstances.demo.example.com
kubectl get pods -n demo-operator-system
```

## Teaching the reconciliation loop visually

Show infinite loop:
```
observe current state
  ↓
compare with desired state (spec)
  ↓
take action (create/update/delete)
  ↓
update status
  ↓
(repeat on any change)
```

Key insight: **idempotent** — running reconciler 10 times has same effect as 1 time.

## Cleanup

```bash
make undeploy
```
