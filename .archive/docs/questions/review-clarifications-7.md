# Review Clarifications 7

Architecture review findings requiring your input before implementation.
Edit each `**Decision:**` line with your answer.

---

## CRITICAL

### C-1. Daily cost formula: universal or per-resource-type?

`001-billing-engine.prp.md` shows: `daily_cost = usage × price_per_year / days_in_year(day)`

`BILLING.md` says there is no single universal formula — each resource type defines its own.

For VirtualMachine with three pricing dimensions (cpu, ram, disk), the formula would need to apply per dimension and then sum.

**Decision:** The PRP formula an illustrative example (not universal), and the canonical rule is that each resource type computes its own daily cost — potentially summing per-dimension costs

Accept this decision and document it

---

### A-1. Duplicate invoice uniqueness on JSON fields

Uniqueness is defined over `(billing_account, period_start, period_end, selection_scope, selected_resource_types, explicit_resources)`.

The last three fields live in `Invoice.metadata` (JSONField), not database columns. The advisory lock only covers `(billing_account, period_start, period_end)`.

Two options:
- (a) Promote `selection_scope` to a real DB column and store a deterministic hash of selection params as a unique-together constraint.
- (b) Keep all selection params in metadata; the advisory lock covers `(billing_account, period_start, period_end)` only; uniqueness for selection params is enforced inside the locked transaction via a queryset check.

**Decision:** Which approach? If (a), which fields become DB columns?

Decision is this following block that it is going to modify many documents and code, so pay attention to update all the documentation. In addition you can request more clarifications if needed:

```
Choose option (a).

Decision:

Promote the invoice selection identity into explicit database fields and enforce uniqueness with a deterministic selection fingerprint.

Recommended new `Invoice` columns:

- `selection_scope`
- `selection_fingerprint`

Keep the full selection details in `Invoice.metadata`, including:

- `selected_resource_types`
- `explicit_resources`

Reasoning:

- duplicate-prevention is a core billing invariant and should not rely only on JSONField comparisons
- `selection_scope` is part of the logical invoice identity and should be queryable/indexable as a real column
- a deterministic `selection_fingerprint` allows uniqueness enforcement for variable selection payloads without forcing complex relational modeling in v1
- metadata still remains the full audit snapshot, but the identity-relevant portion is promoted into schema

Recommended behavior:

- keep the advisory lock on `(billing_account, period_start, period_end)`
- inside the locked transaction, compute a canonical selection payload and derive `selection_fingerprint`
- enforce that there is at most one matching draft invoice for the same:
  - `billing_account`
  - `period_start`
  - `period_end`
  - `selection_scope`
  - `selection_fingerprint`
- if a matching finalized invoice exists, generation must fail
- if a matching draft exists:
  - without `force=true`, fail
  - with `force=true`, replace the draft atomically

Canonicalization rules:

- `resource_types` must be sorted before hashing
- `explicit_resources` must be normalized to `(resource_type, resource_id)` pairs and sorted deterministically before hashing

This keeps the invoice identity explicit, the uniqueness rule enforceable, and the metadata payload flexible.
```

---

### B-1. Mid-period activation: how are non-billable days handled?

A resource with `active_from = 2026-01-15` billed over `2026-01-01` to `2026-01-31` should only accrue cost for days 15–31.

Two options:
- (a) Skip non-billable days entirely — no `InvoiceDailyCost` row is created for days 1–14.
- (b) Create `InvoiceDailyCost` rows for days 1–14 with `daily_cost = 0` for a complete audit trail.

**Decision:** Which option? Same question applies to `active_to` when a resource deactivates mid-period.

Decision is the following block:

```
Choose option (a).

Decision:

Non-billable days are skipped entirely. No `InvoiceDailyCost` row is created for days outside the resource's billable window.

Reasoning:

- `InvoiceDailyCost` should represent billable days that were actually evaluated by the billing engine
- days before `active_from` or after `active_to` are not zero-cost billable days; they are simply out of scope
- skipping them keeps the model cleaner and avoids unnecessary row growth
- auditability can still be preserved through invoice-line or invoice-level metadata describing the active billing window and billed day count

This rule applies symmetrically to both:
- days before `active_from`
- days after `active_to`
```

---

### B-2. Non-billable days: zero-cost rows or no rows?

Closely related to B-1. If a resource is not billable on a given day for any reason (before `active_from`, after `active_to`, price missing, etc.), does the system:
- (a) Produce no `InvoiceDailyCost` row for that day.
- (b) Produce a zero-cost row with a reason code in metadata.

**Decision:** Choose one. This affects test assertions on expected row counts.

Decision answered in B-1

---

## HIGH

