// The demo's player, after Beat's PlaybackQueue: play a list from a song (shuffled or not), previous and next,
// shuffle, repeat (off, all, one), seek. One <audio> plays it; Web Audio feeds the visualizers, analysed as Beat's
// SpectrumAnalyzer does. Nothing plays until someone clicks: browsers allow sound only after a gesture, and the site
// promises never to autoplay. A song without music of its own plays one of the few that have it.
import { useEffect, useMemo, useRef, useState } from 'react';
import type { LyricLine, Track } from './model';

export type RepeatMode = 'off' | 'all' | 'one';

/** One analysed, smoothed moment of audio, all values 0…1, as Beat's SpectrumFrame. */
export interface SpectrumFrame {
  bands: Float32Array;
  level: number;
  bass: number;
  waveform: Float32Array;
}

const bandCount = 64, waveformPoints = 256;
const lowHz = 30, highHz = 16000, bassHz = 150, floorDB = -80, ceilingDB = -12;
const edges = Array.from({ length: bandCount + 1 }, (_, k) => lowHz * (highHz / lowHz) ** (k / bandCount));

/** Reads the analyser each frame and eases values towards their targets: fast up, slow down (Beat's Smoother). */
export class Analysis {
  private freq: Float32Array<ArrayBuffer>;
  private time: Float32Array<ArrayBuffer>;
  readonly frame: SpectrumFrame = { bands: new Float32Array(bandCount), level: 0, bass: 0, waveform: new Float32Array(waveformPoints) };

  constructor(private analyser: AnalyserNode) {
    this.freq = new Float32Array(analyser.frequencyBinCount);
    this.time = new Float32Array(analyser.fftSize);
  }

  next(playing: boolean): SpectrumFrame {
    const f = this.frame;
    const ease = (value: number, target: number) => Math.min(1, Math.max(0, value + (target - value) * (target > value ? 0.6 : 0.12)));
    if (!playing) {
      for (let i = 0; i < bandCount; i++) f.bands[i] = ease(f.bands[i], 0);
      f.level = ease(f.level, 0);
      f.bass = ease(f.bass, 0);
      for (let i = 0; i < waveformPoints; i++) f.waveform[i] *= 0.5;
      return f;
    }
    this.analyser.getFloatFrequencyData(this.freq);
    this.analyser.getFloatTimeDomainData(this.time);
    const binHz = this.analyser.context.sampleRate / this.analyser.fftSize;
    let bassSum = 0, bassCount = 0;
    for (let k = 0; k < bandCount; k++) {
      // Each band takes its loudest bin; a band narrower than one bin uses the bin at its centre.
      const from = Math.floor(edges[k] / binHz), to = Math.floor(edges[k + 1] / binHz);
      let db = -Infinity;
      if (to <= from) db = this.freq[Math.round((edges[k] + edges[k + 1]) / 2 / binHz)] ?? -Infinity;
      else for (let b = from; b < to && b < this.freq.length; b++) db = Math.max(db, this.freq[b]);
      const target = Math.min(1, Math.max(0, (db - floorDB) / (ceilingDB - floorDB)));
      f.bands[k] = ease(f.bands[k], target);
      if (edges[k + 1] <= bassHz) { bassSum += target; bassCount++; }
    }
    let squares = 0;
    for (const s of this.time) squares += s * s;
    const rms = Math.sqrt(squares / this.time.length);
    f.level = ease(f.level, Math.min(1, Math.max(0, (20 * Math.log10(rms + 1e-9) + 50) / 50)));
    f.bass = ease(f.bass, bassCount ? bassSum / bassCount : 0);
    // The largest-magnitude sample of each chunk, so peaks and their sign survive.
    const chunk = this.time.length / waveformPoints;
    for (let i = 0; i < waveformPoints; i++) {
      let peak = 0;
      for (let j = Math.floor(i * chunk); j < Math.floor((i + 1) * chunk); j++) if (Math.abs(this.time[j]) > Math.abs(peak)) peak = this.time[j];
      f.waveform[i] += (peak - f.waveform[i]) * 0.5;
    }
    return f;
  }
}

/** A song with music of its own: its file and, for one with vocals, its lyrics. */
export interface Borrowable {
  audio: string;
  lyrics?: LyricLine[];
}

