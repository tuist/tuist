---
{
  "title": "Once Derleme İçgörüler",
  "titleTemplate": ":title · Derleme İçgörüler · Özellikler · Kılavuzlar · Tuist",
  "description": "Tuist kontrol panelinde Once çalıştırma kayıtlarını canlı olarak izleyin; eylemleri, süreleri, hataları ve önbellek kararlarını inceleyin."
}
---
# Once derleme içgörüleri {#once-build-insights}

Once, çalıştırmalar yürütülürken bunları Tuist'e aktarır; böylece son CI günlüğünü beklemeden ilerlemeyi takip edebilirsiniz. Bir çalıştırmanın başında yazdırılan kontrol paneli bağlantısını açarak grafiğini, eylem durumunu ve önbellek kararlarını inceleyin.

> [!IMPORTANT]
> **Gereksinimler**
>
> - <.localized_link href="/guides/get-started/once-project">Once ile başlayın</.localized_link> kılavuzunu tamamlayın ve Once'ı çalıştıran makineyi kimlik doğrulamasından geçirin.

## Derlemelerinizi bildirin {#report-your-builds}

Once komutlarınızı kullanmaya devam edin:

```bash
once build MyApplication
```

Canlı raporlama en iyi çaba esasına dayanır. Raporlama uç noktasının kullanılamaz olması veya oturumun süresinin dolması derlemeyi başarısız kılmaz. Oturum süresi dolduğunda `once auth login --provider tuist` ile yeniden giriş yapın.

## Kontrol panelinde gösterilenler {#what-the-dashboard-shows}

Çalıştırmaları zaman, dallar ve yerel veya CI ortamları arasında karşılaştırmak için **Derlemeler** ve **Derleme Çalıştırmaları** bölümlerini kullanın. Her çalıştırma şunları içerebilir:

- İstenen komut, durum, başlangıç zamanı ve süre.
- Once sürümü ve bildirilen ana bilgisayar bilgileri.
- Eylemler ve bağımlılıkları, durumları, süreleri ve önbellek sonuçları.
- Bildirilen eylem hataları.
- İstemci tarafından bildirildiğinde Git dalı, commit ve CI bağlamı.

Başarısız veya yavaş işleri bulmak için eylemleri arayın ve filtreleyin. Bildirilen eylem adları ve kaynak dosyalar, işi kodla ilişkilendirmeye yardımcı olur; eski istemciler daha az ayrıntı sağlayabilir. Önbelleğe alınmış veya atlanan eylemler yürütülen iş değildir ve eksik zamanlama bilgisi sıfır süreli bir yürütme anlamına gelmez.

Tuist şu anda Once'ın ham eylem günlük akışını almamaktadır. Tam süreç çıktısı için CI günlüklerini saklayın; çalıştırma özetleri ve yapılandırılmış hatalar bu günlüklerin yerine geçmez.

**Önbellek** görünümü, eylem kararlarını içerik nesnesi aktarımlarından ayırır. Önbellek etkinliğini yorumlamak için <.localized_link href="/guides/features/cache/once">Once önbelleği</.localized_link> bölümüne bakın.

## Testler {#tests}

Test komutları da Once çalıştırmaları üretir. Bildirilen test paketleri ve test durumları **Testler** altında görünür; barındırılan shard'lar ek olarak birleştirilmiş bir test çalıştırması yayımlar. <.localized_link href="/guides/features/test-insights/once">Once test içgörüleri</.localized_link> bölümüne bakın.

## Kodlama ajanları ve Grafana {#coding-agents-and-grafana}

<.localized_link href="/guides/features/agentic-coding/mcp#once-runs">Model Context Protocol araçları</.localized_link>, bir ajanın Once çalıştırmalarını listelemesini ve bir çalıştırmanın eylem ve önbellek toplamlarını okumasını sağlar. Aynı okuma işlemleri HTTP API üzerinden de kullanılabilir.

Nihai Once derleme sağlığı metrikleri için <.localized_link href="/guides/integrations/grafana">Grafana entegrasyonu</.localized_link>nu kullanın. Once şu anda geçen önbellek zamanı tasarrufunu bildirmemektedir; bu nedenle bu ölçüm sıfır olarak değil, kullanılamaz olarak kalır.
