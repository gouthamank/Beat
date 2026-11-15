// The interactive demo: a small working Beat on the made-up showcase library, as a Mac window or an iPhone, built
// after the app's own views (see each file). Each sidebar item keeps its own stack of pages (album, genre, See All),
// as Beat's navigator does. Nothing plays until someone clicks.
import { AnimatePresence, motion } from 'motion/react';
import { useEffect, useMemo, useRef, useState, type ReactNode } from 'react';
import { Demo as DemoContextProvider, type DemoContext } from './context';
import { Editor } from './Editor';
import { Icon } from './Icon';
import {
  catalogNumber, findNode, homeElements, insertNode, isDark, makeLibrary, newElement, newID, startingTree, updateNode, duplicate,
  type CustomField, type DemoAlbum, type Element, type Node, type PageNode,
} from './model';
import { NowPlayingBar, NowPlayingView, playbackAccent } from './NowPlaying';
import { AlbumPage, Confirm, ElementDetail, GenrePage, LibraryAlbums, LibraryArtists, LibraryGenres, LibrarySongs, PageView } from './Pages';
import { usePlayer, type Borrowable } from './player';
import { NameSheet, Sidebar, type Selection, type SidebarAction } from './Sidebar';

type Route = { kind: 'album'; id: string } | { kind: 'genre'; id: string } | { kind: 'element'; pageID: string; elementID: string };
type Mode = 'mac' | 'phone';

const selectionKey = (s: Selection) => (s.kind === 'page' ? `page:${s.id}` : `library:${s.page}`);

function useDarkScheme() {
  const [dark, setDark] = useState(false);
  useEffect(() => {
    const query = matchMedia('(prefers-color-scheme: dark)');
    const update = () => setDark(query.matches);
    update();
    query.addEventListener('change', update);
    return () => query.removeEventListener('change', update);
  }, []);
  return dark;
}

/** iPhone's status bar: the time, signal, Wi-Fi and battery. */
function StatusBar({ color }: { color: string }) {
  return (
    <div className="pointer-events-none absolute inset-x-0 top-0 z-[60] flex h-[50px] items-center justify-between px-8 pt-1 text-[15px] font-semibold" style={{ color }} aria-hidden="true">
      <span className="w-14 text-center">9:41</span>
      <span className="flex items-center gap-1.5">
        <svg viewBox="0 0 18 12" className="h-3 w-[18px]" fill="currentColor"><rect x="0" y="8" width="3" height="4" rx="1" /><rect x="5" y="5.5" width="3" height="6.5" rx="1" /><rect x="10" y="3" width="3" height="9" rx="1" /><rect x="15" y="0" width="3" height="12" rx="1" /></svg>
        <svg viewBox="0 0 16 12" className="h-3 w-4" fill="currentColor"><path d="M8 2.3c2.4 0 4.6.9 6.2 2.5l1.2-1.2A10.4 10.4 0 0 0 8 .6 10.4 10.4 0 0 0 .6 3.6l1.2 1.2A8.7 8.7 0 0 1 8 2.3zm0 3.5c1.4 0 2.8.6 3.8 1.6l1.2-1.2A7 7 0 0 0 8 4.1a7 7 0 0 0-5 2.1l1.2 1.2c1-1 2.4-1.6 3.8-1.6zm0 3.5c.5 0 1 .2 1.3.5L8 11.2 6.7 9.8c.3-.3.8-.5 1.3-.5z" /></svg>
        <svg viewBox="0 0 27 13" className="h-[13px] w-[27px]"><rect x="0.5" y="0.5" width="23" height="12" rx="3.5" fill="none" stroke="currentColor" opacity="0.4" /><rect x="2" y="2" width="20" height="9" rx="2" fill="currentColor" /><path d="M25 4.5v4c.8-.3 1.3-1.1 1.3-2s-.5-1.7-1.3-2z" fill="currentColor" opacity="0.5" /></svg>
      </span>
    </div>
  );
}

