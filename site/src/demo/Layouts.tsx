// An element's content in its layout, as ElementView lays it out: shelves that scroll sideways in rows, grids that
// page sideways when capped, lists in columns, Cover Flow (CoverFlowElement) and the year timeline
// (YearTimelineElement). Item order follows ElementPaging: Across fills each row, Down each column.
import { useEffect, useMemo, useRef, useState, type ReactNode } from 'react';
import { useDemo } from './context';
import { AlbumListCell, AlbumTile, ArtistListCell, ArtistTile, GenreListCell, GenreTile, SongCell } from './Tiles';
import {
  allowsAllRows, effectiveFill, itemGap, tileWidth,
  type Appearance, type DemoAlbum, type FilterResult, type Fill,
} from './model';

/** Item indices grouped into on-screen columns, each top to bottom (ElementPaging.columns). */
export function pagingColumns(count: number, rows: number, fill: Fill): number[][] {
  const r = Math.max(rows, 1);
  if (count <= 0) return [];
  if (fill === 'down' || r === 1) return Array.from({ length: Math.ceil(count / r) }, (_, c) => Array.from({ length: Math.min(r, count - c * r) }, (_, k) => c * r + k));
  const width = Math.ceil(count / r);
  return Array.from({ length: width }, (_, c) => Array.from({ length: Math.ceil((count - c) / width) }, (_, k) => c + k * width));
}

function useWidth<T extends HTMLElement>() {
  const ref = useRef<T>(null);
  const [width, setWidth] = useState(0);
  useEffect(() => {
    if (!ref.current) return;
    const observer = new ResizeObserver(([entry]) => setWidth(entry.contentRect.width));
    observer.observe(ref.current);
    return () => observer.disconnect();
  }, []);
  return [ref, width] as const;
}

/** Rows that scroll sideways together, like Apple Music's shelves. */
function Shelf({ count, rows, fill, gap, rowGap, inset, cell }: { count: number; rows: number; fill: Fill; gap: number; rowGap: number; inset: number; cell: (i: number) => ReactNode }) {
  const columns = pagingColumns(count, Math.min(rows, count), fill);
  return (
    <div className="overflow-x-auto">
      <div className="flex w-max items-start py-1.5" style={{ gap, paddingInline: inset }}>
        {columns.map((column, c) => (
          <div key={c} className="flex flex-col" style={{ gap: rowGap }}>{column.map((i) => <div key={i}>{cell(i)}</div>)}</div>
        ))}
      </div>
    </div>
  );
}

/** Columns that scroll sideways and snap to a column: a capped grid or list's screenful, the rest to the right. */
function PagedColumns({ columns, columnWidth, gap, rowGap, inset, cell }: { columns: number[][]; columnWidth: number; gap: number; rowGap: number; inset: number; cell: (i: number) => ReactNode }) {
  return (
    <div className="snap-x snap-mandatory overflow-x-auto" style={{ scrollPaddingInline: inset }}>
      <div className="flex w-max items-start" style={{ gap, paddingInline: inset }}>
        {columns.map((column, c) => (
          <div key={c} className="flex snap-start flex-col" style={{ width: columnWidth, gap: rowGap }}>{column.map((i) => <div key={i}>{cell(i)}</div>)}</div>
        ))}
      </div>
    </div>
  );
}

/** An adaptive grid; with a row limit and more items than fit, it pages sideways instead. */
function TileGrid({ count, rows, fill, minimum, gap, rowGap, inset, cell }: { count: number; rows: number; fill: Fill; minimum: number; gap: number; rowGap: number; inset: number; cell: (i: number) => ReactNode }) {
  const [ref, width] = useWidth<HTMLDivElement>();
  const columns = Math.max(1, Math.floor((width - 2 * inset + gap) / (minimum + gap)));
  const capped = rows > 0 && count > rows * columns;
  return (
    <div ref={ref}>
      {width === 0 ? null : capped ? (
        <PagedColumns columns={pagingColumns(count, rows, fill)} columnWidth={Math.max(minimum, (width - inset * 2 - gap * (columns - 1)) / columns)}
                      gap={gap} rowGap={rowGap} inset={inset} cell={cell} />
      ) : fill === 'down' ? (
        // Fixed columns sharing the row, each filled top to bottom (FittedColumns).
        <div className="flex items-start" style={{ gap, paddingInline: inset }}>
          {Array.from({ length: columns }, (_, c) => (
            <div key={c} className="flex min-w-0 flex-1 flex-col" style={{ gap: rowGap }}>
              {(pagingColumns(count, Math.ceil(count / columns), 'down')[c] ?? []).map((i) => <div key={i}>{cell(i)}</div>)}
            </div>
          ))}
        </div>
      ) : (
        <div className="grid" style={{ gridTemplateColumns: `repeat(${columns}, minmax(0, 1fr))`, columnGap: gap, rowGap, paddingInline: inset }}>
          {Array.from({ length: count }, (_, i) => <div key={i}>{cell(i)}</div>)}
        </div>
      )}
    </div>
  );
}

