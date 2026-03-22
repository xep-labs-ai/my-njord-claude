# Review Clarifications 11

Architecture review round 11 — consistency pass after round-10 changes.
Edit each `**Decision:**` line with your answer.

---

## HIGH

### H-1. Double-billing risk — same resource billed across different selection scopes for the same period

The duplicate prevention constraint is per `(billing_account, period_start, period_end, selection_scope, selection_fingerprint)`. This allows:

1. Generate invoice for account A, Jan 2026, scope `all_resources` → bills resource X
2. Generate invoice for account A, Jan 2026, scope `explicit_resources` including resource X → bills resource X again

Resource X now appears on two different invoices for the same period. No document addresses this risk.

Three options:
- **(a)** Document as a known v1 limitation with an operational rule: "do not generate invoices with overlapping resource selections for the same billing account and period." Finalization is the safeguard — operators must not finalize overlapping invoices.
- **(b)** Add a cross-invoice check during generation: before billing a resource-day, verify no other invoice for the same billing account and period already includes that resource-day.
- **(c)** Add a database uniqueness constraint on `InvoiceDailyCost` preventing the same `(billing_account, resource_type, resource_id, date)` from appearing in multiple finalized invoices.

Proposal: **(a)** for v1. A cross-invoice check would require joining across multiple invoice records during generation — complex and potentially slow. A DB constraint on `InvoiceDailyCost` would require denormalizing `billing_account` onto that table. For v1, document this as an explicit operational limitation with clear guidance.

**Decision:**

Accept proposal a

---

### H-2. Snapshot ingestion on RETIRED or soft-deleted resources — behavior undefined

No document specifies what should happen when a snapshot ingestion is attempted for a resource that is RETIRED or soft-deleted. Two realistic scenarios:

1. A resource is retired today. Tomorrow, the ingestion system sends yesterday's snapshot (delayed delivery). Should the snapshot be accepted?
2. A soft-deleted resource receives an ingestion attempt — the default manager returns 404.

Options:
- **(a)** RETIRED resources: allow ingestion (the date validation already ensures the snapshot is historical and the resource was billable on that date). Soft-deleted: reject with 404 (soft-delete implies administrative removal).
- **(b)** Reject ingestion for both RETIRED and soft-deleted resources with a clear error response.
- **(c)** Allow ingestion regardless of status, relying entirely on the date-based billing window to control what is billed.

Proposal: **(a)**. RETIRED resources are the normal end-of-life state and late-arriving snapshots are legitimate. Soft-deleted resources are administrative removals and should return 404. Document this explicitly in `004-resource-api.prp.md`.

**Decision:**

Answer is the following block: 

```
Choose option (a).

Decision:

- snapshot ingestion for RETIRED resources is allowed in v1
- snapshot ingestion for soft-deleted resources is rejected

Reasoning:

- RETIRED is the normal end-of-life state, and delayed delivery of historical snapshots is a legitimate operational scenario
- billing correctness is controlled by the snapshot date and the resource's billing window, not only by the current lifecycle state
- soft-deleted resources represent administrative removal and should not remain valid ingestion targets

Recommended rule:

- if a resource is RETIRED, ingestion may still be accepted for a valid historical snapshot date
- if a resource is soft-deleted, ingestion must be rejected
- future-dated snapshots remain invalid regardless of status

Documentation update:

`004-resource-api.prp.md` should explicitly state that RETIRED resources may accept historical delayed snapshots, while soft-deleted resources are not valid ingestion targets in v1.
```

---

## MEDIUM

### M-1. `resource_snapshot.name` in API examples shows the fallback string instead of a real name

In `003-invoice-api.prp.md` detail response, `resource_snapshot.name` is shown as `"StorageHotel #101"` — the same string as the description fallback. This conflates the snapshot's actual `name` field with the description construction rule. The `name` in `resource_snapshot` should be the resource's real `name` field value (e.g., `"storage-primary"`), not the fallback string.

Proposal: update the `resource_snapshot.name` in `003-invoice-api.prp.md` examples to show a realistic resource name (e.g., `"storage-primary"` for StorageHotel, `"vm-prod-001"` for VirtualMachine). The description fallback `"StorageHotel #101"` should only appear in the `description` field.

**Decision:**

Answer is the following block: 

```
Accept the proposal.

Decision:

Update the `resource_snapshot.name` examples in `003-invoice-api.prp.md` to show realistic resource names (for example `"storage-primary"` or `"vm-prod-001"`). The fallback string `"StorageHotel #101"` should appear only in the `description` field.

Reasoning:

- `resource_snapshot` stores the actual resource attributes captured at billing time
- `InvoiceLine.description` is a constructed human-readable label that may fall back to `{ResourceType} #{resource_id}` when the resource name is blank
- showing the fallback string inside `resource_snapshot.name` conflates these two concepts and could lead to incorrect implementations

