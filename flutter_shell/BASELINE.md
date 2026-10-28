# Flutter Shell Baseline

**Initial baseline captured:** 2026-10-22  
**Repair verified:** 2026-10-22  
**Branch:** `chore/flutter-baseline`  
**Initial diagnostic run:** [Build Flutter APK — baseline diagnostics](https://github.com/Pratham-1171/Sprachtreppe-Next/actions/runs/39777350393)  
**Passing validation run:** [Build Flutter APK — all checks passed](https://github.com/Pratham-1171/Sprachtreppe-Next/actions/runs/39785561990)

## Toolchain and dependency resolution

- Flutter: **3.47.7**, stable channel, pinned in `.github/workflows/flutter-apk.yml`
- Dart: **3.13.5**
- DevTools: **2.60.0**
- `flutter pub get`: **PASS**. The resolved `flutter_shell/pubspec.lock` is tracked to make dependency resolution reproducible for this Flutter application.

## Validation results

| Command | Final result | Notes |
|---|---|---|
| `flutter --version` | PASS | Flutter 3.47.7 / Dart 3.13.5. |
| `flutter pub get` | PASS | Dependencies resolved from the tracked lockfile. |
| `flutter analyze` | PASS | **Failed on the first run; fixed in this PR.** The first run found an unused `course_page_v2.dart` page importing absent model/service files. The orphan page was removed rather than adding unused placeholder classes. |
| `flutter test` | PASS | **Failed on the first run; fixed in this PR.** A tracked `test/widget_test.dart` now tests `SprachtreppeApp`, level selection, bottom navigation and Material 3 instead of the generated `MyApp` placeholder. |
| `flutter build apk --debug` | PASS | CI produced `flutter_shell/build/app/outputs/flutter-apk/app-debug.apk` and uploaded the `Sprachtreppe-Flutter-APK` artifact. |

The initial diagnostic run failed overall because `flutter analyze` and `flutter test` were blocked. The repair run passed all four relevant steps: dependency resolution, analysis, tests and debug APK build. See the [passing validation run](https://github.com/Pratham-1171/Sprachtreppe-Next/actions/runs/39785561990); the [initial diagnostic run](https://github.com/Pratham-1171/Sprachtreppe-Next/actions/runs/39777350393) is retained as historical evidence.

## What is tracked in this shell

- `lib/main.dart`: simple Material 3 shell with Course, Practice and Profile tabs. Course level selection uses static sample module names for A1, A2 and B1.
- `test/widget_test.dart`: widget tests for initial course rendering, level selection, bottom navigation and Material 3.

The unfinished `lib/pages/course_page_v2.dart` page was removed in this PR because it was not used by the app and referenced model/service files absent from the tracked tree. The Android project directory is generated in CI by `flutter create --platforms=android --org com.sprachtreppe .`. No Flutter model/service layer, Supabase integration, authentication flow, progress sync or offline-sync logic is currently tracked under `flutter_shell`.

## Scope and next steps

This PR establishes a reproducible, passing Flutter APK baseline; it does not claim that the Flutter shell is feature-complete. The current Course, Practice and Profile screens are a static UI shell, and the Android package/application ID decision remains open for Phase 5.

No Supabase, LMS, app redesign or Gradle changes were made as part of this baseline task.
