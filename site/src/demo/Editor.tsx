// The element editor, after Beat's (ElementEditor+macOS, FilterEditorSheet, RuleEditors, FilterAppearanceForm): the
// name across the top, the live preview beside a Rules / Appearance panel, Delete, Cancel and Save along the bottom.
// Rules: Find, then steps run top to bottom (Filter, Sort, Limit), each movable and removable, and Add Step. On a
// phone: one sheet, Cancel and Save in its bar with an Edit / Preview switch between. (Beat opens each rule on its own
// page there; the demo edits them in place.)
import { createContext, useContext, useEffect, useMemo, useState, type ReactNode } from 'react';
import { Demo, useDemo } from './context';
import { Icon } from './Icon';
import { Confirm, ElementView } from './Pages';
import {
  allowsAllRows, counted, customFieldIsValid, customFieldSources, defaultRows, defaultValue, duration, effectiveFill, evaluate,
  extractor, field, fields, isCustom, layoutsFor, layoutTitles, limitUnits, makeRule, newID, operators, operatorTitles, orderLabels,
  resultKinds, rowRange, textValue,
  type Appearance, type CustomField, type Element, type FieldKey, type LimitUnit, type Match, type Operator, type ResultKind,
  type Rule, type RuleGroup, type RuleValue, type SortField, type SortKey, type Step, type Track,
} from './model';

const control = 'rounded-md border border-line bg-bg px-1.5 py-[3px] text-[12px] text-ink outline-none focus:border-accent';

function Segmented<T extends string | number | boolean>({ value, options, onChange, disabled }: {
  value: T; options: { value: T; title: string }[]; onChange: (v: T) => void; disabled?: boolean;
}) {
  return (
    <div className={`inline-flex rounded-md bg-ink/[0.07] p-[2px] ${disabled ? 'pointer-events-none opacity-40' : ''}`} role="radiogroup">
      {options.map((o) => (
        <button key={String(o.value)} role="radio" aria-checked={value === o.value} onClick={() => onChange(o.value)}
                className={`cursor-pointer rounded-[5px] px-2.5 py-[2px] text-[12px] ${value === o.value ? 'bg-raised font-medium shadow-sm' : 'text-soft hover:text-ink'}`}>
          {o.title}
        </button>
      ))}
    </div>
  );
}

function SmallButton({ icon, title, onClick, disabled }: { icon: string; title: string; onClick: () => void; disabled?: boolean }) {
  return (
    <button onClick={onClick} disabled={disabled} title={title} aria-label={title} className="cursor-pointer text-soft hover:text-ink disabled:opacity-30">
      <Icon name={icon} className="size-[15px]" />
    </button>
  );
}

function Stars({ value, onChange }: { value: number; onChange: (n: number) => void }) {
  return (
    <span className="inline-flex gap-0.5 text-accent">
      {[1, 2, 3, 4, 5].map((n) => (
        <button key={n} onClick={() => onChange(n)} className="cursor-pointer text-[15px] leading-none" aria-label={`${n} stars`}>{n <= value ? '★' : '☆'}</button>
      ))}
    </span>
  );
}

/** The value a rule tests against, shaped by its field and operator. */
function ValueEditor({ rule, onChange }: { rule: Rule; onChange: (v: RuleValue) => void }) {
  const { library } = useDemo();
  const v = rule.value;
  if (v.kind === 'text') {
    // Genre and artist suggest the library's own, as Beat's text fields complete.
    const suggestions = rule.field === 'genre' ? library.genres.map((g) => g.name)
      : rule.field === 'artist' || rule.field === 'albumArtist' ? library.artists.map((a) => a.name) : [];
    const list = suggestions.length ? `${rule.id}-values` : undefined;
    return (
      <>
        <input className={`${control} w-48`} value={v.text} list={list} placeholder="Text" onChange={(e) => onChange({ kind: 'text', text: e.target.value })} aria-label="Value" />
        {list && <datalist id={list}>{suggestions.map((s) => <option key={s} value={s} />)}</datalist>}
      </>
    );
  }
  if (v.kind === 'number') {
    if (rule.field === 'rating') return <Stars value={v.number} onChange={(n) => onChange({ kind: 'number', number: n })} />;
    return <input type="number" className={`${control} w-24 text-right`} value={v.number} onChange={(e) => onChange({ kind: 'number', number: Number(e.target.value) })} aria-label="Value" />;
  }
  if (v.kind === 'range') {
    return (
      <span className="flex items-center gap-1.5 text-[12px]">
        <input type="number" className={`${control} w-20 text-right`} value={v.low} onChange={(e) => onChange({ ...v, low: Number(e.target.value) })} aria-label="From" />
        <span className="text-soft">to</span>
        <input type="number" className={`${control} w-20 text-right`} value={v.high} onChange={(e) => onChange({ ...v, high: Number(e.target.value) })} aria-label="To" />
      </span>
    );
  }
  if (v.kind === 'relative') {
    return (
      <span className="flex flex-wrap items-center gap-1.5">
        <input type="number" min={1} className={`${control} w-20 text-right`} value={v.count} onChange={(e) => onChange({ ...v, count: Number(e.target.value) })} aria-label="Count" />
        <select className={control} value={v.unit} onChange={(e) => onChange({ ...v, unit: e.target.value as typeof v.unit })} aria-label="Unit">
          {(['days', 'weeks', 'months', 'years'] as const).map((u) => <option key={u} value={u}>{u}</option>)}
        </select>
      </span>
    );
  }
  const date = new Date(Date.now() - v.daysAgo * 86_400_000).toISOString().slice(0, 10);
  return (
    <input type="date" className={control} value={date} aria-label="Date"
           onChange={(e) => onChange({ kind: 'date', daysAgo: Math.max(0, Math.round((Date.now() - new Date(e.target.value).getTime()) / 86_400_000)) })} />
  );
}

