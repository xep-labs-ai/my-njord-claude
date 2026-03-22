# Review Clarifications 8

Architecture review round 8 findings requiring your input before implementation.
Edit each `**Decision:**` line with your answer.

---

## CRITICAL

### C-1. InvoiceDailyCost: one row per resource per day vs. one row per dimension per day

`BILLING.md` and `002-resource-models.prp.md` both state "one `InvoiceDailyCost` row per resource per day."

But:
- The unique constraint on `InvoiceDailyCost` includes `pricing_dimension`
- `virtual-machine.prp.md` explicitly says "each dimension has its own daily `InvoiceDailyCost` row"
- The `pricing_dimension` field lists `cpu_count`, `ram_gb`, `disk_gb` as valid values for VirtualMachine

These are incompatible. A VirtualMachine billed on one day would have either 1 row (per-resource) or 3 rows (per-dimension).

**Decision:** Which model is correct?
- **(a)** One row per resource per day — `pricing_dimension` is always a constant like `"all"` for multi-dimension resources, and per-dimension breakdown lives in metadata
- **(b)** One row per dimension per day — VirtualMachine produces 3 rows per billed day (cpu, ram, disk); `BILLING.md` and resource model PRP must be corrected

Answer: The following block is my answer:

```
Choose option (a).

Decision:

`InvoiceDailyCost` is one row per resource per day.

For multi-dimension resources such as `VirtualMachine`, the per-dimension billing breakdown is stored in `InvoiceDailyCost.metadata`, not as separate daily rows.

This means the current PRPs must be corrected to be consistent:

- `BILLING.md` remains authoritative for one row per resource per day
- `002-resource-models.prp.md` should use the uniqueness constraint:
  `(invoice_id, resource_type, resource_id, date) UNIQUE`
- `virtual-machine.prp.md` must not say that each dimension gets its own `InvoiceDailyCost` row
- `pricing_dimension` should not be part of the `InvoiceDailyCost` row identity in this design

Reasoning:

- this keeps the daily audit model centered on one resource-day
- it avoids unnecessary row multiplication
- it still preserves full auditability through structured metadata containing normalized usage, resolved prices, and per-dimension cost contributions

One extra cleanup I would recommend is to say explicitly that pricing_dimension belongs to ResourcePrice, not to the identity of InvoiceDailyCost.
```

---

### C-2. InvoiceDailyCost metadata shape: multi-dimension nested vs. single-dimension flat

Directly related to C-1.

`BILLING.md` shows metadata with all three dimensions nested together:
```json
{
  "normalized_usage": {"cpu_count": "8", "ram_gb": "32", "disk_gb": "500"},
  "resolved_prices": {"cpu_count": {...}, "ram_gb": {...}, "disk_gb": {...}},
  "dimension_costs": {"cpu_count": "6.58", "ram_gb": "3.51", "disk_gb": "2.74"}
}
```

`002-resource-models.prp.md` shows a flat single-dimension shape:
```json
{
  "normalized_usage": "<scalar value after unit conversion>",
  "resolved_prices": {"price_per_unit_year": "500.0000", ...},
  "autofilled": false
}
```

**Decision:** Which shape is authoritative? (Answer will follow from C-1.)
- If **(a)** from C-1: the nested multi-dimension shape in `BILLING.md` is correct
- If **(b)** from C-1: the flat single-dimension shape in `002-resource-models.prp.md` is correct, and `BILLING.md` must be updated

Answer is the following block:

```
Choose the nested multi-dimension shape.

Decision:

Because `InvoiceDailyCost` is one row per resource per day, the authoritative metadata shape must support multiple billing dimensions within the same row.

Therefore, the nested shape shown in `BILLING.md` is correct.

`002-resource-models.prp.md` should be updated so that:

- `normalized_usage` is a structured object keyed by pricing dimension
- `resolved_prices` is a structured object keyed by pricing dimension
- `dimension_costs` is used for per-dimension daily cost breakdown
- `autofilled` remains a required boolean

Reasoning:

- a flat scalar shape does not fit multi-dimension resources such as `VirtualMachine`
- the metadata contract must work for both single-dimension and multi-dimension resources
- for single-dimension resources, the structured objects simply contain one entry

Examples:

- StorageHotel: one entry, e.g. `quota_tb`
- VirtualMachine: multiple entries, e.g. `cpu_count`, `ram_gb`, `disk_gb`

Examples:
```
Example: StorageHotel
{
  "normalized_usage": {
    "quota_tb": "120"
  },
  "resolved_prices": {
    "quota_tb": {
      "price_per_unit_year": "400",
      "currency": "NOK",
      "discount_applied": true
    }
  },
  "dimension_costs": {
    "quota_tb": "131.51"
  },
  "autofilled": false
}