Documentation update:

Ensure the examples clearly distinguish between:
- `resource_snapshot.name` → real resource name
- `description` → generated display string that may use the fallback format
```

---

### M-2. `POST /generate` response — unclear whether `lines` are included

The generate response body example in `003-invoice-api.prp.md` does not include `lines`. The detail endpoint clearly returns lines. There is no explicit statement about whether generate returns lines or only the invoice header.

Two options:
- **(a)** Generate returns the full invoice including `lines` — same shape as the detail endpoint. Add lines to the generate response example.
- **(b)** Generate returns only the invoice header (no `lines`). Lines are available via the detail endpoint. Document this explicitly.

Proposal: **(a)**. The caller needs to know immediately what was generated — returning lines avoids a mandatory follow-up GET. This also keeps generate/detail/finalize responses consistent in shape.

**Decision:**

Accept proposal a

---

### M-3. StorageHotel PRP "Invoice expectations" section omits `resource_snapshot`

`storage-hotel.prp.md` has an "Invoice expectations" section showing the `InvoiceLine.metadata` standard structure but the example JSON does not include `resource_snapshot`. The canonical `resource_snapshot` schema is defined in the same PRP just above, but the invoice expectations example is incomplete.

Proposal: add `resource_snapshot` to the example JSON in the "Invoice expectations" section of `storage-hotel.prp.md`, or add a cross-reference note: "the complete metadata also includes `resource_snapshot` as defined in the Canonical `resource_snapshot` Schema section above."

**Decision:**

Answer is the following block:

```
Accept the proposal.

Decision:

Update the example JSON in the "Invoice expectations" section of `storage-hotel.prp.md` to include `resource_snapshot`.

Reasoning:

- `resource_snapshot` is a required audit field for invoice snapshots
- the current example omits it, which could lead implementers to believe it is optional
- examples should reflect the full required metadata structure whenever possible

Action:

Add `resource_snapshot` to the example JSON in the "Invoice expectations" section, using the canonical schema already defined earlier in the PRP. Optionally add a short note clarifying that the example includes the required snapshot defined above.
```

---

### M-4. `003-invoice-api.prp.md` StorageHotel InvoiceLine metadata missing top-level `quota_unit`

Round 10 L-8 decided that `quota_unit` and `provisioner` intentionally appear both as flat top-level keys in `InvoiceLine.metadata` AND inside `resource_snapshot`. But the StorageHotel InvoiceLine metadata example in `003-invoice-api.prp.md` does not include `quota_unit` as a top-level key — only inside `resource_snapshot`. The redundancy rule is not consistently applied in the API PRP example.

Proposal: add `"quota_unit": "KIB"` as a top-level key in the StorageHotel `InvoiceLine.metadata` example in `003-invoice-api.prp.md`.

**Decision:**

Accept the proposal.

---

### M-5. `active_from` required at creation creates silent backdated billing risk for UNASSIGNED resources

`active_from` is required at resource creation time. An UNASSIGNED resource created on March 1 with `active_from = 2026-01-01` that is activated on June 1 would silently generate a billing window starting January 1 — a 5-month backdated billing window the operator may not have intended.

No document warns about this risk or provides guidance on what `active_from` should represent for UNASSIGNED resources.

Proposal: add a note to `004-resource-api.prp.md` and `002-resource-models.prp.md` clarifying: "`active_from` represents the first day the resource is billable. For resources that start in UNASSIGNED status, operators should set `active_from` to the intended billing start date, not the creation date. Activating a resource does not automatically update `active_from`."

**Decision:**

Accept the proposal

---

### M-6. `resource_id` type in fingerprint canonical JSON — string or integer?

The fingerprint canonical payload schema in `001-billing-engine.prp.md` shows `"resource_id": "..."` (a string). But `resource_id` on `InvoiceLine` and `InvoiceDailyCost` is a `PositiveIntegerField`. The canonicalization rules do not specify whether `resource_id` in the canonical JSON should be a string or an integer. This matters for hash determinism: `{"resource_id": 101}` and `{"resource_id": "101"}` produce different SHA-256 hashes.

Proposal: explicitly state in `001-billing-engine.prp.md` that `resource_id` in the canonical fingerprint JSON is serialized as an **integer** (not a string), consistent with its model type. Update the schema example if it currently shows it as a string.

**Decision:**

Answer is the following block:

```
Accept the proposal.

Decision:

`resource_id` in the canonical fingerprint JSON must be serialized as an integer, not a string.

Reasoning:

- the selection fingerprint must be deterministic
- JSON values `"101"` and `101` produce different SHA-256 hashes
- since `resource_id` is defined as a `PositiveIntegerField` in the data model, the canonical JSON representation should preserve that numeric type

