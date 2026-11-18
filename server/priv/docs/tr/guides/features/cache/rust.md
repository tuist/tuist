---
{
  "title": "Rust önbelleği",
  "titleTemplate": ":title · Önbellek · Özellikler · Kılavuzlar · Tuist",
  "description": "Desteklenen Rust derleme çıktılarını yerel olarak ve Cargo ile Tuist'in uzak önbelleği üzerinden yeniden kullanın."
}
---
# Rust önbelleği {#rust-cache}

Tuist, desteklenen Rust derleme çıktılarını önbelleğe alır; böylece Cargo bu çıktıları kendi derleme çıktıları kaldırıldıktan sonra yeniden kullanabilir. Önbellek, Tuist CLI’nin içine yerleşiktir. Kurulması gereken ayrı bir önbellek yürütülebilir dosyası veya Cargo eklentisi yoktur.

<!-- @snippet: ./_rust-experimental -->

## Önbelleğe almayı etkinleştirme {#enable-caching}

Projenizi bağlamak ve kimlik doğrulaması yapmak için <.localized_link href="/guides/get-started/rust-project">Rust projesi kurulumu</.localized_link> adımlarını izleyin. Ardından derlemenizi Tuist üzerinden çalıştırın:

```sh
tuist cargo build --release
```

Uygun derlemeler için önbelleğe alma otomatiktir. Ek bir önbellek yapılandırması veya etkinleştirme bayrağı gerekmez. Tuist, hesabınızın önbellek uç noktasını keşfeder ve mevcut proje ile sunucu yapılandırmanızı kullanarak önbellek kimlik bilgilerini edinir.

mise kullanıyorsanız, sıradan `cargo` komutlarını yazmaya devam etmek için <.localized_link href="/guides/get-started/rust-project#keep-typing-cargo">Cargo sarmalayıcısını yapılandırın</.localized_link>.

## Nasıl çalışır {#how-it-works}

Cargo başlamadan önce, Tuist daha önceki bir derlemenin aynı araç zinciri, profil ve yapılandırmayla ürettiği kayıt defteri ve git bağımlılıklarının çıktılarını geri yükler; böylece Cargo bunları güncel bulur. Nelerin yeniden derleneceğine karar vermek Cargo’nun sorumluluğunda kalır. Ardından, Cargo’nun hâlâ çalıştırdığı her uygun derleme için Tuist:

1. Eşleşen çıktılar için yerel önbelleğini kontrol eder.
2. Yerel bir önbellek ıskalamasında, Remote Execution API (REAPI) aracılığıyla Kura’yı sorgular, eksik içeriği indirir ve geri yüklemeden önce çıktıları doğrular.
3. Bir önbellek ıskalamasında, derleyiciyi normal şekilde çalıştırır. Başarılı bir derlemeden sonra çıktıları yerel olarak depolar ve yetkilendirildiğinde REAPI aracılığıyla Kura’ya yükler. Uzak önbellek girdisi, başvurduğu tüm içerik kullanılabilir hale geldikten sonra yayımlanır.

Aynı makinedeki derlemeler, diğer çalışma ağaçlarındaki veya hedef dizinlerdeki derlemeler de dahil olmak üzere yerel önbelleği paylaşır. Başka bir derleme zaten aynı paketi derliyor veya aynı derleme betiğini çalıştırıyorsa, Tuist onu bekler ve aynı işi iki kez yapmak yerine onun çıktılarını geri yükler. Bu derleme 10 dakikadan uzun sürerse, Tuist beklemeyi bırakır ve paketi kendisi derler.

Yerel ve CI derlemeleri aynı uzak önbellek protokolünü kullanır. Okuma ve yazma erişimi, Tuist’in sunucu tarafından verilen önbellek kimlik bilgilerinden ve hesabınızın <.localized_link href="/guides/features/cache#restrict-uploads-to-ci">önbellek yükleme politikasından</.localized_link> gelir. Bir hesap, geliştiricilerin indirmesine izin verirken yüklemeleri CI ve hesap token’larıyla sınırlayabilir. Önbellek yazarları güvenilir kod üreticileridir: önbelleğe alınan derleyici çıktıları yürütülebilir koddur, bu nedenle yazma erişimini yalnızca güvendiğiniz makineler ve token’lara verin.

Uzak kurulum başarısız olursa, yerel önbelleğe alma kullanılabilir durumda kalır. Kullanılamayan, eksik veya bozuk önbellek girdileri derlemeye geri döner. Bir yükleme hatası derlemeyi başarısız kılmaz veya yerel önbellek girdisini silmez.

