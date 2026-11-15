// The now-playing bar and Now Playing, after Beat's (NowPlayingBar, NowPlayingView, LyricsView). The bar shows only
// while something plays: a glass capsule whose fill, and a line along its bottom edge, show the progress in the
// cover's colour. Now Playing grows out of it over the window: the cover's colours and a blur of it behind the cover,
// title, artist and album, the scrubber and controls, lyrics beside (in place of the cover on a phone), and the
// visualizer full screen. No close button: drag down, or Esc. (Beat's Radial, round the cover, is left out: it's going.)
import { motion } from 'motion/react';
import { useEffect, useRef, useState } from 'react';
import { useDemo } from './context';
import { Icon } from './Icon';
import { barTint, formatTime, isDark, sceneColours } from './model';
import { useAnalysis, type Player } from './player';
import { isScene, styleTitle, VisualizerCanvas, visualizerStyles, type VisualizerStyle } from './Visualizer';

/** Previous, play/pause, next at Beat's sizes (15 pt, play 22 pt), scaled up in Now Playing. */
function Transport({ scale = 1 }: { scale?: number }) {
  const { player } = useDemo();
  const small = 15 * scale, big = 22 * scale;
  return (
    <div className="flex items-center justify-center" style={{ gap: 22 * scale }}>
      <button onClick={player.previous} className="cursor-pointer" title="Previous" style={{ width: small, height: small }}><Icon name="backward.fill" className="size-full" /></button>
      <button onClick={player.togglePlayPause} className="cursor-pointer" title={player.isPlaying ? 'Pause' : 'Play'} style={{ width: big + 4, height: big }}>
        <Icon name={player.isPlaying ? 'pause.fill' : 'play.fill'} className="size-full" />
      </button>
      <button onClick={player.next} className="cursor-pointer" title="Next" style={{ width: small, height: small }}><Icon name="forward.fill" className="size-full" /></button>
    </div>
  );
}

/** Shuffle, repeat, the queue, volume and output, the active ones in the playback colour. */
function ModeControls({ accent }: { accent: string }) {
  const { player } = useDemo();
  const [volume, setVolume] = useState(1);
  return (
    <div className="flex items-center gap-3.5 text-soft">
      <button onClick={player.toggleShuffle} className="cursor-pointer" title={player.shuffled ? 'Shuffle On' : 'Shuffle Off'} style={{ color: player.shuffled ? accent : undefined }}>
        <Icon name="shuffle" className="size-[15px]" />
      </button>
      <button onClick={player.cycleRepeat} className="relative cursor-pointer" title={`Repeat: ${player.repeat[0].toUpperCase()}${player.repeat.slice(1)}`}
              style={{ color: player.repeat !== 'off' ? accent : undefined }}>
        <Icon name="repeat" className="size-[15px]" />
        {player.repeat === 'one' && <span className="absolute -top-1 -right-1.5 text-[8px] font-bold">1</span>}
      </button>
      <button className="cursor-default opacity-60" title="Queue"><Icon name="list.bullet" className="size-[15px]" /></button>
      <span className="flex items-center gap-1.5" title="Volume">
        <Icon name="speaker.wave.3.fill" className="size-[15px]" />
        <input type="range" min={0} max={1} step={0.01} value={volume} aria-label="Volume" className="w-20"
               style={{ accentColor: 'currentColor' }} onChange={(e) => { setVolume(Number(e.target.value)); player.setVolume(Number(e.target.value)); }} />
      </span>
      <button className="cursor-default opacity-60" title="Output"><Icon name="airplayaudio" className="size-[15px]" /></button>
    </div>
  );
}

