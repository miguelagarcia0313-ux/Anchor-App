# ⚓ Anchor

**One place for everything — finances, tasks, work hours, and health.**

Anchor replaces the spreadsheets and 8-10 apps most students use to track money, tasks, work hours, and health with a single modular mobile app. Each life area is a self-contained widget module, and you choose which ones show up on your dashboard.

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
| 🕒 Work hours | Planned | Clock in/out, auto-calculated pay |
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

## Contributing

We're a student team split across iOS/Flutter engineering, architecture, design, and QA roles. If you're interested in joining, see the **Recruiting plan** section of the project plan doc, or reach out to the project lead.

Branch per feature (`git checkout -b your-module-name`), open a PR into `main`, and tag the architecture lead for review on anything touching `lib/shared/`.

## License

TBD.