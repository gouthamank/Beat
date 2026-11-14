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

## Gapless playback (wanted, Nov 2026: the gap between tracks shows in everyday use)
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

## Syncing plays to Music (on hold, Nov 2026)
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

## Ignoring items in Library > Health (noted Nov 2026)
Some Health items are fine as they are (a deliberate duplicate, an album left without a year). A way to dismiss
them, kept in Beat and never written to Music:

- **Ignore:** a row's hover button or right-click > Ignore hides it from its section.
- **Stored** next to `history.json` in Application Support, keyed by check plus album or song ID, so ignoring one
  problem on a song doesn't hide another (no album artist vs a duplicate).
- **Undo:** a section with ignored items ends with "3 ignored · Show", listing them dimmed with Don't Ignore;
  Settings could add Reset Ignored Items.
- **Stale entries:** an item fixed in Music stops matching, and its entry is dropped at the next check.
- Pure filtering over `LibraryHealthReport`, unit-tested; a small persisted store like `PlayHistoryStore`.

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

## Search field half shown at launch on iPhone (noted Nov 2026)
With the Library grids' search tucked away until pulled down (`SearchFieldPlacement.page` as
`.navigationBarDrawer(displayMode: .automatic)`), it started half revealed at launch: an empty pill under the large
title, gone after the first scroll. Ruled out: the status-bar spacing (`additionalSafeAreaInsets`), `remembersScroll`,
a saved scroll offset (a fresh launch shows it too). Search is always shown (`.always`) for now. Next: a small
Simulator test app (large title + hide-on-scroll search over a grid, adding Beat's grid modifiers one at a time:
`tracksScrolling`, `remembersScroll`, `keyboardGrid`, `contentMargins`) to find what moves the list at launch.

## Tests (noted Nov 2026)
Snapshot and UI tests, unit tests on iOS, and the seams they need: planned in phases in `TESTING.md`.
