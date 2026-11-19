---
{
  "title": "Web Kancaları",
  "titleTemplate": ":title | Entegrasyonlar | Kılavuzlar | Tuist",
  "description": "HTTPS uç noktalarını Tuist etkinliklerine abone edin, teslimatları imzalı bir yük ile doğrulayın ve her denemeyi panodan inceleyin."
}
---
# Webhooks {#webhooks}

Webhooks, sistemlerinizin Tuist içindeki değişikliklere anında tepki vermesini sağlar. İlgili bir olay gerçekleştiğinde — yeni bir test senaryosu gözlemlendiğinde, bir önizleme yüklemesi tamamlandığında veya kararsız bir test düzeltildiğinde — Tuist, o olay türüne abone olduğunuz her uç noktaya bir HTTP POST isteği gönderir. İstek gövdesi bir JSON zarfıdır ve her teslimat, uç noktanın imzalama gizli anahtarıyla doğrulayabileceğiniz bir imza başlığı taşır.

Bir hedef URL kaydedersiniz, istediğiniz olayları seçersiniz ve Tuist imzalama, yeniden denemeler ve teslimat denetim günlüğü işlemlerini yönetir.

## Webhook alma adımları {#steps}

Uygulamanızda olay bildirimlerini almaya şu adımlarla başlayabilirsiniz:

1. [Uygulamanızın almak istediği olayları belirleyin](#event-types).
2. Yerel sunucunuzda bir HTTP uç noktası (URL) olarak [bir webhook uç noktası oluşturun](#create-an-endpoint).
3. Tuist’ten gelen istekleri [yükü ayrıştırarak](#payload) ve Tuist’in teslimatı başarılı olarak işaretlemesi için [bir 2xx durumu döndürerek](#responding) işleyin.
4. İsteğin Tuist’ten geldiğini kanıtlamak için her istekte [imzayı doğrulayın](#verify-signature).
5. Geliştirme yaparken hata ayıklamak için Tuist kontrol panelindeki [olay günlüğünü](#inspect-deliveries) kullanın.

## Olay türleri {#event-types}

Tuist, olayları tanımladıkları kaynağa göre gruplar. Zarf içindeki `type` alanı noktalı gösterim kullanır (`{resource}.{action}`) — bu, kontrol panelinde abone olacağınız değerle aynıdır.

{{webhook_events_table}}

Daha fazla olay türü eklenecek. Henüz yayınlamadığımız bir türe ihtiyacınız varsa bize bildirin; kataloğa ekleyelim.

## Bir uç nokta oluşturma {#create-an-endpoint}

Uç noktalar hesap başına yapılandırılır. Hesap ayarlarınızdan **Webhooks** bölümünü açın, **Uç nokta ekle** düğmesine tıklayın ve şunları girin:

- **Ad** — uç noktanın listede nasıl görüneceği.
- **Uç Nokta URL’si** — `https://` kullanmalıdır.
- **Dinlenecek olaylar** — belirli olayları seçin veya grup düzeyinde **Tümünü seç** seçeneğini kullanın. Tuist, yalnızca abone olunan olaylardan biri tetiklendiğinde uç noktaya POST isteği gönderir.

![Her biri iki olaya abone olmuş iki webhook uç noktasını gösteren Uç Noktalar listesi](/images/guides/integrations/webhooks/endpoints.png)

Kaydettiğinizde Tuist yeni bir imzalama gizli anahtarı oluşturur ve bunu bir kez gösterir. Hemen uygulamanızın yapılandırmasına kopyalayın; kontrol panelinden tekrar alamazsınız. Anahtarı kaybederseniz, uç noktanın işlem menüsünden **Gizli anahtarı döndür** seçeneğini kullanarak yeni bir anahtar oluşturun.

<img src="/images/guides/integrations/webhooks/create-endpoint.png" alt="Ad, URL ve gruplanmış olay türü onay kutularını içeren Webhook uç noktası oluşturma iletişim kutusu" style="max-width: 500px;" />

## Yük {#payload}

Her teslimat tek bir JSON nesnesidir. Zarf, teslimatları çoğaltmayı önlemek, yönlendirmek ve denetlemek için kullanabileceğiniz meta verilerle olaya özgü bir kaynak anlık görüntüsünü sarar:

| Alan     | Açıklama                                                              |
| --------- | ------------------------------------------------------------------------ |
| `id`      | Bu teslimata özgü benzersiz bir UUID. Yeniden denemeler sırasında çoğaltmayı önlemek için kullanın. |
| `type`    | Noktalı olay türü, örn. `test_case.updated`.                         |
| `created` | Tuist’in teslimatı kuyruğa aldığı Unix zaman damgası (saniye).           |
| `object`  | Kaynak anlık görüntüsü. Yapısı olay türüne bağlıdır.              |

Her olay türü için kesin yük şeması, [Tuist API referansında](https://tuist.dev/api/docs#section/Webhook-events) **Webhook olayları** altında belgelenmiştir; her olayın `components.schemas` altında eşleşen bir `WebhookXxxEvent` şeması vardır ve bunu bir kod üretecinden `$ref` ile başvurabilirsiniz.

Örneğin bir `test_case.updated` yükü, yazmaya neden olan standart geçişleri listeleyen bir `events` dizisi de taşır (`marked_flaky`, `muted`, `unskipped`, …) ayrıca alıcıların manuel düzenlemeleri otomasyon kaynaklı değişikliklerden ayırt edebilmesi için `actor_id` ve `alert_id` içerir.

Her istek şu HTTP başlıklarını da taşır:

| Başlık              | Açıklama                                                                                   |
| ------------------- | --------------------------------------------------------------------------------------------- |
| `Content-Type`      | Her zaman `application/json`.                                                                    |
| `User-Agent`        | `Tuist-Webhooks/1.0`.                                                                         |
| `Tuist-Event-Id`    | Gövdedeki `id` ile aynı UUID — yükü ayrıştırmadan önce başlıkları günlüğe kaydediyorsanız kullanışlıdır.     |
| `Tuist-Event-Type`  | Gövdedeki `type` ile aynı dize.                                                            |
| `Tuist-Signature`   | HMAC-SHA256 imzası, `t={timestamp},v1={hex_digest}` biçiminde — aşağıya bakın.          |

## Bir webhooke yanıt verme {#responding}

Bir teslimatı onaylamak için uç noktanız herhangi bir `2xx` durum kodu döndürmelidir. `2xx` aralığının dışındaki tüm durumlar — bağlantı hataları ve zaman aşımları dahil — teslimat hatası olarak kabul edilir ve yeniden denenir. Tuist `3xx` yanıtlarını takip etmez, bu nedenle yeniden yönlendirme yerine doğrudan kanonik URL’de yanıt verin.

İşleyicinizi **hızlı** tutun: Tuist, yanıt için en fazla **10 saniye** bekler. Ağır işlemler yapmanız gerekiyorsa (başka bir API çağrısı, veritabanı güncellemesi, bildirim gönderme), isteği kabul edin ve eşzamansız olarak işleyin. Erken yanıt vermek ayrıca aşağı akış hizmetlerinizdeki geçici yavaşlamalara karşı dayanıklılığınızı artırır.

## İmzayı doğrulama {#verify-signature}

Uç nokta URL’nizi öğrenen herkes ona POST isteği gönderebilir. İmzalama gizli anahtarı, sunucunuzun Tuist’ten gelmeyen her şeyi reddetmesini sağlar.

Her istek için Tuist şunu hesaplar:

```
signed_payload = "{timestamp}.{raw_request_body}"
signature      = HMAC-SHA256(signing_secret, signed_payload)
header         = "t={timestamp},v1={hex(signature)}"
```

Kendi tarafınızda doğrulamak için:

1. `Tuist-Signature` başlığını okuyun ve `t=` (zaman damgası) ile `v1=` (hex özeti) parçalarına ayırın.
2. Zaman damgası sunucunuzun geçerli saatinden **5 dakika** fazlaysa isteği reddedin. Bu, yeniden oynatma penceresini *sınırlar* ancak kapatmaz; bunu aşağıdaki idempotens ile birlikte kullanın.
3. `HMAC-SHA256(signing_secret, "{timestamp}.{raw_body}")` değerini yeniden hesaplayın ve özeti **sabit zamanlı** karşılaştırma ile kıyaslayın.
4. Teslimatları yük `id` üzerinden çoğaltmayı önleyin (aynı zamanda `Tuist-Event-Id` başlığı olarak da görünür). Yeniden denemeler arasında sabit kalır, bu nedenle zaten işlediğiniz kimlikleri kalıcı hale getirmek, yakalanan bir isteğin tolerans penceresi içinde yeniden oynatılmasını engeller ve yeniden deneme sırasında çift işlemeye karşı sizi korur.

> [!IMPORTANT] USE THE RAW BODY
> İmza, Tuist’in gönderdiği baytlar üzerinden hesaplanır. Web çerçeveniz doğrulamadan önce JSON’u yeniden ayrıştırır ve yeniden serileştirirse özet eşleşmez. Ham gövdeyi yakalayın (örneğin Rack’te `request.body.read`, Express’te ham `Buffer`) ve doğrulayıcınıza iletin.

Node.js için bir referans doğrulayıcı — aynı dört adımı (başlığı ayrıştırma, zaman damgası sapmasını kontrol etme, HMAC’i yeniden hesaplama, sabit zamanlı karşılaştırma) alıcınızın yazıldığı dile uyarlayın:

```javascript
import crypto from "node:crypto";

function verifyTuistSignature(rawBody, header, secret, toleranceSeconds = 300) {
  const parts = Object.fromEntries(
    header.split(",").map((kv) => kv.split("=", 2))
  );
  const timestamp = Number(parts.t);
  const signature = parts.v1;
  if (!timestamp || !signature) return false;

  const drift = Math.abs(Math.floor(Date.now() / 1000) - timestamp);
  if (drift > toleranceSeconds) return false;

  const expected = crypto
    .createHmac("sha256", secret)
    .update(`${timestamp}.${rawBody}`)
    .digest("hex");

  const a = Buffer.from(expected, "hex");
  const b = Buffer.from(signature, "hex");
  return a.length === b.length && crypto.timingSafeEqual(a, b);
}
```

## Yeniden denemeler {#retries}

Tuist, `2xx` dışı durum döndüren, zaman aşımına uğrayan veya bağlantı kuramayan tüm teslimatları yeniden dener. Zamanlama sabittir:

| Deneme | Göndermeden önce bekleme süresi |
| ------- | ------------------- |
| 1       | (anında)         |
| 2       | 1 dakika            |
| 3       | 5 dakika           |
| 4       | 30 dakika          |
| 5       | 2 saat             |
| 6       | 8 saat             |
| 7       | 24 saat            |

Yedinci deneme başarısız olduktan sonra teslimat kalıcı olarak başarısız olarak işaretlenir. Her deneme, gönderildiği zaman damgasıyla imzalandığından, yeniden oynatma koruma pencereniz yeniden denemelerde de geçerlidir; bunu genişletmeniz gerekmez.

## Teslimatları inceleme {#inspect-deliveries}

Teslimat geçmişini görmek için **Webhooklar** sayfasından bir uç nokta açın. Ayrıntı sayfası şunları gösterir:

- Hedef URL’yi, maskelenmiş imzalama gizli anahtarını, abone olunan olayları ve oluşturulma tarihini içeren bir **özet kartı**.
- Seçilen zaman aralığına göre çalışan toplamları ve hata sayısını gösteren bir **teslimat grafiği**.
- Durum, olay türü veya olay kimliğine göre filtreleyebileceğiniz bir **olay tablosu**.

![Özet kartı ve olay teslimatları grafiğini gösteren bir webhook uç noktası ayrıntı sayfası](/images/guides/integrations/webhooks/endpoint-detail.png)

O zamanki denemenin tam istek ve yanıtını görmek için bir olaya tıklayın — Tuist’in gönderdiği kesin yük, başlıklar, yukarı akış durum kodu ve yanıt gövdesi. Sunucunuzun gördüğü verilerin aynısıdır, bu da imza doğrulama uyumsuzluğunu veya 5xx yukarı akış hatasını debug etmenin en hızlı yoludur.

![Özeti, istek başlıklarını ve gövdesini ile yukarı akış yanıtını gösteren bir webhook olayı ayrıntı sayfası](/images/guides/integrations/webhooks/event-detail.png)

Teslimat kayıtları, bir entegrasyonu debug ederken geriye bakabilmeniz için süresiz olarak saklanır. Aşağı akış sisteminizin kalıcı kopyalara ihtiyacı varsa (örneğin uyumluluk için), teslimatları geldikçe kendi altyapınızda yakalayın.

## Bir uç noktayı döndürme veya silme {#rotate-or-delete}

Her iki eylem de uç nokta satırındaki üç nokta menüsünde ve uç noktanın ayrıntı sayfasında bulunur:

- **Gizli anahtarı döndür** — yeni bir imzalama gizli anahtarı oluşturur ve bir kez gösterir. Mevcut tüketiciler, siz onları güncelleyene kadar doğrulamada başarısız olur, bu nedenle döndürmeyi bir dağıtım ile birlikte planlayın.
- **Uç noktayı sil** — uç noktayı kaldırır ve teslimatı durdurur. Daha önce kaydedilmiş teslimat denemeleri, standart saklama süresi dolana kadar korunur.

## Güvenlik notları {#security}

- Uç nokta URL’leri HTTPS olmalıdır. Tuist, düz metin hedeflere teslimat yapmayı reddeder.
- Tuist, her teslimattan önce hedef ana bilgisayar adını çözer ve loopback, RFC1918, link-local, ULA ve bulut meta veri adreslerini (`169.254.169.254`, `fd00::/8`, …) reddeder. Bu, yanlış yapılandırılmış bir webhook’un Tuist sunucunuzu çalıştıran ana bilgisayarı taramak veya saldırmak için kullanılmasını engeller.
- Uç nokta URL’si ve imzalama gizli anahtarı diskte şifrelenir. Taşıyıcı kimlik bilgileri oldukları için GDPR/CCPA veri dışa aktarmalarından hariç tutulurlar.
- İmzalama gizli anahtarı yalnızca bir kez gösterilir. Bir parola gibi ele alın: depo yerine gizli yöneticinize kaydedin.
