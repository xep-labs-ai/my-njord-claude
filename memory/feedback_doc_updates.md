---
name: No permission needed for documentation updates
description: Claude and documenter agent do not need to ask for permission before updating documentation files
type: feedback
---

Do not ask for permission before updating documentation files under `docs/`, `docs/PRP/`, `.claude/docs/`, `.claude/agents/`, or `.claude/skills/`.

**Why:** The user explicitly stated that the architect, documenter, and Claude itself should update documentation autonomously without asking for approval first.

**How to apply:** When a documentation change is clearly justified by an architectural decision, clarification answer, or propagation need — make the change directly. Only ask if the change is ambiguous or contradicts a prior decision.
