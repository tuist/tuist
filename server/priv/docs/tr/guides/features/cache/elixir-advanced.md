---
title: Gelişmiş Elixir önbellek yapılandırması
titleTemplate: ":title · Önbellek · Kılavuzlar · Tuist"
description: Ek derleme girdilerini, bağımlılık seçimini ve taşınabilir yeniden kullanımı yapılandırın.
---

# Gelişmiş Elixir önbellek yapılandırması

<.localized_link href="/guides/features/cache/elixir">Elixir önbellek kurulum kılavuzu</.localized_link> ile başlayın. Aşağıdaki seçenekler yalnızca projenizde ek derleme girdileri, bağımlılık istisnaları veya farklı checkout yolları olduğunda gereklidir.

## Bağımlılıkları seçin

`cache: true` desteklenen bağımlılıkları otomatik olarak önbelleğe alır. Bir anahtar kelime listesi aynı otomatik seçimi sağlar, isteğe bağlı geçersiz kılmalarla:

```elixir
cache: [exclude: [:a_dependency_with_compile_time_side_effects]]
```

Önbelleğe almayı belirli bağımlılıklarla sınırlamak için:

```elixir
cache: [dependencies: [:nimble_options, :nimble_parsec]]
```

`dependencies: :all` tüm desteklenen bağımlılıkları açıkça seçer; `dependencies: []` hiçbirini seçmez. `exclude:` her iki seçim üzerinde de önceliklidir. `cache` öğesini atlamak veya onu `false` ya da `nil` olarak ayarlamak önbelleğe almayı devre dışı bırakır.

Desteklenen bağımlılıklar Hex veya Git üzerinden alınır ve Elixir/Erlang kaynaklarıyla standart Mix derleyici ardışık düzenini veya rebar3'ün olağan saf-BEAM derlemesini kullanır. Mix bağımlılıkları, yukarı akış bağımlılıkları rebar3 kullandığında yapıtları yeniden kullanabilir. Rebar yapılandırması, kaynak/başlık dosyaları ve rebar3 çalıştırılabilir dosyasının parmak izi anahtarlara katılır. Paketlenmiş `ebin/*.app` meta verileri ve pasif Makefile dosyaları da desteklenir. Rebar yapılandırma betikleri, aramadan önce Mix tarafından zaten değerlendirilmiştir; bunların kaynağı ve etkin yapılandırması anahtarlara girer. Uygulama kaynak betikleri (`*.app.src.script`) daha sonra rebar3 tarafından değerlendirilir ve denetlenmiş bir derleyici sözleşmesi gerektirir; bu durum derleme eklentileri ve derleme kanca işlevleri için de geçerlidir. Eksik bir rebar3 başlatıcısı, Mix'in normal yükleyicisi kullanılarak parmak izi oluşturulmadan önce kurulur; soğuk çalışanların hâlâ o yükleyiciye erişmesi gerekir.

Özel izleyiciler, kaynak sembolik bağlantıları, şemsiye kökleri ve yerel bağımlılıklar içeren zincirler normal şekilde derlenir. Tuist'in kendi bootstrap bağımlılıkları da soğuk çalışanlarda normal şekilde derlenir. Yapısal uygunluk, keyfi derleme kodunun yalıtılmış olduğunu kanıtlamaz.

## Ek girdileri bildirin

Kaynak ağaçları, kilitli bağımlılık kimlikleri, yukarı akış kaynakları, BEAM dosyaları ve kaynaklar, bağımlılık çalışma zamanı/isteğe bağlı/uygulama bayrakları, çözümlenmiş uygulama meta verileri, açık etkin uygulama yapılandırması, derleyici seçenekleri (lexer ve parser seçenekleri dahil), Mix ortamı ve hedefi ile araç zinciri kimliği otomatik olarak dahil edilir. Bağımlılığa özel `env:` ve `system_env:` anahtara girer ve yapılandırma o ortam altında değerlendirilir. Uygulama varsayılanları, VM yükleme durumu yerine kaynak girdileri üzerinden gelir.

