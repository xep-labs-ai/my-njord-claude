# Review Clarifications 16

Architecture review round 16 — cross-document consistency audit after round 15.
Edit each `**Decision:**` line with your answer.

---

## HIGH

### O-1. `TESTING_TEMPLATES.md` RT-35 says `autofilled = false` for force-mode zero rows — contradicts PRP

**Files:** `.claude/docs/TESTING_TEMPLATES.md` (line ~742), `docs/PRP/001-billing-engine.prp.md` (line 183)

`TESTING_TEMPLATES.md` RT-35 states:

> missing-day rows have autofilled = false (zero is a fallback, not a carry-forward)

`001-billing-engine.prp.md` line 183 explicitly says `autofilled = True` for force-mode zero-cost rows. Round 15 O-17 corrected this in `BILLING.md` but `TESTING_TEMPLATES.md` was not updated. An implementer writing tests from this template would assert the wrong value.

Proposal: update RT-35 in `TESTING_TEMPLATES.md` to say `autofilled = true` for force-mode zero-cost rows. Add a clarifying note: "Zero is a fallback, but `autofilled = true` because the data did not come from a real ingested snapshot."

**Decision:**

---

### O-2. `001-billing-engine.prp.md` zero-cost forced row description uses wrong StorageHotel and VirtualMachine field names

**Files:** `docs/PRP/001-billing-engine.prp.md` (line 185)

The zero-cost forced row description says:

> `metadata` contains zeroed usage values (e.g. `quota_bytes: 0`, `used_bytes: 0` for StorageHotel; `cpu_count: 0`, `ram_mb: 0`, `disks_total_gb: 0` for VirtualMachine)

StorageHotel has no fields called `quota_bytes` or `used_bytes`. The correct normalized usage key is `quota_tb`. For VirtualMachine, `ram_mb` and `disks_total_gb` are raw snapshot field names — the correct normalized billing dimension keys are `ram_gb` and `disk_gb`. The concrete StorageHotel JSON example below uses the correct `quota_tb` key, making the inline text directly contradictory.

Proposal: replace the parenthetical with correct normalized usage dimension names:

> `metadata` contains zeroed usage values (e.g. `{"quota_tb": "0"}` for StorageHotel; `{"cpu_count": "0", "ram_gb": "0", "disk_gb": "0"}` for VirtualMachine)

**Decision:**

---

### O-3. `BILLING.md` "Missing Data Behavior Matrix" still says "fail for that resource" — round 15 O-20 partially applied

**Files:** `.claude/docs/BILLING.md` (line ~580)

Round 15 O-20 was accepted to change "fail for that resource" to "fail the entire invoice generation." The fix was applied in one location but the Missing Data Behavior Matrix still contains the old wording. The PRP (`001-billing-engine.prp.md` line 214) and the paragraph immediately below in `BILLING.md` both say the entire invoice generation fails — not a per-resource skip.

Proposal: change the remaining "fail for that resource" occurrence in the Missing Data Behavior Matrix to "fail the entire invoice generation."

**Decision:**

---

## MEDIUM

### O-4. `002-resource-models.prp.md` has duplicate "Field types:" header in ResourceModel section

**Files:** `docs/PRP/002-resource-models.prp.md` (lines ~177 and ~183)

The ResourceModel section now has two separate "Field types:" headers — an artifact from round 15 O-3 where `namespace` was added as a separate block instead of being merged into the existing field types list. An implementer scanning the section could miss one of the two blocks.

Proposal: merge the two "Field types:" blocks into a single list covering all ResourceModel fields: `billing_account`, `name`, `namespace`, `description_resource`, `status`, `active_from`, `active_to`, `deleted_at`.

**Decision:**

---

### O-5. `003-invoice-api.prp.md` shows `"missing_data_summary": null` in example but description says "present when `incomplete=true`"

**Files:** `docs/PRP/003-invoice-api.prp.md` (line ~71), `docs/PRP/002-resource-models.prp.md` (line ~283)

The generate endpoint response example shows `"missing_data_summary": null` even for a non-incomplete invoice. `002-resource-models.prp.md` says "`missing_data_summary` — present when `incomplete=true`." These imply two different contracts:

- Always-present-but-nullable (implied by the example)
- Conditionally-present (implied by the description)

An implementer following the example would always include the key; one following the description would omit it entirely when `incomplete=false`.

Proposal: pick one contract and document it consistently. Since the example already shows `null`, align the description to: "`missing_data_summary` — always present in Invoice metadata; `null` when `incomplete=false`, populated object when `incomplete=true`." Update the description in `002-resource-models.prp.md` to match.

**Decision:**

---

### O-6. `BILLING.md` Invoice Total Step 2 omits `ROUND_HALF_UP` rounding

**Files:** `.claude/docs/BILLING.md` (lines ~477-483)

Step 2 of the Invoice Total formula says:

> Sum all `InvoiceLine.total_cost` values → produces `Invoice.total_amount`

This omits the rounding step. `001-billing-engine.prp.md` line 100-101 says `Invoice.total_amount` is rounded to 2 decimal places. The Rounding Strategy section below covers this, but the formula itself is incomplete.

Proposal: update Step 2 to:

> Sum all `InvoiceLine.total_cost` values, then round to 2 decimal places using `ROUND_HALF_UP` → produces `Invoice.total_amount`

**Decision:**

---

### O-7. `001-billing-engine.prp.md` has StorageHotel zero-cost example but no VirtualMachine example

**Files:** `docs/PRP/001-billing-engine.prp.md` (lines ~185-196)

Round 15 O-14 added a concrete StorageHotel zero-cost forced row metadata example but no corresponding VirtualMachine example. The inline text at line 185 uses wrong VirtualMachine dimension names (see O-2), so a concrete example is needed to close the ambiguity.

