# Documentation Review — Clarification Questions (Round 2)

This file was generated from a second documentation audit after round 1 decisions were applied.
Each question includes the problem found, the options or proposal, and a blank **Answer** field for you to fill in.

Questions are grouped by priority: **model/schema blockers first**, then billing correctness, then API contract, then hygiene.

---

## MODEL / SCHEMA BLOCKERS

---

### AQ1 — `Invoice.total_cost` vs `Invoice.total_amount` field name conflict

**Status:** ANSWERED

**Problem:**
Two different field names are used for the invoice-level monetary total across docs:
- `002-resource-models.prp.md` calls it `total_cost`
- `001-billing-engine.prp.md` and `BILLING.md` call it `total_amount`
- `003-invoice-api.prp.md` response examples use `total_cost`

`InvoiceLine` also has a field named `total_cost`, so using the same name on Invoice creates additional confusion about which one gets rounded.

**Options:**
- (a) `Invoice.total_amount` (rounded, 2 decimals) + `InvoiceLine.total_cost` (full precision) — clearest semantic distinction
- (b) `Invoice.total_cost` (rounded) + `InvoiceLine.line_cost` or `InvoiceLine.cost` — rename the line field instead
- (c) `Invoice.total` and `InvoiceLine.total` — short names, no ambiguity since they are on different models

**Proposal:** Option (a). `total_amount` on Invoice for the rounded customer-visible total, `total_cost` on InvoiceLine for full-precision per-resource cost. Update `002-resource-models.prp.md` and `003-invoice-api.prp.md`.

**Answer:** option a

---

### AQ3 — `BillingAccount` model fields never defined

**Status:** ANSWERED

**Problem:**
`BillingAccount` is referenced everywhere as a core entity but no PRP defines its fields. Only its conceptual role is described: "represents the billing entity" (org, department, project) and "uses exactly one PriceList."

An implementer cannot create the model or the API without knowing the fields.

**Proposal:**
Minimum viable fields for v1:
- `id` (PK)
- `name` (CharField, required)
- `price_list` (FK to PriceList, required)
- `created_at` / `updated_at`

If BillingAccount needs CRUD endpoints in v1, they should be listed alongside its definition.

**Answer:** Use this new proposal inside this new block, the reason is that I know that this are going to be required fields: 

```
Recommended structure
BillingAccountBase (abstract)

Only generic fields that any billing system might need.

BillingAccountBase (abstract)

name
contact_point
contact_email
contact_telephone_number
customer_number
make_invoice
internal_customer

Purpose:

BillingAccountBase defines generic account identity and contact information
that may be reused by other implementations of the billing system.

It should be implemented as an abstract Django model.

Why these fields stay generic:

Field	Reason
name	universal
contact_*	universal
customer_number	common ERP/customer mapping
make_invoice	generic billing control
internal_customer	generic internal/external distinction
BillingAccount (UiO implementation)

These fields are specific to the UiO / USIT environment.

BillingAccount

id
name
price_list
contact_point
contact_email
contact_telephone_number
customer_number
make_invoice
internal_customer

usit_contact_point
main_agreement_id
main_agreement_description
usit_accounting_place
usit_sub_project
ephorte
uio_unit

created_at
updated_at
UiO-specific field meaning
usit_contact_point
- operational contact inside USIT

main_agreement_id
main_agreement_description
- reference to the primary service agreement

usit_accounting_place
usit_sub_project
- accounting classification used for internal financial reporting

ephorte
- optional reference to UiO document archive / case system

uio_unit
- UiO organizational unit identifier
Important rule to keep

You already mentioned this in the PRP, but I would keep it explicit:

Each BillingAccount must use exactly one PriceList.

So:

price_list
- FK to PriceList
- required
Final model layering

Conceptually the system becomes:

BillingAccountBase (abstract)
        │
        ▼
BillingAccount (UiO implementation)
        │
        ▼
Resources
(StorageHotel, VirtualMachine, ...)
        │
        ▼
Invoices

This separation is clean and future-proof.

If one day the billing engine is reused outside UiO, you could simply implement:

CompanyBillingAccount(BillingAccountBase)

without carrying the UiO accounting fields.
```

---

### AQ4 — `PriceList` model fields never defined

**Status:** ANSWERED

**Problem:**
`PriceList` is referenced as the pricing container and `ResourcePrice` has a FK to it, but PriceList's own fields are never listed. It is unclear whether it has lifecycle status, effective dates, or is always considered active.

