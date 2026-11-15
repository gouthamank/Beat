// SVG stand-ins for the SF Symbols Beat uses, by their SF Symbol names, drawn on a 20-unit grid.
const strokes: Record<string, string> = {
  opticaldisc: 'M10 3.5a6.5 6.5 0 1 1 0 13 6.5 6.5 0 0 1 0-13zM10 8a2 2 0 1 1 0 4 2 2 0 0 1 0-4z',
  house: 'M3 9.5 10 4l7 5.5V16a1 1 0 0 1-1 1h-3.5v-4.5h-5V17H4a1 1 0 0 1-1-1z',
  folder: 'M3 6.5V15a1 1 0 0 0 1 1h12a1 1 0 0 0 1-1V8a1 1 0 0 0-1-1h-6L8.5 5H4a1 1 0 0 0-1 1.5z',
  moon: 'M15.5 12.5A6.5 6.5 0 0 1 7.5 4.5a6.5 6.5 0 1 0 8 8z',
  calendar: 'M4 5.5h12v10.5H4zM4 8.5h12M7 3.5v3M13 3.5v3',
  'rectangle.grid.1x2': 'M4 4h12v5H4zM4 11h12v5H4z',
  'square.stack': 'M5 7h10v9H5zM7 4.5h6',
  'music.microphone': 'M11.5 3.5a3 3 0 1 1 0 6 3 3 0 0 1 0-6zM9.5 9 4 15.5l1 1 6.5-5.5',
  'music.note': 'M9 15.5a2.5 2.5 0 1 1-5 0 2.5 2.5 0 0 1 5 0zM9 15.5V4l6 1.5',
  guitars: 'M12 3.5l3 3-5.5 5.5M9.5 12a3 3 0 1 1-4 4 3 3 0 0 1 4-4zM13.5 5l1.5 1.5',
  'chevron.right': 'M8 4.5l5.5 5.5L8 15.5',
  'chevron.left': 'M12 4.5 6.5 10l5.5 5.5',
  'chevron.up': 'M4.5 12 10 6.5l5.5 5.5',
  'chevron.down': 'M4.5 8l5.5 5.5L15.5 8',
  plus: 'M10 4.5v11M4.5 10h11',
  'plus.circle': 'M10 3.5a6.5 6.5 0 1 1 0 13 6.5 6.5 0 0 1 0-13zM10 7v6M7 10h6',
  'square.and.pencil': 'M9 4.5H5a1 1 0 0 0-1 1V15a1 1 0 0 0 1 1h9.5a1 1 0 0 0 1-1v-4M15 3.5l1.5 1.5L10 11.5H8.5V10z',
  'slider.horizontal.3': 'M3.5 5.5h13M3.5 10h13M3.5 14.5h13M7 4v3M13 8.5v3M9 13v3',
  'plus.square.on.square': 'M7 7h9v9H7zM4 13V4h9M11.5 9.5v4M9.5 11.5h4',
  trash: 'M4.5 6h11M8 6V4.5h4V6M6 6l.8 10h6.4L14 6',
  shuffle: 'M3 6h3l7 8h4M3 14h3l2-2.3M11 8.3 13 6h4M15 4l2 2-2 2M15 12l2 2-2 2',
  repeat: 'M4 9V8a2 2 0 0 1 2-2h10l-2-2M16 11v1a2 2 0 0 1-2 2H4l2 2',
  'list.bullet': 'M7.5 5.5h9M7.5 10h9M7.5 14.5h9M4 5.5h.1M4 10h.1M4 14.5h.1',
  'quote.bubble': 'M4 4.5h12a1 1 0 0 1 1 1v7a1 1 0 0 1-1 1H9l-3.5 3v-3H4a1 1 0 0 1-1-1v-7a1 1 0 0 1 1-1zM7.5 8v2M11 8v2',
  waveform: 'M3 10h1M6 7v6M9 4v12M12 6.5v7M15 8.5v3M17.5 10h-.5',
  'line.3.horizontal.decrease': 'M3.5 6h13M6 10h8M8.5 14h3',
  'arrow.up.arrow.down': 'M7 15.5V4.5M4.5 7 7 4.5 9.5 7M13 4.5v11M10.5 13l2.5 2.5 2.5-2.5',
  number: 'M8 4l-1.5 12M13.5 4 12 16M4.5 8h12M3.5 12h12',
  xmark: 'M5.5 5.5l9 9M14.5 5.5l-9 9',
  pencil: 'M12.5 4.5l3 3L8 15H5v-3zM11 6l3 3',
  'face.smiling': 'M10 3.5a6.5 6.5 0 1 1 0 13 6.5 6.5 0 0 1 0-13zM7.5 11.5a3 3 0 0 0 5 0M8 8h.1M12 8h.1',
  'folder.badge.gearshape': 'M3 6.5V15a1 1 0 0 0 1 1h8M17 9V8a1 1 0 0 0-1-1h-6L8.5 5H4a1 1 0 0 0-1 1.5zM15 11.5a2 2 0 1 1 0 4 2 2 0 0 1 0-4z',
  'sidebar.left': 'M3.5 5h13v10h-13zM8 5v10M5 7.5h1.5M5 10h1.5',
  'sidebar.squares.left': 'M3.5 5h13v10h-13zM8 5v10M5 7.5h1.5M5 10h1.5M5 12.5h1.5',
  magnifyingglass: 'M8.5 3.5a5 5 0 1 1 0 10 5 5 0 0 1 0-10zM12.2 12.2 16.5 16.5',
  'speaker.wave.3.fill': 'M3.5 8v4h3l4 3.5v-11l-4 3.5zM13 8a3 3 0 0 1 0 4M15 6a6 6 0 0 1 0 8',
  'minus.circle': 'M10 3.5a6.5 6.5 0 1 1 0 13 6.5 6.5 0 0 1 0-13zM7 10h6',
  'arrow.up.to.line': 'M4 4h12M10 16V7.5M6.5 11 10 7.5l3.5 3.5',
};

