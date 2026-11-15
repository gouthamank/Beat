// The demo's data and smart filters: a TypeScript copy of Beat's (Field, RuleOperator, SmartFilter, SmartFilterEngine,
// ElementAppearance, Presets), over the showcase library. Steps run in order over songs; Sort orders songs, or
// albums/artists/genres by each one's combined value; Limit keeps songs, minutes, hours or groups; then the songs
// become the kind the element finds.

// MARK: Library

export interface LyricLine {
  time: number;
  text: string;
}

export interface Palette {
  background: string;
  primary: string;
  secondary: string;
}

export interface DemoSong {
  title: string;
  track: number;
  duration: number;
  plays: number;
  skips: number;
  lastPlayedDaysAgo?: number;
  lastSkippedDaysAgo?: number;
  /** A playable file's URL, for the songs with real music. */
  audio?: string;
  /** Synced lyrics, for the songs with vocals. */
  lyrics?: LyricLine[];
}

export interface DemoAlbum {
  id: string;
  title: string;
  artist: string;
  genre: string;
  year: number;
  addedDaysAgo: number;
  /** The comments tag on its songs; one label's releases carry a catalog number in it. */
  comments?: string;
  cover: string;
  /** A large copy, for album pages and Now Playing. */
  coverLarge: string;
  palette: Palette;
  songs: DemoSong[];
}

/** A song with its album: what filters, sorts and lists work on. */
export interface Track {
  key: string;
  song: DemoSong;
  album: DemoAlbum;
}

export interface Artist {
  id: string;
  name: string;
  /** Newest first, as Beat's artist art and pages lead with the newest. */
  albums: DemoAlbum[];
}

export interface Genre {
  id: string;
  name: string;
  albums: DemoAlbum[];
  trackCount: number;
}

export interface Library {
  albums: DemoAlbum[];
  tracks: Track[];
  artists: Artist[];
  genres: Genre[];
}

/** Library order: by artist, then year, then track, as Beat reads the Music library. */
export function makeLibrary(albums: DemoAlbum[]): Library {
  const sorted = [...albums].sort((a, b) => a.artist.localeCompare(b.artist) || a.year - b.year);
  const tracks = sorted.flatMap((album) => album.songs.map((song) => ({ key: `${album.id}/${song.track}`, song, album })));
  const artists = new Map<string, Artist>();
  const genres = new Map<string, Genre>();
  for (const album of sorted) {
    const a = artists.get(album.artist) ?? { id: album.artist, name: album.artist, albums: [] };
    a.albums.unshift(album);
    artists.set(album.artist, a);
    const key = album.genre.toLowerCase();
    const g = genres.get(key) ?? { id: key, name: album.genre, albums: [], trackCount: 0 };
    g.albums.push(album);
    g.trackCount += album.songs.length;
    genres.set(key, g);
  }
  return { albums: sorted, tracks, artists: [...artists.values()], genres: [...genres.values()].sort((a, b) => a.name.localeCompare(b.name)) };
}

// MARK: Fields and rules

export type FieldKey =
  | 'title' | 'artist' | 'albumArtist' | 'album' | 'genre' | 'comments'
  | 'year' | 'rating' | 'playCount' | 'skipCount' | 'duration' | 'trackNumber'
  | 'dateAdded' | 'lastPlayed' | 'lastSkipped';
export type FieldType = 'text' | 'number' | 'date';

/** Beat's fields that the showcase library has values for, with Beat's titles. */
export const fields: { key: FieldKey; title: string; type: FieldType; aggregate: 'sum' | 'average' | 'min' | 'max' }[] = [
  { key: 'title', title: 'Title', type: 'text', aggregate: 'max' },
  { key: 'artist', title: 'Artist', type: 'text', aggregate: 'max' },
  { key: 'albumArtist', title: 'Album Artist', type: 'text', aggregate: 'max' },
  { key: 'album', title: 'Album', type: 'text', aggregate: 'max' },
  { key: 'genre', title: 'Genre', type: 'text', aggregate: 'max' },
  { key: 'comments', title: 'Comments', type: 'text', aggregate: 'max' },
  { key: 'year', title: 'Year', type: 'number', aggregate: 'max' },
  { key: 'rating', title: 'Rating (Stars)', type: 'number', aggregate: 'average' },
  { key: 'playCount', title: 'Plays', type: 'number', aggregate: 'sum' },
  { key: 'skipCount', title: 'Skips', type: 'number', aggregate: 'sum' },
  { key: 'duration', title: 'Time (Seconds)', type: 'number', aggregate: 'sum' },
  { key: 'trackNumber', title: 'Track Number', type: 'number', aggregate: 'min' },
  { key: 'dateAdded', title: 'Date Added', type: 'date', aggregate: 'max' },
  { key: 'lastPlayed', title: 'Last Played', type: 'date', aggregate: 'max' },
  { key: 'lastSkipped', title: 'Last Skipped', type: 'date', aggregate: 'max' },
];
export const field = (key: FieldKey) => fields.find((f) => f.key === key)!;

