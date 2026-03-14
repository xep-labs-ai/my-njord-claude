# CLAUDE.md

## Project

Django Invoice API.

Stack:

- Django 5.2 LTS
- Django REST Framework
- PostgreSQL
- LDAP authentication
- Python 3.12
- uv for dependency management
- pytest for testing

This system generates invoices for company IT resources such as:

- StorageHotel
- VirtualMachine
- future `ResourceModel` types

Billing is deterministic, snapshot-based, auditable, and reproducible.

- Read pyproject.toml for development tooling and conventions.

---

## Non-Negotiable Development Rules

These rules must always be respected.

- Write tests first whenever practical.
- Do not continue implementation until tests pass.
- Use `Decimal` for all money calculations.
- Keep Django views thin.
- Put domain logic in services.
- APIs must live under `/api/v1/`.
- Examples must use `vim`, never `nano`.
- Documentation under `docs/` must stay synchronized with code.

---

## Development Execution Pipeline

Claude must follow this workflow when implementing features or changes.

1. architect
   - review requirements
   - detect missing details
   - clarify ambiguities
   - propose minimal architecture

2. documenter (only if decisions modify documentation)
   - synchronize PRPs and Claude docs
   - ensure documentation reflects the clarified design

3. builder
   - write tests first whenever possible
   - implement minimal code changes
   - update serializers, services, and models
   - create migrations when required

4. tester
   - run the smallest relevant test subset first
   - summarize failures
   - identify root causes

This workflow keeps architecture, implementation, tests, and documentation aligned.

---

## Execution Workflow

When implementing changes:

1. Read the smallest relevant `.claude/docs/` files.
2. Use the relevant skill if one exists for the task.
3. Write or update tests first whenever practical.
4. Implement the minimal code required.
5. Run the smallest relevant test subset first.
6. Fix failures before expanding scope.
7. Update documentation if behavior changed.

Prefer small, deterministic changes over large refactors.

---

## Claude Documentation Routing Rule

Claude documentation lives under:

`.claude/docs/`

Each document contains a lightweight routing header:

- `Doc Purpose`
- `Read this document when`
- `Do not read this document when`

Use that header first to determine whether the document is relevant.

Only load the minimum number of documents necessary for the task.

Do not read every document by default.

---

## Primary Claude Docs

Use these documents depending on the task.

### `.claude/docs/PROJECT.md`

Use for:

- system purpose
- core domain entities
- billing context
- supported resource types
- shared terminology

### `.claude/docs/ARCHITECTURE.md`

Use for:

- app boundaries
- module responsibilities
- cross-domain orchestration
- service-layer boundaries
- modular monolith decisions

### `.claude/docs/STRUCTURE.md`

Use for:

- where files should live
- app layout
- selectors/services/tests placement
- repository organization

### `.claude/docs/API.md`

Use for:

- DRF ViewSets
- serializers
- endpoint patterns
- status codes
- write-operation API tests

### `.claude/docs/BILLING.md`

Use for:

- invoice generation
- pricing resolution
- billing selection rules
- daily evaluation workflow
- snapshot persistence
- financial invariants

This document contains financial and auditability constraints and must be treated carefully.

### `.claude/docs/TESTING.md`

Use for:

- pytest conventions
- test organization
- service tests
- API tests
- minimal useful test scope

### `.claude/docs/TESTING_TEMPLATES.md`

Use for:

- complex resource-model billing scenarios
- reusable invoice-generation test patterns
- missing-data and autofill test ideas
- resource-specific test templates

### `.claude/docs/CODING_RULES.md`

Use for:

- coding guardrails
- architectural constraints
- patterns that must not be introduced
- consistency rules for implementation

### `.claude/docs/DEVELOPER_TOOLING_AND_ENVIRONMENT.md`

Use for:

- `uv`
- `pytest`
- `ruff`
- `mypy`
- local development environment assumptions
- setup and execution conventions

---

## Skills

Reusable workflows live under:

`.claude/skills/`

Currently available skills:

- `django-api-endpoint-pattern`
- `django-testing-pattern`

Use a skill when the task clearly matches its workflow.

Do not invent or reference skills that do not exist in the repository.

---

# Repository Structure

This project uses two Git repositories.

## 1. Project Repository

Location:
project root

This repository contains the Django application and all project code.

Typical contents:

- Django apps
- configuration
- migrations
- tests
- project documentation (docs/)
- pyproject.toml
- CI configuration

This repository represents the **actual product being developed**.

---

## 2. Claude Configuration Repository

Location:
.claude/

The `.claude/` directory is a **separate Git repository** that contains all configuration and documentation used by Claude Code.

It includes:

- CLAUDE.md
- Claude agents
- Claude skills
- Claude documentation (.claude/docs/)
- Claude hooks
- Claude settings

Purpose:

- manage Claude behavior independently from application code
- version Claude workflows and development rules
- allow reuse of Claude configuration across projects

This repository acts as the **AI development environment configuration** for the project.

---

## Task → Docs → Skills Routing Table

Use this table to minimize context loading and improve implementation accuracy.