Kaynak ağacının dışındaki dosyaları okuyan veya derleme sırasında ek ortam değişkenlerine ihtiyaç duyan bağımlılıklar için bu girdileri bildirin:

```elixir
cache: [
  inputs: ["schemas", "config/compiler-input.json"],
  env: ["YOUR_COMPILER_OPTION"]
]
```

Elixir makroları ve modül gövdeleri keyfi dosyaları, ortamı, ortamdaki kod yollarını, ağ yanıtlarını ve zamanı okuyabilir. Tuist bu okumaları otomatik olarak keşfetmez. Bildirilmemiş girdilerin değiştirilmesi eski çıktılar üretebilir. Zamana/ağa bağlı derleme yapan veya her derlemede çalışması gereken yan etkilere sahip bağımlılıkları hariç tutun; daha sıkı kontrol gerektiğinde denetlenmiş bir bağımlılık izin listesi için `dependencies:` kullanın.

Standart derleyici/çalışma zamanı değişkenleri (`ERL_COMPILER_OPTIONS`, `ELIXIR_ERL_OPTIONS`, `ERL_AFLAGS`, `ERL_FLAGS`, `ERL_ZFLAGS`, `SOURCE_DATE_EPOCH`, `ERL_LIBS`, `MIX_PATH` ve `MIX_ARCHIVES`) otomatik olarak yakalanır. Araç zinciri kimliği Elixir yapısını, mevcut olduğunda tam OTP sürümünü, ERTS'yi, derleyici bytecode'unu, işletim sistemi/sürümünü, mimariyi, kelime boyutunu ve bayt sırasını içerir. Etkin bağlam her aramadan önce yakalanır. Bağımlılık başına girdi modelleri, tek bir hazırlık içinde arama planlaması için paylaşılabilir; derleme planı temizler ve geri yükleme yüklü uygulamanın kayıtlarını geçersiz kılar. Aşamalı kurulum ve yayınlama, arama planını yeniden kullanmadan her zaman yeni girdileri kontrol eder. Bir arama isabetsizliği de derlemeden önce yeni bir anahtar yakalar. Değişen girdiler, daha önceki girdiler için derlenmiş kodu kurmak yerine aşamalı bir isabeti reddeder.

Anahtarlar deterministik terim kodlaması ve sıralı dosya sistemi taraması kullanır. Sırasız derleyici bildirimleri ve bildirilen girdi kümeleri sıralanır ve yinelenenler kaldırılır; sıralı derleyici seçenekleri sırasını korur. Dosya içeriği, adları, çalıştırılabilir bitleri ve eksik yollar önemlidir; dosya sistemi zaman damgaları değil. Dosya bildirimleri sahiplik, zaman damgaları veya diğer dosya sistemi meta verilerini modellemez; çıktıları bu değerlerden türeten derleyicileri hariç tutun. Yukarı akış derleyici manifestoları artımlı defter tutumu olarak hariç tutulur; içeriklerini bilinçli olarak okuyan kod bunları ek girdiler olarak bildirmelidir. Regex yapılandırması kaynağını ve seçeneklerini kullanır, asla VM yerel derlenmiş başvuruları kullanmaz. Diğer opak çalışma zamanı değerleri önbelleğe almayı atlar. Güncellenen anahtar modelleri, bir migrasyon olmadan eski girdileri geçersiz kılar.

