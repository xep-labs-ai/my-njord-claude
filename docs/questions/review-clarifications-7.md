# Review Clarifications 7

Architecture review findings requiring your input before implementation.
Edit each `**Decision:**` line with your answer.

---

## CRITICAL

### C-1. Daily cost formula: universal or per-resource-type?

`001-billing-engine.prp.md` shows: `daily_cost = usage × price_per_year / days_in_year(day)`

`BILLING.md` says there is no single universal formula — each resource type defines its own.

For VirtualMachine with three pricing dimensions (cpu, ram, disk), the formula would need to apply per dimension and then sum.

**Decision:** Is the PRP formula an illustrative example (not universal), and the canonical rule is that each resource type computes its own daily cost — potentially summing per-dimension costs? Or should we enforce a single formula for all resource types?

---

### A-1. Duplicate invoice uniqueness on JSON fields

Uniqueness is defined over `(billing_account, period_start, period_end, selection_scope, selected_resource_types, explicit_resources)`.

The last three fields live in `Invoice.metadata` (JSONField), not database columns. The advisory lock only covers `(billing_account, period_start, period_end)`.

Two options:
- (a) Promote `selection_scope` to a real DB column and store a deterministic hash of selection params as a unique-together constraint.
- (b) Keep all selection params in metadata; the advisory lock covers `(billing_account, period_start, period_end)` only; uniqueness for selection params is enforced inside the locked transaction via a queryset check.

**Decision:** Which approach? If (a), which fields become DB columns?

---

### B-1. Mid-period activation: how are non-billable days handled?

A resource with `active_from = 2026-01-15` billed over `2026-01-01` to `2026-01-31` should only accrue cost for days 15–31.

Two options:
- (a) Skip non-billable days entirely — no `InvoiceDailyCost` row is created for days 1–14.
- (b) Create `InvoiceDailyCost` rows for days 1–14 with `daily_cost = 0` for a complete audit trail.

**Decision:** Which option? Same question applies to `active_to` when a resource deactivates mid-period.

---

### B-2. Non-billable days: zero-cost rows or no rows?

Closely related to B-1. If a resource is not billable on a given day for any reason (before `active_from`, after `active_to`, price missing, etc.), does the system:
- (a) Produce no `InvoiceDailyCost` row for that day.
- (b) Produce a zero-cost row with a reason code in metadata.

**Decision:** Choose one. This affects test assertions on expected row counts.

---

## HIGH

### C-2. `make_invoice`: pre-condition or per-day billability check?

`001-billing-engine.prp.md` treats `make_invoice = True` on the billing account as a pre-flight validation — if False, invoice generation fails before evaluating any resources.

`BILLING.md` embeds `make_invoice` in the per-day billability condition alongside `active_from`, `active_to`, etc.

**Decision:** Is `make_invoice` a pre-condition (fail fast, before any resource evaluation) or a per-day condition (evaluated per resource per day)? The PRP position is preferred — please confirm or correct.

---

### C-3. Test file layout: flat `tests/` or per-app `apps/<app>/tests/`?

`TESTING.md` specifies: `tests/services/`, `tests/api/` at the project root.

`000-system-overview.prp.md` and `DEVELOPER_TOOLING.md` show: `apps/<app>/tests/` (per-app).

**Decision:** Which layout should be canonical? (Recommendation: `apps/<app>/tests/` to match Django conventions and keep tests co-located with their app.)

---

### A-2. VirtualMachine autofill: can a daily usage snapshot ever be partial?

When autofill is needed for a missing day, the billing engine should carry forward the "last known complete billing state."

For VirtualMachine, a `VirtualMachineDailyUsage` row has three required fields: `cpu_count`, `ram_mb`, `disks_total_gb`.

**Decision:** Are all three fields required (non-nullable) on `VirtualMachineDailyUsage`? If yes, a partial snapshot is structurally impossible and autofill always carries forward a complete state — this should be stated explicitly in the VM PRP.

---

### I-3. `resource_snapshot` in `InvoiceDailyCost.metadata`: required or optional?

`001-billing-engine.prp.md` requires a `resource_snapshot` key inside `InvoiceDailyCost.metadata` capturing the resource state at billing time (for auditability). `BILLING.md` does not mention this at all.

**Decision:** Confirm `resource_snapshot` is a mandatory audit field on every `InvoiceDailyCost` row. If yes, `BILLING.md` needs to be updated to include it.

---

## MEDIUM

### A-3. Multi-dimension aggregation: where is the formula documented?

