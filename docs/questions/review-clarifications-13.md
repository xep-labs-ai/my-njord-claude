# Review Clarifications 13

Architecture review round 13 — cross-document consistency audit after rounds 1-12.
Edit each `**Decision:**` line with your answer.

---

## HIGH

### H-1. `clarifications.md` Q1 and Q6 still say 3 InvoiceDailyCost rows per VM per day

`clarifications.md` Q1 states "3 InvoiceDailyCost rows per VM per day" and Q6 states "One row per dimension per day (3 rows per VM per day)." The current PRP design (established in review-clarifications-8 C-1, reflected in `002-resource-models.prp.md`, `001-billing-engine.prp.md`, `BILLING.md`, and `virtual-machine.prp.md`) specifies **one InvoiceDailyCost row per resource per day** with per-dimension breakdown in metadata.

If Claude reads `clarifications.md` before the PRPs, it could implement the wrong granularity -- creating 3 rows per VM per day instead of 1 row with structured metadata. This is a fundamental data model decision.

Proposal: add a `**Superseded:**` marker to Q1 and Q6 in `clarifications.md` stating: "Superseded by review-clarifications-8 C-1. Current design: one InvoiceDailyCost row per resource per day with per-dimension breakdown in metadata. See `002-resource-models.prp.md`."

This is consistent with the precedence rule from round 12 L-2 but adds an explicit marker to prevent misreading, given the severity of the contradiction.

**Decision:**

Accept proposal

---

### H-2. `003-invoice-api.prp.md` description examples show fallback format even when `name` is non-blank

The `description` field in all InvoiceLine examples in `003-invoice-api.prp.md` shows `"StorageHotel #101"` -- the fallback format. However, the `resource_snapshot` in the same examples shows `"name": "storage-primary"` (non-blank). Per the documented construction rule, when `name` is present and non-blank, `description` should be `"storage-primary"`, not the fallback.

Round 11 M-1 updated `resource_snapshot.name` to show realistic names, but the `description` field was not updated to match. The examples are now internally inconsistent: the snapshot has a real name, but the description uses the fallback as if the name were blank.

Proposal: change `"description": "StorageHotel #101"` to `"description": "storage-primary"` in the generate, detail, and finalize response examples in `003-invoice-api.prp.md`. The fallback `"StorageHotel #101"` should only appear in examples where `name` is blank or null.

**Decision:**

Accept proposal

---

### H-3. RETIRED transition automatically sets `deleted_at` -- conflates retirement with soft-delete

`004-resource-api.prp.md` line 418 states: "When a resource transitions to RETIRED via PATCH, the service layer sets `deleted_at` to the current timestamp automatically." This means every retirement is also a soft-delete, which causes RETIRED resources to disappear from default querysets immediately.

However, round 11 H-2 explicitly distinguishes RETIRED from soft-deleted resources for ingestion purposes: RETIRED resources accept late-arriving snapshots, while soft-deleted resources return 404. If retirement automatically sets `deleted_at`, then RETIRED resources are also soft-deleted and would return 404 from the default manager -- contradicting the H-2 decision.

Three options:

- **(a)** Remove the automatic `deleted_at` assignment from the RETIRED transition. Make soft-deletion a separate administrative action (e.g., a dedicated endpoint or a separate PATCH field). RETIRED resources remain visible in default querysets and accept late-arriving ingestion.
- **(b)** Keep the automatic `deleted_at` on RETIRED, but change the ingestion endpoints to use the `billing_objects` manager (which includes soft-deleted resources) for lookup. This preserves H-2 behavior but means ingestion endpoints use a different manager than CRUD endpoints.
- **(c)** Keep the current behavior and accept that RETIRED resources are immediately soft-deleted. Update H-2 to clarify that ingestion for RETIRED resources requires using the `billing_objects` manager for resource lookup.

**Decision:**

Accept proposal a

---

### H-4. Invoice number counter -- PRP says global never-resetting, clarifications say per-month

`001-billing-engine.prp.md` line 384 says `NNNNN` is a "**global auto-incrementing sequence** (not per-month) -- the counter does not reset each month." But `clarifications.md` Q8 says "Global per month. All billing accounts share one monthly sequence." and Q3 says "5-digit counter, global monthly sequence."

These are contradictory. If the counter never resets, then `INV-2026-02-00006` follows `INV-2026-01-00005` (the `YYYY-mm` is decorative). If the counter resets monthly, `INV-2026-02-00001` can coexist with `INV-2026-01-00001`.

