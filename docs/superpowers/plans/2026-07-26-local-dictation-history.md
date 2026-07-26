# Local Dictation History Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Save every non-empty final dictation locally before system paste, expose 30 days of searchable history, and let users copy or delete records.

**Architecture:** Add a testable `SottoCore` history store backed by one atomically-written JSON document in Application Support. `AppModel` owns the store and the state machine emits history-save before insertion. The existing settings window gains a shared navigation destination and a SwiftUI history pane.

**Tech Stack:** Swift 6, Foundation Codable/FileManager, Combine `ObservableObject`, SwiftUI, existing `SottoCoreTestHarness`, SwiftPM XCTest.

---

## File Structure

- Create `Sources/SottoCore/DictationHistory.swift`: entry/document types, retention/search/provider policies.
- Create `Sources/SottoCore/DictationHistoryStore.swift`: observable in-memory state, JSON persistence, corruption backup, mutation rollback, expiry scheduling.
- Create `Sources/Sotto/SettingsPane.swift`: shared settings navigation enum.
- Create `Sources/Sotto/DictationOutputCoordinator.swift`: injected history-before-paste orchestration.
- Create `Sources/Sotto/DictationHistoryView.swift`: history list, search, copy/delete/clear UI.
- Create `Tests/SottoTests/DictationOutputCoordinatorTests.swift`: app-level ordering and failure-continuation tests.
- Create `Tests/SottoTests/SettingsNavigationTests.swift`: app-level settings-window routing tests.
- Modify `Package.swift`: add the app-level XCTest target.
- Modify `Sources/SottoCore/DictationStateMachine.swift`: emit one final-output delivery effect.
- Modify `Sources/Sotto/AppModel.swift`: own the store, capture provider, save history, route history navigation.
- Modify `Sources/Sotto/SettingsRootView.swift`: add history pane and privacy disclosure.
- Modify `Sources/Sotto/SettingsWindowController.swift`: inject the history store.
- Modify `Sources/Sotto/MenuBarView.swift`: add Open History.
- Modify `Tests/SottoCoreTestHarness/main.swift`: model, persistence, retention, ordering and navigation tests.
- Modify `README.md`: document local 30-day final-text history.

### Task 1: History data model and pure policies

**Files:**
- Create: `Sources/SottoCore/DictationHistory.swift`
- Modify: `Tests/SottoCoreTestHarness/main.swift`

- [ ] **Step 1: Write failing model and policy tests**

Add tests covering Codable round-trip, newest-first ordering, `createdAt <= now - 30 days` expiry, case-insensitive search, and provider display fallback.

```swift
let now = Date(timeIntervalSince1970: 4_000_000)
let expired = DictationHistoryEntry(
    id: UUID(),
    text: "expired",
    createdAt: now.addingTimeInterval(-30 * 24 * 60 * 60),
    providerID: "fun-asr"
)
try expect(
    DictationHistoryPolicy.retained([expired], now: now),
    equals: [],
    "exactly 30 days is expired"
)
```

- [ ] **Step 2: Run the harness and verify RED**

Run: `swift run SottoCoreTestHarness`

Expected: compile failure because `DictationHistoryEntry` and `DictationHistoryPolicy` do not exist.

- [ ] **Step 3: Implement minimal model and policies**

Define:

```swift
public struct DictationHistoryEntry: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let text: String
    public let createdAt: Date
    public let providerID: String
}

public struct DictationHistoryDocument: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public var entries: [DictationHistoryEntry]
}
```

`DictationHistoryPolicy` supplies `retained`, `sortedNewestFirst`, `matching`, `nextExpirationDate`, and `providerTitle`. Unknown providers return `未知语音服务`.

- [ ] **Step 4: Run the harness and verify GREEN**