function RuleRow({ rule, onChange, onDuplicate, onRemove }: { rule: Rule; onChange: (r: Rule) => void; onDuplicate: () => void; onRemove: () => void }) {
  const setField = (key: FieldKey) => {
    const type = field(key).type;
    const op: Operator = type === 'text' ? 'contains' : operators[type][0];
    const sameType = field(rule.field).type === type;
    onChange({ ...rule, field: key, op: sameType ? rule.op : op, value: sameType ? rule.value : defaultValue(key, op) });
  };
  const setOp = (op: Operator) => {
    const needsNew = (op === 'inRange') !== (rule.op === 'inRange') || ((op === 'inLast' || op === 'notInLast') !== (rule.op === 'inLast' || rule.op === 'notInLast'));
    onChange({ ...rule, op, value: needsNew ? defaultValue(rule.field, op) : rule.value });
  };
  return (
    <div className="space-y-1.5">
      <div className="flex items-center gap-1.5">
        <select className={control} value={rule.field} onChange={(e) => setField(e.target.value as FieldKey)} aria-label="Field">
          {fields.map((f) => <option key={f.key} value={f.key}>{f.title}</option>)}
        </select>
        <select className={control} value={rule.op} onChange={(e) => setOp(e.target.value as Operator)} aria-label="Operator">
          {operators[field(rule.field).type].map((o) => <option key={o} value={o}>{operatorTitles[o]}</option>)}
        </select>
        <div className="flex-1" />
        <SmallButton icon="plus.square.on.square" title="Duplicate Rule" onClick={onDuplicate} />
        <SmallButton icon="minus.circle" title="Remove Rule" onClick={onRemove} />
      </div>
      <ValueEditor rule={rule} onChange={(value) => onChange({ ...rule, value })} />
    </div>
  );
}

/** "Match all / any / none of the following rules:", its rules and nested groups, Add Rule and Add Group. */
function RuleGroupEditor({ group, onChange, onRemove, nested }: { group: RuleGroup; onChange: (g: RuleGroup) => void; onRemove?: () => void; nested?: boolean }) {
  const set = (nodes: RuleGroup['nodes']) => onChange({ ...group, nodes });
  const copy = <T,>(value: T): T => {
    const c = JSON.parse(JSON.stringify(value));
    const renew = (v: any) => { if (v && typeof v === 'object') { if ('id' in v) v.id = newID(); Object.values(v).forEach(renew); } };
    renew(c);
    return c;
  };
  return (
    <div className={`space-y-3 ${nested ? 'rounded-lg border-l-2 border-accent bg-ink/[0.04] p-3' : ''}`}>
      <div className="flex items-center gap-1.5 text-[12px]">
        Match
        <select className={control} value={group.match} onChange={(e) => onChange({ ...group, match: e.target.value as Match })} aria-label="Match">
          <option value="all">all</option><option value="any">any</option><option value="none">none</option>
        </select>
        of the following rules:
        <div className="flex-1" />
        {onRemove && <SmallButton icon="minus.circle" title="Remove Group" onClick={onRemove} />}
      </div>
      {group.nodes.map((node, i) => {
        const replace = (n: RuleGroup['nodes'][number]) => set(group.nodes.map((x, j) => (j === i ? n : x)));
        const remove = () => set(group.nodes.filter((_, j) => j !== i));
        return node.type === 'rule' ? (
          <RuleRow key={node.id} rule={node} onChange={replace} onRemove={remove}
                   onDuplicate={() => set([...group.nodes.slice(0, i + 1), copy(node), ...group.nodes.slice(i + 1)])} />
        ) : (
          <RuleGroupEditor key={node.id} group={node} nested onChange={replace} onRemove={remove} />
        );
      })}
      <div className="flex gap-4 text-[12px] text-soft">
        <button onClick={() => set([...group.nodes, makeRule('artist')])} className="flex cursor-pointer items-center gap-1 hover:text-ink">
          <Icon name="plus.circle" className="size-[15px]" /> Add Rule
        </button>
        <button onClick={() => set([...group.nodes, { type: 'group', id: newID(), match: 'any', nodes: [makeRule('artist')] }])}
                className="flex cursor-pointer items-center gap-1 hover:text-ink">
          <Icon name="plus.square.on.square" className="size-[15px]" /> Add Group
        </button>
      </div>
    </div>
  );
}