Example: VirtualMachine
{
  "normalized_usage": {
    "cpu_count": "8",
    "ram_gb": "32",
    "disk_gb": "500"
  },
  "resolved_prices": {
    "cpu_count": {
      "price_per_unit_year": "300",
      "currency": "NOK",
      "discount_applied": false
    },
    "ram_gb": {
      "price_per_unit_year": "40",
      "currency": "NOK",
      "discount_applied": false
    },
    "disk_gb": {
      "price_per_unit_year": "2",
      "currency": "NOK",
      "discount_applied": false
    }
  },
  "dimension_costs": {
    "cpu_count": "6.58",
    "ram_gb": "3.51",
    "disk_gb": "2.74"
  },
  "autofilled": false
}
```
```

---

### C-3. `make_invoice` still present in per-day billability rule

Round 7 (C-2) decided `make_invoice` is a pre-flight pre-condition, not a per-day condition. But `BILLING.md` still lists it in the per-day billability rule, and `000-system-overview.prp.md` still includes it in the per-day billing logic block.

**Decision:** Confirm these are oversights from the round 7 propagation and should be fixed — remove `make_invoice` from the per-day rule in both files.

Answer: Yes, confirm decision and update `BILLING.md` and `000-system-overview.prp.md` to reflect that `make_invoice` is a pre-flight check, not a per-day condition.

---

### C-4. `force=true` + `autofill=true` + no prior snapshot behavior not propagated

Round 7 (A-4) decided: bill at zero + record in `missing_data_summary` + mark `incomplete=true`. But `BILLING.md` still says "resource still fails unless force-policy explicitly allows partial continuation."

**Decision:** Confirm this is an oversight and `BILLING.md` should be updated to reflect the A-4 decision explicitly.

Answer: Yes, confirm decision and update `BILLING.md`

---

## HIGH

### A-1. `normalized_usage` shape for StorageHotel InvoiceDailyCost metadata

`normalized_usage` is required in `InvoiceDailyCost.metadata` but no document defines what it looks like for StorageHotel specifically.

StorageHotel converts quota from KB/KIB to TB. So `normalized_usage` would be the TB value used in billing.

Two options:
- **(a)** Scalar string: `"normalized_usage": "10.5"` (the TB value)
- **(b)** Keyed dict: `"normalized_usage": {"quota_tb": "10.5"}`

**Decision:** Which shape? Also confirm: is `pricing_dimension` for StorageHotel always `"quota_tb"`?

Answer is the following block:
```
Choose option (b).

Decision:

For StorageHotel, `normalized_usage` must use the keyed dict shape:

`"normalized_usage": {"quota_tb": "10.5"}`

And yes, the StorageHotel `pricing_dimension` is always `quota_tb` in v1.

Reasoning:

- this keeps the `InvoiceDailyCost.metadata` contract consistent across all resource types
- `normalized_usage` should always be keyed by pricing dimension
- that same structure works for both single-dimension resources like StorageHotel and multi-dimension resources like VirtualMachine

Therefore, StorageHotel should not use a scalar special case; it should use the same keyed metadata shape with a single `quota_tb` entry.
```

---

### A-2. `selection_fingerprint` hashing: algorithm, format, encoding

The canonicalization rules (sort resource_types, sort explicit_resources) are defined, but the hash itself is unspecified:
- What algorithm? (SHA-256? SHA-512? MD5?)
- What is the input to the hash? (JSON string? canonical string?)
- What encoding? (hex digest? base64?)
- `CharField(max_length=128)` — is this intentional? SHA-256 hex = 64 chars, SHA-512 hex = 128 chars.

