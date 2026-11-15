// The sidebar, after Beat's SidebarView: your folders and pages first, mixed at any level, then Library. A folder
// row's + (on hover) adds a page or folder inside it, and its trailing chevron turns as it opens; an open, empty
// folder says Empty. New at the bottom: New Page, New Folder, Add Default Home Page. New items are named in a sheet
// (Create or Cancel, which doesn't keep them). Right-click a row: New Page/Folder Below (inside, for a folder),
// Rename…, Duplicate, Delete….
import { useEffect, useRef, useState } from 'react';
import { Icon } from './Icon';
import type { Node } from './model';

export type LibraryPage = 'albums' | 'artists' | 'songs' | 'genres';
export type Selection = { kind: 'page'; id: string } | { kind: 'library'; page: LibraryPage };

export const libraryPages: { key: LibraryPage; title: string; symbol: string }[] = [
  { key: 'albums', title: 'Albums', symbol: 'square.stack' },
  { key: 'artists', title: 'Artists', symbol: 'music.microphone' },
  { key: 'songs', title: 'Songs', symbol: 'music.note' },
  { key: 'genres', title: 'Genres', symbol: 'guitars' },
];

export type SidebarAction =
  | { kind: 'new'; folder: boolean; inside?: string; below?: string }
  | { kind: 'rename'; id: string }
  | { kind: 'duplicate'; id: string }
  | { kind: 'delete'; id: string }
  | { kind: 'addHome' };

interface Props {
  tree: Node[];
  selection: Selection;
  expanded: Set<string>;
  onSelect: (s: Selection) => void;
  onToggle: (id: string) => void;
  onAction: (a: SidebarAction) => void;
}

function Menu({ items, onClose, style }: { items: ({ title: string; icon?: string; action: () => void; destructive?: boolean } | 'divider')[]; onClose: () => void; style: React.CSSProperties }) {
  const ref = useRef<HTMLDivElement>(null);
  useEffect(() => {
    const away = (e: PointerEvent) => { if (!ref.current?.contains(e.target as globalThis.Node)) onClose(); };
    const esc = (e: KeyboardEvent) => { if (e.key === 'Escape') onClose(); };
    setTimeout(() => window.addEventListener('pointerdown', away), 0);
    window.addEventListener('keydown', esc);
    return () => { window.removeEventListener('pointerdown', away); window.removeEventListener('keydown', esc); };
  }, [onClose]);
  return (
    <div ref={ref} role="menu" className="absolute z-[80] w-52 rounded-lg border border-line bg-raised/95 p-1 text-[13px] shadow-2xl backdrop-blur" style={style}>
      {items.map((item, i) => item === 'divider' ? <hr key={i} className="my-1 border-line" /> : (
        <button key={i} role="menuitem" onClick={() => { onClose(); item.action(); }}
                className={`flex w-full cursor-pointer items-center gap-2 rounded px-2 py-1 text-left hover:bg-accent hover:text-accent-ink ${item.destructive ? 'text-red-500' : ''}`}>
          {item.icon && <Icon name={item.icon} className="size-3.5" />}{item.title}
        </button>
      ))}
    </div>
  );
}

