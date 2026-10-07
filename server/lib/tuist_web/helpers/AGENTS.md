# Helpers (Web Layer)

This area owns helper functions for views, forms, and UI utilities.

## Responsibilities
- Provide helpers for formatting, rendering, and UI convenience.
- `VCSLinks.source_file_link/1` links repository-relative paths at the supplied commit or branch. Encode each path/ref segment (including literal percent signs), and keep absolute paths, traversal, backslashes, and control characters as plain text. Filenames may include spaces, Unicode, URL delimiters, and hidden directories.
- `TestLabels.test_run_label/2` keeps Mix execution variants visible as `mix test · <label>`, with `mix test` for absent labels. Scheme filtering remains disabled for Mix.
- `ModuleCache.analytics_period_assigns/2` reuses the relative period already displayed by the picker across presentation-only patches. Passing empty assigns explicitly refreshes the snapshot, including reapplying the same preset; custom bounds always come from DatePicker. `with_hit_rates/1` shares daily percentage formatting between both module-cache pages.
- Build deterministic signed Open Graph image URLs from template variables supplied by controllers and LiveViews. Project tokens bind the project ID and handle, rotate weekly, expire after 400 days, and fall back to generic cards if their path exceeds 2,000 bytes. Marketing/docs tokens stay stable and non-expiring; keep verification of already-published separate-variable signatures.

## Boundaries
- Domain logic belongs in `server/lib/tuist` contexts.
- Frontend assets are in `server/assets`.

## Related Context
- Web layer overview: `server/lib/tuist_web/AGENTS.md`
- Business logic: `server/lib/tuist/AGENTS.md`

- `GradleTask` shares task outcome labels and colors between build tables, task overviews, and individual execution details.
- `ModuleCache` shares miss-reason definitions and comparison limitations between module overview widgets and per-module history, including the evidence-based Evicted state (use `evicted` consistently for reason identifiers and URL parameters). Keep tooltips brief and specific to the selected reason; the module-cache analytics guide owns detailed comparison limits and optimization advice.

- `CldrHelpers.format_number/2` compacts display counts from 10,000 upward with K/M/B/T suffixes and up to one decimal, preserving locale separators. Keep money, percentages, identifiers, and underlying numeric data in their dedicated formats.
