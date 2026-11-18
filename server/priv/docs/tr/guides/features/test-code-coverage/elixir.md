---
{
  "title": "Elixir Kod Kapsamı",
  "titleTemplate": ":title · Kod Kapsamı · Özellikler · Kılavuzlar · Tuist",
  "description": "mix test --cover ile Elixir projenizin satır kapsamını yükleyin ve dosya, uygulama ve commit bazında takip edin."
}
---
# Elixir kod kapsama oranı {#elixir-code-coverage}

Kod kapsama oranı, testlerinizin kodunuzun hangi satırlarını çalıştırdığını gösterir. Hex paketi, her bir `mix test --cover` çalıştırmasının satır kapsama oranını yükler ve Tuist, bir commit'in çalıştırmalarını proje, her OTP uygulaması ve her dosya için tek bir rakamda birleştirir. Panonun **Kod Kapsama Oranı** sayfası bunu commit başına ve her dal için bir trend olarak gösterir.

> [!IMPORTANT]
> **Gereksinimler**
>
> - Paket üzerinden `mix test` yönlendiren <.localized_link href="/guides/get-started/elixir-project">paylaşılan Elixir kurulumunu</.localized_link> tamamlayın

## Kurulum {#setup}

### Testlerinizi kapsama oranıyla çalıştırın {#run-your-tests}

Tuist olmadan `mix test` komutuna verdiğiniz gibi `--cover` parametresini ekleyin:

```sh
mix test --cover
```

Paket, kapsama oranını çalıştırmanın test sonuçlarıyla birlikte yükler. Test paketi tamamlandığında, aynı `test_coverage` seçenekleriyle yapılandırıldığı şekilde Mix'in kapsama aracının yaptığını da yapar:

- **Özet.** Her modülün ve toplamın kapsama oranını yazdırır. `summary: false` bunu kapatır.
- **Eşik.** Toplam eşik değerinin altına düştüğünde, çalıştırmayı çıkış durumu 3 ile başarısız kılar; siz başka bir değer belirlemezseniz bu %90'dır:

```elixir
def project do
  [
    test_coverage: [summary: [threshold: 80]]
  ]
end
```

Mix'te olduğu gibi, eşik özetin bir parçasıdır, bu nedenle `summary: false` her ikisini de kapatır. Çalıştırmayı başarısız kılmadan özeti yazdırmak için `threshold: 0` ayarlayın. `test_coverage: [ignore_modules: [...]]` içinde listelenen modüller özete ve yüklemeye dahil edilmez.

Tuist, kapsama oranını commit başına takip eder, bu nedenle projenizin bir Git deposunda olmasını gerektirir: Bir depo dışındaki çalıştırma, test sonuçlarını yükler ancak kapsama oranını yüklemez.

Kapsama oranı, paketin yüklediği ve commit'i dalına yerleştiren <.localized_link href="/guides/features/test-insights/elixir#git-history">Git geçmişine</.localized_link> dayanır. Sürekli entegrasyondaki çalıştırmalar bunu her zaman yükler ve `--cover` çalıştırmaları bunu herhangi bir makinede yükler. `--cover` ile paket, bir pull request'in nereden dallandığını da bulur: temel dalı getirir ve sığ klonu ihtiyaç duyduğu kadar derinleştirir. Sürekli entegrasyonda, sığ bir checkout da dosya içerikleri olmadan, Tuist'in zaten sahip olduğu commit'lere ulaşana kadar derinleştirilir, böylece bir commit asla üzerinde durduğu ebeveyni olmadan yüklenmez. Uzaktan sunucuya bağlanmasını engellemek için `TUIST_GIT_UNSHALLOW_ENABLED=false` ayarlayın.

### Parçalı çalıştırmalar {#sharded-runs}

Testlerinizi <.localized_link href="/guides/features/test-sharding/elixir">parçalara böldüğünüzde</.localized_link>, her parçayı `--cover` ile çalıştırın:

```sh
MIX_ENV=test TUIST_SHARD_INDEX=0 mix tuist.test --cover
```

Yeni bir çalıştırıcıda, parçalama kılavuzunun <.localized_link href="/guides/features/test-sharding/elixir#test-phase">test aşamasından</.localized_link> bootstrap komutunu kullanın; bu, parça build'ini indirmeden önce Mix'in her bağımlılığı derlemesini engeller ve buna `--cover` ekleyin.

Bir parça yalnızca kendi kapsama oranını bildirir ve test paketinin bir kısmını çalıştırdığı için eşik değerini kontrol etmez. Tuist, bir çalıştırmanın parçalarını tek bir rakamda birleştirir.