This affects:
- uniqueness constraints (global unique vs. unique within month)
- the PostgreSQL sequence design (one global sequence vs. monthly reset logic)
- the meaning of the `NNNNN` component

Two options:

- **(a)** Global never-resetting sequence (as the PRP currently states). `YYYY-mm` in the format reflects the finalization date for human readability only. `NNNNN` comes from a single PostgreSQL sequence that never resets. Uniqueness is on `invoice_number` globally.
- **(b)** Per-month resetting sequence (as `clarifications.md` Q3/Q8 originally stated). `NNNNN` resets to `00001` each month. Requires either a monthly sequence reset mechanism or a `SELECT MAX(...) FOR UPDATE` scoped by month. Uniqueness is still on `invoice_number` globally (the full string is unique).

**Decision:**

Following block is the answer:

```
Do not treat 99999 as a hard limit.

Decision:

Keep the global never-resetting sequence and allow `NNNNN` to grow beyond 5 digits.

Reasoning:

- the sequence is global and monotonic by design
- PostgreSQL sequences do not have a practical upper bound
- enforcing a 5-digit limit would introduce rollover and uniqueness problems
- invoice numbers should never be reused or wrapped in a financial system

Rule:

`NNNNN` is zero-padded to at least 5 digits, but may exceed 5 digits as the sequence grows.

Examples:
INV-2026-01-00001
INV-2026-01-99999
INV-2026-02-100000

Documentation update:

Clarify that 5 digits is a minimum display width, not a maximum constraint.
```

---

## MEDIUM

### M-1. Invoice list response example shows `total_amount: null` for a draft invoice

`003-invoice-api.prp.md` list response example shows `"total_amount": null` for a draft invoice. Per `002-resource-models.prp.md`, `total_amount` is "nullable -- null only before generation runs; set during draft creation." A successfully generated draft always has a non-null `total_amount`. The list endpoint only returns invoices that have been generated, so `total_amount` should never be null in practice.

Proposal: change the list response example `total_amount` from `null` to a realistic value like `"1500.50"` to match the generate and detail examples. This prevents implementers from incorrectly treating `null` as a common draft state.

**Decision:**

Accept proposal

---

### M-2. `deleted_at` missing from StorageHotel and VirtualMachine field lists in `002-resource-models.prp.md`

The StorageHotel field list (line 229) and VirtualMachine field list (line 313) in `002-resource-models.prp.md` say "All fields (including inherited from ResourceModel)" but neither includes `deleted_at`. The `ResourceModel` section (line 175) explicitly defines `deleted_at`, and both `storage-hotel.prp.md` and `virtual-machine.prp.md` correctly include `deleted_at` in their field lists.

Proposal: add `deleted_at` to both the StorageHotel and VirtualMachine field lists in `002-resource-models.prp.md`, consistent with the resource-specific PRPs and the "all fields" header.

**Decision:**

Following block is the answer:

