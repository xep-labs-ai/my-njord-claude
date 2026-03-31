# Review Clarifications — Round 18

**Source:** Architect Agent exhaustive review, 2026-03-30
**Scope:** New issues not identified in rounds 1–17


## Own clarifications and suggestions

Claude must use Architect to ask more about these new clarifications and suggestions:

### Archictecture Project Structure clarifications

- The `Project Structure` inside `.claude/docs/ARCHITECTURE.md` is an example of how the structure should be as the project grows, not an exact listing of all apps and files. Architect must review the Architecture naming and structure rules and suggest better naming if necessary.

### Exceptions and Errors

- Should exceptions be inside their own file like:

```
src/apps/
├── billing/
│   ├── services/
│   ├── api/
│   ├── exceptions.py
│   └── ...
├── ingest/
│   ├── services/
│   ├── api/
│   ├── exceptions.py
│   └── ...
└── common/
    ├── api/
    │   └── exception_handlers.py
    ├── exceptions.py
    └── ...
```

If so it must be documented in the `.claude/docs/ARCHITECTURE.md`

---

## HIGH Severity

---

### O-1. Stale advisory lock reference in BILLING.md

**Files:** `.claude/docs/BILLING.md` line 616

**Description:**
BILLING.md states: "The billing engine uses a PostgreSQL advisory lock to prevent concurrent generation for the same invoice period. See `001-billing-engine.prp.md` for the locking strategy."

This directly contradicts the current PRP design. Rounds 14–17 explicitly removed advisory locks and replaced them with service-layer locking using `select_for_update()`. PRP `001-billing-engine.prp.md` (lines 293–303) clearly states: "v1 does not use PostgreSQL advisory locks" and describes `select_for_update()` on matching draft rows.

**Impact:** An implementer reading BILLING.md would implement advisory locks, directly contradicting the authoritative PRP.

**Proposal:** Replace the advisory lock sentence in BILLING.md with: "The billing engine uses a database uniqueness constraint and service-layer transactional checks with `select_for_update()` on matching draft rows to prevent duplicate generation. v1 does not use PostgreSQL advisory locks."

**Decision:**

Accept proposal

---

### O-2. Ingestion event FK `on_delete` inconsistency between StorageHotel and VirtualMachine PRPs

**Files:** `docs/PRP/resources/storage-hotel.prp.md` line 106, `docs/PRP/resources/virtual-machine.prp.md` lines 72, 101

**Description:**
The `on_delete` policy for ingestion event FKs and snapshot model FKs is inconsistent between the two resource PRPs:

- `StorageHotelDailyQuota.storage_hotel` — `on_delete=PROTECT` (storage-hotel.prp.md line 77)
- `QuotaIngestionEvent.storage_hotel` — `on_delete=CASCADE` (storage-hotel.prp.md line 106)
- `VirtualMachineDailyUsage.virtual_machine` — `on_delete=CASCADE` (virtual-machine.prp.md line 72)
- `VirtualMachineUsageIngestionEvent.virtual_machine` — `on_delete=PROTECT` (virtual-machine.prp.md line 101)

The result is asymmetric: StorageHotel snapshot uses PROTECT (correct) while its ingestion event uses CASCADE; VirtualMachine snapshot uses CASCADE (data loss risk) while its ingestion event uses PROTECT.

The `VirtualMachineDailyUsage` CASCADE means hard-deleting a VirtualMachine silently cascade-deletes all its daily usage snapshots — the data needed for billing.

**Proposal:** Apply `on_delete=PROTECT` to all four FKs. All represent financial/audit data that must not be silently cascade-deleted.

**Decision:**

Accept proposal

---

## MEDIUM Severity

---

### O-3. ARCHITECTURE.md model sub-module names differ between sections

**Files:** `.claude/docs/ARCHITECTURE.md` lines 133–141 vs. lines 316–321

**Description:**
The "Model Organization" section uses plural names (`billing_accounts.py`, `invoices.py`, `resources.py`) and includes `base.py` and `snapshots.py`. The "Project Structure" tree uses singular names (`billing_account.py`, `invoice.py`, `resource.py`) and omits `base.py` and `snapshots.py`.

An implementer must choose one convention and will contradict the other section.

**Proposal:** Reconcile to the plural convention from the Model Organization section. Update the Project Structure tree to match and add `base.py` and `snapshots.py`.

**Decision:**

Accept proposal

---

### O-4. `missing_data_summary` absent from invoice detail response example

**Files:** `docs/PRP/002-resource-models.prp.md` line 295, `docs/PRP/003-invoice-api.prp.md` lines 77, 193

**Description:**
PRP 002 line 295: "`missing_data_summary` — always present in Invoice metadata; `null` when `incomplete=false`, populated object when `incomplete=true`."

