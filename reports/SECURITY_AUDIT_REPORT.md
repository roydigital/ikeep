# SECURITY_AUDIT_REPORT.md

**App:** Ikeep (Flutter + Firebase)
**Project:** ikeep-1af18
**Date:** 2026-04-20
**Auditor:** Agent 1 — Security

---

## Severity Summary

| Severity | Count |
|---|---|
| Critical | 0 |
| High | 2 |
| Medium | 4 |
| Low | 4 |

Firebase rules fail-closed, no hardcoded secrets, no cleartext HTTP, `google-services.json` properly gitignored, GPS coords never persisted (only locality strings). Foundations are sound.

---

## Critical Findings
None.

---

## High Findings

### H1 — Firebase security rules not committed to main branch
- **Location:** Rules exist only in `.claude/worktrees/upbeat-proskuriakova/firestore.rules` and `storage.rules`. `git ls-files` shows neither tracked at repo root. No `firebase.json` at repo root to map them for CI deploys.
- **Impact:** No source-of-truth / review trail for the rules actually deployed to `ikeep-1af18`. Risk that prod rules drift or have been set via console to `allow read, write: if true` and nobody knows.
- **Fix:** Commit `firestore.rules` + `storage.rules` + a `firebase.json` at repo root. Verify live rules via `firebase deploy --only firestore:rules,storage` before launch.

### H2 — Firestore rules / code field-name mismatch breaks household membership
- **Location:** `firestore.rules:51,61,68` expects field `memberIds`, but `lib/services/household_cloud_service.dart:182,282,347` and `lib/domain/models/household.dart:67` write the field as `members`.
- **Impact:** Fails **closed** (safe — not a leak), but non-owner household members silently cannot read household docs, `shared_items`, `borrow_requests`, or `members` subcollection.
- **Fix:** Either rename the Firestore field to `memberIds` consistently across code + model + rules, or change rules to reference `resource.data.members`. **Launch-blocking only if household sharing is user-visible in v1.**

---

## Medium Findings

### M1 — Cross-user reads likely needed but not granted (email-based member lookup)
- `lib/services/household_cloud_service.dart:120-147` (`getUserByEmail`) queries `collection('users').where('email', ...)`, but rules (`firestore.rules:31-37`) restrict `users/{uid}` to `isOwner(uid)`. Query always returns permission-denied.
- **Risk:** Household invites silently fail. Relaxing this rule would enable email enumeration attacks.
- **Fix:** If household invites ship, implement a callable Cloud Function for email → uid resolution.

### M2 — Auth token retry state is process-global but not reset on sign-out
- `lib/providers/auth_providers.dart:9` — module-level global `bool _interactiveGoogleSignInInProgress`.
- **Risk:** If interactive sign-in throws before `finally`, flag sticks and blocks silent restoration.
- **Fix:** Move to Riverpod `StateProvider`, or ensure `finally` is bulletproof.

### M3 — Personal sync permission-denied handling is raw
- `lib/services/firebase_sync_service.dart:567,1905` catches `FirebaseException` generically; `permission-denied` (expired token / rule denial) surfaces as raw `e.toString()` in snackbars.
- **Fix:** Branch on `FirebaseException.code == 'permission-denied'` → trigger silent token refresh or force re-auth.

### M4 — Silent partial upload failure writes corrupted metadata
- `lib/services/firebase_sync_service.dart:283-291` — if Storage upload fails, code sets `imageResult = ImageUploadResult(downloadUrls: [], storagePaths: [])` and still writes item metadata with empty `images` list and `lastSyncedAt` set. Restored devices see image-less items.
- **Fix:** Abort item-doc write if any required upload fails; surface to user with retry CTA.

---

## Low Findings

- **L1 — Path logging in release logcat.** `lib/services/firebase_image_upload_service.dart:276` logs local file paths. Gate `debugPrint` calls behind `kDebugMode`.
- **L2 — Owner email exposed to every household member.** `lib/services/household_cloud_service.dart:180,191,205,270,292,345,356` — acceptable by design, but disclose in privacy policy.
- **L3 — Over-broad location permission.** `AndroidManifest.xml:6-7` declares both `ACCESS_FINE_LOCATION` + `ACCESS_COARSE_LOCATION`, but `lib/services/location_service.dart:51` uses `LocationAccuracy.low`. Drop `ACCESS_FINE_LOCATION` to reduce Play Console sensitive-permission surface.
- **L4 — MainActivity `exported=true`.** `AndroidManifest.xml:25-46` — correct for LAUNCHER activity; no deep-link/browsable filters = no tapjacking exposure. OK.

---

## Input Validation & Injection

| Vector | Risk | Status |
|---|---|---|
| SQL injection | LOW | All DAOs use parameterized `?` placeholders (verified). `item_dao.dart:222` builds LIKE with positional arg — safe. |
| XSS in text fields | N/A | Native Flutter widgets, not WebView — no HTML rendering. |
| Unicode / emoji / RTL / BOM | LOW | UTF-16 handled by Dart/SQLite/Firestore. `\u0000` in names could fail Firestore write — sanitize. |
| Image upload validation | OK | `ImageOptimizerService` validates format, enforces 220KB target + WebP re-encode. |
| PDF upload validation | OK | Soft 2MB, hard 10MB enforced in `PdfOptimizerService`. |

---

## Launch Blockers (Security)

1. **Commit `firestore.rules` + `storage.rules` + `firebase.json` to main branch** with CI deploy. Verify deployed rules match the reviewed version.
2. **Fix `members` / `memberIds` mismatch** if household sharing is user-visible at launch (else defer).
3. **Abort item writes on partial upload failure** (M4) — prevents corrupted metadata.

---

## Verdict

**SECURITY GO WITH FIXES**

The app's fundamentals are sound — rules fail-closed, no secrets leaked, no cleartext traffic, minimal/justified permissions, GPS never persisted, images and PDFs validated. The only launch-blocking issue is getting Firebase rules into source control and confirming deployed rules match reviewed ones. Silent partial-upload corruption (M4) should also be fixed before wide rollout.
