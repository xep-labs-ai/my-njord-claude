# .claude/docs/CODING_RULES.md

## Doc Purpose
Defines coding guardrails and architectural rules that Claude must follow when implementing or modifying code in this repository.

These rules exist to keep the codebase consistent, auditable, and safe for a financial billing system.

This document contains implementation constraints, not architectural explanations.

## Read this document when
- Implementing Django models
- Implementing services or business workflows
- Implementing serializers or views
- Writing financial calculations
- Designing billing logic
- Writing migrations
- Adding dependencies

## Do not read this document when
- Understanding the system domain (see PROJECT.md)
- Understanding architecture (see ARCHITECTURE.md)
- Implementing REST endpoints (see API.md)
- Writing tests (see TESTING.md)
- Understanding billing rules (see BILLING.md)
- Understanding repository structure (see STRUCTURE.md)

---

# Core Philosophy

This project is a financial billing system.

Key priorities:

1. correctness over cleverness
2. reproducibility
3. auditability
4. explicit domain modeling
5. predictable architecture
6. maintainable implementations

Never introduce complexity unless it clearly improves correctness or safety.

---

## Static Analysis and Developer Tooling

This project uses the following development and quality tools:

- ruff
- mypy
- django-stubs
- djangorestframework-stubs
- pytest
- pytest-django
- pytest-cov
- django-extensions
- pre-commit
- django-doctor

Claude must treat these tools as active project conventions, not optional dependencies.

### Rules

- All new Python code must be compatible with the configured `mypy` rules.
- All new Django code must be written with `django-stubs` in mind.
- All new DRF code must be written with `djangorestframework-stubs` in mind.
- New functions and methods must include explicit type annotations.
- Avoid `Any` unless there is a clear and justified reason.
- QuerySets should use typed generics where practical.
- Services, selectors, and serializers should be written in a type-check-friendly way.
- Code must be compatible with `ruff check`.
- Code formatting should remain compatible with `ruff format`.
- Tests must be written and run with `pytest` and `pytest-django`.
- Use `pytest-cov` when validating meaningful domain logic or billing behavior.
- `django-extensions` may be used for development and repository exploration, but not as a substitute for clear application architecture.
- `django-doctor` should be treated as an additional quality signal for Django-specific issues, not as the primary source of truth.
- `pre-commit` hooks should be kept passing for all committed changes.

### Implementation Expectations for Claude

When generating code, Claude should:

- prefer typed service functions
- prefer typed selectors
- prefer typed QuerySets
- avoid untyped helper functions
- avoid introducing patterns that fight `mypy` or the Django/DRF stubs
- generate tests that fit `pytest` and `pytest-django`
- keep code simple enough to pass linting and type checking without unnecessary ignores

### Example Expectations

Preferred:

    def create_invoice(...) -> Invoice:
        ...

    def get_billable_resources(...) -> QuerySet[ResourceModel]:
        ...

Avoid:

    def create_invoice(...):
        ...

    def get_billable_resources(...):
        ...

---

# Django Layering Rules

Responsibilities must remain clearly separated.

## Models

Models may contain:

- persistence fields
- database constraints
- indexes
- simple helpers
- small computed properties

Models must **not** contain:

- billing workflows
- invoice generation logic
- multi-model orchestration
- API-specific behavior

---

## Services

Business logic belongs in **service modules**.

Typical location:

apps/<domain>/services/

Examples of services:

generate_invoice()
recalculate_invoice()
finalize_invoice()
process_usage_ingestion()

Services may:

- read/write multiple models
- enforce domain rules
- orchestrate workflows
- run inside database transactions

Services must produce deterministic outputs.

---

## Serializers

Serializers are responsible for:

- input validation
- output formatting

Serializers must **not**:

- run billing algorithms
- generate invoices
- orchestrate multi-model workflows

---

## Views

Views should remain **thin**.

Views may:

- receive requests
- validate inputs
- call services
- return responses

Views must not contain business logic.

---

# Financial Safety Rules

Financial calculations must follow strict safety rules.

## Always Use Decimal

Never use:

float

Always use:

Decimal

This applies to:

- pricing
- invoice totals
- billing calculations
- discounts

---

## Never Round Early

Internal financial calculations must maintain full precision.

Rounding should occur only when producing final output values.

---

## Finalized Invoices Are Immutable

Claude must **never modify**:

- finalized invoices
- invoice lines
- invoice daily cost records

Only **draft invoices** may be recalculated.

---

# Pricing Rules

Prices are effective-dated.

Existing pricing rows must **never be modified**.

Instead:

- insert a new pricing row
- define new effective dates

This preserves historical billing correctness.

---

# Migration Safety

Claude must **never**:

- delete migrations
- rewrite applied migrations
- manually modify migration history

Safe operations:

python manage.py makemigrations
python manage.py migrate

---

# Dependency Rules

Dependencies must remain minimal.

Preferred development tools:

uv
pytest
ruff
mypy

Claude should avoid introducing heavy dependencies unless they are clearly justified.

---

# Logging

Important domain operations should be logged.

Examples:

- invoice generation
- invoice finalization
- usage ingestion

Logs must **never contain sensitive data**.

---

# Stop Conditions

Claude must stop and ask for clarification if:

- architecture conflicts with documentation
- billing rules become ambiguous
- migrations could destroy data
- secrets or credentials are required

Otherwise Claude should continue implementation.

---

# Golden Rule

When unsure:

Prefer correctness, clarity, and safety over speed.