| Task | Read First | Also Read If Needed | Skill |
|---|---|---|---|
| Add or update API endpoint | `API.md` | `PROJECT.md`, `STRUCTURE.md`, `TESTING.md`, `CODING_RULES.md` | `django-api-endpoint-pattern` |
| Add or update serializer | `API.md` | `PROJECT.md`, `CODING_RULES.md` | `django-api-endpoint-pattern` |
| Add endpoint tests | `TESTING.md` | `API.md`, `TESTING_TEMPLATES.md` | `django-testing-pattern` |
| Add service tests | `TESTING.md` | `PROJECT.md`, `BILLING.md`, `TESTING_TEMPLATES.md` | `django-testing-pattern` |
| Change billing logic | `BILLING.md` | `PROJECT.md`, `ARCHITECTURE.md`, `TESTING.md`, `CODING_RULES.md` | `django-testing-pattern` |
| Add invoice-generation behavior | `BILLING.md` | `ARCHITECTURE.md`, `STRUCTURE.md`, `TESTING.md` | `django-testing-pattern` |
| Add new resource type | `PROJECT.md` | `ARCHITECTURE.md`, `BILLING.md`, `STRUCTURE.md`, `TESTING.md` | none |
| Move or create files | `STRUCTURE.md` | `ARCHITECTURE.md`, `CODING_RULES.md` | none |
| Refactor service-layer code | `ARCHITECTURE.md` | `STRUCTURE.md`, `CODING_RULES.md`, `TESTING.md` | none |
| Update financial rounding/pricing behavior | `BILLING.md` | `TESTING.md`, `PROJECT.md` | `django-testing-pattern` |
| Update developer commands or tooling docs | `DEVELOPER_TOOLING_AND_ENVIRONMENT.md` | `STRUCTURE.md` | none |
| Write or update Claude-facing docs | relevant target doc | `PROJECT.md`, `STRUCTURE.md`, `CODING_RULES.md` | none |

If multiple tasks are involved, load only the docs required for the current subtask.

---

## Billing Safety Rules

For any billing-related implementation, preserve these invariants:

- billing happens per resource per day
- pricing is effective-dated
- invoice generation persists daily snapshots
- finalized invoices are immutable
- billing behavior must be deterministic
- missing data behavior must be explicit
- invoice results must remain auditable and reproducible

Do not introduce shortcuts that bypass persisted billing snapshots.

Do not place billing logic in views or serializers.

---

## API Implementation Rules

When implementing endpoints:

- prefer DRF ViewSets
- keep views thin
- keep serializers explicit
- place business logic in services
- use selectors for read-side query composition where appropriate
- ensure write operations have endpoint tests

Use explicit domain actions instead of hiding business behavior inside generic endpoints when the action is not plain CRUD.

---

## Testing Rules

Testing is mandatory for behavior changes.

Preferred order:

1. write or update the test
2. implement the smallest change
3. run the smallest relevant test subset
4. expand to broader tests only after the focused tests pass

For billing behavior, tests should validate:

- correctness
- determinism
- missing-data handling
- price resolution
- snapshot persistence
- immutability where relevant

---

## Model Usage Guidance

Use cheaper models when possible.

Prefer cheaper models for:

- routine edits
- test writing
- boilerplate
- serializer updates
- simple endpoint wiring
- small refactors
- documentation updates

Use stronger models only when necessary:

- ambiguous billing logic
- architectural changes
- cross-module design decisions
- shared abstractions
- resource-extension design
- difficult financial invariants

Do not use stronger models for routine mechanical changes.

---

## Context Efficiency Rule

Claude should avoid loading unnecessary documentation.

Preferred workflow:

`Identify task -> load minimal docs -> use matching skill if needed -> implement -> test -> update docs`

Examples:

### Example: creating an endpoint

Read:

- `API.md`
- `TESTING.md`

Use skill:

- `django-api-endpoint-pattern`

### Example: changing invoice generation

Read:

- `BILLING.md`
- `TESTING.md`

Also read if needed:

- `ARCHITECTURE.md`

Use skill:

- `django-testing-pattern`

### Example: adding a new resource type

Read:

- `PROJECT.md`
- `ARCHITECTURE.md`
- `BILLING.md`
- `STRUCTURE.md`
- `TESTING.md`

Use skill:

- none unless a relevant skill is later added

---

## File and Doc Alignment Rule

Claude-facing docs under `.claude/docs/` are condensed implementation guidance.

Human/source-of-truth documentation lives under:

- `docs/`
- `docs/PRP/`

PRPs are the source of truth for domain architecture and resource specifications.

If implementation changes behavior, update the appropriate documentation layer:

- update `docs/` when human-facing/source-of-truth docs changed
- update `.claude/docs/` when implementation guidance changed
- update both when necessary

Do not allow Claude docs to drift away from real project behavior.

---

## Final Guidance

When uncertain:

- prefer explicitness over cleverness
- prefer deterministic services over hidden magic
- prefer small changes over broad rewrites
- prefer reading one more relevant doc over guessing
- prefer tests that prove business behavior over superficial coverage

This project is a financial system. Correctness, traceability, and maintainability take priority over speed of implementation.

Before considering a change complete, Claude must run the relevant quality gates for the touched code, including pre-commit hooks or equivalent commands, and fix issues before proposing a final commit-ready result.