Deterministik anahtar kodlama, deterministik derleyici çıktısından ayrıdır. Son Elixir sürümlerinde aksi takdirde özdeş derlemeler arasında yukarı akış BEAM meta verileri değişiyorsa, SDK bootstrap, tohumlama ve önbellek tüketiminden önce `ERL_COMPILER_OPTIONS='[deterministic]'` ayarlamayı düşünün. Bunu mevcut derleyici seçenekleriyle birleştirin ve ayarı değiştirdiğinizde bağımlılık çıktılarını bir kez yeniden derleyin. SDK bunu otomatik olarak ayarlamaz; tam değeri anahtarın bir parçası olarak kalır. Tam yukarı akış baytlar hâlâ hash'lenir, normalize edilmez veya çıkarılmaz. Bu, cross-checkout veya keyfi derleyici çoğaltılabilirlik garantisi değildir. Derleyici seçeneği ayrıca `module_info(:compile)` içinden kaynak/seçenekleri dışlar, bu nedenle benimsemeden önce kapsam, hata ayıklama ve kaynak keşif araçlarını doğrulayın. Derleyici bayrakları sırasız derleme zamanı üreticilerini düzeltmez. SDK, güvenlik yamalarını da içeren Mint 1.10.2 veya sonraki bir sürümü gerektirir. Bu sürüm, HTTP/2 çerçeve işlevlerini oluşturmak için kullanılan haritaları sıralar; SDK'yı yükseltirken eski Mint kilit girdilerini güncelleyin. Diğer bağımlılıklar ve derleyici geçişleri, `deterministic` etkin olsa bile değişken bootstrap BEAM dosyaları üretebilir.

Lexer ve parser çıktıları, yalnızca kilitli Git ağacında veya Hex paket dosya manifestosunda bulunmadıklarında türetilmiş dosyalar olarak ele alınır. Dağıtılan `.erl` dosyaları ve opak dizin/alt modül içerikleri olağan girdiler olarak kalır; yeniden oluşturulan dağıtılan dosyalar aynı sahne sonrası girdi uzlaştırmasından geçmelidir. OTP'nin `parsetools` içindeki üretici şablonları da araç zinciri kimliğine girer. Eşzamanlı derlemeler arasında bağımlılık kaynak checkout'larını yalıtılmış tutun: üreticiler ve yerel derleyiciler `deps/` içine yazabilir. İç içe/özel rebar üretici düzenleri hâlâ denetlenmiş bir `generated` bildirimi gerektirebilir.

## Yerel ve özel derleyiciler

Denetlenmiş bir Mix, rebar3 veya Make derleyicisi için bağımlılık başına bir sözleşme bildirin:

```elixir
cache: [
  builders: [
    bcrypt_elixir: [
      platform: "build-image@sha256:YOUR_IMMUTABLE_IMAGE_DIGEST",
      outputs: ["priv/bcrypt_nif.so"],
      tools: ["cc", "make"],
      env: ["YOUR_BUILDER_OPTION"]
    ]
  ]
]
```

`platform`, uyumlu yerel derleme ortamını tanımlar. Derleyicileri, SDK'ları, sistem başlık dosyalarını ve paylaşılan kütüphaneleri kapsayan, `linux` gibi yeniden kullanılabilir bir etiket yerine değişmez bir imaj/araç zinciri kimliği kullanın. Elixir/OTP ve olağan platform kontrolleri hâlâ geçerlidir. Bu, derleyicinin açık bir denetimidir; yerel girdilerin veya gerekli yan etkilerin otomatik olarak keşfedilmesi değildir. Geçersiz açık derleyici sözleşmeleri, önbelleğe almayı sessizce devre dışı bırakmak yerine düzeltilebilir bir yapılandırma hatası oluşturur.

`outputs`, bağımlılığın uygulama derleme dizinine göreli gereken yolları listeler. Çalışma zamanında ihtiyaç duyulan gerçek kütüphaneleri/yürütülebilir dosyaları listeleyin. Eksik çıktılar, Mix BEAM dosyalarını güncel kabul etse bile geri yüklemeyi veya derlemeyi tetikler; eksik anlık görüntüler reddedilir. Ek ortam değişkenlerini derleyicinin `env` ile ve harici dosyaları/dizinleri `inputs` ile, tüketen projeye göreli olarak bildirin. Yerel anahtarlar, bağımlılığın etkili `system_env` geçersiz kılmalarını kullanarak `PATH`, `CC`, `CXX`, `CFLAGS`, `LDFLAGS`, `SDKROOT` ve `RUSTFLAGS` gibi standart derleme ortamı değişkenlerini otomatik olarak içerir. Çözümlenmiş Mix proje yapılandırması da derleyici anahtarlarına girer. Bağımlılığın kendi `mix.exs` dosyasında tanımlanan işlevler, yakalanan bir derleme takma adı gibi, isme göre girer çünkü bu dosyanın baytları zaten bir girdidir; diğer işlev değerli yapılandırmalar önbelleğe alınamaz.

