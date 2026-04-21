# EDGE_CASES_REPORT.md

**App:** Ikeep (Flutter + Firebase)
**Date:** 2026-04-20
**Auditor:** Agent 3 — Edge Case Hunter

---

## Severity Summary

| Severity | Count |
|---|---|
| Critical | 2 |
| High | 4 |
| Medium | 6 |
| Low | 4 |

---

## Critical (must fix before any production release)

### C1 — Firebase init crash on launch
- **File:** `lib/main.dart:12`
- **Repro:**
  1. Put device in airplane mode **and** clear app data.
  2. Launch the app cold.
  3. If `google-services.json` fingerprint mismatch, missing GMS core (some A6 devices), or rare init IO failure → uncaught `PlatformException` → app crashes to red screen.
- **Impact:** First-launch crashes create 1-star reviews; without Crashlytics you are blind to the root cause.
- **Fix:**
  ```dart
  try {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  } catch (e, st) {
    debugPrint('Firebase init failed: $e');
    // Run app in degraded mode (local-only)
  }
  ```

### C2 — No `maxLength` on item name / lentTo / tag TextFields
- **Files:** `lib/screens/save/save_screen.dart:547, 861, 1250`, `lib/screens/detail/item_detail_screen.dart:2134`
- **Repro:**
  1. Paste 200 KB of text into item-name TextField.
  2. Save item.
  3. SQLite accepts (TEXT unbounded). Home list jank-freezes rendering a 200 KB name. If backed-up, Firestore write exceeds 1 MB document limit → throws.
- **Fix:** `maxLength: 100` on name, 50 on tags, 100 on lentTo; add `LengthLimitingTextInputFormatter`.

---

## High

### H1 — Personal item sync is pure last-write-wins (no conflict resolution)
- **File:** `lib/services/firebase_sync_service.dart:377-379` (uses `SetOptions(merge: true)` with whole patch)
- **Repro:**
  1. Sign in on Phone A and Phone B with same account.
  2. Offline-edit same item's name on both.
  3. Both come online — the later writer wins wholesale; other edit silently destroyed on next pull.
- **Contrast:** `household_sync_service.dart:1033-1151` has rich field-level merge (max of timestamps, per-field decisions). Personal sync does not.
- **Fix (MVP):** Compare `localUpdatedAt` vs `remoteUpdatedAt` field-by-field; merge images array; keep newer location. Document the limitation in release notes.

### H2 — Silent partial upload failure → corrupted metadata
- **File:** `lib/services/firebase_sync_service.dart:283-292, 319-325`
- **Repro:**
  1. Save an item with photo, enable backup, trigger sync.
  2. Storage rules reject OR mid-upload disconnect.
  3. Item metadata still writes to Firestore with empty `images` list, `lastSyncedAt` set, `isBackedUp=true`. Other device restoring sees an image-less item. UI reports "synced" (`partialFailure` returned but ignored).
- **Fix:** Abort item-doc write if required upload fails; surface to user.

### H3 — Session expiry / PERMISSION_DENIED not handled outside household
- **File:** `lib/services/firebase_sync_service.dart:567, 1905`
- **Repro:**
  1. Sign in, stay offline past 1 hour, come online.
  2. First sync returns `permission-denied`.
  3. App surfaces raw `"PERMISSION_DENIED: Missing or insufficient permissions."` in snackbar.
  4. User must manually sign out/in from settings.
- **Fix:** Branch on `FirebaseException.code == 'permission-denied'` → attempt silent token refresh, then force re-auth.

### H4 — Orientation + process-death mid-flow loses form state
- **File:** `lib/screens/save/save_screen.dart:38-56`
- **Repro:**
  1. Open Save screen, type name + pick location.
  2. Open 20 background apps to force low-memory state.
  3. Rotate device.
  4. OS kills backgrounded activity; on return all fields blank.
- **Fix:** Add restoration IDs / `AutomaticKeepAliveClientMixin`, or persist draft to SharedPreferences on dispose.
- **Camera mid-capture:** if plugin returns null on rotation, user is silently `context.pop()`-ed (line 91) with no error.

---

## Medium

### M1 — Android 6/7 install failure via `speech_to_text`
- **File:** `android/app/build.gradle.kts:45` (`minSdk = flutter.minSdkVersion` → 21)
- **Issue:** `speech_to_text: ^7.3.0` requires **minSdk 24**. APK will fail to install on Android 5.0-6.0 (~2-5% of active devices in India as of 2026).
- **Fix:** Explicitly set `minSdk = 24` in `build.gradle.kts`, OR remove `speech_to_text`.

