# Repository Guidelines

## Project Structure & Module Organization

This is a Flutter desktop client for NovelAI. Main application code lives in `lib/`, with feature areas under `presentation/`, `data/`, and `core/`. Generated localization files are controlled by `l10n.yaml` and source ARB files in `lib/l10n/`. Static assets live in `assets/`, fonts in `fonts/`, Windows runner code in `windows/`, and Krita bridge/plugin code in `krita_plugin/`. Tests mirror the app layout under `test/`. Developer and diagnostic scripts are in `tool/` and `scripts/`.

## Build, Test, and Development Commands

Use Flutter `>=3.35.0` and Dart `>=3.10.7`; the current local target is `E:/flutter`.

```powershell
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter run -d windows
flutter build windows --release
flutter test
flutter analyze
```

Run `build_runner` after pulling changes that add or modify Riverpod providers, Freezed models, Hive adapters, JSON models, or routes. `flutter run -d windows` supports hot reload with `r` and hot restart with `R`.

## Coding Style & Naming Conventions

Follow the repository's Dart style and `analysis_options.yaml`. Use two-space indentation, `lowerCamelCase` for variables and methods, `UpperCamelCase` for types, and descriptive provider names ending in `Provider` or `NotifierProvider`. Prefer existing services, providers, and UI components over adding new abstractions. Keep comments focused on why a non-obvious decision exists.

## Testing Guidelines

Use `flutter_test` with `mocktail` for unit and widget tests. Place tests beside the relevant domain path, for example `test/presentation/providers/...` or `test/core/utils/...`. Name test files with `_test.dart`. For generated-code changes, run `build_runner` before testing. For UI behavior changes, add widget tests where practical and at least one provider/service regression test for stateful logic.

## Commit & Pull Request Guidelines

Recent history uses Conventional Commits such as `fix(generation): ...`, `feat(prompt): ...`, and `chore(toolchain): ...`. Keep commits scoped and written in the form `type(scope): concise description`. Pull requests should explain the user-facing change, list validation commands run, mention generated files or assets affected, and include screenshots for visible UI changes.

## Security & Configuration Tips

Do not commit API tokens, passwords, local account data, generated logs, or personal workflow artifacts. Prefer Persistent API Token login for NovelAI testing. Avoid printing full bearer tokens or credentials in logs; redact values and log only token type, length, or prefix when needed.
