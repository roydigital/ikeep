# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

---

## Project Overview

> Important: The social sharing / Network feature (household sharing, nearby lending, and borrow requests) is a future aspect only and is not part of the current required app scope. Keep the detailed notes in this document for future implementation reference, but do not prioritize building or restoring that feature right now.

**App Name:** Ikeep — "Your memory, organized."
**Platform:** Android (Flutter)
**Developer Context:** Built by a non-developer using AI coding assistants. All code must be clean, well-commented, and easy to understand. **Build one feature at a time. Do not combine multiple features in a single implementation.**

Ikeep helps users remember where they stored rarely-used items. Core flow:
1. **Save (10s):** Photo → name → location → save.
2. **Find (5s):** Search by name/tag/location → see photo + location + timestamp.

---

## Commands

```bash
flutter pub get                          # Install/update dependencies (run after any pubspec.yaml change)
flutter run                              # Run on connected device/emulator
flutter test                             # Run all tests
flutter test test/path/to/test.dart      # Run a single test
flutter build apk                        # Build Android release APK
flutter clean                            # Clean build artifacts
```

---

## Actual Tech Stack

| Layer | Technology |
|-------|-----------|
| Framework | Flutter (latest stable) |
| State Management | **Riverpod** (flutter_riverpod) — exclusively |
| Local Database | **SQLite** via `sqflite` / `sqflite_common_ffi` |
| Routing | **GoRouter** (`go_router`) |
| Image Handling | `image_picker`, `flutter_image_compress` |
| Notifications | `flutter_local_notifications` |
| Settings | `shared_preferences` |
| Auth | **Firebase Auth** (`firebase_auth`) + **Google Sign-In** (`google_sign_in`) |
| Cloud Database | **Cloud Firestore** (`cloud_firestore`) — household sharing, nearby items, borrow requests |
| Location | **Geolocator** (`geolocator`) + **Geocoding** (`geocoding`) — GPS → locality string |
| Permissions | `permission_handler` — location permission requests |
| Cloud Sync (future) | Firebase Storage for images (not yet wired) + Appwrite sync stub |
| ML (future) | Google ML Kit stub |

> Firebase Auth and Firestore are actively used for the Network feature (household sharing + nearby lending). Local data is still SQLite-first. Images remain **local file paths**, not cloud URLs.

---

## Actual Folder Structure

