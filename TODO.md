# TODO

## Custom navigation stack (deferred)
Swipe back currently uses the system `NavigationStack`: the swipe triggers Back and a chevron follows the
fingers, but the page itself doesn't move with them. Safari-style interactive swipes need Beat's own
navigation container instead of `NavigationStack`:

- Render the typed `[Route]` path (already in `AppNavigator`) in Beat's own container, with slide
  push/pop transitions.
- **Interactive swipe:** drive the top page's offset from `NSEvent.trackSwipeEvent`'s gesture amount,
  revealing the page underneath, and commit or cancel at the end.
- **The page underneath:** keep it as a snapshot taken when it was covered (as Safari does), or keep it
  alive but hidden. Hidden pages must not contribute toolbar items, `.searchable` fields or navigation
  titles, which is the main difficulty in SwiftUI.
- **Back and Forward buttons:** the toolbar back button and title handling `NavigationStack` gives for
  free would need replacing.
- **State on remount:** pages remounted after a pop would need their scroll and search restored per
  path entry. Today only sidebar roots remember them.

Deferred (Nov 2026) because it replaces the navigation foundation every page sits on; the system stack
with the reverse album zoom and a non-interactive swipe was the smaller change.

## Gapless playback (tabled Nov 2026)
`AudioPlayer` is an `AVQueuePlayer` with one preloaded item: quick, but a short silence still falls between
tracks. Proposal: move to `AVAudioEngine` with `AVAudioPlayerNode`, scheduling the next file to start on the
exact sample the current one ends.

- AAC encoder padding is trimmed when the file is read; MP3 padding needs checking on real files.
- Convert every track to one output format, so a change of sample rate between tracks doesn't leave a gap.
- Rebuild elapsed time and seeking, end-of-track detection, volume, and the visualizer's feed (an engine
  tap, simpler than `AudioTap`). Crossfade then becomes a small follow-up.
- Pure, tested timing logic: which part of which file plays when, and where a seek lands.
- **Risk: AirPlay.** `OutputRoute` routes the `AVPlayer`; an engine can't be handed to `AVRoutePickerView`.
  AirPlay speakers are output devices on macOS, so AirPlay would likely become an output-device menu.
  Build a throwaway test first (AirPlay through the engine, plus one gapless album) before replacing anything.
- Fallback if AirPlay through the engine is bad: keep `AVPlayer` and join consecutive tracks into one
  `AVComposition`. Keeps the picker; queue edits get harder.

Open decision: engine test (AirPlay may become a device menu) or the composition fallback.

## Syncing plays to Music (tabled Nov 2026, needs a decision)
Beat's plays and skips live in `history.json` and are added to Music's counts only inside Beat
(`PlayHistoryStore.merged`). Music, other devices and Music's smart playlists never see them.

The only way to write them is Music's AppleScript interface: `played count`, `played date`, `skipped count`
and `skipped date` are writable, and tracks match by persistent ID. Costs:

- Breaks the "never write to the Music library" hard rule; the rule would need relaxing for these four fields.
- Music must be running. Hold pending plays and write them when Music next opens; never launch it.
- Automation permission prompt, which may come back after ad-hoc rebuilds.
- Plays counted twice: once synced, Beat must stop adding its own copy, so history tracks synced vs pending.
- Can't be undone: with iCloud Music Library, counts (and any bug) spread to other devices.
- Each write makes Music save its library and `LibraryWatcher` reload, so batch writes.

Options: A keep them separate; B opt-in automatic sync (off by default, batched, only while Music runs);
C a manual "Send Beat's plays to Music" button. Leaning B plus C's button for plays already recorded.

## Faster search results (noted Nov 2026)
On Library ▸ Songs there's a visible gap between typing a search and the results appearing; other pages may
feel the same. Each keystroke (`SongsModel.update` in `SongsTableView.swift`) waits 150 ms for typing to stop,
then in a background task folds every song's "title artist albumArtist album" (`SearchText.fold`, ~20k songs,
redone on every search), filters, groups by album and artist, and finally rebuilds the whole
`AlbumSongsLayout` and reloads the table on the main thread.

Plan:
- Measure first: a Time Profiler run while typing on Songs, to see where the time actually goes.
- Fold each song's search text once per library load and reuse it, so a keystroke is only substring checks.
- Build `AlbumSongsLayout` in the background task with the filtering; the main thread only swaps it in.
- Only if it's still noticeably slow: a small spinner (search field or subtitle) shown after ~250 ms, so quick
  searches don't flicker.
- Check Albums, Artists and Genres searches the same way.

## Quick Open (noted Nov 2026)
Jump anywhere by typing: a ⌘K panel over the window that finds albums, artists, genres, sidebar pages and
songs as you type, and opens or plays the pick. With ~3k albums and a deep sidebar tree, it's the fastest way
around the library.