/** The scrubber: elapsed, a line to drag or click, remaining. */
function Scrubber({ color }: { color: string }) {
  const { player } = useDemo();
  const fraction = player.duration ? player.time / player.duration : 0;
  return (
    <div className="flex items-center gap-2.5 text-[10px] tabular-nums opacity-85">
      <span className="w-9">{formatTime(player.time)}</span>
      <div className="relative h-1 flex-1 cursor-pointer rounded-full bg-current/20" role="slider" aria-label="Position" aria-valuenow={Math.round(player.time)}
           onClick={(e) => { const box = e.currentTarget.getBoundingClientRect(); player.seek((e.clientX - box.left) / box.width * player.duration); }}>
        <div className="absolute inset-y-0 left-0 rounded-full" style={{ width: `${fraction * 100}%`, backgroundColor: color }} />
        <div className="absolute top-1/2 size-3 -translate-x-1/2 -translate-y-1/2 rounded-full shadow" style={{ left: `${fraction * 100}%`, backgroundColor: color }} />
      </div>
      <span className="w-9 text-right">-{formatTime(Math.max(0, player.duration - player.time))}</span>
    </div>
  );
}

export function NowPlayingBar({ accent, onOpen, barRef }: { accent: string; onOpen: () => void; barRef: React.RefObject<HTMLDivElement | null> }) {
  const { player, compact } = useDemo();
  const track = player.current;
  if (!track) return null;
  const fraction = player.duration ? Math.min(1, player.time / player.duration) : 0;
  const summary = (
    <span className="flex min-w-0 items-center gap-2.5">
      <img src={track.album.cover} alt="" className="size-[46px] shrink-0 rounded-[7px] object-cover shadow-[0_2px_4px_rgb(0_0_0/0.2)]" />
      <span className="min-w-0 text-left">
        <span className="block truncate text-[13px] font-semibold">{track.song.title}</span>
        <span className="block truncate text-[11px] text-soft">{track.album.artist}</span>
      </span>
    </span>
  );
  return (
    <motion.div ref={barRef} initial={{ y: 40, opacity: 0 }} animate={{ y: 0, opacity: 1 }}
                className="glass relative mx-auto w-full max-w-[880px] cursor-pointer overflow-hidden rounded-[24px]" title="Show Now Playing"
                // The whole bar opens Now Playing; controls take their own clicks first, so it gets the glass between them.
                onClick={(e) => { if (!(e.target as HTMLElement).closest('button,input,[data-seek]')) onOpen(); }}>
      {/* The progress: the glass fills with the cover's colour, and a line along the bottom edge shows the same. */}
      <span className="pointer-events-none absolute inset-y-0 left-0 transition-[width] duration-300 ease-linear"
            style={{ width: `${fraction * 100}%`, backgroundColor: `color-mix(in srgb, ${accent} 22%, transparent)` }} />
      <span className="pointer-events-none absolute bottom-0 left-0 h-[2px] transition-[width] duration-300 ease-linear" style={{ width: `${fraction * 100}%`, backgroundColor: accent }} />
      {/* One click on the bottom edge seeks there. */}
      <span data-seek className="absolute inset-x-0 bottom-0 z-10 h-2 cursor-col-resize" onClick={(e) => {
        const box = e.currentTarget.getBoundingClientRect();
        player.seek((e.clientX - box.left) / box.width * player.duration);
      }} />
      {compact ? (
        <div className="relative flex items-center gap-1.5 px-3.5 py-2.5">
          <span className="min-w-0 flex-1">{summary}</span>
          <button onClick={() => player.togglePlayPause()} className="grid size-11 cursor-pointer place-items-center" aria-label={player.isPlaying ? 'Pause' : 'Play'}>
            <Icon name={player.isPlaying ? 'pause.fill' : 'play.fill'} className="size-6" />
          </button>
          <button onClick={() => player.next()} className="grid size-11 cursor-pointer place-items-center" aria-label="Next">
            <Icon name="forward.fill" className="size-5" />
          </button>
        </div>
      ) : (
        <div className="relative flex items-center gap-4 px-3.5 py-2.5">
          <span className="w-[210px]">{summary}</span>
          <div className="flex flex-1 flex-col items-center gap-1">
            <Transport />
            <div className="flex w-full max-w-[220px] justify-between text-[10px] tabular-nums text-soft">
              <span>{formatTime(player.time)}</span><span>-{formatTime(Math.max(0, player.duration - player.time))}</span>
            </div>
          </div>
          <ModeControls accent={accent} />
        </div>
      )}
    </motion.div>
  );
}

