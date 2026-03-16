# Review Clarifications 9

Architecture review round 9 — comprehensive consistency pass across all docs and PRPs.
Edit each `**Decision:**` line with your answer.

---

## CRITICAL

### C-1. `active_from` nullability conflict between model definition and UNASSIGNED→RETIRED rule

Round 8 M-4 decided that for `UNASSIGNED → RETIRED`, `active_from` and `active_to` may both remain null.
But `002-resource-models.prp.md` defines `active_from` as `date, required` on ResourceModel.
If the field is required at the database/model level it cannot be null — the transition rule and the model definition contradict each other.

Two options:
- **(a)** Make `active_from` nullable at the model level (`null=True, blank=True`). Resources that go `UNASSIGNED → RETIRED` never get a value. Update `002-resource-models.prp.md` accordingly.
- **(b)** Require a valid `active_from` even for mistakenly created resources. For `UNASSIGNED → RETIRED`, set `active_to = active_from` (same day, zero billable days). Round 8 M-4 must be corrected.

**Decision:** Make 'UNASSIGNED → RETIRED' not possible instead. Add that to the documentation.

---

## HIGH

### H-1. `billing_account_not_billable` error: 400 vs 422

`002-resource-models.prp.md` line 30 says `POST /api/v1/invoices/generate` returns **400** when `make_invoice = False`.
`003-invoice-api.prp.md` and `.claude/docs/API.md` both list this error under **422 Unprocessable Entity**.

Since `make_invoice=False` is a pre-flight check that happens before any resource evaluation, 400 (bad request) has some logic. Round 8 AG-2 decided that billing domain failures use 422 to distinguish them from syntactic errors.

**Decision:** Confirm that `billing_account_not_billable` is a 422 domain failure (not 400) and correct `002-resource-models.prp.md` line 30.

Proposal: 422. The check is on a valid request where the billing account is intentionally configured not to be billed — that is a domain state, not a malformed request. Fix `002-resource-models.prp.md`.

**Decision:** Accept the proposal

---

### H-2. `incomplete` field — database column or serializer-computed property?

`003-invoice-api.prp.md` shows `incomplete` as a top-level response field in generate, list, detail, and finalize responses.
`002-resource-models.prp.md` and `001-billing-engine.prp.md` only describe `incomplete` as a flag stored inside `Invoice.metadata`.
There is no `incomplete` column in the Invoice model field list.

This matters for filtering: the list endpoint cannot filter on a metadata subkey without a real column or annotation.

Two options:
- **(a)** Add `incomplete` as a dedicated `BooleanField` on the Invoice model. Top-level in API responses. Filterable.
- **(b)** Keep it in metadata only. Expose it as a serializer-computed property (read-only). Not directly filterable via queryset.

**Decision:**

Answer is the following block:

```
Choose option (a).

Decision:

Add `incomplete` as a dedicated `BooleanField` on the `Invoice` model.

Reasoning:

- `incomplete` is now a first-class invoice state flag and is exposed as a top-level field in API responses
- it should be directly filterable in the invoice list endpoint
- storing it only inside `metadata` would make filtering and querying awkward and would weaken the alignment between the API contract and the model

Recommended design:

- `Invoice.incomplete` is a real BooleanField, default `false`
- it is exposed as a top-level field in generate, list, detail, and finalize responses
- `Invoice.metadata` may still contain supporting details such as `missing_data_summary` and other reasons explaining why the invoice is incomplete|
```

---

### H-3. `resource_snapshot` — canonical schema per resource type never specified

The billing engine PRP says `resource_snapshot` must contain "the minimal identifying attributes needed for audit and display."
The resource models PRP says it should contain "name, id, and resource-type-specific fields."

Neither document defines the exact required fields per resource type:
- StorageHotel: presumably `id`, `name`, `filesystem_identifier`, `quota_unit` — but not formally stated.
- VirtualMachine: example shows `{"id": 205, "name": "vm-prod-001", "provisioner": "VCENTER"}` — partially specified.

An implementer will not know which fields to freeze at billing time.

Proposal: define the canonical `resource_snapshot` schema for each resource type explicitly in their respective resource PRPs.
- StorageHotel: `{"id": <int>, "name": "<str>", "filesystem_identifier": "<str>", "quota_unit": "<str>"}`
- VirtualMachine: `{"id": <int>, "name": "<str>", "provisioner": "<str>"}`

