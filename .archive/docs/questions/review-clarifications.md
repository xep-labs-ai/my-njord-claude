# Documentation Review — Clarification Questions

This file was generated from a full documentation audit.
Each question includes the problem found, the options or proposal, and a blank **Answer** field for you to fill in.

Questions are grouped by priority: **blockers first**, then important-but-not-blockers, then minor fixes.

---

## BLOCKERS (must resolve before implementation)

---

### RQ1 — ResourceModel: abstract vs. concrete Django model

**Status:** ANSWERED

**Problem:**
`ResourceModel` is described as a "base model for billable resources" but it is never stated whether it is a Django abstract model, a concrete model with multi-table inheritance (MTI), or something else.
`InvoiceLine` and `InvoiceDailyCost` use `resource_type + resource_id` fields (not a FK), which strongly implies abstract — but this is never confirmed.
MTI has well-known performance issues and would change how queries work.

**Options:**
- (a) Abstract Django model — no shared table, `resource_type + resource_id` pattern is the correct reference strategy
- (b) Concrete model with MTI — shared table, FK relationships possible but has performance implications
- (c) No base model at all — StorageHotel and VirtualMachine are completely independent models

**Proposal:** Option (a). Abstract model avoids MTI complexity, is consistent with the `resource_type + resource_id` pattern already in the PRPs, and keeps each resource app independent.

**Answer:** option a

---

### RQ2 — Resource lifecycle: per-day status resolution vs. point-in-time

**Status:** ANSWERED

**Problem:**
The billing engine evaluates resources per day. But `status` is a single field on the resource model — not date-tracked. This means:
- If a resource is ACTIVE today but was RETIRED on Jan 15, it gets billed for all days including Jan 1–14 when generating a Jan invoice.
- `BILLING.md` acknowledges this gap ("If the system later supports effective start/end lifecycle dates, billability must be resolved per day") but does not define v1 behavior.

**Options:**
- (a) V1: billability is determined by the resource's **current status at invoice generation time** — point-in-time, no per-day resolution. Document this explicitly.
- (b) V1: add `active_from` / `active_to` fields to `ResourceModel` and resolve billability per day
- (c) V1: billing period start/end on the resource (e.g., `billing_start_date`, `billing_end_date`) as a simpler alternative to full lifecycle tracking

**Proposal:** Option (a) for v1, with a clear note in `BILLING.md` that per-day lifecycle resolution is a known limitation. This avoids model complexity while being explicit about the constraint.

**Answer:** The answer is the following block:
```
Choose option (b), but define it with explicit lifecycle window fields:

- active_from
- active_to (nullable)

Reasoning:

- The billing engine already evaluates resources per day, so billability should also be resolved per day.
- A single current status field is not sufficient for historical billing.
- Point-in-time billing based only on current status would make past invoices inaccurate and harder to audit.
- A simple active window gives the minimum structure needed for deterministic billing without introducing full lifecycle-event modeling.

Definition:

- `active_from` is the first day the resource is billable.
- `active_to` is the last day the resource is billable.
- `active_to = null` means the billing window is open-ended.
- `active_to` is inclusive when present.

Recommended per-day billability rule:

A resource is billable for a given day only if:

- it derives from `ResourceModel`
- `billing_account` is not null
- `active_from <= day`
- (`active_to` is null OR `day <= active_to`)
- it is included in the invoice selection

Status semantics:

- `status` represents the resource's current lifecycle state
- `ACTIVE` means the resource is currently active
- `RETIRED` means the resource is no longer active for future billing
- if `status == RETIRED`, `active_to` should be set to the final billable day

Decision:

Use `active_from` and nullable `active_to` in v1, and resolve billability per day from that window. Do not use a fake far-future default such as 2099-12-31; use null to represent an open-ended billing period.
```

---

### RQ3 — `force=true` without autofill: exact behavior

**Status:** ANSWERED

**Problem:**
The billing engine supports `force=true` (generate invoice even with missing data) and `autofill=true` (carry forward last known value). But what happens when `force=true` AND `autofill=false` and a resource has missing days?

