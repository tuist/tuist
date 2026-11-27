---
{
  "title": "Elixir Kod Kapsamı",
  "titleTemplate": ":title · Kod Kapsamı · Özellikler · Kılavuzlar · Tuist",
  "description": "Elixir projenizin satır kapsamını mix test --cover ile yükleyin ve dosya, uygulama ve commit bazında takip edin."
}
---
# Elixir kod kapsamı {#elixir-code-coverage}

Kod kapsamı, testlerinizin kodunuzun hangi satırlarını çalıştırdığını gösterir. Hex paketi her `mix test --cover` çalıştırmasının satır kapsamını yükler ve Tuist, bir commit’in çalıştırmalarını proje, her OTP uygulaması ve her dosya için tek bir değerde birleştirir. Kontrol panelinin **Kod Kapsamı** sayfası bunu commit başına ve her dal için bir trend olarak gösterir.

> [!IMPORTANT]
> **Gereksinimler**
>
> - Paketi kullanan <.localized_link href="/guides/get-started/elixir-project">ortak Elixir kurulumunu</.localized_link> tamamlayın; bu kurulum `mix test` komutunu paket üzerinden yönlendirir.

## Kurulum {#setup}

### Testlerinizi kapsamla çalıştırın {#run-your-tests}

Tuist olmadan `mix test` komutuna vereceğiniz gibi `--cover` seçeneğini ekleyin:

```sh
mix test --cover
```

Paket, kapsam verisini çalıştırmanın test sonuçlarıyla birlikte yükler. Test paketi tamamlandığında, Mix’in kapsam aracının yaptığı işi de aynı `test_coverage` seçenekleriyle yapılandırılmış şekilde gerçekleştirir:

- **Özet.** Her modülün ve toplam kapsamı yazdırır. `summary: false` bu özelliği kapatır.
- **Eşik.** Toplam kapsam eşik değerinin altına düştüğünde çalıştırma çıkış kodu 3 ile başarısız olur; siz başka bir değer belirlemezseniz eşik %90’dır:

```elixir
def project do
  [
    test_coverage: [summary: [threshold: 80]]
  ]
end
```

Mix’te olduğu gibi eşik özet ayarına bağlıdır, bu nedenle `summary: false` her ikisini de kapatır. Çalıştırmayı başarısız etmeden özeti yazdırmak için `threshold: 0` ayarını kullanın. `test_coverage: [ignore_modules: [...]]` içinde listelenen modüller özete ve yüklemeye dahil edilmez.

Tuist kapsamı commit başına izler, bu yüzden projenizin bir Git deposunda olması gerekir: Bir depo dışındaki çalıştırma test sonuçlarını yükler ancak kapsam verisi yüklemez.

Kapsam, paketin yüklediği ve commit’i ilgili dala yerleştiren <.localized_link href="/guides/features/test-insights/elixir#git-history">Git geçmişine</.localized_link> dayanır. Sürekli entegrasyondaki çalıştırmalar bunu her zaman yükler ve `--cover` çalıştırmaları bunu herhangi bir makinede yükler. `--cover` ile paket, bir pull request’in nereden dallandığını da bulur: temel dalı getirir ve sığ klonu gerektiği kadar derinleştirir. Sürekli entegrasyonda, dosya içerikleri olmadan sığ bir checkout da Tuist’in zaten sahip olduğu commit’lere ulaşana kadar derinleştirilir; böylece bir commit, üzerine bindiği üst commit olmadan asla yüklenmez. Uzak sunucuyla iletişim kurmasını engellemek için `TUIST_GIT_UNSHALLOW_ENABLED=false` ayarını yapın.

### Parçalı çalıştırmalar {#sharded-runs}

<.localized_link href="/guides/features/test-sharding/elixir">Testlerinizi parçalara böldüğünüzde</.localized_link>, her parçayı `--cover` ile çalıştırın:

```sh
MIX_ENV=test TUIST_SHARD_INDEX=0 mix tuist.test --cover
```

Yeni bir çalıştırıcıda, parçalama kılavuzundaki <.localized_link href="/guides/features/test-sharding/elixir#test-phase">test aşamasından</.localized_link> bootstrap komutunu kullanın; bu komut, parça derlemesini indirmeden önce Mix’in tüm bağımlılıkları derlemesini önler ve buna `--cover` ekleyin.

Bir parça yalnızca kendi kapsamını bildirir ve test paketinin bir bölümünü çalıştırdığı için eşiği kontrol etmez. Tuist, bir çalıştırmanın parçalarını tek bir değerde birleştirir.

Her parça, indirdiği derlemeye kapsam sayaçlarını ekler. Bunun yerine bunu yalnızca bir kez yapmak isterseniz, derleme aşamasına da `--cover` ekleyin:

```sh
MIX_ENV=test mix tuist.test.build --shard-max 5 --cover
```

Pipeline çalıştırmaları arasında derleme dizinini koruyup kapsam toplamayan çalıştırmalarda yeniden kullandığınızda bu seçeneği devre dışı bırakın; böylece o derleme sayaçsız kalır.

### CI’da her commit’i tamamlayın {#complete-each-commit}

Bir commit’in kapsamı genellikle birkaç job’dan gelir: parça başına, veritabanı sürümü başına veya uygulama başına bir job. Tuist bunlardan sonuncusunun ne zaman raporladığını bilemez, bu yüzden siz bildirin. Bir commit için tüm test job’ları tamamlandığında, hepsine bağımlı olan bir job’da şunu çalıştırın:

```sh
MIX_ENV=test mix tuist.coverage.complete
```

Görev, commit bilgisini `GIT_COMMIT` ortam değişkeninden veya checkout’un `HEAD` referansından okur; farklı bir commit belirtmek için `--commit <sha>` parametresini kullanın. Bir commit tamamlanana kadar kapsamı **Devam ediyor** olarak görünür ve dalın trendine dahil edilmez.

## Nasıl çalışır {#how-it-works}

### Yerel satır sayaçları {#native-line-counters}

Mix’in kapsam aracı, her çalıştırmanın başında Erlang’ın `cover` modülü için her modülü yeniden derler; bu, büyük projelerde yavaş olabilir. Paket bunun yerine çalışma zamanının yerel satır sayaçlarını kullanır. Yalnızca son çalıştırmadan bu yana bir derleme tarafından yazılan modülleri yeniden derler, çalışma zamanını bu sayaçlara geçirir ve test paketi tamamlandığında sayaçları okur. Mix’in kapsam aracı devre dışı bırakılır, ancak özeti ve eşiği korunur.

Paket, aşağıdaki durumlar için Mix’in kapsam aracına geri döner ve aynı yükleme işlemini gerçekleştirir:

- Şemsiye (umbrella) projesinin kök dizini. Yerel sayım yapmak için testleri her uygulamanın içinde çalıştırın.
- Kendi `test_coverage: [tool: ...]` ayarını yapan bir proje.
- JIT içermeyen bir çalışma zamanı; bu ortam yerel sayım yapamaz.

### Tuist’in ölçtüğü şeyler {#what-tuist-measures}

- **Uygulamalar.** Her OTP uygulaması kontrol panelinde kendi kapsamıyla birlikte bir hedef olarak görünür.
- **Yalnızca ürün kodu.** Test yollarınız altındaki dosyalar test kodudur. Tuist bunları saklar ancak hiçbir değerlendirmeye dahil etmez.
- **Dosya başına satır.** Bir satır, ait olduğu modül sayısından bağımsız olarak dosya başına bir kez sayılır.
- **Fonksiyonlar.** Her satır, kendisinden hemen yukarıda başlayan klauza sahip fonksiyona aittir. Derleyici veya bir makro tarafından üretilen `__info__/1` ya da `__schema__/1` gibi fonksiyonlar listelenmez, ancak satırları yine de dosyaya ait olarak sayılır.
- **Şablonlar.** Yerel sayımda, bir modüle derlenen şablon (örneğin bir LiveView’in `.html.heex`, `embed_templates` veya `EEx.function_from_file`) kendi satırları ve fonksiyonları olmayan ayrı bir dosya olarak ölçülür. Mix’in kapsam aracı şablonları ölçmez, bu nedenle özet ve eşik hesaplamalarına dahil edilmezler.

Bu nedenle Tuist’in değerleri Mix’in kendi kapsam raporundan birkaç açıdan farklılık gösterir: test kodunu hariç tutar ve satırları modül başına değil dosya başına sayar. Yerel sayım ayrıca uygulamanız başlarken çalışan kodu görür ve derleyicinin asla çalışmayacağını kanıtladığı satırları hariç tutar; Mix’in aracı bu satırları hiç kapsanmamış olarak raporlar.

### Atlanan testler {#skipped-tests}

Tuist, bir çalıştırmanın hariç tuttuğu testlerin kapsamını ileri taşıyamaz: paket tüm çalıştırmanın neyi yürüttüğünü kaydeder, her testin neyi yürüttüğünü değil. Bu nedenle, bir çalıştırmanın kendi argümanları (`--only`, `--exclude`, `--failed`, `--stale`, `--name-pattern`, `--max-failures` veya test dosyaları/satırları) testleri hariç tuttuğunda, aynı varyanttan hiçbir şeyi hariç tutmayan bir çalıştırma da yapılmadıkça commit’in kapsamı **Eksik** olarak işaretlenir. `--exclude slow` ve `--only slow` gibi her biri testleri hariç tutan iki çalıştırma, birlikte tüm testleri çalıştırsalar bile commit’i eksik bırakır.

