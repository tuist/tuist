---
{
  "title": "Oluşturulan Xcode projesi",
  "titleTemplate": ":title · Seçici test · Özellikler · Kılavuzlar · Tuist",
  "description": "Tuist Seçici Test ile yalnızca en son değişikliklerinizden etkilenen Xcode ve oluşturulan proje testlerini çalıştırın, böylece sürekli entegrasyon geri bildirimi saniyeler içinde sağlar."
}
---
# Oluşturulan Xcode projesi {#generated-xcode-project}

Proje büyüdükçe, her push işleminde tüm testleri çalıştırmak ölçeklenebilirliğini yitirir. Tuist’in seçici testi, Tuist’in <.localized_link href="/guides/features/projects/hashing">hashing algoritmasına</.localized_link> dayanarak yalnızca son başarılı test çalıştırmasından bu yana hedefleri değişen testleri çalıştırır.

<.localized_link href="/guides/features/projects">Oluşturulan projenizle</.localized_link> testleri seçici olarak çalıştırmak için `tuist test` komutunu kullanın. Komut, projenizi <.localized_link href="/guides/features/cache/module-cache">modül önbelleği</.localized_link> için yaptığı gibi <.localized_link href="/guides/features/projects/hashing">hash’ler</.localized_link> ve başarı durumunda, gelecekteki çalıştırmalarda nelerin değiştiğini belirlemek üzere hash değerlerini kalıcı hale getirir. Gelecekteki çalıştırmalarda `tuist test`, testleri daraltmak ve yalnızca son başarılı test çalıştırmasından bu yana değişenleri çalıştırmak için hash değerlerini şeffaf bir şekilde kullanır.

`tuist test`, test paketinizi çalıştırırken derleme süresini iyileştirmek amacıyla yerel veya uzak depolamanızdaki ikili dosyaları mümkün olduğunca kullanmak için <.localized_link href="/guides/features/cache/module-cache">modül önbelleği</.localized_link> ile doğrudan entegre olur. Seçici testin modül önbellekleme ile birleşimi, CI ortamınızda testlerin çalışma süresini önemli ölçüde azaltabilir.

Testleriniz yalnızca simülatör hedeflerini çalıştırıyorsa, `tuist test` yalnızca önbelleğe alınmış ikili dosyaların simülatör dilimlerini kullanıp indirmesi için `--destination simulator` parametresini iletin. Bkz. <.localized_link href="/guides/features/cache/module-cache#destination-selection">hedef seçimi</.localized_link>. Seçici test hash değerleri her `--destination` değeri için aynıdır.

## Derleme ve test işlerini ayırma {#separate-build-and-test-jobs}

Seçici test, ayrı derleme ve test işlerini destekler. Derleme işinde `tuist test --build-only` çalıştırın ki Tuist, derlemenin ürettiği ürünlerin yanında bir `selective-testing-graph.json` dosyasını kalıcı hale getirebilsin. Bu graf, seçici testin ihtiyaç duyduğu hash değerlerini taşır; böylece test işi, hangi hedeflerin çalıştırılacağını belirlemek için projeyi yeniden oluşturmak veya Swift Package bağımlılıklarını çözmek zorunda kalmaz.

Tuist, `--build-only` sırasında grafi iki yere yazar:

- `-testProductsPath` parametresini ilettiğinizde `.xctestproducts` paketi içinde.
- Türetilmiş verilerin `Build/Products/` dizini altındaki her bir `.xctestrun` dosyasının yanında.

Her iki çıktıdan birini derlenen ürünlerin yanında önbelleğe alın ve test işinde `--without-building` parametresine aynı yolu iletin. Her iki form da çalışır:

```sh
# Build job — writes an .xctestproducts bundle with the graph inside it.
tuist test MyScheme \
  --build-only \
  -- \
  -testProductsPath artifacts/MyScheme.xctestproducts \
  -destination 'platform=iOS Simulator,id=SIMULATOR_IDENTIFIER'

# Test job — restores the same bundle.
tuist test MyScheme \
  --without-building \
  -- \
  -testProductsPath artifacts/MyScheme.xctestproducts \
  -destination 'platform=iOS Simulator,id=SIMULATOR_IDENTIFIER'
```

