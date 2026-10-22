# Flutter Shell Baseline

**Captured:** 2026-10-22  
**Branch used for baseline:** `chore/flutter-baseline`  
**CI run:** [Build Flutter APK — baseline diagnostics](https://github.com/Pratham-1171/Sprachtreppe-Next/actions/runs/39777350393)

## Toolchain and dependency resolution

- Flutter: **3.47.7**, stable channel
- Dart: **3.13.5**
- DevTools: **2.60.0**
- `flutter pub get`: **PASS**. Dependency resolution completed successfully; the generated `pubspec.lock` is included beside `pubspec.yaml` to keep the Flutter shell's resolved versions reproducible.

## Baseline commands

| Command | Result | Notes |
|---|---|---|
| `flutter --version` | PASS | Version details above. |
| `flutter pub get` | PASS | Dependencies resolved with the generated lockfile. |
| `flutter analyze` | FAIL | `lib/pages/course_page_v2.dart` imports missing `models/course_module.dart` and `services/course_service.dart`. `CourseModule` and `CourseService` are consequently undefined, and member accesses also produce nullability diagnostics. The generated default widget test refers to `MyApp`, which is not defined in the app. |
| `flutter test` | FAIL | CI-generated `test/widget_test.dart` cannot compile because it expects `MyApp`; the application entry widget is named `SprachtreppeApp`. |
| `flutter build apk --debug` | PASS | CI built `flutter_shell/build/app/outputs/flutter-apk/app-debug.apk`. |

The workflow run has an overall **failure** because analysis and tests fail. The APK build itself succeeded. Artifact: **`Sprachtreppe-Flutter-APK`**, uploaded by the same [workflow run](https://github.com/Pratham-1171/Sprachtreppe-Next/actions/runs/39777350393).

## What is tracked in this shell

The tracked Flutter application currently consists of:

- `lib/main.dart`: simple Material 3 shell with Course, Practice and Profile tabs. Course level selection uses static sample module names for A1, A2 and B1.
- `lib/pages/course_page_v2.dart`: an unfinished course-page implementation that references model and service files not present in the tracked tree.

The Android project directory is generated during CI by `flutter create --platforms=android --org com.sprachtreppe .`. No Flutter test file, model file, service file, Supabase integration, authentication flow, progress sync or offline-sync logic is currently tracked under `flutter_shell`.

## Recommended next task

Keep this baseline as a record, then address the concrete analyzer/test blockers in a separate, focused change:

1. Decide whether `CoursePageV2` is part of the active app. If it is, add its missing model/service with defined non-null fields; otherwise remove the orphan page rather than masking its errors.
2. Add a tracked widget test that pumps `SprachtreppeApp` (not the generated placeholder's `MyApp`) and tests the actual shell.
3. Re-run `flutter pub get`, `flutter analyze`, `flutter test` and `flutter build apk --debug` in CI. Do not treat a successful APK build as evidence that analysis or tests pass.

No Supabase, LMS, app redesign or Gradle changes were made as part of this baseline task.
