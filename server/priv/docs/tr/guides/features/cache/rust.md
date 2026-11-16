---
{
  "title": "Rust önbelleği",
  "titleTemplate": ":title · Önbellek · Özellikler · Kılavuzlar · Tuist",
  "description": "Desteklenen Rust derleme çıktılarını yerel olarak ve Cargo ile Tuist'in uzak önbelleği üzerinden yeniden kullanın."
}
---
# Rust önbelleği {#rust-cache}

Tuist, desteklenen Rust derleme çıktılarını önbelleğe alır; böylece Cargo, derleme çıktıları kaldırıldıktan sonra bunları yeniden kullanabilir. Önbellek, Tuist CLI’nin içine gömülüdür. Kurulması gereken ayrı bir önbellek yürütülebilir dosyası veya Cargo eklentisi yoktur.

<!-- @snippet: ./_rust-experimental -->

## Önbelleğe almayı etkinleştirme {#enable-caching}

Projenizi bağlamak ve kimlik doğrulaması yapmak için <.localized_link href="/guides/get-started/rust-project">Rust projesi kurulumu</.localized_link> adımlarını izleyin. Ardından derlemenizi Tuist üzerinden çalıştırın:

```sh
tuist cargo build --release
```

Uygun derlemeler için önbelleğe alma otomatiktir. Ek bir önbellek yapılandırması veya etkinleştirme bayrağı gerekmez. Tuist, hesabınızın önbellek uç noktasını keşfeder ve mevcut proje ile sunucu yapılandırmanızı kullanarak önbellek kimlik bilgilerini edinir.

mise kullanıyorsanız, normal `cargo` komutlarını yazmaya devam etmek için <.localized_link href="/guides/get-started/rust-project#keep-typing-cargo">Cargo sarmalayıcısı yapılandırın</.localized_link>.

## Nasıl çalışır {#how-it-works}

Cargo başlamadan önce, Tuist aynı araç zinciri, profil ve yapılandırmayla daha önceki bir derlemede üretilen kayıt defteri ve git bağımlılıklarınızın çıktılarını geri yükler; böylece Cargo bunları güncel bulur. Nelerin yeniden derleneceğine karar verme sorumluluğu Cargo’da kalır. Ardından, Cargo’nun hâlâ çalıştırdığı her uygun derleme için Tuist şunları yapar:

1. Eşleşen çıktılar için yerel önbelleğini kontrol eder.
2. Yerel önbellek ıskalaması durumunda, Uzak Yürütme API’si (REAPI) aracılığıyla Kura’yı sorgular, eksik içeriği indirir ve çıktıları geri yüklemeden önce doğrular.
3. Önbellek ıskalaması durumunda, derleyiciyi normal şekilde çalıştırır. Başarılı bir derlemeden sonra çıktıları yerel olarak depolar ve yetkilendirildiğinde REAPI aracılığıyla Kura’ya yükler. Uzak önbellek girdisi, başvurduğu tüm içerik kullanılabilir hale geldikten sonra yayımlanır.

Aynı makinedeki derlemeler, diğer çalışma ağaçlarındaki veya hedef dizinlerdeki derlemeler dahil olmak üzere yerel önbelleği paylaşır. Başka bir derleme zaten aynı crate’i derliyor veya aynı derleme betiğini çalıştırıyorsa, Tuist onu bekler ve aynı işi iki kez yapmak yerine onun çıktılarını geri yükler. Bu derleme 10 dakikadan uzun sürerse, Tuist beklemeyi bırakır ve crate’i kendisi derler.

Yerel ve CI derlemeleri aynı uzak önbellek protokolünü kullanır. Okuma ve yazma erişimi, Tuist’in sunucu tarafından verilen önbellek kimlik bilgilerinden ve hesabınızın <.localized_link href="/guides/features/cache#restrict-uploads-to-ci">önbellek yükleme politikasından</.localized_link> gelir. Bir hesap, geliştiricilerin indirmesine izin verirken yüklemeleri CI ve hesap jetonlarıyla kısıtlayabilir. Önbellek yazarları güvenilir kod üreticileridir; önbelleğe alınan derleyici çıktıları yürütülebilir koddur, bu nedenle yazma erişimini yalnızca güvendiğiniz makineler ve jetonlara verin.