**Options:**
- (a) Skip the resource entirely — invoice is generated but that resource is excluded
- (b) Bill the resource at zero for missing days — invoice includes the line but with zero cost
- (c) Fail for that resource, continue for others — partial invoice with an error log
- (d) Raise an error and abort — same as `force=false`

**Proposal:** Option (a). Skipping is the safest default — it avoids billing zero (which could look like a legitimate zero-cost invoice line) and avoids silent data loss. The skipped resources should be reported in the invoice generation response.

**Answer:** option b

---

### RQ4 — `pricing_dimension` allowed values

**Status:** ANSWERED

**Problem:**
`ResourcePrice.pricing_dimension` appears in the model fields but its allowed values are never defined. The billing engine needs to match a resource's billable units to the correct `ResourcePrice` row using this field.

**Options for StorageHotel:**
- `"storage"` (single dimension)

**Options for VirtualMachine (per Q6/Q7, per-dimension billing confirmed):**
- `"cpu"`, `"ram"`, `"disk"` (three dimensions)
- or different names: `"cpu_count"`, `"ram_gb"`, `"disk_gb"`

**Proposal:**
- StorageHotel: `"storage"` (one dimension)
- VirtualMachine: `"cpu"`, `"ram"`, `"disk"` (three dimensions, short names, consistent with VM PRP field names `cpu_count`, `ram_gb`, `disk_gb`)

**Answer:** The current block

```
Define `pricing_dimension` as a controlled, explicit identifier that matches the normalized billable quantity used by the billing engine.

Recommended values:

StorageHotel
- `quota_tb`

VirtualMachine
- `cpu_count`
- `ram_gb`
- `disk_gb`
```

---

### RQ5 — Explicit resource selection: ID disambiguation

**Status:** ANSWERED

**Problem:**
`BILLING.md` shows that invoice generation can target explicit resource IDs: `resource_ids: [101, 205, 333]`. But IDs 101, 205, 333 could belong to a StorageHotel or a VirtualMachine — there is no way to know which table to look in without a type discriminator.

**Options:**
- (a) Use UUIDs for all resource PKs — globally unique across all resource types, no type discriminator needed
- (b) Require `(resource_type, resource_id)` pairs in the selection input, e.g. `[{"type": "StorageHotel", "id": 101}]`
- (c) Use a single integer PK sequence per app (current), accept that the UI/caller must know the type and pass it separately

**Proposal:** Option (a). UUIDs are the cleanest solution — they eliminate type ambiguity everywhere (invoice references, API calls, audit logs). The cost is slightly less readable IDs.

**Answer:** the following block:

```
Choose option (b) with the following suggestions. 

Explicit resource selection must use `(resource_type, resource_id)` pairs rather than a plain list of IDs.

Reasoning:

- Resource selection is polymorphic, so the input must identify both the resource model and the resource ID.
- UUIDs would reduce accidental ID collisions, but they would not remove the need to know the resource type for billing, validation, and price resolution.
- This approach is already consistent with the existing `resource_type + resource_id` pattern used by `InvoiceLine` and `InvoiceDailyCost`.
- It keeps the selection contract explicit, deterministic, and easy to validate without requiring a project-wide PK strategy change.

Recommended input shape:

`explicit_resources = [{"resource_type": "storage_hotel", "resource_id": 101}, {"resource_type": "virtual_machine", "resource_id": 205}]`

Decision:

Use typed resource references for explicit selection in v1.
```

---

### RQ6 — Invoice number sequence scope (Q8 carry-forward)

**Status:** ANSWERED

**Problem:**
Invoice number format is `INV-YYYY-mm-NNNN`. Is the `NNNN` counter:
- (a) Global per month — all billing accounts share one sequence, e.g. account A gets INV-2026-02-0001, account B gets INV-2026-02-0002
- (b) Per billing account per month — each account has its own counter, so two accounts can both have INV-2026-02-0001

This affects database constraints (unique index scope) and sequence generation implementation.