/** Opens the custom field sheet from a sort picker; the sheet then hands the new field to `then`. */
const NewCustomField = createContext<(then: (f: CustomField) => void) => void>(() => {});

/** Text reads naturally A to Z; numbers and dates highest or newest first. */
const ascendingFirst = (f: SortField) => f === 'random' || isCustom(f) || field(f).type === 'text';

/** Random, the built-in fields, then a Custom section: the custom fields and New Custom Field…, as Beat's SortFieldPicker. */
function SortFieldSelect({ value, onChange, allowsNone }: { value?: SortField; onChange: (v?: SortField) => void; allowsNone?: boolean }) {
  const { customFields } = useDemo();
  const create = useContext(NewCustomField);
  // A key holding a custom field that has since been deleted still shows it.
  const custom = isCustom(value) && !customFields.some((f) => f.id === value.id) ? [...customFields, value] : customFields;
  const encoded = value === undefined ? '' : isCustom(value) ? `custom:${value.id}` : value;
  return (
    <select className={control} value={encoded} aria-label="Sort by" onChange={(e) => {
      const v = e.target.value;
      if (v === 'new') create((f) => onChange(f));
      else if (v.startsWith('custom:')) onChange(custom.find((f) => f.id === v.slice(7)));
      else onChange((v || undefined) as FieldKey | 'random' | undefined);
    }}>
      {allowsNone && <option value="">As filtered</option>}
      <option value="random">Random</option>
      {fields.map((f) => <option key={f.key} value={f.key}>{f.title}</option>)}
      <optgroup label="Custom">
        {custom.map((f) => <option key={f.id} value={`custom:${f.id}`}>{customFields.includes(f) ? f.name : `${f.name} (deleted)`}</option>)}
        <option value="new">New Custom Field…</option>
      </optgroup>
    </select>
  );
}

type ExtractMode = 'parentheses' | 'brackets' | 'pattern';
const extractModes: { value: ExtractMode; title: string }[] = [
  { value: 'parentheses', title: 'Text in last ( )' }, { value: 'brackets', title: 'Text in last [ ]' }, { value: 'pattern', title: 'Pattern' },
];

/** Creates a custom field, with a live check of what it extracts: how many songs match, and examples, from the
 *  editor's preview first so they're relevant (Beat's CustomFieldSheet). */