Uzak kurulum başarısız olursa, yerel önbelleğe alma kullanılmaya devam eder. Kullanılamayan, eksik veya bozuk önbellek girdileri derlemeye geri döner. Bir yükleme hatası derlemeyi başarısız kılmaz veya yerel önbellek girdisini silmez.

## Neler önbelleğe alınabilir {#what-can-be-cached}

Önbellek şunları destekler:

- Çalışma alanı ve yol crate’leri, bağımlılığı olan crate’ler ve oluşturulmuş kaynaklara sahip crate’ler dahil olmak üzere kitaplık crate’leri. Tuist, bunları derleyicinin okuduğu kaynaklara göre anahtarlar.
- Apple silicon Mac’lerde, kaynak incelemenin önceden anahtarlayamadığı derlemeler; örneğin prosedürel makrolar, satır içi assembly veya yerel kütüphaneler kullanan crate’ler, prosedürel makroların kendileri ve bağlantılı yürütülebilir dosyalar. Tuist, her birinin okuduğu dosyaları, ortam değişkenlerini ve salt okunur komutları (örneğin `git describe`) kaydeder ve bunlara göre anahtarlar.
- Apple silicon Mac’lerde, varsayılan Apple derleyicisiyle gerçekleştirdikleri C derlemeleri dahil olmak üzere derleme betiği çalıştırmaları. Bir çalıştırma, yalnızca okuduğu dosyalar, ortam ve komutlar değişmediğinde geri yüklenir.
- Önbelleğe alınmış bir crate’in tekrar gösterdiği uyarılar ve diğer tanılama bilgileri.

Aşağıdakiler hâlâ normal şekilde derlenir:

- Linux’ta derleme betikleri ve kaydedilmiş derlemeler.
- Ağa bağlanan, Tuist’in gözlemleyemediği programları başlatan veya çıktı dizininin dışına yazan derleme betikleri.
- Artımlı derlemeler, özel hedefler ve desteklenmeyen derleyici argümanları veya kaynak girdileri.
- Yalnızca meta veri içeren `cargo check` çağrıları.
- Beklenmeyen derleyici çıktısı üreten derlemeler.
- Dinamik yükleyici ayarlarıyla (örneğin `LD_PRELOAD`) veya Rust araç zinciri ve hedef dizininin dışındaki `LD_LIBRARY_PATH` dizinleriyle çalışan derlemeler; örneğin kabuğunuzdan devralınanlar veya hedef dizininin dışındaki bir `build.build-dir`.

Var olan küresel bir derleyici sarmalayıcısı, Tuist’in derleme önbelleğini ve derleyici gözlemcisini devre dışı bırakır. Özel çalışma alanı sarmalayıcıları da önbelleğe almayı atlar. <.localized_link href="/guides/features/build-insights/rust#other-compiler-tools">derleyici aracı uyumluluğu</.localized_link> bölümüne bakın.

Önbellek anahtarları paket içeriğini, derleyici ve araç zincirini, argümanları ve derleme ortamını içerir. Çekim, hedef dizini, Cargo evi ve araç zinciri konumları yer tutucularla değiştirilir; böylece başka bir yoldaki çekim aynı girdileri yeniden kullanır. Çıktısı kendi yolunu gömen (örneğin `env!("CARGO_MANIFEST_DIR")` aracılığıyla) bir crate, yalnızca o yolda yeniden kullanılır. Kimlik bilgileri, Tuist raporlama ayarları ve tanınan CI çalıştırma meta verileri girdileri geçersiz kılmaz. Derleme sırasında hariç tutulan bu değişkenleri okuyan crate’ler önbelleğe alınmaz.

## Yeniden kullanımı doğrulama {#verify-reuse}