Proposal: add a VirtualMachine zero-cost forced row metadata example immediately after the StorageHotel one:

```json
{
  "normalized_usage": {"cpu_count": "0", "ram_gb": "0", "disk_gb": "0"},
  "resolved_prices": {
    "cpu_count": {"price_per_unit_year": "300", "currency": "NOK", "discount_applied": false},
    "ram_gb": {"price_per_unit_year": "40", "currency": "NOK", "discount_applied": false},
    "disk_gb": {"price_per_unit_year": "2", "currency": "NOK", "discount_applied": false}
  },
  "dimension_costs": {"cpu_count": "0", "ram_gb": "0", "disk_gb": "0"},
  "autofilled": true
}
```

**Decision:**

---

### O-8. `namespace` appears as top-level key in VirtualMachine InvoiceLine metadata but is not documented as intentional redundancy

**Files:** `docs/PRP/002-resource-models.prp.md` (lines ~374, ~393-394)

VirtualMachine InvoiceLine metadata example includes `"namespace": "USIT"` as a flat top-level key alongside `"provisioner": "VCENTER"`. The document documents `provisioner` as "intentional metadata redundancy" (present both at top-level and inside `resource_snapshot` for fast lookup). `namespace` also appears in both places but is not mentioned in the redundancy note.

Two options:

- **(a)** Add `namespace` to the intentional redundancy note for VirtualMachine: "`provisioner` and `namespace` are recorded as flat top-level keys for fast lookup without parsing `resource_snapshot`."
- **(b)** Remove the top-level `namespace` key from the VirtualMachine InvoiceLine metadata example if it is not needed as a flat lookup key.

Proposal: **(a)** — `namespace` is a natural grouping/lookup key and including it at the top level is consistent with how `provisioner` is treated.

**Decision:**

---

### O-9. StorageHotel InvoiceLine metadata missing `namespace` as top-level key — asymmetric with VirtualMachine

**Files:** `docs/PRP/002-resource-models.prp.md` (lines ~344-361), `docs/PRP/resources/storage-hotel.prp.md` (lines ~183-198)

VirtualMachine InvoiceLine metadata includes `namespace` as a flat top-level key. StorageHotel does not — it only has `quota_unit` as the intentional redundancy. If `namespace` is useful for fast lookup in VirtualMachine, the same reasoning applies to StorageHotel.

Two options:

- **(a)** Add `"namespace": "uio_fs01"` as a top-level key to the StorageHotel InvoiceLine metadata example, matching VirtualMachine.
- **(b)** Keep the asymmetry — StorageHotel's distinguishing lookup key is `quota_unit` (needed for unit conversion audit); `namespace` is inside `resource_snapshot`. Document the asymmetry explicitly.

Proposal: **(a)** for consistency, since both resources now have `namespace` as a required field. Update both `002-resource-models.prp.md` and `storage-hotel.prp.md` metadata examples.

**Decision:**

---

### O-10. StorageHotel PATCH "Not patchable after creation:" header has no content — misleading

**Files:** `docs/PRP/004-resource-api.prp.md` (lines ~148-150)

The StorageHotel PATCH section has an empty "Not patchable after creation:" header followed immediately by a `quota_unit` correction warning. The empty header makes it look like `quota_unit` is not patchable, when in fact it is listed in the patchable fields.

Proposal: remove the empty "Not patchable after creation:" header entirely. If no fields are non-patchable for StorageHotel, there is no need for this section. The `quota_unit` warning can stand alone without the misleading header above it.

**Decision:**

---

## LOW

### O-11. `PROJECT.md` says "clarification rounds 1-13" — stale, rounds 14 and 15 now exist

**Files:** `.claude/docs/PROJECT.md` (line ~38)

Proposal: change "clarification rounds 1-13" to just "clarification rounds" generically to avoid perpetual staleness.

**Decision:**

---

### O-12. `BILLING.md` missing cross-reference to Resource Type Registry validation

**Files:** `.claude/docs/BILLING.md`, `docs/PRP/001-billing-engine.prp.md` (lines ~128-141)

`001-billing-engine.prp.md` defines a Resource Type Registry and requires that invoice generation and `ResourcePrice` creation reject unknown `resource_type` values with 400 Bad Request. `BILLING.md` does not reference this registry or the validation requirement. An implementer reading only `BILLING.md` would not know about it.

Proposal: add a brief cross-reference in `BILLING.md`'s resource selection section:

> Valid resource types are defined in the Resource Type Registry (`001-billing-engine.prp.md`). Unknown `resource_type` values must be rejected with 400 Bad Request at both invoice generation and `ResourcePrice` creation.

**Decision:**

---

### O-13. `001-billing-engine.prp.md` vague "Decimal high precision" summary precedes precise 10dp rule — potentially misleading

**Files:** `docs/PRP/001-billing-engine.prp.md` (lines ~86-94)

Lines 86-94 give a vague summary:

> Internal calculations: Decimal high precision
> Customer totals: 2 decimals NOK

This appears before the precise 10dp rule at lines 96-107. "High precision" could be interpreted as unlimited precision. The detailed section is unambiguous but the summary creates unnecessary confusion.

Proposal: remove or replace the vague summary with a forward reference: "See detailed rounding rules below." The detailed section is complete and stands alone.

**Decision:**

---

### O-15. `TESTING_TEMPLATES.md` examples all use `/ 365` with no note about leap year variability

**Files:** `.claude/docs/TESTING_TEMPLATES.md` (lines ~270, ~514-525, ~586-595)

All template formulas use `/ 365`. `TESTING.md` explicitly requires leap year handling tests, but `TESTING_TEMPLATES.md` provides no leap-year example or note. An implementer generating test fixtures purely from templates would never exercise the `/ 366` path.

Proposal: add a note near the first formula in `TESTING_TEMPLATES.md`:

> All examples assume non-leap year (365 days). Implementations must also be tested with leap year dates (e.g., 2024) using `/ 366`. See `TESTING.md` leap year requirements.

**Decision:**

---

### O-16. `003-invoice-api.prp.md` `missing_snapshot` error example shows only one resource — multi-resource case undocumented

**Files:** `docs/PRP/003-invoice-api.prp.md` (lines ~361-373)

The 422 error example for `missing_snapshot` shows a single resource with missing dates. When multiple resources have missing data the error must report all of them, but the current example implies a single-resource shape. An implementer would design a single-resource error response.

Proposal: add a note after the example: "When multiple resources have missing data, `details` contains a list of affected resources, each with `resource_type`, `resource_id`, and `missing_dates`." Optionally show a multi-resource example.

**Decision:**

---

### O-18. `002-resource-models.prp.md` Invoice `incomplete` field type not listed in the Field types section

**Files:** `docs/PRP/002-resource-models.prp.md` (lines ~257, ~298-311)

The Invoice field list includes `incomplete`. It is described in a paragraph as `BooleanField(default=False)` but is not present in the "Field types:" section alongside `invoice_number`, `billing_account`, `period_start`, etc. The field type must be pieced together from two separate locations.

Proposal: add `incomplete` to the Invoice "Field types:" section: `incomplete` — BooleanField(default=False). `True` when one or more resources were billed at zero due to missing data under force mode.

**Decision:**

---

## DEEP AUDIT — Additional Observations (Round 16 Extension)

The following observations were produced by a deeper, exhaustive pass over all PRPs, Claude docs, and existing app code. They focus on implementation-blocking gaps and pre-development decisions.

---

## HIGH (additional)

### O-19. All BillingAccount and BillingAccountBase `CharField` fields missing `max_length`

**Files:** `docs/PRP/002-resource-models.prp.md` (lines 8-31, 99-107)

Django `CharField` requires `max_length`. The following fields have no `max_length` specified anywhere in the PRPs:

- `BillingAccountBase`: `name`, `contact_point`, `contact_telephone_number`, `customer_number`
- `BillingAccount` (UiO-specific): `usit_contact_point`, `main_agreement_id`, `main_agreement_description`, `usit_accounting_place`, `usit_sub_project`, `ephorte`, `uio_unit`

An implementer cannot write the migration without choosing arbitrary values.

Proposal: specify `max_length` for every CharField. Suggested values:
- `name`: 255
- `contact_point`: 255
- `contact_telephone_number`: 50
- `customer_number`: 50
- UiO-specific fields: 255 (except `main_agreement_description`: 500 if it holds longer text)

**Decision:**

---

### O-20. `customer_number` conditional uniqueness enforcement mechanism unspecified

**Files:** `docs/PRP/002-resource-models.prp.md` (line 29)

The spec says `customer_number` is "unique when set." Standard `unique=True` on a nullable CharField behaves inconsistently between Django model validation and PostgreSQL. The correct Django 5.2 approach is a `UniqueConstraint` with a condition:

```python
UniqueConstraint(
    fields=["customer_number"],
    condition=Q(customer_number__isnull=False),
    name="unique_customer_number_when_set",
)
```

Without specifying this, an implementer may use `unique=True` which adds an unnecessary index on NULL values and may behave unexpectedly with model validators.

Proposal: specify the `UniqueConstraint` with `condition` approach in the PRP.

**Decision:**

---

### O-21. `ResourcePrice` `daterange` exclusion constraint implementation details unspecified

**Files:** `docs/PRP/001-billing-engine.prp.md` (line 334), `docs/PRP/005-pricing-api.prp.md` (lines 260-261)

The spec requires a "PostgreSQL `daterange` exclusion constraint" to prevent overlapping effective date ranges. This requires:

1. The `btree_gist` PostgreSQL extension, created via a Django migration (`CreateExtension('btree_gist')`) — requires superuser or `CREATE EXTENSION` privilege.
2. A Django `ExclusionConstraint` using `DateRange` and `RangeOperators`.
3. A decision on how `effective_to = NULL` (open-ended range) is handled — NULL must be treated as infinity.
4. The constraint must be scoped to `(price_list, resource_type, pricing_dimension)`.

None of these implementation details are specified. The `btree_gist` extension is a hard prerequisite that must be prototyped early.

Proposal: add an implementation note to `005-pricing-api.prp.md`:

```
Exclusion constraint requires:
- btree_gist extension (create via migration before this model's migration)
- ExclusionConstraint on (price_list, resource_type, pricing_dimension, daterange(effective_from, effective_to))
- NULL effective_to treated as unbounded upper bound
- Prototype this constraint early — it may require raw SQL in the migration
```

**Decision:**

---

### O-22. `namespace` field constraints at concrete model level underspecified

**Files:** `docs/PRP/resources/storage-hotel.prp.md` (lines 10-28), `docs/PRP/resources/virtual-machine.prp.md` (lines 10-28), `docs/PRP/002-resource-models.prp.md` (lines 178-179)

The abstract `ResourceModel` says `namespace` is `blank=True, default=""` (optional). But StorageHotel and VirtualMachine require it. The following is unspecified at the concrete model level:

- `max_length` for `namespace` (not specified anywhere)
- Whether `blank=False` is enforced at the concrete model level
- Whether the uniqueness constraints `(namespace, name)` and `(namespace, provisioner, name)` should exclude soft-deleted rows — a soft-deleted resource with the same identity would block recreation of a new resource unless the constraint uses `condition=Q(deleted_at__isnull=True)`

Proposal: specify for both resources:
- `namespace`: `CharField(max_length=255, blank=False)` at the concrete model level
- Uniqueness constraints: use `UniqueConstraint` with `condition=Q(deleted_at__isnull=True)` so soft-deleted resources do not block recreation

**Decision:**

---

### O-23. Advisory lock key computation not specified

