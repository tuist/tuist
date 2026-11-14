---
{
  "title": "Oluşturulan Xcode projesi",
  "titleTemplate": ":title · Seçici test · Özellikler · Kılavuzlar · Tuist",
  "description": "Tuist Seçici Test ile yalnızca son değişikliklerinizden etkilenen Xcode ve oluşturulan proje testlerini çalıştırın, böylece sürekli entegrasyon geri bildirimi saniyeler içinde sağlar."
}
---
# Oluşturulan Xcode projesi {#generated-xcode-project}

Bir proje büyüdükçe, her push işleminden sonra tüm testleri çalıştırmak ölçeklenemez hale gelir. Tuist'in seçici testi, Tuist'in <.localized_link href="/guides/features/projects/hashing">hashing algoritmasına</.localized_link> dayanarak yalnızca son başarılı test çalıştırmasından bu yana hedefleri değişen testleri çalıştırır.

Testleri <.localized_link href="/guides/features/projects">oluşturulan projenizle</.localized_link> seçici olarak çalıştırmak için `tuist test` komutunu kullanın. Komut, projenizi <.localized_link href="/guides/features/cache/module-cache">modül önbelleği</.localized_link> için yaptığı gibi <.localized_link href="/guides/features/projects/hashing">hash'ler</.localized_link> ve başarı durumunda, gelecekteki çalıştırmalarda nelerin değiştiğini belirlemek için hash değerlerini kalıcı hale getirir. Gelecekteki çalıştırmalarda `tuist test`, testleri filtrelemek ve yalnızca son başarılı test çalıştırmasından bu yana değişenleri çalıştırmak için hash değerlerini şeffaf bir şekilde kullanır.

`tuist test`, test paketinizi çalıştırırken derleme süresini iyileştirmek amacıyla yerel veya uzak depolamanızdaki ikili dosyaları mümkün olduğunca kullanmak üzere <.localized_link href="/guides/features/cache/module-cache">modül önbelleği</.localized_link> ile doğrudan entegre olur. Seçici testin modül önbellekleme ile birleşimi, CI ortamınızda testlerin çalışması için gereken süreyi önemli ölçüde azaltabilir.

Testleriniz yalnızca simülatör hedeflerini içeriyorsa, `tuist test` öğesinin önbelleğe alınmış ikili dosyaların yalnızca simülatör dilimlerini kullanmasını ve indirmesini sağlamak için `--destination simulator` parametresini iletin. Bkz. <.localized_link href="/guides/features/cache/module-cache#destination-selection">hedef seçimi</.localized_link>. Seçici test hash değerleri her `--destination` değeri için aynıdır.

## Derleme ve test işlerini ayırma {#separate-build-and-test-jobs}

Seçici test, ayrı derleme ve test işlerini destekler. Derleme işinde `tuist test --build-only` komutunu çalıştırarak Tuist'in, derlemenin ürettiği ürünlerin yanında bir `selective-testing-graph.json` dosyasını kalıcı hale getirmesini sağlayın. Bu graf, seçici testin ihtiyaç duyduğu hash değerlerini taşır; böylece test işi, hangi hedeflerin çalıştırılacağını belirlemek için projeyi yeniden oluşturmak veya Swift Package bağımlılıklarını çözmek zorunda kalmaz.

Tuist, `--build-only` sırasında grafiği iki yere yazar:

- `-testProductsPath` parametresini ilettiğinizde `.xctestproducts` paketi içinde.
- Türetilmiş verilerin `Build/Products/` dizini altındaki her `.xctestrun` dosyasının yanında.

Her iki çıktıdan birini derlenen ürünlerin yanında önbelleğe alın ve test işinde `--without-building` parametresine aynı yolu iletin. Her iki yöntem de çalışır:

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

Tuist bu grafiği girişin yanında bulamadığında (örneğin, derleme işi `tuist test --build-only` yerine düz `xcodebuild build-for-testing` kullandığında), etkilenen hedefleri yine hesaplayabilmek için projeyi yeniden oluşturmaya geri döner. Bu geri dönüş mekanizması, Swift Package bağımlılıklarının test işinde çözülmesini gerektirir; bu nedenle önce `tuist install` komutunu çalıştırın veya işler arasında `Tuist/.build` önbelleğe alın.

Graf, derleme zamanındaki kaynak ağacını yansıtır. Test işini, derleme işiyle aynı commit üzerinde çalıştırın — eğer ikisi arasında kaynak sapması olursa, hash değerleri artık kaynakla eşleşmez ve seçici test, daha yeni kaynağa karşı aslında başarısız olacak testleri atlayabilir.

