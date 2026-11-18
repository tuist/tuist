---
title: Gelişmiş Elixir önbellek yapılandırması
titleTemplate: ":title · Önbellek · Kılavuzlar · Tuist"
description: Ek derleme girdilerini, bağımlılık seçimini ve taşınabilir yeniden kullanımı yapılandırın.
---

# Gelişmiş Elixir önbellek yapılandırması

<.localized_link href="/guides/features/cache/elixir">Elixir önbellek kurulum kılavuzu</.localized_link> ile başlayın. Aşağıdaki seçenekler yalnızca projenizde ek derleme girdileri, bağımlılık istisnaları veya farklı çekim yolları olduğunda gereklidir.

## Bağımlılıkları seçin

`cache: true` desteklenen bağımlılıkları otomatik olarak önbelleğe alır. Bir anahtar kelime listesi de aynı otomatik seçimi yapar ve isteğe bağlı geçersiz kılmalar içerir:

```elixir
cache: [exclude: [:a_dependency_with_compile_time_side_effects]]
```

Önbelleğe almayı belirli bağımlılıklarla sınırlamak için:

```elixir
cache: [dependencies: [:nimble_options, :nimble_parsec]]
```

`dependencies: :all` tüm desteklenen bağımlılıkları açıkça seçer; `dependencies: []` hiçbirini seçmez. `exclude:` her iki seçim üzerinde de önceliklidir. `cache` öğesini atlamak veya onu `false` ya da `nil` olarak ayarlamak önbelleğe almayı devre dışı bırakır.

Desteklenen bağımlılıklar Hex veya Git üzerinden alınır ve Elixir/Erlang kaynaklarıyla standart Mix derleyici hattını veya rebar3’ün sıradan saf-BEAM derlemesini kullanır. Mix bağımlılıkları, yukarı akış bağımlılıkları rebar3 kullandığında yapıtları yeniden kullanabilir. Rebar yapılandırması, kaynak/başlık dosyaları ve rebar3 çalıştırılabilirinin parmak izi anahtarlara katılır. Paketlenmiş `ebin/*.app` meta verileri ve pasif Makefile’lar da desteklenir. Rebar yapılandırma betikleri, aramadan önce Mix tarafından zaten değerlendirilmiştir; bunların kaynağı ve etkin yapılandırması anahtarlara girer. Uygulama kaynak betikleri (`*.app.src.script`) daha sonra rebar3 tarafından değerlendirilir ve denetlenmiş bir derleyici sözleşmesi gerektirir; bu durum derleme eklentileri ve derleme kanca işlevleri için de geçerlidir. Eksik bir rebar3 başlatıcısı, Mix’in normal yükleyicisi kullanılarak parmak izi oluşturulmadan önce kurulur; soğuk çalışanların yine de bu yükleyiciye erişmesi gerekir.

Özel izleyiciler, kaynak sembolik bağlantıları, şemsiye kökleri ve yerel bağımlılıklar içeren zincirler normal şekilde derlenir. Tuist’in kendi bootstrap bağımlılıkları da soğuk çalışanlarda normal şekilde derlenir. Yapısal uygunluk, rastgele derleme kodunun yalıtılmış olduğunu kanıtlamaz.

## Ek girdileri bildirin

Kaynak ağaçları, kilitli bağımlılık kimlikleri, yukarı akış kaynakları, BEAM’ler ve kaynaklar, bağımlılık çalışma zamanı/isteğe bağlı/uygulama bayrakları, çözümlenmiş uygulama meta verileri, açık etkin uygulama yapılandırması, derleyici seçenekleri (lexer ve ayrıştırıcı seçenekleri dahil), Mix ortamı ve hedefi ile araç zinciri kimliği otomatik olarak dahil edilir. Bağımlılığa özel `env:` ve `system_env:` anahtara girer ve yapılandırma o ortam altında değerlendirilir. Uygulama varsayılanları, VM yükleme durumu yerine kaynak girdileri aracılığıyla girer.

Derleme sırasında kaynak ağacının dışındaki dosyaları veya ek ortam değişkenlerini okuyan bağımlılıklar için bu girdileri bildirin:

```elixir
cache: [
  inputs: ["schemas", "config/compiler-input.json"],
  env: ["YOUR_COMPILER_OPTION"]
]
```

