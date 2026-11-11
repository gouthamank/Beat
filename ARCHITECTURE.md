# Beat architecture

## Overview

```
 Music's library DB (~/Music/Music/Music Library.musiclibrary)
            │  read-only
            ▼
 LibraryLoader (actor, owns ITLibrary) ──artwork bytes──► ArtworkCache (NSCache, background decode)
            │ LibrarySnapshot (Sendable value)
            ▼
 LibraryStore (@MainActor @Observable, version counter)
            │                                  PlayHistoryStore (Beat's own plays/skips, JSON)
            │                                         │
            └──────────────┬──────────────────────────┘
                           ▼
            PageStore.evaluate(page on screen) → PreparedLibrary → SmartFilterEngine.evaluate (detached task)
                           │ [element ID: FilterResult]
                           ▼
 SwiftUI views: RootView (NavigationSplitView) → Sidebar tree | PageView | detail pages | editor sheet
                           │ queue.play(tracks, startAt:)
                           ▼
 PlaybackQueue (@Observable) ── QueueState (pure logic)
            │                └─ AudioPlayer (AVQueuePlayer, current + 1 preloaded item)
            ├─ PlayHistoryStore.recordPlay / recordSkip
            ├─ Scrobbler.nowPlaying / played (opt-in Last.fm; queue on disk, LastFMClient actor)
            └─ NowPlayingController (MPNowPlayingInfoCenter, MPRemoteCommandCenter)
```

`BeatApp` creates one of each store and injects them with `.environment(...)`:
- `LibraryStore`
- `ArtworkCache`
- `PlayHistoryStore`
- `PlaybackQueue`
- `PageStore`
- `AppNavigator`

There are no singletons apart from the system's MediaPlayer centers.

## Folders

| Folder | Contents |
|---|---|
| `Beat/Library` | Models, loading, artwork, play history |
| `Beat/Playback` | Queue logic, the AVFoundation player, system Now Playing, the Controls menu |
| `Beat/SmartFilters` | Filter model, rule vocabulary, engine, presets, the editor model |
| `Beat/Pages` | The sidebar tree of folders and pages, page elements, `PageStore` and its persistence |
| `Beat/DesignSystem` | Glass abstraction, artwork view, blurred backdrop |
| `Beat/Views` | All SwiftUI screens; `Pages/` and `SmartFilterEditor/` are grouped |
| `BeatTests` | XCTest unit tests for the pure logic |

## Library layer

- **`LibraryLoader`** (actor) wraps `ITLibrary(apiVersion: "1.1")`.
  - `load()` reloads the library and maps `ITLibMediaItem`s with a file location into `Track` value types. It keeps every artwork-bearing item for lazy art; an album's cover is its first track with artwork in album order (`LibrarySnapshot.artworkTrackID`).
  - `ITLibrary` objects are not Sendable and never leave the actor.