/** Items in equal-width columns; with more than rows × columns it pages sideways a column at a time. */
function ColumnList({ count, rows, columns, fill, gap, inset, cell }: { count: number; rows: number; columns: number; fill: Fill; gap: number; inset: number; cell: (i: number) => ReactNode }) {
  const [ref, width] = useWidth<HTMLDivElement>();
  const perColumn = rows === 0 ? Math.max(1, Math.ceil(count / columns)) : rows;
  const columnGap = gap + 6, rowGap = Math.max(2, gap / 6);
  const capped = rows > 0 && count > perColumn * columns;
  const laidOut = pagingColumns(count, fill === 'across' && !capped ? Math.ceil(count / columns) : perColumn, fill);
  return (
    <div ref={ref}>
      {capped ? (
        <PagedColumns columns={laidOut} columnWidth={Math.max(160, (width - inset * 2 - columnGap * (columns - 1)) / columns)}
                      gap={columnGap} rowGap={rowGap} inset={inset} cell={cell} />
      ) : (
        <div className="flex items-start" style={{ gap: columnGap, paddingInline: inset }}>
          {Array.from({ length: Math.max(columns, laidOut.length) }, (_, c) => (
            <div key={c} className="flex min-w-0 flex-1 flex-col" style={{ gap: rowGap }}>
              {(laidOut[c] ?? []).map((i) => <div key={i}>{cell(i)}</div>)}
            </div>
          ))}
        </div>
      )}
    </div>
  );
}

/** Where a cover sits from its distance to the centre (CoverFlowGeometry.place). */
function place(d: number, side: number, spread: number) {
  if (d === 0) return { x: 0, rotation: 0, scale: 1.08, z: 100, brightness: 0 };
  const sign = d < 0 ? -1 : 1, steps = Math.abs(d);
  return { x: sign * (side * (0.34 + spread) + (steps - 1) * side * spread), rotation: d < 0 ? 60 : -60, scale: 1, z: 100 - steps, brightness: -Math.min(0.08 + 0.03 * steps, 0.25) };
}

/** Cover Flow, iTunes style: click a side cover to bring it round, the centre to open the album, double-click it to
 *  play. Sideways scrolls and swipes, and ← →, flip through. */
