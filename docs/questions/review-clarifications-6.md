# Documentation Review — Clarification Questions (Round 6)

---

## NEEDS YOUR DECISION

---

### EQ1 — `force=true` + missing pricing: should it bill zero or always fail?

**Status:** OPEN

**Problem:**
`001-billing-engine.prp.md` defines `force=true` behavior only for missing usage data (bill at zero) and duplicate drafts (replace). It never defines what happens when pricing data is missing for a day and `force=true`. This is a financial correctness risk — silently generating a zero-cost invoice due to a pricing configuration gap would be a serious error.

**Options:**
- (a) Missing pricing always fails, even with `force=true`. The `force` flag only covers missing usage data and duplicate drafts, never pricing gaps.
- (b) Missing pricing + `force=true` bills at zero and reports the resource in `missing_data_summary`, same as missing usage.

**Proposal:** Option (a). Missing pricing should always be fatal regardless of `force`. A resource billed at zero due to a pricing gap is worse than a failed invoice. Add to `001-billing-engine.prp.md`: "Missing pricing data causes invoice generation to fail even when `force=true`. The `force` flag only affects missing usage data and duplicate draft handling."

---

### EQ2 — Finalize endpoint: 409 vs 422 overlap + 404 in wrong place

**Status:** OPEN

**Problem:**
`003-invoice-api.prp.md` finalize error responses list:
- 404: Invoice not found
- 409: Invoice is already finalized **or does not exist**
- 422: Cannot finalize a non-draft invoice

Two issues:
1. "Does not exist" appears in both 404 and 409 — contradiction.
2. 409 and 422 cover the same case (already finalized / non-draft state).

**Proposal:**
- 404: Invoice not found (only meaning for 404)
- 409: Invoice is already finalized (idempotency conflict — client should not retry)
- Remove 422 from the finalize endpoint (or reserve it for a distinct business rule, e.g., invoice has zero lines)
- Remove "does not exist" from the 409 description

---

### EQ3 — Invoice generation: should `period_start > period_end` be rejected?

**Status:** OPEN

**Problem:**
The validation failure cases in `003-invoice-api.prp.md` do not include `period_start` after `period_end`. This is a basic guard that every invoice generation implementation will need.

**Proposal:** Add to the validation failure list: "`period_start` is after `period_end` → 400 Bad Request."

---

### EQ4 — Future-dated invoice periods: allowed or rejected?

**Status:** OPEN

**Problem:**
The snapshot ingestion API rejects future-dated snapshots (date > today). But the invoice API never says whether `period_end > today` is allowed. With `force=false`, it would fail due to missing snapshots. With `force=true`, it could generate a zero-cost invoice for a future period.

**Options:**
- (a) Reject `period_end > today` at the API validation layer with 400.
- (b) Allow it — the missing-data handling rules take over.

