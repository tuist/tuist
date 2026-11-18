---
{
  "title": "Slack",
  "titleTemplate": ":title | Entegrasyonlar | Kılavuzlar | Tuist",
  "description": "Tuist Slack entegrasyonunun nasıl kullanılacağını öğrenin."
}
---
# Slack için Tuist entegrasyonu {#slack}

Slack için Tuist entegrasyonu, derleme, test ve paket analizlerini doğrudan kanallarınıza taşır. İzlemeyi ekibinizin hatırlaması gereken bir işten, otomatik olarak gerçekleşen bir sürece dönüştürür. Örneğin, ekibiniz derleme performansı, önbellek isabeti oranları veya paket boyutu trendleri hakkında günlük özetler alabilir ve önemli bir metrik gerilediğinde ya da bir test kararsız hale geldiğinde anında uyarılar alabilir.

Bu sayfa, entegrasyonun ne yaptığını, kanal bazında nasıl kurulacağını ve Tuist’in verilerinizi nasıl işlediğini açıklar. Tuist’in üçüncü taraf verileri nasıl topladığı, yönettiği ve sakladığıyla ilgili ayrıntılar için [gizlilik politikamıza](https://tuist.dev/privacy) bakın.

## Entegrasyon nasıl çalışır {#how-it-works}

Tuist, Slack’e bildirimleri Slack’in [Gelen Web Kancaları](https://docs.slack.dev/messaging/sending-messages-using-incoming-webhooks) aracılığıyla gönderir. Entegrasyon yalnızca `incoming-webhook` kapsamını ister. Her bildirim hedefi (proje raporu, uyarı kuralı, kararsız test uyarısı, otomasyon eylemi) kurulum sırasında seçtiğiniz tek bir Slack kanalına karşılık gelir. Slack kanal başına bir web kancası URL’si oluşturur ve Tuist mesajları iletmek için bu URL’yi saklar.

Tuist çalışma alanınızdan mesajları, üye listelerini veya başka herhangi bir veriyi asla okumaz. Entegrasyon yalnızca açıkça yetkilendirdiğiniz kanallara bildirim yazar.

## Kurulum {#setup}

### Proje raporları {#project-reports}

Proje raporları, projenizin derleme, test ve önbellek metriklerinin günlük özetini seçtiğiniz bir Slack kanalına iletir.

1. Tuist panosunda projenizin bildirim ayarlarını açın.
2. **Slack kanalı seç** düğmesine tıklayın ve Tuist’in gönderim yapmasını istediğiniz çalışma alanını ve kanalı seçin. Slack, `incoming-webhook` kapsamını yetkilendirmenizi ve tek bir kanal seçmenizi isteyecektir.
3. Günlük raporun gelmesini istediğiniz haftanın günlerini ve günün saatini seçin.

![Slack rapor yapılandırmasıyla birlikte bildirim ayarlarını gösteren bir görsel](/images/guides/integrations/slack/notifications-settings.png)

Yapılandırıldıktan sonra Tuist, seçilen kanala otomatik günlük raporlar gönderir:

<img src="/images/guides/integrations/slack/report.png" alt="Bir Slack rapor mesajını gösteren bir görsel" style="max-width: 500px;" />

> [!NOTE] PRIVATE CHANNELS
> <!-- -->
> Özel bir kanala gönderim yapmak için önce Slack içinde kanalı açın ve yetkilendirme adımında entegrasyonun görebileceği kanal listesine ekleyin.
> <!-- -->

### Uyarı kuralları {#alert-rules}

Uyarı kuralları, önemli metrikler önemli ölçüde gerilediğinde sizi Slack üzerinden bilgilendirir; böylece yavaşlayan derlemeleri, önbellek bozulmasını veya test yavaşlamalarını mümkün olan en kısa sürede fark edebilirsiniz.

Bir uyarı kuralı oluşturmak için projenizin bildirim ayarlarına gidin ve **Uyarı kuralı ekle** düğmesine tıklayın. Şunları yapılandırabilirsiniz:

- **Ad**: Uyarı için açıklayıcı bir ad
- **Kategori**: Ne ölçülecek (derleme süresi, test süresi, önbellek isabeti oranı veya paket boyutu)
- **Metrik**: Veriler nasıl toplanacak (p50, p90, p99 veya ortalama)
- **Sapma**: Bir uyarıyı tetikleyen yüzde değişimi
- **Kayan pencere**: Karşılaştırma için kaç son çalışmanın dikkate alınacağı
- **Dal**: Önbellek isabeti oranı uyarıları için karşılaştırmayı tek bir dal üzerindeki çalışmalara sınırlayın. Tüm dalları dikkate almak için boş bırakın. Paket boyutu uyarıları her zaman tek bir dalı hedefler.
- **Slack kanalı**: Hedef kanal. Kanalı, yukarıda açıklanan aynı `incoming-webhook` akışı üzerinden yetkilendirirsiniz.

Örneğin, p90 derleme süresinin önceki 100 derlemeye kıyasla %20’den fazla arttığında tetiklenen bir uyarı oluşturabilirsiniz.

Önbellek isabeti oranı uyarısını varsayılan dalınızla sınırlamak, yalnızca o dalın önbelleği doldurduğu durumlarda yararlıdır. Düşük seviyeli bir modüle dokunan çekme isteği dalları önbelleği meşru şekilde ıskalar ve bunları dahil etmek uyarının beklenen gerilemelerde tetiklenmesine neden olur.

Önbellek isabeti oranı uyarısı yalnızca adil bir şekilde karşılaştırabileceği pencereleri karşılaştırır. Her iki pencerenin de kayan pencere boyutu kadar çalışmayı içermesi gerekir ve iki pencereden yalnızca birinde görünen bir önbellek veri kaynağı her ikisinden de çıkarılır. Henüz kayan pencere boyutunun iki katı kadar çalışmayı biriktirmemiş bir dal veya hiçbir şeyle eşleşmeyen bir dal adı bu nedenle kuralı asla tetiklemez. Bir kuralı düşük trafikli bir dal için sınırlandırıyorsanız, dalın pencereyi doldurabilmesi için kayan pencereyi yeterince küçük tutun.

Bir uyarı tetiklendiğinde, Slack kanalınızda buna benzer bir mesaj alırsınız:

<img src="/images/guides/integrations/slack/alert.png" alt="Bir Slack uyarı mesajını gösteren bir görsel" style="max-width: 500px;" />

> [!NOTE] COOLDOWN PERIOD
> <!-- -->
> Bir uyarı tetiklendikten sonra, aynı kural için 24 saat boyunca tekrar tetiklenmez. Bu, bir metrik yükselmiş durumda kaldığında bildirim yorgunluğunu önler.
> <!-- -->

### Kararsız test uyarıları {#flaky-test-alerts}

Kararsız test uyarıları, Tuist yeni bir kararsız test algıladığı anda tetiklenir ve bu durum ekibinizi etkilemeden önce test dengesizliğini fark etmenize yardımcı olur.

Bir kararsız test uyarı kuralı oluşturmak için projenizin bildirim ayarlarına gidin ve **Kararsız test uyarı kuralı ekle** düğmesine tıklayın. Şunları yapılandırabilirsiniz:

- **Ad**: Uyarı için açıklayıcı bir ad
- **Tetik eşiği**: Bir uyarıyı tetiklemek için gereken son 30 gündeki minimum kararsız çalışma sayısı
- **Slack kanalı**: `incoming-webhook` akışı üzerinden yetkilendirilen hedef kanal.

Bir test kararsız hale geldiğinde ve eşikinizi karşıladığında, test senaryosunu incelemek için doğrudan bir bağlantı içeren bir bildirim alırsınız:

<img src="/images/guides/integrations/slack/flaky-test-alert.png" alt="Bir Slack kararsız test uyarı mesajını gösteren bir görsel" style="max-width: 500px;" />

## Entegrasyonu ayırma {#disconnect}

Bir bildirimi durdurmak için, Tuist kontrol panelinizdeki rapordan, uyarı kuralından veya otomasyon eyleminden yapılandırılmış Slack kanalını kaldırın. Tuist’in erişimini tamamen iptal etmek için, Slack içindeki **Ayarlar ve yönetim → Uygulamaları yönet** yoluyla webhook entegrasyonunu kaldırın.