**Files:** `docs/PRP/001-billing-engine.prp.md` (lines 285-288)

PostgreSQL advisory locks require a single `bigint` or two `int` arguments. The spec says "keyed on `(billing_account, period_start, period_end, selection_scope)`" but does not specify how to convert these four fields into an integer. Without a canonical algorithm, two implementations could compute different lock keys and fail to prevent concurrent access.

Proposal: specify the computation algorithm:

```python
import hashlib
key_str = f"{billing_account_id}:{period_start}:{period_end}:{selection_scope}"
lock_key = int(hashlib.sha256(key_str.encode()).hexdigest()[:16], 16) % (2**63)
# Use: SELECT pg_advisory_xact_lock({lock_key})
```

**Decision:**

---

### O-24. Invoice number sequence implementation not specified

**Files:** `docs/PRP/001-billing-engine.prp.md` (lines 399-424)

The spec suggests "use a dedicated PostgreSQL sequence or `SELECT MAX(invoice_number) FOR UPDATE`." The `SELECT MAX` approach is complex and error-prone. A dedicated PostgreSQL sequence is the correct approach but requires:

1. A Django migration with `RunSQL("CREATE SEQUENCE invoice_number_seq START 1;", "DROP SEQUENCE invoice_number_seq;")`
2. The finalization service calling `SELECT nextval('invoice_number_seq')` inside the transaction
3. The sequence name defined as a project constant

Proposal: specify that a dedicated PostgreSQL sequence is the required approach. Add an implementation note to `001-billing-engine.prp.md` with the migration pattern and a named constant for the sequence name.

**Decision:**

---

### O-25. Autofill carry-forward search crosses period boundary — not explicitly permitted

**Files:** `docs/PRP/001-billing-engine.prp.md` (lines 380-386), `.claude/docs/BILLING.md` (lines 277-289)

Autofill uses "the last known valid billing snapshot before the missing day." The spec does not explicitly state whether the search can cross the invoice `period_start` boundary. This is critical: if a resource was last ingested on Dec 15, 2025 and the invoice period is Jan 1–31, 2026, autofill should carry forward the Dec 15 snapshot into January — but this is not stated.

Proposal: add an explicit statement: "Autofill searches backward in time without a period boundary. A snapshot from before `period_start` may be carried forward into the billing period. The search uses the `billing_objects` manager."

**Decision:**

---

### O-26. Invoice generate endpoint does not specify behavior when `selection_scope` conflicts with `selected_resource_types`/`explicit_resources`

**Files:** `docs/PRP/003-invoice-api.prp.md` (lines 19-39)

The spec does not define what happens when:
- `selection_scope = "all_resources"` but `selected_resource_types` or `explicit_resources` is non-empty
- `selection_scope = "resource_types"` but `explicit_resources` is also non-empty
- `selection_scope = "explicit_resources"` but `selected_resource_types` is non-empty

Without this, an implementer must guess — silently ignore extra fields or return 400.

Proposal: specify validation rules:
- `all_resources`: both `selected_resource_types` and `explicit_resources` must be empty/absent, else 400
- `resource_types`: `selected_resource_types` must be non-empty; `explicit_resources` must be absent, else 400
- `explicit_resources`: `explicit_resources` must be non-empty; `selected_resource_types` must be absent, else 400

**Decision:**

---

### O-27. `all_resources` and `explicit_resources` scope: billing engine manager not specified

**Files:** `.claude/docs/BILLING.md` (lines 119-128), `docs/PRP/003-invoice-api.prp.md` (line 324)

For `all_resources` scope, which manager does the billing engine use to find resources? The default manager excludes soft-deleted resources. Using it would silently exclude soft-deleted resources from historical period invoices, producing incorrect results.

For `explicit_resources` ownership validation: if the default manager is used, a soft-deleted resource appears as "not found" — a misleading error.

Proposal: add an explicit statement: "The billing engine uses `billing_objects` manager for all resource queries during invoice generation. The default manager is only for CRUD API endpoints. For explicit resource ownership validation, `billing_objects` is used so that soft-deleted (historically billable) resources can be explicitly selected."

**Decision:**

---

## MEDIUM (additional)

### O-28. `ResourceModel.status` and `Invoice.status` choices not specified as Django `TextChoices`

**Files:** `docs/PRP/002-resource-models.prp.md` (lines 188, 307)

Both status fields use choice values but no `TextChoices` classes are defined. Additionally, resource status uses UPPERCASE (`UNASSIGNED`, `ACTIVE`, `RETIRED`) while invoice status uses lowercase (`draft`, `finalized`). This casing asymmetry is not documented as intentional.

Proposal: specify `TextChoices` classes for both. Decide whether to standardize casing. Suggested: keep the existing values as documented (UPPERCASE for resource status, lowercase for invoice status) but document the asymmetry as intentional, explaining that resource status follows infrastructure conventions and invoice status follows document lifecycle conventions.

**Decision:**

---

### O-29. `Invoice.total_amount` nullable but generation always sets it — missing check constraint

**Files:** `docs/PRP/002-resource-models.prp.md` (line 308)

`total_amount` is nullable but invoice generation always sets it. A null `total_amount` on a committed row indicates data integrity failure. A database check constraint would provide defense-in-depth:

`CHECK (status = 'draft' OR total_amount IS NOT NULL)`

This ensures finalized invoices always have a total even if the service layer fails to set it.

Proposal: add the check constraint to the Invoice model spec, or add a note that `total_amount IS NULL` on a committed row is a data integrity violation that should be monitored.

**Decision:**

---

### O-30. `selection_scope` not defined as a formal `TextChoices` — any string accepted

**Files:** `docs/PRP/001-billing-engine.prp.md` (lines 232-234), `docs/PRP/002-resource-models.prp.md` (line 305)

`selection_scope` is `CharField(max_length=50)` but no formal choices enforcement is specified. Any string could be stored.

