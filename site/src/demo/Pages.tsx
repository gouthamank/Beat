// The page column's contents, after Beat's views: a page of elements (PageView, ElementView), an element's See All
// (ElementDetailView), an album page (AlbumDetailView), a genre's albums, and Library's Albums, Artists, Songs and
// Genres (AlbumsLibraryView, AlbumSongsView, ArtistGridView, GenreGridView).
import { useMemo, useState, type ReactNode } from 'react';
import { useDemo } from './context';
import { Icon } from './Icon';
import { ElementContent } from './Layouts';
import { AlbumTile, ArtistTile, Artwork, GenreTile, PlayingIndicator } from './Tiles';
import {
  counted, elementPadding, evaluate, formatTime, isDark,
  type DemoAlbum, type Element, type FilterResult, type Genre, type PageNode, type Track,
} from './model';

/** The page column's header: a title (and subtitle) on the left, the page's buttons on the right, as the window's
 *  toolbar shows them. */
export function PageHeader({ title, subtitle, back, children }: { title?: string; subtitle?: string; back?: () => void; children?: ReactNode }) {
  const { compact } = useDemo();
  return (
    <div className={`sticky top-0 z-20 flex items-center gap-3 border-b border-line bg-raised/85 backdrop-blur-xl ${compact ? 'px-4 pt-1 pb-2' : 'h-[52px] px-5'}`}>
      {back && (
        <button onClick={back} className="grid size-7 cursor-pointer place-items-center rounded-md text-soft hover:bg-ink/[0.07]" aria-label="Back">
          <Icon name="chevron.left" className="size-4" strokeWidth={2} />
        </button>
      )}
      {title && (
        <div className="min-w-0 flex-1">
          <div className={`truncate font-semibold ${compact ? 'text-[17px]' : 'text-[15px]'}`}>{title}</div>
          {subtitle && <div className="truncate text-[11px] text-soft">{subtitle}</div>}
        </div>
      )}
      {!title && <div className="flex-1" />}
      <div className="flex items-center gap-1">{children}</div>
    </div>
  );
}

export function ToolbarButton({ icon, label, onClick, active, disabled }: { icon: string; label: string; onClick: () => void; active?: boolean; disabled?: boolean }) {
  return (
    <button onClick={onClick} disabled={disabled} aria-label={label} title={label} aria-pressed={active}
            className={`grid size-8 cursor-pointer place-items-center rounded-md text-soft hover:bg-ink/[0.07] hover:text-ink disabled:cursor-default disabled:opacity-35 ${active ? 'bg-ink/[0.1] text-ink' : ''}`}>
      <Icon name={icon} className="size-[17px]" />
    </button>
  );
}

function GlassButton({ icon, label, onClick }: { icon: string; label: string; onClick: () => void }) {
  return (
    <button onClick={onClick} aria-label={label} title={label} className="glass grid h-7 w-9 cursor-pointer place-items-center rounded-full">
      <Icon name={icon} className="size-3.5" />
    </button>
  );
}

/** One element: its header (title and a chevron that opens See All; Play and Shuffle, or in Edit Page mode the
 *  element's controls), then its result in its layout. */