İsteğe bağlı `tools` isimleri o etkili `PATH` üzerinde çözülür; göreli araç yolları bağımlılık kaynak dizinine göredir. Yürütülebilir baytlar ve çözümlenen yollar anahtara girer ve mevcut olmayan bildirilen araçlar önbelleğe almayı atlar. Bir başlatıcı veya derleyici sarmalayıcı parmak izi, SDK'larını, alt süreçlerini veya sistem kütüphanelerini kapsamaz: değişmez `platform` ve ek `inputs` bunları kapsamalıdır. `MAKEFLAGS` olduğu gibi korunur çünkü özel derleyiciler bunu okuyabilir. Devralınan GNU make jobserver tanımlayıcıları bu nedenle çalıştırmalar arasında güvenli önbellek isabet eksikliklerine neden olabilir; bu değerlerin anahtardan kaldırıldığını varsaymak yerine yalıtılmış bir önbellek işinde kararlı derleme bayrakları kullanın.

Bazı derleyiciler yalnızca `_build/` yerine `deps/` altında dosyalar oluşturur. Bu yolları, o bağımlılığın kaynak dizinine göreli olarak `generated` içinde listeleyin, örneğin `generated: ["priv/native"]`. Yalnızca bu oluşturulan yollar kaynak girdilerinden hariç tutulur. Orijinal kaynakları veya kaynak dosyalarını hariç tutmayın: bunlar girdi olarak kalmalıdır. Yollar harfi harfine alınır, glob desenleri veya gezinme yoktur. Sözleşme, platform, ek girdiler, ortam değerleri ve herhangi bir özel bağımlılık derleme komutu anahtarlara katılır. `compile: false`, derlemeden çıkmak için bir tercih olarak kalır; bu tür bağımlılıklar ne önbelleğe alınır ne de raporlanır.

Denetlenmiş anlık görüntüler, kaynak destekli `ebin`, `priv`, `include` ve `src` kaynaklarını geri yüklenen uygulamaya somutlaştırır. Yerel kütüphaneler, port yürütülebilirleri, başlık dosyaları ve oluşturulan kaynaklar bu nedenle bağımlılık kaynaklarını değiştirmeden soğuk bir checkout'ta hayatta kalır. Yürütülebilir modları ve içerdikleri göreli kaynak sembolik bağlantıları korunur; kaçan, mutlak ve döngüsel bağlantılar reddedilir. Tüm yukarı akış uygulama kaynakları aşağı akış anahtarlara girer; yalnızca yerel kütüphaneler veya BEAM'lar değil, sıradan `priv` kaynakları ve özel çıktı dizinleri de dahildir. Üretici kaynak yollarını doğrudan okuyan kod taşınmaz; uygulama yapısının dışında zorunlu yan etkileri olan derleyiciler hâlâ bu adımlara ihtiyaç duyar.

### Yerel olmayan derleyiciler

Bazı özel derleme adımları yerel araç zinciri çalıştırmaz: paketin zaten dağıttığı bir dosyayı kopyalayan, biçimlendirilmiş kaynaklarda `mix format` çalıştıran veya boş bir dizin oluşturan bir takma ad, bir uygulama kaynak betiği, yalnızca bir belge sağlayıcı ekleyen bir rebar3 eklentisi veya paketteki bir sağlama toplamı dosyasına karşı doğrulanan önceden derlenmiş bir NIF indirmesi. Bunları bir `platform` yerine `native: false` ile denetleyin:

```elixir
cache: [
  builders: [
    phoenix: [native: false, outputs: []],
    lumis: [
      native: false,
      outputs: ["priv/native"],
      generated: ["priv/native"],
      env: ["LUMIS_BUILD", "LUMIS_USE_LEGACY_ARTIFACTS", "TARGET_ARCH", "TARGET_OS"]
    ]
  ]
]
```

