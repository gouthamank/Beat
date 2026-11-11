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

## Artwork changed in Music: refresh without a relaunch
Changing an album's art in Music reaches Beat's library within seconds (`LibraryWatcher` reloads ~2 s after
Music writes `Library.musicdb`, and on activation), but covers already shown this session keep the old art
and colours until Beat relaunches:

- `ArtworkCache` keeps decoded images (`NSCache`, keyed by `ArtworkSource` + size) and palettes (dictionary,
  never evicted) across library reloads.
- `ArtworkView` reloads only when its `task(id: source)` changes, and the source (album/track ID) doesn't.

Plan:
- On each library reload, compare each album's cover track (`LibrarySnapshot.artworkTrackID`) and its
  `dateModified` with the previous snapshot; drop changed albums' (and their tracks') images and palettes.
- Include a per-album artwork revision in what `ArtworkView` keys its task on, so on-screen covers refetch;
  `CoverTint.refresh()` so a changed cover's page and sidebar colours update too.
- First check that Music actually bumps a track's modified date when only its artwork changes. If not,
  fall back to comparing a cheap fingerprint of the art bytes for albums on screen.
- Tests: the changed-album diff is pure (two snapshots in, changed album IDs out).

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
