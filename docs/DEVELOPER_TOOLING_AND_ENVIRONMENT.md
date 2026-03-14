# DEVELOPER_TOOLING_AND_ENVIRONMENT.md

## Doc Purpose

Define the developer tooling and execution environment assumptions Claude can rely on when working inside this repository.

This document tells Claude:

- which tools are available
- how dependencies should be installed
- how tests and linters should be executed
- how the repository should be explored from the terminal

It prevents Claude from inventing tooling or workflows that do not exist in this project.


## Read this document when

- Running tests
- Installing dependencies
- Running linting or type checks
- Exploring the repository
- Executing development commands
- Determining how Python environments are managed


## Do not read this document when

- Designing APIs
- Implementing business logic
- Working on billing algorithms
- Understanding the domain model
- Implementing Django models or services



# Operating System

The development environment is expected to run on:

Ubuntu Server 24.x


# Python Environment

Python version:

Python 3.12+

Python dependencies are defined in:

pyproject.toml


## Dependency Management

The preferred dependency manager is:

uv

Claude should always prefer `uv` over `pip` when installing packages.


### Virtual Environment

Typical environment setup:

uv venv
source .venv/bin/activate


### Installing Project Dependencies

Install project dependencies:

uv pip install -e .


### Installing Development Dependencies

uv pip install -e ".[dev]"

Claude should prefer using the dependency groups defined in `pyproject.toml`
instead of installing packages individually.



# Running Tests

The project uses:

pytest  
pytest-django

Run tests with:

uv run pytest

## MCP Servers

This project uses the following MCP integrations:

- Filesystem MCP
- Context7 MCP
- Postgres MCP

Rules:

- Prefer Filesystem MCP for repository exploration
- Prefer Context7 MCP for library documentation
- Prefer Postgres MCP for schema inspection
- Database access should be read-only unless explicitly requested


## Test Execution Strategy

Claude should follow this strategy when running tests:

1. Run the **smallest relevant test subset first**
2. If successful, run a **broader test suite**
3. Avoid running the entire test suite unless necessary


Examples:

Run a single file:

uv run pytest apps/billing/tests/test_invoice_generation.py

Run a single test:

uv run pytest -k test_invoice_generation_basic

## Pre-commit

This repository uses `pre-commit` as a required local quality gate.

Configured hooks currently include:

- `ruff --fix`
- `ruff-format`
- `mypy --config-file=pyproject.toml`
- `django-doctor`

Claude should treat these checks as part of the normal implementation workflow for changed Python code.

Recommended commands:

```bash
uv run pre-commit run --files path/to/changed_file.py
uv run pre-commit run --all-files
```

### django-doctor

`django-doctor` is a Django-specific linting tool that checks for common Django anti-patterns and configuration errors.

Run manually:

```bash
uv run django-doctor check
```

It is also integrated into the pre-commit pipeline.


# Linting

The project uses:

ruff


Run linting:

ruff check .



# Type Checking

Type checking is **mandatory**. All new code must pass mypy.

Tool:

mypy

mypy is enforced by pre-commit hooks.

Run type checking:

mypy .



# PostgreSQL

The project expects a local PostgreSQL database during development.

Typical environment variables:

POSTGRES_DB=invoice
POSTGRES_USER=invoice
POSTGRES_PASSWORD=django
POSTGRES_HOST=127.0.0.1
POSTGRES_PORT=5432


Typical connection string:

postgresql://invoice:django@127.0.0.1:5432/invoice


Claude may assume PostgreSQL is running locally unless instructed otherwise.



# Repository Exploration Tools

Claude may use the following command-line tools to inspect the repository:

git  
tree  
grep  
ripgrep (rg)  
find  
fd  

These tools are preferred for locating files and understanding repository structure.



# Allowed Dependency Installation

Claude may install development dependencies when required for:

- running tests
- linting
- formatting
- type checking


Preferred installation order:

1. uv
2. pip
3. apt (only if strictly necessary)