Bu anahtarlar `PATH` ve diğer yerel derleme değişkenlerini dışarıda bırakır, böylece farklı imajlara ve araç zinciri konumlarına sahip makineler yapıtları paylaşır. `tools` ve `platform` kabul edilmez. Diğer her şey hâlâ geçerlidir: kaynaklar, bağımlılığın çözümlenmiş yapılandırması ve derleme takma adları, Elixir/OTP ve işletim sistemi ailesi anahtarda kalır ve `outputs`, `generated`, `env` ve `inputs` yukarıdakiyle aynı anlamdadır. Adımın okuduğu her değişkeni bildirin, örneğin önceden derlenmiş bir NIF varyantını seçen veya kaynak derlemesini zorlayanlar. `deps/` içine yazan bir adım bu yolları `generated` içinde listelemelidir. Değişen kaynaklar derlemeden sonra hâlâ yakalanır. `native: false` yalnızca çıktısı yerel bir araç zincirine bağlı olmayan bir adım için kullanın; bir derleyici çalıştığında bir `platform` sözleşmesi kullanın.

Girdileri ve çıktıları denetlenene kadar özel derleyicileri hariç tutun. Bir sözleşme, soğuk SDK bootstrap derlemesini, 64 MiB yapıt sınırını veya uyumlu bir derleme ortamı ihtiyacını kaldırmaz.

## Checkout yolları arasında yeniden kullanım

Checkout yolları varsayılan olarak anahtarlara katılır. Bağımlılıklarınız üretici yollarına güvenmiyorsa, farklı checkout konumları arasında yeniden kullanımı etkinleştirin:

```elixir
cache: [portable: true]
```

Checkout yolunu gömülü yapılandırılmış değerler, örneğin `config/config.exs` içinde `__DIR__` üzerinden oluşturulan yollar, taşınabilir anahtarları değiştirmez. Elixir araç zincirinizin kurulu olduğu yer de bunu değiştirmez: arşivler ve rebar3 içeriklerine göre sayılır. Derleyici anahtarları `PATH` dışarıda bırakır, bildirilen `tools` isimlerini ve baytlarını nerede bulunduklarına göre değil isme ve baytlara göre adlandırır ve diğer yerel derleme değişkenlerinin içindeki checkout yolunu değiştirir. Aynı `platform` üzerinde aynı araçlarla derlenen yerel bir bağımlılık bu nedenle başka bir makinede anahtarını korur. Aşağı akış bağımlılıkları da yerel çıktılar bayt bazında özdeş olduğunda anahtarları paylaşır; mutlak yolları kaydeden derleyici hata ayıklama bilgileri bunu engeller.

Önbelleğe alınmış BEAM'lar üretici hata ayıklama/kaynak yollarını ve derleme zamanı `__DIR__`, `__ENV__.file` ve `File.cwd!()` değerlerini korur. Taşınabilir yeniden kullanım bunları yeniden yazmaz. Kaynak bağlantıları mevcut kaynak checkout'una işaret eder. Yukarı akış BEAM baytları da anahtarlara girer ve yollar gömebilir, bu nedenle yeniden kullanım yukarı akış kapanışının bağımsız olarak yeniden derlenmesi yerine aynı önbellekten geri yüklenmesini gerektirebilir.

## Depolama ve erişim

| Seçenek | Varsayılan | Amaç |
| --- | --- | --- |
| `remote` | `true` | Yerel bir isabet eksikliğinden sonra paylaşılan uzak önbelleği kullanın. |
| `upload` | `true` | Yeni paketleri uzakta yayınlayın. `false` okumalara ve yerel anlık görüntülere izin vermeye devam eder. |
| `path` | Tuist'in önbellek dizini, `mix/dependencies/v1` altında | Farklı bir yerel depo seçin. |
| `endpoint` | Otomatik olarak keşfedilir | Hesabın HTTPS REAPI uç noktasını geçersiz kılın. |