For VirtualMachine, each billing dimension produces its own `InvoiceDailyCost` row. `InvoiceLine.total_cost` should equal the sum of all `InvoiceDailyCost` rows for that resource across all dimensions and all days.

`BILLING.md` currently only covers single-dimension aggregation. It does not address the per-dimension row structure.

**Decision:** Should `BILLING.md` be updated to explicitly define multi-dimension aggregation, or is `002-resource-models.prp.md` the authoritative source for this?

---

### A-4. `force=true` + `autofill_missing_days=true` + no prior snapshot

`001-billing-engine.prp.md` states: if no prior snapshot exists, bill at zero, report in `missing_data_summary`, mark invoice `incomplete=true`.

`BILLING.md` says: "resource still fails unless force-policy explicitly allows partial continuation" — vague, does not commit to zero-billing.

**Decision:** Confirm the PRP behavior is correct: zero cost + `incomplete=true` + entry in `missing_data_summary`. Should `BILLING.md` be updated to match this explicitly?

---

### M-5. Soft-deleted resources during historical billing

Soft-deleted resources are excluded from default querysets. But if a resource was active during a billing period and was later soft-deleted, it must still be included in that invoice.

**Decision:** Should the billing engine use an unfiltered queryset (bypassing soft-delete) or a dedicated billing manager (e.g., `Resource.billing_objects.all()`) that includes soft-deleted records? The choice affects how managers are structured.

---

### B-3. Price date-range overlap: service-layer only or DB constraint?

`005-pricing-api.prp.md` says overlap prevention is enforced at the service layer. No advisory lock for price creation is documented, and no PostgreSQL exclusion constraint exists.

Two options:
- (a) Service layer only, wrapped in a `SELECT FOR UPDATE` lock on the price list row.
- (b) Add a PostgreSQL `daterange` exclusion constraint on `(price_list, resource_type, pricing_dimension)`.

**Decision:** Which approach? (Recommendation: at minimum document the locking strategy. A DB exclusion constraint would be stronger.)

---

### M-7. `django-doctor` dependency group

`django-doctor` is in the `quality` optional-dependency group, not `dev`. Pre-commit uses it. Running `uv pip install -e ".[dev]"` does not install it.

**Decision:** Should `django-doctor` move to the `dev` group, or should the install docs say `uv pip install -e ".[dev,quality]"`?

---

## LOW

### C-4. `effective_to` validation: strict `>` or `>=`?

POST validation says `effective_to` must be strictly after `effective_from`.
PATCH validation says `effective_to >= effective_from` (same-day allowed).

**Decision:** Is a single-day price range (`effective_from == effective_to`) valid? If yes, use `>=` for both. If no, use `>` for both.

---

### I-4. `quota_unit` in StorageHotel InvoiceLine metadata

`002-resource-models.prp.md` requires `quota_unit` in the StorageHotel `InvoiceLine` metadata. `storage-hotel.prp.md`'s own metadata example does not include it.

**Decision:** Confirm `quota_unit` is required and update `storage-hotel.prp.md` to include it in the metadata example.

---

### I-5. Rounding: sum first, then round once?

`001-billing-engine.prp.md` is explicit: sum all full-precision line totals, then round once to 2 decimal places at the invoice level.
`BILLING.md` only says `total_amount` is rounded to 2 decimal places without stating this order.

**Decision:** Confirm the rule is "sum full-precision lines first, round once at the invoice level." Update `BILLING.md` to state this explicitly.

---

### B-5. Currency consistency across Invoice / InvoiceLine / InvoiceDailyCost

All three models have an independent `currency` field (default `"NOK"`). No rule prevents them from disagreeing.

**Decision:** Should there be a constraint (DB check or service-layer validation) that `InvoiceLine.currency` and `InvoiceDailyCost.currency` must match `Invoice.currency`? Or are they intentionally independent (e.g., for future multi-currency support)?

---

### API-1. Draft invoice deletion in v1

There is no `DELETE /api/v1/invoices/{id}` endpoint in v1. The only way to remove a draft invoice is to regenerate with `force=true`.

**Decision:** Is this intentional? If yes, document it explicitly as a design decision in `003-invoice-api.prp.md`.

---

### API-3. `PATCH .../effective-to` URL pattern

`PATCH /api/v1/price-lists/{price_list_id}/resource-prices/{id}/effective-to` is a non-standard REST sub-path pattern that does not map naturally to DRF routers.

Alternative: standard `PATCH /api/v1/price-lists/{price_list_id}/resource-prices/{id}/` with restricted writable fields, or a DRF `@action` named `set_effective_to`.

**Decision:** Which pattern should be used?
