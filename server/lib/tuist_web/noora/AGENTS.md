# Noora documentation (Web Layer)

This area serves the Noora design system documentation at `/noora` and `/noora/:page`.

## Responsibilities
- `NooraLive` renders every page inside the docs frame (`Components.docs_shell/1`): header, sidebar with ⌘K page search, and the article. It reuses the marketing root layout and bundle, so Noora's styles and hooks, the theme bootstrap, and the `CodeCopy` and `ThemeSwitcher` hooks are already available. Styles live in `server/assets/marketing/css/routes/noora.css`.
- `Pages` lists the pages in sidebar order. Add a page module there when adding a page; `noora_live_test.exs` renders every registered page.
- A page is a module that does `use TuistWeb.Noora.Page` (see its moduledoc). Component pages declare `components:` and `example` blocks; the introduction and foundations pages define `content/1`.

## Single sources of truth
- Component API tables are read from each component's `attr` and `slot` declarations through `__components__/0`. Fix a wrong or unclear description in the component's `doc:` string in `noora/lib/noora`, not on the page.
- Each `example` block is one `~H` sigil. The macro renders it live and keeps its exact source for the code panel, so the shown code is always what renders. Examples receive no assigns: inline their data as literals, and give hooked elements ids that are unique across the page.
- Foundations pages read `noora/css/tokens.css` at compile time through `Tokens`, grouped by the stylesheet's section comments. Keep those comments accurate when reorganizing the tokens.

## Boundaries
- English only, outside the localized marketing routes. The `:browser_noora` pipeline neither redirects to a locale nor stores a locale preference.
- Unlisted for now: pages render `noindex`, routes opt out of `robots.txt`, and nothing links to `/noora` from the marketing site.
- Examples run real components. Events they emit reach a catch-all `handle_event/3` that ignores them, so examples must work client-side through Noora's hooks or `Phoenix.LiveView.JS`.

## Related Context
- Component library: `noora/AGENTS.md`
- Marketing web layer: `server/lib/tuist_web/marketing/AGENTS.md`
