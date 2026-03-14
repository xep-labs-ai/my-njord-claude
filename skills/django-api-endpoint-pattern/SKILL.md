---
name: django-api-endpoint-pattern
description: Use when adding, modifying, or reviewing exposed Django REST Framework API endpoints in this Django Invoice API project, including resource endpoints, billing workflow endpoints, serializers, viewsets, routers, filtering, pagination, and drf-spectacular schema generation. Do not use for documentation-only work, test-only work with no API contract impact, frontend work, or pure domain/service changes that do not affect the exposed API.
---

# Django API Endpoint Pattern

## Purpose

Use this skill whenever working on exposed API endpoints in the Django Invoice API project.

This skill exists to keep endpoint structure, naming, schema generation, pagination, filtering, and service-layer boundaries consistent across all apps while matching the current project layout and billing domain.

This skill is an implementation workflow. It must stay shorter and more operational than `.claude/docs/API.md`, which remains the rule document.

---

## Read This Skill When

- adding a new exposed API endpoint
- changing an existing API contract
- adding or changing serializers used by exposed endpoints
- adding or changing viewsets, API views, or custom actions
- registering router URLs
- adding pagination or filtering
- improving drf-spectacular schema behavior
- reviewing endpoint consistency across apps
- implementing billing-related workflow endpoints such as invoice generation

## Do Not Read This Skill When

- doing documentation-only updates
- doing test-only updates with no API design impact
- changing models or services with no exposed API effect
- working only on billing internals with no endpoint changes
- working only on project structure docs
- discussing architecture without implementing or reviewing an endpoint

---

## Source of Truth

Before making API changes:

1. Read `.claude/docs/API.md`.
2. Read `.claude/docs/PROJECT.md` if the endpoint touches domain terminology.
3. Read `.claude/docs/BILLING.md` if the endpoint touches invoice generation, pricing, daily costs, snapshots, or billing selection.
4. Inspect similar endpoints in the same app.
5. Inspect at least one similar endpoint in another app when cross-app consistency matters.

If docs and code disagree, do not invent a third pattern. Align with the intended project convention and update the appropriate Claude doc if the convention itself has changed.

---

## Project Assumptions

This skill assumes the current project structure includes:

- human/domain source-of-truth PRPs under `docs/PRP/`
- Claude-oriented implementation docs under `.claude/docs/`
- endpoint and testing workflows under `.claude/skills/`

The current Claude docs most relevant to endpoint work are:

- `.claude/docs/API.md`
- `.claude/docs/PROJECT.md`
- `.claude/docs/BILLING.md`
- `.claude/docs/CODING_RULES.md`
- `.claude/docs/TESTING.md`
- `.claude/docs/ARCHITECTURE.md`

---

## Core Rules

- Follow `.claude/docs/API.md` as the API rule source of truth.
- Follow `.claude/docs/BILLING.md` for billing workflow invariants.
- Use Django REST Framework conventions.
- Prefer `ModelViewSet` or `ReadOnlyModelViewSet` for normal model-backed resources.
- Prefer explicit workflow endpoints for domain actions that are not natural CRUD.
- Keep views thin.
- Keep business logic in services, not in views.
- Keep serializers focused on validation and representation.
- Use `django-filter` when filtering is meaningful.
- Paginate list endpoints unless there is a deliberate documented exception.
- Ensure all endpoint behavior is compatible with `drf-spectacular`.
- Use explicit schema annotations for custom endpoints or unclear schemas.
- Do not expose mutable behavior for immutable billing artifacts unless the API rules explicitly allow it.
- Preserve billing terminology exactly and consistently.

---

## First Decision

Before implementing anything, classify the task as one of these:

1. Standard CRUD resource endpoint
2. Read-only resource endpoint
3. Billing workflow endpoint
4. Other custom domain workflow endpoint
5. Endpoint review or refactor
6. Schema improvement only

Do not mix patterns unless the endpoint genuinely spans more than one category.

---

## Pattern A: Standard CRUD Resource Endpoint

Use this when the endpoint is a normal model-backed resource that fits CRUD semantics.

### Preferred structure

- serializer in `serializers.py`
- `ModelViewSet` in `views.py`
- router registration in `urls.py`
- optional `filters.py`
- inline `@extend_schema` only when auto schema is unclear

### Typical examples

- billing accounts
- price lists
- resource prices
- resource catalog objects that are truly CRUD-managed through the API

### Steps

1. Inspect similar CRUD resources in the same app.
2. Add or update serializer(s).
3. Add or update the `ModelViewSet`.
4. Register with a router.
5. Ensure plural kebab-case URL naming.
6. Ensure list responses are paginated.
7. Add filtering when meaningful.
8. Keep creation/update logic minimal in the viewset and move domain-heavy behavior to services.
9. Add or update tests.
10. Update `.claude/docs/API.md` only if a new convention was introduced.

