// The made-up library from Design/Showcase (see render.swift there): albums and songs, with their generated covers as
// images Astro can resize. No real album art appears anywhere on the site.
import type { ImageMetadata } from 'astro';
import data from '../../../Design/Showcase/showcase.json';

export interface Credit {
  title: string;
  artist: string;
  license: string;
  url: string;
}

export interface Song {
  title: string;
  track: number;
  duration: number;
  plays: number;
  skips: number;
  lastPlayedDaysAgo?: number;
  lastSkippedDaysAgo?: number;
  audio?: string;
  lyrics?: string;
  credit?: Credit;
}

export interface Album {
  id: string;
  title: string;
  artist: string;
  genre: string;
  year: number;
  tint: string;
  colors: string[];
  palette: { background: string; primary: string; secondary: string };
  addedDaysAgo: number;
  /** The comments tag; one label's releases carry a catalog number in it. */
  comments?: string;
  songs: Song[];
  image: ImageMetadata;
}

const covers = import.meta.glob<ImageMetadata>('../../../Design/Showcase/Covers/*.jpg', { eager: true, import: 'default' });

export const albums: Album[] = data.albums.map((album) => {
  const image = covers[`../../../Design/Showcase/${album.cover}`];
  if (!image) throw new Error(`No cover for ${album.id}`);
  return { ...album, image } as Album;
});

/** The real recordings behind the few songs with music, for the footer's credits. */
export const credits: Credit[] = albums.flatMap((album) => album.songs.flatMap((song) => (song.credit ? [song.credit] : [])));
