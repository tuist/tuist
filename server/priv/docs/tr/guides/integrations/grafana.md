---
{
  "title": "Grafana",
  "titleTemplate": ":title | Entegrasyonlar | Kılavuzlar | Tuist",
  "description": "Tuist derleme sağlığını, sürelerini ve önbellek tasarruflarını Grafana'da izleyin ve ekibiniz için uyarıları yapılandırın."
}
---

# Grafana entegrasyonu {#grafana}

Tuist veri kaynağı, süreler, hata sayıları ve önbellekleme sayesinde bildirilen zaman tasarrufu dahil olmak üzere derleme, test ve önbellek metriklerini Grafana’da kullanmanızı sağlar. Ekibinizin önem verdiği projeler ve metrikler etrafında panolar oluşturun veya Tuist metriklerini şirketinizin mevcut panolarındaki diğer veri kaynaklarıyla birleştirin. Derlemeler yavaşladığında veya hatalar arttığında ekibinizi bilgilendirmek için Grafana’nın uyarı kurallarını ve bildirim kanallarını kullanın.

## Kullanılabilir metrikler {#metric-definitions}

Tablolar, okunabilir etiketleri ve bunların sorgu tanımlayıcılarını listeler. Derleme sağlığı sorguları `metric` alanındaki tanımlayıcıyı kullanır; derleme ve test süresi sorguları ise `series` alanında `average`, `p50`, `p90` veya `p99` seçeneklerinden birini seçer.

### Derleme sayıları ve güvenilirlik

