// Validates a translated Localizable.strings against the English source.
// Glossia runs it with GLOSSIA_SOURCE_PATH and GLOSSIA_TARGET_PATH; see app/L10N.md.
import { readFileSync } from "node:fs";

const escapes = { n: "\n", r: "\r", t: "\t", '"': '"', "'": "'", "\\": "\\", "/": "/" };

function parse(text, path) {
  const entries = new Map();
  const trivia = /^(?:\s+|\/\/[^\n]*|\/\*[\s\S]*?\*\/)*/;
  const quoted = /^"((?:[^"\\\r\n]|\\(?:U[\da-fA-F]{4}|[nrt"'\\/]))*)"/;
  let rest = text.replace(/^\uFEFF/, "");
  const skip = () => (rest = rest.slice(trivia.exec(rest)[0].length));
  const take = (pattern, expected) => {
    skip();
    const match = pattern.exec(rest);
    if (!match) throw new Error(`${path}: expected ${expected} near ${JSON.stringify(rest.slice(0, 40))}`);
    rest = rest.slice(match[0].length);
    return match[1];
  };
  const decode = (value) =>
    value.replace(/\\(U[\da-fA-F]{4}|.)/g, (_, escape) =>
      escape.length === 5 ? String.fromCharCode(parseInt(escape.slice(1), 16)) : escapes[escape],
    );
  skip();
  while (rest) {
    const key = decode(take(quoted, "a quoted key"));
    take(/^(=)/, "=");
    const value = decode(take(quoted, "a quoted value"));
    take(/^(;)/, ";");
    if (entries.has(key)) throw new Error(`${path}: duplicate key ${JSON.stringify(key)}`);
    entries.set(key, value);
    skip();
  }
  return entries;
}

function placeholders(value) {
  let implicit = 0;
  const tokens = [];
  for (const [token, position, type] of value.matchAll(/%%|%(?:(\d+)\$)?[-+0 #]*\d*(?:\.\d+)?((?:hh|ll|[hlqLzjt])?[@diuoxXfFeEgGaAcCsSp])/g)) {
    tokens.push(token === "%%" ? token : `${position ?? ++implicit}:${type}`);
  }
  return tokens.sort().join(" ");
}

const { GLOSSIA_SOURCE_PATH: sourcePath, GLOSSIA_TARGET_PATH: targetPath } = process.env;
try {
  if (!sourcePath || !targetPath) throw new Error("GLOSSIA_SOURCE_PATH and GLOSSIA_TARGET_PATH are required");
  const source = parse(readFileSync(sourcePath, "utf8"), sourcePath);
  const target = parse(readFileSync(targetPath, "utf8"), targetPath);
  for (const [key, value] of source) {
    if (!target.has(key)) throw new Error(`${targetPath}: missing key ${JSON.stringify(key)}`);
    if (placeholders(value) !== placeholders(target.get(key))) {
      throw new Error(`${targetPath}: format arguments changed for ${JSON.stringify(key)}`);
    }
  }
  for (const key of target.keys()) {
    if (!source.has(key)) throw new Error(`${targetPath}: unexpected key ${JSON.stringify(key)}`);
  }
} catch (error) {
  console.error(error.message);
  process.exit(1);
}
