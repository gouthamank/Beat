// Beat's visualizer, ported from VisualizerScenes.swift and VisualizerView.swift to a 2D canvas: the seven scenes
// (Horizon, Terrain, Spectrum Rings, Starfield, Fountain, Constellation, Bars as a dot matrix) and Waveform. Same
// geometry, constants and colours; movement scaled by frame time.
import { useEffect, useRef } from 'react';
import type { SpectrumFrame } from './player';
import type { Analysis } from './player';

export type VisualizerStyle = 'horizon' | 'terrain' | 'rings' | 'starfield' | 'fountain' | 'constellation' | 'bars' | 'waveform';
export const visualizerStyles: VisualizerStyle[] = ['horizon', 'terrain', 'rings', 'starfield', 'fountain', 'constellation', 'bars', 'waveform'];
export const styleTitle = (s: VisualizerStyle) => (s === 'rings' ? 'Spectrum Rings' : s[0].toUpperCase() + s.slice(1));
export const isScene = (s: VisualizerStyle) => s !== 'waveform';

interface Colours { accent: string; light: string; deep: string }

const rand = (a: number, b: number) => a + Math.random() * (b - a);
const randInt = (a: number, b: number) => Math.floor(rand(a, b));

function alpha(hex: string, a: number) {
  const v = parseInt(hex.slice(1), 16);
  return `rgba(${(v >> 16) & 255},${(v >> 8) & 255},${v & 255},${Math.max(0, Math.min(1, a))})`;
}

/** What each scene keeps from frame to frame (ridgelines, terrain rows, particles), advanced once a frame. */
class Scenes {
  private last?: number;
  private time = 0;
  private frames = 1;
  private lastKick = -1;
  private gridRoll = 0;
  private terrain: number[][] = [];
  private terrainClock = 0;
  private waves: number[] = [];
  private stars: { x: number; y: number; z: number; tint: number }[] = [];
  private sparks: { x: number; y: number; vx: number; vy: number; band: number }[] = [];
  private nodes: { x: number; y: number; vx: number; vy: number; band: number }[] = [];
  static terrainColumns = 33;
  static terrainRows = 28;

  step(frame: SpectrumFrame, style: VisualizerStyle, now: number, w: number, h: number) {
    const dt = this.last === undefined ? 1 / 60 : Math.min(Math.max((now - this.last) / 1000, 0), 0.05);
    this.last = now;
    this.time += dt;
    this.frames = dt * 60;
    const kicked = frame.bass > 0.55 && this.time - this.lastKick > 0.15;
    if (kicked) this.lastKick = this.time;
    switch (style) {
      case 'horizon': this.gridRoll += dt * 2.9; break;
      case 'terrain': this.stepTerrain(frame, dt); break;
      case 'rings':
        if (kicked) this.waves.push(0);
        this.waves = this.waves.map((x) => x + 0.018 * this.frames).filter((x) => x < 1.3);
        break;
      case 'starfield': this.stepStars(frame); break;
      case 'fountain': this.stepFountain(frame, w, h); break;
      case 'constellation': this.stepNodes(frame); break;
    }
  }

  private stepTerrain(frame: SpectrumFrame, dt: number) {
    this.terrainClock += dt;
    if (this.terrainClock < 2 / 60 && this.terrain.length) return;
    this.terrainClock = 0;
    const half = Math.floor(Scenes.terrainColumns / 2);
    // The spectrum mirrored about the middle, the bass in the centre and higher (and taller) towards the sides.
    this.terrain.push(Array.from({ length: Scenes.terrainColumns }, (_, i) => {
      const off = Math.abs(i - half) / half;
      return frame.bands[Math.floor(off * 44)] * (0.3 + off);
    }));
    if (this.terrain.length > Scenes.terrainRows) this.terrain.shift();
  }

  private newStar(far: boolean) {
    return { x: rand(-1, 1), y: rand(-1, 1), z: far ? 1 : rand(0.05, 1.05), tint: Math.random() };
  }

