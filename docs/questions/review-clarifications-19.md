# Review Clarifications — Round 19

**Source:** Architect Agent exhaustive review, 2026-04-01
**Scope:** New issues not identified in rounds 1–18

---

## HIGH Severity

---

### O-1. `soft_delete_precondition_failed` placed in the wrong error code table in API.md

**Files:** `.claude/docs/API.md` lines 225–237, `docs/PRP/004-resource-api.prp.md` lines 226–231, 441–446

**Description:**
The rc-18 O-17 documenter added `soft_delete_precondition_failed` to the **409 Conflict** error code table in API.md. But PRP 004 is explicit: "400: Resource is not RETIRED or `active_to` is not set." The 400 and 409 responses for soft-delete are:

- **400** — `soft_delete_precondition_failed` (resource not RETIRED or `active_to` not set)
- **409** — `already_soft_deleted` (resource already soft-deleted)

The `already_soft_deleted` code is correctly placed in the 409 table. But `soft_delete_precondition_failed` is a 400 code and must not appear in the 409 table.

**Impact:** Implementation-blocking. An implementer reading API.md will return 409 when the spec requires 400. This is a direct HTTP contract error introduced in rc-18.

**Proposal:**
- Move `soft_delete_precondition_failed` out of the 409 table.
- API.md currently has no 400 error codes table. Either add one, or document the 400 soft-delete error code inline in the soft-delete endpoint section of PRP 004. Update API.md to reflect this correction.

**Decision:**

Accept proposal

---

### O-2. `pyproject.toml` not updated for `src/` layout — pytest and package building will fail

**Files:** `pyproject.toml` lines 32–39, `.claude/docs/ARCHITECTURE.md` lines 306–374

**Description:**
The rc-18 O-15/C-7 decision resolved test path references in TESTING.md but did not update `pyproject.toml` itself. The current configuration:

```toml
[tool.setuptools.packages.find]
where = ["."]
include = ["apps*", "config*"]

[tool.pytest.ini_options]
DJANGO_SETTINGS_MODULE = "config.settings.test"
```

With `where = ["."]`, setuptools looks for packages at the project root. But ARCHITECTURE.md now states that `apps/` and `config/` live under `src/`. This means:

1. `where = ["."]` should be `where = ["src"]`
2. pytest needs `pythonpath = ["src"]` so that `config.settings.test` is importable and `apps.*` modules can be found without installing the package
3. `testpaths` should point to `src` (or at minimum be set explicitly)

Without these changes, running `uv run pytest` will fail with import errors because Python cannot find `config.settings.test` or any `apps.*` module.

**Impact:** Implementation-blocking. No test can run with the current `pyproject.toml` under the documented `src/` layout.

**Proposal:**
```toml
[tool.setuptools.packages.find]
where = ["src"]
include = ["apps*", "config*"]

[tool.pytest.ini_options]
DJANGO_SETTINGS_MODULE = "config.settings.test"
pythonpath = ["src"]
testpaths = ["src"]
python_files = ["test_*.py"]
python_classes = ["Test*"]
python_functions = ["test_*"]
addopts = "-v --tb=short --strict-markers"
```

**Decision:**

Accept proposal

---

## MEDIUM Severity

---

### O-3. ARCHITECTURE.md project tree retains `billing/models/base.py` after it was moved to `common/`

**Files:** `.claude/docs/ARCHITECTURE.md` lines 325–333

**Description:**
The rc-18 O-5/C-2 decision moved `TimestampedModel` and `CreatedAtModel` to `apps/common/models/base.py`. The Model Organization section (ARCHITECTURE.md lines 137–148) was correctly updated to reference `apps/common/models/base.py`. However, the Project Structure tree still lists `base.py` under `apps/billing/models/`:

```
├── models/
│   ├── __init__.py
│   ├── billing_accounts.py
│   ├── invoices.py
│   ├── pricing.py
│   ├── resources.py
│   ├── snapshots.py
│   └── base.py           ← should be removed
```

This means the same document contradicts itself: the Model Organization section says base models live in `apps/common/`, but the project tree still shows `base.py` under `apps/billing/`.

**Impact:** An implementer following the project tree will create `apps/billing/models/base.py` instead of using `apps/common/models/base.py`.