export function ElementView({ element, pageID, result, editing, index, count, accent, actions }: {
  element: Element; pageID: string; result: FilterResult; editing: boolean; index: number; count: number; accent: string;
  actions: { edit: () => void; move: (by: number) => void; duplicate: () => void; remove: () => void };
}) {
  const { openElement, player, compact, preview } = useDemo();
  const look = element.appearance;
  const inset = compact ? 16 : 24;
  if (!editing && !look.showHeader && result.count === 0) return null;
  return (
    <section className="flex flex-col gap-3.5" style={{ paddingBlock: elementPadding(look.spacing) }}>
      {(editing || look.showHeader) && (
        <div className="flex items-center gap-2.5" style={{ paddingInline: inset }}>
          <button onClick={() => !preview && openElement(pageID, element.id)} className="flex min-w-0 cursor-pointer items-baseline gap-2 text-left" title="See All">
            <span className="truncate text-[21px] font-bold">{element.filter.name || 'Untitled'}</span>
            <Icon name="chevron.right" className="size-3.5 shrink-0 text-faint" strokeWidth={2.2} />
          </button>
          {editing && !look.showHeader && <span className="text-[11px] text-soft">Header hidden</span>}
          <div className="flex-1" />
          {editing && !preview ? (
            <div className="flex items-center gap-3 text-soft">
              <button onClick={() => actions.move(-1)} disabled={index === 0} className="cursor-pointer disabled:opacity-30" title="Move Up"><Icon name="chevron.up" /></button>
              <button onClick={() => actions.move(1)} disabled={index >= count - 1} className="cursor-pointer disabled:opacity-30" title="Move Down"><Icon name="chevron.down" /></button>
              <button onClick={actions.edit} className="cursor-pointer" title="Edit Element"><Icon name="slider.horizontal.3" /></button>
              <button onClick={actions.duplicate} className="cursor-pointer" title="Duplicate"><Icon name="plus.square.on.square" /></button>
              <button onClick={actions.remove} className="cursor-pointer" title="Delete Element"><Icon name="trash" /></button>
            </div>
          ) : (
            // Edit sits beside Play outside Edit Page too (Beat has it only there), so the smart filter is easy to find.
            <div className={`flex gap-2 ${preview ? 'pointer-events-none' : ''}`}>
              {!preview && <GlassButton icon="slider.horizontal.3" label="Edit Smart Filter" onClick={actions.edit} />}
              {look.showPlayButtons && result.tracks.length > 0 && (
                <>
                  <GlassButton icon="play.fill" label="Play" onClick={() => player.play(result.tracks)} />
                  <GlassButton icon="shuffle" label="Shuffle" onClick={() => player.play(result.tracks, 0, true)} />
                </>
              )}
            </div>
          )}
        </div>
      )}
      {result.count === 0 ? (
        <p className="text-[13px] text-soft" style={{ paddingInline: inset }}>No matches</p>
      ) : (
        <ElementContent result={result} look={look} accent={accent} />
      )}
    </section>
  );
}

/** A page: its elements top to bottom, Add Element and Edit Page in the toolbar; an empty page invites one. */
export function PageView({ page, accent, onAdd, onEdit, onChange }: {
  page: PageNode; accent: string; onAdd: () => void; onEdit: (element: Element) => void; onChange: (elements: Element[]) => void;
}) {
  const { library } = useDemo();
  const [editing, setEditing] = useState(false);
  const [pendingDelete, setPendingDelete] = useState<Element>();
  const results = useMemo(() => page.elements.map((e) => evaluate(e.filter, library, e.id, e.appearance.sortOverride)), [page.elements, library]);
  return (
    <div className="relative">
      <PageHeader title={page.name}>
        <ToolbarButton icon="plus" label="Add Element" onClick={onAdd} />
        <ToolbarButton icon="square.and.pencil" label={editing ? 'Done Editing' : 'Edit Page'} onClick={() => setEditing((e) => !e)}
                       active={editing} disabled={page.elements.length === 0} />
      </PageHeader>
      {page.elements.length === 0 ? (
        <div className="grid place-items-center px-6 py-24 text-center">
          <Icon name={page.symbol} className="size-11 text-faint" />
          <p className="mt-3 text-[17px] font-semibold">This Page Is Empty</p>
          <p className="mt-1 text-[13px] text-soft">Add elements, each with its own smart filter and layout.</p>
          <button onClick={onAdd} className="mt-4 cursor-pointer rounded-full bg-accent px-4 py-1.5 text-[13px] font-medium text-accent-ink">Add Element</button>
        </div>
      ) : (
        <div className="flex flex-col gap-6 py-6">
          {page.elements.map((element, i) => (
            <ElementView key={element.id} element={element} pageID={page.id} result={results[i]} editing={editing} index={i}
                         count={page.elements.length} accent={accent} actions={{
                           edit: () => onEdit(element),
                           move: (by) => {
                             const next = [...page.elements];
                             next.splice(i + by, 0, ...next.splice(i, 1));
                             onChange(next);
                           },
                           duplicate: () => {
                             const copy = JSON.parse(JSON.stringify(element)) as Element;
                             copy.id = `${element.id}-copy-${Date.now()}`;
                             onChange([...page.elements.slice(0, i + 1), copy, ...page.elements.slice(i + 1)]);
                           },
                           remove: () => setPendingDelete(element),
                         }} />
          ))}
        </div>
      )}
      {pendingDelete && (
        <Confirm title={`Delete “${pendingDelete.filter.name}”?`} message="Its smart filter is deleted with it." action="Delete"
                 onConfirm={() => { onChange(page.elements.filter((e) => e.id !== pendingDelete.id)); setPendingDelete(undefined); }}
                 onCancel={() => setPendingDelete(undefined)} />
      )}
    </div>
  );
}