**Decision:** Specify the algorithm and input format. Example proposal: SHA-256 hex digest of a JSON-serialized canonical payload `{"scope": ..., "resource_types": [...sorted...], "explicit_resources": [...sorted...]}`.

Answer is the following block:
```
Accept the proposal and specify it explicitly.

Decision:

`selection_fingerprint` is the SHA-256 lowercase hex digest of a canonical JSON payload encoded as UTF-8.

Canonical payload shape:

{
  "selection_scope": "<scope>",
  "selected_resource_types": [...sorted...],
  "explicit_resources": [...sorted normalized objects...]
}

Canonicalization rules:

- always include all three keys
- use empty arrays when a component is not applicable
- sort `selected_resource_types` alphabetically
- normalize `explicit_resources` to objects with `resource_type` and `resource_id`
- sort `explicit_resources` by `resource_type`, then `resource_id`
- serialize the JSON without insignificant whitespace
- encode the JSON string as UTF-8 before hashing

Storage:

- `selection_fingerprint` should be stored as `CharField(max_length=64)`

Reasoning:

- SHA-256 is deterministic, standard, and sufficient
- hex encoding is simple and easy to inspect
- a fully specified canonicalization and hashing rule is required for reliable uniqueness enforcement
```

---

### A-3. `selection_fingerprint` for `selection_scope = "all_resources"`

When `selection_scope = "all_resources"`, there are no `resource_types` or `explicit_resources`. The canonicalization rules don't cover this case.

**Decision:** What is the canonical payload for `all_resources`? Proposal: `{"scope": "all_resources"}` with no additional keys — fingerprint is the hash of this fixed string.

Answer is the following block, you can ask more about it or fight it if you want:

```
Reject the minimal payload proposal.

Decision:

The canonical payload for `selection_scope = "all_resources"` must use the same schema as other selection scopes, with empty arrays for non-applicable fields.

Canonical payload:

{
  "selection_scope": "all_resources",
  "selected_resource_types": [],
  "explicit_resources": []
}

The `selection_fingerprint` is the SHA-256 hex digest of the UTF-8 encoded canonical JSON serialization of this payload.

Reasoning:

- using a consistent payload schema across all scopes avoids special-case logic
- it keeps canonicalization deterministic and simpler to implement
- it ensures uniqueness enforcement behaves consistently across all selection modes

One small refinement I would also recommend documenting is that the JSON serialization must use stable key ordering (selection_scope, selected_resource_types, explicit_resources) to guarantee deterministic hashing.
```

---

### M-1. Billing account reassignment mid-period

A resource's `billing_account` FK is patchable. If a resource is moved from Account A to Account B on Jan 16, and Account A's invoice covers Jan 1–31:
- The billing engine queries resources by their **current** FK — the resource is no longer under Account A
- It will be missed entirely from Account A's invoice and will appear on Account B's invoice for the full period

This is a silent billing correctness risk. Two options:
- **(a)** Document as a v1 limitation: billing account is resolved at generation time; historical assignment is not tracked
- **(b)** Make `billing_account` immutable once `active_from` is set; reassignment requires creating a new resource record

**Decision:** Which option?

Answer is the following block:

```
Choose option (a), and document it explicitly as a v1 limitation.

Decision:

In v1, `billing_account` remains patchable. Billing ownership is resolved from the resource’s current `billing_account` at invoice-generation time.

This is a known limitation: historical billing-account assignment is not tracked.

Reasoning:

- billing-account reassignment is a common human correction workflow and must be allowed in practice
- forcing a new resource record for every correction would add significant operational friction
- because v1 does not track assignment history, the system cannot reconstruct which account owned the resource on each historical day

Required documentation note:

If a resource’s `billing_account` is changed after historical usage has been captured, invoice generation for past periods will use the resource’s current `billing_account`, not historical ownership.

Operational rule:

- changing `billing_account` is allowed as an administrative correction
- previously generated draft invoices for affected periods should be regenerated before finalization
- already finalized invoices remain immutable and are not modified by later reassignment

A good extra sentence to add is:

This limitation should be revisited in a future version by introducing historical billing-account assignment tracking if reassignment becomes frequent enough to affect billing correctness materially.
```

---

