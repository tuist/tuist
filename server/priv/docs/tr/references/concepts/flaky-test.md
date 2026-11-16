---
{
  "title": "Kararsız test nedir? Nedenleri, tespiti ve çözümleri",
  "titleTemplate": ":title · Tuist",
  "description": "Kararsız bir test aynı kodda bazen geçer, bazen başarısız olur. Yaygın nedenleri, Xcode, Gradle ve Bazel'de kararsız test tespitinin nasıl çalıştığını ve kararsızlığın nasıl ölçüleceğini öğrenin."
}
---
# Kararsız test nedir? {#what-is-a-flaky-test}

Kararsız test, aynı kod üzerinde çalıştırıldığında hem geçen hem de başarısız olan otomatik bir testtir; test edilen kodda veya testin kendisinde hiçbir değişiklik olmamıştır. Sonucu, testin kontrol etmediği bir şeye bağlıdır: zamanlama, testlerin çalışma sırası, başka bir testten kalan durum, çalıştığı makine veya ağ üzerinden çağırdığı bir hizmet. Bu nedenle kararsız bir başarısızlık, test edilen değişiklik hakkında güvenilir bir bilgi vermez; bu da kararsız testleri maliyetli kılar: herkes ona güvenmeden önce her kırmızı sonuç incelenmeli veya yeniden denenmelidir.

