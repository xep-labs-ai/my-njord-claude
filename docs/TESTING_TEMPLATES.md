# TESTING_TEMPLATES.md

## Doc Purpose

Provides reusable test-template guidance for billable resources derived from `ResourceModel`.

This document helps Claude create:

- a strong initial test set for any new billable resource
- a consistent family of advanced billing tests across resource types
- reusable scenario templates for missing-data, autofill, pricing, and immutability behavior

This document is **not** the source of truth for billing rules.
Billing semantics come from:

- `.claude/docs/BILLING.md`
- `.claude/docs/TESTING.md`
- `docs/PRP/`
- resource-specific PRPs under `docs/PRP/resources/`

---

## Read this document when

- Adding tests for a new `ResourceModel` subtype
- Expanding billing test coverage for a resource type
- Creating invoice-generation tests from a resource PRP
- Translating old resource-specific tests into shared templates
- Designing autofill, missing-data, or snapshot-persistence tests

## Do not read this document when

- Only changing endpoint routing or serializer wiring
- Only changing repository structure
- Only writing human documentation
- Looking for the authoritative billing rules instead of reusable test patterns

---

# Purpose

Every billable resource type should have:

1. a **minimal useful test set**
2. a **shared advanced test set**
3. **resource-specific tests** for its own billing dimensions and normalization rules

Claude should not create only happy-path tests.

For each `ResourceModel` subtype, tests should verify that the resource works correctly inside the **shared billing engine** and also respects its own **resource-specific billing contract**.

---

# Core Testing Rule

For each new billable resource type, Claude should create tests in this order:

1. model and factory sanity
2. billing eligibility behavior
3. daily snapshot completeness behavior
4. price resolution behavior
5. daily cost calculation behavior
6. invoice persistence and snapshot behavior
7. immutability behavior after finalization
8. advanced missing-data and autofill scenarios
9. resource-specific edge cases

Do not stop at “invoice creates successfully”.

---

# Minimal Useful Test Set for Every ResourceModel

Each new resource type should usually start with tests covering at least the following.

## 1. Resource billing eligibility

Create tests for:

- active resource with billing account is billable
- resource with `billing_account=None` is not billable
- retired resource is not billable
- unassigned resource is not billable
- selection exclusions prevent billing
- lifecycle date boundaries are evaluated per day if supported

Template intent:

- verify shared billable-resource rules
- ensure the resource participates correctly in selection filtering

---

## 2. Daily snapshot completeness

Create tests for:

- complete daily coverage across the whole period succeeds
- missing daily snapshot fails by default
- missing first day fails even with autofill if no prior snapshot exists
- incomplete coverage is recorded correctly if `force=true` behavior exists for that workflow

Template intent:

- verify default missing-data policy
- verify that invoice generation is strict unless flags explicitly allow otherwise

---

## 3. Price resolution

Create tests for:

- effective-dated price resolves correctly for each day
- missing price row fails invoice generation
- overlapping price rows fail as invalid configuration
- price changes inside the billing period split daily costs correctly

Template intent:

- verify that prices are resolved per day, not once for the whole invoice

---

## 4. Daily cost calculation

Create tests for:

- simple full-period calculation with one stable price
- calculation across leap year day if yearly prorating is used
- Decimal is used end to end
- customer-visible total is rounded consistently
- no hidden float behavior appears in stored totals

Template intent:

- verify deterministic, reproducible daily totals

---

## 5. Invoice persistence and auditing

Create tests for:

- invoice stores selection metadata
- line snapshots store resource reference and summary metadata
- `InvoiceDailyCost` rows exist for every billed day
- normalized usage and resolved price are stored in daily rows
- autofill metadata is stored when autofill occurs

Template intent:

- daily snapshots must be the audit source of truth

---

## 6. Finalization and immutability

Create tests for:

- finalized invoice cannot be recalculated
- finalized invoice cannot be mutated through normal billing workflows
- later changes to prices or usage do not retroactively change finalized invoice totals

Template intent:

- verify reproducibility after finalization

---

# Shared Advanced Test Family for Every ResourceModel

In addition to the minimal set above, every resource type should implement a shared family of more complex billing tests.

These tests should be adapted to the resource’s own:

- daily snapshot model
- billable dimensions
- normalization rules
- cost formula
- threshold or discount behavior
- missing-data behavior if explicitly customized

The old StorageHotel scenarios below are now treated as **cross-resource templates**.

