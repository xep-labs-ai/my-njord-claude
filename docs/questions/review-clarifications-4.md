# Documentation Review — Clarification Questions (Round 4)

This file contains only questions requiring a decision. The propagation misses from round 3 are being applied separately.

---

### CQ1 — `005-pricing-api.prp.md` and `BillingAccount` API spec

**Status:** ANSWERED

**Problem:**
Round 3 decided:
- `ResourcePrice` managed via API nested under PriceList (`POST/GET/PATCH /api/v1/price-lists/{id}/resource-prices/`)
- `BillingAccount` needs CRUD API endpoints
- A new `docs/PRP/005-pricing-api.prp.md` should be created

Neither spec exists. Three core entities have no HTTP contract.

**Proposal:**
Create `docs/PRP/005-pricing-api.prp.md` covering:

**PriceList:**
- `POST /api/v1/price-lists/`
- `GET /api/v1/price-lists/`
- `GET /api/v1/price-lists/{id}/`
- `PATCH /api/v1/price-lists/{id}/`

**ResourcePrice** (nested under PriceList):
- `POST /api/v1/price-lists/{price_list_id}/resource-prices/`
- `GET /api/v1/price-lists/{price_list_id}/resource-prices/`
- `GET /api/v1/price-lists/{price_list_id}/resource-prices/{id}/`
- No PATCH (see CQ2)

**BillingAccount:**
- `POST /api/v1/billing-accounts/`
- `GET /api/v1/billing-accounts/`
- `GET /api/v1/billing-accounts/{id}/`
- `PATCH /api/v1/billing-accounts/{id}/`

**Answer:** accept proposal

---

### CQ2 — ResourcePrice: PATCH endpoint vs "price rows never updated" rule

**Status:** ANSWERED

**Problem:**
`001-billing-engine.prp.md` states: "price rows **never updated** — new pricing → insert new rows with adjusted effective dates."

Round 3 (BQ9) decided there should be a `PATCH` endpoint for ResourcePrice. These directly contradict each other.

**Options:**
- (a) No PATCH for ResourcePrice — only POST and GET. Corrections require creating a new row with adjusted `effective_from`/`effective_to`. Consistent with the immutability rule.
- (b) Allow PATCH only for rows that have never been referenced by any `InvoiceDailyCost` — once used in billing the row becomes immutable.
- (c) Allow PATCH on non-billing fields only (e.g. description), never on price values or effective dates.

**Proposal:** Option (a). Keeping ResourcePrice immutable is simpler, safer, and consistent with the existing billing invariant. Document the correction workflow: to change a price, set `effective_to` on the old row and create a new row.

**Answer:** accept proposal a

---

### CQ13 — `ResourcePrice` field types and precision

**Status:** ANSWERED

**Problem:**
`001-billing-engine.prp.md` lists ResourcePrice fields but no Django field types, precision, or nullability. Migrations cannot be written.

**Proposal:**
- `price_list` — FK to PriceList, required
- `resource_type` — CharField(max_length=50), required
- `pricing_dimension` — CharField(max_length=50), required
- `price_per_unit_year` — DecimalField(max_digits=14, decimal_places=4), required
- `price_currency` — CharField(max_length=3, default="NOK")
- `discount_price_per_unit_year` — DecimalField(max_digits=14, decimal_places=4), nullable (null = no discount price)
- `discount_threshold_quantity` — DecimalField(max_digits=14, decimal_places=4), nullable (null = discount does not apply)
- `effective_from` — DateField, required
- `effective_to` — DateField, nullable (null = open-ended)
- `created_at` — DateTimeField, auto_now_add

**Answer:** accept proposal

---

### CQ14 — `Invoice` field types and precision

**Status:** ANSWERED

**Problem:**
`002-resource-models.prp.md` lists Invoice fields but several have no type/precision. Migrations cannot be written.

**Proposal:**
- `invoice_number` — CharField(max_length=20), nullable, unique when set (fits `INV-YYYY-mm-NNNNN`)
- `billing_account` — FK to BillingAccount, required
- `period_start` — DateField, required
- `period_end` — DateField, required
- `currency` — CharField(max_length=3, default="NOK")
- `status` — CharField(max_length=20, choices=["draft","finalized"], default="draft")
- `total_amount` — DecimalField(max_digits=12, decimal_places=2), nullable (null until finalized)
- `metadata` — JSONField(default=dict)
- `finalized_at` — DateTimeField, nullable
- `created_at` / `updated_at` — DateTimeField, auto

**Answer:** accept proposal

---

### CQ15 — `InvoiceLine` and `InvoiceDailyCost` field types and precision

**Status:** ANSWERED

**Problem:**
Financial field precision on InvoiceLine and InvoiceDailyCost is unspecified. These are full-precision fields (not rounded) so they need more decimal places than `Invoice.total_amount`.

**Proposal:**

**InvoiceLine:**
- `invoice` — FK to Invoice, required
- `resource_type` — CharField(max_length=50), required
- `resource_id` — PositiveIntegerField, required
- `description` — CharField(max_length=255), optional
- `total_cost` — DecimalField(max_digits=14, decimal_places=6), required (full precision)
- `metadata` — JSONField(default=dict)

**InvoiceDailyCost:**
- `invoice` — FK to Invoice, required
- `resource_type` — CharField(max_length=50), required
- `resource_id` — PositiveIntegerField, required
- `pricing_dimension` — CharField(max_length=50), required
- `date` — DateField, required
- `daily_cost` — DecimalField(max_digits=14, decimal_places=6), required (full precision)
- `metadata` — JSONField(default=dict)
- Unique constraint: `(invoice, resource_type, resource_id, date, pricing_dimension)`

**Answer:** accept proposal

---

### CQ16 — Resource status lifecycle transitions

**Status:** ANSWERED

**Problem:**
Resources are created as `UNASSIGNED` (per `004-resource-api.prp.md`). The path from `UNASSIGNED` → `ACTIVE` → `RETIRED` happens via PATCH, but:
- Which transitions are allowed?
- Can `RETIRED` go back to `ACTIVE`?
    - Must `active_to` be set when transitioning to `RETIRED`?
- Should `billing_account` be required on creation, or optional (to allow truly unassigned resources)?

**Proposal:**

Allowed transitions:
- `UNASSIGNED` → `ACTIVE` (via PATCH, requires `active_from` and `billing_account` to be set)
- `ACTIVE` → `RETIRED` (via PATCH, must set `active_to`)
- `RETIRED` → `ACTIVE` — not allowed (prevents accidental rebilling)

`billing_account` on creation: optional. A resource can be created without a billing account and stay `UNASSIGNED` until assigned.

**Answer:** Accept proposal

---
