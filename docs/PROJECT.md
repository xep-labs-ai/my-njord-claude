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
