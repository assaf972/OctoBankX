# OctoBankX — Application Documentation

OctoBankX is a Sinatra web application that automates daily bank statement downloads for multiple accounts via Secure FTP. It provides a web UI for operations monitoring and a REST JSON API for programmatic access.

---

## Table of Contents

1. [Features](#1-features)
2. [Technology Stack](#2-technology-stack)
3. [Project Structure](#3-project-structure)
4. [Database Structure](#4-database-structure)
5. [Background Jobs](#5-background-jobs)
6. [Web UI](#6-web-ui)
7. [REST API](#7-rest-api)
8. [Running the Application](#8-running-the-application)
9. [Configuration / Settings](#9-configuration--settings)
10. [Testing](#10-testing)

---

## 1. Features

- Register banks with their SFTP connection details
- Register bank accounts linked to a bank, with per-account SFTP credentials
- Daily automated download job that retrieves statement files from each bank via SFTP
- Download lifecycle tracking: `pending → running → success / failed`
- Full error capture and reporting per download attempt
- Web UI dashboards for live status, job monitoring, and historical log
- System-wide settings management
- REST JSON API for all core resources

---

## 2. Technology Stack

| Component     | Technology                               |
|---------------|------------------------------------------|
| Web framework | Sinatra 4                                |
| ORM           | Sequel 5                                 |
| Database      | SQLite 3                                 |
| SFTP          | net-sftp / net-ssh                       |
| Scheduler     | rufus-scheduler (cron-based)             |
| Web server    | Puma                                     |
| Testing       | RSpec 3, Rack::Test, FactoryBot          |

---

## 3. Project Structure

```
octobankx/
├── app.rb                    # Sinatra application — UI + API routes
├── config.ru                 # Rack entry point; runs migrations and starts scheduler
├── Gemfile
├── Rakefile                  # db:migrate, db:reset, jobs:run, spec tasks
├── db/
│   ├── database.rb           # Sequel connection helper and migration runner
│   └── migrations/
│       ├── 001_create_banks.rb
│       ├── 002_create_accounts.rb
│       ├── 003_create_downloads.rb
│       └── 004_create_settings.rb   # also seeds default settings
├── models/
│   ├── bank.rb
│   ├── account.rb
│   ├── download.rb
│   └── setting.rb
├── helpers/
│   └── sftp_helper.rb        # Net::SFTP download wrapper
├── jobs/
│   └── download_job.rb       # Enqueue + execute download records
├── views/                    # ERB templates (layout, home, jobs, log, banks, settings)
├── public/
│   └── style.css
└── spec/
    ├── spec_helper.rb
    ├── factories/factories.rb
    ├── models/                # bank_spec, download_spec, setting_spec
    └── api/                   # accounts_api_spec, downloads_api_spec, status_api_spec
```

---

## 4. Database Structure

### `banks`

Stores SFTP connection details for each financial institution.

| Column            | Type    | Notes                       |
|-------------------|---------|-----------------------------|
| `id`              | integer | Primary key                 |
| `name`            | string  | Unique, required            |
| `sftp_host`       | string  | Required                    |
| `sftp_port`       | integer | Default: 22                 |
| `sftp_remote_path`| string  | Default: `/`                |
| `created_at`      | datetime|                             |
| `updated_at`      | datetime|                             |

### `accounts`

Each account belongs to a bank and holds per-account SFTP credentials.

| Column          | Type    | Notes                                 |
|-----------------|---------|---------------------------------------|
| `id`            | integer | Primary key                           |
| `name`          | string  | Required                              |
| `account_no`    | string  | Required, unique                      |
| `bank_id`       | integer | Foreign key → `banks.id`, required    |
| `branch`        | string  |                                       |
| `currency`      | string  | Default: `USD`                        |
| `balance`       | float   | Default: `0.0`                        |
| `balance_date`  | date    |                                       |
| `sftp_username` | string  | SFTP login for this account           |
| `sftp_password` | string  | SFTP password for this account        |
| `created_at`    | datetime|                                       |
| `updated_at`    | datetime|                                       |

### `downloads`

One record per account per day; tracks the full lifecycle of each statement download.

| Column          | Type    | Notes                                              |
|-----------------|---------|----------------------------------------------------|
| `id`            | integer | Primary key                                        |
| `account_id`    | integer | Foreign key → `accounts.id`, required              |
| `bank_id`       | integer | Foreign key → `banks.id`, required (denormalized for fast filtering) |
| `date`          | date    | Statement date, required                           |
| `status`        | string  | `pending` / `running` / `success` / `failed`       |
| `error_message` | string  | Populated on failure                               |
| `file_path`     | string  | Local path to downloaded file on success           |
| `started_at`    | datetime| When the SFTP transfer began                       |
| `completed_at`  | datetime| When the transfer finished (success or failure)    |
| `created_at`    | datetime|                                                    |

**Download lifecycle:**
```
[created] → pending → running → success
                              ↘ failed
```

### `settings`

Key-value store for system-wide configuration.

| Column        | Type    | Notes              |
|---------------|---------|--------------------|
| `id`          | integer | Primary key        |
| `key`         | string  | Unique, required   |
| `value`       | string  |                    |
| `description` | string  | Human-readable hint|
| `updated_at`  | datetime|                    |

**Default seeded settings:**

| Key              | Default value           | Description                               |
|------------------|-------------------------|-------------------------------------------|
| `download_dir`   | `/tmp/octobankx/downloads` | Local directory for downloaded statements |
| `sftp_timeout`   | `30`                    | SFTP connection timeout in seconds        |
| `job_schedule`   | `0 6 * * *`             | Cron expression for daily job (6 am)      |
| `retention_days` | `90`                    | Days to keep download history             |

---

## 5. Background Jobs

### DownloadJob (`jobs/download_job.rb`)

The daily job has two phases:

#### Phase 1 — Enqueue (`DownloadJob.enqueue(date:)`)

For every account in the system, creates a `Download` record with `status: 'pending'` for the given date. Accounts that already have a download record for that date are skipped (idempotent).

#### Phase 2 — Execute (`DownloadJob.run(date:)`)

Calls `enqueue` then processes all `pending` records for the date:

1. Sets `status = 'running'` and stamps `started_at`
2. Calls `SftpHelper.download` to connect to the bank's SFTP server and download the statement file
3. On success: sets `status = 'success'`, stores `file_path`, stamps `completed_at`
4. On failure: sets `status = 'failed'`, stores `error_message`, stamps `completed_at`

#### Schedule

The scheduler is started in `config.ru` using `rufus-scheduler`. The cron expression is read from the `JOB_SCHEDULE` environment variable, falling back to the `job_schedule` setting value. Default: `0 6 * * *` (every day at 06:00).

The job can also be triggered manually:
- Web UI: click **Run Downloads Now** on the Home or Jobs page
- CLI: `bundle exec rake jobs:run`
- API: `POST /api/v1/downloads` to enqueue a single account

### SftpHelper (`helpers/sftp_helper.rb`)

Wraps `Net::SFTP` with:
- Configurable timeout (from Settings)
- Password or public-key authentication
- Clear error classification (auth failure, connection refused, SFTP status errors)
- Downloaded file saved to `<download_dir>/<bank_name>/<account_no>/<YYYYMMDD_account_no>.csv`

---

## 6. Web UI

All pages use a shared layout with a navigation bar linking to each section.

| Route      | Purpose                                                                 |
|------------|-------------------------------------------------------------------------|
| `/`        | **Home** — last 10 downloads, create-account form, account list        |
| `/banks`   | **Banks** — add a bank, list all registered banks                       |
| `/jobs`    | **Jobs** — live download list with status/account/bank; filter by status or date; trigger manual run |
| `/log`     | **Log** — full download history with filters (account, status, date range) |
| `/settings`| **Settings** — edit all system-wide settings in one form               |

---

## 7. REST API

All API endpoints are under `/api/v1`. Responses are JSON (`Content-Type: application/json`). POST and PATCH endpoints accept either `application/json` bodies or standard form parameters.

### Accounts

#### `GET /api/v1/accounts`

Returns all accounts sorted by name.

**Response** `200 OK`
```json
[
  {
    "id": 1,
    "name": "Main Ops Account",
    "account_no": "ACC001",
    "bank_id": 2,
    "bank_name": "First National",
    "branch": "HQ",
    "currency": "USD",
    "balance": 15000.00,
    "balance_date": "2026-04-19"
  }
]
```

Query parameters: `limit` (default 50, max 200), `offset` (default 0)

---

#### `GET /api/v1/accounts/:id`

Returns a single account by ID.

**Response** `200 OK` — full account object including `created_at`, `updated_at`  
**Response** `404 Not Found` — `{ "error": "Account not found" }`

---

### Downloads

#### `GET /api/v1/downloads`

Returns download records, newest first.

**Query parameters:**

| Parameter    | Description                        |
|--------------|------------------------------------|
| `status`     | Filter by `pending/running/success/failed` |
| `account_id` | Filter by account                  |
| `date`       | Filter by statement date (`YYYY-MM-DD`) |
| `limit`      | Max records (default 50, max 200)  |
| `offset`     | Pagination offset                  |

**Response** `200 OK`
```json
[
  {
    "id": 42,
    "account_id": 1,
    "account_name": "Main Ops Account",
    "account_no": "ACC001",
    "bank_id": 2,
    "bank_name": "First National",
    "date": "2026-04-20",
    "status": "success",
    "error_message": null,
    "file_path": "/data/downloads/First_National/ACC001/20260420_ACC001.csv",
    "started_at": "2026-04-20T06:00:01Z",
    "completed_at": "2026-04-20T06:00:04Z",
    "duration_s": 3.12,
    "created_at": "2026-04-20T06:00:00Z"
  }
]
```

---

#### `GET /api/v1/downloads/:id`

Returns a single download record.

**Response** `200 OK` — download object  
**Response** `404 Not Found` — `{ "error": "Download not found" }`

---

#### `POST /api/v1/downloads`

Enqueues a new download for a given account and date.

**Request body:**
```json
{
  "account_id": 1,
  "date": "2026-04-20"
}
```

`date` defaults to today if omitted.

**Responses:**

| Status | Meaning                                                    |
|--------|------------------------------------------------------------|
| `201`  | Created — returns the new download record                  |
| `404`  | Account not found                                          |
| `409`  | Download already exists for this account+date              |
| `422`  | `account_id` missing or invalid                            |

---

#### `PATCH /api/v1/downloads/:id/status`

Updates the status of a download record. Intended for external job runners or manual overrides.

**Request body:**
```json
{
  "status": "success",
  "file_path": "/data/stmt.csv"
}
```

| Status transition | Extra fields accepted    |
|-------------------|--------------------------|
| `running`         | — (stamps `started_at`)  |
| `success`         | `file_path`              |
| `failed`          | `error_message`          |

**Responses:**

| Status | Meaning                                   |
|--------|-------------------------------------------|
| `200`  | Updated — returns the updated download    |
| `404`  | Download not found                        |
| `422`  | Invalid status value                      |

---

### System Status

#### `GET /api/v1/status`

Returns a real-time system health snapshot.

**Response** `200 OK`
```json
{
  "status": "ok",
  "timestamp": "2026-04-20T10:30:00Z",
  "accounts_count": 5,
  "banks_count": 2,
  "totals": {
    "pending": 0,
    "running": 0,
    "success": 148,
    "failed": 3
  },
  "today": {
    "date": "2026-04-20",
    "pending": 0,
    "running": 0,
    "success": 5,
    "failed": 0
  },
  "last_success": {
    "id": 148,
    "account_id": 3,
    "date": "2026-04-20",
    "completed_at": "2026-04-20T06:00:07Z"
  },
  "last_failure": {
    "id": 120,
    "account_id": 5,
    "date": "2026-04-15",
    "error_message": "SFTP authentication failed",
    "completed_at": "2026-04-15T06:00:03Z"
  }
}
```

---

## 8. Running the Application

### Prerequisites

- Ruby 3.4+
- Bundler

### Setup

```bash
cd octobankx
bundle install
bundle exec rake db:migrate   # creates octobankx.db and runs all migrations
bundle exec puma config.ru    # starts the web server on port 9292
```

Visit `http://localhost:9292`

### Manual job trigger

```bash
bundle exec rake jobs:run
```

### Reset the database

```bash
bundle exec rake db:reset     # drops and recreates octobankx.db
```

### Environment variables

| Variable          | Default                        | Description                          |
|-------------------|--------------------------------|--------------------------------------|
| `DATABASE_URL`    | `sqlite://./octobankx.db`     | Sequel connection string             |
| `SESSION_SECRET`  | random per process             | Cookie session signing key           |
| `JOB_SCHEDULE`    | `0 6 * * *`                   | Cron expression for the download job |
| `DB_LOG`          | `0`                            | Set to `1` to log all SQL queries    |

---

## 9. Configuration / Settings

Settings are stored in the database and editable at `/settings` or via `POST /settings`. The `Setting` model provides a simple API:

```ruby
Setting['download_dir']               # => "/tmp/octobankx/downloads"
Setting.set('sftp_timeout', 60)       # upsert
Setting.all_as_hash                   # => { "key" => "value", ... }
```

---

## 10. Testing

Tests use RSpec with FactoryBot and an isolated per-run SQLite file.

```bash
bundle exec rspec              # run all tests
bundle exec rspec spec/models/ # model tests only
bundle exec rspec spec/api/    # API tests only
```

### Test coverage

| File                              | What it covers                                         |
|-----------------------------------|--------------------------------------------------------|
| `spec/models/setting_spec.rb`     | Validations, `.[]`, `.set` upsert, `.all_as_hash`, UI routes |
| `spec/models/bank_spec.rb`        | Validations, `#sftp_url`, associations, UI routes      |
| `spec/models/download_spec.rb`    | Validations, status predicates, status-based filtering, state transitions, `#duration`, `.for_date`, `.recent`, UI routes |
| `spec/api/accounts_api_spec.rb`   | `GET /api/v1/accounts`, `GET /api/v1/accounts/:id`     |
| `spec/api/downloads_api_spec.rb`  | `GET`, `POST`, `PATCH /status` for downloads           |
| `spec/api/status_api_spec.rb`     | `GET /api/v1/status` — counts, today snapshot, last events |

Each test runs inside a database transaction that is rolled back after the example, keeping the test database clean without truncation overhead.
