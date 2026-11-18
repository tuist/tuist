---
{
  "title": "Rust için Cargo derleme önbelleği",
  "titleTemplate": ":title · Önbellek · Özellikler · Kılavuzlar · Tuist",
  "description": "Tuist'in Cargo derleme önbelleği ile CI ve yeni klonlarda Rust derleme süresini yarıya indirin; bu önbellek, derleme çıktılarını yerel olarak ve uzak bir önbellek üzerinden yeniden kullanır."
}
---
# Rust için Cargo derleme önbelleği {#rust-cache}

Tuist, desteklenen Rust derleme çıktılarını önbelleğe alır; böylece Cargo, derleme çıktıları kaldırıldıktan sonra bunları yeniden kullanabilir. Bu durum, `cargo clean` sonrasında, bir dal değişikliğinde veya başka bir checkout'ta gerçekleşebilir. Buna Cargo derleme önbelleği veya Rust derleme önbelleği de denilebilir: daha önceki bir derlemenin derlediği şeyleri, çalışma alanınızın artımlı olarak derlenmiş crate'leri dahil olmak üzere yeniden kullanarak Rust derleme sürelerini kısaltır. Önbellek, Tuist CLI'nin içine gömülüdür. Kurulması gereken ayrı bir önbellek yürütülebilir dosyası veya Cargo eklentisi yoktur.

<!-- @snippet: ./_rust-experimental -->

## Önbelleğe almayı etkinleştir {#enable-caching}

Projenizi bağlamak ve kimlik doğrulaması yapmak için <.localized_link href="/guides/get-started/rust-project">Rust projesi kurulumu</.localized_link> adımlarını izleyin. Ardından derlemenizi Tuist üzerinden çalıştırın:

```sh
tuist cargo build --release
```

Uygun derlemeler için önbelleğe alma otomatiktir. Ekstra bir önbellek yapılandırması veya etkinleştirme bayrağı gerekmez. Tuist, hesabınızın önbellek uç noktasını keşfeder ve mevcut proje ile sunucu yapılandırmanızı kullanarak önbellek kimlik bilgilerini elde eder.

Mise kullanıyorsanız, normal `cargo` komutlarını yazmaya devam etmek için <.localized_link href="/guides/get-started/rust-project#keep-typing-cargo">Cargo sarmalayıcısını yapılandırın</.localized_link>.

## Nasıl çalışır {#how-it-works}

Cargo başlamadan önce, Tuist kayıt defteri ve git bağımlılıklarınızın aynı araç zinciri, profil ve yapılandırmayla daha önceki bir derlemede ürettiği çıktıları geri yükler; böylece Cargo bunları güncel bulur. Neyin yeniden derleneceğine karar vermeye Cargo devam eder. Ardından, Cargo'nun hâlâ çalıştırdığı her uygun derleme için Tuist şunları yapar:

1. Eşleşen çıktılar için yerel önbelleğini kontrol eder.
2. Yerel bir önbellek ıskalaması durumunda, Uzak Yürütme API'si (REAPI) aracılığıyla Kura'yı sorgular, eksik içeriği indirir ve geri yüklemeden önce çıktıları doğrular.
3. Bir önbellek ıskalaması durumunda derleyiciyi çalıştırır. Başarılı bir derlemeden sonra çıktıları yerel olarak depolar ve yetkilendirildiğinde REAPI aracılığıyla Kura'ya yükler. Uzak önbellek girdisi, yalnızca başvurduğu tüm içerik kullanılabilir hale geldikten sonra yayımlanır.

CI ortamında, bir hedef dizindeki bir crate'in ilk derlemesi artımlı derleme olmadan çalışır; tıpkı Cargo 1.99 ve sonraki sürümlerin varsayılan olarak yaptığı gibi: yeniden kullanılabilecek önceki bir oturum yoktur, CI derlediklerini düzenlemez ve bir oturum oluşturmak bu derlemeyi yavaşlatır ve önbellek girdisini büyütür. Tuist, crate'i hedef dizinde hatırlar; böylece hedef dizinini koruyan bir iş, onu bir sonraki seferde artımlı olarak derler. Yerel derlemeler, Cargo'nun istediği şekilde artımlı olarak derlenir; bu sayede temiz bir derlemeden sonraki ilk düzenleme hızlı kalır. Önbellek girdileri her iki durumda da paylaşılır.

Aynı makinedeki derlemeler, diğer worktree'lerdeki veya hedef dizinlerdeki derlemeler dahil olmak üzere yerel önbelleği paylaşır. Başka bir derleme zaten aynı crate'i derliyor veya aynı derleme betiğini çalıştırıyorsa, Tuist onu bekler ve aynı işi iki kez yapmak yerine onun çıktılarını geri yükler. Bu derleme 10 dakikadan uzun sürerse, Tuist beklemeyi bırakır ve crate'i kendisi derler.

