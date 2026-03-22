# Review Clarifications 15

Architecture review round 15 — cross-document consistency audit after round 14.
Edit each `**Decision:**` line with your answer.

---

## HIGH

### O-1. `BILLING.md` Invoice Total section uses wrong field names

`BILLING.md` Invoice Total section (updated in round 14 O-4) references `InvoiceDailyCost.amount` and `InvoiceLine.total` and `Invoice.total`. The authoritative field names per `002-resource-models.prp.md` are:

- `InvoiceDailyCost.daily_cost` (not `.amount`)
- `InvoiceLine.total_cost` (not `.total`)
- `Invoice.total_amount` (not `.total`)

An implementer following `BILLING.md` would create model fields with incorrect names or look for non-existent attributes.

Proposal: update the Invoice Total section in `BILLING.md` to use the correct field names:

```
InvoiceLine.total_cost = sum(InvoiceDailyCost.daily_cost) for that (invoice, resource_type, resource_id)
Invoice.total_amount = round(sum(InvoiceLine.total_cost), 2, ROUND_HALF_UP)
```

**Decision:**

---

### O-2. `BILLING.md` description construction rule contradicts the PRP — wrong format

`BILLING.md` step 9 of the Example Shared Workflow (added in round 14 O-14) says:

> Construct `InvoiceLine.description`: combine the resource type label and resource name/identifier into a human-readable string, e.g. `"StorageHotel: my-hotel-name"` or `"VirtualMachine: my-vm-name"`

However, `002-resource-models.prp.md` specifies:

> set to the resource's `name` field if present and non-blank, otherwise falls back to `{ResourceType} #{resource_id}` (e.g., `StorageHotel #101`)

The PRP says `description = name` (just the name, no type prefix). The prefix is only used as a fallback when name is blank. The API response examples in `003-invoice-api.prp.md` confirm this: `"description": "storage-primary"` — just the resource name.

Proposal: update `BILLING.md` step 9 to match the PRP:

> Set `InvoiceLine.description` from the resource's `name` if present and non-blank; otherwise use `{ResourceType} #{resource_id}` as a fallback (e.g., `StorageHotel #101`). Never recomputed from the live resource after generation.

**Decision:**

---

### O-3. `namespace` field missing from `ResourceModel` abstract field list in `002-resource-models.prp.md`

Round 14 added `namespace` as a new field on `ResourceModel` (abstract base), making it optional at the abstract level but required on `StorageHotel` and `VirtualMachine`. However, `002-resource-models.prp.md` still lists `ResourceModel` fields without `namespace`:

```
billing_account
name
description_resource
status
active_from
active_to
deleted_at
```

The resource-specific PRPs do include `namespace` in their field lists, but the shared `ResourceModel` definition they inherit from is missing it. An implementer building the abstract model will omit `namespace`.

Two options:

- **(a)** Add `namespace` as an optional abstract field on `ResourceModel` with a note that concrete models (StorageHotel, VirtualMachine) make it required. Specify: `namespace` — CharField, optional at the abstract level (blank=True, default="").
- **(b)** Keep `namespace` off `ResourceModel` entirely and define it only on concrete models. This means it is not inherited and each concrete model must define it independently.

Proposal: **(a)** — consistent with the round 14 decision that said "new field `namespace` was added to ResourceModel."

**Decision:**

---

### O-4. Duplicate `quota_unit` key and missing comma in StorageHotel `resource_snapshot` schema

`storage-hotel.prp.md` canonical resource_snapshot schema block contains `quota_unit` twice and is missing a comma:

```json
{
  "id": "<int>",
  "name": "<str>",
  "namespace": "<str>",
  "quota_unit": "<str>"
  "quota_unit": "<str>",
  "description_resource": "<str>"
}
```

This is invalid JSON. The same duplication appears in `002-resource-models.prp.md`. Also present in the invoice expectations example in `storage-hotel.prp.md`.

Proposal: remove the duplicate `quota_unit` line and add the missing comma. Correct schema:

```json
{
  "id": "<int>",
  "name": "<str>",
  "namespace": "<str>",
  "quota_unit": "<str>",
  "description_resource": "<str>"
}
```

**Decision:**

---

### O-5. Missing comma in VirtualMachine `resource_snapshot` schema

`virtual-machine.prp.md` canonical resource_snapshot schema is missing a comma after `"provisioner"`:

```json
{
  "id": "<int>",
  "name": "<str>",
  "namespace": "<str>",
  "provisioner": "<str>"
  "description_resource": "<str>"
}
```

