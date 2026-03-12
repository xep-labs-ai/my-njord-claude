# TESTING.md

## Doc Purpose

Defines the testing strategy and implementation rules for the Django Invoice API.

This document describes:

- how tests must be written
- which layers must be tested
- pytest conventions
- billing invariants that must always be verified
- expectations for deterministic billing behavior

The goal is to ensure that the billing system remains:

- deterministic
- reproducible
- auditable
- safe to refactor

This document focuses on **testing rules and patterns**, not domain specifications.

Detailed billing scenarios live in:

docs/PRP/


---

## Read this document when

- Writing tests for services or APIs
- Implementing billing logic
- Adding a new billable resource type
- Refactoring billing calculations
- Creating fixtures or factories
- Debugging invoice generation failures

---

## Do not read this document when

- Designing billing domain rules
- Understanding pricing models
- Reviewing invoice generation workflows

For those topics see:

.claude/docs/BILLING.md  
docs/PRP/


---

# Testing Philosophy

Tests must guarantee that invoice generation is:

- deterministic
- reproducible
- explainable from stored data

Tests must validate:

- daily billing behavior
- price resolution
- snapshot persistence
- rounding rules
- resource selection behavior
- missing data policies

Billing tests must never depend on:

- random data
- current system time
- external services


---

# Test Layers

Tests are organized in three main layers.

## 1. Service Tests (Primary Layer)

Service tests validate domain logic.

They must cover:

- invoice generation
- billing day evaluation
- price resolution
- snapshot persistence
- missing data behavior
- rounding
- billing scope selection

Service tests are the **most important tests in the system**.

Most billing scenarios should be implemented as service tests.

Typical location:

tests/services/


---

## 2. API Tests

API tests verify:

- request validation
- serializer behavior
- endpoint routing
- HTTP status codes
- response structure

API tests must **not re-implement billing assertions** already tested in services.

Typical location:

tests/api/


---

## 3. Model Tests

Model tests verify:

- constraints
- field validation
- unique rules
- basic model behavior

They should remain minimal.

Typical location:

tests/models/


---

# Test Framework

Testing uses:

pytest  
pytest-django

Typical command:

uv run pytest


---

# Test Naming Conventions

Test files:

test_<domain>.py

Examples:

test_invoice_generation.py  
test_price_resolution.py  
test_storage_hotel_billing.py


Test functions:

test_<behavior>_<expected_result>

Examples:

test_invoice_generation_fails_when_missing_snapshots  
test_autofill_missing_days_fills_previous_quota  
test_price_resolution_fails_on_overlapping_rows


---

# Deterministic Billing Requirements

Billing tests must verify that:

- the same inputs always produce the same invoice
- daily costs are reproducible
- snapshot rows contain all required information
- pricing decisions are explainable

Tests must verify the persisted data in:

Invoice  
InvoiceLine  
InvoiceDailyCost


---

# Billing Test Invariants

The following behaviors must always be tested.

## Daily Evaluation

Billing must evaluate every day in the billing period.

The billing period is **inclusive**.

Example:

2026-01-01 → 2026-01-31  
→ 31 evaluations.


---

## Price Resolution

Tests must verify:

- correct effective-dated price selection
- failure when no price exists
- failure when multiple overlapping prices exist


---

## Missing Snapshot Handling

Default behavior:

missing snapshot → invoice generation fails

Tests must verify:

- failure when coverage is incomplete
- success when autofill is enabled
- autofill uses the most recent prior snapshot
- autofill does not override later explicit records


---

## Resource Selection

Tests must verify that invoice generation fails when:

- resources belong to another billing account
- unknown resource types are requested
- selection is ambiguous
- explicit selection is empty
- resources are selected multiple times


---

## Decimal Usage

All billing calculations must use:

Decimal

Tests must verify:

- full precision internal calculations
- customer-visible totals rounded to 2 decimals


---

## Leap Year Handling

Daily cost calculations must respect the number of days in the year.

Tests must verify behavior for:

- 365 day years
- 366 day years


---

## Snapshot Persistence

Invoice generation must persist billing snapshots.

Tests must verify that:

InvoiceDailyCost contains:

- resource reference
- billed day
- normalized usage
- resolved price
- daily cost
- metadata describing autofill or missing data


These rows are the **audit source of truth**.


---

## Invoice Immutability

Finalized invoices must be immutable.

Tests must verify that after finalization:

- invoice totals cannot change
- snapshot rows remain unchanged
- recalculation is not allowed


---

# Canonical Billing Test Scenarios

The following simplified examples illustrate expected testing patterns.

Detailed scenario specifications live in:

docs/PRP/


---

## Scenario Example — Missing Middle Days Require Autofill

Period:

2026-01-01 → 2026-01-31

Quota data exists for:

2026-01-01 → 2026-01-15  
2026-01-20 → 2026-01-31

Missing:

2026-01-16 → 2026-01-19


Expected behavior:

without autofill  
→ invoice generation fails

with autofill  
→ missing days inherit the most recent prior quota


Tests must verify:

- correct quota values for filled days
- correct daily costs
- correct invoice total
- snapshot rows record autofill metadata


---

## Scenario Example — Missing End of Period

Period:

2026-01-01 → 2026-01-10

Quota exists for:

2026-01-01 → 2026-01-07

Missing:

2026-01-08 → 2026-01-10


Expected behavior:

without autofill  
→ fail

with autofill  
→ missing days inherit the last known quota


---

## Scenario Example — Autofill Does Not Override Later Records

Quota data:

2026-01-01 → 2026-01-03 : 10 TB  
2026-01-06 → 2026-01-10 : 20 TB

Missing:

2026-01-04 → 2026-01-05


Expected behavior:

Jan 4–5 inherit 10 TB  
Jan 6–10 remain 20 TB


---

# Resource-Specific Billing Tests

Each resource type must define additional tests verifying:

- normalization rules
- pricing dimensions
- resource-specific daily cost formulas
- missing data handling if different


These scenarios should live in:

docs/PRP/resources/


---

# Adding a New Resource Type

When adding a new resource, tests must cover:

- normalization behavior
- price resolution
- daily billing calculation
- missing snapshot behavior
- snapshot persistence
- rounding behavior


No new resource type should be added without **complete billing tests**.


---

# Test Data Strategy

Tests should use:

- minimal fixtures
- explicit setup
- deterministic inputs

Avoid large global fixtures.

Prefer:

small resource factories  
explicit daily snapshot creation


Example approach:

- create billing account
- create resource
- insert daily snapshots
- insert price rows
- generate invoice
- verify snapshot rows and totals


---

# Test Execution Strategy

During development:

Run the smallest relevant subset first.

Example:

pytest tests/services/test_invoice_generation.py


Before committing:

Run the full suite.

Example:

uv run pytest


---

# Summary

Testing in this project ensures that:

- billing remains deterministic
- invoices remain reproducible
- domain rules remain safe to refactor
- resource extensions remain reliable

The billing engine must always be validated through **deterministic service tests backed by persisted billing snapshots**.
