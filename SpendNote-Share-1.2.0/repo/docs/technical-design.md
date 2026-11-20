# Technical design and screen flows

## Local database

Schema version 1 is defined in lib/store.dart. Foreign keys are enabled for every connection. Money uses INTEGER minor units. Financial reports derive from the ledger instead of cached balances. SQLite transactions make setup and restore atomic. Restore deletes children first, inserts parents first and rolls back on a constraint or foreign-key failure. Backups have a versioned envelope and authenticated encryption; future schemas must add explicit migrations and compatible snapshot validation.

Tables: accounts, categories, transactions (unified income/expense/transfer ledger), budgets, savings_goals, goal_contributions, backup_history, app_settings. Ledger constraints require positive amounts, distinct transfer endpoints and mutually exclusive category/destination fields. Budgets enforce unique category/month combinations. Archived records retain their primary keys and historical references.

## Screen flow

First launch → name/currency/first account → Overview.
Overview or History → Add transaction → select type/account/category or destination/date/note → Save.
History → search/filter → record → edit or confirmed delete.
Accounts → create/rename/archive account; manage categories below.
Plan & save → choose month → category budget; savings goal → contribution.
Reports → choose month → totals, category chart, six-month comparison, account balances.
Settings → profile/theme/preferences; PIN; optional Google connection → encrypted backup or select backup → decrypt → explicit replacement confirmation → transactional restore.
Background with PIN enabled → locked screen → PIN or enrolled device biometrics.

## Non-functional baseline

- Core tracking has no network dependency; all writes persist to SQLite before success.
- Monetary arithmetic uses integer minor units; transfers and savings allocations are excluded from expense totals.
- Restore is all-or-nothing; unsupported formats and failed authentication never replace local data.
- Backup passphrases are not stored. PIN verifiers are salted PBKDF2 values in secure storage, with retry throttling during the lock session.
- Android private screens use FLAG_SECURE and automatic Android backups are disabled.
- Responsive phone/tablet layout, semantic Material controls, scrollable forms, visible validation and theme support.
- Acceptance before public release: physical-device TalkBack/text-scaling review, biometric lifecycle checks, process-restart persistence, Google OAuth/Drive end-to-end recovery, release signing and device compatibility matrix.

## Scope notes

Currency changes update display labels without exchange conversion. Savings goals represent allocations rather than separate spendable accounts. Negative computed balances are permitted; the app is a record keeper rather than a bank. Google Drive is manual backup/restore, never synchronization. Archived accounts are excluded from the available-balance dashboard and retained in reports/history.

## Version 1.1 update (November 20, 2026)

The owner changed the original scope to require first-time Google connection and automatic backup. The current implementation and setup steps are described in README.md. Backup passphrases are now retained in Android secure storage for automatic encryption. Durable SQLite revisions queue uploads after edits, with foreground retries and explicit restore. No OS background worker or multi-device merge is implemented. The previous optional/manual-only descriptions in this document describe version 1.0 and are superseded by this update.
