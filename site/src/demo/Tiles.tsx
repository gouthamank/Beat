// Album, artist and genre tiles, list cells and song cells, as Beat draws them (AlbumTile, ArtistTile, GenreTile,
// ListCellContent, SongCell). Album and genre tiles open their pages; song cells play.
import { useState } from 'react';
import { useDemo } from './context';
import { Icon } from './Icon';
import { counted, type Artist, type DemoAlbum, type Genre, type Track } from './model';

export function Artwork({ album, radius, className = '' }: { album?: DemoAlbum; radius: number; className?: string }) {
  return album ? (
    <img src={album.cover} alt="" draggable={false} loading="lazy" className={`aspect-square w-full object-cover ${className}`}
         style={{ borderRadius: radius }} />
  ) : (
    <span className={`block aspect-square w-full bg-line ${className}`} style={{ borderRadius: radius }} />
  );
}

/** Up to four of an artist's covers in a 2×2 square, newest first; one fills it, two sit diagonally, three repeat. */
export function ArtistArtwork({ artist, radius }: { artist: Artist; radius: number }) {
  const covers = artist.albums.slice(0, 4);
  if (covers.length <= 1) return <Artwork album={covers[0]} radius={radius} />;
  const cells = [covers[0], covers[1 % covers.length], covers.length === 2 ? covers[1] : covers[2], covers.length === 4 ? covers[3] : covers[0]];
  return (
    <span className="grid aspect-square w-full grid-cols-2 overflow-hidden" style={{ borderRadius: radius }}>
      {cells.map((a, i) => <img key={i} src={a.cover} alt="" draggable={false} loading="lazy" className="size-full object-cover" />)}
    </span>
  );
}

const tileShadow = (hover: boolean, big = false) =>
  hover ? `0 ${big ? 8 : 6}px ${big ? 28 : 24}px rgb(0 0 0 / 0.3)` : `0 3px ${big ? 12 : 10}px rgb(0 0 0 / 0.15)`;

/** A cover with its title and artist below; grows a little on hover, with a play button in its corner. Clicking
 *  opens the album page. */
export function AlbumTile({ album, showsFooter = true, showsArtist = true }: { album: DemoAlbum; showsFooter?: boolean; showsArtist?: boolean }) {
  const { openAlbum, player, library, preview } = useDemo();
  const [hover, setHover] = useState(false);
  return (
    <div className="flex min-w-0 cursor-pointer flex-col gap-1.5" onMouseEnter={() => setHover(true)} onMouseLeave={() => setHover(false)}
         onClick={(e) => !preview && openAlbum(album, e.currentTarget.querySelector('img'))} role="button" aria-label={`${album.title}, ${album.artist}`}>
      <span className="relative block transition-transform duration-200" style={{ transform: hover ? 'scale(1.03)' : undefined }}>
        <span className="block rounded-[10px] transition-shadow duration-200" style={{ boxShadow: tileShadow(hover, true) }}>
          <Artwork album={album} radius={10} />
        </span>
        {hover && !preview && (
          <button onClick={(e) => { e.stopPropagation(); player.play(library.tracks.filter((t) => t.album.id === album.id)); }}
                  className="glass absolute right-2.5 bottom-2.5 grid size-[34px] cursor-pointer place-items-center rounded-full" aria-label="Play">
            <Icon name="play.fill" className="size-3.5" />
          </button>
        )}
      </span>
      {showsFooter && (
        <span className="min-w-0">
          <span className="block truncate text-[13px] font-medium">{album.title}</span>
          {showsArtist && <span className="block truncate text-[11px] text-soft">{album.artist}</span>}
        </span>
      )}
    </div>
  );
}

/** An artist's photo or cover mosaic, name and album count below. (No artist pages in the demo.) */
export function ArtistTile({ artist, showsFooter = true }: { artist: Artist; showsFooter?: boolean }) {
  const [hover, setHover] = useState(false);
  return (
    <div className="flex min-w-0 flex-col items-center gap-2 text-center" onMouseEnter={() => setHover(true)} onMouseLeave={() => setHover(false)}>
      <span className="block w-full rounded-[10px] transition-all duration-200" style={{ boxShadow: tileShadow(hover), transform: hover ? 'scale(1.03)' : undefined }}>
        <ArtistArtwork artist={artist} radius={10} />
      </span>
      {showsFooter && (
        <span className="w-full min-w-0">
          <span className="block truncate text-[13px] font-medium">{artist.name}</span>
          <span className="block truncate text-[11px] text-soft">{counted(artist.albums.length, 'album')}</span>
        </span>
      )}
    </div>
  );
}

