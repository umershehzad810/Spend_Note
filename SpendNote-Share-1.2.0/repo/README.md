# SpendNote 1.2.0

Android expense tracker with SQLite, required first-time Google connection and automatic encrypted Google Drive backups. This Google requirement supersedes the original optional-login FRS following the owner's November 20, 2026 request.

## Install / build

Use build/app/outputs/flutter-apk/app-release.apk. The release is signed with the same dedicated key as version 1.0.0 and can update that release without uninstalling. Never uninstall an existing release just to update; uninstalling removes local records.

```powershell
C:\Users\pc\Tools\flutter\bin\flutter.bat pub get
C:\Users\pc\Tools\flutter\bin\flutter.bat test
C:\Users\pc\Tools\flutter\bin\flutter.bat build apk --release
```

Keep the private signing key and android/key.properties backed up. See docs/release-signing.md.

## Google Cloud configuration

Package: com.spendnote.spendnote

Release certificate SHA-1:
7B:5A:F9:EB:7B:5F:4B:CF:21:0C:A1:06:99:C8:9F:16:C1:2E:E9:E5

Web OAuth client (embedded as public serverClientId):
451353665067-tjsjkn84a9tmtjac8tq4b15vfle7volj.apps.googleusercontent.com

Android OAuth client (registered in Google Cloud, not passed as serverClientId):
451353665067-33fp7v0uecutbp871sh6i1v9dq34kf6t.apps.googleusercontent.com

The Android and Web clients must be in the same Cloud project. Enable the Google Drive API, configure the consent screen, and add the signing-in account as a test user when the OAuth app is in testing. The app requests drive.appdata plus basic Google identity. No client secret is required or included in the app. Reset the client secret previously disclosed in chat.

For Play Store distribution, also register the Google Play app-signing SHA-1. It can differ from the certificate used for this sideloaded release.

## First launch and recovery

1. Connect Google before entering onboarding or accessing existing financial data.
2. Check Drive for a previous backup. Restore the latest with the recovery passphrase and explicit replacement confirmation, or explicitly continue with local data.
3. Set a recovery passphrase of at least 10 characters and confirm it. It is stored in Android secure storage for automatic encryption. Keep a separate private copy for reinstall/new-phone recovery.
4. Create the initial profile/account if no prior onboarding data was restored.

After setup, tracking works offline. A previously connected account is remembered locally. Signing out returns to the connection gate and leaves financial data on the device. The local database remains bound to the original Google account to avoid accidentally uploading one person's records to a different account.

## Automatic backup behavior

Financial or preference changes increment a durable SQLite revision in the same transaction as the write. After three seconds without another edit, a serialized upload creates an encrypted recovery snapshot in Drive appDataFolder. Pending work retries every minute while the app is open, on app resume and on reopening. Unchanged revisions and backup-history changes do not upload again. New edits made during an upload remain pending for a subsequent upload. Errors show a pending status in Settings. Back up now forces a fresh upload.

No background service runs after Android terminates the app. This is automatic versioned backup, not live multi-device merging. Records on different phones are never silently merged or replaced. Restore remains an explicit operation. Snapshots are retained; this version does not delete previous Drive recovery points. Private appDataFolder files do not appear in the user's normal Drive file list.

AES-256-GCM authenticates snapshots. PBKDF2-HMAC-SHA256 derives encryption keys from the passphrase with a fresh salt and 210,000 iterations. Restore verifies authentication and format, then applies data transactionally with database constraints. A forgotten passphrase cannot be recovered. Device PIN settings remain local. Android automatic cloud backup is disabled and private screens use FLAG_SECURE.

## Features and checks

Onboarding, profiles, income/expense/transfer editing and deletion, exact minor-unit money storage, accounts/categories and archiving, search and filters, budgets, savings goals, reports, charts, themes, optional PIN/biometrics and Drive backup/recovery are implemented. Phase 2 reminders, delivered notifications, exports, receipt attachments and OS background scheduling remain outside this version.

Tests cover financial rules, persistence, encrypted recovery, PIN verification, required Google gating, mobile navigation, auto-backup deduplication, failure/retry and concurrent edits. Google OAuth/Drive server access and biometric hardware still require physical-device acceptance testing with the owner's account.


## SQLite compatibility fix (1.1.1)

The revision-counter UPSERT in 1.1.0 failed on older Android system SQLite engines. It now uses INSERT OR IGNORE followed by UPDATE inside the same financial-write transaction. Existing data and schema stay intact. Setup is idempotent and prevents duplicate submissions. Errors are shown as readable messages rather than raw SQL.

The regression suite runs with the default SQLite engine and can use the official Windows SQLite 3.22.0 DLL to reproduce older-engine behavior:

```powershell
$env:SPENDNOTE_SQLITE_DLL = (Resolve-Path tools/sqlite-legacy/sqlite3.dll).Path
flutter test
```

Download the optional test-only DLL from https://www.sqlite.org/2018/sqlite-dll-win64-x64-3220000.zip and place sqlite3.dll in tools/sqlite-legacy. It is ignored by version control and never packaged in Android. Tests verify the loaded legacy version, rejected old syntax, successful onboarding, revision concurrency, rollback, financial writes, app gating, recovery and backup queue behavior. Re-run without the environment variable to test the default engine.


## Phone UI redesign (1.2.0)

The desktop sidebar is removed. All sizes use four bottom destinations: Home, Activity, Plan and More. Accounts, Reports and Settings are available through More; Settings is also available in the header. Back returns from these screens to More, then Home. The dashboard now prioritizes balance, monthly income/spending, quick entry actions and recent activity. Activity has horizontal type filters, search and a separate filter sheet. All financial edit forms use keyboard-aware bottom sheets with a full-width Save action.

A shared mobile theme provides larger touch controls, rounded cards, readable typography, dark appearance and consistent fields. Phone-aspect portrait windows that incorrectly report a width above 600 logical pixels use a scaled 440-wide phone canvas for the entire navigator, including overlays, safe areas and keyboard insets. This prevents the shrunken desktop layout seen on low-density Android emulators. Tablet/landscape content is constrained, but always retains bottom navigation.

Layout regression tests cover 320, 360, 412 and 1080-wide portrait views, all destinations, keyboard insets, bottom sheets and a larger-font dark-mode case. Screenshots in docs/mobile-preview.png, docs/mobile-activity.png and docs/mobile-transaction-sheet.png use test data. Android launcher icons now match SpendNote's leaf identity. Database and release signing remain compatible with earlier versions.
