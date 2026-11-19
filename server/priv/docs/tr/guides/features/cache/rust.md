---
{
  "title": "Rust için Cargo derleme önbelleği",
  "titleTemplate": ":title · Önbellek · Özellikler · Kılavuzlar · Tuist",
  "description": "Tuist'in Cargo derleme önbelleği ile CI ve yeni klonlarda Rust derleme süresini azaltın; bu önbellek, derleme çıktılarını yerel olarak ve uzak bir önbellek üzerinden yeniden kullanır."
}
---
# Rust için Cargo derleme önbelleği {#rust-cache}

Tuist, desteklenen Rust derleme çıktılarını önbelleğe alır; böylece Cargo, derleme çıktıları silindikten sonra (örneğin `cargo clean` sonrası, bir dal değişikliğinde veya başka bir checkout’ta) bu çıktıları yeniden kullanabilir. Buna Cargo derleme önbelleği veya Rust derleme önbelleği de denir: daha önceki bir derlemenin derlediği içerikleri (çalışma alanınızın artımlı olarak derlenmiş kütükleri dahil) yeniden kullanarak Rust derleme sürelerini kısaltır. Önbellek, Tuist CLI’nin içine yerleşiktir. Kurulması gereken ayrı bir önbellek yürütülebilir dosyası veya Cargo eklentisi yoktur.

<!-- @snippet: ./_rust-experimental -->

## Önbelleğe almayı etkinleştir {#enable-caching}

Projenizi bağlamak ve kimlik doğrulaması yapmak için <.localized_link href="/guides/get-started/rust-project">Rust proje kurulumu</.localized_link> adımlarını izleyin. Ardından derlemenizi Tuist üzerinden çalıştırın:

```sh
tuist cargo build --release
```

Uygun derlemeler için önbelleğe alma otomatiktir. Ek bir önbellek yapılandırması veya etkinleştirme bayrağı gerekmez. Tuist, hesabınızın önbellek uç noktasını keşfeder ve mevcut proje ile sunucu yapılandırmanızı kullanarak önbellek kimlik bilgilerini elde eder.

mise kullanıyorsanız, normal `cargo` komutlarını yazmaya devam etmek için <.localized_link href="/guides/get-started/rust-project#keep-typing-cargo">Cargo sarmalayıcısını yapılandırın</.localized_link>.

## Nasıl çalışır {#how-it-works}

Cargo başlamadan önce, Tuist kayıt defteri ve git bağımlılıklarınızın aynı araç zinciri, profil ve yapılandırmayla daha önceki bir derlemede ürettiği çıktıları geri yükler; böylece Cargo bunları güncel bulur. Nelerin yeniden derleneceğine karar vermek Cargo’nun sorumluluğunda kalır. Ardından, Cargo’nun hâlâ çalıştırdığı her uygun derleme için Tuist şunları yapar:

1. Eşleşen çıktılar için yerel önbelleğini kontrol eder.
2. Yerel bir ıskalamada, Remote Execution API (REAPI) aracılığıyla Kura’yı sorgular, eksik içeriği indirir ve çıktıları geri yüklemeden önce doğrular.
3. Bir önbellek ıskalamasında derleyiciyi çalıştırır. Başarılı bir derlemenin ardından çıktıları yerel olarak depolar ve yetkilendirildiğinde REAPI aracılığıyla Kura’ya yükler. Uzak önbellek girdisi, başvurduğu tüm içerik kullanılabilir hale geldikten sonra yayımlanır.

CI’da, bir kütüğün hedef dizindeki ilk derlemesi artımlı derleme olmadan çalışır; Cargo 1.99 ve sonraki sürümler bunu zaten varsayılan olarak yapar: yeniden kullanılacak önceki bir oturum yoktur, CI derlediklerini düzenlemez ve bir oturum oluşturmak o derlemeyi yavaşlatır ve önbellek girdisini büyütür. Tuist, kütüğü hedef dizinde hatırlar; böylece hedef dizinini koruyan bir iş bir sonraki seferde onu artımlı olarak derler. Yerel derlemeler, Cargo’nun istediği şekilde artımlı olarak derlenir; bu sayede temiz bir derlemeden sonraki ilk düzenleme hızlı kalır. Önbellek girdileri her iki durumda da paylaşılır.

Aynı makinedeki derlemeler, diğer çalışma ağaçlarındaki veya hedef dizinlerdeki derlemeler dahil olmak üzere yerel önbelleği paylaşır. Başka bir derleme zaten aynı kütüğü derliyor veya aynı derleme betiğini çalıştırıyorsa, Tuist onu bekler ve aynı işi iki kez yapmak yerine onun çıktılarını geri yükler. Bu derleme 10 dakikadan uzun sürerse, Tuist beklemeyi bırakır ve kütüğü kendisi derler.