**Proposal:** Option (a). A global monthly counter is simpler to implement (one sequence or one DB row), easier to audit (no duplicate numbers across accounts), and more typical for invoicing systems.

**Answer:** Option a but instead of  `INV-YYYY-mm-NNNN` do `INV-YYYY-mm-NNNNN` To allow more than 9999 invoices per month if needed.

---

### RQ7 — Rounding sequence: line-level vs. invoice-level

**Status:** ANSWERED

**Problem:**
`BILLING.md` says "round customer-visible totals to 2 decimals NOK" but does not define the sequence. Two approaches exist:

- (a) Round each `InvoiceLine.total_cost` independently, then sum rounded line totals for the invoice total → can cause penny discrepancies between sum-of-lines and invoice total
- (b) Sum all line totals at full `Decimal` precision, round only the invoice total once → sum-of-lines may not equal the displayed invoice total

**Proposal:** Option (a). Round at line level. This is the most common invoicing convention, makes each line independently auditable, and the penny discrepancy risk is acceptable with proper documentation. The `InvoiceDailyCost` rows always remain at full precision.

**Answer:** b is the answer

---

### RQ8 — Storage unit conversion: KB/KIB to billing unit

**Status:** ANSWERED

**Problem:**
StorageHotel `quota_unit` can be `KB` or `KIB`. The billing unit is `TB`. The exact conversion formulas are never documented, and it is unclear whether the billing unit `TB` means decimal terabytes (10^12 bytes) or binary tebibytes (2^40 bytes).

**Options:**
- (a) Billing unit is decimal TB (10^12 bytes). KB → TB: divide by 10^9. KIB → TB: multiply by 1024, divide by 10^12 (i.e., divide by ~976,562,500).
- (b) Billing unit is binary TiB (2^40 bytes). KB → TiB: multiply by 1000, divide by 2^40. KIB → TiB: divide by 2^30.
- (c) Billing unit is TB but inputs are always normalized to the same unit before storage — `quota_gb` field instead of raw quota + unit

**Proposal:** Option (a). Decimal TB is the industry standard for storage billing (consistent with how vendors like AWS price storage). Document the exact constant: `KB_TO_TB = Decimal("1e-9")`, `KIB_TO_TB = Decimal("1024") / Decimal("1e12")`.

**Answer:** Option a

---

### RQ9 — LDAP authentication: in scope for v1 or not?

**Status:** ANSWERED

**Problem:**
`000-system-overview.prp.md` lists "authentication / authorization" as a **non-goal** for v1.
`CLAUDE.md` lists **LDAP authentication** as part of the stack.
These contradict each other.

**Options:**
- (a) LDAP is infrastructure-present but not enforced in v1 — the package is installed, settings are configured, but API endpoints are open or use session auth only
- (b) LDAP is a v1 deliverable — remove it from the non-goals list in the overview PRP
- (c) LDAP is out of scope entirely — remove it from `CLAUDE.md` stack list

**Proposal:** Whichever is correct, the docs must agree. If the intent is (a), say so explicitly in both places.

**Answer:** c LDAP is out of the scope for now, remove it from the stack list in `CLAUDE.md`.

---

### RQ10 — STRUCTURE.md is nearly empty

**Status:** ANSWERED

**Problem:**
`.claude/docs/STRUCTURE.md` is referenced in multiple routing tables and skill files as the authority on file placement, but it contains only a routing header and no actual rules.
This means Claude has no documented guidance on where to put files.

**Options:**
- (a) Populate it now, derived from the system overview PRP app structure and conventions implied by other docs
- (b) Remove it from all routing tables until it is written
- (c) Leave it empty and rely on CLAUDE.md's project structure description

**Proposal:** Option (a). Populate with the implied structure: `apps/billing/`, `apps/ingest/`, per-app layout for `models.py`, `services/`, `selectors/`, `serializers.py`, `views.py`, `tests/`.

**Answer:** I have just already removed. It is all inside ARCHITECTURE.md. Remove it from documentation if present

---

## IMPORTANT (not blockers, but should fix before major implementation)

