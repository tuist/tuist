---
{
  "title": "Docs",
  "titleTemplate": ":title · Code · Contributors · Tuist",
  "description": "Contribute to the Tuist documentation site."
}
---
# Docs {#docs}

Source: [github.com/tuist/tuist/tree/main/server/priv/docs](https://github.com/tuist/tuist/tree/main/server/priv/docs)

## What it is for {#what-it-is-for}

The docs site hosts Tuist's product and contributor documentation. It is part of the Tuist server, a Phoenix application, which renders the Markdown pages under `server/priv/docs/en` at `/docs`.

## How to contribute {#how-to-contribute}

Edit the English pages under `server/priv/docs/en`. Translations are managed separately, so don't edit the other locale directories. The sidebar is defined in `server/lib/tuist/docs_sidebar.ex`; add new pages there so readers can find them.

When several pages share the same text, for example the same section across build systems, put it in a file whose name starts with `_` next to those pages and include it with a `@snippet:` HTML comment that points to the file, as the flaky tests pages do. Files starting with `_` are not published as pages on their own.

### Set up locally {#set-up-locally}

Run the server from the `server` directory, following its [setup instructions](https://github.com/tuist/tuist/blob/main/server/AGENTS.md):

```bash
cd server
mise install
mise run dev
```

Then open [http://localhost:8080/en/docs](http://localhost:8080/en/docs).

### Generated content {#generated-content}

The CLI reference is generated from the command spec of the latest CLI release, so it doesn't need to be built locally.

The ProjectDescription API reference is hosted separately as a DocC site at [projectdescription.tuist.dev](https://projectdescription.tuist.dev). To build it locally, run `mise run docs:project-description` from the repository root.
