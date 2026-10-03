# Atlas documentation source

These English Markdown pages are public at `/docs`. They describe Atlas for people evaluating or operating their own organizational workspace.

- Publish the overview and self-hosting guide. Other draft guides remain under `plans/atlas-documentation-drafts/` until their implementation and validation are ready.
- Keep installation instructions consistent with the implemented configuration and release commands. Clearly distinguish implemented behavior from planned self-hosting work.
- Write guides around the reader's sequence of decisions and actions. Explain why a setting or command is needed where the reader uses it, and keep optional services separate from the initial installation.
- Link named tools and services to their official documentation when introducing them in a section, so readers can follow unfamiliar terms.
- Register a new page in `AtlasWeb.DocsHTML` alongside its title, category, sidebar section, and description. Categories are Guides, References, and Explanations. Regenerate social preview images with `mix atlas.docs.images` after changing page titles or descriptions. The module tracks source files and compiles sanitized markup into the release; do not read the source from disk on each request.
- Use unique, plain-text second-level headings for the table of contents. Their identifiers are lowercase words separated by hyphens. Link to other documentation pages using `/docs/...` paths.
- Keep public content free of private credentials, customer examples, and internal operational destinations. Explain provider configuration using organizational examples.
- Verify anonymous access, heading targets, mobile navigation, and theme rendering when changing structure. Documentation has a separate Noora bundle under `assets/css/docs/` and `assets/js/docs.js`.