  private stepStars(frame: SpectrumFrame) {
    if (!this.stars.length) this.stars = Array.from({ length: 500 }, () => this.newStar(false));
    const speed = this.starSpeed(frame) * this.frames;
    for (let i = 0; i < this.stars.length; i++) {
      const s = this.stars[i];
      s.z -= speed;
      if (s.z < 0.03 || Math.abs(s.x / s.z) > 1.3 || Math.abs(s.y / s.z) > 1.3) this.stars[i] = this.newStar(true);
    }
  }

  private stepFountain(frame: SpectrumFrame, w: number, h: number) {
    for (let n = 0; n < Math.round(10 * this.frames) && this.sparks.length < 1500; n++) {
      const band = randInt(0, 56);
      const value = frame.bands[band];
      if (value < 0.25) continue;
      this.sparks.push({ x: w * (0.05 + band / 56 * 0.9), y: h, vx: rand(-0.4, 0.4), vy: -Math.sqrt(value) * h * 0.028 * rand(0.8, 1.1), band });
    }
    for (const s of this.sparks) {
      s.x += s.vx * this.frames;
      s.y += s.vy * this.frames;
      s.vy += h * 0.0006 * this.frames;
    }
    this.sparks = this.sparks.filter((s) => s.y <= h + 2);
  }

  private stepNodes(frame: SpectrumFrame) {
    if (!this.nodes.length) {
      this.nodes = Array.from({ length: 70 }, () => ({ x: Math.random(), y: Math.random(), vx: rand(-0.00075, 0.00075), vy: rand(-0.00075, 0.00075), band: randInt(0, 48) }));
    }
    const pace = (1 + energy(frame) * 3) * this.frames;
    for (const n of this.nodes) {
      n.x = (((n.x + n.vx * pace + 1) % 1) + 1) % 1;
      n.y = (((n.y + n.vy * pace + 1) % 1) + 1) % 1;
    }
  }

  private starSpeed(frame: SpectrumFrame) {
    return 0.003 + energy(frame) * 0.02 + frame.bass * 0.02;
  }

  draw(frame: SpectrumFrame, style: VisualizerStyle, c: Colours, x: CanvasRenderingContext2D, w: number, h: number) {
    switch (style) {
      case 'horizon': return this.drawHorizon(frame, c, x, w, h);
      case 'terrain': return this.drawTerrain(c, x, w, h);
      case 'rings': return this.drawRings(frame, c, x, w, h);
      case 'starfield': return this.drawStars(frame, c, x, w, h);
      case 'fountain': return this.drawFountain(c, x, w, h);
      case 'constellation': return this.drawConstellation(frame, c, x, w, h);
      case 'bars': return this.drawDotMatrix(frame, c, x, w, h);
    }
  }

  /** Spectrum bars as a skyline under a setting sun, on a grid rolling towards you. */
  private drawHorizon(frame: SpectrumFrame, c: Colours, x: CanvasRenderingContext2D, w: number, h: number) {
    const horizon = h * 0.58;
    x.fillStyle = '#000'; x.fillRect(0, 0, w, h);
    const sky = x.createLinearGradient(0, 0, 0, h * 0.6);
    sky.addColorStop(0, c.deep); sky.addColorStop(1, '#000');
    x.fillStyle = sky; x.fillRect(0, 0, w, h * 0.6);
    const sun = x.createLinearGradient(0, horizon - h * 0.22, 0, horizon);
    sun.addColorStop(0, alpha(c.light, 0.4)); sun.addColorStop(1, alpha(c.accent, 0.15));
    x.fillStyle = sun;
    x.beginPath(); x.arc(w / 2, horizon, h * 0.22, Math.PI, 2 * Math.PI); x.fill();
    const count = 48, barWidth = w / count;
    x.fillStyle = alpha(c.accent, 0.75);
    x.beginPath();
    for (let i = 0; i < count; i++) {
      const v = frame.bands[Math.floor(Math.abs(i - count / 2) / (count / 2) * 50)];
      x.rect(i * barWidth + 1, horizon - v * h * 0.35, barWidth - 2, v * h * 0.35);
    }
    x.fill();
    x.fillStyle = '#000'; x.fillRect(0, horizon, w, h - horizon);
    x.strokeStyle = alpha(c.accent, 0.7); x.lineWidth = 1;
    x.beginPath();
    for (let k = 0; k < 14; k++) {
      const z = (k + (this.gridRoll % 1)) / 14;
      const y = horizon + z * z * (h - horizon);
      x.moveTo(0, y); x.lineTo(w, y);
    }
    for (let k = -12; k <= 12; k++) {
      x.moveTo(w / 2 + k * 8, horizon); x.lineTo(w / 2 + k * w * 0.12, h);
    }
    x.stroke();
  }

