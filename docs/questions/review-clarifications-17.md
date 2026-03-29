# Review Clarifications 17

Architecture review round 17 — exhaustive audit after round 16.
Edit each `**Decision:**` line with your answer.

---

## HIGH

### O-1. Ingestion event models use `on_delete=CASCADE` — silent loss of audit records on hard-delete

**Files:** `docs/PRP/resources/storage-hotel.prp.md` (line 102), `docs/PRP/resources/virtual-machine.prp.md` (line 98)

Both `QuotaIngestionEvent` and `VirtualMachineUsageIngestionEvent` have `on_delete=CASCADE` for the FK to the resource. Resources are only soft-deleted in v1, so `CASCADE` should never trigger. However, if a resource is accidentally hard-deleted (e.g., via Django admin or a future cleanup script), all ingestion events would be silently lost.

In a financial audit system, losing ingestion events is a serious integrity risk. `on_delete=PROTECT` would prevent accidental resource hard-deletion if any events exist.

Options:
- **(a)** Keep `CASCADE` with a note that it is a safety-net and should never trigger in normal v1 operation. The soft-delete mechanism is the only removal path.
- **(b)** Change to `on_delete=PROTECT` to prevent silent data loss if a resource is ever hard-deleted.

Proposal: **(a)** with an explicit note — since resources are never hard-deleted in v1, `CASCADE` is a protective fallback, not expected operational behavior. Document this clearly.

**Decision:**

---

### O-2. Explicit resource ownership validation: which manager to use

**Files:** `docs/PRP/003-invoice-api.prp.md` (line 324)

For `explicit_resources` selection, the billing engine must verify each resource belongs to the specified `billing_account`. The spec does not say which manager to use:

- Default manager (excludes soft-deleted): a soft-deleted resource appears as "not found," which is misleading — it exists but was soft-deleted.
- `billing_objects` manager (includes soft-deleted): a historically billable soft-deleted resource can be explicitly selected for a historical period invoice.

Additionally, the spec does not distinguish between:
- Resource does not exist at all → 400 error
- Resource exists but belongs to a different billing account → 400 error

Proposal: Specify that explicit resource ownership validation uses `billing_objects` (includes soft-deleted). A non-existent resource returns 400 with `resource_not_found`. A resource belonging to a different billing account returns 400 with `resource_wrong_billing_account`.

**Decision:**

---

### O-3. 400 error response format: DRF validation vs structured domain errors

**Files:** `docs/PRP/003-invoice-api.prp.md` (lines 310-374)

The spec provides 409 and 422 examples using the structured `{code, message, details}` format. It does not specify what format 400 responses use. There are two types of 400 errors:

1. Field-level validation (e.g., missing required field, invalid date format) — DRF returns `{"field_name": ["error message"]}` by default.
2. Semantic validation (e.g., `selection_scope` conflict with provided fields) — these use the structured `{code, message, details}` format.

Without a rule, implementers may mix formats, producing inconsistent API responses.

Proposal: Specify that ALL 400 responses from the generate endpoint use the structured `{code, message, details}` format. Field-level DRF validation errors are wrapped into this format:
```json
{
  "code": "validation_error",
  "message": "Invalid request parameters.",
  "details": {"period_start": ["This field is required."]}
}
```

**Decision:**

---

### O-4. Duplicate entry validation for `explicit_resources` and `resource_types` not specified

**Files:** `docs/PRP/003-invoice-api.prp.md` (line 323)

The spec says "the same resource is selected more than once" should fail, but does not specify what "same resource" means for each scope:

- `explicit_resources`: duplicate `(resource_type, resource_id)` pairs in the list
- `resource_types`: duplicate resource type strings in the list

Both should be validated. Currently unclear what error to return.

Proposal:
- For `explicit_resources`: if the same `(resource_type, resource_id)` pair appears more than once, return 400 with `code: "duplicate_resource_selection"`.
- For `resource_types`: if the same resource type string appears more than once, return 400 with `code: "duplicate_resource_type"`.

**Decision:**

---

## MEDIUM

### O-5. FK references in API responses: integer PK vs nested object — no global rule

**Files:** `docs/PRP/003-invoice-api.prp.md` (lines 53-56), `docs/PRP/005-pricing-api.prp.md` (lines 63-84)

Invoice API responses show `"billing_account": "<id>"`. BillingAccount API responses show the full object. Resource API responses show `"billing_account": 1`. The consistent pattern is integer PK only, but no global implementation rule is stated.

An implementer might nest related objects in some responses without realizing the project convention.

Proposal: Add a global rule to `API.md`: "All foreign key references in API responses are serialized as the integer primary key of the related object. Nested object serialization is not used unless explicitly documented for a specific endpoint."

**Decision:**

---

### O-6. `InvoiceDailyCost` unique constraint references `invoice_id` but Django uses model field name `invoice`

**Files:** `docs/PRP/002-resource-models.prp.md` (line 439)