## MEDIUM

### M-2. `active_from > active_to` validation on resources

No document states that `active_to >= active_from` must be enforced. A resource with an invalid date range (`active_from = 2026-06-01`, `active_to = 2026-01-01`) would produce undefined billing behavior.

**Decision:** Confirm that `active_to >= active_from` must be enforced at the service layer (and ideally as a DB check constraint). Should this be added to `002-resource-models.prp.md` and `004-resource-api.prp.md`?

Accept decission and document it explicitly in both `002-resource-models.prp.md` and `004-resource-api.prp.md`. Also recommend adding a DB check constraint to enforce this at the database level for data integrity

---

### M-3. Price list change on BillingAccount mid-period

`price_list` is patchable on `BillingAccount`. Changing it mid-year would affect all future invoice generation for uninvoiced historical periods (the billing engine uses the current FK value).

**Decision:** Should the docs explicitly warn that changing `price_list` affects retroactive billing for uninvoiced periods? Or should `price_list` be made immutable after creation?

Answer is the following block:

```
Choose the explicit-warning approach for v1.

Decision:

`BillingAccount.price_list` remains patchable in v1, but the docs must explicitly warn that billing uses the account’s current `price_list` at invoice-generation time.

This is a known limitation: historical price-list assignment is not tracked.

Reasoning:

- changing `price_list` may be necessary as an administrative correction workflow
- making it immutable in v1 would be operationally too rigid
- because v1 does not track historical price-list assignment, changing the current `price_list` can affect invoice generation for uninvoiced historical periods

Required documentation note:

If `BillingAccount.price_list` is changed after historical usage has been captured, future invoice generation for uninvoiced periods will use the current `price_list`, not the historically intended one.

Operational rule:

- `price_list` changes are allowed in v1
- affected draft invoices should be regenerated before finalization
- already finalized invoices remain immutable and are not changed by later `price_list` updates

A strong follow-up note would be to say this should be revisited later by introducing historical price-list assignment tracking if retroactive corrections become common.
```

---

### M-7. VirtualMachine autofill: all three dimensions carried forward atomically

`virtual-machine.prp.md` does not mention autofill behavior. When a day is missing, autofill must carry forward all three dimensions together from the last known `VirtualMachineDailyUsage` row — not individual dimensions independently.

**Decision:** Confirm this rule and add it explicitly to `virtual-machine.prp.md`.

Accept the proposal and update `virtual-machine.prp.md`

---

### IE-1. Invoice API responses missing `selection_scope` and `selection_fingerprint` as top-level fields

`selection_scope` and `selection_fingerprint` are now real DB columns on `Invoice`. All response examples in `003-invoice-api.prp.md` (generate, list, detail, finalize) only show these inside `metadata`, not as top-level fields.

**Decision:** Confirm these must appear as top-level fields in all Invoice response serializations. Should `selection_fingerprint` be exposed in the API at all, or is it an internal implementation detail?

Answer is the following block:

```
Confirm `selection_scope` must appear as a top-level field in all Invoice response serializations.

Do not expose `selection_fingerprint` in the public API in v1.

Decision:

- `selection_scope` is a business-relevant Invoice field and must be serialized at the top level in generate, list, detail, and finalize responses
- `selection_fingerprint` is an internal implementation field used for uniqueness and duplicate-prevention, and should remain internal unless a concrete API use case appears later

Reasoning:

- `selection_scope` helps clients understand what the invoice covers
- it is now a real DB column and should not appear only indirectly through metadata
- `selection_fingerprint` is not needed for normal client behavior and would expose internal implementation detail without clear value

Documentation update:

`003-invoice-api.prp.md` response examples should be updated so `selection_scope` is top-level.
`selection_fingerprint` should be omitted from public response examples in v1.

A small extra cleanup I would recommend is to make sure selected_resource_types and explicit_resources stay grouped under metadata or another clearly named snapshot section, since those are still part of the selection snapshot rather than primary top-level invoice identity.
```

---

### AG-1. Error `code` values for 409 Conflict scenarios

`API.md` defines a structured error format with a `code` field, but no specific `code` values are defined for 409 scenarios:
- Duplicate draft invoice
- Duplicate finalized invoice
- Duplicate snapshot submission
- Already-finalized invoice (on finalize or generate attempt)
- Price row already closed (on `set-effective-to`)

