---
{
  "title": "Gradle Derleme İçgörüleri",
  "titleTemplate": ":title · Derleme İçgörüleri · Özellikler · Kılavuzlar · Tuist",
  "description": "Gradle görev sürelerini ve önbellek davranışını Tuist panosunda takip edin."
}
---
# Gradle derleme içgörüleri {#gradle-build-insights}

Tuist’in Gradle eklentisi, derleme analizlerini Tuist’e gönderebilir; bu sayede görev yürütme ve derleme performansı hakkında görünürlük elde edersiniz.

## Yükleme davranışını yapılandırma {#configure-upload-behavior}

Varsayılan olarak:
- Derleme analizleri yerel derlemeler için arka planda yüklenir.
- Derleme analizleri, kısa ömürlü ajanlarda telemetri kaybını önlemek amacıyla CI çalıştırmaları için ön planda yüklenir.

Bu davranışı, `tuist` uzantısı içindeki `uploadInBackground` ile kontrol edebilirsiniz:

```kotlin
tuist {
    uploadInBackground = false // always upload in the foreground
}
```

## Yapılandırma referansı {#configuration-reference}

`uploadInBackground` seçeneği, `settings.gradle.kts` içindeki `tuist` uzantı bloğunda kullanılabilir:

| Seçenek | Tür | Varsayılan | Açıklama |
| --- | --- | --- | --- |
| `uploadInBackground` | `Boolean?` | `null` (yerelde arka planda, CI’da ön planda) | Yerel derlemeler için derleme içgörülerinin arka planda yüklenip yüklenmeyeceğini belirler. |

Bu ayar, `buildCache` bloğundaki uzak önbellek ayarlarını etkilemez.

## Rapor aktör iddiası {#report-actor-claim}

Derleme ve test raporu istekleri, yalnızca `TUIST_ACTOR_ID` değerini kuruluş kapsamlı bir etikete açıkça ayarladığınızda veya ayarlarınızda `buildInsights.actorId` yapılandırdığınızda isteğe bağlı `x-tuist-actor-id` üstbilgisini içerir. Varsayılan olarak hiçbir etiket gönderilmez ve eklenti işletim sistemi kullanıcı adlarını algılamaz. Ortam geçersiz kılma önceliklidir. Raporlanan tanımlayıcıyı atlamak için herhangi bir geçersiz kılmayı boş dizeye ayarlayın; bu, bireysel kimlik bilgileriyle kurulan kimliği kaldırmaz. Geçersiz geçersiz kılmalar, geri dönüş yapmak yerine iddiayı atlar. Özel bir proxy tanıdık olmayan üstbilgileri reddederse, `TUIST_ACTOR_ID=""` ile devre dışı bırakın.

```kotlin
tuist {
    buildInsights {
        actorId = providers.environmentVariable("CORPORATE_ACTOR_ID").getOrElse("")
    }
}
```

Aktör tanımlayıcıları, boşluk içermeyen yazdırılabilir ASCII karakterlerden oluşan 1–128 bayttır. Projenin raporlarını görüntüleyebilen herkes tarafından, proje herkese açık olduğunda halka açık izleyiciler dahil, görülebilir ve raporlarla birlikte dışa aktarılır. Yayınlamak istemediğiniz gizli anahtarları veya kişisel bilgileri eklemeyin. Doğrulanmış bireysel kimlik bilgisi panoda önceliklidir; istemciler tarafından gönderilen tanımlayıcılar aksi takdirde açıkça **Doğrulanmamış** olarak işaretlenir. Bu tanımlayıcılar asla izin vermez veya otomatik olarak bir Tuist kullanıcısına bağlanmaz. Eski sunucular atıf üstbilgisini yok sayar ve yeni sunucular bunu olmadan eski istemcileri kabul etmeye devam eder. Tanımlayıcı içermeyen yeni ortak token raporları, yayıncı kuruluş yerine **Bilinmiyor** gösterir; geçmiş raporlar önceki atıflarını korur. Derleme ve test listeleri, doğrulanmış kullanıcı filtrelerini doğrulanmamış raporlanan tanımlayıcı filtrelerinden ayırır.

## Ağ güvencesine dayalı yayınlama {#network-trusted-publishing}

Kendi kendine barındırılan dağıtımlar, geliştirici kimlik bilgileri olmadan güvenilir ağlarından gelen Gradle derleme ve test raporlarına açıkça izin verebilir. Bir operatörün önce örnekte `TUIST_NETWORK_TRUSTED_INSIGHTS_ACCESS=true` yapılandırması ve yeniden başlatması gerekir. Bu, desteklenen her proje için geçerlidir; pano ayarı yoktur. Bkz. <.localized_link href="/guides/server/self-host/server#network-trusted-access">kendi kendine barındırma kılavuzu</.localized_link>.

Hedefi depoda bir kez yapılandırın:

```kotlin
tuist {
    project = "organization/project"
    url = "https://tuist.internal.example"
    buildCache { enabled = false }
}
```

