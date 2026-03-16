# Review Clarifications 10

Architecture review round 10 — consistency pass after round-9 changes.
Edit each `**Decision:**` line with your answer.

---

## HIGH

### H-1. Advisory lock key scope narrower than uniqueness constraint

The advisory lock is keyed on `(billing_account, period_start, period_end)` — 3 fields.
The uniqueness constraint is on `(billing_account, period_start, period_end, selection_scope, selection_fingerprint)` — 5 fields.

This means two concurrent requests for the same account and period but **different selection scopes** are blocked by the same lock even though they would produce different invoices that do not conflict. Conversely, it prevents truly concurrent generation for the same account/period regardless of selection.

Two options:
- **(a)** The broader lock scope is intentional — conservative serialization to avoid any concurrent billing for the same account/period. Document this tradeoff explicitly.
- **(b)** Extend the advisory lock key to include `selection_scope` and `selection_fingerprint` to allow non-conflicting concurrent generation.

Proposal: **(a)**. Concurrent invoice generation for the same account and period is an unlikely scenario in practice, and conservative serialization is safer for a financial system. Document the deliberate tradeoff.

**Decision:**

---

### H-2. `resource_snapshot` described as a model field in BILLING.md, but it lives in `InvoiceLine.metadata`

`BILLING.md` lists `resource_snapshot` in a way that reads as a top-level model field ("required frozen snapshot of the resource's identifying attributes... the primary audit snapshot"). All PRPs (`001`, `002`, resource PRPs) consistently place it as a key inside `InvoiceLine.metadata`.

Proposal: fix the phrasing in `BILLING.md` to explicitly state that `resource_snapshot` is a required key within `InvoiceLine.metadata`, not a top-level model field.

**Decision:**

---

## MEDIUM

### M-1. `incomplete` filter missing from invoice list query parameters

`incomplete` was explicitly promoted to a `BooleanField` on Invoice specifically to support direct filtering. But `003-invoice-api.prp.md` does not list `incomplete` as a supported query parameter for `GET /api/v1/invoices/`.

Proposal: add `incomplete` (optional, boolean) to the list of supported query parameters in `003-invoice-api.prp.md`.

**Decision:**

---

### M-2. 409 error code conflict — `duplicate_invoice` vs. `duplicate_draft_invoice` / `duplicate_finalized_invoice`

`API.md` defines two distinct 409 codes: `duplicate_draft_invoice` and `duplicate_finalized_invoice`.
`003-invoice-api.prp.md` error example uses a single generic `duplicate_invoice`.

An implementer reading both would not know which to implement.

Proposal: update the error example in `003-invoice-api.prp.md` to use `duplicate_draft_invoice` for the draft duplicate case and `duplicate_finalized_invoice` for the finalized duplicate case. Remove the generic `duplicate_invoice` code.

**Decision:**

---

### M-3. Duplicate prevention tuple wording — raw fields vs. `selection_fingerprint`

`003-invoice-api.prp.md` line 362 describes the duplicate check using raw fields `(billing_account, period_start, period_end, selection_scope, selected_resource_types, explicit_resources)`.
`001-billing-engine.prp.md` and `BILLING.md` use `(billing_account, period_start, period_end, selection_scope, selection_fingerprint)`.

These are semantically equivalent but the wording suggests different implementation approaches.

Proposal: update `003-invoice-api.prp.md` line 362 to reference `selection_fingerprint` as the mechanism, with a note that it is derived from `selected_resource_types` and `explicit_resources`.

**Decision:**

---

### M-4. Pricing overlap 409 has no defined error code in `API.md`

`005-pricing-api.prp.md` says creating a ResourcePrice with overlapping effective dates returns 409. But `API.md`'s error code table has no code defined for this case.

Proposal: add `price_range_overlap` to the 409 error code table in `API.md`, and reference it in `005-pricing-api.prp.md`.

**Decision:**

---

### M-5. `InvoiceLine` metadata examples in `002-resource-models.prp.md` missing `resource_snapshot`

