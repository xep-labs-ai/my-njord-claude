# Documentation Review — Clarification Questions (Round 5)

---

## NEEDS YOUR DECISION

---

### DQ1 — `Invoice.total_amount`: populated at draft creation or only at finalization?

**Status:** ANSWERED

**Problem:**
`002-resource-models.prp.md` defines `total_amount` as `nullable (null until finalized)` — implying it is null on drafts.
`003-invoice-api.prp.md` draft response example shows `"total_amount": "1500.50"` — implying it is computed at draft creation.

These directly contradict each other.

**Options:**
- (a) Computed at draft creation — `total_amount` reflects the current calculated total; updated if the draft is recalculated. Only `null` before any calculation runs (e.g. during async generation).
- (b) Null until finalization — only assigned when `POST /{id}/finalize` is called.

**Proposal:** Option (a). Computing `total_amount` at draft time gives operators a preview total before finalizing, which is the typical invoicing UX. Update `002-resource-models.prp.md` to say "nullable only before calculation; set during generation, updated on recalculation."

**Answer:** accept proposal 

---

### DQ7 — Discount threshold for VM multi-dimension: per-dimension evaluation never stated

**Status:** ANSWERED

**Problem:**
Round 1 decided discounts apply "per dimension independently," but `001-billing-engine.prp.md` Discounts section never states what value the threshold is compared against for a given dimension. For a `ram_gb` price row with `discount_threshold_quantity = 64`, it is unstated that the comparison is `normalized_ram_gb >= 64`.

**Proposal:**
Add to `001-billing-engine.prp.md` Discounts section: "For multi-dimension resources, the discount threshold on each `ResourcePrice` row is evaluated against the normalized daily usage value of that specific pricing dimension."

This is a documentation-only fix (no architectural decision needed) — just confirming the proposal is correct.

**Answer:** accept proposal

---

### DQ8 — ResourcePrice `effective_to` endpoint: 409 on already-closed rows vs correction workflow

**Status:** ANSWERED

**Problem:**
`005-pricing-api.prp.md` says the `PATCH .../effective-to` endpoint returns 409 "if the row is already closed (has an `effective_to`)."
But `001-billing-engine.prp.md` correction workflow says: "set `effective_to` on the existing row and create a new row."

If a row was created with `effective_to` already set (e.g., a time-bounded price valid Jan–Jun), it can never be shortened via this endpoint. The correction workflow only works for open-ended rows.

**Options:**
- (a) Allow reducing `effective_to` to an earlier date even if already set — as long as overlap validation passes and the new date is not after any `InvoiceDailyCost` that referenced this row.
- (b) Only allow setting `effective_to` on rows where it is currently null (open-ended). Time-bounded rows can only be corrected by creating a replacement row with adjusted dates.
- (c) Allow any update to `effective_to` as long as `effective_from <= new_effective_to` and no overlap is created — simplest approach.

**Proposal:** Option (b). Keep the endpoint narrow: only for closing open-ended rows. Time-bounded rows are immutable by design. Document this clearly in `005-pricing-api.prp.md`.

**Answer:** accept proposal b

---

### DQ11 — Where do Django models live: single `billing` app or per-resource apps?

**Status:** ANSWERED

**Problem:**
The system has two apps: `billing/` and `ingest/`. ARCHITECTURE.md says `billing` owns "resource models." But no document specifies the exact file layout inside `apps/billing/`. With multiple models (BillingAccount, PriceList, ResourcePrice, StorageHotel, VirtualMachine, Invoice, InvoiceLine, InvoiceDailyCost), an implementer cannot know:
- Is it `apps/billing/models.py` (single file)?
- Or `apps/billing/models/` (package with one file per model or group)?
- Do StorageHotel and VirtualMachine live in `billing` or get their own apps?

**Options:**
- (a) All domain models in `apps/billing/models/` as a package (e.g. `billing_accounts.py`, `resources.py`, `invoices.py`). Ingestion snapshot models in `apps/ingest/models/`.
- (b) Each resource type gets its own app: `apps/storage_hotel/`, `apps/virtual_machine/`. Billing aggregation models stay in `apps/billing/`.
- (c) `apps/billing/models.py` as a single file for all models (simple but will grow large).

**Proposal:** Option (a). A models package inside `apps/billing/` keeps things organized without over-fragmenting into many apps. Ingestion event models (QuotaIngestionEvent, VirtualMachineUsageIngestionEvent) stay in `apps/ingest/`. Document in ARCHITECTURE.md.

**Answer:** accept proposal a

---

