---
{
  "title": "Xcode Kod Kapsamı",
  "titleTemplate": ":title · Kod Kapsamı · Özellikler · Kılavuzlar · Tuist",
  "description": "Xcode projelerinin kod kapsamını Tuist'e yükleyin ve dosya bazında ile commit bazında takip edin."
}
---
# Xcode kod kapsama oranı {#xcode-code-coverage}

Kod kapsama oranı, testlerinizin kodunuzun hangi satırlarını çalıştırdığını gösterir. Tuist, her bir test çalıştırmasının satır kapsama oranını yükler ve bir commit'in çalıştırmalarını proje, her hedef ve her dosya için tek bir rakamda birleştirir. Panonun **Kod Kapsama Oranı** sayfası bunu commit başına ve her dal için bir trend olarak gösterir.

<!-- @snippet: ./_xcode-requirements -->

> [!TIP]
> Projenizi Tuist ile oluşturuyorsanız, bunun yerine <.localized_link href="/guides/features/test-code-coverage/generated-xcode-project">oluşturulan proje kılavuzunu</.localized_link> izleyin: bu kılavuz, ikili önbellekten gelen kodu ölçer ve seçici testlerin atladığı test hedeflerinin kapsama oranını ileri taşır.

## Kurulum {#setup}

### Kapsama oranını topla {#collect-coverage}

Kapsama oranı yüklemesini `Tuist.swift` dosyanızda açın. Varsayılan olarak kapalıdır:

```swift
import ProjectDescription

let tuist = Tuist(
    fullHandle: "my-account/my-project",
    testInsights: .testInsights(coverage: .coverage(upload: true)),
    project: .xcode()
)
```

`TUIST_COVERAGE_UPLOAD` ortam değişkeni (`1` veya `0`), seçeneğe göre önceliklidir; örneğin, fork'lardan gelen pull request'leri çalıştıran işlerde yüklemeyi kapatmak için kullanılır.

Ardından şemanızın test eyleminde **Kod Kapsama Oranı**nı açın (**Edit Scheme › Test › Options**) veya çalıştırmaya `-enableCodeCoverage YES` parametresini geçirin ve testlerinizi `tuist xcodebuild test` üzerinden çalıştırın:

```sh
tuist xcodebuild test \
  -scheme MyScheme \
  -enableCodeCoverage YES
```

Tuist, çalıştırmanın topladığı kapsama oranını test sonuçlarıyla birlikte yükler.

### CI'da her commit'i tamamla {#complete-each-commit}

Bir commit'in kapsama oranı genellikle birkaç işten gelir: şema, shard veya platform başına bir tane. Tuist, bunların sonuncusunun ne zaman rapor verdiğini bilemez, bu yüzden ona siz bildirin. Bir commit için tüm test işleri bittiğinde, hepsine bağımlı olan bir işte bunu çalıştırın:

```sh
tuist coverage complete
```

Bir commit tamamlanana kadar, kapsama oranı **Devam ediyor** olarak gösterilir ve dalın trendine dahil edilmez. <.localized_link href="/guides/features/test-code-coverage/generated-xcode-project#commit-status">Oluşturulan proje kılavuzu</.localized_link> her durumu açıklar.

## Atlanan testler {#skipped-tests}

Bir çalıştırma `-skip-testing` ile testleri atladığında, commit'in testlerinin kapsadığından daha azını ölçer ve Tuist bu testleri önceki bir çalıştırmadan ileri taşıyamaz. Commit'in kapsama oranı, o commit'te başka bir çalıştırma bunları çalıştırmadıkça **Eksik** olur. Bir commit'i eksiksiz tutmak için, her commit'te en az bir çalıştırmada tüm testleri çalıştırın.

Karantinaya alma nedeniyle atlanan testler kapsama oranının hiç parçası değildir, bu nedenle bir commit'i asla **Eksik** hale getirmezler.

## Performans etkisi {#performance-impact}

Kapsama oranı toplamak, çoğunlukla testler bittikten sonra, Xcode kapsama raporunu yazarken ve Tuist kapsama oranını dışa aktarırken ek yük getirir. Testlerin derlenmesi ve çalıştırılması, bu özellik olmadan olduğu kadar sürer.

## Kapsama oranını sorgulama {#querying}

`tuist coverage` komutları, panoda gösterilenleri okur. `--commit` olmadan, `--branch` veya varsayılan dalınızın en son tamamlanan commit'ini okurlar:

```sh
tuist coverage show                          # the project's coverage and its targets
tuist coverage files --commit <sha>          # files, least covered first
tuist coverage file Sources/Cart.swift --lines  # a file's functions, with per-line counts
tuist coverage targets                       # targets, least covered first, then those taken from the binary cache without coverage
tuist coverage commits --branch main         # a branch's commits with their status and change, newest first
tuist coverage runs --commit <sha>           # the test runs behind a commit, marked full, partial or discarded
tuist coverage branches                      # the branches with coverage
```

Bir test çalıştırmasının kendi kapsama oranı `tuist test show <test-run-id>` içinde gösterilir.

Tümü, betikleme için `--json` kabul eder.