---

### RQ11 — `InvoiceLine` fields: `total_billed_amount` vs `total_cost`

**Status:** ANSWERED

**Problem:**
`InvoiceLine` has two fields that appear synonymous: `total_billed_amount` and `total_cost`. If they mean the same thing, one should be removed. If they are different, the distinction must be documented.

**Proposal:**
- Rename `total_billed_amount` → `total_billed_quantity` (stores aggregate resource usage, not money)
- Keep `total_cost` as the money field (Decimal, NOK)

**Answer:** the following block:

```
Partially accept the proposal.

`total_billed_amount` should be removed, because it is ambiguous and overlaps with `total_cost`.

However, it should not be replaced with a single scalar `total_billed_quantity` field. That would still assume one aggregate quantity per resource, which does not fit multi-dimension billing for resources like VirtualMachine.

Decision:

- keep `total_cost` as the monetary field
- remove `total_billed_amount`
- store aggregate billed quantities in `InvoiceLine.metadata`, for example under `total_quantity_by_dimension`

This keeps `InvoiceLine` valid for both single-dimension and multi-dimension resources.

maybe a valid example for VirtualMachine line metadata should be something like this:
```
metadata.total_quantity_by_dimension = {
  "cpu_count_days": "248",
  "ram_gb_days": "992",
  "disk_gb_days": "15500"
}
```
```

---

### RQ12 — `InvoiceLine.unit_price_snapshot` purpose and type

**Status:** ANSWERED

**Problem:**
`unit_price_snapshot` is on `InvoiceLine` but its type and meaning are undefined. Since prices can differ day-to-day within the same invoice period, a single snapshot at the line level is ambiguous. Per-day price data is already captured in `InvoiceDailyCost`.

**Options:**
- (a) Remove the field — daily-level data in `InvoiceDailyCost` is sufficient
- (b) Keep it as a representative/display price — the effective price on the last day of the period, or the most common price, clearly documented as non-authoritative
- (c) Change to a JSON field storing a price history summary

**Proposal:** Option (a). Remove it. `InvoiceDailyCost` is the source of truth; a summary field at the line level adds confusion without value.

**Answer:** option a

---

### RQ13 — Duplicate invoice constraint

**Status:** ANSWERED

**Problem:**
No documented uniqueness constraint prevents generating two invoices for the same billing account and billing period. It is unclear whether multiple draft invoices for the same account/period are intentional.

**Proposal:**
Add a unique constraint on `Invoice`: `(billing_account, period_start, period_end)`. Allow override only via explicit `force=true` on re-generation, which would replace the existing draft.

**Answer:** the following block:

```
Accept the intent, but refine the constraint.

A duplicate-prevention rule is required, but invoice uniqueness cannot be based only on `(billing_account, period_start, period_end)` because invoice selection scope is part of the logical invoice identity.

Decision:

- There must be at most one draft invoice for the same billing account, billing period, and billing selection.
- Billing selection includes:
  - `selection_scope`
  - selected resource types
  - selected explicit resources
- If a matching draft invoice already exists:
  - without `force=true`, invoice generation fails
  - with `force=true`, the existing draft is replaced atomically
- If a matching finalized invoice already exists, invoice generation must fail. Finalized invoices are immutable and must not be replaced.

Reasoning:

- This prevents accidental duplicate invoices
- It keeps invoice generation deterministic
- It respects the fact that different billing selections may produce different valid invoices for the same account and period
- It preserves the immutability of finalized invoices

Example, this is allowed:
```
Invoice A:
billing_account = X
period = Jan 2026
selection_scope = resource_types
selected_resource_types = ["storage_hotel"]

Invoice B:
billing_account = X
period = Jan 2026
selection_scope = resource_types
selected_resource_types = ["virtual_machine"]
```
```

---

### RQ14 — `deleted_at` soft-delete semantics

**Status:** ANSWERED

**Problem:**
Both `StorageHotel` and `VirtualMachine` have a `deleted_at` field implying soft-delete, but nothing defines:
- What sets `deleted_at` (API call? admin action?)
- How it interacts with `status` (can a deleted resource be ACTIVE?)
- Whether a soft-deleted resource is billable

