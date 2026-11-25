---
{
  "title": "Rust Kod Kapsamı",
  "titleTemplate": ":title · Kod Kapsamı · Özellikler · Kılavuzlar · Tuist",
  "description": "Rust projenizin Cargo testlerinin satır kapsamını yükleyin ve dosya, paket ve commit bazında takip edin."
}
---
# Rust kod kapsamı {#rust-code-coverage}

Kod kapsamı, testlerinizin kodunuzun hangi satırlarını çalıştırdığını gösterir. Tuist, her bir `cargo test` çalıştırmasının satır kapsamını LLVM'in kaynak tabanlı kapsam ölçümüyle hesaplar ve bir commit'in tüm çalıştırmalarını proje, her paket ve her dosya için tek bir değerde birleştirir. Dashboard'un **Kod Kapsamı** sayfası bunu commit başına ve her dal için bir trend olarak gösterir.

> [!IMPORTANT]
> **Gereksinimler**
>
> - <.localized_link href="/guides/get-started/rust-project">Rust projesi kurulumunu</.localized_link> takip edin
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

Kapsam, Tuist'in bunu toplayan her çalıştırmayla yüklediği ve commit'i dalına yerleştiren Git geçmişine dayanır. Bir Git deposu dışındaki bir çalıştırma, test sonuçlarını yükler ancak kapsam yüklemez.

### Parçalı çalıştırmalar {#sharded-runs}

Testlerinizi <.localized_link href="/guides/features/test-sharding/rust">parçalara böldüğünüzde</.localized_link>, kapsam açıkken çalışan her parça kendi hedeflerinin kapsamını bildirir ve Tuist bir çalıştırmanın parçalarını tek bir değerde birleştirir. Bir parça, test paketinin bir bölümünü bilinçli olarak çalıştırır, bu nedenle commit'in kapsamını eksik hale getirmez.

### CI'da her commit'i tamamlayın {#complete-each-commit}

Bir commit'in kapsamı genellikle birkaç job'dan gelir: parça başına veya özellik kümesi başına bir tane. Tuist, bunların sonuncusunun ne zaman raporladığını bilemez, bu yüzden siz bildirin. Bir commit için tüm test job'ları bittiğinde, hepsine bağımlı olan bir job'da şunu çalıştırın:

```sh
tuist coverage complete
```

Komut, checkout'taki `HEAD` değerinden, yani testlerinizin çalıştığı commit'ten okuma yapar; başka birini belirtmek için `--commit <sha>` parametresini kullanın. Bir commit tamamlanana kadar, kapsamı **Devam ediyor** olarak görünür ve dalın trendine dahil edilmez.

## Nasıl çalışır {#how-it-works}

### Tuist neyi ölçer {#what-tuist-measures}

- **Paketler.** Her Cargo paketi, dashboard üzerinde kendi kapsamına sahip bir hedeftir.
- **Yalnızca ürün kodu.** Entegrasyon testleri, kıyaslamalar ve örnekler (`tests/`, `benches/` ve `examples/` dizinleri ile bu türdeki hedefler) test kodudur. Tuist bunları saklar ancak hiçbir değere dahil etmez. Bir `#[cfg(test)]` modülündeki birim testleri kaynak dosyalarının parçasıdır, bu nedenle satırları `cargo llvm-cov` içinde olduğu gibi onlarla birlikte sayılır.
- **Fonksiyonlar.** Her satır, yukarısında en yakın başlayan fonksiyona aittir. Genel bir fonksiyon, kaç türle örneklendiğinden bağımsız olarak bir kez sayılır.
- **Dokümantasyon testleri** her zamanki gibi çalışır ancak ölçülmez.

Tuist, daha sonra kapsama dayalı test seçimi için her test ikili dosyasının hangi kodu çalıştırdığını da kaydeder. `cargo test` bir ikili dosyanın testlerini tek bir süreçte çalıştırır, bu nedenle bu kayıt ikili dosyanın bütününe aittir, bireysel testlerine değil.

### Atlanan testler {#skipped-tests}

Bir çalıştırmanın kendi argümanları testleri dışarıda bıraktığında, örneğin bir test adı filtresi, `--skip`, `--ignored`, `-p`, `--exclude`, `--lib` veya `--test` kullanıldığında, commit'in kapsamı **Eksik** olur;除非 aynı commit'in hiçbir şeyi dışarıda bırakmayan başka bir çalıştırması da yürütülmediyse. Her test ikili dosyası çalışmadan önce `cargo test` işlemini durduran bir başarısızlık da aynı etkiye sahiptir. Kalan ikili dosyaları çalıştırmaya devam etmek için `--no-fail-fast` ekleyin.