```
lib/
├── main.dart                     # Entry: Firebase.initializeApp, NotificationService, ProviderScope
├── app.dart                      # IkeepApp (ConsumerWidget): router + theme + settings wiring
│
├── core/
│   ├── constants/                # app_constants, db_constants, storage_constants, notification_constants
│   ├── errors/                   # app_exception.dart, failure.dart
│   └── utils/                    # uuid_generator, date_formatter, path_utils, fuzzy_search
│
├── domain/
│   └── models/
│       ├── item.dart             # Item (with lending + visibility fields)
│       ├── location_model.dart   # LocationModel (hierarchical)
│       ├── item_location_history.dart # History entry (with member attribution)
│       ├── item_visibility.dart  # ItemVisibility enum: private_, household, nearby
│       ├── household.dart        # Household (local SQLite model — id, ownerId, name, memberIds)
│       ├── household_member.dart # HouseholdMember (local SQLite model)
│       ├── household_member_lookup_state.dart # HouseholdMemberLookupState — state for email-based member search UI
│       ├── app_user.dart         # AppUser — minimal Firestore user model (uid, email, displayName, householdId)
│       ├── borrow_request.dart   # BorrowRequest (local SQLite model)
│       ├── shared_item.dart      # SharedItem (Firestore model — household catalog)
│       ├── nearby_item.dart      # NearbyItem (Firestore model — geo-based public catalog)
│       ├── firestore_borrow_request.dart # FirestoreBorrowRequest (Firestore model)
│       ├── ml_label.dart         # MlLabel (stub)
│       └── sync_status.dart      # SyncStatus
│
├── data/
│   ├── database/
│   │   ├── database_helper.dart  # SQLite singleton (v8), creates all 7 tables
│   │   ├── item_dao.dart         # CRUD for items table
│   │   ├── location_dao.dart     # CRUD for locations table
│   │   ├── history_dao.dart      # CRUD for item_location_history (with member attribution)
│   │   ├── borrow_request_dao.dart   # CRUD for borrow_requests table
│   │   ├── household_member_dao.dart # CRUD for household_members table
│   │   ├── household_dao.dart    # CRUD for households table (upsert, getById, getLatest, delete)
│   │   └── pending_sync_dao.dart # Queue for offline-first cloud sync (enqueue, getAll, deleteById)
│   └── repositories/
│       ├── item_repository.dart / item_repository_impl.dart
│       ├── location_repository.dart / location_repository_impl.dart
│       ├── history_repository.dart / history_repository_impl.dart
│       ├── borrow_request_repository.dart / borrow_request_repository_impl.dart
│       └── household_repository.dart / household_repository_impl.dart
│
├── providers/
│   ├── database_provider.dart    # Riverpod providers for DAOs and DatabaseHelper
│   ├── repository_providers.dart # Riverpod providers for repositories
│   ├── item_providers.dart       # allItemsProvider, searchResultsProvider, ItemsNotifier
│   ├── location_providers.dart   # Location Riverpod providers
│   ├── history_providers.dart    # History Riverpod providers
│   ├── settings_provider.dart    # AppSettings + SettingsNotifier (SharedPreferences-backed)
│   ├── service_providers.dart    # notificationServiceProvider, etc.
│   ├── household_providers.dart  # Auth state, household members, shared items, borrow requests
│   ├── nearby_providers.dart     # Locality, nearby items, combined catalog, all request providers
│   ├── borrow_request_providers.dart # Local borrow request providers
│   ├── sync_providers.dart       # SyncService providers
│   └── ml_label_providers.dart   # ML label providers
│
├── services/
│   ├── notification_service.dart # flutter_local_notifications: expiry + "still there" + lent reminders
│   ├── image_service.dart        # Image pick + compress + local save
│   ├── sync_service.dart         # Cloud sync orchestration (interface)
│   ├── firebase_sync_service.dart# Firebase backup/sync for items & locations
│   ├── household_cloud_service.dart # Firestore ops for household sharing & borrow requests
│   ├── household_sync_service.dart  # Real-time Firestore listener sync for household items + history; uses PendingSyncDao for offline queue
│   ├── nearby_cloud_service.dart # Firestore ops for geo-based nearby lending
│   ├── location_service.dart     # GPS → locality string (cached 24h)
│   ├── appwrite_sync_service.dart# Appwrite cloud sync (stub)
│   └── ml_label_service.dart     # ML Kit label extraction (stub)
│
├── theme/
│   ├── app_colors.dart           # All color constants
│   ├── app_dimensions.dart       # Spacing, radii, sizes
│   └── app_theme.dart            # AppTheme.lightTheme / AppTheme.darkTheme
│
├── routing/
│   ├── app_routes.dart           # AppRoutes class with static path constants (incl. /settings/manage-family)
│   └── app_router.dart           # routerProvider (GoRouter) with onboarding redirect logic
│
├── screens/
│   ├── home/home_screen.dart
│   ├── save/save_screen.dart
│   ├── search/search_screen.dart
│   ├── detail/item_detail_screen.dart
│   ├── rooms/rooms_screen.dart
│   ├── rooms/add_new_room_screen.dart
│   ├── onboarding/onboarding_screen.dart
│   ├── settings/settings_screen.dart
│   ├── settings/household_settings_screen.dart  # Manage household: create/view, add members via email lookup (route: /settings/manage-family)
│   └── network/network_screen.dart  # Network tab: Catalog, Activity, My Lends
│
└── widgets/
    ├── app_nav_bar.dart              # 5 tabs: Items, Locations, Search, Network, Settings
    ├── item_activity_timeline.dart   # Timeline widget showing item location history (used in ItemDetailScreen)
    └── item_visibility_toggle.dart   # Toggle widget for private/household visibility (requires active household)
```

---

## Architecture: Layered + Riverpod

```
Screens / Widgets
      ↓ watch/read
  Providers (Riverpod)
      ↓ use
  Repositories (abstract interface + impl)
      ↓ use
  DAOs (SQLite via DatabaseHelper)
```

