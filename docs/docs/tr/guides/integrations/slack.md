---
{
  "title": "Slack",
  "titleTemplate": ":title | Integrations | Guides | Tuist",
  "description": "Learn how to integrate Tuist with Slack."
}
---
# Slack entegrasyonu {#slack}

Kuruluşunuz Slack kullanıyorsa, Tuist'i entegre ederek kanallarınızda doğrudan
içgörüler elde edebilirsiniz. Böylece, izleme ekibinizin hatırlaması gereken bir
şey olmaktan çıkıp, kendiliğinden gerçekleşen bir şey haline gelir. Örneğin,
ekibiniz günlük olarak derleme performansı, önbellek isabet oranları veya paket
boyutu eğilimleri hakkında özetler alabilir.

## Kurulum {#setup}

### Slack çalışma alanınızı bağlayın {#connect-workspace}

İlk olarak, Slack çalışma alanınızı `Entegrasyonlar` sekmesinden Tuist
hesabınıza bağlayın:

![Slack bağlantısı ile entegrasyonlar sekmesini gösteren bir
resim](/images/guides/integrations/slack/integrations.png)

**'ı tıklayın Slack** 'u bağlayarak Tuist'in çalışma alanınıza mesaj
göndermesine izin verin. Bu sizi bağlantıyı onaylayabileceğiniz Slack'in
yetkilendirme sayfasına yönlendirecektir.

> [!NOT] SLACK YÖNETİCİSİNİN ONAYI
> <!-- -->
> Slack çalışma alanınız uygulama yüklemelerini kısıtlıyorsa, Slack
> yöneticisinden onay almanız gerekebilir. Slack, yetkilendirme sırasında onay
> talebi sürecinde size rehberlik edecektir.
> <!-- -->

### Proje raporları {#project-reports}

Slack'i bağladıktan sonra, proje ayarlarının bildirimler sekmesinde her proje
için raporları yapılandırın:

![Slack rapor yapılandırmasıyla bildirim ayarlarını gösteren bir
resim](/images/guides/integrations/slack/notifications-settings.png)

Aşağıdakileri yapılandırabilirsiniz:
- **Kanal**: Raporları hangi Slack kanalının alacağını seçin.
- ****'ı planlayın: Raporları almak istediğiniz günleri seçin
- **Saat**: Günün saatini ayarlayın

> [!UYARI] ÖZEL KANALLAR
> <!-- -->
> Tuist Slack uygulamasının özel bir kanalda mesaj gönderebilmesi için, önce
> Tuist botunu o kanala eklemeniz gerekir. Slack'te özel kanalı açın, kanal
> adını tıklayarak ayarları açın, "Entegrasyonlar"ı seçin, ardından "Uygulama
> ekle"yi seçin ve Tuist'i arayın.
> <!-- -->

Yapılandırıldıktan sonra, Tuist seçtiğiniz Slack kanalına otomatik günlük
raporlar gönderir:

<img src="/images/guides/integrations/slack/report.png" alt="An image that shows a Slack report message" style="max-width: 500px;" />

### Uyarı kuralları {#alert-rules}

Önemli metrikler önemli ölçüde gerilediğinde Slack'te uyarı kuralları ile
bildirim alın, böylece yavaşlamış derlemeleri, önbellek bozulmalarını veya test
yavaşlamalarını mümkün olan en kısa sürede yakalayabilir ve ekibinizin
üretkenliği üzerindeki etkiyi en aza indirebilirsiniz.

Uyarı kuralı oluşturmak için projenizin bildirim ayarlarına gidin ve " **"
(Uyarı kuralı ekle) seçeneğine tıklayın.**:

Aşağıdakileri yapılandırabilirsiniz:
- ****'ın adı: Uyarı için açıklayıcı bir ad
- **Kategori**: Ne ölçülmeli (yapım süresi, test süresi veya önbellek isabet
  oranı)
- **Metrik**: Verilerin nasıl toplanacağı (p50, p90, p99 veya ortalama)
- **Sapma**: Uyarıyı tetikleyen yüzde değişim
- **Yuvarlanan pencere**: Karşılaştırılacak son kaç çalıştırma
- **Slack kanalı**: Uyarıyı nereye göndereceksiniz?

