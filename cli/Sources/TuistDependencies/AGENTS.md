# TuistDependencies

Keep external dependency project settings (including `SRCROOT`) consistent after mapping.

- External projects under SwiftPM scratch-directory checkouts are remapped into derived dependencies directories.
- Local packages outside SwiftPM scratch-directory checkouts are not remapped.
- Only local package tests with destinations inferred from production consumers extend the external dependency graph. Preserve their dependency closure across package boundaries for those effective platforms; prune tests with no inferred destinations and their otherwise unused dependencies. Narrowing and pruning share this eligibility calculation.
- Production traversal destinations take precedence for targets already reached by production consumers. Tests may use the union of disjoint dependency platforms and propagate it to test-only dependencies, but must not widen production targets or their deployment targets.