The same syntax error appears in the InvoiceLine metadata example in `002-resource-models.prp.md` and in `virtual-machine.prp.md` invoice expectations section.

Proposal: fix all missing commas in all occurrences of this schema in both files.

**Decision:**

---

## MEDIUM

### O-6. Inconsistent `quota_unit` value across StorageHotel examples (`"KB"` vs `"KIB"`)

Three documents show StorageHotel InvoiceLine metadata examples with different `quota_unit` values:

- `002-resource-models.prp.md`: `"quota_unit": "KB"`
- `003-invoice-api.prp.md`: `"quota_unit": "KIB"`
- `storage-hotel.prp.md`: `"quota_unit": "KB"`

Both are valid values. The inconsistency across documents could confuse implementers writing test fixtures.

Proposal: align all examples to use `"KIB"` to match the API spec examples in `003-invoice-api.prp.md`, or add a note that the value varies per resource instance. No behaviour change required.

**Decision:**

---

### O-7. Duplicate `**Query parameters:**` header in VirtualMachine list endpoint

`004-resource-api.prp.md` VirtualMachine list endpoint contains two separate `**Query parameters:**` headers — an artifact from round 14 O-8 where `active_from` and `active_to` were appended as a second block rather than merged into the first.

Proposal: merge the two `**Query parameters:**` blocks into a single block listing all five parameters: `billing_account`, `status`, `provisioner`, `active_from`, `active_to`.

**Decision:**

---

### O-8. VirtualMachine list endpoint missing `name` filter — asymmetry with StorageHotel

StorageHotel list endpoint includes `name` as a query parameter filter. VirtualMachine list endpoint does not. Both resources inherit `name` from `ResourceModel`. The same symmetry rationale from round 14 O-8 applies.

Proposal: add `name` (optional, string) as a query parameter to the VirtualMachine list endpoint.

**Decision:**

---

### O-9. Both resource list endpoints missing `namespace` filter

Round 14 explicitly stated "Claude must add [namespace] in querysets, filters, and API endpoints where relevant." However:

- StorageHotel list endpoint (`004-resource-api.prp.md`) is missing a `namespace` filter. Uniqueness constraint is `(namespace, name)`.
- VirtualMachine list endpoint is also missing a `namespace` filter. Uniqueness constraint is `(namespace, provisioner, name)`.

Proposal: add `namespace` (optional, string) as a query parameter to both the StorageHotel and VirtualMachine list endpoints.

**Decision:**

---

### O-10. StorageHotel list response example missing `namespace` field

`004-resource-api.prp.md` StorageHotel list response example does not include `namespace` in the response body, even though `namespace` is a required field on StorageHotel. The POST response example does include it. The list response should include the same fields.

Proposal: add `"namespace": "uio_fs01"` (or equivalent) to the StorageHotel list response example.

**Decision:**

---

### O-11. `BILLING.md` `autofilled` description misleadingly ties it only to force-mode

`BILLING.md` `autofilled` field description (updated in round 14 O-12) says:

> True if this daily cost row was generated by force-mode autofill for a day with missing ingestion data.

`autofilled = true` is also set for carry-forward rows generated by `autofill_missing_days=true`, regardless of `force`. The PRP (`002-resource-models.prp.md`) says: "`true` when the usage was autofilled (carry-forward); `false` when from a real snapshot."

Proposal: update `BILLING.md` to match the PRP:

> `autofilled` — BooleanField, default False. True when usage was autofilled (carry-forward from prior snapshot) or when force-mode billed a missing day at zero. False when usage came from a real ingested snapshot.

**Decision:**

---

### O-12. Multiple JSON examples have missing commas in `002-resource-models.prp.md` and `003-invoice-api.prp.md`

Several `resource_snapshot` JSON blocks inside InvoiceLine metadata examples are missing commas between keys, making them syntactically invalid JSON. Affected locations:

- `002-resource-models.prp.md` — StorageHotel and VirtualMachine InvoiceLine metadata examples
- `003-invoice-api.prp.md` — invoice list, detail, and finalize response examples

Proposal: fix all missing commas in JSON examples across both files. No behaviour change; documentation correctness only.

**Decision:**

---

### O-13. `InvoiceLine.description` declared nullable but fallback logic always produces a value

`002-resource-models.prp.md` specifies: `description` — CharField(max_length=255), optional (blank=True, null=True).

The description construction rule guarantees `description` is always set at invoice generation time (name or `{ResourceType} #{resource_id}` fallback). Making it nullable implies it can be null in normal operation, which contradicts the fallback guarantee.