For non-StorageHotel resources, replace:

- “quota”
- “TB”
- “threshold”
- StorageHotel-specific pricing examples

with that resource’s equivalent billing inputs and expected units.

---

# Resource-Agnostic Guidance for Translating Templates

When adapting these templates to another `ResourceModel`, Claude should map the concepts like this:

- StorageHotel `quota` → resource daily billable quantity or normalized usage
- TB → resource billing unit
- threshold discount → equivalent pricing rule for that resource, if any
- daily quota records → resource daily snapshot records
- line total → resource line total under that resource’s formula

If a resource has multiple billable dimensions, create either:

- one test focusing on the dominant dimension first, then
- additional variants covering mixed-dimension pricing

Do not force a threshold-discount structure on resources that do not use one.

---

# Shared Complex Scenario Templates

## Template RT-18 — Missing middle days require autofill flag

### Intent

Verifies that missing days in the middle of a billing period fail by default and are only accepted when autofill is explicitly enabled.

### Generic pattern

Period: contiguous inclusive date range

Daily data exists for:

- start segment
- end segment

Missing:

- one or more middle days

Expected behavior:

- without autofill: invoice generation fails because snapshot coverage is incomplete
- with autofill: invoice generation succeeds
- missing days inherit the most recent prior known value
- all days are billed using the correct carried-forward value
- totals are calculated from the filled daily values
- autofilled days are marked as autofilled in snapshot metadata

### StorageHotel example template

Scenario: SH-18 — Missing middle days require autofill flag  
Period: 2026-01-01 to 2026-01-31

Quota data exists for:

- 2026-01-01 to 2026-01-15: 10 TB
- 2026-01-20 to 2026-01-31: 10 TB

Missing:

- 2026-01-16 to 2026-01-19

Price:

- normal=500, discount=400, threshold=10 TB

Expected behavior:

- invoice creation without autofill-missing-days fails because quota coverage is incomplete
- invoice creation with autofill-missing-days succeeds
- missing days 2026-01-16 to 2026-01-19 are filled from the most recent prior known quota
- all 31 days are billed at 10 TB
- invoice total = 31 × (10 × 400 / 365) = 339.7260273972602739...
- rounded total = 339.73

---

## Template RT-20 — Missing end-of-period days are filled from the latest known value

### Intent

Verifies that missing days at the end of the billing period are filled from the latest known earlier snapshot, but only when autofill is enabled.

### Generic pattern

Daily data exists for:

- beginning of period

Missing:

- one or more final days

Expected behavior:

- without autofill: fail
- with autofill: succeed
- end-of-period missing days inherit the latest known prior value
- totals match the carried-forward values
- snapshot metadata marks only the missing days as autofilled

### StorageHotel example template

Scenario: SH-20 — Missing end-of-period days are filled from the latest known quota  
Period: 2026-01-01 to 2026-01-10

Quota data exists for:

- 2026-01-01 to 2026-01-07: 10 TB

Missing:

- 2026-01-08 to 2026-01-10

Expected behavior:

- without autofill: fail
- with autofill: succeed
- Jan 8–10 are filled as 10 TB
- total = 10 days at 10 TB discount price

---

## Template RT-21 — Autofill respects later explicit records

### Intent

Verifies that autofill only fills the actual missing segment and does not overwrite later explicit daily records.

### Generic pattern

Daily data exists for:

- early segment with value A
- later segment with value B

Missing:

- gap between them

Expected behavior with autofill:

- missing days inherit value A
- later explicit days remain value B
- autofill never smears older values into later explicit records

### StorageHotel example template

Scenario: SH-21 — Autofill respects later explicit quota records  
Period: 2026-01-01 to 2026-01-10

Quota data exists for:

- 2026-01-01 to 2026-01-03: 10 TB
- 2026-01-06 to 2026-01-10: 20 TB

Missing:

- 2026-01-04 to 2026-01-05

Expected behavior with autofill:

- Jan 4–5 are filled as 10 TB
- Jan 6–10 remain 20 TB
- autofill does not smear 10 TB over Jan 6–10

---

## Template RT-22 — Single missing day inherits previous known value only

### Intent

Verifies directional autofill behavior: the missing day must inherit from the most recent prior known snapshot, not from a later one.

### Generic pattern

Daily data exists for:

- day 1 with value A
- day 3 with value B

Missing:

- day 2

Expected behavior with autofill:

- missing day inherits value A
- missing day must not inherit value B
- total reflects A + A + B, or the resource equivalent

### StorageHotel example template

Scenario: SH-22 — Single missing day inherits previous known value only  
Period: 2026-01-01 to 2026-01-03

Quota data exists for:

- 2026-01-01: 10 TB
- 2026-01-03: 20 TB

Missing:

- 2026-01-02

Expected behavior with autofill:

- Jan 2 is filled as 10 TB, not 20 TB
- total = (10 + 10 + 20) TB-days priced correctly

---

## Template RT-23 — Autofill applies per resource independently

### Intent

Verifies that autofill is computed per selected resource independently and does not contaminate other resources or shared invoice calculations.

### Generic pattern

At least two resources are selected.

Resource A:

- complete coverage

Resource B:

- incomplete coverage with fillable gaps

Expected behavior:

- without autofill: invoice fails because one selected resource is incomplete
- with autofill: invoice succeeds
- complete resource remains unchanged
- incomplete resource gets only its own missing days filled
- each line total remains resource-specific and correct

### StorageHotel example template

Scenario: SH-23 — Autofill applies per resource independently  
Period: 2026-01-01 to 2026-01-05

Resource A:

- complete quota coverage for all 5 days at 10 TB

Resource B:

- quota for Jan 1–2 and Jan 5 only at 10 TB
- missing Jan 3–4

Expected behavior:

- without autofill: invoice fails because resource B is incomplete
- with autofill: invoice succeeds
- resource A is unchanged
- resource B gets Jan 3–4 filled
- both line totals are correct

---

## Template RT-25 — Multiple gaps pick the correct last known value for each missing segment

### Intent

Verifies that each missing segment inherits from the correct immediately prior explicit segment, even when values change multiple times across the same billing period.

### Generic pattern

Daily data exists for alternating explicit and missing segments:

- explicit segment A
- missing segment
- explicit segment B
- missing segment
- explicit segment C

Expected behavior with autofill:

- first missing segment inherits A
- second missing segment inherits B
- final explicit segment stays C
- line total reflects the exact segment structure
- autofill metadata correctly marks only the inherited days

### StorageHotel example template

Scenario: SH-25 — Multiple gaps pick the correct last known quota for each missing segment  
Period: 2026-01-01 to 2026-01-12  
Resource: storage-hotel-01 (KB)

Prices:

- P1: effective Jan 1+: normal=500, discount=400, threshold=10 TB

Quota records:

- Jan 1–2: 10 TB
- Jan 3–4: missing
- Jan 5–6: 12 TB
- Jan 7–8: missing
- Jan 9–12: 15 TB

Expected autofill:

- Jan 3–4 inherit 10 TB from Jan 2
- Jan 7–8 inherit 12 TB from Jan 6
- Jan 9–12 remain 15 TB from explicit records

Reference table:

| Day        | Quota (TB) | Source   | Price  | Discount? | Formula         | Daily Cost             |
|------------|------------|----------|--------|-----------|-----------------|------------------------|
| 2026-01-01 | 10         | explicit | 400.00 | yes       | 10 × 400 / 365  | 10.9589041095890410... |
| 2026-01-02 | 10         | explicit | 400.00 | yes       | 10 × 400 / 365  | 10.9589041095890410... |
| 2026-01-03 | 10         | autofill | 400.00 | yes       | 10 × 400 / 365  | 10.9589041095890410... |
| 2026-01-04 | 10         | autofill | 400.00 | yes       | 10 × 400 / 365  | 10.9589041095890410... |
| 2026-01-05 | 12         | explicit | 400.00 | yes       | 12 × 400 / 365  | 13.1506849315068493... |
| 2026-01-06 | 12         | explicit | 400.00 | yes       | 12 × 400 / 365  | 13.1506849315068493... |
| 2026-01-07 | 12         | autofill | 400.00 | yes       | 12 × 400 / 365  | 13.1506849315068493... |
| 2026-01-08 | 12         | autofill | 400.00 | yes       | 12 × 400 / 365  | 13.1506849315068493... |
| 2026-01-09 | 15         | explicit | 400.00 | yes       | 15 × 400 / 365  | 16.4383561643835616... |
| 2026-01-10 | 15         | explicit | 400.00 | yes       | 15 × 400 / 365  | 16.4383561643835616... |
| 2026-01-11 | 15         | explicit | 400.00 | yes       | 15 × 400 / 365  | 16.4383561643835616... |
| 2026-01-12 | 15         | explicit | 400.00 | yes       | 15 × 400 / 365  | 16.4383561643835616... |