Bazı testler bilinçli olarak dışarıda bırakılır ve bir commit'i eksik hale getirmez:

- **<.localized_link href="/guides/features/test-insights/flaky-tests/rust">Karantina</.localized_link> tarafından atlanan testler.** Bunlar kaldırılmış gibi dışarıda bırakılır, bu nedenle yalnızca bunların kapsadığı satırlar kapsanmamış olarak sayılır.
- **Diğer parçaların hedefleri**, testlerinizi parçalara böldüğünüzde.
- **Yoksayılan testler** (`#[ignore]`), varsayılan olarak çalışmazlar.

### Commit edilmemiş değişiklikler {#uncommitted-changes}

İzlenen dosyalarda commit edilmemiş değişiklikler bulunan bir checkout'tan yapılan bir çalıştırma, commit'e ait olmayan kodu ölçer, bu nedenle kapsamı commit'e sayılmaz. Çalıştırma uyarı verir ve değiştirilen dosyaları listeler. CI job'ınızın kaynakların yanına yazdığı dosyalar, örneğin derleme çıktıları veya kapsam raporları, Git bunları izlemiyorsa değişiklik olarak sayılmaz. Bir commit yalnızca bu tür çalıştırmalarla ölçüldüğünde, kapsamı **Eksik** olur ve `tuist coverage complete` nedenini açıklar.

### Tamamlanmış ve eksik commit'ler {#commit-status}

Dashboard'daki her commit'in bir durumu vardır:

| Durum | Anlamı |
| --- | --- |
| Devam ediyor | Çalıştırmalar kapsam bildirdi, ancak `tuist coverage complete` henüz commit için çalıştırılmadı. |
| Tamamlandı | Commit'in çalıştırmalarındaki her test çalıştırıldı veya bilinçli olarak dışarıda bırakıldı. |
| Eksik | Bazı kapsamlar belirlenemedi, bu nedenle rakam bir alt sınırdır. |
| Ölçülmedi | Hiçbir çalıştırma commit için kapsam bildirmedi. |

Bir dalın trendi yalnızca tamamlanmış commit'leri içerir.

## Performans etkisi {#performance-impact}

Enstrümantasyonlu kod biraz daha yavaş çalışır. Tuist yalnızca deponuzdaki paketleri enstrümante eder: bağımlılıklar düzenli derlemelerinizdeki gibi derlenir ve önbellekten gelmeye devam eder. Tuist, kendi paketlerinizin her iki varyantını da hedef dizininde tutar, bu nedenle kodları değişmedikçe kapsamlı ve kapsamsız çalıştırmalar arasında geçiş yapmak onların yeniden derlenmesine neden olmaz.

## Sınırlamalar {#limitations}

- **Hedefe özel `rustflags` içeren özel `rustc-wrapper`.** Projeniz kendi `rustc-wrapper` değerini ayarladığında, Tuist bunun yerine Cargo'nun `build.rustflags` değerine `-C instrument-coverage` ekler. Bir Cargo yapılandırma dosyasındaki `target.<triple>.rustflags` girdisi bunların yerini alır, bu nedenle bayrağı oraya kendiniz ekleyin. Testleri hiçbir kapsam yazmayan bir çalıştırma bunu belirtir.
- **Yapılandırılmış hedef çalıştırıcılar.** Tuist, test ikili dosyalarını kendi çalıştırıcısı aracılığıyla başlatır. Bir Cargo yapılandırma dosyasındaki `target.<triple>.runner` bunun yerini alır: çalıştırmanın kapsamı yine de yüklenir, ancak Tuist hangi test ikili dosyasının neyi çalıştırdığını bilemez. `CARGO_TARGET_<TRIPLE>_RUNNER` ortam değişkeni aracılığıyla ayarlanan bir çalıştırıcı çalışmaya devam eder.
- **Fork'lardan gelen pull request'lerden kapsam yok.** Kapsam yalnızca Tuist ile kimlik doğrulaması yapan çalıştırmalar tarafından yüklenir ve CI genellikle fork'lardan açılan pull request'lerde gizli anahtarları ve kimlik belirteçlerini saklı tutar.

## Kapsam sorgulama {#querying}

Dashboard'un **Kod Kapsamı** sayfası, her commit'in rakamını, paketlerini ve dosyalarını, her dosyanın içerdiği fonksiyonlarla birlikte gösterir. Aynı verilere ajanlar <.localized_link href="/guides/features/agentic-coding/mcp">Model Context Protocol sunucusu</.localized_link> aracılığıyla erişebilir.
