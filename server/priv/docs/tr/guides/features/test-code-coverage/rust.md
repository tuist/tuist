---
{
  "title": "Rust Kod Kapsamı",
  "titleTemplate": ":title · Kod Kapsamı · Özellikler · Kılavuzlar · Tuist",
  "description": "Rust projenizin Cargo testlerinin satır kapsamını yükleyin ve bunu dosya, paket ve commit bazında takip edin."
}
---
# Rust kod kapsama oranı {#rust-code-coverage}

Kod kapsama oranı, testlerinizin kodunuzun hangi satırlarını çalıştırdığını gösterir. Tuist, her `cargo test` çalıştırmasının satır kapsama oranını LLVM'in kaynak tabanlı kapsama özelliğiyle ölçer ve bir commit'in çalıştırmalarını proje, her paket ve her dosya için tek bir değerde birleştirir. Gösterge panelinin **Kod Kapsama Oranı** sayfası bunu commit başına ve her dal için bir eğilim olarak gösterir.

> [!IMPORTANT]
> **Gereksinimler**
>
> - <.localized_link href="/guides/get-started/rust-project">Rust projesi kurulumu</.localized_link> adımlarını izleyin
> - Rust araç zincirinizin LLVM araçları (`llvm-tools`). Tuist bunları rustup tarafından yönetilen bir araç zincirine yükler.
> - Projenizin bir Git deposunda olması

## Kurulum {#setup}

### Kapsama oranını açın {#turn-coverage-on}

Bunu çalışma alanının kök `Cargo.toml` dosyasına ekleyin:

```toml
[workspace.metadata.tuist.test_insights.coverage]
upload = true
```

Tuist'i bunun yerine bir `tuist.toml` içinde yapılandırıyorsanız, oraya `[test_insights.coverage]` ve `upload = true` ekleyin.

Ardından testlerinizi her zamanki gibi çalıştırın:

```sh
tuist cargo test --workspace
```

Tuist, deponuzdaki crate'leri `-C instrument-coverage` ile derler, testleri çalıştırır ve kapsama oranlarını çalıştırmanın test sonuçlarıyla birlikte yükler. Testlerinizin çıktısı ve çıkış kodu değişmez. Tek bir çalıştırma için ayarı geçersiz kılmak üzere `TUIST_COVERAGE_UPLOAD=1` veya `TUIST_COVERAGE_UPLOAD=0` ayarlayın.

Kapsama oranı, Tuist'in onu toplayan her çalıştırmayla birlikte yüklediği ve commit'i dalına yerleştiren Git geçmişine dayanır. Bir Git deposu dışındaki bir çalıştırma, test sonuçlarını yükler ancak kapsama oranını yüklemez.

### Parçalı çalıştırmalar {#sharded-runs}

Testlerinizi <.localized_link href="/guides/features/test-sharding/rust">parçalara böldüğünüzde</.localized_link>, kapsama açıkken çalışan her parça kendi hedeflerinin kapsama oranını bildirir ve Tuist bir çalıştırmanın parçalarını tek bir değerde birleştirir. Bir parça, test paketinin bir bölümünü kasıtlı olarak çalıştırır, bu nedenle commit'in kapsama oranını eksik hale getirmez.

### CI'da her commit'i tamamlayın {#complete-each-commit}

Bir commit'in kapsama oranı genellikle birkaç job'dan gelir: parça başına veya özellik kümesi başına bir tane. Tuist, bunların sonuncusunun ne zaman rapor verdiğini bilemez, bu yüzden siz belirtin. Bir commit için tüm test job'ları bittiğinde, hepsine bağımlı olan bir job'da şunu çalıştırın:

```sh
tuist cargo coverage-complete
```

Komut, commit'i checkout'tan okur veya CI sağlayıcınızın bir pull request üzerinde bildirdiğini kullanır; başka birini belirtmek için `--commit <sha>` parametresini iletin. Bir commit tamamlanana kadar, kapsama oranı **Devam ediyor** olarak görünür ve dalın eğilimine dahil edilmez.

## Nasıl çalışır {#how-it-works}

### Tuist neyi ölçer {#what-tuist-measures}

- **Paketler.** Her Cargo paketi, kendi kapsama oranıyla birlikte gösterge panelinde bir hedeftir.
- **Yalnızca ürün kodu.** Entegrasyon testleri, kıyaslamalar ve örnekler (`tests/`, `benches/` ve `examples/` dizinleri ve bu türdeki hedefler) test kodudur. Tuist bunları saklar ancak her değerden çıkarır. Bir `#[cfg(test)]` modülündeki birim testleri kaynak dosyalarının parçasıdır, bu nedenle satırları `cargo llvm-cov` içinde olduğu gibi onunla birlikte sayılır.
- **Fonksiyonlar.** Her satır, yukarıdan en yakın başlayan fonksiyona aittir. Genel (generic) bir fonksiyon, kaç türle örneklendirildiğinden bağımsız olarak bir kez sayılır.
- **Doctest'ler** her zamanki gibi çalışır ancak ölçülmez.

