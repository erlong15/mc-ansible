# CLAUDE.md

This file provides guidance to Claude Code when working with masterclass materials in this repository.

## Purpose

<!-- TODO: Replace with specific masterclass topic -->
Teaching materials for a **[TOPIC]** masterclass. All slides, demo plans, and comments in code are in **Russian** — keep that language when editing `slides.md`, `demo-plan.md`, `README.md`, and comments in `.tf`/`.yaml`/`.go`/`.py` files.

## Audience

DevOps engineers and system administrators familiar with Linux and basic cloud concepts. May be new to the specific tool being taught. Avoid jargon without explanation; always show the "why" before the "how".

## Repository layout

```
.
├── terraform/          # Yandex Cloud infrastructure (K8s cluster + tool setup)
├── demo/               # Demo materials: configs, manifests, code examples
│   ├── 01-*/           # Step-by-step numbered labs
│   └── charts/         # Helm charts used in demos
├── ansible/            # Ansible playbooks (if topic requires)
├── docs/               # Architecture diagrams (drawio/excalidraw sources)
├── slides.md           # Lecture deck (Marp markdown → PDF/HTML)
├── demo-plan.md        # Step-by-step demo script (source of truth for live flow)
└── README.md           # Student setup guide
```

## Key rules

- `slides.md` and `demo-plan.md` are the source of truth — keep them in sync with demo/ contents.
- `terraform.tfvars` is in `.gitignore` — students copy from `.tfvars.example`.
- All Yandex Cloud resources: `preemptible = true`, `standard-v3`, no hardcoded IDs.
- Russian comments in `.tf`, `.yaml`, `.go`, `.py` files (1-2 lines explaining the concept to the student).

## Yandex Cloud environment

```bash
yc config list          # cloud_id + folder_id + token
export YC_TOKEN=$(yc iam create-token)
terraform init && terraform plan && terraform apply
```

## Subagents

Use the agents in `.claude/agents/` for specialized tasks:

| Agent | When to use |
|---|---|
| `devops-engineer` | Writing K8s manifests, Helm charts, CI/CD configs, Ansible playbooks |
| `devops-architect` | System design, diagram review, architectural decisions |
| `yc-engineer` | Yandex Cloud–specific resources, IAM, networking, provider quirks |
| `lecturer` | Slide content, demo script narrative, student-facing explanations |

Delegate non-trivial work to subagents with `run_in_background: true`.