Elixir makroları ve modül gövdeleri rastgele dosyaları, ortamı, ortamdaki kod yollarını, ağ yanıtlarını ve zamanı okuyabilir. Tuist bu okumaları otomatik olarak keşfetmez. Bildirilmemiş girdilerin değiştirilmesi eski çıktıların oluşmasına neden olabilir. Zaman/ağ bağımlı derlemesi olan veya her derlemede yürütülmesi gereken yan etkileri bulunan bağımlılıkları hariç tutun; daha sıkı kontrol gerektiğinde denetlenmiş bir bağımlılık izin listesini kullanmak için `dependencies:` öğesini kullanın.

Standart derleyici/çalışma zamanı değişkenleri (`ERL_COMPILER_OPTIONS`, `ELIXIR_ERL_OPTIONS`, `ERL_AFLAGS`, `ERL_FLAGS`, `ERL_ZFLAGS`, `SOURCE_DATE_EPOCH`, `ERL_LIBS`, `MIX_PATH` ve `MIX_ARCHIVES`) otomatik olarak yakalanır. Araç zinciri kimliği; Elixir derlemesini, varsa tam OTP sürümünü, ERTS’yi, derleyici bayt kodunu, işletim sistemi/sürümü, mimariyi, kelime boyutunu ve bayt sırasını içerir. Etkin bağlam her aramadan önce yakalanır. Bağımlılık başına girdi modelleri, tek bir hazırlık içinde arama planlaması için paylaşılabilir; derleme planı temizler ve geri yükleme yüklü uygulamanın kayıtlarını geçersiz kılar. Aşamalı kurulum ve yayınlama, arama planını yeniden kullanmadan her zaman yeni girdileri kontrol eder. Bir arama isabetsizliği de derlemeden önce yeni bir anahtar yakalar. Değişen girdiler, daha önceki girdiler için derlenen kodu kurmak yerine aşamalı bir isabeti reddeder.

Anahtarlar deterministik terim kodlaması ve sıralı dosya sistemi taraması kullanır. Sırasız derleyici bildirimleri ve bildirilen girdi kümeleri sıralanır ve yinelenenlerden arındırılır; sıralı derleyici seçenekleri sırasını korur. Dosya içerikleri, adlar, çalıştırılabilir bitler ve eksik yollar önemlidir; dosya sistemi zaman damgaları değildir. Dosya bildirimleri sahiplik, zaman damgaları veya diğer dosya sistemi meta verilerini modellemez; çıktıları bu değerlerden türeten derleyicileri hariç tutun. Yukarı akış derleyici manifestoları artımlı defter tutma olarak hariç tutulur; içeriklerini bilinçli olarak okuyan kod bunları ek girdiler olarak bildirmelidir. Regex yapılandırması kaynağını ve seçeneklerini kullanır, asla VM yerel derlenmiş başvuruları kullanmaz. Diğer şeffaf olmayan çalışma zamanı değerleri önbelleğe almayı atlar. Güncellenen anahtar modelleri, geçiş olmadan eski girişleri geçersiz kılar.

Deterministik anahtar kodlama, deterministik derleyici çıktısından ayrıdır. Son Elixir sürümlerinde aksi takdirde özdeş derlemeler arasında yukarı akış BEAM meta verileri değişiyorsa, SDK bootstrap, tohumlama ve önbellek tüketiminden önce `ERL_COMPILER_OPTIONS='[deterministic]'` ayarlamayı düşünün. Bunu mevcut derleyici seçenekleriyle birleştirin ve ayarı değiştirdiğinizde bağımlılık çıktılarını bir kez yeniden derleyin. SDK bunu otomatik olarak ayarlamaz; kesin değeri anahtarın bir parçası olarak kalır. Tam yukarı akış baytlar hâlâ karma yapılır, normalize edilmez veya çıkarılmaz. Bu, çapraz çekim veya keyfi derleyici tekrarlanabilirliği garantisi değildir. Derleyici seçeneği ayrıca `module_info(:compile)` içinden kaynak/seçenekleri çıkarır, bu nedenle benimsemeden önce kapsam, hata ayıklama ve kaynak keşif araçlarını doğrulayın. Derleyici bayrakları sırasız derleme zamanı üreticilerini düzeltmez. SDK, güvenlik yedeklemeleri dahil olmak üzere Mint 1.10.2 veya sonraki bir sürümü gerektirir. Bu sürüm, HTTP/2 çerçeve işlevlerini oluşturmak için kullanılan haritaları sıralar; SDK’yı yükseltirken eski Mint kilit girişlerini güncelleyin. Diğer bağımlılıklar ve derleyici geçişleri, `deterministic` etkin olsa bile değişken bootstrap BEAM’leri üretebilir.