Derleme ve test raporlama, kimlik doğrulamalı önbellek uç noktası keşfi gerektirmez. Örnek ayrı olarak ağ güvencesine dayalı önbellek erişimini etkinleştirmedikçe veya geliştiriciler token sağlamadıkça önbelleği devre dışı bırakın. İmzasız test raporları parça ve mevcut derleme referanslarını atlar ve karantina veya kararsızlık otomasyonlarını tetiklemez. Kimlik bilgileri gerçekten yoksa karantina araması atlanır; geçerli kimlik bilgileriyle mevcut kimlik doğrulamalı davranış korunur. Kimlik bilgileri varsa yine kullanılır ve geçersiz kimlik bilgileri, kimlik bilgisiz yayınlamaya geri düşmek yerine başarısız olur. Kimlik bilgileri olmadığında, eklenti kendi kendine barındırılan sunucunun kimlik bilgisiz raporlamaya izin verip vermediğini otomatik olarak keşfeder. Herhangi bir istemci bayrağı veya `buildInsights` ayarı gerekmez. Kimlik bilgisiz istemcileri yükseltmeden önce her sunucu çoğaltmasını keşif yetenekli bir sürüme yükseltin. Keşif özelliği olmayan eski sunucular, devre dışı bırakılmış örnekler ve keşif hataları hâlâ kimlik doğrulama gerektirir; kimlik doğrulamalı yayınlama uyumlu kalır. Açıkça boş bırakılan `TUIST_TOKEN`, kimlik bilgisiz yayınlamayı etkinleştirmek yerine güvenli bir şekilde başarısız olur. Gizli anahtarı olmayan fork veya Dependabot işleri için değişkeni boş dize olarak tanımlamak yerine kaldırın.

Sunucu, kimlik bilgisiz rapor kimlikleri atar. Bir gönderimi tekrarlamak ikinci bir rapor oluşturabilir; bu mod yinelenen denemelerin idempotent olacağını veya kimlik doğrulamalı test raporlarıyla ilişkilendirileceğini garanti etmez. Bu tür raporlar VCS yorumlarını veya otomatik hata-aracısı olaylarını tetikleyemez. Ağ erişimi yayınlama güven sınırıdır, raporlanan aktörün kimliğinin kanıtı değildir.

## Özel meta veriler {#custom-metadata}

Farklı ekipler, donanımlar veya iş akışlarından gelen çalıştırmaları karşılaştırmak için Gradle derlemelerine etiketler ve anahtar-değer verileri ekleyin. Etiketler pano filtreleri olarak kullanılabilir ve değerler her derlemenin ayrıntı sayfasında, uygulama programlama arayüzünde ve Model Bağlam Protokolü araçlarında görünür.

Meta verileri ortam değişkenleriyle ayarlayın:

```sh
export TUIST_BUILD_TAGS="nightly,android"
export TUIST_BUILD_VALUE_TICKET="TUIST-123"
export TUIST_BUILD_VALUE_RUNNER="macos-14"
```

Meta verileri `settings.gradle.kts` içinde de yapılandırabilirsiniz:

```kotlin
tuist {
    buildInsights {
        tag("nightly")
        tag("android")
        value("ticket", "TUIST-123")
        value("runner", "macos-14")
    }
}
```

Aynı değer her iki yerde de yapılandırıldığında, `settings.gradle.kts` içindeki değer önceliklidir.

Etiketler yalnızca harf, rakam, tire ve alt çizgi içermelidir. Bir derleme en fazla 50 etikete sahip olabilir ve her etiket en fazla 50 karakter içerebilir. Bir derleme en fazla 20 anahtar-değer girdisine sahip olabilir; her anahtar en fazla 50 karakter, her değer en fazla 500 karakter içerebilir. Bunlar, Xcode derleme meta verileri için kullanılan aynı sunucu tarafı sınırlardır. Eklenti, raporu göndermeden önce geçersiz etiketleri ve aşırı büyük veya boş meta veri girdilerini atlar, bu nedenle geçersiz yapılandırma derleme içgörüleri raporunun geri kalanının depolanmasını engellemez. Etiket kısıtlamasını karşılamayan değerler için anahtar-değer meta verilerini kullanın.

Özel meta veriler, proje üyeleri tarafından panoda, uygulama programlama arayüzü üzerinden ve Model Bağlam Protokolü araçlarıyla görülebilir. Kimlik bilgileri, erişim tokenları veya diğer hassas veriler için kullanmayın. Tuist, Gradle derleme verilerini, bu meta veriler dahil, 90 gün boyunca saklar. Ayrıntılar için <.localized_link href="/guides/server/data-retention">veri saklama politikasına</.localized_link> bakın.

## Hata ayrıntıları {#failure-details}

Bir derleme başarısız olduğunda, eklenti her başarısız görevin veya yapılandırma adımının neden başarısız olduğunu bildirir: Gradle konsolunun yazdırdığı şekilde istisna mesajını ve neden zincirini; örneğin, başarısız bir `compileJava` görevinin derleyici hatalarını veya bir derleme betiğindeki hatayı. Yığın izleri ve görev çıktıları toplanmaz. Eklenti, raporu göndermeden önce proje içindeki yolları göreli hale getirir ve Tuist, tanıdığı kimlik bilgilerini ve diğer yerel yolları gizler. Her mesaj 16 KiB ile sınırlıdır ve bir derleme en fazla 32 başarısız adımın mesajlarını saklar.

Hata mesajları, proje üyeleri tarafından uygulama programlama arayüzü, Model Bağlam Protokolü araçları (`get_gradle_build`, `list_gradle_build_tasks` ve `get_gradle_build_step`) ve CLI üzerinden görülebilir:

```bash
tuist build gradle failure list <build-id>
```

Mesajlar kaynak kod parçacıkları ve proje ayrıntıları içerebilir. Kimlik bilgileri olmadan [ağ güvenilen yayınlama](#network-trusted-publishing) yoluyla yayınlanan raporlar bunları içermez. Tuist, bunları Gradle derleme verilerinin geri kalanıyla birlikte 90 gün boyunca saklar.
