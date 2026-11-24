---
{
  "title": "Kararsız test nedir? Nedenleri, tespiti ve çözümleri",
  "titleTemplate": ":title · Tuist",
  "description": "Kararsız bir test, aynı kod üzerinde bazen geçer bazen başarısız olur. Yaygın nedenleri, Xcode, Gradle ve Bazel'de kararsız test tespitinin nasıl çalıştığını ve kararsızlığın nasıl ölçüleceğini öğrenin."
}
---
# Kararsız test nedir? {#what-is-a-flaky-test}

Kararsız test, aynı koda karşı çalıştırıldığında hem geçen hem de başarısız olan otomatik bir testtir; test edilen kodda veya testin kendisinde hiçbir değişiklik olmamıştır. Sonucu, testin kontrol etmediği bir şeye bağlıdır: zamanlama, testlerin çalışma sırası, başka bir testin geride bıraktığı durum, çalıştığı makine veya ağ üzerinden çağırdığı bir hizmet. Bu nedenle kararsız bir başarısızlık, test edilen değişiklik hakkında güvenilir bir şey söylemez; bu da kararsız testleri maliyetli kılar: herkes güvenmeden önce her kırmızı sonuç incelenmeli veya yeniden denenmelidir.

Kararsızlık her ölçekte yaygındır. Google, tüm test çalışmalarının yaklaşık %1,5’inin kararsız bir sonuç ürettiğini ve testlerinin neredeyse %16’sının belirli bir düzeyde kararsızlık gösterdiğini bildirmiştir ([Google’da Kararsız Testler ve Bunları Nasıl Azaltıyoruz](https://testing.googleblog.com/2016/05/flaky-tests-at-google-and-how-we.html), 2016).

## Kararsız testler nasıl ortaya çıkar {#how-flaky-tests-show-up}

Bir testin kararsız olduğu, aynı girdi için her iki sonucu da ürettiğinde anlaşılır. Pratikte bu kanıt üç kaynaktan birinden gelir:

- **Bir çalışma içindeki yeniden denemeler.** Bir test başarısız olur, runner onu yeniden dener ve yeniden deneme geçer. Bu en düşük maliyetli sinyaldir ve çoğu test runner bunu üretebilir.
- **Aynı commit’in çelişen çalışmaları.** Aynı commit ve yapılandırmaya sahip iki CI çalışması, bir test için farklı sonuçlar bildirir; örneğin pull request üzerindeki bir çalışma ve biri yeniden dene’ye tıkladıktan sonraki yeniden çalışma.
- **Kasıtlı tekrar.** Bir test, kasıtlı olarak art arda birçok kez çalıştırılır ve hiç başarısız olup olmadığına bakılır. Ekipler, şüpheli bir kararsızlığı doğrulamak veya yeni bir testi birleştirmeden önce kararlı olduğunu kontrol etmek için bunu kullanır.

Sonuçlar yalnızca önemli olan her şey aynı olduğunda kararsızlığa kanıt sayılır: commit, derleme yapılandırması, cihaz veya simülatör, işletim sistemi sürümü ve araç zinciri. iOS 17’de başarısız olan ve iOS 18’de geçen bir test, bunlardan birinde gerçek, deterministik bir hata barındırıyor olabilir.

## Derleme sistemine göre kararsız test algılama nasıl çalışır {#how-it-works-per-build-system}

Her araç zinciri testleri yeniden deneyebilir ve tekrarlayabilir, ancak sonuçları farklı şekilde kaydeder ve raporlar.

### Xcode {#xcode}

`xcodebuild` ve test planları test tekrarını destekler. `-retry-tests-on-failure` başarısız olan bir testi yeniden çalıştırır, `-test-iterations <n>` izin verilen deneme sayısını belirler ve `-run-tests-until-failure` bir testi başarısız olana kadar tekrar eder; bu, şüpheli bir kararsızlığı yeniden üretmek için yararlıdır. Test planları, test tekrarlama modu olarak aynı seçenekleri sunar ve ayrıca testleri rastgele sırada çalıştırmak için bir seçenek içerir; bu, gizli sıra bağımlılıklarını ortaya çıkarır.

Her deneme `.xcresult` paketinde saklanır, bu nedenle başarısız olup yeniden denemede geçen bir test orada görünür. Xcode çalışmalar arasında geçmiş tutmaz, bu nedenle aynı çalışma içinde asla yeniden denenmeyen kararsızlıkları algılamak için aynı commit’in farklı çalışmalarından gelen sonuç paketlerini karşılaştırmak gerekir.

### Gradle {#gradle}

Gradle’ın `Test` görevi başarısız testleri kendi başına yeniden denemez. [Test Retry eklentisi](https://github.com/gradle/test-retry-gradle-plugin) (`org.gradle.test-retry`), `Test` görevlerine `retry` bloğu ekler; `maxRetries` ve `failOnPassedAfterRetry` gibi seçenekler sunar. Başarısız olup sonra geçen bir test, test raporlarında ve JUnit XML’inde her iki denemeyle birlikte görünür. Test çerçeveleri kendi tekrar araçlarını ekler; örneğin JUnit 5’in `@RepeatedTest` özelliği.

Gradle’ın derleme önbelleği kararsızlığı gizleyebilir: girdileri değişmemiş önbellenebilir bir `Test` görevi çalışmak yerine önbellekten geri yüklenir, bu nedenle bir kez geçen bir test çalıştırılmadan geçmeye devam eder. Kararsızlığı ölçerken, testleri `--rerun-tasks` ile çalışmaya zorlayın veya derleme önbelleği devre dışıyken `Test` görevini çalıştırın.

### Bazel {#bazel}

Bazel yerleşik desteğe sahiptir. Bir test hedefini `flaky = True` ile işaretlemek, Bazel’in onu en fazla üç kez çalıştırmasını ve yalnızca tüm denemeler başarısız olursa başarısız saymasını sağlar. `--flaky_test_attempts` bayrağı, hedefi değiştirmeden deneme sayısını belirler ve hedefin sonucu, başarısız bir denemeden sonra geçtiğinde `FLAKY` olarak raporlanır. Kararsızlığı kasıtlı olarak ölçmek için `--runs_per_test=<n>` bir testi birçok kez çalıştırır ve `--runs_per_test_detects_flakes`, en az bir çalışma geçip biri başarısız olduğunda bir shard’ı `FLAKY` olarak raporlar.

Bazel, test sonuçlarını derleme çıktılarını önbelleğe aldığı gibi önbelleğe alır. Aynı girdilerle geçen bir test, hem yerel hem de uzak önbellekten tekrar çalıştırılmadan `(cached) PASSED` olarak raporlanır. Taze yürütmelere ihtiyaç duyduğunuzda `--cache_test_results=no` (veya `--nocache_test_results`) kullanın. Bazel belgeleri ayrıca `flaky = True` kullanımına güvenilmesini önermez, çünkü yeniden denediği başarısızlıkları kalıcı olarak gizler.

### Diğer test runner’lar {#other-test-runners}

Aynı desen neredeyse her yerde vardır: pytest’in `pytest-rerunfailures` eklentisi, Jest’in `jest.retryTimes()` yöntemi ve Elixir’in ExUnit’inde `mix test --repeat-until-failure` bulunur; kullanılan rastgele tohumu yazdırır, böylece sıraya bağlı bir başarısızlık `--seed` ile yeniden oynatılabilir.

## Kararsız testlerin yaygın nedenleri {#common-causes}

Açık kaynak projelerde kararsız testlere ilişkin ampirik bir çalışma ([Luo vd., FSE 2014](https://doi.org/10.1145/2635868.2635920)) eşzamansız beklemeyi, eşzamanlılığı ve test sırası bağımlılığını en yaygın kök nedenler olarak bulmuştur. Aşağıdaki liste bunları ve ekiplerin en sık karşılaştığı diğer nedenleri kapsar.

- **Eşzamansız bekleme ve sabit uyku süreleri.** Test, işin bitmesi için `sleep(1)` gibi sabit bir süre veya kısa zaman aşımına sahip bir beklenti ile bekler ve iş bazen daha uzun sürer, özellikle yoğun bir CI makinesinde. Koşulun kendisini, geniş bir üst sınır ile bekleyin.
- **Eşzamanlılık.** İki iş parçacığı veya görev paylaşılan veriler üzerinde yarışır ya da test, arka plandaki bir işlem tamamlanmadan önce iddia yapar. Bu başarısızlıklar genellikle CPU sayısı ve yüke bağlıdır, bu nedenle CI’da ortaya çıkarlar ancak hızlı bir dizüstü bilgisayarda görülmezler.
- **Test sırası bağımlılığı ve paylaşılan durum.** Bir test, başka bir testin oluşturduğu veya temizlemeyi unuttuğu duruma dayanır: bir singleton, bir veritabanı satırı, diskteki bir dosya, `UserDefaults`, bir ortam değişkeni veya mock’lanmış bir global. Testleri rastgele sırada veya paralel çalıştırmak bunu ortaya çıkarır.
- **Zaman ve tarihler.** Gerçek saati kullanan testler gece yarısında, ay sonunda, yaz/kış saati uygulamaları sırasında veya başka bir saat diliminde başarısız olur. Bunun yerine bir saat nesnesi enjekte edin.
- **Tohumsuz rastgelelik ve sırasız koleksiyonlar.** Kaydedilmiş bir tohum olmadan rastgele veri veya bir hash map ya da set’in yineleme sırasına bağlı iddialar.
- **Ağ ve harici servisler.** Gerçek API’lere, paket kayıt defterlerine veya paylaşılan staging ortamlarına yapılan çağrılar, bu servisler yavaş olduğunda veya kullanılamadığında başarısız olur. Sınırda bunları stublayın ve az sayıda açık entegrasyon testi tutun.
- **Kaynak baskısı ve ortam durumu.** Yavaş veya aşırı yüklenmiş makineler, sıfırlanmamış bir simülatör veya emülatör, dolu bir disk veya başka bir işin zaten kullandığı bir port. Birçok ilgisiz test aynı anda başarısız olduğunda, testlerden önce ortamdan şüphelenin.
- **UI testleri.** Uçtan uca ve UI testleri, yukarıdaki nedenlerin çoğunu animasyonlar, render zamanlaması ve sistem diyaloglarıyla birleştirir, bu nedenle birim testlerinden daha sık kararsız olurlar.

Bir değişiklikten sonra tutarlı bir şekilde başarısız olan bir test kararsız değildir; bu bir regresyondur. Kararsız etiketi, aynı kod üzerinde her iki sonucu da üreten testler için ayrılmalıdır.

## Düzeltme, yeniden deneme ve karantinaya alma {#fixing-retrying-and-quarantining}

Ekipler genellikle üç tepkiyi birleştirir ve bunları ayrı tutmak yardımcı olur:

- Nedeni **düzeltin**. Testin değerini geri kazandıran tek tepki budur. Kaydedilen denemeler, hata mesajları ve her başarısız çalışmanın koşulları, nedeni işaret eden kanıtlardır.
- Boru hatlarının akmasını sağlamak için **yeniden deneyin**. Yeniden denemeler yararlı bir tespit sinyalidir, ancak genel yeniden denemeler sorunu gizler ve her başarısız çalışmaya makine zamanı ekler. Başarılı olan bir yeniden deneme, sessizce atılmak yerine hala kararsız bir sonuç olarak kaydedilmelidir.
- Düzeltilirken birleşmeleri engellememesi için bilinen bir kararsız testi **karantinaya alın**. Karantinaya alınan bir test ya hataları yoksayılarak (sessize alınmış) çalışmaya devam eder, bu da kanıt üretmeye devam etmesini sağlar, ya da hiç çalışmaz (atlanmış), bu da kapsamını kaldırır. Karantina, bir sahibi ve bir çıkış koşulu gerektirir; aksi takdirde karantinaya alınan testler birikir ve kapsam sessizce daralır.

## Kararsızlığı nasıl ölçersiniz {#how-to-measure-flakiness}

Kararsızlığı sadece boru hattı başına değil, test başına takip edin:

- **Kararsızlık oranı.** Bir testin çalışmalarının kararsız bir sonuç üreten payı: bir başarısızlığın ardından gelen başarılı bir yeniden deneme veya aynı commit ve yapılandırmaya sahip başka bir çalışma ile çelişen bir sonuç.
- **Etki.** Bir testin kaç boru hattını, çekme isteğini veya birleştirme kuyruğu girişini engellediği veya yavaşlattığı ve yeniden denemelerinin ne kadar makine zamanı tükettiği. Her boru hattında çalışan düşük kararsızlık oranına sahip bir test, nadiren çalışan çok kararsız bir testten daha pahalıya mal olabilir.
- **Trend.** Yeni kararsız testlerin, eskilerinin düzeltilmesinden daha hızlı tanıtılıp tanıtılmadığı. Yeni veya değiştirilen testleri birleştirmeden önce birkaç kez tekrarlamak, birçok kararsızlığı kaynağında yakalar.

Bir testin kararlı olduğunu doğrulamak, sezginin önerdiğinden daha fazla çalışma gerektirir. Bir test her çalışmada *p* olasılığıyla başarısız oluyorsa, *n* çalışmada en az bir başarısızlık görme şansı 1 − (1 − p)ⁿ'dir. Zamanının %1'inde başarısız olan bir test için, 10 çalışma onu yalnızca yaklaşık %10 oranında yakalar ve %95 güvenle yakalamak için yaklaşık 300 çalışma gerekir. Birkaç yeşil yeniden çalışma, bir düzeltmenin işe yaradığına dair zayıf bir kanıttır.

## Ne zaman değmez {#when-it-isnt-worth-it}

Her kararsız test bir incelemeyi hak etmez ve her ekip kararsız test araçlarına ihtiyaç duymaz:

- **Düşük değerli testler.** Kararsız bir test, diğer testlerin zaten sağladığı kapsamı çoğaltıyorsa, onu silmek doğru düzeltme olabilir. Kimsenin güvenmediği bir test zaten hiçbir kapsam sağlamaz.
- **Altyapı sorunları.** Başarısızlıklar tek bir makinede, runner imajında veya günün belirli saatlerinde yoğunlaştığında, ortamı düzeltmek testleri tek tek düzeltmekten daha ucuzdur.
- **Küçük, hızlı test paketleri.** Hızlı bir test paketine ve bilinen tek bir kararsız teste sahip küçük bir ekip için, paylaşılan bir not ve bu hafta içinde bir düzeltme, bir izleme sisteminden daha iyidir. Özel tespit ve karantina, test paketi, katkıda bulunan sayısı veya boru hattı sayısı nedeniyle kimsenin hangi başarısızlıkların gürültü olduğunu hatırlamasını imkansız hale getirdiğinde karşılığını verir.
- **Kritik yollar.** Ödemeleri, veri bütünlüğünü veya güvenliği koruyan bir test için karantina yanlış bir araçtır. Bu testler, rahatsız edici olsa bile düzeltilene kadar engellemelidir.

## Tuist ile kararsız test tespiti {#flaky-test-detection-with-tuist}

[Tuist](https://tuist.dev), Xcode, Gradle, Bazel, Elixir ve diğer desteklenen entegrasyonlardan gelen her test denemesini kaydeder, hem yeniden denemeler arasında hem de desteklenen entegrasyonlar için aynı commit'in CI çalışmaları arasında aynı kod üzerinde başarısız olup geçtiğinde bir testi kararsız olarak işaretler ve ekiplerin düzeltme sırasında bilinen kararsız testleri manuel olarak veya otomasyonlar aracılığıyla sessize almasına veya atlamasına olanak tanır. Destek ve gereksinimler toolchain'e göre farklılık gösterir:

- <.localized_link href="/guides/features/test-insights/flaky-tests">Kararsız testler</.localized_link>, toolchain başına bir kılavuzla tespit, karantina ve yeni testlerin stres testinin nasıl çalıştığını açıklar.
- <.localized_link href="/guides/features/test-insights">Test İçgörileri</.localized_link>, öncelikle test sonuçlarının kaydedilmesini kapsar.
- [Testlerim kararsız](https://tuist.dev/solutions/flaky-tests), kararsız testleri bir ekip olarak teşhis etmek ve sınırlamak için pratik bir kılavuzdur.

İlgili referans: <.localized_link href="/references/concepts/build-cache">Build cache nedir?</.localized_link>, önbelleğe alınmış test sonuçlarının kararsızlıkla nasıl etkileşime girdiği dahil.