Her parça, indirdiği build'e kapsama sayaçlarını ekler. Bunu yalnızca bir kez yapmak yerine, build aşamasına da `--cover` parametresini geçirin:

```sh
MIX_ENV=test mix tuist.test.build --shard-max 5 --cover
```

Pipeline çalıştırmaları arasında build dizinini koruyup kapsama oranı toplamayan çalıştırmalarda yeniden kullandığınızda bunu devre dışı bırakın, böylece o build sayaçsız kalır.

### CI'da her commit'i tamamlayın {#complete-each-commit}

Bir commit'in kapsama oranı genellikle birkaç job'dan gelir: parça başına, veritabanı sürümü başına veya uygulama başına bir tane. Tuist, bunların hangisinin sonuncusunun raporladığını bilemez, bu yüzden siz bildirin. Bir commit için tüm test job'ları tamamlandığında, hepsine bağımlı olan bir job'da şunu çalıştırın:

```sh
MIX_ENV=test mix tuist.coverage.complete
```

Görev, commit'i `GIT_COMMIT` veya checkout'un `HEAD` değerinden okur; başka birini belirtmek için `--commit <sha>` parametresini geçirin. Bir commit tamamlanana kadar, kapsama oranı **Devam ediyor** olarak görünür ve dalın trendine dahil edilmez.

## Nasıl çalışır {#how-it-works}

### Yerel satır sayaçları {#native-line-counters}

Mix'in kapsama aracı, her çalıştırmanın başında Erlang'ın `cover` için her modülü yeniden derler; bu, büyük projelerde yavaşlar. Paket bunun yerine çalışma zamanının yerel satır sayaçlarını kullanır. Son çalıştırmadan bu yana bir derlemenin yazdığı modülleri yalnızca yeniden derler, çalışma zamanını bu sayaçlara geçirir ve test paketi bittiğinde bunları okur. Mix'in kapsama aracı dışlanır, ancak özeti ve eşiği korunur.

Paket, aşağıdaki durumlar için aynı yüklemeyle Mix'in kapsama aracına geri döner:

- Şemsiye projesinin kökü. Yerel sayım yapmak için testleri her uygulamanın içinde çalıştırın.
- Kendi `test_coverage: [tool: ...]` ayarını yapan bir proje.
- JIT olmayan, yerel sayım yapamayan bir çalışma zamanı.

### Tuist'in ölçtüğü şeyler {#what-tuist-measures}

- **Uygulamalar.** Her OTP uygulaması, panoda kendi kapsama oranına sahip bir hedeftir.
- **Yalnızca ürün kodu.** Test yollarınız altındaki dosyalar test kodudur. Tuist bunları saklar ancak her rakamdan çıkarır.
- **Dosya başına satır.** Bir satır, kaç modüle ait olduğundan bağımsız olarak dosya başına bir kez sayılır.
- **Fonksiyonlar.** Her satır, kendisinden hemen yukarıda başlayan klauzuna sahip fonksiyona aittir. Derleyicinin veya bir makronun ürettiği `__info__/1` veya `__schema__/1` gibi fonksiyonlar listelenmez, ancak satırları yine de dosyaları için sayılır.

Bu nedenle Tuist'in rakamları Mix'in kendi kapsama raporundan birkaç şekilde farklılık gösterir: test kodunu dışlar ve satırları modül başına değil dosya başına sayar. Yerel sayım ayrıca uygulamanız başlarken çalışan kodu görür ve derleyicinin asla çalışamayacağını kanıtladığı satırları dışlar; Mix'in aracı bunları hiç kapsanmamış olarak raporlar.

### Atlanan testler {#skipped-tests}

Tuist, bir çalıştırmanın dışladığı testlerin kapsama oranını taşıyamaz: paket, her testin ne çalıştırdığını değil, tüm çalıştırmanın ne yürüttüğünü kaydeder. Bu nedenle, bir çalıştırmanın kendi argümanları `--only`, `--exclude`, `--failed`, `--stale`, `--name-pattern`, `--max-failures` veya test dosyaları ya da satırlarıyla testleri dışladığında, commit'in kapsama oranı **Eksik** olur;除非 hiçbir şeyi dışlamayan aynı varyanttan bir çalıştırma da yapılmışsa. `--exclude slow` ve `--only slow` gibi her biri testleri dışlayan iki çalıştırma, birlikte her testi çalıştırsalar bile commit'i eksik bırakır.

Bazı testler bilinçli olarak dışlanır ve bir commit'i eksik hale getirmez:

- **Test yardımcınızın dışlamaları.** Varsayılan olarak `ExUnit.start(exclude: [...])` tarafından dışlanan testler, projenizin paketinin varsayılan olarak neyi çalıştıracağına ilişkin seçimidir, bu nedenle Tuist bunları eksik olarak saymaz. Kapsama oranlarını commit'e eklemek için bunları başka bir job'da `--include` veya `--only` ile çalıştırın.
- **Kodda atlanan testler** `@tag :skip` ile.
- **<.localized_link href="/guides/features/test-insights/flaky-tests/elixir#quarantining">Karantina</.localized_link> tarafından atlanan testler.** Bunlar, kaldırılmış gibi dışlanır; bu nedenle yalnızca bunların kapsadığı satırlar kapsanmamış olarak sayılır.

### Tamamlanmış ve eksik commit'ler {#commit-status}

Panodaki her commit'in bir durumu vardır:

| Durum | Anlamı |
| --- | --- |
| Devam ediyor | Çalıştırmalar kapsama oranını bildirdi, ancak `mix tuist.coverage.complete` henüz commit için çalıştırılmadı. |
| Tamamlandı | Commit'in çalıştırmalarındaki her test çalıştırıldı veya bilinçli olarak dışlandı. |
| Eksik | Bazı kapsama oranları belirlenemedi, bu nedenle rakam bir alt sınırdır. |
| Ölçülmedi | Hiçbir çalıştırma commit için kapsama oranı bildirmedi. |

Bir dalın trendi yalnızca tamamlanmış commit'leri içerir. Bir commit şu durumlarda eksiktir, örneğin:

- Bir varyantın her çalıştırması kendi argümanlarıyla testleri dışladı.
- Bir varyantın her çalıştırmasında bazı shard'lar eksikti.
- Bir varyantın kapsama oranı yalnızca işlenmemiş değişiklikler içeren bir checkout'taki CI çalıştırmalarından geldi.

Varyant, `--scheme` ile geçtiğiniz etikettir; örneğin bir veritabanı sürümü. Etiketsiz çalıştırmalar tek bir varyanttır. Commit'in rakamı her çalıştırmayı birleştirir, ancak Tuist her varyantı bağımsız olarak tamlık açısından kontrol eder; bu nedenle her varyantın hiçbir şeyi dışlamayan bir çalıştırmaya ihtiyacı vardır.

## Performans etkisi {#performance-impact}

Kapsama toplamak ek yük getirir, bu nedenle `--cover` içeren çalıştırmalar onu içermeyenlerden daha uzun sürer. İlk çalıştırma modüllerinizi satır sayaçlarıyla yeniden derler; sonraki çalıştırmalar yalnızca değişenleri yeniden derler, bu nedenle maliyetleri çok daha düşüktür. Büyük projelerde yerel sayım, Mix'in kapsama aracından çok daha hızlıdır.

## Sınırlamalar {#limitations}

- **HTML raporu yok.** Yerel sayım, `test_coverage: [output: ...]` dizinine herhangi bir rapor yazmaz ve biri ayarlandığında çalıştırma uyarı verir. Bunun yerine panonun dosya sayfaları kapsanan satırları gösterir.
- **Yeniden denemeler kapsama eklemez.** <.localized_link href="/guides/features/test-insights/flaky-tests/elixir#test-retries">Test yeniden denemeleri</.localized_link> ile kapsama, ilk denemenin kapsama oranıdır. Bu deneme başarısız testleri zaten çalıştırdığından, eksik olan tek satırlar kararsız bir testin yeniden denemede ulaştığı ancak ilk denemesinde ulaşmadığı satırlardır.
- **Fork'lardan gelen pull request'lerden kapsama yok.** Kapsama yalnızca Tuist ile kimlik doğrulaması yapan çalıştırmalar tarafından yüklenir ve CI genellikle fork'lardan açılan pull request'lerde gizli anahtarları ve kimlik belirteçlerini tuttuğundan, bu çalıştırmalar kapsama bildirmez. Birleştirildikten sonra, commit kimlik bilgileriyle dalınızda çalışır ve kapsama oranını her zamanki gibi bildirir.

## Kapsama sorgulama {#querying}

Panonun **Kod Kapsama** sayfası, her commit'in rakamını, uygulamalarını ve dosyalarını, her çalıştırmanın kapsadığı satırlarla birlikte gösterir. Aynı verilere ajanlar <.localized_link href="/guides/features/agentic-coding/mcp">Model Context Protocol sunucusu</.localized_link> aracılığıyla erişebilir.
