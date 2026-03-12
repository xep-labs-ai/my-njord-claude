## Doc Purpose

Defines the shared billing rules, invoice generation workflow, and billing-selection behavior for all resources derived from `ResourceModel`.

## Read this document when

- Implementing or changing invoice generation logic
- Adding support for billing a new `ResourceModel`
- Implementing resource selection for invoice generation
- Implementing missing-data behavior, pricing resolution, or invoice snapshots
- Writing billing service tests

## Do not read this document when

- Working only on REST endpoint wiring without changing billing rules
- Working on resource-specific ingestion details
- Working on unrelated Django project structure or testing conventions
- Looking for resource-specific billing fields or unit conversion rules

# Billing Rules

## Purpose

This document defines the shared billing model for the Django Invoice API.

The billing system must be:

- deterministic
- explainable
- auditable
- reproducible after invoice finalization
- extensible across multiple resource types

This document defines only the **shared billing workflow**.

Resource-specific billing details such as:

- daily usage fields
- unit normalization
- resource-specific validation
- resource-specific pricing dimensions

must be defined in the corresponding resource PRP or resource billing documentation.

---

## Core Billing Model

Billing is based on these principles:

- billing happens per resource, per day
- only resources derived from `ResourceModel` are billable through the shared billing engine
- each resource type provides a daily snapshot model used for billing
- pricing is effective-dated
- invoice generation persists daily billing snapshots for auditability
- finalized invoices are immutable

The billing engine must support multiple resource types without changing the core invoice-generation workflow.

---

## Supported Billing Scope

Invoice generation may target:

- all billable resources for a `BillingAccount`
- all resources of one resource type for a `BillingAccount`
- multiple resource types for a `BillingAccount`
- one or more explicitly selected resources for a `BillingAccount`

Examples:

- all `ResourceModel` instances for account A
- only `StorageHotel` resources for account A
- only `VirtualMachine` resources for account A
- only `GPUResource` resources for account A
- a custom selection of specific resources for account A

This selection behavior is part of the invoice-generation request and must be stored in invoice metadata for auditability.

---

## Invoice Generation Inputs

To generate an invoice, the system needs:

- `billing_account_id`
- `period_start`
- `period_end`
- assigned price list
- billing selection scope
- billable resources matching the selection scope
- daily usage snapshots for each selected resource
- effective-dated pricing rows

Optional flags:

- `force`
- `autofill_missing_days`

Optional selection inputs:

- `resource_types`
- `resource_ids`

---

## Billing Selection Model

Billing selection must be explicit.

The engine should support a selection contract conceptually equivalent to:

- `scope = "all_resources"`
- `scope = "resource_types"`
- `scope = "explicit_resources"`

### All resources

Bills all billable resources belonging to the billing account during the selected period.

### Resource types

Bills all billable resources belonging to the billing account whose concrete model type is included in the requested set.

Example:

- `["StorageHotel"]`
- `["VirtualMachine"]`
- `["StorageHotel", "VirtualMachine"]`

### Explicit resources

Bills only the explicitly selected resources.

This must support selecting one or more concrete resources, potentially across resource types, as long as all selected resources belong to the same billing account.

### Validation rules

Invoice generation must fail if:

- selected resources do not belong to the provided billing account
- requested resource types are unknown or unsupported
- the selection is empty when explicit selection is required
- the same resource is effectively selected more than once through conflicting selection inputs
- the selection contract is ambiguous

The selection used to create the invoice must be persisted in invoice metadata.

---

## Billable Resource Rule

A resource is billable for a given day only if:

- it is a concrete resource derived from `ResourceModel`
- `billing_account_id` is not null
- `status == ACTIVE`
- it is included by the invoice selection
- it is valid for billing on that billed day

Resources that are:

- unassigned
- retired
- excluded by selection
- deleted or otherwise not billable on the billed day

must not contribute cost.

If the system later supports effective start/end lifecycle dates, billability must be resolved per day.

---

## Daily Processing Model

Billing is evaluated one day at a time.

For each day in the invoice range, and for each selected billable resource:

1. resolve whether the resource is billable on that day
2. resolve usage snapshot for that day
3. normalize resource-specific usage into the billable unit(s)
4. resolve effective price for that day
5. apply any shared or resource-specific pricing rules
6. calculate daily cost
7. persist a daily invoice snapshot row

