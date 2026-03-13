# Project Clarification Questions

This file tracks all ambiguity questions raised before implementation,
along with their answers. Unanswered questions are marked as PENDING.

---

## Q1 — VirtualMachine v1 billing strategy

**Status:** ANSWERED

**Question:**
The VM PRP explicitly leaves this unresolved:
> "The exact v1 pricing strategy must define whether billing is based on one combined capacity formula or separate dimensions."

Options:
- (a) Per-VM flat rate — one ResourcePrice per VM, billed as `1 unit × price_per_year / days_in_year`
- (b) Per-dimension — separate ResourcePrice rows for cpu, ram, disk, each yielding a daily cost, summed per VM per day
- (c) Something else

**Answer:** (b) Per-dimension billing.
Formula per dimension per day: `quantity × price_per_unit_year / days_in_year(day)`.
Total daily cost per VM = sum of all dimension costs.

---

## Q2 — Database connection parameters

**Status:** ANSWERED

**Question:**
No settings files or `.env` existed. What are the PostgreSQL connection parameters?

**Answer:** Database is already available. A `.env` file has been added to the project root.

---

## Q3 — Invoice number format

**Status:** ANSWERED

**Question:**
`invoice_number` is on the Invoice model but the format was unspecified.

Options:
- (a) Auto-incrementing integer
- (b) UUID
- (c) Formatted string

**Answer:** (c) Formatted string with pattern `INV-YYYY-mm-NNNN`.
Example: `INV-2026-02-0004`.

---

## Q4 — Build scope / where to start

**Status:** PENDING

**Question:**
Should implementation be:
- (a) Everything end-to-end: models → migrations → services → API → tests (full v1)
- (b) A specific layer or feature first (e.g., models only, or billing + StorageHotel first)

---

## Q5 — ResourcePrice model structure for VM dimensions

**Status:** PENDING

**Question:**
With per-dimension billing, `resource_type` alone cannot distinguish cpu from ram from disk.
How should they be differentiated in `ResourcePrice`?

Options:
- (a) Add a `pricing_dimension` field (e.g., `"cpu_count"`, `"ram_mb"`, `"disks_total_gb"`) —
  3 `ResourcePrice` rows per VM per price list
- (b) Something else

---

## Q6 — InvoiceDailyCost granularity for VM

**Status:** PENDING

**Question:**
When billing a VM per dimension, should `InvoiceDailyCost` produce:
- (a) One row per VM per day (aggregated total of all dimension costs)
- (b) One row per dimension per day (3 rows per VM per day: cpu, ram, disk)

---

## Q7 — VM discount model

**Status:** PENDING

**Question:**
`ResourcePrice` has `discount_threshold` and `discount_price_nok_per_unit_year`.
For VM per-dimension billing, does the discount apply:
- (a) Per dimension independently (e.g., if `cpu_count >= threshold`, apply discounted cpu price)
- (b) No discounts for VM in v1 (discount fields on VM dimension rows are always null/unused)
- (c) Something else

---

## Q8 — Invoice number sequence scope

**Status:** PENDING

**Question:**
For `INV-2026-02-0004`, is the 4-digit counter scoped:
- (a) Globally per month (all billing accounts share the same monthly sequence)
- (b) Per billing account per month

---

## Q9 — `.env` loading in Django settings

**Status:** PENDING

**Question:**
No env-loading library is in `pyproject.toml`. How should the `.env` file be read in settings?
- (a) Add a dependency: `python-decouple`, `django-environ`, or `python-dotenv`
- (b) Use `os.environ.get(...)` directly with no extra library