export type Operator =
  | 'is' | 'isNot' | 'contains' | 'doesNotContain' | 'beginsWith' | 'endsWith'
  | 'greaterThan' | 'lessThan' | 'inRange'
  | 'inLast' | 'notInLast' | 'before' | 'after';

export const operatorTitles: Record<Operator, string> = {
  is: 'is', isNot: 'is not', contains: 'contains', doesNotContain: 'does not contain', beginsWith: 'begins with',
  endsWith: 'ends with', greaterThan: 'is greater than', lessThan: 'is less than', inRange: 'is in the range',
  inLast: 'is in the last', notInLast: 'is not in the last', before: 'is before', after: 'is after',
};

export const operators: Record<FieldType, Operator[]> = {
  text: ['is', 'isNot', 'contains', 'doesNotContain', 'beginsWith', 'endsWith'],
  number: ['is', 'isNot', 'greaterThan', 'lessThan', 'inRange'],
  date: ['inLast', 'notInLast', 'before', 'after'],
};

export type DateUnit = 'days' | 'weeks' | 'months' | 'years';
const unitDays: Record<DateUnit, number> = { days: 1, weeks: 7, months: 30.44, years: 365.25 };

export type RuleValue =
  | { kind: 'text'; text: string }
  | { kind: 'number'; number: number }
  | { kind: 'range'; low: number; high: number }
  | { kind: 'relative'; count: number; unit: DateUnit }
  /** A day, as days before today (the showcase library's dates are kept that way). */
  | { kind: 'date'; daysAgo: number };

export interface Rule {
  type: 'rule';
  id: string;
  field: FieldKey;
  op: Operator;
  value: RuleValue;
}

export type Match = 'all' | 'any' | 'none';

export interface RuleGroup {
  type: 'group';
  id: string;
  match: Match;
  nodes: (Rule | RuleGroup)[];
}

let nextID = 0;
export const newID = () => `x${nextID++}`;

/** As `RuleValue.defaultValue`: empty text, 0 (4 stars, the year 2000), the last 30 days, or today. */
export function defaultValue(key: FieldKey, op: Operator): RuleValue {
  const type = field(key).type;
  if (type === 'text') return { kind: 'text', text: '' };
  if (type === 'number') {
    if (op === 'inRange') return { kind: 'range', low: key === 'year' ? 1990 : 0, high: key === 'year' ? 1999 : 10 };
    return { kind: 'number', number: key === 'rating' ? 4 : key === 'year' ? 2000 : 0 };
  }
  return op === 'inLast' || op === 'notInLast' ? { kind: 'relative', count: 30, unit: 'days' } : { kind: 'date', daysAgo: 0 };
}

/** As `Rule.make(field:)`: text fields start with "contains", the rest with their first operator. */
export function makeRule(key: FieldKey): Rule {
  const op = field(key).type === 'text' ? 'contains' : operators[field(key).type][0];
  return { type: 'rule', id: newID(), field: key, op, value: defaultValue(key, op) };
}

// MARK: Steps

export type ResultKind = 'songs' | 'albums' | 'artists' | 'genres';
export const resultKinds: { key: ResultKind; title: string }[] = [
  { key: 'songs', title: 'Songs' }, { key: 'albums', title: 'Albums' }, { key: 'artists', title: 'Artists' }, { key: 'genres', title: 'Genres' },
];

/** A sort field the user defines, as Beat's CustomField: a value pulled out of a text tag, like the catalog number in
 *  "Nightline Records [NLR-030]". Sort keys carry the whole definition, so a filter stays self-contained. */
export interface CustomField {
  id: string;
  name: string;
  source: FieldKey;
  extraction: { kind: 'parentheses' } | { kind: 'brackets' } | { kind: 'pattern'; pattern: string };
}