/** A confirmation, as macOS shows one: title, message, Cancel and a destructive action. */
export function Confirm({ title, message, action, onConfirm, onCancel }: { title: string; message: string; action: string; onConfirm: () => void; onCancel: () => void }) {
  return (
    <div className="fixed inset-0 z-[90] grid place-items-center bg-black/25" onClick={onCancel}>
      <div className="w-64 rounded-xl border border-line bg-raised p-4 text-center shadow-2xl" onClick={(e) => e.stopPropagation()} role="alertdialog">
        <p className="text-[13px] font-semibold">{title}</p>
        <p className="mt-1 text-[11px] text-soft">{message}</p>
        <div className="mt-4 flex flex-col gap-1.5">
          <button onClick={onConfirm} className="cursor-pointer rounded-md bg-red-500 py-1 text-[13px] font-medium text-white">{action}</button>
          <button onClick={onCancel} className="cursor-pointer rounded-md bg-ink/[0.08] py-1 text-[13px]">Cancel</button>
        </div>
      </div>
    </div>
  );
}

/** An album grid page: a genre's albums, an element's See All, Library ▸ Albums' grid. */
export function AlbumGrid({ albums }: { albums: DemoAlbum[] }) {
  const { compact } = useDemo();
  return (
    <div className="grid gap-x-[22px] gap-y-[26px]" style={{ padding: compact ? 16 : 24, gridTemplateColumns: `repeat(auto-fill, minmax(${compact ? 140 : 160}px, 1fr))` }}>
      {albums.map((a) => <AlbumTile key={a.id} album={a} />)}
    </div>
  );
}

export function GenreGrid({ genres }: { genres: Genre[] }) {
  const { compact } = useDemo();
  return (
    <div className="grid gap-5" style={{ padding: compact ? 16 : 24, gridTemplateColumns: `repeat(auto-fill, minmax(${compact ? 140 : 170}px, 1fr))` }}>
      {genres.map((g) => <GenreTile key={g.id} genre={g} />)}
    </div>
  );
}

const songsSummary = (tracks: Track[]) => {
  const seconds = tracks.reduce((s, t) => s + t.song.duration, 0);
  const hours = Math.floor(seconds / 3600), minutes = Math.round((seconds % 3600) / 60);
  return `${counted(tracks.length, 'song')} · ${hours ? `${hours} hour${hours === 1 ? '' : 's'}, ` : ''}${minutes} minutes`;
};

/** A songs element's See All: a sortable table. */
function SongsTable({ tracks, accent }: { tracks: Track[]; accent: string }) {
  const { player } = useDemo();
  const [sort, setSort] = useState<{ column: string; ascending: boolean } | null>(null);
  const columns = [
    { key: 'title', title: 'Title', className: 'flex-[2]', value: (t: Track) => t.song.title },
    { key: 'artist', title: 'Artist', className: 'flex-[1.3]', value: (t: Track) => t.album.artist },
    { key: 'album', title: 'Album', className: 'flex-[1.3]', value: (t: Track) => t.album.title },
    { key: 'time', title: 'Time', className: 'w-12 text-right', value: (t: Track) => t.song.duration },
    { key: 'plays', title: 'Plays', className: 'w-12 text-right', value: (t: Track) => t.song.plays },
  ];
  const rows = useMemo(() => {
    if (!sort) return tracks;
    const column = columns.find((c) => c.key === sort.column)!;
    return [...tracks].sort((a, b) => {
      const x = column.value(a), y = column.value(b);
      return (typeof x === 'string' ? x.localeCompare(y as string) : (x as number) - (y as number)) * (sort.ascending ? 1 : -1);
    });
  }, [tracks, sort]);
  return (
    <div className="px-5 pb-6 text-[13px]">
      <div className="sticky top-[52px] z-10 flex gap-3 border-b border-line bg-raised py-1.5 text-[11px] font-semibold text-soft">
        {columns.map((c) => (
          <button key={c.key} className={`${c.className} cursor-pointer truncate text-left hover:text-ink`}
                  onClick={() => setSort((s) => ({ column: c.key, ascending: s?.column === c.key ? !s.ascending : true }))}>
            {c.title}{sort?.column === c.key ? (sort.ascending ? ' ▴' : ' ▾') : ''}
          </button>
        ))}
      </div>
      {rows.map((t, i) => {
        const isCurrent = player.current?.key === t.key;
        return (
          <div key={t.key} onDoubleClick={() => player.play(rows, i)} className="flex cursor-default gap-3 py-1 select-none odd:bg-ink/[0.03]"
               style={{ color: isCurrent ? accent : undefined }}>
            <span className={`${columns[0].className} truncate`}>{t.song.title}</span>
            <span className={`${columns[1].className} truncate text-soft`}>{t.album.artist}</span>
            <span className={`${columns[2].className} truncate text-soft`}>{t.album.title}</span>
            <span className={`${columns[3].className} tabular-nums text-soft`}>{formatTime(t.song.duration)}</span>
            <span className={`${columns[4].className} tabular-nums text-soft`}>{t.song.plays}</span>
          </div>
        );
      })}
    </div>
  );
}