- **Domain models** (`domain/models/`) are plain Dart classes with `toMap()` / `fromMap()` for SQLite. Firestore models (`SharedItem`, `NearbyItem`, `FirestoreBorrowRequest`) use `fromFirestore()` / `fromMap()` factories for Firestore documents.
- **DAOs** (`data/database/`) handle raw SQL; all receive `DatabaseHelper`.
- **Repositories** (`data/repositories/`) implement abstract interfaces; injected via Riverpod providers in `repository_providers.dart`. Some repositories (e.g., `HouseholdRepositoryImpl`) combine local SQLite + Firestore cloud services.
- **Cloud services** (`services/`) handle Firestore reads/writes directly. `HouseholdCloudService` and `NearbyCloudService` are not wrapped by DAOs — they talk to Firestore, not SQLite. `HouseholdSyncService` bridges both layers: it listens to Firestore real-time snapshots and writes changes into local SQLite via DAOs; failed writes are queued in `pending_sync_operations` and replayed on reconnect.
- **Providers** expose `FutureProvider`, `StateNotifierProvider`, etc. Mutations go through `*Notifier` classes which call `ref.invalidate(...)` to refresh derived providers.
- **Routing** is GoRouter with a `redirect` guard: if onboarding is incomplete, redirect to `/onboarding`; otherwise go to `/home`. Routes are defined in `AppRoutes` (use `AppRoutes.itemDetailPath(uuid)` for parameterized paths). Current named routes: `/`, `/onboarding`, `/home`, `/save`, `/item/:uuid`, `/rooms`, `/settings`, `/settings/manage-family`, `/search`.

### SQLite Schema (7 tables, v8)
- `items` — core item data; `image_paths` and `tags` stored as JSON strings; includes lending fields (`is_lent`, `lent_to`, `lent_on`, `expected_return_date`, `lent_reminder_after_days`, `is_available_for_lending`) and `visibility` (private/household/nearby)
- `locations` — hierarchical (self-referencing `parent_uuid`), tree via `full_path`
- `item_location_history` — log of location changes per item; includes `moved_by_member_uuid` and `moved_by_name` for household attribution
- `pending_sync_operations` — offline-first cloud sync queue; managed by `PendingSyncDao` (enqueue, getAll, deleteById); `HouseholdSyncService` flushes on reconnect
- `borrow_requests` — local borrow request queue (status: pending/approved/denied/cancelled); FK to items
- `household_members` — local cache of household members synced from Firestore
- `households` — local cache of household doc (id, ownerId, name, memberIds as JSON); managed by `HouseholdDao`

### Firestore Collections (Cloud)
- `users/{uid}` — User profile with `householdId`, `isOwner`
- `households/{id}` — Household doc with `ownerUid`, `name`, timestamps
- `households/{id}/members/{uid}` — Member profiles
- `households/{id}/shared_items/{itemUuid}` — Shared item catalog (household scope)
- `households/{id}/borrow_requests/{requestId}` — Household borrow requests
- `household_invites/{docId}` — Pending invitations
- `nearby_items/{itemUuid}` — Public item listings (geo-based, top-level)
- `nearby_borrow_requests/{requestId}` — Nearby borrow requests
- `users/{uid}/items/{itemUuid}` — Backed-up items (sync)
- `users/{uid}/locations/{locationUuid}` — Backed-up locations (sync)

