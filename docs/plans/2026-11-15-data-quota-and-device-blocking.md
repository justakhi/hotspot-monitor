# Data Quota & Safe Device Internet Blocking Implementation Plan

> **For agentic workers:** implement this plan task-by-task, in order, checking off each step as it lands. Steps use checkbox (`- [ ]`) syntax for tracking. Dispatch a fresh subagent per task where the tasks are independent, otherwise execute inline with a review checkpoint after each task.

**Goal:** Add a global hotspot data quota with threshold alerts for non-root and root users, alongside per-device data quotas and safe memory-only `iptables` internet blocking for root users.

**Architecture:** A Flutter `QuotaService` stores quota settings in `SharedPreferences`. The `DashboardViewModel` checks live session usage against the quota to calculate percentage and trigger alert states. In root mode, native `iptables` rules in a custom memory chain (`HOTSPOT_MONITOR_BLOCK`) drop forwarded packets for blocked device IPs without touching system partitions or risking device stability.

**Tech Stack:** Flutter 3.x, Dart (sound null-safety), Forui UI components, `shared_preferences`, Kotlin on Android, Linux `iptables` forward filtering in RAM.

---

### Task 1: Quota Domain Models & Persistence Service

**Files:**
- Create: `lib/domain/models/quota_config.dart`
- Create: `lib/domain/models/device_quota.dart`
- Create: `lib/data/services/quota_service.dart`
- Test: `test/quota_service_test.dart`

- [ ] **Step 1: Write the failing unit test for QuotaService**
  Create `test/quota_service_test.dart` testing default global quota values, saving and loading global quota, and saving/loading per-device quotas and block states.
- [ ] **Step 2: Run test to verify it fails**
  Run `flutter test test/quota_service_test.dart` and confirm compilation/import failure.
- [ ] **Step 3: Implement domain models and QuotaService**
  - Implement `QuotaConfig` (`enabled`, `limitBytes`, `warningPercent`, `lastNotifiedLevel`).
  - Implement `DeviceQuota` (`deviceId`, `limitBytes`, `autoBlockExceeded`, `isBlocked`).
  - Implement `QuotaService` with `SharedPreferences` JSON serialization.
- [ ] **Step 4: Run test to verify it passes**
  Run `flutter test test/quota_service_test.dart` and ensure all tests pass cleanly.

---

### Task 2: Android Native Safe Device Blocking via iptables

**Files:**
- Modify: `android/app/src/main/kotlin/com/justakhi/hotspot_monitor/RootTelemetrySource.kt`
- Modify: `android/app/src/main/kotlin/com/justakhi/hotspot_monitor/MainActivity.kt`
- Modify: `lib/data/services/hotspot_platform_service.dart`

- [ ] **Step 1: Implement custom chain management in RootTelemetrySource.kt**
  - Create custom chain `HOTSPOT_MONITOR_BLOCK` on start if missing.
  - Forward jump rule: `iptables -C FORWARD -j HOTSPOT_MONITOR_BLOCK` (insert if not present).
  - Add `blockDeviceIp(ip: String, block: Boolean): Boolean`.
  - Add `flushAllBlocks()` called on session reset or app shutdown.
- [ ] **Step 2: Add platform channel methods in MainActivity.kt**
  - Add method `setDeviceBlocked` (`ip`, `mac`, `blocked`).
  - Add method `getBlockedIps`.
- [ ] **Step 3: Update HotspotPlatformService in Dart**
  - Add `Future<bool> setDeviceBlocked({required String ip, String? mac, required bool blocked})`.
  - Add `Future<List<String>> getBlockedIps()`.

---

### Task 3: Repository & View Model Quota Integration

**Files:**
- Modify: `lib/data/repositories/hotspot_repository.dart`
- Modify: `lib/ui/features/dashboard/view_models/dashboard_view_model.dart`
- Modify: `test/hotspot_repository_test.dart`

- [ ] **Step 1: Write failing test in hotspot_repository_test.dart**
  Test quota calculations: session bytes vs limit bytes, percentage used (0% to 100%+), warning state (e.g. >= 80%), and exceeded state (>= 100%).
- [ ] **Step 2: Update HotspotRepository & DashboardViewModel**
  - Expose current `QuotaConfig` and device quota map.
  - Calculate `quotaProgress` (0.0 to 1.0) and `quotaStatus` (`none`, `normal`, `warning`, `exceeded`).
  - Add auto-block check: when a device exceeds its configured `limitBytes` and root is active, invoke `setDeviceBlocked`.

---

### Task 4: UI - Global Hotspot Quota Card on Dashboard

**Files:**
- Create: `lib/ui/core/widgets/quota_progress_card.dart`
- Modify: `lib/ui/features/dashboard/views/dashboard_screen.dart`
- Modify: `lib/ui/features/settings/views/settings_screen.dart`

- [ ] **Step 1: Create QuotaProgressCard widget**
  - Displays session usage vs limit (e.g., `512 MB / 2.0 GB`).
  - Progress bar colored by status: default primary blue/neutral, amber for >= 80%, rose/red for >= 100%.
  - Quick action: "Edit Limit" dialog with preset options (500 MB, 1 GB, 2 GB, 5 GB, Custom) and disable toggle.
- [ ] **Step 2: Embed QuotaProgressCard into DashboardScreen**
  - Place cleanly below the active hotspot header / telemetry summary.
- [ ] **Step 3: Add Quota settings in SettingsScreen**
  - Allow setting default session quota and warning threshold.

---

### Task 5: UI - Per-Device Quota & Internet Blocking Controls

**Files:**
- Modify: `lib/ui/features/device_detail/views/device_detail_screen.dart`

- [ ] **Step 1: Add "Internet Access & Quota" section in DeviceDetailScreen**
  - If Root is enabled:
    - "Internet Access" switch: Instant Block / Allow toggle with confirmation.
    - "Device Data Limit": Preset selector (e.g., No limit, 250 MB, 500 MB, 1 GB, Custom).
    - "Auto-block when limit reached" switch.
  - If Non-Root:
    - Show an informative card explaining that per-device blocking requires root privileges, while global quota alerts are fully active.

---

### Task 6: Verification, Static Analysis & Automated Testing

**Files:**
- Modify: `test/widget_test.dart`

- [ ] **Step 1: Update widget_test.dart**
  - Verify QuotaProgressCard renders on Dashboard.
  - Verify editing quota updates the display.
  - Verify device detail displays internet access controls.
- [ ] **Step 2: Run static analysis & test suite**
  - `dart analyze --fatal-infos`
  - `flutter test`
- [ ] **Step 3: Local git commit on dev branch**
  - Clean commit with author `contact@techyke.in`.