`upload: false` istemci davranışını kontrol eder, yetkilendirmeyi değil. Proje önbelleği izinleri sunucu tarafından uygulanır. Yalnızca projenin önbelleğini okuyabilen kimlik bilgileri yüklemeleri otomatik olarak atlar. Proje `endpoint:` seçenekleri ve keşfedilen uç noktalar, geri döngü (`localhost`, `127.0.0.1`, `::1`) geliştirme uç noktaları hariç HTTPS gerektirir.

Boş olmayan bir `TUIST_CACHE_ENDPOINT`, hem `endpoint:` hem de keşfi geçersiz kılar. Barındırılan çalıştırıcılar, küme içindeki özel önbelleklerine erişmek için bunu kullanır. Operatör tarafından kontrol edilen bu ortam geçersiz kılması, geri döngü olmayan ana bilgisayarlarda HTTP'ye de izin verir. HTTP, proje kapsamındaki önbellek belirtecini ve yapıtları şifrelenmemiş olarak gönderir, bu nedenle yalnızca güvenilir bir ağda kullanın. Geçersiz bir geçersiz kılma, keşfi denemeden yerel anlık görüntülere geri döner.

Yerel anlık görüntüler ve uzak paketler 64 MiB ile sınırlıdır; daha büyük yapıtlar önbelleğe alınmadan derlenir. Yerel depoda otomatik tahliye yoktur; gerektiğinde içeriğini kaldırın. Uzak yapıtlar Kura'nın mevcut saklama, tahliye ve proje temizleme kurallarını kullanır.

> [!IMPORTANT]
> Derleyici manifestoları ve BEAM'lar, gizli bilgiler dahil olmak üzere üretici yollarını ve derleme zamanı değerlerini gömebilir. Proje önbelleği okuyucuları bu yapıtlara erişebilir. Önbellek yazıcıları güvenilir kod üreticileridir: özet kontrolleri bozulmayı algılar, kötü amaçlı yürütülebilir BEAM'ları değil. Önbellek yazma kimlik bilgilerini güvenilmeyen PR işlerine açmayın veya bu kimlik bilgileri mevcutken güvenilmeyen bağımlılıkları derlemeyin.

## Eksik isabetleri giderme

- Paketi yükledikten sonra `mix tuist.setup` komutunu çalıştırın ve oluşturulan Mix yapılandırmasını commit edin. Kurulum diğer takma adları ve Tuist seçeneklerini korur; özelleştirilmiş derleme eylemlerini sessizce kaldırmak yerine reddeder.
- Oluşturulan derleme takma adını koruyun. Doğrudan `mix tuist.compile` görev keşfi, önbellekleme onları inceleyemeden önce bağımlılıkları derleyebilir.
- Seçilen, desteklenen bağımlılıklar için zaten güncel ve geçerli çıktılar, `up_to_date` nedeniyle yerel isabet olarak sayılır. Bunlar geriye dönük olarak yayınlanmaz ve herhangi bir yapıt anahtarı, aktarım baytı, geri yükleme gecikmesi veya tahmini tasarruf edilen süre taşımaz. Bir anlık görüntü geri yüklemesini test etmek için, önbelleği doldurduktan sonra yalnızca desteklenen bir bağımlılığın derlemesini `mix deps.clean NAME --build` ile temizleyin, ardından tekrar derleyin.
- Mevcut çıktılar yayınlanmadığından, çalıştırmalar arasında `_build` tutan bir CI işi yalnızca yeniden derlediği bağımlılıkları yükler. Diğer makinelere her şey için isabet sağlamak için, kullandıkları her `MIX_ENV` için yazma erişimiyle boş bir `_build` üzerinden derleme yapın.
- Her bağımlılığın sonucunu (`local_hit`, `remote_hit`, `miss` veya nedeni ile birlikte `bypass`) ve yapıt anahtarını yazdırmak için `TUIST_DEBUG=1` ayarlayın. Bu, derleme raporu gönderilemediğinde bile çalışır, örneğin salt okunur bir önbellek belirteci ile. Farklı bir girişi bulmak için makineler arasındaki anahtarları karşılaştırın.
- `MIX_ENV`, `MIX_TARGET`, derleyici ayarlarını ve bildirilen girişleri eşleştirin. Taşınabilir yeniden kullanım etkinleştirilmedikçe yol değişiklikleri de anahtarları değiştirir.
- Desteklenmeyen bağımlılıklar eksik isabet olarak değil, **Önbelleğe alınmamış** olarak görünür. İsabet oranından hariç tutulurlar. Ne aramalar ne de güncel yerel isabetler içeren bir derlemenin oranı kullanılamaz durumdadır, %0 değildir.
- Eksik kimlik bilgileri, kullanılamayan uç noktalar ve bozuk anlık görüntüler derlemeye geri döner. Derleyici hataları derlemeyi yine de başarısız kılar.
- CAS kayıtları derleme raporundan sonra gelebilir. Yeni alınan aktarımları görmek için yenileyin. Yerel isabetlerin ve eski derlemelerin uzak CAS çıktıları yoktur.