function CustomFieldSheet({ samples, onSave, onCancel }: { samples: Track[]; onSave: (f: CustomField) => void; onCancel: () => void }) {
  const { library } = useDemo();
  const [name, setName] = useState('');
  const [source, setSource] = useState<FieldKey>('album');
  const [mode, setMode] = useState<ExtractMode>('parentheses');
  const [pattern, setPattern] = useState('');
  const current: CustomField = {
    id: '', name: name.trim(), source,
    extraction: mode === 'pattern' ? { kind: 'pattern', pattern } : { kind: mode },
  };
  const valid = customFieldIsValid(current);
  const canSave = current.name !== '' && valid;
  const check = useMemo(() => {
    const extract = extractor(current);
    const matches = library.tracks.reduce((n, t) => n + (extract(t) === undefined ? 0 : 1), 0);
    const seen = new Set<string>();
    const examples: { source: string; value?: string }[] = [];
    const add = (t: Track) => {
      const text = textValue(source, t);
      if (examples.length >= 8 || !text || seen.has(text)) return;
      seen.add(text);
      examples.push({ source: text, value: extract(t) });
    };
    samples.forEach(add);
    if (!examples.length) for (const t of library.tracks) { if (extract(t) !== undefined) add(t); if (examples.length === 8) break; }
    return { matches, examples };
  }, [library, samples, source, mode, pattern]);
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => { if (e.key === 'Escape') { e.stopPropagation(); onCancel(); } };
    window.addEventListener('keydown', onKey, true);
    return () => window.removeEventListener('keydown', onKey, true);
  });
  return (
    <div className="fixed inset-0 z-[90] grid place-items-center bg-black/25 p-4" onClick={onCancel}>
      <div className="flex max-h-full w-[400px] max-w-full flex-col overflow-hidden rounded-xl border border-line bg-raised text-ink shadow-2xl"
           onClick={(e) => e.stopPropagation()} role="dialog" aria-label="New Custom Field">
        <div className="min-h-0 flex-1 space-y-4 overflow-y-auto p-4">
          <FormSection footer={mode === 'pattern' ? 'Uses the first match, or its first capture group if the pattern has one. Case doesn’t matter.' : undefined}>
            <FormRow label="Name">
              <input value={name} onChange={(e) => setName(e.target.value)} placeholder="e.g. Catalog No." aria-label="Name" autoFocus
                     className={`${control} w-44`} />
            </FormRow>
            <FormRow label="Source">
              <select className={control} value={source} onChange={(e) => setSource(e.target.value as FieldKey)} aria-label="Source">
                {customFieldSources.map((k) => <option key={k} value={k}>{field(k).title}</option>)}
              </select>
            </FormRow>
            <FormRow label="Extract">
              <select className={control} value={mode} onChange={(e) => setMode(e.target.value as ExtractMode)} aria-label="Extract">
                {extractModes.map((m) => <option key={m.value} value={m.value}>{m.title}</option>)}
              </select>
            </FormRow>
            {mode === 'pattern' && (
              <div className="py-2">
                <input value={pattern} onChange={(e) => setPattern(e.target.value)} placeholder="e.g. NLR-\d+" aria-label="Pattern" spellCheck={false}
                       className={`${control} w-full font-mono`} />
                {pattern && !valid && <p className="mt-1 text-[11px] text-red-500">Not a valid regular expression.</p>}
              </div>
            )}
          </FormSection>
          <FormSection title="Check">
            <p className="py-2 text-[12px] text-soft">Matches {check.matches.toLocaleString()} of {counted(library.tracks.length, 'song')}</p>
            {check.examples.map((x) => (
              <div key={x.source} className="flex items-center justify-between gap-3 py-2 text-[12px]">
                <span className="min-w-0 truncate">{x.source}</span>
                <span className={`shrink-0 font-mono ${x.value === undefined ? 'text-faint' : ''}`}>{x.value ?? 'no match'}</span>
              </div>
            ))}
          </FormSection>
        </div>
        <div className="flex justify-end gap-2 border-t border-line px-3.5 py-3 text-[13px]">
          <button onClick={onCancel} className="cursor-pointer rounded-md bg-ink/[0.08] px-3 py-1 hover:bg-ink/[0.12]">Cancel</button>
          <button onClick={() => onSave({ ...current, id: newID() })} disabled={!canSave}
                  className="cursor-pointer rounded-md bg-accent px-3 py-1 font-medium text-accent-ink disabled:opacity-40">Create</button>
        </div>
      </div>
    </div>
  );
}

function SortKeysEditor({ keys, onChange }: { keys: SortKey[]; onChange: (k: SortKey[]) => void }) {
  return (
    <div className="space-y-2 text-[12px]">
      {keys.map((key, i) => {
        const labels = orderLabels(key.field);
        return (
          <div key={i} className="flex flex-wrap items-center gap-1.5">
            <span className="w-12 text-soft">{i === 0 ? 'Sort by' : 'then by'}</span>
            <SortFieldSelect value={key.field} onChange={(f) => {
              const next = f ?? 'random';
              onChange(keys.map((k, j) => (j === i ? { field: next, ascending: ascendingFirst(next) } : k)));
            }} />
            {labels && (
              <select className={control} value={key.ascending ? 'up' : 'down'} aria-label="Order"
                      onChange={(e) => onChange(keys.map((k, j) => (j === i ? { ...k, ascending: e.target.value === 'up' } : k)))}>
                <option value="down">{labels.descending}</option>
                <option value="up">{labels.ascending}</option>
              </select>
            )}
            {keys.length > 1 && <SmallButton icon="minus.circle" title="Remove Sort Key" onClick={() => onChange(keys.filter((_, j) => j !== i))} />}
          </div>
        );
      })}
      <button onClick={() => onChange([...keys, { field: 'title', ascending: true }])} className="flex cursor-pointer items-center gap-1 text-soft hover:text-ink">
        <Icon name="plus.circle" className="size-[15px]" /> Add Sort Key
      </button>
    </div>
  );
}

