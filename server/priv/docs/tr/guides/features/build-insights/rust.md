---
{
  "title": "Rust Derleme Analizleri",
  "titleTemplate": ":title · Derleme Analizleri · Özellikler · Kılavuzlar · Tuist",
  "description": "Yavaş paketleri bulun, derleme performansını karşılaştırın ve Tuist'te Rust derleyici uyarılarını ve hatalarını inceleyin."
}
---
# Rust derleme içgörüleri {#rust-build-insights}

Build Insights, Cargo derlemelerinizi yavaşlatan unsurları bulmanıza ve bunların tüm ekibi etkilemeden önce gerilemeleri yakalamanıza yardımcı olur. Yerel derlemeleri CI ile karşılaştırabilir, derleme sürelerinin nasıl değiştiğini görebilir ve her derlemede derlenen paketleri inceleyebilirsiniz.

> [!IMPORTANT]
> **Gereksinimler**
>
> - Projenizi bağlamak ve kimlik doğrulaması yapmak için <.localized_link href="/guides/get-started/rust-project">Rust projesi kurulumu</.localized_link> adımlarını izleyin.

## Derlemelerinizi bildirin {#report-your-builds}

Alıştığınız Cargo komutlarını Tuist üzerinden çalıştırın:

```sh
tuist cargo build --workspace
tuist cargo check --all-targets
tuist cargo +nightly build --features tracing
```

mise kullanıyorsanız, normal `cargo` komutlarını kullanmaya devam etmek için bir <.localized_link href="/guides/get-started/rust-project#keep-typing-cargo">Cargo sarmalayıcısı yapılandırın</.localized_link>. Argümanlarınız, araç zinciri seçiminiz, çıktınız ve çıkış kodunuz aynı kalır.

## Derlemeyi yavaşlatan unsuru bulun {#explore-your-builds}

Panodaki **Derlemeler → Derleme Çalıştırmaları** bölümünden bir derleme açın. Benzer derlemeleri karşılaştırmak için tarih, ortam ve Rust sürümü filtrelerini kullanın. Derlemeler ve önbellek sayaçlarına ayrıca `tuist build cargo list` ve `tuist build cargo show`, `GET /api/projects/{account_handle}/{project_handle}/cargo/builds` ile `list_cargo_builds` ve `get_cargo_build` <.localized_link href="/guides/features/agentic-coding/mcp">MCP araçları</.localized_link> üzerinden de erişilebilir.

**Genel Bakış** sekmesinde, yavaş paketleri bulmak için **Derleyici işleri**ni kullanın. **Süre** veya **Başlangıç sonrası** (Cargo komutunun başlamasından bu yana geçen süre) göre sıralayın ya da paket adına veya kök kaynak dosyasına göre arama yapın.

Her satır, birden çok kaynak dosya içerebilen bir paket için tek bir `rustc` çağrısını temsil eder. **Paket kökü**, kök kaynak dosyasını tanımlar; süre, yalnızca o dosya için değil, tüm derleyici işi için geçerlidir. Bir paket, farklı hedefler veya yapılandırmalar için birden fazla kez görünebilir. Derleyici mesajları **Uyarılar** ve **Hatalar** altında gruplanır.

### Paketleri derlemeler arasında takip edin {#crate-history}

Projeniz için mevcut olduğunda, **Derlemeler → Paketler** gözlemlenen paketleri ve derleme geçmişlerini gösterir. Bir paketi açarak kaydedilen sürelerini ve sonuçlarını derlemeler arasında karşılaştırın, ardından derlemeyi ilgili Cargo derlemesine kadar takip edin. Aynı envanter, proje API’sindeki `/cargo/crates` yolu ve paylaşılan MCP varlık araçlarında `kind: cargo_crates` ile de kullanılabilir.

Paketler, tam olarak kaydedilen kök yoluna, adına ve türüne göre gruplanır. Çıkış yollarının değiştirilmesi geçmişleri bölebilir; profiller, özellikler ve hedef üçlüleri ayırt edilmez. Bu, çalışma alanınızdaki her paketi değil, gözlemlenen derleyici işlerinin bir envanteridir. Önbelleğe alınmış veya güncel paketler derleme örnekleri oluşturmaz.

### Derleme raporlarını ilişkilendirin {#report-attribution}

Kimliği doğrulanmış raporlar, kişisel kimlik bilgilerinin arkasındaki bireyi tanımlar. Paylaşılan kimlik bilgilerinin bir bireyi tanımlaması gerekmez. İsteğe bağlı olarak, raporlayan makinede sabit ve opak bir tanımlayıcı olarak `TUIST_ACTOR_ID` değerini ayarlayın; bu varsayılan olarak kapalıdır ve doğrulanmamış bir iddia olarak görüntülenir, yetkilendirme için asla kullanılmaz. Eski sunucular bu iddiayı yok sayabilir. İçine gizli anahtarlar koymayın.

## Zamanlamaları okuyun {#timing-boundaries}

Derleme süresi, tüm Cargo komutunun ne kadar sürdüğünü gösterir. Derleyici işleri paralel çalışabildiğinden, süreleri toplam derleme süresine eşit olmaz.

