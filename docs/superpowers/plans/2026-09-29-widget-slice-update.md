# Widget, slice completion and updates implementation plan

> **For agentic workers:** Use superpowers:executing-plans inline. User selected the recommended interaction and previously requested direct implementation; continue without additional procedural approval gates.

**Goal:** Show saved plans in a Home Screen widget, open a native full-screen slice interaction, and update via a stable SideStore source.
**Architecture:** The app remains the sole document writer. A separate atomic archive in an App Group supplies the read-only widget. Full-screen completion uses existing model actions; release metadata points to tested GitHub Release assets.
**Tech Stack:** Swift 6, SwiftUI, WidgetKit, Foundation, GitHub Actions, Node built-ins.
**Spec:** ../specs/2026-09-29-widget-slice-update-proposal.md (recommended option selected by user).

## Global constraints
- iOS 17 minimum; primary target iPhone 14 Pro; user iOS 27 requires device validation.
- Retain com.dpclaude.planner, private original storage and JSON compatibility; ASCII base signing names and Chinese localization.
- No server for personal plans; no Apple credentials in CI; same free SideStore workflow.
- Widget is read-only; full-screen slicing completes, never deletes; support undo and Reduce Motion.
- Update installation must use SideStore; no silent self-installation claim.

## Review focus
- Vertical scrolling, tiny drags and repeated gestures must not complete accidentally (Task 1 rules and Task 2 UI).
- Failed persistence must not publish unsaved plans (Task 1 archive + Task 2 view-model test).
- Midnight projection must preserve finished history and repeat completion semantics (Task 1 projection test).
- Resigned App Group identifiers must resolve in both targets; missing group displays an explicit status (Task 3 artifact and real-device checks).
- Version comparison must be numeric, reject invalid metadata/foreign URLs and preserve old app on update failure (Task 4 tests).

### Task 1: Rules and snapshot archive
Files: PlannerCore/SliceRules.swift, PlannerCore/WidgetProjection.swift, PlannerCore/UpdateManifest.swift, PlannerStore/WidgetArchive.swift; corresponding package tests.
Interfaces: SliceRules.accepts(horizontal:vertical:width:), WidgetProjection(document:day:timeZone:), UpdateManifest.validated(data:) / isNewer(than:), WidgetArchive.write(document:to:) / read(from:).
- [ ] Write cloud RED tests: short/vertical drags rejected, numeric versions and invalid download URLs, next-day projection, corrupt archive rejection and replacement.
- [ ] Implement minimal functions and run swift test with all existing tests on macOS.
- [ ] Commit verified core/archive changes.

### Task 2: Full-screen interaction and persisted snapshot publication
Files: App/Views/SliceCompletionView.swift, PlannerDayView.swift, PlannerViewModel.swift; AppTests and UITests.
Interfaces: SliceCompletionView(model:), PlannerViewModel.completeForSlice(_:) and undoSliceCompletion(), model.isShowingSlice; optional onPersist callback only after a successful disk write/load.
- [ ] Add UI RED test: create task, open slice, horizontal swipe completes, undo restores; keep new test independent of missing core types.
- [ ] Add state tests for idempotent completion, undo after another addition, repeated rule/day identity and no snapshot on failed save.
- [ ] Implement bounded-duration SwiftUI blade/fragment animation, haptics, accessible completion button, pending-save/error status and Reduce Motion.
- [ ] Run full iOS test suite, capture screenshots and commit.

### Task 3: Widget extension
Files: Shared/PlannerWidgetBridge.swift, Widget/PlannerWidget.swift, project.yml, entitlements and packaging script.
Interfaces: app publishes successful saved copies; extension reads immutable archive and derives today's projection. planner://slice deep link opens today's full-screen page.
- [ ] Add large/medium widgets with day, pending tasks and progress, explicit missing-data state, midnight timeline and reload requests after saves.
- [ ] Resolve SideStore ALTAppGroups plus canonical group; never move/delete original private store.
- [ ] Embed extension, ad-hoc entitlement metadata for SideStore resigning; validate names, group entitlements, extension architecture and IPA structure in CI.
- [ ] Verify compile and screenshots; record device-only signing/refresh limitations.

### Task 4: Update delivery
Files: App/Views/UpdateSection.swift, scripts/release-metadata.mjs, release tests and .github/workflows/ios-native.yml.
Interfaces: planner-update.json {version,downloadURL,notes}; planner-source.json standard AltSource; HTTPS latest-release assets hosted on DPclaude/ios.
- [ ] Node RED tests for source/manifest consistent version, bundle, URL, real file size and invalid version rejection.
- [ ] Generate metadata from built IPA; publish only after successful verification on explicit workflow_dispatch publish input.
- [ ] Add check update / add source / SideStore install buttons; handle offline, invalid response and missing SideStore.
- [ ] Run full verification, final independent review, publish tested v1.1.0 assets and verify accessible source + direct IPA.
- [ ] Update novice guide and PR; preserve draft and real-device acceptance boundary.
