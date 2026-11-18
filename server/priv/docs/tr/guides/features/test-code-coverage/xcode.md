---
{
  "title": "Xcode Kod Kapsamı",
  "titleTemplate": ":title · Kod Kapsamı · Özellikler · Kılavuzlar · Tuist",
  "description": "Xcode projelerinin kod kapsamını Tuist'e yükleyin ve dosya bazında, commit bazında takip edin."
}
---
# Xcode kod kapsamı {#xcode-code-coverage}

<!-- @snippet: ./_xcode-early-access -->

Kod kapsamı, testlerinizin kodunuzun hangi satırlarını çalıştırdığını gösterir. Tuist, her bir test çalıştırmasının satır kapsamını yükler ve bir commit'in çalıştırmalarını proje, her hedef ve her dosya için tek bir rakamda birleştirir. Kontrol panelinin **Kod Kapsamı** sayfası bunu commit başına ve her dal için bir trend olarak gösterir.

> [!TIP]
> Projenizi Tuist ile oluşturuyorsanız, bunun yerine <.localized_link href="/guides/features/test-code-coverage/generated-xcode-project">oluşturulan proje kılavuzunu</.localized_link> takip edin: bu kılavuz, ikili önbellekten gelen kodu ölçer ve seçici testin atladığı test hedeflerinin kapsamını ilerletir.

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

`TUIST_COVERAGE_UPLOAD` ortam değişkeni (`1` veya `0`), seçeneğe göre önceliklidir; örneğin, fork'lardan gelen pull request'leri çalıştıran işlerde yüklemeyi kapatmak için kullanılır.

Ardından şemanızın test eyleminde **Kod Kapsamı**nı açın (**Edit Scheme › Test › Options**) veya çalıştırmaya `-enableCodeCoverage YES` parametresini geçirin ve testlerinizi `tuist xcodebuild test` üzerinden çalıştırın:

```sh
tuist xcodebuild test \
  -scheme MyScheme \
  -enableCodeCoverage YES
```

Tuist, çalıştırmanın topladığı kapsamı test sonuçlarıyla birlikte yükler.

### CI'da her commiti tamamla {#complete-each-commit}

Bir commit'in kapsamı genellikle birkaç işten gelir: şema, parça veya platform başına bir tane. Tuist, bunların sonuncusunun ne zaman raporlandığını bilemez, bu yüzden ona bildirin. Bir commit için tüm test işleri bittiğinde, hepsine bağımlı olan bir işte bunu çalıştırın:

```sh
tuist coverage complete
```

Bir commit tamamlanana kadar, kapsamı **Devam ediyor** olarak gösterilir ve dalının trendine dahil edilmez. <.localized_link href="/guides/features/test-code-coverage/generated-xcode-project#commit-status">Oluşturulan proje kılavuzu</.localized_link> her durumu açıklar.

## Atlanan testler {#skipped-tests}

Bir çalıştırma `-skip-testing` ile testleri atladığında, commit'in testlerinin kapsadığından daha azını ölçer ve Tuist bu testleri önceki bir çalıştırmadan ilerleteemez. Commit'in kapsamı, o commit'te başka bir çalıştırma onları çalıştırmadıkça **Eksik** olur. Bir commiti eksiksiz tutmak için, commit başına en az bir çalıştırmada her testi çalıştırın.

Karantinaya alınan ve atlanan testler kapsamın hiçbir parçası değildir, bu nedenle bir commiti asla **Eksik** yapmazlar.

## Performans etkisi {#performance-impact}

Kapsam toplamak, çoğunlukla testler bittikten sonra, Xcode kapsam raporunu yazarken ve Tuist kapsamı dışa aktarırken ek yük getirir. Testlerin derlenmesi ve çalıştırılması, kapsam olmadan olduğu kadar sürer.

## Kapsam sorgulama {#querying}

`tuist coverage` komutları kontrol panelinde gösterilenleri okur. `--commit` olmadan, `--branch` veya varsayılan dalınızın en son tamamlanan commit'ini okurlar:

```sh
tuist coverage show                          # the project's coverage and its targets
tuist coverage files --commit <sha>          # files, least covered first
tuist coverage file Sources/Cart.swift --lines  # a file's functions, with per-line counts
```

Tümü betikleme için `--json` kabul eder.