/** The text fields a custom field can read (Beat's, less the ones the showcase library has no values for). */
export const customFieldSources: FieldKey[] = ['album', 'title', 'artist', 'albumArtist', 'comments', 'genre'];

export const isCustom = (f: SortField | undefined): f is CustomField => typeof f === 'object';

export function customFieldIsValid(f: CustomField) {
  if (f.extraction.kind !== 'pattern') return true;
  if (!f.extraction.pattern) return false;
  try { new RegExp(f.extraction.pattern); return true; } catch { return false; }
}

function lastEnclosed(text: string, open: string, close: string) {
  const end = text.lastIndexOf(close);
  const start = end > 0 ? text.lastIndexOf(open, end - 1) : -1;
  const value = start >= 0 ? text.slice(start + 1, end).trim() : '';
  return value || undefined;
}

/** Builds the extraction once, compiling any pattern. Undefined for no match, an empty match or an invalid pattern;
 *  a pattern uses its first capture group if it has one, else the whole match, and ignores case. */
export function extractor(f: CustomField): (t: Track) => string | undefined {
  const e = f.extraction;
  if (e.kind === 'parentheses') return (t) => lastEnclosed(textValue(f.source, t), '(', ')');
  if (e.kind === 'brackets') return (t) => lastEnclosed(textValue(f.source, t), '[', ']');
  let regex: RegExp;
  try { regex = new RegExp(e.pattern, 'i'); } catch { return () => undefined; }
  if (!e.pattern) return () => undefined;
  return (t) => {
    const m = regex.exec(textValue(f.source, t));
    const value = (m ? (m.length > 1 && m[1] !== undefined ? m[1] : m[0]) : '').trim();
    return value || undefined;
  };
}

export type SortField = FieldKey | 'random' | CustomField;

export interface SortKey {
  /** A field, 'random', or a custom field. */
  field: SortField;
  ascending: boolean;
}

export type LimitUnit = 'songs' | 'albums' | 'artists' | 'genres' | 'minutes' | 'hours';
export const limitUnits: LimitUnit[] = ['songs', 'albums', 'artists', 'genres', 'minutes', 'hours'];

export type Step =
  | { kind: 'filter'; id: string; group: RuleGroup }
  | { kind: 'sort'; id: string; keys: SortKey[] }
  | { kind: 'limit'; id: string; count: number; unit: LimitUnit };

export interface SmartFilter {
  name: string;
  output: ResultKind;
  steps: Step[];
}

/** Beat's direction names for a sort: A to Z, Oldest First, Lowest First. */
export function orderLabels(key: SortField): { ascending: string; descending: string } | undefined {
  if (key === 'random') return undefined;
  if (isCustom(key)) return { ascending: 'A to Z', descending: 'Z to A' };
  const type = field(key).type;
  if (type === 'text') return { ascending: 'A to Z', descending: 'Z to A' };
  if (type === 'date') return { ascending: 'Oldest First', descending: 'Newest First' };
  return { ascending: 'Lowest First', descending: 'Highest First' };
}

// MARK: Appearance

export type Layout = 'shelf' | 'grid' | 'list' | 'coverFlow' | 'timeline';
export type Size = 'small' | 'medium' | 'large';
export type Spacing = 'compact' | 'regular' | 'roomy';
export type Fill = 'across' | 'down';

export const layoutTitles: Record<Layout, string> = { shelf: 'Shelf', grid: 'Grid', list: 'List', coverFlow: 'Cover Flow', timeline: 'Timeline' };

export interface Appearance {
  layout: Layout;
  size: Size;
  /** Shelf: rows scrolling sideways together; grid: rows shown (0 is All); list: rows per column (0 is All). */
  rows: number;
  columns: number;
  spacing: Spacing;
  fill?: Fill;
  newestFirst?: boolean;
  showHeader: boolean;
  showPlayButtons: boolean;
  showFooter: boolean;
  sortOverride?: SortKey;
}

/** Songs show as a shelf or a list; artists and genres also as a grid; albums also as Cover Flow or a timeline. */
export function layoutsFor(output: ResultKind): Layout[] {
  switch (output) {
    case 'songs': return ['shelf', 'list'];
    case 'albums': return ['shelf', 'grid', 'list', 'coverFlow', 'timeline'];
    default: return ['shelf', 'grid', 'list'];
  }
}