Yerel ve CI derlemeleri aynı uzak önbellek protokolünü kullanır. Okuma ve yazma erişimi, Tuist’in sunucu tarafından verilen önbellek kimlik bilgileri ve hesabınızın <.localized_link href="/guides/features/cache#restrict-uploads-to-ci">önbellek yükleme politikası</.localized_link> üzerinden sağlanır. Bir hesap, geliştiricilerin indirmesine izin verirken yüklemeleri yalnızca CI ve hesap jetonlarıyla kısıtlayabilir. Önbellek yazarları güvenilir kod üreticileridir: önbelleğe alınan derleyici çıktıları yürütülebilir koddur; bu nedenle yazma erişimini yalnızca güvendiğiniz makineler ve jetonlara verin.

Uzak kurulum başarısız olursa, yerel önbelleğe alma kullanılabilir kalır. Kullanılamayan, eksik veya bozuk önbellek girdileri derlemeye geri döner. Bir yükleme hatası derlemeyi başarısız kılmaz veya yerel önbellek girdisini silmez.

## Neler önbelleğe alınabilir {#what-can-be-cached}

Önbellek şunları destekler:

- Kütüphane kütükleri; çalışma alanı ve yol kütükleri, bağımlılığı olan kütükler ve oluşturulmuş kaynaklara sahip kütükler dahil. Tuist bunları derleyicinin okuduğu kaynaklara göre anahtarlar.
- `cargo check` ve `cargo clippy`, kütüphaneleri yalnızca meta veriye derler. Girdileri derlemelerinkinden ayrıdır; bu nedenle bir check asla `cargo build` için bir kütüphane sağlamaz. `cargo clippy`’nin düz derleyiciyle derlediği bağımlılıklar (çalışma alanı dışındaki yol kütükleri gibi) `cargo check` girdilerini yeniden kullanır.
- Apple silicon Mac’lerde ve glibc ile x86_64 ve arm64 Linux’ta, kaynak incelemenin önceden anahtarlayamadığı derlemeler; örneğin yordamsal makrolar, satır içi assembly veya yerel kütüphaneler kullanan kütükler, yordamsal makroların kendileri ve bağlantılı yürütülebilir dosyalar. Tuist, her birinin okuduğu dosyaları, ortam değişkenlerini ve salt okunur komutları (`git describe` gibi) kaydeder ve bunlara göre anahtarlar. Linux’ta, bir bağlantının okuduğu sistem bağlayıcısı, C kütüphanesi ve başlangıç dosyaları anahtarın bir parçasıdır.
- Aynı platformlarda, derleme betiği çalıştırmaları; bunların gerçekleştirdiği C derlemeleri dahil (macOS’ta varsayılan Apple derleyicisiyle, Linux’ta herhangi bir dinamik bağlı derleyiciyle). Bir çalıştırma yalnızca okuduğu dosyalar, ortam ve komutlar değişmediğinde geri yüklenir.
- Uyarılar ve diğer tanılar; önbelleğe alınmış bir kütük bunları tekrar gösterir, Clippy lint’leri dahil.

Aşağıdakiler hâlâ normal şekilde derlenir:

- glibc olmayan Linux dağıtımlarında (Alpine gibi) derleme betikleri ve kaydedilmiş derlemeler.
- Ağa bağlanan, Tuist’in gözlemleyemediği programları başlatan (Linux’ta statik bağlı programlar) veya çıktı dizininin dışına yazan derleme betikleri.
- Özel hedefler ve desteklenmeyen derleyici argümanları veya kaynak girdileri.
- Yordamsal makroların ve derleme betiklerinin Clippy derlemeleri ve `cargo` lint grubunu etkinleştiren Clippy çalıştırmaları; bu grup, çalışma alanının her bildirimini ve kilit dosyasını `cargo metadata` aracılığıyla okur.
- Beklenmeyen derleyici çıktısı üreten derlemeler.
- Dinamik yükleyici ayarlarıyla (örneğin `LD_PRELOAD`) veya Rust araç zinciri ve hedef dizini dışındaki `LD_LIBRARY_PATH` dizinleriyle çalışan derlemeler; örneğin kabuğunuzdan devralınanlar veya hedef dizini dışındaki bir `build.build-dir`.

Önceden var olan genel bir derleyici sarmalayıcısı, Tuist’in derleme önbelleğini ve derleyici gözlemcisini devre dışı bırakır. Clippy’ninki dışındaki özel çalışma alanı sarmalayıcıları da önbelleğe almayı atlar. <.localized_link href="/guides/features/build-insights/rust#other-compiler-tools">derleyici aracı uyumluluğu</.localized_link> bölümüne bakın.