Lexer ve ayrıştırıcı çıktıları, yalnızca kilitli Git ağacında veya Hex paket dosya manifestosunda bulunmadıklarında türetilmiş dosyalar olarak ele alınır. Dağıtılan `.erl` dosyaları ve şeffaf olmayan dizin/alt modül içerikleri sıradan girdiler olarak kalır; yeniden oluşturulan dağıtılan dosyalar aynı sahne sonrası girdi uzlaştırmasından geçmelidir. OTP’nin `parsetools` ürününden gelen üretici şablonları da araç zinciri kimliğine girer. Bağımlılık kaynak çekimlerini eşzamanlı derlemeler arasında yalıtılmış tutun: üreticiler ve yerel derleyiciler `deps/` içine yazabilir. İç içe/özel rebar üretici düzenleri hâlâ denetlenmiş bir `generated` bildirimi gerektirebilir.

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

`platform`, uyumlu yerel derleme ortamını tanımlar. Derleyicileri, SDK’ları, sistem başlıklarını ve paylaşılan kütüphaneleri kapsayan değişmez bir imaj/araç zinciri kimliği kullanın; `linux` gibi yeniden kullanılabilir bir etiket kullanmayın. Elixir/OTP ve olağan platform kontrolleri hâlâ geçerlidir. Bu, derleyicinin açık bir denetimidir; yerel girdilerin veya gerekli yan etkilerin otomatik olarak keşfedilmesi değildir. Geçersiz açık derleyici sözleşmeleri, önbelleğe almayı sessizce devre dışı bırakmak yerine düzeltilebilir bir yapılandırma hatası oluşturur.

`outputs`, bağımlılığın uygulama derleme dizinine göreli gerekli yolları listeler. Çalışma zamanında gereken gerçek kütüphaneleri/çalıştırılabilir dosyaları listeleyin. Eksik çıktılar, Mix BEAM’leri güncel kabul etse bile geri yüklemeyi veya derlemeyi tetikler; eksik anlık görüntüler reddedilir. Tüketen projeye göreli olarak derleyicinin `env` ile ek ortam değişkenlerini ve `inputs` ile harici dosyaları/dizinleri bildirin. Yerel anahtarlar, bağımlılığın etkili `system_env` geçersiz kılmalarını kullanarak `PATH`, `CC`, `CXX`, `CFLAGS`, `LDFLAGS`, `SDKROOT` ve `RUSTFLAGS` gibi standart derleme ortamı değişkenlerini otomatik olarak içerir. Çözümlenmiş Mix proje yapılandırması da derleyici anahtarlarına girer. Bağımlılığın kendi `mix.exs` dosyasında tanımlanan işlevler, yakalanan bir derleme takma adı gibi, ada göre girer çünkü bu dosyanın baytları zaten bir girdidir; diğer işlev değerli yapılandırmalar önbelleğe alınamaz.

İsteğe bağlı `tools` adları o etkili `PATH` üzerinde çözümlenir; göreli araç yolları bağımlılık kaynak dizinine göredir. Çalıştırılabilir baytlar ve çözümlenen yollar anahtara girer ve kullanılamayan bildirilen araçlar önbelleğe almayı atlar. Bir başlatıcı veya derleyici sarmalayıcı parmak izi, SDK’larını, alt süreçlerini veya sistem kütüphanelerini kapsamaz: bunları değişmez `platform` ve ek `inputs` kapsamalıdır. `MAKEFLAGS`, özel derleyiciler bunu okuyabildiği için olduğu gibi korunur. Devralınan GNU make jobserver tanımlayıcıları bu nedenle çalıştırmalar arasında güvenli önbellek isabet eksikliklerine neden olabilir; bu değerlerin anahtardan kaldırıldığını varsaymak yerine, yalıtılmış bir önbellek işinde kararlı derleme bayrakları kullanın.

