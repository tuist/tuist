---
{
  "title": "Rust Kod Kapsamı",
  "titleTemplate": ":title · Kod Kapsamı · Özellikler · Kılavuzlar · Tuist",
  "description": "Rust projenizin Cargo testlerinin satır kapsamını yükleyin ve bunu dosya, paket ve commit bazında takip edin."
}
---
# Rust kod kapsamı {#rust-code-coverage}

Kod kapsamı, testlerinizin kodunuzun hangi satırlarını çalıştırdığını gösterir. Tuist, her bir `cargo test` çalıştırmasının satır kapsamını LLVM'nin kaynak tabanlı kapsam ölçümüyle hesaplar ve bir commit'in çalıştırmalarını proje, her paket ve her dosya için tek bir değerde birleştirir. Panonun **Kod Kapsamı** sayfası bunu commit başına ve her dal için bir eğilim olarak gösterir.

> [!IMPORTANT]
> **Gereksinimler**
>
> - <.localized_link href="/guides/get-started/rust-project">Rust projesi kurulumu</.localized_link> adımlarını izleyin
> - Rust araç zincirinizin LLVM araçları (`llvm-tools`). Tuist bunları rustup tarafından yönetilen bir araç zincirine yükler.
> - Projenizin bir Git deposunda olması

## Kurulum {#setup}

### Kapsamı açın {#turn-coverage-on}

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

Tuist, deponuzdaki crate'leri `-C instrument-coverage` ile derler, testleri çalıştırır ve çalıştırmanın test sonuçlarıyla birlikte kapsam verilerini yükler. Testlerinizin çıktısı ve çıkış kodu değişmez. Tek bir çalıştırma için ayarı geçersiz kılmak üzere `TUIST_COVERAGE_UPLOAD=1` veya `TUIST_COVERAGE_UPLOAD=0` değerini ayarlayın.

Kapsam, Tuist'in onu toplayan her çalıştırmayla yüklediği ve commit'i dalına yerleştiren Git geçmişine dayanır. Bir Git deposu dışındaki bir çalıştırma, test sonuçlarını yükler ancak kapsam verisi yüklemez.

### Parçalı çalıştırmalar {#sharded-runs}

<.localized_link href="/guides/features/test-sharding/rust">Testlerinizi parçalara böldüğünüzde</.localized_link>, kapsam açıkken çalışan her parça kendi hedeflerinin kapsamını bildirir ve Tuist bir çalıştırmanın parçalarını tek bir değerde birleştirir. Bir parça, test suite'inin bir bölümünü bilinçli olarak çalıştırır, bu nedenle commit'in kapsamını eksik hale getirmez.

### CI'da her commit'i tamamlayın {#complete-each-commit}

Bir commit'in kapsamı genellikle birkaç job'dan gelir: parça başına veya özellik kümesi başına bir tane. Tuist, bunların sonuncusunun ne zaman raporladığını bilemez, bu yüzden siz belirtin. Bir commit için tüm test job'ları bittiğinde, hepsine bağımlı olan bir job'da şunu çalıştırın:

```sh
tuist cargo coverage-complete
```

Komut, checkout'un `HEAD` değerinden, yani testlerinizin çalıştığı commit'ten okuma yapar; başka birini belirtmek için `--commit <sha>` parametresini kullanın. Bir commit tamamlanana kadar, kapsamı **Devam ediyor** olarak görünür ve dalının eğilimine dahil edilmez.

## Nasıl çalışır {#how-it-works}

### Tuist'in ölçtüğü şeyler {#what-tuist-measures}

- **Paketler.** Her Cargo paketi, panoda kendi kapsamıyla birlikte bir hedeftir.
- **Sadece ürün kodu.** Entegrasyon testleri, benchmarklar ve örnekler (`tests/`, `benches/` ve `examples/` dizinleri ve bu türdeki hedefler) test kodudur. Tuist bunları saklar ancak her hesaplamada dışarıda bırakır. Bir `#[cfg(test)]` modülündeki birim testleri kaynak dosyalarının bir parçasıdır, bu nedenle satırları da `cargo llvm-cov` içinde olduğu gibi onunla birlikte sayılır.
- **Fonksiyonlar.** Her satır, hemen üzerinde başlayan fonksiyona aittir. Genel (generic) bir fonksiyon, kaç tür ile somutlaştırıldığından bağımsız olarak bir kez sayılır.
- **Dokümantasyon testleri** her zamanki gibi çalışır ancak ölçülmez.

Tuist ayrıca daha sonra kapsama dayalı test seçimi için her test binary'sinin hangi kodu çalıştırdığını kaydeder. `cargo test` bir binary'nin testlerini tek bir süreçte çalıştırır, bu nedenle bu kayıt bireysel testlere değil, binary'nin tamamına aittir.

### Atlanan testler {#skipped-tests}

