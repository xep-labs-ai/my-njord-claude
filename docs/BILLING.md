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
- `explicit_resources`

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

- `["storage_hotel"]`
- `["virtual_machine"]`
- `["storage_hotel", "virtual_machine"]`

### Explicit resources

Bills only the explicitly selected resources.

This must support selecting one or more concrete resources, potentially across resource types, as long as all selected resources belong to the same billing account.

Input format uses `(resource_type, resource_id)` pairs:

```json
explicit_resources = [
  {"resource_type": "storage_hotel", "resource_id": 101},
  {"resource_type": "virtual_machine", "resource_id": 205}
]
```

### Validation rules

Invoice generation must fail if:

- selected resources do not belong to the provided billing account
- requested resource types are unknown or unsupported (Valid resource types are defined in the Resource Type Registry (`001-billing-engine.prp.md`). Unknown `resource_type` values must be rejected with 400 Bad Request at both invoice generation and `ResourcePrice` creation.)
- the selection is empty when explicit selection is required
- the same resource is effectively selected more than once through conflicting selection inputs
- the selection contract is ambiguous

The selection used to create the invoice must be persisted in invoice metadata.

---

## Billable Resource Rule

A resource is billable for a given day only if:

- it is a concrete resource derived from `ResourceModel`
- `billing_account_id` is not null
- `active_from <= day`
- `active_to IS NULL OR day <= active_to`
- it is included by the invoice selection

Note: `billing_account.make_invoice = True` is a pre-condition checked before resource evaluation (see Pre-flight Validation), not a per-day condition.

Resources that are:

- unassigned
- outside their active billing window
- excluded by selection

must not contribute cost.

Billability is resolved **per day** using the `active_from` and `active_to` fields from ResourceModel. The `status` field represents the resource's current lifecycle state but does not determine historical billability.

The billing engine uses the `billing_objects` manager for all resource queries during invoice generation. The default manager is only used by CRUD API endpoints. For explicit resource ownership validation, `billing_objects` is also used so that soft-deleted (historically billable) resources can be explicitly selected.

---

## Pre-flight Validation

Before any resource selection or per-day evaluation happens:

- `billing_account.make_invoice` must be `True`. If `make_invoice = False`, invoice generation must fail immediately with a billing domain error (422).

This check is intentionally placed before resource selection to fail fast when the billing account has invoicing disabled.

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

A single-day invoice where `period_start == period_end` is valid and produces exactly one daily evaluation.

All billing date logic uses `Europe/Oslo`.

---

## Non-billable Days Rule

Non-billable days produce **no `InvoiceDailyCost` row**.

Non-billable days include:

- days before `active_from`
- days after `active_to`
- any day outside the resource's billable window per the Billable Resource Rule

Auditability for the active billing window and billed day count may be preserved in invoice-line or invoice-level metadata.

**Clarification:** This rule applies to days outside the resource's billing window (`active_from`/`active_to`). It is distinct from billable days where snapshot data is missing -- under `force=true`, those days produce a zero-cost `InvoiceDailyCost` row with `autofilled=true` (zero is assigned as a fallback because no snapshot data exists, not because a prior value was carried forward). See Force Mode behavior.

---

## Zero-Billable-Day Exclusion

Resources with zero billable days in the selected period produce no `InvoiceLine` and no `InvoiceDailyCost` rows. They are treated as if they were not selected.

---

## v1 Limitation: Billing Account Resolution

In v1, the billing engine uses the resource's **current** `billing_account` at invoice-generation time. Historical assignment is not tracked. If a resource's `billing_account` is changed after historical usage has been captured, invoice generation for past uninvoiced periods will use the current `billing_account`, not historical ownership. Previously generated draft invoices for affected periods should be regenerated before finalization. Already finalized invoices remain immutable.

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
- if no prior valid snapshot exists for the resource, fail the entire invoice generation

Autofill behavior must be defined carefully per resource type.  
If a resource has multiple billing dimensions, autofill must use the last known complete billing state, not a partial state.

### Force mode

If `force=true` and `autofill_missing_days=false`:

- resources with missing days are billed at **zero** for those missing days
- the invoice line is included with zero cost
- missing days must be reported in the invoice generation response

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
- `VirtualMachine`: yearly price per CPU count, per GB RAM, and per GB disk
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

## Multi-Dimension Resource Aggregation

There is **one `InvoiceDailyCost` row per resource per day**.

For multi-dimension resources (e.g., VirtualMachine), the per-dimension breakdown is stored in `InvoiceDailyCost.metadata` under fields such as `normalized_usage`, `resolved_prices`, and `dimension_costs`.

