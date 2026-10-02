# Cache globe

The public marketing page at `/globe` turns cache reuse into a live display. `/globe?demo=true` runs a clearly labeled illustrative demonstration. Demo data never enters the database or the shared statistics service.

## Data

`CacheGlobe.snapshot/1` reads `kura_usage_events`, which already stores the serving region, request count, byte count, and reporting window. It exposes only totals for the seven public managed serving regions (the ones Kura enables in production), each placed at its datacenter's city. Private runner regions, unknown regions, uploads, and peer replication are excluded. Region coordinates represent serving areas; they are not developer locations or precise machine locations.

The large counter is **download requests**, not unique binaries, builds, or estimated time saved. Requests can include partial or repeated downloads and different cache artifact kinds. The byte total measures delivery, not unique stored bytes. Both cover reporting windows starting since midnight in Coordinated Universal Time. The recent total covers windows starting in the last five minutes. Usage is reported in batches, so neither the counter nor the lights claims to represent individual transfers at their exact occurrence time.

The query uses `FINAL` to deduplicate retried rollups in the existing replacing table. It has a ten-second execution bound, a fifteen-second client timeout, two query threads, and a 256-mebibyte memory limit. The marketing poller refreshes every 30 seconds and explicitly uses the shared Redis cache when configured. Its 30-second lock lease outlasts the query timeout, and competing refreshes wait up to 30 seconds before failing. Without Redis, the existing in-memory fallback caches per server process. Viewer count does not change polling frequency. No new customer data or retention policy is introduced. The cached snapshot contains only public region totals. The existing older marketing artifact counter remains separate because its underlying daily aggregate counts both uploads and downloads.

When no snapshot exists, the page shows waiting and no invented value. Query failures preserve the last successful snapshot and mark it unavailable. Browser disconnects and aging observations have distinct reconnecting and delayed states. The globe pauses activity lights when its data is no longer current.

## Visual direction

The page follows the redesigned marketing site's frame without its chrome: only the wordmark linking home above the cache page's hero skeleton (copy bottom-left on a 600px card) and an activity frame of hairline rows for the counters, the seven serving regions, the status line and the display controls. No shared navbar, footer or CTA, so it can stay on a screen. Everything uses Noora tokens and works in both themes.

The globe is the cache page's `DitherGlobe` hook — the stippled sphere on the marketing dither ramp — placed on the hero's right side and bleeding into the card's fade. The page's `CacheGlobe` hook feeds it the seven public serving regions as markers (`data-markers`, then `dither-globe:markers` events): a region with downloads in the last five minutes pulses, an idle one keeps a dim core. Request origins — places requests come from — draw as small white dots that launch arcs to their serving region at their measured rate; the region cells count the arcs as they land and re-sync to the measured five-minute counts on every snapshot. The snapshot carries no origins until the usage rollups record a request's country, so live data draws no arcs; demo mode uses illustrative origins. Nothing connects regions to invented destinations.

Earlier research into Shopify's BFCM globes (layered atmosphere, aggregate-once-then-distribute streaming) informed the data flow; none of that imagery ships with the page.

## Verification

Run the focused marketing globe, marketing statistics, runtime children, and globe LiveView test files. Launch the server with `mise run dev`, open both `/globe` and `/globe?demo=true` in headless Chrome, and capture desktop and mobile screenshots. Local development does not start the shared marketing poller by default, so its live page correctly starts in a waiting state. Check pause/resume, reduced motion, full screen, reconnecting, stale data, both themes, and navigation cleanup.
