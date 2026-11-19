---
{
  "title": "Oluşturulan Xcode projesi",
  "titleTemplate": ":title · Kod Kapsamı · Özellikler · Kılavuzlar · Tuist",
  "description": "İkili önbelleğin ve seçici testin atladığı kodlar dahil olmak üzere, Tuist tarafından oluşturulan bir Xcode projesinin kod kapsamını dosya bazında ve commit bazında ölçün."
}
---
# Oluşturulan Xcode projesi {#generated-xcode-project-code-coverage}

Kod kapsamı, testlerinizin kodunuzun hangi satırlarını çalıştırdığını gösterir. Tuist, her `tuist test` çalıştırmasının satır kapsamını yükler ve bir commit'in çalıştırmalarını proje, her hedef ve her dosya için tek bir rakamda birleştirir. Gösterge panelinin **Kod Kapsamı** sayfası bunu commit başına ve her dal için bir trend olarak gösterir.

<!-- @snippet: ./_xcode-requirements -->

Tuist iş atladığında bile rakam doğru kalır. <.localized_link href="/guides/features/cache/module-cache">ikili önbellek</.localized_link>ten gelen hedefleriniz kapsam sayaçlarıyla derlenir, böylece kodları kaynak koddan derlenen kod gibi ölçülür. Ve <.localized_link href="/guides/features/selective-testing/generated-xcode-project">seçici test</.localized_link> bir test hedefini atladığında, hedef daha önceki bir çalıştırmada sahip olduğu kapsamı, Tuist'in her çalıştırmada kaydettiği [hedef düzeyi kapsam](#target-level-coverage) aracılığıyla korur.

## Kurulum {#setup}

### Kapsamı açın {#turn-coverage-on}

`Tuist.swift` dosyanızın oluşturma seçeneklerinde kapsamı açın ve varsayılan olarak kapalı olan kapsam yüklemeyi etkinleştirin:

```swift
import ProjectDescription

let tuist = Tuist(
    testInsights: .testInsights(coverage: .coverage(upload: true)),
    project: .tuist(
        generationOptions: .options(
            coverage: .coverage(enabled: true)
        )
    )
)
```

Oluşturma seçeneği açıkken:

- Tuist'in oluşturduğu her şemanın test eylemi kapsam toplar ve sizin tanımladığınız, `coverage` ayarını boş bırakan her şemanın test eylemi de aynı şekilde davranır. `.options(coverage: false)` veya `.options(coverage: true)` içeren bir şema kendi değerini korur. Test planları kapsamı kendileri belirler: Tuist'in oluşturduğu test planları için `coverage: true` parametresini `.testPlans(_:coverage:)` öğesine iletin.
- Projenizin kendi hedefleri, Debug yapılandırmalarında kapsam sayaçlarıyla ikili önbellekten okunur ve önbelleğe alınır. Bkz. [Nasıl çalışır](#instrumented-binaries).

`TUIST_COVERAGE_ENABLED` ve `TUIST_COVERAGE_UPLOAD` ortam değişkenleri (`1` veya `0`), `enabled` ve `upload` ayarlarından önceliklidir. Bunları tek bir komut yerine, tüm bir ortam (örneğin bir CI iş akışı) için ayarlayın; böylece önbelleği ısıtan komutlar ile onu okuyan komutlar uyumlu olur.

> [!IMPORTANT] KEEP THE VALUE THE SAME EVERYWHERE
> Oluşturma seçeneği, projenizin hedeflerinin önbellek anahtarlarını ve test hedeflerinin seçici test hash'lerini değiştirir. Önbelleği paylaşan her makinede aynı değeri kullanın ve bunu ortamdan (örneğin `Environment.isCI` üzerinden) türetmeyin. Kapsamı kapalı olan bir çalıştırma, kapsamı açık olan çalıştırmaların ikili dosyalarını veya seçici test sonuçlarını yeniden kullanmaz.

### Şemaları dışarıda bırakın {#leave-schemes-out}

Bazı test paketleri kapsamınıza dahil olmamalıdır. Örneğin, uygulamanızı veya CLI'nizi başka bir süreçten süren kabul veya uçtan uca testler, kapsamın göremeyeceği kodu çalıştırır ve bunların toplanması yalnızca yavaşlamalarına neden olur. Şemalarının test eyleminde kapsamı kapatın:

```swift
.scheme(
    name: "AcceptanceTests",
    testAction: .targets(
        ["AcceptanceTests"],
        options: .options(coverage: false)
    )
)
```

Şema, `Tuist.swift` seçeneği veya `TUIST_COVERAGE_ENABLED` ne derse desin kapsamı kapalı tutar ve onun çalıştırmaları bir commit'in kapsamına sayılmaz. Kapsam şema başına toplanır; bu nedenle bir test hedefini dışarıda bırakmak için onu kendi şemasına taşıyın.

### Testlerinizi çalıştırın {#run-your-tests}

Testlerinizi her zamanki gibi `tuist test` ile çalıştırın:

```sh
tuist test
```

Tuist, çalıştırmanın topladığı kapsamı test sonuçlarıyla birlikte yükler. Bu, <.localized_link href="/guides/features/test-sharding/generated-xcode-project">parçalı çalıştırmaları</.localized_link> ve başka bir job'da `--without-building` ile derlenen ürünleri test eden çalıştırmaları içerir. Bir çalıştırmanın kapsamının Tuist'e yüklenmemesini sağlamak için (örneğin fork'lardan gelen pull request'leri çalıştıran job'larda) `TUIST_COVERAGE_UPLOAD=0` ayarını yapın.

### CI'da her commit'i tamamlayın {#complete-each-commit}

Bir commit'in kapsamı genellikle birkaç job'dan gelir: şema başına, parça başına veya platform başına bir tane. Tuist, bunlardan sonuncusunun rapor verdiğini anlayamaz, bu yüzden siz bildirin. Bir commit için tüm test job'ları bittiğinde, hepsine bağımlı olan bir job'da şunu çalıştırın:

```sh
tuist coverage complete
```

Komut, checkout'un `HEAD` değerinden, yani testlerinizin çalıştığı commit'ten okuma yapar; başka birini belirtmek için `--commit <sha>` parametresini kullanın. Bir commit tamamlanana kadar, kapsamı **Devam ediyor** olarak görünür ve dalının trendine dahil edilmez.

### Tüm paketi varsayılan dalınızda çalıştırın {#full-runs}

> [!IMPORTANT] SET UP A FULL RUN
> Seçici test, atlanan hedefleri taşıyacak daha önceki bir çalıştırma varsa ancak bir commit'in kapsamını tam tutar. Varsayılan dalınızda, seçici test olmadan her testin bir çalıştırmasını zamanlayın:
>
> ```sh
> tuist test --no-selective-testing
> ```
>
> Her birleştirmede bir kez çalıştırmak idealdir. Az değişiklik yapılan bir depo için günlük veya haftalık yeterli olabilir. Kaydedilen kapsam 31 gün sonra sona erer, bu nedenle bundan daha sık çalıştırın.

Taşınan kapsam, tam çalıştırmalara dayanır. Tam çalıştırmalar, her hedefin kaydedilen kapsamını süresi dolmadan yeniler ve seçici bir çalıştırmanın derlemediği dosyaların güncel durumunu Tuist'e sağlar. Bir depo, tam çalıştırmalar arasında ne kadar çok değişirse, seçici bir çalıştırma o sıklıkta değişmiş bir dosya bulur ve commit'in kapsamı **Eksik** olur.

## Hedef düzeyi kapsam {#target-level-coverage}

Bir çalıştırmanın kapsamı, tüm çalıştırmanın neyi yürüttüğünü söyler, her test hedefinin neyi yürüttüğünü değil. Seçici test bir hedefi atladığında, Tuist'in kapsamını ileri taşımak için o hedefin daha önceki bir çalıştırmada neyi yürüttüğünü bilmesi gerekir.

Bu nedenle Tuist, her çalıştırmada her test hedefinin hangi dosyaları ve satırları yürüttüğünü de kaydeder. Bunları, Xcode'un her test süreci için yazdığı kapsamdan okur; bu nedenle bağlanacak veya yapılandırılacak bir şey yoktur. Bu kayıt macOS ve iOS simülatöründe yapılır, cihazlarda yapılmaz. UI testleri, sürdükleri uygulama hakkında hiçbir şey kaydetmez çünkü uygulamanın kodu kendi sürecinde çalışır.

## Nasıl çalışır {#how-it-works}

### Enstrümantal ikili dosyalar {#instrumented-binaries}

İkili önbellekten gelen bir hedef, önceden derlenmiş bir ikili dosyadır ve bir test çalıştırması yalnızca ikili dosya kapsam sayaçlarıyla derlendiyse kodunu ölçebilir. Kapsam açıkken, ikili önbellek projenizin kendi hedeflerinin enstrümantal varyantını saklar ve her komut bu varyantı okur ve önbelleğe alır:

- **Debug yapılandırmaları** enstrümantal varyantı kullanır: `tuist cache` onu önbelleğe alır, `tuist generate` ve `tuist test` ise onu okur.
- **Release yapılandırmaları** her zaman düz varyantı kullanır, bu nedenle dağıttığınız ürünler asla kapsam sayaçları taşımaz.
- **Harici paketler** her zaman düz varyantı kullanır. Tuist yalnızca deponuzun kodunu ölçer.

Önbelleği, test job'larınızla aynı ortamda kapsam açıkken ısıtın; böylece `tuist test` enstrümantal ikili dosyaları bulur. Bir çalıştırma kapsam toplar ancak hedeflerinizi önbellekten düz ikili dosyalar olarak alırsa, Tuist sizi uyarır ve kodları ölçülmez. <.localized_link href="/guides/features/cache/module-cache#code-coverage">modül önbelleği</.localized_link> varyantları ayrıntılı olarak belgeler.

### Makineler arası yollar {#paths-across-machines}

Enstrümantal ikili dosyalar, kaynak yollarını derlendikleri checkout'a göre göreceli olarak kaydeder; bu nedenle CI'da önbelleğe alınan bir ikili dosya, herhangi bir geliştiricinin makinesinde doğru dosyaları ölçer.

<.localized_link href="/guides/features/cache/xcode-cache">Xcode önbelleği</.localized_link>, ön ek eşlemesi yoluyla aynı şekilde çalışır; Tuist bunu kapsam toplayan derlemelerde varsayılan olarak kapatır çünkü Xcode'un kendi kapsam raporu eşlenen yolları çözümleyemez. Xcode 27 ve sonraki sürümlerde, `enableCaching` açıkken `prefixMapping: true` bunu açık tutar, böylece kapsam derlemeleri derleme sonuçlarını checkout'lar arasında da paylaşır:

```swift
.options(coverage: .coverage(enabled: true, prefixMapping: true))
```

Tuist'in yüklemesi eşlenen yolları çözer, ancak Xcode'un kapsam raporu ve `xccov` bu dosyaları dışarıda bırakabilir. Bkz. <.localized_link href="/guides/features/cache/xcode-cache#coverage-with-prefix-mapping">Ön ek eşlemeli kapsam</.localized_link>.

### Atlanan testler {#skipped-tests}

Seçici test, daha önceki başarılı bir çalıştırma aynı hash ile zaten test ettiyse bir test hedefini atlar. Hash, hedefin kaynaklarını, testlerini ve tüm bağımlılıklarını kapsar; bu nedenle aynı hash, aynı kod üzerinde aynı testler anlamına gelir. Tuist, o önceki çalıştırmanın hedef için kaydettiği [hedef düzeyi kapsam](#target-level-coverage) verisini yeniden kullanır. Eğer hiçbir şey kaydedilmediyse (örneğin o sırada kapsam kapalıydı veya çalıştırma 31 günden eskiyse), taşınacak bir veri yoktur ve commit **Eksik** olarak işaretlenir.

Seçici bir çalıştırma ayrıca her dosyayı derlemez. Derlemediği dosyalar için Tuist, dosyalar o zamandan beri değişmediği sürece satırları en yakın önceki tam çalıştırmadan alır. Bu nedenle varsayılan dalınızdaki [tam çalıştırmalar](#full-runs) önemlidir.

`--skip-test-targets` veya `-skip-testing` ile kendinizin atladığı testler ileri taşınmaz: Çalıştırmaları bunları dışarıda bırakan bir commit, o commit'te başka bir çalıştırma bunları yürütmedikçe **Eksik** olur. Karantinaya alınan testler kapsamın parçası değildir: Tuist bunları ne taşır ne de commit'i bunlar nedeniyle **Eksik** olarak işaretler.

### Tamamlanan ve eksik commit'ler {#commit-status}

Panodaki her commit'in bir durumu vardır:

| Durum | Anlamı |
| --- | --- |
| Devam ediyor | Çalıştırmalar kapsam bildirdi, ancak `tuist coverage complete` henüz commit için çalıştırılmadı. |
| Tamamlandı | Commit'in şemalarının her testi çalıştırıldı veya ileri taşındı. |
| Eksik | Bazı kapsam verileri belirlenemedi, bu nedenle rakam alt sınırdır. |
| Ölçülmedi | Hiçbir çalıştırma commit için kapsam bildirmadi. |

Bir dalın trendi yalnızca tamamlanan commit'leri içerir. Bir commit şu durumlarda eksiktir, örneğin:

- Seçici test, ileri taşınamayan bir hedefi atladı: Önceki çalıştırma bunun için kapsam kaydetmedi, seçici çalıştırmanın derlemediği bir dosya son tam çalıştırmadan beri değişti veya commit `Package.resolved`, `Project.swift` ya da bir `.xcconfig` gibi her hedefi etkileyen dosyaları değiştirdi.
- Bir çalıştırma `--skip-test-targets` veya `-skip-testing` ile testleri atladı ve commit'teki başka hiçbir çalıştırma bunları yürütmedi.
- Bir çalıştırma hedeflerinizi ikili önbellekten düz ikili dosyalar olarak aldı.
- Bir şemanın her çalıştırması `-only-testing` ile daraltıldı.
- Bir şemanın kapsamı yalnızca işlenmemiş değişiklikleri olan bir checkout'taki CI çalıştırmalarından geldi.

## Performans etkisi {#performance-impact}

Kapsam toplamak, çoğunlukla testler bittikten sonra, Xcode kapsam raporunu yazarken ve Tuist kapsamı dışa aktarırken ek yük getirir. Testlerin derlenmesi ve çalıştırılması yaklaşık olarak kapsamsız durumla aynı süreyi alır. Enstrümantal derlemeler ayrıca DerivedData'da ve Debug ikili önbelleğinde daha fazla disk alanı kaplar. Release derlemeleri ve arşivler bundan etkilenmez.

## Sınırlamalar {#limitations}

### Kapsam toplayan şemaların Release derlemeleri {#release-builds}

Bir şemanın test eylemi kapsam topladığında, Xcode ayrıca `xcodebuild build` tarafından o şema için kaynaktan derlenen hedefleri, Release dahil herhangi bir yapılandırmada enstrümante eder. `xcodebuild archive` ayarı yoksayar, bu nedenle arşivler asla enstrümante edilmez. Arşivleri dağıtın veya `.options(coverage: false)` içeren bir şemadan Release ürünleri derleyin.

### Diğer kapsam araçları {#other-coverage-tools}

`-enableCodeCoverage YES` yalnızca bir çalıştırmanın kapsam toplayıp toplamayacağına karar verir, tıpkı Xcode'da olduğu gibi. Tuist'in önbellekten enstrümantal ikili dosyaları okumasını sağlamaz, bu nedenle bunun yerine `Tuist.swift` seçeneğini veya `TUIST_COVERAGE_ENABLED` kullanın.

Başka bir kapsam aracına veri sağlamak için `tuist test` komutunun her çalıştırmanın kapsamını LCOV olarak yazmasını sağlayın. Bu, Tuist'in yüklediği aynı kapsamdır; depo göreli yollar ve ikili önbellekten gelen kod dahildir:

```sh
tuist test --coverage-output-path coverage
```

Her çalıştırma `coverage/<result bundle name>.lcov` yazar. Parçalı bir çalıştırmanın dosyalarını `lcov -a` ile birleştirin. Seçenek kapsam yüklemenin açık olmasını gerektirir.

Xcode'un kendi kapsam raporu ve bunu okuyan araçlar, yalnızca Xcode'un o çalıştırmada derlediği hedefleri içerir, asla ikili önbellekten gelen kodu içermez. Tuist'in yüklemesi her ikisini de ölçer. Bir hedefin kapsamının Xcode'un raporunda görünmesini istiyorsanız, projeyi o hedef kaynaktan derlenecek şekilde oluşturun: `tuist generate MyTarget`, `MyTarget` öğesini kaynak olarak tutar ve geri kalanını önbellekten alır.

## Kapsam sorgulama {#querying}

`tuist coverage` komutları panoda gösterilenleri okur. `--commit` olmadan, `--branch` veya varsayılan dalınızın en son tamamlanan commit'ini okurlar:

```sh
tuist coverage show                          # the project's coverage and its targets
tuist coverage files --commit <sha>          # files, least covered first
tuist coverage file Sources/Cart.swift --lines  # a file's functions, with per-line counts
tuist coverage targets                       # targets, least covered first, then those taken from the binary cache without coverage
tuist coverage commits --branch main         # a branch's commits with their status and change, newest first
tuist coverage runs --commit <sha>           # the test runs behind a commit, marked full, partial or discarded
tuist coverage branches                      # the branches with coverage
```

Bir test çalıştırmasının kendi kapsamı `tuist test show <test-run-id>` içinde gösterilir.

Hepsi betikleme için `--json` kabul eder. Aynı verilere ajanlar <.localized_link href="/guides/features/agentic-coding/mcp">Model Context Protocol sunucusu</.localized_link> aracılığıyla erişebilir.