### Hangi bayrağı kullanmalıyım? {#which-flag-should-i-use}

`.xctestrun` ve `.xctestproducts`, iki farklı Xcode çıktı formatıdır ve taşınabilirlik ile işlem hattı kolaylığı arasında bir denge kurarlar:

- **`-testProductsPath` (`.xctestproducts`) — yeni işlem hatları için önerilir.** Kendi kendine yeten bir dizindir: derlenen `.xctest` ikili dosyaları ve bunların `.xctestrun` dosyaları, yolları paket köküne göreli hale getirilmiş olarak içinde bulunur; böylece nereye giderse gitsin geçerliliğini korur.
- **`-xctestrun` (ham `.xctestrun`) — zaten türetilmiş veri etrafında kurulmuş bir işlem hattınız varsa bunu kullanın.** `xcodebuild build-for-testing`, varsayılan olarak `<derivedData>/Build/Products/` üstüne bir `.xctestrun` yazar ve onu o ağaçtaki başka yerlerde bulunan test paketlerine işaret eder. Başka bir işte yeniden kullanmak, `Build/Products/` içindeki yolların bozulmadan kalmasını gerektirir.

Yeni başlıyorsanız `-testProductsPath` tercih edin. Tuist'i, türetilmiş verileri zaten önbelleğe alan mevcut bir işlem hattına entegre ediyorsanız, derleme işi `tuist test --build-only` üzerinden çalıştığı sürece `-xctestrun` aynı hızlı yolu izler.

Her iki giriş modu da `-workspace`/`-project`/`-scheme` ile karşılıklı olarak özel olduğundan, passthrough argümanları `-xctestrun` veya `-testProductsPath` içerdiğinde Tuist bu bayrakları atlar ve seçilen hedefleri `-only-testing` üzerinden iletir.

