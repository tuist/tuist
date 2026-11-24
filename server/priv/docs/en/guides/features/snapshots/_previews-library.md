### Tune the comparison {#tune}

To tolerate small rendering differences, such as anti-aliasing, give a preview a diff threshold: the share of pixels, from 0 to 1, that may differ before the image counts as changed.

```swift
import TuistSnapshots

#Preview {
    ProfileView()
        .snapshotDiffThreshold(0.02)
}
```

To leave previews out, override `includes(_:)` in your `PreviewSnapshotTestCase` subclass.

### Options {#options}

- `--no-snapshots` (`TUIST_TEST_SNAPSHOTS=false`): turns uploads off in CI.
- `--snapshot-set <name>` (`TUIST_TEST_SNAPSHOT_SET`): the set the images belong to. Defaults to the scheme.