Two options:

- **(a)** Keep nullable — allows manual InvoiceLine creation without a description, or accommodates rows created before this rule existed.
- **(b)** Make non-nullable with `blank=True, default=""` — since generation always sets it. Stronger: make it `blank=False` to enforce it at the model level.

Proposal: **(b)** with `blank=True, default=""` — non-nullable to reflect that generation always produces a value, but with blank allowed for edge cases.

**Decision:**

---

## LOW

### O-14. Force-mode zero-cost row in `001-billing-engine.prp.md` missing explicit `dimension_costs` shape and concrete example

`001-billing-engine.prp.md` documents the zero-cost forced row partially but does not show a concrete metadata example with the complete shape including `dimension_costs`.

Proposal: add a concrete example for a force-mode zero-cost StorageHotel row:

```json
{
  "normalized_usage": {"quota_tb": "0"},
  "resolved_prices": {"quota_tb": {"price_per_unit_year": "500", "currency": "NOK", "discount_applied": false}},
  "dimension_costs": {"quota_tb": "0"},
  "autofilled": true
}
```

**Decision:**

---

### O-15. `001-billing-engine.prp.md` uses field name `amount` instead of `daily_cost` for force-mode zero-cost row

`001-billing-engine.prp.md` line in the force-mode zero-cost row spec says:

> `amount` = Decimal("0.00")

The actual field name on `InvoiceDailyCost` is `daily_cost` (per `002-resource-models.prp.md`). This is a naming inconsistency within the PRPs themselves.

Proposal: change `amount` to `daily_cost` in that line.

**Decision:**

---

### O-16. VirtualMachine PATCH endpoint does not mention `namespace` patchability

`004-resource-api.prp.md` VirtualMachine PATCH lists patchable fields and notes `provisioner` as non-patchable, but `namespace` is not mentioned at all. By contrast, StorageHotel PATCH lists `namespace` as patchable.

Since `namespace` is part of VirtualMachine's uniqueness constraint `(namespace, provisioner, name)`, the decision matters:

- **(a)** Make `namespace` patchable on VirtualMachine — consistent with StorageHotel behavior.
- **(b)** Make `namespace` non-patchable on VirtualMachine — consistent with `provisioner` treatment (identity fields should be stable).
- **(c)** Make `namespace` non-patchable on both resources — if namespace is considered an identity/organizational field that should not change after creation.

Proposal: clarify intent. If `namespace` is an organizational grouping that operators might reassign, **(a)**. If it is part of resource identity (like `provisioner`), **(b)** or **(c)**.

**Decision:**

---

### O-17. Direct contradiction: `BILLING.md` says `autofilled=false` for force-mode zero rows; PRP says `autofilled=True`

`BILLING.md`:

> under `force=true`, those days produce a zero-cost `InvoiceDailyCost` row with `autofilled=false`

`001-billing-engine.prp.md`:

> `autofilled` = True

These directly contradict each other. PRPs are the source of truth, so `BILLING.md` is wrong.

Proposal: update `BILLING.md` to set `autofilled=true` for force-mode zero-cost rows, matching the PRP.

**Decision:**

---

### O-19. `autofilled` semantic overloading needs a clarifying note in `001-billing-engine.prp.md`

`autofilled = true` covers two distinct scenarios:

1. Carry-forward rows — usage filled from prior snapshot (non-zero values).
2. Force-mode zero-cost rows — usage fabricated as zeros (no prior snapshot).

Both are "not from a real snapshot" but their metadata shapes differ. Without a note, implementers may conflate them.

Proposal: add a clarifying note near the `autofilled` documentation in `001-billing-engine.prp.md`:

> `autofilled = true` covers two cases: (1) carry-forward — `normalized_usage` matches a prior snapshot and is non-zero; (2) force-mode zero fallback — `normalized_usage` contains fabricated zeros. The distinction is visible in the metadata values: carry-forward rows have non-zero usage; zero-cost fallback rows have zeroed usage.

**Decision:**

---

### O-20. `BILLING.md` "fail for that resource" wording contradicts "entire invoice generation fails"

`BILLING.md` autofill section says "fail for that resource" when no prior snapshot exists, but the very next paragraph says "the entire invoice transaction is rolled back." The PRP (`001-billing-engine.prp.md`) confirms it is a global failure.

"Fail for that resource" could be read as a per-resource skip, which is explicitly NOT the behavior.

Proposal: change "fail for that resource" to "fail the entire invoice generation" to match the PRP and the paragraph immediately below it.

**Decision:**
