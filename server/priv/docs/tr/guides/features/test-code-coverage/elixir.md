---
{
  "title": "Elixir Kod Kapsamı",
  "titleTemplate": ":title · Kod Kapsamı · Özellikler · Kılavuzlar · Tuist",
  "description": "mix test --cover ile Elixir projenizin satır kapsamını yükleyin ve dosya, uygulama ve commit bazında takip edin."
}
---
# Elixir kod kapsama oranı {#elixir-code-coverage}

Kod kapsama oranı, testlerinizin kodunuzun hangi satırlarını çalıştırdığını gösterir. Hex paketi her bir `mix test --cover` çalıştırmasının satır kapsama oranını yükler ve Tuist, bir commit'in çalıştırmalarını proje, her OTP uygulaması ve her dosya için tek bir rakamda birleştirir. Dashboard'un **Kod Kapsama Oranı** sayfası bunu commit bazında ve her branch için bir trend olarak gösterir.

> [!IMPORTANT]
> **Gereksinimler**
>
> - Paket üzerinden `mix test` yönlendiren <.localized_link href="/guides/get-started/elixir-project">ortak Elixir kurulumunu</.localized_link> tamamlayın

## Kurulum {#setup}

### Testlerinizi kapsama oranı ile çalıştırın {#run-your-tests}

Tuist olmadan `mix test` komutuna verdiğiniz gibi `--cover` parametresini ekleyin:

```sh
mix test --cover
```

Paket, çalıştırmanın test sonuçlarıyla birlikte kapsama oranını yükler. Test paketi tamamlandığında, aynı `test_coverage` seçenekleriyle yapılandırılmış Mix'in kapsama aracının yaptığını da yapar:

- **Özet.** Her modülün ve toplamın kapsama oranını yazdırır. `summary: false` bunu kapatır.
- **Eşik.** Toplam eşik değerinin altına düştüğünde çalıştırmayı çıkış durumu 3 ile başarısız kılar; siz başka bir değer belirlemediyseniz bu %90'dır:

```elixir
def project do
  [
    test_coverage: [summary: [threshold: 80]]
  ]
end
```

Mix'te olduğu gibi eşik değeri özete aittir, bu nedenle `summary: false` her ikisini de kapatır. Çalıştırmayı başarısız kılmadan özeti yazdırmak için `threshold: 0` ayarlayın. `test_coverage: [ignore_modules: [...]]` içinde listelenen modüller özetten ve yüklemeden hariç tutulur.

Tuist kapsama oranını commit bazında izler, bu nedenle projenizin bir Git deposunda olması gerekir: Bir Git deposu dışındaki bir çalıştırma test sonuçlarını yükler ancak kapsama oranını yüklemez.

Kapsama oranı, paketin yüklediği ve commit'i branch'ine yerleştiren <.localized_link href="/guides/features/test-insights/elixir#git-history">Git geçmişine</.localized_link> dayanır. Sürekli entegrasyon üzerindeki çalıştırmalar bunu her zaman yükler ve `--cover` çalıştırmaları bunu herhangi bir makinede yükler. `--cover` ile paket, bir pull request'in nereden dallandığını da bulur: temel branch'i getirir ve sığ klonu gerektiği kadar derinleştirir. Uzaktan sunucuyla iletişim kurmasını engellemek için `TUIST_GIT_UNSHALLOW_ENABLED=false` ayarlayın.

### Parçalı çalıştırmalar {#sharded-runs}

Testlerinizi <.localized_link href="/guides/features/test-sharding/elixir">parçalara böldüğünüzde</.localized_link>, her parçayı `--cover` ile çalıştırın:

```sh
MIX_ENV=test TUIST_SHARD_INDEX=0 mix tuist.test --cover
```

Yeni bir runner üzerinde, parçalama rehberinin <.localized_link href="/guides/features/test-sharding/elixir#test-phase">test aşamasından</.localized_link> bootstrap komutunu kullanın; bu, parça build'ini indirmeden önce Mix'in tüm bağımlılıkları derlemesini engeller ve buna `--cover` ekleyin.

Bir parça yalnızca kendi kapsama oranını bildirir ve test paketinin bir kısmını çalıştırdığı için eşik değerini kontrol etmez. Tuist, bir çalıştırmanın parçalarını tek bir rakamda birleştirir.

Her parça, indirdiği build'e kapsama sayaçlarını ekler. Bunun yerine bunu bir kez yapmak için build aşamasına da `--cover` parametresini iletin:

```sh
MIX_ENV=test mix tuist.test.build --shard-max 5 --cover
```

Pipeline çalıştırmaları arasında build dizinini koruyup bunu kapsama toplamayan çalıştırmalarda yeniden kullandığınızda bu parametreyi kapalı bırakın, böylece o build sayaçsız kalır.

### CI üzerinde her commit'i tamamlayın {#complete-each-commit}

Bir commit'in kapsama oranı genellikle birkaç job'dan gelir: parça başına, veritabanı sürümü başına veya uygulama başına bir tane. Tuist bunların hangisinin sonuncusunun raporladığını bilemez, bu yüzden siz bildirin. Bir commit için tüm test job'ları tamamlandığında, hepsine bağımlı olan bir job'da şunu çalıştırın:

```sh
MIX_ENV=test mix tuist.coverage.complete
```

Görev, commit'i `GIT_COMMIT` veya checkout'un `HEAD` değerinden okur; başka birini belirtmek için `--commit <sha>` parametresini iletin. Bir commit tamamlanana kadar kapsama oranı **Devam ediyor** olarak gösterilir ve branch'in trendine dahil edilmez.

## Nasıl çalışır {#how-it-works}

### Yerel satır sayaçları {#native-line-counters}

Mix'in kapsama aracı, her çalıştırmanın başında Erlang'ın `cover` özelliği için her modülü yeniden derler; bu büyük projelerde yavaşlar. Paket bunun yerine runtime'ın yerel satır sayaçlarını kullanır. Son çalıştırmadan bu yana bir derlemenin yazdığı modülleri yalnızca yeniden derler, runtime'ı bu sayaçlara geçirir ve test paketi bittiğinde bunları okur. Mix'in kapsama aracı devre dışı bırakılır ancak özeti ve eşik değeri korunur.

Paket, aynı yüklemeyle Mix'in kapsama aracına aşağıdaki durumlar için geri döner:

- Bir umbrella projesinin kök dizini. Yerel sayım yapmak için testleri her uygulamanın içinde çalıştırın.
- Kendi `test_coverage: [tool: ...]` ayarını yapan bir proje.
- JIT olmayan bir runtime, ki yerel sayım yapamaz.

### Tuist'in ölçtüğü şeyler {#what-tuist-measures}

- **Uygulamalar.** Her OTP uygulaması dashboard'da kendi kapsama oranına sahip bir hedeftir.
- **Yalnızca ürün kodu.** Test yollarınız altındaki dosyalar test kodudur. Tuist bunları saklar ancak her rakamdan hariç tutar.
- **Dosya başına satır.** Bir satır, kaç modüle ait olduğundan bağımsız olarak dosya başına bir kez sayılır.
- **Fonksiyonlar.** Her satır, yukarısında en yakın başlayan clause'a sahip fonksiyona aittir. Derleyicinin veya bir makronun ürettiği `__info__/1` veya `__schema__/1` gibi fonksiyonlar listelenmez ancak satırları yine de dosyaları için sayılır.

Bu nedenle Tuist'in rakamları Mix'in kendi kapsama raporundan birkaç şekilde farklılık gösterir: test kodunu hariç tutarlar ve satırları modül başına değil dosya başına sayarlar. Yerel sayım ayrıca uygulamanız başlarken çalışan kodu görür ve derleyicinin asla çalışmayacağını kanıtladığı satırları hariç tutar; Mix'in aracı bunları hiç kapsanmamış olarak raporlar.

### Atlanan testler {#skipped-tests}

Tuist, bir çalıştırmanın hariç tuttuğu testlerin kapsama oranını ilerleteemez: paket, her testin neyi çalıştırdığını değil, tüm çalıştırmanın neyi yürüttüğünü kaydeder. Bu nedenle, bir çalıştırmanın kendi argümanları `--only`, `--exclude`, `--failed`, `--stale`, `--name-pattern`, `--max-failures` veya test dosyaları ya da satırları ile testleri hariç tuttuğunda, commit'in kapsama oranı **Tamamlanmamış** olur;除非 hiçbir şeyi hariç tutmayan aynı varyantın bir çalıştırması da gerçekleşmişse. Her biri testleri hariç tutan iki çalıştırma, örneğin `--exclude slow` ve `--only slow`, birlikte her testi çalıştırsalar bile commit'i yine de tamamlanmamış yapar.

Bazı testler kasıtlı olarak hariç tutulur ve commit'i tamamlanmamış yapmaz:

- **Test yardımcınızın hariç tutmaları.** Varsayılan olarak `ExUnit.start(exclude: [...])` tarafından hariç tutulan testler, projenizin paketinin varsayılan olarak neyi çalıştıracağına dair seçimidir, bu nedenle Tuist bunları eksik olarak saymaz. Kapsama oranlarını commit'e eklemek için bunları başka bir job'da `--include` veya `--only` ile çalıştırın.
- **Kodda atlanan testler** (`@tag :skip` ile).
- **<.localized_link href="/guides/features/test-insights/flaky-tests/elixir#quarantining">karantina</.localized_link>nın atladığı testler.** Bunlar, kaldırılmış gibi hariç tutulur; bu nedenle yalnızca bunların kapsadığı satırlar kapsanmamış olarak sayılır.

### Tamamlanmış ve tamamlanmamış commit'ler {#commit-status}

Dashboard'daki her commit'in bir durumu vardır:

| Durum | Anlamı |
| --- | --- |
| Devam ediyor | Çalıştırmalar kapsama oranını bildirdi ancak `mix tuist.coverage.complete` henüz commit için çalıştırılmadı. |
| Tamamlandı | Commit'in çalıştırmalarındaki her test çalıştırıldı veya kasıtlı olarak hariç tutuldu. |
| Tamamlanmadı | Bazı kapsama oranları belirlenemedi, bu nedenle rakam bir alt sınırdır. |
| Ölçülmedi | Hiçbir çalıştırma commit için kapsama oranı bildirmedi. |

Bir dalın trendi yalnızca tamamlanmış commit'leri içerir. Bir commit örneğin şu durumlarda tamamlanmamıştır:

- Bir varyantın her çalıştırması kendi argümanlarıyla testleri hariç tuttu.
- Bir varyantın her çalıştırmasında bazı shard'lar eksikti.
- Bir varyantın kapsama oranı yalnızca commit edilmemiş değişikliklere sahip bir checkout üzerindeki CI çalıştırmalarından geldi.

Varyant, `--scheme` ile geçtiğiniz etikettir; örneğin bir veritabanı sürümü. Etiketsiz çalıştırmalar tek bir varyanttır. Commit'in rakamı her çalıştırmayı birleştirir ancak Tuist her varyantın tamlığını ayrı ayrı kontrol eder; bu nedenle her varyantın hiçbir şeyi hariç tutmayan bir çalıştırmaya ihtiyacı vardır.

## Performans etkisi {#performance-impact}

Kapsama toplamak ek yük getirir, bu nedenle `--cover` içeren çalıştırmalar onu içermeyenlerden daha uzun sürer. İlk çalıştırma modüllerinizi satır sayaçlarıyla yeniden derler; sonraki çalıştırmalar yalnızca değişenleri yeniden derler, bu nedenle maliyetleri çok daha düşüktür. Büyük projelerde yerel sayım, Mix'in kapsama aracından çok daha hızlıdır.

## Sınırlamalar {#limitations}

- **HTML raporu yok.** Yerel sayım `test_coverage: [output: ...]` dizinine rapor yazmaz ve biri ayarlandığında çalıştırma uyarı verir. Bunun yerine dashboard'un dosya sayfaları kapsanan satırları gösterir.
- **Yeniden denemeler kapsama eklemez.** <.localized_link href="/guides/features/test-insights/flaky-tests/elixir#test-retries">Test yeniden denemeleri</.localized_link> ile kapsama oranı ilk denemeninkidir. Bu deneme başarısız testleri zaten çalıştırdığından eksik olan tek satırlar, kararsız bir testin yeniden denemede ulaştığı ancak ilk denemesinde ulaşmadığı satırlardır.
- **Fork'lardan gelen pull request'lerden kapsama yok.** Kapsama yalnızca Tuist ile kimlik doğrulaması yapan çalıştırmalar tarafından yüklenir ve CI genellikle fork'lardan açılan pull request'lerde gizli anahtarları ve kimlik belirteçlerini withhold eder, bu nedenle bu çalıştırmalar kapsama bildirmez. Birleştirildikten sonra commit, kimlik bilgileriyle dalınızda çalışır ve kapsama oranını her zamanki gibi bildirir.

## Kapsama sorgulama {#querying}

Dashboard'un **Kod Kapsama** sayfası, her çalıştırmanın kapsadığı satırlarla birlikte her commit'in rakamını, uygulamalarını ve dosyalarını gösterir. Aynı verilere ajanlar <.localized_link href="/guides/features/agentic-coding/mcp">Model Context Protocol sunucusu</.localized_link> üzerinden erişebilir.