  /** The spectrum on a grid of round LEDs, the top lit dot of each column in the light colour, like hi-fi gear. */
  private drawDotMatrix(frame: SpectrumFrame, c: Colours, x: CanvasRenderingContext2D, w: number, h: number) {
    x.fillStyle = '#050505'; x.fillRect(0, 0, w, h);
    const columns = 32, rows = 16, cw = w / columns, ch = h / rows, radius = Math.min(cw, ch) * 0.32;
    for (let column = 0; column < columns; column++) {
      const level = Math.round(frame.bands[Math.floor(column * 1.5)] * rows);
      for (let row = 0; row < rows; row++) {
        const height = rows - row;
        x.fillStyle = height === level ? c.light : height < level ? alpha(c.accent, 0.55 + (1 - row / rows) * 0.45) : 'rgba(255,255,255,0.05)';
        x.beginPath(); x.arc(column * cw + cw / 2, row * ch + ch / 2, radius, 0, Math.PI * 2); x.fill();
      }
    }
  }

  /** A wireframe landscape rolling towards you, each new row of hills the current spectrum. */
  private drawTerrain(c: Colours, x: CanvasRenderingContext2D, w: number, h: number) {
    const horizon = h * 0.38, columns = Scenes.terrainColumns, depth = Scenes.terrainRows, half = Math.floor(columns / 2);
    x.fillStyle = '#000'; x.fillRect(0, 0, w, h);
    const sky = x.createLinearGradient(0, 0, 0, horizon);
    sky.addColorStop(0, '#000'); sky.addColorStop(1, c.deep);
    x.fillStyle = sky; x.fillRect(0, 0, w, horizon);
    x.fillStyle = alpha(c.light, 0.8);
    x.beginPath(); x.arc(w / 2, horizon, h * 0.16, Math.PI, 2 * Math.PI); x.fill();
    const point = (k: number, i: number, v: number): [number, number] => {
      const z = (k + 1) / depth, spread = w * (0.12 + z * 1.1);
      return [w / 2 + (i - half) / half * spread / 2, horizon + z * z * (h - horizon) - v * h * 0.25 * z];
    };
    const offset = depth - this.terrain.length;
    x.lineWidth = 1;
    this.terrain.forEach((row, k) => {
      const kk = k + offset, a = 0.15 + kk / depth * 0.85;
      x.strokeStyle = alpha(c.accent, a);
      x.beginPath();
      row.forEach((v, i) => { const [px, py] = point(kk, i, v); i === 0 ? x.moveTo(px, py) : x.lineTo(px, py); });
      x.stroke();
      if (k === 0) return;
      x.strokeStyle = alpha(c.accent, a * 0.6);
      x.beginPath();
      for (let i = 0; i < columns; i += 2) {
        const [ax, ay] = point(kk - 1, i, this.terrain[k - 1][i]);
        const [bx, by] = point(kk, i, row[i]);
        x.moveTo(ax, ay); x.lineTo(bx, by);
      }
      x.stroke();
    });
  }