## FIELD TYPE GAPS (block migration writing — straightforward, just need confirmation)

---

### DQ5 — `ResourceModel.name` field type undefined

**Status:** ANSWERED

**Problem:**
`ResourceModel` lists `name` as a field but no type, max_length, or required/unique constraint is defined.

**Proposal:** `name -- CharField(max_length=255), required, not unique` (multiple resources may share display names; uniqueness for StorageHotel is on `filesystem_identifier`).

**Answer:** accept proposal

---

### DQ6 — `ResourceModel.billing_account` FK spec undefined

**Status:** ANSWERED

**Problem:**
`ResourceModel.billing_account` is listed as a field but FK target, nullability, and `on_delete` behavior are never specified.

**Proposal:** `billing_account -- FK to BillingAccount, nullable (null = unassigned), on_delete=PROTECT` (prevents deleting a BillingAccount that still has resources).

**Answer:** accept proposal

---

### DQ9 — Snapshot model field types undefined

**Status:** ANSWERED

**Problem:**
`StorageHotelDailyQuota.quota_raw` and `VirtualMachineDailyUsage.cpu_count / ram_mb / disks_total_gb` have no Django field types. Migrations cannot be written.

**Proposal:**
- `quota_raw` — DecimalField(max_digits=25, decimal_places=4) — handles large raw KB/KIB values
- `cpu_count` — PositiveIntegerField
- `ram_mb` — DecimalField(max_digits=14, decimal_places=2)
- `disks_total_gb` — DecimalField(max_digits=14, decimal_places=2)

**Answer:** accept proposal

---

### DQ10 — `ResourceModel.status` field type and default not in model spec

**Status:** ANSWERED

**Problem:**
`ResourceModel` lists `status` with lifecycle states but no Django field type, choices, or default. `004-resource-api.prp.md` says resources default to `UNASSIGNED` on creation but this is not in the model definition.

**Proposal:** `status -- CharField(max_length=20, choices=["UNASSIGNED", "ACTIVE", "RETIRED"], default="UNASSIGNED")`.

**Answer:** accept proposal

---

## PROPAGATION MISSES (already decided, just not yet applied)

---

### DQ2 — `InvoiceLine.currency` missing from field type definitions

**Status:** ANSWERED

**Problem:**
`InvoiceLine` field listing includes `currency` but the field types section omits it.

**Proposal:** Add `currency -- CharField(max_length=3, default="NOK")` to InvoiceLine field type definitions.

**Answer:** accept proposal

---

### DQ3 — `InvoiceDailyCost.currency` missing from field type definitions

**Status:** ANSWERED

**Problem:**
Same issue as DQ2 for `InvoiceDailyCost`.

**Proposal:** Add `currency -- CharField(max_length=3, default="NOK")` to InvoiceDailyCost field type definitions.

**Answer:** accept proposal

---

### DQ4 — `billing_account` listed as required in POST endpoints but lifecycle says optional

**Status:** ANSWERED

**Problem:**
`004-resource-api.prp.md` StorageHotel and VirtualMachine POST endpoints list `billing_account` as a required writable field. The same document's lifecycle section says it is optional (resources start as UNASSIGNED without one). Direct contradiction in the same file.

**Proposal:** Change `billing_account` from "required" to "optional (nullable)" in both POST endpoint writable field lists.

**Answer:** accept proposal

---

### DQ12 — `virtual-machine.prp.md` InvoiceDailyCost metadata not updated to required/optional split

**Status:** ANSWERED

**Problem:**
Round 3 (BQ13) established required vs optional metadata fields. StorageHotel PRP was updated. VirtualMachine PRP still uses "may include" language for all metadata fields and does not mention `normalized_usage`, `resolved_prices`, `autofilled` as required.

**Proposal:** Update `virtual-machine.prp.md` InvoiceDailyCost metadata section to: required: `normalized_usage`, `resolved_prices`, `autofilled`, `cpu_count`, `ram_gb`, `disk_gb` (normalized dimension values), `dimension_costs`, `source_snapshot_date`.

**Answer:** accept proposal

---

### DQ13 — `004-resource-api.prp.md` list responses use bare arrays instead of DRF pagination

**Status:** ANSWERED

**Problem:**
StorageHotel and VirtualMachine list response examples show bare `[{...}]` arrays. `API.md` and `005-pricing-api.prp.md` both mandate the standard DRF pagination envelope.

**Proposal:** Update both list response examples in `004-resource-api.prp.md` to use the `count / next / previous / results` envelope.

**Answer:** accept proposal

---
