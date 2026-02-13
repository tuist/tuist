# Session Context

## User Prompts

### Prompt 1

Implement the following plan:

# Fix: Static ObjC xcframeworks missing from search paths after binary caching

## Context

A user reported a bug (https://github.com/Alex-Ozun/TuistTestCaching): after `tuist cache App` and then `tuist generate --cache-profile all-possible`, the build fails with `Unable to find module dependency: 'GoogleMaps'`.

The project has: `App (target)` -> `FeatureA (dynamic framework)` -> `GoogleMaps.xcframework (static, ObjC)`.

After caching, FeatureA becomes a cached dy...

### Prompt 2

Did you test if it works with the fixture shared?

### Prompt 3

Can you create a PR with the fix?

### Prompt 4

Help me understand why thi sis happening. Is this a recent issue?

### Prompt 5

Can you include this context in the PR description?

### Prompt 6

Can you monitor CI?

### Prompt 7

Fix those acceptance tests, and investigate the issues to see if you can fix them