Sunucuların, `up_to_date` yerel isabetleri kaydetmek için derleme-raporu sözleşmesi `0.2` desteğine ihtiyacı vardır. Daha eski bir sunucu önbellek verilerini veya bir şema numaralandırma değerini açıkça reddederse, paket bu yeni yeniden kullanım gözlemleri olmadan raporu bir kez yeniden dener. Derleme ayrıntıları ve diğer önbellek sonuçları korunur; sunucu yükseltilene kadar yeni yerel yeniden kullanım kullanılamaz durumda kalır. Sunucuyu önce dağıtmak bu ek isteği önler. Sözleşme sürümü desteği pazarlık etmez ve kimlik doğrulama hataları, taşıma hataları ve diğer doğrulama mesajları yeniden denenmez. Numaralandırma hataları daha eski sunucularda alanlarını tanımlamaz; saklanan geçersiz bir alan tek yeniden denemede yine de başarısız olur.

## Manuel derleme entegrasyonu

Kurulum projenizin yapılandırmasını güvenli bir şekilde düzenleyemiyorsa, özel derleme eylemlerini koruyarak bu takma adı ve bu işlevleri Mix proje modülünüze manuel olarak ekleyin:

```elixir
# In aliases/0:
compile: &compile/1

# In the same Mix project module:
defp compile(args) do
  if "--no-compile" not in args do
    compile_tuist_ex()
  end

  Mix.Task.run("deps.loadpaths", ["--no-compile", "--no-deps-check"])
  Mix.Task.run("tuist.compile", args)
end

defp compile_tuist_ex do
  deps =
    ["tuist_ex"]
    |> Mix.Dep.filter_by_name(Mix.Dep.load_and_cache(), include_children: true)
    |> Enum.reject(&(Mix.Dep.ok?(&1) and &1.scm.fetchable?()))
    |> Enum.map(&Atom.to_string(&1.app))

  if deps != [], do: Mix.Task.run("deps.compile", deps)
end
```

Bu işlevler, soğuk paralel derlemeler dahil olmak üzere Tuist'i diğer bağımlılıklardan önce derler ve yükler; Tuist ve bağımlılıkları zaten derlendiğinde veya komut `--no-compile` ile çalıştırıldığında bu işi atlar. Aynı işlevler Hex, Git ve yol kurulumlarıyla çalışır; betik yolu gerekmez.

Takma adınız `deps.compile tuist_ex --include-children` ile başlarsa, her `mix compile` Tuist'in bağımlılıklarını yeniden derler ve tüm projenizi yeniden derleyebilir. Değiştirmek için `mix tuist.setup` komutunu tekrar çalıştırın.

## Nasıl çalışır

Elixir önbellekleme, ayrı bir Mix depolama hizmeti yerine Bazel tarafından kullanılan paylaşılan REAPI ActionCache/CAS hattını, kimlik doğrulamayı ve Kura imzalı analitiği kullanır. Modellenen bir giriş anahtarı, tam bir derleme paketinin ham bayt SHA-256 özetini içeren bir ActionResult'a referans verir. Tuist, aşamalı kurulumdan önce dosyalarını, uygulama meta verilerini, bildirilen BEAM'ları ve SCM manifestosunu doğrular. Bozuk girdiler başarılı derlemeden sonra onarılır.

