### Karşılaştırmayı ayarla {#tune}

Kenar yumuşatma gibi küçük işleme farklarını tolere etmek için ön izlemeye bir fark eşiği verin: görüntünün değişmiş sayılması için farklı olabilecek piksellerin 0 ile 1 arasındaki oranı.

```swift
import TuistSnapshots

#Preview {
    ProfileView()
        .snapshotDiffThreshold(0.02)
}
```

Ön izlemeleri dışlamak için `PreviewSnapshotTestCase` alt sınıfınızda `includes(_:)` yöntemini geçersiz kılın.

### Seçenekler {#options}

- `--no-snapshots` (`TUIST_TEST_SNAPSHOTS=false`): CI'da yüklemeleri kapatır.
- `--snapshot-set <name>` (`TUIST_TEST_SNAPSHOT_SET`): görsellerin ait olduğu küme. Varsayılan olarak şemadır.
