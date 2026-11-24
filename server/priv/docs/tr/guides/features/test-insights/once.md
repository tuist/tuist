---
{
  "title": "Once Test İçgörüler",
  "titleTemplate": ":title · Test İçgörüler · Özellikler · Kılavuzlar · Tuist",
  "description": "Tuist kontrol panelinde Once test paketlerini, bireysel sonuçları, hataları ve süreleri inceleyin."
}
---
# Once test içgörüleri {#once-test-insights}

Once, test sonuçlarını Tuist'e raporlar; böylece yerel ve CI çalıştırmalarında test paketinizi takip edebilir, hataları inceleyebilir ve tekil çalışanlardan rapor toplamadan yavaş testleri bulabilirsiniz.

> [!IMPORTANT]
> **Gereksinimler**
>
> - <.localized_link href="/guides/get-started/once-project">Once ile başlayın</.localized_link> kılavuzunu tamamlayın.
> - Yapılandırılmış sonuçlar raporlayan test hedeflerini kullanın. Sunulan ayrıntı düzeyi, hedef türüne ve test çalıştırıcısına bağlıdır.

## Test çalıştırmalarınızı raporlayın {#report-your-test-runs}

Tüm paketi çalıştırın veya bir hedef seçin:

```bash
once test
once test MyTests
```

Once, yerel test olaylarını akış olarak iletir ve tamamlanan sonuçları Tuist'in ortak test modeline yayınlar. **Tests** ve **Test Runs** çalıştırmaları gösterir; tekil test durumları da ortak test geçmişine sahiptir. Bir <.localized_link href="/guides/features/test-sharding/once">hosted sharded run</.localized_link>, tanılama olay akışını yeniden saymak yerine her çalışan için bir raporu birleştirilmiş bir çalıştırmaya yayınlar.

## Neler izlenir {#what-is-tracked}

- Raporlanan test hedefleri, paketleri ve tekil test durumları.
- Çalıştırıcı tarafından sağlandığında süreleriyle birlikte geçen, başarısız olan ve atlanan sonuçlar.
- Barındırılan parçalı raporlarda çalıştırıcı tarafından sağlanan hata mesajları.
- Bir test başarısız olup daha sonra geçtiğinde sıralı yeniden deneme girişimleri ve kararsız sonuçlar.
- Once tarafından sağlanan dal, commit ve CI bağlamı.

Test kimliği yerel hedef, paket ve durum adını kullanır. Parçalama toplu iş kimlikleri zamanlama birimleridir, test adları değildir.

Normal `once test` raporlaması sonuçları ve yeniden deneme girişimlerini korur ancak şu anda ortak test geçmişinde hata mesajlarını içermez. Barındırılan parçalı raporlar hata mesajlarını içerebilir, ancak hiçbir raporlama yolu kaynak konumlarını sağlamaz. Tuist'te bulunmayan tanılama bilgileri için CI günlüklerinizi saklayın.

Her test hedefi aynı ayrıntı düzeyini sağlamaz. Bazı çalıştırıcılar tekil durumları raporlarken diğerleri yalnızca özetler sunar; kesin dosya veya durum yürütmesi ayrı bir yetenektir. Durum bazlı analitiklere veya ince taneli zamanlamaya güvenmeden önce [Once'ın test ekosistemi kapsamı](https://buildonce.dev/docs/guide/graph/testing#understand-current-ecosystem-coverage) bölümüne bakın.

## Kararsız testler {#flaky-tests}

Tuist, tutarsız sonuçları belirlemek için bildirilen girişimleri ve CI geçmişini kullanır. Bir girişimi bildirmek, yeniden denemeleri etkinleştirmekle aynı şey değildir: yeniden denemeleri destekleyen çalıştırıcıda yapılandırın. Algılama ve mevcut karantina sınırı için <.localized_link href="/guides/features/test-insights/flaky-tests/once">Once kararsız testler</.localized_link> bölümüne bakın.

## Seçim ve kod kapsamı {#selection-and-code-coverage}

Once, yerel grafiğinden `--changed-path` ile muhafazakar şekilde testleri seçebilir. Bu, Once'ın kendi seçimidir; Tuist'in barındırdığı kod kapsamına dayalı test seçimi değildir:

```bash
once test --changed-path src/library.rs
```

Yerel Once raporlaması şu anda kod kapsamını Tuist'e yüklemez. Başarılı bir test raporu veya parça planı Kod Kapsamı panosunu doldurmaz.

## Sorun giderme {#troubleshooting}

Bir çalıştırma eksikse, etkin önbellek sağlayıcısının Tuist projenizi adlandırdığından emin olun ve `once auth login --provider tuist` ile tekrar kimlik doğrulaması yapın. Canlı raporlama en iyi çaba esasına dayanır ve raporlama hizmeti kullanılamadığında aksi halde başarılı olan bir test komutunu başarısız hale getirmez.

Çalıştırma özetleri ve yapılandırılmış test hataları tam süreç günlükleri değildir. Bu sunucu şu anda Once'ın ham eylem günlük akışını almaz; yapılandırılmış sonuçlara dahil olmayan çıktılar için CI günlüklerinizi saklayın.
