// usage: bun scripts/icons.ts [--check]: renders every icon Koe's Swift names (an "Icon…" literal) into Resources/Icons as SVG with
// shinsa's own icon pipeline (packages/ui/scripts/icons.ts: Central Icons, round, radius 3, stroke 2), so each glyph is the one the web
// draws. Ported from shinsa-ios's scripts/icons.ts. SHINSA_SOURCE is a shinsa checkout with its dependencies installed.
import { existsSync, mkdirSync, readdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { homedir } from 'node:os';
import { join, resolve } from 'node:path';

const ROOT = resolve(import.meta.dir, '..');
const OUT = join(ROOT, 'Resources/Icons');
const check = process.argv.includes('--check');

const source = Bun.env.SHINSA_SOURCE ?? join(homedir(), 'Developer/Projects/shinsa');
const { renderIconMarkup } = await import(join(source, 'packages/ui/scripts/icons.ts'));

const swift = readdirSync(join(ROOT, 'Sources'), { recursive: true, withFileTypes: true })
  .filter((entry) => entry.isFile() && entry.name.endsWith('.swift'))
  .map((entry) => readFileSync(join(entry.parentPath, entry.name), 'utf8'))
  .join('\n');
const names = [...new Set([...swift.matchAll(/"(Icon[A-Z][A-Za-z0-9]*)"/g)].map((match) => match[1] as string))].sort();

function render(name: string) {
  const radius = name.startsWith('IconChevron') ? '0' : '3';
  const inner = renderIconMarkup(name, radius) as string;
  return `<svg width="24" height="24" viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">${inner.replaceAll('currentColor', '#000000')}</svg>\n`;
}

const files = new Map(names.map((name) => [`${name}.svg`, render(name)] as const));

if (check) {
  const onDisk = existsSync(OUT) ? readdirSync(OUT) : [];
  const stale = onDisk.filter((path) => !files.has(path));
  const differing = [...files].filter(([path, body]) => !existsSync(join(OUT, path)) || readFileSync(join(OUT, path), 'utf8') !== body);
  if (stale.length || differing.length) {
    console.error(`Icons differ from shinsa's: ${[...stale, ...differing.map(([path]) => path)].join(', ')}. Run bun scripts/icons.ts`);
    process.exit(1);
  }
  console.log(`${names.length} icons match shinsa's`);
} else {
  rmSync(OUT, { recursive: true, force: true });
  mkdirSync(OUT, { recursive: true });
  for (const [path, body] of files) writeFileSync(join(OUT, path), body);
  console.log(`${names.length} icons → ${OUT}`);
}