OTP 28 ve sonrasında, uzak oturumlar en az 1 KiB'lik ByteStream aktarımları için zstd sıkıştırmasını müzakere eder. Sıkıştırılamayan yüklemeler, daha eski OTP çalışma zamanları ve sıkıştırma olmayan sunucular kimlik taşımasını kullanır. Özetler, yapıt sınırları ve bildirilen baytlar sıkıştırılmamış içeriği ifade eder. Kodu çözülmüş baytlar kurulmadan önce sınırlandırılır ve doğrulanır. Her bağımlılık tek bir CAS paketi olarak kalır, küçük yapıtlar için dosya başına veya parça isteklerinden kaçınır.

Uzak kimlik bilgileri/bağlantıları tembel olarak çözülür; boşta kalan derlemeler ve yerel isabetler (zaten güncel çıktılar dahil) uzak uç noktalarla iletişim kurmaz. Her çıkışta, derleyici hatası dahil, bir oturum kapatılır. İstemci RPC'lerinin 30 saniyelik bir zaman aşımı vardır. Mix, kilit kontrolleri, yerel bağımlılık derlemesi ve desteklenmeyen işlerden sorumlu olmaya devam eder.

Panel gecikmesi/bayt verileri, yerel ve uzak kaynak ayrımını korur ve kullanılamayan değerleri ölçülen sıfırdan ayırır. Uzak zamanlama, istemci CAS aktarımlarını ölçer; yerel zamanlama ise doğrulama ve kurulumu içerir; hiçbiri derlemeyi kapsamaz. CAS Çıktıları, yerel kopyalar veya eylem-giriş anahtarları yerine başarılı Kura imzalı aktarımları kullanır. Aktarım hızı, baytların ölçülen süreye bölünmesiyle hesaplanır; sıkıştırılmış boyutlar mevcut değildir. Tahmini kazanılan derleme süresi, üreticinin orijinal derleme süresidir, uçtan uca ölçülen derleme tasarrufu değildir.

Bağımsız ve hazır bağımlılıklar, aynı HTTP/2 bağlantısı üzerinden en fazla dört eşzamanlı isteklik pencereler halinde getirilir. Bu, kodu çözülmüş paket arabelleğini yapıt başına 64 MiB sınırına tabi olan dört yapıtla sınırlar. Anahtar planlama, Mix durumu ve kurulum seri olarak gerçekleşir. Alt akış anahtarları, üst akış yapıtlarını bekler; önceden getirilen baytlar yalnızca tam giriş anahtarı altında tüketilir ve uzak kurulumdan önce girdiler yeniden kontrol edilir. Zaten güncel çıktılar ve yerel anlık görüntüler spekülatif uzak isteklere neden olmaz. Seçili önbellek isabetsizliklerinde derleme ve yüklemeler seri kalır; eşzamanlılık her derlemenin daha hızlı olacağının garantisi değildir.

## Her bağımlılık derlemeyi atlayabilir mi?

Uyumlu bir isabet, desteklenen bir bağımlılığın derlemesini atlayabilir ancak `cache: true` açık başarısızdır, sıfır derleme garantisi vermez. Eksik/temizlenmiş girdiler, desteklenmeyen derleyiciler ve soğuk SDK başlatma yine de derleme yapabilir. Yüksek isabet oranı tek başına duvar saati hızlanması sağlamaz.

Bir kez derle/çok kez test et CI senaryoları için
<.localized_link href="/guides/features/test-sharding/elixir">Elixir test sharding</.localized_link>
hazırlanmış derlemeyi dağıtmak için kullanın; bunun yerine her işçinin bağımlılık başına önbellek isabetlerinden derlemeyi yeniden oluşturmasını beklemeyin. Tam bir derlemeyi, özellikle yerel kütüphaneler içerenleri yeniden kullanmak yine de uyumlu bir platform, araç zinciri ve yapılandırma gerektirir. Keyfi özel derlemeler, harici girdilerini, çıktılarını ve gerekli yan etkilerini modellemeden derleme adımlarını güvenli bir şekilde atlayamaz.