Run: `swift run SottoCoreTestHarness`

Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/SottoCore/DictationHistory.swift Tests/SottoCoreTestHarness/main.swift
git commit -m "Add dictation history model and retention policy"
```

### Task 2: Atomic local persistence and expiry scheduling

**Files:**
- Create: `Sources/SottoCore/DictationHistoryStore.swift`
- Modify: `Tests/SottoCoreTestHarness/main.swift`

- [ ] **Step 1: Write failing store tests**

Use a unique temporary directory. Cover:

- load and append persist a schema-versioned JSON document
- entries publish newest first
- startup purges expired entries and saves the filtered document
- every append purges expired entries before persistence
- corrupt JSON is moved to `dictation-history.corrupt-<timestamp>.json`
- injected write failure keeps a new entry in memory
- injected write failure rolls back delete and clear
- the earliest expiry is scheduled and a manual scheduler can fire it
- firing expiry removes expired entries and persists the filtered document
- expiry-write failure schedules a five-minute retry
- firing that retry persists the already-filtered in-memory state

The store initializer accepts:

```swift
init(
    fileURL: URL,
    now: @escaping @Sendable () -> Date = Date.init,
    writeData: @escaping @Sendable (Data, URL) throws -> Void = liveAtomicWrite,
    scheduler: any DictationHistoryExpirationScheduling
)
```

Use a manual fake `DictationHistoryExpirationScheduling` implementation that records the requested date and exposes `fire()`. Wrap actor-isolated store assertions in `MainActor.assumeIsolated`.

- [ ] **Step 2: Run the harness and verify RED**

Run: `swift run SottoCoreTestHarness`

Expected: compile failure because `DictationHistoryStore` is missing.

- [ ] **Step 3: Implement the store**

Implement `@MainActor public final class DictationHistoryStore: ObservableObject` with:

- `@Published public private(set) var entries`
- `@Published public private(set) var errorMessage`
- `append(text:providerID:)`
- `delete(id:)`
- `clearAll()`
- `purgeExpired()`
- `search(_:)`
- one injected, cancellable expiry scheduler

Live storage URL is `Application Support/Sotto/dictation-history.json`. Create the parent directory, atomically write JSON, and mark the directory/file excluded from backup.

On corrupt load, move the original beside the live file before resetting. Never log entry text.

Expiry task behavior:

1. cancel the previous task;
2. sleep until `nextExpirationDate`;
3. purge and save;
4. schedule the next expiry;
5. on persistence failure, surface the error and retry in five minutes.

- [ ] **Step 4: Run tests and strict build**

Run:

```bash
swift run SottoCoreTestHarness
swift test
swift build -c release -Xswiftc -warnings-as-errors
```

Expected: both pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/SottoCore/DictationHistoryStore.swift Tests/SottoCoreTestHarness/main.swift
git commit -m "Persist local dictation history"
```

### Task 3: Save history before system paste

**Files:**
- Modify: `Package.swift`
- Modify: `Sources/SottoCore/DictationStateMachine.swift`
- Create: `Sources/Sotto/DictationOutputCoordinator.swift`
- Modify: `Sources/Sotto/AppModel.swift`
- Modify: `Tests/SottoCoreTestHarness/main.swift`
- Create: `Tests/SottoTests/DictationOutputCoordinatorTests.swift`

- [ ] **Step 1: Write failing ordering tests**

Change the polished-transcript expectation to one indivisible output effect:

```swift
try expect(
    machine.handle(.transcriptPolished("final")),
    equals: [.deliverFinalText("final")],
    "one effect owns history and insertion ordering"
)
```

Add tests proving cancel, no speech and failure do not emit `.deliverFinalText`.

Add a SwiftPM app-level test target:

```swift
.testTarget(
    name: "SottoTests",
    dependencies: ["Sotto", "SottoCore"]
)
```

In `DictationOutputCoordinatorTests`, inject fakes and prove:

- the exact event order is history, insertion-readiness gate, then paste;
- the provider ID passed to history is the supplied session provider;
- a failed history save still reaches the readiness gate and paste;
- a rejected readiness gate prevents paste;
- the readiness gate and paste are each invoked exactly once;
- the insertion outcome is returned unchanged.

- [ ] **Step 2: Run harness and verify RED**

Run: `swift run SottoCoreTestHarness`

Expected: failure because `.saveHistory` is absent.

- [ ] **Step 3: Implement state-machine and model wiring**

Replace `DictationEffect.insertText(String)` with `DictationEffect.deliverFinalText(String)`. In `.transcriptPolished`, emit only that single effect, so no second path can independently save or paste.

`AppModel`:

- owns `let historyStore: DictationHistoryStore`;
- accepts it through initializer injection;
- captures `settings.provider.rawValue` when dictation starts;
- handles `.deliverFinalText` once by passing the captured provider and final text through an injected `DictationOutputCoordinator`;
- supplies the coordinator an insertion-readiness collaborator that waits for overlay dismissal and then verifies `phase == .inserting`;
- handles the single returned insertion outcome and applies the state-machine success/failure event;
- clears the pending provider after insertion, cancel, no speech or failure.

The coordinator uses narrow collaborators:

```swift
@MainActor protocol DictationHistoryRecording {
    @discardableResult func append(text: String, providerID: String) -> Bool
}

@MainActor protocol DictationTextInserting {
    func insert(_ text: String) async -> TextInsertionOutcome
}

@MainActor protocol DictationInsertionReadiness {
    func waitUntilReady() async -> Bool
}
```

The coordinator appends synchronously, awaits the readiness gate exactly once, then calls the inserter exactly once only when ready. The live readiness implementation preserves the existing overlay-dismissal wait and phase guard. A history save failure must not prevent paste. A readiness rejection returns no insertion outcome, allowing `AppModel` to keep the existing clipboard-recovery failure path without issuing a second paste.

- [ ] **Step 4: Run tests and strict build**

Run:

```bash
swift run SottoCoreTestHarness
swift test --filter DictationOutputCoordinatorTests
swift build -c release -Xswiftc -warnings-as-errors
```

Expected: pass.

- [ ] **Step 5: Commit**

```bash
git add Package.swift Sources/SottoCore/DictationStateMachine.swift Sources/Sotto/DictationOutputCoordinator.swift Sources/Sotto/AppModel.swift Tests/SottoCoreTestHarness/main.swift Tests/SottoTests/DictationOutputCoordinatorTests.swift
git commit -m "Save final dictations before paste"
```