function StepCard({ step, output, first, last, onChange, onMove, onRemove }: {
  step: Step; output: ResultKind; first: boolean; last: boolean; onChange: (s: Step) => void; onMove: (by: number) => void; onRemove: () => void;
}) {
  const meta = {
    filter: { icon: 'line.3.horizontal.decrease', title: 'Filter', subtitle: 'keep songs that match' },
    sort: { icon: 'arrow.up.arrow.down', title: 'Sort', subtitle: `order the ${output}` },
    limit: { icon: 'number', title: 'Limit', subtitle: 'keep only the first few' },
  }[step.kind];
  return (
    <div className="space-y-3">
      <div className="flex items-center gap-2">
        <Icon name={meta.icon} className="size-[18px] text-accent" />
        <span className="text-[13px] font-semibold">{meta.title}</span>
        <span className="text-[11px] text-soft">{meta.subtitle}</span>
        <div className="flex-1" />
        <div className="flex gap-2.5">
          <SmallButton icon="chevron.up" title="Move Up" onClick={() => onMove(-1)} disabled={first} />
          <SmallButton icon="chevron.down" title="Move Down" onClick={() => onMove(1)} disabled={last} />
          <SmallButton icon="trash" title="Remove Step" onClick={onRemove} />
        </div>
      </div>
      <div className="pl-3.5">
        {step.kind === 'filter' && <RuleGroupEditor group={step.group} onChange={(group) => onChange({ ...step, group })} />}
        {step.kind === 'sort' && <SortKeysEditor keys={step.keys} onChange={(keys) => onChange({ ...step, keys })} />}
        {step.kind === 'limit' && (
          <div className="flex items-center gap-1.5 text-[12px]">
            <span className="text-soft">Keep the first</span>
            <input type="number" min={1} className={`${control} w-20 text-right`} value={step.count} onChange={(e) => onChange({ ...step, count: Number(e.target.value) })} aria-label="Count" />
            <select className={control} value={step.unit} onChange={(e) => onChange({ ...step, unit: e.target.value as LimitUnit })} aria-label="Unit">
              {limitUnits.map((u) => <option key={u} value={u}>{u}</option>)}
            </select>
          </div>
        )}
      </div>
    </div>
  );
}

function Rules({ element, onChange }: { element: Element; onChange: (e: Element) => void }) {
  const [menu, setMenu] = useState(false);
  const f = element.filter;
  const setSteps = (steps: Step[]) => onChange({ ...element, filter: { ...f, steps } });
  const setOutput = (output: ResultKind) => {
    // A layout this kind can't take falls back to a shelf, as `appearance.fit(to:)`.
    const fits = layoutsFor(output).includes(element.appearance.layout);
    const layout = fits ? element.appearance.layout : 'shelf';
    onChange({ ...element, filter: { ...f, output }, appearance: { ...element.appearance, layout, rows: fits ? element.appearance.rows : defaultRows(layout, output) } });
  };
  const add = (kind: Step['kind']) => {
    setMenu(false);
    const step: Step = kind === 'filter' ? { kind, id: newID(), group: { type: 'group', id: newID(), match: 'all', nodes: [makeRule('artist')] } }
      : kind === 'sort' ? { kind, id: newID(), keys: [{ field: 'title', ascending: true }] }
      : { kind, id: newID(), count: 25, unit: 'songs' };
    setSteps([...f.steps, step]);
  };
  return (
    <div className="space-y-3.5 p-4 text-[12px]">
      <div className="flex items-center gap-2">
        <span className="text-soft">Find</span>
        <Segmented value={f.output} onChange={setOutput} options={resultKinds.map((k) => ({ value: k.key, title: k.title }))} />
      </div>
      <hr className="border-line" />
      <p className="text-[11px] text-soft">Steps run top to bottom</p>
      {f.steps.map((step, i) => (
        <div key={step.id} className="space-y-3.5">
          {i > 0 && <hr className="border-line" />}
          <StepCard step={step} output={f.output} first={i === 0} last={i === f.steps.length - 1}
                    onChange={(s) => setSteps(f.steps.map((x) => (x.id === step.id ? s : x)))}
                    onMove={(by) => { const next = [...f.steps]; next.splice(i + by, 0, ...next.splice(i, 1)); setSteps(next); }}
                    onRemove={() => setSteps(f.steps.filter((x) => x.id !== step.id))} />
        </div>
      ))}
      <div className="relative">
        <button onClick={() => setMenu((m) => !m)} className="flex cursor-pointer items-center gap-1 rounded-md bg-ink/[0.07] px-2.5 py-1 text-[12px] hover:bg-ink/[0.12]">
          <Icon name="plus" className="size-3.5" /> Add Step <Icon name="chevron.down" className="size-3" />
        </button>
        {menu && (
          <div className="absolute top-8 left-0 z-10 w-32 rounded-lg border border-line bg-raised p-1 shadow-xl" role="menu">
            {([['filter', 'Filter', 'line.3.horizontal.decrease'], ['sort', 'Sort', 'arrow.up.arrow.down'], ['limit', 'Limit', 'number']] as const).map(([kind, title, icon]) => (
              <button key={kind} role="menuitem" onClick={() => add(kind)} className="flex w-full cursor-pointer items-center gap-2 rounded px-2 py-1 text-left hover:bg-accent hover:text-accent-ink">
                <Icon name={icon} className="size-3.5" /> {title}
              </button>
            ))}
          </div>
        )}
      </div>
    </div>
  );
}

