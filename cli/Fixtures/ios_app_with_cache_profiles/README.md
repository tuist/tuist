# Cache Profiles Fixture

This fixture demonstrates configuring cache profiles.

## What it contains:

- An internal framework `ExpensiveModule` referenced by name in the profile.
- A second internal framework `TaggedModule` tagged with `cacheable` and matched via the `tag:cacheable` query in the profile.
- A third internal framework `NonCacheableModule` to validate best-effort replacement: it depends on `ExpensiveModule`, allowing you to observe replacements affecting dependencies.

## Usage:

You can exercise this fixture by warming the cache:

```bash
tuist cache
```

Then generate the project using the configured profile:

```bash
# Use the default "development" profile (only-external + selected internals)
tuist generate

# Replace as many as possible (internals too), excluding focused targets
tuist generate --cache-profile all-possible

# No binary replacement at all
tuist generate --cache-profile none
```
