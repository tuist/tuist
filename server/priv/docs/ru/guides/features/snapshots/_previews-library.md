### Настройка сравнения {#tune}

Чтобы допустить небольшие различия в рендеринге, такие как сглаживание, задайте для превью порог разницы: доля пикселей от 0 до 1, которая может отличаться, прежде чем изображение будет считаться изменённым.

```swift
import TuistSnapshots

#Preview {
    ProfileView()
        .snapshotDiffThreshold(0.02)
}
```

Чтобы исключить превью, переопределите `includes(_:)` в вашем подклассе `PreviewSnapshotTestCase`.

### Параметры {#options}

- `--no-snapshots` (`TUIST_TEST_SNAPSHOTS=false`): отключает загрузку в CI.
- `--snapshot-set <name>` (`TUIST_TEST_SNAPSHOT_SET`): набор, к которому относятся изображения. По умолчанию используется схема.