function CoverFlow({ albums, side, spread, inset }: { albums: DemoAlbum[]; side: number; spread: number; inset: number }) {
  const { openAlbum, player, library, preview } = useDemo();
  const [centre, setCentre] = useState(0);
  const index = Math.min(centre, Math.max(0, albums.length - 1));
  const move = (to: number) => setCentre(Math.max(0, Math.min(albums.length - 1, to)));
  const stage = useRef<HTMLDivElement>(null);
  const travel = useRef(0);
  const drag = useRef<{ x: number; moved: boolean } | null>(null);
  const nudge = (delta: number) => {
    // One cover per swipe step of sideways movement, either way.
    travel.current += delta;
    const steps = Math.trunc(travel.current / 30);
    if (steps) { travel.current -= steps * 30; setCentre((c) => Math.max(0, Math.min(albums.length - 1, c + steps))); }
  };
  const nudgeRef = useRef(nudge);
  nudgeRef.current = nudge;
  useEffect(() => {
    const element = stage.current;
    if (!element) return;
    // Sideways scrolls flip covers instead of reaching the page; vertical ones pass through.
    const onWheel = (e: WheelEvent) => {
      if (Math.abs(e.deltaX) <= Math.abs(e.deltaY)) return;
      e.preventDefault();
      nudgeRef.current(e.deltaX);
    };
    element.addEventListener('wheel', onWheel, { passive: false });
    return () => element.removeEventListener('wheel', onWheel);
  }, []);
  const current = albums[index];
  return (
    <div className="py-1.5">
      <div ref={stage} tabIndex={0} className="relative touch-pan-y overflow-hidden outline-none select-none"
           style={{ height: side * 1.5, perspective: side * 4 }}
           onKeyDown={(e) => { if (e.key === 'ArrowLeft') move(index - 1); if (e.key === 'ArrowRight') move(index + 1); }}
           onPointerDown={(e) => { drag.current = { x: e.clientX, moved: false }; }}
           onPointerMove={(e) => {
             if (!drag.current || !e.buttons) return;
             const dx = drag.current.x - e.clientX;
             if (Math.abs(dx) > 3) drag.current.moved = true;
             drag.current.x = e.clientX;
             nudge(dx);
           }}
           onPointerUp={() => setTimeout(() => { drag.current = null; }, 0)}>
        {albums.map((album, i) => {
          const d = i - index;
          if (Math.abs(d) > 8) return null;
          const p = place(d, side, spread);
          return (
            <button key={album.id} className="absolute top-1/2 left-1/2 cursor-pointer transition-[transform,filter] duration-300 ease-out"
                    style={{
                      width: side, height: side, marginLeft: -side / 2, marginTop: -side / 2, zIndex: Math.round(p.z),
                      transform: `translateX(${p.x}px) rotateY(${p.rotation}deg) scale(${p.scale})`,
                      filter: p.brightness ? `brightness(${1 + p.brightness})` : undefined, opacity: Math.abs(d) > 6 ? 0 : 1,
                    }}
                    onClick={(e) => { if (drag.current?.moved || preview) return; d === 0 ? openAlbum(album, e.currentTarget) : move(i); }}
                    onDoubleClick={() => { if (d === 0 && !preview) player.play(library.tracks.filter((t) => t.album.id === album.id)); }}
                    aria-label={d === 0 ? `Open ${album.title}` : `Show ${album.title}`}>
              <img src={album.cover} alt="" draggable={false} className="size-full rounded-lg object-cover shadow-[0_10px_30px_rgb(0_0_0/0.3)]" />
            </button>
          );
        })}
      </div>
      {current && (
        <div className="mt-3.5 text-center" style={{ paddingInline: inset }}>
          <div className="truncate text-[13px] font-semibold">{current.title}</div>
          <div className="truncate text-[11px] text-soft">{current.artist}</div>
        </div>
      )}
    </div>
  );
}

/** Years along a line that scrolls sideways, each year's albums as a small grid under its mark. */
function YearTimeline({ albums, newestFirst, rows, fill, tileWidth: width, gap, rowGap, inset, footer }: {
  albums: DemoAlbum[]; newestFirst: boolean; rows: number; fill: Fill; tileWidth: number; gap: number; rowGap: number; inset: number; footer: boolean;
}) {
  const years = useMemo(() => {
    const groups = new Map<number, number[]>();
    albums.forEach((a, i) => groups.set(a.year, [...(groups.get(a.year) ?? []), i]));
    return [...groups].sort((a, b) => (newestFirst ? b[0] - a[0] : a[0] - b[0]));
  }, [albums, newestFirst]);
  return (
    <div className="overflow-x-auto">
      <div className="flex w-max items-start py-1.5" style={{ paddingInline: inset }}>
        {years.map(([year, indices]) => (
          <div key={year} className="flex flex-col gap-3">
            <div className="flex flex-col gap-1.5">
              <span className="text-[13px] font-semibold tabular-nums text-soft">{year || 'No year'}</span>
              <span className="relative h-0.5 bg-line"><span className="absolute top-1/2 left-0 size-2 -translate-y-1/2 rounded-full bg-soft" /></span>
            </div>
            <div className="flex items-start" style={{ gap, paddingRight: gap * 2.5 }}>
              {pagingColumns(indices.length, rows, fill).map((column, c) => (
                <div key={c} className="flex flex-col" style={{ width, gap: rowGap }}>
                  {column.map((k) => <AlbumTile key={indices[k]} album={albums[indices[k]]} showsFooter={footer} />)}
                </div>
              ))}
            </div>
          </div>
        ))}
      </div>
    </div>
  );
}

