# ⚓ Anchor

**One place for everything — finances, tasks, work hours, and health.**

Anchor replaces the spreadsheets and 8-10 apps most students use to track money, tasks, and health with a single modular mobile app. Each life area is a self-contained widget module, and you choose which ones show up on your dashboard.

Senior design project — Fall 2026
Project lead: Michael Garcia

---

## Why

Every semester, students rebuild the same spreadsheets to track work hours, finances, to-dos, reminders, workouts, body weight, diet, and medicine — then juggle a pile of separate apps just to cover the basics. Anchor puts all of it behind one customizable dashboard instead.

## Features / modules

| Module | Status | What it does |
|---|---|---|
| 🧭 Dashboard shell | In progress | Add, remove, and reorder widget modules |
| 💰 Finance | Working (Plaid sandbox) | Bank import via Plaid, manual expenses, budget rings, re-categorizing, "money saved if you cut it" projection — see [Finance module](#-finance-module) |
| ✅ Tasks & reminders | In progress | To-dos, due dates, notifications |
| 🏋️ Health | Planned | Workouts, body weight trend, diet, medicine reminders |

See [`docs/Anchor_Project_Plan.docx`](docs/Anchor_Project_Plan.docx) for the full project plan, architecture rationale, timeline, and team roles.

## Tech stack

- **Framework:** [Flutter](https://flutter.dev) (Dart) — cross-platform, iOS + Android from one codebase
- **Charts:** [`fl_chart`](https://pub.dev/packages/fl_chart)
- **Local storage:** [`drift`](https://pub.dev/packages/drift) (SQLite)
- **Auth & cloud data:** [Firebase Authentication](https://firebase.google.com/docs/auth) (email/password) and [Cloud Firestore](https://firebase.google.com/docs/firestore), protected by [`firestore.rules`](firestore.rules)
- **Server code:** [Cloud Functions for Firebase](https://firebase.google.com/docs/functions) (TypeScript, in [`functions/`](functions/)) — the only code that talks to Plaid
- **Bank data:** [Plaid](https://plaid.com/docs/) **Sandbox** (Transactions product) with [`plaid_flutter`](https://pub.dev/packages/plaid_flutter) for the Link UI
- **State/architecture:** shared `AnchorModule` interface — every module plugs into the dashboard shell without changing shared code

## Getting started

**Prerequisites:** [Flutter SDK](https://docs.flutter.dev/get-started/install), an editor (VS Code recommended, with the Flutter extension), and an Android emulator or physical device.

```bash
git clone https://github.com/yourname/anchor-app.git
cd anchor-app
flutter pub get
flutter run
```

### Firebase authentication setup

The first screen is a Firebase email/password login. Before running the app, connect it to a Firebase project:

1. Create or select a project in the [Firebase Console](https://console.firebase.google.com/).
2. Install the Firebase CLI and sign in with `firebase login`.
3. Install the FlutterFire CLI with `dart pub global activate flutterfire_cli`.
4. From the project root, run `flutterfire configure` and select Android, iOS, macOS, and Web as needed. This creates `lib/firebase_options.dart` and registers the app identifiers.
5. In Firebase Console, open **Authentication > Sign-in method**, enable **Email/Password**, and save.
6. In Firebase Console, create a Cloud Firestore database for the project.
7. Deploy the included per-user security rules with `firebase deploy --only firestore:rules`.
8. Run `flutter pub get`, then `flutter run`.

This repository already includes `lib/firebase_options.dart` and `android/app/google-services.json` for the team's project (`anchor-app-20260911`). These files identify the project; they are not secrets, and access is controlled by `firestore.rules`. If you connect your own Firebase project, `flutterfire configure` overwrites them. The authentication gate sends signed-in users to the dashboard and everyone else to the login screen. The login screen also supports creating a new email/password account.

Health, Fitness, and Tasks sync through Firestore under each signed-in user's account. Existing local records are uploaded once on the first signed-in sync; later updates are shared between the app and browser. When no Firebase user is available, the modules use local storage.

### Run in a web browser

If Flutter is installed and your browser is available, use one of these commands from the project root:

```bash
# Open in Chrome
flutter run -d chrome --web-port 5000

# Open in Edge
flutter run -d edge --web-port 5000
```

If you want a local web server instead of a browser target:

```bash
flutter run -d web-server --web-port 8080 --web-hostname 0.0.0.0
```

Keep that terminal running, then open [http://localhost:8080](http://localhost:8080) in your browser. If `localhost:8080` is not reachable from your browser, forward port `8080` in VS Code's **Ports** panel and open the forwarded URL instead. Enable **Email/Password** under Firebase Console's **Authentication > Sign-in method** before creating an account or signing in.

To stop the app, focus the terminal running Flutter and press `q` or `Ctrl+C`. To start it again, run the same `flutter run` command above and reopen [http://localhost:8080](http://localhost:8080).

If the `flutter` command is not recognized in PowerShell, add Flutter to your PATH first:

```powershell
$env:Path += ";C:\Software\flutter\bin"
```

Then run `flutter doctor` to check the environment before starting the app.

## 💰 Finance module

Finance tracks spending against monthly budgets. Expenses come from two places: a connected bank account (through Plaid) and manual entries typed into the app. Both land in the same Firestore collection, and the Finance screen updates live from it — there is no mock data.

### What the user can do

| Feature | Where | Notes |
|---|---|---|
| Connect a bank | Finance screen → **Connect bank** | Opens Plaid Link (sandbox). After linking, the app syncs transactions automatically and retries while Plaid is still preparing history (`NOT_READY`). |
| Sync transactions | Finance screen → **Sync now** | Pulls new, changed, and removed transactions since the last sync. |
| Add a manual expense | Finance screen → **Add Expense** | Amount, category, date, optional note. Amount must be more than $0 and at most $100,000 (see [Limits](#limits)). |
| Delete an expense | Finance screen → recent expenses list | **Manual expenses only.** Bank transactions mirror the bank and can't be deleted in the app. |
| Re-categorize an expense | Tap a category → tap an expense | Works on bank and manual expenses. The user's choice (`userCategory`) always wins over the automatic one (`autoCategory`) and survives later syncs. |
| See budget pace | Category rings on the Finance screen and dashboard card | Spent vs. budget for the current month, per category. |
| Edit a budget | Tap a category → category detail screen | Saved to Firestore. New users start from `defaultBudgets` in `finance_repository.dart`. |
| Savings projection | "If you cut ___" card | Pick discretionary **categories** (not individual expenses) and a number of months to see projected savings. |

### Categories

`groceries`, `eating_out`, `subscriptions`, `entertainment`, `miscellaneous`

The list lives in **three places that must match**. Add or rename a category in all three or not at all:

1. `manualEntryCategories` in `lib/modules/finance/manual_entry_form.dart`
2. `isCategory()` in `firestore.rules`
3. `AnchorCategory` in `functions/src/categorize.ts`

How bank transactions are categorized (`categorize.ts`):

1. Money coming in, transfers, and loan payments are **skipped** (not spending).
2. Known subscription merchants (Netflix, Hulu, Spotify, YouTube, Gold's Gym, Planet Fitness) and gyms → `subscriptions`.
3. Otherwise, Plaid's [personal finance category](https://plaid.com/documents/pfc-taxonomy-all.csv) is mapped to an Anchor category.
4. Anything left over → `miscellaneous`.

### How the data flows

```
App ──createLinkToken──────▶ Cloud Function ──▶ Plaid     (link_token)
App ──Plaid Link UI────────▶ Plaid                         (public_token)
App ──exchangePublicToken──▶ Cloud Function ──▶ Plaid     (access_token saved server-side only)
App ──syncTransactions─────▶ Cloud Function ──▶ Plaid ──▶ Firestore ──▶ Finance screen (live listener)
App ──Add Expense──────────────────────────────────────▶ Firestore (checked by firestore.rules)
```

The Plaid secret and the bank `access_token` **never reach the phone**. Setup, deployment, sandbox logins, and a backend smoke test are documented in [`functions/README.md`](functions/README.md).

### Firestore layout

| Path | Written by | Readable by the app? |
|---|---|---|
| `users/{uid}/expenses/{id}` | Cloud Functions (`source: "plaid"`, id = Plaid `transaction_id`) and the app (`source: "manual"`) | Yes, owner only |
| `users/{uid}/settings/finance` | App writes `budgets`; Cloud Functions write `bank` (connection status, last sync) | Yes, owner only |
| `plaidItems/{uid}` | Cloud Functions only (access token, sync cursor) | **No** — rules deny all app access |

### Limits

Manual amounts must be **greater than $0 and at most $100,000**. The cap is enforced in two places that must match:

- `kMaxManualExpense` in `lib/modules/finance/finance_limits.dart` (the form shows an error before saving)
- `request.resource.data.amount <= 100000` in `firestore.rules` (the server rejects anything else)

The form check is for the user's benefit; the rule is the real protection, since anyone could call Firestore directly. Change both together, then run `firebase deploy --only firestore:rules`. Bank imports are written by Cloud Functions through the Admin SDK, so this cap does not apply to them.

### Code map

| File | Responsibility |
|---|---|
| `lib/modules/finance/finance_module.dart` | Module entry point and dashboard summary card |
| `lib/modules/finance/finance_screen.dart` | Full Finance screen: bank card, rings, projection, recent expenses |
| `lib/modules/finance/category_detail_screen.dart` | One category: big ring, editable budget, this month's transactions |
| `lib/modules/finance/finance_widgets.dart` | Shared widgets (`BankCard`, `CategoryPaceRow`, `SavingsProjectionCard`, `ExpenseTile`) |
| `lib/modules/finance/manual_entry_form.dart` | Add Expense bottom sheet and the category list |
| `lib/modules/finance/finance_limits.dart` | `kMaxManualExpense` (must match `firestore.rules`) |
| `lib/modules/finance/data/finance_repository.dart` | `FinanceRepository` interface, Firestore implementation, in-memory implementation for tests, `defaultBudgets` |
| `lib/modules/finance/data/finance_expense.dart` | Expense model; converts to the shared `TrackableEntry` so the insights math works on real data |
| `lib/modules/finance/data/finance_feed.dart` | One shared live subscription for every Finance widget |
| `lib/modules/finance/plaid/plaid_service.dart` | `BankConnector` interface and the real Plaid implementation |
| `lib/modules/insights/insights_calculations.dart` | `calculateBudgetPace()` and `calculateSavingsProjection()` |
| `functions/src/plaid.ts` | `createLinkToken`, `exchangePublicToken`, `syncTransactions` |
| `functions/src/categorize.ts` | Plaid transaction → Anchor category |

### Testing

**Unit and widget tests** (`flutter test`, also run by CI on every PR into `main`):

- `test/finance_test.dart` covers `FinanceExpense.fromMap`, `parseBudgets`, the stream combiner, and the Finance screen using `InMemoryFinanceRepository` and a fake bank connector, so no Firebase or Plaid connection is needed.

**BDD tests** (Behave + Appium + Flutter Driver, required for the course):

- Feature files are in `features/`, step definitions in `features/steps/finance_steps.py`.
- The steps find widgets by **Key**. Keys such as `finance_summary_card`, `finance_category_row_<category>`, `manual_entry_amount_field`, and `manual_entry_save_button` are load-bearing: rename them only together with the step file.
- The instrumented entry point is `test_driver/app.dart`, which enables the Flutter Driver extension without changing `lib/main.dart`.

```bash
pip install -r requirements.txt

# 1. Launch the instrumented app on a device (debug build)
flutter run --target=test_driver/app.dart

# 2. In a second terminal: start Appium (with the flutter driver installed)
appium

# 3. In a third terminal: run the scenarios
behave features/
```

### Known limitations

- Plaid runs in **Sandbox** only (fake banks and transactions). Production would need Plaid approval and encrypted storage for access tokens.
- Re-categorizing changes the category used in the app, not at the bank.
- Expenses older than 120 days (`financeLookback`) are not loaded.

## Project structure

```
lib/
  main.dart
  shell/
    dashboard_screen.dart      # home screen, hosts enabled modules
  shared/
    anchor_module.dart         # interface every module implements
    trackable_entry.dart       # shared data model
  modules/
    finance/
      data/                    # repository, expense model, live feed
      plaid/                   # bank connection (Plaid Link + Cloud Functions)
    insights/                  # budget pace + savings projection math
    tasks/
functions/                     # Cloud Functions (TypeScript): Plaid + categorization
features/                      # BDD feature files + Behave steps
test_driver/                   # Flutter Driver entry point for Appium
firestore.rules                # Firestore security rules
```

## Adding a new module

1. Create `lib/modules/your_module/your_module.dart`
2. Implement the `AnchorModule` interface (copy `tasks_module.dart` as a template)
3. Register it in `_allModules` in `lib/shell/dashboard_screen.dart`

No other files need to change — that's the architectural bet this project is testing.

### Rules for linking a new model to its data

When a module introduces a model that must survive app restarts, follow these rules:

1. Give every model a stable `id`. Do not use the list index as an identifier.
2. Include the module name in the stored record, such as `moduleType: 'finance'`, so records cannot be confused between modules. Use `TrackableEntry` in `lib/shared/trackable_entry.dart` when the data fits its shared shape.
3. Implement both serialization directions: a `toMap()`/JSON method for saving and a `fromMap()`/JSON factory for loading. Store dates in ISO-8601 format and convert booleans consistently.
4. Link user-owned data to `FirebaseAuth.instance.currentUser!.uid`. Firestore paths and local storage keys must include the UID; never put all users' records under one global key.
5. Load the current user's records before showing the module's editable UI. Show a loading state while the asynchronous load is in progress.
6. Save after every create, edit, delete, and completion/status change. Do not rely on an in-memory list as the source of truth.
7. Keep module IDs stable once released. Add the module to `_allModules` and use the same ID for dashboard preferences, filtering, and stored records.
8. Add a test that creates a model, recreates the module, and verifies the data returns. Also verify that two user IDs cannot see each other's data.

Dashboard module visibility follows the same user-scoped pattern through `lib/shell/module_preferences.dart`. Health, Fitness, and Tasks use Firestore for signed-in users and retain local storage for offline cache and first-login migration. Other modules using only local storage do not sync across devices.

## Contributing

Branch per feature (`git checkout -b your-module-name`), open a PR into `main`, and tag the project lead for review on anything touching `lib/shared/`.

## License

TBD.