export function defaultRows(layout: Layout, output: ResultKind) {
  switch (layout) {
    case 'shelf': return output === 'songs' ? 4 : 1;
    case 'grid': return 2;
    case 'list': return 10;
    default: return 1;
  }
}

export function rowRange(layout: Layout, output: ResultKind): [number, number] {
  switch (layout) {
    case 'shelf': return output === 'songs' ? [1, 6] : [1, 3];
    case 'grid': return [1, 6];
    case 'list': return [1, 25];
    case 'coverFlow': return [1, 1];
    case 'timeline': return [1, 4];
  }
}

export const allowsAllRows = (layout: Layout) => layout === 'grid' || layout === 'list';
export const effectiveFill = (a: Appearance): Fill => a.fill ?? (a.layout === 'list' ? 'down' : 'across');

export function defaultAppearance(output: ResultKind): Appearance {
  return { layout: 'shelf', size: 'medium', rows: defaultRows('shelf', output), columns: 1, spacing: 'regular', showHeader: true, showPlayButtons: true, showFooter: true };
}

/** Tile widths by Size, as `ElementAppearance.Size.tileWidth`. */
export function tileWidth(size: Size, kind: ResultKind, compact: boolean) {
  if (compact && kind !== 'songs') return { small: 100, medium: 150, large: 300 }[size];
  const widths = { albums: [132, 168, 210], artists: [110, 140, 176], genres: [150, 180, 220], songs: [260, 300, 360] }[kind];
  return widths[['small', 'medium', 'large'].indexOf(size)];
}

export const itemGap = (s: Spacing) => ({ compact: 10, regular: 18, roomy: 28 }[s]);
export const elementPadding = (s: Spacing) => ({ compact: 0, regular: 6, roomy: 14 }[s]);

export interface Element {
  id: string;
  filter: SmartFilter;
  appearance: Appearance;
}

// MARK: Engine

function fold(text: string) {
  return text.normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase();
}

export function textValue(key: FieldKey, t: Track): string {
  switch (key) {
    case 'title': return t.song.title;
    case 'artist': case 'albumArtist': return t.album.artist;
    case 'album': return t.album.title;
    case 'genre': return t.album.genre;
    case 'comments': return t.album.comments ?? '';
    default: return '';
  }
}

function numberValue(key: FieldKey, t: Track): number {
  switch (key) {
    case 'year': return t.album.year;
    case 'rating': return 0;
    case 'playCount': return t.song.plays;
    case 'skipCount': return t.song.skips;
    case 'duration': return t.song.duration;
    case 'trackNumber': return t.song.track;
    default: return 0;
  }
}

/** Days ago, or undefined for a date the song doesn't have (never played). */
function dateValue(key: FieldKey, t: Track): number | undefined {
  switch (key) {
    case 'dateAdded': return t.album.addedDaysAgo;
    case 'lastPlayed': return t.song.lastPlayedDaysAgo;
    case 'lastSkipped': return t.song.lastSkippedDaysAgo;
    default: return undefined;
  }
}

function test(rule: Rule, t: Track): boolean {
  const type = field(rule.field).type;
  const v = rule.value;
  if (type === 'text') {
    const text = fold(textValue(rule.field, t));
    const wanted = fold(v.kind === 'text' ? v.text : '');
    switch (rule.op) {
      case 'is': return text === wanted;
      case 'isNot': return text !== wanted;
      case 'contains': return text.includes(wanted);
      case 'doesNotContain': return !text.includes(wanted);
      case 'beginsWith': return text.startsWith(wanted);
      case 'endsWith': return text.endsWith(wanted);
      default: return false;
    }
  }
  if (type === 'number') {
    const n = numberValue(rule.field, t);
    if (rule.op === 'inRange' && v.kind === 'range') return n >= Math.min(v.low, v.high) && n <= Math.max(v.low, v.high);
    const wanted = v.kind === 'number' ? v.number : 0;
    switch (rule.op) {
      case 'is': return n === wanted;
      case 'isNot': return n !== wanted;
      case 'greaterThan': return n > wanted;
      case 'lessThan': return n < wanted;
      default: return false;
    }
  }
  // A missing date (never played) is never "in the last N", and always "not in the last N".
  const daysAgo = dateValue(rule.field, t);
  if (rule.op === 'inLast' || rule.op === 'notInLast') {
    const span = v.kind === 'relative' ? v.count * unitDays[v.unit] : 0;
    const within = daysAgo !== undefined && daysAgo <= span;
    return rule.op === 'inLast' ? within : !within;
  }
  if (daysAgo === undefined || v.kind !== 'date') return false;
  return rule.op === 'before' ? daysAgo > v.daysAgo : daysAgo < v.daysAgo;
}

