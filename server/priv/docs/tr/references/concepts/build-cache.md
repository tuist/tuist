---
{
  "title": "Derleme önbelleği nedir? Yerel ve uzak derleme önbellekleri açıklaması",
  "titleTemplate": ":title · Tuist",
  "description": "Bir derleme önbelleği, önceki derlemelerin çıktılarını yeniden kullanır. Xcode, Gradle ve Bazel'de yerel ve uzak derleme önbelleklerinin nasıl çalıştığı, Xcode önbelleklerinin ne olduğu ve önbelleğe almanın ne zaman verimli olduğu."
}
---
# Derleme önbelleği nedir? {#what-is-a-build-cache}

Bir derleme önbelleği, derlenmiş nesne dosyaları, modüller, kütüphaneler veya test sonuçları gibi ayrı derleme adımlarının çıktılarını; bunları üretmek için kullanılan her şeyden (kaynak dosyalar, derleyici bayrakları, bağımlılıklar, ortam ve araç zinciri sürümü) hesaplanan bir anahtar altında saklar. Daha sonraki bir derleme, girdileri aynı anahtarı üreten bir adıma ihtiyaç duyduğunda, derleme sistemi adımı tekrar çalıştırmak yerine saklanan çıktıyı kullanır. Bir **yerel derleme önbelleği** tek bir makinede bulunur ve o makinenin sonraki derlemelerini hızlandırır. Bir **uzak derleme önbelleği**, birçok makinenin okuma ve yazma yaptığı paylaşılan bir sunucudur; böylece bir CI işi, bir ekip arkadaşı veya bir kodlama ajanı başkasının zaten derlediği çıktıları yeniden kullanabilir.

## Derleme önbelleği, artımlı derleme ve CI önbelleği {#build-cache-incremental-build-and-ci-cache}

"Önbellek" olarak adlandırılan üç kavram vardır ve bunlar farklı şekilde davranır:

- **Artımlı derlemeler**, kendi derleme dizininizde zaten bulunan çıktıları yeniden kullanır ve yalnızca o dizindeki son derlemeden bu yana değişenleri tekrar derler. Genellikle dosya zaman damgalarına veya derleme ürünleriyle birlikte tutulan bir bağımlılık grafiğine güvenirler. Dal değiştirmek, checkout konumunu taşımak veya yeni bir makineden başlamak bu durumu kaybettirir.
- **Bir derleme önbelleği**, çıktıları girdilerinin içeriğine göre arar, aynı dizinde en son neyin derlendiğine göre değil. Bu, girdiler eşleştiği sürece çıktıların dallar, checkout'lar ve makineler arasında yeniden kullanılabilmesini sağlar.
- **CI dizin önbelleğe alma** (örneğin GitHub Actions'da `actions/cache`), bir işin sonunda bir dizini kaydeder ve bir sonraki işin başında, kilitleme dosyası hash'i gibi seçtiğiniz bir anahtar altında geri yükler. Bu bir dosya transferidir, derleme önbelleği değildir: derleme sistemi hala neyin yeniden derleneceğine karar verir ve geri yüklenen dizin kısmen veya tamamen eski olabilir.

İndirilen paketler veya Gradle ya da Swift paket önbelleği gibi bağımlılık önbellekleri ise farklıdır: bunlar derlemeyi değil, ağ üzerinden indirme işlemini kaydeder.

## Derleme önbelleği nasıl çalışır? {#how-a-build-cache-works}

Önbelleğe almayı destekleyen derleme sistemleri, derlemeyi adımlara böler (Bazel bunlara eylem, Gradle ise görev der) ve her biri için aynı işlemi yapar:

1. **Bir önbellek anahtarı hesapla.** Derleme sistemi, çıktıyı etkileyebilecek her girdiyi hash'ler: girdi dosyalarının içerikleri, komut satırı veya görev yapılandırması, ilgili ortam değişkenleri ve araç zinciri.
2. **Anahtarı ara.** Önce yerel önbelleği kontrol eder ve yapılandırılmışsa uzak önbelleği de kontrol eder.
3. **Eşleşme veya kaçırma.** Eşleşme durumunda, saklanan çıktıları indirir veya kopyalar ve adımı atlar. Kaçırma durumunda, adımı çalıştırır ve izin veriliyorsa çıktıları o anahtar altında yükler.

Çoğu önbellek, çıktıları **içerik adreslenebilir depolama** (CAS) içinde saklar; burada her blob kendi içeriğinin hash'i altında saklanır ve ayrıca önbellek anahtarlarından ürettikleri çıktılara ayrı bir indeks bulunur. Aynı dosyalar yalnızca bir kez saklanır ve istemci indirdiği veriyi doğrulayabilir.

Modelin katı bir gereksinimi vardır: anahtar, çıktıyı değiştiren her girdiyi içermelidir. Eğer bir adım, derleme sisteminin bilmediği bir girdiyi okursa (bildirilmemiş bir dosya, bir ortam değişkeni, geçerli saat veya makineye yüklü bir araç gibi), önbellek mevcut girdilerle eşleşmeyen bir çıktı döndürebilir. Derleme sistemleri, yalnızca bildirilen girdilere bağlı olan adımlara **hermetik** der. Tersine durum daha yaygın ve daha az tehlikelidir: mutlak yol veya zaman damgası gibi ilgisiz bir şey içeren bir anahtar, her makinede farklı bir anahtar üretir, bu nedenle önbellek asla eşleşmez.

## Derleme önbelleklerinin derleme sistemine göre çalışma şekli {#how-it-works-per-build-system}

### Gradle derleme önbelleği {#gradle}

[Gradle derleme önbelleği](https://docs.gradle.org/current/userguide/build_cache.html), Java ve Kotlin derleme ile test yürütme gibi önbelleklenebilir görevlerin çıktılarını; görevin türü, uygulaması, girdi özellikleri ve normalize edilmiş girdi dosyalarına göre anahtarlayarak saklar. Varsayılan olarak kapalıdır. `gradle.properties` içinde `org.gradle.caching=true` ile veya tek bir derleme için `--build-cache` ile etkinleştirin.

- **Yerel.** Yerleşik yerel önbellek, Gradle kullanıcı ev dizinindeki bir klasördür (varsayılan olarak `~/.gradle`). Derleme önbelleği açık olduğunda etkinleşir ve Gradle, yakın zamanda kullanılmayan girdileri periyodik olarak kaldırır.
- **Uzak.** Uzak önbellek, örneğin `HttpBuildCache` ile `settings.gradle(.kts)` içinde yapılandırılır. Gradle, yerel bir kaçırma durumunda çıktıları uzak önbellekten indirir ve bir sonraki sefer için yerel olarak saklar. Uzak önbellek varsayılan olarak yüklemeleri kabul etmez; yaygın bir kurulum, CI'nın push yapmasına (`isPush = true` CI'da çalışırken) ve geliştirici makinelerinin yalnızca okumasına izin verir.

Gradle, önbellekten geri yüklenen bir görevi `FROM-CACHE` olarak raporlar; bu, `UP-TO-DATE` değerinden farklıdır: up-to-date, Gradle'ın artımlı derlemesinin görevin çıktılarını önbelleğe danışmadan zaten yerinde bulduğu anlamına gelir. Yapılandırma önbelleği, görev çıktılarını değil, yapılandırma aşamasının sonucunu önbelleğe alan üçüncü, ayrı bir özelliktir.

### Bazel uzak önbelleği {#bazel}

Bazel her eylemi önbelleğe alır. Eylem önbelleği, bir eylemin anahtarını (komut satırı, ortam ve girdi dosyalarının özeti) eylemin çıktılarıyla eşler ve çıktılar kendileri içerik adreslenebilir bir depoda bulunur.

- **Yerel.** Bazel, bir eylem önbelleğini ve derleme çıktılarını çıktı tabanında tutar; bu size tek bir çalışma alanında hızlı artımlı derlemeler sağlar. `--disk_cache=<path>`, aynı makinedeki çalışma alanları ve dallar arasında paylaşılan bir disk önbelleği ekler.
- **Uzak.** `--remote_cache=grpcs://…` (veya `https://…`), Bazel'i [Uzak Yürütme API'sini](https://github.com/bazelbuild/remote-apis) veya düz bir HTTP önbelleğini uygulayan bir uzak önbelleğe yönlendirir. `--remote_upload_local_results=false`, bir makineyi salt okunur yapar; birçok ekip geliştirici makinelerinin paylaşılan önbelleğe yazmasını bu şekilde engeller. `--remote_download_minimal` veya `--remote_download_toplevel` ("baytlar olmadan derleme"), yerel derlemenin asla ihtiyaç duymadığı ara çıktıların indirilmesini önler.

Bazel ayrıca test sonuçlarını da önbelleğe alır: girdileri değişmemiş bir test, çalıştırılmadan `(cached) PASSED` olarak raporlanır. Uzak önbellek, eylemlerin de uzak makinelerde çalıştığı uzak yürütme ile aynı değildir; bir önbellek yalnızca sonuçları saklar.

### Xcode önbellekleri nelerdir? {#xcode}

Xcode, karıştırılması kolay birkaç önbellek ve dizin kullanır. Derleme sürelerini etkileyenler şunlardır:

- **DerivedData** (`~/Library/Developer/Xcode/DerivedData/<Project>-<hash>/`), her projenin derleme ürünlerini, ara dosyalarını, indeksini, günlüklerini ve çözümlenmiş Swift paketlerini tutar. Artımlı derlemelerin yeniden kullandığı durumu temsil eder. Silmek güvenlidir ancak o projenin sonraki derlemesi tam bir yeniden derleme olur ve indeksleme ile paket çözümleme işlemleri tekrar çalışır.
- **Clang modül önbelleği** (`~/Library/Developer/Xcode/DerivedData/ModuleCache.noindex/`), içe aktarılan C ve Objective-C modülleri ile SDK çerçeveleri için önceden derlenmiş Clang modüllerini (`.pcm` dosyaları) tutar ve projeler arasında paylaşılır. Açıkça derlenen modüller etkinleştirildiğinde, Xcode bunun yerine modülleri normal derleme görevleri olarak derler ve her projenin ara dosyalarıyla birlikte saklar. Silmek güvenlidir; modüller gerektiğinde yeniden derlenir.
- **Derleme önbelleği** (Xcode 26 ve sonrası, varsayılan olarak DerivedData içindeki `CompilationCache.noindex`, `COMPILATION_CACHE_CAS_PATH` ile yapılandırılabilir), `COMPILATION_CACHE_ENABLE_CACHING = YES` olduğunda Swift, C ve Objective-C için içerik adresli derleme çıktılarını tutar. Silmek güvenlidir; yeniden oynatılabilecek derlemeler tekrar çalışır.
- **Swift Package Manager önbelleği** (`~/Library/Caches/org.swift.swiftpm/`), projeler arasında paylaşılan indirilen paket depolarını ve bildirim dosyalarını tutar. Silmek güvenlidir; paketler tekrar alınır.

`~/Library/Developer` altındaki diğer büyük dizinler derleme önbelleği değildir ancak disk alanı temizlenirken sıkça karşımıza çıkar: `Xcode/Archives`, arşivlenmiş uygulama derlemelerini ve hata ayıklama sembollerini tutar (çöküşleri sembolize etmek için ihtiyaç duyabileceğinizleri saklayın), `Xcode/iOS DeviceSupport`, bağlı cihazların işletim sistemi sürümleri için sembolleri tutar ve `CoreSimulator/Devices`, simülatörleri ve verilerini tutar (`xcrun simctl delete unavailable`, artık yüklü olmayan çalışma zamanlarına ait simülatörleri kaldırır).

DerivedData, Xcode'un artımlı derleme durumudur, içerik adresli bir önbellek değildir: diskteki proje konumuna ve dosya zaman damgalarına bağlıdır. DerivedData'yı farklı bir yoldan bir CI önbelleğinden geri yüklemek veya yeni bir checkout işleminden sonra her dosyanın değiştirilme zamanının değişmesi, genellikle yine de tam bir yeniden derlemeye yol açar.

Xcode 26'da tanıtılan **derleme önbelleği**, bu sayfanın bağlamında Xcode'un derleme önbelleğidir. Derleme sonuçlarını girdilerinin içeriğine göre saklar ve bir isabette bunları yeniden oynatır, böylece çıktılar dal değiştirmelerden ve temizlenen derleme ürünlerinden etkilenmez. Sadece derlemeyi önbelleğe alır, her derleme adımını değil: bağlama, kaynak işleme ve betik aşamaları yine de çalışır. Varsayılan olarak depo tek bir makineye özeldir ve DerivedData içinde bulunur, bu nedenle DerivedData'nın tamamını silmek onu da atar; yalnızca bir projenin derleme ürünlerini silmek onu korur. Xcode ayrıca derleme önbelleğini bir eklenti aracılığıyla uzak bir önbellek hizmetine bağlayabilir (`COMPILATION_CACHE_ENABLE_PLUGIN` ve `COMPILATION_CACHE_REMOTE_SERVICE_PATH`), bu da onu paylaşılan bir uzak önbelleğe dönüştürür.

Derleme önbelleğinden önce, Xcode projeleri makineler arasında işleri çoğunlukla tüm modülleri **ikili önbelleğe alarak** yeniden kullanırdı: bağımlılıkları önceden derlenmiş çerçeveler veya XCFramework'ler olarak derlemek ve kaynakları derlemek yerine bunları bağlamak. Bu, bir derlemeden ziyade bir modül granülerliğinde çalışır ve projenin nasıl derlendiğini değiştirir.

## Gecikme, blob boyutu ve blob sayısı {#latency-blob-size-and-blob-count}

Uzak önbellek isabeti bedava değildir. Bir çıktıyı getirmek, öncekini beklemek zorunda kalan her istek için sabit bir gecikmeye ve baytlarını taşımak için geçen süreye mal olur:

**zaman ≈ R × L + S / B**

burada *R*, örtüşemeyen gidiş-dönüş sayısıdır, *L*, önbelleğe gidiş-dönüş gecikmesidir, *S*, aktarılan bayt sayısıdır ve *B*, bant genişliğidir. Hangi terimin baskın olduğu, derleme sisteminin işini bloblara nasıl böldüğüne bağlıdır:

- **Az sayıda büyük blob, bant genişliği sınırlıdır.** Gradle görevinin paketlenmiş çıktıları veya ikili modül önbelleğindeki önceden derlenmiş bir çerçeve gibi kaba çıktıları saklayan önbellekler, her biri megabaytlarca veri taşıyan daha az istek yapar. 200 MB'lık bir çıktı kümesi, 100 Mbit/s'de yaklaşık 16 saniye ve 1 Gbit/s'de 2 saniyeden az sürer, oysa birkaç milisaniyelik ek gecikme neredeyse hiç fark etmez.
- **Çok sayıda küçük blob, gecikme sınırlıdır.** Bazel'in eylem başına önbelleği ve Xcode'un derleme önbelleği gibi ince taneli önbellekler, birkaç kilobaytlık bloblar için binlerce istek yapar, bunların çoğu yalnızca bir anahtarın var olup olmadığını sormak içindir. 2.000 arama, aynı anda 8'i havada ve 40 ms gecikme ile, blobların ne kadar küçük olduğuna bakılmaksızın bir derleme yalnızca gidiş-dönüşlerde yaklaşık 10 saniye bekler. 2 ms gecikme ile aynı aramalar yaklaşık yarım saniye sürer. Daha fazla bant genişliği burada yardımcı olmaz; daha yakın bir önbellek yardımcı olur.
- **Iskalamalar da bir gidiş-dönüşe mal olur.** Iskalayan her arama, herhangi bir iş tasarrufu sağlamadan gecikme ekler. Düşük isabet oranına sahip uzak bir önbellek, derlemeyi hiç uzak önbellek olmamasından daha yavaş hale getirebilir.
- **Hacim her ikisini de katlar.** Blob sayısı projenin yapısıyla birlikte artar: çok sayıda küçük modül veya hedeften oluşan bir grafik, birkaç büyük olandan daha fazla ve daha küçük çıktılar üretir. Bir projeyi bölmek paralellliği ve geçersiz kılmayı iyileştirir, ancak derlemeyi önbellek gecikmesine karşı daha hassas hale getirir.

Bir isabet, yalnızca çıktıyı getirmek yeniden hesaplamaktan daha hızlı olduğunda değerlidir ve bu karşılaştırma mesafeye göre değişir. Yerel olarak 50 ms süren bir derleme, aynı ağdaki bir önbellekten iyi bir isabettir ancak başka bir kıtadaki bir önbellekten kötü bir isabettir. Bu nedenle uzak önbellekler için kaldıraçlar çoğunlukla ham bant genişliğinden ziyade gecikme ve istek sayısı ile ilgilidir:

- **Önbelleği derlemelerin çalıştığı yere yakın tutun**, CI çalışanlarıyla aynı bölgede veya ağda ve geliştiricilere mümkün olduğunca yakın.
- **İstekleri örtüştürün.** Bazel'in Uzak Yürütme API'si, varlık kontrollerini (`FindMissingBlobs`) ve küçük okumaları toplu hale getirir ve `--remote_max_connections` eşzamanlılığı sınırlar. Xcode'un `COMPILATION_CACHE_ENABLE_DETACHED_KEY_QUERIES`, derleme önbelleği aramalarını yürütme kanalları üzerinde değil, derlemenin geri kalanıyla birlikte çalıştırır. HTTP/2, birçok isteği tek bir bağlantı üzerinden çoğullar.
- **Daha az indirin.** Bazel'in `--remote_download_minimal`, ara çıktıları atlar ve Bazel'in `--disk_cache` veya Gradle'ın yerel derleme önbelleği gibi yerel bir önbellek katmanı, ağ isteği olmadan tekrarlanan isabetlere hizmet eder.
- **Büyük blobları sıkıştırın.** Bazel'in `--remote_cache_compression`, önbellek desteklediğinde zstd kullanır; bu, bant genişliği sınırlı aktarımlara yardımcı olur ancak gecikme sınırlı olanlara pek katkıda bulunmaz.

## Yaygın tuzaklar {#common-pitfalls}

- **Bildirilmemiş girdiler.** Bir adım, anahtarının parçası olmayan bir dosyayı, ortam değişkenini veya aracı okur. Önbellek bu durumda farklı girdilerden oluşturulmuş çıktılar döndürebilir. Gradle'da özel görevlerin her girdisini bildirin; Bazel'de eylemleri yalıtılmış tutun ve ana makine `PATH` değerinin sızmasını önlemek için `--incompatible_strict_action_env` seçeneğini göz önünde bulundurun.
- **Makineye özgü anahtarlar.** Girdilere veya çıktılara gömülü mutlak yollar, kullanıcı adları ve derleme zaman damgaları, anahtarların makineler arasında farklılaşmasına neden olur, bu da uzak önbelleğin hiç isabet etmemesine yol açar. Gradle'ın yol duyarlılığı, Bazel'in göreli yürütme yolları ve Xcode'daki Clang ile Swift önek eşleme ayarları bu farkları ortadan kaldırmak için vardır.
- **Grafın köküne yakın kararsız girdiler.** Her şeyin bağımlı olduğu bir modüle derleme numarası, commit hash'i veya tarih basmak, her derlemede onun üzerindeki her şeyi geçersiz kılar. Kararsız değerleri mümkün olduğunca geç enjekte edin, ideal olarak yalnızca sürüm derlemelerine.
- **Araç zinciri uyumsuzlukları.** Farklı derleyici, JDK veya Xcode sürümleri farklı anahtarlar üretir. Bu doğru bir davranıştır ancak karışık sürümlere sahip bir filo, önbelleği etkili bir şekilde böler.
- **Zehirlenmiş veya güvenilmeyen yazmalar.** Commit edilmemiş değişikliklere sahip bir geliştirici makinesi veya yalıtılmamış bir kurulum, başkalarının yeniden kullanacağı çıktılar yükleyebilir. Pek çok ekip, yalnızca güvenilir dallardaki CI'nin uzak önbelleğe yazmasına izin verir ve diğer tüm makineleri salt okunur yapar. Güvenilmeyen pull request'lerin derlemeleri, güvenilir derlemelerin okuduğu bir önbelleğe yazmamalıdır.
- **Aktarım maliyetini görmezden gelmek.** Çalışması 50 milisaniye süren bir adım, uzak bir önbellekten getirildiğinde daha uzun sürebilir. Bkz. [Gecikme, blob boyutu ve blob sayısı](#latency-blob-size-and-blob-count).
- **Gizli test çalıştırmaları.** Testler deterministik olduğunda test sonuçlarını önbelleğe almak doğrudur, ancak bu aynı zamanda bir kez geçen kararsız bir testin, çalıştırılmadan geçmeye devam ettiği anlamına gelir. Bkz. <.localized_link href="/references/concepts/flaky-test">Kararsız test nedir?</.localized_link>.

## Derleme önbelleği nasıl ölçülür {#how-to-measure-a-build-cache}

Bir önbellek, yalnızca isabet oranına değil, uçtan uca ne kadar tasarruf sağladığına göre değerlidir:

- **İşle ağırlıklandırılmış isabet oranı.** Adım başına isabetleri ve ıskalamaları sayın, ancak bunları her adımın çalışma süresine göre ağırlıklandırın. Ucuz adımlarda %95'lik bir isabet oranı, en yavaş derlemelerde %50'lik bir isabet oranından daha az tasarruf sağlayabilir.
- **Soğuk, ılık ve tipik derlemeler.** Boş önbellekli bir derlemeyi, tamamen ısınmış önbellekli bir derlemeyle ve insanların gerçekten çalıştırdığı derlemelerle (örneğin küçük bir değişiklikten sonra bir pull request'teki CI) karşılaştırın. Önemli olan sayı sonuncusudur.
- **Önbelliğin kendisinde harcanan zaman.** İstek sayısını, gecikmeyi, bayt sayısını ve indirme ile yükleme için harcanan zamanı ölçün. Bu sürenin çoğu birçok küçük isteği beklemekle geçiyorsa, daha fazla bant genişliğinden ziyade daha yakın bir önbellek daha fazla yardımcı olur; birkaç büyük blob taşınıyorsa, bant genişliği ve sıkıştırma daha önemlidir.
- **Neden ıskalamalar olur.** İki makinede aynı adım için önbellek anahtarlarını karşılaştırın. Gradle, `-Dorg.gradle.caching.debug=true` ile her anahtarın arkasındaki girdileri yazdırabilir, Bazel iki derleme arasında fark alabileceğiniz yürütme günlüklerini (`--execution_log_compact_file`) yazabilir ve Xcode, `COMPILATION_CACHE_ENABLE_DIAGNOSTIC_REMARKS = YES` olduğunda derleme günlüğünde derleme önbelleği isabetlerini ve ıskalamalarını raporlar.

## Ne zaman değmez {#when-it-isnt-worth-it}

Bir derleme önbelleği altyapı, bir güvenlik sınırı ve yeni bir hata sınıfı ekler. Her zaman doğru araç değildir:

- **Küçük veya hızlı derlemeler.** Temiz bir derleme bir dakika sürüyorsa, uzak önbellek çok az tasarruf sağlar ve ağ gidiş-dönüşleri onu daha yavaş hale getirebilir.
- **Tasarım gereği ıskalayan derlemeler.** Çoğu derleme grafın köküne yakın bir girdiyi değiştiriyorsa, bu düzeltilene kadar önbellek yardımcı olamaz. Önce geçersiz kılmayı düzeltin; önbellek yalnızca girdileri eşleşen işleri atlar.
- **Kalıcı derleme makineleri.** Aynı dalda işler arasında derleme dizinini koruyan bir CI makinesi zaten artımlı derlemeler alır. Paylaşılan bir önbellek, makineler geçici olduğunda, çok sayıda dal olduğunda veya geliştiriciler ile CI'nin birbirlerinin işlerini yeniden kullanması gerektiğinde yardımcı olur.
- **Henüz düzeltemediğiniz yalıtılmamış derlemeler.** Zaman zaman yanlış çıktılar döndüren bir önbellek, zaman tasarrufundan daha fazla güven maliyetine sahiptir. Önbelleğe aldığınız adımları önce tekrarlanabilir hale getirin veya sorunlu olanları önbelleksiz bırakın (örneğin Bazel'in `no-remote-cache` etiketi ile).
- **Yavaş veya uzak ağlar.** Önbellek derlemelerin çalıştığı yerden uzaktaysa, bunu herkese yaymadan önce aktarım süresini ölçün.

## Tuist ile derleme önbellekleme {#build-caching-with-tuist}

[Tuist](https://tuist.dev), her derleme sisteminin kendi önbelleğine takılan bir uzak önbellek sağlar, böylece geliştirici makineleri, CI ve kodlama ajanları birbirlerinin çıktılarını yeniden kullanır ve etkisini ölçebilmeniz için isabetleri, ıskalamaları ve aktarım sürelerini kaydeder:

- <.localized_link href="/guides/features/cache/xcode-cache">Xcode önbelleği</.localized_link>, Xcode 26 veya sonraki sürümlerdeki herhangi bir Xcode projesi için Xcode'un derleme önbelleğini paylaşılan bir uzak önbelleğe bağlar.
- <.localized_link href="/guides/features/cache/module-cache">Modül önbelleği</.localized_link>, Tuist ile oluşturulan projelerde tüm modülleri önceden derlenmiş ikili dosyalarla değiştirir.
- <.localized_link href="/guides/features/cache/gradle-cache">Gradle önbelleği</.localized_link> ve <.localized_link href="/guides/features/cache/bazel-cache">Bazel önbelleği</.localized_link>, Gradle için uzak derleme önbelleği ve Bazel için Uzak Yürütme API önbelleği olarak hizmet eder.
- <.localized_link href="/guides/features/cache">Önbellek</.localized_link>, Elixir ve Once dahil olmak üzere desteklenen her derleme sistemini listeler.
- [Yavaş derlemeler](https://tuist.dev/solutions/slow-builds), bir önbellek seçmeden önce kaldırılmaya değer işi bulmak için pratik bir kılavuzdur.
- [Derleme sistemlerinin fiziği](https://tuist.dev/blog/2026/08/25/the-physics-of-build-systems) ve [Kura](https://tuist.dev/blog/2026/09/14/kura), Tuist'in önbelleğinden alınan ölçümlerle, modül önbelleği, Xcode'un derleme önbelleği, Bazel ve Gradle arasında yapıt boyutu ve istek hacminin nasıl farklılaştığını açıklar.
