# CLAUDE.md

## Project
Django Invoice API using Django 5.2, DRF, PostgreSQL, LDAP, uv, pytest.

## Non-negotiable Rules
- Write tests first whenever practical.
- Do not continue implementation until tests pass.
- Use Decimal for money.
- Keep views thin.
- Put business logic in services.
- APIs live under /api/v1/.
- Use vim in examples, never nano.
- Keep docs under docs/ synchronized with code.

## Primary References
- .claude/docs/PROJECT.md
- .claude/docs/API.md
- .claude/docs/TESTING.md
- .claude/docs/BILLING.md
- .claude/docs/STRUCTURE.md

## Skills
- skills/django-api-endpoint-pattern
- skills/django-model-pattern
- skills/django-service-pattern
- skills/django-testing-pattern
- skills/django-resource-pattern

## Execution Order
1. Read relevant docs
2. Write/update tests
3. Implement minimal code
4. Run/fix tests
5. Update docs if behavior changed

## Model Usage
- Use cheaper model for routine edits, tests, boilerplate, refactors.
- Use stronger model only for architecture, ambiguous billing logic, or cross-file design decisions.

## Claude Doc Loading Rule

Files under `.claude/docs/` use a mandatory lightweight routing header:

- `Doc Purpose`
- `Read this doc when`
- `Do not read this doc when`

Use that header first to decide whether the full document is relevant before relying on the rest of the file.

Do not load `.claude/docs/` files unnecessarily.
Prefer the smallest relevant set of docs for the task.

Use:
- `PROJECT.md` for domain context
- `STRUCTURE.md` for file placement
- `API.md` for endpoint rules
- `TESTING.md` for test conventions
- `BILLING.md` for billing and financial constraints
