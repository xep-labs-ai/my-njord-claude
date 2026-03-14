# Documentation Review — Clarification Questions (Round 3)

This file was generated from a third documentation audit after round 1 and round 2 decisions were applied.
Each question includes the problem found, the options or proposal, and a blank **Answer** field for you to fill in.

Questions are grouped by priority.

---

## HIGH PRIORITY

---

### BQ2 — `resource_type` casing: PascalCase vs snake_case

**Status:** PENDING

**Problem:**
`resource_type` string format is inconsistent across documents:
- `BILLING.md` `selected_resource_types` examples use PascalCase: `["StorageHotel"]`, `["VirtualMachine"]`
- `BILLING.md` `explicit_resources` examples use snake_case: `"storage_hotel"`, `"virtual_machine"`
- `001-billing-engine.prp.md`, `003-invoice-api.prp.md`, `InvoiceLine`, `InvoiceDailyCost` all use snake_case

An implementer building the serializer cannot know which format is canonical.

**Options:**
- (a) snake_case everywhere — `"storage_hotel"`, `"virtual_machine"`. Already used on InvoiceLine, InvoiceDailyCost, and all API examples. Most consistent with Django/Python conventions.
- (b) PascalCase everywhere — `"StorageHotel"`, `"VirtualMachine"`. Matches the Django model class names.

**Proposal:** Option (a). Snake_case is already the majority format across the codebase. Update `BILLING.md` `selected_resource_types` examples to use `["storage_hotel"]`, `["virtual_machine"]`.

**Answer:**

---

### BQ6 — `make_invoice = False` rule missing from billing engine spec

**Status:** PENDING

**Problem:**
`BillingAccount.make_invoice` (BooleanField, default=True) was defined in round 2 with the rule: "resources belonging to an account where `make_invoice = False` are excluded from all invoice generation runs silently."

This rule does not appear in:
- `001-billing-engine.prp.md` (billable resource identification step)
- `BILLING.md` (Billable Resource Rule section)
- `003-invoice-api.prp.md` (validation rules)

An implementer building from those docs would never add the check.

Also unspecified: if `POST /api/v1/invoices/generate` is called for an account with `make_invoice = False`, does it return an error or produce an empty invoice?

**Options for the generate endpoint behavior:**
- (a) Return a validation error (400) — explicit rejection is safer
- (b) Produce an empty invoice with zero lines — consistent with "silent exclusion" semantics
- (c) Return a warning in the response but still generate an empty invoice

**Proposal:**
- Add `make_invoice = True` as a required condition in the billable resource rule in `001-billing-engine.prp.md` and `BILLING.md`
- For the API: option (a) — return 400 when `make_invoice = False`. Silent empty invoices are harder to debug.

**Answer:**

---

## MEDIUM PRIORITY

---

### BQ3 — Old `resource_ids` / `selected_resource_ids` naming still present

**Status:** PENDING

**Problem:**
RQ5 (round 1) decided explicit resource selection uses `explicit_resources` (typed pairs). But two files still use old names:
- `BILLING.md` line ~104 lists `resource_ids` as an optional selection input
- `002-resource-models.prp.md` Invoice metadata uses `selected_resource_ids`

**Proposal:**
- `BILLING.md`: rename `resource_ids` → `explicit_resources`
- `002-resource-models.prp.md` Invoice metadata: rename `selected_resource_ids` → `explicit_resources`

**Answer:**

---

### BQ4 — StorageHotel ingestion: request field `quota_value` vs model field `quota_raw`

**Status:** PENDING

**Problem:**
In `004-resource-api.prp.md`:
- Ingestion request body uses `"quota_value": "5000"`
- Response body and the `StorageHotelDailyQuota` model use `"quota_raw": "5000"`

The name mismatch means the serializer would need a silent field rename, which is confusing.

**Options:**
- (a) Use `quota_raw` in the request body too — consistent with the model field name, no translation needed
- (b) Use `quota_value` in both request and response, and rename the model field to `quota_value`
- (c) Keep `quota_value` in the request as the external-facing name, map to `quota_raw` in the serializer, and document this mapping explicitly

**Proposal:** Option (a). Use `quota_raw` everywhere. The model field name is the source of truth. Update `004-resource-api.prp.md` request example.

**Answer:**

---

### BQ5 — StorageHotel PRP metadata key not updated to standard format

**Status:** PENDING

**Problem:**
`storage-hotel.prp.md` still uses `total_quota_days_tb` as the InvoiceLine metadata key.
`002-resource-models.prp.md` defines the standard as `total_quantity_by_dimension.quota_tb_days` (with `billing_dimensions` array).

These are different key names and structures for the same data.

**Proposal:**
Update `storage-hotel.prp.md` InvoiceLine metadata example to match the standard from `002-resource-models.prp.md`:
```json
{
  "billing_dimensions": ["quota_tb"],
  "total_quantity_by_dimension": {
    "quota_tb_days": "3720"
  }
}
```

**Answer:**

---

### BQ7 — `BillingAccountBase` field constraints underspecified

**Status:** PENDING

**Problem:**
`002-resource-models.prp.md` defines `BillingAccountBase` fields but is missing nullable/required/default specs for most of them. Migrations cannot be written without this.

Fields needing clarification:
- `contact_point` — required or optional?
- `contact_email` — required or optional?
- `contact_telephone_number` — required or optional?
- `customer_number` — required or optional? Unique constraint?
- `internal_customer` — default True or False?

And on `BillingAccount`:
- `usit_contact_point` — required or optional?
- `main_agreement_id` — required or optional?
- `main_agreement_description` — required or optional?
- `usit_accounting_place` — required or optional?
- `usit_sub_project` — required or optional?
- `ephorte` — required or optional?
- `uio_unit` — required or optional?

