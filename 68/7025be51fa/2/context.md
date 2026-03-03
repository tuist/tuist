# Session Context

## User Prompts

### Prompt 1

Implement the following plan:

# Fix: ModuleMapMapper flags lost when configuration-level OTHER_SWIFT_FLAGS overrides base

## Context

Issue [#9676](https://github.com/tuist/tuist/issues/9676): When an app depends on dynamic frameworks that import ObjC modules from static SPM packages, the Swift compiler fails with `Unable to find module dependency: 'FirebaseCrashlytics'` (and similar).

**Root cause:** The `ModuleMapMapper` writes `-Xcc -fmodule-map-file=` flags to `target.settings.base["OTHER...

### Prompt 2

Did you try that against the fixture to check if everything works?

### Prompt 3

[Request interrupted by user for tool use]

### Prompt 4

It's the fixture included in this issue: https://github.com/tuist/tuist/issues/9676

### Prompt 5

[Request interrupted by user]

### Prompt 6

/Users/pepicrft/Downloads/tuistexample

It's here

### Prompt 7

[Request interrupted by user for tool use]

### Prompt 8

I want you to build and test that project e2e. That's the only one we can confirm if the fix works

### Prompt 9

Can you create a PR with the fix? Explain the issue el5