/** A genre: its first album's art, with its name and song count over a dark fade at the bottom. Opens its page. */
export function GenreTile({ genre, showsFooter = true }: { genre: Genre; showsFooter?: boolean }) {
  const { openGenre, preview } = useDemo();
  const [hover, setHover] = useState(false);
  return (
    <button onClick={() => !preview && openGenre(genre)} onMouseEnter={() => setHover(true)} onMouseLeave={() => setHover(false)}
            className="relative block w-full cursor-pointer rounded-[14px] text-left transition-all duration-200"
            style={{ boxShadow: tileShadow(hover), transform: hover ? 'scale(1.03)' : undefined }}>
      <Artwork album={genre.albums[0]} radius={14} />
      {showsFooter && (
        <>
          <span className="absolute inset-0 rounded-[14px] bg-[linear-gradient(transparent_50%,rgb(0_0_0/0.75))]" />
          <span className="absolute bottom-0 left-0 p-3 text-white">
            <span className="block text-[14px] font-semibold">{genre.name}</span>
            <span className="block text-[11px] opacity-80">{counted(genre.trackCount, 'song')}</span>
          </span>
        </>
      )}
    </button>
  );
}

/** Art, title and subtitle, for album, artist and genre lists. */
function ListCell({ art, title, subtitle, onClick }: { art: React.ReactNode; title: string; subtitle: string; onClick?: (cover: Element | null) => void }) {
  return (
    <div onClick={(e) => onClick?.(e.currentTarget.querySelector('img'))} role={onClick ? 'button' : undefined}
         className={`flex min-w-0 items-center gap-2.5 rounded-lg p-[5px] hover:bg-ink/[0.06] ${onClick ? 'cursor-pointer' : ''}`}>
      <span className="block size-[42px] shrink-0 overflow-hidden rounded-[5px]">{art}</span>
      <span className="min-w-0 flex-1">
        <span className="block truncate text-[13px]">{title}</span>
        <span className="block truncate text-[11px] text-soft">{subtitle}</span>
      </span>
    </div>
  );
}

export function AlbumListCell({ album }: { album: DemoAlbum }) {
  const { openAlbum, preview } = useDemo();
  return <ListCell art={<Artwork album={album} radius={5} />} title={album.title} subtitle={album.artist} onClick={preview ? undefined : (cover) => openAlbum(album, cover)} />;
}

export function ArtistListCell({ artist }: { artist: Artist }) {
  return <ListCell art={<ArtistArtwork artist={artist} radius={5} />} title={artist.name} subtitle={counted(artist.albums.length, 'album')} />;
}

export function GenreListCell({ genre }: { genre: Genre }) {
  const { openGenre, preview } = useDemo();
  return <ListCell art={<Artwork album={genre.albums[0]} radius={5} />} title={genre.name} subtitle={counted(genre.trackCount, 'song')}
                   onClick={preview ? undefined : () => openGenre(genre)} />;
}

/** Three bouncing bars marking the playing song; still when paused. */
export function PlayingIndicator({ animating, color = 'currentColor' }: { animating: boolean; color?: string }) {
  return (
    <span className="flex h-3.5 items-end gap-[2px]" aria-hidden="true">
      {[0, 1, 2].map((i) => (
        <span key={i} className="w-[3px] rounded-[1px]" style={{
          backgroundColor: color, height: animating ? undefined : `${[50, 80, 35][i]}%`,
          animation: animating ? `beat-bounce ${[0.9, 0.7, 1.1][i]}s ease-in-out ${i * 0.15}s infinite alternate` : undefined,
        }} />
      ))}
    </span>
  );
}

/** A song: cover, title, "Artist · Album". A click plays it (or pauses the playing one); the playing song is tinted,
 *  with the equalizer on its cover. */
export function SongCell({ track, context, index, accent }: { track: Track; context: Track[]; index: number; accent: string }) {
  const { player, preview } = useDemo();
  const [hover, setHover] = useState(false);
  const isCurrent = player.current?.key === track.key;
  return (
    <div role="button" onMouseEnter={() => setHover(true)} onMouseLeave={() => setHover(false)}
         onClick={() => { if (preview) return; isCurrent ? player.togglePlayPause() : player.play(context, index); }}
         className="flex min-w-0 cursor-pointer items-center gap-2.5 rounded-lg p-[5px]"
         style={{ backgroundColor: isCurrent ? `color-mix(in srgb, ${accent} 16%, transparent)` : hover ? 'color-mix(in srgb, var(--ink) 6%, transparent)' : undefined }}>
      <span className="relative block size-[42px] shrink-0 overflow-hidden rounded-[5px]">
        <Artwork album={track.album} radius={5} />
        {(hover || isCurrent) && (
          <span className="absolute inset-0 grid place-items-center bg-black/45 text-white">
            {isCurrent ? <PlayingIndicator animating={player.isPlaying} color="#fff" /> : <Icon name="play.fill" className="size-3.5" />}
          </span>
        )}
      </span>
      <span className="min-w-0 flex-1">
        <span className={`block truncate text-[13px] ${isCurrent ? 'font-semibold' : ''}`}>{track.song.title}</span>
        <span className="block truncate text-[11px] text-soft">{track.album.artist} · {track.album.title}</span>
      </span>
    </div>
  );
}