**Proposal:**
Define each field's required/optional status. Suggested defaults:
- All contact fields: optional (`blank=True, null=True`)
- `customer_number`: optional, unique when set (`blank=True, null=True, unique=True` — or nullable non-unique)
- `internal_customer`: default `False`
- All UiO-specific fields: optional (`blank=True, null=True`)

**Answer:**

---

### BQ9 — `ResourcePrice` overlap prevention: enforcement path undefined

**Status:** PENDING

**Problem:**
`001-billing-engine.prp.md` says "No two ResourcePrice rows for the same `(price_list, resource_type, pricing_dimension)` may have overlapping effective date ranges — enforced at the service layer." But no PRP says:
- Is there a `POST /api/v1/resource-prices/` endpoint?
- Is ResourcePrice managed via Django admin only?
- Where exactly is overlap validation implemented?

**Options:**
- (a) Django admin only in v1 — overlap validation in model `clean()` method
- (b) API endpoint — define in a new PRP or add to `004-resource-api.prp.md`
- (c) Management command or fixture only — no UI, validation in service

**Proposal:** Option (a) for v1. ResourcePrice rows are managed via Django admin. Overlap validation is enforced in the model's `clean()` method. Document this explicitly in `001-billing-engine.prp.md`.

**Answer:**

---

### BQ10 — No CRUD endpoints defined for `BillingAccount`, `PriceList`, `ResourcePrice`

**Status:** PENDING

**Problem:**
Invoice generation requires a `BillingAccount` with a `PriceList` and `ResourcePrice` rows to exist. But no PRP defines how these entities are created. An implementer building end-to-end cannot create test data through the API.

**Options:**
- (a) Django admin only for all three — document this in `002-resource-models.prp.md` or a new PRP
- (b) API endpoints for all three — define in `004-resource-api.prp.md` or a new `005-admin-api.prp.md`
- (c) Mixed — `BillingAccount` via API (needed by operators), `PriceList` and `ResourcePrice` via admin only

**Proposal:** Option (c). `BillingAccount` likely needs API endpoints since operators need to manage billing accounts programmatically. `PriceList` and `ResourcePrice` are pricing configuration that changes rarely and can be admin-managed in v1.

**Answer:**

---

### BQ12 — Rounding method stated as "suggested" rather than required

**Status:** PENDING

**Problem:**
`BILLING.md` describes `ROUND_HALF_UP` as "Suggested rounding method." In a financial system this must be a hard requirement, not a suggestion. `001-billing-engine.prp.md` states the 2-decimal rule but does not specify the rounding method at all.

**Proposal:**
- Change "Suggested rounding method" → "Required rounding method: `ROUND_HALF_UP`" in `BILLING.md`
- Add `ROUND_HALF_UP` as the required rounding method to `001-billing-engine.prp.md`

**Answer:**

---

### BQ13 — `InvoiceDailyCost.metadata` required vs optional fields unclear

**Status:** PENDING

**Problem:**
`002-resource-models.prp.md` lists metadata fields with "may include" language.
`BILLING.md` says daily snapshots "must contain" normalized usage, price used, and metadata about autofill.

These contradict each other. For a financial system with auditability requirements, a minimum set of metadata fields must be mandatory.

**Proposal:**
Split into required and optional:

Required (needed for audit reproducibility):
- `normalized_usage` — the usage value after unit conversion, used for the billing calculation
- `resolved_price` — the price per unit applied on that day (from ResourcePrice)
- `autofilled` — boolean, whether the usage value was autofilled (true) or from a real snapshot (false)

Optional (useful but not mandatory):
- `source_snapshot_date` — when autofilled, the date of the original snapshot that was carried forward
- `dimension_costs` — per-dimension cost breakdown (for VM multi-dimension rows)
- `missing_data_flags` — additional diagnostic info

**Answer:**

---

## LOW PRIORITY

---

### BQ1 — `STRUCTURE.md` still referenced in `documenter.md`

**Status:** PENDING

**Problem:**
AQ7 (round 2) removed `STRUCTURE.md` references from most files, but `.claude/agents/documenter.md` still lists it in the "Allowed Documentation Targets" section.

**Proposal:** Remove `STRUCTURE.md` from the allowed targets list in `documenter.md`. Replace with `ARCHITECTURE.md` if file-placement guidance is needed.

**Answer:**

---

### BQ8 — `InvoiceDailyCost` → `InvoiceLine` relationship is implicit, never stated

**Status:** PENDING

**Problem:**
`InvoiceDailyCost` has a FK to `Invoice` but no FK to `InvoiceLine`. The relationship to its parent line is through `(invoice, resource_type, resource_id)` tuple matching. This is not stated anywhere — an implementer must guess.

**Options:**
- (a) Keep the implicit tuple-based relationship — state explicitly in `002-resource-models.prp.md` that there is no FK to InvoiceLine and aggregation uses `(invoice, resource_type, resource_id)` matching
- (b) Add an explicit `invoice_line` FK to `InvoiceDailyCost` — simplifies aggregation queries, makes the relationship traversable

**Proposal:** Option (a) for v1. The tuple approach is already implied by the data model and avoids the need to manage a FK when replacing drafts. Document this explicitly.

**Answer:**

---

### BQ11 — `003-invoice-api.prp.md` still shows ambiguous `billing_account` placeholder

**Status:** PENDING

**Problem:**
The request body example in `003-invoice-api.prp.md` still shows `"billing_account": "<id or identifier>"`. AQ9 decided this is the integer PK.

**Proposal:** Change to `"billing_account": 1` (integer literal) to match the decision and all resource API examples.

**Answer:**

---
