---
{
  "title": "Rust önbelleği",
  "titleTemplate": ":title · Önbellek · Özellikler · Kılavuzlar · Tuist",
  "description": "Desteklenen Rust derleme çıktılarını yerel olarak ve Cargo ile Tuist'in uzak önbelleği üzerinden yeniden kullanın."
}
---
# Rust önbelleği {#rust-cache}

Tuist, desteklenen Rust derleme çıktılarını önbelleğe alır; böylece Cargo, derleme çıktıları kaldırıldıktan sonra bunları yeniden kullanabilir. Önbellek, Tuist CLI içine yerleşiktir. Kurulması gereken ayrı bir önbellek yürütülebilir dosyası veya Cargo eklentisi yoktur.

<!-- @snippet: ./_rust-experimental -->

## Önbelleğe almayı etkinleştirin {#enable-caching}

Projenizi bağlamak ve kimlik doğrulaması yapmak için <.localized_link href="/guides/get-started/rust-project">Rust proje kurulumu</.localized_link> adımlarını izleyin. Ardından derlemenizi Tuist üzerinden çalıştırın:

```sh
tuist cargo build --release
```

Uygun derlemeler için önbelleğe alma otomatiktir. Ekstra bir önbellek yapılandırması veya etkinleştirme bayrağı gerekmez. Tuist, hesabınızın önbellek uç noktasını keşfeder ve mevcut proje ile sunucu yapılandırmanızı kullanarak önbellek kimlik bilgilerini edinir.

mise kullanıyorsanız, normal `cargo` komutlarını yazmaya devam etmek için bir <.localized_link href="/guides/get-started/rust-project#keep-typing-cargo">Cargo sarmalayıcısı yapılandırın</.localized_link>.

## Nasıl çalışır {#how-it-works}

Cargo başlamadan önce, Tuist daha önce aynı araç zinciri, profil ve yapılandırmayla üretilmiş kayıt defteri ve git bağımlılıklarınızın çıktılarını geri yükler; böylece Cargo bunları güncel bulur. Neyin yeniden derleneceğine karar verme sorumluluğu Cargo'da kalır. Ardından, Cargo'nun hâlâ çalıştırdığı her uygun derleme için Tuist şunları yapar:

1. Eşleşen çıktılar için yerel önbelleğini kontrol eder.
2. Yerel bir önbellek ıskalaması durumunda, Uzak Yürütme API'si (REAPI) aracılığıyla Kura'yı sorgular, eksik içeriği indirir ve geri yüklemeden önce çıktıları doğrular.
3. Bir önbellek ıskalaması durumunda, derleyiciyi normal şekilde çalıştırır. Başarılı bir derlemeden sonra çıktıları yerel olarak depolar ve yetkilendirildiğinde REAPI aracılığıyla Kura'ya yükler. Uzak önbellek girdisi, başvurduğu tüm içerik kullanılabilir hale geldikten sonra yayımlanır.

Aynı makinedeki derlemeler, diğer çalışma ağaçlarındaki veya hedef dizinlerindeki derlemeler de dahil olmak üzere yerel önbelleği paylaşır. Başka bir derleme zaten aynı paketi derliyor veya aynı derleme betiğini çalıştırıyorsa, Tuist onu bekler ve aynı işi iki kez yapmak yerine onun çıktılarını geri yükler. Bu derleme 10 dakikadan uzun sürerse, Tuist beklemeyi bırakır ve paketi kendisi derler.

Yerel ve CI derlemeleri aynı uzak önbellek protokolünü kullanır. Okuma ve yazma erişimi, Tuist'in sunucu tarafından verilen önbellek kimlik bilgileri ve hesabınızın <.localized_link href="/guides/features/cache#restrict-uploads-to-ci">önbellek yükleme politikası</.localized_link> ile sağlanır. Bir hesap, geliştiricilerin indirmesine izin verirken yüklemeleri CI ve hesap jetonlarıyla sınırlayabilir. Önbellek yazarları güvenilir kod üreticileridir: önbelleğe alınan derleyici çıktıları yürütülebilir koddur, bu nedenle yazma erişimini yalnızca güvendiğiniz makineler ve jetonlara verin.

