# Architecture

## Doc Purpose
Describe the high-level architecture of the Django Invoice API and how the main layers collaborate.

## Read this doc when
- designing new services or modules
- understanding how billing workflows are orchestrated
- deciding where business logic should live
- reasoning about system structure

## Do not read this doc when
- implementing API endpoints (see API.md)
- writing tests (see TESTING.md)
- implementing financial rules (see BILLING.md)

## Purpose

This document defines the high-level architecture of the Invoice API.

It describes system shape, application boundaries, and code organization rules.
It does not define detailed billing rules or endpoint conventions.

Related documents:

- `.claude/docs/PROJECT.md`
- `.claude/docs/API.md`
- `.claude/docs/BILLING.md`

---

## Architectural Style

This project uses a modular monolith architecture.

That means:

- one Django service
- multiple internal apps with explicit boundaries
- one PostgreSQL database
- shared transactional consistency
- service-layer orchestration for multi-step workflows

This is the preferred starting point because:

- the domain is still evolving
- billing rules require strong consistency
- invoice generation is transactional
- new resource types will be added over time
- clean internal boundaries are more important than early distribution

---

## System Shape

The system is an API-only Django application that manages:

- billing accounts
- billable resources
- daily usage snapshots
- pricing
- invoice generation
- invoice persistence

The billing model is resource-centric:

- resources belong to a billing lifecycle
- resources produce daily billing inputs
- pricing is applied per day using effective-dated rules
- invoices are generated from reproducible daily calculations

---

## Main Application Boundaries

### `billing`

Owns the core billing domain.

Typical responsibilities:

- `BillingAccount`
- `PriceList`
- `ResourcePrice`
- `Invoice`
- `InvoiceLine`
- `InvoiceDailyCost`
- resource models
- billing services
- invoice lifecycle

This app owns the financial meaning of the system.

### `ingest`

Owns ingestion concerns.

Typical responsibilities:

- ingestion event models
- inbound usage/quota APIs
- payload validation and normalization
- duplicate detection
- raw payload preservation for auditing

This app owns how external systems submit billing input data.

---

## Resource Model Strategy

Billable infrastructure resources follow a shared contract.

Each resource type should:

- belong to a `BillingAccount`, or remain explicitly unassigned
- have a lifecycle status
- define its own daily snapshot model
- define its own ingestion event model when external data is pushed in
- participate in billing only when domain rules allow it

Examples of resource types:

- `StorageHotel`
- `VirtualMachine`

Future resource types should extend the same architectural pattern rather than inventing a separate billing flow.

---

## Model Organization

All domain models live in `apps/billing/models/` as a Python package. Organize into sub-modules:

- `apps/billing/models/base.py` — TimestampedModel, CreatedAtModel, BillingAccountBase (abstract)
- `apps/billing/models/billing_accounts.py` — BillingAccountBase (abstract), BillingAccount (concrete UiO implementation)
- `apps/billing/models/pricing.py` — PriceList, ResourcePrice
- `apps/billing/models/resources.py` — ResourceModel (abstract), StorageHotel, VirtualMachine
- `apps/billing/models/snapshots.py` — StorageHotelDailyQuota, VirtualMachineDailyUsage
- `apps/billing/models/invoices.py` — Invoice, InvoiceLine, InvoiceDailyCost
- `apps/billing/models/__init__.py` — exports all models

Ingestion event models (QuotaIngestionEvent, VirtualMachineUsageIngestionEvent) live in `apps/ingest/models/`.

Resource types (StorageHotel, VirtualMachine) do NOT get their own apps — they live in `apps/billing/`.

---

## Internal Code Layers

The codebase should remain simple, explicit, and testable.

### Models

Use Django models for:

- persistence
- database constraints
- relationships
- immutable billing snapshots where required

### Serializers

Use DRF serializers for:

- request validation
- response rendering
- explicit API schemas

Serializers must not contain multi-step domain workflows.

### Services

Use service modules for multi-step business operations.

Examples:

- invoice generation
- invoice recalculation
- invoice finalization
- usage ingestion
- quota ingestion

Services coordinate model updates inside clear transaction boundaries.

### Selectors

Use selector modules for read-oriented query logic.

Examples:

- billable resources for a period
- effective price lookup
- invoice detail queries
- reporting-oriented query composition

Selectors keep read complexity out of views and services.

### Views

Use DRF viewsets for standard CRUD endpoints.

Use explicit action endpoints or API views for domain workflows such as:

- generate invoice
- recalculate invoice
- finalize invoice
- ingest usage snapshots

Views should stay thin and delegate domain work to services.

---

## Transaction Boundaries

Use database transactions for workflows that create or update multiple related rows.

Examples:

- ingestion of daily snapshots
- invoice generation
- invoice recalculation
- invoice finalization

These workflows must either:

- complete fully
- or roll back fully

Partially created invoice state is not acceptable.

---

## State Ownership

### Resource lifecycle

Resource state determines whether a resource can participate in billing.

Shared lifecycle states are defined by the resource model layer.
Billing eligibility rules are defined by the billing domain.

### Invoice lifecycle

Invoice state controls allowed operations.

Expected invoice states:

- `draft`
- `finalized`

The billing domain owns transition rules and immutability requirements.

---

## Architectural Rules

1. Keep business workflows out of views.
2. Keep multi-step domain logic out of serializers.
3. Do not hide billing workflows inside model `save()` overrides.
4. Use explicit database constraints for data integrity.
5. Keep finalized invoice data immutable.
6. Preserve raw ingestion payloads when ingestion is external.
7. Prefer new effective-dated records over mutating historical pricing state.

---

## Why Not Microservices

Do not split this system into microservices at this stage.

Reasons:

- billing and pricing need strong consistency
- invoice generation is transactional
- operational complexity would increase without clear benefit
- expected scale fits comfortably within a modular monolith

The priority is clean internal boundaries, not early service separation.

---

## Evolution Path

This architecture should support future additions such as:

- more resource types
- richer usage billing
- scheduled invoice jobs
- PDF generation
- export integrations
- stronger auth and permission layers

These should be added by extending existing boundaries, not by bypassing them.