| Metrik | Tanımlayıcı | Ne ölçer |
| --- | --- | --- |
| Derleme sayısı | `builds` | Kaydedilen derleme sayısı. |
| Başarılı derlemeler | `successful_builds` | Başarıyla tamamlanan derlemeler. |
| Başarısız derlemeler | `failed_builds` | Başarısız olan derlemeler. |
| İptal edilen derlemeler | `cancelled_builds` | İptal edildi olarak kaydedilen derlemeler. Bkz. [derleme sistemi farkları](#build-systems). |
| Derleme başarı oranı | `success_rate` | Başarılı ÷ (başarılı + başarısız), yüzde olarak. |
| Başarısız veya yavaş derlemeler | `builds_needing_attention` | Başarısız veya yavaş derlemeler, derleme başına bir kez sayılır. |

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
| Birikimli görev zamanı tasarrufu (Gradle) | `cache_work_avoided` | Önbellek isabetleriyle kaçınılan tahmini görev yürütme süresinin toplamı. |
| Birikimli görev zamanını raporlayan derlemeler | `cache_work_avoided_samples` | Tam bir tahmine sahip derlemeler. |
| Raporlanan önbellek zamanı tasarrufu | `cache_time_saved` | Raporlanan geçen süre tasarruflarının toplamı. |
| Önbellek zamanı tasarrufunu raporlayan derlemeler | `cache_time_saved_samples` | Geçerli bir tasarruf değerine sahip derlemeler. |

Gradle eklentisi, yerel ve uzak görev önbelleği isabetleri için otomatik olarak kaçınılan tahmini işi raporlar. Her önbelleğe alınmış görev için, Gradle tarafından saklanan orijinal yürütme süresinden görevin geri yükleme süresini çıkarır; minimum değer sıfırdır. Derleme tahmini bu değerleri toplar. Paralel görevler örtüşebilir, bu nedenle bu geçen derleme süresi tasarrufu değil, birikimli görev süresidir. Güncel ve atlanan görevler hariç tutulur.

Görev önbelleği isabeti olmayan bir derleme sıfır rapor eder. Önbelleğe alınmış herhangi bir görevin orijinal zamanlaması eksikse, telemetri eksikse veya özel meta veri haritasında yer yoksa eklenti tahmini atlar. Daha eski eklenti sürümleri ve diğer derleme sistemleri bunu rapor etmez. Kapsamı kontrol etmek için raporlama sayısını toplam derleme sayısı ile karşılaştırın.

Raporlanan geçen süre tasarrufları `tuist.cache_time_saved_ms` meta verilerinden gelir. Bu metrik, otomatik tahminden ayrı kalır.

Hiçbir derleme raporlamadığında önbellek tasarruflarının değeri yoktur. Once şu anda bu ölçümü kaydetmemektedir. Önbellek isabet ve ıskalama oranları bu veri kaynağı üzerinden kullanılamaz.

### Tablolar

Bu tanımlayıcılar, sorgunun `queryType` alanının değerleridir.

| Tablo | Sorgu türü | İçerik |
| --- | --- | --- |
| İş yüküne göre sağlık | `buildWorkloads` | Derleme sayısı, başarı oranı, medyan ve 90. yüzdelik süre. |
| Başarısızlık kategorileri | `buildFailureReasons` | Tüm başarısızlıklar ve başarısızlık kategorisine göre sayılar. |
| Son başarısız derlemeler | `buildRecentFailures` | Tuist bağlantılarıyla birlikte son 100 başarısızlık. |

Son başarısızlıklar başlangıç zamanı, süre, kullanıcı, dal ve istenen görevleri içerir. Başarısızlık kategorileri `verification`, `infrastructure_tooling` ve `unknown` şeklindedir.

İş yükü özetleri ve dal/iş yükü değer listeleri en fazla 1000 değer döndürür. Derleme sağlığı değişken sorguları son 90 günü kullanır; eski Gradle değişken sorguları mevcut geçmiş penceresini korur. Bazel, araç tarafından rapor edilen derleme kullanıcısını gösterir. Diğer entegrasyonlar, raporlama kimlik bilgisiyle ilişkili hesabı gösterir. Kaydedilmiş bir kullanıcı olmadığında, geçmiş Bazel ve Once çalıştırmaları ile proje kimlik bilgileriyle rapor edilen Once çalıştırmaları Bilinmeyen olarak görünür.

Eşleşen başarısızlıkları bulmak için Derleme Çalıştırmaları üzerindeki Başarısızlık kategorisi filtresini kullanın. Kategori, anlamını açıklayan bir bilgi ipucuyla birlikte derleme ayrıntılarında görünür; varsayılan genel bakış ve Derleme Çalıştırmaları tabloları mevcut sütunlarını korur. Başarılı, iptal edilen ve tamamlanmamış derlemelerin başarısızlık kategorisi yoktur. Gradle’ın Önbellek Analitiği kartı ve derleme ayrıntıları Birikimli görev zamanı tasarrufunu gösterir; araç ipucu tahmini ve paralel görevlerin etkisini açıklar. Önbellek widget'ı, seçilen aralığı aynı filtreleri kullanarak hemen önceki eşit uzunluktaki dönemle karşılaştırır. Karşılaştırmalar nötrdür: daha büyük bir toplam daha fazla derlemeyi yansıtabilir. Eksik önceki tahminler karşılaştırma göstermez; kaydedilmiş sıfır taban çizgisi yüzde yerine mutlak artışı gösterir.

## Standart pano {#what-you-can-query}

[derleme sağlığı panosunu](https://github.com/tuist/tuist/blob/main/grafana-datasource/src/dashboards/build-health.json) içe aktarın, ardından veri kaynağınızı ve projenizi seçin. Derleme sayısı, başarı oranı, medyan ve 90. yüzdelik süreler, yavaş derleme eşiği, nötr başarısız veya yavaş derleme sayısı, gruplandırılmış önbellek tasarrufları ve raporlama kapsamı ile üç başarısızlık ve iş yükü tablosunu içerir. Gerektiğinde diğer kullanılabilir metrikler için paneller ekleyin. Otomatik yavaş eşik, seçilen dönemin kendi 90. yüzdelik değeridir; bunun üzerindeki derlemeler mutlaka bir gerilemeyi göstermez. Süre hedefi uyarıları için sabit bir eşik ayarlayın. Önbellek panelleri, Gradle’ın otomatik birikimli görev süresi tahminini kapsamının yanında önceliklendirir, ardından açıkça rapor edilen geçen süre tasarruflarını kendi kapsamlarının yanında gösterir.

## Derleme sistemleri {#build-systems}

Derleme sağlığı sorguları ve standart pano Bazel, Cargo, Once, Gradle ve Xcode'u destekler. Tuist, derleme sistemini projenizden seçer. Karışık projeler şu anda derleme sağlığı sorguları veya standart pano tarafından desteklenmemektedir.

| Derleme sistemi | İş yükü | İptal raporlaması | Önbellek tasarrufları |
| --- | --- | --- | --- |
| Bazel | Komut | Çıkış kodu 8, `run` hariç | Özel meta veri gerektirir |
| Cargo | Komut | Ayırt edilmez; sayı sıfırdır | Geçen süre tasarrufları özel meta veri gerektirir; derleyici işinden kaçınılması geçen süre tasarrufu değildir |
| Once | Komut türü | Kaydedilen iptal nedeni | Kaydedilmedi |
| Gradle | Görev grubu | Rapor edilen iptaller | Otomatik işten kaçınma tahmini; geçen süre tasarrufları özel meta veri gerektirir |
| Xcode | Şema | Ayırt edilmez; sayı sıfırdır | Özel meta veri gerektirir |

İşlem kayıtları ve tamamlanmamış çalıştırmalar hariç tutulur. Bazel; derleme, test, çalıştırma ve kapsam komutlarını içerir. Once; sonlandırılmış derleme, test ve genel çalıştırmaları içerir. Cargo; `build`, `check` ve `test-build` gibi derleme komutlarını içerir; eski test yürütme raporları derleme sağlığından hariç tutulur. Cargo son başarısızlıklar, varsa kaydedilen başlangıç zamanını kullanır, yoksa ekleme zamanına düşer; eksik süreler sıfır yerine mevcut değil olarak kalır.

Gradle görevleri öncelik sırasına göre enstrümante testler, birim testler, lint/kontroller, assemble/package veya Diğer olarak gruplar. Her derleme tek bir iş yüküne aittir. Özel meta veriler Xcode, Bazel, Cargo ve Gradle için iş yüklerini geçersiz kılabilir.

### Başarısızlık kategorileri

| Kategori | Anlamı | Kaydedilen kanıt |
| --- | --- | --- |
| `verification` | Kod derleme, bağlama, testler veya kontrollerde başarısız oldu. | Gradle doğrulama veya derleme istisnaları ve bilinen başarısız görev türleri; Xcode derleyici ve bağlayıcı sorunları; Bazel yapılandırılmış sıfır dışı derleyici/test eylem sonuçları; Cargo kaydedilen başarısız rustc derlemeleri; Once test başarısızlıkları veya derleme, bağlama, test, lint veya kontrol olarak açıkça belirtilen başarısız eylemler. |
| `infrastructure_tooling` | Derleme, araçları, bağımlılıkları veya ortamı başarısız olduğu için normal şekilde çalıştırılamadı. | Gradle yapılandırma, bağımlılık çözümleme, girdi/çıktı veya bellek hataları; Bazel yapılandırılmış altyapı hataları ve [belgelenmiş çıkış kodları](https://bazel.build/run/scripts); Once altyapı eylem hataları. |
| `unknown` | Rapor, başarısızlığı sınıflandırmak için yeterli kanıt içermiyor. | Keyfi komutlar, eksik tanılar ve yapılandırılmış kanıt içermeyen eski raporlar. |

Derleme betiklerindeki hatalar dahil olmak üzere Gradle yapılandırma aşaması hataları, görev yürütmesi devam edemediği için altyapı/araçlar altında gruplanır.

Açık kategori meta verisi veya kaydedilmiş başarısız bir rustc derlemesi olmayan Cargo hataları `unknown` olarak kalır; başarısız bir `check` veya `test-build` komutu tek başına bir doğrulama hatası oluşturmaz. Cargo görev yeniden kullanım sayaçları ve tahmini derleyici işinden kaçınılması, hiçbir zaman geçen süre önbellek tasarruflarını veya Gradle'ın birikimli görev süresi metriğini sağlamaz.

Açık `tuist.failure_category` meta verisi otomatik sınıflandırmayı geçersiz kılar. Aksi takdirde, bir derlemede her ikisi de meydana geldiğinde altyapı kanıtı doğrulamaya göre önceliklidir. Başarısız olan keyfi bir betiğin derleyici veya test hatası olduğu varsayılmaz. Tarihsel raporlar Tuist'in zaten sakladığı kanıtları kullanabilir, ancak yeni raporlayıcı alanları eksik bilgileri geriye dönük olarak doldurmaz. Otomatik raporlayıcı meta verileri, mevcut 20 girişlik özel meta veri sınırı içindeki kullanılabilir alanı kullanır.

`buildFailureReasons` yanıtı, uyumluluk için `all` satırını korur. Standart pano, bu toplamı Başarısızlık kategorileri grafiğinden filtreler ve toplam başarısızlıkları ayrı olarak gösterir. Eski `gradleFailureReasons` sorgusu orijinal üç kategori satırını korur.

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

Ortam değerleri `any`, `ci` (otomatik derlemeler) ve `local` şeklindedir. Durum değerleri `success`, `failure` ve derleme sağlığı sorguları için `cancelled` şeklindedir; tüm durumları dahil etmek için değeri belirtmeyin. Derleme türü değerleri `clean` ve `incremental` şeklindedir; her ikisini de dahil etmek için değeri belirtmeyin.

Boş derleme sağlığı aralıklarında sıfır sayım bulunur ve ortalama süre, süre yüzdelik dilimi veya başarı oranı değeri yoktur. Yavaş derleme eşiği yine de seçilen tam aralığı kullanır. Ayrı test süresi sorgusu, boş zaman serisi aralıkları için sıfır döndürür. Tüm dönem yüzdelik dilimleri, aralık yüzdelik dilimlerinden ziyade çalıştırmalardan hesaplanır. Derleme sağlığı yüzdelik dilimleri kesin toplamayı kullanır; ayrı Xcode ve test süresi sorguları yaklaşık yüzdelik dilimler kullanır.

Derleme sağlığı zaman serileri, görünür kalması için seçilen aralığın başlangıcına kısmi bir ilk kova yerleştirir. Eski Gradle sorguları orijinal kova zaman damgalarını korur.

Tüm sorgular 366 güne kadar olan tarih aralıklarını kabul eder. Sınırları ve zaman damgaları farklılık gösterir:

| Sorgu | Kullanılan zaman damgası | Aralık sınırları |
| --- | --- | --- |
| Derleme sağlığı: Xcode, Bazel, Cargo, Gradle | Kayıt ekleme zamanı | Başlangıcı içerir, sonu hariç tutar |
| Derleme sağlığı: Once | Çalıştırma başlangıç zamanı | Başlangıcı içerir, sonu hariç tutar |
| Xcode derleme süreleri | Kayıt ekleme zamanı | Başlangıcı ve sonu hariç tutar |
| Test süreleri | Kaydedilen çalıştırma zamanı | Başlangıcı ve sonu içerir |

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
| `tuist.cache_work_avoided_ms` | Yalnızca Gradle. Otomatik olarak raporlanan, 365 güne kadar tamsayı milisaniye cinsinden kaçınılan iş tahmini. |
| `tuist.cache_time_saved_ms` | 0 ile 31.536.000.000 (365 gün) arasında tamsayı milisaniye. |

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

Önbellek tasarruflarını yalnızca o derleme için geçen süre ölçümünüz veya belgelenmiş bir tahmininiz varsa bildirin. Görevler eşzamanlı çalıştığında, önbellek isabetleri ve kümülatif görev süreleri tek başına geçen süredeki tasarrufu belirleyemez. Eksik önbellek tasarrufları bilinmiyor olarak kalır. Eksik hata kategorisi meta verileri, [Derleme sistemleri](#build-systems) altında açıklandığı gibi kaydedilmiş kanıtlara geri döner. Veri saklama politikası değişmemiştir.

## Uyarılar ve Slack {#alerts-and-slack}

Sayısal bir metrik içeren Grafana tarafından yönetilen bir uyarı kuralı oluşturun. Örneğin:

| Metrik | Tanımlayıcı | Örnek koşul |
| --- | --- | --- |
| Derleme başarı oranı | `success_rate` | %99'un altında |
| Başarısız derlemeler | `failed_builds` | Sıfırın üzerinde |
| 90. yüzdelik dilim süresi | `p90` | Ekibinizin süre sınırının üzerinde |

Değerlendirme penceresi boyunca tek bir değer için **Tüm dönem** modunu kullanın veya bir zaman serisini tek bir değere indirgeyin. Tüm dönem modundaki süre sorguları için tek bir seri seçin.

- Sabit proje ve filtre değerleri kullanın. Arka planda uyarı değerlendirilirken pano değişkenleri kullanılamaz.
- Uyarılar için sayısal sorgular kullanın. Bir iş yükünü izlemek için bir derleme sağlığı sorgusunu o iş yüküne göre filtreleyin.
- Derleme veya bildirilen önbellek tasarrufu olmayan aralıklar için kuralın veri yok davranışını ayarlayın.

Bir [Slack iletişim noktası](https://grafana.com/docs/grafana/latest/alerting/configure-notifications/manage-contact-points/integrations/configure-slack/) yapılandırın ve kuralı Grafana'nın bildirim ilkesi aracılığıyla bu noktaya yönlendirin. Bildirimleri Grafana gönderir ve Slack kimlik bilgilerini saklar.

## Mevcut panoları yükseltme {#upgrading}

Mevcut süre panelleri sorgularını, filtrelerini, seri adlarını ve birimlerini korur. Kaydedilen Gradle sağlık panelleri ve değişkenleri de çalışmaya devam eder.

Paylaşılan derleme sağlığı sorgularını kullanmak için standart panoyu ayrı olarak içe aktarın. Mevcut panolar otomatik olarak taşınmaz. Paylaşılan sorgular, derleme sağlığı uç noktalarını sağlayan bir Tuist sunucusu gerektirir; mevcut süre sorguları daha eski sunucularla da çalışmaya devam eder.

## Gereksinimler {#requirements}

- Grafana 10.4 veya daha yenisi.
- Grafiğini çizmek istediğiniz projeleri ve metrikleri okuma iznine sahip bir Tuist jetonu. Aşağıdaki [Kimlik Doğrulama](#authentication) bölümüne bakın.

## Kimlik Doğrulama {#authentication}

Panolar ve arka planda uyarı değerlendirme için bir <.localized_link href="/guides/server/authentication#account-tokens">hesap jetonu</.localized_link> kullanın. Derleme metrikleri için `project:builds:read`, test süreleri için `project:tests:read` izni verin ve grafiğini çizmek istediğiniz projelere erişimi kısıtlayın. Yalnızca kullandığınız metrikler için gereken kapsamlar gereklidir. Bir tane oluşturmak için <.localized_link href="/guides/server/authentication#creating-an-account-token">jeton oluşturma talimatlarını</.localized_link> izleyin.

Entegrasyon ayrıca kendi projesi için mevcut proje jetonlarını ve kullanıcının okuma izinlerine sahip <.localized_link href="/guides/server/authentication#as-a-user">kullanıcı erişim jetonlarını</.localized_link> kabul eder. Kullanıcı erişim jetonları kısa ömürlüdür. Grafana, sağladığınız jetonu saklar ve onu yenilemez veya yerel Tuist oturum açma bilgilerinizi yeniden kullanmaz; süresi dolduğunda değiştirin. Hesap jetonları, bir kullanıcının oturum açma oturumundan bağımsız olarak proje erişimini, izinleri ve sona erme süresini kontrol etmenize olanak tanır.

## Yapılandırma {#configuration}

Veri kaynağını ekleyin ve şunları ayarlayın:

| Alan | Kaydedilen ayar | Notlar |
| --- | --- | --- |
| Sunucu URL'si | `jsonData.url` | Varsayılan olarak `https://tuist.dev` değerine ayarlanır. |
| Jeton | `secureJsonData.apiToken` | Şifrelenmiş olarak saklanan Tuist bearer jetonu. |

Bağlantıyı kontrol etmek için **Kaydet ve test et** seçeneğini belirleyin. Grafana erişilebilir projeleri listeler, ardından ilk projeye karşı derleme ve test okuma izinlerini kontrol eder.

## Kurulum {#installation}

### Grafana kataloğundan {#from-the-grafana-catalog}

Yayınlandıktan sonra, diğer tüm veri kaynakları gibi **Bağlantılar → Yeni bağlantı ekle → Tuist** yolundan veya `grafana-cli plugins install tuist-metrics-datasource` komutuyla kurun.

### Yayınlanmadan önce (kendiniz barındırdığınız Grafana) {#before-it-is-published-self-hosted-grafana}

Eklenti, katalog için onaylanana kadar imzasızdır. Kendi kendine barındırılan bir örnekte şunlardan birini yapabilirsiniz:

- **İmzasız olarak yüklemeye izin ver** — `tuist-metrics-datasource` öğesini `allow_loading_unsigned_plugins` listesine ekleyin (veya `GF_PLUGINS_ALLOW_LOADING_UNSIGNED_PLUGINS=tuist-metrics-datasource`) ve derlenen eklentiyi eklentiler dizininize bırakın.
- Örnekleriniz için **özel olarak imzalayın** — `npm run sign -- --rootUrls https://grafana.example.com` (URL, örneğin `root_url` değeriyle eşleşmelidir), ardından zip dosyasını dağıtın.

[Grafana Cloud, katalogdaki eklentileri zorunlu kılar](https://grafana.com/docs/grafana-cloud/learn-and-build/get-started/learn/find-and-use-plugins/) ve imzasız veya manuel olarak yüklenen eklentileri desteklemez.