/** An element's full result, opened from its header. */
export function ElementDetail({ element, accent, back, onEdit }: { element: Element; accent: string; back: () => void; onEdit: () => void }) {
  const { library, player } = useDemo();
  const result = useMemo(() => evaluate(element.filter, library, element.id, element.appearance.sortOverride), [element, library]);
  const subtitle = result.kind === 'songs' ? songsSummary(result.tracks) : counted(result.count, result.kind.slice(0, -1));
  return (
    <div>
      <PageHeader title={element.filter.name} subtitle={subtitle} back={back}>
        <ToolbarButton icon="play.fill" label="Play" onClick={() => player.play(result.tracks)} />
        <ToolbarButton icon="shuffle" label="Shuffle" onClick={() => player.play(result.tracks, 0, true)} />
        <ToolbarButton icon="slider.horizontal.3" label="Edit Element" onClick={onEdit} />
      </PageHeader>
      {result.kind === 'songs' ? <SongsTable tracks={result.tracks} accent={accent} />
        : result.kind === 'albums' ? <AlbumGrid albums={result.albums} />
        : result.kind === 'genres' ? <GenreGrid genres={result.genres} />
        : <ArtistGrid artists={result.artists} />}
    </div>
  );
}

function ArtistGrid({ artists }: { artists: ReturnType<typeof useDemo>['library']['artists'] }) {
  const { compact } = useDemo();
  return (
    <div className="grid gap-5" style={{ padding: compact ? 16 : 24, gridTemplateColumns: `repeat(auto-fill, minmax(${compact ? 120 : 150}px, 1fr))` }}>
      {artists.map((a) => <ArtistTile key={a.id} artist={a} />)}
    </div>
  );
}

/** An album page: on the cover's colours, the cover beside its title, artist, details, Play and Shuffle; the tracks
 *  below. Clicking a track plays the album from it. */