**Decision:**

Answer is the following block:

```
Accept the proposal.

Decision:

The canonical `resource_snapshot` schema must be defined explicitly in each resource PRP.

Reasoning:

- `resource_snapshot` is part of the audit contract and cannot remain loosely defined
- the exact identifying fields are resource-specific, so they belong in the resource PRPs rather than only in the shared billing-engine PRP
- this ensures implementers know exactly which fields must be frozen at invoice generation time

Recommended schemas:

StorageHotel:
- `id`
- `name`
- `filesystem_identifier`
- `quota_unit`

VirtualMachine:
- `id`
- `name`
- `provisioner`

Documentation rule:

- `001-billing-engine.prp.md` should keep the general requirement that a frozen identifying snapshot is required
- each resource PRP should define the exact required `resource_snapshot` schema for that resource type
```

---

### H-4. `filesystem_identifier` in StorageHotel InvoiceLine metadata — flat key or inside `resource_snapshot`?

`003-invoice-api.prp.md` (detail response example) shows `filesystem_identifier` as a **flat top-level key** inside InvoiceLine metadata:
```json
{"billing_dimensions": ["quota_tb"], "total_quantity_by_dimension": {...}, "filesystem_identifier": "storage-001"}
```

`002-resource-models.prp.md` describes InvoiceLine metadata as containing a `resource_snapshot` (which would include `filesystem_identifier`) plus `quota_unit` as a flat key.

These cannot both be correct. Two options:
- **(a)** `filesystem_identifier` lives inside `resource_snapshot`, not as a flat key. The `003-invoice-api.prp.md` example must be corrected.
- **(b)** `filesystem_identifier` is stored both inside `resource_snapshot` and as a flat top-level metadata key for convenience. This is redundant but intentional.

Proposal: option (a). Keep `filesystem_identifier` inside `resource_snapshot` only, and correct the response example in `003-invoice-api.prp.md`.

**Decision:**

Answer is the following block:
```
Choose option (a).

Decision:

`filesystem_identifier` must live inside `resource_snapshot`, not as a flat top-level key in `InvoiceLine.metadata`.

Reasoning:

- `filesystem_identifier` is part of the frozen identifying snapshot of the StorageHotel resource
- `resource_snapshot` is the canonical place for frozen identifying fields
- duplicating the same value both inside and outside `resource_snapshot` would be redundant and increase the risk of inconsistency

Documentation update:

- correct the `003-invoice-api.prp.md` detail response example
- keep `filesystem_identifier` inside `resource_snapshot`
- do not expose it as a separate flat metadata key
```

---

### H-5. Discount cross-field validation — null `discount_threshold` with non-null `discount_price` (or vice versa)

The discount rules state: "if `discount_threshold_quantity` is null, discount does not apply."
But there is no validation rule for the case where only one of the two discount fields is set:
- `discount_price_per_unit_year` is non-null but `discount_threshold_quantity` is null.
- `discount_threshold_quantity` is non-null but `discount_price_per_unit_year` is null.

The billing engine behavior for these partial states is undefined. A buggy ResourcePrice record could produce incorrect billing silently.

Proposal: enforce as a cross-field validation rule at the service and model level — both fields must be set together or both must be null. Storing a record with only one set is a validation error. Add this to `005-pricing-api.prp.md` and `001-billing-engine.prp.md`.

**Decision:**

Accept the proposal.

---

### H-6. Autofill + no prior snapshot + multiple resources — which resources fail?

`BILLING.md` states: "`force=false` + `autofill_missing_days=true` + no prior snapshot → entire invoice generation fails (fatal — not a per-resource skip)."

"Entire invoice" is ambiguous when multiple resources are selected. If resource A has complete data and resource B has no prior snapshot, does the **entire invoice transaction fail** (including resource A), or does only resource B fail while A proceeds?

The phrase "not a per-resource skip" implies the entire transaction fails. But this means a single resource with no history can block invoice generation for all resources on the account.

Proposal: confirm that a single resource failing the no-prior-snapshot check under `force=false` causes the **entire invoice transaction to be rolled back** — no invoice is created, no lines persist. Add a multi-resource example to `BILLING.md` explicitly showing this behavior.