**Proposal:** Option (a). Reject at API layer. Future-dated invoice periods have no valid use case in v1, and the failure mode with `force=true` (zero-cost invoice for days that haven't happened yet) is confusing and potentially dangerous.

---

### EQ5 — `autofill_missing_days=true` + no prior snapshot: what happens with `force=true` vs `force=false`?

**Status:** OPEN

**Problem:**
`001-billing-engine.prp.md` says "if no prior valid snapshot exists for the resource, fail for that resource." This is under the autofill section, but "fail for that resource" is ambiguous:
- Does the entire invoice generation fail?
- Or is the resource excluded and the invoice generated without it?

And what if `force=true` is also set?

**Proposal:**
- `force=false` + `autofill_missing_days=true` + no prior snapshot → entire invoice generation fails (fatal).
- `force=true` + `autofill_missing_days=true` + no prior snapshot → resource is billed at zero for all its days; reported in `missing_data_summary`; invoice marked `incomplete=true`.

---

### EQ6 — Invoice number generation algorithm

**Status:** OPEN

**Problem:**
The format `INV-YYYY-mm-NNNNN` is shown but the algorithm is not defined:
- Is `YYYY-mm` the finalization date or the `period_start`?
- Is `NNNNN` a global sequence or per-month?
- How is concurrency handled (two invoices finalized simultaneously)?

**Proposal:**
- `YYYY-mm` is derived from the **finalization date** (not period_start) — the invoice number reflects when it was issued, not the billing period it covers.
- `NNNNN` is a **global auto-incrementing sequence** (not per-month). Gaps are acceptable (already stated in spec).
- Concurrency: use `SELECT MAX(invoice_number) FOR UPDATE` within the finalization transaction, or a dedicated PostgreSQL sequence.

---

### EQ7 — `resource_type` registry: where are valid values defined and enforced?

**Status:** OPEN

**Problem:**
`resource_type` is used throughout all PRPs as a string (`"storage_hotel"`, `"virtual_machine"`) but there is no central registry of valid values, no naming convention document, and no guidance on what happens when an unknown value is submitted (e.g., in invoice generation's `selected_resource_types` or `ResourcePrice.resource_type`).

**Proposal:** Add a "Resource Type Registry" to `001-billing-engine.prp.md`:
- Valid values: `"storage_hotel"`, `"virtual_machine"`
- Convention: snake_case of the Django model name
- Code location: a choices class or constant module in `apps/billing/`
- Validation: invoice generation and ResourcePrice creation must reject unknown resource types with 400

---

### EQ8 — `active_from`/`active_to` PATCH after a resource has finalized invoice data

**Status:** OPEN

**Problem:**
`004-resource-api.prp.md` allows patching `active_from` and `active_to` on resources. But if a finalized invoice includes daily costs for a resource, changing `active_from` to a date after billed days (or `active_to` before billed days) would make the historical invoice inconsistent with the resource's current state.

**Options:**
- (a) Block changes to `active_from`/`active_to` that would invalidate finalized invoice data — requires querying InvoiceDailyCost to validate each PATCH.
- (b) Allow changes freely — finalized invoices are immutable by design, so the invoice is correct at the time it was generated. The PATCH only affects future generation.
- (c) Block changes only for RETIRED resources (active_to is final once set with retirement).

**Proposal:** Option (b). Finalized invoices are already immutable. The resource PATCH only affects future generation runs. Add a note: "Changing `active_from` or `active_to` on a resource with finalized invoice data is allowed. Finalized invoices are unaffected — they represent a point-in-time calculation."

---

### EQ9 — Soft-delete: is there an API endpoint or is it triggered via PATCH?

**Status:** OPEN

**Problem:**
`002-resource-models.prp.md` defines soft-delete semantics (`deleted_at` must be set, `status=RETIRED`, `active_to` must be set). But `004-resource-api.prp.md` has no DELETE endpoint and does not specify how `deleted_at` gets set. A developer cannot implement soft-delete without knowing the trigger.

**Options:**
- (a) `DELETE /api/v1/storage-hotels/{id}/` sets `deleted_at=now()`, `status=RETIRED`, and requires `active_to` to already be set (or sets it to today).
- (b) `deleted_at` is set automatically by the service layer when `status` transitions to `RETIRED` via PATCH. No DELETE endpoint exists.
- (c) `deleted_at` is a patchable field — clients set it explicitly via PATCH.

**Proposal:** Option (b). Keep the API surface minimal. The PATCH to `status=RETIRED` (which already requires `active_to`) triggers `deleted_at=now()` in the service layer. No DELETE endpoint in v1. Add to `004-resource-api.prp.md`: "When a resource transitions to RETIRED via PATCH, the service layer sets `deleted_at` to the current timestamp. There is no dedicated DELETE endpoint."

---

### EQ10 — `incomplete` flag: when is it `true`?

**Status:** OPEN

**Problem:**
`003-invoice-api.prp.md` shows `"incomplete": false` in the draft response, and `002-resource-models.prp.md` lists `incomplete` in Invoice metadata. But neither document defines when `incomplete` is `true`.

**Proposal:** Define: "`incomplete = true` when `force=true` was used and at least one resource had missing usage data that was billed at zero (days with no snapshot and no autofill). An autofilled invoice where all days were successfully filled using the carry-forward rule is **not** considered incomplete."

---

### EQ11 — `InvoiceLine.description` generation rule

**Status:** OPEN

**Problem:**
`003-invoice-api.prp.md` shows `"description": "StorageHotel #101"` as an example, but no rule defines how to construct this string. Should it use the resource's `name` field? A formatted type+id string? Both?

**Proposal:** Define: "`InvoiceLine.description` is set to the resource's `name` field at the time of invoice generation. If `name` is blank or null, fall back to `{ResourceType} #{resource_id}` (e.g., `StorageHotel #101`)."

---

### EQ12 — `resource_snapshot` in InvoiceDailyCost metadata: required or optional?

**Status:** OPEN

**Problem:**
`001-billing-engine.prp.md` says InvoiceLine and InvoiceDailyCost metadata "should include a frozen resource snapshot." `002-resource-models.prp.md` lists `resource_snapshot` as optional in InvoiceDailyCost metadata. These conflict.

Storing a full resource snapshot per InvoiceDailyCost row is storage-intensive (one row per resource per day per dimension).

**Options:**
- (a) Require `resource_snapshot` in `InvoiceLine.metadata` only (one per resource per invoice). Keep it optional in InvoiceDailyCost.
- (b) Require `resource_snapshot` in both InvoiceLine and InvoiceDailyCost.
- (c) Keep it optional in both — billing engine note was guidance, not a mandate.

**Proposal:** Option (a). Require `resource_snapshot` in `InvoiceLine.metadata` for auditability. Keep it optional in InvoiceDailyCost to avoid row explosion. Update `001-billing-engine.prp.md` to reflect this distinction.

---

### EQ13 — `quota_unit` and `provisioner` in InvoiceLine metadata: required or optional?

**Status:** OPEN

**Problem:**
`002-resource-models.prp.md` lists `quota_unit` and `provisioner` under InvoiceLine metadata as "may also include." For audit reproducibility, `quota_unit` is needed to verify StorageHotel unit conversions, and `provisioner` identifies the VM source. If the resource is later changed, the invoice metadata would be the only record.

**Proposal:**
- Make `quota_unit` **required** in InvoiceLine metadata for `resource_type = "storage_hotel"`.
- Make `provisioner` **required** in InvoiceLine metadata for `resource_type = "virtual_machine"`.
- Update `002-resource-models.prp.md` accordingly.

---

## PROPAGATION MISSES (already clear, just need confirmation before applying)

---

### EQ14 — `BILLING.md` mentions "yearly or monthly price" but only yearly pricing exists

**Status:** OPEN

**Problem:**
`.claude/docs/BILLING.md` contains the text "yearly or monthly price by CPU, RAM, and disk dimensions." Only `price_per_unit_year` exists in ResourcePrice. There is no monthly pricing field anywhere in the spec.

**Proposal:** Remove "or monthly" from BILLING.md. Replace with "yearly price per CPU count, per GB RAM, and per GB disk."

---

### EQ15 — `Invoice.updated_at` missing from field list in `002-resource-models.prp.md`

**Status:** OPEN

**Problem:**
`002-resource-models.prp.md` Invoice field list (lines 352–365) does not include `updated_at`, but line 401 states `created_at / updated_at — DateTimeField, auto`.

**Proposal:** Add `updated_at` to the Invoice field list for consistency.

---

### EQ16 — `ARCHITECTURE.md` does not list location of `TimestampedModel`, `CreatedAtModel`, `BillingAccountBase`

**Status:** OPEN

**Problem:**
The model organization section in `.claude/docs/ARCHITECTURE.md` lists `billing_accounts.py` for "BillingAccountBase, BillingAccount" but does not specify where `TimestampedModel` and `CreatedAtModel` (abstract base models from `002-resource-models.prp.md`) should live, nor does it note that `BillingAccountBase` is abstract.

**Proposal:**
- Add `apps/billing/models/base.py` to the model layout for `TimestampedModel`, `CreatedAtModel`, and `BillingAccountBase`.
- Update `billing_accounts.py` entry to: "BillingAccountBase (abstract), BillingAccount (concrete UiO implementation)."

---

### EQ17 — LDAP in `CLAUDE.md` stack vs auth as non-goal in `000-system-overview.prp.md`

**Status:** OPEN

**Problem:**
`CLAUDE.md` stack listing includes "LDAP authentication." `000-system-overview.prp.md` Non-Goals section includes "authentication / authorization." This causes a developer to be unsure whether auth middleware or login views are needed.

**Proposal:** Remove "LDAP authentication" from the CLAUDE.md stack listing entirely (it was already removed in an earlier round — this may be a residual copy). Auth is an infrastructure/deployment concern, not part of the billing API application logic in v1.

---

### EQ18 — `resolved_prices` shape undefined

**Status:** OPEN

**Problem:**
`InvoiceDailyCost.metadata` requires `resolved_prices` but its structure is never defined. Since only one ResourcePrice row can apply per `(resource_type, pricing_dimension, day)`, the name is slightly misleading. A developer needs to know the expected shape.

**Proposal:** Define the expected shape in `002-resource-models.prp.md`:

```json
"resolved_prices": {
  "price_per_unit_year": "500.0000",
  "discount_price_per_unit_year": "400.0000",
  "discount_threshold_quantity": "10.0000",
  "applied_price": "400.0000",
  "discount_applied": true
}
```

Where `applied_price` is the price actually used in the daily cost calculation.

---

### EQ19 — `missing_data_summary` shape undefined

**Status:** OPEN

**Problem:**
`003-invoice-api.prp.md` shows `"missing_data_summary": null` in the response but never defines the shape when it is non-null.

**Proposal:** Define the shape:

```json
"missing_data_summary": {
  "storage_hotel": {
    "101": {"missing_days": ["2026-01-05", "2026-01-06"], "count": 2}
  },
  "virtual_machine": {
    "205": {"missing_days": ["2026-01-10"], "count": 1}
  }
}
```

---

### EQ20 — `/effective-to` PATCH URL pattern: keep as-is or normalize to standard PATCH?

**Status:** OPEN

**Problem:**
`PATCH /api/v1/price-lists/{price_list_id}/resource-prices/{id}/effective-to` uses a field-name URL suffix. This is non-standard REST and may cause issues with drf-spectacular schema generation and client generators.

**Options:**
- (a) Keep as-is — the explicit URL makes the constraint obvious and prevents misuse.
- (b) Change to `PATCH /api/v1/price-lists/{price_list_id}/resource-prices/{id}/` with a dedicated serializer that only accepts `effective_to`.

**Proposal:** Option (a). The explicit URL signals to API consumers that this is a constrained operation, not a general PATCH. The drf-spectacular schema can be decorated manually if needed. This is consistent with the immutability model of ResourcePrice.

---