Bir çalıştırmanın kendi argümanları testleri dışarıda bıraktığında, örneğin bir test adı filtresi, `--skip`, `--ignored`, `-p`, `--exclude`, `--lib` veya `--test` kullanıldığında, commit'in kapsamı **Eksik** olarak işaretlenir;除非 hiçbir şeyi dışarıda bırakmayan başka bir commit çalıştırması da yapılmadıysa. Her test binary'si çalışmadan önce `cargo test` işlemini durduran bir hata da aynı etkiye sahiptir. Kalan binary'lerin çalışmaya devam etmesi için `--no-fail-fast` ekleyin.

Bazı testler bilinçli olarak dışarıda bırakılır ve bir commit'i eksik hale getirmez:

- **<.localized_link href="/guides/features/test-insights/flaky-tests/rust">Karantina</.localized_link> tarafından atlanan testler.** Bunlar kaldırılmış gibi dışarıda bırakılır, bu nedenle yalnızca onların kapsadığı satırlar kapsanmamış olarak sayılır.
- **Diğer parçaların hedefleri**, testlerinizi parçalara böldüğünüzde.
- **Yoksayılan testler** (`#[ignore]`), varsayılan olarak çalışmazlar.

### Commit edilmemiş değişiklikler {#uncommitted-changes}

İzlenen dosyalarında commit edilmemiş değişiklikler bulunan bir checkout'tan yapılan bir çalıştırma, commit'e ait olmayan kodu ölçer, bu nedenle kapsamı commit'e sayılmaz. Çalıştırma uyarı verir ve değişen dosyaları listeler. CI job'unuzun kaynakların yanına yazdığı dosyalar, örneğin derleme çıktıları veya kapsam raporları, Git tarafından izlenmedikleri sürece değişiklik olarak sayılmaz. Bir commit sadece bu tür çalıştırmalarla ölçüldüğünde, kapsamı **Eksik** olur ve `tuist cargo coverage-complete` nedenini açıklar.

### Tamamlanmış ve eksik commit'ler {#commit-status}

Panodaki her commit'in bir durumu vardır:

| Durum | Anlamı |
| --- | --- |
| Devam ediyor | Çalıştırmalar kapsam bildirdi, ancak `tuist cargo coverage-complete` henüz commit için çalıştırılmadı. |
| Tamamlandı | Commit çalıştırmalarındaki her test çalıştırıldı veya bilinçli olarak dışarıda bırakıldı. |
| Eksik | Bazı kapsam verileri belirlenemedi, bu nedenle rakam bir alt sınırdır. |
| Ölçülmedi | Commit için kapsam bildiren hiçbir çalıştırma yok. |

Bir dalın eğilimi yalnızca tamamlanmış commit'leri içerir.

## Performans etkisi {#performance-impact}

Enstrümante edilmiş kod biraz daha yavaş çalışır. Tuist yalnızca deponuzdaki crate'leri enstrümante eder: bağımlılıklar normal derlemelerinizdeki gibi derlenir ve önbellekten gelmeye devam eder. Tuist, kendi crate'lerinizin her iki varyantını da hedef dizininde tutar, böylece kapsamlı ve kapalı çalıştırmalar arasında geçiş yapmak, kodları değişmedikçe yeniden derleme gerektirmez.

## Sınırlamalar {#limitations}

- **Hedefe özel `rustflags` içeren özel `rustc-wrapper`.** Projeniz kendi `rustc-wrapper` değerini ayarladığında, Tuist bunun yerine Cargo'nun `build.rustflags` değerine `-C instrument-coverage` ekler. Bir Cargo yapılandırma dosyasındaki `target.<triple>.rustflags` girdisi bunların yerini alır, bu nedenle bayrağı oraya kendiniz ekleyin. Testlerinin hiç kapsam yazmadığı bir çalıştırma bunu belirtir.
- **Yapılandırılmış hedef çalıştırıcılar.** Tuist, test binary'lerini kendi çalıştırıcısı aracılığıyla başlatır. Bir Cargo yapılandırma dosyasındaki `target.<triple>.runner` bunun yerini alır: çalıştırmanın kapsamı yine de yüklenir, ancak Tuist hangi test binary'sinin neyi çalıştırdığını bilemez. `CARGO_TARGET_<TRIPLE>_RUNNER` ortam değişkeni üzerinden ayarlanan bir çalıştırıcı çalışmaya devam eder.
- **Fork'lardan gelen pull request'lerden kapsam yok.** Kapsam yalnızca Tuist ile kimlik doğrulaması yapan çalıştırmalar tarafından yüklenir ve CI genellikle fork'lardan açılan pull request'lerde gizli anahtarları ve kimlik belirteçlerini tutar.

## Kapsam sorgulama {#querying}

Panonun **Kod Kapsamı** sayfası, her commit'in rakamını, paketlerini ve dosyalarını, her dosyanın içerdiği fonksiyonlarla birlikte gösterir. Aynı verilere ajanlar <.localized_link href="/guides/features/agentic-coding/mcp">Model Context Protocol sunucusu</.localized_link> aracılığıyla erişebilir.
