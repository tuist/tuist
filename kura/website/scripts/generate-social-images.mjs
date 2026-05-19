import fs from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

import matter from "gray-matter";
import sharp from "sharp";

const WIDTH = 1200;
const HEIGHT = 630;
const __dirname = path.dirname(fileURLToPath(import.meta.url));
const rootDir = path.resolve(__dirname, "..");
const srcDir = path.join(rootDir, "src");
const outputDir = path.join(srcDir, "assets", "social");
const logoPath = path.join(srcDir, "public", "logo.png");
const pagePaths = [
  path.join(srcDir, "en", "index.njk"),
  path.join(srcDir, "ja", "index.njk"),
  path.join(srcDir, "en", "blog", "index.njk"),
  path.join(srcDir, "ja", "blog", "index.njk"),
];

function escapeHtml(value) {
  return String(value)
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
}

function tokenize(text) {
  const source = String(text).trim();
  return /\s/.test(source) ? source.split(/\s+/).filter(Boolean) : [...source];
}

function wrapText(text, maxLineLength, maxLines) {
  const tokens = tokenize(text);
  const lines = [];
  let current = "";

  for (const token of tokens) {
    const separator = /\s/.test(String(text)) && current ? " " : "";
    const next = `${current}${separator}${token}`;

    if (next.length <= maxLineLength) {
      current = next;
      continue;
    }

    if (current) {
      lines.push(current);
      current = token;
    } else {
      lines.push(token);
    }

    if (lines.length === maxLines) break;
  }

  if (current && lines.length < maxLines) {
    lines.push(current);
  }

  if (lines.length === maxLines && tokens.join("").length > lines.join("").length) {
    lines[maxLines - 1] = `${lines[maxLines - 1].replace(/[,.!?;:]?$/, "")}...`;
  }

  return lines;
}

function formatDate(value, localeTag) {
  if (!value) return null;

  const date = value instanceof Date ? value : new Date(value);
  if (Number.isNaN(date.getTime())) return null;

  return date.toLocaleDateString(localeTag, {
    year: "numeric",
    month: "long",
    day: "numeric",
    timeZone: "UTC",
  });
}

function renderSvg({ title, kicker, date, localeKey }) {
  const lines = wrapText(title, localeKey === "ja" ? 13 : 20, 3);
  const fontSize = lines.length >= 3 ? (localeKey === "ja" ? 58 : 58) : 66;
  const lineHeight = Math.round(fontSize * 1.3);
  const titleTop = lines.length === 1 ? 248 : lines.length === 2 ? 224 : 200;
  const sansStack =
    "'Hiragino Maru Gothic ProN', 'Hiragino Sans', 'Yu Gothic', 'Helvetica Neue', sans-serif";
  const serifStack = "'Hiragino Mincho ProN', 'Yu Mincho', 'Times New Roman', serif";
  const titleLines = lines
    .map(
      (line, index) =>
        `<tspan x="96" y="${titleTop + index * lineHeight}">${escapeHtml(line)}</tspan>`,
    )
    .join("");
  const dateLine = date
    ? `<text x="96" y="408" font-family="${sansStack}" font-size="22" font-weight="700" letter-spacing="2" fill="#7a6d5e">${escapeHtml(date)}</text>`
    : "";

  return `
<svg width="${WIDTH}" height="${HEIGHT}" viewBox="0 0 ${WIDTH} ${HEIGHT}" xmlns="http://www.w3.org/2000/svg">
  <defs>
    <linearGradient id="sky" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="#e3f1fb"/>
      <stop offset="0.55" stop-color="#fbeede"/>
      <stop offset="1" stop-color="#fce4ec"/>
    </linearGradient>
    <linearGradient id="field" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="#a9dd9a"/>
      <stop offset="1" stop-color="#7fc878"/>
    </linearGradient>
  </defs>
  <rect width="${WIDTH}" height="${HEIGHT}" fill="url(#sky)"/>
  <circle cx="1010" cy="120" r="92" fill="#ffe9b0" opacity="0.5"/>
  <circle cx="1010" cy="120" r="58" fill="#ffdf94"/>
  <ellipse cx="300" cy="120" rx="86" ry="28" fill="#ffffff" opacity="0.8"/>
  <ellipse cx="356" cy="108" rx="54" ry="22" fill="#ffffff" opacity="0.8"/>
  <path d="M0 470 Q 300 410 640 462 T 1200 466 V630 H0 Z" fill="#bfe6ad"/>
  <path d="M0 512 Q 360 452 760 508 T 1200 512 V630 H0 Z" fill="url(#field)"/>
  <g>
    <rect x="852" y="438" width="14" height="78" rx="6" fill="#c4895a"/>
    <circle cx="826" cy="412" r="48" fill="#f7bcd3"/>
    <circle cx="876" cy="398" r="56" fill="#f3a9c6"/>
    <circle cx="908" cy="436" r="44" fill="#f7bcd3"/>
    <circle cx="848" cy="448" r="42" fill="#fcd6e4"/>
  </g>
  <g fill="#f4a9c6" opacity="0.85">
    <ellipse cx="120" cy="520" rx="7" ry="4"/>
    <ellipse cx="220" cy="540" rx="6" ry="4"/>
    <ellipse cx="420" cy="548" rx="7" ry="4"/>
    <ellipse cx="640" cy="540" rx="6" ry="4"/>
    <ellipse cx="180" cy="300" rx="9" ry="6"/>
    <ellipse cx="520" cy="220" rx="8" ry="5"/>
    <ellipse cx="700" cy="320" rx="9" ry="6"/>
  </g>
  <g transform="translate(96 96)">
    <rect width="auto"/>
    <text x="0" y="0" font-family="${sansStack}" font-size="22" font-weight="700" letter-spacing="3" fill="#3c322a">蔵</text>
    <text x="34" y="0" font-family="${sansStack}" font-size="20" font-weight="700" letter-spacing="4" fill="#7a6d5e">${escapeHtml(kicker)}</text>
  </g>
  <text font-family="${sansStack}" font-size="${fontSize}" font-weight="700" fill="#3c322a">${titleLines}</text>
  ${dateLine}
  <g transform="translate(96 528)">
    <rect x="-20" y="-34" width="430" height="74" rx="20" fill="#fffdf6" stroke="#3c322a" stroke-width="3"/>
    <text x="0" y="-2" font-family="${serifStack}" font-size="24" font-weight="700" letter-spacing="2" fill="#3c322a">Kura 蔵 · くら</text>
    <text x="0" y="24" font-family="${sansStack}" font-size="15" font-weight="700" letter-spacing="3" fill="#7a6d5e">kura.run · BUILT BY TUIST</text>
  </g>
</svg>`;
}