The constraint is written as `(invoice_id, resource_type, resource_id, date) UNIQUE`. In Django's `UniqueConstraint`, field names reference the model field (`invoice`), not the database column (`invoice_id`). Django auto-appends `_id` for FK columns.

The implementation difference:
```python
# Correct Django syntax:
UniqueConstraint(fields=["invoice", "resource_type", "resource_id", "date"], name="...")
# The above creates the DB constraint on (invoice_id, resource_type, resource_id, date)
```

Proposal: Add a note to the InvoiceDailyCost constraints section: "In Django, the `UniqueConstraint` uses the model field name `invoice`, which Django maps to the database column `invoice_id`."

**Decision:**

---

## LOW

### O-7. `PriceList` uses `TimestampedModel` — confirm as intentional

**Files:** `docs/PRP/002-resource-models.prp.md` (lines 39-58), `docs/PRP/005-pricing-api.prp.md` (lines 190-199)

`PriceList` uses `TimestampedModel` (has both `created_at` and `updated_at`). The only patchable field is `name`. Since `name` can change, `updated_at` is justified. This is internally consistent.

Proposal: No change needed. Add a comment confirming this is intentional: "`PriceList` uses `TimestampedModel` because `name` is patchable."

**Decision:**

---

### O-8. `InvoiceLine` uses `CreatedAtModel` — confirm as v1 design

**Files:** `docs/PRP/002-resource-models.prp.md` (line 340)

`InvoiceLine` uses `CreatedAtModel` (no `updated_at`). In v1, draft replacement deletes and recreates all lines. In a future v2 recalculation feature, lines may need to be updated in-place rather than deleted and recreated.

Proposal: No change for v1. Add a note: "If v2 recalculation needs in-place line updates, `InvoiceLine` may need migration to `TimestampedModel`."

**Decision:**

---

### O-9. `InvoiceLine` and `InvoiceDailyCost` `currency` fields — service-layer propagation confirmation

**Files:** `docs/PRP/002-resource-models.prp.md` (lines 315-316, 412, 446)

All three models (`Invoice`, `InvoiceLine`, `InvoiceDailyCost`) have a `currency` field that must always match. In v1 all are `"NOK"`. The service layer must propagate `Invoice.currency` to every child row during generation. No database trigger or constraint enforces cross-table currency consistency.

Proposal: No change needed. Add a comment: "Currency consistency across `Invoice`, `InvoiceLine`, and `InvoiceDailyCost` is enforced by the generation service. The service must propagate `Invoice.currency` to all child rows."

**Decision:**

---

### O-10. `StorageHotel.quota_unit` not stored in `StorageHotelDailyQuota` — historical unit tracking gap

**Files:** `docs/PRP/resources/storage-hotel.prp.md` (lines 56-78)

`StorageHotelDailyQuota` stores `quota_raw` but not the `quota_unit` that was in effect when the snapshot was taken. `quota_unit` lives on `StorageHotel` and is patchable. If changed after snapshots are ingested, the billing engine interprets historical `quota_raw` values using the new unit, producing incorrect billing.

This is acknowledged in the `quota_unit correction warning` in the PATCH endpoint spec. The billing engine reads `quota_unit` from the live `StorageHotel` resource.

Proposal: No specification change. Add a developer note: "If historical `quota_unit` tracking becomes needed, `StorageHotelDailyQuota` would need a `quota_unit` field. For v1, the ingestion event's `raw_payload` provides the only historical unit record."

**Decision:**

---

### O-11. `BillingAccount` API has no endpoint to list resources belonging to the account

**Files:** `docs/PRP/005-pricing-api.prp.md` (lines 95-106)

The `GET /api/v1/billing-accounts/{id}/` endpoint returns only the `BillingAccount` object. There is no cross-resource listing — an operator must call each resource type's list endpoint with `?billing_account=X` to discover all resources for an account.

Proposal: This is acceptable for v1. No change needed. In v2, a cross-resource listing endpoint or resource counts in the BillingAccount detail response could be added.

**Decision:**

---

### O-12. `InvoiceLine.resource_id` and `InvoiceDailyCost.resource_id` typed as `PositiveIntegerField` — confirm intentional

**Files:** `docs/PRP/002-resource-models.prp.md` (lines 409, 445)

Both fields are `PositiveIntegerField`, which adds a `CHECK >= 0` constraint. Django's default `AutoField` uses a signed integer (auto-increment never produces negatives). Using `PositiveIntegerField` for these non-FK fields that reference resource PKs adds a defensive constraint.

Proposal: No change. Confirm as intentional: "`resource_id` is `PositiveIntegerField` to prevent accidentally storing negative IDs. It cannot be a FK since multiple resource types share the same field."

**Decision:**

---

## PRE-DEVELOPMENT CONSIDERATIONS

### C-1. Django project skeleton must be created first

**Category:** Architecture Decision

The repository has `pyproject.toml` and pre-commit config but no Django project skeleton. Before any model or service code can be written, create:

- `config/settings/base.py`, `dev.py`, `test.py`
- `config/urls.py`, `wsgi.py`, `asgi.py`
- `manage.py`
- `apps/billing/__init__.py`, `apps/billing/apps.py`
- `apps/ingest/__init__.py`, `apps/ingest/apps.py`
- `INSTALLED_APPS`, `REST_FRAMEWORK`, `DEFAULT_AUTO_FIELD = "django.db.models.BigAutoField"`
- `TIME_ZONE = "Europe/Oslo"`, `USE_TZ = True`

Verify `uv run python manage.py check` passes before writing any model code.

**Decision:**

---

### C-2. Model creation and migration order

**Category:** Data Migration Risk

Models have dependency chains:

```
TimestampedModel / CreatedAtModel (abstract, no migration)
  -> PriceList
  -> BillingAccountBase (abstract) -> BillingAccount
  -> ResourceModel (abstract) -> StorageHotel / VirtualMachine (depend on BillingAccount)
  -> ResourcePrice (depends on PriceList)
  -> Invoice (depends on BillingAccount)
  -> InvoiceLine (depends on Invoice)
  -> InvoiceDailyCost (depends on Invoice)
  -> StorageHotelDailyQuota (depends on StorageHotel)
  -> VirtualMachineDailyUsage (depends on VirtualMachine)
  -> QuotaIngestionEvent (depends on StorageHotel, lives in apps/ingest/)
  -> VirtualMachineUsageIngestionEvent (depends on VirtualMachine, lives in apps/ingest/)
```

`apps/ingest/` models have FKs to `apps/billing/` models. This creates a cross-app dependency.

Recommendation: Write all `apps/billing/` models first, run `makemigrations billing`. Then write `apps/ingest/` models and run `makemigrations ingest`. Do not attempt both in a single `makemigrations` call.

**Decision:**

---

### C-3. Test factory strategy: `factory_boy` vs plain functions vs pytest fixtures

**Category:** Testing Strategy

The project needs factory functions or classes for test data. Options:

1. `factory_boy` with Django integration (not currently in `pyproject.toml`)
2. Plain Python factory functions (`create_billing_account(**overrides)`)
3. Pytest fixtures

`TESTING.md` mentions "small resource factories" and "explicit daily snapshot creation." Plain factory functions align with this emphasis.

Recommendation: Use plain factory functions in `conftest.py` per app's test directory. Do not add `factory_boy` unless explicitly required.

**Decision:**

---

### C-4. Verify pre-commit hooks pass before writing any Python code

**Category:** Django Convention

The `.pre-commit-config.yaml` runs `ruff`, `ruff-format`, `mypy`, and `django-doctor`. `mypy` requires `DJANGO_SETTINGS_MODULE`; `django-doctor` requires Django to be importable. Until the project skeleton exists, these hooks will fail on any Python file.

Recommendation: Create the project skeleton (C-1) and verify `pre-commit run --all-files` passes before writing model code.

**Decision:**

---

### C-5. Service module organization

**Category:** Architecture Decision

The billing app needs multiple services. `ARCHITECTURE.md` specifies `apps/<app>/services/` as the location. Given complexity (invoice generation, finalization, price resolution, resource selection, daily cost), a package is appropriate.

Proposed structure:
```
apps/billing/services/
  __init__.py
  invoice_generation.py
  invoice_finalization.py
  price_resolution.py
  resource_selection.py
  daily_cost.py

apps/ingest/services/
  __init__.py
  quota_ingestion.py
  vm_usage_ingestion.py
```

**Decision:**

---

### C-6. `DEFAULT_AUTO_FIELD` setting

**Category:** Django Convention

Django 5.2 defaults to `BigAutoField` for new projects. The PRPs say all PKs are `integer PK` but do not specify `AutoField` vs `BigAutoField`.

Recommendation: Set `DEFAULT_AUTO_FIELD = "django.db.models.BigAutoField"` in `base.py`. This is the Django 5.2 convention and prevents future migration pain.

**Decision:**

---

### C-7. `REST_FRAMEWORK` settings before writing any serializer

**Category:** Architecture Decision

The project needs DRF settings for pagination, authentication, permissions, renderers, and Decimal serialization. Deciding these upfront prevents inconsistency.

Recommended configuration:

```python
REST_FRAMEWORK = {
    "DEFAULT_PAGINATION_CLASS": "rest_framework.pagination.PageNumberPagination",
    "PAGE_SIZE": 50,
    "DEFAULT_PERMISSION_CLASSES": ["rest_framework.permissions.AllowAny"],
    "DEFAULT_AUTHENTICATION_CLASSES": [],
    "COERCE_DECIMAL_TO_STRING": True,
    "DEFAULT_SCHEMA_CLASS": "drf_spectacular.openapi.AutoSchema",
}
```

Note: `COERCE_DECIMAL_TO_STRING = True` ensures `DecimalField` values in serializers are rendered as strings in JSON, preserving precision.

**Decision:**

---