Ideas:
- Results grouped by kind (pages, albums, artists, genres, songs), best matches first; ↑ ↓ to move, Return to
  open, ⌥Return (or similar) to play.
- Open through `AppNavigator.openAlbum/openArtist/openGenre` and sidebar selection, so the navigation rules
  (nesting, the cover zoom) hold.
- Match on folded text built once per library load: `LibrarySnapshot.albumSearchText` already has it per album,
  and the smart-filter `FoldedText` folds song fields once. Search off the main actor; keep keystrokes cheap.
- Glass panel via `beatGlass`; Esc or a click outside closes it.

## Sort buttons on page elements (noted Nov 2026)
Change an element's order straight from its header, without opening the filter editor, like the album sort
menu on artist pages (`AlbumSortMenu` in `ArtistDetailView.swift`).

Questions to settle first:
- Does a choice made here change the element's saved filter (its Sort step in `pages.json`), or only how it's
  shown this session? Saving keeps one source of truth; a temporary override would need a reset.
- Which sorts to offer: the element's own Sort step plus a few common ones for its kind (title, artist, year,
  date added, plays, random), and ascending/descending.
- Filters whose Limit comes after the Sort ("25 most played") give different songs when re-sorted; a header
  sort should probably re-order the result without changing what the limit picked.

## Library health page (noted Nov 2026)
A read-only report of what's worth fixing in Music. Beat never writes to the library, so it only points the way:
each item names the problem and opens the album (or shows the song) so it can be fixed in Music.