**Proposal:** Remove `base.py` from the billing models tree. The Model Organization section is already correct.

**Decision:**

---

### O-4. ARCHITECTURE.md project tree missing `models/` directory under `ingest/` app

**Files:** `.claude/docs/ARCHITECTURE.md` lines 350–361

**Description:**
The ARCHITECTURE.md Model Organization section (line 148) states: "Ingestion event models (`QuotaIngestionEvent`, `VirtualMachineUsageIngestionEvent`) live in `apps/ingest/models/`."

However, the project structure tree for the `ingest/` app shows only:
```
├── ingest/
│   ├── __init__.py
│   ├── apps.py
│   ├── exceptions.py
│   ├── services/
│   ├── api/
│   └── tests/
```

There is no `models/` directory shown. An implementer reading only the project tree would not know where to put the ingestion event models.

**Proposal:** Add `models/` (with `__init__.py` and a `ingestion_events.py` file, or similar) to the `ingest/` app in the project structure tree, consistent with the Model Organization section and the pattern used for `billing/`.

**Decision:**

Accept proposal

---

### O-5. PRP 003 finalize response missing `missing_data_summary` in metadata

**Files:** `docs/PRP/003-invoice-api.prp.md` lines 270–280

**Description:**
The rc-18 O-4 decision established: "`missing_data_summary` — always present in Invoice metadata; `null` when `incomplete=false`, populated when `incomplete=true`."

Following rc-18, both the generate response and the detail response were updated to include `"missing_data_summary": null` in the metadata example. However, the finalize response metadata example (lines 270–280) still does not include `missing_data_summary`:

```json
"metadata": {
    "selected_resource_types": ["storage_hotel"],
    "autofill_missing_days": true,
    "force": false,
    "provisional": false
}
```

Since `missing_data_summary` is always present in all Invoice metadata (per PRP 002), the finalize response must include it too.

**Proposal:** Add `"missing_data_summary": null` to the finalize response metadata example (as the finalize example shows a non-incomplete invoice).

**Decision:**

Accept proposal

---

### O-6. `billing/api/` sub-package layout in ARCHITECTURE.md conflicts with flat file convention in API.md

**Files:** `.claude/docs/ARCHITECTURE.md` lines 342–346, `.claude/docs/API.md` lines 68–88

**Description:**
ARCHITECTURE.md project tree shows `billing/api/` using nested sub-packages:

```
├── api/
│   ├── serializers/    ← sub-package (directory)
│   ├── views/          ← sub-package (directory)
│   ├── urls.py
│   └── filters.py
```

API.md defines the API module layout as flat files:

```
apps/<app>/api/
├── serializers.py
├── views.py
├── urls.py
├── filters.py
└── schema.py
```

API.md does note that "Topic sub-modules such as `invoice_views.py` are permitted when a single `views.py` would become unwieldy," but this implies flat files are the default with sub-modules as a named exception — not default sub-packages.

Additionally, ARCHITECTURE.md omits `schema.py` which API.md documents as a reserved file for reusable schema components.

**Impact:** Implementers will choose different structures. Without a canonical answer, the codebase will be inconsistent across apps.

**Proposal:** Decide on one canonical layout and update both documents to match. Options:
1. Flat files default (per API.md) — simpler, consistent with small apps
2. Sub-packages default (per ARCHITECTURE.md) — better for complex apps like billing

Recommendation: Keep flat files as the default (matching API.md), since ARCHITECTURE.md shows a "conventions and patterns" tree that may have been intended to show the sub-package option as an example for complex apps. Add `schema.py` to ARCHITECTURE.md and note that sub-packages are the exception.

**Decision:**

Accept proposal 1

---

## LOW Severity

---

### O-7. `set-effective-to` overlap error has no documented error code

**Files:** `docs/PRP/005-pricing-api.prp.md` lines 332–341, `.claude/docs/API.md` lines 232–234

**Description:**
The `set-effective-to` endpoint (PRP 005 line 341) documents two 409 cases:
- `price_row_already_closed` — row already has `effective_to` set
- Overlap detected — no error code documented

API.md defines `price_range_overlap` as the overlap code for **ResourcePrice create**. But `set-effective-to` may also trigger an overlap (if setting `effective_to` would create a date range that overlaps another row). The error code for this case on `set-effective-to` is unspecified.

