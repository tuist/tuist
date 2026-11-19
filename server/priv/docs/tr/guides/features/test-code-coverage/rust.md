---
{
  "title": "Rust Kod Kapsamı",
  "titleTemplate": ":title · Kod Kapsamı · Özellikler · Kılavuzlar · Tuist",
  "description": "Rust projenizin Cargo testlerinin satır kapsamını yükleyin ve bunu dosya, paket ve commit bazında takip edin."
}
---
# Rust kod kapsama oranı {#rust-code-coverage}

Kod kapsama oranı, testlerinizin kodunuzun hangi satırlarını çalıştırdığını gösterir. Tuist, her bir `cargo test` çalıştırmasının satır kapsama oranını LLVM'in kaynak tabanlı kapsama aracıyla ölçer ve bir commit'in çalıştırmalarını proje, her paket ve her dosya için tek bir değerde birleştirir. Dashboard'un **Kod Kapsama Oranı** sayfası bunu commit başına ve her dal için bir eğilim olarak gösterir.

> [!IMPORTANT]
> **Gereksinimler**
>
> - <.localized_link href="/guides/get-started/rust-project">Rust projesi kurulumu</.localized_link> adımlarını takip edin
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

Tuist, deponuzdaki crate'leri `-C instrument-coverage` ile derler, testleri çalıştırır ve kapsama oranını çalıştırmanın test sonuçlarıyla birlikte yükler. Testlerinizin çıktısı ve çıkış kodu değişmez. Tek bir çalıştırma için ayarı geçersiz kılmak amacıyla `TUIST_COVERAGE_UPLOAD=1` veya `TUIST_COVERAGE_UPLOAD=0` değerini ayarlayın.

Kapsama oranı, Tuist'in bunu topladığı her çalıştırma ile yüklediği Git geçmişine dayanır; bu da commit'i dalına yerleştirir. Bir Git deposu dışındaki bir çalıştırma, test sonuçlarını yükler ancak kapsama oranını yüklemez.

### Parçalı çalıştırmalar {#sharded-runs}

Testlerinizi <.localized_link href="/guides/features/test-sharding/rust">parçalara böldüğünüzde</.localized_link>, kapsama oranı açıkken çalışan her parça kendi hedeflerinin kapsama oranını bildirir ve Tuist bir çalıştırmanın parçalarını tek bir değerde birleştirir. Bir parça, test paketinin bir bölümünü bilinçli olarak çalıştırdığından commit'in kapsama oranını eksik hale getirmez.

### CI'da her commit'i tamamlayın {#complete-each-commit}

Bir commit'in kapsama oranı genellikle birkaç job'dan gelir: parça başına veya özellik kümesi başına bir tane. Tuist, bunların sonuncusunun ne zaman rapor verdiğini bilemez, bu yüzden siz belirtin. Bir commit için tüm test job'ları tamamlandığında, hepsine bağımlı olan bir job'da şunu çalıştırın:

```sh
tuist cargo coverage-complete
```

Komut, checkout'taki `HEAD` üzerinden, testlerinizin çalıştığı commit'i okur; başka birini belirtmek için `--commit <sha>` parametresini kullanın. Bir commit tamamlanana kadar, kapsama oranı **Devam ediyor** olarak görünür ve dalın eğilimine dahil edilmez.

## Nasıl çalışır {#how-it-works}

### Tuist neyi ölçer {#what-tuist-measures}

- **Paketler.** Her Cargo paketi, dashboard'da kendi kapsama oranıyla birlikte bir hedeftir.
- **Sadece ürün kodu.** Entegrasyon testleri, kıyaslama testleri ve örnekler (`tests/`, `benches/` ve `examples/` dizinleri ile bu türdeki hedefler) test kodudur. Tuist bunları saklar ancak her türlü hesaplamada dışında bırakır. Bir `#[cfg(test)]` modülündeki birim testleri kaynak dosyalarının bir parçasıdır, bu nedenle satırları `cargo llvm-cov` içinde olduğu gibi onlarla birlikte sayılır.
- **Fonksiyonlar.** Her satır, üzerinde en yakın başlayan fonksiyona aittir. Genel (generic) bir fonksiyon, kaç tür ile somutlaştırıldığına bakılmaksızın bir kez sayılır.
- **Dokümantasyon testleri** her zamanki gibi çalışır ancak ölçülmez.

Tuist, daha sonra kapsama oranı tabanlı test seçimi için her test binary'sinin hangi kodu çalıştırdığını da kaydeder. `cargo test` bir binary'nin testlerini tek bir süreçte çalıştırır, bu nedenle bu kayıt bireysel testlere değil, binary'nin bütününe aittir.

