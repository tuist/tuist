---
{
  "title": "Rust Derleme İçgörileri",
  "titleTemplate": ":title · Derleme İçgörileri · Özellikler · Kılavuzlar · Tuist",
  "description": "Yavaş paketleri bulun, derleme performansını karşılaştırın ve Tuist'te Rust derleyici uyarılarını ve hatalarını inceleyin."
}
---
# Rust derleme içgörüleri {#rust-build-insights}

Derleme İçgörüleri, Cargo derlemelerinizi yavaşlatan etkenleri bulmanıza ve bunlar tüm ekibi etkilemeden önce gerilemeleri yakalamanıza yardımcı olur. Yerel derlemeleri CI ile karşılaştırabilir, derleme sürelerinin nasıl değiştiğini görebilir ve her derlemede derlenen paketleri inceleyebilirsiniz.

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

mise kullanıyorsanız, normal `cargo` komutlarını kullanmaya devam etmek için <.localized_link href="/guides/get-started/rust-project#keep-typing-cargo">Cargo sarmalayıcısını yapılandırın</.localized_link>. Argümanlarınız, araç zinciri seçiminiz, çıktınız ve çıkış kodunuz aynı kalır.

## Bir derlemeyi yavaşlatan şeyi bulun {#explore-your-builds}

Panodaki **Derlemeler → Derleme Çalıştırmaları** bölümünden bir derleme açın. Benzer derlemeleri karşılaştırmak için tarih, ortam ve Rust sürümü filtrelerini kullanın. Derlemeler ve önbellek sayaçlarına ayrıca `tuist build cargo list`, `tuist build cargo show`, `GET /api/projects/{account_handle}/{project_handle}/cargo/builds` ve `list_cargo_builds` ile `get_cargo_build` <.localized_link href="/guides/features/agentic-coding/mcp">MCP araçları</.localized_link> üzerinden de erişilebilir.

**Genel Bakış** sayfasında, yavaş paketleri bulmak için **Derleyici işleri**ni kullanın. **Süre** veya **Başlangıç sonrası** (Cargo komutunun başlamasından bu yana geçen süre) göre sıralayın ya da paket adına veya kök kaynak dosyasına göre arama yapın.

Her satır, birden fazla kaynak dosya içerebilen bir paket için tek bir `rustc` çağrısını temsil eder. **Paket kökü**, kök kaynak dosyasını tanımlar; süre yalnızca o dosya için değil, tüm derleyici işi için geçerlidir. Bir paket, farklı hedefler veya yapılandırmalar için birden fazla kez görünebilir. Derleyici mesajları **Uyarılar** ve **Hatalar** altında gruplanır.

### Paketleri derlemeler arasında takip edin {#crate-history}

Projeniz için mevcut olduğunda, **Derlemeler → Paketler** gözlemlenen paketleri ve derleme geçmişlerini gösterir. Kaydedilen süreleri ve sonuçları derlemeler arasında karşılaştırmak için bir paket açın, ardından derlemeyi ilgili Cargo derlemesine kadar takip edin. Aynı envanter, proje API'sindeki `/cargo/crates` yolu ve `kind: cargo_crates` değerine sahip ortak MCP varlık araçları aracılığıyla da kullanılabilir.

Paketler, kaydedilen tam kök yoluna, adına ve türüne göre gruplanır. Çıkarma yollarının değiştirilmesi geçmişleri bölebilir; profiller, özellikler ve hedef üçlüleri ayırt edilmez. Bu, çalışma alanınızdaki her paketi değil, gözlemlenen derleyici işlerinin bir envanteridir. Önbelleğe alınmış veya güncel paketler derleme örnekleri oluşturmaz.

### Derleme raporlarını ilişkilendirin {#report-attribution}

Kimliği doğrulanmış raporlar, kişisel kimlik bilgilerinin arkasındaki kişiyi tanımlar. Paylaşılan kimlik bilgilerinin bir kişiyi tanımlaması gerekmez. İsteğe bağlı olarak, raporlayan makinede kararlı ve opak bir tanımlayıcı olarak `TUIST_ACTOR_ID` ayarlayın; varsayılan olarak kapalıdır ve doğrulanmamış bir iddia olarak görüntülenir, yetkilendirme için asla kullanılmaz. Eski sunucular bu iddiayı yok sayabilir. İçine gizli anahtarlar koymayın.

## Zamanlamaları okuyun {#timing-boundaries}

Derleme süresi, tüm Cargo komutunun ne kadar sürdüğünü gösterir. Derleyici işleri paralel çalışabilir, bu nedenle süreleri derleme süresine eşit olmaz.

Cargo yalnızca yeniden derlenmesi gereken paketleri derler. Zaten güncel olan paketler derleyici listesinde görünmez. Tuist'in derleme önbelleği ile geri yüklenen işler, derleyici yürütmeleri olarak değil, önbellek ölçümlerinde görünür.

