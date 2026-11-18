---
{
  "title": "Grafana",
  "titleTemplate": ":title | Entegrasyonlar | Kılavuzlar | Tuist",
  "description": "Tuist derleme sağlığını, sürelerini ve önbellek tasarruflarını Grafana'da izleyin ve ekibiniz için uyarıları yapılandırın."
}
---

# Grafana entegrasyonu {#grafana}

Tuist veri kaynağı, süreler, hata sayıları ve önbellekleme sayesinde bildirilen zaman tasarrufu dahil olmak üzere derleme, test ve önbellek metriklerini Grafana’da kullanmanıza olanak tanır. Ekibinizin önem verdiği projeler ve metrikler etrafında panolar oluşturun veya Tuist metriklerini şirketinizin mevcut panolarındaki diğer veri kaynaklarıyla birleştirin. Derlemeler yavaşladığında veya hatalar arttığında ekibinizi bilgilendirmek için Grafana’nın uyarı kurallarını ve bildirim kanallarını kullanın.

## Kullanılabilir metrikler {#metric-definitions}

Tablolar, okunabilir etiketleri ve bunların sorgu tanımlayıcılarını listeler. Derleme sağlığı sorguları `metric` alanındaki tanımlayıcıyı kullanır; derleme ve test süresi sorguları ise `series` alanında `average`, `p50`, `p90` veya `p99` seçeneklerinden birini seçer.

### Derleme sayıları ve güvenilirlik