const fills: Record<string, string> = {
  'play.fill': 'M6 3.8v12.4a.6.6 0 0 0 .9.5l10-6.2a.6.6 0 0 0 0-1L6.9 3.3a.6.6 0 0 0-.9.5z',
  'pause.fill': 'M5.5 4h3v12h-3zM11.5 4h3v12h-3z',
  'forward.fill': 'M2.5 5.2v9.6a.5.5 0 0 0 .8.4l6.7-4.8a.5.5 0 0 0 0-.8L3.3 4.8a.5.5 0 0 0-.8.4zM10 5.2v9.6a.5.5 0 0 0 .8.4l6.7-4.8a.5.5 0 0 0 0-.8l-6.7-4.8a.5.5 0 0 0-.8.4z',
  'backward.fill': 'M17.5 5.2v9.6a.5.5 0 0 1-.8.4L10 10.4a.5.5 0 0 1 0-.8l6.7-4.8a.5.5 0 0 1 .8.4zM10 5.2v9.6a.5.5 0 0 1-.8.4L2.5 10.4a.5.5 0 0 1 0-.8l6.7-4.8a.5.5 0 0 1 .8.4z',
  airplayaudio: 'M10 12.5 14.5 17h-9zM5.2 13.2A6.5 6.5 0 1 1 14.8 13.2l-1-1A5 5 0 1 0 6.2 12.2z',
};

export function Icon({ name, className = 'size-4', strokeWidth = 1.6 }: { name: string; className?: string; strokeWidth?: number }) {
  if (fills[name]) {
    return (
      <svg viewBox="0 0 20 20" className={className} fill="currentColor" aria-hidden="true">
        <path d={fills[name]} />
      </svg>
    );
  }
  return (
    <svg viewBox="0 0 20 20" className={className} fill="none" stroke="currentColor" strokeWidth={strokeWidth}
         strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
      <path d={strokes[name] ?? strokes['music.note']} />
    </svg>
  );
}