Bazı derleyiciler yalnızca `_build/` yerine `deps/` altında dosyalar oluşturur. Bu yolları, o bağımlılığın kaynak dizinine göreli olarak `generated` içinde listeleyin, örneğin `generated: ["priv/native"]`. Yalnızca bu oluşturulan yollar kaynak girdilerinden hariç tutulur. Orijinal kaynakları veya kaynak dosyalarını hariç tutmayın: bunlar girdi olarak kalmalıdır. Yollar kelimenin tam anlamıyla alınır, glob desenleri veya gezinme yoktur. Sözleşme, platform, ek girdiler, ortam değerleri ve herhangi bir özel bağımlılık derleme komutu anahtarlara katılır. `compile: false`, derlemeden çıkış için bir tercih olarak kalır; bu tür bağımlılıklar ne önbelleğe alınır ne de raporlanır.

Denetlenmiş anlık görüntüler, kaynak destekli `ebin`, `priv`, `include` ve `src` kaynaklarını geri yüklenen uygulamaya somutlaştırır. Yerel kütüphaneler, port çalıştırılabilir dosyaları, başlıklar ve oluşturulan kaynaklar bu nedenle bağımlılık kaynaklarını değiştirmeden soğuk bir çekimden sağ çıkar. Çalıştırılabilir modları ve içerdikleri göreli kaynak sembolik bağlantıları korunur; kaçan, mutlak ve döngüsel bağlantılar reddedilir. Tüm yukarı akış uygulama kaynakları, yalnızca yerel kütüphaneler veya BEAM’ler değil, sıradan `priv` kaynakları ve özel çıktı dizinleri dahil olmak üzere aşağı akış anahtarlarına girer. Üretici kaynak yollarını doğrudan okuyan kod yeniden konumlandırılmaz; uygulama yapısının dışında zorunlu yan etkileri olan derleyiciler hâlâ bu adımlara ihtiyaç duyar.

### Yerel olmayan derleyiciler

Bazı özel derleme adımları yerel bir araç zinciri çalıştırmaz: paketin zaten dağıttığı bir dosyayı kopyalayan, biçimlendirilmiş kaynaklarda `mix format` çalıştıran veya boş bir dizin oluşturan bir takma ad, bir uygulama kaynak betiği, yalnızca bir belge sağlayıcı ekleyen bir rebar3 eklentisi veya paketteki bir sağlama toplamı dosyasına karşı doğrulanan önceden derlenmiş bir NIF indirmesi. Bunları bir `platform` yerine `native: false` ile denetleyin:

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

Bu anahtarlar `PATH` ve diğer yerel derleme değişkenlerini dışarıda bırakır, böylece farklı imajlara ve araç zinciri konumlarına sahip makineler yapıtları paylaşır. `tools` ve `platform` kabul edilmez. Diğer her şey hâlâ geçerlidir: kaynaklar, bağımlılığın çözümlenmiş yapılandırması ve derleme takma adları, Elixir/OTP ve işletim sistemi ailesi anahtarda kalır ve `outputs`, `generated`, `env` ve `inputs` yukarıdakiyle aynı anlamdadır. Adımın okuduğu her değişkeni, örneğin önceden derlenmiş bir NIF varyantını seçen veya kaynak derlemesini zorlayanları bildirin. `deps/` içine yazan bir adım, bu yolları `generated` içinde listelemelidir. Değişen kaynaklar derlemeden sonra hâlâ yakalanır. `native: false` yalnızca çıktısı yerel bir araç zincirine bağlı olmayan bir adım için kullanın; bir derleyici çalıştığında bir `platform` sözleşmesi kullanın.

Girdileri ve çıktıları denetlenene kadar özel derleyicileri hariç tutun. Bir sözleşme, soğuk SDK bootstrap derlemesini, 64 MiB yapıt sınırını veya uyumlu bir derleme ortamı ihtiyacını kaldırmaz.

## Çekim yolları arasında yeniden kullanım

Çekim yolları varsayılan olarak anahtarlara katılır. Bağımlılıklarınız üretici yollarına güvenmiyorsa, farklı çekim konumları arasında yeniden kullanımı etkinleştirin:

```elixir
cache: [portable: true]
```

Çekim yolunu gömülen yapılandırılmış değerler, örneğin `config/config.exs` içinde `__DIR__` ile oluşturulan yollar, taşınabilir anahtarları değiştirmez. Elixir araç zincirinizin yüklendiği yer de değiştirmez: arşivler ve rebar3 içeriklerine göre sayılır. Derleyici anahtarları `PATH` dışarıda bırakır, bildirilen `tools` öğelerini nerede bulunduklarına göre değil ada ve baytlara göre adlandırır ve diğer yerel derleme değişkenlerinin içindeki çekim yolunu değiştirir. Bu nedenle, aynı `platform` üzerinde aynı araçlarla derlenen yerel bir bağımlılık, başka bir makinede anahtarını korur. Yerel çıktılar bayt düzeyinde özdeş olduğunda aşağı akış bağımlılıkları da anahtarları paylaşır; bu durum, mutlak yolları kaydeden derleyici hata ayıklama bilgileri tarafından engellenir.