Checks:
- Albums without artwork (`LibrarySnapshot.hasArtwork`), and albums whose songs carry mixed covers.
- Songs or albums with no year (they land under Timeline's "No year").
- Likely duplicates: the same title, artist and length on more than one song, or the same album split in two
  (same title and album artist, different album IDs).
- Missing files: songs whose `location` no longer exists on disk.
- Inconsistent tags within an album: mixed album artists, genres or years, gaps or repeats in track numbers.
- Songs without a genre or album artist.

Ideas:
- A Library page in the sidebar (hideable in Settings like the others), one section per check with a count;
  computed off the main actor, once per library load.
- Pure checks over a `LibrarySnapshot`, so each is unit-tested with `Track.fixture`.

## First-run tutorial (noted Nov 2026)
A guided first look, like Android's spotlight coach marks, with most of the time spent on custom pages and
smart filters, Beat's headline feature and the least obvious one.

The Mac equivalents:
- TipKit (macOS 14+, so fine for Beat's macOS 15 target): popover tips anchored to a control, with rules for
  when each shows (after an event, once per user) and no repeat once dismissed. The native, low-effort option.
- Spotlight-style coach marks (dim everything except one control, a caption beside it): not built in, but Beat
  already measures views in window coordinates (`FrameProbe`) and draws window overlays (`HeroOverlay`), so a
  dimmed overlay with a cut-out is within reach.
- Possibly both: a short spotlight tour on first launch, TipKit tips for things found later.

Flow ideas, smart filters first:
1. Welcome: Beat reads the Music library and never changes it.
2. The sidebar: folders and pages, and Home is just a page you can edit.
3. Make a page, add an element, and walk the editor: "Find [kind] in [source]", a rule, a sort, a limit, then
   Appearance (shelf, grid, list, Cover Flow, Timeline). Ideally on the user's own library with a sample filter
   (e.g. "most played albums this year") that's created as they go.
4. Shorter stops: Now Playing (click the cover for Radial, lyrics, the visualizer), Space to play/pause, swipe
   back.

To decide:
- Skippable at any step, replayable from the Help menu; a tip shown once never returns.
- Whether the tour creates a real page or uses a throwaway one it removes at the end.
- Keep it short: a few steps on launch, the rest as tips when the user first reaches each place.

## Reorderable columns in Library > Songs (noted Nov 2026)
Drag a column header sideways to move the column, like Finder and Music. Investigated, not started.

Where things stand:
- Library > Songs is the AppKit `AlbumSongsTable` (an `NSTableView`), which turns reordering off outright
  (`allowsColumnReordering = false` in `makeNSView`) and rebuilds its columns in a fixed order in
  `rebuildColumns`: leading pad, cover, #, Title, the optional columns, Time, trailing pad.
- Smart-filter song lists (`SongsTableView`, SwiftUI `Table`) already reorder by drag through
  `TableColumnCustomization`, but keep it in `@SceneStorage("SongsColumns")`, which survives only as long as
  the window's restored state; moving it to `@AppStorage` (it's Codable) would make it stick for sure.

Plan for Library > Songs (native header drag, no new UI):
- Turn reordering on and veto moves in `tableView(_:shouldReorderColumn:toColumn:)`: the pads and the cover
  column stay put (covers are drawn behind the rows at the cover column's position, and `SongRowView.hitTest`
  passes clicks there through to them). #, Title, the optional columns and Time move freely among themselves.
- Save the order on `tableViewColumnDidMove`. `songs.albumColumns` ("genre,plays") only records which optional
  columns are shown: `AlbumSongsView.shown` filters the built-in list through a Set, so order comes from that
  list. Add a saved order (say `songs.columnOrder`, covering #, Title, Time and the optional columns), have
  `shown` and `rebuildColumns` follow it, and add the key to `SettingsArchive.preferenceKeys`.
- `SongRowView.songArea` (the row highlight and click area) is computed from the # column's left edge to the
  Time column's right edge (`rect(ofColumn: number)` ... `rect(ofColumn: time)`), which assumes # is first and
  Time last. Compute it from the leftmost and rightmost movable columns instead.
- `fitTitleColumn` already works from widths, not positions, so Title can sit anywhere.
- Tests: the saved-order parsing and merging (new optional columns appended, removed ones dropped) is pure.

## Showcase website (noted Nov 2026)
A single page that shows Beat off: what it is, what it looks like, and how to get it.

Ideas:
- Lead with the headline feature: the sidebar of pages built from smart filters, shown with a real page
  (shelves, Cover Flow, Timeline) next to the filter that makes it.
- Sections for Now Playing (cover colours, lyrics, Radial), the visualizer scenes (short looping clips),
  album and artist pages with the cover zoom, and the read-only promise: Beat never changes the Music library.
- Screenshots and short screen recordings from the real app, in light and dark, on macOS 15 and 26.
- Download and requirements: macOS 15+, local DRM-free files; how to install a build that isn't notarised
  (signing is self-signed for now), and a link to the GitHub repo (MIT).
- Hosting: GitHub Pages from the repo (a `docs/` folder or a `gh-pages` branch) keeps it free and next to
  the code.

## iPad, then iPhone (noted Nov 2026)
Beat on iPad first, then iPhone, sharing one engine with the Mac app. The library is the songs synced to the
device from the Mac (Finder sync); Apple Music streaming and cloud-only songs stay out of scope, as on the Mac.

Library:
- A new loader on MediaPlayer (`MPMediaQuery` / `MPMediaLibrary`, "Media & Apple Music" permission) producing
  the same `[Track]` as `LibraryLoader` does from `iTunesLibrary`, which is macOS-only.
- Play `MPMediaItem.assetURL` with `AVPlayer`. It's nil for DRM and cloud-only items: skip those at load, the
  iOS form of "tracks without a file location are skipped".
- Available: title, artists, album, genre, grouping, comments, composer, year, plays, skips, rating, BPM,
  dates, track/disc numbers, duration, artwork. Not available: bitrate, sample rate, file size, kind, file
  path. Hide what depends on them (format line, file sizes, `.lrc` lyrics beside files); embedded and online
  lyrics still work.
- Library changes: `MPMediaLibraryDidChange` notifications instead of `LibraryWatcher` (FSEvents).

Shared as is (pure Swift): models, `SmartFilterEngine`, pages (`PageStore`, `pages.json`), play history,
`QueueState`, lyrics parsing, Last.fm, Discogs, `ArtworkPalette`, spectrum analysis, the launch caches, and
their tests. Playback carries over too: `AVPlayer`, the audio tap, `MPRemoteCommandCenter`, AirPlay picker
(plus an audio session and the background audio mode on iOS).

Interface work:
- `project.yml`: a multiplatform target (or a shared framework plus Mac and iOS apps).
- UIKit versions of the AppKit pieces: `FrameProbe`, `ShapeShadow`, `PlayingIndicator`; `NSImage` to a
  platform image type in `ArtworkCache`/`BackdropImages`.
- Library > Songs (`AlbumSongsTable`, an `NSTableView`) needs a touch version.
- The AppKit event monitors (swipe back, Space, sidebar reclick, search focus) drop out or become gestures;
  hover, keyboard grids and right-click menus become touch, long-press and swipe equivalents.
- Settings window becomes a settings screen; Liquid Glass via `Glass.swift` works natively on iOS 26.

Order:
1. iPad: `NavigationSplitView` behaves much as on the Mac, so the sidebar of pages carries over. Roughly two to
   three weeks of focused work for a solid first version.
2. iPhone: the sidebar becomes a tab bar or a list to drill into; layouts for a small screen. A few more weeks.
- Pages and settings move between devices with Settings > Export/Import (`SettingsArchive`) to start with.
