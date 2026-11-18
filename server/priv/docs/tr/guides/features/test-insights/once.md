---
{
  "title": "Once Test İçgörüler",
  "titleTemplate": ":title · Test İçgörüler · Özellikler · Kılavuzlar · Tuist",
  "description": "Tuist kontrol panelinde Once test paketlerini, tekil sonuçları, hataları ve süreleri inceleyin."
}
---
# Once test içgörüleri {#once-test-insights}

Once, test sonuçlarını Tuist'e bildirir; böylece test paketinizi yerel ve CI çalıştırmaları arasında takip edebilir, hataları inceleyebilir ve tekil çalışanlardan rapor toplamadan yavaş testleri bulabilirsiniz.

> [!IMPORTANT]
> **Gereksinimler**
>
> - <.localized_link href="/guides/get-started/once-project">Once ile başlayın</.localized_link> kılavuzunu tamamlayın.
> - Yapılandırılmış sonuçlar bildiren test hedeflerini kullanın. Sunulan ayrıntı düzeyi, hedef türüne ve test çalıştırıcısına bağlıdır.

## Test çalıştırmalarınızı bildirin {#report-your-test-runs}

Tüm paketi çalıştırın veya bir hedef seçin:

```bash
once test
once test MyTests
```

Once, yerel test olaylarını akışa alır ve tamamlanan sonuçları Tuist'in ortak test modeline yayımlar. **Tests** ve **Test Runs** sayfaları çalıştırmaları gösterir; tekil test durumlarının da ortak bir test geçmişi bulunur. Bir <.localized_link href="/guides/features/test-sharding/once">barındırılan parçalı çalıştırma</.localized_link>, tanılama olay akışını tekrar saymak yerine her çalışan için tek bir raporu birleştirilmiş bir çalıştırmaya yayımlar.

## Neler izlenir {#what-is-tracked}

- Bildirilen test hedefleri, paketleri ve tekil test durumları.
- Çalıştırıcı tarafından sağlandığında süreleriyle birlikte geçen, başarısız olan ve atlanan sonuçlar.
- Barındırılan parçalı raporlarda çalıştırıcı tarafından sağlanan hata mesajları.
- Bir test başarısız olup daha sonra geçtiğinde sıralı yeniden deneme girişimleri ve kararsız sonuçlar.
- Once tarafından sağlanan dal, commit ve CI bağlamı.

Test kimliği yerel hedef, paket ve durum adlarını kullanır. Parçalama toplu iş kimlikleri zamanlama birimleridir, test adları değildir.

Normal `once test` bildirimleri sonuçları ve yeniden deneme girişimlerini korur ancak şu anda ortak test geçmişine hata mesajlarını dahil etmez. Barındırılan parçalı raporlar hata mesajları içerebilir, ancak hiçbir bildirim yolu kaynak konumlarını sağlamaz. Tuist'te mevcut olmayan tanılama bilgileri için CI günlüklerinizi saklayın.

Her test hedefi aynı ayrıntı düzeyini sağlamaz. Bazı çalıştırıcılar tekil durumları bildirirken diğerleri yalnızca özetler sunar; kesin dosya veya durum yürütmesi ayrı bir yetenektir. Durum başına analitiklere veya ince ayarlı zamanlamaya güvenmeden önce [Once'ın test ekosistemi kapsamı](https://buildonce.dev/docs/guide/graph/testing#understand-current-ecosystem-coverage) bölümüne bakın.

## Kararsız testler {#flaky-tests}

Tuist, tutarsız sonuçları belirlemek için bildirilen girişimleri ve CI geçmişini kullanır. Bir girişimi bildirmek, yeniden denemeleri etkinleştirmekle aynı değildir: yeniden denemeleri destekleyen çalıştırıcıda yapılandırın. Algılama ve mevcut karantina sınırı için <.localized_link href="/guides/features/test-insights/flaky-tests/once">Once kararsız testler</.localized_link> kılavuzuna bakın.

## Seçim ve kod kapsamı {#selection-and-code-coverage}

Once, yerel grafiğinden `--changed-path` kullanarak testleri muhafazakar bir şekilde seçebilir. Bu, Once'ın kendi seçimidir; Tuist'in barındırdığı kapsama dayalı test seçimi değildir:

```bash
once test --changed-path src/library.rs
```

Yerel Once bildirimleri şu anda kod kapsamını Tuist'e yüklemez. Başarılı bir test raporu veya parça planı Kod Kapsamı panosunu doldurmaz.

## Sorun giderme {#troubleshooting}

Bir çalıştırma eksikse, etkili önbellek sağlayıcısının Tuist projenizi adlandırdığından emin olun ve `once auth login --provider tuist` ile yeniden kimlik doğrulaması yapın. Canlı bildirim en iyi çabayla yapılır ve bildirim hizmeti kullanılamadığında aksi takdirde başarılı olan bir test komutunu başarısız hale getirmez.

Çalıştırma özetleri ve yapılandırılmış test hataları tam süreç günlükleri değildir. Bu sunucu şu anda Once'ın ham eylem günlük akışını almaz; yapılandırılmış sonuçlara dahil olmayan çıktılar için CI günlüklerinizi saklayın.