Action:

Update the canonical payload schema in `001-billing-engine.prp.md` so that `resource_id` appears as an integer in all examples.

Also add a canonicalization rule stating that numeric identifiers must be serialized as JSON numbers, not strings.
```

---

### M-7. Non-billable Days Rule doesn't distinguish from force-mode zero-cost rows

`BILLING.md` "Non-billable Days Rule" says non-billable days produce no `InvoiceDailyCost` row. But `force=true` with missing snapshot data bills those days at zero and DOES produce an `InvoiceDailyCost` row (`daily_cost = 0`, `autofilled = true`). These are two different concepts that a reader could conflate:

- **Non-billable** = resource outside its active window → no row ever
- **Billable day with missing snapshot + force=true** → zero-cost row IS produced

Proposal: add a clarifying note to the Non-billable Days Rule section in `BILLING.md` explicitly distinguishing these two cases. Something like: "This rule applies to days outside the resource's billing window. It is distinct from billable days where snapshot data is missing — see Force Mode behavior."

**Decision:**

Accept the proposal

---

## LOW

### L-1. Discount threshold exact boundary — no explicit test or example

The discount rule uses `usage >= threshold → discounted price`. This is consistent across `001-billing-engine.prp.md` and `TESTING_TEMPLATES.md`. However, no test template or example explicitly covers the case where daily usage exactly equals the threshold (e.g., 10 TB with threshold = 10 TB). This is the most important boundary case for billing correctness.

Proposal: add a note or small test scenario to `TESTING_TEMPLATES.md` explicitly confirming that `usage == threshold` receives the discount price (`>=` operator). This can be a brief note on RT-26 or a new micro-scenario RT-27.

**Decision:**

Accept the proposal

---

### L-2. `set-effective-to` uses PATCH verb but action semantics suggest POST

`005-pricing-api.prp.md` specifies `PATCH /api/v1/price-lists/{id}/resource-prices/{id}/set-effective-to/`. DRF `@action` defaults to `POST` for non-safe methods. Using `PATCH` requires explicitly setting `methods=["patch"]` on the action decorator. An implementer following DRF conventions would default to `POST`.

Two options:
- **(a)** Keep `PATCH` — it conveys partial-update semantics (only `effective_to` is being set). Add a note that the DRF `@action` must explicitly set `methods=["patch"]`.
- **(b)** Change to `POST` — cleaner match with action semantics and DRF defaults.

**Decision:**

Accept proposal b

---

### L-3. Snapshot model naming — template says `DailyUsage`, StorageHotel uses `DailyQuota`

`_resource-template.prp.md` uses `<ResourceName>DailyUsage` as the snapshot model naming convention. StorageHotel deviates with `StorageHotelDailyQuota`. VirtualMachine follows the template with `VirtualMachineDailyUsage`.

Proposal: add a note to `_resource-template.prp.md` that the `DailyUsage` suffix is a convention suggestion. Resource-specific suffixes (e.g., `DailyQuota`, `DailyCapacity`) are acceptable when the domain term is clearer.

**Decision:**

Accept the proposal

---

### L-4. CLAUDE.md routing table missing row for resource status transitions

Resource status transitions (UNASSIGNED → ACTIVE → RETIRED) touch models, the resource API, services, and billing implications. There is no routing table entry for this task.

Proposal: add a row to the CLAUDE.md routing table: "Resource status transitions → Read `004-resource-api.prp.md` | Also read `002-resource-models.prp.md`, `TESTING.md`."

**Decision:**

Accept the proposal

---

### L-5. StorageHotel/VM field lists say "in addition to inherited" but then re-list inherited fields

`002-resource-models.prp.md` StorageHotel and VirtualMachine sections begin with "(in addition to inherited ResourceModel fields including `deleted_at`)" but then the field list re-includes inherited fields like `billing_account`, `status`, `active_from`, `active_to`.

Proposal: change the header from "in addition to inherited" to "all fields (including inherited)" to match the actual listing approach, removing the contradiction.

**Decision:**

Accept the proposal

---

### L-6. No note on whether fractional `ram_mb` values are expected

`VirtualMachineDailyUsage.ram_mb` is `DecimalField(max_digits=14, decimal_places=2)`. The API example shows `"65536"` (integer-like). Hypervisors typically report RAM in whole MB. No document clarifies whether fractional MB values (e.g., `"65536.50"`) are valid or expected.

Proposal: add a brief note to `virtual-machine.prp.md` or `004-resource-api.prp.md` clarifying that `ram_mb` is a whole-number value in practice (hypervisors report whole MB), but `DecimalField` is used for consistency with the billing calculation pipeline. Fractional values are technically accepted but not expected.

**Decision:**

Accept the proposal

---

### L-7. Finalize endpoint 409 says "idempotency conflict" but the behavior is not idempotent

`003-invoice-api.prp.md` labels the already-finalized 409 as "(idempotency conflict)" but true idempotency would return 200 with the finalized invoice. The comment is misleading.

Proposal: remove the "(idempotency conflict)" parenthetical. The 409 is a state conflict, not an idempotency mechanism. Or change the behavior to return 200 with the already-finalized invoice (true idempotency). Simpler fix: just remove the misleading comment.

**Decision:**

Accept the proposal

---

### L-8. Test template quota values labeled KB but math uses TB

`TESTING_TEMPLATES.md` RT-25 and RT-26 label resources as `storage-hotel-01 (KB)`, implying the quota unit is KB. But the quota values in those templates are given directly in TB (e.g., "10 TB", "12 TB") and the pricing math uses TB directly. If the quota unit is KB, then "10 TB" should be expressed as `10,000,000,000 KB` in the test data — which is not what the templates show.

Proposal: change the resource label from `(KB)` to `(TB pricing)` or remove the unit suffix. Add a brief note clarifying that template quota values are given in the billing unit (TB) for readability, not in the raw ingestion unit.

**Decision:**

Accept the proposal

---

### L-9. `provisional` exclusion note in BILLING.md redundant with `metadata` exclusion

`BILLING.md` says "`provisional` is intentionally excluded from the list response in v1." But `provisional` lives inside `metadata`, and `metadata` as a whole is excluded from the list response. The note creates a false impression that `provisional` needs special exclusion logic.

Proposal: update the note in `BILLING.md` to: "`provisional` is excluded from the list response because `metadata` is excluded from the list serializer as a whole — no separate exclusion logic is needed for `provisional`."

**Decision:**

Accept the proposal

---

### L-10. CODING_RULES.md routing header too broad in "do not read" clause

`CODING_RULES.md` says "Do not read this document when: Implementing REST endpoints (see API.md)." But billing endpoints (invoice generation, finalization) require the financial safety rules in CODING_RULES.md (Decimal usage, immutability, no billing logic in views).

Proposal: soften the exclusion to: "Do not read this document when: implementing non-billing REST endpoints. For billing endpoints, also read this document for financial safety rules."

**Decision:**

Accept the proposal

---

### L-11. API response examples show `total_cost` with 2 decimal places but the field is 10

`InvoiceLine.total_cost` is `DecimalField(decimal_places=10)`. API response examples in `003-invoice-api.prp.md` show it as `"1500.50"` (2dp). DRF serializes DecimalField at the field's full precision, so the actual response would be `"1500.5000000000"`.

Proposal: either update the examples to show full precision (e.g., `"1500.5000000000"`) or add a note that line-level costs in examples are simplified and actual values use 10 decimal places.

**Decision:**

Accept the proposal that suggest to update the examples to show full precision

---

### L-12. Resource template missing sections now present in actual resource PRPs

`_resource-template.prp.md` is missing sections that both `storage-hotel.prp.md` and `virtual-machine.prp.md` now include after rounds 1-10:
- Manager Availability
- Soft-Delete Invariants
- Autofill Rule
- Canonical `resource_snapshot` Schema
- Unit Conversion Rules

A future implementer creating a new resource type from the template would miss all of these.

Proposal: update `_resource-template.prp.md` to add placeholder sections for each of the above, with brief guidance on what each should contain.

**Decision:**

Accept the proposal

---

### L-13. RT-25 "Line total (rounded)" label is misleading — rounding applies to invoice total, not line

`TESTING_TEMPLATES.md` RT-25 shows:
- "Line total (rounded): 162.19"
- "Invoice total: 162.19"

`InvoiceLine.total_cost` has 10 decimal places and is NOT rounded. Only `Invoice.total_amount` is rounded to 2dp. The label suggests the line total is rounded, which is incorrect.

Proposal: change "Line total (rounded): 162.19" to remove the "(rounded)" qualifier, and clarify it as "Invoice total_amount (rounded to 2dp): 162.19" to show the rounding happens at the invoice level.

**Decision:**

Accept the proposal

---

### L-14. `Invoice.metadata` — `selection_scope` listed as both a top-level field and a metadata key

`002-resource-models.prp.md` defines `selection_scope` as a top-level database column on `Invoice`. But it also appears in the "metadata may include" list. Unlike `InvoiceDailyCost.autofilled` (where the dual-presence is explicitly documented as intentional), there is no note clarifying whether `selection_scope` should be duplicated in metadata.

Proposal: clarify in `002-resource-models.prp.md` that `selection_scope` is a top-level field and does NOT need to be duplicated in `Invoice.metadata`. Remove it from the metadata list, or if it must remain for snapshot completeness, add an explicit note like the one added for `autofilled`.

**Decision:**

Accept the proposal

---
