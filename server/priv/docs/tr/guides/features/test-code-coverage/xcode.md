---
{
  "title": "Xcode Kod Kapsamı",
  "titleTemplate": ":title · Kod Kapsamı · Özellikler · Kılavuzlar · Tuist",
  "description": "Xcode projelerinin kod kapsamını Tuist'e yükleyin ve dosya bazında ile commit bazında takip edin."
}
---
# Xcode kod kapsama oranı {#xcode-code-coverage}

Kod kapsama oranı, testlerinizin kodunuzun hangi satırlarını çalıştırdığını gösterir. Tuist, her test çalıştırmasının satır kapsama oranını yükler ve bir commit’in çalıştırmalarını proje, her hedef ve her dosya için tek bir değerde birleştirir. Panonun **Kod Kapsama Oranı** sayfası bunu commit bazında ve her dal için bir trend olarak gösterir.

<!-- @snippet: ./_xcode-requirements -->

> [!TIP]
> Projenizi Tuist ile oluşturuyorsanız, bunun yerine <.localized_link href="/guides/features/test-code-coverage/generated-xcode-project">oluşturulan proje kılavuzunu</.localized_link> izleyin: bu kılavuz, ikili önbellekten gelen kodu ölçer ve seçici testin atladığı test hedeflerinin kapsama oranını sonraki aşamalara taşır.

## Kurulum {#setup}

### Kapsama oranını topla {#collect-coverage}

Kapsama yükleme özelliğini `Tuist.swift` dosyanızda açın. Varsayılan olarak kapalıdır:

```swift
import ProjectDescription

let tuist = Tuist(
    fullHandle: "my-account/my-project",
    testInsights: .testInsights(coverage: .coverage(upload: true)),
    project: .xcode()
)
```

`TUIST_COVERAGE_UPLOAD` ortam değişkeni (`1` veya `0`), seçenekten önceliklidir; örneğin, fork’lardan gelen pull request’leri çalıştıran işlerde yüklemeyi kapatmak için kullanılabilir.

Ardından şemanızın test eyleminde **Kod Kapsama Oranı**nı açın (**Şemayı Düzenle › Test › Seçenekler**) veya çalıştırmaya `-enableCodeCoverage YES` parametresini geçirin ve testlerinizi `tuist xcodebuild test` üzerinden çalıştırın:

```sh
tuist xcodebuild test \
  -scheme MyScheme \
  -enableCodeCoverage YES
```

Tuist, çalıştırmanın topladığı kapsama oranını test sonuçlarıyla birlikte yükler.

### CI üzerinde her committi tamamla {#complete-each-commit}

Bir commit’in kapsama oranı genellikle birkaç işten gelir: şema başına, parça başına veya platform başına bir tane. Tuist, bunların sonuncusunun ne zaman raporlandığını bilemez, bu nedenle ona bildirin. Bir commit için tüm test işleri tamamlandığında, hepsine bağımlı olan bir işte şunu çalıştırın:

```sh
tuist coverage complete
```

Bir commit tamamlanana kadar, kapsama oranı **Devam ediyor** olarak gösterilir ve dalının trendine dahil edilmez. <.localized_link href="/guides/features/test-code-coverage/generated-xcode-project#commit-status">Oluşturulan proje kılavuzu</.localized_link> her durumu açıklar.

## Atlanan testler {#skipped-tests}

Bir çalıştırma `-skip-testing` ile testleri atlarsa, commit’in testlerinin kapsadığından daha az ölçüm yapar ve Tuist bu testleri önceki bir çalıştırmadan ileriye taşıyamaz. Commit’in kapsama oranı, o commit’teki başka bir çalıştırma bunları çalıştırmadıkça **Eksik** olarak işaretlenir. Bir committi eksiksiz tutmak için, her commit’te en az bir çalıştırmada tüm testleri çalıştırın.

Karantinaya alınan ve atlanan testler kapsama oranına dahil değildir, bu nedenle bir committi asla **Eksik** hale getirmezler.

## Performans etkisi {#performance-impact}

Kapsama oranı toplamak, çoğunlukla testler bittikten sonra, Xcode kapsama raporunu yazarken ve Tuist kapsama oranını dışa aktarırken ek yük getirir. Testlerin derlenmesi ve çalıştırılması, bu özellik olmadan olduğu kadar sürer.

## Kapsama oranını sorgulama {#querying}

`tuist coverage` komutları, panoda gösterilen verileri okur. `--commit` olmadan, `--branch` dalınızın veya varsayılan dalınızın en son tamamlanan commit’ini okurlar:

```sh
tuist coverage show                          # the project's coverage and its targets
tuist coverage files --commit <sha>          # files, least covered first
tuist coverage file Sources/Cart.swift --lines  # a file's functions, with per-line counts
```

Tümü, betikleme için `--json` kabul eder.
