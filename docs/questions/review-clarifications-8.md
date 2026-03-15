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

---

### C-3. `make_invoice` still present in per-day billability rule

Round 7 (C-2) decided `make_invoice` is a pre-flight pre-condition, not a per-day condition. But `BILLING.md` still lists it in the per-day billability rule, and `000-system-overview.prp.md` still includes it in the per-day billing logic block.

**Decision:** Confirm these are oversights from the round 7 propagation and should be fixed — remove `make_invoice` from the per-day rule in both files.

---

### C-4. `force=true` + `autofill=true` + no prior snapshot behavior not propagated

Round 7 (A-4) decided: bill at zero + record in `missing_data_summary` + mark `incomplete=true`. But `BILLING.md` still says "resource still fails unless force-policy explicitly allows partial continuation."

**Decision:** Confirm this is an oversight and `BILLING.md` should be updated to reflect the A-4 decision explicitly.

---

## HIGH

### A-1. `normalized_usage` shape for StorageHotel InvoiceDailyCost metadata

`normalized_usage` is required in `InvoiceDailyCost.metadata` but no document defines what it looks like for StorageHotel specifically.

StorageHotel converts quota from KB/KIB to TB. So `normalized_usage` would be the TB value used in billing.

Two options:
- **(a)** Scalar string: `"normalized_usage": "10.5"` (the TB value)
- **(b)** Keyed dict: `"normalized_usage": {"quota_tb": "10.5"}`

**Decision:** Which shape? Also confirm: is `pricing_dimension` for StorageHotel always `"quota_tb"`?

---

### A-2. `selection_fingerprint` hashing: algorithm, format, encoding

The canonicalization rules (sort resource_types, sort explicit_resources) are defined, but the hash itself is unspecified:
- What algorithm? (SHA-256? SHA-512? MD5?)
- What is the input to the hash? (JSON string? canonical string?)
- What encoding? (hex digest? base64?)
- `CharField(max_length=128)` — is this intentional? SHA-256 hex = 64 chars, SHA-512 hex = 128 chars.

**Decision:** Specify the algorithm and input format. Example proposal: SHA-256 hex digest of a JSON-serialized canonical payload `{"scope": ..., "resource_types": [...sorted...], "explicit_resources": [...sorted...]}`.

---

### A-3. `selection_fingerprint` for `selection_scope = "all_resources"`

When `selection_scope = "all_resources"`, there are no `resource_types` or `explicit_resources`. The canonicalization rules don't cover this case.

**Decision:** What is the canonical payload for `all_resources`? Proposal: `{"scope": "all_resources"}` with no additional keys — fingerprint is the hash of this fixed string.

---

### M-1. Billing account reassignment mid-period

A resource's `billing_account` FK is patchable. If a resource is moved from Account A to Account B on Jan 16, and Account A's invoice covers Jan 1–31:
- The billing engine queries resources by their **current** FK — the resource is no longer under Account A
- It will be missed entirely from Account A's invoice and will appear on Account B's invoice for the full period

This is a silent billing correctness risk. Two options:
- **(a)** Document as a v1 limitation: billing account is resolved at generation time; historical assignment is not tracked
- **(b)** Make `billing_account` immutable once `active_from` is set; reassignment requires creating a new resource record

**Decision:** Which option?

---

## MEDIUM

### M-2. `active_from > active_to` validation on resources

No document states that `active_to >= active_from` must be enforced. A resource with an invalid date range (`active_from = 2026-06-01`, `active_to = 2026-01-01`) would produce undefined billing behavior.

**Decision:** Confirm that `active_to >= active_from` must be enforced at the service layer (and ideally as a DB check constraint). Should this be added to `002-resource-models.prp.md` and `004-resource-api.prp.md`?

---

### M-3. Price list change on BillingAccount mid-period

`price_list` is patchable on `BillingAccount`. Changing it mid-year would affect all future invoice generation for uninvoiced historical periods (the billing engine uses the current FK value).

**Decision:** Should the docs explicitly warn that changing `price_list` affects retroactive billing for uninvoiced periods? Or should `price_list` be made immutable after creation?

---

### M-7. VirtualMachine autofill: all three dimensions carried forward atomically

`virtual-machine.prp.md` does not mention autofill behavior. When a day is missing, autofill must carry forward all three dimensions together from the last known `VirtualMachineDailyUsage` row — not individual dimensions independently.

**Decision:** Confirm this rule and add it explicitly to `virtual-machine.prp.md`.

---

### IE-1. Invoice API responses missing `selection_scope` and `selection_fingerprint` as top-level fields

`selection_scope` and `selection_fingerprint` are now real DB columns on `Invoice`. All response examples in `003-invoice-api.prp.md` (generate, list, detail, finalize) only show these inside `metadata`, not as top-level fields.

**Decision:** Confirm these must appear as top-level fields in all Invoice response serializations. Should `selection_fingerprint` be exposed in the API at all, or is it an internal implementation detail?

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

Accept or modify?

---

### AG-2. 400 vs 422 for billing domain failures

Currently all errors from the generate endpoint return 400. But there is a meaningful difference between:
- **400**: malformed request (missing required JSON field, invalid date format)
- **Domain failure**: valid request but billing engine fails (no pricing found, no billable resources, missing snapshots without `force=true`)

**Decision:** Should billing domain failures return 422 (Unprocessable Entity) instead of 400? Or consolidate everything on 400 with distinct `code` values?

---

### BG-1. Resource with zero billable days in the selected period

A resource with `active_from = 2026-02-01` billed over `2026-01-01`–`2026-01-31` has zero billable days. No document defines the behavior.