Line total (full precision):

- (4 × 10 × 400 / 365)
- (4 × 12 × 400 / 365)
- (4 × 15 × 400 / 365)
- = 162.1917808219178082...

Line total (rounded): 162.19  
Invoice total: 162.19

---

# Additional Shared Complex Tests Every Resource Should Usually Have

The old StorageHotel scenarios are useful, but not sufficient alone.

For each new resource type, Claude should usually also create templates or concrete tests for the following.

## RT-30 — First day missing with no prior snapshot fails even with autofill

Intent:

- verify that autofill never invents a value without prior known data

Expected behavior:

- invoice generation fails for that resource
- failure explains no prior snapshot exists for autofill

---

## RT-31 — Price change inside autofilled gap still resolves per day

Intent:

- verify that autofill fills usage, but price resolution still happens independently for each day

Expected behavior:

- missing days inherit usage from prior snapshot
- each day still resolves the correct effective-dated price
- totals reflect both autofill and price split behavior

---

## RT-32 — Explicit resource selection and autofill together

Intent:

- verify that autofill behavior works correctly when invoice generation targets explicitly selected resources only

Expected behavior:

- only selected resources are evaluated
- unselected resources never contribute cost
- selected resources still fail or autofill according to flags

---

## RT-33 — Finalized invoice remains unchanged after source usage changes

Intent:

- verify that later changes to daily snapshots do not affect finalized invoices

Expected behavior:

- finalized invoice totals and `InvoiceDailyCost` rows stay unchanged
- regenerated later draft invoice may differ, but finalized one does not

---

## RT-34 — Overlapping price rows fail even if usage data is valid

Intent:

- verify configuration failure is caught before accepting the result as a valid invoice

Expected behavior:

- invoice generation fails with clear price-overlap error
- no finalized invoice is produced from invalid price configuration

---

# How Claude Should Name These Tests

Claude should prefer descriptive names that encode the behavior.

Examples:

- `test_storage_hotel_invoice_generation_fails_when_middle_days_are_missing_without_autofill`
- `test_storage_hotel_autofill_uses_last_known_quota_for_middle_gap`
- `test_virtual_machine_autofill_does_not_override_later_explicit_snapshot`
- `test_resource_invoice_generation_applies_autofill_per_resource_independently`
- `test_storage_hotel_multiple_gaps_use_correct_last_known_quota_per_segment`

Do not use opaque names like:

- `test_case_1`
- `test_sh_18`
- `test_complex_invoice`

Scenario codes may appear in comments or docstrings, but behavior must be obvious from the test name.

---

# Test Construction Rules

When Claude implements a concrete test from these templates, it should:

- arrange data explicitly by day or by clearly defined day ranges
- avoid hidden factory defaults that obscure billing inputs
- assert both failure and success branches when a flag changes behavior
- assert `InvoiceDailyCost` row count
- assert exact days that were autofilled
- assert normalized usage values on representative days
- assert exact Decimal totals where practical
- assert rounded customer-visible totals when relevant
- assert line totals and invoice totals separately
- assert metadata persisted for autofill and selection behavior

When the behavior is subtle, Claude should also assert representative daily rows, not only the final total.

---

# Resource-Specific Extensions

This file defines shared templates, not the full test plan for any given resource.

Each resource type must add tests for its own unique concerns.

Examples:

StorageHotel:

- threshold discount boundaries
- TB normalization rules
- quota unit conversion edge cases

VirtualMachine:

- multiple pricing dimensions such as CPU, RAM, and disk
- missing one dimension inside a daily snapshot
- changes in one dimension without changes in others

Future resources:

- custom normalization logic
- tiered pricing
- capacity floors or ceilings
- special lifecycle billing boundaries

If a resource has billing rules that do not fit these templates, create resource-specific templates in addition to this file instead of forcing a bad abstraction.

---

# Relationship to Other Claude Docs

Use this document together with:

- `.claude/docs/TESTING.md` for overall testing strategy and pytest conventions
- `.claude/docs/BILLING.md` for shared billing rules
- `.claude/docs/API.md` when endpoint behavior also needs write-operation tests
- `docs/PRP/` for resource-specific domain truth

This file should help Claude create good tests faster, but it must not replace billing or resource PRPs as the source of truth.