**Proposal:**
Minimum viable fields for v1:
- `id` (PK)
- `name` (CharField, required)
- `created_at` / `updated_at`

No status field in v1 — PriceLists are always active. A ResourcePrice's `effective_from`/`effective_to` controls validity.

**Answer:** this block is the answer:

```
Accept the proposal, with one refinement: `PriceList.name` should be unique in v1.

Decision:

Define `PriceList` with:

- `id`
- `name`
- `created_at`
- `updated_at`

Rules:

- `name` is required and unique
- `PriceList` has no status field in v1
- `PriceList` is the pricing container only
- price validity is determined by `ResourcePrice.effective_from` and `ResourcePrice.effective_to`

Reasoning:

- a minimal `PriceList` model is sufficient because lifecycle behavior already exists on `ResourcePrice`
- adding a status field to `PriceList` in v1 would duplicate pricing-validity semantics
- a unique `name` makes lookup, filtering, and administration simpler and deterministic
```

---

### AQ6 — `InvoiceDailyCost` unique constraint broken for multi-dimension resources

**Status:** ANSWERED

**Problem:**
The current unique constraint on `InvoiceDailyCost` is `(invoice_id, resource_type, resource_id, date)`. VirtualMachine produces 3 rows per resource per day (cpu_count, ram_gb, disk_gb). This violates the constraint — all 3 rows have the same `(invoice_id, resource_type, resource_id, date)`.

This directly contradicts the Q6 decision: "one row per dimension per day."

**Options:**
- (a) Add `pricing_dimension` as a first-class field on `InvoiceDailyCost` and update the unique constraint to `(invoice_id, resource_type, resource_id, date, pricing_dimension)` — consistent with per-dimension billing
- (b) One `InvoiceDailyCost` row per resource per day, with all dimension costs rolled into `metadata` — keeps the constraint but loses per-dimension first-class records

**Proposal:** Option (a). Adding `pricing_dimension` as a CharField on `InvoiceDailyCost` is the correct approach. For single-dimension resources (StorageHotel), the value is `quota_tb`. Update `002-resource-models.prp.md`.

**Answer:** option a is the answer

---

### AQ16 — `pricing_dimension` not a field on `InvoiceDailyCost`

**Status:** ANSWERED

**Problem:**
Directly related to AQ6. The `pricing_dimension` field is defined on `ResourcePrice` but is absent from `InvoiceDailyCost`. Without it as a first-class column:
- The unique constraint cannot include it
- Querying daily costs by dimension requires JSON extraction
- The audit trail for "which price was applied to which dimension on which day" is harder to trace

**Proposal:**
Add `pricing_dimension` (CharField) to `InvoiceDailyCost`. For StorageHotel rows: `quota_tb`. For VirtualMachine rows: `cpu_count`, `ram_gb`, or `disk_gb`. Update `002-resource-models.prp.md` and the unique constraint.

**Answer:** Accept proposal

---

## BILLING CORRECTNESS

---

### AQ2 — VM: `ram_mb` stored, `ram_gb` billed — conversion formula undefined

**Status:** ANSWERED

**Problem:**
VirtualMachineDailyUsage stores RAM as `ram_mb`. The billing dimension is `ram_gb`. The conversion formula is never documented.

- Decimal: `ram_mb / 1000 = ram_gb`
- Binary: `ram_mb / 1024 = ram_gib`

The StorageHotel PRP has explicit conversion constants. The VM PRP has none.

Similarly, `disks_total_gb` → `disk_gb`: is this 1:1 or is there a conversion?
And `cpu_count` → `cpu_count`: confirm 1:1.

**Proposal:**
Add a "Unit Conversion Rules" section to `virtual-machine.prp.md`:
- `ram_mb` → `ram_gb`: divide by 1024 (binary, consistent with how RAM is typically measured in VM contexts)
- `disks_total_gb` → `disk_gb`: 1:1 (no conversion)
- `cpu_count` → `cpu_count`: 1:1 (no conversion)

**Answer:** Accept proposal

---

### AQ15 — `ResourcePrice.effective_to`: inclusive or exclusive?

**Status:** ANSWERED

**Problem:**
`effective_to` on `ResourcePrice` is used in price resolution logic (`day <= effective_to`) which implies it is **inclusive**. But this is never explicitly stated in any pricing section. An implementer creating price rows needs to know: does `effective_to = 2026-01-31` mean the price is valid ON January 31, or only UNTIL January 31?