### C-2. `make_invoice`: pre-condition or per-day billability check?

`001-billing-engine.prp.md` treats `make_invoice = True` on the billing account as a pre-flight validation — if False, invoice generation fails before evaluating any resources.

`BILLING.md` embeds `make_invoice` in the per-day billability condition alongside `active_from`, `active_to`, etc.

**Decision:** Is `make_invoice` a pre-condition (fail fast, before any resource evaluation) or a per-day condition (evaluated per resource per day)? The PRP position is preferred — please confirm or correct.

Accept decision and update documentation to be consistent:

```
Confirm the PRP position.

Decision:

`make_invoice` is a pre-condition on `BillingAccount`, not a per-day billability condition.

Rules:

- if `BillingAccount.make_invoice = false`, invoice generation must fail fast before resource selection and before any per-day billing evaluation
- `make_invoice` must not be included in the per-day billability rule

Reasoning:

- `make_invoice` is an account-level control flag, not a resource/day attribute
- it applies uniformly to the entire invoice request
- treating it as a per-day condition would add unnecessary repetition and blur the distinction between account eligibility and resource billability

Documentation fix:

- keep `make_invoice` in the invoice-generation pre-flight validation section
- remove it from the per-day billability condition in `BILLING.md`
```

---

### C-3. Test file layout: flat `tests/` or per-app `apps/<app>/tests/`?

`TESTING.md` specifies: `tests/services/`, `tests/api/` at the project root.

`000-system-overview.prp.md` and `DEVELOPER_TOOLING.md` show: `apps/<app>/tests/` (per-app).

**Decision:** Which layout should be canonical? (Recommendation: `apps/<app>/tests/` to match Django conventions and keep tests co-located with their app.)

Decision: Accept recomendation and update doc

---

### A-2. VirtualMachine autofill: can a daily usage snapshot ever be partial?

When autofill is needed for a missing day, the billing engine should carry forward the "last known complete billing state."

For VirtualMachine, a `VirtualMachineDailyUsage` row has three required fields: `cpu_count`, `ram_mb`, `disks_total_gb`.

**Decision:** Are all three fields required (non-nullable) on `VirtualMachineDailyUsage`? If yes, a partial snapshot is structurally impossible and autofill always carries forward a complete state — this should be stated explicitly in the VM PRP.

Decision is the following block:

```
Yes.

Decision:

All three billing fields on `VirtualMachineDailyUsage` are required and non-nullable in v1:

- `cpu_count`
- `ram_mb`
- `disks_total_gb`

Reasoning:

- a VM daily usage row must represent a complete billing state for that day
- VM billing in v1 depends on all three dimensions
- partial snapshots would make normalization and billing ambiguous
- autofill is defined as carrying forward the last known complete billing state, which is only safe if persisted VM daily rows are always complete

Documentation update:

The VirtualMachine PRP should state explicitly that partial daily usage snapshots are not allowed in v1 and that autofill always carries forward a complete VM billing state.
```

---

### I-3. `resource_snapshot` in `InvoiceDailyCost.metadata`: required or optional?

`001-billing-engine.prp.md` requires a `resource_snapshot` key inside `InvoiceDailyCost.metadata` capturing the resource state at billing time (for auditability). `BILLING.md` does not mention this at all.

**Decision:** Confirm `resource_snapshot` is a mandatory audit field on every `InvoiceDailyCost` row. If yes, `BILLING.md` needs to be updated to include it.

The decision is the following block:

```
Reject the proposal.

Decision:

`resource_snapshot` is required in `InvoiceLine.metadata`, but it is optional in `InvoiceDailyCost.metadata`.

Reasoning:

- `InvoiceLine` is the correct level to store the frozen identifying snapshot of the billed resource
- this provides auditability without duplicating the same data across many daily rows
- `InvoiceDailyCost` should focus on daily billing facts such as normalized usage, resolved prices, autofill status, and daily cost
- requiring `resource_snapshot` on every daily row would significantly increase storage with little additional audit value

Documentation update:

`001-billing-engine.prp.md` should clarify that the mandatory resource snapshot lives in `InvoiceLine.metadata`, while `InvoiceDailyCost.metadata` may include it optionally.
```

---

## MEDIUM

### A-3. Multi-dimension aggregation: where is the formula documented?

For VirtualMachine, each billing dimension produces its own `InvoiceDailyCost` row. `InvoiceLine.total_cost` should equal the sum of all `InvoiceDailyCost` rows for that resource across all dimensions and all days.

`BILLING.md` currently only covers single-dimension aggregation. It does not address the per-dimension row structure.

**Decision:** Should `BILLING.md` be updated to explicitly define multi-dimension aggregation, or is `002-resource-models.prp.md` the authoritative source for this?

