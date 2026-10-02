import { defineConfig } from 'vite';
import { viteSingleFile } from 'vite-plugin-singlefile';

// The production build is one self-contained index.html (JS, CSS and fonts inlined),
// so the iOS app can load it offline from inside the bundle.
export default defineConfig({
  plugins: [viteSingleFile()],
  build: {
    target: 'es2020',
    assetsInlineLimit: 100_000_000,
    cssCodeSplit: false,
    chunkSizeWarningLimit: 4000,
  },
  server: { port: 5173 },
});