PRP 003 line 77 (generate response) includes `"missing_data_summary": null`. PRP 003 line 193 (detail response) does NOT include `missing_data_summary` for a non-incomplete invoice.

**Proposal:** PRP 002 is authoritative: always present, `null` when `incomplete=false`. Update PRP 003 detail response example to include `"missing_data_summary": null`, matching the generate response example.

**Decision:**

Accept proposal

---

### O-5. `common` app missing from PRP 000; base model location conflict

**Files:** `docs/PRP/000-system-overview.prp.md` lines 196–210, `.claude/docs/ARCHITECTURE.md` lines 135, 349–355

**Description:**
PRP 000 lists only `apps/billing/` and `apps/ingest/`. ARCHITECTURE.md includes `apps/common/` in the project structure tree. Separately, ARCHITECTURE.md Model Organization (line 135) places `TimestampedModel` and `CreatedAtModel` in `apps/billing/models/base.py`, while the project structure tree implies they live in `apps/common/models/`.

**Proposal:** Since `TimestampedModel` and `CreatedAtModel` are cross-app abstractions, place them in `apps/common/models/base.py`. Update ARCHITECTURE.md Model Organization accordingly. Add `apps/common/` to PRP 000's app listing. Remove `base.py` from the billing models list.

**Decision:**

Accept proposal, and in addition Claude must use the architect to document the following:

- The apps in the project structure were just an example of how the structure is intended to be as the project grows, not an exact listing of all apps and files. Architect must review the Architecture naming and structure rules and suggest better naming if necessary.

---

### O-6. `discount_price_per_unit_year` "must be positive" blocks zero-discount (free-after-threshold)

**Files:** `docs/PRP/005-pricing-api.prp.md` lines 266–267

**Description:**
PRP 005 line 266: `price_per_unit_year` must be non-negative (>= 0). PRP 005 line 267: `discount_price_per_unit_year` must be positive if set.

"Must be positive" (strictly > 0) prevents `discount_price_per_unit_year = 0`, blocking the free-after-threshold scenario (e.g., normal price = 5, discount price = 0).

**Proposal:** Clarify whether zero is a valid discount price. If yes, change "must be positive" to "must be non-negative (>= 0)" and add a constraint that when `price_per_unit_year = 0`, discount fields must be null. If no, document why free-after-threshold is not supported.

**Decision:**

Accept proposal, it can be zero

---

### O-7. REST_FRAMEWORK settings missing `MAX_PAGE_SIZE`; needs custom pagination class

**Files:** `.claude/docs/API.md` lines 127–135, 152

**Description:**
API.md line 152 states the maximum page size is 200, but the `REST_FRAMEWORK` settings block only includes `"PAGE_SIZE": 50`. Standard DRF `PageNumberPagination` does not support `MAX_PAGE_SIZE` directly; a custom subclass with `max_page_size = 200` is required. `apps/common/pagination.py` is already in the project structure.

**Proposal:** Define a custom pagination class in `apps/common/pagination.py` with `max_page_size = 200` and `page_size = 50`, and reference it as `DEFAULT_PAGINATION_CLASS` in REST_FRAMEWORK settings. Document this in API.md.

**Decision:**

Accept proposal.

---

### O-8. API.md `missing_snapshot` error `details` is object; PRP 003 requires list

**Files:** `.claude/docs/API.md` lines 196–205, `docs/PRP/003-invoice-api.prp.md` lines 396–414

**Description:**
API.md shows `details` as a single object for `missing_snapshot` errors. PRP 003 line 414 explicitly states: "`details` is always a list of affected resources, even when only one resource has missing data." The API.md example predates this rule and shows the wrong format.

**Proposal:** Update the `missing_snapshot` example in API.md to show `details` as a list, consistent with PRP 003.

**Decision:**

Accept proposal

---

### O-9. `Invoice.total_amount` nullable description implies a transient state that never persists

**Files:** `docs/PRP/002-resource-models.prp.md` lines 329, 335

**Description:**
PRP 002 says `total_amount` is "null only before generation runs; set during draft creation and updated on recalculation." The generate endpoint creates invoices with status=draft AND computes totals in the same transaction, so `total_amount` should never be null on a committed row.

The check constraint `CHECK (status = 'draft' OR total_amount IS NOT NULL)` only enforces non-null for finalized invoices.

**Proposal:** Clarify in PRP 002 that `total_amount` is set atomically during draft creation. The nullable field declaration exists for ORM compatibility (DecimalField requires `null=True` or a default), but no committed Invoice row should have `total_amount = null`. The check constraint is a safety net for finalization.

**Decision:**

Accept proposal.

---

## LOW Severity

---

