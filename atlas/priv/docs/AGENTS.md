# Atlas documentation source

These English Markdown pages are public at `/docs`. They describe Atlas for people evaluating or operating their own organizational workspace.

- Publish only the overview while decoupling is in progress. Keep its status in one Noora Markdown alert instead of repeated feature sections. Draft guides are retained under `plans/atlas-documentation-drafts/`; do not expose deployment instructions or category navigation until those pages are ready.
- Keep installation instructions consistent with the implemented configuration and release commands. Clearly distinguish implemented behavior from planned self-hosting work.
- Register a new page in `AtlasWeb.DocsHTML` alongside its title, category, sidebar section, and description. Categories are Guides, References, and Explanations. Regenerate social preview images with `mix atlas.docs.images` after changing page titles or descriptions. The module tracks source files and compiles sanitized markup into the release; do not read the source from disk on each request.
- Use unique, plain-text second-level headings for the table of contents. Their identifiers are lowercase words separated by hyphens. Link to other documentation pages using `/docs/...` paths.
- Keep public content free of private credentials, customer examples, and internal operational destinations. Explain provider configuration using organizational examples.
- Verify anonymous access, heading targets, mobile navigation, and theme rendering when changing structure. Documentation has a separate Noora bundle under `assets/css/docs/` and `assets/js/docs.js`.