export function ElementContent({ result, look, accent }: { result: FilterResult; look: Appearance; accent: string }) {
  const { compact } = useDemo();
  const inset = compact ? 16 : 24;
  const gap = itemGap(look.spacing);
  const width = tileWidth(look.size, result.kind, compact);
  const footer = look.showFooter;
  const tileRowGap = footer ? gap + 6 : gap;
  const fill = effectiveFill(look);
  const listColumns = compact ? 1 : look.columns;
  const rows = allowsAllRows(look.layout) ? look.rows : Math.max(1, look.rows);
  const { kind, layout } = { kind: result.kind, layout: look.layout };

  if (kind === 'songs') {
    const tracks = result.tracks;
    const cell = (i: number) => <SongCell track={tracks[i]} context={tracks} index={i} accent={accent} />;
    if (layout === 'list') return <ColumnList count={tracks.length} rows={rows} columns={listColumns} fill={fill} gap={gap} inset={inset} cell={cell} />;
    return <Shelf count={tracks.length} rows={rows} fill={fill} gap={gap} rowGap={4} inset={inset} cell={(i) => <div style={{ width }}>{cell(i)}</div>} />;
  }
  if (kind === 'albums') {
    const albums = result.albums;
    if (layout === 'list') return <ColumnList count={albums.length} rows={rows} columns={listColumns} fill={fill} gap={gap} inset={inset} cell={(i) => <AlbumListCell album={albums[i]} />} />;
    if (layout === 'coverFlow') {
      const side = { small: 180, medium: 240, large: 320 }[look.size];
      return <CoverFlow albums={albums} side={compact ? Math.min(side, 200) : side} spread={{ compact: 0.2, regular: 0.28, roomy: 0.4 }[look.spacing]} inset={inset} />;
    }
    if (layout === 'timeline') return <YearTimeline albums={albums} newestFirst={!!look.newestFirst} rows={rows} fill={fill} tileWidth={width} gap={gap} rowGap={tileRowGap} inset={inset} footer={footer} />;
    if (layout === 'grid') return <TileGrid count={albums.length} rows={rows} fill={fill} minimum={width} gap={gap} rowGap={tileRowGap} inset={inset} cell={(i) => <AlbumTile album={albums[i]} showsFooter={footer} />} />;
    return <Shelf count={albums.length} rows={rows} fill={fill} gap={gap} rowGap={tileRowGap} inset={inset} cell={(i) => <div style={{ width }}><AlbumTile album={albums[i]} showsFooter={footer} /></div>} />;
  }
  if (kind === 'artists') {
    const artists = result.artists;
    if (layout === 'list') return <ColumnList count={artists.length} rows={rows} columns={listColumns} fill={fill} gap={gap} inset={inset} cell={(i) => <ArtistListCell artist={artists[i]} />} />;
    if (layout === 'grid') return <TileGrid count={artists.length} rows={rows} fill={fill} minimum={width} gap={gap} rowGap={tileRowGap} inset={inset} cell={(i) => <ArtistTile artist={artists[i]} showsFooter={footer} />} />;
    return <Shelf count={artists.length} rows={rows} fill={fill} gap={gap} rowGap={tileRowGap} inset={inset} cell={(i) => <div style={{ width }}><ArtistTile artist={artists[i]} showsFooter={footer} /></div>} />;
  }
  const genres = result.genres;
  if (layout === 'list') return <ColumnList count={genres.length} rows={rows} columns={listColumns} fill={fill} gap={gap} inset={inset} cell={(i) => <GenreListCell genre={genres[i]} />} />;
  if (layout === 'grid') return <TileGrid count={genres.length} rows={rows} fill={fill} minimum={width} gap={gap} rowGap={gap} inset={inset} cell={(i) => <GenreTile genre={genres[i]} showsFooter={footer} />} />;
  return <Shelf count={genres.length} rows={rows} fill={fill} gap={gap} rowGap={gap} inset={inset} cell={(i) => <div style={{ width }}><GenreTile genre={genres[i]} showsFooter={footer} /></div>} />;
}