The central InvoiceLine metadata examples for StorageHotel and VirtualMachine in `002-resource-models.prp.md` do not include `resource_snapshot`. Yet `resource_snapshot` is marked as required for all resources, and the resource-specific PRPs (`storage-hotel.prp.md`, `virtual-machine.prp.md`) do include it.

Proposal: add `resource_snapshot` to both InvoiceLine metadata examples in `002-resource-models.prp.md`, consistent with the resource PRPs.

**Decision:**

---

### M-6. `total_quantity_by_dimension` computation never formally defined

The `{dimension}_days` naming convention is documented, and examples exist (e.g., `quota_tb_days: "3720"`), but no document defines how the values are computed. Questions left open:
- Is it `sum(daily_normalized_usage[dimension])` across all billed days?
- Are autofilled days included?
- Is it computed from `InvoiceDailyCost.metadata.normalized_usage[dimension]` per day?

Proposal: add a formal definition to `001-billing-engine.prp.md` or `BILLING.md`: "`{dimension}_days` is the sum of `InvoiceDailyCost.metadata.normalized_usage[dimension]` across all billed days for the resource in the invoice period, including autofilled days."

**Decision:**

---

## LOW

### L-1. `selection_scope` not listed as an invoice list filter parameter

`selection_scope` is part of the invoice identity and is returned in list responses, but there is no corresponding query parameter to filter by it.

Two options:
- **(a)** Add `selection_scope` as an optional filter parameter.
- **(b)** Intentionally exclude it in v1; document the omission.

**Decision:**

---

### L-2. `quota_raw` API validation constraints not documented (max digits, decimal places)

The model defines `quota_raw` as `DecimalField(max_digits=25, decimal_places=4)`. The API validation only says "positive number or zero" — it does not communicate the precision limits. An implementer or API consumer would not know the field accepts up to 21 integer digits and 4 decimal places.

Proposal: add explicit precision constraints to the `quota_raw` validation rules in `004-resource-api.prp.md` (`max_digits=25, decimal_places=4`).

**Decision:**

---

### L-3. `updated_at` not included in invoice API responses — intentional or oversight?

The Invoice model has `updated_at` but none of the API response examples (generate, list, detail, finalize) include it. It is not documented as intentionally excluded.

Two options:
- **(a)** Include `updated_at` in detail and generate/finalize responses (useful for tracking when a draft was last regenerated).
- **(b)** Intentionally exclude it in v1; document the omission.

**Decision:**

---

### L-4. `ram_gb` binary GiB note missing from billing engine PRP

`virtual-machine.prp.md` has the clarifying note that "GB in VirtualMachine context means binary gigabytes (GiB = 1024 MB)." `001-billing-engine.prp.md` lists `ram_gb` as a pricing dimension with no such note.

Proposal: add a note to the Allowed Pricing Dimensions section in `001-billing-engine.prp.md` clarifying that `ram_gb` is computed as `ram_mb / 1024` (binary). Also confirm whether `disk_gb` is binary or decimal and document it explicitly.

**Decision:**

---

### L-5. Zero-value VM usage dimensions — billing behavior undocumented

StorageHotel explicitly documents that `quota_raw = 0` is valid and produces `daily_cost = 0`. VirtualMachine's validation says "non-negative" (implying 0 is allowed) but there is no explicit note about what happens when `cpu_count = 0`, `ram_mb = 0`, or `disks_total_gb = 0`.

Proposal: add a note to the VirtualMachine resource PRP or `004-resource-api.prp.md` confirming that zero-value dimensions are valid and produce `daily_cost = 0` for that dimension, consistent with the StorageHotel behavior.

**Decision:**

---

### L-6. Draft replacement wording "if any" is logically vacuous

`001-billing-engine.prp.md` says: "The old invoice number (if any) is not reused." Drafts always have `invoice_number = null`, so "if any" can never be true. The wording creates a false implication.

Proposal: replace with: "The replacement draft has `invoice_number = null` (consistent with all draft invoices)."

**Decision:**

---

### L-7. BILLING.md says "validation error" for `billing_account_not_billable` — should say "domain error (422)"

