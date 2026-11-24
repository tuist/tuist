### 比較を調整する {#tune}

アンチエイリアスなどの小さな描画の差異を許容するには、プレビューに差分しきい値を設定します。これは、画像が変更されたものとみなされるまでに許容されるピクセルの割合で、0から1の範囲で指定します。

```swift
import TuistSnapshots

#Preview {
    ProfileView()
        .snapshotDiffThreshold(0.02)
}
```

プレビューを除外するには、`PreviewSnapshotTestCase` サブクラスで `includes(_:)` をオーバーライドしてください。

### オプション {#options}

- `--no-snapshots` (`TUIST_TEST_SNAPSHOTS=false`): CIでのアップロードを無効にします。
- `--snapshot-set <name>` (`TUIST_TEST_SNAPSHOT_SET`): 画像が属するセット。デフォルトはスキームです。
