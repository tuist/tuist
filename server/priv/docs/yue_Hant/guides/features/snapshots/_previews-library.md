### 調整比較 {#tune}

如要容忍細微的渲染差異（例如抗鋸齒），請為預覽設定差異閾值：即像素中可容許不同的比例，範圍由 0 至 1，超過此值才會將圖片視為已變更。

```swift
import TuistSnapshots

#Preview {
    ProfileView()
        .snapshotDiffThreshold(0.02)
}
```

如要排除預覽，請在你的 `PreviewSnapshotTestCase` 子類別中覆寫 `includes(_:)`。

### 選項 {#options}

- `--no-snapshots`（`TUIST_TEST_SNAPSHOTS=false`）：在 CI 中關閉上傳。
- `--snapshot-set <name>`（`TUIST_TEST_SNAPSHOT_SET`）：圖片所屬的集合。預設為 scheme。
