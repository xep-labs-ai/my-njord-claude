---
name: django-testing-pattern
description: Use this skill when writing or updating tests for Django services, billing logic, DRF endpoints, serializers, selectors, or resource-specific invoice scenarios in the Django Invoice API project.
---

# Django Testing Pattern

## Purpose

This skill defines the standard workflow for creating and updating tests in the Django Invoice API project.

Use this skill to keep tests:

- behavior-focused
- deterministic
- minimal but sufficient
- aligned with billing invariants
- aligned with project structure and pytest conventions

This skill is a **workflow**, not the source of truth for testing rules.

Authoritative project rules live in:

- `.claude/docs/TESTING.md`
- `.claude/docs/TESTING_TEMPLATES.md`
- `.claude/docs/BILLING.md` when billing behavior is involved
- `.claude/docs/API.md` when endpoint behavior is involved

---

## Use This Skill When

Use this skill when the task involves:

- writing new pytest tests
- updating failing tests after a behavior change
- adding service-layer tests
- adding DRF endpoint tests
- adding serializer validation tests
- adding selector/query tests
- adding billing and invoice generation tests
- creating resource-specific billing scenario tests
- testing missing-data, autofill, pricing, or immutability behavior

Typical prompts:

- "add tests for this service"
- "write pytest tests for this endpoint"
- "create billing tests for missing days"
- "add invoice-generation tests"
- "test this serializer"
- "add tests for StorageHotel billing"
- "create tests before implementation"

---

## Do Not Use This Skill When

Do not use this skill when the task is only about:

- pure implementation without test work
- repository structure changes with no tests
- writing human documentation only
- API design rules only
- billing architecture discussion without actual test creation

Also do not use this skill as a replacement for reading the relevant docs.

---

## Required Document Routing

Before writing tests, read only the smallest relevant set of docs.

### Always read

- `.claude/docs/TESTING.md`

### Read when relevant

- `.claude/docs/TESTING_TEMPLATES.md` for reusable scenarios and complex billing test ideas
- `.claude/docs/BILLING.md` for invoice generation, pricing, snapshots, immutability, missing data, autofill, and billing invariants
- `.claude/docs/API.md` for endpoint tests
- `.claude/docs/PROJECT.md` for domain understanding
- `.claude/docs/STRUCTURE.md` for file placement
- `.claude/docs/CODING_RULES.md` when architectural constraints may affect test design

Do not load unnecessary docs.

---

## Core Testing Principles

All tests written with this skill should follow these principles:

- test behavior, not implementation trivia
- test the smallest relevant unit
- keep tests explicit and readable
- avoid unnecessary fixtures and abstraction
- prefer deterministic setup
- assert business outcomes clearly
- add regression coverage for bugs
- keep financial behavior auditable and explainable
- use `Decimal` where money is involved

For billing logic, prioritize:

- correctness
- determinism
- reproducibility
- missing-data behavior
- effective-dated pricing behavior
- snapshot persistence
- finalized invoice immutability

---

## Standard Workflow

Follow this workflow in order.

### 1. Identify the test target

Classify the task as one of:

- service test
- API test
- serializer test
- selector test
- model behavior test
- billing workflow test
- resource-specific billing test
- regression test for a reported bug

State the target clearly before writing tests.

---

### 2. Identify the behavior to prove

Write down the exact behavior the test must prove.

Examples:

- invoice generation fails when a selected resource belongs to another billing account
- missing middle days fail without autofill
- autofill carries the last known valid snapshot forward
- overlapping price rows cause invoice generation failure
- POST endpoint returns 201 and persists expected state
- finalized invoice cannot be recalculated

The test should prove one business behavior at a time.

---

### 3. Choose the smallest useful test layer

Prefer the narrowest layer that can prove the behavior.

Use:

- **service tests** for domain logic
- **API tests** for routing, validation, permissions, and response behavior
- **serializer tests** for validation and transformation logic
- **selector tests** only when query behavior is non-trivial
- **billing workflow tests** when end-to-end billing orchestration must be verified

Do not default to API tests if the behavior is pure service logic.

Do not test internal helper functions directly unless they contain meaningful business logic.

---

### 4. Place the test in the correct location

Follow `.claude/docs/STRUCTURE.md`.

Typical patterns:

```text
apps/<app_name>/tests/test_services_<topic>.py
apps/<app_name>/tests/test_api_<topic>.py
apps/<app_name>/tests/test_serializers.py
apps/<app_name>/tests/test_selectors.py
apps/<app_name>/tests/test_billing_<topic>.py
```

Prefer clear filenames over overly generic `test_models.py` or `test_misc.py` when a more specific name is possible.

---

### 5. Create only the minimum required setup

Prefer the smallest deterministic arrangement.

Use only the data needed to prove the behavior.

Avoid:

- oversized fixtures
- unrelated object creation
- hidden setup that makes the test hard to understand
- broad shared fixtures when local setup is clearer

For billing tests, create only the needed:

- billing account
- resource
- pricing rows
- daily snapshots
- invoice period

---

### 6. Write the failing test first

Whenever practical:

- write the test before implementation
- ensure it fails for the expected reason
- then implement the minimal fix

This project prefers test-first development.

---

### 7. Assert the real outcome

Assertions should validate business outcomes, not weak proxies.

Prefer assertions like:

- invoice generation raises the correct domain error
- returned response status is correct
- response body contains expected fields
- persisted invoice snapshot rows exist
- daily costs are exactly what billing rules imply
- missing-data metadata is stored
- autofilled days are marked in metadata
- finalized invoice remains unchanged