### O-10. `on_delete=PROTECT` chain creates an unclearable dependency graph

**Files:** `docs/PRP/002-resource-models.prp.md` line 193, `docs/PRP/005-pricing-api.prp.md` line 343

**Description:**
`ResourceModel.billing_account` uses PROTECT. `BillingAccount.price_list` uses PROTECT. Nothing can be hard-deleted in v1. This is by design (no DELETE endpoints) but is not explicitly documented as a constraint chain.

**Decision:**

Following block is the answer:

```
Recommended decision:

- KEEP the current `PROTECT` chain
- ADD explicit documentation that this is intentional in v1
- DO NOT treat this as a schema flaw

Why:
- consistent with no-DELETE v1 policy
- preserves auditability and referential integrity
- prevents destructive cleanup of financially relevant history
- retirement / soft-delete is the intended lifecycle path

So this is primarily a documentation clarification, not a model redesign issue.
```

---

### O-11. `ResourcePrice.__str__` always shows open-ended dash regardless of `effective_to`

**Files:** `docs/PRP/002-resource-models.prp.md` line 597

**Description:**
The `__str__` is `f"{self.resource_type}/{self.pricing_dimension} ({self.effective_from}-)"` — always shows an open dash even when `effective_to` is set.

**Proposal:** Consider `f"... ({self.effective_from} - {self.effective_to or ''})"` for admin/shell clarity.

**Decision:**

Accept proposal

---

### O-12. No explicit specification for `InvoiceDailyCost` API exposure in v1

**Files:** `docs/PRP/003-invoice-api.prp.md` lines 487–491

**Description:**
PRP 003 lists `GET /api/v1/invoices/{id}/daily-costs` as a v2 endpoint. There is no v1 API access to InvoiceDailyCost data, preventing programmatic audit workflows in v1.

**Proposal:** Add a brief note to PRP 003 stating that InvoiceDailyCost data is not exposed through the v1 API.

**Decision:**

Accept proposal

---

### O-13. No ordering specification for InvoiceLines in API responses

**Files:** `docs/PRP/003-invoice-api.prp.md`

**Description:**
Invoice detail/generate responses include `"lines": [...]` but no ordering is specified. This affects test stability and API predictability.

**Proposal:** Specify that InvoiceLines should be ordered by `(resource_type, resource_id)` for deterministic output.

**Decision:**

Accept proposal

---

### O-14. `InvoiceLine.created_at` presence in API responses undocumented

**Files:** `docs/PRP/003-invoice-api.prp.md` lines 79–103, `docs/PRP/002-resource-models.prp.md` lines 362–364

**Description:**
`InvoiceLine` inherits from `CreatedAtModel` (has `created_at`), but API response examples in PRP 003 do not include `created_at`. Whether this is intentionally excluded from the serializer is undocumented.

**Proposal:** Add a note to PRP 003 that `InvoiceLine.created_at` is intentionally excluded from API responses, or include it in the examples if it should be exposed.

**Decision:**

Include it in all the examples, it is not intentionally excluded.

---

### O-15. TESTING.md and TESTING_TEMPLATES.md test file paths use `apps/` not `src/apps/`

**Files:** `.claude/docs/TESTING.md` line 504

**Description:**
TESTING.md shows `uv run pytest apps/billing/tests/test_invoice_generation.py`. With the monorepo structure (`src/` as Django root), the actual path may be `src/apps/billing/tests/test_invoice_generation.py`, depending on pytest configuration.

**Proposal:** Verify `pyproject.toml` configures pytest `testpaths` correctly. Update test path references in TESTING.md if needed.

**Decision:**

Accept proposal and ensure that all the things that are using the old structure are updated to reflect the new structure, including the test templates.

---

### O-16. `namespace` field override pattern undocumented for implementation

**Files:** `docs/PRP/002-resource-models.prp.md` lines 195–196

**Description:**
PRP 002 states `namespace` is optional at the abstract level (`blank=True, default=""`) but required at the concrete level (`blank=False`). This requires field redeclaration in each concrete model, a Django pattern that should be explicitly noted.

**Proposal:** Add a brief implementation note about field redeclaration.

**Decision:**

Following block is the answer:

```
Recommended decision:

- ACCEPT the proposal
- ADD a short implementation note
- KEEP the current abstract/concrete design

Why:
- valid Django pattern
- abstract base should stay flexible
- concrete models can enforce stricter requirements
- the only missing piece is explicit documentation about field redeclaration
```

---

### O-17. Soft-delete endpoint error codes not in API.md error code table

**Files:** `.claude/docs/API.md` lines 222–241, `docs/PRP/004-resource-api.prp.md` lines 209–231

**Description:**
PRP 004 defines soft-delete endpoints returning 400 and 409 for various conditions, but API.md's central error code table does not include named codes for soft-delete operations.

