---
{
  "title": "Xcode Kod Kapsamı",
  "titleTemplate": ":title · Kod Kapsamı · Özellikler · Kılavuzlar · Tuist",
  "description": "Xcode projelerinin kod kapsamını Tuist'e yükleyin ve dosya bazında ve commit bazında takip edin."
}
---
# Xcode kod kapsamı {#xcode-code-coverage}

Kod kapsamı, testlerinizin kodunuzun hangi satırlarını çalıştırdığını gösterir. Tuist, her test çalıştırmasının satır kapsamını yükler ve bir commit'in çalıştırmalarını proje, her hedef ve her dosya için tek bir rakamda birleştirir. Kontrol panelinin **Kod Kapsamı** sayfası bunu commit başına ve her dal için bir eğilim olarak gösterir.

<!-- @snippet: ./_xcode-requirements -->

> [!TIP]
> Projenizi Tuist ile oluşturuyorsanız, bunun yerine <.localized_link href="/guides/features/test-code-coverage/generated-xcode-project">oluşturulan proje kılavuzunu</.localized_link> izleyin: bu kılavuz, ikili önbellekten gelen kodu ölçer ve seçici testlerin atladığı test hedeflerinin kapsamını ileri taşır.

## Kurulum {#setup}

### Kapsamı topla {#collect-coverage}

`Tuist.swift` içinde kapsam yüklemeyi açın. Varsayılan olarak kapalıdır:

```swift
import ProjectDescription

let tuist = Tuist(
    fullHandle: "my-account/my-project",
    testInsights: .testInsights(coverage: .coverage(upload: true)),
    project: .xcode()
)
```

`TUIST_COVERAGE_UPLOAD` ortam değişkeni (`1` veya `0`), seçeneğe göre önceliklidir; örneğin, fork'lardan gelen pull request'leri çalıştıran işlerde yüklemeyi kapatmak için kullanılabilir.

Ardından şemanızın test eyleminde **Kod Kapsamı**nı açın (**Şemayı Düzenle › Test › Seçenekler**) veya çalıştırmaya `-enableCodeCoverage YES` parametresini geçirin ve testlerinizi `tuist xcodebuild test` üzerinden çalıştırın:

```sh
tuist xcodebuild test \
  -scheme MyScheme \
  -enableCodeCoverage YES
```

Tuist, çalıştırmanın topladığı kapsamı test sonuçlarıyla birlikte yükler.

### CI'da her commit'i tamamla {#complete-each-commit}

Bir commit'in kapsamı genellikle birkaç işten gelir: şema başına, parça başına veya platform başına bir iş. Tuist, bunların sonuncusunun ne zaman rapor verdiğini bilemez, bu yüzden siz belirtin. Bir commit için tüm test işleri tamamlandığında, hepsine bağımlı olan bir işte bunu çalıştırın:

```sh
tuist coverage complete
```

Bir commit tamamlanana kadar, kapsamı **Devam ediyor** olarak gösterilir ve dalının eğilimine dahil edilmez. <.localized_link href="/guides/features/test-code-coverage/generated-xcode-project#commit-status">Oluşturulan proje kılavuzu</.localized_link> her durumu açıklar.

## Atlanan testler {#skipped-tests}

Bir çalıştırma `-skip-testing` ile testleri atladığında, commit'in testlerinin kapsadığından daha az ölçüm yapar ve Tuist bu testleri önceki bir çalıştırmadan ileri taşıyamaz. Commit'in kapsamı, o commit'te başka bir çalıştırma bunları çalıştırmadıkça **Eksik** olur. Bir commit'i tam tutmak için, commit başına en az bir çalıştırmada her testi çalıştırın.

Karantinaya alınan testler kapsamın hiçbir parçası değildir, bu nedenle bir commit'i asla **Eksik** yapmazlar.

## Performans etkisi {#performance-impact}

Kapsam toplamak, çoğunlukla testler bittikten sonra, Xcode kapsam raporunu yazarken ve Tuist kapsamı dışa aktarırken ek yük getirir. Testlerin derlenmesi ve çalıştırılması, kapsam olmadan olduğu kadar sürer.

## Kapsam sorgulama {#querying}

`tuist coverage` komutları, kontrol panelinde gösterilenleri okur. `--commit` olmadan, `--branch` veya varsayılan dalınızın en son tamamlanan commit'ini okurlar:

```sh
tuist coverage show                          # the project's coverage and its targets
tuist coverage files --commit <sha>          # files, least covered first
tuist coverage file Sources/Cart.swift --lines  # a file's functions, with per-line counts
tuist coverage targets                       # targets, least covered first, then those taken from the binary cache without coverage
tuist coverage commits --branch main         # a branch's commits with their status and change, newest first
tuist coverage runs --commit <sha>           # the test runs behind a commit, marked full, partial or discarded
tuist coverage branches                      # the branches with coverage
```

Bir test çalıştırmasının kendi kapsamı `tuist test show <test-run-id>` içinde gösterilir.

Tümü, betikleme için `--json` kabul eder.
