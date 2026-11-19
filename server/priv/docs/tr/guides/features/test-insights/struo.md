---
{
  "title": "Struo Test İçgörüler",
  "titleTemplate": ":title · Test İçgörüler · Özellikler · Kılavuzlar · Tuist",
  "description": "Tuist kontrol panelinde Struo test paketlerini, bireysel sonuçları, hataları ve süreleri inceleyin."
}
---
# Struo test içgörüleri {#struo-test-insights}

<a id="once-test-insights"></a>

Struo, test sonuçlarını Tuist'e bildirir; böylece test paketinizi yerel ve CI çalıştırmaları boyunca takip edebilir, hataları inceleyebilir ve tek tek çalışanlardan rapor toplamadan yavaş testleri bulabilirsiniz.

> [!IMPORTANT]
> **Gereksinimler**
>
> - <.localized_link href="/guides/get-started/struo-project">Struo ile başlayın</.localized_link> kılavuzunu tamamlayın.
> - Yapılandırılmış sonuçlar bildiren test hedeflerini kullanın. Sunulan ayrıntı düzeyi, hedef türüne ve test çalıştırıcısına bağlıdır.

## Test çalıştırmalarınızı bildirin {#report-your-test-runs}

Tüm paketi çalıştırın veya bir hedef seçin:

```bash
struo test
struo test MyTests
```

Struo, yerel test olaylarını akış olarak gönderir ve tamamlanan sonuçları Tuist'in ortak test modeline yayınlar. **Tests** ve **Test Runs** çalıştırmaları gösterir; tekil test vakalarının da ortak test geçmişi bulunur. Bir <.localized_link href="/guides/features/test-sharding/struo">hosted sharded run</.localized_link>, tanılama olay akışını tekrar saymak yerine her çalışan için bir rapor yayımlayarak bunları tek bir bileşik çalıştırmada birleştirir.

## Neler izlenir {#what-is-tracked}

- Bildirilen test hedefleri, test paketleri ve tekil test vakaları.
- Çalıştırıcı tarafından sağlandığında süreleriyle birlikte geçen, başarısız olan ve atlanan sonuçlar.
- Barındırılan parçalı raporlarda çalıştırıcı tarafından sağlanan hata mesajları.
- Bir test başarısız olup daha sonra geçtiğinde sıralı yeniden deneme girişimleri ve kararsız sonuçlar.
- Struo tarafından sağlanan dal, commit ve CI bağlamı.

Test kimliği, yerel hedef, paket ve vaka adını kullanır. Parçalama toplu iş kimlikleri zamanlama birimleridir, test adı değildir.

Normal `struo test` bildirimleri sonuçları ve yeniden deneme girişimlerini korur ancak şu anda ortak test geçmişine hata mesajlarını dahil etmez. Barındırılan parçalı raporlar hata mesajları içerebilir, ancak hiçbir bildirim yolu kaynak konumlarını sağlamaz. Tuist'te mevcut olmayan tanılama bilgileri için CI günlüklerinizi saklayın.

Her test hedefi aynı ayrıntı düzeyini sağlamaz. Bazı çalıştırıcılar tekil vakaları bildirirken diğerleri yalnızca özet sunar; kesin dosya veya vaka yürütmesi ayrı bir yetenektir. Vaka bazlı analitiklere veya ince taneli zamanlamaya güvenmeden önce [Struo'nun test ekosistemi kapsamına](https://struo.run/docs/guide/graph/testing#understand-current-ecosystem-coverage) bakın.

## Kararsız testler {#flaky-tests}

Tuist, tutarsız sonuçları belirlemek için bildirilen girişimleri ve CI geçmişini kullanır. Bir girişimi bildirmek, yeniden denemeleri etkinleştirmekle aynı şey değildir: yeniden denemeleri destekleyen çalıştırıcıda yapılandırın. Algılama ve geçerli karantina sınırı için <.localized_link href="/guides/features/test-insights/flaky-tests/struo">Struo kararsız testler</.localized_link> bölümüne bakın.

## Seçim ve kod kapsamı {#selection-and-code-coverage}

Struo, yerel grafiğinden testleri `--changed-path` ile muhafazakar şekilde seçebilir. Bu, Struo'nun kendi seçimidir; Tuist'in barındırdığı kapsama dayalı test seçimi değildir:

```bash
struo test --changed-path src/library.rs
```

Yerel Struo bildirimi şu anda kod kapsamını Tuist'e yüklemez. Başarılı bir test raporu veya parça planı Kod Kapsamı panosunu doldurmaz.

## Sorun giderme {#troubleshooting}

Bir çalıştırma eksikse, etkili önbellek sağlayıcısının Tuist projenizi adlandırdığından emin olun ve `struo auth login --provider tuist` ile yeniden kimlik doğrulaması yapın. Canlı bildirim en iyi çaba ile yapılır ve raporlama hizmeti kullanılamadığında aksi takdirde başarılı olan bir test komutunu başarısızlığa dönüştürmez.

Çalıştırma özetleri ve yapılandırılmış test hataları tam işlem günlükleri değildir. Bu sunucu şu anda Struo'nun ham eylem günlük akışını almaz; yapılandırılmış sonuçlara dahil olmayan çıktılar için CI günlüklerinizi saklayın.
