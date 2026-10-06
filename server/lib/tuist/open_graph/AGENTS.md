# Open Graph Project Cards

- `ProjectImage` renders self-contained, HTML-escaped cards using bundled fonts and inline SVGs. It must not load customer URLs in the headless browser.
- `OpenGraphImageTemplates` binds both the project ID and current handle, verifies public visibility on every image request, and includes the renderer module in the asset digest.
- `OpenGraphImages` stores project cards under `open-graph-images/projects/`; marketing/docs keep their existing shared prefix. The daily retention worker sweeps only project cards after 30 days, in bounded pages with continuation tokens.
- Public visibility does not make member-only configuration public. Do not put automation conditions, names, or enabled state in project cards.

Related: [business logic](../AGENTS.md), [web helpers](../../tuist_web/helpers/AGENTS.md), and [data export](../../../data-export.md).
