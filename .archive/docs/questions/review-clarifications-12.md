# Review Clarifications 12

Architecture review round 12 — documentation consistency and correctness pass.
Edit each `**Decision:**` line with your answer.

---

## HIGH

### H-1. `PROJECT.md` claims "No Django project has been developed yet" — stale implementation status

`PROJECT.md` says "No Django project has been developed yet" and "Everything must be created from scratch." The PRPs, clarification rounds (1 through 11), and tooling all exist. The implementation status section is stale and misleading. A reader (or Claude) encountering this text could incorrectly conclude that no design work has been done.

Proposal: update the implementation status section in `PROJECT.md` to reflect the current state — design and specification phase is complete, implementation has not yet started, PRPs and clarification rounds define the target architecture.

**Decision:**

Accept proposal

---

### H-2. `PROJECT.md` missing standard routing header

`PROJECT.md` is missing the standard routing header (`Doc Purpose`, `Read this document when`, `Do not read this document when`) that all other `.claude/docs/` files have. `CLAUDE.md` says Claude should use that header first to determine document relevance.

Proposal: add the standard routing header to `PROJECT.md`, consistent with all other `.claude/docs/` files.

Suggested header:

```
Doc Purpose: system purpose, core domain entities, billing context, supported resource types, shared terminology
Read this document when: you need to understand the project domain, resource types, billing concepts, or shared terminology
Do not read this document when: you are making isolated test, formatting, or tooling changes with no domain impact
```

**Decision:**

Accept proposal

---

### H-3. `BILLING.md` snapshot field lists omit `currency`

`BILLING.md` Line-level and Daily-level snapshot field lists do not include the `currency` field. Per `002-resource-models.prp.md`, both `InvoiceLine` and `InvoiceDailyCost` have a `currency` field (`CharField`, default `"NOK"`).

Proposal: add `currency` to both the line-level and daily-level snapshot field lists in `BILLING.md`.

**Decision:**

Following block is the answer:

```
Accept the proposal.

Decision:

Add `currency` to both the line-level and daily-level snapshot field lists in `BILLING.md`.

Reasoning:

- `002-resource-models.prp.md` already defines `currency` on both `InvoiceLine` and `InvoiceDailyCost`
- `BILLING.md` should stay aligned with the actual persisted snapshot model
- currency is part of the meaning of both line-level totals and daily billed amounts, even if v1 defaults to `"NOK"`

Documentation update:

- add `currency` to the line-level snapshot field list
- add `currency` to the daily-level snapshot field list

This keeps `BILLING.md` consistent with the invoice snapshot model defined elsewhere in the PRPs.
```

---

### H-4. `BILLING.md` does not describe the dual-storage strategy for `autofilled`

`BILLING.md` mentions `autofilled` only in a metadata context. Per `002-resource-models.prp.md` and review-clarifications-10 C-1, `autofilled` is a dedicated `BooleanField` column on `InvoiceDailyCost` AND is kept in metadata for audit self-containment. `BILLING.md` does not describe this dual-storage strategy.

Proposal: update `BILLING.md` to state that `autofilled` exists as both a top-level `BooleanField(default=False)` on `InvoiceDailyCost` (the queryable source of truth) and as a key in `InvoiceDailyCost.metadata` (for audit self-containment), consistent with C-1 from round 10.

**Decision:**

Accept proposal

---

### H-5. `BILLING.md` says force-mode zero-cost rows have `autofilled=true` — semantically wrong

`BILLING.md` line 249 says: "under `force=true`, those days produce a zero-cost `InvoiceDailyCost` row with `autofilled=true`."

This is semantically wrong. `autofilled=true` means "carried forward from a prior snapshot." Force-mode zero-cost billing does not carry anything forward — it assigns zero because no snapshot exists. These rows should have `autofilled=false`.

Proposal: change `BILLING.md` to state that force-mode zero-cost rows have `autofilled=false`, and add a clarifying note distinguishing force-mode zero rows (no data available, zero assigned) from autofilled rows (data carried forward from a prior snapshot).

**Decision:**

Accept proposal

---

## MEDIUM

### M-1. `000-system-overview.prp.md` lifecycle section could better clarify `status` vs. `active_from`/`active_to` for billing

`000-system-overview.prp.md` lifecycle section describes resource statuses but does not prominently clarify that `status` is cosmetic for billing purposes and that `active_from`/`active_to` are what actually determine billability. A reader might assume `status` controls billing eligibility.

Two options:
- **(a)** Add an explicit note to the lifecycle section: "`status` is for operational/display purposes only. Billing eligibility is determined exclusively by `active_from` and `active_to` date ranges."
- **(b)** Leave the current text as-is; the distinction is documented elsewhere in the billing PRPs.

Proposal: **(a)**. The lifecycle section is the natural place where a reader forms their mental model of how resources interact with billing, so the clarification belongs there.

**Decision:**

Following block is the answer:

```
Accept the proposal.

Decision:

Add an explicit clarification to the lifecycle section in `000-system-overview.prp.md` stating that `status` is not used for billing eligibility.

Reasoning:

- the lifecycle section is where readers form their mental model of resource behavior
- without this clarification, it is easy to assume that `status` controls billing
- in this system, billing is determined strictly by date ranges (`active_from`, `active_to`), not by `status`

Recommended addition:

Billing rule:

- `status` is for operational and display purposes only
- billing eligibility is determined exclusively by `active_from` and `active_to`
- a resource is billable on a given day if:
  - `active_from <= date`
  - and (`active_to` is null or `date <= active_to`)

Clarification:

- setting `status = RETIRED` does not retroactively affect billing
- billing stops when `active_to` is reached, not when status changes
```