`BILLING.md` says invoice generation "must fail immediately with a validation error" when `make_invoice = False`. But `API.md` reserves 400 for request validation errors and 422 for billing domain failures. This was resolved as 422 in round 9, but the wording in BILLING.md still says "validation error."

Proposal: change the wording in `BILLING.md` to "must fail immediately with a billing domain error (422)" to align with the 400/422 distinction.

**Decision:**

---

### L-8. `quota_unit` / `provisioner` duplicated in both `resource_snapshot` and as flat metadata keys

Both `quota_unit` (StorageHotel) and `provisioner` (VirtualMachine) appear as:
- A flat top-level key in `InvoiceLine.metadata`
- A field inside `resource_snapshot` within the same metadata

This creates duplication within the same JSON field. It is not necessarily wrong, but it is undocumented as intentional.

Two options:
- **(a)** Intentional redundancy for convenience (quick access without nested lookup). Document this explicitly.
- **(b)** Consolidate into `resource_snapshot` only. Remove the flat top-level key.

**Decision:**

---

### L-9. `dimension_costs` examples show 2 decimal places; `daily_cost` stores 10

`BILLING.md` and `002-resource-models.prp.md` examples show `dimension_costs` values like `"131.51"`, `"6.58"` (2 decimal places). But `InvoiceDailyCost.daily_cost` is `DecimalField(decimal_places=10)`. Since `daily_cost` is the sum of `dimension_costs` values, rounding them to 2 places before summing would lose precision.

Proposal: update `dimension_costs` examples to show full Decimal precision (e.g., `"6.5753424657"`) or add a note that the examples are simplified and actual values use full Decimal precision.

**Decision:**

---

### L-10. `InvoiceLine.description` fallback format not in `BILLING.md`

`002-resource-models.prp.md` defines a fallback: `{ResourceType} #{resource_id}` (e.g., `StorageHotel #101`) when `name` is blank. `BILLING.md` mentions "human-readable description" without specifying this rule.

Proposal: add the fallback format to `BILLING.md`'s line-level snapshot section, or add a cross-reference to `002-resource-models.prp.md`.

**Decision:**

---

### L-11. `RETIRED → ACTIVE` prohibition not stated in `002-resource-models.prp.md`

`004-resource-api.prp.md` explicitly forbids `RETIRED → ACTIVE` ("prevents accidental rebilling"). `002-resource-models.prp.md` lists lifecycle states but does not mention forbidden transitions.

Proposal: add a brief transition rules table or note to `002-resource-models.prp.md` listing both allowed and forbidden transitions, or add a cross-reference to `004-resource-api.prp.md`.

**Decision:**

---

### L-12. `filesystem_identifier` and `quota_unit` immutability after creation undocumented

`004-resource-api.prp.md` lists patchable fields for StorageHotel PATCH (`name`, `billing_account`, `active_from`, `active_to`, `status`) but does not mention `filesystem_identifier` or `quota_unit`. It is unclear whether their omission means they are immutable after creation.

If `quota_unit` can be changed, all future snapshot normalizations for that resource would use the new unit — a billing correctness risk. If `filesystem_identifier` can be changed, the UNIQUE constraint behavior changes.

Proposal: explicitly document that `filesystem_identifier` and `quota_unit` are **not patchable** after creation. Similarly document that VirtualMachine's `provisioner` is not patchable.

**Decision:**

---

### L-13. `updated_at` missing from "not patchable" exclusion list in `005-pricing-api.prp.md`

`005-pricing-api.prp.md` says: "All fields are patchable except `id`, `created_at`." It omits `updated_at`, which is auto-populated (`auto_now=True`) and not writable via the API.

Proposal: update the exclusion list to: "All fields are patchable except `id`, `created_at`, `updated_at`."

**Decision:**

---

### L-14. `config/settings/tests/` directory in project structure is unexplained

`000-system-overview.prp.md` shows a `config/settings/tests/` directory in the config layout alongside `config/settings/test.py`. No document explains what this directory contains or whether it coexists with `test.py`.

Two options:
- **(a)** `config/settings/tests/` is an error. Remove it; only `config/settings/test.py` exists.
- **(b)** `config/settings/tests/` is intentional — document its purpose.

**Decision:**

---