**Decision:** Define the error codes for each 409 scenario. Proposal:
- `duplicate_draft_invoice`
- `duplicate_finalized_invoice`
- `duplicate_snapshot`
- `invoice_already_finalized`
- `price_row_already_closed`

Accept or modify? Accept the proposal

---

### AG-2. 400 vs 422 for billing domain failures

Currently all errors from the generate endpoint return 400. But there is a meaningful difference between:
- **400**: malformed request (missing required JSON field, invalid date format)
- **Domain failure**: valid request but billing engine fails (no pricing found, no billable resources, missing snapshots without `force=true`)

**Decision:** Should billing domain failures return 422 (Unprocessable Entity) instead of 400? Or consolidate everything on 400 with distinct `code` values?

Answer should billing domain failures with 422 to distinguish them from syntactic/validation errors, and use structured error codes for specific failure reasons.

---

### BG-1. Resource with zero billable days in the selected period

A resource with `active_from = 2026-02-01` billed over `2026-01-01`–`2026-01-31` has zero billable days. No document defines the behavior.

**Decision:** Confirm the rule: resources with zero billable days in the period are silently excluded — no `InvoiceLine`, no `InvoiceDailyCost` rows created. Or should they appear with `total_cost = 0`?

Answer is the following block and document it

```
Confirm the exclusion rule.

Decision:

Resources with zero billable days in the selected period are silently excluded.

No `InvoiceLine` is created, and no `InvoiceDailyCost` rows are created.

Reasoning:

- a resource should appear in an invoice only if it is billable on at least one day in the selected period
- resources with zero billable days are outside the effective billing scope for that invoice
- including them with `total_cost = 0` would add noise and blur the distinction between out-of-scope resources and genuinely billed resources with zero-cost days
```

---

### BG-2. `force=false` + `autofill=true` + no prior snapshot: invoice fails or resource skipped?

If `force=false` and `autofill_missing_days=true` and a resource has no prior snapshot for a missing day, does:
- **(a)** The entire invoice generation fail (fatal error)
- **(b)** Only that resource fail / be skipped

**Decision:** Which behavior? Fail and document it

---

### A-5. `ram_mb` to `ram_gb`: binary GiB (÷1024) or SI GB (÷1000)?

`virtual-machine.prp.md` says divide by 1024 (binary) but calls the result "GB". In practice, hypervisors use binary (GiB), but the naming is misleading.

**Decision:** Is "GB" in this system intentionally binary (GiB = 1024 MB)? If yes, add a clarifying note that "GB" throughout this system means binary gigabytes, consistent with hypervisor conventions.

```
Confirm that "GB" in this system represents binary gigabytes (GiB).

Decision:

`ram_mb` is converted to `ram_gb` using binary conversion:

ram_gb = ram_mb / 1024

This follows the conventions used by virtualization platforms where memory sizes are expressed in binary units.

Documentation update:

Add a note to `virtual-machine.prp.md` stating that the term "GB" in this system represents binary gigabytes (GiB), even though the field name uses the conventional "GB" label.
```

---

### MI-1. `filesystem_identifier UNIQUE` constraint missing from `002-resource-models.prp.md`

`storage-hotel.prp.md` defines `filesystem_identifier` as UNIQUE. This constraint is missing from `002-resource-models.prp.md`'s StorageHotel field definitions.

**Decision:** Confirm the constraint exists and add it to `002-resource-models.prp.md`.

Accept the decision

---

## LOW

### A-4. `InvoiceLine.total_cost` is `decimal_places=6`, not "full precision"

`BILLING.md` says `InvoiceLine.total_cost` is kept at "full Decimal precision." But the field is `DecimalField(decimal_places=6)`, which truncates. Summing 31 daily costs at 6 decimal places will differ slightly from summing at full Python Decimal precision then storing.

**Decision:** Should `decimal_places` be increased (e.g., 10), or should the documentation be corrected to say "6 decimal places" instead of "full precision"?

Increase decimal_places to 10 to better align with the "full precision" claim in the documentation

---

### C-6. `InvoiceLine.total_cost` formula missing dimension axis