function matches(group: RuleGroup, t: Track): boolean {
  if (group.nodes.length === 0) return true;
  const results = group.nodes.map((n) => (n.type === 'rule' ? test(n, t) : matches(n, t)));
  switch (group.match) {
    case 'all': return results.every(Boolean);
    case 'any': return results.some(Boolean);
    case 'none': return !results.some(Boolean);
  }
}

const groupKey = (kind: ResultKind | LimitUnit, t: Track) =>
  kind === 'albums' ? t.album.id : kind === 'artists' ? t.album.artist : kind === 'genres' ? t.album.genre.toLowerCase() : t.key;

/** Seeded per element and day, as Beat's Random is stable within a day. */
function seededRandom(seed: string) {
  let h = 2166136261;
  for (const c of seed + new Date().toDateString()) h = Math.imul(h ^ c.charCodeAt(0), 16777619);
  return () => {
    h = Math.imul(h ^ (h >>> 15), 2246822507);
    h = Math.imul(h ^ (h >>> 13), 3266489909);
    return ((h ^= h >>> 16) >>> 0) / 4294967296;
  };
}

type SortValue = number | string | undefined;

function sortValue(key: FieldKey, members: Track[]): SortValue {
  const f = field(key);
  if (f.type === 'text') return members.length ? textValue(key, members[0]) : '';
  if (f.type === 'date') {
    // Newer is larger: a date's value is minus its days ago. A song never played has none.
    const values = members.map((t) => dateValue(key, t)).filter((d): d is number => d !== undefined).map((d) => -d);
    return values.length ? (f.aggregate === 'min' ? Math.min(...values) : Math.max(...values)) : undefined;
  }
  const values = members.map((t) => numberValue(key, t));
  if (!values.length) return undefined;
  switch (f.aggregate) {
    case 'sum': return values.reduce((a, b) => a + b, 0);
    case 'average': return values.reduce((a, b) => a + b, 0) / values.length;
    case 'min': return Math.min(...values);
    case 'max': return Math.max(...values);
  }
}

/** Missing values sort last in either direction. */
function compare(a: SortValue, b: SortValue, ascending: boolean) {
  if (a === undefined && b === undefined) return 0;
  if (a === undefined) return 1;
  if (b === undefined) return -1;
  const r = typeof a === 'string' ? a.localeCompare(b as string, undefined, { numeric: true }) : (a as number) - (b as number);
  return r === 0 ? 0 : (r < 0) === ascending ? -1 : 1;
}

/** Sorts songs, or for album/artist/genre results the groups by their combined value, each group's songs together. */
function sort(tracks: Track[], keys: SortKey[], kind: ResultKind, random: () => number): Track[] {
  if (!keys.length) return tracks;
  const order: string[] = [];
  const groups = new Map<string, Track[]>();
  for (const t of tracks) {
    const k = kind === 'songs' ? t.key : groupKey(kind, t);
    if (!groups.has(k)) order.push(k);
    groups.set(k, [...(groups.get(k) ?? []), t]);
  }
  // A custom field's value is its first song's (as in Beat); built once per key, so a pattern compiles once.
  const extractors = keys.map((key) => (isCustom(key.field) ? extractor(key.field) : undefined));
  const values = new Map(order.map((k) => [k, keys.map((key, n): SortValue => {
    if (key.field === 'random') return random();
    if (isCustom(key.field)) return extractors[n]!(groups.get(k)![0]);
    return sortValue(key.field, groups.get(k)!);
  })]));
  const sorted = order.map((k, i) => ({ k, i })).sort((x, y) => {
    for (let n = 0; n < keys.length; n++) {
      const r = compare(values.get(x.k)![n], values.get(y.k)![n], keys[n].ascending);
      if (r) return r;
    }
    return x.i - y.i;
  });
  return sorted.flatMap(({ k }) => groups.get(k)!);
}

