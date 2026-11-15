# TODO

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

## Showcase website (planned Nov 2026)
A single page at `beat.gouthaman.dev`, hosted on Netlify, that shows Beat off and lets visitors try it.

Decided:
- **Stack:** Astro (static, no JavaScript but the demo's) with the demo as one React component, Tailwind,
  Framer Motion. In `site/` in this repo; Netlify's base directory is `site`.
- **Interactive demo near the top**, in the spirit of tryklack.com: a small working Beat window. Sidebar pages
  switch; an element's editor sits beside its page and changing a rule, sort or limit reflows the albums live;
  an appearance switcher (shelf, grid, list, Cover Flow, Timeline); clicking an album tints the now-playing bar
  with its cover colour; a Mac / iPhone toggle shows the phone layout with the drawer. Its filter engine is a small
  TypeScript copy of the app's rules.
- **Audio plays, never autoplays:** a handful of CC0 tracks (credited in the footer) behind the demo's play
  button, with a small visualizer. Nothing sounds until the visitor presses play.
- **No real album art anywhere** (copyright). One generated, made-up library (about 40 albums: names, artists,
  genres, years, covers drawn by a script) feeds both the demo's data and a showcase library the real app opens
  through `-BeatFixtureLibrary`, isolated like the UI-test build, for the screenshots and clips. The CC0 tracks go
  into it so the visualizer and Now Playing have real music.
- **Platforms:** Mac and iPhone get equal billing; iPad gets an "Also on iPad" line and one screenshot until it's
  been dogfooded more.
- **Sections:** hero (icon, pitch, Download for Mac, Build for iPhone); the demo; pages built from smart filters;
  Now Playing (cover colours, lyrics, Radial, visualizer clips); album and artist pages with the cover zoom;
  read-only and private; Mac, iPhone and iPad; Get Beat.
- **Mac download:** a GitHub Action on a `v*` tag builds Release, signs with the "Beat Local Signing" certificate
  (a .p12 and its password in GitHub secrets, imported into a temporary keychain; `Secrets.xcconfig` written from
  secrets too), makes a drag-to-Applications DMG with `create-dmg`, and attaches it to a GitHub Release. Not
  notarised: the site shows the System Settings > Privacy & Security > Open Anyway step (macOS 15 dropped
  right-click > Open). The runner image must have Xcode 26.
- **iPhone and iPad:** build from source only (no paid Apple Developer Program, so no TestFlight); the site links
  the README's steps and says a free Apple ID's install stops opening after 7 days. AltStore and SideStore were
  considered and dropped: too much setup for users.
- **Screenshots and clips:** captured by hand from the showcase library, from a shot list (window size, light or
  dark, what to have open), then resized and encoded by a script.

Order: the release action and DMG; the generated library (covers and data); the site's skeleton and sections; the
demo; the shot list, then the captures.

Open:
- Which CC0 tracks, and whether one has vocals for the lyrics shots (lyrics for a made-up song would need writing).
- Light and dark: the site follows the system; which one the screenshots lead with.
