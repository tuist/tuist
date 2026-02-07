# Cached Framework Headers Issue

This fixture reproduces an issue where ObjC headers become invisible when a framework
is replaced with a cached xcframework binary during `tuist test`.

## Structure

```
App -> ModuleA, ModuleB
ModuleB -> ModuleA

ModuleA has:
  - Public ObjC headers (ClassA.h) -> included in xcframework
  - Private ObjC headers (PrivateHelper.h) -> included in xcframework
  - Project ObjC headers (InternalHelper.h) -> NOT included in xcframework
  - Swift code (ModuleAFile.swift)

ModuleATests has:
  - Swift tests using @testable import (works with cache)
  - ObjC test using #import <ModuleA/ClassA.h> (works with cache)
  - ObjC test using #import "ClassA.h" (FAILS with cache)
  - ObjC test using #import "InternalHelper.h" (FAILS with cache)
  - ObjC test using #import <ModuleA/PrivateHelper.h> (works with cache)
```

## Reproduction Steps

### 1. Generate and verify tests pass without caching

```bash
tuist generate --no-open --cache-profile none
xcodebuild test -workspace CachedFrameworkHeaders.xcworkspace \
  -scheme CachedFrameworkHeaders-Workspace \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing ModuleATests
# All 5 tests pass
```

### 2. Warm the cache

```bash
tuist cache
```

### 3. Generate for testing with caching and observe failures

```bash
tuist test --test-targets ModuleATests --no-selective-testing --generate-only
xcodebuild build-for-testing -workspace CachedFrameworkHeaders.xcworkspace \
  -scheme CachedFrameworkHeaders-Workspace \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing ModuleATests
```

**Expected errors:**
- `InternalHelperTests.m:2:9: error: 'InternalHelper.h' file not found`
- `ClassAObjCTests.m:2:9: error: 'ClassA.h' file not found`

## Root Causes

1. **Project-level headers not in xcframework**: Headers declared with `project` visibility
   are not included in the xcframework binary. When ModuleA is cached, `InternalHelper.h`
   no longer exists on disk.

2. **Quoted includes lose source search paths**: When test code uses `#import "ClassA.h"`
   (quoted include) instead of `#import <ModuleA/ClassA.h>` (angle-bracket include), the
   header search paths that pointed to the source directory are gone when the module is
   replaced with a cached binary.

## Workarounds

- Use `--no-binary-cache` or `--cache-profile none` to skip caching
- Use angle-bracket includes (`#import <ModuleA/ClassA.h>`) instead of quoted includes
- Avoid testing modules with project-level ObjC headers when caching is enabled