```sh
# Build job — writes the graph as a sibling of each xctestrun in derived data.
tuist test MyScheme \
  --build-only \
  -- \
  -derivedDataPath artifacts/derived-data

# Test job — points --without-building at any of those xctestrun files.
tuist test MyScheme \
  --without-building \
  -- \
  -derivedDataPath artifacts/derived-data \
  -destination 'platform=iOS Simulator,id=SIMULATOR_IDENTIFIER' \
  -xctestrun artifacts/derived-data/Build/Products/MyScheme_iphonesimulator.xctestrun
```

Tuist bu grafi girdinin yanında bulamadığında (örneğin, derleme işi `tuist test --build-only` yerine düz `xcodebuild build-for-testing` kullandığında), etkilenen hedefleri yine de hesaplayabilmek için projeyi yeniden oluşturmaya geri döner. Bu geri dönüş mekanizması, test işinde Swift Package bağımlılıklarının çözülmesini gerektirir; bu nedenle önce `tuist install` çalıştırın veya işler arasında `Tuist/.build` önbelleğe alın.

Graf, derleme zamanındaki kaynak ağacını yansıtır. Test işini, derleme işiyle aynı commit’e karşı çalıştırın — eğer ikisi arasında kaynak farklılaşırsa, hash değerleri artık kaynakla eşleşmez ve seçici test, daha yeni kaynağa karşı aslında başarısız olacak testleri atlayabilir.

### Hangi bayrağı kullanmalıyım? {#which-flag-should-i-use}

`.xctestrun` ve `.xctestproducts`, iki farklı Xcode çıktı formatıdır ve taşınabilirlik ile pipeline kolaylığı arasında bir denge kurarlar:

- **`-testProductsPath` (`.xctestproducts`) — yeni pipeline’lar için önerilir.** Kendi kendine yeten bir dizindir: derlenen `.xctest` ikili dosyaları ve bunların `.xctestrun` dosyaları, yolları paket köküne göreli hale getirilmiş olarak içinde bulunur; böylece nereye taşınırsa taşınsın geçerliliğini korur.
- **`-xctestrun` (ham `.xctestrun`) — türetilmiş veri etrafında zaten bir pipeline kurduysanız bunu kullanın.** `xcodebuild build-for-testing`, varsayılan olarak `<derivedData>/Build/Products/` üstüne bir `.xctestrun` yazar ve onu o ağaçtaki başka yerlerde bulunan test paketlerine işaret edecek şekilde konumlandırır. Başka bir işte yeniden kullanmak, `Build/Products/` içindeki yolların bozulmadan kalmasını gerektirir.

Yeni başlıyorsanız `-testProductsPath` tercih edin. Tuist’i türetilmiş veriyi zaten önbelleğe alan mevcut bir pipeline’a entegre ediyorsanız, derleme işi `tuist test --build-only` üzerinden çalıştığı sürece `-xctestrun` aynı hızlı yolu izler.

Her iki giriş modu da `-workspace`/`-project`/`-scheme` ile karşılıklı olarak dışlayıcıdır; bu nedenle passthrough argümanları `-xctestrun` veya `-testProductsPath` içerdiğinde Tuist bu bayrakları atlar ve seçilen hedefleri `-only-testing` aracılığıyla iletir.

