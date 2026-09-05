# Per-target scheme build purposes

This fixture reproduces the inability to disable one Build tab column for one target.

Generate it with the Tuist version being tested:

```sh
cd examples/xcode/generated_app_with_per_target_build_for
tuist generate
```

The fixture contains three targets:

- `ExampleLibrary`, which contains the reusable code.
- `ExampleLibraryTests`, which imports and tests `ExampleLibrary`.
- `ExampleLibraryApp`, which imports and displays a value from `ExampleLibrary`.

Open `ExampleLibrary.xcworkspace`, edit the `ExampleLibrary` scheme, and inspect its Build tab. The baseline manifest uses the existing `targets:` API, so all three targets are enabled for Analyze, Test, Run, Profile, and Archive.

The generated XML can also be inspected without Xcode:

```sh
grep -A8 BuildActionEntry ExampleLibrary.xcodeproj/xcshareddata/xcschemes/ExampleLibrary.xcscheme
```

After adding per-target build-purpose support, change the build action to:

```swift
buildAction: .buildAction(
    buildActionTargets: [
        .target("ExampleLibrary"),
        .target("ExampleLibraryTests"),
        .target(
            "ExampleLibraryApp",
            buildFor: [.analyzing, .archiving, .profiling, .running]
        ),
    ]
)
```

Regenerate the project. `ExampleLibraryApp` should then have `buildForTesting = "NO"`, while its other four values remain `"YES"`.
