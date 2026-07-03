---
name: excalidraw-masterclass
description: Excalidraw JSON format for quick architecture sketches, whiteboard diagrams, and slide illustrations in masterclass materials.
metadata:
  type: skill
  topic: excalidraw
---

# Excalidraw skill — masterclass context

## When to use excalidraw

- Whiteboard-style explanations during slides
- Quick architectural sketches
- Diagrams that should look hand-drawn (approachable, not intimidating)

## File format

Excalidraw files are JSON stored in `docs/` as `*.excalidraw` files. Open at excalidraw.com or with VS Code extension.

## Minimal excalidraw JSON template

```json
{
  "type": "excalidraw",
  "version": 2,
  "source": "https://excalidraw.com",
  "elements": [
    {
      "type": "rectangle",
      "id": "node1",
      "x": 100, "y": 100,
      "width": 160, "height": 80,
      "strokeColor": "#1971c2",
      "backgroundColor": "#d0ebff",
      "fillStyle": "solid",
      "roughness": 1,
      "roundness": { "type": 3 },
      "label": { "text": "K8s Cluster" }
    },
    {
      "type": "text",
      "id": "label1",
      "x": 130, "y": 130,
      "text": "K8s Cluster",
      "fontSize": 16,
      "textAlign": "center"
    },
    {
      "type": "arrow",
      "id": "arrow1",
      "points": [[0,0],[200,0]],
      "x": 100, "y": 200,
      "strokeColor": "#2f9e44",
      "label": { "text": "деплой" }
    }
  ],
  "appState": {
    "gridSize": null,
    "viewBackgroundColor": "#ffffff"
  }
}
```

## Standard colors for K8s diagrams

```
Namespace/cluster boundary: #e3fafc (light cyan) border #0c8599
Application box:            #d3f9d8 (light green) border #2f9e44  
Database/storage:           #fff3bf (light yellow) border #f08c00
External/internet:          #f8f9fa (light gray)  border #868e96
ArgoCD/GitOps:              #e5dbff (light purple) border #7048e8
Arrows (traffic):           #2f9e44
Arrows (sync):              #7048e8
```

## Quick diagram patterns

**GitOps flow:**
```
[Git Repo] --push--> [ArgoCD] --sync--> [K8s Cluster]
                        ↑
                    [Developer]
```

**Request path:**
```
[User] --> [Yandex LB] --> [Envoy Gateway] --> [Service] --> [Pod]
```

**IaC layers:**
```
Terraform
  └─ MK8S Cluster
       └─ ArgoCD (helm_release)
            └─ App (ApplicationSet)
```

## Embedding in slides

Export as SVG or PNG, then:
```markdown
![GitOps Flow](docs/gitops-flow.svg)
```

Or paste JSON directly when presenting in excalidraw.com for live drawing effect.