  /** One ring per frequency, bass in the middle; each kick sends a wave out that bends them as it passes. */
  private drawRings(frame: SpectrumFrame, c: Colours, x: CanvasRenderingContext2D, w: number, h: number) {
    x.fillStyle = c.deep; x.fillRect(0, 0, w, h);
    const radius = Math.min(w, h) * 0.47, count = 36;
    for (let i = 0; i < count; i++) {
      const v = frame.bands[Math.floor(i * 1.6)], base = 0.06 + i / count * 0.94;
      const push = this.waves.reduce((sum, wave) => sum + 0.05 * Math.exp(-(((base - wave) * 9) ** 2)) * (1.3 - wave), 0);
      x.strokeStyle = alpha(i < count / 2 ? c.accent : c.light, 0.15 + v * 0.85);
      x.lineWidth = 0.6 + v * 4;
      x.beginPath(); x.arc(w / 2, h / 2, radius * (base + push), 0, Math.PI * 2); x.stroke();
    }
  }

  /** Flying through stars; faster when louder, stretched into streaks on the kick. */
  private drawStars(frame: SpectrumFrame, c: Colours, x: CanvasRenderingContext2D, w: number, h: number) {
    x.fillStyle = '#030303'; x.fillRect(0, 0, w, h);
    const focal = w * 0.4, trail = this.starSpeed(frame) * (2 + frame.bass * 10);
    x.lineCap = 'round';
    const groups: [string, number, number][] = [];
    for (const [tint, colour] of [c.accent, c.light].entries()) {
      for (const [near, [width, a]] of [[1.8, 1], [1.2, 0.75], [0.7, 0.4]].entries()) groups.push([alpha(colour, a), width, tint * 3 + near]);
    }
    const paths = groups.map(() => new Path2D());
    for (const s of this.stars) {
      const near = s.z < 0.35 ? 0 : s.z < 0.7 ? 1 : 2;
      const tail = Math.min(1, s.z + trail);
      const p = paths[(s.tint > 0.8 ? 1 : 0) * 3 + near];
      p.moveTo(w / 2 + s.x / tail * focal, h / 2 + s.y / tail * focal);
      p.lineTo(w / 2 + s.x / s.z * focal, h / 2 + s.y / s.z * focal);
    }
    groups.forEach(([colour, width], i) => { x.strokeStyle = colour; x.lineWidth = width; x.stroke(paths[i]); });
  }

  /** Each frequency a jet along the bottom, bass on the left: sparks rise as high as the band is loud. */
  private drawFountain(c: Colours, x: CanvasRenderingContext2D, w: number, h: number) {
    x.fillStyle = '#030303'; x.fillRect(0, 0, w, h);
    const paths = [new Path2D(), new Path2D(), new Path2D()];
    for (const s of this.sparks) {
      const p = paths[s.band < 18 ? 0 : s.band < 38 ? 1 : 2];
      p.moveTo(s.x - s.vx * 2, s.y - s.vy * 2); p.lineTo(s.x, s.y);
    }
    x.lineWidth = 2; x.lineCap = 'round';
    [c.accent, alpha(c.light, 0.8), alpha(c.light, 0.5)].forEach((colour, i) => { x.strokeStyle = colour; x.stroke(paths[i]); });
  }