/** Synced lyrics: the current line bright and a third of the way down, the others faded; a click seeks. */
function Lyrics({ primary, secondary }: { primary: string; secondary: string }) {
  const { player, compact } = useDemo();
  const lines = player.lyrics;
  const current = lines.reduce((found, line, i) => (line.time <= player.time + 0.15 ? i : found), -1);
  const box = useRef<HTMLDivElement>(null);
  useEffect(() => {
    const element = box.current?.querySelector<HTMLElement>(`[data-line="${Math.max(current, 0)}"]`);
    if (element && box.current) box.current.scrollTo({ top: element.offsetTop - box.current.clientHeight / 3, behavior: 'smooth' });
  }, [current]);
  if (!lines.length) {
    return <div className="grid h-full place-items-center text-[17px]" style={{ color: secondary }}>No lyrics for this song</div>;
  }
  return (
    <div ref={box} data-lyrics className="h-full touch-pan-y overflow-y-auto overscroll-contain py-[35%] [mask-image:linear-gradient(transparent,black_12%,black_85%,transparent)]">
      {lines.map((line, i) => (
        <button key={i} data-line={i} onClick={() => player.seek(line.time)}
                className={`block w-full cursor-pointer py-2 text-left font-bold leading-snug transition-opacity duration-300 ${compact ? 'text-[20px]' : 'text-[22px]'}`}
                style={{ color: primary, opacity: i === current ? 1 : 0.35 }}>
          {line.text}
        </button>
      ))}
    </div>
  );
}

