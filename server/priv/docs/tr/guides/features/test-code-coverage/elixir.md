---
{
  "title": "Elixir Kod Kapsamı",
  "titleTemplate": ":title · Kod Kapsamı · Özellikler · Rehberler · Tuist",
  "description": "Elixir projenizin satır kapsamını mix test --cover ile yükleyin ve dosya, uygulama ve commit bazında takip edin."
}
---
# Elixir kod kapsamı {#elixir-code-coverage}

Kod kapsamı, testlerinizin kodunuzun hangi satırlarını çalıştırdığını gösterir. Hex paketi her bir `mix test --cover` çalıştırmasının satır kapsamını yükler ve Tuist, bir commit'in çalıştırmalarını proje, her OTP uygulaması ve her dosya için tek bir rakamda birleştirir. Panonun **Kod Kapsamı** sayfası bunu commit bazında ve her dal için bir eğilim olarak gösterir.

> [!IMPORTANT]
> **Gereksinimler**
>
> - Paket üzerinden `mix test` yönlendiren <.localized_link href="/guides/get-started/elixir-project">paylaşılan Elixir kurulumunu</.localized_link> tamamlayın

## Kurulum {#setup}

### Testlerinizi kapsamlı çalıştırın {#run-your-tests}

Tuist olmadan `mix test` komutuna verdiğiniz gibi `--cover` parametresini ekleyin:

```sh
mix test --cover
```

Paket, kapsamı çalıştırmanın test sonuçlarıyla birlikte yükler. Test paketi tamamlandığında, aynı `test_coverage` seçenekleriyle yapılandırılmış Mix'in kapsam aracının yaptığını da yapar:

- **Özet.** Her modülün ve toplamın kapsamını yazdırır. `summary: false` bunu kapatır.
- **Eşik.** Toplam eşik değerinin altına düştüğünde çalıştırmayı çıkış durumu 3 ile başarısız kılar; siz ayarlamadığınız sürece bu değer %90'dır:

```elixir
def project do
  [
    test_coverage: [summary: [threshold: 80]]
  ]
end
```

Mix'te olduğu gibi eşik özete aittir, bu nedenle `summary: false` her ikisini de kapatır. Çalıştırmayı başarısız kılmadan özeti yazdırmak için `threshold: 0` ayarlayın. `test_coverage: [ignore_modules: [...]]` içinde listelenen modüller özetten ve yüklemeden hariç tutulur.

Tuist kapsamı commit başına izler, bu nedenle projenizin bir Git deposunda olması gerekir: Depo dışındaki bir çalıştırma test sonuçlarını yükler ancak kapsamı yüklemez.

Kapsam, paketin yüklediği ve commit'i dalına yerleştiren <.localized_link href="/guides/features/test-insights/elixir#git-history">Git geçmişine</.localized_link> dayanır. Sürekli entegrasyondaki çalıştırmalar bunu her zaman yükler ve `--cover` çalıştırmaları bunu herhangi bir makinede yükler. `--cover` ile paket ayrıca bir pull request'in nereden dallandığını bulur: temel dalı getirir ve sığ klonu gerektiği kadar derinleştirir. Sürekli entegrasyonda, sığ bir checkout da Tuist'in zaten sahip olduğu commit'lere ulaşana kadar dosya içerikleri olmadan derinleştirilir, böylece bir commit asla üzerine oturduğu ebeveyni olmadan yüklenmez. Uzak sunucuya bağlanmasını engellemek için `TUIST_GIT_UNSHALLOW_ENABLED=false` ayarlayın.

### Parçalı çalıştırmalar {#sharded-runs}

Testlerinizi <.localized_link href="/guides/features/test-sharding/elixir">parçalara böldüğünüzde</.localized_link>, her parçayı `--cover` ile çalıştırın:

```sh
MIX_ENV=test TUIST_SHARD_INDEX=0 mix tuist.test --cover
```

Yeni bir çalıştırıcıda, shard'ın build'ini indirmeden önce Mix'in her bağımlılığı derlemesini engelleyen parçalama kılavuzundaki <.localized_link href="/guides/features/test-sharding/elixir#test-phase">test aşamasından</.localized_link> bootstrap komutunu kullanın ve buna `--cover` ekleyin.

Bir shard yalnızca kendi kapsamını bildirir ve test paketinin bir kısmını çalıştırdığı için eşik değerini kontrol etmez. Tuist, bir çalıştırmanın shard'larını tek bir rakamda birleştirir.