Also not stated: whether two `ResourcePrice` rows for the same `(price_list, resource_type, pricing_dimension)` are allowed to have overlapping date ranges.

**Proposal:**
Add to `001-billing-engine.prp.md` ResourcePrice section:
- `effective_to` is **inclusive** — the price is valid on that day
- `effective_to = null` means open-ended (no expiration)
- No two `ResourcePrice` rows for the same `(price_list, resource_type, pricing_dimension)` may have overlapping effective date ranges — enforced at the service layer

**Answer:** Accept proposal

---

### AQ17 — InvoiceLine aggregation for multi-dimension VMs: 1 line or 3 lines per VM?

**Status:** ANSWERED

**Problem:**
`InvoiceLine` is described as representing "one resource within an invoice." For VirtualMachine with 3 billing dimensions, it is unclear whether the invoice gets:
- 1 line per VM (total_cost = sum of all 3 dimensions across all days)
- 3 lines per VM (one per dimension)

This affects the model, the billing engine aggregation logic, and the API response shape.

**Options:**
- (a) 1 line per VM — `total_cost` is the aggregate across all dimensions and days; per-dimension breakdown lives in `metadata.total_quantity_by_dimension`
- (b) 3 lines per VM — one per dimension, each with its own `total_cost`, `pricing_dimension` set on the line

**Proposal:** Option (a). One line per resource keeps the invoice structure simple and consistent with single-dimension resources. Per-dimension detail is already captured at the `InvoiceDailyCost` level. The `metadata` field on InvoiceLine is already designed for this.

**Answer:** accept proposal

---

## API CONTRACT

---

### AQ5 — VM metadata keys inconsistent across documents

**Status:** ANSWERED

**Problem:**
Two documents describe VM `InvoiceLine.metadata` keys differently:

`virtual-machine.prp.md`:
- `total_cpu_days`
- `total_ram_mb_days` ← RAM in MB
- `total_disks_gb_days`

`002-resource-models.prp.md`:
- `cpu_count_days`
- `ram_gb_days` ← RAM in GB
- `disk_gb_days`

These are different names AND different units (MB-days vs GB-days). The billing dimension is `ram_gb`, so the aggregate should logically be in GB-days.

**Proposal:**
Standardize on `002-resource-models.prp.md` naming, using normalized billing-unit quantities:
- `cpu_count_days` (count × days)
- `ram_gb_days` (GB × days, converted from MB before aggregation)
- `disk_gb_days` (GB × days)

Update `virtual-machine.prp.md` to match.

**Answer:** accept proposal remembering that the ram conversion formula must be documented in the PRP as well (AQ2)

---

### AQ7 — `STRUCTURE.md` deleted but still referenced in several files

**Status:** ANSWERED

**Problem:**
RQ10 was answered: "I have just already removed. It is all inside ARCHITECTURE.md." But `STRUCTURE.md` is still referenced in:
- `.claude/agents/architect.md`
- `.claude/docs/ARCHITECTURE.md`
- `.claude/docs/CODING_RULES.md`
- `.claude/docs/BILLING.md`
- `.claude/skills/django-api-endpoint-pattern/SKILL.md`
- `.claude/skills/django-testing-pattern/SKILL.md`

These stale references will confuse Claude when it tries to read a file that does not exist.

**Proposal:**
Remove or replace all `STRUCTURE.md` references in those files. Where file placement guidance is needed, point to `ARCHITECTURE.md` instead.

**Answer:** acecpt proposal

---

### AQ8 — Duplicate prevention: no concurrency strategy defined

**Status:** ANSWERED

**Problem:**
The duplicate prevention key includes JSON fields (`selection_scope`, `selected_resource_types`, `explicit_resources`). PostgreSQL cannot enforce a unique constraint across JSON subfields natively. If two requests arrive simultaneously, both could pass the service-layer check before either commits.

**Options:**
- (a) Service-layer check with `SELECT ... FOR UPDATE` or PostgreSQL advisory lock within the generation transaction
- (b) Add a computed `selection_hash` column (a hash of the selection parameters) with a unique DB constraint on `(billing_account, period_start, period_end, selection_hash)` filtered to non-finalized invoices
- (c) Accept the race condition risk for v1 — document it as a known limitation