### Task 4: Shared settings navigation and menu entry

**Files:**
- Create: `Sources/Sotto/SettingsPane.swift`
- Modify: `Sources/Sotto/AppModel.swift`
- Modify: `Sources/Sotto/SettingsRootView.swift`
- Modify: `Sources/Sotto/SettingsWindowController.swift`
- Modify: `Sources/Sotto/MenuBarView.swift`
- Create: `Tests/SottoTests/SettingsNavigationTests.swift`

- [ ] **Step 1: Write failing app-level navigation tests**

Create shared observable `SettingsNavigationState` and `SettingsPane`, plus an injected `SettingsWindowPresenting` collaborator. Verify:

- the initial pane is `.start`;
- `AppModel.openHistory()` changes it to `.history`;
- the fake window presenter receives `show`;
- ordinary `openSettings()` does not overwrite an existing non-start selection.

- [ ] **Step 2: Run harness and verify RED**

Run: `swift test --filter SettingsNavigationTests`

Expected: missing history destination.

- [ ] **Step 3: Implement navigation**

Add the `history` pane immediately after `start`, symbol `clock.arrow.circlepath`. Bind `SettingsRootView`'s `List` directly to the shared navigation state so the state exercised by tests is the UI source of truth.

`AppModel.openHistory()` sets the requested pane before showing the window. `SettingsWindowController` injects `model.historyStore`.

Add `Open History…` to the menu between Copy Last Result and the divider.

- [ ] **Step 4: Run app tests and strict build**

Run:

```bash
swift test --filter SettingsNavigationTests
swift build -c release -Xswiftc -warnings-as-errors
```

Expected: pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/Sotto/SettingsPane.swift Sources/Sotto/AppModel.swift Sources/Sotto/SettingsRootView.swift Sources/Sotto/SettingsWindowController.swift Sources/Sotto/MenuBarView.swift Tests/SottoTests/SettingsNavigationTests.swift
git commit -m "Add dictation history navigation"
```

### Task 5: History UI and privacy disclosure

**Files:**
- Create: `Sources/Sotto/DictationHistoryView.swift`
- Modify: `Sources/Sotto/SettingsRootView.swift`
- Modify: `README.md`

- [ ] **Step 1: Add pure filtering/empty-state tests**

Verify whitespace-only search returns all entries, unmatched search produces the no-results state, and provider/time display inputs are stable.

- [ ] **Step 2: Implement the SwiftUI page**

Build:

- title, local-only 30-day disclosure and search field;
- purge expired entries whenever History appears;
- newest-first scrollable cards;
- localized timestamp and provider title;
- selectable final text;
- Copy and Delete actions;
- Clear All with confirmation;
- distinct no-history and no-results empty states;
- inline persistence-error banner.

Copy writes only to `NSPasteboard`; it does not mutate an entry and does not send `⌘V`.

- [ ] **Step 3: Update privacy and README**

Change Privacy to `转写历史：本机保存 30 天`. Update README statements that currently promise no transcript history while retaining the no-audio/no-live-segment guarantees.

- [ ] **Step 4: Run tests and strict build**

Run:

```bash
swift run SottoCoreTestHarness
swift test
swift build -c release -Xswiftc -warnings-as-errors
git diff --check
```

Expected: pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/Sotto/DictationHistoryView.swift Sources/Sotto/SettingsRootView.swift README.md Tests/SottoCoreTestHarness/main.swift
git commit -m "Add local dictation history interface"
```

### Task 6: Merge and publish

**Files:**
- Modify: `Packaging/Info.plist`
- Modify: `README.md`

- [ ] **Step 1: Final verification on the feature branch**

Run:

```bash
swift run SottoCoreTestHarness
swift test
swift build -c release -Xswiftc -warnings-as-errors
plutil -lint Packaging/Info.plist
git diff --check
```

- [ ] **Step 2: Push and merge the feature PR**

Push `codex/local-dictation-history`, open a ready PR, confirm it is clean/mergeable, and squash-merge.

- [ ] **Step 3: Prepare the next patch release**

Create `codex/release-v0.2.9`, bump `CFBundleShortVersionString` from `0.2.8` to `0.2.9` and `CFBundleVersion` from `10` to `11`, and update README release links/artifact names.

- [ ] **Step 4: Verify and merge the release PR**

Repeat the core harness, `swift test`, strict release build, plist validation and diff check. Merge the clean release PR.

- [ ] **Step 5: Tag and package**

Tag merged `main` as `v0.2.9`, run `./scripts/package-distribution.sh`, generate `SHA256SUMS.txt`, and verify:

- app version/build/commit;
- ad-hoc signature;
- DMG integrity;
- ZIP integrity;
- local checksums.

- [ ] **Step 6: Publish and verify GitHub Release**

Upload DMG, ZIP and SHA256SUMS. Verify the release is Latest, assets are uploaded, remote digests match local checksums, and the tag points to merged `main`.

Per user instruction, do not automate a live Codex/Feishu insertion smoke test.