Önbellek anahtarları paket içeriğini, derleyiciyi ve araç zincirini, argümanları ve derleme ortamını içerir. Clippy girdileri ayrıca Clippy sürümüne, `CLIPPY_ARGS`, `CLIPPY_CONF_DIR`, `CLIPPY_DISABLE_DOCS_LINKS` içindeki lint argümanlarına, paketin `Cargo.toml` dosyasına ve Clippy’nin yüklediği `clippy.toml` veya `.clippy.toml` dosyalarına bağlıdır. Çekim (checkout), hedef dizin, Cargo ev dizini ve araç zinciri konumları yer tutucularla değiştirilir; böylece başka bir yoldaki çekim aynı girdileri yeniden kullanır. Çıktısı kendi yolunu gömen (örneğin `env!("CARGO_MANIFEST_DIR")` aracılığıyla) bir kütük yalnızca o yolda yeniden kullanılır. Kimlik bilgileri, Tuist raporlama ayarları ve tanınan CI çalıştırma meta verileri girdileri geçersiz kılmaz. Derleme sırasında bu hariç tutulan değişkenleri okuyan kütükler önbelleğe alınmaz.

## Yeniden kullanımı doğrulama {#verify-reuse}

Cargo zaten güncel çıktıları yeniden derlemekten kaçınır. Tuist’in önbelleğini, Cargo’nun mevcut çıktıları yerine denemek için bir kez derleyin, Cargo’nun çıktılarını kaldırın ve ardından aynı derlemeyi tekrarlayın:

```sh
tuist cargo build --release
cargo clean
tuist cargo build --release
```

Uygun kütüphaneler ikinci derlemede geri yüklenebilir; desteklenmeyen kütükler hâlâ derlenir. Cargo’nun çıktılarını kaldırmak, Tuist’in ayrı yerel önbelleğini kaldırmaz. Bu işlem yeniden kullanımı kontrol eder, mutlaka uzaktan indirmeleri değil: yerel bir isabet Kura’dan aktarım gerektirmez. Girdi doğrulama ve önbellek işlemleri ek yük getirir; bu nedenle derlemeyi atlamak küçük kütükler için daha hızlı derlemeler garantilemez.

İsabetlerin doğru olduğunu kontrol etmek için, örneğin CI’da canary olarak, değişkenlerden birini `sampled` (her derlemede aynı olan 64 kütükten biri) veya `always` olarak ayarlayın:

- `TUIST_CARGO_VERIFY`, bir isabetin anahtarlandığı girdilerin hâlâ derleyicinin veya derleme betiğinin okuduklarıyla aynı olup olmadığını kontrol eder.
- `TUIST_CARGO_VERIFY_RECOMPILE`, isabetleri tekrar derler ve çıktılarını önbellektekilerle karşılaştırır.

Kontrol edilen bir kütük, önbelleğe alınmamış gibi geri yüklenmek yerine derlenir; böylece çıktıları her zaman günceldir ve doğrulama derleme sonuçlarını değiştirmez. Doğrulama, kontrol edilen kütüğün önbellek girdisini asla saklamaz veya değiştirmez. Güncel çıktıları önbellektekilerden farklıysa, ona bağımlı kütükler isabet edemez ve önbelleğe alınmamış bir derlemedeki gibi önbelleğe alınır. Artımlı derlemeler tekrarlanabilir değildir; bu nedenle `TUIST_CARGO_VERIFY_RECOMPILE` bunlar için yalnızca meta verileri ve bağımlılık bilgilerini karşılaştırır. `TUIST_DEBUG=1` ile her kontrol bir `Tuist Cargo cache: verified` satırı yazdırır ve fark bulan kontroller derlemenin önbellek ölçümlerinde sapma olarak sayılır.

## Önbellek etkinliğini inceleme {#inspect-cache-activity}

İsabet oranlarını, kaydedilen aktarımları, gecikmeyi, throughput’u ve son derlemeleri incelemek için projenizin panosunda **Cargo Cache** bölümünü açın. Bireysel görev kararlarını ve CAS çıktılarını görmek için bir derlemenin **Cache** sekmesini açın.

Eksik ölçümler sıfır olarak sayılmaz ve bir önbellek isabeti mutlaka uzaktan indirme anlamına gelmez. Ayrıntılar için <.localized_link href="/guides/features/build-insights/rust#cache-measurements">Rust önbellek ölçümleri</.localized_link> bölümüne bakın.

## Sorun giderme {#troubleshooting}

Önbellek aktarımını ve raporlama hatalarını incelemek için hata ayıklama çıktısını etkinleştirin:

```sh
TUIST_DEBUG=1 tuist cargo build --release
```

Hata ayıklama çıktısı ayrıca bir derlemenin veya derleme betiği çalıştırmasının neden saklanmadığını da açıklar. Hiç isabet görmüyorsanız, başka bir derleyici sarmalayıcısının öncelik almadığını ve derleyici, bayraklar ile ortamın önbelleği dolduran derlemeyle eşleştiğini kontrol edin. Uzaktan yüklemeler için kimlik doğrulamayı ve hesabın önbellek yükleme politikasını da kontrol edin.