/** An iPhone 17 Pro, roughly: a titanium band with its buttons, the screen's black border, the Dynamic Island. */
function PhoneFrame({ children, statusColor }: { children: ReactNode; statusColor: string }) {
  const metal = 'linear-gradient(145deg, #dcdce0 0%, #8b8b91 22%, #45454b 50%, #9c9ca2 78%, #e2e2e6 100%)';
  const button = 'absolute w-[4px] rounded-sm';
  return (
    <div className="relative mx-auto w-full max-w-[380px]" style={{ aspectRatio: '380 / 790' }}>
      <span className={`${button} -left-[3px] top-[15%] h-[4%]`} style={{ background: metal }} />
      <span className={`${button} -left-[3px] top-[21.5%] h-[7%]`} style={{ background: metal }} />
      <span className={`${button} -left-[3px] top-[30%] h-[7%]`} style={{ background: metal }} />
      <span className={`${button} -right-[3px] top-[24%] h-[11%]`} style={{ background: metal }} />
      <div className="absolute inset-0 rounded-[60px] p-[3px] shadow-[0_40px_90px_rgb(0_0_0/0.35)]" style={{ background: metal }}>
        <div className="size-full rounded-[57px] bg-black p-[9px]">
          <div className="relative size-full overflow-hidden rounded-[48px] bg-raised text-ink">
            <div className="absolute top-[11px] left-1/2 z-[70] h-[33px] w-[112px] -translate-x-1/2 rounded-full bg-black" aria-hidden="true" />
            <StatusBar color={statusColor} />
            {children}
            <div className="pointer-events-none absolute bottom-[7px] left-1/2 z-[70] h-[5px] w-[132px] -translate-x-1/2 rounded-full opacity-60"
                 style={{ backgroundColor: statusColor }} aria-hidden="true" />
          </div>
        </div>
      </div>
    </div>
  );
}

interface ZoomRect { x: number; y: number; width: number; height: number }

/** An album page on the phone, as iOS's zoom transition: it grows out of the cover that was tapped (scaled to the
 *  cover's width, clipped to the square at its top) and shrinks back into it on Back. Opened from elsewhere, it
 *  slides in from the right. */
function AlbumZoom({ from, size, children }: { from?: ZoomRect; size?: { width: number; height: number }; children: ReactNode }) {
  const spring = { type: 'spring', stiffness: 260, damping: 32 } as const;
  const open = { x: 0, y: 0, scale: 1, clipPath: 'inset(0px 0px 0px 0px round 48px)', opacity: 1 };
  const closed = (() => {
    if (!from || !size) return { x: '100%', opacity: 1 };
    const scale = from.width / size.width;
    return { x: from.x, y: from.y, scale, clipPath: `inset(0px 0px ${size.height - size.width}px 0px round ${10 / scale}px)`, opacity: 1 };
  })();
  return (
    <motion.div className="absolute inset-0 z-20 origin-top-left bg-raised" initial={closed} animate={open} exit={closed} transition={spring}>
      {children}
    </motion.div>
  );
}