Örneğin, p90 derleme süresi önceki 100 derlemeye kıyasla %20'den fazla
arttığında tetiklenen bir uyarı oluşturabilirsiniz.

Bir uyarı tetiklendiğinde, Slack kanalınızda aşağıdaki gibi bir mesaj alırsınız:

<img src="/images/guides/integrations/slack/alert.png" alt="An image that shows a Slack alert message" style="max-width: 500px;" />

> [!NOT] BEKLEME SÜRESİ
> <!-- -->
> Bir uyarı tetiklendikten sonra, aynı kural için 24 saat boyunca tekrar
> tetiklenmez. Bu, bir metrik yüksek kaldığında bildirim yorgunluğunu önler.
> <!-- -->

### Kararsız test uyarıları {#flaky-test-alerts}

Testin dengesiz hale geldiğinde anında bildirim alın. Dönen pencereleri
karşılaştıran metrik tabanlı uyarı kurallarından farklı olarak, dengesiz test
uyarıları Tuist yeni bir dengesiz test algıladığı anda tetiklenir ve testin
dengesizliği ekibinizi etkilemeden önce fark etmenize yardımcı olur.

Flaky test uyarı kuralı oluşturmak için projenizin bildirim ayarlarına gidin ve
" **" (Flaky test uyarı kuralı ekle) seçeneğine tıklayın. Flaky test uyarı
kuralı ekleyin**:

Aşağıdakileri yapılandırabilirsiniz:
- ****'ın adı: Uyarı için açıklayıcı bir ad
- **Tetikleme eşiği**: Son 30 gün içinde bir uyarıyı tetiklemek için gereken
  minimum hatalı çalışma sayısı
- **Slack kanalı**: Uyarıyı nereye göndereceksiniz?

Bir test dengesiz hale gelip eşiğinizi aşarsa, test durumunu incelemek için
doğrudan bağlantı içeren bir bildirim alırsınız:

<img src="/images/guides/integrations/slack/flaky-test-alert.png" alt="An image that shows a Slack flaky test alert message" style="max-width: 500px;" />

## Yerinde kurulumlar {#on-premise}

Yerinde Tuist kurulumları için, kendi Slack uygulamanızı oluşturmanız ve gerekli
ortam değişkenlerini yapılandırmanız gerekir.

### Slack uygulaması oluşturun {#create-slack-app}

1. [Slack API Uygulamaları sayfasına](https://api.slack.com/apps) gidin ve
   **Yeni Uygulama Oluştur'u tıklayın.**
2. **'ı seçin Uygulama manifestosundan** ve uygulamayı yüklemek istediğiniz
   çalışma alanını seçin
3. Aşağıdaki manifestoyu yapıştırın ve yönlendirme URL'sini Tuist sunucu
   URL'nizle değiştirin:

```json
{
    "display_information": {
        "name": "Tuist",
        "description": "Get regular updates and alerts for your builds, tests, and caching.",
        "background_color": "#6f2cff"
    },
    "features": {
        "bot_user": {
            "display_name": "Tuist",
            "always_online": false
        }
    },
    "oauth_config": {
        "redirect_urls": [
            "https://your-tuist-server.com/integrations/slack/callback"
        ],
        "scopes": {
            "bot": [
                "chat:write",
                "chat:write.public"
            ]
        }
    },
    "settings": {
        "org_deploy_enabled": false,
        "socket_mode_enabled": false,
        "token_rotation_enabled": false
    }
}
```

4. Uygulamayı inceleyin ve oluşturun

### Ortam değişkenlerini yapılandırın {#configure-environment}

Tuist sunucunuzda aşağıdaki ortam değişkenlerini ayarlayın:

- `SLACK_CLIENT_ID` - Slack uygulamanızın Temel Bilgiler sayfasındaki İstemci
  Kimliği
- `SLACK_CLIENT_SECRET` - Slack uygulamanızın Temel Bilgiler sayfasındaki
  Müşteri Gizli Anahtarı