Önbelleğe alınan BEAM’ler, üretici hata ayıklama/kaynak yollarını ve derleme zamanı `__DIR__`, `__ENV__.file` ve `File.cwd!()` değerlerini korur. Taşınabilir yeniden kullanım bunları yeniden yazmaz. Kaynak bağlantıları mevcut kaynak çekimine işaret eder. Yukarı akış BEAM baytları da anahtarlara girer ve yollar gömebilir, bu nedenle yeniden kullanım, yukarı akış kapanışını bağımsız olarak yeniden derlemek yerine aynı önbellekten geri yüklemeyi gerektirebilir.

## Depolama ve erişim

| Seçenek | Varsayılan | Amaç |
| --- | --- | --- |
| `remote` | `true` | Yerel bir isabet eksikliğinden sonra paylaşılan uzak önbelleği kullanın. |
| `upload` | `true` | Yeni paketleri uzaktan yayınlayın. `false` okuma ve yerel anlık görüntülere hâlâ izin verir. |
| `path` | Tuist'in önbellek dizini, `mix/dependencies/v1` altında | Farklı bir yerel depolama alanı seçin. |
| `endpoint` | Otomatik olarak keşfedilir | Hesabın HTTPS REAPI uç noktasını geçersiz kılın. |

`upload: false` istemci davranışını kontrol eder, yetkilendirmeyi değil. Proje önbelleği izinleri sunucu tarafından uygulanır. Yalnızca projenin önbelleğini okuyabilen kimlik bilgileri yüklemeleri otomatik olarak atlar. Proje `endpoint:` seçenekleri ve keşfedilen uç noktalar, geri döngü (`localhost`, `127.0.0.1`, `::1`) geliştirme uç noktaları hariç HTTPS gerektirir.

Boş olmayan bir `TUIST_CACHE_ENDPOINT`, hem `endpoint:` hem de keşfi geçersiz kılar. Barındırılan çalıştırıcılar, küme içindeki özel önbelleklerine erişmek için bunu kullanır. Operatör tarafından kontrol edilen bu ortam geçersiz kılması, geri döngü olmayan ana bilgisayarlarda HTTP'ye de izin verir. HTTP, proje kapsamındaki önbellek belirtecini ve yapıtları şifrelenmemiş olarak gönderir; bu nedenle yalnızca güvenilir bir ağda kullanın. Geçersiz bir geçersiz kılma, keşfi denemeden yerel anlık görüntülere geri döner.

Yerel anlık görüntüler ve uzak paketler 64 MiB ile sınırlıdır; daha büyük yapıtlar önbelleğe alınmadan derlenir. Yerel depoda otomatik tahliye yoktur; gerektiğinde içeriğini kaldırın. Uzak yapıtlar Kura'nın mevcut saklama, tahliye ve proje temizleme kurallarını kullanır.

> [!IMPORTANT]
> Derleyici bildirimleri ve BEAM'ler, gizli bilgiler dahil olmak üzere üretici yollarını ve derleme zamanı değerlerini gömebilir. Proje önbelleği okuyucuları bu yapıtlara erişebilir. Önbellek yazıcıları güvenilir kod üreticileridir: özet kontrolleri bozulmayı algılar, kötü niyetli çalıştırılabilir BEAM'leri değil. Önbellek yazma kimlik bilgilerini güvenilmeyen PR işlerine açmayın veya bu kimlik bilgileri mevcutken güvenilmeyen bağımlılıkları derlemeyin.

## Eksik isabetleri giderme