export function NowPlayingView({ from, accent, startVisualizing = false, onClose, onOpenAlbum }: {
  from?: DOMRect; accent: string; startVisualizing?: boolean; onClose: () => void; onOpenAlbum: () => void;
}) {
  const { player, compact } = useDemo();
  const track = player.current!;
  const p = track.album.palette;
  const dark = isDark(p);
  const analysis = useAnalysis(player.analyser);
  const [showLyrics, setShowLyrics] = useState(true);
  const [visualizing, setVisualizing] = useState(false);
  const [style, setStyle] = useState<VisualizerStyle>('horizon');
  const [hint, setHint] = useState<VisualizerStyle>();
  const [controlsVisible, setControlsVisible] = useState(true);
  const [pull, setPull] = useState(0);
  const root = useRef<HTMLDivElement>(null);
  const hideTimer = useRef<number>(undefined);
  const hintTimer = useRef<number>(undefined);
  const drag = useRef<number | null>(null);

  const reveal = () => {
    setControlsVisible(true);
    clearTimeout(hideTimer.current);
    hideTimer.current = window.setTimeout(() => setControlsVisible(false), 3000);
  };
  const step = (by: number) => {
    const i = visualizerStyles.indexOf(style);
    const next = visualizerStyles[(i + by + visualizerStyles.length) % visualizerStyles.length];
    setStyle(next);
    setHint(next);
    reveal();
    clearTimeout(hintTimer.current);
    hintTimer.current = window.setTimeout(() => setHint(undefined), 1200);
  };
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (e.key === 'Escape') { visualizing ? setVisualizing(false) : onClose(); }
      if (visualizing && e.key === 'ArrowLeft') step(-1);
      if (visualizing && e.key === 'ArrowRight') step(1);
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  });
  useEffect(() => { if (visualizing) reveal(); }, [visualizing]);
  // Asked to show the visualizer, Now Playing opens first and then moves into it, so it's seen to be part of it.
  useEffect(() => {
    if (!startVisualizing) return;
    const timer = window.setTimeout(() => setVisualizing(true), 1100);
    return () => clearTimeout(timer);
  }, []);

  // Grows out of the bar: from its rectangle, inside the window, to the whole window.
  const box = root.current?.parentElement?.getBoundingClientRect();
  const start = from && box ? { top: from.top - box.top, left: from.left - box.left, width: from.width, height: from.height, borderRadius: 24 } : { opacity: 0 };
  const lyricsOn = showLyrics;
  const colours = sceneColours(p);
  const primary = p.primary, secondary = p.secondary;

  const cover = (
    // Beat caps a square cover at 340 points beside lyrics and 440 without; the demo's window is shorter than Beat's,
    // so the cover also gives way to the title and controls below it (about 330 points) to fit the height.
    <div className="relative mx-auto aspect-square" style={compact ? { width: '100%' } : { width: `min(${lyricsOn ? 340 : 440}px, calc(100cqh - 330px))` }}>
      <img src={track.album.coverLarge} alt=""
           className="relative size-full rounded-2xl object-cover shadow-[0_14px_30px_rgb(0_0_0/0.35)]" />
    </div>
  );

  const playerColumn = (
    <div className={`flex flex-col items-center gap-[22px] ${compact ? 'w-full' : ''}`} style={{ width: compact ? undefined : lyricsOn ? 400 : 520 }}>
      {!(compact && lyricsOn) && <div className={compact ? 'w-[78%]' : 'flex w-full justify-center'}>{cover}</div>}
      <div className="w-full text-center">
        <div className="line-clamp-2 text-[26px] font-bold leading-tight" style={{ color: primary }}>{track.song.title}</div>
        <div className="truncate text-[19px]" style={{ color: secondary }}>{track.album.artist}</div>
        <button onClick={onOpenAlbum} className="cursor-pointer truncate text-[15px] hover:underline" style={{ color: secondary }} title="Show Album">{track.album.title}</button>
      </div>
      <div className="flex w-full max-w-[420px] flex-col gap-3" style={{ color: primary }}>
        <Scrubber color={primary} />
        <div className="py-1.5"><Transport scale={1.3} /></div>
        <div className="flex items-center justify-center gap-3.5" style={{ color: secondary }}>
          {!compact && <ModeControls accent={primary} />}
          <button onClick={() => setShowLyrics((s) => !s)} className="cursor-pointer" title="Lyrics" aria-pressed={lyricsOn} style={{ color: lyricsOn ? primary : undefined }}>
            <Icon name="quote.bubble" className="size-[15px]" />
          </button>
          <button onClick={() => setVisualizing(true)} className="cursor-pointer" title="Visualizer"><Icon name="waveform" className="size-[15px]" /></button>
        </div>
        {!compact && <div className="pt-2.5 text-center text-[10px] tabular-nums opacity-70" style={{ color: secondary }}>AAC</div>}
      </div>
    </div>
  );

  return (
    <motion.div ref={root} initial={start} animate={{ top: 0, left: 0, width: '100%', height: '100%', borderRadius: 0, opacity: 1 }}
                exit={from && box ? start : { opacity: 0 }} transition={{ type: 'spring', stiffness: 260, damping: 30 }}
                // On a touchscreen a drag here closes Now Playing rather than scrolling the website under it (touch-none);
                // the lyrics scroll themselves. The pointer is captured so a drag keeps going past the edges.
                className="absolute z-50 touch-none overflow-hidden [container-type:size]" role="dialog" aria-label="Now Playing"
                style={{ backgroundColor: p.background, colorScheme: dark ? 'dark' : 'light', translate: `0 ${pull}px` }}
                onPointerDown={(e) => {
                  if ((e.target as HTMLElement).closest('button,input,select,[role=slider],[data-lyrics]')) return;
                  drag.current = e.clientY;
                  e.currentTarget.setPointerCapture(e.pointerId);
                }}
                onPointerMove={(e) => { if (drag.current !== null && e.buttons) setPull(Math.max(0, e.clientY - drag.current)); if (visualizing) reveal(); }}
                onPointerUp={() => { if (pull > 120) onClose(); else setPull(0); drag.current = null; }}
                onPointerCancel={() => { setPull(0); drag.current = null; }}>
      {/* The backdrop: the cover's colour with a vivid blur of the cover over it. */}
      <div className="pointer-events-none absolute inset-0" aria-hidden="true">
        <img src={track.album.coverLarge} alt="" className="size-full scale-125 object-cover opacity-80 blur-[70px] saturate-[1.6]" />
        <div className="absolute inset-0" style={{ backgroundColor: p.background, opacity: 0.45 }} />
      </div>
      {visualizing ? (
        <div className="absolute inset-0" style={{ colorScheme: isScene(style) ? 'dark' : undefined }}>
          <VisualizerCanvas analysis={analysis} playing={player.isPlaying} style={style} colours={colours} primary={primary} />
          <div className="absolute inset-0 flex flex-col px-7 pt-11 pb-7 transition-opacity duration-400" style={{ opacity: controlsVisible ? 1 : 0 }}>
            <div className="flex items-center">
              <button onClick={() => setVisualizing(false)} className="glass grid size-9 cursor-pointer place-items-center rounded-full" title="Leave Visualizer (Esc)">
                <Icon name="chevron.left" className="size-4" strokeWidth={2} />
              </button>
              <div className="flex flex-1 justify-center">
                <select value={style} onChange={(e) => setStyle(e.target.value as VisualizerStyle)} aria-label="Style"
                        className="glass w-[200px] rounded-md px-2 py-1 text-[13px] outline-none">
                  {visualizerStyles.map((s) => <option key={s} value={s}>{styleTitle(s)}</option>)}
                </select>
              </div>
              <div className="size-9" />
            </div>
            <div className="flex-1" />
            <div className={`flex ${compact ? 'flex-col gap-3' : 'items-end gap-6'}`}>
              <div className="min-w-0 flex-1">
                <div className="truncate text-[15px] font-semibold" style={{ color: isScene(style) ? '#fff' : primary }}>{track.song.title}</div>
                <div className="truncate text-[13px]" style={{ color: isScene(style) ? 'rgb(255 255 255 / 0.7)' : secondary }}>{track.album.artist}</div>
              </div>
              <div className="flex flex-col gap-2" style={{ width: compact ? undefined : 380, color: isScene(style) ? '#fff' : primary }}>
                <Scrubber color={isScene(style) ? colours.accent : primary} />
                <Transport />
              </div>
              {!compact && <div className="flex-1" />}
            </div>
          </div>
          {hint && (
            <div className="glass absolute top-1/2 left-1/2 -translate-x-1/2 -translate-y-1/2 rounded-full px-5 py-3 text-[20px] font-semibold">{styleTitle(hint)}</div>
          )}
        </div>
      ) : (
        <div className={`relative flex h-full items-center justify-center ${compact ? 'flex-col gap-5 px-5 pt-14 pb-8' : 'gap-14 p-12'}`}>
          {compact && lyricsOn && <div className="min-h-0 w-full flex-1"><Lyrics primary={primary} secondary={secondary} /></div>}
          {playerColumn}
          {!compact && lyricsOn && <div className="h-full max-h-[640px] w-full max-w-[560px] min-w-0"><Lyrics primary={primary} secondary={secondary} /></div>}
        </div>
      )}
    </motion.div>
  );
}

/** The playing cover's colour, made readable on the window, else the system accent (`\.playbackAccent`). */
export function playbackAccent(player: Player, dark: boolean, fallback: string) {
  const p = player.current?.album.palette;
  return (p && barTint(p, dark)) ?? fallback;
}