**Decision:**

Accept the proposal.

---

## MEDIUM

### M-1. `provisional` field missing from list endpoint response

`003-invoice-api.prp.md` shows `incomplete` in the list response but not `provisional`.
Both flags are present in the generate and detail responses (though `provisional` lives inside `metadata`).
Since `incomplete` is listed at the top level in the list response, the absence of `provisional` may be an oversight.

Two options:
- **(a)** Intentional omission: `provisional` is a detail-level concern and is excluded from the list response. Document this as deliberate.
- **(b)** Add `provisional` to the list response alongside `incomplete`.

**Decision:**

Answer is the following block:

```
Choose option (a).

Decision:

`provisional` is intentionally omitted from the invoice list response in v1.

Reasoning:

- the list endpoint is a reduced summary serializer
- `incomplete` is the more important list-level operational flag and is useful for filtering
- `provisional` is a detail-level concern and is better exposed through the full invoice detail response, where the surrounding metadata is also available

Documentation update:

`003-invoice-api.prp.md` should explicitly state that `provisional` is intentionally excluded from the list response in v1.
```

---

### M-2. VirtualMachine has no natural key / uniqueness constraint

StorageHotel has `UNIQUE` on `filesystem_identifier`, preventing duplicate resource creation.
VirtualMachine has no equivalent constraint. Two VMs with the same `name` and `provisioner` are entirely valid records that would each accumulate snapshots and billing independently.

Two options:
- **(a)** Add a uniqueness constraint to VirtualMachine — e.g., `UNIQUE (name, provisioner)` or a new dedicated unique identifier field.
- **(b)** Explicitly document that VirtualMachine deduplication is the caller's responsibility. The system treats every record as a distinct resource regardless of `name`/`provisioner` values.

**Decision:**

Answer is the following block:

```
Choose option (b).

Decision:

VirtualMachine deduplication is the caller's responsibility in v1.

The system treats each VirtualMachine record as a distinct billable resource regardless of whether another record has the same `name` and `provisioner`.

Reasoning:

- VirtualMachine currently has no strong natural key defined in the PRPs
- `name` is not reliable enough to be a safe uniqueness constraint
- `provisioner` does not make the pair unique in a robust way
- adding a weak uniqueness rule would risk false collisions without truly solving resource identity

Documentation update:

The VirtualMachine PRP should explicitly state that:
- there is no natural-key uniqueness constraint in v1 beyond the primary key
- callers and ingestion workflows are responsible for avoiding duplicate VM creation
- duplicate VM rows, if created, are treated as separate billable resources
```

---

### M-3. `quota_raw = 0` — valid or rejected?

`004-resource-api.prp.md` states quota ingestion requires "a positive number or zero."
A StorageHotel with zero quota is semantically odd but may occur (deprovisioned storage, quota revoked).

Three options:
- **(a)** `quota_raw = 0` is valid. It produces `normalized_usage = {"quota_tb": "0"}` and `daily_cost = 0`.
- **(b)** `quota_raw = 0` is rejected with a 400 validation error.
- **(c)** `quota_raw = 0` is valid but produces a zero-cost `InvoiceDailyCost` row and contributes `0` to `InvoiceLine.total_cost`.

Proposal: option (a)/(c) — zero is valid and produces zero-cost billing rows. This is consistent with legitimate real-world scenarios and the general rule that zero-day-cost rows are still auditable records.

**Decision:**

Accept the proposal.

---

### M-4. `cpu_count` type coercion — `PositiveIntegerField` stored, `Decimal` used in billing

`002-resource-models.prp.md` defines `cpu_count` as `PositiveIntegerField`.
Billing calculations use `Decimal` throughout.
The normalization rules say `cpu_count` is `1:1, no conversion` but do not document the int→Decimal type coercion step.

`InvoiceDailyCost.metadata` shows `"cpu_count": "8"` (a Decimal string), not an integer.

Proposal: add an explicit note to `virtual-machine.prp.md` and `001-billing-engine.prp.md` that `cpu_count` is stored as `PositiveIntegerField` but coerced to `Decimal` during normalization for billing calculations. The coercion is `Decimal(str(cpu_count))`.

**Decision:**

Accept the proposal.

---

### M-5. `on_delete` specs incomplete for several FK relationships