export default function Demo({ albums, pool }: { albums: DemoAlbum[]; pool: Borrowable[] }) {
  const library = useMemo(() => makeLibrary(albums), [albums]);
  const player = usePlayer(pool);
  const dark = useDarkScheme();
  const systemAccent = dark ? '#0A84FF' : '#007AFF';
  const [tree, setTree] = useState<Node[]>(startingTree);
  const [customFields, setCustomFields] = useState<CustomField[]>([catalogNumber]);
  const [expanded, setExpanded] = useState(new Set(['moods']));
  const [selection, setSelection] = useState<Selection>({ kind: 'page', id: 'home' });
  const [stacks, setStacks] = useState<Record<string, Route[]>>({});
  const [editor, setEditor] = useState<{ element: Element; pageID: string; isNew: boolean }>();
  const [naming, setNaming] = useState<{ id: string; isNew: boolean; previous: Selection }>();
  const [deleting, setDeleting] = useState<Node>();
  const [nowPlaying, setNowPlaying] = useState(false);
  const [visualizerFirst, setVisualizerFirst] = useState(false);
  /** Bumped by the tour, so Now Playing opens afresh even when it's already open. */
  const [nowPlayingRun, setNowPlayingRun] = useState(0);
  const [barRect, setBarRect] = useState<DOMRect>();
  const barRef = useRef<HTMLDivElement>(null);
  const [mode, setMode] = useState<Mode>('mac');
  const [narrow, setNarrow] = useState(false);
  const [drawer, setDrawer] = useState(false);

  // A phone or narrow window has no room for the Mac window: it gets the iPhone and no switch.
  useEffect(() => {
    const query = matchMedia('(max-width: 820px)');
    const update = () => setNarrow(query.matches);
    update();
    query.addEventListener('change', update);
    return () => query.removeEventListener('change', update);
  }, []);
  // Next past the last song stops: Now Playing closes with it.
  useEffect(() => { if (!player.current) setNowPlaying(false); }, [player.current]);

  const shown: Mode = narrow ? 'phone' : mode;
  const compact = shown === 'phone';
  const accent = playbackAccent(player, dark, systemAccent);
  const key = selectionKey(selection);
  const stack = stacks[key] ?? [];
  const route = stack[stack.length - 1];
  const routeAlbum = route?.kind === 'album' ? library.albums.find((a) => a.id === route.id) : undefined;
  const tintAlbum = compact ? undefined : routeAlbum;
  const phoneAlbum = compact ? routeAlbum : undefined;
  /** The phone's screen, and the covers its album pages zoomed out of (in the screen's coordinates), by album. */
  const screenRef = useRef<HTMLDivElement>(null);
  const [zoomFrom, setZoomFrom] = useState<Record<string, ZoomRect>>({});

  /** A route already in the trail is returned to; otherwise it's pushed. */
  const push = (r: Route) => setStacks((all) => {
    const trail = all[key] ?? [];
    const at = trail.findIndex((x) => JSON.stringify(x) === JSON.stringify(r));
    return { ...all, [key]: at >= 0 ? trail.slice(0, at + 1) : [...trail, r] };
  });
  const back = () => setStacks((all) => ({ ...all, [key]: (all[key] ?? []).slice(0, -1) }));

  const context: DemoContext = {
    library, player, compact, preview: false, customFields,
    saveCustomField: (f) => setCustomFields((all) => [...all.filter((x) => x.id !== f.id), f]),
    openAlbum: (album, from) => {
      const screen = screenRef.current?.getBoundingClientRect(), cover = from?.getBoundingClientRect();
      setZoomFrom((all) => {
        const { [album.id]: _, ...rest } = all;
        return screen && cover ? { ...rest, [album.id]: { x: cover.left - screen.left, y: cover.top - screen.top, width: cover.width, height: cover.height } } : rest;
      });
      push({ kind: 'album', id: album.id });
    },
    openGenre: (genre) => push({ kind: 'genre', id: genre.id }),
    openElement: (pageID, elementID) => push({ kind: 'element', pageID, elementID }),
  };

  const changePage = (pageID: string, change: (p: PageNode) => PageNode) =>
    setTree((t) => updateNode(t, pageID, (n) => (n.kind === 'page' ? change(n) : n)));

  const select = (s: Selection) => {
    // Clicking the selected item again goes back to its top.
    if (selectionKey(s) === key) setStacks((all) => ({ ...all, [key]: [] }));
    setSelection(s);
    setDrawer(false);
  };

  const onSidebar = (a: SidebarAction) => {
    if (a.kind === 'new') {
      const id = newID();
      const node: Node = a.folder ? { kind: 'folder', id, name: 'Untitled Folder', symbol: 'folder', children: [] }
        : { kind: 'page', id, name: 'Untitled Page', symbol: 'rectangle.grid.1x2', elements: [] };
      setTree((t) => insertNode(t, node, { inside: a.inside, below: a.below }));
      if (a.inside) setExpanded((e) => new Set([...e, a.inside!]));
      const previous = selection;
      if (!a.folder) setSelection({ kind: 'page', id });
      setNaming({ id, isNew: true, previous });
    } else if (a.kind === 'rename') {
      setNaming({ id: a.id, isNew: false, previous: selection });
    } else if (a.kind === 'duplicate') {
      const node = findNode(tree, a.id);
      if (node) setTree((t) => insertNode(t, { ...duplicate(node), name: `${node.name} Copy` }, { below: a.id }));
    } else if (a.kind === 'delete') {
      setDeleting(findNode(tree, a.id));
    } else {
      const home: PageNode = { kind: 'page', id: newID(), name: 'Home', symbol: 'house', elements: homeElements() };
      setTree((t) => [home, ...t]);
      setSelection({ kind: 'page', id: home.id });
    }
  };

  const namingNode = naming && findNode(tree, naming.id);
  const cancelNaming = () => {
    // A new item that isn't named isn't kept.
    if (naming?.isNew) {
      setTree((t) => updateNode(t, naming.id, () => undefined));
      setSelection(naming.previous);
    }
    setNaming(undefined);
  };

  const contentFor = (route: Route | undefined) => {
    if (route?.kind === 'album') {
      const album = library.albums.find((a) => a.id === route.id);
      return album && <AlbumPage album={album} back={back} />;
    }
    if (route?.kind === 'genre') {
      const genre = library.genres.find((g) => g.id === route.id);
      return genre && <GenrePage genre={genre} back={back} />;
    }
    if (route?.kind === 'element') {
      const page = findNode(tree, route.pageID);
      const element = page?.kind === 'page' ? page.elements.find((e) => e.id === route.elementID) : undefined;
      return element && <ElementDetail element={element} accent={accent} back={back} onEdit={() => setEditor({ element, pageID: route.pageID, isNew: false })} />;
    }
    if (selection.kind === 'library') {
      return { albums: <LibraryAlbums />, artists: <LibraryArtists />, songs: <LibrarySongs accent={accent} />, genres: <LibraryGenres /> }[selection.page];
    }
    const page = findNode(tree, selection.id);
    if (page?.kind !== 'page') return null;
    return (
      <PageView page={page} accent={accent}
                onAdd={() => setEditor({ element: newElement(), pageID: page.id, isNew: true })}
                onEdit={(element) => setEditor({ element, pageID: page.id, isNew: false })}
                onChange={(elements) => changePage(page.id, (p) => ({ ...p, elements }))} />
    );
  };
  const pageContent = contentFor(route);
  // On the phone an album page zooms out of its cover over the page it came from, which stays underneath.
  const phoneUnder = phoneAlbum ? stack[stack.length - 2] : route;

  const sidebar = (
    <Sidebar tree={tree} selection={selection} expanded={expanded} onSelect={select} onAction={onSidebar}
             onToggle={(id) => setExpanded((e) => { const n = new Set(e); n.has(id) ? n.delete(id) : n.add(id); return n; })} />
  );

  const editorView = editor && (
    <Editor element={editor.element} isNew={editor.isNew} accent={accent} onClose={() => setEditor(undefined)}
            onSave={(element) => {
              changePage(editor.pageID, (p) => ({
                ...p, elements: editor.isNew ? [...p.elements, element] : p.elements.map((e) => (e.id === element.id ? element : e)),
              }));
              setEditor(undefined);
            }}
            onDelete={() => {
              changePage(editor.pageID, (p) => ({ ...p, elements: p.elements.filter((e) => e.id !== editor.element.id) }));
              setStacks((all) => ({ ...all, [key]: (all[key] ?? []).filter((r) => !(r.kind === 'element' && r.elementID === editor.element.id)) }));
              setEditor(undefined);
            }} />
  );

  const overlays = (
    <>
      <AnimatePresence>
        {nowPlaying && player.current && (
          <NowPlayingView key={`np${nowPlayingRun}`} from={barRect} accent={accent} startVisualizing={visualizerFirst} onClose={() => setNowPlaying(false)}
                          onOpenAlbum={() => { setNowPlaying(false); push({ kind: 'album', id: player.current!.album.id }); }} />
        )}
      </AnimatePresence>
      {namingNode && (
        <NameSheet title={naming!.isNew ? (namingNode.kind === 'folder' ? 'New Folder' : 'New Page') : (namingNode.kind === 'folder' ? 'Folder Name' : 'Page Name')}
                   symbol={namingNode.symbol} name={namingNode.name} saveTitle={naming!.isNew ? 'Create' : 'Rename'} onCancel={cancelNaming}
                   onSave={(name) => {
                     setTree((t) => updateNode(t, naming!.id, (n) => ({ ...n, name })));
                     if (naming!.isNew && namingNode.kind === 'page') setDrawer(false);
                     setNaming(undefined);
                   }} />
      )}
      {deleting && (
        <Confirm title={`Delete “${deleting.name}”?`} action="Delete"
                 message={deleting.kind === 'page' ? 'Its elements and their smart filters are deleted with it.'
                   : deleting.children.length === 0 ? 'The folder is empty.' : `The folder and everything inside it are deleted.`}
                 onConfirm={() => {
                   setTree((t) => updateNode(t, deleting.id, () => undefined));
                   if (selection.kind === 'page' && (selection.id === deleting.id || (deleting.kind === 'folder' && findNode(deleting.children, selection.id)))) {
                     setSelection({ kind: 'library', page: 'albums' });
                   }
                   setDeleting(undefined);
                 }} onCancel={() => setDeleting(undefined)} />
      )}
    </>
  );

  const openNowPlaying = () => {
    setBarRect(barRef.current?.getBoundingClientRect());
    setVisualizerFirst(false);
    setNowPlaying(true);
  };

  /** The tour's chips: each runs the real thing in the window, from Home. (Not part of Beat: the website's.) */
  const tour = (() => {
    const album = (title: string) => library.albums.find((a) => a.title === title)!;
    const toHome = () => {
      setEditor(undefined);
      setNowPlaying(false);
      setDrawer(false);
      setSelection({ kind: 'page', id: 'home' });
      setStacks((all) => ({ ...all, 'page:home': [] }));
    };
    const playAlbum = (title: string, songTitle: string, visualizer: boolean) => {
      const tracks = library.tracks.filter((t) => t.album.id === album(title).id);
      toHome();
      player.play(tracks, Math.max(0, tracks.findIndex((t) => t.song.title === songTitle)));
      setBarRect(undefined);
      setVisualizerFirst(visualizer);
      setNowPlayingRun((n) => n + 1);
      setNowPlaying(true);
    };
    return [
      { title: 'Open an album', icon: 'square.stack', run: () => {
        toHome();
        setZoomFrom({});
        setStacks((all) => ({ ...all, 'page:home': [{ kind: 'album', id: album('Night Transit').id }] }));
      } },
      // A new page at the end of the sidebar: named, then empty, inviting its first element.
      { title: 'Make a page', icon: 'plus', run: () => { toHome(); onSidebar({ kind: 'new', folder: false }); } },
      { title: 'Edit a smart filter', icon: 'slider.horizontal.3', run: () => {
        toHome();
        const home = findNode(tree, 'home');
        const element = home?.kind === 'page' ? home.elements.find((e) => e.filter.name === 'Recently Played') ?? home.elements[0] : undefined;
        if (element) setEditor({ element, pageID: 'home', isNew: false });
      } },
      // The Nightline Records page, its element's editor open on a sort by the Catalog No. custom field. A deleted page
      // comes back first.
      { id: 'custom-field', title: 'Sort by a custom field', icon: 'arrow.up.arrow.down', run: () => {
        toHome();
        let page = findNode(tree, 'label');
        if (page?.kind !== 'page' || !page.elements.length) {
          page = startingTree().find((n) => n.id === 'label')!;
          const restored = page;
          setTree((t) => [...t.filter((n) => n.id !== 'label'), restored]);
        }
        if (page.kind !== 'page') return;
        setSelection({ kind: 'page', id: 'label' });
        setStacks((all) => ({ ...all, 'page:label': [] }));
        setEditor({ element: page.elements[0], pageID: 'label', isNew: false });
      } },
      { id: 'lyrics', title: 'Play a song with lyrics', icon: 'quote.bubble', run: () => playAlbum('Glow Season', 'Glow Season', false) },
      { id: 'visualizer', title: 'Open the visualizer', icon: 'waveform', run: () => playAlbum('Night Transit', 'Night Transit', true) },
    ];
  })();
  // The page's sections can run a chip too ("Try it in the demo"): a `beat-demo` event naming the chip's id.
  const tourRef = useRef(tour);
  tourRef.current = tour;
  useEffect(() => {
    const run = (e: Event) => tourRef.current.find((c) => 'id' in c && c.id === (e as CustomEvent<string>).detail)?.run();
    window.addEventListener('beat-demo', run);
    return () => window.removeEventListener('beat-demo', run);
  }, []);

  return (
    <DemoContextProvider.Provider value={context}>
      <div className="demo" style={{ ['--site-accent' as string]: 'var(--accent)', ['--accent' as string]: systemAccent, ['--accent-ink' as string]: '#fff' }}>
        {!narrow && (
          <div className="mb-6 flex justify-center">
            <div className="flex rounded-full border border-line bg-raised p-1 text-sm" role="tablist" aria-label="Device">
              {(['mac', 'phone'] as const).map((m) => (
                <button key={m} role="tab" aria-selected={mode === m} onClick={() => { setMode(m); setEditor(undefined); setNowPlaying(false); }}
                        className={`cursor-pointer rounded-full px-4 py-1.5 font-medium ${mode === m ? 'bg-ink text-bg' : 'text-soft hover:text-ink'}`}>
                  {m === 'mac' ? 'Mac' : 'iPhone'}
                </button>
              ))}
            </div>
          </div>
        )}
        <div className="mb-6 flex flex-wrap justify-center gap-2" aria-label="Try">
          {tour.map((chip) => (
            <button key={chip.title} onClick={chip.run}
                    className="flex cursor-pointer items-center gap-1.5 rounded-full border border-line bg-raised px-3.5 py-1.5 text-[13px] font-medium shadow-sm transition-colors hover:border-[var(--site-accent)] hover:text-[var(--site-accent)]">
              <Icon name={chip.icon} className="size-4" /> {chip.title}
            </button>
          ))}
        </div>

        {shown === 'mac' ? (
          <div className="relative mx-auto grid h-[680px] max-w-[1100px] grid-cols-[220px_1fr] grid-rows-[minmax(0,1fr)] overflow-hidden rounded-xl border border-line bg-raised text-ink shadow-[0_30px_80px_rgb(0_0_0/0.25)]">
            {/* On album pages the sidebar takes the cover's colours, so the window reads as one surface. */}
            <aside className="relative flex min-h-0 flex-col border-r border-line bg-bg/70 pt-3 backdrop-blur transition-colors duration-500"
                   style={tintAlbum ? { backgroundColor: tintAlbum.palette.background, color: tintAlbum.palette.primary, colorScheme: isDark(tintAlbum.palette) ? 'dark' : 'light', ['--ink' as string]: tintAlbum.palette.primary, ['--ink-soft' as string]: tintAlbum.palette.secondary, ['--line' as string]: 'rgb(0 0 0 / 0.12)' } : undefined}>
              {tintAlbum && (
                <img src={tintAlbum.coverLarge} alt="" aria-hidden="true" className="pointer-events-none absolute inset-0 size-full scale-150 object-cover opacity-35 blur-[60px] saturate-150" />
              )}
              <div className="relative mb-4 flex gap-2 px-4" aria-hidden="true">
                <span className="size-3 rounded-full bg-[#ff5f57]" /><span className="size-3 rounded-full bg-[#febc2e]" /><span className="size-3 rounded-full bg-[#28c840]" />
              </div>
              <div className="relative min-h-0 flex-1">{sidebar}</div>
            </aside>
            <div className="relative min-w-0">
              {/* Room for the bar under each page; an album page's colour runs down behind it. */}
              <div className="h-full overflow-y-auto" style={{ ['--bar-space' as string]: player.current ? '96px' : '0px' }}>
                <div className={route?.kind === 'album' ? 'h-full' : 'min-h-full'} style={{ paddingBottom: route?.kind === 'album' ? 0 : 'var(--bar-space)' }}>{pageContent}</div>
              </div>
              {player.current && (
                <div className="absolute inset-x-0 bottom-0 z-30 px-5 pb-3.5">
                  <NowPlayingBar accent={accent} onOpen={openNowPlaying} barRef={barRef} />
                </div>
              )}
            </div>
            <div className="pointer-events-none absolute inset-0 *:pointer-events-auto">{overlays}</div>
            {/* The window's buttons stay over Now Playing and the visualizer, as in Beat. */}
            {nowPlaying && player.current && (
              <div className="pointer-events-none absolute top-3 left-4 z-[80] flex gap-2" aria-hidden="true">
                <span className="size-3 rounded-full bg-[#ff5f57]" /><span className="size-3 rounded-full bg-[#febc2e]" /><span className="size-3 rounded-full bg-[#28c840]" />
              </div>
            )}
            <AnimatePresence>
              {editorView && (
                <motion.div key="editor" initial={{ opacity: 0 }} animate={{ opacity: 1 }} exit={{ opacity: 0 }} className="absolute inset-0 z-[75] bg-black/25 p-6">
                  <motion.div initial={{ y: -20, scale: 0.98 }} animate={{ y: 0, scale: 1 }} className="h-full">{editorView}</motion.div>
                </motion.div>
              )}
            </AnimatePresence>
          </div>
        ) : (
          <PhoneFrame statusColor={nowPlaying && player.current ? player.current.album.palette.primary : phoneAlbum ? phoneAlbum.palette.primary : 'var(--ink)'}>
            {/* An album page runs up behind the status bar, which takes the page's colours. */}
            <div ref={screenRef} className="h-full overflow-y-auto" style={{ ['--bar-space' as string]: player.current ? '96px' : '0px', paddingTop: 50, paddingBottom: player.current ? 110 : 30 }}>
              <div className="flex items-center px-3 pt-1">
                {!phoneUnder && (
                  <button onClick={() => setDrawer(true)} className="grid size-9 cursor-pointer place-items-center rounded-full text-accent" aria-label="Show sidebar">
                    <Icon name="sidebar.left" className="size-6" />
                  </button>
                )}
              </div>
              {contentFor(phoneUnder)}
            </div>
            <AnimatePresence>
              {phoneAlbum && (
                <AlbumZoom key={phoneAlbum.id} from={zoomFrom[phoneAlbum.id]}
                           size={screenRef.current ? { width: screenRef.current.clientWidth, height: screenRef.current.clientHeight } : undefined}>
                  <div className="h-full overflow-y-auto" style={{ ['--bar-space' as string]: player.current ? '96px' : '0px' }}>{pageContent}</div>
                </AlbumZoom>
              )}
            </AnimatePresence>
            {player.current && <div className="absolute inset-x-3 bottom-6 z-30"><NowPlayingBar accent={accent} onOpen={openNowPlaying} barRef={barRef} /></div>}
            <AnimatePresence>
              {drawer && (
                <>
                  <motion.div key="shade" initial={{ opacity: 0 }} animate={{ opacity: 1 }} exit={{ opacity: 0 }} className="absolute inset-0 z-40 bg-black/30" onClick={() => setDrawer(false)} />
                  <motion.div key="drawer" initial={{ x: -300 }} animate={{ x: 0 }} exit={{ x: -300 }} transition={{ type: 'spring', stiffness: 400, damping: 40 }}
                              className="glass absolute inset-y-0 left-0 z-50 w-[280px] pt-14">{sidebar}</motion.div>
                </>
              )}
              {editorView && (
                <motion.div key="sheet" initial={{ y: '100%' }} animate={{ y: 0 }} exit={{ y: '100%' }} transition={{ type: 'spring', stiffness: 400, damping: 40 }}
                            className="absolute inset-x-0 top-12 bottom-0 z-[65] overflow-hidden rounded-t-[22px] shadow-[0_-20px_40px_rgb(0_0_0/0.25)]">
                  {editorView}
                </motion.div>
              )}
            </AnimatePresence>
            {overlays}
          </PhoneFrame>
        )}
      </div>
    </DemoContextProvider.Provider>
  );
}
