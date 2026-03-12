# API Conventions

## Doc Purpose
Rules for implementing and modifying REST API endpoints under `/api/v1/`.

## Read this doc when
- creating or updating DRF endpoints
- adding serializers, viewsets, routers, or schema annotations
- deciding status code behavior for API operations

## Do not read this doc when
- implementing billing calculations
- deciding repository file placement
- writing general pytest strategy

## Purpose

This document defines the architectural conventions for the Invoice API.

Implementation workflows for endpoints are defined in the Claude skill:

skills/django-api-endpoint-pattern

This document focuses only on API design rules.

---

## Stack

The API uses:

- Django REST Framework (`rest_framework`)
- `drf-spectacular`
- `django-filter`

---

## Base Path and Versioning

All API endpoints must live under:

/api/v1/

Endpoints must always be versioned.

---

## Endpoint Style

Default pattern:

- ModelSerializer
- ModelViewSet or ReadOnlyModelViewSet
- router registration

Use `APIView` or custom views only when the endpoint does not fit CRUD semantics.

Examples include:

- ingestion workflows
- invoice generation
- reporting endpoints

---

## API Module Layout

Each Django app exposing API endpoints should use a consistent API package layout.

Preferred structure:

apps/<app>/api/
├── serializers.py
├── views.py
├── urls.py
├── filters.py
└── schema.py

Responsibilities:

- serializers.py → DRF serializers
- views.py → viewsets and API views
- urls.py → router registration and explicit endpoint paths
- filters.py → django-filter FilterSet classes
- schema.py → reusable drf-spectacular schema components (reserved for large or complex shared annotations)

Topic sub-modules such as `invoice_views.py` are permitted when a single `views.py` would become unwieldy for a complex view set. All other files follow the standard layout above.

This structure must remain consistent across apps so that endpoint patterns are predictable and easy to maintain.

---

## URL Naming Rules

Use plural kebab-case resource names.

Examples:

/api/v1/billing-accounts/
/api/v1/storage-hotels/
/api/v1/price-lists/

Avoid:

- singular resource names
- snake_case URLs
- camelCase URLs

---

## Exposed Model Rule

Every exposed model must have:

- a serializer
- a view or viewset
- a URL registration

Serializers may exist without being exposed as standalone endpoints.

---

## Pagination Policy

All list endpoints must be paginated.

Default pagination style:

PageNumberPagination

Project-level defaults are configured in DRF settings.

---

## Filtering Policy

Use `django-filter` when filtering is meaningful.

Define `filterset_class` explicitly for filtered endpoints.

Avoid manual query parameter parsing.

---

## Response Format

Use standard Django REST Framework response shapes.

Object responses return the resource directly.

List responses use DRF pagination:

{
  "count": ...
  "next": ...
  "previous": ...
  "results": [...]
}

Do not introduce a custom response envelope.

---

## Error Format

Errors should return structured JSON with:

- code
- message
- optional details

Example:

{
  "code": "missing_quota_days",
  "message": "Quota data is incomplete for the selected billing period.",
  "details": {
    "storage_hotel_id": 42
  }
}

---

## Schema Generation

All endpoints must work correctly with `drf-spectacular`.

Standard CRUD endpoints may rely on automatic schema generation.

Custom endpoints must use explicit schema annotations when the schema is unclear.

### @extend_schema placement

Place `@extend_schema` decorators **inline on view methods**, not centralized in `schema.py`.

Example for an `APIView` method:

```python
from drf_spectacular.utils import extend_schema, OpenApiResponse

class GenerateInvoiceView(APIView):
    @extend_schema(
        request=GenerateInvoiceSerializer,
        responses={201: InvoiceSerializer, 422: OpenApiResponse(description="Error")},
    )
    def post(self, request):
        ...
```

Example for a `ViewSet` action:

```python
from drf_spectacular.utils import extend_schema

class InvoiceListView(ListAPIView):
    @extend_schema(responses={200: InvoiceListSerializer(many=True)})
    def get(self, request, *args, **kwargs):
        return super().get(request, *args, **kwargs)
```

`schema.py` is reserved for reusable schema components that would otherwise be duplicated across many views.

---

## Consistency Across Apps

Endpoint patterns must remain consistent across apps under `apps/`.

Do not introduce a new endpoint style unless it is required by the domain and documented here.

---

## Implementation

When implementing or modifying endpoints, use the project skill:

skills/django-api-endpoint-pattern

