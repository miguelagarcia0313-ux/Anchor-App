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
| 💰 Finance | In progress | Spend-vs-budget rings, "money saved if you cut it" projection |
| ✅ Tasks & reminders | In progress | To-dos, due dates, notifications |
| 🏋️ Health | Planned | Workouts, body weight trend, diet, medicine reminders |

See [`docs/Anchor_Project_Plan.docx`](docs/Anchor_Project_Plan.docx) for the full project plan, architecture rationale, timeline, and team roles.

## Tech stack

- **Framework:** [Flutter](https://flutter.dev) (Dart) — cross-platform, iOS + Android from one codebase
- **Charts:** [`fl_chart`](https://pub.dev/packages/fl_chart)
- **Local storage:** [`drift`](https://pub.dev/packages/drift) (SQLite)
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
6. Run `flutter pub get`, then `flutter run`.

The generated `lib/firebase_options.dart` is project-specific and is intentionally not included in this repository. The authentication gate sends signed-in users to the dashboard and everyone else to the login screen. The login screen also supports creating a new email/password account.

### Run in a web browser

From the project root, start Flutter's web server:

```bash
flutter run -d web-server --web-port 8080 --web-hostname 0.0.0.0
```

Keep that terminal running, then open [http://localhost:8080](http://localhost:8080) in your browser. If `localhost:8080` is not reachable from your browser, forward port `8080` in VS Code's **Ports** panel and open the forwarded URL instead. Enable **Email/Password** under Firebase Console's **Authentication > Sign-in method** before creating an account or signing in.

To stop the app, focus the terminal running Flutter and press `q` or `Ctrl+C`. To start it again, run the same `flutter run` command above and reopen [http://localhost:8080](http://localhost:8080).

Run `flutter doctor` first if this is your first time setting up Flutter — it'll flag anything missing.

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
    tasks/
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
4. Link user-owned data to `FirebaseAuth.instance.currentUser!.uid`. Storage keys and database queries must include the UID; never put all users' records under one global key.
5. Load the current user's records before showing the module's editable UI. Show a loading state while the asynchronous load is in progress.
6. Save after every create, edit, delete, and completion/status change. Do not rely on an in-memory list as the source of truth.
7. Keep module IDs stable once released. Add the module to `_allModules` and use the same ID for dashboard preferences, filtering, and stored records.
8. Add a test that creates a model, recreates the module, and verifies the data returns. Also verify that two user IDs cannot see each other's data.

Dashboard module visibility follows the same user-scoped pattern through `lib/shell/module_preferences.dart`. Local storage survives app sessions on the same device; use a Firebase database when the model must sync across devices.

## Contributing

Branch per feature (`git checkout -b your-module-name`), open a PR into `main`, and tag the project lead for review on anything touching `lib/shared/`.

## License

TBD.