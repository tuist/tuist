---
{
  "title": "Gradle Derleme Analizleri",
  "titleTemplate": ":title · Derleme Analizleri · Özellikler · Kılavuzlar · Tuist",
  "description": "Gradle görev sürelerini ve önbellek davranışını Tuist panosunda takip edin."
}
---
# Gradle derleme içgörüleri {#gradle-build-insights}

Tuist’in Gradle eklentisi, derleme analizlerini Tuist’e göndererek görev yürütme ve derleme performansı hakkında görünürlük sağlar.

## Yükleme davranışını yapılandırma {#configure-upload-behavior}

Varsayılan olarak:
- Derleme analizleri yerel derlemeler için arka planda yüklenir.
- Derleme analizleri, kısa ömürlü ajanlarda telemetri kaybını önlemek amacıyla CI çalıştırmaları için ön planda yüklenir.

Bu davranışı, `tuist` uzantısı içindeki `uploadInBackground` kullanarak kontrol edebilirsiniz:

```kotlin
tuist {
    uploadInBackground = false // always upload in the foreground
}
```

## Yapılandırma referansı {#configuration-reference}

`uploadInBackground` seçeneği, `settings.gradle.kts` dosyasındaki `tuist` uzantı bloğunda kullanılabilir:

| Seçenek | Tür | Varsayılan | Açıklama |
| --- | --- | --- | --- |
| `uploadInBackground` | `Boolean?` | `null` (yerelde arka plan, CI’da ön plan) | Derleme içgörülerinin yerel derlemeler için arka planda yüklenip yüklenmeyeceğini belirler. |

Bu ayar, `buildCache` bloğundaki uzak önbellek ayarlarını etkilemez.

## Rapor aktör talebi {#report-actor-claim}

Derleme ve test raporu istekleri, yalnızca `TUIST_ACTOR_ID` değerini kuruluş kapsamına sahip bir etikete açıkça ayarladığınızda veya ayarlarınızda `buildInsights.actorId` yapılandırdığınızda isteğe bağlı `x-tuist-actor-id` üstbilgisini içerir. Varsayılan olarak hiçbir etiket gönderilmez ve eklenti işletim sistemi kullanıcı adlarını algılamaz. Ortam geçersiz kılması önceliklidir. Raporlanan tanımlayıcıyı atlamak için herhangi bir geçersiz kılmayı boş dizeye ayarlayın; bu, bireysel kimlik bilgileriyle oluşturulan kimliği kaldırmaz. Geçersiz geçersiz kılmalar, geri dönüş yapmak yerine talebi atlar. Özel bir proxy tanıdık olmayan üstbilgileri reddederse, `TUIST_ACTOR_ID=""` ile devre dışı bırakın.

```kotlin
tuist {
    buildInsights {
        actorId = providers.environmentVariable("CORPORATE_ACTOR_ID").getOrElse("")
    }
}
```

Aktör tanımlayıcıları, boşluk içermeyen yazdırılabilir ASCII karakterlerden oluşan 1–128 bayttır. Projenin raporlarını görüntüleyebilen herkes tarafından, proje herkese açık olduğunda halka açık izleyiciler de dahil olmak üzere görülebilir ve raporlarla birlikte dışa aktarılır. Yayınlanmasını istemediğiniz gizli anahtarları veya kişisel bilgileri eklemeyin. Dashboard’da doğrulanmış bireysel kimlik bilgisi önceliklidir; istemciler tarafından gönderilen tanımlayıcılar aksi takdirde açıkça **Doğrulanmamış** olarak işaretlenir. Bunlar asla izin vermez veya otomatik olarak bir Tuist kullanıcısına bağlanmaz. Eski sunucular atıf üstbilgisini yoksayar ve yeni sunucular bunu içermeyen eski istemcileri kabul etmeye devam eder. Tanımlayıcı içermeyen yeni paylaşılan token raporları, yayınlayan kuruluş yerine **Bilinmiyor** gösterir; geçmiş raporlar önceki atıflarını korur. Derleme ve test listeleri, doğrulanmış kullanıcı filtrelerini doğrulanmamış raporlanan tanımlayıcı filtrelerinden ayırır.

## Ağa güvendiği yayınlama {#network-trusted-publishing}

Kendi kendine barındırılan dağıtımlar, geliştirici kimlik bilgileri olmadan güvenilir ağlarından gelen Gradle derleme ve test raporlarına açıkça izin verebilir. Bir operatörün önce örnekte `TUIST_NETWORK_TRUSTED_INSIGHTS_ACCESS=true` yapılandırması ve yeniden başlatması gerekir. Bu, desteklenen her proje için geçerlidir; dashboard ayarı yoktur. Bkz. <.localized_link href="/guides/server/self-host/server#network-trusted-access">kendi kendine barındırma kılavuzu</.localized_link>.

