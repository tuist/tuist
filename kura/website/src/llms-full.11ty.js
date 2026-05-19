import site from "./_data/site.js";

export default class {
  data() {
    return {
      permalink: "/llms-full.txt",
      eleventyExcludeFromCollections: true,
    };
  }

  render({ agentDocs }) {
    const order = { home: 0, blog: 1, post: 2 };
    const sorted = [...agentDocs].sort(
      (a, b) =>
        (a.locale === "en" ? 0 : 1) - (b.locale === "en" ? 0 : 1) ||
        order[a.kind] - order[b.kind],
    );

    const header = `# Kura, full text for agents

> ${site.tagline}

This file concatenates every page of ${site.url} as Markdown.

`;

    return (
      header +
      sorted
        .map((d) => `${d.markdown.trim()}\n`)
        .join("\n---\n\n")
    );
  }
}
