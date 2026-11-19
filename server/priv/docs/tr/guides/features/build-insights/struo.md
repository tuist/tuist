---
{
  "title": "Struo Derleme İçgörüleri",
  "titleTemplate": ":title · Derleme İçgörüleri · Özellikler · Kılavuzlar · Tuist",
  "description": "Struo çalıştırmalarını canlı olarak izleyin ve Tuist panosunda eylemleri, süreleri, hataları ve önbellek kararlarını inceleyin."
}
---
# Struo derleme içgörüleri {#struo-build-insights}

<a id="once-build-insights"></a>

Struo, çalışmaları yürütülürken Tuist’e akıtarak son CI günlüğünü beklemeden ilerlemeyi takip etmenizi sağlar. Grafiğini, eylem durumunu ve önbellek kararlarını incelemek için bir çalışmanın başında yazdırılan pano bağlantısını açın.

> [!IMPORTANT]
> **Gereksinimler**
>
> - <.localized_link href="/guides/get-started/struo-project">Struo ile başlayın</.localized_link> kılavuzunu tamamlayın ve Struo’yu çalıştıran makineyi kimlik doğrulayın.

## Derlemelerinizi bildirin {#report-your-builds}

Struo komutlarınızı kullanmaya devam edin:

```bash
struo build MyApplication
```

Canlı raporlama en iyi çaba esasına dayanır. Raporlama uç noktasının kullanılamıyor olması veya oturumun süresinin dolması derlemeyi başarısız kılmaz. Oturumun süresi dolarsa `struo auth login --provider tuist` ile yeniden giriş yapın.

## Panoda neler gösterilir {#what-the-dashboard-shows}

Çalışmaları zaman, dallar ve yerel veya CI ortamları arasında karşılaştırmak için **Derlemeler** ve **Derleme Çalıştırmaları** bölümlerini kullanın. Her çalıştırma şunları içerebilir:

- İstenen komut, durum, başlangıç zamanı ve süre.
- Struo sürümü ve bildirilen ana bilgisayar bilgileri.
- Eylemler ve bağımlılıkları, durumu, süresi ve önbellek sonuçları.
- Bildirilen eylem hataları.
- İstemci tarafından bildirildiğinde Git dalı, commit ve CI bağlamı.

Başarısız veya yavaş işleri bulmak için eylemleri arayın ve filtreleyin. Bildirilen eylem adları ve kaynak dosyalar, işin kodla ilişkisini kurmanıza yardımcı olur; eski istemciler daha az ayrıntı sağlayabilir. Önbelleğe alınmış veya atlanan eylemler yürütülen iş değildir ve eksik zamanlama sıfır süreli bir yürütme anlamına gelmez.

Tuist şu anda Struo’nun ham eylem günlük akışını almıyor. Tam süreç çıktısı için CI günlüklerini saklayın; çalıştırma özetleri ve yapılandırılmış hatalar bu günlüklerin yerine geçmez.

**Önbellek** görünümü, eylem kararlarını içerik nesnesi aktarımlarından ayırır. Önbellek etkinliğini yorumlamak için <.localized_link href="/guides/features/cache/struo">Struo önbelleği</.localized_link> bölümüne bakın.

## Testler {#tests}

Test komutları da Struo çalıştırmaları üretir. Bildirilen test paketleri ve test senaryoları **Testler** altında görünür; barındırılan shard’lar ek olarak birleştirilmiş bir test çalıştırması yayımlar. <.localized_link href="/guides/features/test-insights/struo">Struo test içgörüleri</.localized_link> bölümüne bakın.

## Kodlama ajanları ve Grafana {#coding-agents-and-grafana}

<.localized_link href="/guides/features/agentic-coding/mcp#struo-runs">Model Context Protocol araçları</.localized_link>, bir ajanın Struo çalıştırmalarını listelemesine ve bir çalıştırmanın eylem ve önbellek toplamlarını okumasına olanak tanır. Aynı okuma işlemleri HTTP API üzerinden de kullanılabilir.

Nihai Struo derleme sağlığı metrikleri için <.localized_link href="/guides/integrations/grafana">Grafana entegrasyonu</.localized_link>nu kullanın. Struo şu anda geçen önbellek zamanı tasarrufunu raporlamadığından, bu ölçüm sıfır yerine kullanılamaz durumda kalır.