Her shard, indirdiği build'e kapsam sayaçlarını ekler. Bunun yerine bunu bir kez yapmak için, build aşamasına da `--cover` parametresini iletin:

```sh
MIX_ENV=test mix tuist.test.build --shard-max 5 --cover
```

Pipeline çalıştırmaları arasında build dizinini koruyup kapsam toplamayan çalıştırmalarda yeniden kullandığınızda bunu devre dışı bırakın, böylece o build sayaçsız kalır.

### CI'da her commit'i tamamlayın {#complete-each-commit}

Bir commit'in kapsamı genellikle birkaç job'dan gelir: shard başına, veritabanı sürümü başına veya uygulama başına bir tane. Tuist bunların hangisinin en son raporladığını bilemez, bu yüzden ona siz bildirin. Bir commit için tüm test job'ları tamamlandığında, hepsine bağımlı olan bir job'da şunu çalıştırın:

```sh
MIX_ENV=test mix tuist.coverage.complete
```

Görev, commit'i `GIT_COMMIT` veya checkout'un `HEAD` değerinden okur; başka birini belirtmek için `--commit <sha>` parametresini iletin. Bir commit tamamlanana kadar kapsamı **Devam ediyor** olarak görünür ve dalının eğilimine dahil edilmez.

## Nasıl çalışır {#how-it-works}

### Yerel satır sayaçları {#native-line-counters}

Mix'in kapsam aracı, her çalıştırmanın başında Erlang'ın `cover` özelliği için her modülü yeniden derler; bu büyük projelerde yavaşlar. Paket bunun yerine çalışma zamanının yerel satır sayaçlarını kullanır. Son çalıştırmadan bu yana bir derlemenin yazdığı modülleri yalnızca yeniden derler, çalışma zamanını bu sayaçlara geçirir ve test paketi bittiğinde onları okur. Mix'in kapsam aracı devre dışı bırakılır, ancak özeti ve eşiği korunur.

Paket, aynı yüklemeyle Mix'in kapsam aracına şu durumlar için geri döner:

- Şemsiye projesinin kök dizini. Yerel sayım yapmak için testleri her uygulamanın içinde çalıştırın.
- Kendi `test_coverage: [tool: ...]` ayarını yapan bir proje.
- JIT içermeyen ve yerel sayım yapamayan bir çalışma zamanı.

### Tuist'in ölçtüğü şeyler {#what-tuist-measures}

- **Uygulamalar.** Her OTP uygulaması, kendi kapsamıyla panoda bir hedeftir.
- **Yalnızca ürün kodu.** Test yollarınız altındaki dosyalar test kodudur. Tuist bunları saklar ancak her rakamdan hariç tutar.
- **Dosya başına satır.** Bir satır, kaç modüle ait olduğundan bağımsız olarak dosya başına bir kez sayılır.
- **Fonksiyonlar.** Her satır, yukarısında en yakın başlayan klauza sahip olduğu fonksiyona aittir. Derleyicinin veya bir makronun ürettiği `__info__/1` veya `__schema__/1` gibi fonksiyonlar listelenmez, ancak satırları yine de dosyaları için sayılır.

Bu nedenle Tuist'in rakamları Mix'in kendi kapsam raporundan birkaç şekilde farklılık gösterir: test kodunu hariç tutar ve satırları modül başına değil dosya başına sayar. Yerel sayım ayrıca uygulamanız başlarken çalışan kodu görür ve derleyicinin asla çalışmayacağını kanıtladığı satırları hariç tutar; Mix'in aracı bunları hiç kapsanmamış olarak raporlar.

### Atlanan testler {#skipped-tests}

Tuist, bir çalıştırmanın hariç tuttuğu testlerin kapsamını taşıyamaz: paket her testin ne çalıştırdığını değil, tüm çalıştırmanın ne yürüttüğünü kaydeder. Bu nedenle, bir çalıştırmanın kendi argümanları `--only`, `--exclude`, `--failed`, `--stale`, `--name-pattern`, `--max-failures` veya test dosyaları ya da satırlarıyla testleri hariç tuttuğunda, commit'in kapsamı **Eksik** olur;除非 hiçbir şeyi hariç tutmayan aynı varyantın bir çalıştırması da yapılmışsa. Her biri testleri hariç tutan iki çalıştırma, örneğin `--exclude slow` ve `--only slow`, birlikte her testi çalıştırsalar bile commit'i eksik bırakır.

Bazı testler kasıtlı olarak hariç tutulur ve bir commit'i eksik hale getirmez:

- **Test yardımcınızın hariç tutmaları.** `ExUnit.start(exclude: [...])` tarafından varsayılan olarak hariç tutulan testler, projenizin paketinin varsayılan olarak neyi çalıştırdığına dair seçimidir, bu nedenle Tuist bunları eksik olarak saymaz. Kapsamlarını commit'e eklemek için bunları başka bir job'da `--include` veya `--only` ile çalıştırın.
- **Kodda atlanan testler** `@tag :skip` ile.
- **<.localized_link href="/guides/features/test-insights/flaky-tests/elixir#quarantining">Karantina</.localized_link> tarafından atlanan testler.** Bunlar kaldırılmış gibi hariç tutulur, bu nedenle yalnızca bunların kapsadığı satırlar kapsam dışı olarak sayılır.

### Tam ve eksik commit'ler {#commit-status}

Panodaki her commit'in bir durumu vardır:

| Durum | Anlamı |
| --- | --- |
| Devam ediyor | Çalıştırmalar kapsam bildirdi, ancak `mix tuist.coverage.complete` henüz commit için çalıştırılmadı. |
| Tamamlandı | Commit'in çalıştırmalarındaki her test çalıştırıldı veya kasıtlı olarak hariç tutuldu. |
| Eksik | Bazı kapsamlar belirlenemedi, bu nedenle rakam alt sınırdır. |
| Ölçülmedi | Hiçbir çalıştırma commit için kapsam bildirmedi. |

Bir dalın eğilimi yalnızca tamamlanmış commit'leri içerir. Bir commit şu durumlarda eksiktir, örneğin:

- Bir varyantın her çalıştırması kendi argümanlarıyla testleri hariç tuttu.
- Bir varyantın her çalıştırmasında bazı shard'lar eksikti.
- Bir varyantın kapsamı yalnızca işlenmemiş değişikliklere sahip bir checkout üzerindeki CI çalıştırmalarından geldi.

Varyant, `--scheme` ile geçtiğiniz etikettir, örneğin bir veritabanı sürümü. Etiketsiz çalıştırmalar tek bir varyanttır. Commit'in rakamı her çalıştırmayı birleştirir, ancak Tuist her varyantın tamlığını ayrı ayrı kontrol eder, bu nedenle her varyantın hiçbir şeyi hariç tutmayan bir çalıştırmaya ihtiyacı vardır.

## Performans etkisi {#performance-impact}

Kapsam toplamak ek yük getirir, bu nedenle `--cover` içeren çalıştırmalar onu içermeyenlerden daha uzun sürer. İlk çalıştırma modüllerinizi satır sayaçlarıyla yeniden derler; sonraki çalıştırmalar yalnızca değişenleri yeniden derler, bu nedenle maliyetleri çok daha düşüktür. Büyük projelerde yerel sayım ayrıca Mix'in kapsam aracından çok daha hızlıdır.

## Sınırlamalar {#limitations}

- **HTML raporu yok.** Yerel sayım `test_coverage: [output: ...]` dizinine rapor yazmaz ve biri ayarlandığında çalıştırma uyarı verir. Bunun yerine panonun dosya sayfaları kapsanan satırları gösterir.
- **Yeniden denemeler kapsam eklemez.** <.localized_link href="/guides/features/test-insights/flaky-tests/elixir#test-retries">Test yeniden denemeleri</.localized_link> ile kapsam ilk denemeninkidir. Bu deneme başarısız testleri zaten çalıştırdı, bu nedenle eksik olan tek satırlar kararsız bir testin yeniden denemede ulaştığı ancak ilk denemesinde ulaşmadığı satırlardır.
- **Fork'lardan gelen pull request'lerden kapsam yok.** Kapsam yalnızca Tuist ile kimlik doğrulaması yapan çalıştırmalar tarafından yüklenir ve CI genellikle fork'lardan açılan pull request'lerden gizli anahtarları ve kimlik belirteçlerini esirger, bu nedenle bu çalıştırmalar kapsam bildirmez. Birleştirildikten sonra, commit kimlik bilgileriyle dalınızda çalışır ve kapsamını normal şekilde bildirir.

## Kapsam sorgulama {#querying}

Pano'nun **Kod Kapsamı** sayfası her commit'in rakamını, uygulamalarını ve dosyalarını, her çalıştırmanın kapsadığı satırlarla birlikte gösterir. Aynı verilere ajanlar <.localized_link href="/guides/features/agentic-coding/mcp">Model Context Protocol sunucusu</.localized_link> aracılığıyla erişebilir.