function limit(tracks: Track[], count: number, unit: LimitUnit): Track[] {
  const n = Math.max(count, 0);
  if (unit === 'songs') return tracks.slice(0, n);
  if (unit === 'minutes' || unit === 'hours') {
    const budget = n * (unit === 'hours' ? 3600 : 60);
    const kept: Track[] = [];
    let total = 0;
    for (const t of tracks) {
      if (total + t.song.duration > budget) break;
      total += t.song.duration;
      kept.push(t);
    }
    return kept;
  }
  const allowed = new Set<string>();
  return tracks.filter((t) => {
    const k = groupKey(unit, t);
    if (allowed.has(k)) return true;
    if (allowed.size >= n) return false;
    allowed.add(k);
    return true;
  });
}

export interface FilterResult {
  kind: ResultKind;
  tracks: Track[];
  albums: DemoAlbum[];
  artists: Artist[];
  genres: Genre[];
  count: number;
}

export function evaluate(filter: SmartFilter, library: Library, seed: string, override?: SortKey): FilterResult {
  let tracks = library.tracks;
  const random = seededRandom(seed);
  for (const step of filter.steps) {
    if (step.kind === 'filter') tracks = tracks.filter((t) => matches(step.group, t));
    else if (step.kind === 'sort') tracks = sort(tracks, step.keys, filter.output, random);
    else tracks = limit(tracks, step.count, step.unit);
  }
  // Appearance's Order reorders what the rules return, after every step.
  if (override) tracks = sort(tracks, [override], filter.output, random);
  const unique = <T>(values: T[]) => [...new Set(values)];
  const result: FilterResult = { kind: filter.output, tracks, albums: [], artists: [], genres: [], count: 0 };
  if (filter.output === 'albums') {
    const ids = unique(tracks.map((t) => t.album.id));
    result.albums = ids.map((id) => library.albums.find((a) => a.id === id)!);
    const position = new Map(ids.map((id, i) => [id, i]));
    result.tracks = [...tracks].sort((a, b) => position.get(a.album.id)! - position.get(b.album.id)! || a.song.track - b.song.track);
  } else if (filter.output === 'artists') {
    result.artists = unique(tracks.map((t) => t.album.artist)).map((name) => library.artists.find((a) => a.id === name)!);
  } else if (filter.output === 'genres') {
    result.genres = unique(tracks.map((t) => t.album.genre.toLowerCase())).map((id) => library.genres.find((g) => g.id === id)!);
  }
  result.count = { songs: result.tracks.length, albums: result.albums.length, artists: result.artists.length, genres: result.genres.length }[filter.output];
  return result;
}

// MARK: Presets and the sidebar

const filterStep = (match: Match, nodes: (Rule | RuleGroup)[]): Step => ({ kind: 'filter', id: newID(), group: { type: 'group', id: newID(), match, nodes } });
const rule = (key: FieldKey, op: Operator, value: RuleValue): Rule => ({ type: 'rule', id: newID(), field: key, op, value });
const sortStep = (...keys: SortKey[]): Step => ({ kind: 'sort', id: newID(), keys });
const limitStep = (count: number, unit: LimitUnit): Step => ({ kind: 'limit', id: newID(), count, unit });
const element = (name: string, output: ResultKind, steps: Step[], appearance?: Partial<Appearance>): Element =>
  ({ id: newID(), filter: { name, output, steps }, appearance: { ...defaultAppearance(output), ...appearance } });

