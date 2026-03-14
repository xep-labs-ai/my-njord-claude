# Documentation Review — Clarification Questions

This file was generated from a full documentation audit.
Each question includes the problem found, the options or proposal, and a blank **Answer** field for you to fill in.

Questions are grouped by priority: **blockers first**, then important-but-not-blockers, then minor fixes.

---

## BLOCKERS (must resolve before implementation)

---

### RQ1 — ResourceModel: abstract vs. concrete Django model

**Status:** PENDING

**Problem:**
`ResourceModel` is described as a "base model for billable resources" but it is never stated whether it is a Django abstract model, a concrete model with multi-table inheritance (MTI), or something else.
`InvoiceLine` and `InvoiceDailyCost` use `resource_type + resource_id` fields (not a FK), which strongly implies abstract — but this is never confirmed.
MTI has well-known performance issues and would change how queries work.

**Options:**
- (a) Abstract Django model — no shared table, `resource_type + resource_id` pattern is the correct reference strategy
- (b) Concrete model with MTI — shared table, FK relationships possible but has performance implications
- (c) No base model at all — StorageHotel and VirtualMachine are completely independent models

**Proposal:** Option (a). Abstract model avoids MTI complexity, is consistent with the `resource_type + resource_id` pattern already in the PRPs, and keeps each resource app independent.

**Answer:**

---

### RQ2 — Resource lifecycle: per-day status resolution vs. point-in-time

**Status:** PENDING

**Problem:**
The billing engine evaluates resources per day. But `status` is a single field on the resource model — not date-tracked. This means:
- If a resource is ACTIVE today but was RETIRED on Jan 15, it gets billed for all days including Jan 1–14 when generating a Jan invoice.
- `BILLING.md` acknowledges this gap ("If the system later supports effective start/end lifecycle dates, billability must be resolved per day") but does not define v1 behavior.

**Options:**
- (a) V1: billability is determined by the resource's **current status at invoice generation time** — point-in-time, no per-day resolution. Document this explicitly.
- (b) V1: add `active_from` / `active_to` fields to `ResourceModel` and resolve billability per day
- (c) V1: billing period start/end on the resource (e.g., `billing_start_date`, `billing_end_date`) as a simpler alternative to full lifecycle tracking

**Proposal:** Option (a) for v1, with a clear note in `BILLING.md` that per-day lifecycle resolution is a known limitation. This avoids model complexity while being explicit about the constraint.

**Answer:**

---

### RQ3 — `force=true` without autofill: exact behavior

**Status:** PENDING

**Problem:**
The billing engine supports `force=true` (generate invoice even with missing data) and `autofill=true` (carry forward last known value). But what happens when `force=true` AND `autofill=false` and a resource has missing days?

**Options:**
- (a) Skip the resource entirely — invoice is generated but that resource is excluded
- (b) Bill the resource at zero for missing days — invoice includes the line but with zero cost
- (c) Fail for that resource, continue for others — partial invoice with an error log
- (d) Raise an error and abort — same as `force=false`

**Proposal:** Option (a). Skipping is the safest default — it avoids billing zero (which could look like a legitimate zero-cost invoice line) and avoids silent data loss. The skipped resources should be reported in the invoice generation response.

**Answer:**

---

### RQ4 — `pricing_dimension` allowed values

**Status:** PENDING

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

**Answer:**

---

### RQ5 — Explicit resource selection: ID disambiguation

**Status:** PENDING

**Problem:**
`BILLING.md` shows that invoice generation can target explicit resource IDs: `resource_ids: [101, 205, 333]`. But IDs 101, 205, 333 could belong to a StorageHotel or a VirtualMachine — there is no way to know which table to look in without a type discriminator.

**Options:**
- (a) Use UUIDs for all resource PKs — globally unique across all resource types, no type discriminator needed
- (b) Require `(resource_type, resource_id)` pairs in the selection input, e.g. `[{"type": "StorageHotel", "id": 101}]`
- (c) Use a single integer PK sequence per app (current), accept that the UI/caller must know the type and pass it separately

**Proposal:** Option (a). UUIDs are the cleanest solution — they eliminate type ambiguity everywhere (invoice references, API calls, audit logs). The cost is slightly less readable IDs.

**Answer:**

---

### RQ6 — Invoice number sequence scope (Q8 carry-forward)

**Status:** PENDING

**Problem:**
Invoice number format is `INV-YYYY-mm-NNNN`. Is the `NNNN` counter:
- (a) Global per month — all billing accounts share one sequence, e.g. account A gets INV-2026-02-0001, account B gets INV-2026-02-0002
- (b) Per billing account per month — each account has its own counter, so two accounts can both have INV-2026-02-0001

This affects database constraints (unique index scope) and sequence generation implementation.

**Proposal:** Option (a). A global monthly counter is simpler to implement (one sequence or one DB row), easier to audit (no duplicate numbers across accounts), and more typical for invoicing systems.

**Answer:**