---

### M-2. `BILLING.md` references `selection_fingerprint` but never defines the algorithm

`BILLING.md` references `selection_fingerprint` in the duplicate prevention key but never defines the fingerprint algorithm or canonical payload schema. The full specification is in `001-billing-engine.prp.md`. `BILLING.md` has no cross-reference to it.

Proposal: add a cross-reference in `BILLING.md` pointing to `001-billing-engine.prp.md` for the `selection_fingerprint` algorithm definition, and add a one-sentence summary of what the fingerprint represents (e.g., "a deterministic hash of the canonical selection payload").

**Decision:**

Accept proposal

---

### M-3. Description fallback format — PascalCase vs. snake_case ambiguity

The description fallback format is defined as `{ResourceType} #{resource_id}` (e.g., `StorageHotel #101`) in both `BILLING.md` and `002-resource-models.prp.md`. It is ambiguous whether `{ResourceType}` should be the Django model class name (PascalCase: `StorageHotel`) or the `resource_type` string value (snake_case: `storage_hotel`).

API response examples in `003-invoice-api.prp.md` show `StorageHotel #101` (PascalCase), suggesting PascalCase is intended.

Two options:
- **(a)** PascalCase (Django model class name): `StorageHotel #101`
- **(b)** snake_case (`resource_type` field value): `storage_hotel #101`

Proposal: **(a)** PascalCase. It is more human-readable as a display string, and all existing examples already use this form.

**Decision:**

Accept proposal

---

### M-4. `API.md` error codes reference ResourcePrice endpoints that `API.md` does not document

`API.md`'s error code table includes `price_row_already_closed` for "ResourcePrice create" context and `price_range_overlap` for "ResourcePrice create". However, `API.md` does not document ResourcePrice endpoints or the `set-effective-to` endpoint — those are only in `005-pricing-api.prp.md`. A reader of `API.md` alone finds error codes with no context for when or where they occur.

Two options:
- **(a)** Add a brief note or cross-reference in `API.md` indicating that ResourcePrice endpoints are defined in `005-pricing-api.prp.md`.
- **(b)** Move the ResourcePrice-specific error codes out of `API.md` and into `005-pricing-api.prp.md` only.

Proposal: **(a)**. The error code table in `API.md` serves as a centralized reference, which is useful. Adding a cross-reference preserves that value while pointing readers to the full endpoint documentation.

**Decision:**

Accept proposal

---

### M-5. StorageHotel field list missing `name` in `002-resource-models.prp.md`

StorageHotel field list in `002-resource-models.prp.md` (and `storage-hotel.prp.md`) is missing the `name` field. VirtualMachine correctly includes `name`. `004-resource-api.prp.md` shows `name` as a writable field on StorageHotel creation, confirming the field exists.

Proposal: add `name` (`CharField`, optional/blank) to the StorageHotel field list in `002-resource-models.prp.md` and `storage-hotel.prp.md`, consistent with VirtualMachine and the API PRP.

**Decision:**

Accept proposal

---

### M-6. `TESTING.md` uses bare `pytest` without `uv run` prefix

`TESTING.md` uses bare `pytest` (without `uv run` prefix) in one place while the rest of the document and `DEVELOPER_TOOLING_AND_ENVIRONMENT.md` consistently use `uv run pytest`.

Proposal: change the bare `pytest` reference to `uv run pytest` for consistency.

**Decision:**

Accept proposal

---

## LOW

### L-1. `docs/PRP/resources/_resource-template.prp.md` endpoint paths missing `/api/v1/` prefix

`docs/PRP/resources/_resource-template.prp.md` shows endpoint paths without the `/api/v1/` prefix (e.g., `POST /<resources>/`). All concrete resource PRPs have the correct prefix per RQ19, but the template was not updated.

Proposal: update the template to use the `/api/v1/` prefix in endpoint path examples.

**Decision:**

Accept proposal

---

### L-2. Clarification files have no mechanism to flag superseded answers

Clarification files have no mechanism to flag when an answer was superseded by a later round. Stale answers in earlier files could override correct behavior from PRPs if Claude reads the earlier file first.

Three options:
- **(a)** Add a `Superseded by:` marker to individual questions when a later round changes the decision. Requires retroactive edits to earlier files.
- **(b)** Add a general note at the top of each clarification file: "If a decision in this file conflicts with a later round or the current PRPs, the later source takes precedence."
- **(c)** Do nothing — the PRPs are the source of truth and clarification files are historical records. Claude should always prefer PRP content over clarification files.

Proposal: **(c)** with a small addition. The PRPs are already the source of truth. Add a one-line note to `CLAUDE.md` or `BILLING.md` stating: "PRPs take precedence over review-clarifications files when content conflicts." This avoids retroactive edits while making the precedence rule explicit.

**Decision:**

```
Accept the proposal with a small addition.

Decision:

Choose option (c).

PRPs are the authoritative source of truth. Clarification files are historical records and may contain outdated decisions.

Add an explicit precedence rule in `CLAUDE.md` stating that PRPs take precedence over clarification files in case of conflict.

Reasoning:

- PRPs define the system contract and must be authoritative
- clarification files are iterative and may contain superseded answers
- retroactively editing all clarification files is not scalable
- a single explicit precedence rule avoids ambiguity and keeps the system maintainable

Recommended rule:

PRPs (`docs/PRP/*.prp.md`) are the source of truth.  
If any clarification or review document conflicts with a PRP, the PRP must be followed.

Clarification files should be treated as historical context, not authoritative specification.
```
---

## Follow-Up Questions

No follow-up questions required. All decisions in this round are clear, unambiguous, and implementation-ready. A documenter can safely apply these changes.