### Key Providers to Know
| Provider | Type | Purpose |
|----------|------|---------|
| `settingsProvider` | `StateNotifierProvider<SettingsNotifier, AppSettings>` | Theme mode, onboarding flag, notification toggles |
| `allItemsProvider` | `FutureProvider<List<Item>>` | All non-archived items |
| `searchResultsProvider` | `FutureProvider<List<Item>>` | SQL pre-filter + in-memory fuzzy sort |
| `itemSearchQueryProvider` | `StateProvider<String>` | Current search query |
| `itemsNotifierProvider` | `StateNotifierProvider<ItemsNotifier, bool>` | save / update / archive / delete mutations |
| `routerProvider` | `Provider<GoRouter>` | App router; watches `settingsProvider` for redirect |
| `householdDaoProvider` | `Provider<HouseholdDao>` | DAO for local `households` SQLite table |
| `pendingSyncDaoProvider` | `Provider<PendingSyncDao>` | DAO for local `pending_sync_operations` SQLite queue |
| `householdSyncServiceProvider` | `Provider<HouseholdSyncService>` | Real-time Firestore sync; call `startSync(householdId)` to activate |
| `authStateProvider` | `StreamProvider<User?>` | Firebase Auth state stream |
| `isSignedInProvider` | `Provider<bool>` | Whether user is authenticated |
| `hasHouseholdProvider` | `Provider<bool>` | Whether current user belongs to a household |
| `currentHouseholdProvider` | `FutureProvider<Household?>` | Full Household model for current user |
| `currentHouseholdIdProvider` | `FutureProvider<String?>` | Current user's household ID |
| `householdMembersProvider` | `FutureProvider<List<HouseholdMember>>` | All household members |
| `householdSharedItemsProvider` | `StreamProvider<List<SharedItem>>` | Items shared in household; re-emits on every local Firestore sync write |
| `householdSyncBootstrapProvider` | `FutureProvider<SyncResult>` | Starts/stops Firestore listeners based on household membership |
| `householdLocalChangesProvider` | `StreamProvider<void>` | Emits void whenever HouseholdSyncService writes a local change |
| `householdMemberLookupProvider` | `StateNotifierProvider<HouseholdMemberLookupController, HouseholdMemberLookupState>` | Email-based user search for adding household members |
| `allIncomingRequestsProvider` | `FutureProvider<List<FirestoreBorrowRequest>>` | Combined household + nearby incoming requests |
| `allOutgoingRequestsProvider` | `FutureProvider<List<FirestoreBorrowRequest>>` | Combined household + nearby outgoing requests |
| `allPendingIncomingCountProvider` | `Provider<int>` | Badge count for Network tab |
| `userLocalityProvider` | `FutureProvider<String?>` | User's GPS-derived locality (cached 24h) |
| `nearbyItemsProvider` | `FutureProvider<List<NearbyItem>>` | Nearby items from strangers in same locality |
| `combinedCatalogProvider` | `FutureProvider<CombinedCatalog>` | Merged household + nearby items for Network catalog |

---

## Design System

### Colors (Dark Theme — Primary)
Never hardcode colors — use `app_colors.dart` constants, then reference via `AppTheme`.

| Role | Hex |
|------|-----|
| Background Primary | `#0D0B1A` |
| Background Secondary | `#1E1035` |
| Surface / Cards | `#1A1530` / `#2A2440` |
| Primary Accent | `#7C3AED` |
| Primary Light | `#A78BFA` |
| Text Primary | `#FFFFFF` |
| Text Secondary | `#9CA3AF` |
| Card Border | `#3D3560` |
| Success | `#10B981` |
| Warning | `#F59E0B` |
| Error | `#EF4444` |

### Spacing (from `app_dimensions.dart`)
- Screen horizontal padding: 16–20dp
- Card border radius: 12–16dp | Card spacing: 12dp
- Camera FAB: 64dp | Bottom nav: 64dp
- Search bar: 48–52dp tall, 24dp radius (pill)

---

## Current Screen Status

| Screen | Status |
|--------|--------|
| Onboarding | Built |
| Home | Built |
| Save | Built |
| Search | Built |
| Item Detail | Built |
| Rooms / Add Room | Built |
| Settings | Built |
| Household Settings | Built (`/settings/manage-family`) — create household, add members via email lookup, view members list |
| Network | Future aspect only for now; detailed notes retained below for later implementation |
| Login / Auth | Built (currently used for account/backup flows; previous Network-related notes remain below for future reference) |
| History Timeline | **Not built** |
| Collections | **Not built** |

### Navigation
Bottom nav currently reflects the active core product scope. The previous Network-tab notes below are retained only as future reference.

### Network Screen (3 tabs) - Future Aspect Reference
1. **Catalog** — Browse shared items from household members + nearby strangers (combined view)
2. **Activity** — Manage incoming/outgoing borrow requests (with badge for pending count)
3. **My Lends** — Track items the user has lent out