---

### RQ7 — Rounding sequence: line-level vs. invoice-level

**Status:** PENDING

**Problem:**
`BILLING.md` says "round customer-visible totals to 2 decimals NOK" but does not define the sequence. Two approaches exist:

- (a) Round each `InvoiceLine.total_cost` independently, then sum rounded line totals for the invoice total → can cause penny discrepancies between sum-of-lines and invoice total
- (b) Sum all line totals at full `Decimal` precision, round only the invoice total once → sum-of-lines may not equal the displayed invoice total

**Proposal:** Option (a). Round at line level. This is the most common invoicing convention, makes each line independently auditable, and the penny discrepancy risk is acceptable with proper documentation. The `InvoiceDailyCost` rows always remain at full precision.

**Answer:**

---

### RQ8 — Storage unit conversion: KB/KIB to billing unit

**Status:** PENDING

**Problem:**
StorageHotel `quota_unit` can be `KB` or `KIB`. The billing unit is `TB`. The exact conversion formulas are never documented, and it is unclear whether the billing unit `TB` means decimal terabytes (10^12 bytes) or binary tebibytes (2^40 bytes).

**Options:**
- (a) Billing unit is decimal TB (10^12 bytes). KB → TB: divide by 10^9. KIB → TB: multiply by 1024, divide by 10^12 (i.e., divide by ~976,562,500).
- (b) Billing unit is binary TiB (2^40 bytes). KB → TiB: multiply by 1000, divide by 2^40. KIB → TiB: divide by 2^30.
- (c) Billing unit is TB but inputs are always normalized to the same unit before storage — `quota_gb` field instead of raw quota + unit

**Proposal:** Option (a). Decimal TB is the industry standard for storage billing (consistent with how vendors like AWS price storage). Document the exact constant: `KB_TO_TB = Decimal("1e-9")`, `KIB_TO_TB = Decimal("1024") / Decimal("1e12")`.

**Answer:**

---

### RQ9 — LDAP authentication: in scope for v1 or not?

**Status:** PENDING

**Problem:**
`000-system-overview.prp.md` lists "authentication / authorization" as a **non-goal** for v1.
`CLAUDE.md` lists **LDAP authentication** as part of the stack.
These contradict each other.

**Options:**
- (a) LDAP is infrastructure-present but not enforced in v1 — the package is installed, settings are configured, but API endpoints are open or use session auth only
- (b) LDAP is a v1 deliverable — remove it from the non-goals list in the overview PRP
- (c) LDAP is out of scope entirely — remove it from `CLAUDE.md` stack list

**Proposal:** Whichever is correct, the docs must agree. If the intent is (a), say so explicitly in both places.

**Answer:**

---

### RQ10 — STRUCTURE.md is nearly empty

**Status:** PENDING

**Problem:**
`.claude/docs/STRUCTURE.md` is referenced in multiple routing tables and skill files as the authority on file placement, but it contains only a routing header and no actual rules.
This means Claude has no documented guidance on where to put files.

**Options:**
- (a) Populate it now, derived from the system overview PRP app structure and conventions implied by other docs
- (b) Remove it from all routing tables until it is written
- (c) Leave it empty and rely on CLAUDE.md's project structure description

**Proposal:** Option (a). Populate with the implied structure: `apps/billing/`, `apps/ingest/`, per-app layout for `models.py`, `services/`, `selectors/`, `serializers.py`, `views.py`, `tests/`.

**Answer:**

---

## IMPORTANT (not blockers, but should fix before major implementation)

---

### RQ11 — `InvoiceLine` fields: `total_billed_amount` vs `total_cost`

**Status:** PENDING

**Problem:**
`InvoiceLine` has two fields that appear synonymous: `total_billed_amount` and `total_cost`. If they mean the same thing, one should be removed. If they are different, the distinction must be documented.

**Proposal:**
- Rename `total_billed_amount` → `total_billed_quantity` (stores aggregate resource usage, not money)
- Keep `total_cost` as the money field (Decimal, NOK)

**Answer:**

---

### RQ12 — `InvoiceLine.unit_price_snapshot` purpose and type

**Status:** PENDING

**Problem:**
`unit_price_snapshot` is on `InvoiceLine` but its type and meaning are undefined. Since prices can differ day-to-day within the same invoice period, a single snapshot at the line level is ambiguous. Per-day price data is already captured in `InvoiceDailyCost`.

**Options:**
- (a) Remove the field — daily-level data in `InvoiceDailyCost` is sufficient
- (b) Keep it as a representative/display price — the effective price on the last day of the period, or the most common price, clearly documented as non-authoritative
- (c) Change to a JSON field storing a price history summary

**Proposal:** Option (a). Remove it. `InvoiceDailyCost` is the source of truth; a summary field at the line level adds confusion without value.

**Answer:**

---

### RQ13 — Duplicate invoice constraint

**Status:** PENDING

