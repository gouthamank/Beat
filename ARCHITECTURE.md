# How Beat is built

Beat is a music player that sits on top of the music you already have. On the Mac it reads the Music app's
library; on iPad and iPhone, the songs synced to the device. It never changes that library. What it adds is its own
way of browsing: a sidebar of **pages**, each made of **elements**, and each element is a **smart filter** (find
songs, sort them, keep some) shown in a layout of your choosing.

This document walks through the pieces in the order data flows through them: from the library, through the
filters, to the screen and the speakers. The diagrams are [Mermaid](https://mermaid.js.org), which GitHub and most
Markdown viewers draw as pictures. For the rules to follow when changing things, see `CLAUDE.md`.

## The big picture

```mermaid
flowchart TD
    music[("Music library<br/>(Mac: Music app · iPhone/iPad: synced songs)")]
    source["LibrarySource<br/>reads it, read-only"]
    store["LibraryStore<br/>the current snapshot"]
    history["PlayHistoryStore<br/>Beat's own plays and skips"]
    pages["PageStore<br/>pages, elements, results"]
    engine["SmartFilterEngine<br/>filter → sort → limit"]
    views["Views<br/>sidebar, pages, album and artist pages"]
    queue["PlaybackQueue"]
    player["AudioPlayer<br/>(AVQueuePlayer)"]
    system["Lock screen, media keys,<br/>Last.fm (optional)"]

    music --> source --> store
    store --> pages
    history --> pages
    pages <--> engine
    pages --> views
    views -- "play these" --> queue
    queue --> player
    queue --> history
    queue --> system
```

`BeatApp` creates one of each store at launch and hands them to every view through SwiftUI's environment
(`.environment(...)`): `LibraryStore`, `ArtworkCache`, `PlayHistoryStore`, `PlaybackQueue`, `PageStore`,
`AppNavigator` and a few smaller ones (`HeroTransition`, `ArtistImages`, `Scrobbler`). There are no global
singletons beyond the system's own media centres.

Where the code lives:

| Folder | What's in it |
|---|---|
| `Beat/Library` | The data model, reading the library, artwork, the launch caches, play history, Quick Open's index, Library ▸ Health's checks |
| `Beat/SmartFilters` | What a smart filter is, the engine that runs it, the presets |
| `Beat/Pages` | The sidebar tree of folders and pages, page elements, saving them |
| `Beat/Playback` | The queue, the audio player, the audio tap for the visualizer, system Now Playing |
| `Beat/Lyrics`, `Beat/ArtistInfo`, `Beat/Scrobbling` | The optional online extras: LRCLIB lyrics, Discogs artist info, Last.fm |
| `Beat/DesignSystem` | Liquid Glass (with a fallback for macOS 15), artwork views, blurred backdrops |
| `Beat/Views` | The screens |
| `Beat/Platform` | Everything that differs between the Mac and iPad/iPhone (see [Platforms](#platforms)) |
| `BeatTests` | Unit tests for the pure logic |

## The library

Everything starts with a **`LibrarySnapshot`**: an immutable value holding every playable song (`Track`) and the
albums, artists and genres built from them (`LibrarySnapshot.build(tracks:)`, a pure, tested function). Because
it's a plain value, it can be handed to background work freely. It also carries each album's and each song's
search text, folded (case and accents removed) once when it's built, so a search only compares text: the Library
pages' searches and Quick Open all use it.

A **`LibrarySource`** produces it. There are three, one per situation:

| Source | Where | Reads |
|---|---|---|
| `LibraryLoader` | Mac | The Music app's library through `iTunesLibrary.framework` |
| `MediaLibrarySource` | iPhone, iPad | Songs synced from a Mac, through MediaPlayer (`MPMediaQuery`) |
| `FolderLibrarySource` | Simulator, UI tests | Audio files in the app's Documents folder (the Simulator has no library), or the UI tests' fixture songs |

Songs without a playable file (Apple Music streaming, cloud-only, DRM) are skipped. Beat only plays local files.

`FolderLibrarySource` reads tags from the files itself. It skips hidden files and folders (songs deleted in the
Files app wait in a hidden `.Trash` there), and falls back to ID3v2.2's three-letter frames (`TP2`, `TYE`, `TRK`,
`TCO`), which older iTunes wrote and AVFoundation gives no standard identifier.

**`LibraryStore`** owns the current snapshot. Reading 20,000 songs takes a few seconds, so launch is two-stage:

1. Show the library saved last time (`LibraryCache`, a JSON file in Caches) straight away.
2. Read the real library behind it, and swap it in only if something changed.

Cover thumbnails are saved too (`ArtworkDiskCache`, small HEIC files), named after the cover they came from, so a
changed cover never shows a stale picture. `ArtworkCache` decodes and scales artwork off the main thread, keeps
each cover's colour palette (`ArtworkPalette`), and serves anything already loaded instantly.

The library is re-read when Music changes it: the Mac watches Music's database files (`LibraryWatcher`, FSEvents),
iOS listens for MediaPlayer's change notification. Switching back to Beat re-reads only if something changed.

**`PlayHistoryStore`** keeps Beat's own play and skip counts (a play counts at half the song or 4 minutes). They
are merged with Music's counts when filters run, and never written back to Music.

## Smart filters

A smart filter is a short pipeline of steps, run in order:

```mermaid
flowchart LR
    all["Whole library"] --> f["Filter<br/>match all / any / none<br/>of rules and groups"]
    f --> s["Sort<br/>by fields, a custom field,<br/>or random (stable for the day)"]
    s --> l["Limit<br/>first N songs, albums, artists,<br/>genres, minutes or hours"]
    l --> p["Show as<br/>songs · albums · artists · genres"]
```

Steps can repeat and their order matters: "sort by plays, keep 25" isn't "keep 25, sort by plays". A filter that
shows albums still works on songs underneath; the albums are whatever those songs belong to.

The model is in `SmartFilter.swift` and `Field.swift`. The engine (`SmartFilterEngine.evaluate`) is a pure function
from a filter and a **`PreparedLibrary`** (the snapshot with play history merged in, plus the current date) to a
`FilterResult`. Being pure makes it easy to test and safe to run in the background:

- Each filter step is compiled once into a closure rather than interpreted per song.
- Text fields are folded (case and accents removed) once per library, not once per comparison.
- A page's elements are evaluated in parallel.

**Custom fields** (`CustomField.swift`) let you sort by something inside a tag, like a catalogue number in
brackets, or anything a regular expression can pull out.

## Pages

The sidebar is a free-form tree: folders and pages, mixed at any level. Only pages hold content.

```mermaid
flowchart TD
    tree["PageTree"] --> folder["Folder"]
    tree --> page1["Page"]
    folder --> page2["Page"]
    folder --> sub["Folder"]
    page1 --> e1["Element"]
    page1 --> e2["Element"]
    e1 --> filter["SmartFilter<br/>what to find"]
    e1 --> look["ElementAppearance<br/>how to show it"]
```

Each **element** owns its filter and its appearance: shelf, grid, list, Cover Flow or year timeline, plus size,
rows, spacing and so on. Home is just an ordinary page.

**`PageTree`** (pure, tested) does every structural change: insert, move, duplicate, delete. **`PageStore`** holds
the tree, saves it to `pages.json`, and runs filters lazily, only for the page on screen and only for elements that
changed. A `pages.json` that won't read is set aside rather than overwritten.

The **element editor** (`FilterEditorSheet`) edits a draft (`EditableFilter`, a copy of the filter with an ID on every
piece so lists can be edited safely) and shows a live preview built from the real element view. Its layout differs
by platform: a window with the preview beside Rules and Appearance on the Mac, and forms in a navigation stack on
iPad and iPhone (see [Platforms](#platforms)).

## On screen

`RootView` lays out the window: the sidebar, the page with its navigation stack, and a few full-window layers on top.

```mermaid
flowchart TD
    root["RootView"]
    root --> split["Sidebar + page stack<br/>(Mac, iPad: side by side · iPhone: page with a drawer)"]
    root --> bar["Now-playing bar<br/>(one per window)"]
    root --> layers["Full-window layers:<br/>cover flight · Now Playing · cover viewer · Quick Open"]
    split --> pagev["Page: its elements"]
    pagev --> detail["Album, artist, genre and See All pages<br/>(pushed onto the stack)"]
```

A few things are worth knowing about why it's shaped this way:

- **The now-playing bar and the full-window layers sit above the navigation stack, not inside it.** Pages pushed
  onto a stack are drawn above anything attached to the stack, so the bar would vanish under an album page. One bar
  for the whole window also stays still while pages slide in and out.
- **Opening an album or artist is always done through `AppNavigator`** (`openAlbum`, `openArtist`, `openGenre`).
  It keeps one navigation trail per sidebar page, returns to a page already in the trail instead of opening it
  twice, and remembers each page's scroll position and search.
- **Album and artist pages take their colours from the cover.** `CoverTint` works out the front page's palette and
  everything that follows the cover reads from it: the page, the sidebar, the now-playing bar and, on the Mac, the
  window's light or dark. Text colours are picked to stay readable on the cover's background.
- **Covers fly between screens.** On the Mac, tapping a tile flies its cover into the album page's header and back
  again (`HeroTransition`). Views in separate columns can't share SwiftUI's matched geometry, so each tile carries a
  tiny probe that reports its position in the window (`FrameProbe`), and the flight is drawn in a layer over
  everything. iPad and iPhone use iOS's own zoom transition instead, which can follow a swipe down.
- **Library ▸ Songs** groups every song by album under its album artist. On the Mac that's an AppKit table, since a
  SwiftUI list of ~3,000 album blocks was too slow; on iPad and iPhone, for now, a SwiftUI list. `SongsModel`
  filters, groups and lays out the rows (`AlbumSongsLayout`) in the background, so the main thread only swaps them in.
  On the Mac the song columns can be dragged into another order and the optional ones resized (`SongColumnOrder`,
  `SongColumnWidths`, both saved); the padding and cover columns stay put, because covers are drawn behind the rows
  at the cover column.
- **Search** is per page: a field in the toolbar on the Mac, and under the title on iPad and iPhone, where it tucks
  away as the page scrolls. There a page subtitle present from the first frame squashed it, so `pageSubtitle` shows
  its text a frame late.
- **Grids, shelves and lists work from the keyboard** on the Mac (`KeyboardGrid`): each collection is one Tab stop,
  and the arrow keys move a highlight across it.

### Quick Open

⌘K on the Mac, or the search button at the top of the sidebar on iPad and iPhone, opens a panel over the window that
finds pages, albums, artists, genres and songs as you type. **`QuickOpenIndex`** (pure, tested) holds every item's
folded text, built once per library or sidebar change off the main thread, and ranks matches: exact names, then names
starting with the query, then word starts, then any match; groups are ordered by their best match.

What a pick does is decided by **`QuickOpenAction.resolve`** (pure, tested): a page is selected in the sidebar;
albums, artists and genres open on the Library page that lists them (`AppNavigator.goTo`), so the sidebar shows where
you are; a song opens its album with the song highlighted, shows it in Library ▸ Songs, or plays, as chosen in
Settings ▸ General. On the Mac ⌥Return does the other of opening and playing. The panel dims the whole window: on
the Mac the title bar and toolbar are drawn by AppKit above SwiftUI's content, so they get a dim view of their own
(`titleBarDim`).

### Library ▸ Health (Mac)

A read-only report of what's worth fixing in Music: albums without artwork, songs without a year, likely
duplicates, albums split in two, missing files, mixed tags within an album, and songs without a genre or album
artist. **`LibraryHealth`** runs the checks (pure, tested; the file check is passed in), once per library version
in the background. Each row opens its album, a song's with the song highlighted, to fix it in Music. It's Mac only
(`LibraryPage.available`): a synced library can't be fixed on iPad or iPhone, and its file and year checks don't
apply there.

### Now Playing

The bar opens **Now Playing**, which grows out of the bar to fill the window and shrinks back into it. It shows the
cover on its own colours, the transport, optional **lyrics** and a full-screen **visualizer**:

- **Lyrics** come from, in order: a `.lrc` file beside the song, lyrics embedded in the file, then (only if you turn
  it on) LRCLIB online. Synced lyrics follow the song and seek when tapped. A DJ mix whose "lyrics" are a timed
  tracklist becomes **chapters** instead: the progress line splits at each track (`MixChapters`).
- **The visualizer** reads the audio through a tap on the player (`AudioTap`, one tap shared by every song; see
  [Playback](#playback)), analyses it on the main thread (`SpectrumAnalyzer`, an FFT into 64 bands) and draws it as a
  waveform or one of several scenes. Radial, a ring of bars around the cover, is toggled by clicking the cover.

## Playback

```mermaid
flowchart LR
    views["Views"] -- "play, next, shuffle…" --> queue["PlaybackQueue"]
    queue --> state["QueueState<br/>order, shuffle, repeat<br/>(pure, tested)"]
    queue --> player["AudioPlayer<br/>current song + next one preloaded"]
    player --> tap["AudioTap → visualizer<br/>(one tap for every song)"]
    queue --> np["NowPlayingController<br/>lock screen, media keys"]
    queue --> hist["PlayHistoryStore"]
    queue --> scrob["Scrobbler (Last.fm, opt-in)"]
```

`PlaybackQueue` is what the views talk to. The ordering rules (shuffle that keeps the current song first, repeat
one and all, skipping missing files) live in `QueueState`, a pure struct with its own tests. On the Mac the volume
slider is Beat's own; on iPad and iPhone it is the system volume.

**Gapless.** `AudioPlayer` is an `AVQueuePlayer` holding the current song and the next one, which it joins without a
gap: encoder padding (iTunes' `iTunSMPB` in MP3s, and AAC's) is trimmed as files are read. The visualizer's tap goes
on every song through an audio mix, and it must be **one tap shared by all of them** (`AudioTap.make` once, then
`attach` to each item): a fresh tap per song stopped `AVQueuePlayer` joining them, leaving a short silence at every
boundary. An audio mix alone, or no tap, doesn't.

**Crossfade (not built).** Overlapping two songs, each fading, is beyond `AVQueuePlayer` and would need
`AVAudioEngine` with a player node per song. A throwaway test (an album played through `AVAudioEngine` with the files
scheduled back to back) found:

- The engine joins files exactly: MP3s with encoder padding information are trimmed when read.
- **AirPlay changes.** macOS lists AirPlay speakers as outputs only once one is the Mac's output (Control Center ▸
  Sound). An engine can't offer them in Beat's own picker the way `AVRoutePickerView` does for an `AVPlayer`, so
  AirPlay would mean the Mac's system output.
- Everything `AVQueuePlayer` gives for free would be rebuilt: elapsed time and seeking, end of song, volume, and
  the visualizer's feed (an engine tap, simpler than `AudioTap`).

## Platforms

Beat is two apps from one set of sources. The Mac target (`Beat`) and the iPad/iPhone target (`BeatiOS`) compile
the same `Beat/` folder, except that each leaves out the other's half of `Beat/Platform/`.

```mermaid
flowchart TD
    shared["Shared code: Beat/<br/>models, filters, pages, playback,<br/>most views"]
    api["Platform.swift<br/>lists the names both platforms provide"]
    mac["Beat/Platform/macOS<br/>AppKit, iTunesLibrary"]
    ios["Beat/Platform/iOS<br/>UIKit, MediaPlayer"]
    shared --> api
    api -. "Mac app" .-> mac
    api -. "iPad / iPhone app" .-> ios
```

Shared code never mentions AppKit or UIKit. Where the platforms differ, both folders provide the **same names**,
and each app compiles one of them:

| File (in both folders) | What it provides |
|---|---|
| `Platform+*.swift` | Images and colours (`PlatformImage`, `PlatformColor`), opening links, the window background, where a page's search field goes and its subtitle (`SearchFieldPlacement.page`, `pageSubtitle`), small view helpers |
| `Window+*.swift` | The window around `RootView`: light/dark handling, event monitors and Quick Open's title-bar dim (`titleBarDim`) on the Mac; phone layouts, the sidebar drawer, Settings as a sheet and zoom transitions on iOS |
| `BeatApp+*.swift` | Start-up setup, menus, the Mac's Settings window and About panel |
| `SettingsView+*.swift` | The Settings container (Mac tabs, iPad two columns, iPhone list) and settings-file import/export |
| `ElementEditor+*.swift` | The element editor's layout |
| `FrameProbe.swift` | The tiny view that reports a tile's position for transitions |
| `BarLayers.swift` | The now-playing bar's progress drawing |
| `AlbumSongsTable.swift` | Library ▸ Songs |
| `LibraryWatcher.swift`, `OutputRoute.swift`, `RoutePicker.swift`, `VolumeControl.swift` | Library changes, AirPlay, volume |

Some pieces exist on one platform only: the library loaders (above), Library ▸ Health and the reorderable Songs
columns on the Mac, the Mac's keyboard and trackpad monitors (Space to play, ⌘[ and swipe back), and the iOS
sidebar drawer, form-based rule editor, back-swipe restorer and keyboard dismissal. Differences of a line or two stay in the shared file as `#if os(macOS)`.

**Phones and narrow iPad windows** get their own layouts through one switch, `\.compactLayout` (set from iOS's
horizontal size class, always off on the Mac):

- The sidebar becomes a drawer over the page.
- Album and artist headers stack, lists drop their cards, and shelves size their covers to the screen.
- The element editor becomes forms with Cancel and Save in its navigation bar.
- Now Playing stacks the cover, lyrics and controls vertically.

Because the switch is off on the Mac, the Mac's layouts never change.

## What's saved where

| What | Where | Owner |
|---|---|---|
| Pages, elements and custom fields | `Application Support/Beat/pages.json` | `PageStore` |
| Beat's plays and skips | `Application Support/Beat/history.json` | `PlayHistoryStore` |
| Scrobbles waiting to send | `Application Support/Beat/scrobbles.json` | `Scrobbler` |
| Downloaded lyrics | `Application Support/Beat/lyrics/` | `LyricsProvider` |
| Downloaded artist info and photos | `Application Support/Beat/artists/` | `ArtistInfoProvider` |
| The library as last read, for a fast launch | `Caches/Beat/library.json` | `LibraryCache` |
| Cover thumbnails | `Caches/Beat/Thumbnails/` | `ArtworkDiskCache` |
| Last.fm session, Discogs token | Keychain | `Scrobbler`, Settings |
| Preferences (including Quick Open's choices and the Songs columns' order and widths), the selected page, open folders, volume | `UserDefaults` | Settings, `AppNavigator`, `PlaybackQueue`, Library ▸ Songs |

Settings ▸ General ▸ Export saves pages, elements, custom fields and the preferences in one file
(`SettingsArchive`), which is how they move between a Mac and an iPhone. Tokens and play history stay on each device.

## Doing work off the main thread

The stores, the player and the views run on the main actor. The library, filters and results are plain `Sendable`
values, so the heavy work (reading the library, running filters, decoding artwork) happens in background tasks and
only the result comes back. The library loaders are actors. The one exception to "analysis on the main thread" is
the audio tap's callback, which runs on the real-time audio thread and therefore only copies samples into a buffer:
no allocation, no locks it can wait on.
