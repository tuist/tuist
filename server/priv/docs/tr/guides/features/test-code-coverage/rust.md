---
{
  "title": "Rust Kod Kapsamı",
  "titleTemplate": ":title · Kod Kapsamı · Özellikler · Kılavuzlar · Tuist",
  "description": "Rust projenizin Cargo testlerinin satır kapsamını yükleyin ve bunu dosya, paket ve commit bazında takip edin."
}
---
# Rust kod kapsamı {#rust-code-coverage}

Kod kapsamı, testlerinizin kodunuzun hangi satırlarını çalıştırdığını gösterir. Tuist, her bir `cargo test` çalıştırmasının satır kapsamını LLVM'in kaynak tabanlı kapsam ölçümüyle hesaplar ve bir commit'in çalıştırmalarını proje, her paket ve her dosya için tek bir değerde birleştirir. Kontrol panelinin **Kod Kapsamı** sayfası bunu commit başına ve her dal için bir trend olarak gösterir.

> [!IMPORTANT]
> **Gereksinimler**
>
> - <.localized_link href="/guides/get-started/rust-project">Rust proje kurulumunu</.localized_link> takip edin
> - Rust araç zincirinizin LLVM araçları (`llvm-tools`). Tuist bunları rustup tarafından yönetilen bir araç zincirine yükler.
> - Projenizin bir Git deposunda olması

## Kurulum {#setup}

### Kapsamı açın {#turn-coverage-on}

Bunu çalışma alanının kök `Cargo.toml` dosyasına ekleyin:

```toml
[workspace.metadata.tuist.test_insights.coverage]
upload = true
```

Tuist'i bunun yerine bir `tuist.toml` içinde yapılandırıyorsanız, oraya `[test_insights.coverage]` ekleyin ve `upload = true` ayarını yapın.

Ardından testlerinizi her zamanki gibi çalıştırın:

```sh
tuist cargo test --workspace
```

Tuist, deponuzdaki crate'leri `-C instrument-coverage` ile derler, testleri çalıştırır ve çalıştırmanın test sonuçlarıyla birlikte kapsamlarını yükler. Testlerinizin çıktısı ve çıkış kodu değişmez. Tek bir çalıştırma için ayarı geçersiz kılmak amacıyla `TUIST_COVERAGE_UPLOAD=1` veya `TUIST_COVERAGE_UPLOAD=0` değerini ayarlayın.

Kapsam, Tuist'in onu toplayan her çalıştırmayla birlikte yüklediği ve commit'i dalına yerleştiren Git geçmişine dayanır. Bir Git deposu dışındaki bir çalıştırma, test sonuçlarını yükler ancak kapsam yüklemez. Bir dal yerine bir commit'in kontrol kopyasından yapılan bir çalıştırmanın dalı yoktur ve commit'ini bir dala yerleştirmez; Tuist'in tanımadığı bir CI sisteminde, <.localized_link href="/guides/features/test-insights/rust#continuous-integration">sürekli entegrasyon</.localized_link> bölümünde açıklandığı gibi dalı `TUIST_GIT_BRANCH` ile adlandırın.

### Parçalı çalıştırmalar {#sharded-runs}

Testlerinizi <.localized_link href="/guides/features/test-sharding/rust">parçalara böldüğünüzde</.localized_link>, kapsam açıkken çalışan her parça kendi hedeflerinin kapsamını bildirir ve Tuist bir çalıştırmanın parçalarını tek bir değerde birleştirir. Bir parça, test paketinin bir kısmını bilinçli olarak çalıştırdığından commit'in kapsamını eksik hale getirmez.

### CI'da her commit'i tamamlayın {#complete-each-commit}

Bir commit'in kapsamı genellikle birkaç işten gelir: parça başına veya özellik kümesi başına bir tane. Tuist, bunların sonuncusunun ne zaman rapor verdiğini bilemez, bu yüzden siz bildirin. Bir commit için tüm test işleri tamamlandığında, hepsine bağımlı olan bir işte şunu çalıştırın:

```sh
tuist coverage complete
```

Komut, kontrol kopyasının `HEAD` değerinden, testlerinizin çalıştığı commit'i okur; başka birini belirtmek için `--commit <sha>` parametresini kullanın. Bir commit tamamlanana kadar, kapsamı **Devam ediyor** olarak gösterilir ve dalın trendine dahil edilmez.

## Nasıl çalışır {#how-it-works}

### Tuist neyi ölçer {#what-tuist-measures}

- **Paketler.** Her Cargo paketi, kendi kapsamıyla birlikte kontrol panelinde bir hedeftir.
- **Yalnızca ürün kodu.** Entegrasyon testleri, kıyaslamalar ve örnekler (`tests/`, `benches/` ve `examples/` dizinleri ve bu türdeki hedefler) test kodudur. Tuist bunları saklar ancak her türlü hesaplamada dışarıda bırakır. Bir `#[cfg(test)]` modülündeki birim testleri kaynak dosyalarının parçasıdır, bu nedenle satırları da onunla birlikte sayılır, tıpkı `cargo llvm-cov` durumunda olduğu gibi.
- **Fonksiyonlar.** Her satır, hemen üzerinde başlayan fonksiyona aittir. Genel (generic) bir fonksiyon, kaç tür ile örneklendirildiğinden bağımsız olarak bir kez sayılır.
- **Dokümantasyon testleri** her zamanki gibi çalışır ancak ölçülmez.

