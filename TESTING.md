# Testing Beat

Beat has three kinds of tests, from cheapest to most thorough:

- **Unit tests** check pure logic (filters, the queue, layouts, caches) without drawing anything.
- **Snapshot tests** render views with a fixed library and compare them with saved reference images: they catch
  layout regressions (spacing, truncation, a colour wrong in dark mode).
- **UI tests** (XCUITest) launch the app and drive it through the accessibility tree: they catch what only shows
  up in the whole app, like the now-playing bar not following a window resize.

The user runs every suite, from Xcode or `make`; nothing runs in CI. For the rules on what gets a test, see
`CLAUDE.md`; for how the pieces fit together, `ARCHITECTURE.md`.

## Where things stand

- **Unit tests:** XCTest files in `BeatTests`: shared ones at the top, `macOS/` and `iOS/` for each platform's own.
  `make test` runs them on the Mac (261), `make ios-test` inside the iOS app on the iPhone Simulator (258).
  Everything CLAUDE.md lists as pure logic is covered.
- **Snapshot and UI tests:** none yet. The plan below adds them.

## The plan

Phases in order; each builds on the ones before. All of them add files, so `xcodegen generate` runs after each
(the make targets do it).

### 1. Unit tests on iOS
- A `BeatiOSTests` target (unit tests hosted in `BeatiOS`) built from the shared `BeatTests` sources plus
  `BeatTests/iOS/`; the Mac target gets `BeatTests/macOS/`, each excluding the other's folder, like
  `Beat/Platform/`. `LibraryWatcherTests` (the Mac's Music watcher) moves to `macOS/`; `ArtistInfoTests` draws its
  test image with Core Graphics instead of AppKit, so it stays shared.
- `make ios-test` runs it on the iPhone 17 Pro Simulator.
- Shared logic then gets checked under iOS too, and iOS-only code becomes testable.

### 2. Unit-test gaps and seams
A **seam** is a place where tests can swap in a stand-in (a fake or mock) without changing the code that uses it.
Shared helpers live in `BeatTests/TestSupport.swift`: `FakeLibrarySource`, `FakePlayer`, `TestImages`, `temporaryFolder()`,
`temporaryDefaults()` and `eventually`. Tests never use Beat's real files or defaults: the Mac tests run inside
Beat itself, with its real bundle ID.

| Area | What to test | Needs |
|---|---|---|
| `AppNavigator` | `goBack`; each sidebar page keeps its path; `pathBinding(for:)` ignores writes from a stack that isn't selected; restoring the selection; naming and cancelling a new page | Its `UserDefaults` passed in (`init(defaults:)`), so tests never change Beat's saved sidebar |
| `LibraryStore` | Saved library first, then the real one; a read that changed nothing keeps the snapshot; changed art reported; lost access clears everything; reads coalesce; re-reads only after a write | Its source, cache folder and library stamp passed in (`init(loader:cacheDirectory:libraryStamp:)`); `LibraryCache` takes a folder |
| `ArtworkCache` | Loads once, shares concurrent loads, `invalidate` bumps `revision` and forgets only changed art, saved thumbnails used only for the current label | Nothing (it already took its source and disk cache) |
| `FirstLoadGate` | Art requests wait for the first read, then resolve | Nothing |
| `FolderLibrarySource` | `stableID`, the album grouping key, year and track tags, the audio-extension filter; reading a folder of generated WAV files | Tag parsing pulled out of the async `AVAsset` read into small functions; the file moved to `Beat/Library/` (shared), so its tests run on both platforms |
| `RuleSummary` (iOS) | Summaries for each rule and value kind | Small extraction if it isn't already pure |
| `PlaybackQueue` | What it asks the player to do when playing, skipping, going back, and when a song ends or the queue runs out; missing files skipped; plays and skips reaching `PlayHistoryStore` | `AudioPlaying`, a protocol `AudioPlayer` conforms to, with `FakePlayer` recording calls; `publishesNowPlaying: false` skips the system's Now Playing and media keys; the AirPlay picker is made on first use, so a test queue never attaches one |

### 3. Snapshot tests
- **Tool:** [swift-snapshot-testing](https://github.com/pointfreeco/swift-snapshot-testing), a test-only package
  (Beat's first dependency; nothing ships in the app). It renders in a real hosting window, so `List`, AppKit-backed
  views, materials and glass draw; SwiftUI's `ImageRenderer` leaves platform views blank.
- **Where:** in the unit-test targets, Mac and iOS; reference images in `__Snapshots__` folders next to the tests,
  committed.
- **What:**
  1. Elements: every layout (list, shelf, grid, Cover Flow, timeline) for songs, albums, artists and genres, header
     shown and hidden.
  2. Pages: album, artist, Library ▸ Songs.
  3. Chrome: the now-playing bar, Now Playing, the sidebar and the phone's drawer, the element editor (Mac and
     iPhone).
  4. Each in light and dark, at iPhone, iPad and Mac widths, with `compactLayout` on and off.
- **Needs:**
  - An environment helper that wraps a view with every store it reads (`LibraryStore`, `PageStore`,
    `AppNavigator`, `PlaybackQueue`, `PlayHistoryStore`), in memory: `PageStore(directory:)` and
    `PlayHistoryStore(fileURL:)` already take a location; the other two come from phase 2.
  - Covers in `ArtworkCache` before capture (generated images, the same ones the fixture files embed), or
    snapshots catch grey placeholders.
  - Fixed `now`, locale, time zone, text size and colour scheme; animations off.
- **OS-bound references:** the Mac runs macOS 15, so Mac references show the material fallback, not glass; iOS
  references come from the iPhone 17 Pro and iPad Simulators on iOS 26. After an OS or Xcode update, re-record and
  check the diffs by eye.

### 4. UI test groundwork
- **One fixture library on both platforms:** `FolderLibrarySource` is shared code since phase 2; both platforms'
  `makeLibrarySource()` use it when launched with `-BeatFixtureLibrary <folder>`. The Mac never opens Music during a UI test.
- **Fixture files:** a generator script (like `Design/AppIcon/render.swift`) writing about 20 short tagged audio
  files (a few seconds of tone, embedded art, several albums, artists, genres and years). Its output is committed
  (a few hundred KB).
- **Isolated app state (required on the Mac):** UI tests run the real app on the user's machine, so without this
  they would edit the real `pages.json`. `-BeatDataDirectory <folder>` moves every store's files there
  (`PageStore`, `PlayHistoryStore`, `Scrobbler`, `ArtistInfoProvider`, `LibraryCache`, `ArtworkDiskCache`) through
  one shared helper replacing each type's `defaultDirectory`/`defaultURL`, uses its own `UserDefaults` suite, and
  forces online features off. A unit test checks every store honours it.
- **Accessibility identifiers** on the controls tests touch: sidebar rows, element headers and tiles, the
  now-playing bar, the editor's Save and Cancel, Now Playing, the drawer. There are none today.

### 5. Mac UI tests
`BeatUITests` target, `make test-ui`. The first run asks for Accessibility permission for the test runner (once).
In order of value:
1. Launch, resize the window, check the now-playing bar follows the page column; quit and relaunch, check the
   window keeps its size (the 1.1.2 regressions).
2. Open an album from a tile and go back (⌘[); open and close Now Playing; switch sidebar pages.
3. Create, rename and delete a page; edit an element's rules and see the page update; Cancel leaves nothing behind.

### 6. iPhone and iPad UI tests
`BeatiOSUITests` target, `make ios-test-ui`: the same paths with swipe back, plus the sidebar drawer, swiping
between songs in Now Playing, and Songs keeping its place after an album.
