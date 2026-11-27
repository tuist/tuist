### 调整对比 {#tune}

为了容忍细微的渲染差异（例如抗锯齿），可以为预览设置差异阈值：在图像被视为已更改之前，允许不同的像素比例，取值范围为 0 到 1。

```swift
import TuistSnapshots

#Preview {
    ProfileView()
        .snapshotDiffThreshold(0.02)
}
```

若要排除某些预览，请在你的 `PreviewSnapshotTestCase` 子类中重写 `includes(_:)`。

### 选项 {#options}

- `--no-snapshots` (`TUIST_TEST_SNAPSHOTS=false`)：在 CI 中关闭上传功能。
- `--snapshot-set <name>` (`TUIST_TEST_SNAPSHOT_SET`)：图像所属的集合。默认为 scheme。