**Proposal:**
- Setting `deleted_at` also sets `status = RETIRED`
- A resource with `deleted_at IS NOT NULL` is never billable
- Default queryset excludes soft-deleted resources (custom manager)

**Answer:** this block:

```
Partially accept the proposal, but clarify the semantics.

Decision:

- `deleted_at` represents soft deletion at the application level
- if `deleted_at` is set, `status` must be `RETIRED`
- soft-deleted resources must be excluded from default querysets
- soft-deleted resources must not be billable for days after their billing end
- billability for historical days must still be resolved from `active_from` / `active_to`, not from `deleted_at` alone

Reasoning:

- soft deletion and billing lifecycle are related, but not identical
- a resource may be soft-deleted after its final billable day, and historical invoices must still remain correct
- using `deleted_at is not null` as the sole billability rule would make past billing inaccurate
- default querysets should hide soft-deleted resources from normal application use, while audit and billing workflows must still be able to access them

Recommended invariants:

- if `deleted_at` is not null, `status` must be `RETIRED`
- if `deleted_at` is not null, `active_to` must be set
- `active_to` should be on or before the calendar date of `deleted_at`
```

---

### RQ15 — Invoice API endpoints: where are they specified?

**Status:** ANSWERED

**Problem:**
No PRP or doc defines the invoice lifecycle API: generate, finalize, retrieve. The billing engine PRP defines the algorithm but not the HTTP interface.

**Proposal:**
Add an invoice API section to either `001-billing-engine.prp.md` or a new `003-invoice-api.prp.md` covering:
- `POST /api/v1/invoices/generate`
- `POST /api/v1/invoices/{id}/finalize`
- `GET  /api/v1/invoices/`
- `GET  /api/v1/invoices/{id}/`

**Answer:** The following block:

```
Create a new dedicated PRP:

`docs/PRP/003-invoice-api.prp.md`
Decision
Invoice lifecycle endpoints should be specified in a dedicated PRP, not embedded into the billing-engine PRP.

Recommended file:

- `docs/PRP/003-invoice-api.prp.md`
Reasoning
- `001-billing-engine.prp.md` should remain focused on billing rules, orchestration, and snapshot behavior.
- The invoice API is a separate contract: request shape, validation rules, endpoint semantics, lifecycle transitions, and response structure.
- A dedicated PRP keeps the architecture clearer and makes future API changes easier to review.
- This also matches the existing PRP structure, where concerns are separated into focused documents.
What 003-invoice-api.prp.md should define

At minimum:

- endpoint list
- request and response shapes
- selection input contract
- validation failures
- draft vs finalized behavior
- duplicate-prevention behavior
- `force=true` regeneration rules
- invoice retrieval shape
- line and daily-cost exposure rules
- status transition rules
Recommended initial endpoints
POST   /api/v1/invoices/generate
GET    /api/v1/invoices/
GET    /api/v1/invoices/{id}/
POST   /api/v1/invoices/{id}/finalize

Optional later:

GET    /api/v1/invoices/{id}/lines
GET    /api/v1/invoices/{id}/daily-costs
POST   /api/v1/invoices/{id}/recalculate
DELETE /api/v1/invoices/{id}

But for v1, the first four are enough.

Suggested PRP note
`003-invoice-api.prp.md` defines the HTTP contract for invoice generation, retrieval, and finalization.

`001-billing-engine.prp.md` remains the source of truth for billing calculation rules and snapshot persistence behavior.
Best answer to send
Accept the proposal, but implement it as a dedicated PRP.

Decision:

Create a new PRP:

`docs/PRP/003-invoice-api.prp.md`

This document should define the invoice lifecycle HTTP contract, including:

- `POST /api/v1/invoices/generate`
- `POST /api/v1/invoices/{id}/finalize`
- `GET  /api/v1/invoices/`
- `GET  /api/v1/invoices/{id}/`

Reasoning:

- the billing-engine PRP should remain focused on billing rules and invoice-generation behavior
- the invoice API is a separate contract and deserves its own specification
- a dedicated PRP makes endpoint semantics, validation, lifecycle transitions, and response models easier to review and evolve

`001-billing-engine.prp.md` should remain the source of truth for billing logic, while `003-invoice-api.prp.md` should become the source of truth for the invoice HTTP interface.
```