Tuist ayrıca daha sonra kapsam tabanlı test seçimi için her test ikili dosyasının hangi kodu çalıştırdığını kaydeder. `cargo test` bir ikili dosyanın testlerini tek bir işlemde çalıştırır, bu nedenle bu kayıt bireysel testlere değil, ikili dosyanın bütününe aittir.

### Atlanan testler {#skipped-tests}

Bir çalıştırmanın kendi argümanları testleri dışarıda bıraktığında, örneğin bir test adı filtresi, `--skip`, `--ignored`, `-p`, `--exclude`, `--lib` veya `--test` kullanıldığında, commit'in kapsamı **Eksik** olarak işaretlenir;除非 hiçbir şeyi dışarıda bırakmayan başka bir commit çalıştırması da yapılmadıysa. Her test ikili dosyası çalışmadan önce `cargo test` işlemini durduran bir hata da aynı etkiye sahiptir. Kalan ikili dosyaları çalıştırmaya devam etmek için `--no-fail-fast` ekleyin.

Bazı testler bilinçli olarak dışarıda bırakılır ve bir commit'i eksik hale getirmez:

- **<.localized_link href="/guides/features/test-insights/flaky-tests/rust">Karantina</.localized_link> tarafından atlanan testler.** Bunlar kaldırılmış gibi dışarıda bırakılır, bu nedenle yalnızca bunların kapsadığı satırlar kapsanmamış olarak sayılır.
- **Diğer parçaların hedefleri**, testlerinizi parçalara böldüğünüzde.
- **Yoksayılan testler** (`#[ignore]`), varsayılan olarak çalışmazlar.

### Commit edilmemiş değişiklikler {#uncommitted-changes}

İzlenen dosyalarda commit edilmemiş değişiklikler bulunan bir kontrol kopyasından yapılan bir çalıştırma, commit'e ait olmayan kodu ölçtüğünden kapsamı commit'e sayılmaz. Çalıştırma uyarı verir ve değiştirilen dosyaları listeler. CI işinizin kaynakların yanına yazdığı dosyalar, derleme çıktıları veya kapsam raporları gibi, Git tarafından izlenmedikleri sürece değişiklik olarak sayılmaz. Bir commit'i yalnızca bu tür çalıştırmalar ölçtüyse, kapsamı **Eksik** olur ve `tuist coverage complete` nedenini açıklar.

### Tamamlanan ve eksik commit'ler {#commit-status}

Kontrol panelindeki her commit'in bir durumu vardır:

| Durum | Anlamı |
| --- | --- |
| Devam ediyor | Çalıştırmalar kapsam bildirdi, ancak `tuist coverage complete` henüz commit için çalıştırılmadı. |
| Tamamlandı | Commit çalıştırmalarındaki tüm testler çalıştırıldı veya bilinçli olarak dışarıda bırakıldı. |
| Eksik | Bazı kapsam verileri belirlenemedi, bu nedenle gösterilen değer alt sınırdır. |
| Ölçülmedi | Hiçbir çalıştırma commit için kapsam bildirmedi. |

Bir dalın eğilimi yalnızca tamamlanan commit'leri içerir.

## Performans etkisi {#performance-impact}

Enstrümantasyonlu kod biraz daha yavaş çalışır. Tuist yalnızca deponuzdaki crate'leri enstrümante eder: bağımlılıklar normal derlemelerinizdeki gibi derlenir ve önbellekten gelmeye devam eder. Tuist kendi crate'lerinizin her iki varyantını da hedef dizininde tutar, bu nedenle kapsamlı ve kapssız çalıştırmalar arasında geçiş yapmak, kodları değişmedikçe yeniden derlemez.

## Sınırlamalar {#limitations}

- **Hedefe özel `rustflags` içeren özel `rustc-wrapper`.** Projeniz kendi `rustc-wrapper` ayarını yaptığında, Tuist bunun yerine Cargo'nun `build.rustflags` değerine `-C instrument-coverage` ekler. Bir Cargo yapılandırma dosyasındaki `target.<triple>.rustflags` girdisi bunların yerine geçer, bu nedenle bayrağı oraya kendiniz ekleyin. Testleri kapsam yazmayan bir çalıştırma bunu belirtir.
- **Yapılandırılmış hedef çalıştırıcılar.** Tuist test ikili dosyalarını kendi çalıştırıcısı aracılığıyla başlatır. Bir Cargo yapılandırma dosyasındaki `target.<triple>.runner` bunun yerini alır: çalıştırmanın kapsamı yine yüklenir ancak Tuist hangi test ikili dosyasının neyi çalıştırdığını bilemez. `CARGO_TARGET_<TRIPLE>_RUNNER` ortam değişkeni üzerinden ayarlanan bir çalıştırıcı çalışmaya devam eder.
- **Fork'lardan gelen çekme isteklerinden kapsam yok.** Kapsam yalnızca Tuist ile kimlik doğrulaması yapan çalıştırmalar tarafından yüklenir ve CI genellikle fork'lardan açılan çekme isteklerinden gizli anahtarları ve kimlik belirteçlerini saklar.

## Kapsam sorgulama {#querying}

Kontrol panelinin **Kod Kapsamı** sayfası, her bir commit'in değerini, paketlerini ve dosyalarını, her dosyanın içerdiği fonksiyonlarla birlikte gösterir. Aynı verilere ajanlar <.localized_link href="/guides/features/agentic-coding/mcp">Model Context Protocol sunucusu</.localized_link> aracılığıyla erişebilir.
