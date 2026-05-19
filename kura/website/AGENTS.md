# Kura Website

This node covers the `kura/website/` subtree, a localized Eleventy site for Kura with English and Japanese routes, blog feeds, and generated social cards.

## Key Boundaries
- Site metadata and shared copy: `src/_data/`
- Shared layouts and reusable presentation components: `src/_includes/`
- Locale roots and public routes: `src/en/`, `src/ja/`
- Styling and cursor-beam behavior: `src/assets/styles.css`, `src/assets/beam.js`
- Generated OG card pipeline: `scripts/generate-social-images.mjs`
- Static assets copied to the final site: `src/public/`

## Development
- Install dependencies with `aube install`
- Run the local dev server with `aube run dev`
- Produce a production build with `aube run build`
- Regenerate social images only with `aube run social:images`

## Deployment
- Tooling is pinned in `.mise.toml`; `mise/tasks/*.sh` wrap the `aube run` scripts
- `.github/workflows/kura-website.yml` builds on every PR and deploys to Cloudflare Pages on `main` (project `kura`, served at `kura.run`)
- The deploy uploads `_site/` plus `functions/` (Pages Middleware) via `wrangler pages deploy`; the Cloudflare Pages project root must be `kura/website`

## Maintenance Notes
- Keep English and Japanese routes in parity when adding new pages or posts
- If you change front matter fields used by the OG script, update `scripts/generate-social-images.mjs` in the same change
- Favor shared copy in `src/_data/copy.js` for page-level localization; keep post-level localization in paired locale files under `src/en/blog/posts/` and `src/ja/blog/posts/`
- Preserve the language switcher and `alternates` metadata so canonical and feed links stay correct across locales
