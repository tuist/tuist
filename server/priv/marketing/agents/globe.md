# Tuist cache activity globe

A public visualization of aggregate Tuist cache activity. It is not a project-level analytics report.

## What the display means

The [globe page](/globe) combines aggregate cache metrics with animation. Live regional data uses delayed, privacy-thresholded country-level estimates; per-second counters between reports are estimates from recent measured rates. Some arcs are decorative and do not represent individual transfers. Adding `?demo=true` shows illustrative data only.

## When to use it

Use it to illustrate a shared cache serving many environments. To decide whether caching will help a specific project, read [Cache](/marketing-markdown/cache) and measure your own builds.

## Limitations

Do not read an arc as a specific transfer, request location, or customer build. Missing live data is not a measured zero. This guide does not copy live counters. For your own cache behavior, use the project's cache dashboards and [Build Insights](/en/docs-markdown/guides/features/build-insights).