Proposal: define a `SelectionScope` `TextChoices` class (`all_resources`, `resource_types`, `explicit_resources`) and add it as `choices` on the field.

**Decision:**

---

### O-31. `BillingAccount.name` uniqueness — serializer validation not specified

**Files:** `docs/PRP/002-resource-models.prp.md` (line 112)

`BillingAccount.name` is unique. Database uniqueness violations raise `IntegrityError`, which DRF does not automatically convert to 400. The serializer needs explicit `UniqueValidator` or the service layer needs to catch `IntegrityError`. Same issue for `PriceList.name`.

Proposal: add a note that serializers for `BillingAccount` and `PriceList` must include `UniqueValidator` on `name`, or that the service layer handles `IntegrityError` with a structured 400 response.

**Decision:**

---

### O-32. Ingestion event models — uniqueness constraint intent not documented

**Files:** `docs/PRP/resources/storage-hotel.prp.md` (lines 86-108), `docs/PRP/resources/virtual-machine.prp.md` (lines 80-106)

`QuotaIngestionEvent` and `VirtualMachineUsageIngestionEvent` have no uniqueness constraints. It is unclear whether this is intentional (append-only audit log, duplicates acceptable) or an oversight.

Proposal: add an explicit note: "Ingestion event models intentionally have no uniqueness constraint. They are append-only audit logs. Idempotency is enforced by the snapshot model's `(resource, date) UNIQUE` constraint, not by the event model."

**Decision:**

---

### O-33. No database indexes specified beyond UNIQUE constraints

**Files:** All PRPs

The following query patterns are implied by the spec but no explicit indexes are documented:

1. Invoice lookup by `(billing_account, period_start, period_end, selection_scope, selection_fingerprint)` — used for duplicate detection
2. Invoice filtering by `billing_account`, `status` — list endpoint
3. InvoiceDailyCost lookup by `(invoice, resource_type, resource_id)` — aggregation
4. ResourcePrice lookup by `(price_list, resource_type, pricing_dimension)` with date filtering — price resolution
5. Resource filtering by `billing_account`, `status`, `deleted_at IS NULL` — billing engine + list endpoints
6. Partial index on `deleted_at IS NULL` for the default manager

Proposal: add a "Required Indexes" section to `002-resource-models.prp.md` specifying indexes beyond those implied by UNIQUE and FK constraints.

**Decision:**

---

### O-34. Invoice duplicate prevention unique constraint not formally specified

**Files:** `docs/PRP/002-resource-models.prp.md` (lines 286-292), `docs/PRP/001-billing-engine.prp.md` (lines 275-278)

The spec says "at most one draft invoice per `(billing_account, period_start, period_end, selection_scope, selection_fingerprint)`" but no UNIQUE constraint is formally specified on the Invoice model. Without it, concurrent requests could bypass the advisory lock and create duplicates.

Proposal: add to the Invoice model constraints: `UniqueConstraint(fields=["billing_account", "period_start", "period_end", "selection_scope", "selection_fingerprint"], name="unique_invoice_selection")`.

**Decision:**

---

### O-35. Check constraints for date ordering not specified

**Files:** `docs/PRP/002-resource-models.prp.md` (line 213), `docs/PRP/003-invoice-api.prp.md` (line 318), `docs/PRP/005-pricing-api.prp.md` (line 261)

Three cross-field ordering rules are validated at the service layer but have no database check constraints:

1. `ResourceModel`: `active_to >= active_from` (when both are set)
2. `Invoice`: `period_end >= period_start`
3. `ResourcePrice`: `effective_to >= effective_from` (when `effective_to` is set)

Proposal: specify Django `CheckConstraint` for each:
- `Q(active_to__isnull=True) | Q(active_to__gte=F("active_from"))` on ResourceModel (abstract, using `%(app_label)s_%(class)s_` naming prefix)
- `Q(period_end__gte=F("period_start"))` on Invoice
- `Q(effective_to__isnull=True) | Q(effective_to__gte=F("effective_from"))` on ResourcePrice

**Decision:**

---

### O-36. `Invoice.currency` derivation during generation not specified

**Files:** `docs/PRP/002-resource-models.prp.md` (line 304), `docs/PRP/001-billing-engine.prp.md` (line 320)

Invoice has `currency` defaulting to `"NOK"` but the spec does not say how `Invoice.currency` is set during generation — hardcoded to "NOK", derived from the first resolved price, or from the BillingAccount?

Proposal: clarify that in v1, `Invoice.currency` is always hardcoded to `"NOK"`. The billing engine validates all resolved prices have `price_currency = "NOK"` and fails with a clear error if any mismatch is found. The field exists for future multi-currency support.

**Decision:**

---

### O-37. Soft-delete invariant `active_to <= date(deleted_at)` has timezone complexity

**Files:** `docs/PRP/resources/storage-hotel.prp.md` (line 47), `docs/PRP/resources/virtual-machine.prp.md` (line 145)

`active_to` is a `DateField`; `deleted_at` is a `DateTimeField`. The comparison requires extracting the date from the datetime in the `Europe/Oslo` timezone. A database check constraint would need `AT TIME ZONE 'Europe/Oslo'` which is complex.

Proposal: specify that this invariant is enforced only at the service layer (in the soft-delete service), not as a database check constraint. The service must use `Europe/Oslo` timezone: `active_to <= deleted_at.astimezone(ZoneInfo("Europe/Oslo")).date()`.

**Decision:**

---

### O-38. `price_per_unit_year` "positive" — does this mean `> 0` or `>= 0`?

**Files:** `docs/PRP/005-pricing-api.prp.md` (lines 262-263)

The spec says `price_per_unit_year must be positive` and `discount_price_per_unit_year must be positive if set`. Does "positive" mean `> 0` (strictly, zero excluded) or `>= 0` (non-negative, zero allowed)?

