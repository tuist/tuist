# Problem-focused marketing guides

These English sources are served at `/marketing-markdown/solutions/<slug>` and as English-only browser pages at `/solutions/<slug>`. Follow the parent `AGENTS.md` for delivery and measurement.

- Lead with how Tuist addresses the user's symptom and the supported Tuist adoption path, then explain diagnostic measurements. Map interventions to documented features and toolchain requirements; do not turn troubleshooting advice into competitor recommendations.
- Make project optimization first and execution-environment optimization second explicit. Use Gradle, Bazel, and Elixir examples as well as Xcode, preserve actual support limits, and distinguish project repair from capacity, locality, and parallelism changes. Cost guidance links to sourced billing units and includes Tuist's own charges, allowances, and fixed-fee exceptions.
- Include `## Diagnose`, `## Investigate with an agent`, and `## First experiment` sections. Open with why the problem happens and how Tuist addresses it, close with further reading and a `## Frequently asked questions` section of four to six real questions, which becomes the page's FAQPage structured data. Integrate prerequisites into the relevant feature or adoption step rather than adding a Limitations section. Link to feature guides instead of duplicating full setup instructions or support matrices.
- Distinguish insight from automatic optimization, build outputs from persistent directories, selective testing from line-level impact analysis, sharding from reduced total work, and quarantine from fixing a test.
- Agent examples must name tools present in the MCP documentation and distinguish reading evidence from authorized writes. Mention separate integration authentication when relevant.
- Cost guidance must use measured total usage and current commercial terms, not guaranteed savings. Link the live pricing table for runner rates instead of restating them.
- The marketing maintainers own these guides. Review them alongside changes to linked feature guides; review the complete set quarterly.
- New files automatically enter the Markdown discovery inventory. Update inventory assertions and test explicit Markdown delivery, the English-only browser page and sitemap entry, and `/llms.txt` discovery.