export function Sidebar({ tree, selection, expanded, onSelect, onToggle, onAction }: Props) {
  const [menu, setMenu] = useState<{ x: number; y: number; node?: Node; createOnly?: boolean; bottom?: boolean }>();
  const [hover, setHover] = useState<string>();
  const box = useRef<HTMLDivElement>(null);

  const openMenu = (e: React.MouseEvent, node?: Node, createOnly = false) => {
    e.preventDefault();
    e.stopPropagation();
    const r = box.current!.getBoundingClientRect();
    setMenu({ x: e.clientX - r.left, y: e.clientY - r.top, node, createOnly });
  };

  const nodeItems = (node: Node, createOnly: boolean) => {
    const folder = node.kind === 'folder';
    const create = [
      { title: folder ? 'New Page' : 'New Page Below', icon: 'rectangle.grid.1x2', action: () => onAction({ kind: 'new', folder: false, ...(folder ? { inside: node.id } : { below: node.id }) }) },
      { title: folder ? 'New Folder' : 'New Folder Below', icon: 'folder', action: () => onAction({ kind: 'new', folder: true, ...(folder ? { inside: node.id } : { below: node.id }) }) },
    ];
    if (createOnly) return create;
    return [...create, 'divider' as const,
      { title: 'Rename…', icon: 'pencil', action: () => onAction({ kind: 'rename', id: node.id }) },
      { title: 'Duplicate', icon: 'plus.square.on.square', action: () => onAction({ kind: 'duplicate', id: node.id }) },
      'divider' as const,
      { title: 'Delete…', icon: 'trash', action: () => onAction({ kind: 'delete', id: node.id }), destructive: true },
    ];
  };

  // One flat list with hand-drawn indentation: 18 points a level for the first two levels.
  const indent = (depth: number) => Math.min(depth, 2) * 18;
  const rows = (nodes: Node[], depth: number): React.ReactNode[] => nodes.flatMap((node) => {
    if (node.kind === 'folder') {
      const open = expanded.has(node.id);
      const row = (
        <div key={node.id} role="button" tabIndex={0} aria-expanded={open} onClick={() => onToggle(node.id)} onContextMenu={(e) => openMenu(e, node)}
             onMouseEnter={() => setHover(node.id)} onMouseLeave={() => setHover(undefined)}
             className="flex h-7 cursor-default items-center rounded-md px-2 text-[13px] hover:bg-ink/[0.04]" style={{ paddingLeft: 8 + indent(depth) }}>
          <Icon name={node.symbol} className="mr-2 size-4 shrink-0 text-accent" />
          <span className="min-w-0 flex-1 truncate">{node.name}</span>
          <button onClick={(e) => openMenu(e, node, true)} title={`Add a page or folder to “${node.name}”`} aria-label={`Add to ${node.name}`}
                  className={`mr-1 grid size-[22px] cursor-pointer place-items-center text-soft ${hover === node.id ? '' : 'pointer-events-none opacity-0'}`}>
            <Icon name="plus" className="size-3" strokeWidth={2.2} />
          </button>
          <Icon name="chevron.right" className={`size-2.5 text-soft transition-transform ${open ? 'rotate-90' : ''}`} strokeWidth={2.6} />
        </div>
      );
      if (!open) return [row];
      return [row, ...(node.children.length ? rows(node.children, depth + 1) : [
        <div key={`${node.id}-empty`} className="flex h-7 items-center px-2 text-[13px] text-faint" style={{ paddingLeft: 8 + indent(depth + 1) }}>Empty</div>,
      ])];
    }
    const selected = selection.kind === 'page' && selection.id === node.id;
    return [(
      <div key={node.id} role="button" tabIndex={0} onClick={() => onSelect({ kind: 'page', id: node.id })} onContextMenu={(e) => openMenu(e, node)}
           className={`flex h-7 cursor-default items-center rounded-md px-2 text-[13px] ${selected ? 'bg-accent text-accent-ink' : 'hover:bg-ink/[0.04]'}`}
           style={{ paddingLeft: 8 + indent(depth) }}>
        <Icon name={node.symbol} className={`mr-2 size-4 shrink-0 ${selected ? '' : 'text-accent'}`} />
        <span className="min-w-0 flex-1 truncate">{node.name}</span>
      </div>
    )];
  });

  return (
    <div ref={box} className="relative flex h-full flex-col">
      <nav className="min-h-0 flex-1 overflow-y-auto px-2.5">
        {rows(tree, 0)}
        <p className="mt-4 mb-0.5 px-2 text-[11px] font-semibold text-soft">Library</p>
        {libraryPages.map((page) => {
          const selected = selection.kind === 'library' && selection.page === page.key;
          return (
            <div key={page.key} role="button" tabIndex={0} onClick={() => onSelect({ kind: 'library', page: page.key })}
                 className={`flex h-7 cursor-default items-center rounded-md px-2 text-[13px] ${selected ? 'bg-accent text-accent-ink' : 'hover:bg-ink/[0.04]'}`}>
              <Icon name={page.symbol} className={`mr-2 size-4 ${selected ? '' : 'text-accent'}`} /> {page.title}
            </div>
          );
        })}
      </nav>
      <button onClick={(e) => { const r = box.current!.getBoundingClientRect(); setMenu({ x: e.clientX - r.left, y: e.clientY - r.top, bottom: true }); }}
              className="flex cursor-pointer items-center gap-1.5 px-4 py-2.5 text-[13px] text-soft hover:text-ink">
        <Icon name="plus.circle" className="size-4" /> New
      </button>
      {menu && (
        <Menu onClose={() => setMenu(undefined)} style={menu.bottom ? { left: 12, bottom: 44 } : { left: Math.min(menu.x, 40), top: menu.y }}
              items={menu.node ? nodeItems(menu.node, !!menu.createOnly) : [
                { title: 'New Page', icon: 'rectangle.grid.1x2', action: () => onAction({ kind: 'new', folder: false }) },
                { title: 'New Folder', icon: 'folder', action: () => onAction({ kind: 'new', folder: true }) },
                'divider',
                { title: 'Add Default Home Page', icon: 'house', action: () => onAction({ kind: 'addHome' }) },
              ]} />
      )}
    </div>
  );
}

/** Naming a new page or folder, or renaming one: Beat's NameSheet. */
export function NameSheet({ title, symbol, name, saveTitle, onSave, onCancel }: {
  title: string; symbol: string; name: string; saveTitle: string; onSave: (name: string) => void; onCancel: () => void;
}) {
  const [value, setValue] = useState(name);
  const input = useRef<HTMLInputElement>(null);
  useEffect(() => { input.current?.select(); }, []);
  const save = () => { if (value.trim()) onSave(value.trim()); };
  return (
    <div className="absolute inset-0 z-[85] flex items-start justify-center bg-black/20 pt-16" onClick={onCancel}>
      <div className="w-80 rounded-xl border border-line bg-raised p-5 shadow-2xl" onClick={(e) => e.stopPropagation()} role="dialog" aria-label={title}>
        <div className="flex items-center gap-2 text-[15px] font-semibold"><Icon name={symbol} className="size-5 text-accent" />{title}</div>
        <input ref={input} value={value} onChange={(e) => setValue(e.target.value)} aria-label="Name"
               onKeyDown={(e) => { if (e.key === 'Enter') save(); if (e.key === 'Escape') onCancel(); }}
               className="mt-3 w-full rounded-md border border-line bg-bg px-2 py-1.5 text-[13px] outline-none focus:border-accent" />
        <div className="mt-4 flex justify-end gap-2 text-[13px]">
          <button onClick={onCancel} className="cursor-pointer rounded-md bg-ink/[0.08] px-3 py-1">Cancel</button>
          <button onClick={save} disabled={!value.trim()} className="cursor-pointer rounded-md bg-accent px-3 py-1 font-medium text-accent-ink disabled:opacity-40">{saveTitle}</button>
        </div>
      </div>
    </div>
  );
}