export function AlbumPage({ album, back }: { album: DemoAlbum; back: () => void }) {
  const { library, player, compact } = useDemo();
  const p = album.palette;
  const dark = isDark(p);
  const tracks = library.tracks.filter((t) => t.album.id === album.id);
  const minutes = Math.round(album.songs.reduce((s, x) => s + x.duration, 0) / 60);
  return (
    <div className="relative min-h-full" style={{ backgroundColor: p.background, color: p.primary, colorScheme: dark ? 'dark' : 'light' }}>
      {/* The cover's colour, a vivid blur of the cover fading in from the top, and a wash of the colour over both. */}
      <div className="pointer-events-none absolute inset-x-0 top-0 h-[520px] overflow-hidden [mask-image:linear-gradient(black,rgb(0_0_0/0.6),transparent)]" aria-hidden="true">
        <img src={album.coverLarge} alt="" className="size-full scale-125 object-cover blur-[60px] saturate-150" />
      </div>
      <div className="pointer-events-none absolute inset-0" style={{ backgroundColor: p.background, opacity: 0.55 }} aria-hidden="true" />
      {/* Padding rather than margin, so the page's colour runs down under the now-playing bar and, on a phone, up
          behind the status bar (a margin passed through and left that strip uncovered). */}
      <div className="relative" style={{ paddingTop: compact ? 50 : 0, paddingBottom: 'calc(40px + var(--bar-space, 0px))' }}>
        <div className="flex h-[52px] items-center px-4">
          <button onClick={back} className="grid size-7 cursor-pointer place-items-center rounded-md hover:bg-black/10" aria-label="Back" style={{ color: p.primary }}>
            <Icon name="chevron.left" className="size-4" strokeWidth={2} />
          </button>
        </div>
        <div className={`flex gap-7 ${compact ? 'flex-col items-center px-4 text-center' : 'items-end px-14'}`}>
          <div className={`${compact ? 'w-[70%]' : 'w-[200px]'} shrink-0 overflow-hidden rounded-xl shadow-[0_16px_40px_rgb(0_0_0/0.35)]`}>
            <img src={album.coverLarge} alt="" className="aspect-square w-full object-cover" />
          </div>
          <div className="min-w-0 pb-1">
            <h2 className="text-[26px] font-bold leading-tight">{album.title}</h2>
            <p className="mt-0.5 text-[17px]" style={{ color: p.secondary }}>{album.artist}</p>
            <p className="mt-1.5 text-[12px]" style={{ color: p.secondary }}>{album.genre} · {album.year} · {counted(album.songs.length, 'song')} · {minutes} mins</p>
            <div className={`mt-4 flex gap-2.5 ${compact ? 'justify-center' : ''}`}>
              <button onClick={() => player.play(tracks)} className="flex cursor-pointer items-center gap-1.5 rounded-lg px-5 py-1.5 text-[13px] font-medium"
                      style={{ backgroundColor: p.primary, color: p.background }}>
                <Icon name="play.fill" className="size-3.5" /> Play
              </button>
              <button onClick={() => player.play(tracks, 0, true)} className="flex cursor-pointer items-center gap-1.5 rounded-lg bg-white/15 px-5 py-1.5 text-[13px] font-medium">
                <Icon name="shuffle" className="size-3.5" /> Shuffle
              </button>
            </div>
          </div>
        </div>
        <div className={`mt-7 overflow-hidden rounded-2xl ${compact ? 'mx-3' : 'mx-14'}`}
             style={{ backgroundColor: dark ? 'rgb(0 0 0 / 0.18)' : 'rgb(255 255 255 / 0.35)' }}>
          {tracks.map((t, i) => {
            const isCurrent = player.current?.key === t.key;
            return (
              <button key={t.key} onClick={() => (isCurrent ? player.togglePlayPause() : player.play(tracks, i))}
                      className="flex w-full cursor-pointer items-center gap-4 border-b border-current/10 px-5 py-2.5 text-left text-[14px] last:border-0 hover:bg-black/5">
                <span className="w-5 text-right text-[13px] tabular-nums" style={{ color: p.secondary }}>
                  {isCurrent ? <PlayingIndicator animating={player.isPlaying} color={p.secondary} /> : t.song.track}
                </span>
                <span className="min-w-0 flex-1 truncate">{t.song.title}</span>
                <span className="text-[13px] tabular-nums" style={{ color: p.secondary }}>{formatTime(t.song.duration)}</span>
              </button>
            );
          })}
        </div>
      </div>
    </div>
  );
}

/** Library ▸ Albums: an artist list beside the grid (a menu on a phone); picking an artist narrows the grid. */
export function LibraryAlbums() {
  const { library, compact } = useDemo();
  const [artist, setArtist] = useState<string>();
  const albums = artist ? library.albums.filter((a) => a.artist === artist) : library.albums;
  return (
    <div>
      <PageHeader title={artist ?? 'Albums'} subtitle={counted(albums.length, 'album')}>
        {compact && (
          <select value={artist ?? ''} onChange={(e) => setArtist(e.target.value || undefined)} aria-label="Artist"
                  className="rounded-md border border-line bg-raised px-1.5 py-1 text-[12px]">
            <option value="">All Artists</option>
            {library.artists.map((a) => <option key={a.id} value={a.id}>{a.name}</option>)}
          </select>
        )}
      </PageHeader>
      <div className="flex">
        {!compact && (
          <div className="sticky top-[52px] h-[calc(100vh)] max-h-[600px] w-[210px] shrink-0 overflow-y-auto border-r border-line p-2 text-[13px]">
            <button onClick={() => setArtist(undefined)} className={`flex w-full cursor-pointer justify-between rounded-md px-2 py-1 ${!artist ? 'bg-ink/[0.1]' : 'hover:bg-ink/[0.05]'}`}>
              All Artists <span className="text-soft">{library.albums.length}</span>
            </button>
            <p className="mt-3 mb-1 px-2 text-[11px] font-semibold text-soft">Artists</p>
            {library.artists.map((a) => (
              <button key={a.id} onClick={() => setArtist(a.id)}
                      className={`flex w-full cursor-pointer justify-between rounded-md px-2 py-1 text-left ${artist === a.id ? 'bg-ink/[0.1]' : 'hover:bg-ink/[0.05]'}`}>
                <span className="truncate">{a.name}</span> <span className="text-soft">{a.albums.length}</span>
              </button>
            ))}
          </div>
        )}
        <div className="min-w-0 flex-1"><AlbumGrid albums={albums} /></div>
      </div>
    </div>
  );
}

