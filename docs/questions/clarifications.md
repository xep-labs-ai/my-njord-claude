# Project Clarification Questions

This file tracks all ambiguity questions raised before implementation,
along with their answers. Unanswered questions are marked as PENDING.

---

## Q1 — VirtualMachine v1 billing strategy

**Status:** ANSWERED

**Answer:** VM v1 billing is per-dimension (cpu_count, ram_gb, disk_gb), with 3 InvoiceDailyCost rows per VM per day. Discounts apply per dimension independently (resolved via Q6 and Q7).

**Question:**
The VM PRP explicitly leaves this unresolved:
> "The exact v1 pricing strategy must define whether billing is based on one combined capacity formula or separate dimensions."


---

## Q3 — Invoice number format

**Status:** ANSWERED

**Question:**
`invoice_number` is on the Invoice model but the format was unspecified.

Options:
- (a) Auto-incrementing integer
- (b) UUID
- (c) Formatted string

**Answer:** (c) Formatted string with pattern `INV-YYYY-mm-NNNNN`.
Example: `INV-2026-02-00004`. (5-digit counter, global monthly sequence)

---

## Q4 — Build scope / where to start

**Status:** ANSWERED

**Question:**
Should implementation be:
- (b) A specific layer or feature first (e.g., models only, or billing + StorageHotel first)

---

## Q6 — InvoiceDailyCost granularity for VM

**Status:** ANSWERED

**Question:**
When billing a VM per dimension, should `InvoiceDailyCost` produce:
- (b) One row per dimension per day (3 rows per VM per day: cpu, ram, disk)

---

## Q7 — VM discount model

**Status:** ANSWERED

**Question:**
`ResourcePrice` has `discount_threshold`
For VM per-dimension billing, does the discount apply:
- (a) Per dimension independently (e.g., if `cpu_count >= threshold`, apply discounted cpu price)

---

## Q8 — Invoice number sequence scope

**Status:** ANSWERED

**Answer:** Global per month. All billing accounts share one monthly sequence. Format updated to INV-YYYY-mm-NNNNN (5-digit counter) to allow more than 9999 invoices per month. Unique index on Invoice: (invoice_number) globally unique.

**Question:**
For `INV-2026-02-0004`, is the 4-digit counter scoped:
- (a) Globally per month (all billing accounts share the same monthly sequence)
- (b) Per billing account per month

---

## Q9 — `.env` loading in Django settings

**Status:** ANSWERED

**Question:**
No env-loading library is in `pyproject.toml`. How should the `.env` file be read in settings?
- (a) Use `os.environ.get(...)` directly with no extra library
