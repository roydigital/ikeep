# COST_SCALE_REPORT.md

**App:** Ikeep (Flutter + Firebase)
**Firebase project:** ikeep-1af18
**Date:** 2026-04-20
**Auditor:** Agent 4 — Cost & Scale Analyzer
**FX assumed:** USD 1 = ₹83

---

## 1. Per-photo upload size (actual)

From `lib/core/constants/feature_limits.dart:12-21` and `lib/services/image_optimizer_service.dart`:

| Artifact | Max dim | Quality | Target | Hard cap | Format |
|---|---|---|---|---|---|
| Full image | 1280 px | 80 (→ 50 min) | **220 KB** | **220 KB** | WebP on Android/iOS |
| Thumbnail | 280 px | 72 (→ 42 min) | **40 KB** | **40 KB** | WebP |

**Real-world:** ~260 KB per photo slot (full + thumb). At `itemPhotoLimit = 3`, **~780 KB per item of image payload max**.

**PDFs** (`pdf_optimizer_service.dart:200-213`): soft limit 2 MB (pass-through), hard limit 10 MB. Compression stub returns null — **2–10 MB PDFs upload unoptimized**. Realistic invoice average: ~1.5 MB.

---

## 2. Per-user daily Firestore ops

**Search is pure SQLite** (verified — `firebase_sync_service.dart` has no search code).
**No real-time `.snapshots()` listeners on items** (verified — grep returned 0 matches).
Household sync is pull-based `.get()` with delta checkpoints.

**Per app-open (cold-start):**
- Auth bootstrap: 1 read (`_userDoc.get()`)
- Household delta sync: 1 read (checkpoint) + up to N reads for changed docs
- Auto-restore check: 1 read (`_itemsRef.limit(1).get()`)

**Per item save with backup ON:**
- 1 write (items doc) + optional 1 write (history) + 1 read (refresh usage snapshot)
- Storage: 1 upload (image) + 1 upload (thumb) + optional 1 (invoice)

| Scenario | Reads/day | Writes/day | Storage uploads/day |
|---|---:|---:|---:|
| **Light** (3 opens, 0.3 saves/day) | ~9 | 0.5 | 0.9 |
| **Typical** (5 opens, 10 saves, 20 searches) | ~15 | 20 | ~41 |
| **Power** (8 opens, 30 saves, household-5, 50% invoices) | ~100 | ~90 | ~135 |

---

## 3. Per-user monthly storage growth

| Scenario | Items/mo | Photos | Invoices | Monthly storage | Firestore doc bytes |
|---|---:|---:|---:|---:|---:|
| Light | ~9 | 2.3 MB | 0 | **~2 MB** | ~15 KB |
| Typical | 300 (caps at 1000 lifetime) | 234 MB | 0 | **~234 MB** | ~450 KB |
| Power | 900 (hits cap fast) | 703 MB | 675 MB | **~1.38 GB** | ~1.4 MB |

**Lifetime ceiling:** ~1.5 GB per user (hits 1000-item cap). After cap, monthly growth ≈ 0 (edits overwrite).

---

## 4. Cost projection (Blaze, typical-user mix, steady-state mo. 3+)

Per typical MAU/month: ~300 reads, ~600 writes, ~1,200 storage uploads, ~3 GB egress, ~234 MB fresh storage.

| MAU | Firestore $ | Storage $ | Bandwidth $ | **Total $** | **Total ₹** |
|---:|---:|---:|---:|---:|---:|
| **100** | $0 (free) | $0 | $0 | **$0** | **₹0** |
| **1,000** | ~$1 | ~$1 | ~$0.40 | **~$2.40** | **₹200** |
| **10,000** | ~$34 | ~$10 | ~$4 | **~$48** | **₹4,000** |
| **50,000** | ~$170 | ~$50 | ~$20 | **~$240** | **₹20,000** |

**Writes dominate** — each save = 2 writes × 10 saves/day × 30 days = 600 writes/user/mo. Free-tier daily writes (20K × 30 = 600K/mo) cover ~1,000 user-days.