function FormSection({ title, footer, children }: { title?: string; footer?: string; children: ReactNode }) {
  return (
    <section>
      {title && <p className="mb-1 px-1 text-[11px] font-semibold text-soft">{title}</p>}
      <div className="divide-y divide-line rounded-lg bg-ink/[0.04] px-3">{children}</div>
      {footer && <p className="mt-1 px-1 text-[11px] text-soft">{footer}</p>}
    </section>
  );
}

function FormRow({ label, children, disabled }: { label: string; children: ReactNode; disabled?: boolean }) {
  return (
    <div className={`flex items-center justify-between gap-3 py-2 text-[12px] ${disabled ? 'opacity-40' : ''}`}>
      <span>{label}</span>
      {children}
    </div>
  );
}

function Toggle({ on, onChange, disabled }: { on: boolean; onChange: (v: boolean) => void; disabled?: boolean }) {
  return (
    <button role="switch" aria-checked={on} disabled={disabled} onClick={() => onChange(!on)}
            className={`relative h-[18px] w-8 cursor-pointer rounded-full transition-colors disabled:cursor-default ${on ? 'bg-accent' : 'bg-ink/25'}`}>
      <span className="absolute top-[2px] size-[14px] rounded-full bg-white shadow transition-[left]" style={{ left: on ? 16 : 2 }} />
    </button>
  );
}

function Stepper({ value, min, max, label, onChange }: { value: number; min: number; max: number; label: string; onChange: (n: number) => void }) {
  return (
    <span className="flex items-center gap-2">
      <span className="tabular-nums">{label}</span>
      <span className="inline-flex overflow-hidden rounded-md border border-line">
        <button onClick={() => onChange(Math.max(min, value - 1))} disabled={value <= min} className="cursor-pointer px-1.5 disabled:opacity-30" aria-label="Decrease">−</button>
        <button onClick={() => onChange(Math.min(max, value + 1))} disabled={value >= max} className="cursor-pointer border-l border-line px-1.5 disabled:opacity-30" aria-label="Increase">+</button>
      </span>
    </span>
  );
}