Cargo yalnızca yeniden derlenmesi gereken paketleri derler. Zaten güncel olan paketler derleyici listesinde görünmez. Tuist’in derleme önbelleği ile geri yüklenen işler, derleyici yürütmesi olarak değil, önbellek ölçümlerinde yer alır.

Tuist, derleme betiklerini ayrı olarak ölçmez veya bir Derleme Zaman Çizelgesi göstermez. Büyük bir derleme, ilk 500 derleyici işini gösterir ve daha fazlası kaydedildiyse bununla ilgili bir uyarı görüntüler.

## Önbellek ölçümlerini okuyun {#cache-measurements}

`tuist cargo`, Tuist CLI’da uygulanan deneysel bir derleme önbelleği içerir. Kurulum, Kura üzerinden uzaktan okuma/yazma, desteklenen derlemeler ve sorun giderme için <.localized_link href="/guides/features/cache/rust">Rust önbellek kılavuzu</.localized_link>nu izleyin.

Derlemeler arasındaki önbellek isabeti oranlarını ve kaydedilen aktarım, gecikme ve verim ölçümlerini takip etmek için proje kenar çubuğundaki **Cargo Önbelleği**ni açın. Tarih veya ortama göre filtreleyin, günlük eğilimler ile tekil derleme isabeti oranları arasında geçiş yapın veya önbellek etkinliğini incelemek için son bir derlemeyi açın. Önbellek ölçümü olmayan derlemeler sıfır olarak sayılmaz, bunun yerine kullanılamaz durumda kalır.

Görev isabetlerini, görev kaçırma durumlarını, isabet oranını ve indirilen/yüklenen bayt miktarını görmek için bir derlemenin **Önbellek** sekmesini açın. Derleme önbellek verisi raporladığında bu sekme görünür.

- **Önbelleklenebilir Görevler**, hangi derleyici ve derleme betiği görevlerinin önbelleğe alınmış çıktıları yeniden kullandığını gösterir. Görevlerde arama veya filtreleme yapın, önbellek okuma/yazma gecikmesini inceleyin ve çıktılarını görmek için bir satırı genişletin.
- **CAS Çıktıları**, boyutları, süreleri ve verimleri ile birlikte yapıt indirmelerini ve yüklemelerini gösterir. Grafik, tamamlanan aktarımları sayar; zaten mevcut olan yapıtlar ve başarısız denemeler tabloda kalır.

**İsabet**, önbelleğe alınmış çıktıların yeniden kullanıldığı anlamına gelir. **Kaçırıldı**, görevin bunun yerine derlendiği anlamına gelir. İsabetler yerel ve uzak olarak ayrılmaz; CAS Çıktıları kaydedilen yapıt işlemlerini gösterir.

Ayrıntılı kayıtlar eksik veya eksikse sayfa bir uyarı gösterir. Özet yine de tüm derlemeyi kapsar. Tahmini olarak önlenen derleyici işi, **kazanılan geçen derleme süresi değildir**.

<!-- @snippet: ../cache/_rust-experimental -->

Artımlı derlemeler normal şekilde derlenir.

### Test çalıştıran derlemeler {#builds-that-run-tests}

`tuist cargo test`, testleri dahil olmak üzere tüm komutun süresini raporlar. Ayrıca, <.localized_link href="/guides/features/test-insights/rust">Rust Test İçgörüleri</.localized_link> aracılığıyla doctest’ler dahil olmak üzere tekil test sonuçlarını raporlar. Tekil test sonuçları **Testler** altında görünür; komut süresi derleme içgörülerinde yer alır.

## Diğer derleyici araçları {#other-compiler-tools}

Tuist, `RUSTC_WRAPPER`, `CARGO_BUILD_RUSTC_WRAPPER` veya Cargo yapılandırması aracılığıyla yapılandırılan mevcut derleyici sarmalayıcılarını korur ve `RUSTC_WORKSPACE_WRAPPER` öğesini değiştirmeden bırakır. Önceden var olan küresel bir sarmalayıcı, Tuist’in önbelleğini ve derleyici gözlemcisini devre dışı bırakır: Tuist, bu sarmalayıcının gerçekten rustc’yi çalıştırıp çalıştırmadığını belirleyemez. Özel çalışma alanı sarmalayıcıları da raporda daha az derleyici işi bırakabilir.

Tuist, Cargo’yu rustup üzerinden bulur. Özel bir kurulum kullanıyorsanız, `TUIST_CARGO_EXECUTABLE` değerini yürütülebilir dosyanın yoluna ayarlayın. Cargo’yu doğrudan araç zinciri yoluyla çağırmak mise’nin sarmalayıcısını atlar. Bir Cargo takma adı, `build` gibi yerleşik bir komutun yerine geçemez.

Cargo’nun nightly `-C` seçeneğini kullanıyorsanız, bunun yerine önce çalışma alanına geçin: Tuist `-C` komutlarını iletir ancak bunların derleme zamanlamalarını toplamaz.

## Sorun giderme {#troubleshooting}

Bir derleme panoda görünmüyorsa, raporunun neden gönderilmediğini görmek için hata ayıklama çıktısını etkinleştirin:

```sh
TUIST_DEBUG=1 tuist cargo build --workspace
```

Raporlama, derlemenizin sonucunu değiştirmez.
