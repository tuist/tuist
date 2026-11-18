---
{
  "title": "Oluşturulan Xcode projesi",
  "titleTemplate": ":title · Kod Kapsamı · Özellikler · Kılavuzlar · Tuist",
  "description": "İkili önbelleğin ve seçici testin atladığı kodlar dahil olmak üzere, Tuist tarafından oluşturulan bir Xcode projesinin dosya ve commit bazında kod kapsamını ölçün."
}
---
# Oluşturulan Xcode projesi {#generated-xcode-project-code-coverage}

Kod kapsamı, testlerinizin kodunuzun hangi satırlarını çalıştırdığını gösterir. Tuist, her bir `tuist test` çalıştırmasının satır kapsamını yükler ve bir commit'in çalıştırmalarını proje, her hedef ve her dosya için tek bir rakamda birleştirir. Kontrol panelinin **Kod Kapsamı** sayfası bunu commit başına ve her dal için bir eğilim olarak gösterir.

<!-- @snippet: ./_xcode-requirements -->

Tuist işleri atladığında bile rakam doğru kalır. <.localized_link href="/guides/features/cache/module-cache">ikili önbellek</.localized_link>ten gelen hedefleriniz kapsam sayaçlarıyla derlenir, bu nedenle kodları kaynaktan derlenen kod gibi ölçülür. Ve <.localized_link href="/guides/features/selective-testing/generated-xcode-project">seçici test</.localized_link> bir test hedefini atladığında, hedef Tuist'in her çalıştırmada kaydettiği [hedef düzeyi kapsam](#target-level-coverage) sayesinde önceki bir çalıştırmada sahip olduğu kapsamı korur.

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