Yerel ve CI derlemeleri aynı uzak önbellek protokolünü kullanır. Okuma ve yazma erişimi, Tuist'in sunucu tarafından verilen önbellek kimlik bilgilerinden ve hesabınızın <.localized_link href="/guides/features/cache#restrict-uploads-to-ci">önbellek yükleme politikasından</.localized_link> gelir. Bir hesap, geliştiricilerin indirmesine izin verirken yüklemeleri CI ve hesap token'larıyla sınırlayabilir. Önbellek yazıcıları güvenilir kod üreticileridir: önbelleğe alınan derleyici çıktıları yürütülebilir koddur, bu nedenle yazma erişimini yalnızca güvendiğiniz makinelere ve token'lara verin.

Uzak kurulum başarısız olursa, yerel önbelleğe alma kullanılmaya devam eder. Kullanılamayan, eksik veya bozuk önbellek girdileri derlemeye geri döner. Bir yükleme hatası, derlemeyi başarısız kılmaz veya yerel önbellek girdisini silmez.

## Neler önbelleğe alınabilir {#what-can-be-cached}

Önbellek şunları destekler:

- Çalışma alanı ve yol crate'leri, bağımlılığı olan crate'ler ve oluşturulmuş kaynaklara sahip crate'ler dahil olmak üzere kitaplık crate'leri. Tuist, bunları derleyicinin okuduğu kaynaklara göre anahtarlar.
- `cargo check` ve `cargo clippy`, kitaplıkları yalnızca meta verilere derler. Girdileri derlemelerinkinden ayrıdır; bu nedenle bir check asla `cargo build` için bir kitaplık sağlamaz. `cargo clippy` tarafından düz derleyiciyle derlenen bağımlılıklar, çalışma alanı dışındaki yol crate'leri gibi, `cargo check` girdilerini yeniden kullanır.
- Apple silicon Mac'lerde ve glibc ile x86_64 ve arm64 Linux'ta, kaynak incelemenin önceden anahtarlayamadığı derlemeler; prosedürel makrolar, satır içi assembly veya yerel kitaplıklar kullanan crate'ler, prosedürel makroların kendileri ve bağlantılı yürütülebilir dosyalar. Tuist, her birinin okuduğu dosyaları, ortam değişkenlerini ve salt okunur komutları (örneğin `git describe`) kaydeder ve bunlara göre anahtarlar. Linux'ta, bir bağlantının okuduğu sistem bağlayıcısı, C kitaplığı ve başlangıç dosyaları anahtarın bir parçasıdır.
- Aynı platformlarda, derleme betiği çalıştırmaları; bunların gerçekleştirdiği C derlemeleri dahil (macOS'ta varsayılan Apple derleyicisiyle, Linux'ta herhangi bir dinamik bağlı derleyiciyle). Bir çalıştırma, yalnızca okuduğu dosyalar, ortam ve komutlar değişmediğinde geri yüklenir.
- Clippy lint'leri dahil olmak üzere, önbelleğe alınmış bir crate'in tekrar gösterdiği uyarılar ve diğer tanılar.

Aşağıdakiler hâlâ normal şekilde derlenir:

- Alpine gibi glibc olmayan Linux dağıtımlarında derleme betikleri ve kaydedilmiş derlemeler.
- Ağa bağlanan, Tuist'in gözlemleyemediği programları başlatan (Linux'ta statik bağlı programlar) veya çıktı dizinlerinin dışına yazan derleme betikleri.
- Özel hedefler ve desteklenmeyen derleyici argümanları veya kaynak girdileri.
- Prosedürel makroların ve derleme betiklerinin Clippy derlemeleri ve çalışma alanının her bildirimini ve kilitleme dosyasını `cargo metadata` aracılığıyla okuyan `cargo` lint grubunu etkinleştiren Clippy çalıştırmaları.
- Beklenmeyen derleyici çıktısı üreten derlemeler.
- Dinamik yükleyici ayarlarıyla, örneğin `LD_PRELOAD` ile veya Rust araç zinciri ve hedef dizini dışındaki `LD_LIBRARY_PATH` dizinleriyle çalışan derlemeler; örneğin kabuğunuzdan devralınanlar veya hedef dizini dışındaki bir `build.build-dir`.

Var olan küresel bir derleyici sarmalayıcısı, Tuist'in derleme önbelleğini ve derleyici gözlemcisini devre dışı bırakır. Clippy'ninki dışındaki özel çalışma alanı sarmalayıcıları da önbelleğe almayı atlar. <.localized_link href="/guides/features/build-insights/rust#other-compiler-tools">derleyici aracı uyumluluğu</.localized_link> bölümüne bakın.