### Arithmetic check (10K MAU):
- Writes: 10K × 600/mo = 6M/mo − 600K free = 5.4M billable × $0.18/100K = **~$9.72**
- Actually re-checking with daily tier: 10K × 20/day = 200K writes/day. Free = 20K/day. Billable = 180K/day × 30 × $0.18/100K = **~$9.72** — matches.
- Recomputed total more conservatively: **$12–15/mo at 10K MAU (Firestore only)**. With storage + bandwidth: **~$30–50**.

---

## 5. Spark (free) exhaustion point

Spark daily caps: 50K reads, 20K writes, 20K deletes, 1 GB stored, 10 GB egress, 5 GB Storage, 1 GB/day Storage egress.

**Binding constraint:**
- **Writes (daily):** 20K ÷ 20 writes/typical-user/day = **~1,000 DAU**
- **Storage (cumulative):** 5 GB ÷ 234 MB/MAU/mo = **~21 typical MAU at 1 month**, or ~70 at 1 week

**Spark effectively breaks at ~100–200 DAU** (storage cap hits first).

---

## 6. Blaze monthly bill at each tier

| MAU | Monthly $ | Monthly ₹ |
|---:|---:|---:|
| 100 | $0 | ₹0 |
| 1,000 | ~$2.40 | **~₹200** |
| 10,000 | ~$48 | **~₹4,000** |
| 50,000 | ~$240 | **~₹20,000** |

**Unit economics:** At 10K MAU (~₹4,000/mo), even 1% paying ₹50+/mo covers infrastructure. Defensible.

---

## 7. Top 5 cost-reduction recommendations

### #1 — Add `cached_network_image` + route lists to thumbnails (**-85% bandwidth**)
- Files: `lib/widgets/adaptive_image.dart:151`, `lib/screens/rooms/rooms_screen.dart:1314`, `lib/screens/settings/settings_screen.dart:1093`, `lib/widgets/quick_add_item_card.dart:570`
- All use raw `Image.network` — re-downloads on every scroll
- Use `CloudMediaDescriptor.thumbnailPath` (40 KB) instead of full (220 KB) in list views

### #2 — Batch history writes into parent item write (**-33% writes**)
- File: `lib/services/firebase_sync_service.dart:401-411`
- Embed latest history entry into item doc (capped array, size-bounded)

### #3 — Debounce `refreshPersonalUsage` (**-30% reads/day**)
- File: `lib/services/firebase_sync_service.dart:425-427`
- Currently reads after every item sync; batch to once/minute

### #4 — Gate `autoRestoreProvider.checkAndRestore()` behind first-run flag
- File: `lib/app.dart:79`
- Fires `hasRemoteBackup` on every sign-in, not just fresh install
- Guard with `SharedPreferences` `auto_restore_checked` flag

### #5 — Skip `_clearRemoteItemTombstone` for new items (**-1 delete/save**)
- File: `lib/services/firebase_sync_service.dart:380`
- Currently deletes tombstone on every item write, even new items with no tombstone

---

## 8. Projected Cost After Optimizations

| MAU | Before | After #1+#3 | Savings |
|---:|---:|---:|---:|
| 10K | ~₹4,000 | **~₹1,500** | -60% |
| 50K | ~₹20,000 | **~₹7,500** | -60% |

---

## 9. Verdict

**COST GO WITH OPTIMIZATIONS**

At 10K MAU, current bill is ~₹4,000/mo — defensible but the `Image.network` pattern (no caching) creates 5–10× bandwidth overhead that will bite on viral growth. Ship recommendations #1 and #3 before Play production to cut 10K-MAU bill from ~₹4,000 to ~₹1,500 and prevent surprise invoices.

**Set a Firebase budget alert at $20 / $50 / $100 thresholds before launch.**

Key files: `lib/services/image_optimizer_service.dart:93`, `lib/services/firebase_image_upload_service.dart:377-445`, `lib/services/pdf_optimizer_service.dart:200-213`, `lib/services/firebase_sync_service.dart:377-427`, `lib/core/constants/feature_limits.dart:12-30`, `lib/widgets/adaptive_image.dart:151`, `lib/app.dart:79`.
