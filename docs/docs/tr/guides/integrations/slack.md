---
{
  "title": "Slack",
  "titleTemplate": ":title | Integrations | Guides | Tuist",
  "description": "Learn how to integrate Tuist with Slack."
}
---
# Slack entegrasyonu {#slack}

Kuruluşunuz Slack kullanıyorsa, içgörüleri doğrudan kanallarınızda ortaya
çıkarmak için Tuist'i entegre edebilirsiniz. Bu, izlemeyi ekibinizin yapmayı
hatırlaması gereken bir şeyden, sadece gerçekleşen bir şeye dönüştürür. Örneğin,
ekibiniz derleme performansı, önbellek isabet oranları veya paket boyutu
eğilimlerinin günlük özetlerini alabilir.

## Kurulum {#setup}

### Slack çalışma alanınızı bağlayın {#connect-workspace}

İlk olarak, Slack çalışma alanınızı `Integrations` sekmesinden Tuist hesabınıza
bağlayın:

![Slack bağlantısı ile entegrasyonlar sekmesini gösteren bir
görüntü](/images/guides/integrations/slack/integrations.png)

Çalışma alanınıza mesaj göndermek üzere Tuist'i yetkilendirmek için **Connect
Slack** adresine tıklayın. Bu sizi Slack'in bağlantıyı onaylayabileceğiniz
yetkilendirme sayfasına yönlendirecektir.

> [!NOT] SLACK YÖNETİCİ ONAYI Slack çalışma alanınız uygulama yüklemelerini
> kısıtlıyorsa, bir Slack yöneticisinden onay istemeniz gerekebilir. Slack,
> yetkilendirme sırasında onay talebi sürecinde size rehberlik edecektir.

### Proje raporları {#project-reports}

After connecting Slack, configure reports for each project in the project
settings' notifications tab:

![An image that shows the notifications settings with Slack report
configuration](/images/guides/integrations/slack/notifications-settings.png)

Yapılandırabilirsiniz:
- **Kanal**: Raporları hangi Slack kanalının alacağını seçin
- **Zamanlama**: Haftanın hangi günlerinde rapor alacağınızı seçin
- **Saat**: Günün saatini ayarlayın

Tuist, yapılandırıldıktan sonra seçtiğiniz Slack kanalına otomatik günlük
raporlar gönderir:

<img src="/images/guides/integrations/slack/report.png" alt="An image that shows a Slack report message" style="max-width: 500px;" />

### Alert rules {#alert-rules}

Get notified in Slack with alert rules when key metrics significantly regress to
help you catch slower builds, cache degradation, or test slowdowns as soon as
possible, minimizing the impact on your team's productivity.

To create an alert rule, go to your project's notification settings and click
**Add alert rule**:

Yapılandırabilirsiniz:
- **Name**: A descriptive name for the alert
- **Category**: What to measure (build duration, test duration, or cache hit
  rate)
- **Metric**: How to aggregate the data (p50, p90, p99, or average)
- **Deviation**: The percentage change that triggers an alert
- **Rolling window**: How many recent runs to compare against
- **Slack channel**: Where to send the alert

For example, you might create an alert that triggers when the p90 build duration
increases by more than 20% compared to the previous 100 builds.

When an alert triggers, you'll receive a message like this in your Slack
channel:

<img src="/images/guides/integrations/slack/alert.png" alt="An image that shows a Slack alert message" style="max-width: 500px;" />

> [!NOTE] COOLDOWN PERIOD After an alert triggers, it won't fire again for the
> same rule for 24 hours. This prevents notification fatigue when a metric stays
> elevated.

## Şirket içi kurulumlar {#on-premise}

Şirket içi Tuist kurulumları için kendi Slack uygulamanızı oluşturmanız ve
gerekli ortam değişkenlerini yapılandırmanız gerekir.

### Bir Slack uygulaması oluşturun {#create-slack-app}

1. Slack API Uygulamaları sayfasına](https://api.slack.com/apps) gidin ve **Yeni
   Uygulama Oluştur'a tıklayın**
2. **Bir uygulama bildiriminden** öğesini seçin ve uygulamayı yüklemek
   istediğiniz çalışma alanını seçin
3. Yönlendirme URL'sini Tuist sunucu URL'si ile değiştirerek aşağıdaki bildirimi
   yapıştırın:

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

4. Uygulamayı gözden geçirin ve oluşturun

### Ortam değişkenlerini yapılandırma {#configure-environment}

Tuist sunucunuzda aşağıdaki ortam değişkenlerini ayarlayın:

- `SLACK_CLIENT_ID` - Slack uygulamanızın Temel Bilgiler sayfasındaki İstemci
  Kimliği
- `SLACK_CLIENT_SECRET` - Slack uygulamanızın Temel Bilgiler sayfasındaki
  İstemci Sırrı