A price of zero would represent a free resource. If free resources should use `make_invoice=False` instead, zero prices should be prohibited.

Proposal: clarify whether zero is allowed. If not, add a check constraint `price_per_unit_year > 0` and document that free resources are handled via `make_invoice=False`, not zero pricing.

**Decision:**

---

### O-39. `discount_price_per_unit_year < price_per_unit_year` cross-field validation missing

**Files:** `docs/PRP/005-pricing-api.prp.md`

The spec does not require `discount_price < price`. A misconfigured "discount" greater than the normal price would silently overbill customers who exceed the discount threshold.

Proposal: add cross-field validation at the service layer and as a check constraint: `discount_price_per_unit_year < price_per_unit_year` when both are set.

**Decision:**

---

### O-40. `request_id` source on ingestion events not specified

**Files:** `docs/PRP/resources/storage-hotel.prp.md` (line 106), `docs/PRP/resources/virtual-machine.prp.md` (line 104), `docs/PRP/004-resource-api.prp.md` (lines 167-213, 381-410)

Both ingestion event models have `request_id: UUIDField, nullable` but the ingestion API endpoint request body specs do not include `request_id`. It is unclear whether `request_id` comes from:
- (a) A request body field
- (b) An HTTP header (e.g., `X-Request-ID`)
- (c) Server-side middleware generation

Proposal: specify the source. If from the caller, add it as an optional field to the ingestion endpoint request body spec. If from an HTTP header, document which header. If server-generated, document the generation mechanism.

**Decision:**

---

### O-41. `raw_payload` content definition missing

**Files:** `docs/PRP/resources/storage-hotel.prp.md` (line 104), `docs/PRP/resources/virtual-machine.prp.md` (line 100)

Both ingestion event models have `raw_payload: JSONField, required` but what goes into it is not specified. Is it the entire HTTP request body as received, or just the validated/normalized subset?

Proposal: specify that `raw_payload` stores the exact JSON body sent by the client before any validation or normalization, for audit reproducibility.

**Decision:**

---

### O-42. Default ordering for list endpoints not specified

**Files:** `docs/PRP/003-invoice-api.prp.md`, `docs/PRP/004-resource-api.prp.md`, `docs/PRP/005-pricing-api.prp.md`

No list endpoint specifies default ordering. Without it, DRF pagination produces nondeterministic results — items can appear on multiple pages or be skipped.

Proposal: specify default ordering for each list endpoint:
- Invoices: `-created_at` (newest first)
- Resources (StorageHotel, VirtualMachine): `id` or `name`
- BillingAccounts: `name`
- PriceLists: `name`
- ResourcePrices: `effective_from`

**Decision:**

---

### O-43. `active_from`/`active_to` filter semantics on resource list endpoints ambiguous

**Files:** `docs/PRP/004-resource-api.prp.md` (lines 91-92, 300-304)

`active_from` and `active_to` filter descriptions are ambiguous. Does `active_from=2026-03-01` mean:
- (a) Resources where the `active_from` field value is `>= 2026-03-01` (field comparison)
- (b) Resources that are active on 2026-03-01, i.e., `active_from <= 2026-03-01 AND (active_to IS NULL OR active_to >= 2026-03-01)` (date-range overlap)

These are fundamentally different queries with different results.

Proposal: clarify the semantics. Option (a) is simpler to implement. If (a), rename the filter parameters to `active_from_gte` and `active_to_lte`, or document them clearly as field-value comparisons, not date-range overlap filters.

**Decision:**

---

### O-44. Default pagination page size not specified

**Files:** `.claude/docs/API.md` (lines 125-132)

`API.md` says DRF `PageNumberPagination` is used with "project-level defaults." No actual page size is specified. The developer must choose before writing any view.

Proposal: specify a default page size (e.g., 50) and a maximum page size (e.g., 200) in the API spec.

**Decision:**

---

### O-45. `InvoiceDailyCost` model base class not specified

**Files:** `docs/PRP/002-resource-models.prp.md` (lines 418-450)

`InvoiceDailyCost` has `created_at` in its field list but its base class (e.g., `CreatedAtModel`) is not explicitly stated. `InvoiceLine` explicitly states `CreatedAtModel`. The omission creates ambiguity.

Proposal: add: "InvoiceDailyCost inherits from `CreatedAtModel` (append-only, no `updated_at`)."

**Decision:**

---

### O-46. `deleted_at` missing from ResourceModel "Field types:" section

**Files:** `docs/PRP/002-resource-models.prp.md` (lines 183-191)

`deleted_at` is in the ResourceModel field list and described in a paragraph, but is not listed in the "Field types:" section alongside other fields. An implementer reading only the field types section would miss it.

Proposal: add `deleted_at` to the Field types section: `deleted_at` — DateTimeField, nullable (null = not soft-deleted).

**Decision:**

---

### O-47. `TESTING_TEMPLATES.md` has no VirtualMachine-specific billing test templates

**Files:** `.claude/docs/TESTING_TEMPLATES.md`

All concrete billing test templates are StorageHotel-specific. VirtualMachine has fundamentally different billing (three dimensions, MB-to-GB conversion, multi-dimension discount logic). Key untemplate scenarios:
- Multi-dimension billing: cpu + ram + disk summed into one `InvoiceDailyCost`
- MB-to-GB conversion boundary (e.g., 1023 MB vs 1024 MB)
- Mixed discount: one dimension above threshold, others below
- Zero value in one dimension with non-zero others

Proposal: add at least one concrete VirtualMachine test template showing multi-dimension billing math.

**Decision:**

---

### O-48. `missing_snapshot` error response for multiple resources not specified

**Files:** `docs/PRP/003-invoice-api.prp.md` (lines 361-373)