```
Many of these fields are duplicated info from the resources defined in `docs/PRP/resources/*` so I decided to remove them from `002-resource-models.prp.md` to avoid redundancy and potential inconsistencies. But these resources are still mentioned under the "Billable resources" section in `002-resource-models.prp.md`.
```

---

### M-3. `dimension_costs` examples still use simplified precision despite L-11 decision

Review-clarifications-11 L-11 decided to "update the examples to show full precision." The `total_cost` examples in `003-invoice-api.prp.md` were updated to `"1500.5000000000"`. However, `dimension_costs` values in four documents still show simplified values like `"131.51"`, `"6.58"`, `"3.51"`, `"2.74"`:

- `BILLING.md` (lines 430-455) -- has a precision disclaimer note
- `002-resource-models.prp.md` (lines 605-630) -- has a precision disclaimer note
- `storage-hotel.prp.md` (lines 174-184) -- no disclaimer
- `virtual-machine.prp.md` (lines 195-208) -- no disclaimer

Since `InvoiceDailyCost.daily_cost` uses 10 decimal places and `dimension_costs` values should match that precision, the L-11 decision to show full precision was not fully propagated to `dimension_costs`.

Proposal: update all `dimension_costs` examples across all four documents to show full 10dp precision (e.g., `"131.5068493150"` instead of `"131.51"`). Remove the "simplified for readability" disclaimer notes since the examples will now be accurate.

**Decision:**

Accept proposal

---

### M-4. DecimalField response examples show integer-like values but DRF serializes at full precision

API response examples in `004-resource-api.prp.md` show DecimalField values without trailing decimal places: `"quota_raw": "5000"`, `"ram_mb": "65536"`, `"disks_total_gb": "500"`. DRF's `DecimalField` serializer uses the field's `decimal_places` setting, so actual responses would be `"5000.0000"` (for `quota_raw` with `decimal_places=4`), `"65536.00"` (for `ram_mb` with `decimal_places=2`), and `"500.00"` (for `disks_total_gb` with `decimal_places=2`).

Proposal: update the response examples to show the values at the field's configured precision: `"5000.0000"` for `quota_raw`, `"65536.00"` for `ram_mb`, `"500.00"` for `disks_total_gb`. This prevents implementers from being surprised by the actual DRF serialization output.

**Decision:**

Following block is the answer:

```
Accept the proposal.

Decision:

Update the API response examples to reflect the actual DRF serialization output, while keeping DecimalField precision unchanged in the models.

Reasoning:

- DRF serializes DecimalField values using their configured `decimal_places`
- the current examples are misleading because they omit trailing zeros
- even if most values are integers in practice, fractional values may appear due to normalization and pricing calculations
- keeping decimals avoids future breaking changes

Action:

Update examples in `004-resource-api.prp.md`:

"quota_raw": "5000.0000"
"ram_mb": "65536.00"
"disks_total_gb": "500.00"

Add clarification:

Decimal fields are serialized with fixed precision. Trailing zeros are expected even when the value is conceptually an integer.
```

---

### M-5. `InvoiceLine` missing timestamp field specification

`002-resource-models.prp.md` defines `TimestampedModel` (created_at + updated_at) and `CreatedAtModel` (created_at only) as base models. `InvoiceDailyCost` explicitly includes `created_at`. However, `InvoiceLine` has no timestamp fields listed and does not specify which base model it inherits from.

InvoiceLine rows are created during invoice generation and deleted/recreated during draft replacement -- they are never updated in place. This makes `CreatedAtModel` the appropriate base.

Proposal: add `created_at` to the InvoiceLine field list in `002-resource-models.prp.md` and note that InvoiceLine inherits from `CreatedAtModel` (append-only, no `updated_at`).

**Decision:**

Accept proposal

---

### M-6. `apps/ingest/` app boundary undefined

`000-system-overview.prp.md` lists `apps/billing/` and `apps/ingest/` as the main Django apps. However, no PRP or documentation file describes what lives in `apps/ingest/` versus `apps/billing/`. All resource models, daily snapshot models, ingestion event models, and their field definitions are in the billing PRPs (`002-resource-models.prp.md`). The ingestion API endpoints are in `004-resource-api.prp.md`. It is unclear which models, views, and services belong in each app.

Two options:

- **(a)** Define the boundary: `apps/billing/` owns all models (resources, invoices, pricing). `apps/ingest/` owns ingestion API views, ingestion services, and ingestion event models. Daily snapshot models stay in `apps/billing/` since they are used by the billing engine.
- **(b)** Merge everything into `apps/billing/` for v1 and defer the `apps/ingest/` split until the codebase is large enough to warrant it. Remove `apps/ingest/` from the overview.

Proposal: **(a)** is cleaner architecturally, but the boundary should be explicitly documented. Add a brief note to `000-system-overview.prp.md` clarifying what each app owns.

**Decision:**

```
Choose option (a).

Decision:

Keep `apps/ingest/` and explicitly document the app boundary.

Recommended v1 ownership:

- `apps/billing/` owns the core billing domain:
  - resources
  - daily snapshot models
  - pricing models
  - invoice models
  - billing engine services

- `apps/ingest/` owns ingestion-facing behavior:
  - ingestion API views
  - ingestion serializers
  - ingestion orchestration/services
  - ingestion event models
  - request/audit handling for inbound snapshot data

Reasoning:

- this preserves a clean architectural separation without over-complicating v1
- daily snapshot models should remain in `apps/billing/` because they are canonical billing state and are used directly by the billing engine
- ingestion event models and ingestion API logic fit naturally in `apps/ingest/` because they describe how data enters the system, not the billing domain itself

Documentation update:

Add a short app-boundary note to `000-system-overview.prp.md` clarifying that:
- `apps/billing/` owns durable billing state and billing logic
- `apps/ingest/` owns ingestion workflows and ingestion audit/event handling
- daily snapshot models stay in `apps/billing/`
```

---

### M-7. `TESTING_TEMPLATES.md` RT-30 says "fails for that resource" but failure is global/fatal

RT-30 says "invoice generation fails for that resource" and "failure explains no prior snapshot exists for autofill." Per `BILLING.md` and `001-billing-engine.prp.md`, when `force=false` and autofill cannot find a prior snapshot, the **entire invoice generation fails** (fatal error -- not a per-resource skip). The entire transaction is rolled back.

Proposal: update RT-30 to say "invoice generation fails entirely (the entire transaction is rolled back)" instead of "fails for that resource." Add a reference to the fatal-error semantics from `BILLING.md`.

**Decision:**

Accept proposal

---

### M-8. `explicit_resources` metadata format not specified in `002-resource-models.prp.md`

The Invoice metadata "may include" list in `002-resource-models.prp.md` mentions `explicit_resources` but does not specify its format. The canonical format is `[{"resource_type": "...", "resource_id": 101}]` as defined in `001-billing-engine.prp.md` and `003-invoice-api.prp.md`.

Without a format note in the model PRP, an implementer could store the data in a different shape, breaking fingerprint reproducibility and audit consistency.

Proposal: add a brief format note to the Invoice metadata section in `002-resource-models.prp.md` specifying that `explicit_resources` uses the canonical `[{"resource_type": "...", "resource_id": <int>}]` format, or add a cross-reference to `001-billing-engine.prp.md`.

**Decision:**

Accept proposal

---

## LOW

### L-1. Force-mode zero-cost wording in `BILLING.md` could be clearer

`BILLING.md` line 249 now correctly states force-mode zero-cost rows have `autofilled=false` (per round 12 H-5). However, the phrasing "because no prior snapshot is being carried forward, only zero is assigned" is slightly ambiguous -- "only zero is assigned" could be read as "the value zero is the only thing assigned" or "merely zero is assigned."

Proposal: rephrase to: "...those days produce a zero-cost `InvoiceDailyCost` row with `autofilled=false` (zero is assigned as a fallback because no snapshot data exists, not because a prior value was carried forward). See Force Mode behavior."

**Decision:**

Accept proposal

---

### L-2. No test template for force-mode zero-cost billing

`TESTING_TEMPLATES.md` has no RT-xx template covering `force=true` with `autofill_missing_days=false` zero-cost billing. This is a distinct code path with specific metadata expectations: `autofilled=false`, `incomplete=true`, `missing_data_summary` in Invoice metadata, and `daily_cost = 0` with zero normalized usage.

Proposal: add a new test template RT-35 for force-mode zero-cost billing, covering:

- missing snapshot + `force=true` + `autofill_missing_days=false`
- produces zero-cost `InvoiceDailyCost` rows with `autofilled=false`
- invoice has `incomplete=true`
- `missing_data_summary` in Invoice metadata lists affected resources and dates
- daily cost is 0
- line total reflects the zero-cost days

**Decision:**

Accept proposal

---

### L-3. StorageHotel missing explicit Autofill Rule section

`virtual-machine.prp.md` has an explicit "Autofill Rule" section documenting atomic carry-forward behavior. `storage-hotel.prp.md` has no equivalent section. The resource template `_resource-template.prp.md` now includes an Autofill Rule placeholder (per round 11 L-12). StorageHotel should also have this section for consistency.

Proposal: add an "Autofill Rule" section to `storage-hotel.prp.md` stating: "When autofill is needed for a missing day, `quota_raw` is carried forward from the last known `StorageHotelDailyQuota` row. Since StorageHotel has a single billing dimension (`quota_tb`), the carry-forward is equivalent to carrying forward the complete billing state."

**Decision:**

Accept proposal

---

### New own clarification

A new field was added to StorageHotel in file `docs/PRP/resources/storage-hotel.prp.md` named "description". This field is not mentioned in any other file, and I want that you check if it is necessary to add it to other files. 

The reason for this field is that StorageHotel have a requirement to be able to have their own description, for invoice purposes later on -probably when creating PDF-

## Follow-Up Questions

### FQ-1. H-3 follow-up: what mechanism triggers soft-delete if not automatic on RETIRED?

H-3 decision (a) removes the automatic `deleted_at` assignment from the RETIRED transition. RETIRED resources will remain visible in default querysets and accept late-arriving ingestion.

This raises a question: how does soft-delete happen in v1?

Three options:

- **(a)** Add a dedicated `POST /api/v1/storage-hotels/{id}/soft-delete` (and equivalent for VirtualMachine) action endpoint. This is explicit and auditable. The endpoint sets `deleted_at` and enforces the soft-delete invariants (status must be RETIRED, active_to must be set).
- **(b)** Allow setting `deleted_at` via PATCH on the resource. This is simpler but less explicit -- a client could accidentally soft-delete a resource by patching the wrong field.
- **(c)** Defer soft-delete to v2. In v1, resources can be RETIRED but never soft-deleted. The `billing_objects` manager and `deleted_at` field remain in the schema for future use, but no API mechanism sets `deleted_at`.

Proposal: **(a)** is the cleanest approach for a financial system -- explicit action endpoints are preferred over implicit field patches for irreversible operations. However, **(c)** is the simplest if soft-delete is not operationally needed in v1.

**Decision:**

Soft-delete should be triggered by a dedicated DRF endpoint action. Choose option (a).

---

### FQ-2. H-4 follow-up: `invoice_number` `max_length=20` may be too short for growing counter

H-4 decided that `NNNNN` is zero-padded to at least 5 digits but may grow beyond 5 digits as the sequence increases. The current `invoice_number` field is `CharField(max_length=20)` in `002-resource-models.prp.md`.

Format breakdown: `INV-YYYY-mm-NNNNN` = 4 + 5 + 3 + counter_digits = 12 + counter_digits.

- 5 digits: `INV-2026-01-00001` = 17 characters (fits)
- 6 digits: `INV-2026-02-100000` = 18 characters (fits)
- 7 digits: `INV-2026-03-1000000` = 19 characters (fits)
- 8 digits: `INV-2026-04-10000000` = 20 characters (fits exactly)
- 9 digits: `INV-2026-05-100000000` = 21 characters (exceeds max_length=20)

At ~10,000 resources and monthly invoicing, the counter could reach 8 digits within about 8 years. 9 digits would take ~80 years.

Two options:

- **(a)** Increase `max_length` to 30 to provide comfortable headroom. This is a schema-time decision with no runtime cost.
- **(b)** Keep `max_length=20`. 8-digit counters are sufficient for the foreseeable operational lifetime. Revisit if needed.

Proposal: **(a)** is safer. Changing `max_length` later requires a migration on a table with potentially millions of rows. Setting it to 30 now costs nothing.

**Decision:**

Accept proposal (a). Increase `max_length` to 30.

---

### FQ-3. New StorageHotel `description` field: full specification needed

The user added a `description` field to StorageHotel in `storage-hotel.prp.md`. This field currently appears only in the StorageHotel field list and is not documented elsewhere.

To propagate this field correctly, the following details are needed:

**(a)** Field type and constraints: what Django field type? Proposal: `TextField(blank=True, default="")` -- a free-text field with no length limit, optional, defaults to empty string. Or `CharField(max_length=500, blank=True, default="")` if a length limit is preferred.

**(b)** Is this field StorageHotel-specific, or should it be added to `ResourceModel` so all resource types inherit it? VirtualMachine might also benefit from a description field in the future.

**(c)** Should `description` appear in the canonical `resource_snapshot` schema for StorageHotel? If the purpose is "for invoice purposes later on (PDF generation)," then capturing it in the snapshot ensures the description at billing time is preserved even if the resource's description changes later.

**(d)** Should `description` be writable via the API? If yes, it needs to be added to the writable fields list in `004-resource-api.prp.md` for both `POST` (creation) and `PATCH` (update).

**(e)** Is `description` patchable after creation? Proposal: yes, same as `name`.

**(f)** Naming consideration: `ResourceModel` already has a `name` field. `InvoiceLine` also has a `description` field (the frozen human-readable label). Adding a `description` field on StorageHotel creates a naming overlap -- `InvoiceLine.description` and `StorageHotel.description` are different concepts. Should the StorageHotel field use a different name (e.g., `resource_description`, `notes`, `detail`) to avoid confusion? Or is `description` clear enough in context?

**Decision:**

Rename the field to `description_resource`. It belongs on `ResourceModel` (not StorageHotel-only) so all resource types inherit it. Field type: `CharField(max_length=200, blank=True, default="")` -- optional. It must appear in `resource_snapshot` for all resource types. It is API writable on creation and patchable after creation. Update all files where this field is worth mentioning.

---
