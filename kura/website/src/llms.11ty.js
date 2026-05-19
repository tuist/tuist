import site from "./_data/site.js";

const abs = (p) => new URL(p, site.url).toString();

export default class {
  data() {
    return {
      permalink: "/llms.txt",
      eleventyExcludeFromCollections: true,
    };
  }

  render({ agentDocs }) {
    const byKind = (kind, locale) =>
      agentDocs.filter((d) => d.kind === kind && d.locale === locale);

    const line = (d) => `- [${d.title}](${abs(d.mdUrl)}): ${d.description}`;

    const sitePages = [
      ...byKind("home", "en"),
      ...byKind("home", "ja"),
      ...byKind("blog", "en"),
      ...byKind("blog", "ja"),
    ]
      .map(line)
      .join("\n");

    const posts = agentDocs
      .filter((d) => d.kind === "post" && d.locale === "en")
      .map(line)
      .join("\n");
    const postsSection = posts ? `## Blog posts\n\n${posts}\n\n` : "";

    return `# Kura

> ${site.tagline}

${site.description}

Every page on this site has a Markdown version: append \`index.md\` to any page URL, or send \`Accept: text/markdown\`. Japanese translations live under \`/ja/\`.

## Site

${sitePages}

${postsSection}## Reference

- [Architecture](${site.architecture}): How Kura works, from a high level down to the runtime, replication, and rollout details.
- [README](${site.readme}): Setup, configuration, the runtime model, and operational limits.
- [Source code](${site.repo}): The Kura implementation, a Rust service for low-latency cache meshes.
- [Hosted by Tuist](${site.tuist}): Let Tuist run a managed Kura mesh for your teams.
`;
  }
}