- Paketi kurduktan sonra `mix tuist.setup` komutunu çalıştırın ve oluşturulan Mix yapılandırmasını commit edin. Kurulum diğer takma adları ve Tuist seçeneklerini korur; özelleştirilmiş derleme eylemlerini sessizce kaldırmak yerine reddeder.
- Oluşturulan derleme takma adını koruyun. Doğrudan `mix tuist.compile` görev keşfi, önbellekleme onları inceleyemeden önce bağımlılıkları derleyebilir.
- Seçilen, desteklenen bağımlılıklar için zaten güncel ve geçerli çıktılar, `up_to_date` nedeniyle yerel isabet olarak sayılır. Bunlar geriye dönük olarak yayınlanmaz ve herhangi bir yapıt anahtarı, aktarılan bayt, geri yükleme gecikmesi veya tahmini tasarruf edilen süre taşımaz. Bir anlık görüntü geri yüklemesini test etmek için, önbelleği doldurduktan sonra yalnızca desteklenen bir bağımlılığın derlemesini `mix deps.clean NAME --build` ile temizleyin, ardından tekrar derleyin.
- Mevcut çıktılar yayınlanmadığından, çalıştırmalar arasında `_build` öğesini koruyan bir CI işi yalnızca yeniden derlediği bağımlılıkları yükler. Diğer makinelerin her şey için isabet almasını sağlamak için, kullandıkları her `MIX_ENV` için yazma erişimiyle boş bir `_build` üzerinden derleme yapın.
- Her bağımlılığın sonucunu (`local_hit`, `remote_hit`, `miss` veya nedeni ile birlikte `bypass`) ve yapıt anahtarını yazdırmak için `TUIST_DEBUG=1` ayarlayın. Bu, derleme raporu gönderilemediğinde bile çalışır; örneğin salt okunur bir önbellek belirteci ile. Farklı bir girişi bulmak için makineler arasındaki anahtarları karşılaştırın.
- `MIX_ENV`, `MIX_TARGET`, derleyici ayarlarını ve bildirilen girişleri eşleştirin. Taşınabilir yeniden kullanım etkinleştirilmedikçe yol değişiklikleri de anahtarları değiştirir.
- Desteklenmeyen bağımlılıklar isabet eksikliği olarak değil, **Önbelleğe alınmamış** olarak görünür. İsabet oranından hariç tutulurlar. Ne aramalar ne de güncel yerel isabetler içeren bir derlemenin oranı kullanılamaz durumdadır, %0 değildir.
- Eksik kimlik bilgileri, kullanılamayan uç noktalar ve bozuk anlık görüntüler derlemeye geri döner. Derleyici hataları yine de derlemeyi başarısız kılar.
- CAS kayıtları derleme raporundan sonra gelebilir. Yeni alınan aktarımları görmek için yenileyin. Yerel isabetlerin ve eski derlemelerin uzak CAS çıktıları yoktur.

Sunucuların, `up_to_date` yerel isabetleri kaydetmek için derleme-raporu sözleşmesi `0.2` desteğine ihtiyacı vardır. Daha eski bir sunucu önbellek verilerini veya bir şema numaralandırma değerini açıkça reddederse, paket bu yeni yeniden kullanım gözlemleri olmadan raporu bir kez yeniden dener. Derleme ayrıntıları ve diğer önbellek sonuçları korunur; yeni yerel yeniden kullanım sunucu yükseltilene kadar kullanılamaz durumda kalır. Sunucuyu önce dağıtmak bu ek isteği önler. Sözleşme sürümü desteği müzakere etmez ve kimlik doğrulama hataları, taşıma hataları ve diğer doğrulama mesajları yeniden denenmez. Numaralandırma hataları daha eski sunucularda alanlarını tanımlamaz; saklanan geçersiz bir alan tek yeniden denemede yine de başarısız olur.

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

Bu işlevler, soğuk paralel derlemeler dahil olmak üzere Tuist'i diğer bağımlılıklardan önce derler ve yükler; Tuist ve bağımlılıkları zaten derlendiğinde veya komut `--no-compile` ile çalıştırıldığında bu işi atlar. Aynı işlevler Hex, Git ve yol kurulumlarıyla çalışır; betik yoluna gerek yoktur.

Takma adınız `deps.compile tuist_ex --include-children` ile başlıyorsa, her `mix compile` Tuist'in bağımlılıklarını yeniden derler ve tüm projenizi yeniden derleyebilir. Değiştirmek için `mix tuist.setup` komutunu tekrar çalıştırın.

## Nasıl çalışır

Elixir önbellekleme, ayrı bir Mix depolama hizmeti yerine Bazel tarafından kullanılan paylaşılan REAPI ActionCache/CAS hattını, kimlik doğrulamayı ve Kura imzalı analitikleri kullanır. Modellenen bir giriş anahtarı, tam bir derleme paketinin ham bayt SHA-256 özetini içeren bir ActionResult'a referans verir. Tuist, aşamalı kurulumdan önce dosyalarını, uygulama meta verilerini, bildirilen BEAM'leri ve SCM bildirimini doğrular. Bozuk girdiler başarılı derlemeden sonra onarılır.