**Decision:** Confirm the rule: resources with zero billable days in the period are silently excluded — no `InvoiceLine`, no `InvoiceDailyCost` rows created. Or should they appear with `total_cost = 0`?

---

### BG-2. `force=false` + `autofill=true` + no prior snapshot: invoice fails or resource skipped?

If `force=false` and `autofill_missing_days=true` and a resource has no prior snapshot for a missing day, does:
- **(a)** The entire invoice generation fail (fatal error)
- **(b)** Only that resource fail / be skipped

**Decision:** Which behavior?

---

### A-5. `ram_mb` to `ram_gb`: binary GiB (÷1024) or SI GB (÷1000)?

`virtual-machine.prp.md` says divide by 1024 (binary) but calls the result "GB". In practice, hypervisors use binary (GiB), but the naming is misleading.

**Decision:** Is "GB" in this system intentionally binary (GiB = 1024 MB)? If yes, add a clarifying note that "GB" throughout this system means binary gigabytes, consistent with hypervisor conventions.

---

### MI-1. `filesystem_identifier UNIQUE` constraint missing from `002-resource-models.prp.md`

`storage-hotel.prp.md` defines `filesystem_identifier` as UNIQUE. This constraint is missing from `002-resource-models.prp.md`'s StorageHotel field definitions.

**Decision:** Confirm the constraint exists and add it to `002-resource-models.prp.md`.

---

## LOW

### A-4. `InvoiceLine.total_cost` is `decimal_places=6`, not "full precision"

`BILLING.md` says `InvoiceLine.total_cost` is kept at "full Decimal precision." But the field is `DecimalField(decimal_places=6)`, which truncates. Summing 31 daily costs at 6 decimal places will differ slightly from summing at full Python Decimal precision then storing.

**Decision:** Should `decimal_places` be increased (e.g., 10), or should the documentation be corrected to say "6 decimal places" instead of "full precision"?

---

### C-6. `InvoiceLine.total_cost` formula missing dimension axis

`BILLING.md` says: "`InvoiceLine.total_cost` = sum of `InvoiceDailyCost.daily_cost` across all billed days for that resource."

If C-1 answer is (b) (one row per dimension per day), the formula is missing the dimension axis. It should read: "across all billed days **and all pricing dimensions** for that resource."

**Decision:** Update the formula once C-1 is resolved.

---

### SR-1. `TESTING.md` execution example uses old path

`TESTING.md` has an example using `pytest tests/services/test_invoice_generation.py` — the old flat layout. Round 7 C-3 updated the canonical layout to `apps/<app>/tests/` but this example was missed.

**Decision:** Confirm this should be updated to `pytest apps/billing/tests/test_invoice_generation.py`.

---

### M-4. `UNASSIGNED → RETIRED` state transition

The resource state machine covers `UNASSIGNED → ACTIVE` and `ACTIVE → RETIRED` but not `UNASSIGNED → RETIRED` (e.g., a resource provisioned by mistake that never became active).

**Decision:** Is `UNASSIGNED → RETIRED` allowed? If yes, is `active_to` required for this transition?

---

### IE-3. Invoice list response: intentional field subset or accidental omission?

The `GET /invoices/` list response example omits `metadata`, `finalized_at`, `selection_scope`, and `selection_fingerprint`. It is unclear whether this is a deliberate lightweight serializer or an accidental gap.

**Decision:** Does the list endpoint return the full Invoice object or a reduced subset? If reduced, which fields are intentionally excluded?

---

### IE-4. Finalize response: full object or minimal confirmation?

The finalize response example only shows `id`, `invoice_number`, `status`, `finalized_at`, `total_amount`, `currency`. Is this intentional or should it return the full Invoice object?

**Decision:** Full Invoice object or minimal confirmation payload?

---

### MI-2. VirtualMachine InvoiceDailyCost metadata fields marked optional but decided required

Round 5 DQ12 accepted that `cpu_count`, `ram_gb`, `disk_gb`, and `dimension_costs` in VM InvoiceDailyCost metadata are required. But `virtual-machine.prp.md` still lists these under "Optional fields (VM-specific)."

**Decision:** Confirm `cpu_count`, `ram_gb`, `disk_gb` are required in VM InvoiceDailyCost metadata. Update `virtual-machine.prp.md`.

---

### M-10. `on_delete` behavior for InvoiceLine.invoice and InvoiceDailyCost.invoice FKs

Neither FK specifies `on_delete`. For draft replacement (Invoice deleted → children deleted), `CASCADE` is the expected behavior.

**Decision:** Confirm `on_delete=CASCADE` for both FKs. Add to `002-resource-models.prp.md`.

---

### SR-3. Resource template uses `/usage` but StorageHotel uses `/quota`

`_resource-template.prp.md` shows `POST /<resources>/{id}/usage` as the ingestion endpoint. StorageHotel uses `/quota`. The template does not note that this path varies by resource type.

**Decision:** Add a note to the template that the ingestion endpoint name is resource-specific and must be defined per resource PRP.

---

### M-5. Recalculation endpoint: stub spec needed for v2 planning

`POST /api/v1/invoices/{id}/recalculate` is listed as v2 but has no definition. No one knows if it deletes and rebuilds, re-uses the same selection params, or accepts new flags.

**Decision:** Should a brief stub specification be added now? Proposal: "Recalculation re-executes billing for an existing draft invoice using the same `selection_scope` and `selection_fingerprint`. All existing InvoiceLines and InvoiceDailyCosts are replaced. `force` and `autofill_missing_days` flags may be re-specified."