Tuist, derleme betiklerini ayrı olarak ölçmez veya bir Derleme Zaman Çizelgesi göstermez. Büyük bir derleme, ilk 500 derleyici işini gösterir ve daha fazlası kaydedildiyse buna dair bir bildirim sunar.

## Önbellek ölçümlerini okuyun {#cache-measurements}

`tuist cargo`, Tuist CLI'da uygulanan deneysel bir derleme önbelleği içerir. Kurulum, Kura üzerinden uzaktan okuma ve yazma, desteklenen derlemeler ve sorun giderme için <.localized_link href="/guides/features/cache/rust">Rust önbellek kılavuzu</.localized_link>nu izleyin.

Projedeki kenar çubuğunda **Cargo Önbelleği**ni açarak derlemeler arasındaki önbellek isabeti oranlarını ve kaydedilen aktarım, gecikme ve verim ölçümlerini takip edin. Tarih veya ortama göre filtreleyin, günlük eğilimler ile tekil derleme isabeti oranları arasında geçiş yapın veya önbellek etkinliğini incelemek için yakın tarihli bir derleme açın. Önbellek ölçümü olmayan derlemeler sıfır olarak sayılmak yerine kullanılamaz durumda kalır.

Görev isabetlerini, görev kaçırıklarını, isabet oranını ve indirilen/yüklenen baytları görmek için bir derlemenin **Önbellek** sekmesini açın. Derleme önbellek verisi bildirdiğinde bu sekme görünür.

- **Önbelleklenebilir Görevler**, hangi derleyici ve derleme-betiği görevlerinin önbelleğe alınmış çıktıları yeniden kullandığını gösterir. Görevlerde arama veya filtreleme yapın, önbellek okuma/yazma gecikmesini inceleyin ve çıktılarını görmek için bir satırı genişletin.
- **CAS Çıktıları**, boyutları, süreleri ve verimleri ile birlikte yapıt indirmelerini ve yüklemelerini gösterir. Grafik, tamamlanan aktarımları sayar; zaten mevcut olan yapıtlar ve başarısız denemeler tabloda kalır.

**İsabet**, önbelleğe alınmış çıktıların yeniden kullanıldığı anlamına gelir. **Kaçırıldı**, görevin bunun yerine derlendiği anlamına gelir. İsabetler yerel ve uzak olarak ayrılmaz; CAS Çıktıları kaydedilen yapıt işlemlerini gösterir.

Ayrıntılı kayıtlar eksik veya eksikse, sayfa bir bildirim gösterir. Özet yine de tüm derlemeyi kapsar. Tahmini önlenen derleyici işi, **kazanılan geçen derleme süresi değildir**.

<!-- @snippet: ../cache/_rust-experimental -->

Artımlı derlemeler normal şekilde derlenir.

### Testleri çalıştıran derlemeler {#builds-that-run-tests}

`tuist cargo test`, testleri de dahil olmak üzere tüm komutun süresini bildirir. Ayrıca, <.localized_link href="/guides/features/test-insights/rust">Rust Test İçgörüleri</.localized_link> aracılığıyla doctestler dahil olmak üzere tekil test sonuçlarını bildirir. Tekil test sonuçları **Testler** altında görünür; komut süresi derleme içgörülerinde görünür.

## Diğer derleyici araçları {#other-compiler-tools}

Tuist, `RUSTC_WRAPPER`, `CARGO_BUILD_RUSTC_WRAPPER` veya Cargo yapılandırması aracılığıyla yapılandırılan mevcut derleyici sarmalayıcılarını korur ve `RUSTC_WORKSPACE_WRAPPER` değerini olduğu gibi bırakır. Önceden var olan genel bir sarmalayıcı, Tuist'in önbelleğini ve derleyici gözlemcisini devre dışı bırakır: Tuist, bu sarmalayıcının gerçekten rustc'yi çalıştırıp çalıştırmadığını belirleyemez. Özel çalışma alanı sarmalayıcıları da raporda daha az derleyici işi bırakabilir.

Tuist, Cargo'yu rustup aracılığıyla bulur. Özel bir kurulum kullanıyorsanız, `TUIST_CARGO_EXECUTABLE` değerini yürütülebilir dosyanın yoluna ayarlayın. Cargo'yu doğrudan araç zinciri yoluyla çağırmak, mise'nin sarmalayıcısını atlar. Bir Cargo takma adı, `build` gibi yerleşik bir komutun yerini alamaz.

Cargo'nun nightly `-C` seçeneğini kullanıyorsanız, bunun yerine önce çalışma alanına geçin: Tuist, `-C` komutlarını iletir ancak derleme zamanlamalarını toplamaz.

## Sorun giderme {#troubleshooting}

Bir derleme panoda görünmüyorsa, raporunun neden gönderilmediğini görmek için hata ayıklama çıktısını etkinleştirin:

```sh
TUIST_DEBUG=1 tuist cargo build --workspace
```

Raporlama, derlemenizin sonucunu değiştirmez.
