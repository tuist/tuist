---
{
  "title": "Rust önbelleği",
  "titleTemplate": ":title · Önbellek · Özellikler · Kılavuzlar · Tuist",
  "description": "Desteklenen Rust derleme çıktılarını yerel olarak ve Cargo ile Tuist'in uzak önbelleği üzerinden yeniden kullanın."
}
---
# Rust önbelleği {#rust-cache}

Tuist, desteklenen Rust derleme çıktılarını önbelleğe alır; böylece Cargo, derleme çıktıları kaldırıldıktan sonra bunları yeniden kullanabilir. Önbellek, Tuist CLI’nin içine yerleşiktir. Kurulması gereken ayrı bir önbellek yürütülebilir dosyası veya Cargo eklentisi yoktur.

<!-- @snippet: ./_rust-experimental -->

## Önbelleğe almayı etkinleştir {#enable-caching}

Projenizi bağlamak ve kimlik doğrulaması yapmak için <.localized_link href="/guides/get-started/rust-project">Rust projesi kurulumu</.localized_link> kılavuzunu izleyin. Ardından derlemenizi Tuist üzerinden çalıştırın:

```sh
tuist cargo build --release
```

Uygun derlemeler için önbelleğe alma otomatiktir. Ek bir önbellek yapılandırması veya etkinleştirme bayrağı gerekmez. Tuist, hesabınızın önbellek uç noktasını keşfeder ve mevcut proje ile sunucu yapılandırmanızı kullanarak önbellek kimlik bilgilerini edinir.

mise kullanıyorsanız, normal `cargo` komutlarını yazmaya devam etmek için <.localized_link href="/guides/get-started/rust-project#keep-typing-cargo">Cargo sarmalayıcısını yapılandırın</.localized_link>.

## Nasıl çalışır {#how-it-works}

Cargo başlamadan önce, Tuist daha önceki bir derlemenin aynı araç zinciri, profil ve yapılandırmayla ürettiği kayıt defteri ve git bağımlılıklarınızın çıktılarını geri yükler; böylece Cargo bunları güncel bulur. Neyin yeniden derleneceğine karar vermek Cargo’nun sorumluluğunda kalır. Ardından, Cargo’nun hâlâ çalıştırdığı her uygun derleme için Tuist şunları yapar:

1. Eşleşen çıktılar için yerel önbelleğini kontrol eder.
2. Yerel bir önbellek ıskalamasında, Uzaktan Yürütme API’si (REAPI) aracılığıyla Kura’yı sorgular, eksik içeriği indirir ve geri yüklemeden önce çıktıları doğrular.
3. Bir önbellek ıskalamasında, derleyiciyi normal şekilde çalıştırır. Başarılı bir derlemeden sonra çıktıları yerel olarak depolar ve yetkilendirildiğinde REAPI aracılığıyla Kura’ya yükler. Uzak önbellek girişi, başvurduğu tüm içerik kullanılabilir hale geldikten sonra yayımlanır.

Yerel ve CI derlemeleri aynı uzak önbellek protokolünü kullanır. Okuma ve yazma erişimi, Tuist’in sunucu tarafından verilen önbellek kimlik bilgileri ve hesabınızın <.localized_link href="/guides/features/cache#restrict-uploads-to-ci">önbellek yükleme politikası</.localized_link> üzerinden sağlanır. Bir hesap, geliştiricilerin indirmesine izin verirken yüklemeleri CI ve hesap token’larıyla sınırlayabilir. Önbellek yazarları güvenilir kod üreticileridir: önbelleğe alınan derleyici çıktıları yürütülebilir koddur, bu nedenle yazma erişimini yalnızca güvendiğiniz makinelere ve token’lara verin.

Uzak kurulum başarısız olursa, yerel önbelleğe alma kullanılmaya devam eder. Kullanılamayan, eksik veya bozuk önbellek girdileri derlemeye geri döner. Bir yükleme hatası derlemeyi başarısız kılmaz veya yerel önbellek girdisini silmez.

## Neler önbelleğe alınabilir {#what-can-be-cached}

Önbellek şunları destekler:

- Çalışma alanı ve yol paketleri, bağımlılığı olan paketler ve oluşturulmuş kaynaklara sahip paketler dahil olmak üzere kitaplık paketleri. Tuist, bunları derleyicinin okuduğu kaynaklara göre anahtarlar.
- Apple silicon Mac’lerde, kaynak incelemesinin önceden anahtarlayamadığı derlemeler; örneğin prosedürel makrolar, satır içi assembly veya yerel kütüphaneler kullanan paketler, prosedürel makroların kendileri ve bağlantılı yürütülebilir dosyalar. Tuist, her birinin okuduğu dosyaları, ortam değişkenlerini ve salt okunur komutları (örneğin `git describe`) kaydeder ve bunlara göre anahtarlar.
- Apple silicon Mac’lerde, varsayılan Apple derleyicisiyle gerçekleştirdikleri C derlemeleri dahil olmak üzere derleme betiği çalıştırmaları. Bir çalıştırma yalnızca okuduğu dosyalar, ortam ve komutlar değişmediğinde geri yüklenir.
- Önbelleğe alınan bir paketin tekrar gösterdiği uyarılar ve diğer tanılama bilgileri.