`BILLING.md` says: "`InvoiceLine.total_cost` = sum of `InvoiceDailyCost.daily_cost` across all billed days for that resource."

If C-1 answer is (b) (one row per dimension per day), the formula is missing the dimension axis. It should read: "across all billed days **and all pricing dimensions** for that resource."

**Decision:** Update the formula once C-1 is resolved.

Accept the decision and update the formula in `BILLING.md` to include "and all pricing dimensions" once C-1 is resolved.

---

### SR-1. `TESTING.md` execution example uses old path

`TESTING.md` has an example using `pytest tests/services/test_invoice_generation.py` — the old flat layout. Round 7 C-3 updated the canonical layout to `apps/<app>/tests/` but this example was missed.

**Decision:** Confirm this should be updated to `pytest apps/billing/tests/test_invoice_generation.py`.

Accept the decision

---

### M-4. `UNASSIGNED → RETIRED` state transition

The resource state machine covers `UNASSIGNED → ACTIVE` and `ACTIVE → RETIRED` but not `UNASSIGNED → RETIRED` (e.g., a resource provisioned by mistake that never became active).

**Decision:** Is `UNASSIGNED → RETIRED` allowed? If yes, is `active_to` required for this transition?

Answer is the following block:

```
Yes.

Decision:

`UNASSIGNED -> RETIRED` is allowed in v1.

Reasoning:

- this covers resources that were created, provisioned, or discovered by mistake but never entered active billable service
- forcing them through `ACTIVE` would create fake lifecycle history

`active_to` is not required for this transition.

Reasoning:

- `active_to` represents the last billable day
- a resource that was never `ACTIVE` had no billable lifecycle
- therefore there is no billable end date to record

Rule:

- for `UNASSIGNED -> RETIRED`, `active_from` and `active_to` may both remain null
- such resources have zero billable days and never appear in invoices
```

---

### IE-3. Invoice list response: intentional field subset or accidental omission?

The `GET /invoices/` list response example omits `metadata`, `finalized_at`, `selection_scope`, and `selection_fingerprint`. It is unclear whether this is a deliberate lightweight serializer or an accidental gap.

**Decision:** Does the list endpoint return the full Invoice object or a reduced subset? If reduced, which fields are intentionally excluded?

Answer is the following block:

```
Decision:

`GET /api/v1/invoices/` should use a reduced summary serializer in v1, not the full Invoice object.

This omission should be intentional, not accidental.

Recommended behavior:

The list response should include:
- `id`
- `invoice_number`
- `billing_account`
- `period_start`
- `period_end`
- `currency`
- `status`
- `total_cost`
- `selection_scope`
- `created_at`
- `finalized_at`
- `incomplete`

The list response should intentionally exclude:
- `metadata`
- `selection_fingerprint`

Reasoning:

- the list endpoint is for browsing and filtering, so it should return a lightweight summary
- `metadata` is potentially large and belongs in the detail response
- `selection_fingerprint` is an internal implementation detail and should not be exposed in the public API in v1
- `selection_scope` and `finalized_at` are lightweight and business-relevant, so they should be included in the list serializer

The detail endpoint (`GET /api/v1/invoices/{id}/`) should return the full invoice representation.
```

---

### IE-4. Finalize response: full object or minimal confirmation?

The finalize response example only shows `id`, `invoice_number`, `status`, `finalized_at`, `total_amount`, `currency`. Is this intentional or should it return the full Invoice object?

**Decision:** Full Invoice object or minimal confirmation payload?

Answer is the following block:

```
Decision:

`POST /api/v1/invoices/{id}/finalize` should return the full finalized Invoice object in v1.

Reasoning:

- finalization is a major state transition
- clients typically need the authoritative post-finalization invoice immediately
- returning the full object avoids an unnecessary follow-up GET
- this keeps the API simpler and more consistent, since the mutation endpoint returns the resulting resource state

Rule:

- the finalize response should use the same serializer shape as the invoice detail endpoint
- internal implementation fields such as `selection_fingerprint` should still remain excluded from the public API
```

---

### MI-2. VirtualMachine InvoiceDailyCost metadata fields marked optional but decided required