### Aggregation Rules

- `InvoiceDailyCost.daily_cost` = sum of all per-dimension daily costs for that resource on that day
- `InvoiceLine.total_cost` = sum of `InvoiceDailyCost.daily_cost` across all billed days for that resource

**Authoritative `InvoiceDailyCost.metadata` shape** (nested, keyed by pricing dimension):

Required fields on every `InvoiceDailyCost` row:

- `normalized_usage` — object keyed by pricing dimension
- `resolved_prices` — object keyed by pricing dimension, each entry contains `price_per_unit_year`, `currency`, `discount_applied`
- `dimension_costs` — object keyed by pricing dimension, each value is the per-dimension daily cost as a Decimal string
- `autofilled` — BooleanField, default False. True when usage was autofilled (carry-forward from prior snapshot) or when force-mode billed a missing day at zero. False when usage came from a real ingested snapshot.

StorageHotel example:

```json
{
  "normalized_usage": {"quota_tb": "120"},
  "resolved_prices": {
    "quota_tb": {"price_per_unit_year": "400", "currency": "NOK", "discount_applied": true}
  },
  "dimension_costs": {"quota_tb": "131.5068493150"},
  "autofilled": false
}
```

VirtualMachine example:

```json
{
  "normalized_usage": {"cpu_count": "8", "ram_gb": "32", "disk_gb": "500"},
  "resolved_prices": {
    "cpu_count": {"price_per_unit_year": "300", "currency": "NOK", "discount_applied": false},
    "ram_gb": {"price_per_unit_year": "40", "currency": "NOK", "discount_applied": false},
    "disk_gb": {"price_per_unit_year": "2", "currency": "NOK", "discount_applied": false}
  },
  "dimension_costs": {"cpu_count": "6.5753424657", "ram_gb": "3.5068493150", "disk_gb": "2.7397260273"},
  "autofilled": false
}
```

**Dual-storage strategy for `autofilled`:**

`autofilled` exists in two places:

1. As a dedicated `BooleanField(default=False)` column on the `InvoiceDailyCost` model — this is the queryable source of truth and supports direct filtering and aggregation queries
2. As a required key in `InvoiceDailyCost.metadata` — for audit self-containment, ensuring the snapshot is complete and reproducible

The column is the primary source; the metadata copy ensures audit transparency. See `002-resource-models.prp.md` and review-clarifications-10 C-1 for details.

**`daily_cost` field meaning:**

`InvoiceDailyCost.daily_cost` = sum of all values in `metadata.dimension_costs` for that row.

`InvoiceLine.total_cost` = sum of `InvoiceDailyCost.daily_cost` across all billed days for that resource.

---

## Invoice Total

Invoice total is calculated in two steps:

**Step 1: Aggregate daily costs into InvoiceLine totals**

Sum all `InvoiceDailyCost.daily_cost` values grouped by `InvoiceLine` → produces `InvoiceLine.total_cost`

**Step 2: Aggregate InvoiceLine totals into Invoice total**

Sum all `InvoiceLine.total_cost` values, then round to 2 decimal places using `ROUND_HALF_UP` → produces `Invoice.total_amount`

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
- currency
- total cost
- `description` — `InvoiceLine.description` is a frozen human-readable description captured at invoice generation time. Construction rule: use the resource's `name` if it is present and non-blank; if `name` is null or blank, fall back to `{ResourceType} #{resource_id}` where `{ResourceType}` is the Django model class name in PascalCase (e.g., `StorageHotel #101`, not `storage_hotel #101`). Once stored, the description must not be recomputed from the live resource. See also `002-resource-models.prp.md`.
- `resource_snapshot` — `InvoiceLine.metadata` must include a required `resource_snapshot` key containing the minimal frozen identifying attributes needed for audit and display. `resource_snapshot` is not a top-level field on `InvoiceLine`; it is a required structured value stored inside `InvoiceLine.metadata`. This is the primary audit snapshot and must be present for all InvoiceLines.
- summary billing metadata useful for debugging

### Daily-level snapshot

Per billed resource per day:

- resource reference
- resource type
- currency
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

Rounding happens at the invoice level only:

- `InvoiceDailyCost.daily_cost` uses 10 decimal places (`decimal_places=10`)
- `InvoiceLine.total_cost` uses 10 decimal places (`decimal_places=10`)
- `Invoice.total_amount` is rounded to 2 decimal places NOK (customer-visible total)

Rounding process:

- Sum all full-precision `InvoiceLine.total_cost` values
- Round once at the invoice level to produce `Invoice.total_amount`