**Proposal:** Add soft-delete error codes to API.md (e.g., `soft_delete_precondition_failed` for 400, `already_soft_deleted` for 409).

**Decision:**

Accept proposal

---

### O-18. ARCHITECTURE.md common app listing missing `apps.py` and `__init__.py`

**Files:** `.claude/docs/ARCHITECTURE.md` lines 349–355

**Description:**
The project structure tree shows `apps/common/` but omits `apps.py` and `__init__.py`, which are present for billing and ingest apps.

**Proposal:** Add `apps.py` and `__init__.py` to the common app listing.

**Decision:**

Accept proposal

---

### O-19. PRP 002 does not specify which app owns `TimestampedModel` / `CreatedAtModel`

**Files:** `docs/PRP/002-resource-models.prp.md` lines 134–157

**Description:**
PRP 002 defines these abstract base models but does not specify their app location. Related to O-5.

**Proposal:** Add a one-line note specifying the app location once O-5 is resolved.

**Decision:**

Accept proposal

---

### O-20. Finalize endpoint 409 response body example missing from PRP 003

**Files:** `docs/PRP/003-invoice-api.prp.md` line 239

**Description:**
PRP 003 documents the finalize endpoint returning 409 for "already finalized" but does not show an example response body.

**Proposal:** Add a brief 409 response body example to the finalize endpoint section.

**Decision:**

Accept proposal

---

## Pre-Implementation Checklist

### C-1. Resolve ingestion event and snapshot FK `on_delete` policy (O-2)

Before writing any models, decide on a consistent `on_delete` policy for all four FKs:
- `StorageHotelDailyQuota.storage_hotel` (currently PROTECT)
- `QuotaIngestionEvent.storage_hotel` (currently CASCADE — likely wrong)
- `VirtualMachineDailyUsage.virtual_machine` (currently CASCADE — likely wrong)
- `VirtualMachineUsageIngestionEvent.virtual_machine` (currently PROTECT)

Recommended: PROTECT for all four.

**Decision:**

Accept proposal

---

### C-2. Resolve base model location (O-5, O-19)

Decide whether `TimestampedModel` and `CreatedAtModel` live in `apps/common/models/base.py` or `apps/billing/models/base.py`. Update PRP 002, PRP 000, and ARCHITECTURE.md consistently.

**Decision:**

They live in `apps/common/models/base.py`

---

### C-3. Resolve model sub-module naming convention (O-3)

Decide between plural and singular for model sub-module filenames. Update both sections of ARCHITECTURE.md to match.

**Decision:**

Accept proposal

---

### C-4. Remove stale advisory lock reference from BILLING.md (O-1)

Fix before implementation begins to prevent an implementer from building the wrong concurrency strategy.

**Decision:**

Accept proposal

---

### C-5. Decide on `discount_price_per_unit_year = 0` validity (O-6)

Is a zero discount price (free-after-threshold) a valid business scenario? This affects validation rules in the ResourcePrice creation service.

**Decision:**

Claude Architect should recommend a better approach if necessary. Meanwhile zeor is acceptable.

---

### C-6. Implement custom pagination class for `max_page_size` (O-7)

`apps/common/pagination.py` needs a custom `PageNumberPagination` subclass with `max_page_size = 200`. Document before the first list endpoint is implemented.

**Decision:**

Accept proposal, and ensure that if pagination was proposed to be present in another places, they should also be updated to use the new pagination class.

---

### C-7. Verify pytest test path configuration (O-15)

With the `src/` monorepo structure, verify that `pyproject.toml` configures pytest to find tests correctly. Update TESTING.md path examples if needed.

**Decision:**

Accept proposal

---

### C-8. Decide on InvoiceLine ordering in API responses (O-13)

Specify a deterministic ordering for InvoiceLine objects in detail/generate responses.

**Decision:**

Claude architect should propose a suggestion and document it afterwards.

---

### C-9. Decide on `InvoiceLine.created_at` API exposure (O-14)

Should `InvoiceLine.created_at` be included in API responses?

**Decision:**

Yes, include it in API responses and examples.

---

### C-10. Update API.md `missing_snapshot` error example to list format (O-8)

Fix the API.md drift to match the authoritative PRP 003 format before implementation.

**Decision:**

Accept proposal

---

## Issue Summary

| Severity | Issues |
|----------|--------|
| HIGH     | O-1, O-2 |
| MEDIUM   | O-3, O-4, O-5, O-6, O-7, O-8, O-9 |
| LOW      | O-10 through O-20 |

The two HIGH issues (stale advisory lock in BILLING.md and inconsistent `on_delete` policies) are implementation-blocking and must be resolved before writing any Django model or service code.