export function usePlayer(pool: Borrowable[]) {
  const audio = useRef<HTMLAudioElement | null>(null);
  const [analyser, setAnalyser] = useState<AnalyserNode>();
  const [queue, setQueue] = useState<Track[]>([]);
  const [index, setIndex] = useState(0);
  const [isPlaying, setIsPlaying] = useState(false);
  const [time, setTime] = useState(0);
  const [duration, setDuration] = useState(0);
  const [shuffled, setShuffled] = useState(false);
  const [repeat, setRepeat] = useState<RepeatMode>('off');
  const state = useRef({ queue, index, repeat });
  state.current = { queue, index, repeat };
  const current = queue[index];
  /** What a song plays: its own music, or one of the songs with music, borrowed with its lyrics so the words always
   *  match what's heard. */
  const borrowed = (t: Track): Borrowable | undefined => {
    if (t.song.audio) return { audio: t.song.audio, lyrics: t.song.lyrics };
    if (!pool.length) return undefined;
    let h = 0;
    for (const c of t.key) h = (h * 31 + c.charCodeAt(0)) >>> 0;
    return pool[h % pool.length];
  };
  const source = (t: Track) => borrowed(t)?.audio;

  useEffect(() => () => audio.current?.pause(), []);

  const ensureAudio = () => {
    if (audio.current) return audio.current;
    const element = new Audio();
    element.preload = 'none';
    element.addEventListener('timeupdate', () => setTime(element.currentTime));
    element.addEventListener('durationchange', () => setDuration(element.duration || 0));
    element.addEventListener('play', () => setIsPlaying(true));
    element.addEventListener('pause', () => setIsPlaying(false));
    element.addEventListener('ended', () => {
      const { queue, index, repeat } = state.current;
      if (repeat === 'one') { element.currentTime = 0; void element.play(); return; }
      if (index + 1 < queue.length) start(queue, index + 1);
      else if (repeat === 'all' && queue.length) start(queue, 0);
      else setIsPlaying(false);
    });
    try {
      // Web Audio for the visualizers, made inside the click that started playback, as browsers require.
      const context = new AudioContext();
      const node = context.createAnalyser();
      node.fftSize = 4096;
      node.smoothingTimeConstant = 0;
      context.createMediaElementSource(element).connect(node);
      node.connect(context.destination);
      setAnalyser(node);
    } catch {
      // The music still plays, without the visualizers.
    }
    audio.current = element;
    return element;
  };

  const start = (tracks: Track[], at: number) => {
    setQueue(tracks);
    setIndex(at);
    setTime(0);
    setDuration(0);
    const src = source(tracks[at]);
    if (!src) return;
    const element = ensureAudio();
    element.src = src;
    void element.play();
  };

  return {
    current, queue, index, isPlaying,
    /** The lyrics of what's playing (its own, or those of the music it borrowed). */
    lyrics: queue[index] ? borrowed(queue[index])?.lyrics ?? [] : [], time, duration: duration || current?.song.duration || 0, shuffled, repeat, analyser,
    play(tracks: Track[], startAt = 0, shuffle = false) {
      if (!tracks.length) return;
      let list = tracks;
      let at = startAt;
      if (shuffle) {
        list = [...tracks].sort(() => Math.random() - 0.5);
        at = 0;
      }
      setShuffled(shuffle);
      start(list, at);
    },
    togglePlayPause() {
      const element = audio.current;
      if (!element || !current) return;
      if (element.paused) void element.play();
      else element.pause();
    },
    next() {
      if (index + 1 < queue.length) start(queue, index + 1);
      else if (repeat === 'all' && queue.length) start(queue, 0);
    },
    previous() {
      // Back to the start of the song first, unless it's only just begun.
      if (time > 3 && audio.current) { audio.current.currentTime = 0; return; }
      if (index > 0) start(queue, index - 1);
      else if (audio.current) audio.current.currentTime = 0;
    },
    toggleShuffle() {
      if (!current) return;
      const others = queue.filter((_, i) => i !== index);
      if (!shuffled) others.sort(() => Math.random() - 0.5);
      setQueue([current, ...others]);
      setIndex(0);
      setShuffled(!shuffled);
    },
    cycleRepeat() { setRepeat((r) => (r === 'off' ? 'all' : r === 'all' ? 'one' : 'off')); },
    seek(seconds: number) {
      const element = audio.current;
      if (element && element.duration) element.currentTime = Math.max(0, Math.min(seconds, element.duration - 0.3));
    },
    setVolume(v: number) { ensureAudio().volume = v; },
  };
}

export type Player = ReturnType<typeof usePlayer>;

/** A frame loop with the analysis, while `active`. */
export function useAnalysis(analyser: AnalyserNode | undefined) {
  return useMemo(() => (analyser ? new Analysis(analyser) : undefined), [analyser]);
}