**Problem:**
No documented uniqueness constraint prevents generating two invoices for the same billing account and billing period. It is unclear whether multiple draft invoices for the same account/period are intentional.

**Proposal:**
Add a unique constraint on `Invoice`: `(billing_account, period_start, period_end)`. Allow override only via explicit `force=true` on re-generation, which would replace the existing draft.

**Answer:**

---

### RQ14 — `deleted_at` soft-delete semantics

**Status:** PENDING

**Problem:**
Both `StorageHotel` and `VirtualMachine` have a `deleted_at` field implying soft-delete, but nothing defines:
- What sets `deleted_at` (API call? admin action?)
- How it interacts with `status` (can a deleted resource be ACTIVE?)
- Whether a soft-deleted resource is billable

**Proposal:**
- Setting `deleted_at` also sets `status = RETIRED`
- A resource with `deleted_at IS NOT NULL` is never billable
- Default queryset excludes soft-deleted resources (custom manager)

**Answer:**

---

### RQ15 — Invoice API endpoints: where are they specified?

**Status:** PENDING

**Problem:**
No PRP or doc defines the invoice lifecycle API: generate, finalize, retrieve. The billing engine PRP defines the algorithm but not the HTTP interface.

**Proposal:**
Add an invoice API section to either `001-billing-engine.prp.md` or a new `003-invoice-api.prp.md` covering:
- `POST /api/v1/invoices/generate`
- `POST /api/v1/invoices/{id}/finalize`
- `GET  /api/v1/invoices/`
- `GET  /api/v1/invoices/{id}/`

**Answer:**

---

## MINOR FIXES (low effort, should be done alongside other work)

---

### RQ16 — Q1 in clarifications.md: marked HELPME but Q6/Q7 already resolve it

**Status:** PENDING

**Problem:**
Q1 asks about VM billing strategy and is marked HELPME. But Q6 answers "one row per dimension per day" and Q7 answers "discounts per dimension independently." Q1 should be marked ANSWERED.

**Proposal:** Update Q1 status to ANSWERED with summary: "VM v1 billing is per-dimension (cpu, ram, disk), with 3 InvoiceDailyCost rows per VM per day. Discounts apply per dimension independently."

**Answer:**

---

### RQ17 — Q3 in clarifications.md: marked HELPME but has an answer

**Status:** PENDING

**Problem:**
Q3 has status "HELPME" but the answer `(c) Formatted string with pattern INV-YYYY-mm-NNNN` is already written in the document.

**Proposal:** Change Q3 status to ANSWERED.

**Answer:**

---

### RQ18 — Q7 in clarifications.md: trailing `|` typo

**Status:** PENDING

**Problem:**
Line reads `**Status:** ANSWERED|` — stray pipe character.

**Proposal:** Remove the `|`.

**Answer:**

---

### RQ19 — VM and StorageHotel PRP API paths missing `/api/v1/` prefix

**Status:** PENDING

**Problem:**
Both resource PRPs list endpoints without the required `/api/v1/` prefix, contradicting the API rules in `CLAUDE.md`.

**Proposal:** Prefix all endpoint listings with `/api/v1/` in both resource PRPs.

**Answer:**

---

### RQ20 — mypy described as "optional" in one doc, mandatory in another

**Status:** PENDING

**Problem:**
`DEVELOPER_TOOLING_AND_ENVIRONMENT.md` says "Type checking is optional but available." `CODING_RULES.md` says all new code must be compatible with mypy and type annotations are required. mypy is also in pre-commit hooks.

**Proposal:** Update `DEVELOPER_TOOLING_AND_ENVIRONMENT.md` to say type checking is mandatory.

**Answer:**

---

### RQ21 — `django-doctor` not in pre-commit

**Status:** PENDING

**Problem:**
`CODING_RULES.md` lists `django-doctor` as a quality tool. `pyproject.toml` includes it under optional dependencies. But it is not in the pre-commit config and `DEVELOPER_TOOLING_AND_ENVIRONMENT.md` does not mention it.

**Options:**
- (a) Add it to pre-commit
- (b) Document it as a manual-only tool
- (c) Remove it entirely

**Answer:**

---

### RQ22 — Testing skill references `apps/invoices/` (wrong app name)

**Status:** PENDING

**Problem:**
`.claude/skills/django-testing-pattern/SKILL.md` has an example path `apps/invoices/tests/test_api_invoice_generation.py`. The project has `apps/billing/`, not `apps/invoices/`.

**Proposal:** Change to `apps/billing/tests/test_api_invoice_generation.py`.

**Answer:**

---

### RQ23 — Testing skill SKILL.md wrapped in markdown code fence

**Status:** PENDING

**Problem:**
The entire `django-testing-pattern/SKILL.md` is wrapped in a ` ```md ` / ` ``` ` code fence. The API endpoint skill does not have this. This may cause the skill to be parsed as a code block rather than actionable content.

**Proposal:** Remove the outer code fence wrapping.

**Answer:**

---
