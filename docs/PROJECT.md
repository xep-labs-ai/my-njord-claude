# Project Overview

## Doc Purpose

system purpose, core domain entities, billing context, supported resource types, shared terminology

## Read this document when

you need to understand the project domain, resource types, billing concepts, or shared terminology

## Do not read this document when

you are making isolated test, formatting, or tooling changes with no domain impact

---

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

Design and specification is complete. PRPs (docs/PRP/), clarification rounds 1-12, and project tooling (pyproject.toml) all exist.

No Django application code has been written yet. The task ahead is to build the Django app from the PRPs.

Do not assume any Django app, settings, migrations, or tests exist. Everything must be created from scratch based on the PRPs.