Tuist, daha sonra kapsama tabanlı test seçimi için her test ikili dosyasının hangi kodu çalıştırdığını da kaydeder. `cargo test` bir ikili dosyanın testlerini tek bir işlemde çalıştırır, bu nedenle bu kayıt ikili dosyanın bütününe aittir, bireysel testlerine değil.

### Atlanan testler {#skipped-tests}

Bir çalıştırmanın kendi argümanları testleri dışarıda bıraktığında, örneğin bir test adı filtresi, `--skip`, `--ignored`, `-p`, `--exclude`, `--lib` veya `--test`, commit'in kapsama oranı **Eksik** olur;除非 hiçbir şeyi dışarıda bırakmayan başka bir commit çalıştırması da çalıştırıldıysa. Her test ikili dosyası çalışmadan önce `cargo test` işlemini durduran bir hata da aynı etkiye sahiptir. Kalan ikili dosyaları çalıştırmaya devam etmek için `--no-fail-fast` ekleyin.

Bazı testler kasıtlı olarak dışarıda bırakılır ve bir commit'i eksik hale getirmez:

- **<.localized_link href="/guides/features/test-insights/flaky-tests/rust">Karantina</.localized_link> tarafından atlanan testler.** Bunlar kaldırılmış gibi dışarıda bırakılır, bu nedenle yalnızca bunların kapsadığı satırlar kapsanmamış olarak sayılır.
- **Diğer parçaların hedefleri**, testlerinizi parçalara böldüğünüzde.
- **Yoksayılan testler** (`#[ignore]`), varsayılan olarak çalışmazlar.

### Tamamlanan ve eksik commit'ler {#commit-status}

Gösterge panelindeki her commit'in bir durumu vardır:

| Durum | Anlamı |
| --- | --- |
| Devam ediyor | Çalıştırmalar kapsama oranını bildirdi, ancak `tuist cargo coverage-complete` henüz commit için çalıştırılmadı. |
| Tamamlandı | Commit'in çalıştırmalarındaki her test çalıştırıldı veya kasıtlı olarak dışarıda bırakıldı. |
| Eksik | Bazı kapsama verileri belirlenemedi, bu nedenle gösterilen değer bir alt sınırdır. |
| Ölçülmedi | Commit için kapsama oranı bildiren hiçbir çalıştırma yok. |

Bir dalın eğilimi yalnızca tamamlanmış commit'leri içerir.

## Performans etkisi {#performance-impact}

Enstrümantasyonlu kod biraz daha yavaş çalışır. Tuist yalnızca deponuzdaki paketleri enstrümante eder: bağımlılıklar normal derlemelerinizdeki gibi derlenir ve önbellekten gelmeye devam eder. Tuist, kendi paketlerinizin her iki varyantını da hedef dizininde tutar, bu nedenle kapsama ile ve kapsama olmadan yapılan çalıştırmalar arasında geçiş yapmak, kodları değişmedikçe onları yeniden derlemez.

## Sınırlamalar {#limitations}

- **Hedefe özel `rustflags` içeren özel `rustc-wrapper`.** Projeniz kendi `rustc-wrapper` ayarını yaptığında, Tuist bunun yerine Cargo'nun `build.rustflags` bölümüne `-C instrument-coverage` ekler. Bir Cargo yapılandırma dosyasındaki `target.<triple>.rustflags` girişi bunların yerini alır, bu nedenle bayrağı oraya kendiniz ekleyin. Testleri hiç kapsama verisi yazmayan bir çalıştırma bunu belirtir.
- **Yapılandırılmış hedef çalıştırıcılar.** Tuist, test ikili dosyalarını kendi çalıştırıcısı aracılığıyla başlatır. Bir Cargo yapılandırma dosyasındaki `target.<triple>.runner` bunun yerini alır: çalıştırmanın kapsama verisi yine yüklenir, ancak Tuist hangi test ikili dosyasının neyi çalıştırdığını bilemez. `CARGO_TARGET_<TRIPLE>_RUNNER` ortam değişkeni üzerinden ayarlanan bir çalıştırıcı çalışmaya devam eder.
- **Fork'lardan gelen pull request'lerde kapsama yok.** Kapsama yalnızca Tuist ile kimlik doğrulaması yapan çalıştırmalar tarafından yüklenir ve CI genellikle fork'lardan açılan pull request'lerde gizli anahtarları ve kimlik belirteçlerini saklı tutar.

## Kapsama sorgulama {#querying}

Gösterge panelinin **Kod Kapsama** sayfası, her commit'in değerini, paketlerini ve dosyalarını, her dosyanın içerdiği fonksiyonlarla birlikte gösterir. Aynı verilere ajanlar <.localized_link href="/guides/features/agentic-coding/mcp">Model Context Protocol sunucusu</.localized_link> aracılığıyla erişebilir.
