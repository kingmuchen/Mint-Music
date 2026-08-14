/**
 * Build script for AMLL Lyric Player WebView bundle
 *
 * 1. Bundles entry.js + AMLL core (+ deps) into a single IIFE
 * 2. Copies CSS to assets/amll/
 */

import { execSync } from 'child_process'
import { copyFileSync, mkdirSync, readFileSync, writeFileSync } from 'fs'
import { join, dirname } from 'path'
import { fileURLToPath } from 'url'

const __dirname = dirname(fileURLToPath(import.meta.url))
const root = join(__dirname, '..')
const assetsDir = join(root, 'assets', 'amll')

// Ensure output dir exists
mkdirSync(assetsDir, { recursive: true })

console.log('[build] 1. Checking dependencies...')
try {
  execSync('npx esbuild --version', { cwd: __dirname, stdio: 'pipe' })
} catch {
  console.log('[build] Installing esbuild...')
  execSync('npm install --save-dev esbuild', { cwd: __dirname, stdio: 'inherit' })
}

// Build
console.log('[build] 2. Bundling AMLL lyric player + bridge with esbuild...')
execSync(
  'npx esbuild src/entry.js --bundle --outfile=../assets/amll/amll-bundle.js --format=iife --minify --tree-shaking=true --platform=browser --define:import.meta.env.DEV=false',
  { cwd: __dirname, stdio: 'inherit' }
)

// Copy CSS
console.log('[build] 3. Copying AMLL CSS...')
const cssSrc = join(root, 'node_modules', '@applemusic-like-lyrics', 'core', 'dist', 'style.css')
const cssDest = join(assetsDir, 'amll-core.css')
copyFileSync(cssSrc, cssDest)

console.log('[build] 4. Creating lyric_player.html...')
const html = `<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1,user-scalable=no">
  <link rel="stylesheet" href="amll-core.css">
  <style>
    * { margin: 0; padding: 0; box-sizing: border-box; }
    html, body {
      width: 100%; height: 100%;
      overflow: hidden;
      background: transparent;
    }
    #player {
      width: 100%; height: 100%;
      --amll-lp-color: rgba(255, 255, 255, 0.9);
      --amll-lp-font-size: max(max(3.5vh, 1.8vw), 14px);
      --amll-lp-hover-bg-color: rgba(255, 255, 255, 0.08);
    }
  </style>
</head>
<body>
  <div id="player"></div>
  <script src="amll-bundle.js"></script>
  <script>
    document.addEventListener('DOMContentLoaded', function () {
      AmllBridge.init('player');
    });
  </script>
</body>
</html>`
writeFileSync(join(assetsDir, 'lyric_player.html'), html)

console.log('[build] Done! Assets written to:', assetsDir)
