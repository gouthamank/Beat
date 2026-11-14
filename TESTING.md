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
  `make mac-test` runs them on the Mac, `make ios-test` inside the iOS app on the iPhone Simulator.
  Everything CLAUDE.md lists as pure logic is covered, plus the stores (phase 2).
- **Snapshot tests:** `BeatTests/Snapshots/`, in the same runs: elements, pages and chrome, light and dark, at Mac
  width on the Mac and iPad and iPhone widths on iOS (326 tests in all on each; one skipped on the Mac).
- **UI tests (Mac):** `BeatUITests`, run with `make mac-test-ui` (about 3 minutes; leave the Mac alone): the window,
  navigation, Now Playing, pages and elements, and Cover Flow from screenshots. See "UI tests: how they work".
- **UI tests (iPhone and iPad):** phase 6.

## Snapshot tests: how they work

- **Writing one:** build the stores with `SnapshotStores.make(for: self)` and call `assertScreens(view, stores:)`
  (`fullScreen: true` for a whole page; `width:` for something narrower, like the sidebar). The library is
  `SnapshotLibrary`: nine albums with generated covers, fixed dates, no network. Every store a view reads is in
  `SnapshotStores.provide`; keep it in step with `BeatApp.withStores` when a store is added.
- **Recording:** a test without a reference records one and fails once; run it again.
- **After a deliberate design change** (say, rounder covers), the snapshots it touches fail. Then:
  1. `make mac-test`: the failures name each test and device, with the reference (`@−`) and the new capture (`@+`).
     Xcode's Report navigator (after ⌘U) shows both and their difference.
  2. Look at every one. Only the intended change should show; anything else that moved is a regression to fix.
  3. `make mac-test-record`: re-records exactly the snapshots that didn't match (they report as failures while they
     record). It runs with `SNAPSHOT_TESTING_RECORD=failed`, passed through as `TEST_RUNNER_…`.
  4. `make mac-test` again: it passes.
  5. The same on iOS with `make ios-test-record`; the references are separate. Commit the new images with the
     change, so the history shows what it looked like.

  Deleting a reference also re-records it; `record: true` on one `assertScreens` call re-records that test on every
  run (only while working on it).
- **References** live in `BeatTests/Snapshots/__Snapshots__/<Test>/<test>.<device>-<light|dark>.png`: about 7 MB.
  The Mac's are 2× (the screen's scale), iOS's 1× (a quarter of the size; layout and colour changes still show).
- **They depend on the OS:** Mac references come from macOS 15 (material fallbacks, not glass), iOS references from
  the iOS 26 Simulator. After updating either, expect to re-record.
- **Nothing real leaks in:** the Mac tests run inside Beat itself, so the harness never reads Beat's settings or
  files: its own `UserDefaults` (`.defaultAppStorage`, and `defaults:` on `AppNavigator`, `PlaybackQueue`,
  `NowPlayingView`), in-memory stores, a `FakePlayer`, no system Now Playing, cover colours forced on.
