# Repository Guidelines

## Project Structure & Module Organization

This repository is a Swift Package Manager macOS AppKit project for Ezshot, a native menu bar screenshot and image-markup utility. Keep application code under `src/`, tests under `tests/`, and generated files, build outputs, local caches, and downloaded dependencies out of version control through `.gitignore`.

Current layout:

```text
src/EzshotApp/        AppKit app, capture flow, overlays, editor UI
src/EzshotCore/       document and preference model code
tests/EzshotCoreTests/ executable test runner for core behavior
scripts/run-app.sh    build/sign/launch helper for local manual testing
README.md             English primary README
README.zh_TW.md       Traditional Chinese README
```

## Build, Test, and Development Commands

Use these canonical commands:

```sh
swift build                 # build all targets
swift run ezshot-core-tests # run the core test runner
sh scripts/run-app.sh --rebuild # rebuild/sign and launch .build/Ezshot.app
sh scripts/run-app.sh          # relaunch the existing signed app bundle
```

Prefer `scripts/run-app.sh` for manual app testing. Screen Recording permission is tied to the launched app identity; relaunching the existing signed bundle avoids unnecessary permission churn. The local app bundle runs as a regular app so editor windows appear in `Cmd+Tab`.

## Coding Style & Naming Conventions

Follow Swift and AppKit conventions. Use 4-space indentation, `PascalCase` for types, `camelCase` for properties and methods, and keep files focused on one responsibility. Prefer the project’s existing AppKit patterns over introducing a new UI framework. Keep menu and toolbar text routed through the localizer when user-facing strings are added.

## Testing Guidelines

Add tests with new core behavior, especially preferences, document saving, image mutation, filenames, and undo-related model state. Keep tests in `tests/EzshotCoreTests/` unless a future Swift test framework is introduced. Run `swift build` and `swift run ezshot-core-tests` before committing.

## Commit & Pull Request Guidelines

Use clear, imperative commit messages such as `Add capture configuration` or `Fix screenshot export path`. Keep commits focused and avoid mixing unrelated refactors with feature changes.

Pull requests should include a short summary, test results, linked issues when available, and screenshots or recordings for user-visible UI changes.

## Security & Configuration Tips

Do not commit secrets, access tokens, local credentials, or machine-specific config. Store environment-specific values in ignored `.env` files and document required variable names in `.env.example`.

## Agent-Specific Instructions

Install software with Scoop on Windows or Homebrew on macOS/Linux first. Use another source only when the requested software is unavailable through those package managers, and briefly explain why.