> [!WARNING]
> **Modül ve dosya düzeyinde granülerlik**
>
> Testler ve kaynaklar arasındaki kod içi bağımlılıkların tespit edilmesinin imkansızlığı nedeniyle, varsayılan seçici testin maksimum granülerliği hedef düzeyindedir. [Kapsam stratejisi](#coverage-based-test-selection) bunu tekil testlere kadar daraltır. Bu nedenle, seçici testin faydalarını en üst düzeye çıkarmak için hedeflerinizi küçük ve odaklı tutmanızı öneririz.


## Kapsama dayalı test seçimi {#coverage-based-test-selection}

> [!NOTE]
> **Erken erişim**
>
> Kapsama dayalı test seçimi erken erişim aşamasındadır. Hesabınızda etkinleştirmek için bizimle iletişime geçin. Etkinleştirilene kadar strateji, varsayılan seçici test gibi davranır.

Varsayılan olarak, seçici test hash değeri daha önce geçen tüm test hedeflerini atlar. `.coverage()` stratejisi daha ileri gider: kalan test hedeflerinde, daha önceki bir çalıştırmadaki kod kapsamının değişikliğinizin dokunduğu dosyaların hiçbirini içermemediği testleri de atlar. XCTest ve XCUITest testleriyle ve bunun için yapılandırılmış paketlerdeki [Swift Testing](#swift-testing) testleriyle çalışır. `Tuist.swift` içinde etkinleştirin:

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

- **Kapsam yüklemeleri.** Tuist, testleri önceki çalıştırmaların yüklediği kapsama verilerine göre seçer; bu nedenle `tuist test`, `upload: false` ile ayarlanmış `.coverage()` içeren bir manifesti yükleyemez.
- **[TestCoverageAttribution](https://github.com/tuist/TestCoverageAttribution) 0.5.1 veya üzeri** [test hedefleriniz tarafından bağlantılı](#linking-testcoverageattribution). Her testin hangi dosyaları yürüttüğünü kaydeder ve Tuist'in seçmediği testleri atlar. Bu olmadan bir hedef, varsayılan durumda olduğu gibi yalnızca tamamen atlanır.
- **Yeterince sık yapılan tam test çalıştırmaları.** `tuist test --no-selective-testing` ile yapılan bir çalıştırma her testi yürütür ve bir temel çizgi haline gelir. Seçici bir çalıştırma, aynı platformdaki commit geçmişindeki yakın tarihli bir çalıştırma ile karşılaştırma yapar ve böyle bir temel çizgi olmadan kapsam uygulamaz. Bunların nerede ve ne sıklıkla çalıştırılacağı, ekibinizin çalışma şekline bağlıdır; örneğin varsayılan dalınızın her commitinde, gecelik veya sürüm dallarında. Varsayılan dalı öneriyoruz: buradaki tam bir çalıştırma, bir değişiklik yayınlanmadan önce kapsamın göremediği şeyleri, örneğin bir testin bağımlı olduğu bir fixture veya hizmeti de yakalar.

Strateji açıkken, `tuist test` hash değeri daha önce geçen hedefleri atlar, ardından Tuist'e kalan hedeflerden hangilerinin değişikliğinizden etkilenebileceğini sorar. Etkilenen testi olmayan hedefler derlenmez. Yeni testler, son seferde başarısız olan testler, değiştirilmiş bir test dosyasındaki testler ve kaydedilmiş kapsamı olmayan testler her zaman çalışır.

Bazen kapsam uygulanmaz ve çıktı bunun nedenini açıklar: hash değeri geçmeyen hedeflerin tüm testleri, varsayılan seçici testte olduğu gibi çalıştırılır. Bu durum, aynı platformda yakın tarihli bir temel çizgi olmadığında, değişiklik 5.000'den fazla dosyaya dokunduğunda veya `Package.resolved`, `Project.swift` ya da bir `.xcconfig` gibi herhangi bir testi etkileyebilecek bir dosya değiştiğinde gerçekleşir. Her testi çalıştırmak için `--no-selective-testing` parametresini kullanın.

> [!NOTE]
> **Test kapsamı**
>
> Xcode dahil olmak üzere tek bir çalıştırmanın raporunu okuyan kapsam araçları, tüm test paketinin çalıştığını varsayar; bu nedenle seçici bir çalıştırmanın raporu atladığı testleri dışarıda bırakır. Tuist'in <.localized_link href="/guides/features/test-code-coverage/generated-xcode-project">kod kapsamı</.localized_link> özelliği bunun yerine, her çalıştırmada kaydettiği <.localized_link href="/guides/features/test-code-coverage/generated-xcode-project#target-level-coverage">hedef düzeyi kapsamı</.localized_link> kullanarak atlanan test hedeflerinin kapsam verilerini önceki bir çalıştırmadan taşır.

### TestCoverageAttribution bağlantısı {#linking-testcoverageattribution}

Paketi `Tuist/Package.swift` dosyasına ekleyin ve küçük sürümüne sabitleyin; çünkü 0.x küçük sürümleri kaydedilen verileri değiştirebilir:

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

Tuist varsayılan olarak paketleri statik çerçeveler olarak bağlar. Yalnızca XCTest içeren bir hedef paketteki hiçbir şeyi referans almaz, bu nedenle bağlayıcı onu ve buna bağlı olarak kayıt ve atlama işlevlerini düşürür. Test hedefinin `OTHER_LDFLAGS` değerine `-ObjC` ekleyin veya paketi `Tuist/Package.swift` içinde dinamik olarak bağlayın:

```swift
#if TUIST
    import ProjectDescription

    let packageSettings = PackageSettings(
        productTypes: ["TestCoverageAttribution": .framework]
    )
#endif
```

### Swift Testing {#swift-testing}

Swift Testing'in bir kütüphanenin katılabileceği bir gözlem API'si yoktur, bu nedenle testlerinin paketinde TestCoverageAttribution'ın `.coverageAttribution` niteliğine sahip olması gerekir. Bu nitelik, kendisine sahip olan paketin içinde yer alan alt paketlere de uygulanır. Bu niteliğe sahip olmayan paketlerdeki testler test başına kapsam kaydetmez, bu nedenle hedefleri çalıştığında onlar da çalışır.

```swift
import TestCoverageAttribution
import Testing

@Suite(.coverageAttribution)
struct DiscountTests {
    @Test func appliesDiscount() { … }
}
```

- **Testler örtüşmemelidir.** Swift Testing varsayılan olarak bir işlemin testlerini paralel olarak çalıştırır ve kapsam sayaçları aynı anda çalışan testleri ayırt edemez; bu nedenle bu testler kendi kapsamlarını kaydetmez ve her zaman çalışır. `.serialized` yalnızca bir paketin kendi testlerini sıralar, bu nedenle yalnızca hedef tek bir pakete sahip olduğunda yeterlidir. XCTest'in ekstra bir yapılandırmaya ihtiyacı yoktur: paralel testleme her test klonunu kendi işleminde çalıştırır.
- **Paralelleştirmeyi test hedefi başına kapatın.** Xcode ayarı her test hedefine uygular, bu nedenle yalnızca test bazında seçim yapmak istediğiniz hedefler için kapatabilirsiniz ve şemanın diğer hedefleri paralel çalışmaya devam eder. Ayrı bir şemaya gerek yoktur. Bunu test edilebilir hedef üzerinde ayarlayın: `.testableTarget(target: "CheckoutTests", parallelization: .disabled)`. Bu ayar ayrıca o hedefin XCTest testlerini klonlar olmadan çalıştırır. Tuist'in oluşturduğu şemalar bunu projenin `testingOptions` ayarından alır; `.parallelizable` veya `.swiftTestingOnlyParallelizable` içermiyorlarsa kapalıdır. `tuist test` komutuna `-parallel-testing-enabled YES` veya `NO` parametresini iletmek, o çalıştırma için her hedefin ayarını geçersiz kılar.
- **Atlama işlemi için Swift 6.3 (Xcode 26.4) veya üzeri gereklidir.** Nitelik, Tuist'in seçmediği testleri iptal eder ve bunları atlanmış olarak raporlar. Daha eski sürümlerde testler yine de kapsam kaydeder, ancak Tuist'in seçmediği testler yine de çalışır.

### Her zaman çalışan testler {#tests-that-always-run}

Kapsam yalnızca bir testin yürüttüğü kodu görür. Gerçek girdileri fixture'lar, kaynaklar, ağ veya ortam olan bir test, kapsanan kodda herhangi bir değişiklik olmadan bozulabilir. Testi atlanamaz olarak işaretlerseniz, Tuist onu seçmese bile çalışır:

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

Bu yalnızca çalışan test hedeflerinde geçerlidir. Hash değeri daha önce geçen veya Tuist'in hiçbir testini seçmediği bir hedef tamamen atlanır ve hiç başlamaz, bu nedenle onun atlanamaz testleri de çalışmaz.

Tüm seçenekler için [TestCoverageAttribution README](https://github.com/tuist/TestCoverageAttribution#unskippable-tests) dosyasına bakın.


## Çekme/birleştirme isteği yorumları {#pullmerge-request-comments}

> [!WARNING]
> **Git forge entegrasyonu gerekli**
>
> Otomatik çekme/birleştirme isteği yorumları almak için <.localized_link href="/guides/server/accounts-and-projects">Tuist projenizi</.localized_link> bir Git forge ile entegre edin: <.localized_link href="/guides/integrations/gitforge/github">GitHub</.localized_link>, <.localized_link href="/guides/integrations/gitforge/origin">Cursor Origin</.localized_link> veya <.localized_link href="/guides/integrations/gitforge/entire">Entire</.localized_link>.


Tuist projeniz [GitHub](https://github.com) gibi Git platformunuzla bağlantılı hale geldiğinde ve `tuist test` öğesini CI iş akışınızın bir parçası olarak kullanmaya başladığınızda, Tuist pull/merge requestlerinize doğrudan bir yorum gönderir; bu yorumda hangi testlerin çalıştırıldığı ve hangilerinin atlandığı belirtilir: ![Tuist Önizleme bağlantısı içeren GitHub uygulaması yorumu](/images/guides/features/selective-testing/github-app-comment.png)


## Panoda kaçırılanları inceleme {#investigating-misses-on-the-dashboard}

Daha önce önbelleğe alınmış bir test hedefi kaçırılmış (miss) olarak göründüğünde, bir test çalıştırması sayfasındaki **Seçici Test** sekmesi, hash değerini üreten girdileri detaylı incelemenize olanak tanır. Bir satırı genişletmek bileşen bazlı alt hash değerlerini — kaynaklar, bağımlılıklar, ortam değişkenleri, proje ve hedef ayarları, Info.plist, yetkiler, başlık dosyaları vb. — ortaya çıkarır; böylece çalıştırmalar arasında sapma gösteren girdiyi tespit edebilirsiniz.

Seçici Test kartının üst kısmındaki **JSON Olarak Kopyala** düğmesini kullanarak her seçici test hedefini hash ve alt hash değerleriyle birlikte dışa aktarın. İki çalıştırma arasındaki JSON'u karşılaştırmak, test hedefinin hash değeri saptığında hangi girdinin değiştiğini doğrulamanın en hızlı yoludur.
