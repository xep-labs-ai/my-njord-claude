# Review Clarifications 14

Architecture review round 14 — cross-document consistency audit after rounds 1-13.
Edit each `**Decision:**` line with your answer.

---

## HIGH

### O-1. `clarifications.md` Q3 and Q8 still describe per-month invoice number sequence

`clarifications.md` Q3 says "5-digit counter, global monthly sequence." Q8 says "Global per month. All billing accounts share one monthly sequence." The current PRP (`001-billing-engine.prp.md` line 385) says the counter is a "global auto-incrementing sequence (not per-month) — the counter does not reset each month." Review-clarifications-13 H-4 explicitly confirmed the global never-resetting sequence as authoritative.

If Claude reads `clarifications.md` before the PRPs and does not notice the precedence rule, it could implement a per-month resetting sequence, breaking uniqueness guarantees and violating the PRP.

Proposal: add a `**Superseded:**` marker to Q3 and Q8 in `clarifications.md` stating: "Superseded by review-clarifications-13 H-4. Current design: global never-resetting sequence. `NNNNN` is zero-padded to at least 5 digits but may grow beyond 5 digits. The counter does not reset each month. See `001-billing-engine.prp.md`."

**Decision:**

---

### O-2. Force-mode zero-cost `InvoiceDailyCost` metadata shape unspecified

Both `BILLING.md` and `001-billing-engine.prp.md` say that when `force=true` and `autofill_missing_days=false`, missing days are "billed at zero" and produce `InvoiceDailyCost` rows with `daily_cost = 0` and `autofilled = false`. However, neither document specifies what values go into the required metadata fields (`normalized_usage`, `resolved_prices`, `dimension_costs`) for these zero-cost rows.

An implementer must know:

- Should `normalized_usage` contain zeroed values (e.g., `{"quota_tb": "0"}`) or be empty/null?
- Should `resolved_prices` still contain the resolved price for that day (since missing pricing is always fatal, a price must exist)?
- Should `dimension_costs` contain zeroed values (e.g., `{"quota_tb": "0"}`) or be empty/null?

Three options:

- **(a)** Zeroed metadata: `normalized_usage` contains zero for each dimension, `resolved_prices` contains the resolved price (a price must exist), `dimension_costs` contains zero for each dimension. This is self-consistent and means the metadata always has the expected structure regardless of the data source.
- **(b)** Null/empty metadata: `normalized_usage`, `resolved_prices`, and `dimension_costs` are empty objects or null. Simpler but breaks the invariant that these fields are always present and keyed by pricing dimension.
- **(c)** Partial metadata: `normalized_usage` has zeroed values, `resolved_prices` is omitted because no snapshot data was used. Middle ground but introduces a nullable pattern for a normally-required field.

Proposal: **(a)** is the safest and most consistent. It preserves the metadata structure invariant, makes zero-cost rows auditable (the price is recorded even though the cost is zero), and requires no special-case handling when reading metadata.

**Decision:**

---

## MEDIUM

### O-3. `review-clarifications.md` RQ7 rounding answer presentation could mislead

RQ7 asked about rounding sequence (line-level vs. invoice-level). The **proposal** text recommends option (a) — round at line level. The **answer** says "b is the answer" — sum at full precision, round only at the invoice total. The PRPs and `BILLING.md` correctly implement option (b).

The issue is presentation: the proposal text is prominent and detailed, while the answer is a terse one-liner. A reader skimming the clarification file could mistake the proposal for the decision.

Proposal: add a brief clarifying note after the answer in RQ7: "Note: option (b) was chosen, overriding the proposal. Sum all `InvoiceLine.total_cost` values at full precision, then round once at `Invoice.total_amount` to 2 decimal places using `ROUND_HALF_UP`."

**Decision:**

---

### O-4. `BILLING.md` Invoice Total formula omits `InvoiceLine` aggregation step

`BILLING.md` line ~477 says `invoice_total = sum(daily_cost)`. The actual computation is two steps: (1) `InvoiceLine.total_cost = sum of InvoiceDailyCost.daily_cost for that resource`, (2) `Invoice.total_amount = round(sum of InvoiceLine.total_cost, 2)`. While mathematically equivalent, the formula as written skips the intermediate `InvoiceLine.total_cost` computation, which is a stored field at 10dp.

An implementer could compute `Invoice.total_amount` directly from daily costs without populating `InvoiceLine.total_cost`, which would leave InvoiceLine totals as zero or null.

