---
{
  "title": "Rust Kod Kapsamı",
  "titleTemplate": ":title · Kod Kapsamı · Özellikler · Kılavuzlar · Tuist",
  "description": "Rust projenizin Cargo testlerinin satır kapsamını yükleyin ve dosya, paket ve commit bazında takip edin."
}
---
# Rust kod kapsamı {#rust-code-coverage}

Kod kapsamı, testlerinizin kodunuzun hangi satırlarını yürüttüğünü gösterir. Tuist, her bir `cargo test` çalıştırmasının satır kapsamını LLVM'in kaynak tabanlı kapsam ölçümüyle hesaplar ve bir commit'in çalıştırmalarını proje, her paket ve her dosya için tek bir değerde birleştirir. Kontrol panelindeki **Kod Kapsamı** sayfası bunu commit başına ve her dal için bir trend olarak gösterir.

> [!IMPORTANT]
> **Gereksinimler**
>
> - <.localized_link href="/guides/get-started/rust-project">Rust projesi kurulumunu</.localized_link> takip edin
> - Rust araç zincirinizin LLVM araçları (`llvm-tools`). Tuist bunları rustup tarafından yönetilen bir araç zincirine yükler.
> - Projenizin bir Git deposunda olması

## Kurulum {#setup}

### Kapsamı açın {#turn-coverage-on}

Bunu deponuzun kökündeki `tuist.toml` dosyasına ekleyin:

```toml
[test_insights.coverage]
upload = true
```

Ardından testlerinizi normal şekilde çalıştırın:

```sh
tuist cargo test --workspace
```

Tuist deponuzdaki crate'leri `-C instrument-coverage` ile derler, testleri çalıştırır ve çalışma sonuçlarıyla birlikte kapsam verilerini yükler. Testlerinizin çıktısı ve çıkış kodu değişmez. Tek bir çalıştırma için ayarı geçersiz kılmak üzere `TUIST_COVERAGE_UPLOAD=1` veya `TUIST_COVERAGE_UPLOAD=0` değerini ayarlayın.

Kapsam, Tuist'in bu veriyi toplayan her çalıştırma ile birlikte yüklediği ve commit'i dalına yerleştiren Git geçmişine dayanır. Bir Git deposu dışındaki bir çalıştırma test sonuçlarını yükler ancak kapsam verisi yüklemez.

### Parçalı çalıştırmalar {#sharded-runs}

Testlerinizi <.localized_link href="/guides/features/test-sharding/rust">parçalara böldüğünüzde</.localized_link>, kapsam açıkken çalışan her parça kendi hedeflerinin kapsamını bildirir ve Tuist bir çalıştırmanın parçalarını tek bir değerde birleştirir. Bir parça, test paketinin bir bölümünü bilinçli olarak çalıştırdığından commit'in kapsamını eksik hale getirmez.

### CI üzerinde her commit'i tamamlayın {#complete-each-commit}

Bir commit'in kapsamı genellikle birkaç işten gelir: parça başına veya özellik kümesi başına bir tane. Tuist hangisinin en son rapor verdiğini bilemez, bu yüzden siz bildirin. Bir commit için tüm test işleri bittiğinde, hepsine bağımlı olan bir işte şunu çalıştırın:

```sh
tuist cargo coverage-complete
```

Komut, commit'i checkout'tan veya CI sağlayıcınızın bir pull request için bildirdiği commit'ten okur; başka birini belirtmek için `--commit <sha>` parametresini kullanın. Bir commit tamamlanana kadar, kod kapsamı **Devam ediyor** olarak gösterilir ve dalın trendine dahil edilmez.

## Nasıl çalışır {#how-it-works}

### Tuist neyi ölçer {#what-tuist-measures}

- **Paketler.** Her Cargo paketi kontrol panelinde kendi kapsamıyla birlikte bir hedef olarak görünür.
- **Yalnızca ürün kodu.** Entegrasyon testleri, benchmarklar ve örnekler (`tests/`, `benches/` ve `examples/` dizinleri ile bu türdeki hedefler) test kodudur. Tuist bunları saklar ancak hiçbir değere dahil etmez. Bir `#[cfg(test)]` modülündeki birim testleri kaynak dosyalarının parçasıdır, bu nedenle satırları da onunla birlikte sayılır; tıpkı `cargo llvm-cov` içinde olduğu gibi.
- **Fonksiyonlar.** Her satır, kendisinden hemen önce başlayan fonksiyona aittir. Genel (generic) bir fonksiyon, kaç farklı tip ile örneklendirildiğinden bağımsız olarak bir kez sayılır.
- **Doctestler** normal şekilde çalışır ancak ölçülmez.

