# PRODUCTION_READINESS_REPORT.md

**App:** Ikeep (Flutter + Firebase)
**Version:** 1.0.7+9 (per pubspec.yaml)
**Target:** Google Play production full release
**Date:** 2026-04-20
**Consolidated by:** GO/NO-GO Decision Agent (synthesis of Security, Performance, Edge Case, Cost/Scale, and Release Readiness audits)

---

## TL;DR — Verdict

# 🔴 **NO-GO as of today.**

**With ~2 days of focused work → GO-WITH-CAUTION on 5% staged rollout.**

The architecture is solid. The individual issues are small. But there are 11 critical blockers that together would produce a painful production launch for a non-developer — especially the absence of Crashlytics (you'd be flying blind) and the unwrapped Firebase init (crashes for a minority of users). Fix those and you can ship with confidence.

---

## Aggregate Severity

| Source | Critical | High | Medium | Low |
|---|---:|---:|---:|---:|
| Security | 0 | 2 | 4 | 4 |
| Performance | 0 | 4 | 6 | 4 |
| Edge Cases | 2 | 4 | 6 | 4 |
| Cost / Scale | 0 | 1 (bandwidth) | 4 (opts) | 0 |
| Release Readiness | 1 | 5 | 6 | 4 |
| **TOTAL** | **3** | **16** | **26** | **16** |

---

## 🚨 CRITICAL BLOCKERS — Must Fix Before Production

These will cause crashes, install failures, data loss, or Play policy rejection. Ship order is deliberate.

### B1 — Add Firebase Crashlytics (Release Readiness)
- **File:** `pubspec.yaml:49` (has `firebase_analytics`, missing `firebase_crashlytics`), `lib/main.dart:10`
- **Why:** A solo non-developer shipping to production without crash telemetry is flying blind. One bad release → angry reviews you can't diagnose.
- **Fix:**
  ```yaml
  firebase_crashlytics: ^4.1.3
  ```
  ```dart
  FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;
  PlatformDispatcher.instance.onError = (e, st) {
    FirebaseCrashlytics.instance.recordError(e, st, fatal: true); return true;
  };
  ```
- **Effort:** 30 min

### B2 — Wrap `Firebase.initializeApp()` in try/catch (Edge Cases C1)
- **File:** `lib/main.dart:12`
- **Why:** Unhandled init failure = first-launch crash, especially on degraded GMS devices.
- **Effort:** 15 min

### B3 — Remove `appwrite` dep + placeholder credentials (Quality)
- **Files:** `pubspec.yaml:41`, `lib/core/constants/storage_constants.dart:15-21` (has `'YOUR_PROJECT_ID'`)
- **Why:** Shipping with placeholder credentials in binary is a Play policy / security-review risk.
- **Effort:** 20 min

### B4 — Explicitly pin `minSdk = 24`, `targetSdk = 35` (Release + Edge Cases M1)
- **File:** `android/app/build.gradle.kts:45-46`
- **Why:** `speech_to_text` needs minSdk 24; current inheritance from Flutter defaults is fragile. Play requires targetSdk 35+ as of Aug 2025.
- **Effort:** 10 min

### B5 — Add `maxLength` to all TextFields (Edge Cases C2)
- **Files:** `lib/screens/save/save_screen.dart:547, 861, 1250`, `lib/screens/detail/item_detail_screen.dart:2134`
- **Why:** Paste-based DoS; Firestore 1MB doc limit; SQLite bloat.
- **Effort:** 30 min

### B6 — Replace white splash with branded dark splash (Release Readiness)
- **File:** `android/app/src/main/res/drawable/launch_background.xml:4`
- **Why:** White flash on every cold start against dark-themed app = jarring, feels broken. Use `flutter_native_splash`.
- **Effort:** 1 hour

### B7 — Declare `allowBackup=false`, `usesCleartextTraffic=false` (Release Readiness)
- **File:** `android/app/src/main/AndroidManifest.xml`
- **Why:** Default `allowBackup=true` allows ADB backup of app data including cached tokens. Explicit false-declarations required for Play policy.
- **Effort:** 10 min

### B8 — Add pre-request rationale for location permission (Release Readiness)
- **File:** `lib/services/location_service.dart`
- **Why:** Play requires prominent in-app disclosure before first sensitive-permission access, or listing is rejected.
- **Effort:** 1 hour

### B9 — Commit `firestore.rules` + `storage.rules` + `firebase.json` to main (Security H1)
- **Current:** Rules live only in `.claude/worktrees/upbeat-proskuriakova/`.
- **Why:** No source-of-truth for what rules are actually deployed to `ikeep-1af18`.
- **Fix:** Commit files. Run `firebase deploy --only firestore:rules,storage` to verify deploy matches.
- **Effort:** 30 min

### B10 — Abort item sync on partial upload failure (Security M4 / Edge H2)
- **File:** `lib/services/firebase_sync_service.dart:283-292, 319-325`
- **Why:** Currently writes item metadata with empty `images` list if Storage upload fails → silent corruption on other devices.
- **Effort:** 2 hours

### B11 — Add retry cap + dead-letter to pending sync queue (Performance P2)
- **File:** `lib/data/database/pending_sync_dao.dart`
- **Why:** Permanently-failing operations re-queue forever; battery + sync degradation after weeks.
- **Fix:** Add `retry_count` column; drop after 5 attempts; log.
- **Effort:** 3 hours

**Total blocker effort:** ~1.5–2 days of focused work.

---

## 🟠 HIGH PRIORITY — Fix in First Patch (within 1 week)

Not release-blocking, but ship hotfix 1.0.8 within 7 days of launch.

| ID | Item | File:Line | Effort |
|---|---|---|---|
| H1 | Add `cached_network_image` + route lists to thumbnails (-85% bandwidth) | adaptive_image.dart:151 | 4h |
| H2 | Bound `_uploadCache` with LRU | firebase_image_upload_service.dart:56 | 2h |
| H3 | Handle `PERMISSION_DENIED` → silent token refresh | firebase_sync_service.dart:567 | 3h |
| H4 | Dispose `lentToController` in detail dialog | item_detail_screen.dart:2091 | 30m |
| H5 | Semantic labels on nav bar + icon buttons | app_nav_bar.dart, item_detail_screen.dart | 2h |
| H6 | Fix household `members` vs `memberIds` mismatch (if shipping household) | firestore.rules:51 + household_cloud_service.dart:182 | 1h |
| H7 | Add field-level merge to personal sync (prevent silent data loss) | firebase_sync_service.dart:377 | 1d |
| H8 | Add `connectivity_plus` + offline banner | pubspec.yaml + settings | 3h |
| H9 | Fix `ItemsNotifier` invalidation storm | item_providers.dart:714 | 30m |
| H10 | Debounce `refreshPersonalUsage` | firebase_sync_service.dart:425 | 1h |
| H11 | Gate auto-restore behind first-run flag | app.dart:79 | 30m |

**Total:** ~3 days

---

## 🟡 MEDIUM — Fix in v1.1

| Area | Items |
|---|---|
| Perf | Add `tags_lower` indexed column; stop unconditional locations JOIN; move image hashing to isolate |
| Quality | Extract oversized screens (home 1820 LOC, settings 1893, save 1431) into sub-widgets |
| UX | Empty-state widgets on every list screen; font-scale clamp; orientation lock if needed |
| Theme | Replace hardcoded `Colors.white/black` with theme-aware colors across 6 files |
| Cost | Batch history writes into parent item write; skip tombstone-delete for new items |
| Accessibility | Tap targets for tag-close button, chevrons; contrast review for AAA-grade text |
| Infrastructure | Localization scaffolding (`flutter_localizations`); root-directory cruft cleanup |

---

## 📊 Rollout Strategy — 5% Start, NOT 20%

### Recommended phased rollout

| Phase | % rollout | Duration | Gate to advance |
|---|---:|---|---|
| Internal testing | - | 2 days | All B1-B11 verified fixed + Crashlytics reporting 0 fatal |
| **Production 5%** | 5% | **48-72h** | Crash-free users >99.5%, no P0 incidents, Firebase bill within projection |
| Production 20% | 20% | 48-72h | Crash-free users >99.3%, cost trajectory OK, no sync corruption reports |
| Production 50% | 50% | 5 days | Hotfix 1.0.8 (H1-H11) shipped and stable |
| Production 100% | 100% | ongoing | Monitoring + on-call playbook documented |

### Why 5% and not 20%?
1. **No Crashlytics today** — blast radius of a bad release is unknown. Start small, expand on signal.
2. **Personal-sync has last-write-wins** — two-device users could lose data; you want to catch reports from a small cohort first.
3. **Cost curve is untested in production** — without the thumbnail optimization, 10K MAU = ₹4,000/mo; a 20% rollout to a larger install base could spike the bill before you notice.
4. **minSdk change** — bumping to 24 cuts off some existing testers. 5% lets you see install-failure ratios.

### Budget alerts to configure before launch
- Firebase console → **Budget alerts at $20 / $50 / $100 USD**
- Play Console → **Vitals alert: ANR rate >0.47%, crash rate >1.09%** (Google's "bad behavior" thresholds)
- Crashlytics → **Velocity alert: any new fatal exceeding 50 events/hour**

---

## 🔍 Report Artifacts

- [`SECURITY_AUDIT_REPORT.md`](SECURITY_AUDIT_REPORT.md) — Agent 1
- [`PERFORMANCE_REPORT.md`](PERFORMANCE_REPORT.md) — Agent 2
- [`EDGE_CASES_REPORT.md`](EDGE_CASES_REPORT.md) — Agent 3
- [`COST_SCALE_REPORT.md`](COST_SCALE_REPORT.md) — Agent 4

---

## Final Verdict

> **🔴 NO-GO today.**
> **🟢 GO-WITH-CAUTION after B1–B11 are verified fixed (~2 days).**
> **Start at 5% rollout. Advance only on green signal.**

Ikeep's architecture is genuinely good — Riverpod and GoRouter discipline is consistent, SQLite indexes are well-chosen, household sync has real field-level conflict resolution, rules fail closed, no secrets in repo. This is not a rewrite; it is a polish pass.

The user said "I would rather delay 2 days than ship a broken app." That is exactly the trade here. Two days of the 11 blockers above converts a risky launch into a confident one.