Hedefi depoda bir kez yapılandırın:

```kotlin
tuist {
    project = "organization/project"
    url = "https://tuist.internal.example"
    buildCache { enabled = false }
}
```

Derleme ve test raporlama, kimliği doğrulanmış önbellek uç noktası keşfi gerektirmez. Örnek ayrı olarak ağa güvenilen önbellek erişimini etkinleştirmediyse veya geliştiriciler token sağlamadıysa önbelleği devre dışı bırakın. İmzasız test raporları parça ve mevcut derleme referanslarını atlar ve karantina veya kararsızlık otomasyonlarını tetiklemez. Kimlik bilgileri gerçekten yoksa karantina araması atlanır; geçerli kimlik bilgileriyle mevcut kimlik doğrulamalı davranış korunur. Kimlik bilgileri varsa hâlâ kullanılır ve geçersiz kimlik bilgileri, kimlik bilgisiz yayınlamaya geri düşmek yerine başarısız olur. Kimlik bilgileri olmadığında, eklenti kendi kendine barındırılan sunucunun kimlik bilgisiz raporlamaya izin verip vermediğini otomatik olarak keşfeder. Hiçbir istemci bayrağı veya `buildInsights` ayarı gerekmez. Kimlik bilgisiz istemcileri yükseltmeden önce her sunucu çoğaltmasını keşif yetenekli bir sürüme yükseltin. Keşif özelliği olmayan eski sunucular, devre dışı bırakılmış örnekler ve keşif hataları hâlâ kimlik doğrulama gerektirir; kimlik doğrulamalı yayınlama uyumlu kalır. Açıkça boş bırakılan `TUIST_TOKEN`, kimlik bilgisiz yayınlamayı etkinleştirmek yerine güvenli şekilde başarısız olur. Gizli anahtarlara erişimi olmayan fork veya Dependabot işleri için, değişkeni boş dize olarak tanımlamak yerine kaldırın.

Sunucu, kimlik bilgisiz rapor kimlikleri atar. Bir gönderimi tekrarlamak ikinci bir rapor oluşturabilir; bu mod, yinelenen denemelerin idempotent olacağını veya kimlik doğrulamalı test raporlarıyla ilişkilendirileceğini garanti etmez. Bu tür raporlar VCS yorumlarını veya otomatik hata-aracı olaylarını tetikleyemez. Ağ erişimi, yayınlama güven sınırıdır; raporlanan aktörün kimliğinin kanıtı değildir.

## Özel meta veriler {#custom-metadata}

Farklı ekipler, donanımlar veya iş akışlarından gelen çalıştırmaları karşılaştırmak için Gradle derlemelerine etiketler ve anahtar-değer verileri ekleyin. Etiketler dashboard filtreleri olarak kullanılabilir ve değerler her derlemenin ayrıntı sayfasında, uygulama programlama arayüzünde ve Model Bağlam Protokolü araçlarında görünür.

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

Etiketler yalnızca harf, rakam, tire ve alt çizgi içerebilir. Bir derleme en fazla 50 etikete sahip olabilir ve her etiket en fazla 50 karakter içerebilir. Bir derleme en fazla 20 anahtar-değer girdisine sahip olabilir; her anahtar en fazla 50 karakter, her değer en fazla 500 karakter içerebilir. Bunlar, Xcode derleme meta verileri için kullanılan aynı sunucu tarafı sınırlardır. Eklenti, raporu göndermeden önce geçersiz etiketleri ve aşırı büyük veya boş meta veri girdilerini atlar, bu nedenle geçersiz yapılandırma derleme içgörüleri raporunun geri kalanının saklanmasını engellemez. Etiket kısıtlamasını karşılamayan değerler için anahtar-değer meta verilerini kullanın.

Özel meta veriler, dashboard’da ve uygulama programlama arayüzü ile Model Bağlam Protokolü araçları aracılığıyla proje üyeleri tarafından görülebilir. Bunları kimlik bilgileri, erişim token’ları veya diğer hassas veriler için kullanmayın. Tuist, bu meta veriler de dahil olmak üzere Gradle derleme verilerini 90 gün boyunca saklar. Ayrıntılar için bkz. <.localized_link href="/guides/server/data-retention">veri saklama politikası</.localized_link>.