Shows a sign-in prompt if the user is not authenticated.

---

## Development Rules

- **Build one feature at a time.**
- **No hardcoded colors or strings** — use `app_colors.dart` and `core/constants/`.
- **State management = Riverpod only.** No `setState` in complex widgets. No Provider package.
- **Routing = GoRouter only.** Add new routes to `AppRoutes` + `routerProvider`. Never use `Navigator.push` directly for main navigation.
- **New screens need a route** in both `app_routes.dart` and `app_router.dart`.
- **Image compression:** Max 1MB per photo before saving locally.
- **Minimum SDK:** Android API 21. All code must be null-safe.
- **Use `const` constructors** wherever possible.

### Naming Conventions
- Files: `snake_case` | Classes: `PascalCase` | Variables/Functions: `camelCase`
- SQLite table/column names: `snake_case` — all defined in `db_constants.dart`

### Git Workflow
- Commit after every complete feature/screen.
- Format: `"feat: Added [feature name]"` or `"fix: Fixed [bug description]"`
- Remote: `https://github.com/roydigital/ikeep.git` (main branch)

---

## Key Architectural Concepts

### Hybrid Data Model (Local + Cloud)
- **SQLite** is the source of truth for items, locations, history, and local borrow requests/members
- **Firestore** is used for cross-device features: household sharing, nearby lending, borrow request coordination
- Some models exist in both layers: `BorrowRequest` (local) vs `FirestoreBorrowRequest` (cloud), with separate status enums (local has 4 statuses, Firestore has 5 including `returned`)

### Two Sharing Scopes
| Scope | Access Model | Firestore Location | Discovery |
|-------|-------------|-------------------|-----------|
| **Household** | Invite-based, private | `households/{id}/shared_items/` | Only household members see each other's items |
| **Nearby** | Geo-based, public | `nearby_items/` (top-level) | Anyone in the same locality can see and request items |

### Item Visibility (ItemVisibility enum)
- `private_` (default) — Only visible on owner's device
- `household` — Shared with household members
> Note: `nearby` (geo-based public) was removed from the enum. Only `private_` and `household` exist.

### Locality Strategy
- Never stores raw GPS coordinates (privacy)
- Reverses GPS coordinates to a locality string (e.g., "HSR Layout, Bangalore")
- Caches locality for 24 hours in SharedPreferences with manual refresh override

### Borrow Request Lifecycle
1. Requester sends request → status: `pending`
2. Owner approves → status: `approved`; item marked as lent; other pending requests auto-denied
3. OR Owner denies → status: `denied`
4. Requester can cancel → status: `cancelled`
5. (Firestore only) Item returned → status: `returned`

### Item Lending / Sharing Fields (on Item model)
- `isLent`, `lentTo`, `lentOn`, `expectedReturnDate`, `lentReminderAfterDays` — track active lends
- `isAvailableForLending` — whether the item can be requested by others
- `seasonCategory` — string tag for seasonal classification (default: `'all_year'`)
- `visibility` — controls sharing scope (`private_` or `household`; `nearby` was removed)
- `householdId` — ID of the household this item is shared with (null for private items)
- `sharedWithMemberUuids` — list of member UUIDs this item is explicitly shared with (empty = all household members); cleared when item goes private

### Notification Channels
- `ikeep_expiry` — Expiry reminders
- `ikeep_still_there` — "Still there?" reminders
- `ikeep_lent` — Lent item return reminders

---

## MVP Build Order (Remaining)

### Next Up
1. History screen (timeline: saved/moved/archived events from `item_location_history`)
2. Cloud sync (Firebase Storage for images, Firestore for item data backup)
3. Collections screen (items grouped by room/location)

### Future (V2)
- Voice search, ML Kit auto-labeling
- Android home screen widget
- Offline sync with conflict resolution

---

## Do NOT

- Use GetX — Riverpod only
- Use `Navigator.push` for main navigation — GoRouter only
- Hardcode colors — use `app_colors.dart`
- Implement multiple features at once
- Store full-resolution images (always compress first)
- Add a screen without a route in `app_routes.dart` + `app_router.dart`
- Use `setState` in any widget that touches shared state — use Riverpod notifiers
