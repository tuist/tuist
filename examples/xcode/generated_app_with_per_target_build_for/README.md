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

Open `ExampleLibrary.xcworkspace`, edit the `ExampleLibrary` scheme, and inspect its Build tab. The explicit scheme uses the per-target Build-action API to produce:

| Target | Analyze | Test | Run | Profile | Archive |
| --- | --- | --- | --- | --- | --- |
| `ExampleLibrary` | Yes | Yes | Yes | Yes | Yes |
| `ExampleLibraryTests` | No | Yes | No | No | No |
| `ExampleLibraryApp` | Yes | No | Yes | Yes | Yes |

The generated XML can also be inspected without Xcode:

```sh
grep -A8 BuildActionEntry ExampleLibrary.xcodeproj/xcshareddata/xcschemes/ExampleLibrary.xcscheme
```

After regenerating, `ExampleLibraryApp` should have `buildForTesting = "NO"`, `ExampleLibraryTests` should have only `buildForTesting = "YES"`, and `ExampleLibrary` should have all five values set to `"YES"`.
