# Widget and task editing refinement

**Goal:** Faster perceived widget completion; completed plans stay separately below open plans; blank space opens adding a plan; simpler categories/editor; persistent ordering and red important tasks.
**Architecture:** Retain single app-process writer and immutable widget archive. Widget Toggle gives optimistic system feedback; actual persistence remains authoritative. Notification reconciliation compares existing scheduled content instead of resubmitting all requests. Add backward-compatible importance/order fields.
**Tech Stack:** Swift 6, SwiftUI, WidgetKit, App Intents, UserNotifications; iOS 17 minimum; GitHub macOS CI.
**Spec:** User's numbered requirements in this conversation; notifications show task text at reminder time. Desktop drag is unsupported; in-App reorder synchronizes to widget, pending user preference for extra widget arrows.

## Constraints and review focus
- Preserve IDs, SideStore app groups, English signing names, old backups and category 0 data; hide the default category choice without silently recategorizing existing plans.
- Completion must survive retries, cold launch and concurrent App edits; completed items remain separate, constrained by widget capacity.
- Mixed repeat/ordinary ordering must persist, remain deterministic, and respect filtered sections.
- Importance survives edit, conversion, undo, backup, widget publication; missing fields default safely.
- Notify with task content, cancel obsolete reminders, update edited reminders; skip only identical pending requests, not missing requests.
- Widget add deep link works cold/warm and chooses today; errors remain actionable without permanent footer copy.

## Tasks
- [ ] Add regression tests; confirm current behavior fails in cloud CI.
- [ ] Extend Models/PlannerDocument/BackupCodec for importance and repeat order; implement scoped reorder; add conversion, backup, filtered and repeat tests.
- [ ] Update TaskEditor/TaskRow/PlannerDayView for red importance, earlier reminders, category chips and native List reorder.
- [ ] Update WidgetProjection/PlannerWidgetContent for separate completed rows, optimistic circles and no decorative footer/progress; route blank space to adding today.
- [ ] Reconcile notification requests by content; use task title and test unchanged/edited/missing requests.
- [ ] Run Core/Store, App state, UI, metadata checks and device Release packaging; review and fix findings.
- [ ] Publish verified 1.3.0 IPA/update source, refresh simple instructions, retain draft PR.

No simulator-only claim establishes physical SideStore performance or iOS 27 notification delivery.