async function writeImage(svg, logoBuffer, outputPath) {
  const image = await sharp(Buffer.from(svg))
    .composite([{ input: logoBuffer, left: 928, top: 250 }])
    .png()
    .toBuffer();

  let existing = null;

  try {
    existing = await fs.readFile(outputPath);
  } catch {}

  if (!existing || !existing.equals(image)) {
    await fs.writeFile(outputPath, image);
  }
}

function fileSlugWithoutDate(value) {
  return path.basename(value, path.extname(value)).replace(/^\d{4}-\d{2}-\d{2}-/, "");
}

async function renderPageImage(pagePath, logoBuffer) {
  const source = await fs.readFile(pagePath, "utf8");
  const { data } = matter(source);

  if (!data.socialImageFile || !data.socialTitle || !data.socialKicker) {
    return null;
  }

  const localeKey = pagePath.includes(`${path.sep}ja${path.sep}`) ? "ja" : "en";
  const svg = renderSvg({
    title: data.socialTitle,
    kicker: data.socialKicker,
    localeKey,
  });
  const outputPath = path.join(outputDir, data.socialImageFile);
  await writeImage(svg, logoBuffer, outputPath);
  return data.socialImageFile;
}

async function renderPostImage(postPath, logoBuffer) {
  const source = await fs.readFile(postPath, "utf8");
  const { data } = matter(source);

  if (!data.title) return null;

  const localeKey = postPath.includes(`${path.sep}ja${path.sep}`) ? "ja" : "en";
  const imageFile = `${fileSlugWithoutDate(postPath)}-${localeKey}.png`;
  const svg = renderSvg({
    title: data.title,
    kicker: data.socialKicker || (localeKey === "ja" ? "KURA ・ ブログ" : "KURA · BLOG"),
    date: formatDate(data.date, localeKey === "ja" ? "ja-JP" : "en-US"),
    localeKey,
  });
  const outputPath = path.join(outputDir, imageFile);
  await writeImage(svg, logoBuffer, outputPath);
  return imageFile;
}

export async function generateSocialImages() {
  await fs.mkdir(outputDir, { recursive: true });

  const expected = new Set();
  const logoBuffer = await sharp(logoPath)
    .resize(260, 260, {
      fit: "contain",
      background: { r: 0, g: 0, b: 0, alpha: 0 },
    })
    .png()
    .toBuffer();
  const postPaths = [
    ...(
      await fs.readdir(path.join(srcDir, "en", "blog", "posts"))
    ).map((file) => path.join(srcDir, "en", "blog", "posts", file)),
    ...(
      await fs.readdir(path.join(srcDir, "ja", "blog", "posts"))
    ).map((file) => path.join(srcDir, "ja", "blog", "posts", file)),
  ].filter((file) => /\.(md|njk)$/.test(file));

  for (const pagePath of pagePaths) {
    const output = await renderPageImage(pagePath, logoBuffer);
    if (output) expected.add(output);
  }

  for (const postPath of postPaths) {
    const output = await renderPostImage(postPath, logoBuffer);
    if (output) expected.add(output);
  }

  const generated = (await fs.readdir(outputDir)).filter((file) => file.endsWith(".png"));

  await Promise.all(
    generated
      .filter((file) => !expected.has(file))
      .map((file) => fs.rm(path.join(outputDir, file))),
  );
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  await generateSocialImages();
}