/** Beat's built-in Home, as `Presets.all`. */
export function homeElements(): Element[] {
  return [
    element('Recently Added', 'albums', [sortStep({ field: 'dateAdded', ascending: false }), limitStep(24, 'albums')]),
    element('Recently Played', 'albums', [
      filterStep('all', [rule('lastPlayed', 'inLast', { kind: 'relative', count: 3, unit: 'months' })]),
      sortStep({ field: 'lastPlayed', ascending: false }), limitStep(24, 'albums'),
    ]),
    element('Random Albums', 'albums', [sortStep({ field: 'random', ascending: true }), limitStep(16, 'albums')]),
    element('Most Played', 'songs', [
      filterStep('all', [rule('playCount', 'greaterThan', { kind: 'number', number: 0 })]),
      sortStep({ field: 'playCount', ascending: false }), limitStep(40, 'songs'),
    ]),
    element('Forgotten Favorites', 'songs', [
      filterStep('all', [
        { type: 'group', id: newID(), match: 'any', nodes: [
          rule('rating', 'greaterThan', { kind: 'number', number: 3 }),
          rule('playCount', 'greaterThan', { kind: 'number', number: 9 }),
        ] },
        rule('lastPlayed', 'notInLast', { kind: 'relative', count: 6, unit: 'months' }),
      ]),
      sortStep({ field: 'random', ascending: true }), limitStep(40, 'songs'),
    ]),
    element('Top Artists', 'artists', [sortStep({ field: 'playCount', ascending: false }), limitStep(16, 'artists')]),
    element('Never Played', 'albums', [
      filterStep('all', [rule('playCount', 'is', { kind: 'number', number: 0 })]),
      sortStep({ field: 'random', ascending: true }), limitStep(16, 'albums'),
    ]),
    element('Top Rated', 'songs', [
      filterStep('all', [rule('rating', 'greaterThan', { kind: 'number', number: 3 })]),
      sortStep({ field: 'rating', ascending: false }, { field: 'playCount', ascending: false }), limitStep(40, 'songs'),
    ]),
    element('Your Genres', 'genres', [sortStep({ field: 'playCount', ascending: false }), limitStep(16, 'genres')]),
  ];
}

/** A new element, as `EditableFilter.new()` with the default appearance. */
export function newElement(): Element {
  return element('New Smart Filter', 'songs', [
    filterStep('all', [makeRule('artist')]),
    sortStep({ field: 'dateAdded', ascending: false }),
    limitStep(50, 'songs'),
  ]);
}

export interface PageNode {
  kind: 'page';
  id: string;
  name: string;
  symbol: string;
  elements: Element[];
}

export interface FolderNode {
  kind: 'folder';
  id: string;
  name: string;
  symbol: string;
  children: Node[];
}

/** The sidebar tree: folders and pages mixed freely at any level; only pages are leaves. */
export type Node = PageNode | FolderNode;

/** Home, plus a folder of pages someone might make, so the demo shows folders from the start. */
export function startingTree(): Node[] {
  return [
    { kind: 'page', id: 'home', name: 'Home', symbol: 'house', elements: homeElements() },
    {
      kind: 'folder', id: 'moods', name: 'Moods', symbol: 'folder', children: [
        { kind: 'page', id: 'late', name: 'Late Nights', symbol: 'moon', elements: [
          element('After Dark', 'albums', [
            filterStep('any', [
              rule('genre', 'is', { kind: 'text', text: 'Jazz' }), rule('genre', 'is', { kind: 'text', text: 'Ambient' }),
              rule('genre', 'is', { kind: 'text', text: 'Soul' }),
            ]),
            sortStep({ field: 'year', ascending: true }),
          ], { layout: 'coverFlow', rows: 1 }),
        ] },
        { kind: 'page', id: 'years', name: 'Through the Years', symbol: 'calendar', elements: [
          element('Every Album', 'albums', [sortStep({ field: 'year', ascending: true })], { layout: 'timeline', rows: 1 }),
        ] },
      ],
    },
    // One label's releases in catalog order, which no built-in field gives: reissues sit among the new records.
    { kind: 'page', id: 'label', name: 'Nightline Records', symbol: 'opticaldisc', elements: [
      element('Nightline Records', 'albums', [
        filterStep('all', [rule('comments', 'contains', { kind: 'text', text: 'Nightline Records' })]),
        sortStep({ field: catalogNumber, ascending: true }),
      ], { layout: 'list', rows: 6, columns: 2 }),
    ] },
  ];
}

/** The custom field the Nightline Records page sorts by. */
export const catalogNumber: CustomField = { id: 'catalog', name: 'Catalog No.', source: 'comments', extraction: { kind: 'brackets' } };

export function findNode(tree: Node[], id: string): Node | undefined {
  for (const n of tree) {
    if (n.id === id) return n;
    if (n.kind === 'folder') {
      const found = findNode(n.children, id);
      if (found) return found;
    }
  }
}

/** The tree with one node changed (or removed, when `change` returns undefined). */
export function updateNode(tree: Node[], id: string, change: (node: Node) => Node | undefined): Node[] {
  return tree.flatMap((n) => {
    if (n.id === id) {
      const changed = change(n);
      return changed ? [changed] : [];
    }
    return n.kind === 'folder' ? [{ ...n, children: updateNode(n.children, id, change) }] : [n];
  });
}

