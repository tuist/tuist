### 비교 조정하기 {#tune}

안티앨리어싱과 같은 작은 렌더링 차이를 허용하려면 미리보기에 차이 임계값을 설정하세요. 이는 이미지가 변경된 것으로 간주되기 전에 달라질 수 있는 픽셀 비율(0에서 1 사이)입니다.

```swift
import TuistSnapshots

#Preview {
    ProfileView()
        .snapshotDiffThreshold(0.02)
}
```

미리보기를 제외하려면 `PreviewSnapshotTestCase` 서브클래스에서 `includes(_:)`를 재정의하세요.

### 옵션 {#options}

- `--no-snapshots` (`TUIST_TEST_SNAPSHOTS=false`): CI에서 업로드를 비활성화합니다.
- `--snapshot-set <name>` (`TUIST_TEST_SNAPSHOT_SET`): 이미지가 속하는 집합입니다. 기본값은 스킴입니다.
