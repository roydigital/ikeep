# Premium Feature Rebuild Contract

This release removes all monetization and paywall behavior so the app can ship without Google Play billing during closed-testing review.

## Archive Reference

- Git ref: `refs/archive/premium-pre-detach-20260324-145524`
- Commit: `6158cecce7feb716eabfc40078b35377a2849d95`

This archived ref captures the monetized implementation before detachment, including the uncommitted worktree state that existed at the time of removal.

## What Was Removed

- Billing runtime bootstrap in `lib/app.dart`
- Premium state and plan handling in `lib/providers/settings_provider.dart`
- Billing service/provider wiring in `lib/providers/service_providers.dart`
- Subscription-aware sync quota checks in `lib/services/firebase_sync_service.dart`
- Premium backup quota enforcement in `lib/providers/item_providers.dart`
- Paywall and upgrade entry points in:
  - `lib/screens/save/save_screen.dart`
  - `lib/screens/detail/item_detail_screen.dart`
  - `lib/screens/settings/settings_screen.dart`
- Deleted files:
  - `lib/screens/settings/paywall_screen.dart`
  - `lib/widgets/google_play_billing_listener.dart`
  - `lib/services/google_play_billing_service.dart`
  - `lib/core/constants/subscription_constants.dart`

## Current Release Defaults

- Cloud backup limit is unified to `1000` items.
- Cloud backup warning threshold is unified to `900` items.
- Photo limit is unified to `3` photos per item.
- Subscription, purchase, restore, and upgrade UI/copy has been removed from app and review-visible web pages.
- Legacy prefs `is_premium` and `app_plan` are cleared on load so old installs do not carry stale premium state.

## Rebuild Inputs Required Later

When re-enabling monetization, the prompt should include:

- Google Play Billing product ID for the monthly plan
- Google Play Billing product ID for the yearly plan
- Final pricing/copy if the release messaging should differ from the archived implementation
- Whether the release should keep the same free-vs-paid limits (`50` free cloud backups, `1000` paid cloud backups, `1` free photo, `3` paid photos) or change them

## Exact Rebuild Targets

Use the archived ref as the source of truth for the premium implementation shape. Rebuild the feature by restoring these behaviors:

- `AppSettings` regains premium state with:
  - `AppPlan` enum
  - `isPremium`
  - persistent keys `is_premium` and `app_plan`
  - notifier methods to mutate plan state after purchase/restore
- `lib/app.dart` wraps the app with the billing listener again so purchase updates are observed globally
- `lib/providers/service_providers.dart` restores `googlePlayBillingServiceProvider` and reintroduces plan-aware sync quota wiring
- `lib/screens/settings/paywall_screen.dart` is restored as the purchase surface
- `lib/screens/settings/settings_screen.dart` regains:
  - upgrade CTA
  - plan badge / manage subscription affordance
  - subscription management sheet
- `lib/screens/save/save_screen.dart` and `lib/screens/detail/item_detail_screen.dart` regain:
  - upgrade prompts when free limits are reached
  - free-vs-paid quota messaging
  - photo gating tied to plan state
- `lib/core/constants/subscription_constants.dart` is restored with:
  - free/premium cloud backup limits
  - free/premium photo limits
  - Google Play manage URL
  - testing/setup notices
  - Google Play product IDs

## Rebuild Procedure

1. Diff the current branch against `refs/archive/premium-pre-detach-20260324-145524`.
2. Restore the deleted premium files from that ref.
3. Reapply premium state fields/methods in the settings provider.
4. Rewire app bootstrap, providers, and sync quota checks to use billing state.
5. Restore save/detail/settings upgrade entry points and subscription UI.
6. Replace the archived placeholder Billing IDs with the provided production IDs.
7. Reintroduce any legal/help-center subscription copy only if the release actually ships monetization.

## Prompt Shortcut

If a future request says:

`Rebuild the Premium Feature with Google Play Billing IDs: <monthly_id>, <yearly_id>`

then the implementation should restore the archived premium flow from the ref above, wire those IDs into the billing constants/service, and bring back the original premium gating/UI across settings, save, detail, and sync behavior.