`002-resource-models.prp.md` specifies `on_delete=PROTECT` for `ResourceModel.billing_account` and `on_delete=CASCADE` for `InvoiceLine.invoice` and `InvoiceDailyCost.invoice` (round 8 M-10). But the following FKs are never specified:

| FK | Current spec |
|----|-------------|
| `BillingAccount.price_list` | not specified |
| `Invoice.billing_account` | not specified |
| `StorageHotelDailyQuota.storage_hotel` | not specified |
| `VirtualMachineDailyUsage.virtual_machine` | not specified |

Proposal:
- `BillingAccount.price_list` → `PROTECT` (a billing account cannot exist without a price list)
- `Invoice.billing_account` → `PROTECT` (invoices must never be orphaned)
- `StorageHotelDailyQuota.storage_hotel` → `CASCADE` (quota snapshots belong to the resource)
- `VirtualMachineDailyUsage.virtual_machine` → `CASCADE` (usage snapshots belong to the resource)

**Decision:**

Accept the proposal.

---

### M-6. `deleted_at` not defined on abstract `ResourceModel`

The `ResourceModel` abstract model field list in `002-resource-models.prp.md` does not include `deleted_at`.
Both `StorageHotel` and `VirtualMachine` include `deleted_at` individually.

If `deleted_at` is not part of the abstract model, a future resource type could omit it and break the `billing_objects` manager (which relies on soft-delete semantics defined on ResourceModel).

Proposal: add `deleted_at` to the `ResourceModel` abstract field list, and remove it from the individual concrete model field lists since it is inherited. Also add it to `_resource-template.prp.md`.

**Decision:**

Aceept the proposal.

---

### M-7. `active_from`/`active_to` missing from `_resource-template.prp.md`

The resource template PRP lists model fields as: `id, billing_account, name, status, created_at, updated_at, deleted_at`.
It omits `active_from` and `active_to`, which are required fields on `ResourceModel`.

An implementer using this template to add a new resource type would miss the core billing-window fields.

Proposal: add `active_from` and `active_to` to the template PRP field list with their types and constraints.

**Decision:**

Accept the proposal.

---

### M-8. Error response body missing from API examples for 409 and 422 cases

`API.md` defines a structured error format: `{"code": "...", "message": "...", "details": {...}}`.
`003-invoice-api.prp.md` specifies HTTP status codes for error cases but includes no error response body examples.

An implementer would not know whether to return the structured format from `API.md`, DRF's default format, or something custom.

Additionally, `API.md` shows `missing_quota_days` as an example code, but this code does not appear in any defined error code table. The actual defined code appears to be `missing_snapshot`.

Proposal:
1. Add at least one error response body example to `003-invoice-api.prp.md` for a 409 and a 422 case, using the structured format from `API.md`.
2. Replace `missing_quota_days` in `API.md` with a real defined code (e.g., `missing_snapshot`).

**Decision:**

Answer is the following block:

```
Accept the proposal.

Decision:

- `003-invoice-api.prp.md` must include concrete error response examples using the structured error format defined in `API.md`
- at minimum, add one 409 example and one 422 example
- `API.md` should replace `missing_quota_days` with a real defined error code such as `missing_snapshot`

Reasoning:

- HTTP status codes alone are not enough; implementers need the expected response body format
- the shared structured error format from `API.md` should be the authoritative contract across endpoints
- endpoint PRPs should show concrete examples using that shared format
- undefined example codes such as `missing_quota_days` create confusion and should be replaced with a code that actually exists in the documented error vocabulary

Recommended examples:

409:
{
  "code": "duplicate_invoice",
  "message": "A draft invoice already exists for the same billing account, billing period, and billing selection.",
  "details": {
    "billing_account": 123,
    "period_start": "2026-01-01",
    "period_end": "2026-01-31",
    "selection_scope": "all_resources"
  }
}

422:
{
  "code": "missing_snapshot",
  "message": "Invoice generation failed because one or more required billing snapshots were missing.",
  "details": {
    "resource_type": "storage_hotel",
    "resource_id": 101,
    "missing_dates": ["2026-01-16", "2026-01-17", "2026-01-18"]
  }
}

One extra cleanup I would recommend is to create a short shared error-code table in API.md, so codes like duplicate_invoice, missing_snapshot, and selection_ambiguous are defined once and reused consistently.
```