This daily approach is the shared foundation that supports:

- arbitrary invoice ranges
- multiple resource types
- price changes mid-period
- future changes in billing dimensions
- transparent debugging
- reproducible finalized invoices

---

## Day Resolution

The invoice date range is inclusive.

If invoice period is:

- `2026-01-01`
- `2026-01-31`

then 31 daily evaluations must happen for each selected resource that is billable during those days.

All billing date logic uses `Europe/Oslo`.

---

## Usage Resolution

Each resource type must define:

- which daily snapshot model is used
- which fields are required for billing
- how raw snapshot values are normalized into billable units
- whether resource-specific pricing modifiers exist

### Normal mode

Load the required daily snapshot for `(resource, date)`.

If missing:

- fail invoice generation

### Autofill mode

If `autofill_missing_days=true`:

- carry forward the last known valid billing snapshot or billing-relevant values before the missing day
- if no prior valid snapshot exists for the resource, fail for that resource

Autofill behavior must be defined carefully per resource type.  
If a resource has multiple billing dimensions, autofill must use the last known complete billing state, not a partial state.

### Force mode

If `force=true`:

- allow generation to proceed when allowed by the implementation policy
- mark invoice metadata as incomplete
- record missing-day details in metadata

### Combined flags

When both `force=true` and `autofill_missing_days=true`, autofill takes priority first.

### Default rule

If both `force=false` and `autofill_missing_days=false`, missing required billing data is fatal.

---

## Resource-Specific Normalization

The shared billing engine must not hardcode `StorageHotel` assumptions.

Instead, each resource type must define how daily snapshots are normalized into billable values.

Examples:

- `StorageHotel` may normalize quota into TB
- `VirtualMachine` may normalize CPU, RAM, and disk capacity into one or more billable dimensions
- `GPUResource` may normalize GPU count, VRAM, or accelerator class

Normalization rules must be deterministic and testable.

Resource-specific unit conversion helpers should live in the resource domain, or in shared utilities only when genuinely cross-resource.

---

## Price Resolution

For each billed resource and billed day, find the applicable `ResourcePrice` row where:

- the price row matches the resource type and pricing dimensions required by that resource
- `effective_from <= day`
- `effective_to is null or day <= effective_to`

If no row exists:

- fail invoice generation

If multiple rows overlap:

- treat as invalid configuration
- this must be prevented by constraints and validation earlier

Price resolution must be explainable from persisted invoice snapshot data.

---

## Pricing Rules

The billing engine supports shared pricing orchestration, but pricing formulas may differ by resource type.

Shared requirements:

- pricing is resolved per day
- pricing is based on effective-dated configuration
- pricing must be deterministic
- pricing inputs used for billing must be reconstructible from persisted invoice data

Resource-specific pricing examples:

- `StorageHotel`: yearly price per TB
- `VirtualMachine`: yearly or monthly price by CPU, RAM, and disk dimensions
- future resources: any deterministic formula defined by their billing specification

Shared billing orchestration must not assume a single billing unit across all resource types.

---

## Daily Cost Formula

There is no single formula that must apply to every resource type.

Instead:

daily_cost = resource_type_specific_daily_cost(resource, day, normalized_usage, resolved_price)

However, all resource-specific formulas must follow these rules:

- use `Decimal`
- be deterministic
- be based only on resolved billing inputs for that day
- be reproducible from stored invoice snapshots

For yearly prorated pricing models, a resource type may use:

daily_cost = billable_quantity * yearly_price / days_in_year(day)

If an invoice spans multiple years, each day uses the divisor for its own year.

---

## Leap Year Decision

For any pricing rule that prorates by year, use actual days in year.

The `days_in_year(day)` helper returns:

- `366` for leap years
- `365` for non-leap years

based on the specific billed day.

This helper belongs in shared billing utilities.

---

## Invoice Total

Invoice total is the sum of all daily costs for all included resources.

invoice_total = Σ daily_cost

Invoice lines should usually aggregate totals per resource.

If the domain later requires a different line aggregation strategy, that must be explicitly defined without changing the underlying daily snapshot model.

---

## Snapshot Persistence