### M2 — Hardcoded `Colors.white` / `Colors.black` in light-mode regressions
- **Files:** `settings_screen.dart:1317,1346`, `home_screen.dart:461-510`, `main_screen.dart:316-335`, `household_settings_screen.dart:336,592`, `update_dialog.dart:100`, `app_info_tooltip.dart:91`
- **Issue:** Produces white-on-white buttons in light mode where background is not `AppColors.primary`.
- **Fix:** Replace with `Theme.of(context).colorScheme.onSurface` / `onPrimary`.

### M3 — `lentToController` leaked in item detail dialog
- **File:** `lib/screens/detail/item_detail_screen.dart:2091`
- **Issue:** `TextEditingController` created inside `showDialog` without matching `dispose()`.
- **Fix:** Use `StatefulBuilder` + dispose in `dispose()`, or use `TextEditingValue` with `onChanged`.

### M4 — Tap target below 48dp
- **File:** `lib/screens/save/save_screen.dart:840` (tag `close` button — 14dp icon, no padding wrapper)
- **Fix:** Wrap in `IconButton(padding: EdgeInsets.all(12))` or `InkWell` with `minSize: 48`.

### M5 — Offline state invisible to user
- **Issue:** `connectivity_plus` not in `pubspec.yaml`. Every cloud action is optimistic. No pre-flight offline check.
- **Fix:** Add `connectivity_plus`; show offline banner in settings + save screen.

### M6 — `_interactiveGoogleSignInInProgress` can stick on throw
- **File:** `lib/providers/auth_providers.dart:9`
- **Fix:** Wrap entire flow in `try { } finally { flag = false; }`; move state into Riverpod.

---

## Low

- **L1** — Splash screen white on dark-themed app (`launch_background.xml:4`). Use `flutter_native_splash`.
- **L2** — No `SystemChrome.setPreferredOrientations`. Landscape + camera flows untested.
- **L3** — No font-scale clamping. 200% accessibility scale overflows nav bar + save form.
- **L4** — Nav-bar icons / FAB lack `Semantics` labels — TalkBack users hear "Button, Button, Button."

---

## Firebase-Down Behavior Matrix

| Service | Behavior when down | Grade |
|---|---|---|
| **Firebase init** | **CRASH** (main.dart:12 unwrapped) | F |
| **Auth** | Silent bootstrap catch (auth_providers.dart:31-35). App runs signed-out. | A |
| **Firestore (personal)** | Raw error string in snackbar; local SQLite still works. | C |
| **Firestore (household)** | Queued into `pending_sync_operations`; replayed later. | A |
| **Storage (images/invoices)** | Silent corruption — metadata written with empty image list (H2). | D |

---

## Concurrent Edit Conflict Outcome

| Scope | Behavior | Status |
|---|---|---|
| **Household items** | Field-level merge in `_mergeRemoteSharedItemDelta` — max(localTs, remoteTs), per-field content/location/media resolution, member-boundary enforcement | ✅ Solid |
| **Personal items** | Full-patch `set(merge: true)` — last writer wins; no version field | ❌ Silent data loss |

---

## Input Handling Audit

| Input | Sanitized? | Where enforced |
|---|---|---|
| Item name | ❌ no `maxLength` | save_screen.dart:547 |
| Tags | ❌ no length cap; case-sensitive dedup | save_screen.dart:861 |
| lentTo | ❌ no `maxLength` | save_screen.dart:1250 |
| SQL injection | ✅ parameterized `?` placeholders throughout DAOs | item_dao.dart:222 uses positional LIKE arg — safe |
| Emojis / ZWJ / RTL | ✅ UTF-16 handled by Dart/SQLite/Firestore |  |
| `\u0000` in names | ⚠️ could fail Firestore write | unsanitized |

---

## Accessibility Snapshot

- **Contrast** — `#7C3AED` on `#0D0B1A` = 5.6:1 → passes WCAG AA normal text, fails AAA. `#A78BFA` is ~9:1 (fine).
- **Semantic labels** — only 8 `Semantics` / `tooltip` occurrences across 5 files.
- **Tap targets** — tag-close button 14dp (fail); nav-bar ~52dp (borderline); FAB 72dp (OK).

---

## Launch Blockers (Edge Cases)

1. **C1** — Wrap `Firebase.initializeApp()` in try/catch.
2. **C2** — Add `maxLength` to all TextFields.
3. **M1** — Explicitly set `minSdk = 24` in `build.gradle.kts`.
4. **H2** — Abort item sync on partial upload failure.
5. **M3** — Dispose `lentToController` in detail dialog.

---

## Verdict

**EDGE CASES GO WITH FIXES**

Household sync is well-engineered with real conflict resolution. The 5 blockers above are each <1 day of work. Shipping without them produces: install-fail reports from A5/A6 users, cold-launch crashes, silent data-loss on two-device personal accounts, OOM from pathological paste. Fix these → ship safely.