---

## MINOR FIXES (low effort, should be done alongside other work)

---

### RQ16 — Q1 in clarifications.md: marked HELPME but Q6/Q7 already resolve it

**Status:** ANSWERED

**Problem:**
Q1 asks about VM billing strategy and is marked HELPME. But Q6 answers "one row per dimension per day" and Q7 answers "discounts per dimension independently." Q1 should be marked ANSWERED.

**Proposal:** Update Q1 status to ANSWERED with summary: "VM v1 billing is per-dimension (cpu, ram, disk), with 3 InvoiceDailyCost rows per VM per day. Discounts apply per dimension independently."

**Answer:** accept proposal

---

### RQ17 — Q3 in clarifications.md: marked HELPME but has an answer

**Status:** ANSWERED

**Problem:**
Q3 has status "HELPME" but the answer `(c) Formatted string with pattern INV-YYYY-mm-NNNN` is already written in the document.

**Proposal:** Change Q3 status to ANSWERED and modify it to INV-YYYY-mm-NNNNN to allow more than 9999 invoices per month if needed.

**Answer:**

---

### RQ18 — Q7 in clarifications.md: trailing `|` typo

**Status:** ANSWERED

**Problem:**
Line reads `**Status:** ANSWERED|` — stray pipe character.

**Proposal:** Remove the `|`.

**Answer:** yes pls

---

### RQ19 — VM and StorageHotel PRP API paths missing `/api/v1/` prefix

**Status:** ANSWERED

**Problem:**
Both resource PRPs list endpoints without the required `/api/v1/` prefix, contradicting the API rules in `CLAUDE.md`.

**Proposal:** Prefix all endpoint listings with `/api/v1/` in both resource PRPs.

**Answer:** Accept proposal

---

### RQ20 — mypy described as "optional" in one doc, mandatory in another

**Status:** ANSWERED

**Problem:**
`DEVELOPER_TOOLING_AND_ENVIRONMENT.md` says "Type checking is optional but available." `CODING_RULES.md` says all new code must be compatible with mypy and type annotations are required. mypy is also in pre-commit hooks.

**Proposal:** Update `DEVELOPER_TOOLING_AND_ENVIRONMENT.md` to say type checking is mandatory

**Answer:** Accept proposal

---

### RQ21 — `django-doctor` not in pre-commit

**Status:** ANSWERED

**Problem:**
`CODING_RULES.md` lists `django-doctor` as a quality tool. `pyproject.toml` includes it under optional dependencies. But it is not in the pre-commit config and `DEVELOPER_TOOLING_AND_ENVIRONMENT.md` does not mention it.

**Options:**
- (a) Add it to pre-commit
- (b) Document it as a manual-only tool
- (c) Remove it entirely

**Answer:** add to pre-commit

---

### RQ22 — Testing skill references `apps/invoices/` (wrong app name)

**Status:** ANSWERED

**Problem:**
`.claude/skills/django-testing-pattern/SKILL.md` has an example path `apps/invoices/tests/test_api_invoice_generation.py`. The project has `apps/billing/`, not `apps/invoices/`.

**Proposal:** Change to `apps/billing/tests/test_api_invoice_generation.py`.

**Answer:** Accept proposal

---

### RQ23 — Testing skill SKILL.md wrapped in markdown code fence

**Status:** ANSWERED

**Problem:**
The entire `django-testing-pattern/SKILL.md` is wrapped in a ` ```md ` / ` ``` ` code fence. The API endpoint skill does not have this. This may cause the skill to be parsed as a code block rather than actionable content.

**Proposal:** Remove the outer code fence wrapping.

**Answer:** yes pls

---