Round 5 DQ12 accepted that `cpu_count`, `ram_gb`, `disk_gb`, and `dimension_costs` in VM InvoiceDailyCost metadata are required. But `virtual-machine.prp.md` still lists these under "Optional fields (VM-specific)."

**Decision:** Confirm `cpu_count`, `ram_gb`, `disk_gb` are required in VM InvoiceDailyCost metadata. Update `virtual-machine.prp.md`.

Answer is the following block:

```
Accept the decision and update `virtual-machine.prp.md`.

Decision:

For `VirtualMachine`, `InvoiceDailyCost.metadata` must include the full per-dimension billing data in v1.

Required VM metadata fields:

- `cpu_count`
- `ram_gb`
- `disk_gb`
- `dimension_costs`

Reasoning:

- VM billing is dimension-based across CPU, RAM, and disk
- one `InvoiceDailyCost` row represents one VM on one billed day
- the row must therefore contain the complete per-dimension billing state needed to explain and reproduce `daily_cost`

Documentation update:

`virtual-machine.prp.md` should remove these fields from the "optional" section and mark them as required VM-specific metadata fields.
```

---

### M-10. `on_delete` behavior for InvoiceLine.invoice and InvoiceDailyCost.invoice FKs

Neither FK specifies `on_delete`. For draft replacement (Invoice deleted → children deleted), `CASCADE` is the expected behavior.

**Decision:** Confirm `on_delete=CASCADE` for both FKs. Add to `002-resource-models.prp.md`.

Accept the decision

---

### SR-3. Resource template uses `/usage` but StorageHotel uses `/quota`

`_resource-template.prp.md` shows `POST /<resources>/{id}/usage` as the ingestion endpoint. StorageHotel uses `/quota`. The template does not note that this path varies by resource type.

**Decision:** Add a note to the template that the ingestion endpoint name is resource-specific and must be defined per resource PRP.

Answer is the following block:

```
Accept the proposal.

Decision:

The resource template must explicitly state that the ingestion endpoint name is resource-specific and must be defined by each resource PRP.

The `/usage` path shown in `_resource-template.prp.md` is only a placeholder example.

Reasoning:

Different resource types ingest different kinds of billing snapshots (e.g., StorageHotel quota vs VirtualMachine capacity). Forcing a generic `/usage` endpoint would produce misleading API semantics.

Documentation update:

Add a note to `_resource-template.prp.md` stating that the ingestion endpoint path must be defined per resource and should reflect the type of billing data being ingested.

A good optional rule you might add later is:

Prefer singular, domain-specific nouns for ingestion endpoints (e.g., `/quota`, `/usage`, `/capacity`, `/allocation`).
```

---

### M-5. Recalculation endpoint: stub spec needed for v2 planning

`POST /api/v1/invoices/{id}/recalculate` is listed as v2 but has no definition. No one knows if it deletes and rebuilds, re-uses the same selection params, or accepts new flags.

**Decision:** Should a brief stub specification be added now? Proposal: "Recalculation re-executes billing for an existing draft invoice using the same `selection_scope` and `selection_fingerprint`. All existing InvoiceLines and InvoiceDailyCosts are replaced. `force` and `autofill_missing_days` flags may be re-specified."

Answer is the following block:

```
Accept the proposal in principle, but phrase it slightly more clearly.

Decision:

Yes, a brief v2 stub specification should be added now.

Recommended stub:

`POST /api/v1/invoices/{id}/recalculate` is a draft-only operation.

It re-executes billing for an existing draft invoice using the invoice’s stored billing context and stored selection snapshot.

Behavior:

- re-use:
  - `billing_account`
  - `period_start`
  - `period_end`
  - `selection_scope`
  - stored selection data
- delete and rebuild all existing `InvoiceLine` and `InvoiceDailyCost` rows
- recompute invoice totals
- preserve the same Invoice record and draft status

Flags:

- `force` may be re-specified
- `autofill_missing_days` may be re-specified

Restrictions:

- finalized invoices cannot be recalculated
- recalculation does not change invoice identity
- recalculation does not accept a new billing account, period, or selection scope

Reasoning:

This gives the v2 endpoint a clear intended meaning without over-specifying implementation details too early.
```