Uzak kurulum başarısız olursa, yerel önbelleğe alma kullanılabilir durumda kalır. Kullanılamayan, eksik veya bozuk önbellek girdileri derlemeye geri döner. Bir yükleme hatası, derlemeyi başarısız kılmaz veya yerel önbellek girdisini silmez.

## Neler önbelleğe alınabilir {#what-can-be-cached}

Önbellek şunları destekler:

- Çalışma alanı ve yol paketleri, bağımlılığı olan paketler ve oluşturulmuş kaynaklara sahip paketler de dahil olmak üzere kitaplık paketleri. Tuist, bunları derleyicinin okuduğu kaynaklara göre anahtarlar.
- Apple silicon Mac'lerde ve glibc ile x86_64 ve arm64 Linux'ta, kaynak incelemesinin önceden anahtarlayamadığı derlemeler; örneğin prosedürel makrolar, satır içi assembly veya yerel kitaplıklar kullanan paketler, prosedürel makroların kendileri ve bağlantılı yürütülebilir dosyalar. Tuist, her birinin okuduğu dosyaları, ortam değişkenlerini ve salt okunur komutları (örneğin `git describe`) kaydeder ve bunlara göre anahtarlar. Linux'ta, sistem bağlayıcısı, C kitaplığı ve bir bağlantının okuduğu başlangıç dosyaları anahtarının bir parçasıdır.
- Aynı platformlarda, gerçekleştirdikleri C derlemeleri de dahil olmak üzere derleme betiği çalıştırmaları (macOS'ta varsayılan Apple derleyicisi ile, Linux'ta herhangi bir dinamik olarak bağlantılı derleyici ile). Bir çalıştırma, yalnızca okuduğu dosyalar, ortam ve komutlar değişmediğinde geri yüklenir.
- Önbelleğe alınmış bir paketin tekrar gösterdiği uyarılar ve diğer tanılama bilgileri.

Şunlar hâlâ normal şekilde derlenir:

- Alpine gibi glibc olmayan Linux dağıtımlarındaki derleme betikleri ve kaydedilmiş derlemeler.
- Ağa bağlanan, Tuist'in gözlemleyemediği programları başlatan (Linux'ta statik olarak bağlantılı programlar) veya çıktı dizininin dışına yazan derleme betikleri.
- Artımlı derlemeler, özel hedefler ve desteklenmeyen derleyici argümanları veya kaynak girdileri.
- Yalnızca meta veri içeren `cargo check` çağrıları.
- Beklenmeyen derleyici çıktısı üreten derlemeler.
- `LD_PRELOAD` gibi dinamik yükleyici ayarlarıyla veya Rust araç zinciri ve hedef dizini dışındaki `LD_LIBRARY_PATH` dizinleriyle çalışan derlemeler; örneğin kabuğunuzdan miras alınanlar veya hedef dizini dışındaki bir `build.build-dir`.

Önceden var olan küresel bir derleyici sarmalayıcısı, Tuist'in derleme önbelleğini ve derleyici gözlemcisini devre dışı bırakır. Özel çalışma alanı sarmalayıcıları da önbelleğe almayı atlar. <.localized_link href="/guides/features/build-insights/rust#other-compiler-tools">derleyici aracı uyumluluğu</.localized_link> bölümüne bakın.

Önbellek anahtarları, paket içeriğini, derleyici ve araç zincirini, argümanları ve derleme ortamını içerir. Çekim, hedef dizini, Cargo evi ve araç zinciri konumları yer tutucularla değiştirilir; böylece başka bir yoldaki çekim aynı girdileri yeniden kullanır. Çıktısı kendi yolunu gömülü olarak içeren bir paket (örneğin `env!("CARGO_MANIFEST_DIR")` aracılığıyla) yalnızca o yolda yeniden kullanılır. Kimlik bilgileri, Tuist raporlama ayarları ve tanınan CI çalıştırma meta verileri girdileri geçersiz kılmaz. Derleme sırasında bu dışlanan değişkenleri okuyan paketler önbelleğe alınmaz.

