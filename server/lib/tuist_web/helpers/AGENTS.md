# Helpers (Web Layer)

This area owns helper functions for views, forms, and UI utilities.

## Responsibilities
- Provide helpers for formatting, rendering, and UI convenience.
- `ModuleCache.analytics_period_assigns/2` keeps a page's relative date snapshot stable across presentation-only patches and reparses custom bounds when the date selection changes.
- Build deterministic signed Open Graph image URLs from template variables supplied by controllers and LiveViews.

## Boundaries
- Domain logic belongs in `server/lib/tuist` contexts.
- Frontend assets are in `server/assets`.

## Related Context
- Web layer overview: `server/lib/tuist_web/AGENTS.md`
- Business logic: `server/lib/tuist/AGENTS.md`

- `GradleTask` shares task outcome labels and colors between build tables, task overviews, and individual execution details.
- `ModuleCache` shares miss-reason definitions and comparison limitations between module overview widgets and per-module history, including the evidence-based Evicted state (use `evicted` consistently for reason identifiers and URL parameters). Keep tooltips brief and specific to the selected reason; the module-cache analytics guide owns detailed comparison limits and optimization advice.