For reproducibility, invoice generation must persist the data required to explain the invoice later.

### Invoice-level snapshot

Persist invoice metadata including at least:

- billing account
- period start
- period end
- selection scope used
- selected resource types if applicable
- selected resource IDs if applicable
- whether `force` was used
- whether `autofill_missing_days` was used
- whether the invoice is incomplete
- missing-data details when relevant

### Line-level snapshot

Per billed resource:

- resource reference
- resource type
- total cost
- human-readable description
- summary billing metadata useful for debugging

### Daily-level snapshot

Per billed resource per day:

- resource reference
- resource type
- billed day
- normalized usage values used for billing
- price used
- pricing modifiers used
- daily cost
- metadata about autofill or missing-data handling when relevant

This daily snapshot is the source of truth for later debugging and auditing.

---

## Rounding Strategy

Use `Decimal` internally.

Recommended approach:

- avoid unnecessary intermediate rounding
- round customer-visible totals to 2 decimals NOK
- use one project-wide rounding rule

Suggested default:

- `ROUND_HALF_UP`

The rounding policy must be consistent across resource types.

---

## Missing Data Behavior Matrix

### Default

- missing required daily billing data -> fail

### `autofill_missing_days=true`

- missing day -> carry forward previous valid billing state
- no prior valid billing state exists -> fail for that resource
- invoice metadata should record that autofill was used

### `force=true`

- missing day -> continue only according to implementation policy
- invoice metadata marks result incomplete

### `force=true` + `autofill_missing_days=true`

- autofill takes priority first
- autofill fills what it can
- if no prior valid billing state exists, resource still fails unless force-policy explicitly allows partial continuation

---

## Draft and Finalized Behavior

### Draft invoice

- may be recalculated
- may be deleted and rebuilt internally
- not yet final

### Finalized invoice

- immutable
- no recalculation
- snapshot rows are fixed
- must remain reproducible even if source pricing or usage data later changes

---

## Resource-Type Extension Contract

A new billable resource type must define:

- concrete resource model derived from `ResourceModel`
- daily snapshot model
- resource-specific normalization rules
- pricing dimensions and matching rules
- daily cost formula
- missing-data rules if they differ from the shared defaults
- invoice snapshot expectations
- tests for selection, billing, and immutability

The shared billing engine should require only this contract, not custom orchestration logic per resource whenever possible.

---

## Example Billing Selections

### Example 1: invoice all resources for a billing account

- billing account: `BA-001`
- selection scope: `all_resources`

This includes all active billable resources for the account during the period.

### Example 2: invoice only StorageHotel resources

- billing account: `BA-001`
- selection scope: `resource_types`
- resource types: `["StorageHotel"]`

This excludes `VirtualMachine` and all other resource types.

### Example 3: invoice StorageHotel and VirtualMachine only

- billing account: `BA-001`
- selection scope: `resource_types`
- resource types: `["StorageHotel", "VirtualMachine"]`

This includes both types and excludes all others.

### Example 4: invoice explicit resources

- billing account: `BA-001`
- selection scope: `explicit_resources`
- resource IDs: `[101, 205, 333]`

Only those resources are billed, regardless of other billable resources on the account.

---

## Example Shared Workflow

Example invoice request:

- billing account: `BA-001`
- period: `2026-01-01` to `2026-01-31`
- selection scope: `resource_types`
- resource types: `["StorageHotel", "VirtualMachine"]`
- `autofill_missing_days=true`

Shared workflow:

1. resolve selected resources for the billing account
2. evaluate each selected resource day by day
3. load daily snapshot data
4. autofill missing days when allowed
5. normalize usage according to resource type
6. resolve effective price for each resource/day
7. compute daily cost with the resource-specific formula
8. persist daily invoice cost rows
9. aggregate invoice lines per resource
10. compute invoice total
11. persist invoice metadata including selection rules used

---

## Non-Goals of This Document

This document does not define:

- REST endpoint shapes
- serializer design
- router registration
- resource-specific ingestion APIs
- resource-specific unit conversion constants
- resource-specific pricing formulas in full detail

Those belong in:

- `.claude/docs/API.md`
- `.claude/docs/STRUCTURE.md`
- resource PRPs
- resource-specific implementation docs