---

### M-9. `InvoiceDailyCost` no FK to `InvoiceLine` — service-layer integrity guarantee undocumented

`002-resource-models.prp.md` explicitly states: "InvoiceDailyCost does not have a FK to InvoiceLine. The relationship is resolved through tuple matching on `(invoice, resource_type, resource_id)`."

This means there is no database-level referential integrity between daily cost rows and their parent invoice line. A partial failure during invoice generation could leave orphaned `InvoiceDailyCost` rows.

The transaction boundary requirement in `ARCHITECTURE.md` provides rollback-on-failure, but this guarantee is only documented at the architecture level, not the service contract level.

Proposal: add an explicit invariant to `001-billing-engine.prp.md` or `BILLING.md`: "The invoice generation service must guarantee that for every `InvoiceDailyCost` row created, a corresponding `InvoiceLine` exists for the same `(invoice, resource_type, resource_id)` tuple, and vice versa. This invariant is enforced by the transaction boundary, not the database schema."

**Decision:**

Answer is the following block:

```
Accept the proposal.

Decision:

Add an explicit service-level invariant to `001-billing-engine.prp.md` stating that invoice generation must preserve logical integrity between `InvoiceLine` and `InvoiceDailyCost`, even though no direct FK exists between them.

Recommended invariant:

Invoice generation must guarantee tuple-level consistency for `(invoice, resource_type, resource_id)`.

For every such tuple in a committed invoice:
- if one or more `InvoiceDailyCost` rows exist, exactly one corresponding `InvoiceLine` must exist
- if an `InvoiceLine` exists, it must aggregate all `InvoiceDailyCost` rows for that same tuple
- invoice generation must run inside a transaction so partial writes cannot leave orphaned `InvoiceDailyCost` rows or unmatched `InvoiceLine` rows

Reasoning:

- the lack of a direct FK is an intentional modeling choice, not a relaxation of integrity requirements
- this guarantee should be documented explicitly at the billing-service level, not only implied through a general architecture transaction note
```

---

### M-10. pytest settings: `config.settings.dev` vs. dedicated test settings module

`pyproject.toml` sets `DJANGO_SETTINGS_MODULE = "config.settings.dev"` for both pytest and mypy.
`000-system-overview.prp.md` shows a config layout that includes `config/settings/tests/`.

If a dedicated `config/settings/test.py` is planned, using `config.settings.dev` for test runs means:
- dev and test environments share the same settings (including database config)
- the planned `tests/` settings module is unused

Proposal: decide now whether tests use `config.settings.dev` or a dedicated `config.settings.test`. If a test-specific settings module is planned, update `pyproject.toml` to reference it and add its creation to the bootstrapping sequence.

**Decision:**

Answer is the following block:

```
Choose a dedicated test settings module.

Decision:

Tests should use `config.settings.test`, not `config.settings.dev`.

Reasoning:

- test execution should be isolated from development settings
- using `config.settings.dev` for pytest would blur the distinction between dev and test environments
- the documented project structure already anticipates a dedicated test settings module
- a separate test settings module makes it easier to control database, cache, email, hashing, and other test-specific behavior

Required updates:

- update `pyproject.toml` so pytest uses:
  `DJANGO_SETTINGS_MODULE = "config.settings.test"`
- if `django-stubs` / mypy settings are also being configured now, prefer pointing them to `config.settings.test` as well for consistency
- add creation of `config/settings/test.py` to the initial bootstrapping sequence

Rule:

- `config.settings.dev` is for local development
- `config.settings.test` is for automated tests
```

---

### M-11. `recalculate` endpoint referenced as a core concept in `ARCHITECTURE.md` and `BILLING.md` but deferred to v2

Round 8 M-5 accepted a stub spec for `POST /api/v1/invoices/{id}/recalculate` as a v2 endpoint.
However:
- `ARCHITECTURE.md` lists invoice recalculation as a typical service function
- `BILLING.md` states "Draft invoice: may be recalculated"
- `CODING_RULES.md` lists `recalculate_invoice()` as an example service

These references give the impression that recalculation is a v1 feature. An implementer following BILLING.md would expect to build this service in v1.