**Proposal:** Option (a) for v1. Use a PostgreSQL advisory lock keyed on `(billing_account_id, period_start, period_end)` within the invoice generation service. Document this in `001-billing-engine.prp.md`.

**Answer:** accept proposal a

---

### AQ9 — `billing_account` in API request: integer PK or external identifier?

**Status:** ANSWERED

**Problem:**
`003-invoice-api.prp.md` shows `"billing_account": "<id or identifier>"`. It is unclear whether the caller passes the database PK, a UUID, or a human-readable identifier like an account code.

**Options:**
- (a) Integer PK — simple for v1, consistent with DRF defaults
- (b) UUID PK — globally unique, better for external integrations
- (c) Separate `account_code` or `slug` field — human-readable, PK stays internal

**Proposal:** Option (a) for v1. Integer PK. The API uses it internally; if a slug is needed later it can be added as a filter without breaking the existing contract.

**Answer:**  accept proposal a with the following clarification in the following block:

```
Choose option (a) for v1.

The invoice API should accept the internal `BillingAccount` primary key as an integer in the request payload.

Decision:

- `billing_account` in invoice-generation requests is the integer primary key of `BillingAccount`
- it must reference an existing BillingAccount row
- business fields such as `name`, `customer_number`, or other external/accounting identifiers must not be used as the primary invoice-generation identifier in v1
```

---

### AQ10 — Resource CRUD and ingestion endpoints: request/response shapes undefined

**Status:** ANSWERED

**Problem:**
Both resource PRPs list endpoints (`POST /api/v1/storage-hotels/`, `PATCH /api/v1/storage-hotels/{id}/`, `POST /api/v1/storage-hotels/{id}/quota`, etc.) but define no request or response shapes, validation rules, or behavior. For ingestion specifically:
- Can you POST quota for a future date?
- Can you overwrite an existing snapshot for the same date?
- What fields are writable on resource creation?
- What fields are patchable?

**Proposal:**
Create a new `docs/PRP/004-resource-api.prp.md` covering StorageHotel and VirtualMachine CRUD and ingestion contracts. At minimum specify the ingestion endpoints since they directly feed the billing engine.

Alternatively, add a "API Contract" section to each resource PRP.

**Answer:** This folloing block is my answer:

```
Accept the proposal and use a dedicated API PRP.

Decision:

Create:

`docs/PRP/004-resource-api.prp.md`

This document should define the HTTP contract for resource CRUD and daily snapshot ingestion for v1.

Reasoning:

- request/response shapes, writable fields, patch behavior, and ingestion validation are API-contract concerns
- a dedicated PRP keeps these rules centralized and consistent across resource types
- ingestion directly affects billing correctness, so overwrite and validation rules must be explicit

`004-resource-api.prp.md` should define at minimum:

- create, list, retrieve, and patch request/response shapes
- writable vs read-only fields for each resource type
- ingestion request/response shapes
- duplicate snapshot behavior
- future-date policy
- status codes and validation failures

Recommended v1 ingestion rules:

- future-dated snapshots are not allowed
- if a snapshot already exists for the same resource and date, ingestion fails by default rather than overwriting
- overwrite/correction behavior, if needed later, should be defined explicitly rather than happening implicitly

The resource-specific PRPs should continue to define domain models and billing semantics, while `004-resource-api.prp.md` becomes the source of truth for the resource HTTP interface.
```

---

### AQ11 — `autofill` vs `autofill_missing_days` naming inconsistency

**Status:** ANSWERED

**Problem:**
`003-invoice-api.prp.md` uses `"autofill": true` in the request body example, but `BILLING.md`, `001-billing-engine.prp.md`, and the invoice metadata response all use `autofill_missing_days`.

**Proposal:**
Use `autofill_missing_days` everywhere, including in the API request body. Update `003-invoice-api.prp.md` request example.

**Answer:** accept proposal

---

### AQ12 — Draft replacement with `force=true`: delete or update in place?

**Status:** ANSWERED

**Problem:**
Multiple docs say a matching draft is "replaced atomically" when `force=true`, but the replacement mechanics are never defined:
- (a) Delete old draft + cascade delete its lines/daily-costs, create a fresh invoice with a new PK and new invoice number in one transaction — simplest, but changes PK and burns a sequence number
- (b) Update existing draft in place, delete and recreate lines/daily-costs — preserves PK and invoice number, but requires careful cascade logic
- (c) Soft-delete old draft (set status to REPLACED), create new one — preserves history but adds a new status