Kararsızlık her ölçekte yaygındır. Google, tüm test çalışmalarının yaklaşık %1,5'inin kararsız bir sonuç ürettiğini ve testlerinin neredeyse %16'sının belirli bir düzeyde kararsızlık gösterdiğini bildirmiştir ([Google'da Kararsız Testler ve Bunları Nasıl Azaltıyoruz](https://testing.googleblog.com/2016/05/flaky-tests-at-google-and-how-we.html), 2016).

## Kararsız testler nasıl ortaya çıkar {#how-flaky-tests-show-up}

Bir testin kararsız olduğu, aynı girdi için her iki sonucu da ürettikten sonra anlaşılır. Pratikte bu kanıt üç kaynaktan birinden gelir:

- **Bir çalışma içindeki yeniden denemeler.** Bir test başarısız olur, çalıştırıcı onu yeniden dener ve yeniden deneme geçer. Bu en ucuz sinyaldir ve çoğu test çalıştırıcısı bunu üretebilir.
- **Aynı commit için farklı sonuç veren çalışmalar.** Aynı commit ve yapılandırmanın iki CI çalışması, bir test için farklı sonuçlar bildirir; örneğin pull request üzerindeki bir çalışma ve biri yeniden denemeye tıkladıktan sonraki yeniden çalışma.
- **Kasıtlı tekrar.** Bir test, hiç başarısız olup olmadığını görmek amacıyla art arda birçok kez çalıştırılır. Ekipler, şüpheli bir kararsızlığı doğrulamak veya yeni bir testi birleştirmeden önce kararlı olduğunu kontrol etmek için bunu kullanır.

Sonuçlar yalnızca önemli olan her şey aynı olduğunda kararsızlığa kanıt sayılır: commit, derleme yapılandırması, cihaz veya simülatör, işletim sistemi sürümü ve araç zinciri. iOS 17'de başarısız olup iOS 18'de geçen bir test, bunlardan birinde gerçek, deterministik bir hata içerebilir.

## Derleme sistemine göre kararsız test algılama nasıl çalışır {#how-it-works-per-build-system}

Her araç zinciri testleri yeniden deneyebilir ve tekrarlayabilir, ancak sonuçları farklı şekilde kaydeder ve raporlar.

### Xcode {#xcode}

`xcodebuild` ve test planları test tekrarını destekler. `-retry-tests-on-failure` başarısız bir testi yeniden çalıştırır, `-test-iterations <n>` kaç denemeye izin verileceğini belirler ve `-run-tests-until-failure` bir test başarısız olana kadar tekrarlar; bu, şüpheli bir kararsızlığı yeniden üretmek için yararlıdır. Test planları, test tekrar modu olarak aynı seçenekleri sunar ve ayrıca testleri rastgele sırada çalıştırma seçeneği ekler; bu, gizli sıra bağımlılıklarını ortaya çıkarır.

Her deneme `.xcresult` paketinde saklanır, bu nedenle başarısız olup yeniden denemede geçen bir test orada görünür. Xcode çalışmalar arasında geçmiş tutmaz, bu yüzden aynı çalışma içinde hiç yeniden denenmeyen kararsızlıkları algılamak, aynı commit'in farklı çalışmalarından gelen sonuç paketlerini karşılaştırmayı gerektirir.

### Gradle {#gradle}

Gradle'ın `Test` görevi başarısız testleri kendi başına yeniden denemez. [Test Yeniden Deneme eklentisi](https://github.com/gradle/test-retry-gradle-plugin) (`org.gradle.test-retry`), `Test` görevlerine `retry` bloğu ekler; `maxRetries` ve `failOnPassedAfterRetry` gibi seçenekler sunar. Başarısız olup sonra geçen bir test, test raporlarında ve JUnit XML'inde her iki denemeyle birlikte görünür. Test çerçeveleri kendi tekrar araçlarını ekler; örneğin JUnit 5'in `@RepeatedTest` özelliği.

Gradle'ın derleme önbelleği kararsızlığı gizleyebilir: girdileri değişmemiş, önbelleğe alınabilir bir `Test` görevi çalıştırmak yerine önbellekten geri yüklenir, bu nedenle bir kez geçen bir test çalıştırılmadan geçmeye devam eder. Kararsızlığı ölçerken, testleri `--rerun-tasks` ile çalışmaya zorlayın veya derleme önbelleği devre dışıyken `Test` görevini çalıştırın.

### Bazel {#bazel}

Bazel yerleşik destek sunar. Bir test hedefini `flaky = True` ile işaretlemek, Bazel'in bunu en fazla üç kez çalıştırmasını ve yalnızca tüm denemeler başarısız olursa başarısız olarak raporlamasını sağlar. `--flaky_test_attempts` bayrağı, hedefi değiştirmeden deneme sayısını belirler ve bir deneme başarısız olduktan sonra başarılı olursa hedefin sonucu `FLAKY` olarak bildirilir. Kararsızlığı bilinçli olarak ölçmek için `--runs_per_test=<n>` bir testi birçok kez çalıştırır ve en az bir çalışma başarılı olup biri başarısız olduğunda bir parçayı `FLAKY` olarak raporlayan `--runs_per_test_detects_flakes` kullanılır.

Bazel, test sonuçlarını derleme çıktıları gibi önbelleğe alır. Aynı girdilerle geçen bir test, hem yerel hem de uzak önbellekten, tekrar çalıştırılmadan `(cached) PASSED` olarak raporlanır. Taze yürütmelere ihtiyacınız olduğunda `--cache_test_results=no` (veya `--nocache_test_results`) kullanın. Bazel belgeleri ayrıca `flaky = True` kullanımına güvenilmesini önermez, çünkü yeniden denediği başarısızlıkları kalıcı olarak gizler.

### Diğer test çalıştırıcıları {#other-test-runners}

Aynı desen neredeyse her yerde vardır: pytest'te `pytest-rerunfailures` eklentisi, Jest'te `jest.retryTimes()` ve Elixir'in ExUnit'inde `mix test --repeat-until-failure` bulunur; kullanılan rastgele tohumu yazdırır, böylece sıraya bağlı bir başarısızlık `--seed` ile yeniden oynatılabilir.

## Kararsız testlerin yaygın nedenleri {#common-causes}

Açık kaynak projelerde kararsız testler üzerine yapılan ampirik bir çalışma ([Luo ve diğerleri, FSE 2014](https://doi.org/10.1145/2635868.2635920)) asenkron bekleme, eşzamanlılık ve test sırası bağımlılığını en yaygın kök nedenler olarak bulmuştur. Aşağıdaki liste bunları ve ekiplerin en sık karşılaştığı diğer nedenleri kapsar.

- **Asenkron beklemeler ve sabit uyumalar.** Test, işin bitmesi için `sleep(1)` gibi sabit bir süre veya kısa zaman aşımıyla bir beklenti kullanır ve iş bazen daha uzun sürer, özellikle yoğun bir CI makinesinde. Koşulun kendisini, geniş bir üst sınır ile bekleyin.
- **Eşzamanlılık.** İki iş parçacığı veya görev paylaşılan veri üzerinde yarışır ya da test, arka plan işlemi tamamlanmadan önce iddia yapar. Bu başarısızlıklar genellikle CPU sayısı ve yüküne bağlıdır, bu nedenle CI'da ortaya çıkar ama hızlı bir dizüstü bilgisayarda görünmez.
- **Test sırası bağımlılığı ve paylaşılan durum.** Bir test, başka bir testin oluşturduğu veya temizlemeyi unuttuğu duruma güvenir: bir singleton, bir veritabanı satırı, diskteki bir dosya, `UserDefaults`, bir ortam değişkeni veya taklit edilmiş bir global. Testleri rastgele sırada veya paralel çalıştırmak bunu ortaya çıkarır.
- **Zaman ve tarihler.** Gerçek saati kullanan testler gece yarısında, ay sonunda, yaz/kış saati değişikliklerinde veya başka bir saat diliminde başarısız olur. Bunun yerine bir saat enjekte edin.
- **Tohumsuz rastgelelik ve sırasız koleksiyonlar.** Kaydedilmiş bir tohum olmadan rastgele veri veya bir hash map ya da kümenin yineleme sırasına bağlı iddialar.
- **Ağ ve harici hizmetler.** Gerçek API'lere, paket kayıt defterlerine veya paylaşılan staging ortamlarına yapılan çağrılar, bu hizmetler yavaş olduğunda veya kullanılamadığında başarısız olur. Sınırda bunları stublayın ve az sayıda açık entegrasyon testi tutun.
- **Kaynak baskısı ve ortam durumu.** Yavaş veya aşırı yüklü makineler, sıfırlanmamış bir simülatör veya emülatör, dolu bir disk veya başka bir işin zaten kullandığı bir port. Birçok ilgisiz test aynı anda başarısız olduğunda, önce testlerden şüphelenmek yerine ortamdan şüphelenin.
- **Kullanıcı arayüzü testleri.** Uçtan uca ve kullanıcı arayüzü testleri, yukarıdaki nedenlerin çoğunu animasyonlar, render zamanlaması ve sistem diyaloglarıyla birleştirir, bu nedenle birim testlerinden daha sık kararsız olurlar.

Bir değişiklikten sonra tutarlı bir şekilde başarısız olan bir test kararsız değildir; bu bir regresyondur. Kararsız etiketi, aynı kod üzerinde her iki sonucu da üreten testler için ayrılmalıdır.

## Düzeltme, yeniden deneme ve karantinaya alma {#fixing-retrying-and-quarantining}

Ekipler genellikle üç yanıtı birleştirir ve bunları ayrı tutmak yardımcı olur:

- Nedeni **düzeltin**. Testin değerini geri kazandıran tek yanıt budur. Kaydedilen denemeler, hata mesajları ve her başarısız çalışmanın koşulları, nedeni gösteren kanıtlardır.
- Boru hatlarının akmasını sağlamak için **yeniden deneyin**. Yeniden denemeler faydalı bir tespit sinyalidir, ancak genel yeniden denemeler sorunu gizler ve her başarısız çalışmaya makine zamanı ekler. Başarılı olan bir yeniden deneme, sessizce atılmak yerine yine de kararsız bir sonuç olarak kaydedilmelidir.
- Düzeltilirken birleşmeleri engellememesi için bilinen bir kararsız testi **karantinaya alın**. Karantinaya alınan bir test ya hataları yoksayılarak (sessize alınmış) çalışmaya devam eder, bu da kanıt üretmeye devam etmesini sağlar, ya da hiç çalışmaz (atlanmış), bu da kapsamını kaldırır. Karantina, bir sahibe ve bir çıkış koşuluna ihtiyaç duyar; aksi takdirde karantinaya alınan testler birikir ve kapsam sessizce daralır.

## Kararsızlık nasıl ölçülür {#how-to-measure-flakiness}

Kararsızlığı sadece boru hattı başına değil, test başına takip edin:

- **Kararsızlık oranı.** Bir testin çalışmaları arasında kararsız bir sonuç üretenlerin payı: bir başarısızlığın ardından gelen başarılı bir yeniden deneme veya aynı commit ve yapılandırmaya sahip başka bir çalışma ile çelişen bir sonuç.
- **Etki.** Bir testin kaç boru hattını, çekme isteğini veya birleştirme kuyruğu girişini engellediği veya yavaşlattığı ve yeniden denemelerinin ne kadar makine zamanı tükettiği. Her boru hattında çalışan düşük kararsızlık oranına sahip bir test, nadiren çalışan çok kararsız bir testten daha pahalı olabilir.
- **Trend.** Yeni kararsız testlerin, eskileri düzeltilenden daha hızlı tanıtılıp tanıtılmadığı. Yeni veya değiştirilen testleri birleştirmeden önce birkaç kez tekrarlamak, birçok kararsızlığı kaynağında yakalar.

Bir testin kararlı olduğunu doğrulamak, sezgilerin önerdiğinden daha fazla çalışma gerektirir. Bir test her çalışmada *p* olasılığıyla başarısız oluyorsa, *n* çalışmada en az bir başarısızlık görme şansı 1 − (1 − p)ⁿ'dir. Zamanın %1'inde başarısız olan bir test için, 10 çalışma onu sadece yaklaşık %10 oranında yakalar ve %95 güvenle yakalamak için yaklaşık 300 çalışma gerekir. Birkaç yeşil yeniden çalışma, bir düzeltmenin işe yaradığına dair zayıf bir kanıttır.

## Ne zaman değmez {#when-it-isnt-worth-it}

Her kararsız test bir araştırmayı hak etmez ve her ekip kararsız test araçlarına ihtiyaç duymaz:

- **Düşük değerli testler.** Kararsız bir test, diğer testlerin zaten sağladığı kapsamı tekrarlıyorsa, onu silmek doğru düzeltme olabilir. Kimsenin güvenmediği bir test zaten hiçbir kapsam sağlamaz.
- **Altyapı sorunları.** Başarısızlıklar tek bir makinede, çalıştırıcı imajında veya günün belirli bir saatinde kümeleniyorsa, ortamı düzeltmek testleri tek tek düzeltmekten daha ucuzdur.
- **Küçük, hızlı test paketleri.** Hızlı bir pakete ve bilinen tek bir kararsız teste sahip küçük bir ekip için, paylaşılan bir not ve bu hafta içinde bir düzeltme, bir izleme sisteminden daha iyidir. Özel tespit ve karantina, paketin büyüklüğü, katkıda bulunan sayısı veya boru hattı sayısı nedeniyle kimse hangi başarısızlıkların gürültü olduğunu hatırlayamadığında karşılığını verir.
- **Kritik yollar.** Ödemeleri, veri bütünlüğünü veya güvenliği koruyan bir test için karantina yanlış bir araçtır. Bu testler, rahatsız edici olsa bile düzeltilene kadar engellemelidir.

## Tuist ile kararsız test tespiti {#flaky-test-detection-with-tuist}

[Tuist](https://tuist.dev), Xcode, Gradle, Bazel, Elixir ve diğer desteklenen entegrasyonlardan gelen her test denemesini kaydeder, bir test aynı kod üzerinde hem yeniden denemeler sırasında hem de desteklenen entegrasyonlar için aynı commit'in CI çalışmaları sırasında başarısız olup geçtiğinde onu kararsız olarak işaretler ve ekiplerin düzeltme sürecinde bilinen kararsız testleri manuel olarak veya otomasyonlar aracılığıyla sessize almasına veya atlamasına olanak tanır. Destek ve gereksinimler araç zincirine göre farklılık gösterir:

- <.localized_link href="/guides/features/test-insights/flaky-tests">Kararsız testler</.localized_link>, tespit, karantina ve yeni testlerin stres testinin nasıl çalıştığını, araç zinciri başına bir kılavuzla açıklar.
- <.localized_link href="/guides/features/test-insights">Test İçgörüler</.localized_link>, öncelikle test sonuçlarının kaydedilmesini kapsar.
- [Testlerim kararsız](https://tuist.dev/solutions/flaky-tests), kararsız testleri bir ekip olarak teşhis etmek ve kontrol altına almak için pratik bir kılavuzdur.

İlgili referans: <.localized_link href="/references/concepts/build-cache">Yapı önbelleği nedir?</.localized_link>, önbelleğe alınmış test sonuçlarının kararsızlıkla nasıl etkileşime girdiği dahil.