- **`Models.swift`:** `Track`, `Album`, `Artist`, `Genre` and `LibrarySnapshot`. Beat doesn't read playlists from Music.
  - `LibrarySnapshot.build(tracks:)` is a pure function that groups tracks into albums (disc/track order), artists (keyed by the album artist's case-folded name; compilations excluded) and genres.
  - `artistKey(_:)` is the single definition of "which artist a track belongs to", used by grouping, limits and projection.
- **`LibraryStore`:** holds the current snapshot, a load state, and a `version` that's bumped on every load. Reload happens on launch, on `didBecomeActive`, and when `LibraryWatcher` sees Music write its database. Overlapping requests coalesce into one follow-up load.
- **`LibraryWatcher`:** an FSEvents stream on the `.musiclibrary` bundle, scheduled on the main queue, debounced 2 s. `isRelevant(paths:)` (tested) keeps only `.musicdb`/`.itdb`/`sentinel` writes.
- **`ArtworkCache`:** pulls `imageData` from the loader and downsamples it with ImageIO in a `@concurrent` function. It caches by (`ArtworkSource`, size), where a source is an album's cover or a track's own art (Now Playing uses the track's, so albums whose tracks carry different art change per track), with `.thumbnail` and `.large`, and deduplicates in-flight requests. `ArtworkView` shows any cached image immediately (a large request falls back to the cached thumbnail) so already-loaded art never flashes a placeholder. The cache also extracts and keeps an `ArtworkPalette` per source.
- **`PlayHistoryStore`:** `[PersistentID: Stats]` of Beat-recorded plays and skips, written atomically in the background.
  - A play counts at 50% of the track or 4 minutes. A skip is a manual "next" between 2 and 20 seconds in.
  - These stats are merged into Music's counts only inside `PreparedLibrary`, never written back.
- **`Scrobbler`:** opt-in Last.fm scrobbling, fed by `PlaybackQueue`. It announces a track when it starts playing and queues a `Scrobble` when the play counts (the same rule as above). `ScrobbleQueue` (pure, tested) is saved to `scrobbles.json` and sent in batches of 50 by `flush()`, which backs off from 1 to 30 minutes while Last.fm is unreachable. A revoked session keeps the queue and asks the user to connect again.
  - Sign-in is Last.fm's desktop flow: `auth.getToken`, the approval page in the browser, then polling `auth.getSession`. The session key goes in the Keychain.
  - `LastFMRequest` (pure, tested) signs calls with the API key and secret compiled in from `Config/Secrets.xcconfig`. Having a key is the feature switch: builds without one (or with the example placeholders) have no Last.fm tab and a scrobbler that does nothing.

## Playback layer

- **`QueueState`** (pure struct, unit-tested): the item list, the original order while shuffled, the current index and the repeat mode.
  - `index(after:manual:isPlayable:)` handles repeat off/all/one (a manual skip ignores repeat-one) and skips unplayable tracks.
  - Shuffle keeps the current track first. Unshuffling restores the original order and keeps the current track.
  - `insertNext` / `append` keep the unshuffled order in sync.
- **`AudioPlayer`:** an `AVQueuePlayer` holding exactly the current item plus one preloaded upcoming item for near-gapless transitions.
  - It reports `onTime`, `onAdvanced` (the preloaded item took over) and `onFinished`.
  - A failed item is treated as ended.
- **`PlaybackQueue`:** the façade the views use (`play`, `playNext`, `addToQueue`, transport, shuffle, repeat, volume).
  - After any queue change it recomputes the upcoming item and hands it to `AudioPlayer`.
  - Previous restarts the track if more than 3 seconds have played.
  - Volume persists in `UserDefaults`.
- **`NowPlayingController`:** publishes title, artist, album, duration, elapsed time, rate and artwork, and routes remote commands back as `@MainActor @Sendable` closures.
- **`PlaybackCommands`:** the "Controls" menu (⌘→/⌘← next/previous, ⌘↑/⌘↓ volume). `SpaceBarMonitor` handles Space.

## Smart filters

### Model (`SmartFilter.swift`, `Field.swift`)
```
SmartFilter
  output:  songs | albums | artists | genres what the result is shown as
  steps:   [FilterStep]                       run in order
             .filter(RuleGroup)               match all/any/none of nodes; nodes are rules or nested groups
             .sort([SortKey])                 field, .random or .custom(CustomField), ascending flag
             .limit(Limit)                    count of songs/albums/artists/genres/minutes/hours
```
How a filter is shown lives on the page element that owns it (see Pages), not on the filter.

**Custom fields (`CustomField.swift`)** are user-defined sort fields: a value extracted from a text tag (text in the last parentheses or brackets, or a regex using capture group 1 if present). A sort key embeds the whole definition, so filters stay self-contained and the engine stays pure. `PageStore.customFields` is only the picker's list. Saving a definition rewrites every embedded copy with the same ID (`refreshCustomFields`), and deleting one leaves existing copies sorting. Values compare with `localizedStandardCompare`, like other text, and no match sorts last in either direction.
- `Field` has a `FieldType`: text, number, date or bool. The type decides which `RuleOperator`s are valid and how a group aggregates when sorting (`sum`, `average`, `min` or `max`).
- `RuleValue` covers `.text`, `.number`, `.range`, `.date`, and `.relative(n, unit)`. Filters always start from the whole library.
- Rating rules and sorts work in stars (0–5), not Music's 0–100 scale.

### Engine (`SmartFilterEngine.swift`)
The core is a pure function: `evaluate(filter, in: PreparedLibrary) -> FilterResult`.
- **`PreparedLibrary`** is built once per library/history version and shared by every element evaluated against it. It holds the snapshot, tracks with `PlayHistoryStore` stats merged in, and an injected `now` and `calendar`.
- **Filter** tests individual tracks. Text matching ignores case and diacritics, and an empty "contains" matches everything. A missing date is never "in the last N" and always "not in the last N". Date boundaries are inclusive.
- **Sort** sorts tracks when the output is songs. Otherwise it groups tracks by album, artist or genre (first-appearance order), sorts the groups by each key's aggregate, and flattens back to tracks. The sort is stable, and missing values sort last in either direction. Random draws from a `SeededRNG` seeded with the filter ID and the day number, so random shelves are stable within a day.
- **Limit** keeps the first N tracks, the tracks that fit a time budget, or the tracks of the first N distinct albums, artists or genres. The limit unit can differ from the output kind ("songs from 3 artists").
- **Projection** turns the final track list into `FilterResult`. Album results reorder `tracks` into album, then disc/track order so "play section" sounds right.
- Step order matters (sort→limit ≠ limit→sort). The tests pin this down.

### Presets
- **`Presets`:** nine built-in filters. `Presets.homePage()` wraps them as elements of a "Home" page with fresh IDs; it seeds the tree on first launch and backs "Add Default Home Page".

## Pages (`Beat/Pages/`)

### Model (`PageModel.swift`, `PageTree.swift`)
```
PageTree.nodes: [SidebarNode]                 the user's sidebar, top level
  SidebarNode { id, name, symbol, content }
    .folder([SidebarNode])                    nests without limit
    .page(Page)                               a leaf: never has children
  Page.elements: [PageElement]
    PageElement { filter: SmartFilter, appearance: ElementAppearance }   id == filter.id
      ElementAppearance: layout (shelf/grid/list), size, rows, columns, spacing, showHeader, showPlayButtons, sortOverride
```
- The tree is free-form: folders and pages mix at every level, including the top. Home is an ordinary page.
- **`PageTree`** is a pure value type holding every structural operation (insert, remove, move, duplicate, updatePage). `move` refuses a page as a destination and a folder into its own subtree. `index` in `move` refers to the destination before the move. Duplicates get fresh IDs throughout.
- Each element owns its filter; there is no shared filter list. `effectiveFilter` appends the sort override as a last step, so it reorders without changing membership.
- `ElementAppearance.layouts(for:)`: songs are shelf or list, everything else shelf, grid or list. `fit(to:)` keeps layout, rows and columns valid when the output changes. Elements have no icon; the header is the filter name.

### Store (`PageStore.swift`)
- Holds `tree`, `customFields` and `results` keyed by element ID. Saves `~/Library/Application Support/Beat/pages.json` as `{ version, nodes, customFields }`, pretty-printed, with writes chained so they land in order. The old `filters.json` is no longer read.
- **Corrupt file:** if `pages.json` doesn't decode, it's renamed to `pages.corrupt-<timestamp>.json` before falling back to the default tree, so the next save can't overwrite it.
- **Lazy evaluation:** `evaluate(pageID:…)` runs only the visible page's elements, and only those that changed since their last result. A new library or history version (`LibraryKey`) rebuilds the `PreparedLibrary` and invalidates every result. `PageView` and `ElementDetailView` trigger it through the `PageEvaluation` modifier (150 ms debounce, keyed by the versions and the page's contents).

### Editor (`EditableFilter.swift`, `Views/SmartFilterEditor/`)
- **`EditableFilter`** mirrors `SmartFilter`, but every step, group, node and sort key carries a UUID, so `ForEach($array)` bindings survive inserts, deletes and reorders. It converts both ways losslessly (tested against all presets).
- **`Rule.make(field:)` and `RuleValue.defaultValue(for:op:)`** give new rules sensible starting values. `fits(_:field:)` resets the value when an operator change needs a different shape (a range, relative vs absolute date).
- **`FilterEditorSheet`** edits one element (`ElementDraft`: page ID, `EditableFilter`, `ElementAppearance`). A Rules / Appearance switch picks the top pane; a live preview fills the bottom of a `VSplitView`.
  - Rules: flat step sections (move up/down, delete, add).
  - Rules opens with "Find [Show as] in [source]", which defines what the filter finds, then the steps.
  - Appearance (`FilterAppearanceForm`): name, layout, size, rows, columns (list only), spacing, header toggles and the sort override.
  - `SortFieldPicker` is shared by the Sort step and the sort override. Its Custom section lists custom fields and opens `CustomFieldSheet` (with a live match check over the library, examples from the current preview) and `CustomFieldsManager`.
  - The preview (`ElementPreview`) evaluates the element's `effectiveFilter` with a 200 ms debounce whenever the draft changes, and renders the real `ElementView` with `isPreview: true` (no See All link, menu or edit controls) inside its own destination-less `NavigationStack`, so it looks exactly like the page and clicks stay in the sheet.
  - `Show as` changes are fitted to the appearance at the sheet level, since the Appearance form may not be on screen.
- **`RuleGroupEditor`** is recursive. Nested groups go through `AnyView` to break the opaque-type cycle, and nesting is capped at depth 3.
- **`AppNavigator`** holds the sidebar selection, the element being edited and the node being renamed. The editor sheet is attached in `RootView`. `ElementMenu` holds the shared Edit / Duplicate / Move / Delete element actions.

## UI layer

- **`RootView`:** a `NavigationSplitView` with `SidebarView` on the left and a `NavigationStack` bound to `AppNavigator.path`, which resets whenever the selection changes. Overlays on the split view (outside the stack, so pushed pages don't cover them): the loading state, `HeroOverlay` and `NowPlayingOverlay`.
  - Routes are typed: `AlbumRoute`, `ArtistRoute`, `GenreRoute`, `ElementRoute`.
  - If the selected page disappears (deleted, or nothing selected), it falls back to the first page in the tree.
  - Every page applies `.nowPlayingBarHost()`, which floats `NowPlayingBar` and adds bottom `contentMargins` so scrolling content clears it.
- **Sidebar:** the page tree above the fixed Library section. It's rendered flat: `SidebarRow.visible` lists the visible rows depth-first (skipping collapsed folders, expansion state held in `SidebarView`) with hand-drawn indentation and chevrons. Each open folder ends with an "Add" row (a New Page / New Folder menu) that also gives drops an "end of this folder" position.
  - Page rows stay plain (tag, `itemProvider` drag, context menu). Drop targets and popovers on a selectable row swallow its click on macOS.
  - Row context menus create, rename (a sheet whose field opens with the name selected), change icon (sheet, presented from the sidebar), duplicate, Move To and delete (with a page count for folders).
  - Drag and drop: one `ForEach.dropDestination` over the flat rows; a drop before row *i* lands at that row's parent and index, past the end goes to the end of the top level. Moves run in a `Task` after the drop callback. Folders (not selectable) also accept drops onto themselves, which moves an item inside, and click to expand. The bottom "New" menu doubles as a "Move to Top Level" drop target.
- **Pages:** `PageView` renders a page's elements with `ElementView`, laid out by each element's appearance.
  - Shelf: rows that scroll sideways together, filled column by column. Grid: adaptive, cut off after N rows using the measured column count. List: rows × columns compact rows (songs, albums, artists or genres), filled column by column.
  - Edit Page mode shows every header (even hidden ones) with inline move, edit, duplicate and delete controls.
  - Element headers link to `ElementDetailView` ("See All").
- **Library views:**
  - `AlbumGridView` / `AlbumTile`: hover play button, context menu.
  - `AlbumDetailView`: coloured from the cover. `ArtworkPalette` gives a background (the dominant colour, edges weighted) and primary/secondary text colours from the cover that meet 4.5:1 and 3:1 contrast, else white/black. The page forces light/dark from the palette so controls and glass match.
- **Album zoom (`HeroTransition.swift`):** `AlbumTile` and album list rows open albums themselves, measuring their art with a `FrameProbe` (an AppKit view reporting its window frame). `HeroOverlay` flies the cached cover from there to the album header's probed frame, then hands over. Reduce Motion skips it; the editor preview disables album navigation.
- **Cover viewer (`ArtViewerOverlay`, in `HeroTransition.swift`):** clicking an album page's header art sets `navigator.artViewer`; the root overlay grows the cover from the header's probed frame to a window-filling, aspect-correct view on black, swapping in a `.full` (4096 px) decode. Click or Esc shrinks it back.
- **Now Playing (`NowPlayingView.swift`):** opened from the bar or ⌘L. `NowPlayingOverlay` grows a clipped frame from the bar's probed window frame to the full window while the full-size content fades in, and reverses on close. Big art, title and the transport, centred. Coloured by the current cover's palette, with a 55% wash of the palette background over the blur so text contrast holds (album pages do the same). `QueueState.moveUpNext`/`clearUpNext` exist and are tested, but no view uses them since Playing Next was removed.
- **Lyrics (`Beat/Lyrics/`, `LyricsView`):** a lyrics button in Now Playing (remembered in `nowPlaying.showLyrics`) puts the player in a left column and lyrics on the right. `LyricsProvider` (actor, injected through `\.lyricsProvider`) resolves sources in order, via the pure `LyricsResolver`: a `.lrc` file beside the audio, embedded lyrics (`AVURLAsset.load(.lyrics)`; LRC-formatted text counts as synced), LRCLIB synced, embedded plain, LRCLIB plain. LRCLIB is used only when `lyrics.online` is on; answers (including misses, retried after 30 days) are cached in `Application Support/Beat/lyrics/<trackID>.json` and used even when the setting is off. Synced lyrics highlight the current line (`LRC.currentIndex` over `queue.currentTime`), auto-scroll unless the user scrolled in the last 4 s, and seek on click.
- **Output (`RoutePicker`):** `AVRoutePickerView` bound to Beat's `AVQueuePlayer` (`PlaybackQueue.outputPlayer`), in `ModeControls`. The system menu handles speakers, headphones and AirPlay, and routes Beat only.
- **Visualizer:** `AudioTap` attaches an `MTAudioProcessingTap` to each `AVPlayerItem` (skipped when `visualizer.enabled` is off). Its C process callback pulls the source audio through unchanged and mixes it to mono into `SampleBuffer` (a 2048-sample ring in a `Mutex`; real-time thread, no allocation). `SpectrumAnalyzer` (pure, tested) runs a Hann-windowed vDSP FFT on the main thread at display rate and reduces it to 64 log-spaced bands (30 Hz to 16 kHz), loudness, bass and a 256-point waveform; `Smoother` gives fast rise, slow fall. `VisualizerView` draws Pulse, Bars, Radial or Waveform in a `Canvas` under a `TimelineView`, coloured from the palette. Now Playing's visualizer mode (⇧⌘V) fills the view; controls and cursor hide after 3 s idle; Esc leaves the mode first. Visuals lead the sound on AirPlay (shown as a note).
- **Settings (`SettingsView`):** Appearance (`appearance.coverColours`: Cover Colours or Plain, which simply withholds the palette from album pages and Now Playing), Lyrics (`lyrics.online`, Clear Downloaded Lyrics) and Visualizer (`visualizer.enabled`, which skips the tap entirely).
  - **Library ▸ Songs = `AlbumSongsView`** (Album by Artist only): `SongsQuery.groupByAlbum` groups in library album order, split by `sectionsByArtist` under pinned album-artist headers (`LazyVStack` `pinnedViews: .sectionHeaders`; the name links to the artist page); each group is a plain cover (click: full-window viewer, only when the album has artwork) plus its title and year in a cover column the user resizes (`ColumnResizeHandle`, `songs.albumArtWidth`) beside `AlbumSongRow`s. Track number, title (artist underneath when it differs from the album artist) and time always show; other columns are `ExtraColumn`s chosen from a Columns menu (`songs.albumColumns`), display only, no sorting.
  - **Songs See All = `SongsTableView`**, where order matters: a compact, sortable `Table` with SwiftUI column customization (`@SceneStorage("SongsColumns")`) and optional 18 pt covers. Both views share `SongsHeader` and `SongsModel`, which filters/sorts/groups off the main actor through the pure `SongsQuery` (every search word must match; natural text sort; missing values last; custom-field values cached per track).
  - `AlbumGridView` search matches every word against `LibrarySnapshot.albumSearchText` (title, album artist and every track artist, folded), so featured and compilation artists find their albums.
  - `ArtistGenreViews`
- **Now-playing marker:** `PlayingIndicator` (animated equalizer bars) marks the current track in album rows, song cells and the Songs table.

## Persistence

| File | Owner | Contents |
|---|---|---|
| `~/Library/Application Support/Beat/history.json` | `PlayHistoryStore` | Beat-recorded plays/skips per track |
| `~/Library/Application Support/Beat/scrobbles.json` | `Scrobbler` | Plays waiting to be sent to Last.fm |
| Keychain `lastfm-session`, `UserDefaults` `lastfm.enabled`, `lastfm.username` | `Scrobbler`, Settings | Last.fm session, switch and account name |
| `~/Library/Application Support/Beat/pages.json` | `PageStore` | The sidebar tree: folders, pages, elements (each with its smart filter and appearance) |
| `~/Library/Application Support/Beat/filters.json` | (none) | Legacy smart filters from before pages; left on disk, no longer read |
| `UserDefaults` `volume` | `PlaybackQueue` | Last volume |
| `UserDefaults` `appearance.coverColours`, `lyrics.online`, `nowPlaying.showLyrics` | Settings, Now Playing | Preferences |
| `~/Library/Application Support/Beat/lyrics/` | `LyricsProvider` | Cached LRCLIB answers |
| `UserDefaults` `sidebar.selection`, `sidebar.expanded` | `AppNavigator` | The selected sidebar item (`SidebarItem.storageString`) and open folder IDs, restored at launch |
| `UserDefaults` `elements.newDefault` | `NewElementDefaults` | The `PageElement` (filter + appearance) new elements start from, set in Settings; absent means built-in |
| `UserDefaults` `library.hidden` | Settings | Library pages hidden from the sidebar |
| `UserDefaults` `appearance.sidebarTint`, `albums.artistList`, `artistInfo.online` | Settings, Albums | Sidebar tint on album and artist pages; Albums' artist list shown; Discogs lookups on |
| `UserDefaults` `artist.sorts` | Artist page | Sort order of Albums, Singles & EPs and Appears On (JSON `ArtistSorts`; shared by all artists) |
| Keychain `discogs-token` | Settings / `ArtistInfoProvider` | The user's Discogs personal access token |
| `~/Library/Application Support/Beat/artists/` | `ArtistInfoProvider` | Cached Discogs artist answers (JSON) and photos, named by a hash of the artist ID |

## Concurrency model
- All stores and `AudioPlayer` / `NowPlayingController` are `@MainActor`.
- `LibraryLoader` is an actor. Snapshots, tracks, filters and results are `Sendable` value types, so they cross into detached tasks freely.
- Heavy work (library mapping, filter evaluation, image decoding) runs off the main actor. Results are assigned back on the main actor.
- AVFoundation and NotificationCenter callbacks arrive on the main queue and use `MainActor.assumeIsolated`. MediaPlayer callbacks hop with `Task { @MainActor in … }`.