Aşağıdakiler normal şekilde derlenmeye devam eder:

- Linux’ta derleme betikleri ve kaydedilmiş derlemeler.
- Ağa bağlanan, Tuist’in gözlemleyemediği programları başlatan veya çıktı dizininin dışına yazan derleme betikleri.
- Artımlı derlemeler, özel hedefler ve desteklenmeyen derleyici argümanları veya kaynak girdileri.
- Yalnızca meta veri içeren `cargo check` çağrıları.
- Beklenmeyen derleyici çıktısı üreten derlemeler.

Var olan küresel bir derleyici sarmalayıcısı, Tuist’in derleme önbelleğini ve derleyici gözlemcisini devre dışı bırakır. Özel çalışma alanı sarmalayıcıları da önbelleğe almayı atlar. <.localized_link href="/guides/features/build-insights/rust#other-compiler-tools">derleyici aracı uyumluluğu</.localized_link> bölümüne bakın.

Önbellek anahtarları paket içeriğini, derleyici ve araç zincirini, argümanları ve derleme ortamını içerir. Checkout, hedef dizin, Cargo home ve araç zinciri konumları yer tutucularla değiştirilir; böylece başka bir yoldaki checkout aynı girdileri yeniden kullanır. Çıktısı kendi yolunu gömən bir paket (örneğin `env!("CARGO_MANIFEST_DIR")` aracılığıyla) yalnızca o yolda yeniden kullanılır. Kimlik bilgileri, Tuist raporlama ayarları ve tanınan CI çalıştırma meta verileri girdileri geçersiz kılmaz. Derleme sırasında bu hariç tutulan değişkenleri okuyan paketler önbelleğe alınmaz.

## Yeniden kullanımı doğrula {#verify-reuse}

Cargo zaten güncel çıktıların yeniden derlenmesini önler. Cargo’nun mevcut çıktıları yerine Tuist’in önbelleğini test etmek için bir kez derleyin, Cargo’nun çıktılarını kaldırın ve ardından aynı derlemeyi tekrarlayın:

```sh
tuist cargo build --release
cargo clean
tuist cargo build --release
```

Uygun kitaplıklar ikinci derlemede geri yüklenebilir; desteklenmeyen paketler hâlâ derlenir. Cargo’nun çıktılarını kaldırmak, Tuist’in ayrı yerel önbelleğini kaldırmaz. Bu, yeniden kullanımı kontrol eder; mutlaka uzak indirmeleri değil: yerel bir isabet Kura’dan aktarım gerektirmez. Girdi doğrulama ve önbellek işlemleri ek yük getirir, bu nedenle derlemekten kaçınmak küçük paketler için daha hızlı derlemeler garantilemez.

## Önbellek etkinliğini incele {#inspect-cache-activity}

İsabet oranlarını, kaydedilen aktarımları, gecikmeyi, throughput’u ve son derlemeleri incelemek için projenizin panosundaki **Cargo Cache** bölümünü açın. Bireysel görev kararlarını ve CAS çıktılarını görmek için bir derlemenin **Cache** sekmesini açın.

Eksik ölçümler sıfır olarak sayılmaz ve bir önbellek isabeti mutlaka uzak bir indirme anlamına gelmez. Ayrıntılar için <.localized_link href="/guides/features/build-insights/rust#cache-measurements">Rust önbellek ölçümleri</.localized_link> bölümüne bakın.

## Sorun giderme {#troubleshooting}

Önbellek aktarımını ve raporlama hatalarını incelemek için hata ayıklama çıktısını etkinleştirin:

```sh
TUIST_DEBUG=1 tuist cargo build --release
```

Hata ayıklama çıktısı ayrıca bir derlemenin veya derleme betiği çalıştırmasının neden depolanmadığını da açıklar. Hiç isabet görmüyorsanız, başka bir derleyici sarmalayıcısının öncelik almadığını ve derleyici, bayraklar ile ortamın önbelleği dolduran derlemeyle eşleştiğini kontrol edin. Uzak yüklemeler için kimlik doğrulamayı ve hesabın önbellek yükleme politikasını da kontrol edin.