OTP 28 ve sonraki sürümlerde, uzak oturumlar en az 1 KiB'lik ByteStream aktarımları için zstd sıkıştırmasını müzakere eder. Sıkıştırılamayan yüklemeler, daha eski OTP çalışma zamanları ve sıkıştırma olmayan sunucular kimlik taşıması kullanır. Özetler, yapıt sınırları ve bildirilen baytlar sıkıştırılmamış içeriği ifade eder. Kodu çözülmüş baytlar kurulmadan önce sınırlanır ve doğrulanır. Her bağımlılık tek bir CAS paketi olarak kalır ve küçük yapıtlar için dosya başına veya parça isteklerinden kaçınılır.

Uzak kimlik bilgileri/bağlantıları tembel olarak çözülür; boşta kalan derlemeler ve yerel isabetler (zaten güncel çıktılar dahil) uzak uç noktalarla iletişim kurmaz. Her çıkışta, derleyici hatası dahil, bir oturum kapatılır. İstemci RPC'lerinin 30 saniyelik bir zaman aşımı vardır. Mix, kilit kontrolleri, yerel bağımlılık derlemesi ve desteklenmeyen işlerden sorumlu olmaya devam eder.

Pano gecikmesi/bayt değerleri, yerel ve uzak kökeni korur ve ölçülen sıfır ile kullanılamayan değerleri ayırt eder. Uzak zamanlama, istemci CAS aktarımlarını ölçer; yerel zamanlama ise doğrulama ve kurulumu içerir; ikisi de derlemeyi kapsamaz. CAS Çıktıları, yerel kopyaları veya eylem-giriş anahtarlarını değil, başarılı Kura imzalı aktarımları kullanır. Verim, baytların ölçülen zamana bölünmesiyle hesaplanır; sıkıştırılmış boyutlar mevcut değildir. Tahmini kaçınılan derleme süresi, üreticinin orijinal derleme süresidir, uçtan uca ölçülen derleme tasarrufu değildir.

Bağımsız ve hazır bağımlılıklar, aynı HTTP/2 bağlantısı üzerinden en fazla dört eşzamanlı isteklik pencereler halinde alınır. Bu, kodu çözülmüş paket arabelleğini yapıt başına 64 MiB sınırına tabi olacak şekilde dört yapıtla sınırlar. Anahtar planlaması, Mix durumu ve kurulum seri kalır. Aşağı akış anahtarları yukarı akış yapıtlarını bekler; önceden getirilen baytlar yalnızca tam giriş anahtarı altında tüketilir ve uzak kurulumdan önce girdiler yeniden kontrol edilir. Zaten güncel çıktılar ve yerel anlık görüntüler spekülasyon amaçlı uzak isteklere neden olmaz. Seçili önbellek isabetlerinde derleme ve yüklemeler seri kalır; eşzamanlılık her derlemenin daha hızlı olacağının garantisi değildir.

## Her bağımlılık derlemeyi atlayabilir mi?

Uyumlu bir isabet, desteklenen bir bağımlılığın derlemesini atlayabilir ancak `cache: true` açık başarısızlık davranışı sergiler, sıfır derleme garantisi vermez. Eksik/atılmış girdiler, desteklenmeyen derleyiciler ve soğuk SDK başlatma yine de derleme yapabilir. Yüksek isabet oranı tek başına gerçek zamanlı hızlanma sağlamaz.

Bir kez derle/çok kez test et CI senaryoları için
<.localized_link href="/guides/features/test-sharding/elixir">Elixir test sharding</.localized_link>
her çalışanın bunu bağımlılık bazlı önbellek isabetlerinden yeniden oluşturmasını beklemek yerine tam hazırlanmış derlemeyi dağıtmak amacıyla şunu kullanın: Tam bir derlemeyi, özellikle yerel kütüphaneler içerenleri yeniden kullanmak hâlâ uyumlu bir platform, araç zinciri ve yapılandırma gerektirir. Keyfi özel derlemeler, harici girdilerini, çıktılarını ve gerekli yan etkilerini modellemeden derleme adımlarını güvenle atlayamaz.
