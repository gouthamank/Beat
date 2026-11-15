// What tiles and pages reach without being handed it: the library, the player, navigation and the layout.
import { createContext, useContext } from 'react';
import type { CustomField, DemoAlbum, Genre, Library } from './model';
import type { Player } from './player';

export interface DemoContext {
  library: Library;
  player: Player;
  compact: boolean;
  /** The editor's preview: renders as on the page, but nothing in it opens or plays. */
  preview: boolean;
  /** Opens an album's page; `from` is the cover clicked, which a phone's page zooms out of. */
  openAlbum: (album: DemoAlbum, from?: Element | null) => void;
  openGenre: (genre: Genre) => void;
  openElement: (pageID: string, elementID: string) => void;
  /** The custom sort fields, shared by every element (Beat keeps them with the pages). */
  customFields: CustomField[];
  saveCustomField: (field: CustomField) => void;
}

export const Demo = createContext<DemoContext>(null!);
export const useDemo = () => useContext(Demo);
