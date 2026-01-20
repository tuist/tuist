---
{
  "title": "Hashing",
  "titleTemplate": ":title · Projects · Features · Guides · Tuist",
  "description": "Learn about Tuist's hashing logic upon which features like binary caching and selective testing are built."
}
---
# Hashing {#hashing}

Features like
<LocalizedLink href="/guides/features/cache">caching</LocalizedLink> or
selective test execution require a way to determine whether a target has
changed. Tuist calculates a hash for each target in the dependency graph to
determine if a target has changed. The hash is calculated based on the following
attributes:

- The target's attributes (e.g., name, platform, product, etc.)
- The target's files
- The hash of the target's dependencies

### Cache attributes {#cache-attributes}

Additionally, when calculating the hash for
<LocalizedLink href="/guides/features/cache">caching</LocalizedLink>, we also
hash the following attributes.

#### Swift version {#swift-version}

We hash the Swift version obtained from running the command `/usr/bin/xcrun
swift --version` to prevent compilation errors due to Swift version mismatches
between the targets and the binaries.

::: info MODULE STABILITY
<!-- -->
Previous versions of binary caching relied on the
`BUILD_LIBRARY_FOR_DISTRIBUTION` build setting to enable [module
stability](https://www.swift.org/blog/library-evolution#enabling-library-evolution-support)
and enable using binaries with any compiler version. However, it caused
compilation issues in projects with targets that don't support module stability.
Generated binaries are bound to the Swift version used to compile them, and the
Swift version must match the one used to compile the project.
<!-- -->
:::

#### Configuration {#configuration}

The idea behind the flag `-configuration` was to ensure debug binaries were not
used in release builds and viceversa. However, we are still missing a mechanism
to remove the other configurations from the projects to prevent them from being
used.

## Debugging {#debugging}

If you notice non-deterministic behaviors when using the caching across
environments or invocations, it might be related to differences across the
environments or a bug in the hashing logic. We recommend following these steps
to debug the issue:

1. Run `tuist hash cache` or `tuist hash selective-testing` (hashes for
   <LocalizedLink href="/guides/features/cache">binary caching</LocalizedLink>
   or <LocalizedLink href="/guides/features/selective-testing">selective testing</LocalizedLink>), copy the hashes, rename the project directory, and
   run the command again. The hashes should match.
2. If the hashes don't match, it's likely that the generated project depends on
   the environment. Run `tuist graph --format json` in both cases and compare
   the graphs. Alternatively, generate the projects and compare their
   `project.pbxproj` files with a diff tool such as
   [Diffchecker](https://www.diffchecker.com).
3. If the hashes are the same but differ across environments (for example, CI
   and local), make sure the same [configuration](#configuration) and [Swift
   version](#swift-version) are used everywhere. The Swift version is tied to
   the Xcode version, so confirm the Xcode versions match.

If the hashes are still non-deterministic, let us know and we can help with the
debugging.


::: info BETTER DEBUGGING EXPERIENCE PLANNED
<!-- -->
Improving our debugging experience is in our roadmap. The print-hashes command,
which lacks the context to understand the differences, will be replaced by a
more user-friendly command that uses a tree-like structure to show the
differences between the hashes.
<!-- -->
:::
