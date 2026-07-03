---
name: presentations-masterclass
description: Marp markdown slide format, presentation structure, and best practices for masterclass slide decks. Use when writing or reviewing slides.md.
metadata:
  type: skill
  topic: presentations
---

# Presentations skill — masterclass context

## Slide deck: Marp markdown

Slides are written in `slides.md` using [Marp](https://marp.app/) format — plain Markdown rendered to HTML/PDF.

**File header:**
```markdown
---
marp: true
theme: default
paginate: true
---
```

**Slide separator:** `---` (horizontal rule)

## Structure template for a 2-hour masterclass

```markdown
# [TOPIC]: [SUBTITLE]

---

## Agenda

- Часть 1: Теория (30 мин)
- Часть 2: Демо (60 мин)
- Часть 3: Практика (20 мин)
- Q&A (10 мин)

---

## 1. Проблема

- pain point 1
- pain point 2
- pain point 3

**Вопрос к аудитории:** Как вы сейчас решаете это?

---

## 2. Что такое [TOOL]

- определение в 1-2 предложениях
- ключевые концепции (3-5 пунктов)

**Ключевая идея:** одна фраза, которую должны запомнить все.

---

## 3. Архитектура

[здесь будет схема — вставить из excalidraw/drawio]

---

## Демо: [шаги]

1. Шаг 1 — что делаем
2. Шаг 2 — что показываем
3. Шаг 3 — что объясняем

---

## Итоги

- что узнали
- когда применять
- когда НЕ применять

---

## Ссылки

- [Official docs](https://...)
- [Репозиторий мастеркласса](https://github.com/...)
```

## Slide content rules

- **1 idea per slide** — если хочется добавить больше, разбить на 2 слайда.
- **Max 5 bullets** — если больше, слайд перегружен.
- **Code blocks** — только ключевые 5-10 строк; остальное — в demo-plan.md.
- **Bold for key terms** — `**GitOps**`, `**ArgoCD**`, не `Gitops`, не `argocd`.
- **Questions** — периодически добавлять `**Вопрос к аудитории:**` для вовлечения.

## Marp render commands

```bash
# Установить
npm install -g @marp-team/marp-cli

# Рендер в HTML (для живого показа)
marp slides.md -o slides.html

# Рендер в PDF (раздаточный материал)
marp slides.md --pdf -o slides.pdf

# Режим просмотра с автообновлением
marp slides.md --preview
```