/** The Appearance tab: how the element is laid out on its page. */
function AppearanceForm({ element, onChange }: { element: Element; onChange: (e: Element) => void }) {
  const a = element.appearance, output = element.filter.output;
  const set = (changes: Partial<Appearance>) => onChange({ ...element, appearance: { ...a, ...changes } });
  const [low, high] = rowRange(a.layout, output);
  const rowMin = allowsAllRows(a.layout) ? 0 : low;
  const fillApplies = a.layout !== 'coverFlow' && (a.rows !== 1 || (a.layout === 'list' && a.columns > 1));
  const footerApplies = a.layout !== 'list' && a.layout !== 'coverFlow' && output !== 'songs';
  const labels = a.sortOverride && orderLabels(a.sortOverride.field);
  return (
    <div className="space-y-4 p-4">
      <FormSection title="Layout">
        <FormRow label="Layout">
          <Segmented value={a.layout} onChange={(layout) => set({ layout, rows: defaultRows(layout, output) })}
                     options={layoutsFor(output).map((l) => ({ value: l, title: layoutTitles[l] }))} />
        </FormRow>
        <FormRow label="Size" disabled={a.layout === 'list'}>
          <Segmented value={a.size} onChange={(size) => set({ size })} disabled={a.layout === 'list'}
                     options={[{ value: 'small', title: 'Small' }, { value: 'medium', title: 'Medium' }, { value: 'large', title: 'Large' }]} />
        </FormRow>
        {high > low && (
          <FormRow label={a.layout === 'timeline' ? 'Rows per year' : a.layout === 'list' && a.columns > 1 ? 'Rows per column' : 'Rows'}>
            <Stepper value={a.rows} min={rowMin} max={high} label={a.rows === 0 ? 'All' : String(a.rows)} onChange={(rows) => set({ rows })} />
          </FormRow>
        )}
        {a.layout === 'list' && (
          <FormRow label="Columns"><Stepper value={a.columns} min={1} max={4} label={String(a.columns)} onChange={(columns) => set({ columns })} /></FormRow>
        )}
        {fillApplies && (
          <FormRow label="Fill">
            <Segmented value={effectiveFill(a)} onChange={(fill) => set({ fill })} options={[{ value: 'across', title: 'Across' }, { value: 'down', title: 'Down' }]} />
          </FormRow>
        )}
      </FormSection>
      {a.layout === 'timeline' && (
        <FormSection title="Timeline">
          <FormRow label="Years">
            <Segmented value={!!a.newestFirst} onChange={(newestFirst) => set({ newestFirst })} options={[{ value: false, title: 'Oldest first' }, { value: true, title: 'Newest first' }]} />
          </FormRow>
        </FormSection>
      )}
      <FormSection title="Style" footer={!a.showHeader ? 'Hidden headers: use Edit Page to change it later.' : undefined}>
        <FormRow label="Spacing">
          <Segmented value={a.spacing} onChange={(spacing) => set({ spacing })} options={[{ value: 'compact', title: 'Compact' }, { value: 'regular', title: 'Regular' }, { value: 'roomy', title: 'Roomy' }]} />
        </FormRow>
        <FormRow label="Show header"><Toggle on={a.showHeader} onChange={(showHeader) => set({ showHeader })} /></FormRow>
        <FormRow label="Show play buttons" disabled={!a.showHeader}><Toggle on={a.showPlayButtons} disabled={!a.showHeader} onChange={(showPlayButtons) => set({ showPlayButtons })} /></FormRow>
        <FormRow label="Show footer" disabled={!footerApplies}><Toggle on={a.showFooter} disabled={!footerApplies} onChange={(showFooter) => set({ showFooter })} /></FormRow>
      </FormSection>
      <FormSection title="Order" footer={a.layout === 'timeline'
        ? 'Years always run in the order set above; this orders albums within each year (or leave it to the rules’ sort).'
        : 'Reorders what the rules return, after every step. Which items appear doesn’t change.'}>
        <FormRow label={a.layout === 'timeline' ? 'Within a year' : 'Order'}>
          <SortFieldSelect allowsNone value={a.sortOverride?.field} onChange={(f) => set({
            sortOverride: f ? { field: f, ascending: ascendingFirst(f) } : undefined,
          })} />
        </FormRow>
        {labels && a.sortOverride && (
          <FormRow label="Direction">
            <Segmented value={a.sortOverride.ascending} onChange={(ascending) => set({ sortOverride: { ...a.sortOverride!, ascending } })}
                       options={[{ value: false, title: labels.descending }, { value: true, title: labels.ascending }]} />
          </FormRow>
        )}
      </FormSection>
    </div>
  );
}

/** The element as it will look on its page, with "N albums · N songs · time" over it. */
function Preview({ element, accent }: { element: Element; accent: string }) {
  const context = useDemo();
  const result = useMemo(() => evaluate(element.filter, context.library, element.id, element.appearance.sortOverride), [element, context.library]);
  const minutes = result.tracks.reduce((s, t) => s + t.song.duration, 0);
  const summary = result.kind === 'songs'
    ? `${counted(result.tracks.length, 'song')} · ${duration(minutes)}`
    : `${counted(result.count, result.kind.slice(0, -1))} · ${counted(result.tracks.length, 'song')} · ${duration(minutes)}`;
  return (
    <div className="flex h-full min-h-0 flex-col bg-bg/50">
      <div className="flex items-baseline gap-2 border-b border-line px-4 py-2">
        <span className="text-[13px] font-semibold">Preview</span>
        <span className="text-[11px] text-soft">{summary}</span>
      </div>
      <div className="min-h-0 flex-1 overflow-y-auto py-4">
        {result.count === 0 ? (
          <div className="grid h-full place-items-center text-center">
            <div>
              <Icon name="line.3.horizontal.decrease" className="mx-auto size-8 text-faint" />
              <p className="mt-2 text-[15px] font-semibold">No Matches</p>
              <p className="text-[12px] text-soft">Try loosening a rule or raising the limit.</p>
            </div>
          </div>
        ) : (
          <Demo.Provider value={{ ...context, preview: true }}>
            <ElementView element={element} pageID="" result={result} editing={false} index={0} count={1} accent={accent}
                         actions={{ edit() {}, move() {}, duplicate() {}, remove() {} }} />
          </Demo.Provider>
        )}
      </div>
    </div>
  );
}

