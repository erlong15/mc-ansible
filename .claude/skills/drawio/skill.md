---
name: drawio-masterclass
description: Draw.io diagram creation and XML format for architecture diagrams, network topology, and K8s cluster visualizations in masterclass materials.
metadata:
  type: skill
  topic: drawio
---

# Draw.io skill — masterclass context

## When to use draw.io vs excalidraw

- **draw.io**: precise architecture diagrams, network topology, formal deliverables
- **excalidraw**: quick sketches for slides, whiteboard-style explanations

## File format

Draw.io files are XML stored in `docs/` as `*.drawio` files. Can be opened in:
- draw.io desktop app
- diagrams.net (web)
- VS Code extension (hediet.vscode-drawio)

## Minimal architecture diagram XML

```xml
<mxfile>
  <diagram name="Architecture">
    <mxGraphModel>
      <root>
        <mxCell id="0"/>
        <mxCell id="1" parent="0"/>

        <!-- Yandex Cloud boundary -->
        <mxCell id="2" value="Yandex Cloud" style="shape=mxgraph.cisco.sites.generic_building;fillColor=#dae8fc;strokeColor=#6c8ebf;" vertex="1" parent="1">
          <mxGeometry x="40" y="40" width="600" height="400" as="geometry"/>
        </mxCell>

        <!-- K8s cluster -->
        <mxCell id="3" value="MK8S Cluster" style="rounded=1;fillColor=#d5e8d4;strokeColor=#82b366;" vertex="1" parent="1">
          <mxGeometry x="80" y="100" width="300" height="200" as="geometry"/>
        </mxCell>

        <!-- ArgoCD -->
        <mxCell id="4" value="ArgoCD" style="shape=mxgraph.kubernetes.argocd;" vertex="1" parent="1">
          <mxGeometry x="120" y="150" width="60" height="60" as="geometry"/>
        </mxCell>

        <!-- Arrow -->
        <mxCell id="5" edge="1" source="4" target="3" parent="1">
          <mxGeometry relative="1" as="geometry"/>
        </mxCell>
      </root>
    </mxGraphModel>
  </diagram>
</mxfile>
```

## Common shapes for K8s diagrams

```
Kubernetes icons (mxgraph.kubernetes.*):
  - pod, deployment, service, ingress
  - namespace, configmap, secret
  - argocd, helm

Network shapes:
  - shape=mxgraph.cisco.routers.router
  - shape=mxgraph.cisco.firewalls.firewall
  - shape=cloud (built-in)
```

## Diagram types for masterclasses

1. **Cluster topology** — nodes, namespaces, pods
2. **GitOps flow** — Git → ArgoCD → K8s
3. **Network flow** — user → LB → Gateway → Service → Pod
4. **IaC layering** — Terraform → MK8S → Helm → App

## Export for slides

Export as PNG (transparent background) and embed in slides.md:
```markdown
![Architecture](docs/architecture.png)
```
