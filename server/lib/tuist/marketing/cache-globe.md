# Cache globe

The public marketing page at `/globe` turns cache reuse into a conference display. `/globe?demo=true` runs a clearly labeled illustrative demonstration. Demo data never enters the database or the shared statistics service.

## Data

`CacheGlobe.snapshot/1` reads `kura_usage_events`, which already stores the serving region, request count, byte count, and reporting window. It exposes only totals for the five public managed serving regions. Private runner regions, unknown regions, uploads, and peer replication are excluded. Region coordinates represent serving areas; they are not developer locations or precise machine locations.

The large counter is **download requests**, not unique binaries, builds, or estimated time saved. Requests can include partial or repeated downloads and different cache artifact kinds. The byte total measures delivery, not unique stored bytes. Both cover reporting windows starting since midnight in Coordinated Universal Time. The recent total covers windows starting in the last five minutes. Usage is reported in batches, so neither the counter nor the lights claims to represent individual transfers at their exact occurrence time.

The query uses `FINAL` to deduplicate retried rollups in the existing replacing table. It has a ten-second execution bound, two query threads, and a 256-mebibyte memory limit. The marketing poller refreshes every 30 seconds; the existing shared key-value cache coalesces concurrent refreshes across server processes. Viewer count does not change polling frequency. No new customer data or retention policy is introduced. The cached snapshot contains only public region totals. The existing older marketing artifact counter remains separate because its underlying daily aggregate counts both uploads and downloads.

When no snapshot exists, the page shows waiting and no invented value. Query failures preserve the last successful snapshot and mark it unavailable. Browser disconnects and aging observations have distinct reconnecting and delayed states. The globe pauses activity lights when its data is no longer current.

## Visual direction and references

- [Shopify's globe rendering breakdown](https://shopify.engineering/bfcm-3d-data-visualization): layered atmosphere, geographic particles, and bounded animation complexity.
- [Shopify's 2023 globe overview and video](https://www.shopify.com/news/shopify-s-bfcm-globe-brings-commerce-to-life-like-never-before-heres-how-our-engineers-built-it): an engaging planetary scene paired with readable business counters.
- [Shopify's rotating Earth layer demonstration](https://www.youtube.com/watch?v=N4oeDV4rNQo): directional lighting and a continuous atmospheric edge as the planet rotates. Inspected frames across the 20-second demonstration.
- [Shopify's streaming data architecture](https://shopify.engineering/bfcm-live-map-2021-apache-flink-redesign): aggregate activity once, then distribute it to displays.

The Tuist version uses its own purple palette, brand assets, and typography. The globe rotates in the browser using the existing `cobe` dependency. Light trails leave a serving region radially and never connect to an invented destination. Region bars show relative recent volume, not a fabricated historical trend. Shopify imagery is research material and is not shipped with the page.

## Verification

Run the focused marketing globe, marketing statistics, runtime children, and globe LiveView test files. Launch the server with `mise run dev`, open both `/globe` and `/globe?demo=true` in headless Chrome, and capture desktop and mobile screenshots. Check pause/resume, reduced motion, full screen, reconnecting, stale data, rendering fallback, and navigation cleanup. Local development does not start the shared marketing poller by default, so its live page correctly starts in a waiting state.