  /** Drifting stars joined when close; the bass widens their reach, so the web knits together on the kick. */
  private drawConstellation(frame: SpectrumFrame, c: Colours, x: CanvasRenderingContext2D, w: number, h: number) {
    x.fillStyle = '#030303'; x.fillRect(0, 0, w, h);
    const reach = w * (0.08 + frame.bass * 0.14);
    const links = [new Path2D(), new Path2D(), new Path2D(), new Path2D()];
    for (let a = 0; a < this.nodes.length; a++) {
      for (let b = a + 1; b < this.nodes.length; b++) {
        const px = this.nodes[a].x * w, py = this.nodes[a].y * h, qx = this.nodes[b].x * w, qy = this.nodes[b].y * h;
        const d = Math.hypot(px - qx, py - qy);
        if (d >= reach) continue;
        const bucket = Math.min(3, Math.floor((1 - d / reach) * 4));
        links[bucket].moveTo(px, py); links[bucket].lineTo(qx, qy);
      }
    }
    x.lineWidth = 1;
    links.forEach((p, bucket) => { x.strokeStyle = alpha(c.accent, 0.7 * (bucket + 0.5) / 4); x.stroke(p); });
    for (const n of this.nodes) {
      const v = frame.bands[n.band];
      x.fillStyle = alpha(c.light, 0.5 + v * 0.5);
      x.beginPath(); x.arc(n.x * w, n.y * h, 1.5 + v * 3.5, 0, Math.PI * 2); x.fill();
    }
  }
}

function energy(frame: SpectrumFrame) {
  let sum = 0;
  for (const b of frame.bands) sum += b;
  return frame.bands.length ? sum / frame.bands.length : 0;
}

/** A glowing oscilloscope line across the middle, over the cover's backdrop. */
function drawWaveform(frame: SpectrumFrame, primary: string, x: CanvasRenderingContext2D, w: number, h: number) {
  const points = frame.waveform, mid = h / 2, amplitude = h * 0.3;
  const path = new Path2D();
  points.forEach((v, i) => {
    const px = w * i / (points.length - 1), py = mid - Math.max(-1, Math.min(1, v * 1.4)) * amplitude;
    i === 0 ? path.moveTo(px, py) : path.lineTo(px, py);
  });
  const width = 2 + frame.level * 3;
  x.lineCap = 'round'; x.lineJoin = 'round';
  x.save();
  x.filter = 'blur(10px)';
  x.strokeStyle = alpha(primary, 0.7); x.lineWidth = width * 3; x.stroke(path);
  x.restore();
  x.strokeStyle = primary; x.lineWidth = width; x.stroke(path);
}

/** A canvas redrawn each frame at the screen's resolution. */
function useCanvasLoop(draw: (x: CanvasRenderingContext2D, w: number, h: number, now: number) => void, active: boolean) {
  const canvas = useRef<HTMLCanvasElement>(null);
  const drawRef = useRef(draw);
  drawRef.current = draw;
  useEffect(() => {
    const element = canvas.current;
    const x = element?.getContext('2d');
    if (!element || !x) return;
    let frame = 0;
    const loop = (now: number) => {
      const ratio = window.devicePixelRatio || 1;
      const { width, height } = element.getBoundingClientRect();
      if (element.width !== Math.round(width * ratio)) { element.width = Math.round(width * ratio); element.height = Math.round(height * ratio); }
      x.setTransform(ratio, 0, 0, ratio, 0, 0);
      x.clearRect(0, 0, width, height);
      drawRef.current(x, width, height, now);
      if (active) frame = requestAnimationFrame(loop);
    };
    frame = requestAnimationFrame(loop);
    return () => cancelAnimationFrame(frame);
  }, [active]);
  return canvas;
}

export function VisualizerCanvas({ analysis, playing, style, colours, primary }: {
  analysis?: Analysis; playing: boolean; style: VisualizerStyle; colours: Colours; primary: string;
}) {
  const scenes = useRef(new Scenes());
  const canvas = useCanvasLoop((x, w, h, now) => {
    if (!analysis) return;
    const frame = analysis.next(playing);
    scenes.current.step(frame, style, now, w, h);
    if (style === 'waveform') drawWaveform(frame, primary, x, w, h);
    else scenes.current.draw(frame, style, colours, x, w, h);
  }, true);
  return <canvas ref={canvas} className="absolute inset-0 size-full" aria-hidden="true" />;
}