export function Editor({ element, isNew, accent, onSave, onDelete, onClose }: {
  element: Element; isNew: boolean; accent: string; onSave: (e: Element) => void; onDelete: () => void; onClose: () => void;
}) {
  const { compact, library, customFields, saveCustomField } = useDemo();
  const [draft, setDraft] = useState(element);
  /** Where a new custom field goes once created: the sort picker that asked for it. */
  const [creating, setCreating] = useState<{ then: (f: CustomField) => void }>();
  const samples = useMemo(() => (creating ? evaluate(draft.filter, library, draft.id).tracks : []), [creating]);
  const [tab, setTab] = useState<'rules' | 'appearance'>('rules');
  const [showingPreview, setShowingPreview] = useState(false);
  const [asking, setAsking] = useState<'delete' | 'discard'>();
  const changed = JSON.stringify(draft) !== JSON.stringify(element);
  const canSave = draft.filter.name.trim() !== '';
  const cancel = () => (changed ? setAsking('discard') : onClose());
  const setName = (name: string) => setDraft({ ...draft, filter: { ...draft.filter, name } });
  const panel = (
    <NewCustomField.Provider value={(then) => setCreating({ then })}>
    <div className="flex min-h-0 flex-col">
      <div className="flex justify-center border-b border-line py-2.5">
        <Segmented value={tab} onChange={setTab} options={[{ value: 'rules', title: 'Rules' }, { value: 'appearance', title: 'Appearance' }]} />
      </div>
      <div className="min-h-0 flex-1 overflow-y-auto">
        {tab === 'rules' ? <Rules element={draft} onChange={setDraft} /> : <AppearanceForm element={draft} onChange={setDraft} />}
      </div>
    </div>
    </NewCustomField.Provider>
  );
  const dialogs = (
    <>
      {asking === 'delete' && (
        <Confirm title={`Delete “${draft.filter.name}”?`} message="Its smart filter is deleted with it." action="Delete"
                 onConfirm={onDelete} onCancel={() => setAsking(undefined)} />
      )}
      {asking === 'discard' && (
        <Confirm title="Discard your changes?" message="The element stays as it was." action="Discard Changes"
                 onConfirm={onClose} onCancel={() => setAsking(undefined)} />
      )}
      {creating && (
        <CustomFieldSheet samples={samples} onCancel={() => setCreating(undefined)}
                          onSave={(f) => { saveCustomField(f); creating.then(f); setCreating(undefined); }} />
      )}
    </>
  );

  if (compact) {
    return (
      <div className="flex h-full flex-col bg-raised text-ink">
        <div className="flex items-center justify-between gap-2 border-b border-line px-4 pt-4 pb-2.5">
          <button onClick={cancel} className="cursor-pointer text-[15px] text-accent">Cancel</button>
          <Segmented value={showingPreview} onChange={setShowingPreview} options={[{ value: false, title: 'Edit' }, { value: true, title: 'Preview' }]} />
          <button onClick={() => onSave(draft)} disabled={!canSave} className="cursor-pointer text-[15px] font-semibold text-accent disabled:opacity-40">
            {isNew ? 'Create' : 'Save'}
          </button>
        </div>
        {showingPreview ? <div className="min-h-0 flex-1"><Preview element={draft} accent={accent} /></div> : (
          <div className="flex min-h-0 flex-1 flex-col">
            <input value={draft.filter.name} onChange={(e) => setName(e.target.value)} placeholder="Name" aria-label="Name"
                   className="mx-4 mt-3 rounded-lg bg-ink/[0.06] px-3 py-2 text-[15px] font-semibold outline-none" />
            {panel}
            {!isNew && (
              <button onClick={() => setAsking('delete')} className="cursor-pointer border-t border-line py-3 text-[15px] text-red-500">Delete Element…</button>
            )}
          </div>
        )}
        {dialogs}
      </div>
    );
  }

  return (
    <div className="flex h-full flex-col overflow-hidden rounded-xl border border-line bg-raised text-ink shadow-[0_30px_80px_rgb(0_0_0/0.4)]">
      <div className="border-b border-line px-5 py-3">
        <input value={draft.filter.name} onChange={(e) => setName(e.target.value)} placeholder="Name" aria-label="Name"
               className="w-full bg-transparent text-[20px] font-semibold outline-none" />
      </div>
      <div className="grid min-h-0 flex-1 grid-cols-[minmax(0,1fr)_380px]">
        <div className="min-h-0 border-r border-line"><Preview element={draft} accent={accent} /></div>
        {panel}
      </div>
      <div className="flex items-center gap-2 border-t border-line px-3.5 py-3 text-[13px]">
        {!isNew && <button onClick={() => setAsking('delete')} className="cursor-pointer rounded-md px-2.5 py-1 text-red-500 hover:bg-red-500/10">Delete Element…</button>}
        <div className="flex-1" />
        <button onClick={cancel} className="cursor-pointer rounded-md bg-ink/[0.08] px-3 py-1 hover:bg-ink/[0.12]">Cancel</button>
        <button onClick={() => onSave(draft)} disabled={!canSave} className="cursor-pointer rounded-md bg-accent px-3 py-1 font-medium text-accent-ink disabled:opacity-40">
          {isNew ? 'Create' : 'Save'}
        </button>
      </div>
      {dialogs}
    </div>
  );
}