Önbellek anahtarları paket içeriğini, derleyici ve araç zincirini, argümanları ve derleme ortamını içerir. Clippy girdileri ayrıca Clippy sürümüne, `CLIPPY_ARGS`, `CLIPPY_CONF_DIR`, `CLIPPY_DISABLE_DOCS_LINKS` içindeki lint argümanlarına, paketin `Cargo.toml` dosyasına ve Clippy'nin yüklediği `clippy.toml` veya `.clippy.toml` dosyalarına bağlıdır. Çıkış dizini, hedef dizini, Cargo ev dizini ve araç zinciri konumları yer tutucularla değiştirilir; böylece başka bir yoldaki bir çıkış aynı girdileri yeniden kullanır. Çıktısı kendi yolunu gömen (örneğin `env!("CARGO_MANIFEST_DIR")` aracılığıyla) bir crate yalnızca o yolda yeniden kullanılır. Kimlik bilgileri, Tuist raporlama ayarları ve tanınan CI çalıştırma meta verileri girdileri geçersiz kılmaz. Derleme sırasında bu dışlanan değişkenleri okuyan crate'ler önbelleğe alınmaz.

## Yeniden kullanımı doğrula {#verify-reuse}

Cargo zaten güncel çıktıları yeniden derlemekten kaçınır. Cargo'nun mevcut çıktıları yerine Tuist'in önbelleğini test etmek için bir kez derleyin, Cargo'nun çıktılarını kaldırın ve ardından aynı derlemeyi tekrarlayın:

```sh
tuist cargo build --release
cargo clean
tuist cargo build --release
```

Uygun kütüphaneler ikinci derlemede geri yüklenebilir; desteklenmeyen crate'ler hâlâ derlenir. Cargo'nun çıktılarını kaldırmak Tuist'in ayrı yerel önbelleğini kaldırmaz. Bu işlem yeniden kullanımı kontrol eder, mutlaka uzak indirmeleri değil: yerel bir isabet Kura'dan bir aktarım gerektirmez. Girdi doğrulama ve önbellek işlemleri ek yük getirir, bu nedenle derlemeyi atlamak küçük crate'ler için daha hızlı derlemeler garantilemez.

İsabetlerin doğru olduğunu kontrol etmek için, örneğin CI'da bir kanarya olarak, herhangi bir değişkeni `sampled` (her 64 crate'ten biri, her derlemede aynı crate'ler) veya `always` olarak ayarlayın:

- `TUIST_CARGO_VERIFY`, bir isabetin anahtarlandığı girdilerin hâlâ derleyicinin veya derleme betiğinin okuduklarıyla aynı olup olmadığını kontrol eder.
- `TUIST_CARGO_VERIFY_RECOMPILE` isabetleri tekrar derler ve çıktılarını önbellektekilerle karşılaştırır.

Doğrulanan bir crate, önbelleğe alınmamış gibi geri yüklenmek yerine derlenir; böylece çıktıları her zaman günceldir ve doğrulama derleme sonuçlarını değiştirmez. Doğrulama, doğrulanan crate'in önbellek girdisini asla saklamaz veya değiştirmez. Güncel çıktıları önbellektekilerden farklıysa, ona bağımlı olan crate'ler isabet edemez ve önbelleğe alınmamış bir derlemedeki gibi önbelleğe alınır. Artımlı derlemeler tekrarlanabilir değildir, bu nedenle bunlar için `TUIST_CARGO_VERIFY_RECOMPILE` yalnızca meta verileri ve bağımlılık bilgilerini karşılaştırır. `TUIST_DEBUG=1` ile her kontrol bir `Tuist Cargo cache: verified` satırı yazdırır ve fark bulan kontroller derlemenin önbellek ölçümlerinde sapma olarak sayılır.

## Önbellek etkinliğini incele {#inspect-cache-activity}

Projenizin panosundaki **Cargo Önbelleği** bölümünü açarak isabet oranlarını, kaydedilen aktarımları, gecikmeyi, throughput'u ve son derlemeleri inceleyin. Bireysel görev kararlarını ve CAS çıktılarını görmek için bir derlemenin **Önbellek** sekmesini açın.

Eksik ölçümler sıfır olarak sayılmaz ve bir önbellek isabeti mutlaka uzak bir indirme anlamına gelmez. Ayrıntılar için <.localized_link href="/guides/features/build-insights/rust#cache-measurements">Rust önbellek ölçümleri</.localized_link> bölümüne bakın.

## Sorun giderme {#troubleshooting}

Önbellek aktarımını ve raporlama hatalarını incelemek için hata ayıklama çıktısını etkinleştirin:

```sh
TUIST_DEBUG=1 tuist cargo build --release
```

Hata ayıklama çıktısı ayrıca bir derlemenin veya derleme betiği çalıştırmasının neden saklanmadığını da açıklar. Hiç isabet görmüyorsanız, başka bir derleyici sarmalayıcısının öncelik almadığını ve derleyici, bayraklar ile ortamın önbelleği dolduran derlemeyle eşleştiğini kontrol edin. Uzak yüklemeler için kimlik doğrulamayı ve hesabın önbellek yükleme politikasını da kontrol edin.