Bazı testler bilinçli olarak hariç tutulur ve commit’i eksik hale getirmez:

- **Test yardımcınızın dışlamaları.** `ExUnit.start(exclude: [...])` tarafından varsayılan olarak hariç tutulan testler, projenizin test paketinin varsayılan olarak neyi çalıştıracağına ilişkin tercihini yansıtır; bu nedenle Tuist bunları eksik olarak saymaz. Kapsamlarını commit’e eklemek için bu testleri başka bir job’da `--include` veya `--only` ile çalıştırın.
- **Kodda atlanan testler** `@tag :skip` ile.
- **<.localized_link href="/guides/features/test-insights/flaky-tests/elixir#quarantining">Karantina</.localized_link> tarafından atlanan testler.** Bunlar kaldırılmış gibi hariç tutulur, bu nedenle yalnızca bunların kapsadığı satırlar kapsanmamış olarak sayılır.

### Tamamlanan ve tamamlanmayan commit’ler {#commit-status}

Panodaki her commit’in bir durumu vardır:

| Durum | Anlamı |
| --- | --- |
| Devam ediyor | Çalıştırmalar kapsam bildirdi, ancak `mix tuist.coverage.complete` henüz commit için çalıştırılmadı. |
| Tamamlandı | Commit’in çalıştırmalarına ait tüm testler çalıştırıldı veya bilinçli olarak hariç tutuldu. |
| Eksik | Bazı kapsamlar belirlenemedi, bu nedenle değer bir alt sınırdır. |
| Ölçülmedi | Hiçbir çalıştırma commit için kapsam bildirmedi. |

Bir dalın trendi yalnızca tamamlanan commit’leri içerir. Bir commit şu durumlarda eksiktir, örneğin:

- Bir varyantın her çalıştırması kendi argümanlarıyla testleri hariç tuttu.
- Bir varyantın her çalıştırmasında bazı shard’lar eksikti.
- Bir varyantın kapsamı yalnızca işlenmemiş değişiklikleri olan bir checkout üzerindeki CI çalıştırmalarından geldi.

Varyant, `--scheme` ile ilettiğiniz etikettir; örneğin bir veritabanı sürümü. Etiketsiz çalıştırmalar tek bir varyanttır. Commit’in değeri tüm çalıştırmaları birleştirir, ancak Tuist her varyantın tamlığını ayrı ayrı kontrol eder; bu nedenle her varyantın hiçbir şeyi hariç tutmayan bir çalıştırması gerekir.

## Performans etkisi {#performance-impact}

Kapsam toplamak ek yük getirir, bu nedenle `--cover` içeren çalıştırmalar onu içermeyenlerden daha uzun sürer. İlk çalıştırma modüllerinizi satır sayaçlarıyla yeniden derler; sonraki çalıştırmalar yalnızca değişenleri yeniden derler, bu nedenle maliyetleri çok daha düşüktür. Büyük projelerde yerel sayım, Mix’in kapsam aracından çok daha hızlıdır.

## Sınırlamalar {#limitations}

- **HTML raporu yok.** Yerel sayım `test_coverage: [output: ...]` dizinine rapor yazmaz ve biri ayarlandığında çalıştırma uyarı verir. Bunun yerine panonun dosya sayfaları kapsanan satırları gösterir.
- **Yeniden denemeler kapsam eklemez.** <.localized_link href="/guides/features/test-insights/flaky-tests/elixir#test-retries">Test yeniden denemeleri</.localized_link> ile kapsam ilk denemenin kapsamıdır. Bu deneme başarısız testleri zaten çalıştırdığından, eksik olan tek satırlar kararsız bir testin yeniden denemede ulaştığı ancak ilk denemesinde ulaşmadığı satırlardır.
- **Fork’lardan gelen pull request’lerden kapsam yok.** Kapsam yalnızca Tuist ile kimlik doğrulaması yapan çalıştırmalar tarafından yüklenir ve CI genellikle fork’lardan açılan pull request’lerde gizli anahtarları ve kimlik belirteçlerini tutar, bu nedenle bu çalıştırmalar kapsam bildirmez. Birleştirildikten sonra, commit kimlik bilgileriyle dalınızda çalışır ve kapsamını her zamanki gibi bildirir.

## Kapsam sorgulama {#querying}

Panonun **Kod Kapsamı** sayfası, her çalıştırmanın kapsadığı satırlarla birlikte her commit’in değerini, uygulamalarını ve dosyalarını gösterir. Aynı verilere ajanlar <.localized_link href="/guides/features/agentic-coding/mcp">Model Context Protocol sunucusu</.localized_link> üzerinden erişebilir.