/** Library ▸ Songs: songs under their albums, the cover on the left, in artist → year → title order, under pinned
 *  artist headers. Each row: track number, title, genre, plays and time. */
export function LibrarySongs({ accent }: { accent: string }) {
  const { library, player, compact } = useDemo();
  return (
    <div>
      <PageHeader title="Songs" subtitle={songsSummary(library.tracks)} />
      <div className="pb-6">
        {library.artists.map((artist) => (
          <section key={artist.id}>
            <div className="sticky top-[52px] z-10 border-b border-line bg-raised/95 px-5 py-1.5 text-[15px] font-bold backdrop-blur">{artist.name}</div>
            {[...artist.albums].reverse().map((album) => {
              const tracks = library.tracks.filter((t) => t.album.id === album.id);
              return (
                <div key={album.id} className="flex gap-4 border-b border-line px-5 py-3">
                  {!compact && (
                    <div className="w-[130px] shrink-0">
                      <Artwork album={album} radius={6} />
                      <div className="mt-1.5 truncate text-[12px] font-medium">{album.title}</div>
                      <div className="text-[11px] text-soft">{album.year}</div>
                    </div>
                  )}
                  <div className="min-w-0 flex-1 text-[13px]">
                    {compact && <div className="mb-1 text-[13px] font-semibold">{album.title} <span className="font-normal text-soft">· {album.year}</span></div>}
                    {tracks.map((t, i) => {
                      const isCurrent = player.current?.key === t.key;
                      return (
                        <div key={t.key} onDoubleClick={() => player.play(tracks, i)} onClick={() => compact && player.play(tracks, i)}
                             className="flex cursor-default items-center gap-3 rounded px-1.5 py-[3px] select-none hover:bg-ink/[0.04]"
                             style={isCurrent ? { backgroundColor: `color-mix(in srgb, ${accent} 16%, transparent)` } : undefined}>
                          <span className="w-5 text-right text-[11px] tabular-nums text-soft">
                            {isCurrent ? <PlayingIndicator animating={player.isPlaying} color={accent} /> : t.song.track}
                          </span>
                          <span className="min-w-0 flex-1 truncate">{t.song.title}</span>
                          {!compact && <span className="w-24 truncate text-soft">{album.genre}</span>}
                          {!compact && <span className="w-10 text-right tabular-nums text-soft">{t.song.plays}</span>}
                          <span className="w-10 text-right tabular-nums text-soft">{formatTime(t.song.duration)}</span>
                        </div>
                      );
                    })}
                  </div>
                </div>
              );
            })}
          </section>
        ))}
      </div>
    </div>
  );
}

export function LibraryArtists() {
  const { library } = useDemo();
  return (
    <div>
      <PageHeader title="Artists" subtitle={counted(library.artists.length, 'artist')} />
      <ArtistGrid artists={library.artists} />
    </div>
  );
}

export function LibraryGenres() {
  const { library } = useDemo();
  return (
    <div>
      <PageHeader title="Genres" subtitle={counted(library.genres.length, 'genre')} />
      <GenreGrid genres={library.genres} />
    </div>
  );
}

export function GenrePage({ genre, back }: { genre: Genre; back: () => void }) {
  return (
    <div>
      <PageHeader title={genre.name} subtitle={counted(genre.albums.length, 'album')} back={back} />
      <AlbumGrid albums={genre.albums} />
    </div>
  );
}
