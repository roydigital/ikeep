# Ikeep App Update System (Android)

## Architecture Summary

Ikeep now uses a hybrid Android update architecture:

1. **Layer A: Google Play In-App Updates (source of truth for real update availability)**
   - Implemented via `in_app_update`.
   - Supports:
     - Flexible update flow (download while using app).
     - Immediate update flow (critical flow handled by Google Play UI).
   - Works for:
     - Production.
     - Closed testing tracks when the app is installed from Google Play.

2. **Layer B: Firebase Remote Config policy layer (custom messaging + force/optional control)**
   - Remote keys control:
     - Latest version metadata.
     - Minimum supported version.
     - Optional vs force mode.
     - UI title/message/changelog.
   - Lets the app show custom in-app messaging while still relying on Play APIs for real update execution.

3. **Decision Engine**
   - Merges:
     - Installed app version.
     - Play update availability/install status.
     - Remote policy.
   - Emits one effective state:
     - `noUpdate`
     - `optionalUpdateAvailable`
     - `forceUpdateRequired`
     - `downloadingUpdate`
     - `downloadedPendingInstall`
     - `updateError`

4. **UI**
   - `MainScreen`:
     - Optional update banner.
     - Optional update dialog on launch/resume (cooldown-aware).
     - Force update full-screen blocker.
   - `SettingsScreen`:
     - App version tile.
     - Check for updates.
     - Update now CTA + status label.

## Dependencies Added

- `in_app_update`
- `firebase_remote_config`
- `firebase_analytics`

## Firebase Remote Config Keys

Required keys:

- `latest_version_code_android` (int)
- `latest_version_name_android` (string)
- `minimum_supported_version_code_android` (int)
- `update_mode` (`none` / `optional` / `force`)
- `update_title` (string)
- `update_message` (string)
- `show_changelog` (bool)
- `changelog_text` (string)
- `play_store_url` (string)
- `is_update_live` (bool)

Optional enhancement keys:

- `schedule_optional_reminder_after_dismiss` (bool)
- `optional_reminder_delay_minutes` (int)

## Testing Checklist

### 1) Local debug build (`flutter run`)
- Expected:
  - Remote policy UI logic works.
  - Play In-App Update flow usually **does not** fully execute.
- Reason:
  - In-App Update is tied to Play-distributed installs and real Play versions.

### 2) Local release build (side-loaded APK/AAB)
- Expected:
  - Same as debug for local logic.
  - Play update flow is not a reliable validation path.

### 3) Play Internal / Closed Testing build (installed from Play track)
- Required for real validation of in-app update behavior.
- Validate:
  - Optional update banner/dialog appears after publishing higher build.
  - Flexible flow starts and reaches downloaded state.
  - Download completion prompts install/restart.
  - Force policy blocks app usage if min-supported version is not met.

### 4) Production build
- Validate staged rollout behavior and final messaging.
- Confirm fallback store URL opens correctly when in-app flow is unavailable.

## Important Testing Limitation

Google Play In-App Updates are **not reliably testable** with local APK installs alone.  
For closed testing support, testers must install from the Play testing track they are opted into.

## Edge Cases Handled

- Remote Config fetch failures/offline: use cached/default policy.
- Play API errors: surfaced as `updateError` without freezing loading state.
- Resume spam prevention: throttled resume checks.
- Optional prompt spam prevention: session-dismiss + cooldown persistence.
- Flexible update completion: install-state listener updates UI to `downloadedPendingInstall`.
- Fallback when Play flow not allowed: open Play Store URL.
