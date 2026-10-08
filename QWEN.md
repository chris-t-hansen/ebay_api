# ebay_api

## Project Overview

A Python + MariaDB project for interacting with the eBay API to manage listings and sales. Currently in early scaffolding stage — no source files have been written yet.

**Owner:** Chris Hansen

## Tech Stack

- **Language:** Python
- **Database:** MariaDB (local, port 3306)
- **External API:** eBay API (Sandbox environment)
- **Auth:** eBay OAuth (Client ID, Client Secret, RuName)

## Project Structure

```
ebay_api/
├── .env            # Local secrets (gitignored)
├── .env.template   # Template with placeholder structure
├── .gitignore
├── LICENSE         # MIT License (c) 2026 Chris Hansen
└── README.md
```

**Expected structure once code is added:**
- A `src/` or top-level Python module for the application code
- A virtual environment directory (`.venv/` — excluded from git)
- A `requirements.txt` or `pyproject.toml` for dependencies

## Environment Variables

Sensitive configuration lives in `.env` (gitignored). A `.env.template` is committed as a reference. Required variables:

| Variable | Purpose |
|---|---|
| `DB_HOST` | MariaDB host (default: localhost) |
| `DB_PORT` | MariaDB port (default: 3306) |
| `DB_NAME` | Database name (default: ebay_api) |
| `DB_USER` | Database user |
| `DB_PASSWORD` | Database password |
| `EBAY_CLIENT_ID` | eBay App ID |
| `EBAY_CLIENT_SECRET` | eBay Cert ID |
| `EBAY_RUNAME` | eBay RuName for OAuth callback |
| `EBAY_ENV` | `sandbox` or `production` (currently: sandbox) |

## Building and Running

_No source code or build scripts exist yet._ Expected setup once code is added:

```bash
# Create virtual environment
python -m venv .venv
source .venv/bin/activate

# Install dependencies
pip install -r requirements.txt  # or: pip install -e .

# Run the application
python -m <module_name>
```

## Development Conventions

_Not yet established._ The `.gitignore` suggests:
- Python virtual environments in `.venv/`, `venv/`, `ENV/`, or `env/`
- Standard Python cache exclusion (`__pycache__/`, `*.pyc`, etc.)