- **Known limits on the Mac** (its capture draws the layer tree, not the window server's picture):
  - Cover Flow is skipped: 3D transforms come out flat. Covered on iOS, and on the Mac by `CoverFlowUITests`.
  - Vibrancy is left out: the sidebar's icons draw black in dark mode. Layout still compares.
  - The offscreen window is never key, so the harness sets `controlActiveState` to `.key` for lists to draw active.
- **On iOS** the harness captures its own window (`drawHierarchy`, which keeps 3D transforms) once two frames in a
  row match, in 8-bit sRGB: the library's own hosting gave navigation bars no margins, a fixed wait caught pages
  still fading in, and wide-colour captures never matched their saved PNGs on soft shadows.

## UI tests: how they work

- **Running:** `make mac-test-ui` makes the shared home `/tmp/BeatUITests`, builds the UITest configuration and drives
  it. The first run asks once to let the test runner control the Mac (Accessibility). Each test launches Beat with
  `-BeatFixtureLibrary`, `CFFIXED_USER_HOME` and `-BeatFreshStart YES` (see phase 4), and with
  `-ApplePersistenceIgnoreState NO`, so windows save and restore as on a launch from the Dock.
- **Writing one:** subclass `BeatUITestCase`; `launch()`, `waitFor(identifier)`, `eventually`, `quit()`,
  `createPage`, `openAlbum`, `playAlbum`, `resizeWindow` (which fails if the size didn't change). Find things by
  identifier (the table under phase 4). The Albums grid is lazy, so only tiles on screen exist: use albums near the
  top. Query buttons in `app.windows` when the Touch Bar may have a copy (a confirmation's Delete did).
- **Launch arguments come in pairs** (`-name value`): a bare flag followed by another argument left that one's value
  over, AppKit took it for a file to open, and Beat made no window.
- **Mac text:** a static text's string is its accessibility *value*; its label is empty.
- **Screenshots** (`ScreenshotReference`): swift-snapshot-testing can't be used in a UI-test bundle (Xcode builds
  those with Swift Testing switched off, and the library imports it), and the runner is sandboxed, so it can't
  touch the repo (`ENABLE_APP_SANDBOX` doesn't reach it). References in `BeatUITests/__Snapshots__` are built into
  the test bundle, which it can read; one passes when at most 1% of pixels differ. A missing or different
  screenshot fails the test and is attached to the results; `make mac-test-ui-record` runs the tests and saves those
  attachments as references (`Scripts/save-ui-screenshots.py`). Look at the failures first: whatever was attached
  is saved. Screenshot tests launch with `pinnedLook` (dark, blue accent), so the Mac's own appearance doesn't
  matter, and crop to the page column: an element's own screenshot is its whole frame on screen, which can run past
  the window.

## The plan

Phases in order; each builds on the ones before. All of them add files, so `xcodegen generate` runs after each
(the make targets do it).

### 1. Unit tests on iOS (done)
- A `BeatiOSTests` target (unit tests hosted in `BeatiOS`) built from the shared `BeatTests` sources plus
  `BeatTests/iOS/`; the Mac target gets `BeatTests/macOS/`, each excluding the other's folder, like
  `Beat/Platform/`. `LibraryWatcherTests` (the Mac's Music watcher) moves to `macOS/`; `ArtistInfoTests` draws its
  test image with Core Graphics instead of AppKit, so it stays shared.
- `make ios-test` runs it on the iPhone 17 Pro Simulator.
- Shared logic then gets checked under iOS too, and iOS-only code becomes testable.

### 2. Unit-test gaps and seams (done)
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

### 3. Snapshot tests (done)
swift-snapshot-testing 1.19.7 (test-only), `BeatTests/Snapshots/`: 12 element layouts, 5 pages (album, artist,
genre, Library ▸ Albums, Library ▸ Songs; not Home, whose presets count back from today) and 4 pieces of chrome
(now-playing bar, Now Playing, sidebar, element editor). See "Snapshot tests: how they work" above.

### 4. UI test groundwork (done)
- **Fixture library:** `Fixtures/Library`, 31 short tagged .m4a songs in the snapshot library's nine albums, with
  covers (about 250 KB, committed). Written by `swift Fixtures/make-library.swift`; `FixtureLibraryTests` reads it
  as a UI-test launch does. Launched with `-BeatFixtureLibrary <folder>`, both platforms' `makeLibrarySource()`
  read that folder (`FolderLibrarySource`, shared since phase 2, which now also reads MP4 track numbers) and never
  open Music.
- **Isolated app state**, in two parts:
  - **Its own app:** UI tests run the UITest configuration, Debug under the bundle ID `dev.gouthaman.Beat.uitest`. Its
    settings (every `@AppStorage`, the window's saved size and split) are its own domain, never the user's Beat's
    (on the Mac they're in `~/Library/Preferences/dev.gouthaman.Beat.uitest.plist`); on iOS it's a separate app with
    its own container.
  - **A temporary home for files:** a UI test sets `CFFIXED_USER_HOME` to a folder in /tmp. Foundation's folders
    (Application Support, Caches, Documents) follow it, so `pages.json`, history, caches and thumbnails land there
    with no store changed. Settings don't follow it on macOS (they're written by `cfprefsd`), hence the bundle ID.
    **The folder must exist before Beat launches:** with it missing, settings couldn't see the system's (light mode,
    the default blue accent) and nothing saved stuck. The Mac tests share `/tmp/BeatUITests`, which `make mac-test-ui`
    makes before running (the sandboxed test runner can't). The Keychain is shared, but Beat only touches it with
    Last.fm or Discogs switched on, which fresh settings never are.
  - **A fresh start per test:** `-BeatFreshStart` clears the UI-test app's settings key by key and deletes `Library/`
    in the home, before any store reads anything. A test that relaunches to check what was kept leaves it out.
- **The guard:** `LaunchOptions.checkIsolation()`, first thing in `BeatApp.init`. When `-BeatFixtureLibrary` is
  given (even without its folder), Beat stops (`fatalError`) unless the fixture folder exists, it's the UI-test
  build, and the temporary home is in /tmp, already exists and holds every data folder. A test that silently wrote
  to the real folders could lose the user's pages, so a launch that can't prove isolation doesn't start, and a fresh
  start only ever deletes inside a home in /tmp. `LaunchOptionsTests` covers the rules.
- **By hand:** `make mac-run-fixtures` builds the UI-test app and opens it on the fixture songs, fresh: what a UI test
  sees. `make mac-run-fixtures KEEP=1` reopens it as it was left, to check what a relaunch keeps.
- **Accessibility identifiers** on what UI tests touch, dot-separated, with a name where there's one per item:

  | Identifier | What |
  |---|---|
  | `sidebar.page.<name>`, `sidebar.library.<albums/artists/songs/genres>` | Sidebar rows |
  | `sidebar.open` | The phone's button that opens the sidebar drawer |
  | `page.<name>`, `page.addElement` | A page's scroll view, filling the page column; its Add Element button |
  | `element.<name>` | An element's title (tap: See All) |
  | `albumTile.<title>` | An album tile: one element, title and artist read together |
  | `albumPage`, `albumPage.play`, `artistPage` | Album and artist pages' scroll views (not their window-wide backgrounds); the album's Play |
  | `nowPlayingBar`, `nowPlaying` | The bar and full Now Playing (containers: their controls stay reachable; Esc closes Now Playing) |
  | `editor.name`, `editor.save`, `editor.cancel` | The element editor's name and buttons |
  | `nameSheet.name`, `nameSheet.save`, `nameSheet.cancel` | The name sheet for new and renamed pages |
  | `editor.tab`, `editor.find`, `editor.layout` | The Mac editor's Rules/Appearance, Find and Layout pickers (segments by name) |
  | `coverFlow`, `coverFlow.caption` | Cover Flow and the album named under its centre cover |

  Phases 5 and 6 add more as tests need them.

### 5. Mac UI tests (done)
`BeatUITests`, 11 tests: the bar following window resizes and the window keeping its size (the 1.1.2 regressions);
opening an album and going back, sidebar pages keeping their place, Now Playing opening and closing; creating,
renaming and deleting a page, a fresh start forgetting the last launch's pages, cancelling a new page or element,
adding an element; Cover Flow at its start, middle and end. See "UI tests: how they work".

### 6. iPhone and iPad UI tests
`BeatiOSUITests` target, `make ios-test-ui`: the same paths with swipe back, plus the sidebar drawer, swiping
between songs in Now Playing, and Songs keeping its place after an album.
