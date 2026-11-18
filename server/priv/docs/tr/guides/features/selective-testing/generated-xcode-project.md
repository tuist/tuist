---
{
  "title": "Oluşturulan Xcode projesi",
  "titleTemplate": ":title · Seçici test · Özellikler · Kılavuzlar · Tuist",
  "description": "Tuist Seçici Test ile yalnızca son değişikliklerinizden etkilenen Xcode ve oluşturulan proje testlerini çalıştırın, böylece sürekli entegrasyon geri bildirimi saniyeler içinde alır."
}
---
# Oluşturulan Xcode projesi {#generated-xcode-project}

Proje büyüdükçe, her push işleminde tüm testleri çalıştırmak ölçeklenebilirliğini yitirir. Tuist'in seçici testi, Tuist'in <.localized_link href="/guides/features/projects/hashing">hashing algoritmasına</.localized_link> dayanarak yalnızca son başarılı test çalıştırmasından bu yana hedefleri değişen testleri çalıştırır.

<.localized_link href="/guides/features/projects">Oluşturulan projenizle</.localized_link> testleri seçici olarak çalıştırmak için `tuist test` komutunu kullanın. Bu komut, projenizi <.localized_link href="/guides/features/cache/module-cache">modül önbelleği</.localized_link> için yaptığı gibi <.localized_link href="/guides/features/projects/hashing">hashler</.localized_link> ve başarılı olduğunda, gelecekteki çalıştırmalarda nelerin değiştiğini belirlemek için hashleri kalıcı hale getirir. Gelecekteki çalıştırmalarda, `tuist test` testleri daraltmak ve yalnızca son başarılı test çalıştırmasından bu yana değişenleri çalıştırmak için hashleri şeffaf bir şekilde kullanır.

`tuist test`, test paketinizi çalıştırırken derleme süresini iyileştirmek amacıyla yerel veya uzak depolamanızdaki ikili dosyaları mümkün olduğunca kullanmak için <.localized_link href="/guides/features/cache/module-cache">modül önbelleği</.localized_link> ile doğrudan entegre olur. Seçici testin modül önbellekleme ile kombinasyonu, CI ortamınızda test çalıştırma süresini önemli ölçüde azaltabilir.

Testleriniz yalnızca simülatör hedeflerini içeriyorsa, `tuist test` komutunun önbelleğe alınmış ikili dosyaların yalnızca simülatör dilimlerini kullanması ve indirmesi için `--destination simulator` parametresini geçirin. Bkz. <.localized_link href="/guides/features/cache/module-cache#destination-selection">hedef seçimi</.localized_link>. Seçici test hashleri her `--destination` değeri için aynıdır.

## Derleme ve test işlerini ayırma {#separate-build-and-test-jobs}

Seçici test, ayrı derleme ve test işlerini destekler. Derleme işinde `tuist test --build-only` komutunu çalıştırın; böylece Tuist, derlemenin ürettiği ürünlerin yanında bir `selective-testing-graph.json` dosyasını kalıcı hale getirebilir. Bu grafik, seçici testin ihtiyaç duyduğu hashleri taşır; bu sayede test işinin hangi hedeflerin çalıştırılacağını belirlemek için projeyi yeniden oluşturması veya Swift Package bağımlılıklarını çözmesi gerekmez.

Tuist, `--build-only` sırasında grafiği iki yere yazar:

- `-testProductsPath` parametresini geçtiğinizde, `.xctestproducts` paketi içinde.
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

Tuist bu grafiği girişin yanında bulamazsa (örneğin, derleme işi `tuist test --build-only` yerine düz `xcodebuild build-for-testing` kullandıysa), etkilenen hedefleri yine de hesaplayabilmek için projeyi yeniden oluşturmaya geri döner. Bu geri dönüş mekanizması, test işinde Swift Package bağımlılıklarının çözülmüş olmasını gerektirir; bu nedenle önce `tuist install` komutunu çalıştırın veya işler arasında `Tuist/.build` dizinini önbelleğe alın.

Grafik, derleme zamanındaki kaynak ağacını yansıtır. Test işini, derleme işiyle aynı commit üzerinde çalıştırın — eğer ikisi arasında kaynak farklılaşırsa, hashler artık kaynakla eşleşmez ve seçici test, daha yeni kaynağa karşı aslında başarısız olacak testleri atlayabilir.

### Hangi bayrağı kullanmalıyım? {#which-flag-should-i-use}

`.xctestrun` ve `.xctestproducts`, iki farklı Xcode çıktı formatıdır ve taşınabilirlik ile pipeline kolaylığı arasında bir denge kurarlar:

- **`-testProductsPath` (`.xctestproducts`) — yeni pipeline'lar için önerilir.** Kendi kendine yeten bir dizindir: derlenen `.xctest` ikili dosyaları ve bunların `.xctestrun` dosyaları, yolları paket köküne göre göreceli hale getirilmiş şekilde içinde bulunur; bu sayede nereye giderse gitsin geçerliliğini korur.
- **`-xctestrun` (ham `.xctestrun`) — türetilmiş veri etrafında zaten kurulmuş bir pipeline'ınız varsa bunu kullanın.** `xcodebuild build-for-testing`, varsayılan olarak `<derivedData>/Build/Products/` üst kısmına bir `.xctestrun` yazar ve onu o ağaçtaki başka yerlerde bulunan test paketlerine yönlendirir. Başka bir işte yeniden kullanmak, `Build/Products/` içindeki yolların bozulmadan kalmasını gerektirir.

Yeni başlıyorsanız, `-testProductsPath` tercih edin. Türetilmiş veriyi zaten önbelleğe alan mevcut bir pipeline'a Tuist'i entegre ediyorsanız, derleme işi `tuist test --build-only` üzerinden çalıştığı sürece `-xctestrun` aynı hızlı yolu sağlar.

Her iki giriş modu da `-workspace`/`-project`/`-scheme` ile karşılıklı olarak dışlayıcıdır; bu nedenle, passthrough argümanları `-xctestrun` veya `-testProductsPath` içerdiğinde Tuist bu bayrakları atlar ve seçilen hedefleri `-only-testing` aracılığıyla iletir.