### Atlanan testler {#skipped-tests}

Bir çalıştırmanın kendi argümanları testleri dışarıda bıraktığında, örneğin bir test adı filtresi, `--skip`, `--ignored`, `-p`, `--exclude`, `--lib` veya `--test`, commit'in kapsama oranı **Eksik** olur;除非 hiçbir şeyi dışarıda bırakmayan başka bir commit çalıştırması da çalıştırıldıysa. Her test binary'si çalışmadan önce `cargo test` işlemini durduran bir hata da aynı etkiye sahiptir. Kalan binary'leri çalıştırmaya devam etmek için `--no-fail-fast` ekleyin.

Bazı testler bilinçli olarak dışarıda bırakılır ve bir commit'i eksik hale getirmez:

- **<.localized_link href="/guides/features/test-insights/flaky-tests/rust">Karantina</.localized_link> tarafından atlanan testler.** Bunlar kaldırılmış gibi dışarıda bırakılır, bu nedenle sadece bunların kapsadığı satırlar kapsanmamış olarak sayılır.
- **Diğer parçaların hedefleri**, testlerinizi parçalara böldüğünüzde.
- **Yoksayılan testler** (`#[ignore]`), varsayılan olarak çalışmazlar.

### Tamamlanmış ve eksik commit'ler {#commit-status}

Dashboard'daki her commit'in bir durumu vardır:

| Durum | Anlamı |
| --- | --- |
| Devam ediyor | Çalıştırmalar kapsama oranını bildirdi, ancak `tuist cargo coverage-complete` henüz commit için çalıştırılmadı. |
| Tamamlandı | Commit'in çalıştırmalarındaki her test çalıştırıldı veya bilinçli olarak dışarıda bırakıldı. |
| Eksik | Bazı kapsama oranları belirlenemedi, bu nedenle gösterilen değer alt sınırdır. |
| Ölçülmedi | Hiçbir çalıştırma commit için kapsama oranı bildirmedi. |

Bir dalın eğilimi yalnızca tamamlanmış commit'leri içerir.

## Performans etkisi {#performance-impact}

Enstrümantasyonlu kod biraz daha yavaş çalışır. Tuist yalnızca deponuzdaki crate'leri enstrümante eder: bağımlılıklar normal derlemelerinizdeki gibi derlenir ve önbellekten gelmeye devam eder. Tuist, kendi crate'lerinizin her iki varyantını da hedef dizininde tutar, bu nedenle kapsama oranı olan ve olmayan çalıştırmalar arasında geçiş yapmak, kodları değişmedikçe yeniden derlemez.

## Sınırlamalar {#limitations}

- **Hedefe özel `rustflags` içeren özel `rustc-wrapper`.** Projeniz kendi `rustc-wrapper` ayarını yaptığında, Tuist bunun yerine Cargo'nun `build.rustflags` kısmına `-C instrument-coverage` ekler. Bir Cargo yapılandırma dosyasındaki `target.<triple>.rustflags` girdisi bunların yerine geçer, bu nedenle bayrağı oraya kendiniz ekleyin. Testlerinin hiçbir kapsama verisi yazmadığı bir çalıştırma bunu belirtir.
- **Yapılandırılmış hedef çalıştırıcılar.** Tuist, test binary'lerini kendi çalıştırıcısı aracılığıyla başlatır. Bir Cargo yapılandırma dosyasındaki `target.<triple>.runner` bunun yerini alır: çalıştırmanın kapsama verisi yine yüklenir, ancak Tuist hangi test binary'sinin neyi çalıştırdığını bilemez. `CARGO_TARGET_<TRIPLE>_RUNNER` ortam değişkeni aracılığıyla ayarlanan bir çalıştırıcı çalışmaya devam eder.
- **Fork'lardan gelen pull request'lerden kapsama verisi yok.** Kapsama verisi yalnızca Tuist ile kimlik doğrulaması yapan çalıştırmalar tarafından yüklenir ve CI genellikle fork'lardan açılan pull request'lerde gizli anahtarları ve kimlik belirteçlerini tutar.

## Kapsama oranını sorgulama {#querying}

Dashboard'un **Kod Kapsama Oranı** sayfası, her commit'in değerini, paketlerini ve dosyalarını, her dosyanın içerdiği fonksiyonlarla birlikte gösterir. Aynı verilere ajanlar <.localized_link href="/guides/features/agentic-coding/mcp">Model Context Protocol sunucusu</.localized_link> aracılığıyla erişebilir.