**Proposal:** Document that `price_range_overlap` is also used for overlap conflicts on the `set-effective-to` endpoint, making it consistent with the create endpoint.

**Decision:**

Accept proposal

---

### O-8. BILLING.md line 465 references archived clarification file

**Files:** `.claude/docs/BILLING.md` line 465

**Description:**
BILLING.md line 465 contains: "See `002-resource-models.prp.md` and review-clarifications-10 C-1 for details."

`review-clarifications-10` is an archived file under `.claude/.archive/`. Claude docs should not reference archived files (per `What Claude must not read or check` in CLAUDE.md). This reference is stale and should be removed.

**Proposal:** Remove the "review-clarifications-10 C-1" reference from BILLING.md line 465. The context is already covered by PRP 002.

**Decision:**

Accept proposal

---

### O-9. API.md has no 400 error codes table; error codes for 400 responses are undiscoverable

**Files:** `.claude/docs/API.md` lines 222–248

**Description:**
API.md documents error codes in two tables: 409 Conflict and 422 Unprocessable Entity. There is no 400 Bad Request error codes table.

As a result:
- The soft-delete 400 code (`soft_delete_precondition_failed`, raised by O-1 above) has no home in the registry once moved out of the 409 table.
- Other potential 400 domain codes (e.g., `invalid_status_transition`, `active_to_before_active_from`) are not centrally documented.
- Implementers must hunt through individual PRP documents to discover 400 error codes.

**Proposal:** Add a **400 Bad Request** error codes table to API.md. Seed it with the known named 400 codes:
- `soft_delete_precondition_failed` — Resource soft-delete — Resource is not in RETIRED status or `active_to` is not set

Document a convention: generic field-level validation errors use `validation_error` (already shown in the 400 example); named domain-specific 400 codes are registered in the table.

**Decision:**

Accept proposal

---

### O-10. `billing/models/constants.py` vs `billing/resource_types.py` naming inconsistency

**Files:** `.claude/docs/ARCHITECTURE.md` line 323, `docs/PRP/001-billing-engine.prp.md` line 127

**Description:**
ARCHITECTURE.md project tree shows `apps/billing/constants.py`. PRP 001 (line 127) says: "Code location: a choices class or constant module in `apps/billing/` (e.g., `apps/billing/resource_types.py`)."

The two documents suggest different file names for the same module: `constants.py` vs `resource_types.py`. An implementer must choose one.

**Proposal:** Decide on the canonical filename. Recommendation: `resource_types.py` is more descriptive (its sole responsibility is the resource type registry). `constants.py` implies it will accumulate unrelated constants over time. Update ARCHITECTURE.md to match PRP 001's suggestion.

**Decision:**

Accept proposal

---

## Pre-Implementation Checklist

### C-1. Fix `soft_delete_precondition_failed` table placement before implementing soft-delete (O-1)

The wrong HTTP status code (409 vs 400) will be implemented if this is not corrected first.

**Decision:**

Accept proposal

---

### C-2. Update `pyproject.toml` for `src/` layout before running any tests (O-2)

No pytest test can pass without `pythonpath = ["src"]` and `where = ["src"]`.

**Decision:**

Accept proposal

---

### C-3. Clean up ARCHITECTURE.md project tree (O-3, O-4)

- Remove `base.py` from `billing/models/`
- Add `models/` to `ingest/`

**Decision:**

Accept proposal

---

### C-4. Decide on flat files vs. sub-packages for `api/` layout (O-6)

Must be resolved before writing the first API file, or different apps will use different structures.

**Decision:**

Flat packages for now

---

### C-5. Decide on `resource_types.py` vs `constants.py` for the resource type module (O-10)

Minor but must be consistent from the first file created.

**Decision:**

Choose `resource_types.py` for clarity

---

## Issue Summary

| Severity | Issues |
|----------|--------|
| HIGH     | O-1, O-2 |
| MEDIUM   | O-3, O-4, O-5, O-6 |
| LOW      | O-7, O-8, O-9, O-10 |

The two HIGH issues (wrong HTTP status code table placement and broken `pyproject.toml` for `src/` layout) are implementation-blocking and must be resolved before any code is written.