## Yeniden kullanımı doğrulayın {#verify-reuse}

Cargo zaten güncel çıktıların yeniden derlenmesinden kaçınır. Tuist'in önbelleğini Cargo'nun mevcut çıktıları yerine test etmek için bir kez derleyin, Cargo'nun çıktılarını kaldırın ve ardından aynı derlemeyi tekrarlayın:

```sh
tuist cargo build --release
cargo clean
tuist cargo build --release
```

Uygun kitaplıklar ikinci derlemede geri yüklenebilir; desteklenmeyen paketler hâlâ derlenir. Cargo'nun çıktılarını kaldırmak, Tuist'in ayrı yerel önbelleğini kaldırmaz. Bu işlem yeniden kullanımı kontrol eder, mutlaka uzak indirmeleri değil: yerel bir isabet için Kura'dan bir aktarım gerekmez. Girdi doğrulama ve önbellek işlemleri ek yük getirir, bu nedenle derlemekten kaçınmak küçük paketler için daha hızlı derlemeler garanti etmez.

İsabetlerin doğru olduğunu kontrol etmek için, örneğin CI'da bir kanarya testi olarak, herhangi bir değişkeni `sampled` (her derlemede aynı paketlerle 64 paketten biri) veya `always` olarak ayarlayın:

- `TUIST_CARGO_VERIFY`, bir isabetin anahtarlandığı girdilerin hâlâ derleyicinin veya derleme betiğinin okudukları olup olmadığını kontrol eder.
- `TUIST_CARGO_VERIFY_RECOMPILE`, isabetleri tekrar derler ve çıktılarını önbellektekilerle karşılaştırır.

Doğrulanmış bir paket, önbelleğe alınmamış gibi davranarak geri yüklenmek yerine derlenir; bu nedenle çıktıları her zaman günceldir ve doğrulama derleme sonuçlarını değiştirmez. Doğrulama işlemi, doğrulanan paketin önbellek girdisini asla saklamaz veya değiştirmez. Güncel çıktıları önbellektekilerden farklıysa, buna bağımlı paketler isabet alamaz ve önbelleğe alınmamış bir derlemedeki gibi önbelleğe alınır. Artımlı derlemeler tekrarlanabilir olmadığından, bunlar için `TUIST_CARGO_VERIFY_RECOMPILE` yalnızca meta verileri ve bağımlılık bilgilerini karşılaştırır. `TUIST_DEBUG=1` ile her kontrol bir `Tuist Cargo cache: verified` satırı yazdırır ve fark bulan kontroller, derlemenin önbellek ölçümlerinde sapma olarak sayılır.

## Önbellek etkinliğini inceleyin {#inspect-cache-activity}

İsabet oranlarını, kaydedilen aktarımları, gecikmeyi, throughput'u ve son derlemeleri incelemek için projenizin panosunda **Cargo Cache** öğesini açın. Bireysel görev kararlarını ve CAS çıktılarını görmek için bir derlemenin **Cache** sekmesini açın.

Eksik ölçümler sıfır olarak sayılmaz ve bir önbellek isabeti mutlaka uzak bir indirme anlamına gelmez. Ayrıntılar için <.localized_link href="/guides/features/build-insights/rust#cache-measurements">Rust önbellek ölçümleri</.localized_link> bölümüne bakın.

## Sorun giderme {#troubleshooting}

Önbellek aktarım ve raporlama hatalarını incelemek için hata ayıklama çıktısını etkinleştirin:

```sh
TUIST_DEBUG=1 tuist cargo build --release
```

Hata ayıklama çıktısı ayrıca bir derlemenin veya derleme betiği çalıştırmasının neden saklanmadığını da açıklar. Hiç isabet görmüyorsanız, başka bir derleyici sarmalayıcısının öncelik almadığından ve derleyici, bayraklar ile ortamın önbelleği dolduran derlemeyle eşleştiğinden emin olun. Uzak yüklemeler için kimlik doğrulamayı ve hesabın önbellek yükleme politikasını da kontrol edin.
