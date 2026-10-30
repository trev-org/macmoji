// Regenerates RevCore/Sources/RevCore/Resources/emoji.json from emojibase-data (MIT).
// Usage: cd scripts && npm install && node gen-emoji.mjs
import { readFileSync, writeFileSync } from "node:fs";
import { createRequire } from "node:module";
const require = createRequire(import.meta.url);
const data = require("emojibase-data/en/data.json");
const iamcal = require("emojibase-data/en/shortcodes/iamcal.json");
const github = require("emojibase-data/en/shortcodes/github.json");
const pkgVersion = require("emojibase-data/package.json").version;
const arr = (v) => (v == null ? [] : Array.isArray(v) ? v : [v]);
const out = [];
for (const e of data) {
  // iamcal (Slack) names first, then GitHub aliases; fall back to the label for brand-new emoji.
  const names = [...new Set([...arr(iamcal[e.hexcode]), ...arr(github[e.hexcode])])];
  if (names.length === 0) names.push(e.label.toLowerCase().replace(/[^a-z0-9+\-]+/g, "_").replace(/^_|_$/g, ""));
  const entry = { e: e.emoji, n: names, k: (e.tags || []).filter((t) => !names.includes(t)), o: e.order ?? 99999 };
  const skins = (e.skins || []).filter((s) => typeof s.tone === "number");
  if (skins.length === 5) entry.s = skins.sort((a, b) => a.tone - b.tone).map((s) => s.emoji);
  out.push(entry);
}
out.sort((a, b) => a.o - b.o);
const target = new URL("../RevCore/Sources/RevCore/Resources/emoji.json", import.meta.url);
writeFileSync(target, JSON.stringify({ source: `emojibase-data ${pkgVersion}`, emoji: out }));
console.log(`wrote ${out.length} emoji from emojibase-data ${pkgVersion}`);