The `missing_snapshot` 422 error example shows one resource. When multiple resources have missing data, the response should list all of them. An implementer following the single-resource example would design a single-resource-only error shape.

Proposal: add a note or multi-resource example: "When multiple resources have missing data, `details` is a list of objects, each with `resource_type`, `resource_id`, and `missing_dates`."

**Decision:**

---

## LOW (additional)

### O-49. `VirtualMachine.provisioner` field constraints incomplete

**Files:** `docs/PRP/resources/virtual-machine.prp.md` (lines 30-33)

`provisioner` has only one allowed value (`VCENTER`) but `max_length` is not specified and the choices implementation mechanism (Django `TextChoices` class vs plain list) is not specified.

Proposal: specify `CharField(max_length=50, choices=Provisioner.choices)` with a `Provisioner` TextChoices class.

**Decision:**

---

### O-50. `StorageHotel.quota_unit` choices class and `max_length` not specified

**Files:** `docs/PRP/resources/storage-hotel.prp.md` (lines 30-35)

Same issue as O-49 for `quota_unit`. Values are `KB` and `KIB` but no `max_length` or `TextChoices` class is specified.

Proposal: specify `CharField(max_length=10, choices=QuotaUnit.choices)` with a `QuotaUnit` TextChoices class.

**Decision:**

---

### O-51. `StorageHotel.quota_raw` precision notes for testing

**Files:** `docs/PRP/resources/storage-hotel.prp.md` (line 78)

`quota_raw` is `DecimalField(max_digits=25, decimal_places=4)`. Tests should exercise realistic magnitude values (1 TB = 10,000,000 KiB = ~10,000,000,000 raw) to ensure the Decimal pipeline handles real-world magnitudes correctly.

Proposal: add a note in `TESTING_TEMPLATES.md` that tests should use realistic KB/KiB magnitudes, not small integers, to catch precision issues in the conversion pipeline.

**Decision:**

---

### O-52. `cpu_count` Decimal coercion is an internal concern — API must stay integer

**Files:** `docs/PRP/resources/virtual-machine.prp.md` (line 72), `docs/PRP/001-billing-engine.prp.md`

`cpu_count` is `PositiveIntegerField` and `001-billing-engine.prp.md` states it must be coerced to `Decimal` during billing normalization. This is an internal billing engine concern. The API serializer must return `cpu_count` as a JSON integer, not a Decimal string.

Proposal: add a note: "`cpu_count` is serialized as a JSON integer in all API responses. Decimal coercion (`Decimal(str(cpu_count))`) happens only inside the billing calculation pipeline."

**Decision:**

---

### O-53. No `__str__` method specified for any model

**Files:** All PRPs

No model specifies a `__str__` implementation. While not blocking, meaningful `__str__` methods are essential for Django admin, shell exploration, and log readability.

Proposal: add a brief note that models should implement `__str__`. Suggested representations:
- `BillingAccount`: `f"{self.name}"`
- `Invoice`: `f"Invoice {self.id} ({self.status})"`
- `StorageHotel`: `f"{self.namespace}/{self.name}"`
- `VirtualMachine`: `f"{self.namespace}/{self.provisioner}/{self.name}"`
- `ResourcePrice`: `f"{self.resource_type}/{self.pricing_dimension} ({self.effective_from}-)"`

**Decision:**

---

### O-54. Decimal values in JSONField metadata must be serialized as strings — no rule stated

**Files:** `docs/PRP/002-resource-models.prp.md`, `docs/PRP/001-billing-engine.prp.md`

JSON has no native Decimal type. Python's default `json.dumps()` and Django's `JSONField` do not handle `Decimal` natively. Examples throughout the spec show Decimal values as strings (e.g., `"quota_tb": "120"`), but no implementation rule is stated.

Proposal: add a global rule: "All Decimal values stored in JSONField metadata must be serialized as strings. Use `DjangoJSONEncoder` on all JSONField definitions (`models.JSONField(default=dict, encoder=DjangoJSONEncoder)`) to handle Decimal, datetime, date, and UUID types automatically."

**Decision:**

---

### O-55. `set-effective-to` endpoint overlap validation scope unclear

**Files:** `docs/PRP/005-pricing-api.prp.md` (lines 311-312)

The `set-effective-to` endpoint closes an open-ended price. The newly bounded range `[effective_from, new_effective_to]` could overlap with another existing row for the same `(price_list, resource_type, pricing_dimension)`. The service-layer validation must explicitly check this overlap before the database exclusion constraint fires, to provide a clear error message.

Proposal: add: "The service must validate that `[row.effective_from, new_effective_to]` does not overlap any other row in the same `(price_list, resource_type, pricing_dimension)` group."

**Decision:**

---

---

## SECTION 2: Pre-Development Considerations

These are items to decide or verify **before writing the first line of application code**. They are ordered by dependency — earlier items must be resolved before later ones.

---

### C-1. Create the Django project skeleton first

**Category:** Architecture Decision

The repository has `pyproject.toml` and pre-commit config but no Django project skeleton. Before any model or service code can be written, create:
- `config/settings/base.py`, `dev.py`, `test.py`
- `config/urls.py`, `wsgi.py`, `asgi.py`
- `manage.py`
- `apps/__init__.py`, `apps/billing/apps.py`, `apps/ingest/apps.py`
- `INSTALLED_APPS`, `REST_FRAMEWORK`, `DEFAULT_AUTO_FIELD = "django.db.models.BigAutoField"`
- `TIME_ZONE = "Europe/Oslo"`, `USE_TZ = True`

Verify `uv run python manage.py check` passes before any other work.

---

### C-2. Verify pre-commit hooks pass before writing Python

**Category:** Django Convention

The `.pre-commit-config.yaml` runs `mypy` and `django-doctor`, both of which require a valid `DJANGO_SETTINGS_MODULE`. Until the project skeleton exists, these hooks will fail on any Python file. Verify `pre-commit run --all-files` passes on the empty skeleton before writing models.