Proposal: update `ARCHITECTURE.md`, `BILLING.md`, and `CODING_RULES.md` to clarify that in v1, draft regeneration using `POST /generate` with `force=true` is the mechanism for updating a draft invoice. The dedicated `recalculate` endpoint is deferred to v2.

**Decision:**

Accept the proposal

---

## LOW

### L-1. `BillingAccountBase` listed in two locations in `ARCHITECTURE.md`

`ARCHITECTURE.md` lists `BillingAccountBase` in both `apps/billing/models/base.py` and `apps/billing/models/billing_accounts.py`.

Proposal: remove `BillingAccountBase` from the `base.py` description. `billing_accounts.py` is the correct and natural home for both the abstract and concrete billing account models.

**Decision:**

Accept the proposal.

---

### L-2. `selection_fingerprint` exclusion — stated per-endpoint instead of once globally

`003-invoice-api.prp.md` mentions that `selection_fingerprint` is excluded from the list response (line 94) and again from the finalize response (line 177). The detail response also omits it without comment.

Proposal: add a single global statement to `003-invoice-api.prp.md`: "`selection_fingerprint` is excluded from all public API responses in v1. It is an internal implementation detail used for duplicate prevention." Remove per-endpoint restatements.

**Decision:**

Accept the proposal

---

### L-3. Currency constraint — only NOK is valid in v1, but not formally documented

`ResourcePrice.price_currency` defaults to `"NOK"` but allows any value. The billing engine has no documented behavior for mixed-currency invoices.

Proposal: add an explicit v1 constraint to `BILLING.md` and `001-billing-engine.prp.md`: "All pricing in v1 uses NOK. The billing engine must validate that all resolved ResourcePrice rows for an invoice use the same currency, matching `Invoice.currency`. A mismatch is a fatal billing error."

**Decision:**

Accept the proposal.

---

### L-4. Single-day invoice period (`period_start == period_end`) not documented as valid

`003-invoice-api.prp.md` lists "`period_start` after `period_end`" as a 400 error but never addresses the equal case.
Given the inclusive date range rule, `period_start == period_end` should produce exactly one daily evaluation.

Proposal: add a note to `003-invoice-api.prp.md` and `BILLING.md`: "A single-day invoice where `period_start == period_end` is valid and produces exactly one daily evaluation."

**Decision:**

Accept the proposal

---

### L-5. `total_quantity_by_dimension` key naming convention (`_days` suffix) never formally defined

InvoiceLine metadata uses keys like `quota_tb_days`, `cpu_count_days`, `ram_gb_days`, `disk_gb_days`.
The `_days` suffix is never documented as a naming rule. An implementer could use `quota_tb` or a different suffix.

Proposal: document the naming rule explicitly in `002-resource-models.prp.md`: "Keys in `total_quantity_by_dimension` use the format `{pricing_dimension}_days`, representing the cumulative quantity-days for that dimension across all billed days in the invoice period."

**Decision:**

Accept the proposal

---

### L-6. No bulk ingestion endpoint noted — potential bottleneck at scale

The system overview states ~10,000 resources as expected scale and recommends batched processing. But ingestion endpoints accept only one snapshot per request. 10,000 resources × 1 daily snapshot = 10,000 API calls per day minimum.

Proposal: add a note in `004-resource-api.prp.md` acknowledging that single-record ingestion is a v1 constraint and that a bulk ingestion endpoint is a likely future enhancement.

**Decision:**

Accept the proposal

---

### L-7. Missing test template — usage drops below discount threshold mid-period

`TESTING_TEMPLATES.md` has no template for a resource where usage starts above the discount threshold and drops below it mid-period (or vice versa). Scenario SH-25 only tests all-days-above-threshold.

Proposal: add a template (e.g., SH-26) testing a mid-period threshold crossing: some days billed at discount price, remaining days at normal price within the same invoice period.

**Decision:**

Accept the proposal.

---

### L-8. CLAUDE.md routing table has no "project orientation" row

The routing table in CLAUDE.md covers task-specific scenarios but has no entry for "first-time project orientation" or "understanding the system domain." An implementer starting fresh has no documented entry point.

Proposal: add a routing table row: "Project orientation / first-time understanding → Read `PROJECT.md` and `docs/PRP/000-system-overview.prp.md`."

**Decision:**

Accept the proposal.

---
