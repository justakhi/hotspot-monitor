# GitHub Releases Update Checker & Changelog Implementation Plan

> **For agentic workers:** implement this plan task-by-task, in order, checking off each step as it lands. Steps use checkbox (`- [ ]`) syntax for tracking. Dispatch a fresh subagent per task where the tasks are independent, otherwise execute inline with a review checkpoint after each task.

**Goal:** Check for app updates against GitHub Releases on app startup, present a popup dialog with the release changelog and one-tap download action, provide a manual "Check for Updates" setting, and ensure release builds generate and package changelogs.

**Architecture:** A zero-dependency `UpdateCheckerService` queries `https://api.github.com/repos/justakhi/hotspot-monitor/releases/latest` via Dart's built-in `HttpClient`, compares semver strings, caches last-check timestamps in `SharedPreferences`, and surfaces release notes (`body`). The `DashboardScreen` checks for updates on first load (rate-limited) and displays an update dialog. The GitHub Actions release workflow packages commit-driven release notes and an updated `CHANGELOG.md`.

**Tech Stack:** Flutter 3.x, Dart (sound null-safety), `dart:io` `HttpClient`, Forui UI components, `shared_preferences`, GitHub Releases REST API v3.

---

### Task 1: Update Checker Domain Model & Service

**Files:**
- Create: `lib/domain/models/app_release_info.dart`
- Create: `lib/data/services/update_checker_service.dart`
- Test: `test/update_checker_test.dart`

- [ ] **Step 1: Write failing unit tests for semver comparison and JSON parsing**
  Create `test/update_checker_test.dart` testing:
  - Version comparison (`1.0.0` vs `v1.0.1`, `v1.1.0`, `v1.0.0`, `v0.9.9`).
  - Parsing GitHub release JSON payload (tag, name, body changelog, html_url, browser_download_url).
- [ ] **Step 2: Run test to verify it fails**
  Run `flutter test test/update_checker_test.dart`.
- [ ] **Step 3: Implement AppReleaseInfo and UpdateCheckerService**
  - Implement `AppReleaseInfo` model with `isNewer` comparison.
  - Implement `UpdateCheckerService` with `HttpClient` fetch, cache throttling, and manual force checks.
- [ ] **Step 4: Run test to verify it passes**
  Run `flutter test test/update_checker_test.dart`.

---

### Task 2: Repository & ViewModel Integration

**Files:**
- Modify: `lib/data/repositories/hotspot_repository.dart`
- Modify: `lib/ui/features/dashboard/view_models/dashboard_view_model.dart`
- Modify: `test/hotspot_repository_test.dart`

- [ ] **Step 1: Add update checking to HotspotRepository and DashboardViewModel**
  - Inject `UpdateCheckerService` into `HotspotRepository`.
  - Expose `Future<AppReleaseInfo?> checkForUpdate({bool force = false})`.
  - Add `availableUpdate` property to `DashboardViewModel`.
- [ ] **Step 2: Test in hotspot_repository_test.dart**
  - Test repository delegates update check and returns valid release info.

---

### Task 3: In-App Update Dialog UI

**Files:**
- Create: `lib/ui/core/widgets/update_available_dialog.dart`
- Modify: `lib/ui/features/dashboard/views/dashboard_screen.dart`
- Modify: `lib/ui/features/settings/views/settings_screen.dart`

- [ ] **Step 1: Create UpdateAvailableDialog widget**
  - Display release version tag (e.g. `v1.1.0`), release title, and formatted changelog body.
  - "Download Update" button opens download URL in browser / starts download.
  - "Later" button dismisses cleanly.
- [ ] **Step 2: Trigger update popup on DashboardScreen load**
  - After initialization, trigger automatic check. If newer version exists, show `UpdateAvailableDialog`.
- [ ] **Step 3: Add "Check for Updates" tile in SettingsScreen**
  - Displays current version (`v1.0.0`).
  - Tap runs manual check (`force = true`), displays a toast if up-to-date or opens the dialog if an update is found.

---

### Task 4: Changelog Tracking & CI/CD Workflow

**Files:**
- Create: `CHANGELOG.md`
- Modify: `.github/workflows/ci-and-release.yml`

- [ ] **Step 1: Create CHANGELOG.md**
  - Document v1.0.0 release notes and prepare section for v1.1.0 (quota alerts, device blocking, update popup).
- [ ] **Step 2: Ensure CI release workflow attaches changelog**
  - Verify `generate_release_notes: true` in `ci-and-release.yml`.

---

### Task 5: Verification & Automated Tests

**Files:**
- Modify: `test/widget_test.dart`

- [ ] **Step 1: Run static analysis & test suite**
  - `dart analyze --fatal-infos`
  - `flutter test`
- [ ] **Step 2: Commit locally on dev branch**
  - Commit author `contact@techyke.in`.