Cargo zaten güncel çıktıların yeniden derlenmesinden kaçınır. Tuist’in önbelleğini, Cargo’nun mevcut çıktıları yerine test etmek için bir kez derleyin, Cargo’nun çıktılarını kaldırın ve ardından aynı derlemeyi tekrarlayın:

```sh
tuist cargo build --release
cargo clean
tuist cargo build --release
```

Uygun kitaplıklar ikinci derlemede geri yüklenebilir; desteklenmeyen crate’ler hâlâ derlenir. Cargo’nun çıktılarını kaldırmak, Tuist’in ayrı yerel önbelleğini kaldırmaz. Bu işlem yeniden kullanımı kontrol eder, mutlaka uzak indirmeleri değil: yerel bir isabet için Kura’dan bir aktarım gerekmez. Girdi doğrulama ve önbellek işlemleri ek yük getirir; bu nedenle derlemekten kaçınmak, küçük crate’ler için daha hızlı derlemeler garantilemez.

İsabetlerin doğru olduğunu kontrol etmek için, örneğin CI’da canary testi olarak, herhangi bir değişkeni `sampled` (her 64 crate’ten biri, her derlemede aynı crate’ler) veya `always` olarak ayarlayın:

- `TUIST_CARGO_VERIFY`, bir isabetin anahtarlandığı girdilerin hâlâ derleyicinin veya derleme betiğinin okudukları olup olmadığını kontrol eder.
- `TUIST_CARGO_VERIFY_RECOMPILE`, isabetleri tekrar derler ve çıktılarını önbellektekilerle karşılaştırır.

Doğrulanan bir crate, önbelleğe alınmamış gibi geri yüklenmek yerine derlenir; böylece çıktıları her zaman günceldir ve doğrulama derleme sonuçlarını değiştirmez. Doğrulama, doğrulanan crate’in önbellek girdisini asla saklamaz veya değiştirmez. Güncel çıktıları önbellektekilerden farklıysa, ona bağımlı crate’ler isabet edemez ve önbelleğe alınmamış bir derlemedeki gibi önbelleğe alınır. Artımlı derlemeler tekrarlanabilir değildir; bu nedenle bunlar için `TUIST_CARGO_VERIFY_RECOMPILE` yalnızca meta verileri ve bağımlılık bilgilerini karşılaştırır. `TUIST_DEBUG=1` ile her kontrol bir `Tuist Cargo cache: verified` satırı yazdırır ve fark bulan kontroller, derlemenin önbellek ölçümlerinde sapma olarak sayılır.

## Önbellek etkinliğini inceleme {#inspect-cache-activity}

İsabet oranlarını, kaydedilen aktarımları, gecikmeyi, verimliliği ve son derlemeleri incelemek için projenizin panosunda **Cargo Önbelleği** öğesini açın. Bireysel görev kararlarını ve CAS çıktılarını görmek için bir derlemenin **Önbellek** sekmesini açın.

Eksik ölçümler sıfır olarak sayılmaz ve bir önbellek isabeti mutlaka uzak bir indirme anlamına gelmez. Ayrıntılar için <.localized_link href="/guides/features/build-insights/rust#cache-measurements">Rust önbellek ölçümleri</.localized_link> bölümüne bakın.

## Sorun giderme {#troubleshooting}

Önbellek aktarımını ve raporlama hatalarını incelemek için hata ayıklama çıktısını etkinleştirin:

```sh
TUIST_DEBUG=1 tuist cargo build --release
```

Hata ayıklama çıktısı ayrıca bir derlemenin veya derleme betiği çalıştırmasının neden saklanmadığını da açıklar. Hiç isabet görmüyorsanız, başka bir derleyici sarmalayıcısının öncelik almadığını ve derleyicinin, bayrakların ve ortamın önbelleği dolduran derlemeyle eşleştiğini kontrol edin. Uzak yüklemeler için kimlik doğrulamayı ve hesabın önbellek yükleme politikasını da kontrol edin.
