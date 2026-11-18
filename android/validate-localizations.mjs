// Validates a translated strings.xml against the English source.
// Glossia runs it with GLOSSIA_SOURCE_PATH and GLOSSIA_TARGET_PATH; see android/L10N.md.
import { readFileSync } from "node:fs";

const escapes = { n: "\n", t: "\t", '"': '"', "'": "'", "\\": "\\", "@": "@", "?": "?" };
const entities = { amp: "&", lt: "<", gt: ">", quot: '"', apos: "'" };

function parse(text, path) {
  const entries = new Map();
  let rest = text.replace(/^\uFEFF/, "");
  const fail = (expected) => {
    throw new Error(`${path}: expected ${expected} near ${JSON.stringify(rest.slice(0, 60))}`);
  };
  const take = (pattern, expected) => {
    rest = rest.replace(/^(?:\s+|<!--[\s\S]*?-->)*/, "");
    const match = pattern.exec(rest);
    if (!match) fail(expected);
    rest = rest.slice(match[0].length);
    return match;
  };
  take(/^(?:<\?xml[^?]*\?>)?/, "an XML declaration");
  take(/^<resources\s*>/, "<resources>");
  while (!take(/^(?:<\/resources>)?/, "</resources>")[0]) {
    const [, name, raw] = take(/^<string\s+name="([a-z][a-z0-9_]*)"\s*>([^<]*)<\/string>/, '<string name="...">');
    const value = raw.trim().replace(/&(amp|lt|gt|quot|apos);/g, (_, entity) => entities[entity]);
    // Glossia only extracts values in Android's quoted form.
    const quoted = /^"((?:[^"\\]|\\(?:u[\da-fA-F]{4}|[nt"'\\@?]))*)"$/.exec(value);
    if (!quoted) throw new Error(`${path}: ${name} must be a quoted string, such as "Sign in"`);
    if (entries.has(name)) throw new Error(`${path}: duplicate string ${name}`);
    entries.set(
      name,
      quoted[1].replace(/\\(u[\da-fA-F]{4}|.)/g, (_, escape) =>
        escape.length === 5 ? String.fromCharCode(parseInt(escape.slice(1), 16)) : escapes[escape],
      ),
    );
  }
  if (rest.trim()) fail("the end of the file");
  return entries;
}

function placeholders(value) {
  let implicit = 0;
  const tokens = [];
  for (const [token, position, type] of value.matchAll(/%%|%n|%(?:(\d+)\$)?[-+0 #,(]*\d*(?:\.\d+)?([bBhHsScCdoxXeEfgGaA])/g)) {
    tokens.push(token === "%%" || token === "%n" ? token : `${position ?? ++implicit}:${type}`);
  }
  return tokens.sort().join(" ");
}

const { GLOSSIA_SOURCE_PATH: sourcePath, GLOSSIA_TARGET_PATH: targetPath } = process.env;
try {
  if (!sourcePath || !targetPath) throw new Error("GLOSSIA_SOURCE_PATH and GLOSSIA_TARGET_PATH are required");
  const source = parse(readFileSync(sourcePath, "utf8"), sourcePath);
  const target = parse(readFileSync(targetPath, "utf8"), targetPath);
  for (const [name, value] of source) {
    if (!target.has(name)) throw new Error(`${targetPath}: missing string ${name}`);
    if (placeholders(value) !== placeholders(target.get(name))) {
      throw new Error(`${targetPath}: format arguments changed for ${name}`);
    }
  }
  for (const name of target.keys()) {
    if (!source.has(name)) throw new Error(`${targetPath}: unexpected string ${name}`);
  }
} catch (error) {
  console.error(error.message);
  process.exit(1);
}