Tuist ayrıca daha sonra kapsam tabanlı test seçimi için her test ikilisinin hangi kodu yürüttüğünü kaydeder. `cargo test` bir ikilinin testlerini tek bir süreçte çalıştırır, bu nedenle kayıt ikili dosyanın bütününe aittir, tek tek testlerine değil.

### Atlanan testler {#skipped-tests}

Bir çalıştırmanın kendi argümanları testleri dışarda bıraktığında, örneğin bir test adı filtresi, `--skip`, `--ignored`, `-p`, `--exclude`, `--lib` veya `--test` kullanıldığında, commit'in kapsamı **Eksik** olur; ancak aynı commit için hiçbir şeyi dışlamayan başka bir çalıştırma da yapıldıysa durum farklıdır. Her test ikilisi çalışmadan önce `cargo test` işlemini durduran bir hata da aynı etkiye sahiptir. Kalan ikilileri çalıştırmaya devam etmek için `--no-fail-fast` ekleyin.

Bazı testler bilinçli olarak dışlanır ve bir commit'i eksik hale getirmez:

- **<.localized_link href="/guides/features/test-insights/flaky-tests/rust">Karantina</.localized_link> tarafından atlanan testler.** Bunlar kaldırılmış gibi dışlanır, bu nedenle yalnızca onların kapsadığı satırlar kapsanmamış sayılır.
- **Diğer parçaların hedefleri**, testlerinizi parçalara böldüğünüzde.
- **Yoksayılan testler** (`#[ignore]`), varsayılan olarak çalışmazlar.

### Tamamlanmış ve eksik commit'ler {#commit-status}

Kontrol panelindeki her commit'in bir durumu vardır:

| Durum | Anlamı |
| --- | --- |
| Devam ediyor | Çalıştırmalar kapsam bildirmiş ancak `tuist cargo coverage-complete` henüz o commit için çalıştırılmamış. |
| Tamamlandı | Commit'in çalıştırmalarındaki her test ya çalıştı ya da bilinçli olarak dışlandı. |
| Eksik | Bazı kapsam verileri belirlenemedi, bu nedenle değer bir alt sınırdır. |
| Ölçülmedi | Commit için kapsam bildiren bir çalıştırma yok. |

Bir dalın eğilimi yalnızca tamamlanmış commit'leri içerir.

## Performans etkisi {#performance-impact}

Enstrümantasyonlu kod biraz daha yavaş çalışır. Tuist yalnızca deponuzdaki crate'leri enstrümante eder: bağımlılıklar normal derlemelerinizdeki gibi derlenir ve önbellekten gelmeye devam eder. Tuist kendi crate'lerinizin her iki varyantını da hedef dizininde tutar, bu nedenle kapsamlı ve kapamsız çalıştırmalar arasında geçiş yapmak, kodları değişmedikçe yeniden derleme yapmaz.

## Sınırlamalar {#limitations}

- **Hedefe özel `rustflags` içeren özel `rustc-wrapper`.** Projeniz kendi `rustc-wrapper` değerini ayarladığında, Tuist bunun yerine Cargo'nun `build.rustflags` bölümüne `-C instrument-coverage` ekler. Bir Cargo yapılandırma dosyasındaki `target.<triple>.rustflags` girdisi bunların yerini alır, bu nedenle bayrağı oraya kendiniz ekleyin. Testlerin kapsam yazmadığı bir çalıştırma bunu belirtir.
- **Yapılandırılmış hedef çalıştırıcılar.** Tuist test ikililerini kendi çalıştırıcısı üzerinden başlatır. Bir Cargo yapılandırma dosyasındaki `target.<triple>.runner` bunun yerini alır: çalıştırmanın kapsamı yine de yüklenir, ancak Tuist hangi test ikilisinin neyi yürüttüğünü bilemez. `CARGO_TARGET_<TRIPLE>_RUNNER` ortam değişkeni aracılığıyla ayarlanan bir çalıştırıcı çalışmaya devam eder.
- **Fork'lardan gelen pull request'lerde kapsam yok.** Kapsam yalnızca Tuist ile kimlik doğrulaması yapan çalıştırmalar tarafından yüklenir ve CI genellikle fork'lardan açılan pull request'lerde gizli anahtarları ve kimlik belirteçlerini withholding eder.

## Kapsam sorgulama {#querying}

Kontrol panelinin **Kod Kapsamı** sayfası, her commit'in değerini, paketlerini ve dosyalarını, her dosyanın içerdiği fonksiyonlarla birlikte gösterir. Aynı verilere ajanlar <.localized_link href="/guides/features/agentic-coding/mcp">Model Context Protocol sunucusu</.localized_link> aracılığıyla erişebilir.
