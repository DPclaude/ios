# Interactive widgets and reminders implementation plan

> **For agentic workers:** Use superpowers:executing-plans inline; retain existing worktree and direct implementation authorization.

**Goal:** Complete today's plans on the Home Screen and schedule per-plan local reminders.
**Architecture:** A shared app-process runtime handles UI and LiveActivityIntent mutations. Widget snapshots remain derived and read-only; generation guards stale imported data. Reminder projection is pure Core code; a serialized app notification coordinator updates system requests only after persistence.
**Tech Stack:** Swift 6, SwiftUI, WidgetKit, AppIntents, UserNotifications, XCTest, GitHub macOS CI.
**Spec:** docs/superpowers/specs/2026-09-29-interactive-reminders.md

## Global constraints
- iOS 17+; version 1.2.0; unchanged bundle IDs/private data location.
- No server, credentials, paid push entitlement or main-branch merge.
- 30-day daily schedule, nearest 60 notifications; truthful capacity/permission UI.

## Review focus
- Cold Intent vs concurrent UI load must share the same model and not reset edits.
- Stale widget after midnight/import must not complete a different day's task.
- Save/schedule failure must stay visible and retryable without false completion.
- Daily completion must cancel only that occurrence; undo must restore future requests.
- Old backup, DST, disabled permission and large reminder lists must preserve data and expose limitations.

### Task 1: Native data and interactions
Files: Core Models/ReminderSchedule/WidgetProjection, Store WidgetArchive, App PlannerRuntime/PlannerViewModel, Shared CompletePlanIntent/Bridge/Content, Widget provider, project.yml.
- [x] Add tests for reminder JSON roundtrip/validation, date projections, idempotent widget completion, stale generation/day and failed persistence.
- [x] Run cloud RED (`swift test --package-path native/Planner`, iOS XCTest); record expected missing-feature failures.
- [x] Add optional reminderMinute with backup validation and conversion preservation; deterministic 30-day/60-entry schedule.
- [x] Add single runtime, generation-bearing widget archive, background intent with awaited persistence and source-date guard.
- [x] Run Core and app-state suites GREEN; commit.

### Task 2: Notifications and usable UI
Files: App ReminderCoordinator, editor/settings, tests and docs.
- [x] Add reminder UI test and coordinator reconciliation tests using a notification-client seam.
- [x] Add serialized notification reconciliation after saved snapshots, permission and failure feedback, settings and editor controls.
- [x] Verify full suite, package embedded widget, validate IPA version/intent metadata; fresh reviewer and important fixes.
- [x] Publish verified 1.2.0 IPA/SideStore metadata, update beginner instructions; keep draft PR; report device-only checks accurately.