| Metrik | Tanımlayıcı | Ne ölçer |
| --- | --- | --- |
| Derleme sayısı | `builds` | Kaydedilen derleme sayısı. |
| Başarılı derlemeler | `successful_builds` | Başarıyla tamamlanan derlemeler. |
| Başarısız derlemeler | `failed_builds` | Başarısız olan derlemeler. |
| İptal edilen derlemeler | `cancelled_builds` | İptal edildi olarak kaydedilen derlemeler. Bkz. [derleme sistemi farklılıkları](#build-systems). |
| Derleme başarı oranı | `success_rate` | Yüzde olarak başarılı ÷ (başarılı + başarısız). |
| Başarısız veya yavaş derlemeler | `builds_needing_attention` | Başarısız veya yavaş derlemeler, her derleme için bir kez sayılır. |

### Derleme ve test süreleri

| Metrik | Tanımlayıcı | Ne ölçer |
| --- | --- | --- |
| Ortalama süre | `average` | Seçilen çalıştırmaların ortalama süresi. |
| Medyan süre | `p50` | Çalıştırma sürelerinin 50. yüzdelik değeri. |
| 90. yüzdelik süre | `p90` | Çalıştırmaların %90’ının içinde kaldığı veya altında olduğu süre. |
| 99. yüzdelik süre | `p99` | Çalıştırmaların %99’unun içinde kaldığı veya altında olduğu süre. |
| Yavaş derleme eşiği | `slow_build_threshold` | 90. yüzdelik süre veya milisaniye cinsinden sabit sınırınız. |

Test süresi metrikleri, Tuist’te kaydedilen test çalıştırmalarını kullanır. Yavaş derleme eşiği yalnızca derlemeler için geçerlidir: bir derlemenin süresi bu eşiği aştığında yavaş kabul edilir. İptal edilen derlemeler ayrı sayılır ve derleme başarı oranına dahil edilmez.

### Önbellek tasarrufları

| Metrik | Tanımlayıcı | Ne ölçer |
| --- | --- | --- |
| Kümülatif görev süresi tasarrufu (Gradle) | `cache_work_avoided` | Önbellek isabetleriyle kaçınılan tahmini görev yürütme süresinin toplamı. |
| Kümülatif görev süresini raporlayan derlemeler | `cache_work_avoided_samples` | Tam bir tahmine sahip derlemeler. |
| Raporlanan önbellek zaman tasarrufu | `cache_time_saved` | Raporlanan geçen süre tasarruflarının toplamı. |
| Önbellek zaman tasarrufunu raporlayan derlemeler | `cache_time_saved_samples` | Geçerli bir tasarruf değerine sahip derlemeler. |

Gradle eklentisi, yerel ve uzak görev önbellek isabetleri için otomatik olarak kaçınılan tahmini işi raporlar. Her önbelleğe alınmış görev için, Gradle tarafından saklanan orijinal yürütme süresinden görevin geri yükleme süresini çıkarır; minimum değer sıfırdır. Derleme tahmini bu değerleri toplar. Paralel görevler çakışabileceğinden bu, kümülatif görev süresidir, geçen derleme süresi tasarrufu değildir. Güncel ve atlanan görevler hariç tutulur.

Görev önbellek isabeti olmayan bir derleme sıfır raporlar. Herhangi bir önbelleğe alınmış görevin orijinal zamanlaması eksikse, telemetri eksikse veya özel meta veri haritasında yer yoksa eklenti tahmini atlar. Daha eski eklenti sürümleri ve diğer derleme sistemleri bunu raporlamaz. Kapsamı kontrol etmek için raporlama sayısını toplam derleme sayısı ile karşılaştırın.

Raporlanan geçen süre tasarrufları `tuist.cache_time_saved_ms` meta verilerinden gelir. Bu metrik, otomatik tahminden ayrı kalır.

Hiçbir derleme bunları raporlamadığında önbellek tasarruflarının değeri yoktur. Once şu anda bu ölçümü kaydetmez. Önbellek isabet ve ıskalama oranları bu veri kaynağı üzerinden kullanılamaz.

### Tablolar

Bu tanımlayıcılar, sorgunun `queryType` alanının değerleridir.

| Tablo | Sorgu türü | İçerik |
| --- | --- | --- |
| İş yüküne göre sağlık | `buildWorkloads` | Derleme sayısı, başarı oranı, medyan ve 90. yüzdelik süre. |
| Arıza kategorileri | `buildFailureReasons` | Tüm arızalar ve arıza kategorisine göre sayılar. |
| Son başarısız derlemeler | `buildRecentFailures` | En son 100 arıza, Tuist bağlantılarıyla birlikte. |

Son arızalar başlangıç zamanı, süre, kullanıcı, dal ve istenen görevleri içerir. Arıza kategorileri `verification`, `infrastructure_tooling` ve `unknown` şeklindedir.

İş yükü özetleri ve dal/iş yükü değer listeleri en fazla 1000 değer döndürür. Derleme sağlığı değişken sorguları son 90 günü kullanır; eski Gradle değişken sorguları mevcut geçmiş penceresini korur. Bazel, araç tarafından raporlanan derleme kullanıcısını gösterir. Diğer entegrasyonlar, raporlama kimlik bilgisiyle ilişkili hesabı gösterir. Kaydedilmiş bir kullanıcı olmadığında, geçmiş Bazel ve Once çalıştırmaları ile proje kimlik bilgileriyle raporlanan Once çalıştırmaları Bilinmiyor olarak görünür.

Eşleşen arızaları bulmak için Derleme Çalıştırmaları üzerinde Arıza kategorisi filtresini kullanın. Kategori, anlamını açıklayan bir bilgi ipucuyla birlikte derleme ayrıntılarında görünür; varsayılan genel bakış ve Derleme Çalıştırmaları tabloları mevcut sütunlarını korur. Başarılı, iptal edilen ve tamamlanmamış derlemelerin arıza kategorisi yoktur. Gradle’ın Önbellek Analitiği kartı ve derleme ayrıntıları Kümülatif görev süresi tasarrufunu gösterir; araç ipucu tahmini ve paralel görevlerin etkisini açıklar. Önbellek widget'ı, seçilen aralığı aynı filtreleri kullanarak hemen önceki eşit uzunluktaki dönemle karşılaştırır. Karşılaştırmalar nötrdür: daha büyük bir toplam daha fazla derlemeyi yansıtabilir. Eksik önceki tahminler karşılaştırma göstermez; kaydedilmiş sıfır taban çizgisi yüzde yerine mutlak artışı gösterir.

## Standart pano {#what-you-can-query}

[Derleme sağlığı panosunu](https://github.com/tuist/tuist/blob/main/grafana-datasource/src/dashboards/build-health.json) içe aktarın, ardından veri kaynağınızı ve projenizi seçin. Derleme sayısı, başarı oranı, medyan ve 90. yüzdelik süreler, yavaş derleme eşiği, nötr başarısız veya yavaş derleme sayısı, gruplandırılmış önbellek tasarrufları ve raporlama kapsamı ile üç arıza ve iş yükü tablosunu içerir. Gerektiğinde diğer kullanılabilir metrikler için paneller ekleyin. Otomatik yavaş eşiği, seçilen dönemin kendi 90. yüzdelik değeridir; bunun üzerindeki derlemeler mutlaka bir gerilemeyi göstermez. Süre hedefi uyarıları için sabit bir eşik ayarlayın. Önbellek panelleri, kapsamının yanında Gradle’ın otomatik kümülatif görev süresi tahminine öncelik verir, ardından kendi kapsamlarının yanında açıkça raporlanan geçen süre tasarruflarını sunar.

## Derleme sistemleri {#build-systems}

Derleme sağlığı sorguları ve standart pano Bazel, Cargo, Once, Gradle ve Xcode'u destekler. Tuist, derleme sistemini projenizden seçer. Karışık projeler şu anda derleme sağlığı sorguları veya standart pano tarafından desteklenmemektedir.

| Derleme sistemi | İş yükü | İptal raporlaması | Önbellek tasarrufları |
| --- | --- | --- | --- |
| Bazel | Komut | Çıkış kodu 8, `run` hariç | Özel meta veri gerektirir |
| Cargo | Komut | Ayırt edilmez; sayı sıfırdır | Geçen süre tasarrufları özel meta veri gerektirir; derleyici işinden kaçınılması geçen süre tasarrufu değildir |
| Once | Komut türü | Kaydedilen iptal nedeni | Kaydedilmedi |
| Gradle | Görev grubu | Raporlanan iptaller | Otomatik işten kaçınma tahmini; geçen süre tasarrufları özel meta veri gerektirir |
| Xcode | Şema | Ayırt edilmez; sayı sıfırdır | Özel meta veri gerektirir |

İşlem kayıtları ve tamamlanmamış çalıştırmalar hariç tutulur. Bazel, derleme, test, çalıştırma ve kapsam komutlarını içerir. Once, sonlandırılmış derleme, test ve genel çalıştırmaları içerir. Cargo, `build`, `check` ve `test-build` gibi derleme komutlarını içerir; eski test yürütme raporları derleme sağlığına dahil edilmez. Cargo son başarısızlıklar, mevcut olduğunda kaydedilen başlangıç zamanını kullanır, yoksa ekleme zamanına geri döner; eksik süreler sıfır yerine kullanılamaz olarak kalır.

Gradle görevleri öncelik sırasına göre enstrümante testler, birim testler, lint/kontroller, assemble/package veya Diğer olarak gruplandırır. Her derleme tek bir iş yüküne aittir. Özel meta veriler, Xcode, Bazel, Cargo ve Gradle için iş yüklerini geçersiz kılabilir.

### Arıza kategorileri

| Kategori | Anlamı | Kaydedilen kanıt |
| --- | --- | --- |
| `verification` | Kod derleme, bağlama, testler veya kontroller sırasında başarısız oldu. | Gradle doğrulama veya derleme istisnaları ve bilinen başarısız görev türleri; Xcode derleyici ve bağlayıcı sorunları; Bazel yapılandırılmış sıfır olmayan derleyici/test eylem sonuçları; Cargo kaydedilen başarısız rustc derlemeleri; Once test hataları veya açıkça derleme, bağlama, test, lint veya kontrol olarak bildirilen başarısız eylemler. |
| `infrastructure_tooling` | Derleme, araçları, bağımlılıkları veya ortamı başarısız olduğu için normal şekilde çalıştırılamadı. | Gradle yapılandırma, bağımlılık çözümleme, giriş/çıkış veya bellek hataları; Bazel yapılandırılmış altyapı hataları ve [belgelenmiş çıkış kodları](https://bazel.build/run/scripts); Once altyapı eylem hataları. |
| `unknown` | Rapor, arızayı sınıflandırmak için yeterli kanıt içermiyor. | Keyfi komutlar, eksik tanılar ve yapılandırılmış kanıt içermeyen eski raporlar. |

Derleme betiklerindeki hatalar dahil olmak üzere Gradle yapılandırma aşaması hataları, görev yürütmesi devam edemediği için altyapı/araçlar altında gruplandırılır.

Açık kategori meta verisi veya kaydedilmiş başarısız bir rustc derlemesi olmayan Cargo hataları `unknown` olarak kalır; başarısız bir `check` veya `test-build` komutu tek başına bir doğrulama hatası oluşturmaz. Cargo görev yeniden kullanım sayaçları ve tahmini derleyici işinden kaçınma, hiçbir zaman geçen süre önbellek tasarruflarını veya Gradle'ın kümülatif görev süresi metriğini sağlamaz.

Açık `tuist.failure_category` meta verisi, otomatik sınıflandırmayı geçersiz kılar. Aksi takdirde, bir derlemede her ikisi de meydana geldiğinde altyapı kanıtı doğrulamaya göre önceliklidir. Başarısız olan keyfi bir betiğin derleyici veya test hatası olduğu varsayılmaz. Tarihsel raporlar Tuist'in zaten sakladığı kanıtları kullanabilir, ancak yeni raporlayıcı alanları eksik bilgileri geriye doğru doldurmaz. Otomatik raporlayıcı meta verileri, mevcut 20 girdilik özel meta veri sınırı içindeki kullanılabilir alanı kullanır.

`buildFailureReasons` yanıtı, uyumluluk için `all` satırını korur. Standart pano, bu toplamı Arıza kategorileri grafiğinden filtreler ve toplam hataları ayrı olarak gösterir. Eski `gradleFailureReasons` sorgusu, orijinal üç kategori satırını korur.

## Sorgu seçenekleri {#query-options}

Sayısal sorgular şu `queryType` değerlerini kullanır:

| Sorgu | Sorgu türü |
| --- | --- |
| Derleme sağlığı | `buildHealth` |
| Xcode derleme süreleri | `buildDuration` |
| Test süreleri | `testDuration` |

`resultMode` alanı, sonuçların nasıl döndürüleceğini kontrol eder:

| Sonuç | Değer | Davranış |
| --- | --- | --- |
| Zaman serisi | `series` | Her aralık için bir değer. |
| Tüm dönem | `total` | Aralıktaki tüm çalıştırmalardan hesaplanan tek bir değer. |

Filtre etiketleri şu sorgu alanlarıyla eşleşir:

| Filtre | Sorgu alanı | Kullanılabilir olduğu yerler |
| --- | --- | --- |
| Ortam | `environment` | Tüm sorgular |
| Dal | `gitBranch` | Derleme sağlığı sorguları ve tabloları |
| İş yükü | `workload` | Derleme sağlığı sorguları ve tabloları |
| Durum | `status` | Derleme sağlığı sorguları, tabloları ve Xcode süreleri |
| Şema | `scheme` | Xcode derleme ve test süreleri |
| Yapılandırma | `configuration` | Xcode derleme süreleri |
| Derleme türü | `category` | Xcode derleme süreleri |

Ortam değerleri `any`, `ci` (otomatik derlemeler) ve `local` şeklindedir. Durum değerleri `success`, `failure` ve derleme sağlığı sorguları için `cancelled` şeklindedir; tüm durumları dahil etmek için değeri boş bırakın. Derleme türü değerleri `clean` ve `incremental` şeklindedir; her ikisini de dahil etmek için değeri boş bırakın.

Boş derleme sağlığı aralıklarında sıfır sayım bulunur ve ortalama süre, süre yüzdelik dilimi veya başarı oranı değeri yoktur. Yavaş derleme eşiği yine de seçilen tam aralığı kullanır. Ayrı test süresi sorgusu, boş zaman serisi aralıkları için sıfır döndürür. Tüm dönem yüzdelik dilimleri, aralık yüzdeliklerinden ziyade çalıştırmalardan hesaplanır. Derleme sağlığı yüzdelik dilimleri kesin toplamayı kullanır; ayrı Xcode ve test süresi sorguları yaklaşık yüzdelik dilimleri kullanır.

Derleme sağlığı zaman serileri, seçilen aralığın başlangıcına kısmi ilk kovayı yerleştirerek görünür kalmasını sağlar. Eski Gradle sorguları orijinal kova zaman damgalarını korur.

Tüm sorgular 366 güne kadar olan tarih aralıklarını kabul eder. Sınırları ve zaman damgaları farklılık gösterir:

| Sorgu | Kullanılan zaman damgası | Aralık sınırları |
| --- | --- | --- |
| Derleme sağlığı: Xcode, Bazel, Cargo, Gradle | Kayıt ekleme zamanı | Başlangıcı içerir, bitişi hariç tutar |
| Derleme sağlığı: Once | Çalıştırma başlangıç zamanı | Başlangıcı içerir, bitişi hariç tutar |
| Xcode derleme süreleri | Kayıt ekleme zamanı | Başlangıç ve bitişi hariç tutar |
| Test süreleri | Kaydedilen çalışma zamanı | Başlangıcı ve bitişi içerir |

### Pano değişkenleri

Projeler ve desteklenen filtreler için pano değişkenlerini kullanın. Dal ve iş yükü değişkenleri şu sorguları kullanır:

| Değişken | Sorgu |
| --- | --- |
| Dal | `buildBranches account/project` |
| İş yükü | `buildWorkloads account/project` |

Filtreler tek bir kesin değeri kabul eder. Dal ve iş yükü değişkenleri için Tümü seçeneğinin özel değerini `__tuist_all__` olarak ayarlayın. Diğer filtreler yerleşik Herhangi biri seçeneğini veya boş bir değeri kullanır. Çoklu seçimler ve düzenli ifadeler desteklenmez.

## Özel meta verileri raporlama {#custom-metadata}

Xcode, Bazel, Cargo ve Gradle derlemeleri şu isteğe bağlı meta veri değerlerini kabul eder:

| Anahtar | Kabul edilen değer |
| --- | --- |
| `tuist.workload` | Varsayılan gruplandırmayı değiştiren bir iş yükü adı. |
| `tuist.failure_category` | `verification` veya `infrastructure_tooling`. |
| `tuist.cache_work_avoided_ms` | Yalnızca Gradle. Otomatik olarak raporlanan, 365 güne kadar tamsayı milisaniye cinsinden işten kaçınılan tahmini. |
| `tuist.cache_time_saved_ms` | 0'dan 31.536.000.000'e (365 gün) kadar tamsayı milisaniye. |

Bunları derleme entegrasyonunuzun özel meta veri yapılandırması aracılığıyla sağlayın:

```json
{
  "custom_metadata": {
    "values": {
      "tuist.workload": "Release verification",
      "tuist.failure_category": "verification",
      "tuist.cache_time_saved_ms": "12000"
    }
  }
}
```

Önbellek tasarruflarını yalnızca o derleme için geçen süre ölçümünüz veya belgelenmiş bir tahmininiz varsa bildirin. Görevler eşzamanlı çalıştığında, önbellek isabetleri ve kümülatif görev süreleri tek başına geçen süredeki tasarrufu belirleyemez. Eksik önbellek tasarrufları bilinmiyor olarak kalır. Eksik hata kategorisi meta verileri, [Derleme sistemleri](#build-systems) bölümünde açıklandığı gibi kayıtlı kanıtlara geri döner. Veri saklama değiştirilmez.

## Uyarılar ve Slack {#alerts-and-slack}

Sayısal bir metrikle Grafana tarafından yönetilen bir uyarı kuralı oluşturun. Örneğin:

| Metrik | Tanımlayıcı | Örnek koşul |
| --- | --- | --- |
| Derleme başarı oranı | `success_rate` | %99'un altında |
| Başarısız derlemeler | `failed_builds` | Sıfırın üzerinde |
| 90. yüzdelik dilim süresi | `p90` | Ekibinizin süre sınırının üzerinde |

Değerlendirme penceresi boyunca tek bir değer için **Tüm dönem** kullanın veya bir zaman serisini tek bir değere indirin. Tüm dönem modundaki süre sorguları için bir seri seçin.

- Sabit proje ve filtre değerleri kullanın. Arka plan uyarı değerlendirmesi sırasında pano değişkenleri kullanılamaz.
- Uyarılar için sayısal sorgular kullanın. Bir iş yükünü izlemek için bir derleme sağlığı sorgusunu o iş yüküne göre filtreleyin.
- Derleme veya bildirilen önbellek tasarrufu olmayan aralıklar için kuralın veri yok davranışını ayarlayın.

Bir [Slack iletişim noktası](https://grafana.com/docs/grafana/latest/alerting/configure-notifications/manage-contact-points/integrations/configure-slack/) yapılandırın ve kuralı Grafana'nın bildirim ilkesi aracılığıyla buna yönlendirin. Grafana bildirimleri gönderir ve Slack kimlik bilgilerini saklar.

## Mevcut panoları yükseltme {#upgrading}

Mevcut süre panelleri sorgularını, filtrelerini, seri adlarını ve birimlerini korur. Kaydedilen Gradle sağlık panelleri ve değişkenleri de çalışmaya devam eder.

Paylaşılan derleme sağlığı sorgularını kullanmak için standart panoyu ayrı olarak içe aktarın. Mevcut panolar otomatik olarak taşınmaz. Paylaşılan sorgular, derleme sağlığı uç noktalarını sağlayan bir Tuist sunucusu gerektirir; mevcut süre sorguları eski sunucularla da çalışmaya devam eder.

## Gereksinimler {#requirements}

- Grafana 10.4 veya daha yenisi.
- Grafiğini çizmek istediğiniz projeleri ve metrikleri okuma iznine sahip bir Tuist jetonu. Aşağıdaki [Kimlik Doğrulama](#authentication) bölümüne bakın.

## Kimlik Doğrulama {#authentication}

Panolar ve arka plan uyarı değerlendirmesi için bir <.localized_link href="/guides/server/authentication#account-tokens">hesap jetonu</.localized_link> kullanın. Derleme metrikleri için `project:builds:read`, test süreleri için `project:tests:read` izni verin ve grafiğini çizmek istediğiniz projelere erişimi kısıtlayın. Yalnızca kullandığınız metrikler için gereken kapsamlar gereklidir. Bir tane oluşturmak için <.localized_link href="/guides/server/authentication#creating-an-account-token">jeto oluşturma talimatlarını</.localized_link> izleyin.

Entegrasyon, kendi projesi için mevcut proje jetonlarını ve kullanıcının okuma izinlerine sahip <.localized_link href="/guides/server/authentication#as-a-user">kullanıcı erişim jetonlarını</.localized_link> da kabul eder. Kullanıcı erişim jetonları kısa ömürlüdür. Grafana sağladığınız jetonu saklar, onu yenilemez veya yerel Tuist girişinizi yeniden kullanmaz; süresi dolduğunda değiştirin. Hesap jetonları, bir kullanıcının giriş oturumundan bağımsız olarak proje erişimini, izinleri ve sona erme tarihini kontrol etmenize olanak tanır.

## Yapılandırma {#configuration}

Veri kaynağını ekleyin ve ayarlayın:

| Alan | Kaydedilen ayar | Notlar |
| --- | --- | --- |
| Sunucu URL'si | `jsonData.url` | Varsayılan olarak `https://tuist.dev`. |
| Jeton | `secureJsonData.apiToken` | Tuist bearer jetonu, şifrelenmiş olarak saklanır. |

Bağlantıyı kontrol etmek için **Kaydet ve test et** seçeneğini belirleyin. Grafana erişilebilir projeleri listeler, ardından derleme ve test okuma izinlerini ilk projeye göre kontrol eder.

## Kurulum {#installation}

### Grafana kataloğundan {#from-the-grafana-catalog}

Yayınlandıktan sonra, diğer veri kaynakları gibi **Bağlantılar → Yeni bağlantı ekle → Tuist** yoluyla veya `grafana-cli plugins install tuist-metrics-datasource` ile kurun.

### Yayınlanmadan önce (kendine ait barındırılan Grafana) {#before-it-is-published-self-hosted-grafana}

Eklenti, katalog için onaylanana kadar imzasızdır. Kendine ait barındırılan bir örnekte şunlardan birini yapabilirsiniz:

- **İmzasız olarak izin ver** — `tuist-metrics-datasource` öğesini `allow_loading_unsigned_plugins` (veya `GF_PLUGINS_ALLOW_LOADING_UNSIGNED_PLUGINS=tuist-metrics-datasource`) içine ekleyin ve derlenen eklentiyi eklentiler dizininize bırakın.
- Örnekleriniz için **Özel olarak imzalayın** — `npm run sign -- --rootUrls https://grafana.example.com` (URL, örnek `root_url` ile eşleşmelidir), ardından zip dosyasını dağıtın.

[Grafana Cloud, katalogdaki eklentileri zorunlu kılar](https://grafana.com/docs/grafana-cloud/learn-and-build/get-started/learn/find-and-use-plugins/) ve imzasız veya manuel olarak yüklenen eklentileri desteklemez.
