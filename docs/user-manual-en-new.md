# OctoBankX — User Manual

**כספת** (Kasefet) — Automated Bank Statement Download Manager

OctoBankX connects to your banks via SFTP, automatically downloads daily statement files for all configured banks, and provides a full audit trail of every download attempt. Both a desktop web interface and a mobile-optimized interface are included, with full support for English and Hebrew (RTL).

---

## Table of Contents

1. [Dashboard (Home)](#1-dashboard-home)
2. [Banks](#2-banks)
3. [Jobs](#3-jobs)
4. [Log](#4-log)
5. [Settings](#5-settings)
6. [Email Senders](#6-email-senders)
7. [Mobile Interface](#7-mobile-interface)
8. [Switching Languages](#8-switching-languages)
9. [Settings Reference](#9-settings-reference)

---

## 1. Dashboard (Home)

The Dashboard is the home page of OctoBankX. It gives you an at-a-glance overview of recent activity, key metrics, and system health.

![Dashboard — English](../screenshots/en/home.png)

### Summary Cards

At the top of the dashboard, four summary cards display today's key metrics:

| Card | Description |
|------|-------------|
| **Total Downloads** | Total number of download records in the system |
| **Success Today** | How many downloads completed successfully today |
| **Failed Today** | How many downloads failed today |

### Charts

- **Weekly Activity** — a bar chart showing daily success (green) and failure (red) counts for the past 7 days
- **Status Breakdown** — a doughnut chart showing the overall distribution of download statuses (success, failed, pending, running)

### Last 10 Downloads

Below the charts, a table shows the 10 most recent download attempts across all banks:

| Column | Description |
|--------|-------------|
| **Date** | The statement date |
| **Bank** | The bank this download belongs to |
| **Status** | `success`, `failed`, `running`, or `pending` |
| **Error** | Error message if the download failed |
| **File** | Path to the downloaded file on success |
| **Started** | When the SFTP transfer began |
| **Completed** | When the transfer finished |

Status badges are colour-coded: **green** for success, **red** for failed, **blue** for running, and **grey** for pending.

### Run Downloads Now

The **Run Downloads Now** button triggers an immediate download job for today across all banks, without waiting for the scheduled run.

---

## 2. Banks

The Banks page manages SFTP connection details and file parsing configuration for each bank.

![Banks — English](../screenshots/en/banks.png)

### Registered Banks

The main panel lists all configured banks showing:

| Column | Description |
|--------|-------------|
| **Name** | Display name of the bank |
| **SFTP Host** | Hostname of the bank's SFTP server |
| **Port** | SFTP port (usually `22`) |
| **Remote Path** | Directory on the SFTP server where statements are deposited |
| **Ruler** | Column mapping rules for parsing statement files |
| **Parser** | The parser class assigned to process this bank's files |
| **Target Folder** | Local folder where downloaded files are saved |

### Adding a New Bank

Fill in the **New Bank** form:

1. **Name** — a recognisable label for the bank (e.g. `בנק לאומי`)
2. **SFTP Host** — the server hostname (e.g. `sftp.leumi.co.il`)
3. **SFTP Port** — defaults to `22`; change if the bank uses a non-standard port
4. **Remote Path** — the directory path on the SFTP server (e.g. `/statements`)
5. **Ruler** — column mapping definition for statement parsing
6. **Parser** — select the appropriate parser (LeumiParser, PoalimParser, DiscountParser, FibiParser)
7. **Target Folder** — local destination folder path

Click **Add Bank** to save. The new bank will appear immediately in the registered banks list.

---

## 3. Jobs

The Jobs page shows every download job that has been executed or is queued, with filtering options.

![Jobs — English](../screenshots/en/jobs.png)

### Filters

At the top of the page you can filter the job list by:

- **Status** — All Statuses, Success, Failed, Running, or Pending
- **Date** — narrow results to a specific date

Click **Filter** to apply.

### Job List

Each row represents a single download attempt for one bank on one date:

| Column | Description |
|--------|-------------|
| **Date** | Statement date |
| **Bank** | Bank name |
| **Status** | Outcome of the attempt |
| **Error** | Error detail if the job failed |
| **File** | Downloaded file path on success |
| **Started** | When the SFTP transfer began |
| **Completed** | When the transfer finished |

### Running a Job Manually

Use the **Run Now** button to trigger an immediate download for all banks for today's date.

---

## 4. Log

The Log page is the complete download history — a full audit trail of every statement download ever attempted.

![Log — English](../screenshots/en/log.png)

### Filters

The log supports multiple filters that can be combined:

- **Bank** — filter by a specific bank (or "All banks")
- **Status** — All Statuses, Success, Failed, Running, Pending
- **From / To** — date range selector

Click **Filter** to apply.

### Log Entries

Each entry shows the same fields as the Jobs page. The log is ordered most-recent-first and retains records according to the `retention_days` setting (default: 90 days).

> **Tip:** Use the Log page for auditing and troubleshooting — the Jobs page is focused on today's activity, while the Log covers the full history.

---

## 5. Settings

The Settings page controls system-wide behaviour of OctoBankX.

![Settings — English](../screenshots/en/settings.png)

### Configuration Fields

| Setting | Description | Default |
|---------|-------------|---------|
| **alert_email** | Email address that receives failure alerts | `ops@octobankx.local` |
| **download_dir** | Local directory where downloaded statements are stored | `/tmp/octobankx/downloads` |
| **job_schedule** | Cron expression for the automatic daily download job | `0 6 * * *` (6 AM daily) |
| **max_retries** | Maximum SFTP retry attempts per bank per day | `3` |
| **notify_on_fail** | Send an alert email when a download fails (`true`/`false`) | `true` |
| **retention_days** | Number of days to keep download history in the database | `90` |
| **sftp_timeout** | SFTP connection timeout in seconds | `30` |

Click **Save Settings** to apply changes. Changes to `job_schedule` take effect on the next scheduled run.

> **Note:** The `download_dir` must be writable by the application process. Ensure the directory exists before saving.

---

## 6. Email Senders

Some banks and broker firms deliver statement files via email rather than SFTP. OctoBankX includes a built-in email listener that monitors a dedicated inbox (e.g. `kassefet-server@gmail.com`) via IMAP or POP3, and automatically downloads attachments from approved senders.

![Email Senders — English](../screenshots/en/email_senders.png)

### Approved Senders

The Email Senders page displays all approved email addresses in a table:

| Column | Description |
|--------|-------------|
| **Sender Name** | A descriptive label (e.g. "Bank Leumi – Statements") |
| **Sender Email** | The email address the system accepts files from |
| **Bank** | The bank this sender is associated with — attachments are filed under this bank |
| **Status** | `Active` (green) or `Inactive` (grey) |

Only emails from **active** approved senders are processed. All other emails are ignored.

### Adding a New Sender

Fill in the **New Approved Sender** form:

1. **Sender Name** — a descriptive label for this sender
2. **Sender Email** — the exact email address the bank uses to send files
3. **Associated Bank** — select which bank this sender belongs to

Click **Add Sender** to save.

### Managing Senders

- **Deactivate / Activate** — toggle a sender on or off without deleting it
- **Delete** — permanently remove a sender from the approved list

### Email Configuration

Email connection settings are managed on the **Settings** page:

| Setting | Description |
|---------|-------------|
| `email_protocol` | `imap` or `pop` |
| `email_host` | Mail server hostname (e.g. `imap.gmail.com`) |
| `email_port` | Server port (e.g. `993` for IMAP SSL) |
| `email_username` | Email account username |
| `email_password` | Email account password or app-specific password |
| `email_ssl` | Use SSL/TLS (`true` / `false`) |
| `email_check_interval` | How often to check for new emails (in minutes) |

### How It Works

1. The email listener job runs at the configured interval
2. It connects to the inbox using the configured IMAP or POP3 settings
3. For each unread email, it checks whether the sender is in the approved list
4. If approved, all CSV/Excel/ZIP attachments are saved to the bank's download directory
5. A download record is created with `success` status
6. The email is marked as read (IMAP) or deleted (POP3)

---

## 7. Mobile Interface

OctoBankX includes a fully optimised mobile web interface accessible at `/mobile/`. All pages are available through a bottom navigation bar.

### Mobile Dashboard

![Mobile Dashboard — English](../screenshots/en/mobile_home.png)

The mobile dashboard shows summary counters at the top (success today, failed today, running) followed by a scrollable list of recent downloads — each displayed as a card with the bank name and status badge.

### Mobile Banks

![Mobile Banks — English](../screenshots/en/mobile_banks.png)

Banks are displayed as cards, each showing the SFTP host, port, remote path, ruler, parser, and target folder. Tap **New Bank** at the top to expand the registration form.

### Mobile Jobs

![Mobile Jobs — English](../screenshots/en/mobile_jobs.png)

The jobs list adapts to mobile with a compact card layout. Date filter and status filters appear at the top. Each card shows the bank, date, status, and any error message.

### Mobile Log

![Mobile Log — English](../screenshots/en/mobile_log.png)

The log on mobile uses the same card layout as Jobs. Filter controls (bank, status, date range) are accessible at the top.

### Mobile Settings

![Mobile Settings — English](../screenshots/en/mobile_settings.png)

Settings are rendered as a mobile-friendly form with all the same configuration options. A **Switch to Desktop Version** link at the bottom navigates to the full desktop interface.

### Mobile Email Senders

![Mobile Email Senders — English](../screenshots/en/mobile_email_senders.png)

Email senders are displayed as cards, each showing the sender name, email address, associated bank, and status badge. Tap the buttons to activate/deactivate or delete a sender. An expandable form at the bottom allows adding new approved senders.

---

## 8. Switching Languages

OctoBankX supports **English** and **Hebrew** (עברית). The language switcher appears in the navigation bar on both desktop and mobile interfaces.

- Click **English** or **עברית** in the top navigation to switch languages
- The Hebrew interface automatically applies right-to-left (RTL) layout
- Your language preference is stored in the session and persists across page navigations

---

## 9. Settings Reference

| Setting | Type | Description |
|---------|------|-------------|
| `alert_email` | string (email) | Recipient for all system alert emails |
| `download_dir` | string (path) | Absolute path to the local statements directory |
| `email_check_interval` | integer | Minutes between inbox checks |
| `email_host` | string | IMAP/POP3 server hostname |
| `email_password` | string | Email account password or app-specific password |
| `email_port` | integer | IMAP/POP3 server port |
| `email_protocol` | string | `imap` or `pop` |
| `email_ssl` | boolean | Use SSL/TLS for email connection |
| `email_username` | string (email) | Email account username |
| `job_schedule` | string (cron) | Standard 5-field cron expression controlling the automatic download schedule |
| `max_retries` | integer | How many times the system retries a failed SFTP connection before marking the job as `failed` |
| `notify_on_fail` | boolean | When `true`, an email is sent to `alert_email` for each failed download |
| `retention_days` | integer | Log records older than this many days are automatically purged |
| `sftp_timeout` | integer | Seconds to wait before aborting an SFTP connection attempt |

---

*OctoBankX © 2026*