Avoid vague assertions like:

- object is not None
- count increased by one without checking what was created
- status code only, when payload correctness matters

---

### 8. Run the smallest relevant test subset first

Start with the narrowest command.

Examples:

```bash
uv run pytest apps/billing/tests/test_billing_autofill.py
uv run pytest apps/api/tests/test_invoice_generation_api.py
uv run pytest apps/billing/tests/test_services_invoice_generation.py -k missing_days
```

Expand only after focused tests pass.

Always use `uv run pytest`.

Examples must use `vim`, never `nano`.

---

### 9. Refine only if needed

If the first test is too broad or brittle:

- split it into smaller cases
- extract only meaningful setup helpers
- make scenario names clearer
- reduce fixture indirection

Prefer clarity over cleverness.

---

## Test Design Patterns

## A. Service Test Pattern

Use for domain logic and orchestration.

Typical structure:

1. arrange domain objects
2. call service
3. assert returned result and persisted side effects

Good for:

- invoice generation
- billing selection validation
- price resolution behavior
- resource billability rules
- snapshot generation
- immutability enforcement

---

## B. API Test Pattern

Use for:

- routing
- serializers through the API layer
- permissions/auth
- request validation
- status codes
- response payloads
- endpoint side effects

Minimum expectations for write endpoints:

- correct status code
- correct persistence behavior
- correct validation behavior
- useful response assertions

Do not push domain-heavy assertions into the API layer if they belong in service tests.

---

## C. Billing Scenario Pattern

Use when testing invoice generation rules.

Typical scenario structure:

- billing period
- resources selected
- daily snapshots present or missing
- price rows
- flags such as `autofill_missing_days` and `force`
- expected invoice result or expected failure

These tests should explicitly state:

- dates
- quantities
- prices
- expected cost behavior
- expected metadata behavior

---

## D. Regression Test Pattern

When fixing a bug:

1. create the test that reproduces the bug
2. verify it fails before the fix when practical
3. implement the fix
4. keep the test as regression protection

Name the test by the business behavior, not by an internal implementation detail.

---

## Billing-Specific Expectations

When this skill is used for billing tests, verify the relevant invariant explicitly.

Possible invariants include:

- billing is evaluated per resource per day
- invoice date range is inclusive
- pricing is effective-dated
- no matching price row causes failure
- overlapping price rows are invalid
- missing snapshot fails unless allowed behavior is enabled
- autofill uses the most recent prior valid snapshot
- if no prior snapshot exists, autofill fails for that resource
- daily billing snapshots are persisted
- finalized invoices are immutable
- totals derive from daily costs
- monetary values use `Decimal`

Do not test billing behavior with floats.

---

## What Good Tests Look Like

Good tests in this project are:

- scenario-based
- explicit about dates and pricing
- small enough to understand quickly
- strict about financial outcomes
- resistant to unrelated refactors
- easy to audit later

A good test name usually describes:

- the condition
- the action
- the expected result

Examples:

- `test_invoice_generation_fails_when_middle_days_are_missing_without_autofill`
- `test_autofill_uses_last_known_snapshot_for_missing_days`
- `test_invoice_generation_fails_when_price_rows_overlap`
- `test_finalize_invoice_prevents_recalculation`
- `test_create_invoice_endpoint_returns_422_for_business_rule_violation`

---

## What to Avoid

Avoid these anti-patterns:

- giant fixtures with hidden behavior
- testing multiple unrelated business rules in one test
- asserting implementation internals instead of outcomes
- using API tests for everything
- relying on implicit ordering unless business-relevant
- weak assertions
- duplicated scenario setup that should be a small helper
- helpers so abstract that the scenario becomes unreadable

For billing specifically, avoid:

- float math
- hand-wavy expected totals
- incomplete date assertions
- ignoring snapshot persistence
- ignoring missing-data metadata when it matters

---

## Suggested Output Shape When Using This Skill

When responding to a test-writing task, structure the work like this:

1. identify what kind of test is needed
2. list the behaviors being proven
3. choose the file location
4. write the tests
5. note any assumptions briefly
6. mention the smallest pytest command to run

Keep the implementation focused and minimal.

---

## Project-Specific Notes

This project uses:

- Django 5.2 LTS
- DRF
- PostgreSQL
- pytest
- `uv`
- `Decimal` for money
- API base path `/api/v1/`

Billing is snapshot-based and auditable.

That means tests for billing changes should usually verify persisted invoice artifacts, not only returned totals.

---

## Example Commands

Run a focused test file:

```bash
uv run pytest apps/billing/tests/test_billing_autofill.py
```

Run a specific scenario:

```bash
uv run pytest apps/billing/tests/test_billing_autofill.py -k missing_middle_days
```

Run API tests for one endpoint module:

```bash
uv run pytest apps/billing/tests/test_api_invoice_generation.py
```

Edit a file:

```bash
vim .claude/skills/django-testing-pattern/SKILL.md
```

---

## Success Criteria

This skill has been applied correctly when:

- the correct docs were loaded
- the smallest useful test layer was chosen
- tests prove business behavior clearly
- billing invariants remain protected
- only minimal setup was introduced
- test placement follows project structure
- focused pytest commands can run immediately

---

## Maintenance Rule

Update this skill when the project changes its standard test workflow.

Do not move detailed project rules into this skill if they already belong in:

- `.claude/docs/TESTING.md`
- `.claude/docs/TESTING_TEMPLATES.md`
- `.claude/docs/BILLING.md`
- `.claude/docs/API.md`

Keep this skill focused on workflow and decision-making.
