### 調整比較 {#tune}

為了容許微小的渲染差異（例如抗鋸齒），請為預覽設定差異閾值：在影像被視為已變更之前，允許不同的像素比例，範圍從 0 到 1。

```swift
import TuistSnapshots

#Preview {
    ProfileView()
        .snapshotDiffThreshold(0.02)
}
```

若要排除預覽，請在你的 `PreviewSnapshotTestCase` 子類別中覆寫 `includes(_:)`。

### 選項 {#options}

- `--no-snapshots` (`TUIST_TEST_SNAPSHOTS=false`)：在 CI 中關閉上傳。
- `--snapshot-set <name>` (`TUIST_TEST_SNAPSHOT_SET`)：影像所屬的集合。預設為方案。
