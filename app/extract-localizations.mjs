// Regenerates the English Localizable.strings from the compiler's string extraction.
// Build the iOS and macOS app with SWIFT_EMIT_LOC_STRINGS=YES into the derived data
// directory passed as the first argument; see app/AGENTS.md.
import { readdirSync, readFileSync, writeFileSync } from "node:fs";
import { dirname, join, relative } from "node:path";
import { fileURLToPath } from "node:url";

const appDirectory = dirname(fileURLToPath(import.meta.url));
const sourcesDirectory = join(appDirectory, "Sources");
const derivedData = process.argv[2];
if (!derivedData) {
  console.error("Usage: node extract-localizations.mjs <derived-data-path>");
  process.exit(1);
}

const origins = new Map();
for (const entry of readdirSync(join(derivedData, "Build/Intermediates.noindex"), { recursive: true, withFileTypes: true })) {
  if (!entry.isFile() || !entry.name.endsWith(".stringsdata")) continue;
  const data = JSON.parse(readFileSync(join(entry.parentPath, entry.name), "utf8"));
  if (!data.source.startsWith(`${sourcesDirectory}/`)) continue;
  for (const { key } of data.tables.Localizable ?? []) {
    if (!origins.has(key)) origins.set(key, new Set());
    origins.get(key).add(relative(sourcesDirectory, data.source));
  }
}
if (origins.size === 0) {
  console.error(`No strings found for ${sourcesDirectory}. Did the build set SWIFT_EMIT_LOC_STRINGS=YES?`);
  process.exit(1);
}

// .strings uses JSON's string escapes, except that \u must be written as \U.
const quote = (value) => JSON.stringify(value).replace(/\\u([\da-fA-F]{4})/g, "\\U$1");
const catalog = [...origins]
  .sort(([a], [b]) => (a < b ? -1 : a > b ? 1 : 0))
  .map(([key, files]) => `/* ${[...files].sort().join(", ")} */\n${quote(key)} = ${quote(key)};\n`)
  .join("\n");
writeFileSync(join(appDirectory, "Resources/TuistApp/en.lproj/Localizable.strings"), catalog);
console.log(`Extracted ${origins.size} strings`);