## Neler önbelleğe alınabilir {#what-can-be-cached}

Önbellek şunları destekler:

- Çalışma alanı ve yol paketleri, bağımlılığı olan paketler ve oluşturulmuş kaynaklara sahip paketler dahil olmak üzere kitaplık paketleri. Tuist bunları derleyicinin okuduğu kaynaklara göre anahtarlar.
- `cargo check` ve `cargo clippy`, kitaplıkları yalnızca meta verilere derler. Girdileri derlemelerinkinden ayrıdır, bu nedenle bir kontrol asla `cargo build` için bir kitaplık sağlamaz. `cargo clippy` tarafından düz derleyiciyle derlenen bağımlılıklar (çalışma alanı dışındaki yol paketleri gibi) `cargo check` girdilerini yeniden kullanır.
- Apple silicon Mac’lerde ve glibc ile x86_64 ve arm64 Linux’ta, kaynak incelemesinin önceden anahtarlayamadığı derlemeler; örneğin yordamsal makrolar, satır içi assembly veya yerel kitaplıklar kullanan paketler, yordamsal makroların kendileri ve bağlantılı yürütülebilir dosyalar. Tuist, her birinin okuduğu dosyaları, ortam değişkenlerini ve salt okunur komutları (`git describe` gibi) kaydeder ve bunlara göre anahtarlar. Linux’ta, bir bağlantının okuduğu sistem bağlayıcısı, C kitaplığı ve başlangıç dosyaları anahtarının bir parçasıdır.
- Aynı platformlarda, derleme betiği çalıştırmaları; bunların gerçekleştirdiği C derlemeleri de dahil (macOS’ta varsayılan Apple derleyicisiyle, Linux’ta herhangi bir dinamik olarak bağlanmış derleyiciyle). Bir çalıştırma, yalnızca okuduğu dosyalar, ortam ve komutlar değişmediğinde geri yüklenir.
- Clippy’nin lint’leri dahil olmak üzere önbelleğe alınmış bir paketin tekrar gösterdiği uyarılar ve diğer tanılar.

Aşağıdakiler hâlâ normal şekilde derlenir:

- Alpine gibi glibc olmayan Linux dağıtımlarında derleme betikleri ve kaydedilmiş derlemeler.
- Ağa bağlanan, Tuist’in gözlemleyemediği programları başlatan (Linux’ta statik olarak bağlanmış programlar) veya çıktı dizininin dışına yazan derleme betikleri.
- Artımlı derlemeler, özel hedefler ve desteklenmeyen derleyici argümanları veya kaynak girdileri.
- Yordamsal makroların ve derleme betiklerinin Clippy derlemeleri ve çalışma alanının her manifestosunu ile kilit dosyasını `cargo metadata` aracılığıyla okuyan `cargo` lint grubunu etkinleştiren Clippy çalıştırmaları.
- Beklenmeyen derleyici çıktısı üreten derlemeler.
- Dinamik yükleyici ayarlarıyla (örneğin `LD_PRELOAD`) veya Rust araç zinciri ve hedef dizini dışındaki `LD_LIBRARY_PATH` dizinleriyle çalışan derlemeler; örneğin kabuğunuzdan miras alınanlar veya hedef dizini dışındaki bir `build.build-dir`.

Önceden var olan küresel bir derleyici sarmalayıcısı, Tuist’in derleme önbelleğini ve derleyici gözlemcisini devre dışı bırakır. Clippy’ninki dışındaki özel çalışma alanı sarmalayıcıları da önbelleğe almayı atlar. <.localized_link href="/guides/features/build-insights/rust#other-compiler-tools">derleyici aracı uyumluluğu</.localized_link> bölümüne bakın.

Önbellek anahtarları paket içeriğini, derleyici ve araç zincirini, argümanları ve derleme ortamını içerir. Clippy girdileri ayrıca Clippy sürümüne, `CLIPPY_ARGS`, `CLIPPY_CONF_DIR`, `CLIPPY_DISABLE_DOCS_LINKS` içindeki lint argümanlarına, paketin `Cargo.toml` dosyasına ve Clippy’nin yüklediği `clippy.toml` veya `.clippy.toml` dosyalarına bağlıdır. Çekim, hedef dizini, Cargo evi ve araç zinciri konumları yer tutucularla değiştirilir, böylece başka bir yoldaki çekim aynı girdileri yeniden kullanır. Çıktısı kendi yolunu gömen (örneğin `env!("CARGO_MANIFEST_DIR")` aracılığıyla) bir paket yalnızca o yolda yeniden kullanılır. Kimlik bilgileri, Tuist raporlama ayarları ve tanınan CI çalıştırma meta verileri girdileri geçersiz kılmaz. Derleme sırasında bu hariç tutulan değişkenleri okuyan paketler önbelleğe alınmaz.

