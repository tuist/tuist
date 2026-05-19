import { readdir, readFile } from "node:fs/promises";
import { fileURLToPath } from "node:url";
import path from "node:path";
import matter from "gray-matter";
import site from "./site.js";
import copy from "./copy.js";

const here = path.dirname(fileURLToPath(import.meta.url));

const abs = (p) => new URL(p, site.url).toString();
const ymd = (d) => new Date(d).toISOString().slice(0, 10);
const stripDatePrefix = (file) =>
  file.replace(/^\d{4}-\d{2}-\d{2}-/, "").replace(/\.md$/, "");

const localeConfig = {
  en: {
    code: "en",
    home: "/",
    blog: "/blog/",
    postsDir: path.join(here, "..", "en", "blog", "posts"),
    post: (slug) => `/blog/${slug}/`,
  },
  ja: {
    code: "ja",
    home: "/ja/",
    blog: "/ja/blog/",
    postsDir: path.join(here, "..", "ja", "blog", "posts"),
    post: (slug) => `/ja/blog/${slug}/`,
  },
};

async function readPosts(cfg) {
  const files = (await readdir(cfg.postsDir))
    .filter((f) => f.endsWith(".md"))
    .sort()
    .reverse();

  const posts = [];
  for (const file of files) {
    const raw = await readFile(path.join(cfg.postsDir, file), "utf8");
    const { data, content } = matter(raw);
    const slug = stripDatePrefix(file);
    const htmlUrl = cfg.post(slug);
    posts.push({
      slug,
      title: data.title,
      description: data.description,
      author: data.author || site.author,
      date: data.date,
      htmlUrl,
      mdUrl: `${htmlUrl}index.md`,
      body: content.trim(),
    });
  }
  return posts;
}

function homeMarkdown(code, cfg, posts) {
  const c = copy.home;
  const chips = c.hero.chips
    .map((chip) => `- **${chip[code]}**: ${chip.desc[code]}`)
    .join("\n");
  const langs = c.languages.items.map((i) => i.name).join(", ");
  const story = c.why.story[code].join("\n\n");
  const blogList = posts
    .slice(0, 5)
    .map(
      (p) =>
        `- [${p.title}](${abs(p.htmlUrl)}) (${ymd(p.date)}): ${p.description}`,
    )
    .join("\n");
  const blogSection = posts.length
    ? `\n\n## Latest from the blog\n\n${blogList}`
    : "";

  return `# Kura

_${site.tagline}_

> ${site.description}

- Website: ${abs(cfg.home)}
- Architecture: ${site.architecture}
- README: ${site.readme}
- Source code: ${site.repo}
- Hosted by Tuist: ${site.tuist}

## What Kura is

${c.hero.title[code]}

${c.hero.body[code]}

${c.hero.note[code]}

## What makes it different

${chips}

## Languages Kura speeds up

${c.languages.intro[code]}

${langs}.

## Why we built Kura

**${c.why.intro[code]}**

${story}

## ${c.hosted.title[code]}

${c.hosted.body[code]}

${c.hosted.cta[code]}: ${site.tuist}${blogSection}
`;
}

function blogIndexMarkdown(code, cfg, posts) {
  const c = copy.blogIndex;
  const list = posts
    .map(
      (p) =>
        `- [${p.title}](${abs(p.htmlUrl)}) (${ymd(p.date)}): ${p.description}\n  Markdown: ${abs(p.mdUrl)}`,
    )
    .join("\n");
  const postsSection = posts.length ? `## Posts\n\n${list}\n\n` : "";

  return `# Kura Blog

> ${c.intro[code]}

${c.title[code]}

${postsSection}Back to Kura: ${abs(cfg.home)}
`;
}

function postMarkdown(post, cfg) {
  return `# ${post.title}

> ${post.description}

${ymd(post.date)} · ${post.author} · Kura Blog

${post.body}

---

Canonical page: ${abs(post.htmlUrl)}
Back to the blog: ${abs(cfg.blog)}
Kura: ${abs(cfg.home)}
`;
}

export default async function () {
  const docs = [];

  for (const code of Object.keys(localeConfig)) {
    const cfg = localeConfig[code];
    const posts = await readPosts(cfg);

    docs.push({
      kind: "home",
      locale: code,
      title: code === "ja" ? "Kura (日本語)" : "Kura",
      description: site.description,
      pageUrl: cfg.home,
      mdUrl: `${cfg.home}index.md`,
      markdown: homeMarkdown(code, cfg, posts),
    });

    docs.push({
      kind: "blog",
      locale: code,
      title: code === "ja" ? "Kura ブログ" : "Kura Blog",
      description: copy.blogIndex.intro[code],
      pageUrl: cfg.blog,
      mdUrl: `${cfg.blog}index.md`,
      markdown: blogIndexMarkdown(code, cfg, posts),
    });

    for (const post of posts) {
      docs.push({
        kind: "post",
        locale: code,
        title: post.title,
        description: post.description,
        date: post.date,
        pageUrl: post.htmlUrl,
        mdUrl: post.mdUrl,
        markdown: postMarkdown(post, cfg),
      });
    }
  }

  return docs;
}