The correct two-step aggregation is already described in the Multi-Dimension Resource Aggregation section (line ~416), but the Invoice Total section contradicts it by showing a single-step formula.

Proposal: update the Invoice Total section in `BILLING.md` to show the two-step aggregation:

```
InvoiceLine.total_cost = sum(InvoiceDailyCost.daily_cost) for that (invoice, resource_type, resource_id)
Invoice.total_amount = round(sum(InvoiceLine.total_cost), 2, ROUND_HALF_UP)
```

**Decision:**

---

### O-5. `BILLING.md` duplicate prevention section missing advisory lock cross-reference

`BILLING.md` line ~598 describes duplicate prevention using `(billing_account, period_start, period_end, selection_scope, selection_fingerprint)` but does not mention the PostgreSQL advisory lock concurrency mechanism. The full advisory lock specification is in `001-billing-engine.prp.md` (line ~258), including the lock key `(billing_account, period_start, period_end, selection_scope)` — note that the lock key intentionally excludes `selection_fingerprint`.

An implementer reading only `BILLING.md` would not know about the advisory lock requirement and could implement duplicate prevention using only database constraints, which would not prevent race conditions during concurrent invoice generation.

Proposal: add a brief cross-reference in `BILLING.md`'s duplicate prevention section: "Concurrency control uses a PostgreSQL advisory lock keyed on `(billing_account, period_start, period_end, selection_scope)` within the invoice generation transaction. See `001-billing-engine.prp.md` for the full concurrency specification."

**Decision:**

---

### O-6. Ingestion event model field types unspecified

`QuotaIngestionEvent` in `storage-hotel.prp.md` (line ~86) and `VirtualMachineUsageIngestionEvent` in `virtual-machine.prp.md` (line ~77) list their fields but do not specify Django field types, max_length constraints, or nullability. These models live in `apps/ingest/` and an implementer needs field types to write the migration.

Proposal: add field type specifications to both ingestion event models in their respective resource PRPs. Suggested types:

**QuotaIngestionEvent:**
- `storage_hotel` — FK to StorageHotel, required, on_delete=CASCADE
- `date` — DateField, required
- `raw_payload` — JSONField, required
- `normalized_quota_raw` — DecimalField(max_digits=25, decimal_places=4), required
- `request_id` — UUIDField, nullable (null if not provided by the caller)
- `created_at` — DateTimeField, auto_now_add

**VirtualMachineUsageIngestionEvent:**
- `virtual_machine` — FK to VirtualMachine, required, on_delete=CASCADE
- `date` — DateField, required
- `raw_payload` — JSONField, required
- `normalized_cpu_count` — PositiveIntegerField, required
- `normalized_ram_mb` — DecimalField(max_digits=14, decimal_places=2), required
- `normalized_disks_total_gb` — DecimalField(max_digits=14, decimal_places=2), required
- `request_id` — UUIDField, nullable (null if not provided by the caller)
- `created_at` — DateTimeField, auto_now_add

**Decision:**

---

### O-7. `review-clarifications-3.md` BQ6 says `make_invoice=False` returns 400 — PRP says 422

BQ6 in `review-clarifications-3.md` proposed returning 400 when `make_invoice = False`, and the user accepted. Later clarification rounds changed this to 422 (`billing_account_not_billable`), which is reflected in `003-invoice-api.prp.md` line 341, `002-resource-models.prp.md` line 30, `API.md` line 218, and `BILLING.md` line 189. The PRP is correct (422), but the clarification file contains a contradictory answer that was never marked as superseded.

Proposal: add a `**Superseded:**` marker to BQ6 in `review-clarifications-3.md` stating: "Superseded. The status code for `billing_account_not_billable` was changed to 422 Unprocessable Entity. See `003-invoice-api.prp.md` and `API.md` error code tables."

**Decision:**

---

### O-8. Asymmetric list filter parameters between StorageHotel and VirtualMachine

`004-resource-api.prp.md` StorageHotel list endpoint (line ~88) includes `active_from` and `active_to` as query parameters. VirtualMachine list endpoint (line ~296) includes `billing_account`, `status`, and `provisioner` but omits `active_from` and `active_to`. Both resources inherit these fields from `ResourceModel`, so the filtering capability should be symmetric unless there is an intentional reason to differ.

Two options:

- **(a)** Add `active_from` and `active_to` as optional query parameters to the VirtualMachine list endpoint, matching StorageHotel.
- **(b)** Keep the asymmetry and document the intentional omission (e.g., VirtualMachine filtering by date ranges is not expected to be useful in v1).

Proposal: **(a)**. Both resource types inherit the same base fields and an API consumer would expect consistent filtering capabilities across resource types.

**Decision:**

---

## LOW

### O-9. VM ingestion example shows `cpu_count` as string instead of JSON integer

`004-resource-api.prp.md` line ~378 shows the VM usage ingestion request body with `"cpu_count": "8"` (a JSON string). The model field `cpu_count` is a `PositiveIntegerField`. DRF serializes integer fields as JSON integers, not strings. The response example (line ~389) also shows `"cpu_count": "8"`.

While DRF handles coercion, showing an integer field value as a string in examples is misleading and inconsistent with how DRF actually serializes the field.

Proposal: change `"cpu_count": "8"` to `"cpu_count": 8` (JSON integer, no quotes) in both the request and response examples for the VM usage ingestion endpoint in `004-resource-api.prp.md`.

**Decision:**

---

### O-10. `BILLING.md` draft replacement does not mention CASCADE delete behavior

`BILLING.md` line ~620 says draft invoices "may be deleted and rebuilt internally" during `force=true` regeneration. It does not mention that this relies on `on_delete=CASCADE` on the InvoiceLine and InvoiceDailyCost foreign keys to the Invoice model (as specified in `002-resource-models.prp.md`). An implementer reading only `BILLING.md` might implement explicit child-row deletion instead of relying on CASCADE.

Proposal: add a brief note to the draft replacement section in `BILLING.md`: "Deleting the draft Invoice automatically cascades to its InvoiceLine and InvoiceDailyCost rows via `on_delete=CASCADE` (see `002-resource-models.prp.md`)."

**Decision:**

---

### O-11. ResourcePrice not explicitly stated to use CreatedAtModel

`005-pricing-api.prp.md` says ResourcePrice is "immutable — rows are never updated after creation" and the response example shows only `created_at` (no `updated_at`). However, neither `005-pricing-api.prp.md` nor `002-resource-models.prp.md` explicitly states that ResourcePrice inherits from `CreatedAtModel`. An implementer could use `TimestampedModel` (which adds `updated_at`), introducing a field that should never be populated on an immutable model.

Proposal: add a brief note to the ResourcePrice section in `002-resource-models.prp.md` or `001-billing-engine.prp.md` stating that ResourcePrice uses `CreatedAtModel` (append-only, `created_at` only, no `updated_at`).

**Decision:**

---

### O-12. `BILLING.md` Daily-level snapshot field list omits `autofilled`

`BILLING.md` line ~519 lists the fields that should be persisted per billed resource per day. The list includes "metadata about autofill or missing-data handling when relevant" but does not explicitly list `autofilled` as a dedicated `BooleanField` column. The dual-storage strategy for `autofilled` is described separately (line ~456) but the snapshot field list is incomplete.

Proposal: add `autofilled` (boolean, dedicated column — see dual-storage strategy) to the Daily-level snapshot field list in `BILLING.md`.

**Decision:**

---

### O-13. `PROJECT.md` says "clarification rounds 1-12" — 13 rounds exist

`PROJECT.md` line 38 says "PRPs (docs/PRP/), clarification rounds 1-12, and project tooling (pyproject.toml) all exist." Round 13 has been completed and applied. The count is stale.

Proposal: change "clarification rounds 1-12" to "clarification rounds 1-13" or remove the specific round count and say "clarification rounds" generically to avoid future staleness.

**Decision:**

---

### O-14. `BILLING.md` Example Shared Workflow omits `InvoiceLine.description` construction

`BILLING.md` line ~697 shows the shared workflow as 11 steps. Step 9 says "aggregate invoice lines per resource" but does not mention construction of `InvoiceLine.description` using the name-or-fallback rule (documented at line ~512). The description construction rule involves querying the resource's `name` field, applying the PascalCase fallback if blank, and freezing the result — this is a non-trivial step that an implementer following the workflow could miss.

Proposal: add a sub-step under step 9 in the workflow: "set `InvoiceLine.description` from the resource's `name` (or PascalCase fallback if blank) — see Line-level snapshot section."

**Decision:**

---

## Follow-Up Questions

No follow-up questions required. All proposals in this round are self-contained.