## Yeniden kullanımı doğrulama {#verify-reuse}

Cargo zaten güncel çıktıları yeniden derlemekten kaçınır. Cargo’nun mevcut çıktıları yerine Tuist’in önbelleğini test etmek için bir kez derleyin, Cargo’nun çıktılarını kaldırın, ardından aynı derlemeyi tekrarlayın:

```sh
tuist cargo build --release
cargo clean
tuist cargo build --release
```

Uygun kütüphaneler ikinci derlemede geri yüklenebilir; desteklenmeyen paketler hâlâ derlenir. Cargo’nun çıktılarını kaldırmak, Tuist’in ayrı yerel önbelleğini kaldırmaz. Bu işlem yeniden kullanımı kontrol eder, mutlaka uzaktan indirmeleri değil: yerel bir isabet Kura’dan aktarım gerektirmez. Girdi doğrulama ve önbellek işlemleri ek yük getirir, bu nedenle derlemeyi önlemek küçük paketler için daha hızlı derlemeler garantilemez.

İsabetlerin doğru olduğunu kontrol etmek için, örneğin CI’da bir kanarya olarak, değişkenlerden birini `sampled` (64 pakette biri, her derlemede aynı paketler) veya `always` olarak ayarlayın:

- `TUIST_CARGO_VERIFY`, bir isabetin anahtarlandığı girdilerin hâlâ derleyicinin veya derleme betiğinin okuduklarıyla aynı olup olmadığını kontrol eder.
- `TUIST_CARGO_VERIFY_RECOMPILE`, isabetleri tekrar derler ve çıktıları önbellektekilerle karşılaştırır.

Kontrol edilen bir paket, önbelleğe alınmamış gibi geri yüklenmek yerine derlenir; bu nedenle çıktıları her zaman günceldir ve doğrulama derleme sonuçlarını değiştirmez. Doğrulama, kontrol edilen paketin önbellek girdisini asla saklamaz veya değiştirmez. Güncel çıktıları önbellektekilerden farklıysa, ona bağımlı paketler isabet edemez ve önbelleğe alınmamış bir derlemedeki gibi önbelleğe alınır. Artımlı derlemeler tekrarlanabilir değildir, bu nedenle bunlar için `TUIST_CARGO_VERIFY_RECOMPILE` yalnızca meta verileri ve bağımlılık bilgilerini karşılaştırır. `TUIST_DEBUG=1` ile her kontrol bir `Tuist Cargo cache: verified` satırı yazdırır ve fark bulan kontroller derlemenin önbellek ölçümlerinde sapma olarak sayılır.

## Önbellek etkinliğini inceleme {#inspect-cache-activity}

İsabet oranlarını, kaydedilen aktarımları, gecikmeyi, throughput’u ve son derlemeleri incelemek için projenizin panosunda **Cargo Önbelleği**’ni açın. Bireysel görev kararlarını ve CAS çıktılarını görmek için bir derlemenin **Önbellek** sekmesini açın.

Eksik ölçümler sıfır olarak sayılmaz ve bir önbellek isabeti mutlaka uzaktan indirme anlamına gelmez. Ayrıntılar için <.localized_link href="/guides/features/build-insights/rust#cache-measurements">Rust önbellek ölçümleri</.localized_link> bölümüne bakın.

## Sorun giderme {#troubleshooting}

Önbellek aktarımını ve raporlama hatalarını incelemek için hata ayıklama çıktısını etkinleştirin:

```sh
TUIST_DEBUG=1 tuist cargo build --release
```

Hata ayıklama çıktısı ayrıca bir derlemenin veya derleme betiği çalıştırmasının neden saklanmadığını da açıklar. Hiç isabet görmüyorsanız, başka bir derleyici sarmalayıcısının öncelik almadığını ve derleyici, bayraklar ile ortamın önbelleği dolduran derlemeyle eşleştiğini kontrol edin. Uzaktan yüklemeler için kimlik doğrulamayı ve hesabın önbellek yükleme politikasını da kontrol edin.