Required rounding method:

- `ROUND_HALF_UP`

The rounding policy must be consistent across resource types.

---

## Currency Consistency

`Invoice.currency` is set at generation start to `billing_account.price_list.currency` and frozen for the invoice's lifetime. In v1 this is always `"NOK"`. `InvoiceLine.currency` and `InvoiceDailyCost.currency` are propagated from `Invoice.currency` during generation. No per-price currency validation is needed: all ResourcePrices in a PriceList inherit their currency from `PriceList.currency` by construction.

This is a service-layer invariant that must be maintained during invoice generation.

**v1 currency constraint:** All pricing in v1 uses NOK. The billing engine must validate that all resolved `ResourcePrice` rows for an invoice use the same currency as `Invoice.currency`. A currency mismatch is a fatal billing error.

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

### `force=false` + `autofill_missing_days=true` + no prior snapshot

- The **entire invoice generation fails** (fatal error -- not a per-resource skip)
- This means the entire invoice transaction is rolled back. No invoice is created, no InvoiceLines persist, no InvoiceDailyCost rows persist.
- Example: if resource A has complete data and resource B has no prior snapshot, and `force=false`, the entire invoice generation fails -- resource A's valid data does not produce a partial invoice.

### `force=true` + `autofill_missing_days=true`

- autofill takes priority first
- autofill fills what it can
- if no prior valid billing state exists: bill the resource-day at **zero cost**, record the condition in `missing_data_summary`, mark the invoice `incomplete=true`

---

## Duplicate Invoice Prevention

There must be at most one draft invoice per `(billing_account, period_start, period_end, selection_scope, selection_fingerprint)`.

`selection_fingerprint` is a deterministic hash of the canonical selection payload (resource types and explicit resources, each sorted before hashing). See `001-billing-engine.prp.md` for the complete fingerprint algorithm and canonical payload schema.

A matching finalized invoice must block regeneration entirely (finalized invoices are immutable).

A matching draft is replaced atomically when `force=true`.

The billing engine uses a PostgreSQL advisory lock to prevent concurrent generation for the same invoice period. See `001-billing-engine.prp.md` for the locking strategy.

**v1 limitation — cross-scope double-billing risk:** v1 does not prevent the same resource from appearing in multiple invoices for the same period under different selection scopes. Operators must not generate invoices with overlapping resource selections for the same billing account and period. Finalization is the operational safeguard — do not finalize overlapping invoices.

---

## Invoice Flags

`incomplete` is a dedicated `BooleanField` on the `Invoice` model (not metadata-only). It is exposed as a top-level field in API responses and is directly filterable in list queries. `Invoice.metadata` may still contain `missing_data_summary` and supporting details when `incomplete=true`.

`provisional` is stored in `Invoice.metadata`. It is available in detail and generate responses but excluded from the list response because `metadata` is excluded from the list serializer as a whole -- no separate exclusion logic is needed for `provisional`.

---

## Draft and Finalized Behavior

### Draft invoice

- may be updated by calling `POST /generate` with `force=true` (dedicated `recalculate` endpoint is deferred to v2)
- may be deleted and rebuilt internally
- not yet final

When deleting a draft Invoice for replacement, the delete cascades to its InvoiceLines and InvoiceDailyCosts via Django's CASCADE delete behavior. No manual cleanup of child records is required.

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
- resource types: `["storage_hotel"]`

This excludes `VirtualMachine` and all other resource types.

### Example 3: invoice StorageHotel and VirtualMachine only

- billing account: `BA-001`
- selection scope: `resource_types`
- resource types: `["storage_hotel", "virtual_machine"]`

This includes both types and excludes all others.

### Example 4: invoice explicit resources

- billing account: `BA-001`
- selection scope: `explicit_resources`
- explicit_resources: `[{"resource_type": "storage_hotel", "resource_id": 101}, {"resource_type": "virtual_machine", "resource_id": 205}]`

Only those resources are billed, regardless of other billable resources on the account.

---

## Example Shared Workflow

Example invoice request:

- billing account: `BA-001`
- period: `2026-01-01` to `2026-01-31`
- selection scope: `resource_types`
- resource types: `["storage_hotel", "virtual_machine"]`
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
   - For each resource, create an InvoiceLine with aggregated costs
   - Set `InvoiceLine.description` from the resource's `name` if present and non-blank; otherwise use `{ResourceType} #{resource_id}` as a fallback (e.g., `StorageHotel #101`). Never recomputed from the live resource after generation.
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
- `.claude/docs/ARCHITECTURE.md`
- resource PRPs
- resource-specific implementation docs