---

### C-3. Prototype the `btree_gist` exclusion constraint before writing migrations

**Category:** Data Migration Risk

The `ResourcePrice` date-range overlap exclusion constraint requires `btree_gist`. This must be prototyped in a test migration early. The `btree_gist` extension requires superuser or `CREATE EXTENSION` privilege. Confirm the development PostgreSQL user has this privilege before starting.

---

### C-4. Decide all CharField `max_length` values before writing models

**Category:** Architecture Decision

Changing `max_length` after migrations are created requires additional migrations and risks data truncation if reduced. See O-19 for the full table of fields needing `max_length` decisions.

---

### C-5. Define all Django `TextChoices` classes before writing models

**Category:** Django Convention

`ResourceStatus`, `InvoiceStatus`, `SelectionScope`, `QuotaUnit`, `Provisioner`, `ResourceType`, `PricingDimension` — define all choices classes upfront in a shared module (e.g., `apps/billing/choices.py`) so models, serializers, and services use consistent values.

---

### C-6. Decide the `DjangoJSONEncoder` strategy for all JSONFields

**Category:** Billing Invariant

All JSONField metadata stores Decimal values as strings. Use `models.JSONField(default=dict, encoder=DjangoJSONEncoder)` on every JSONField in the project. Decide this once and apply consistently before writing any model.

---

### C-7. Create the migration order plan before running `makemigrations`

**Category:** Data Migration Risk

Dependency order:
1. `apps/billing/` — PriceList, BillingAccount, ResourcePrice, ResourceModel→StorageHotel/VirtualMachine, snapshot models, Invoice, InvoiceLine, InvoiceDailyCost
2. `apps/ingest/` — QuotaIngestionEvent, VirtualMachineUsageIngestionEvent (FK to billing models)

Run `makemigrations billing` first, then `makemigrations ingest`. Do not run both simultaneously.

---

### C-8. Configure `REST_FRAMEWORK` settings before writing serializers

**Category:** Architecture Decision

Key settings to decide upfront:
- `PAGE_SIZE` (see O-44 — propose 50)
- `COERCE_DECIMAL_TO_STRING = True` — ensures Decimal fields render as strings in JSON
- `DEFAULT_PERMISSION_CLASSES = ["rest_framework.permissions.AllowAny"]` for v1
- `DEFAULT_AUTHENTICATION_CLASSES = []` for v1
- `DEFAULT_SCHEMA_CLASS = "drf_spectacular.openapi.AutoSchema"`

---

### C-9. Implement and test pure functions before any Django-dependent code

**Category:** Billing Invariant

These pure functions have no Django dependencies and can be built and tested first:
1. Unit conversion functions: `kb_to_tb()`, `kib_to_tb()`, `mb_to_gb()`
2. Selection fingerprint computation (SHA-256 of canonical JSON)
3. Advisory lock key computation
4. Invoice number formatter

Test each exhaustively with known values before wiring into services.

---

### C-10. Decide the invoice number PostgreSQL sequence creation strategy

**Category:** Architecture Decision

The sequence must be created in a Django migration (`RunSQL`) before any invoice finalization is possible. The sequence name should be a project constant. Test concurrent finalization calls to verify sequence correctness.

---

### C-11. Plan the service module structure for `apps/billing/services/`

**Category:** Architecture Decision

The billing engine is too complex for a single file. Proposed structure:
```
apps/billing/services/
  __init__.py
  invoice_generation.py  # orchestration
  invoice_finalization.py
  price_resolution.py
  resource_selection.py
  daily_cost.py
apps/ingest/services/
  __init__.py
  quota_ingestion.py
  vm_usage_ingestion.py
```

---

### C-12. Ensure `billing_objects` is the second manager, not the first

**Category:** Django Convention

Django uses the first manager as `_default_manager`. DRF serializers, admin, and `ModelForm` use it by default. Define `objects = ActiveResourceManager()` first, `billing_objects = AllResourceManager()` second on every concrete resource model.

---

### C-13. Create a `today_oslo()` utility function before any date logic

**Category:** Billing Invariant

All "today" comparisons must use `Europe/Oslo` timezone. Create a single utility: `def today_oslo() -> date: return datetime.now(ZoneInfo("Europe/Oslo")).date()`. Use this everywhere instead of `date.today()` or `timezone.now().date()`.

---

### C-14. Decide the error response format — DRF default vs. unified structured format

**Category:** Architecture Decision

DRF field validation errors use `{"field": ["message"]}`. Domain errors use `{code, message, details}`. Decide whether to:
- (a) Keep both formats (simpler but inconsistent)
- (b) Write a custom DRF exception handler that wraps all errors in `{code, message, details}` (consistent)

Option (b) is strongly recommended for a financial API. Implement the custom handler before writing any view.

---

### C-15. Decide the build order for the full implementation

**Category:** Architecture Decision

Recommended sequence:
1. Project skeleton + settings + pre-commit verification
2. Abstract base models (TimestampedModel, CreatedAtModel, BillingAccountBase, ResourceModel)
3. PriceList, BillingAccount, ResourcePrice
4. StorageHotel, VirtualMachine
5. Snapshot models (StorageHotelDailyQuota, VirtualMachineDailyUsage)
6. Invoice, InvoiceLine, InvoiceDailyCost
7. Ingestion event models
8. All migrations
9. Pure utility functions (conversion, fingerprint, lock key, invoice number)
10. Price resolution service + tests
11. Resource selection service + tests
12. Daily cost calculation service + tests
13. Invoice generation orchestration + tests
14. Invoice finalization service + tests
15. Serializers and ViewSets (CRUD endpoints)
16. Ingestion endpoint views
17. Invoice API endpoint views
18. URL routing
19. API integration tests
20. End-to-end billing scenario tests