---

## Pattern B: Read-Only Resource Endpoint

Use this when the resource should be exposed for reading but not modified through the API.

### Preferred structure

- serializer in `serializers.py`
- `ReadOnlyModelViewSet` in `views.py`
- router registration in `urls.py`
- filtering and pagination where meaningful

### Typical examples

- immutable invoice views
- invoice line views
- invoice daily cost views
- reference data that should not be edited through the API

### Steps

1. Confirm the resource should truly be read-only.
2. Add or update serializer(s).
3. Add or update the `ReadOnlyModelViewSet`.
4. Register with a router.
5. Ensure plural kebab-case URL naming.
6. Ensure list responses are paginated unless clearly bounded and documented otherwise.
7. Add filtering where useful.
8. Add or update tests for list/detail behavior and access rules.
9. Improve schema output if needed.

### Important rule

For invoice artifacts that become immutable after finalization, the API must not accidentally expose update or delete behavior.

---

## Pattern C: Billing Workflow Endpoint

Use this when the endpoint drives billing operations that are not natural CRUD.

### Typical examples

- invoice generation
- invoice preview
- invoice finalization
- billing selection validation
- missing-data evaluation
- billing recomputation checks
- billing breakdown or audit views with custom request parameters

### Preferred structure

- explicit API view or explicit custom action
- request serializer
- response serializer
- service-layer orchestration
- explicit `@extend_schema`

### Steps

1. Read `.claude/docs/BILLING.md` before implementation.
2. Identify the billing invariant the endpoint must preserve.
3. Define explicit request and response serializers.
4. Keep the view responsible only for request parsing, calling the service, and returning structured responses.
5. Put billing logic in services.
6. Annotate schema explicitly.
7. Add tests for success, validation, permissions, and billing-specific failure cases.
8. Ensure immutable invoice behavior is preserved where applicable.
9. Record any new API convention in `.claude/docs/API.md` only if it is meant to be reused.

### Billing-specific rules

- Do not hide billing-selection behavior in ad hoc request parsing.
- Do not place invoice generation logic in serializers.
- Do not let the endpoint bypass billing validation rules defined in `.claude/docs/BILLING.md`.
- Preserve auditability and explainability in API behavior and naming.
- Use stable names for flags such as `force` and `autofill_missing_days` only if they match project conventions.

---

## Pattern D: Other Custom Domain Workflow Endpoint

Use this when the endpoint is domain-specific but not billing-generation CRUD.

### Typical examples

- resource-specific ingestion actions
- quota import endpoints
- custom reporting endpoints
- domain actions that operate on a resource but are not CRUD

### Preferred structure

- explicit custom action or API view
- request serializer when input exists
- response serializer when response shape is non-trivial
- service-layer orchestration
- explicit schema annotations

### Steps

1. Confirm CRUD does not fit.
2. Define the domain action clearly.
3. Keep the request and response explicit.
4. Put business logic in services.
5. Keep URL and naming aligned with existing project style.
6. Add tests for success, validation, auth, and domain failures.
7. Update docs only if a new reusable pattern is introduced.

---

## Pattern E: Endpoint Review or Refactor

Use this when standardizing or cleaning up an endpoint without intentionally changing the public contract.

### Goals

- preserve external behavior unless change is intentional
- align with `.claude/docs/API.md`
- improve readability and consistency
- reduce view complexity
- improve pagination, filtering, and schema clarity where safe
- protect behavior with tests

### Steps

1. Identify the current API contract.
2. Add or strengthen tests before large refactors.
3. Preserve URL shape and response semantics unless intentional.
4. Move heavy logic out of views.
5. Normalize serializer/view/filter structure.
6. Add missing schema annotations.
7. Keep changes minimal and explainable.

### Avoid

- accidental breaking changes
- response shape drift during cleanup
- changing domain terminology casually

---

## Pattern F: Schema Improvement Only

Use this when endpoint behavior stays the same and only schema clarity is being improved.

### Typical cases

- missing request schema
- unclear response schema
- undocumented query parameters
- unclear summaries or descriptions
- custom workflow endpoints rendered poorly in Swagger or Redoc

### Steps

1. Confirm behavior is not changing.
2. Add inline `@extend_schema` where useful.
3. Document custom parameters, request bodies, responses, and important error cases.
4. Verify the schema is clearer after the change.

---

## API Code Layout

Unless the app already has a documented and accepted variation, place API code in:

```text
apps/<app>/api/
├── __init__.py
├── serializers.py
├── views.py
├── urls.py
├── filters.py
└── schema.py
