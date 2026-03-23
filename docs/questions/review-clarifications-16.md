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