The decision is the following block, update all the required information in the documentaion. You can also request more clarifications if needed:

```
Update `BILLING.md` explicitly.

Decision:

`BILLING.md` should be the authoritative source for multi-dimension aggregation rules.

`002-resource-models.prp.md` should continue to define the storage model, but the billing formula and rollup behavior belong in `BILLING.md`.

Reasoning:

- multi-dimension aggregation is billing-engine behavior, not only model structure
- the core rule for how per-dimension costs roll up into daily totals, invoice-line totals, and invoice totals should be centralized in the billing document
- this avoids leaving a critical billing rule implicit or scattered across model PRPs

Important clarification:

The current PRPs must also be made consistent on whether:
- each dimension produces its own `InvoiceDailyCost` row, or
- there is one `InvoiceDailyCost` row per resource per day with per-dimension costs stored in metadata

That design must be decided once and then reflected consistently in both `BILLING.md` and `002-resource-models.prp.md`.
```

---

### A-4. `force=true` + `autofill_missing_days=true` + no prior snapshot

`001-billing-engine.prp.md` states: if no prior snapshot exists, bill at zero, report in `missing_data_summary`, mark invoice `incomplete=true`.

`BILLING.md` says: "resource still fails unless force-policy explicitly allows partial continuation" — vague, does not commit to zero-billing.

**Decision:** Confirm the PRP behavior is correct: zero cost + `incomplete=true` + entry in `missing_data_summary`. Should `BILLING.md` be updated to match this explicitly?

The decision is the flollowing block:

```
Confirm the PRP behavior.

Decision:

Yes — when `autofill_missing_days = true` but no prior valid snapshot exists, and `force = true`, the billing engine must continue with zero cost for that resource-day, record the condition in `missing_data_summary`, and mark the invoice `incomplete = true`.

Rules:

- without `force = true`, invoice generation fails
- with `force = true`, the affected resource-day is billed at zero
- the invoice must record the missing-data condition explicitly
- the invoice must be marked incomplete

Reasoning:

- autofill cannot succeed if no prior valid snapshot exists
- when forced continuation is allowed, the fallback behavior must be deterministic and explicit
- zero billing + `missing_data_summary` + `incomplete = true` provides a clear and auditable degraded-path result

Documentation update:

`BILLING.md` should be updated to state this behavior explicitly, so it matches `001-billing-engine.prp.md` and removes ambiguity around “partial continuation.”
```

---

### M-5. Soft-deleted resources during historical billing

Soft-deleted resources are excluded from default querysets. But if a resource was active during a billing period and was later soft-deleted, it must still be included in that invoice.

**Decision:** Should the billing engine use an unfiltered queryset (bypassing soft-delete) or a dedicated billing manager (e.g., `Resource.billing_objects.all()`) that includes soft-deleted records? The choice affects how managers are structured.

Decision is the following block and this needs to be documented in addition in the shared resource model section, so both StorageHotel and VirtualMachine inherit the same manager behavior:
```
Choose a dedicated billing manager.

Decision:

The billing engine should use a dedicated manager such as `billing_objects` that includes soft-deleted resources needed for historical billing.

Reasoning:

- soft-deleted resources must still be available for invoice generation when they were billable during the requested billing period
- the default manager should continue to exclude soft-deleted resources for normal application behavior
- a dedicated billing manager is clearer and safer than ad hoc bypassing of the default soft-delete filter

Recommended structure:

- default manager: excludes soft-deleted resources
- `billing_objects` manager: includes soft-deleted resources for billing and audit workflows

Clarification:

Including a resource in the billing queryset does not make it billable by itself. Per-day billability must still be resolved from the normal billing rules, including the resource billing window.
```

---

### B-3. Price date-range overlap: service-layer only or DB constraint?

`005-pricing-api.prp.md` says overlap prevention is enforced at the service layer. No advisory lock for price creation is documented, and no PostgreSQL exclusion constraint exists.

Two options:
- (a) Service layer only, wrapped in a `SELECT FOR UPDATE` lock on the price list row.
- (b) Add a PostgreSQL `daterange` exclusion constraint on `(price_list, resource_type, pricing_dimension)`.

**Decision:** Which approach? (Recommendation: at minimum document the locking strategy. A DB exclusion constraint would be stronger.)

The decision is the following block:

```
Choose option (b).

Decision:

Add a PostgreSQL `daterange` exclusion constraint for `ResourcePrice` overlap prevention.

Reasoning:

- overlap prevention is a core billing invariant and should be enforced by the database
- a service-layer check alone is weaker under concurrency and easier to bypass accidentally in future write paths
- a PostgreSQL exclusion constraint gives the strongest guarantee that no two rows for the same (`price_list`, `resource_type`, `pricing_dimension`) can have overlapping effective date ranges

Implementation rule:

- keep service-layer validation for clear API error messages
- use the database exclusion constraint as the authoritative enforcement mechanism

Documentation update:

`005-pricing-api.prp.md` should state that overlap prevention is validated in the service layer and enforced by a PostgreSQL exclusion constraint
```

---

### M-7. `django-doctor` dependency group

`django-doctor` is in the `quality` optional-dependency group, not `dev`. Pre-commit uses it. Running `uv pip install -e ".[dev]"` does not install it.

**Decision:** Should `django-doctor` move to the `dev` group, or should the install docs say `uv pip install -e ".[dev,quality]"`?

Yes, accept decision.

---

## LOW

### C-4. `effective_to` validation: strict `>` or `>=`?

POST validation says `effective_to` must be strictly after `effective_from`.
PATCH validation says `effective_to >= effective_from` (same-day allowed).

**Decision:** Is a single-day price range (`effective_from == effective_to`) valid? If yes, use `>=` for both. If no, use `>` for both.

Decision: Yes, it is valid

---

### I-4. `quota_unit` in StorageHotel InvoiceLine metadata

`002-resource-models.prp.md` requires `quota_unit` in the StorageHotel `InvoiceLine` metadata. `storage-hotel.prp.md`'s own metadata example does not include it.

**Decision:** Confirm `quota_unit` is required and update `storage-hotel.prp.md` to include it in the metadata example.

Accept decision

---

### I-5. Rounding: sum first, then round once?

`001-billing-engine.prp.md` is explicit: sum all full-precision line totals, then round once to 2 decimal places at the invoice level.
`BILLING.md` only says `total_amount` is rounded to 2 decimal places without stating this order.

**Decision:** Confirm the rule is "sum full-precision lines first, round once at the invoice level." Update `BILLING.md` to state this explicitly.

Yes, accept decision

---

### B-5. Currency consistency across Invoice / InvoiceLine / InvoiceDailyCost

All three models have an independent `currency` field (default `"NOK"`). No rule prevents them from disagreeing.

**Decision:** Should there be a constraint (DB check or service-layer validation) that `InvoiceLine.currency` and `InvoiceDailyCost.currency` must match `Invoice.currency`? Or are they intentionally independent (e.g., for future multi-currency support)?

They must match. Accept decision and update documentation to state this explicitly.

---

### API-1. Draft invoice deletion in v1

There is no `DELETE /api/v1/invoices/{id}` endpoint in v1. The only way to remove a draft invoice is to regenerate with `force=true`.

**Decision:** Is this intentional? If yes, document it explicitly as a design decision in `003-invoice-api.prp.md`.

The decision is the following block, and document it

```
Yes — this is intentional.

Decision:

There is no `DELETE /api/v1/invoices/{id}` endpoint in v1.

Draft invoices are removed only through regeneration using `force=true`.

Reasoning:

- draft invoices are temporary artifacts produced by invoice generation
- regeneration with `force=true` is the controlled mechanism for replacing them
- allowing arbitrary deletion would introduce a second lifecycle path that bypasses billing logic
- finalized invoices remain immutable and cannot be deleted

Documentation:

`003-invoice-api.prp.md` should explicitly state that draft invoices cannot be deleted via the API and must be replaced through regeneration with `force=true`.
```

---

### API-3. `PATCH .../effective-to` URL pattern

`PATCH /api/v1/price-lists/{price_list_id}/resource-prices/{id}/effective-to` is a non-standard REST sub-path pattern that does not map naturally to DRF routers.

Alternative: standard `PATCH /api/v1/price-lists/{price_list_id}/resource-prices/{id}/` with restricted writable fields, or a DRF `@action` named `set_effective_to`.

**Decision:** Which pattern should be used? Use a DRF `@action` named `set_effective_to` for clarity and RESTfulness

Decision is the following block:

```
Choose a DRF `@action` named `set_effective_to`.

Decision:

Use:

`PATCH /api/v1/price-lists/{price_list_id}/resource-prices/{id}/set-effective-to/`

Reasoning:

- changing `effective_to` is a business-significant pricing operation, not just a generic field edit
- a DRF `@action` fits naturally with ViewSet routing
- it is clearer and more maintainable than a raw field-style sub-path such as `/effective-to`
- it allows specialized validation for date ordering and overlap prevention

Guideline:

- use standard `PATCH .../{id}/` for ordinary partial updates
- use explicit DRF actions for constrained lifecycle or domain-specific operations such as setting `effective_to`
```
