---
{
  "title": "Slack",
  "titleTemplate": ":title | Entegrasyonlar | Kılavuzlar | Tuist",
  "description": "Slack için Tuist entegrasyonunun nasıl kullanılacağını öğrenin."
}
---
# Slack için Tuist entegrasyonu {#slack}

Tuist'in Slack entegrasyonu, derleme, test ve paket analizlerini doğrudan kanallarınıza taşır. İzlemeyi ekibinizin hatırlaması gereken bir görev olmaktan çıkarıp otomatik hale getirir. Örneğin, ekibiniz derleme performansı, önbellek isabeti oranları veya paket boyutu trendleri hakkında günlük özetler alabilir; önemli bir metrik gerilediğinde veya bir test kararsız hale geldiğinde anında uyarılar alabilir.

Bu sayfa, entegrasyonun ne yaptığını, kanal bazında nasıl kurulacağını ve Tuist'in verilerinizi nasıl işlediğini açıklar. Tuist'in üçüncü taraf verileri nasıl topladığı, yönettiği ve sakladığıyla ilgili ayrıntılar için [gizlilik politikamıza](https://tuist.dev/privacy) bakın.

## Entegrasyon nasıl çalışır {#how-it-works}

Tuist, Slack'e Slack'in [Gelen Web Kancaları](https://docs.slack.dev/messaging/sending-messages-using-incoming-webhooks) aracılığıyla bildirim gönderir. Entegrasyon yalnızca `incoming-webhook` kapsamını ister. Her bildirim hedefi (proje raporu, uyarı kuralı, kararsız test uyarısı, otomasyon eylemi) kurulum sırasında seçtiğiniz tek bir Slack kanalına karşılık gelir. Slack, her kanal için bir web kancası URL'si oluşturur ve Tuist mesajları iletmek üzere bunu saklar.

Tuist çalışma alanınızdan mesajları, üye listelerini veya başka herhangi bir veriyi asla okumaz. Entegrasyon yalnızca açıkça yetkilendirdiğiniz kanallara bildirim yazar.

## Kurulum {#setup}

### Proje raporları {#project-reports}

Proje raporları, projenizin derleme, test ve önbellek metriklerinin günlük özetini seçtiğiniz bir Slack kanalına iletir.

1. Tuist panosunda projenizin bildirim ayarlarını açın.
2. **Slack kanalı seç** düğmesine tıklayın ve Tuist'in gönderim yapmasını istediğiniz çalışma alanını ve kanalı seçin. Slack, `incoming-webhook` kapsamını yetkilendirmenizi ve tek bir kanal seçmenizi isteyecektir.
3. Günlük raporun gelmesini istediğiniz haftanın günlerini ve saatini seçin.

![Slack rapor yapılandırmasıyla bildirim ayarlarını gösteren bir görsel](/images/guides/integrations/slack/notifications-settings.png)

Yapılandırıldıktan sonra Tuist, seçilen kanala otomatik günlük raporlar gönderir:

<img src="/images/guides/integrations/slack/report.png" alt="Bir Slack rapor mesajını gösteren bir görsel" style="max-width: 500px;" />

> [!NOTE] PRIVATE CHANNELS
> <!-- -->
> Özel bir kanala gönderim yapmak için önce Slack içinde kanalı açın ve yetkilendirme adımı sırasında entegrasyonun görebileceği kanal listesine ekleyin.
> <!-- -->

### Uyarı kuralları {#alert-rules}

Uyarı kuralları, önemli metrikler önemli ölçüde gerilediğinde sizi Slack üzerinden bilgilendirir; böylece yavaşlayan derlemeleri, önbellek bozulmalarını veya test yavaşlamalarını mümkün olan en kısa sürede fark edebilirsiniz.

Bir uyarı kuralı oluşturmak için projenizin bildirim ayarlarına gidin ve **Uyarı kuralı ekle** düğmesine tıklayın. Şunları yapılandırabilirsiniz:

- **Ad**: Uyarı için açıklayıcı bir ad
- **Kategori**: Ne ölçüleceği (derleme süresi, test süresi, önbellek isabeti oranı veya paket boyutu)
- **Metrik**: Verilerin nasıl toplanacağı (p50, p90, p99 veya ortalama)
- **Sapma**: Bir uyarıyı tetikleyen yüzde değişimi
- **Kayan pencere**: Karşılaştırılacak son çalışma sayısı
- **Dal**: Önbellek isabeti oranı uyarıları için karşılaştırmayı tek bir dal üzerindeki çalışmalara kısıtlayın. Her dalı dikkate almak için boş bırakın. Paket boyutu uyarıları her zaman tek bir dalı hedefler.
- **Slack kanalı**: Hedef kanal. Kanalı, yukarıda açıklanan aynı `incoming-webhook` akışı üzerinden yetkilendirirsiniz.

Örneğin, p90 derleme süresinin önceki 100 derlemeye kıyasla %20'den fazla arttığında tetiklenen bir uyarı oluşturabilirsiniz.

Önbellek isabeti oranı uyarısını varsayılan dalınıza kapsamak, yalnızca o dal önbelleği doldurduğunda yararlıdır. Düşük seviyeli bir modüle dokunan çekme isteği dalları önbelleği meşru biçimde ıskalar ve bunları dahil etmek uyarının beklenen gerilemelerde tetiklenmesine neden olur.

Önbellek isabeti oranı uyarısı yalnızca adilce karşılaştırabileceği pencereleri karşılaştırır. Her iki pencerenin de kayan pencere boyutu kadar çalışma içermesi gerekir ve iki pencereden yalnızca birinde görünen bir önbellek veri kaynağı her ikisinden de hariç tutulur. Henüz kayan pencere boyutunun iki katı kadar çalışma biriktirmemiş bir dal veya hiçbir şeyle eşleşmeyen bir dal adı bu nedenle kuralı asla tetiklemez. Bir kuralı düşük trafikli bir dala kısıtlarsanız, dalın pencereyi doldurabilmesi için kayan pencereyi yeterince küçük tutun.

Bir uyarı tetiklendiğinde, Slack kanalınızda buna benzer bir mesaj alırsınız:

<img src="/images/guides/integrations/slack/alert.png" alt="Bir Slack uyarı mesajını gösteren bir görsel" style="max-width: 500px;" />

> [!NOTE] COOLDOWN PERIOD
> <!-- -->
> Bir uyarı tetiklendikten sonra, aynı kural için 24 saat boyunca tekrar tetiklenmez. Bu, bir metrik yükselmiş durumda kaldığında bildirim yorgunluğunu önler.
> <!-- -->

### Kararsız test uyarıları {#flaky-test-alerts}

Kararsız test uyarıları, Tuist yeni bir kararsız test algıladığı anda tetiklenir; böylece test dengesizliğini ekibinizi etkilemeden önce yakalamanıza yardımcı olur.

Bir kararsız test uyarı kuralı oluşturmak için projenizin bildirim ayarlarına gidin ve **Kararsız test uyarı kuralı ekle** düğmesine tıklayın. Şunları yapılandırabilirsiniz:

- **Ad**: Uyarı için açıklayıcı bir ad
- **Tetikleme eşiği**: Bir uyarıyı tetiklemek için gereken son 30 gündeki minimum kararsız çalışma sayısı
- **Slack kanalı**: Hedef kanal, `incoming-webhook` akışı üzerinden yetkilendirilir.

Bir test kararsız hale geldiğinde ve eşik değerinizi karşıladığında, test senaryosunu incelemek için doğrudan bağlantı içeren bir bildirim alırsınız:

<img src="/images/guides/integrations/slack/flaky-test-alert.png" alt="Bir Slack kararsız test uyarı mesajını gösteren bir görsel" style="max-width: 500px;" />

## Entegrasyonu kesme {#disconnect}

Bir bildirimi durdurmak için Tuist panonuzda rapordan, uyarı kuralından veya otomasyon eyleminden yapılandırılmış Slack kanalını kaldırın. Tuist’in erişimini tamamen iptal etmek için Slack içinde **Ayarlar ve yönetim → Uygulamaları yönet** yoluyla webhook entegrasyonunu kaldırın.