/** Inserts `node` inside a folder (at its end), below a node (after it, at its level), or at the top level's end. */
export function insertNode(tree: Node[], node: Node, place: { inside?: string; below?: string }): Node[] {
  if (place.inside) return updateNode(tree, place.inside, (f) => (f.kind === 'folder' ? { ...f, children: [...f.children, node] } : f));
  if (place.below) {
    const walk = (nodes: Node[]): Node[] => nodes.flatMap((n) =>
      n.id === place.below ? [n, node] : n.kind === 'folder' ? [{ ...n, children: walk(n.children) }] : [n]);
    return walk(tree);
  }
  return [...tree, node];
}

/** A copy with new IDs throughout, for Duplicate. */
export function duplicate<T extends Node | Element>(value: T): T {
  const copy = JSON.parse(JSON.stringify(value));
  const renew = (v: any) => {
    if (v && typeof v === 'object') {
      if ('id' in v) v.id = newID();
      Object.values(v).forEach(renew);
    }
  };
  renew(copy);
  return copy;
}

// MARK: Colours

export function luminance(hex: string) {
  const v = parseInt(hex.slice(1), 16);
  const [r, g, b] = [(v >> 16) & 255, (v >> 8) & 255, v & 255].map((c) => {
    const s = c / 255;
    return s <= 0.03928 ? s / 12.92 : ((s + 0.055) / 1.055) ** 2.4;
  });
  return 0.2126 * r + 0.7152 * g + 0.0722 * b;
}

const contrast = (a: string, b: string) => {
  const [x, y] = [luminance(a), luminance(b)];
  return (Math.max(x, y) + 0.05) / (Math.min(x, y) + 0.05);
};

/** White reads better than black on the cover's background: the page uses dark appearance. */
export const isDark = (p: Palette) => contrast(p.background, '#FFFFFF') > contrast(p.background, '#000000');

function rgb(hex: string) {
  const v = parseInt(hex.slice(1), 16);
  return [(v >> 16) & 255, (v >> 8) & 255, v & 255].map((c) => c / 255);
}
const toHex = (c: number[]) => '#' + c.map((x) => Math.round(Math.max(0, Math.min(1, x)) * 255).toString(16).padStart(2, '0')).join('');
const over = (top: string, bottom: string, opacity: number) => {
  const [a, b] = [rgb(top), rgb(bottom)];
  return toHex(a.map((x, i) => x * opacity + b[i] * (1 - opacity)));
};
const saturation = (hex: string) => {
  const c = rgb(hex);
  const high = Math.max(...c);
  return high === 0 ? 0 : (high - Math.min(...c)) / high;
};

/** The bar's progress colour, as `BarTint`: the cover's more colourful of background and primary, made readable on
 *  the window; undefined (the accent) for a grey cover. */
export function barTint(p: Palette, dark: boolean): string | undefined {
  const pick = saturation(p.background) >= saturation(p.primary) ? p.background : p.primary;
  if (saturation(pick) < 0.15) return undefined;
  const background = dark ? '#292929' : '#F5F5F5';
  const toward = dark ? '#FFFFFF' : '#000000';
  let result = pick;
  for (let step = 0; step <= 10; step++) {
    result = over(toward, pick, step / 10);
    if (contrast(result, background) >= 3) break;
  }
  return result;
}

/** Colours for the visualizer scenes, which draw their own dark ground, as `SceneColours`. */
export function sceneColours(p?: Palette) {
  if (!p) return { accent: '#8C99F2', light: '#E6EBFF', deep: '#0F0F17' };
  const showing = [p.primary, p.secondary].filter((c) => contrast(c, '#000000') >= 3);
  const accent = showing[0] ?? over('#FFFFFF', p.primary, 0.6);
  const light = showing[1] ?? over('#FFFFFF', accent, 0.55);
  return { accent, light, deep: over('#000000', p.background, 0.7) };
}

export const formatTime = (seconds: number) => `${Math.floor(seconds / 60)}:${String(Math.floor(seconds % 60)).padStart(2, '0')}`;
export const counted = (n: number, noun: string) => `${n.toLocaleString()} ${noun}${n === 1 ? '' : 's'}`;

/** "40 min", or "2 h 50 min", as the editor's preview summary. */
export function duration(seconds: number) {
  const minutes = Math.floor(seconds / 60);
  return minutes >= 60 ? `${Math.floor(minutes / 60)} h ${minutes % 60} min` : `${minutes} min`;
}