- Tuist'in oluşturduğu her şemanın test eylemi kapsam toplar ve ayrıca tanımladığınız ve `coverage` ayarını boş bırakan her şemanın test eylemi de kapsam toplar. `.options(coverage: false)` veya `.options(coverage: true)` içeren bir şema kendi değerini korur. Test planları kapsamı kendileri belirler: Tuist'in oluşturduğu test planları için `.testPlans(_:coverage:)` öğesine `coverage: true` parametresini geçirin.
- Projenizin kendi hedefleri, Debug yapılandırmalarında kapsam sayaçlarıyla ikili önbellekten okunur ve önbelleğe alınır. Bkz. [Nasıl çalışır](#instrumented-binaries).

`TUIST_COVERAGE_ENABLED` ve `TUIST_COVERAGE_UPLOAD` ortam değişkenleri (`1` veya `0`), `enabled` ve `upload` ayarlarından önceliklidir. Bunları tek bir komut yerine, tüm bir ortam (örneğin bir CI iş akışı) için ayarlayın; böylece önbelleği ısıtan komutlar ile onu okuyan komutlar uyumlu olur.

> [!IMPORTANT] KEEP THE VALUE THE SAME EVERYWHERE
> Oluşturma seçeneği, projenizin hedeflerinin önbellek anahtarlarını ve test hedeflerinin seçici test karmalarını değiştirir. Önbelleği paylaşan her makinede aynı değeri kullanın ve bunu ortamdan (örneğin `Environment.isCI` üzerinden) türetmeyin. Kapsam kapalıyken yapılan bir çalıştırma, kapsam açıkken yapılan çalıştırmaların ikili dosyalarını veya seçici test sonuçlarını yeniden kullanmaz.

### Şemaları dışarıda bırakın {#leave-schemes-out}

Bazı test paketleri kapsamınıza dahil edilmemelidir. Örneğin, uygulamanızı veya CLI'nizi başka bir süreçten süren kabul veya uçtan uca testler, kapsamın göremediği kodu yürütür ve bunları toplamak yalnızca yavaşlatır. Şemalarının test eyleminde kapsamı kapatın:

```swift
.scheme(
    name: "AcceptanceTests",
    testAction: .targets(
        ["AcceptanceTests"],
        options: .options(coverage: false)
    )
)
```

Şema, `Tuist.swift` seçeneği veya `TUIST_COVERAGE_ENABLED` ne derse desin kapsamı kapalı tutar ve onun çalıştırmaları bir commit'in kapsamına sayılmaz. Kapsam şema başına toplanır, bu nedenle bir test hedefini dışarıda bırakmak için onu kendi şemasına taşıyın.

### Testlerinizi çalıştırın {#run-your-tests}

Testlerinizi her zamanki gibi `tuist test` ile çalıştırın:

```sh
tuist test
```

Tuist, çalıştırmanın topladığı kapsamı test sonuçlarıyla birlikte yükler. Bu, <.localized_link href="/guides/features/test-sharding/generated-xcode-project">bölünmüş çalıştırmaları</.localized_link> ve `--without-building` ile başka bir işte derlenen ürünleri test eden çalıştırmaları içerir. Bir çalıştırmanın kapsamının Tuist'e yüklenmemesini sağlamak için (örneğin fork'lardan gelen pull request'leri çalıştıran işlerde) `TUIST_COVERAGE_UPLOAD=0` ayarını yapın.

### CI'da her commit'i tamamlayın {#complete-each-commit}

Bir commit'in kapsamı genellikle birkaç işten gelir: şema başına, parça başına veya platform başına bir tane. Tuist, hangisinin sonuncusunun rapor verdiğini bilemez, bu yüzden siz söyleyin. Bir commit için tüm test işleri bittiğinde, hepsine bağımlı olan bir işte şunu çalıştırın:

```sh
tuist coverage complete
```

Komut, commit'i checkout'tan veya CI sağlayıcınızdan okur; başka birini belirtmek için `--commit <sha>` parametresini geçirin. Bir commit tamamlanana kadar, kapsamı **Devam ediyor** olarak görünür ve dalının eğilimine dahil edilmez.

### Tüm paketi varsayılan dalınızda çalıştırın {#full-runs}

> [!IMPORTANT] SET UP A FULL RUN
> Seçici test, atlanan hedefleri taşıyacak önceki bir çalıştırma varsa bir commit'in kapsamını tam tutar. Varsayılan dalınızda, seçici test olmadan her testin bir çalıştırmasını zamanlayın:
>
> ```sh
> tuist test --no-selective-testing
> ```
>
> Her birleştirmede bir kez çalıştırmak idealdir. Az değişiklik yapan bir depo için günlük veya haftalık yeterli olabilir. Kaydedilen kapsam 31 gün sonra sona erer, bu nedenle bundan daha sık çalıştırın.

Taşınan kapsam, tam çalıştırmalara dayanır. Tam çalıştırmalar, her hedefin kaydedilen kapsamını sona ermeden önce yeniler ve seçici bir çalıştırmanın derlemediği dosyaların güncel durumunu Tuist'e sağlar. Bir depo, tam çalıştırmalar arasında ne kadar çok değişirse, seçici bir çalıştırma o sıklıkta değişmiş bir dosya bulur ve commit'in kapsamı **Eksik** olur.

## Hedef düzeyi kapsam {#target-level-coverage}

Bir çalıştırmanın kapsamı, tüm çalıştırmanın neyi yürüttüğünü söyler, her test hedefinin neyi yürüttüğünü değil. Seçici test bir hedefi atladığında, Tuist'in kapsamını ileri taşımak için o hedefin önceki bir çalıştırmada neyi yürüttüğünü bilmesi gerekir.

Bu nedenle Tuist, her çalıştırmada her test hedefinin hangi dosyaları ve satırları yürüttüğünü de kaydeder. Bunları Xcode'un her test süreci için yazdığı kapsamdan okur, bu nedenle bağlantı veya yapılandırma gerekmez. macOS ve iOS simülatöründe kaydedilir, cihazlarda kaydedilmez. UI testleri, sürdükleri uygulama hakkında hiçbir şey kaydetmez çünkü uygulamanın kodu kendi sürecinde çalışır.

## Nasıl çalışır {#how-it-works}

### Enstrümantasyonlu ikili dosyalar {#instrumented-binaries}

İkili önbellekten gelen bir hedef, önceden derlenmiş bir ikili dosyadır ve bir test çalıştırması yalnızca ikili dosya kapsam sayaçlarıyla derlendiyse kodunu ölçebilir. Kapsam açıkken, ikili önbellek projenizin kendi hedeflerinin enstrümantasyonlu bir varyantını saklar ve her komut bu varyantı okur ve ısıtır:

- **Debug yapılandırmaları** enstrümantasyonlu varyantı kullanır: `tuist cache` onu ısıtır, `tuist generate` ve `tuist test` ise onu okur.
- **Release yapılandırmaları** her zaman düz varyantı kullanır, bu nedenle yayınladığınız ürün asla kapsam sayaçları taşımaz.
- **Harici paketler** her zaman düz varyantı kullanır. Tuist yalnızca deponuzun kodunu ölçer.

Önbelleği, test işlerinizle aynı ortamda kapsam açıkken ısıtın, böylece `tuist test` enstrümantasyonlu ikili dosyaları bulur. Bir çalıştırma kapsam toplar ancak hedeflerinizi önbellekten düz ikili dosyalar olarak alırsa, Tuist sizi uyarır ve kodları ölçülmez. <.localized_link href="/guides/features/cache/module-cache#code-coverage">modül önbelleği</.localized_link> varyantları ayrıntılı olarak belgeler.

### Makineler arası yollar {#paths-across-machines}

Enstrümantasyonlu ikili dosyalar, kaynak yollarını derlendikleri checkout'a göre göreceli olarak kaydeder, bu nedenle CI'da ısıtılan bir ikili dosya herhangi bir geliştiricinin makinesinde doğru dosyaları ölçer.

<.localized_link href="/guides/features/cache/xcode-cache">Xcode önbelleği</.localized_link>, ön ek eşlemesi yoluyla aynı şekilde çalışır; Tuist bunu kapsam toplayan derlemelerde varsayılan olarak kapatır çünkü Xcode'un kendi kapsam raporu eşlenmiş yolları çözümleyemez. Xcode 27 ve sonraki sürümlerde, `enableCaching` açıkken `prefixMapping: true` bunu açık tutar, böylece kapsam derlemeleri derleme sonuçlarını checkout'lar arasında da paylaşır:

```swift
.options(coverage: .coverage(enabled: true, prefixMapping: true))
```

Tuist'in yüklemesi eşlenmiş yolları çözer, ancak Xcode'un kapsam raporu ve `xccov` bu dosyaları dışarıda bırakabilir. Bkz. <.localized_link href="/guides/features/cache/xcode-cache#coverage-with-prefix-mapping">Ön ek eşlemesiyle kapsam</.localized_link>.

### Atlanan testler {#skipped-tests}

Seçici test, daha önce geçen bir çalıştırma aynı karma ile zaten test ettiyse bir test hedefini atlar. Karma, hedefin kaynaklarını, testlerini ve tüm bağımlılıklarını kapsar; bu nedenle aynı karma, aynı kod üzerinde aynı testler anlamına gelir. Tuist, o çalıştırmanın hedef için kaydettiği [hedef düzeyi kapsam](#target-level-coverage) verisini yeniden kullanır. Eğer hiçbir şey kaydedilmediyse (örneğin o sırada kapsam kapalıydı veya çalıştırma 31 günden eskiyse), taşınacak bir veri yoktur ve commit **Eksik** olarak işaretlenir.

Seçici bir çalıştırma ayrıca her dosyayı derlemez. Derlemediği dosyalar için Tuist, dosyalar o zamandan beri değişmediği sürece satırları en yakın önceki tam çalıştırmadan alır. Bu nedenle varsayılan dalınızdaki [tam çalıştırmalar](#full-runs) önemlidir.

Kendinizin `--skip-test-targets` veya `-skip-testing` ile atladığı testler ileri taşınmaz: Çalıştırmaları bunları dışarıda bırakan bir commit, o committeki başka bir çalıştırma onları yürütmedikçe **Eksik** olur. Karantinaya alınan testler kapsamın parçası değildir: Tuist bunları ne taşır ne de commit'i bunlar nedeniyle **Eksik** olarak işaretler.

### Tamamlanan ve eksik commit'ler {#commit-status}

Panodaki her commit'in bir durumu vardır:

| Durum | Anlamı |
| --- | --- |
| Devam ediyor | Çalıştırmalar kapsam bildirdi, ancak `tuist coverage complete` henüz commit için çalıştırılmadı. |
| Tamamlandı | Commit'in şemalarının her testi çalıştırıldı veya ileri taşındı. |
| Eksik | Bazı kapsam verileri belirlenemedi, bu nedenle rakam alt sınırdır. |
| Ölçülmedi | Hiçbir çalıştırma commit için kapsam bildirmedi. |

Bir dalın trendi yalnızca tamamlanan commit'leri içerir. Bir commit şu durumlarda eksiktir, örneğin:

- Seçici test, ileri taşınamayan bir hedefi atladı: Önceki çalıştırma bunun için herhangi bir kapsam kaydetmedi, seçici çalıştırmanın derlemediği bir dosya son tam çalıştırmadan bu yana değişti veya commit, `Package.resolved`, `Project.swift` veya bir `.xcconfig` gibi her hedefi etkileyen dosyaları değiştirdi.
- Bir çalıştırma `--skip-test-targets` veya `-skip-testing` ile testleri atladı ve o committeki başka hiçbir çalıştırma bunları yürütmedi.
- Bir çalıştırma hedeflerinizi ikili önbellekten düz ikili dosyalar olarak aldı.
- Bir şemanın her çalıştırması `-only-testing` ile daraltıldı.
- Bir şemanın kapsamı yalnızca işlenmemiş değişiklikleri olan bir checkout'taki CI çalıştırmalarından geldi.

## Performans etkisi {#performance-impact}

Kapsam toplamak, çoğunlukla testler bittikten sonra, Xcode kapsam raporunu yazarken ve Tuist kapsamı dışa aktarırken ek yük getirir. Testlerin derlenmesi ve çalıştırılması, kapsam olmadan olduğu kadar zaman alır. Enstrümantasyonlu derlemeler DerivedData'da ve Debug ikili önbelleğinde daha fazla disk alanı kaplar. Release derlemeleri ve arşivler bundan etkilenmez.

## Sınırlamalar {#limitations}

### Kapsam toplayan şemaların Release derlemeleri {#release-builds}

Bir şemanın test eylemi kapsam topladığında, Xcode ayrıca `xcodebuild build` tarafından o şema için kaynak koddan derlenen hedefleri enstrümantasyonlu hale getirir; bu durum Release dahil tüm yapılandırmalar için geçerlidir. `xcodebuild archive` bu ayarı yoksayar, bu nedenle arşivler asla enstrümantasyonlu olmaz. Arşivleri dağıtın veya `.options(coverage: false)` içeren bir şemadan Release ürünlerini derleyin.

### Diğer kapsam araçları {#other-coverage-tools}

`-enableCodeCoverage YES` yalnızca bir çalıştırmanın kapsam toplayıp toplamayacağına karar verir, Xcode'daki gibi. Tuist'in önbellekten enstrümantasyonlu ikili dosyaları okumasını sağlamaz, bu nedenle bunun yerine `Tuist.swift` seçeneğini veya `TUIST_COVERAGE_ENABLED` kullanın.

Başka bir kapsam aracına veri sağlamak için `tuist test` komutunun her çalıştırmanın kapsamını LCOV olarak yazmasını sağlayın. Bu, Tuist'in yüklediği kapsamla aynıdır; depo göreli yollar ve ikili önbellekten gelen kod dahildir:

```sh
tuist test --coverage-output-path coverage
```

Her çalıştırma `coverage/<result bundle name>.lcov` dosyasını yazar. Parçalı bir çalıştırmanın dosyalarını `lcov -a` ile birleştirin. Seçenek, kapsam yüklemenin açık olmasını gerektirir.

Xcode'un kendi kapsam raporu ve bunu okuyan araçlar, yalnızca Xcode'un o çalıştırmada derlediği hedefleri içerir, ikili önbellekten gelen kodu asla içermez. Tuist'in yüklemesi her ikisini de ölçer. Bir hedefin kapsamının Xcode'un raporunda görünmesini istiyorsanız, projeyi o hedef kaynaktan derlenecek şekilde oluşturun: `tuist generate MyTarget`, `MyTarget` öğesini kaynak olarak tutar ve geri kalanını önbellekten alır.

## Kapsam sorgulama {#querying}

`tuist coverage` komutları panoda gösterilen verileri okur. `--commit` olmadan, `--branch` veya varsayılan dalınızın en son tamamlanan commit'ini okurlar:

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

Tümü betikleme için `--json` kabul eder. Aynı verilere ajanlar <.localized_link href="/guides/features/agentic-coding/mcp">Model Context Protocol sunucusu</.localized_link> üzerinden erişebilir.