**Proposal:** Option (a). Delete old draft and all its children, create a new invoice. The old invoice number is not reused — gaps in the sequence are acceptable (already stated in the invoice number decision). Document this in `001-billing-engine.prp.md`.

**Answer:** accept proposal

---

### AQ13 — `InvoiceLine.billing_unit` for multi-dimension VMs

**Status:** ANSWERED

**Problem:**
`InvoiceLine` has a `billing_unit` field. For StorageHotel this is clearly `"TB"`. For VirtualMachine with 3 dimensions (cpu_count, ram_gb, disk_gb), there is no single billing unit that applies to the whole line.

**Options:**
- (a) `billing_unit` is nullable — leave it null for multi-dimension resources, dimension units are in metadata
- (b) Remove `billing_unit` from `InvoiceLine` entirely — unit information lives at the `InvoiceDailyCost` level (via `pricing_dimension`)
- (c) Store a composite string like `"cpu_count/ram_gb/disk_gb"` — awkward but explicit

**Proposal:** Option (a). Keep `billing_unit` nullable for v1. For StorageHotel it is `"quota_tb"`. For VirtualMachine it is `null` (dimension detail is in InvoiceDailyCost and metadata). Update `002-resource-models.prp.md`.

**Answer:** This following block is my proposal:

```
Choose option (b).

Remove `billing_unit` from `InvoiceLine`.

Reasoning:

- a single `billing_unit` does not fit multi-dimension resources such as VirtualMachine
- keeping it nullable would preserve a field that is not part of the true shared contract
- `InvoiceLine` is a summary row, while billing dimension and unit details belong in `InvoiceDailyCost` and structured metadata

Decision:

Remove the field and represent billing dimensions through metadata instead.

since the recommended metadata example is going to look similar to this:
```
Recommended metadata examples

For StorageHotel:

InvoiceLine.metadata = {
  "billing_dimensions": ["quota_tb"],
  "total_quantity_by_dimension": {
    "quota_tb_days": "3720"
  }
}

For VirtualMachine:

InvoiceLine.metadata = {
  "billing_dimensions": ["cpu_count", "ram_gb", "disk_gb"],
  "total_quantity_by_dimension": {
    "cpu_count_days": "248",
    "ram_gb_days": "992",
    "disk_gb_days": "15500"
  }
}
```
```

---

### AQ14 — `BILLING.md` Example 4 uses old plain-ID format

**Status:** ANSWERED

**Problem:**
`BILLING.md` Example 4 (explicit resource selection) still shows:
```
resource IDs: [101, 205, 333]
```
This uses the old plain-ID format replaced by typed `(resource_type, resource_id)` pairs in RQ5.

**Proposal:**
Update Example 4 to use the typed format:
```
explicit_resources: [
  {"resource_type": "storage_hotel", "resource_id": 101},
  {"resource_type": "virtual_machine", "resource_id": 205}
]
```

**Answer:** accept proposal

---

### AQ18 — Invoice number: assigned at draft creation or finalization?

**Status:** ANSWERED

**Problem:**
Invoice numbers follow `INV-YYYY-mm-NNNNN`. API response examples show `invoice_number` on draft invoices, implying it is assigned at creation. But this is never explicitly stated. Consequences:
- Draft replacement with `force=true` burns a sequence number (the replaced draft's number is abandoned)
- Gaps in the sequence will exist — are they acceptable?

**Proposal:**
State explicitly:
- Invoice numbers are assigned at **draft creation**
- Gaps in the monthly sequence from replaced or abandoned drafts are acceptable
- The replaced draft's number is not reused

**Answer:** Check this proposal instead:

```
Reject the proposal.

Decision:

- `invoice_number` must be assigned at finalization, not at draft creation
- draft invoices must not have a formal invoice number
- the invoice-number sequence applies only to finalized invoices
- once assigned, an invoice number is immutable and must never be reused

Reasoning:

- drafts are mutable working objects and may be recalculated, replaced, or deleted
- the invoice number should be reserved for the final accounting artifact
- assigning numbers only at finalization avoids unnecessary sequence gaps caused by abandoned or replaced drafts
- this aligns better with the system rule that finalized invoices are immutable

Recommended behavior:

- Draft: `invoice_number = null`
- Finalized: `invoice_number` assigned during finalization
```

---