> [!WARNING]
> **Modül düzeyi ile dosya düzeyi granülerliği**
>
> Testler ve kaynaklar arasındaki kod içi bağımlılıkları tespit etmenin imkansızlığı nedeniyle, varsayılan seçici testin maksimum granülerliği hedef düzeyindedir. [Kapsam stratejisi](#coverage-based-test-selection) bunu tekil testlere kadar daraltır. Bu nedenle, seçici testin faydalarını en üst düzeye çıkarmak için hedeflerinizi küçük ve odaklı tutmanızı öneririz.


## Kapsama dayalı test seçimi {#coverage-based-test-selection}

> [!NOTE]
> **Erken erişim**
>
> Kapsama dayalı test seçimi erken erişim aşamasındadır. Hesabınızda etkinleştirmek için bizimle iletişime geçin. Etkinleştirilene kadar strateji, varsayılan seçici test gibi davranır.

Varsayılan olarak seçici test, hash’i daha önce geçen tüm test hedeflerini atlar. `.coverage()` stratejisi daha ileri gider: kalan test hedeflerinde, daha önceki bir çalıştırmadaki kod kapsamının değişikliğinizin dokunduğu dosyalardan hiçbirini içermemediği testleri de atlar. XCTest ve XCUITest testleriyle ve buna uygun yapılandırılmış paketlerdeki [Swift Testing](#swift-testing) testleriyle çalışır. `Tuist.swift` içinde etkinleştirin:

```swift
import ProjectDescription

let tuist = Tuist(
    fullHandle: "{account-handle}/{project-handle}",
    testInsights: .testInsights(
        coverage: .coverage(upload: true),
        selectiveTesting: .selectiveTesting(strategy: .coverage())
    ),
    project: .tuist()
)
```

Strateji şunları gerektirir:

- **Kapsam yüklemeleri.** Tuist, testleri önceki çalıştırmaların yüklediği kapsama göre seçer; bu nedenle `tuist test`, `upload: false` ile ayarlanmış `.coverage()` içeren bir manifesti yükleyemez.
- **[TestCoverageAttribution](https://github.com/tuist/TestCoverageAttribution) 0.5.1 veya üzeri** [test hedefleriniz tarafından bağlanmış](#linking-testcoverageattribution). Her testin hangi dosyaları yürüttüğünü kaydeder ve Tuist’in seçmediği testleri atlar. Bu olmadan bir hedef yalnızca varsayılandaki gibi tamamen atlanır.
- **Yeterince sık tam test çalıştırmaları.** `tuist test --no-selective-testing` ile yapılan bir çalıştırma her testi yürütür ve bir temel oluşturur. Seçici bir çalıştırma, aynı platformda commit geçmişindeki yakın bir temel ile karşılaştırma yapar ve temel olmadan kapsam uygulamaz. Bunları nerede ve ne sıklıkta çalıştıracağınız ekibinizin çalışma biçimine bağlıdır; örneğin varsayılan dalınızın her commit’inde, geceleyin veya sürüm dallarında. Varsayılan dalı öneriyoruz: oradaki tam bir çalıştırma, bir değişiklik yayınlanmadan önce kapsamın göremeyeceği şeyleri, örneğin bir testin bağımlı olduğu bir sabit veriyi veya hizmeti de yakalar.

Strateji açıkken `tuist test`, hash’i daha önce geçen hedefleri atlar ve ardından Tuist’e, kalan hedeflerden hangilerinin değişikliğinizden etkilenebileceğini sorar. Etkilenen testi olmayan hedefler derlenmez. Yeni testler, son seferde başarısız olan testler, değiştirilmiş bir test dosyasındaki testler ve kaydedilmiş kapsamı olmayan testler her zaman çalışır.

Bazen kapsam uygulanmaz ve çıktı nedenini açıklar: hash’i geçmeyen hedeflerin tüm testleri, varsayılan seçici testteki gibi çalışır. Bu durum, aynı platformda yakın bir temel olmadığında, değişiklik 5.000’den fazla dosyaya dokunduğunda veya herhangi bir testi etkileyebilecek bir dosya değiştiğinde, örneğin `Package.resolved`, `Project.swift` veya bir `.xcconfig` gerçekleşir. Her testi çalıştırmak için `--no-selective-testing` parametresini geçirin.

> [!NOTE]
> **Test kapsamı**
>
> Tek bir çalıştırmanın raporunu okuyan kapsam araçları, Xcode dahil olmak üzere, tüm test paketinin çalıştığını varsayar; bu nedenle seçici bir çalıştırmanın raporu atladığı testleri dışarıda bırakır. Tuist’in <.localized_link href="/guides/features/test-code-coverage/generated-xcode-project">kod kapsamı</.localized_link> bunun yerine, her çalıştırmada kaydettiği <.localized_link href="/guides/features/test-code-coverage/generated-xcode-project#target-level-coverage">hedef düzeyindeki kapsamı</.localized_link> kullanarak atlanan test hedeflerinin kapsamını önceki bir çalıştırmadan taşır.

### TestCoverageAttribution bağlama {#linking-testcoverageattribution}

Paketi `Tuist/Package.swift` konumuna ekleyin ve küçük sürümüne sabitleyin, çünkü 0.x küçük sürümleri kaydettiklerini değiştirebilir:

```swift
import PackageDescription

let package = Package(
    name: "MyApp",
    dependencies: [
        .package(
            url: "https://github.com/tuist/TestCoverageAttribution",
            .upToNextMinor(from: "0.5.1")
        ),
    ]
)
```

Ardından bunu test hedeflerinize ekleyin, ancak asla bir uygulama hedefine eklemeyin:

```swift
.target(
    name: "CheckoutTests",
    destinations: .iOS,
    product: .unitTests,
    bundleId: "dev.tuist.CheckoutTests",
    sources: ["CheckoutTests/**"],
    dependencies: [
        .target(name: "Checkout"),
        .external(name: "TestCoverageAttribution"),
    ]
)
```

Tuist paketleri varsayılan olarak statik çerçeveler olarak bağlar. Yalnızca XCTest içeren bir hedef paketteki hiçbir şeye referans vermez, bu nedenle bağlayıcı onu ve buna bağlı olarak kaydetme ve atlama işlemlerini düşürür. Test hedefinin `OTHER_LDFLAGS` alanına `-ObjC` ekleyin veya paketi `Tuist/Package.swift` içinde dinamik olarak bağlayın:

```swift
#if TUIST
    import ProjectDescription

    let packageSettings = PackageSettings(
        productTypes: ["TestCoverageAttribution": .framework]
    )
#endif
```

### Swift Testing {#swift-testing}

Swift Testing’in bir kütüphanenin katılabileceği bir gözlem API’si yoktur, bu nedenle testlerinin paketinde TestCoverageAttribution’ın `.coverageAttribution` özelliğine ihtiyacı vardır. Özellik, kendisine sahip olan pakete iç içe geçmiş paketlere uygulanır. Bu özelliğe sahip olmayan paketlerdeki testler test başına kapsam kaydetmez, bu nedenle hedefleri çalıştığında onlar da çalışır.

```swift
import TestCoverageAttribution
import Testing

@Suite(.coverageAttribution)
struct DiscountTests {
    @Test func appliesDiscount() { … }
}
```

- **Testler örtüşmemelidir.** Swift Testing varsayılan olarak bir işlemin testlerini paralel çalıştırır ve kapsam sayaçları aynı anda çalışan testleri ayırt edemez, bu nedenle bu testler kendi kapsamlarını kaydetmez ve her zaman çalışır. `.serialized` yalnızca bir paketin kendi testlerini sıralar, bu nedenle yalnızca hedef tek bir pakete sahip olduğunda yeterlidir. XCTest’in ekstra bir yapılandırmaya ihtiyacı yoktur: paralel testleme her test klonunu kendi işleminde çalıştırır.
- **Paralelleştirmeyi test hedefi başına kapatın.** Xcode ayarı her test hedefine uygular, bu nedenle yalnızca test bazında seçilmesini istediğiniz hedefler için kapatabilirsiniz ve şemanın diğer hedefleri paralel çalışmaya devam eder. Ayrı bir şemaya gerek yoktur. Bunu test edilebilir hedef üzerinde ayarlayın, `.testableTarget(target: "CheckoutTests", parallelization: .disabled)`, bu ayrıca o hedefin XCTest testlerini klon olmadan çalıştırır. Tuist’in oluşturduğu şemalar bunu projenin `testingOptions` ayarından alır; `.parallelizable` veya `.swiftTestingOnlyParallelizable` içermiyorsa kapalıdır. `tuist test` komutuna `-parallel-testing-enabled YES` veya `NO` geçirmek, o çalıştırma için her hedefin ayarını geçersiz kılar.
- **Atlama için Swift 6.3 (Xcode 26.4) veya üzeri gerekir.** Özellik, Tuist’in seçmediği testleri iptal eder ve bunları atlanmış olarak raporlar. Daha eski sürümlerde testler yine de kapsam kaydeder, ancak Tuist’in seçmediği testler yine de çalışır.

### Her zaman çalışan testler {#tests-that-always-run}

Kapsam yalnızca bir testin yürüttüğü kodu görür. Gerçek girdileri sabit veriler, kaynaklar, ağ veya ortam olan bir test, kapsanan herhangi bir kod değişmeden bozulabilir. Onu atlanamaz olarak işaretlerseniz, Tuist onu seçmese bile çalışır:

```swift
// Swift Testing: on a test or a suite.
// `.skippable` opts a nested test or suite back in.
@Suite(.coverageAttribution, .unskippable)
struct FixtureTests {
    @Test func parsesTheFixtures() { … }
}

// XCTest: list the class's tests, or set `isUnskippable` for all of them.
final class NetworkTests: XCTestCase {
    @objc static let unskippableTests = ["testParsesTheFixtures"]
}
```

Bu yalnızca çalışan test hedeflerinde geçerlidir. Hash’i zaten geçen veya Tuist’in hiçbir testini seçmediği bir hedef tamamen atlanır ve asla başlamaz, bu nedenle onun atlanamaz testleri de çalışmaz.

Tüm seçenekler için [TestCoverageAttribution README](https://github.com/tuist/TestCoverageAttribution#unskippable-tests) dosyasına bakın.

### Bir seçimi inceleme {#inspecting-a-selection}

Test çalıştırmasının Seçici Test sekmesi, kapsamın neyi seçtiğini ve nedenini gösterir. Aynı verilere CLI üzerinden `--json` ile betikleme için ve ajanlar aracılığıyla <.localized_link href="/guides/features/agentic-coding/mcp">Model Context Protocol sunucusu</.localized_link> üzerinden erişilebilir:

```sh
tuist test list --selective-testing coverage           # the runs coverage-based selection decided
tuist test show <test-run-id>                          # a run's strategy, baseline and test counts
tuist test selective-testing list <test-run-id>        # each test selected or skipped, with its reason and the file that matched
tuist test selective-testing changed-files <test-run-id>  # the files that changed since the baseline
tuist test case run show <test-case-run-id>            # why a test ran
```

Kapsam uygulanmadığında, testler yine de kapsam tabanlı bir seçim olarak sayılır: nedenleri, kapsamın karar verememesinin sebebini belirtir, örneğin `tracked_file_changed`.


## Çekme/birleştirme isteği yorumları {#pullmerge-request-comments}

> [!WARNING]
> **Git forge entegrasyonu gerekli**
>
> Otomatik çekme/birleştirme isteği yorumları almak için <.localized_link href="/guides/server/accounts-and-projects">Tuist projenizi</.localized_link> bir Git forge ile entegre edin: <.localized_link href="/guides/integrations/gitforge/github">GitHub</.localized_link>, <.localized_link href="/guides/integrations/gitforge/origin">Cursor Origin</.localized_link> veya <.localized_link href="/guides/integrations/gitforge/entire">Entire</.localized_link>.


Tuist projeniz [GitHub](https://github.com) gibi Git platformunuzla bağlantılı hale geldiğinde ve CI iş akışınızın bir parçası olarak `tuist test` kullanmaya başladığınızda, Tuist doğrudan çekme/birleştirme isteklerinize hangi testlerin çalıştırıldığını ve hangilerinin atlandığını içeren bir yorum gönderir: ![Tuist Önizleme bağlantısı içeren GitHub uygulaması yorumu](/images/guides/features/selective-testing/github-app-comment.png)


## Panoda kaçakları inceleme {#investigating-misses-on-the-dashboard}

Daha önce önbelleğe alınmış bir test hedefi kaçak olarak göründüğünde, bir test çalıştırması sayfasındaki **Seçici Test** sekmesi, hash’i oluşturan girdileri derinlemesine incelemenize olanak tanır. Bir satırı genişletmek, bileşen başına alt hash’leri — kaynaklar, bağımlılıklar, ortam değişkenleri, proje ve hedef ayarları, Info.plist, yetkiler, başlıklar vb. — ortaya çıkarır, böylece çalıştırmalar arasında sapma gösteren girdiyi tam olarak belirleyebilirsiniz.

Seçici Test kartının üst kısmındaki **JSON olarak Kopyala** düğmesini kullanarak her seçici test hedefini hash’i ve alt hash’leriyle birlikte dışa aktarın. İki çalıştırma arasındaki JSON’u karşılaştırmak, test hedefinin hash’i saptığında hangi girdinin değiştiğini doğrulamanın en hızlı yoludur.
