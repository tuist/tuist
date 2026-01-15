# Static framework resources in tests and Metal embedding

This example reproduces two issues that can happen after stopping bundle generation for
static frameworks and validates the fixes:

- Unit tests that depend on a static framework with resources should resolve `Bundle.module`
  when running under `xctest` even if the app target does not link XCTest.
- A static framework that only contains Metal sources should still be embedded so the
  generated `default.metallib` is available at runtime.

## Structure

- `StaticResourcesFramework` is a static framework with a bundled `Message.txt` resource.
- `StaticMetalFramework` is a static framework that only contains a `.metal` file.
- `AppTests` reads the resource via `Bundle.module` from `StaticResourcesFramework`.
- `App` should embed `StaticMetalFramework.framework` so `default.metallib` is present.

## Run

From this directory:

```
tuist generate
```

Optionally run tests on a simulator:

```
tuist test App --device "<available simulator name>"
```
