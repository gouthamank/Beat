import react from '@astrojs/react';
import tailwindcss from '@tailwindcss/vite';
import { defineConfig } from 'astro/config';

export default defineConfig({
  site: 'https://beat.gouthaman.dev',
  // React only for the interactive demo; the rest of the page ships no JavaScript.
  integrations: [react()],
  vite: {
    plugins: [tailwindcss()],
    // The covers and library data come from Design/Showcase, outside the site's folder.
    server: { fs: { allow: ['..'] } },
  },
});