> [!WARNING]
> **Modül ve dosya düzeyinde granülerlik**
>
> Testler ve kaynaklar arasındaki kod içi bağımlılıkların tespit edilmesinin imkansızlığı nedeniyle, varsayılan seçici testin maksimum granülerliği hedef düzeyindedir. [Kapsam stratejisi](#coverage-based-test-selection) bunu tekil testlere kadar daraltır. Bu nedenle, seçici testin faydalarını en üst düzeye çıkarmak için hedeflerinizi küçük ve odaklı tutmanızı öneririz.


## Kapsama dayalı test seçimi {#coverage-based-test-selection}

> [!NOTE]
> **Erken erişim**
>
> Kapsama dayalı test seçimi erken erişim aşamasındadır. Hesabınızda etkinleştirmek için bizimle iletişime geçin. Etkinleştirilene kadar strateji, varsayılan seçici test gibi davranır.

Varsayılan olarak, seçici test hashi daha önce geçen tüm test hedeflerini atlar. `.coverage()` stratejisi daha ileri gider: kalan test hedeflerinde, daha önceki bir çalıştırmadaki kod kapsamının değişikliğinizin dokunduğu dosyalardan hiçbirini içermediği testleri de atlar. XCTest ve XCUITest testleriyle ve bunun için yapılandırılmış paketlerdeki [Swift Testing](#swift-testing) testleriyle çalışır. `Tuist.swift` içinde etkinleştirin:

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

- **Kapsam yüklemeleri.** Tuist, önceki çalıştırmaların yüklediği kapsama verilerine göre testleri seçer; bu nedenle `tuist test`, `upload: false` ile ayarlanmış `.coverage()` içeren bir manifesti yükleyemez.
- **[TestCoverageAttribution](https://github.com/tuist/TestCoverageAttribution) 0.5.1 veya sonrası** [test hedefleriniz tarafından bağlanmış olmalıdır](#linking-testcoverageattribution). Her testin hangi dosyaları yürüttüğünü kaydeder ve Tuist'in seçmediği testleri atlar. Bu olmadan bir hedef, varsayılan davranışta olduğu gibi yalnızca tamamı atlanır.
- **Yeterince sık yapılan tam test çalıştırmaları.** `tuist test --no-selective-testing` ile yapılan bir çalışma her testi yürütür ve bir temel haline gelir. Seçici bir çalışma, aynı platformdaki commit geçmişindeki yakın bir temel ile karşılaştırma yapar ve temel olmadan kapsam uygulamaz. Bunların nerede ve ne sıklıkta çalıştırılacağı ekibinizin çalışma şekline bağlıdır; örneğin varsayılan dalınızın her commitinde, geceleyin veya sürüm dallarında. Varsayılan dalı öneririz: buradaki tam bir çalışma, bir değişiklik yayınlanmadan önce kapsamın göremediği şeyleri, örneğin bir testin bağımlı olduğu bir fixture veya hizmeti de yakalar.

Strateji açıkken, `tuist test` hashi daha önce geçen hedefleri atlar, ardından Tuist'e kalan hedeflerden hangilerinin değişikliğinizden etkilenebileceğini sorar. Etkilenen testi olmayan hedefler derlenmez. Yeni testler, son seferde başarısız olan testler, değiştirilmiş bir test dosyasındaki testler ve kaydedilmiş kapsamı olmayan testler her zaman çalışır.

Bazen kapsam uygulanmaz ve çıktı nedenini açıklar: hashi geçmeyen hedeflerin tüm testleri, varsayılan seçici testte olduğu gibi çalışır. Bu durum, aynı platformda yakın bir temel olmadığında, değişiklik 5.000'den fazla dosyaya dokunduğunda veya herhangi bir testi etkileyebilecek bir dosya değiştiğinde, örneğin `Package.resolved`, `Project.swift` veya bir `.xcconfig` durumunda gerçekleşir. Her testi çalıştırmak için `--no-selective-testing` parametresini kullanın.

> [!NOTE]
> **Test kapsamı**
>
> Tek bir çalıştırmanın raporunu okuyan kapsam araçları (Xcode dahil) tüm test paketinin çalıştığını varsayar, bu nedenle seçici bir çalıştırmanın raporu atladığı testleri dışarıda bırakır. Tuist'in <.localized_link href="/guides/features/test-code-coverage/generated-xcode-project">kod kapsamı</.localized_link> bunun yerine, her çalıştırmada kaydettiği <.localized_link href="/guides/features/test-code-coverage/generated-xcode-project#target-level-coverage">hedef düzeyi kapsamı</.localized_link> kullanarak atlanan test hedeflerinin kapsamını önceki bir çalıştırmadan taşır.

### TestCoverageAttribution bağlama {#linking-testcoverageattribution}

Paketi `Tuist/Package.swift` konumuna ekleyin ve küçük sürümüne sabitleyin, çünkü 0.x küçük sürümü kaydettiklerini değiştirebilir:

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

Tuist, paketleri varsayılan olarak statik çerçeveler olarak bağlar. Yalnızca XCTest içeren bir hedef pakette hiçbir şeye referans vermez, bu nedenle bağlayıcı onu ve buna bağlı olarak kaydetme ve atlama işlemlerini düşürür. Test hedefinin `OTHER_LDFLAGS` değerine `-ObjC` ekleyin veya paketi `Tuist/Package.swift` içinde dinamik olarak bağlayın:

```swift
#if TUIST
    import ProjectDescription

    let packageSettings = PackageSettings(
        productTypes: ["TestCoverageAttribution": .framework]
    )
#endif
```

### Swift Testing {#swift-testing}

Swift Testing'in bir kütüphanenin katılabileceği bir gözlem API'si yoktur, bu nedenle testlerinin paketinde TestCoverageAttribution'ın `.coverageAttribution` özelliğine ihtiyacı vardır. Bu özellik, kendisine sahip olan pakete iç içe geçmiş paketlere de uygulanır. Bu özelliğe sahip olmayan paketlerdeki testler test başına kapsam kaydetmez, bu nedenle hedefleri çalıştığında onlar da çalışır.

```swift
import TestCoverageAttribution
import Testing

@Suite(.coverageAttribution)
struct DiscountTests {
    @Test func appliesDiscount() { … }
}
```

- **Testler örtüşmemelidir.** Swift Testing, varsayılan olarak bir işlemin testlerini paralel olarak çalıştırır ve kapsam sayaçları aynı anda çalışan testleri ayırt edemez, bu nedenle bu testler kendi kapsamlarını kaydetmez ve her zaman çalışır. `.serialized` yalnızca bir paketin kendi testlerini sıralar, bu nedenle yalnızca hedef tek bir pakete sahip olduğunda yeterlidir. XCTest'in ekstra bir yapılandırmaya ihtiyacı yoktur: paralel testleme her test klonunu kendi işleminde çalıştırır.
- **Paralelleştirmeyi test hedefi başına kapatın.** Xcode ayarı her test hedefine uygular, bu nedenle onu yalnızca test bazında seçilmesini istediğiniz hedefler için kapatabilirsiniz ve şemanın diğer hedefleri paralel çalışmaya devam eder. Ayrı bir şemaya gerek yoktur. Bunu test edilebilir hedef üzerinde ayarlayın, `.testableTarget(target: "CheckoutTests", parallelization: .disabled)`, bu ayrıca o hedefin XCTest testlerini klonlar olmadan çalıştırır. Tuist'in oluşturduğu şemalar bunu projenin `testingOptions` değerinden alır; `.parallelizable` veya `.swiftTestingOnlyParallelizable` içermedikleri sürece kapalıdır. `tuist test` komutuna `-parallel-testing-enabled YES` veya `NO` parametresini iletmek, o çalışma için her hedefin ayarını geçersiz kılar.
- **Atlama için Swift 6.3 (Xcode 26.4) veya sonraki sürümler gerekir.** Özellik, Tuist'in seçmediği testleri iptal eder ve bunları atlanmış olarak raporlar. Daha eski sürümlerde testler yine de kapsam kaydeder, ancak Tuist'in seçmediği testler yine de çalışır.

### Her zaman çalışan testler {#tests-that-always-run}

Kapsam yalnızca bir testin yürüttüğü kodu görür. Gerçek girdileri fixture'lar, kaynaklar, ağ veya ortam olan bir test, kapsanan kodda herhangi bir değişiklik olmadan bozulabilir. Onu atlanamaz olarak işaretlerseniz, Tuist onu seçmese bile çalışır:

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

Bu yalnızca çalışan test hedeflerinde geçerlidir. Hashi zaten geçen veya Tuist'in hiçbir testini seçmediği bir hedef tamamen atlanır ve asla başlamaz, bu nedenle onun atlanamaz testleri de çalışmaz.

Tüm seçenekler için [TestCoverageAttribution README](https://github.com/tuist/TestCoverageAttribution#unskippable-tests) dosyasına bakın.

### Bir seçimi inceleme {#inspecting-a-selection}

Test çalıştırmasının Seçici Test sekmesi, kapsamın neyi seçtiğini ve nedenini gösterir. Aynı verilere CLI üzerinden, betik yazımı için `--json` ile ve ajanlar için <.localized_link href="/guides/features/agentic-coding/mcp">Model Context Protocol sunucusu</.localized_link> aracılığıyla erişilebilir:

```sh
tuist test list --selective-testing coverage           # the runs coverage-based selection decided
tuist test show <test-run-id>                          # a run's strategy, baseline and test counts
tuist test selective-testing list <test-run-id>        # each test selected or skipped, with its reason and the file that matched
tuist test selective-testing changed-files <test-run-id>  # the files that changed since the baseline
tuist test case run show <test-case-run-id>            # why a test ran
```

Kapsam uygulanmadığında, testler yine de kapsam tabanlı bir seçim olarak sayılır: nedenleri, kapsamın karar verememesinin sebebini, örneğin `tracked_file_changed` gibi belirtir.


## Çekme/birleştirme isteği yorumları {#pullmerge-request-comments}

> [!WARNING]
> **Git forge entegrasyonu gerekli**
>
> Otomatik çekme/birleştirme isteği yorumları almak için <.localized_link href="/guides/server/accounts-and-projects">Tuist projenizi</.localized_link> bir Git forge ile entegre edin: <.localized_link href="/guides/integrations/gitforge/github">GitHub</.localized_link>, <.localized_link href="/guides/integrations/gitforge/origin">Cursor Origin</.localized_link> veya <.localized_link href="/guides/integrations/gitforge/entire">Entire</.localized_link>.


Tuist projeniz [GitHub](https://github.com) gibi Git platformunuzla bağlantılı hale geldiğinde ve CI iş akışınızın bir parçası olarak `tuist test` kullanmaya başladığınızda, Tuist doğrudan çekme/birleştirme isteklerinize hangi testlerin çalıştırıldığını ve hangilerinin atlandığını içeren bir yorum gönderir: ![Tuist Önizleme bağlantısı içeren GitHub uygulaması yorumu](/images/guides/features/selective-testing/github-app-comment.png)


## Panoda kaçırılanları inceleme {#investigating-misses-on-the-dashboard}

Daha önce önbelleğe alınmış bir test hedefi kaçırma olarak göründüğünde, bir test çalıştırması sayfasındaki **Seçici Test** sekmesi, hashi üreten girdileri derinlemesine incelemenize olanak tanır. Bir satırı genişletmek, bileşen başına alt hashleri — kaynaklar, bağımlılıklar, ortam değişkenleri, proje ve hedef ayarları, Info.plist, yetkiler, başlıklar vb. — ortaya çıkarır, böylece çalıştırmalar arasında sapma gösteren girdiyi tespit edebilirsiniz.

Seçici Test kartının üst kısmındaki **JSON olarak Kopyala** düğmesini kullanarak her seçici test hedefini hashi ve alt hashleriyle birlikte dışa aktarın. İki çalışma arasındaki JSON'u karşılaştırmak, test hedefinin hashi saptığında hangi girdinin değiştiğini doğrulamanın en hızlı yoludur.
