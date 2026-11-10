# Noora

Phoenix LiveView component library published to Hex. The server uses a local path
dependency, so changes here affect `server/` directly. Component code lives in
`lib/`, hooks in `js/`, styles in `css/`, and built assets in `priv/static/`.

- Build: `mise run noora:build` (JS dependencies, assets, and Elixir compilation).
- JS tests: `mise run noora:test`.
- Formatting: `mise run noora:lint` or `mise run noora:lint --fix`.
- Preview components in `storybook/`. Its independent deployment is defined by
  `infra/helm/noora-storybook/` and `.github/workflows/noora-storybook-deployment.yml`.
- `.github/workflows/noora-release.yml` stamps the version into `mix.exs` and publishes
  to Hex; releases use `cliff.toml` for changelogs. `package.json` is private and is
  never published to npm.

## Component contracts

- Right-to-left documents set `dir="rtl"` on `<html>`. Style the inline axis with
  logical properties (`margin-inline-start`, `inset-inline-end`, `text-align: start`);
  keep physical values only where JS or Zag positions in physical pixels, and say so.
  Zag machines inherit `dir` in `js/machine.js`. Directional icons are listed in
  `@rtl_mirrored_icons` (`lib/noora/icon.ex`) and mirror with the CSS `scale`
  property so rotations still compose.
- Share table/chart thumb sizing and dragging through `ScrollIndicator.js` and
  `css/scroll_indicator.css`; tables trigger updates explicitly so hidden overlays
  do not measure on scroll.
- Sidebars persist vertical scroll per ID in tab-scoped session storage unless
  `persist_scroll={false}`. Ordinary scroll areas persist only with
  `data-scroll-persist-key`. Restore through child hydration, cancel on user input,
  keep hidden mobile sidebars from overwriting desktop positions, tolerate storage
  failures, and remove listeners on teardown.
- Initialize selects with server values and sync explicit changes, not unchanged
  echoes that would overwrite newer client choices. Keep hidden select and label
  synchronized so untouched defaults submit.
- Forward textarea `autocomplete`/`autocorrect` and text-input `readonly`. Textarea
  overlays start hidden, inert, and aria-hidden; no overlay leaves behavior unchanged.
- Toggle root labels render Zag's `switch:<id>` from the start to preserve focus
  across patches. Icon transitions restore state even after unchanged-state patches.
- Input suffix-help triggers stay keyboard-focusable at `bottom-end`; keep tooltip
  content in normal positioner flow so collision measurement includes its full size.
- Table `row_toggle` callbacks enable server-owned lazy `expanded_rows`; tables
  without callbacks retain client-side expansion.
- `Noora.Icon` uses per-SVG `@external_resource` and `__mix_recompile__?/0` for
  additions/removals, never the directory itself (Mix cannot digest directories).
  Brand SVGs use monochrome filled `currentColor` and `brand_<name>/1` helpers.
- Delegate date-picker navigation from the hook root so patched controls still work.
- Charts initialize near the viewport only when `data-lazy="true"`; offscreen
  updates/destruction remain safe and resize listeners register once per lifetime.
- Calendar tooltips use UTC period starts with `dateFormat: "day" | "week" | "month"`
  (weeks show ranges), alongside minute/hour modes. Plain numeric tooltips/value
  axes humanize from 10,000 with K/M/B/T (up to one decimal); percentage templates
  round to at most one decimal without changing data. Preserve explicit unit
  formats, category/time axes, and numeric series values.
- Text-filter update forms set `autocomplete="off"` to keep browser history out of
  their popover; rendered-form tests must not depend on attribute order.
