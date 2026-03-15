# Project Overview

this project is a django rest apI that generates invoices for company IT resources.

Core entities:
- BillingAccount
- Resource models
- PriceList / ResourcePrice
- Invoice / InvoiceLine
- Daily usage snapshots

Core rules:
- Billing is computed per resource per day
- Pricing is effective-dated
- Snapshot data is immutable
- Finalized invoices are immutable

Detailed product rules live in docs/PRP/.

---

## Implementation Status

No Django project has been developed yet.

The only file that exists at the project root (besides documentation) is `pyproject.toml`, which defines the chosen tools, plugins, and dependencies for when implementation begins.

Do not assume any Django app, settings, migrations, or tests exist. Everything must be created from scratch.
