---
{
  "title": "Bağımlılıklar",
  "titleTemplate": ":title · Projeler · Özellikler · Kılavuzlar · Tuist",
  "description": "Tuist projenizde bağımlılıkları nasıl tanımlayacağınızı öğrenin."
}
---
# Bağımlılıklar {#dependencies}

Bir proje büyüdükçe, kod paylaşımı yapmak, sınırları belirlemek ve derleme sürelerini iyileştirmek için onu birden çok hedefe bölmek yaygındır. Birden çok hedef, aralarında bir **bağımlılık grafiği** oluşturan bağımlılıkların tanımlanması anlamına gelir; bu grafiğe harici bağımlılıklar da dahil olabilir.

## XcodeProj ile kodlanmış grafikler {#xcodeprojcodified-graphs}

Xcode ve XcodeProj’un tasarımı nedeniyle, bir bağımlılık grafiğinin bakımı zahmetli ve hataya açık bir iş olabilir. Karşılaşabileceğiniz sorunlara ilişkin bazı örnekler şunlardır:

- Xcode’un derleme sistemi projenin tüm ürünlerini derived data içindeki aynı dizine çıkardığından, hedefler olmaması gereken ürünleri içe aktarabilir. Derlemeler, temiz derlemelerin daha yaygın olduğu CI ortamlarında veya farklı bir yapılandırma kullanıldığında başarısız olabilir.
- Bir hedefin geçişli dinamik bağımlılıklarının, `LD_RUNPATH_SEARCH_PATHS` derleme ayarının parçası olan dizinlerden herhangi birine kopyalanması gerekir. Aksi takdirde hedef, çalışma zamanında bunları bulamaz. Grafik küçükken bunu düşünmek ve kurmak kolaydır, ancak grafik büyüdükçe bir sorun haline gelir.
- Bir hedef statik bir [XCFramework](https://developer.apple.com/documentation/xcode/creating-a-multi-platform-binary-framework-bundle) bağladığında, Xcode’un paketi işlemesi ve geçerli platform ile mimari için doğru ikili dosyayı çıkarması amacıyla hedefe ek bir derleme aşaması gerekir. Bu derleme aşaması otomatik olarak eklenmez ve eklemeyi unutmak kolaydır.

Yukarıdakiler yalnızca birkaç örnektir; yıllar içinde karşılaştığımız çok daha fazla sorun vardır. Bir bağımlılık grafiğini sürdürmek ve geçerliliğini sağlamak için bir mühendis ekibine ihtiyaç duyduğunuzu hayal edin. Daha da kötüsü, karmaşıklıkların kontrol edemediğiniz veya özelleştiremediğiniz kapalı kaynaklı bir derleme sistemi tarafından derleme zamanında çözülmesi. Tanıdık geliyor mu? Apple’ın Xcode ve XcodeProj ile benimsediği ve Swift Package Manager’ın miras aldığı yaklaşım budur.

Bağımlılık grafiğinin **açık** ve **statik** olması gerektiğine kesinlikle inanıyoruz çünkü ancak o zaman **doğrulanabilir** ve **optimize edilebilir**. Tuist ile neyin neye bağlı olduğunu tanımlamaya odaklanırsınız, gerisini biz hallederiz. Karmaşıklıklar ve uygulama ayrıntıları sizden soyutlanır.

Aşağıdaki bölümlerde projenizde bağımlılıkların nasıl bildirileceğini öğreneceksiniz.

> [!TIP]
> **Grafik doğrulama**
>
> Tuist, projeyi oluştururken döngü olmadığını ve tüm bağımlılıkların geçerli olduğunu sağlamak için grafiği doğrular. Bunun sayesinde herhangi bir ekip, bağımlılık grafiğini bozma endişesi duymadan grafiğin geliştirilmesine katkıda bulunabilir.


## Yerel bağımlılıklar {#local-dependencies}

Hedefler, aynı ve farklı projelerdeki diğer hedeflere ve ikili dosyalara bağımlı olabilir. Bir `Target` örneği oluştururken, aşağıdaki seçeneklerden herhangi biriyle `dependencies` argümanını iletebilirsiniz:

- `Target`: Aynı proje içindeki bir hedefle bağımlılık bildirir.
- `Project`: Farklı bir projedeki bir hedefle bağımlılık bildirir.
- `Framework`: İkili bir framework ile bağımlılık bildirir.
- `Library`: İkili bir kütüphane ile bağımlılık bildirir.
- `XCFramework`: İkili bir XCFramework ile bağımlılık bildirir.
- `SDK`: Sistem SDK’sı ile bağımlılık bildirir.
- `XCTest`: XCTest ile bağımlılık bildirir.
- `Macro`: Aynı projede tanımlanan bir Swift makro hedefiyle bağımlılık bildirir (bkz. [Swift Makroları](#swift-macros)).

> [!NOTE]
> **Bağımlılık koşulları**
>
> Her bağımlılık türü, bağımlılığı platforma göre koşullu olarak bağlamak için bir `condition` seçeneğini kabul eder. Varsayılan olarak, bağımlılık hedefin desteklediği tüm platformlar için bağlanır.


## Harici bağımlılıklar {#external-dependencies}

Tuist ayrıca projenizde harici bağımlılıklar bildirmenize olanak tanır.

### Swift Paketleri {#swift-packages}

Swift Paketleri, projenizde bağımlılık bildirmek için önerdiğimiz yoldur. Tuist bunları çözmek için Swift Package Manager’ı kullanır; yerel paketlerle modülerleştirme ile bir Tuist projesinin karşılaştırması için bkz. [Swift Package Manager vs Tuist](https://tuist.dev/compare/swift-package-manager). Bunları Xcode’un varsayılan entegrasyon mekanizmasını kullanarak veya Tuist’in XcodeProj tabanlı entegrasyonunu kullanarak entegre edebilirsiniz.

#### Tuist’in XcodeProj tabanlı entegrasyonu {#tuists-xcodeprojbased-integration}

Xcode’un varsayılan entegrasyonu en kullanışlı yöntem olsa da, orta ve büyük ölçekli projeler için gereken esneklik ve kontrolden yoksundur. Bunu aşmak için Tuist, Swift Paketlerini projenize XcodeProj hedeflerini kullanarak entegre etmenizi sağlayan XcodeProj tabanlı bir entegrasyon sunar. Bunun sayesinde, entegrasyon üzerinde size daha fazla kontrol sunmanın yanı sıra, <.localized_link href="/guides/features/cache">önbellekleme</.localized_link> ve <.localized_link href="/guides/features/selective-testing">seçici test çalıştırmaları</.localized_link> gibi iş akışlarıyla uyumlu hale getirebiliriz.

XcodeProj entegrasyonunun yeni Swift Package özelliklerini desteklemesi veya daha fazla paket yapılandırmasını yönetmesi daha uzun zaman alabilir. Ancak Swift Paketleri ile XcodeProj hedefleri arasındaki eşleme mantığı açık kaynaktır ve topluluk tarafından katkıda bulunulabilir. Bu durum, kapalı kaynaklı olan ve Apple tarafından sürdürülen Xcode’un varsayılan entegrasyonunun tersinedir.

Harici bağımlılıklar eklemek için, `Tuist/` altında veya projenin kök dizininde bir `Package.swift` dosyası oluşturmanız gerekir.

::: code-group
```swift [Tuist/Package.swift]
// swift-tools-version: 5.9
import PackageDescription

#if TUIST
    import ProjectDescription
    import ProjectDescriptionHelpers

    let packageSettings = PackageSettings(
        productTypes: [
            "Alamofire": .framework, // default is .staticFramework
        ]
    )

#endif

let package = Package(
    name: "PackageName",
    dependencies: [
        .package(url: "https://github.com/Alamofire/Alamofire", from: "5.0.0"),
    ],
    targets: [
        .binaryTarget(
            name: "Sentry",
            url: "https://github.com/getsentry/sentry-cocoa/releases/download/8.40.1/Sentry.xcframework.zip",
            checksum: "db928e6fdc30de1aa97200576d86d467880df710cf5eeb76af23997968d7b2c7"
        ),
    ]
)
```
<!-- -->
:::

> [!TIP]
> **Paket ayarları**
>
> Bir derleyici yönergesiyle sarılmış `PackageSettings` örneği, paketlerin nasıl entegre edileceğini yapılandırmanıza olanak tanır. Örneğin, yukarıdaki örnekte paketler için kullanılan varsayılan ürün türünü geçersiz kılmak amacıyla kullanılır. Varsayılan olarak buna ihtiyacınız olmamalıdır. Ayrıca SwiftPM ikili hedefleri için beklenen imzaları `expectedSignatures` aracılığıyla yapılandırmak için de kullanabilirsiniz.


### İkili Hedef İmzaları

Yerel veya uzak bir Swift paketi ikili bir XCFramework hedefi sunuyorsa, beklenen imzasını `PackageSettings.expectedSignatures` kullanarak yapılandırabilirsiniz:

```swift
#if TUIST
    import ProjectDescription

    let packageSettings = PackageSettings(
        expectedSignatures: [
            "SelfSignedXCFramework": .selfSigned(
                fingerprint: "EF61C3C0339FC84805357AFEC2E0BB0E6A0D5EE64165B333F934BF9E282785BC"
            ),
        ]
    )
#endif
```

> [!IMPORTANT] CUSTOM BUILD CONFIGURATIONS
> Projeniz özel derleme yapılandırmaları (standart `Debug` ve `Release` dışındaki yapılandırmalar) kullanıyorsa, bunları `PackageSettings` içinde `baseSettings` kullanarak belirtmeniz gerekir. Harici bağımlılıkların doğru şekilde derlenebilmesi için projenizin yapılandırmalarını bilmesi gerekir. Örneğin:
>
> ```swift
> #if TUIST
>     import ProjectDescription
>
>     let packageSettings = PackageSettings(
>         productTypes: [:],
>         baseSettings: .settings(configurations: [
>             .debug(name: "Base"),
>             .release(name: "Production")
>         ])
>     )
> #endif
> ```
>
> Daha fazla ayrıntı için bkz. [#8345](https://github.com/tuist/tuist/issues/8345).

`Package.swift` dosyası yalnızca harici bağımlılıkları bildirmek için bir arayüzdür, başka bir şey değildir. Bu nedenle pakette herhangi bir hedef veya ürün tanımlamazsınız. Bağımlılıkları tanımladıktan sonra, bağımlılıkları çözmek ve `Tuist/Dependencies` dizinine çekmek için aşağıdaki komutu çalıştırabilirsiniz:

```bash
tuist install
# Resolving and fetching dependencies.
# Installing Swift Package Manager dependencies.
```

Fark etmiş olabileceğiniz gibi, [CocoaPods](https://cocoapods.org)’a benzer bir yaklaşım benimsiyoruz; burada bağımlılıkların çözülmesi ayrı bir komutla yapılır. Bu, kullanıcılara bağımlılıkların ne zaman çözüleceği ve güncelleneceği konusunda kontrol sağlar ve projenin Xcode’da açıldığında derlemeye hazır olmasına olanak tanır. Proje büyüdükçe Apple’ın Swift Package Manager entegrasyonunun sunduğu geliştirici deneyiminin zamanla azaldığına inanıyoruz.

Proje hedeflerinizden bu bağımlılıklara `TargetDependency.external` bağımlılık türünü kullanarak başvurabilirsiniz:

::: code-group
```swift [Project.swift]
import ProjectDescription

let project = Project(
    name: "App",
    organizationName: "tuist.io",
    targets: [
        .target(
            name: "App",
            destinations: [.iPhone],
            product: .app,
            bundleId: "dev.tuist.app",
            deploymentTargets: .iOS("13.0"),
            infoPlist: .default,
            sources: ["Targets/App/Sources/**"],
            dependencies: [
                .external(name: "Alamofire"),
            ]
        ),
    ]
)
```
<!-- -->
:::

> [!NOTE]
> **Harici paketler için şema oluşturulmaz**
>
> Şemalar listesini temiz tutmak amacıyla Swift Package projeleri için **şemalar** otomatik olarak oluşturulmaz. Bunları Xcode’un arayüzü üzerinden oluşturabilirsiniz.


#### Xcode’un varsayılan entegrasyonu {#xcodes-default-integration}

Xcode’un varsayılan entegrasyon mekanizmasını kullanmak istiyorsanız, bir proje örneği oluştururken `packages` listesini iletebilirsiniz:

```swift
let project = Project(name: "MyProject", packages: [
    .package(url: "https://github.com/krzyzanowskim/CryptoSwift", .exact("1.8.0"))
])
```

Ardından bunlara hedeflerinizden şu şekilde başvurabilirsiniz:

```swift
let target: Target = .target(name: "MyTarget", destinations: .iOS, product: .framework, bundleId: "dev.tuist.MyTarget", dependencies: [
    .package(product: "CryptoSwift", type: .runtime)
])
```

Xcode’un varsayılan entegrasyonu aracılığıyla harici bir Swift Paketinden bir Swift Makrosu veya Derleme Aracı Eklentisi entegre ederken, bunları sırasıyla `.macro` ve `.plugin` türleriyle bildirin. Makrolar ayrıca [Tuist’in XcodeProj tabanlı entegrasyonu](#tuists-xcodeprojbased-integration) aracılığıyla da kullanılabilir ve bir paketten tüketmek yerine kendi Swift makronuzu tanımlamak istiyorsanız bkz. [Swift Makroları](#swift-macros).

> [!WARNING]
> **SPM derleme aracı eklentileri**
>
> SPM derleme aracı eklentileri, proje bağımlılıklarınız için Tuist’in [XcodeProj tabanlı entegrasyonunu](#tuists-xcodeprojbased-integration) kullansanız bile [Xcode’un varsayılan entegrasyon](#xcodes-default-integration) mekanizması kullanılarak bildirilmelidir.

SPM derleme aracı eklentileri, Xcode ve SwiftPM’in bir hedef için çalıştırılması gereken somut derleme komutlarını keşfetmek amacıyla yürüttüğü Swift programlarıdır. Bu komutlar paket grafiğine, hedef dosyalarına, eklenti çalışma dizinine, çözümlenmiş eklenti araçlarına ve eklenti tarafından bildirilen çıktılara bağlı olabilir. Bazı eklentiler ayrıca aynı hedef derlemesinin parçası haline gelmesi gereken dosyalar da oluşturur.

Tuist’in XcodeProj tabanlı entegrasyonu, eşleme statik olduğunda (örneğin kitaplıklar, ikililer, çalıştırılabilir dosyalar ve makrolar) paket ürünlerini yerel Xcode hedeflerine eşler. Derleme aracı eklentilerinin, Xcode’un SwiftPM entegrasyonu dışında eşdeğer bir yerel Xcode projesi ilkel öğesi yoktur. Bir eklenti nihayetinde bir çalıştırılabilir dosya çalıştırabilse de, bu çalıştırılabilir dosyanın normal bir betik derleme aşamasından çağrılması eklentiyi çalıştırmakla eşdeğer değildir: Tuist’in önce eklentinin Swift kodunu değerlendirmesi, SwiftPM’in eklenti bağlamını yeniden oluşturması, komutları keşfetmesi, bildirilen girdileri ve çıktıları modellemesi ve Xcode derlemeyi planlamadan önce oluşturulan tüm dosyaları hedef grafiğine eklemesi gerekir.

Bu nedenle, bir eklenti paketini yalnızca `Tuist/Package.swift` içinde bildirmek ve `.external(name:)` aracılığıyla tüketmek desteklenmez. Desteklenen alternatif, paketi `Project.packages` içinde bildirmek ve eklenti ürününü tüketen hedefe `.package(product:type: .plugin)` ile eklemektir. Bu, eklentinin oluşturulan Xcode projesine bir Swift Package ürün bağımlılığı olarak bağlı kalmasını sağlar, böylece Xcode ve SwiftPM onu yerel eklenti bağlamıyla çalıştırabilir.

Bedeli, Xcode’un bu eklenti entegrasyonuna sahip olmasıdır:

- Xcode, eklenti paketini SwiftPM entegrasyonu aracılığıyla çözer ve derler.
- Paket, oluşturulan projede Tuist tarafından oluşturulan harici bir hedef yerine bir Swift Package referansı olarak görünür.
- Tuist, eklentiye statik olarak eşlenen paket ürünleri için sağlayabildiği kontrol, doğrulama, önbellekleme ve seçici test davranışı düzeyini sunamaz.
- CI ve yerel derlemeler, bu eklenti paketleri için Xcode’un paket çözümlemesine izin vermelidir.

Bu sonuçlar nedeniyle, Tuist projelerinde SPM derleme aracı eklentilerinin kullanılmasını genellikle önermiyoruz. Mümkün olduğunda, hedefte bildirilen bir derleme aşaması betiğini tercih edin veya Tuist ya da Xcode’u çağırmadan önce oluşturulan Xcode projesi dışındaki bir betikten aracı çalıştırın.

Bir SPM derleme aracı eklentisinin pratik bir uygulaması, Xcode’un "Derleme Aracı Eklentilerini Çalıştır" derleme aşaması sırasında kod linting işlemi yapmaktır. Derleme aracı eklentisi bozulmadan bir Xcode projesi oluşturmak için paketi proje manifestosunun `packages` dizisinde bildirin ve ardından bir hedefin bağımlılıklarına `.plugin` türünde bir paket ekleyin.

```swift
import ProjectDescription

let project = Project(
    name: "Framework",
    packages: [
        .package(url: "https://github.com/SimplyDanny/SwiftLintPlugins", from: "0.56.1"),
    ],
    targets: [
        .target(
            name: "Framework",
            destinations: .iOS,
            product: .framework,
            bundleId: "dev.tuist.Framework",
            dependencies: [
                .package(product: "SwiftLintBuildToolPlugin", type: .plugin),
            ]
        ),
    ]
)
```

### Carthage {#carthage}

[Carthage](https://github.com/carthage/carthage) `frameworks` veya `xcframeworks` çıktısı verdiği için, bağımlılıkları `Carthage/Build` dizinine çıkarmak amacıyla `carthage update` komutunu çalıştırabilir ve ardından hedefinizdeki bağımlılığı bildirmek için `.framework` veya `.xcframework` hedef bağımlılık türünü kullanabilirsiniz. Bunu, projeyi oluşturmadan önce çalıştırabileceğiniz bir betik içine alabilirsiniz.

```bash
#!/usr/bin/env bash

carthage update
tuist generate
```

> [!WARNING]
> **Derleme ve test**
>
> Projenizi `xcodebuild build` ve `tuist test` aracılığıyla derleyip test ediyorsanız, benzer şekilde derleme veya test öncesi `carthage update` komutunu çalıştırarak Carthage tarafından çözümlenen bağımlılıkların mevcut olduğundan emin olmanız gerekir.


### CocoaPods {#cocoapods}

[CocoaPods](https://cocoapods.org), bağımlılıkları entegre etmek için bir Xcode projesi bekler. Projeyi oluşturmak için Tuist’i kullanabilir ve ardından projenizi ve Pods bağımlılıklarını içeren bir çalışma alanı oluşturarak bağımlılıkları entegre etmek için `pod install` komutunu çalıştırabilirsiniz. Bunu, projeyi oluşturmadan önce çalıştırabileceğiniz bir betik içine alabilirsiniz.

```bash
#!/usr/bin/env bash

tuist generate
pod install
```

> [!WARNING]
> CocoaPods bağımlılıkları, projeyi oluşturduktan hemen sonra `xcodebuild` çalıştıran `build` veya `test` gibi iş akışlarıyla uyumlu değildir. Ayrıca, parmak izi mantığı Pods bağımlılıklarını hesaba katmadığı için ikili önbellekleme ve seçici test ile de uyumlu değildir.


## Swift Makroları {#swift-macros}

Bir Tuist projesinde [Swift Makroları](https://docs.swift.org/swift-book/documentation/the-swift-programming-language/macros/) ile çalışırken iki farklı senaryo vardır ve hangi durumda olduğunuzu açıkça belirtmek önemlidir:

- **Harici bir Swift Paketinde tanımlanan bir makroyu tüketme.** Her iki entegrasyon mekanizması da makroları destekler. [Tuist’in XcodeProj tabanlı entegrasyonu](#tuists-xcodeprojbased-integration) ile paketi `Tuist/Package.swift` içinde bildirir ve `.external(name:)` ile ona bağımlı olursunuz — Tuist, makro ürününü yerel bir hedefe eşler. [Xcode’un varsayılan entegrasyonu](#xcodes-default-integration) ile bağımlılığı `.package(product:type: .macro)` ile bildirirsiniz. Derleme aracı eklentilerinin aksine, makrolar Xcode’un varsayılan entegrasyonuyla sınırlı değildir.
- **Kendi makronuzu tanımlama** projenizin bir parçası olarak — örneğin monorepo’nuzdaki paylaşılan bir kütüphanede. Bunun için bir `Package.swift` gerekmez: Tuist, birinci sınıf bir `.macro` ürün türüne sahiptir, bu nedenle makro hedefini bildirimlerinizde doğrudan tanımlayabilirsiniz.

### Kendi makronuzu tanımlama {#defining-your-own-macro}

Bir Swift makrosu bir derleyici eklentisidir: Swift derleyicisinin derleme zamanında yüklediği ve çalıştırdığı bir yürütülebilir dosya. Tuist bunu yerel olarak `.macro` ürün türüyle modeller. Apple, Xcode projelerinde bir Swift Makro hedef türü sunmasa da Tuist, bir komut satırı aracı hedefi oluşturarak, onu makroyu kullanan hedeflerin bağımlılığı olarak bağlayarak ve Swift derleyici ayarlarına `-load-plugin-executable` bayrağını enjekte ederek bunu mümkün kılar. Tüm bu altyapı sizin için otomatik olarak yönetilir.

Tipik bir makro iki hedefe ayrılır: makroyu uygulayan **eklenti** hedefi (`product: .macro`) ve makronun genel arayüzünü bildiren (`@attached`/`@freestanding` bildirimleri) ve eklentiye `.macro(name:)` aracılığıyla bağımlı olan **kütüphane** hedefi. Eklenti derleme makinesinde çalıştığı için hedefi yalnızca ana bilgisayar içindir (macOS).

Makro uygulaması [swift-syntax](https://github.com/swiftlang/swift-syntax) bağımlılığına sahiptir; bunu `Tuist/Package.swift` içinde düzenli bir harici bağımlılık olarak bildirirsiniz:

```swift [Tuist/Package.swift]
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PackageName",
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-syntax", from: "600.0.0"),
    ]
)
```

Ardından makro eklentisi ve kütüphane hedeflerini projenizde doğrudan tanımlayabilirsiniz:

```swift [Project.swift]
import ProjectDescription

let project = Project(
    name: "MyLibrary",
    targets: [
        // The compiler plugin that implements the macro. macOS-only, since it
        // runs on the build machine at compile time.
        .target(
            name: "MyMacrosImplementation",
            destinations: [.mac],
            product: .macro,
            bundleId: "dev.tuist.MyMacrosImplementation",
            sources: ["Sources/MyMacrosImplementation/**"],
            dependencies: [
                .external(name: "SwiftSyntax"),
                .external(name: "SwiftSyntaxMacros"),
                .external(name: "SwiftCompilerPlugin"),
            ]
        ),
        // The library that exposes the macro declarations to consumers and
        // depends on the plugin via `.macro(name:)`.
        .target(
            name: "MyLibrary",
            destinations: .iOS,
            product: .framework,
            bundleId: "dev.tuist.MyLibrary",
            sources: ["Sources/MyLibrary/**"],
            dependencies: [
                .macro(name: "MyMacrosImplementation"),
            ]
        ),
    ]
)
```

`MyLibrary` ile bağlantı kuran herhangi bir hedef artık makroyu kullanabilir — Tuist, derleyicinin onu yükleyebilmesi için eklentiyi yaygınlaştırır.


## Statik veya dinamik {#static-or-dynamic}

Çerçeveler ve kütüphaneler statik veya dinamik olarak bağlanabilir; **bu seçim, uygulama boyutu ve başlatma süresi gibi unsurlar üzerinde önemli etkilere sahiptir**. Önemi göz önüne alındığında, bu karar genellikle fazla düşünülmeden verilir.

**Genel kural**, hızlı başlatma süreleri elde etmek için sürüm derlemelerinde mümkün olduğunca çok şeyin statik olarak bağlanması ve hızlı yineleme süreleri elde etmek için hata ayıklama derlemelerinde mümkün olduğunca çok şeyin dinamik olarak bağlanmasıdır.

Bir proje grafiğinde statik ve dinamik bağlama arasında geçiş yapmanın zorluğu, Xcode’da bunun basit olmamasıdır çünkü bir değişiklik tüm grafikte zincirleme etki yaratır (örneğin kütüphaneler kaynak içeremez, statik çerçevelerin gömülmesine gerek yoktur). Apple, sorunu Swift Package Manager’ın statik ve dinamik bağlama arasındaki otomatik kararı veya [Birleştirilebilir Kütüphaneler](https://developer.apple.com/documentation/xcode/configuring-your-project-to-use-mergeable-libraries) gibi derleme zamanı çözümleriyle çözmeye çalıştı. Ancak bu, derleme grafiğine yeni dinamik değişkenler ekleyerek belirsizlik kaynaklarını artırır ve derleme grafiğine dayanan Swift Previews gibi bazı özelliklerin güvenilirliğini potansiyel olarak zedeler.

Neyse ki Tuist, statik ve dinamik arasında geçişle ilişkili karmaşıklığı kavramsal olarak sıkıştırır ve bağlama türleri arasında standart olan <.localized_link href="/guides/features/projects/synthesized-files#bundle-accessors">demet erişimcilerini</.localized_link> sentezler. <.localized_link href="/guides/features/projects/dynamic-configuration">Ortam değişkenleri aracılığıyla dinamik yapılandırmalar</.localized_link> ile birlikte, çağrı zamanında bağlama türünü iletebilir ve hedeflerinizin ürün türünü ayarlamak için bu değeri bildirimlerinizde kullanabilirsiniz.

```swift
// Use the value returned by this function to set the product type of your targets.
func productType() -> Product {
    if case let .string(linking) = Environment.linking {
        return linking == "static" ? .staticFramework : .framework
    } else {
        return .framework
    }
}
```

Tuist’in <.localized_link href="/guides/features/projects/cost-of-convenience">maliyetleri nedeniyle örtük yapılandırma yoluyla kolaylığı varsayılan olarak benimsemediğini</.localized_link> unutmayın. Bu, ortaya çıkan ikili dosyaların doğru olmasını sağlamak için bağlama türünü ve bazen gerekli olan ek derleme ayarlarını, örneğin [`-ObjC` bağlayıcı bayrağını](https://github.com/pointfreeco/swift-composable-architecture/discussions/1657#discussioncomment-4119184), sizin belirlemenize güvendiğimiz anlamına gelir. Bu nedenle benimsediğimiz yaklaşım, doğru kararları verebilmeniz için size genellikle belge biçiminde kaynaklar sağlamaktır.

> [!TIP]
> **Örnek: The Composable Architecture**
>
> Birçok projenin entegre ettiği bir Swift Paketi [The Composable Architecture](https://github.com/pointfreeco/swift-composable-architecture)’dir. Daha fazla ayrıntı için [bu bölüme](#the-composable-architecture) bakın.


### Senaryolar {#scenarios}

Bağlamayı tamamen statik veya dinamik olarak ayarlamanın uygulanabilir olmadığı veya iyi bir fikir olmadığı bazı senaryolar vardır. Aşağıda, statik ve dinamik bağlamayı karıştırmanız gerekebilecek senaryolardan oluşan kapsamlı olmayan bir liste bulunmaktadır:

- **Eklentilere sahip uygulamalar:** Uygulamalar ve eklentilerinin kodu paylaşması gerektiğinden, bu hedefleri dinamik hale getirmeniz gerekebilir. Aksi takdirde, aynı kodun hem uygulamada hem de eklentide kopyalanmasıyla ikili dosya boyutu artar.
- **Önceden derlenmiş harici bağımlılıklar:** Bazen statik veya dinamik olan önceden derlenmiş ikili dosyalar sağlanır. Statik ikili dosyalar, dinamik olarak bağlanmak üzere dinamik çerçeveler veya kütüphaneler içine sarılabilir.

Grafikte değişiklik yaparken Tuist bunu analiz eder ve bir "statik yan etki" algılarsa bir uyarı gösterir. Bu uyarı, dinamik hedefler aracılığıyla dolaylı olarak statik bir hedefe bağımlı olan bir hedefi statik olarak bağlamanızdan kaynaklanabilecek sorunları tespit etmenize yardımcı olmayı amaçlar. Bu yan etkiler genellikle ikili dosya boyutunun artması veya en kötü durumda çalışma zamanı çökmeleri olarak ortaya çıkar.

## Sorun Giderme {#troubleshooting}

### Objective-C Bağımlılıkları {#objectivec-dependencies}

Objective-C bağımlılıklarını entegre ederken, [Apple Teknik SSS QA1490](https://developer.apple.com/library/archive/qa/qa1490/_index.html) bölümünde detaylandırıldığı gibi çalışma zamanı çökmelerini önlemek için tüketen hedefe belirli bayrakların eklenmesi gerekebilir.

Derleme sistemi ve Tuist’in bayrağın gerekli olup olmadığını çıkarmanın bir yolu olmadığından ve bayrak potansiyel olarak istenmeyen yan etkilerle geldiğinden, Tuist bu bayraklardan hiçbirini otomatik olarak uygulamaz. Ayrıca Swift Package Manager, `-ObjC` bayrağının bir `.unsafeFlag` aracılığıyla dahil edildiğini kabul ettiğinden, çoğu paket gerektiğinde bunu varsayılan bağlama ayarlarının bir parçası olarak dahil edemez.

Objective-C bağımlılıklarının tüketicileri (veya dahili Objective-C hedefleri), tüketen hedeflerde `OTHER_LDFLAGS` ayarlayarak gerektiğinde `-ObjC` veya `-force_load` bayraklarını uygulamalıdır.

### Firebase ve diğer Google kütüphaneleri {#firebase-other-google-libraries}

Google’ın açık kaynak kütüphaneleri — güçlü olmalarına rağmen — Tuist içinde entegre edilmesi zor olabilir çünkü genellikle standart olmayan mimari ve derleme teknikleri kullanırlar.

Firebase ve Google’ın diğer Apple platformu kütüphanelerini entegre etmek için izlemeniz gerekebilecek birkaç ipucu şunlardır:

#### `-ObjC` öğesinin `OTHER_LDFLAGS` değerine {#ensure-objc-is-added-to-other_ldflags} eklendiğinden emin olun

Google'ın kütüphanelerinin çoğu Objective-C ile yazılmıştır. Bu nedenle, tüketen herhangi bir hedefin `OTHER_LDFLAGS` derleme ayarına `-ObjC` etiketini eklemesi gerekir. Bu, bir `.xcconfig` dosyasında ayarlanabilir veya Tuist manifestlerinizdeki hedef ayarlarında manuel olarak belirtilebilir. Örnek:

```swift
Target.target(
    ...
    settings: .settings(
        base: ["OTHER_LDFLAGS": "$(inherited) -ObjC"]
    )
    ...
)
```

Daha fazla ayrıntı için yukarıdaki [Objective-C Bağımlılıkları](#objectivec-dependencies) bölümüne bakın.

#### `FBLPromises` için ürün türünü dinamik çerçeveye ayarla {#set-the-product-type-for-fblpromises-to-dynamic-framework}

Bazı Google kütüphaneleri, Google'ın başka bir kütüphanesi olan `FBLPromises` bağımlılığına sahiptir. `FBLPromises` öğesinden bahseden ve şuna benzeyen bir çökmeyle karşılaşabilirsiniz:

```
NSInvalidArgumentException. Reason: -[FBLPromise HTTPBody]: unrecognized selector sent to instance 0x600000cb2640.
```

`Package.swift` dosyanızda `FBLPromises` ürün türünü açıkça `.framework` olarak ayarlamak sorunu çözmelidir:

```swift [Tuist/Package.swift]
// swift-tools-version: 5.10

import PackageDescription

#if TUIST
import ProjectDescription
import ProjectDescriptionHelpers

let packageSettings = PackageSettings(
    productTypes: [
        "FBLPromises": .framework,
    ]
)
#endif

let package = Package(
...
```

### The Composable Architecture {#the-composable-architecture}

[Burada](https://github.com/pointfreeco/swift-composable-architecture/discussions/1657#discussioncomment-4119184) ve [sorun giderme bölümünde](#troubleshooting) açıklandığı gibi, paketleri statik olarak bağlarken (Tuist'in varsayılan bağlama türü budur) `OTHER_LDFLAGS` derleme ayarını `$(inherited) -ObjC` olarak ayarlamanız gerekir. Alternatif olarak, paketin ürün türünü dinamik olacak şekilde geçersiz kılabilirsiniz. Statik bağlantı yaparken test ve uygulama hedefleri genellikle sorunsuz çalışır ancak SwiftUI önizlemeleri bozulur. Bu sorun, her şeyi dinamik olarak bağlayarak çözülebilir. Aşağıdaki örnekte [Sharing](https://github.com/pointfreeco/swift-sharing) de bir bağımlılık olarak eklenmiştir çünkü sıklıkla The Composable Architecture ile birlikte kullanılır ve kendi [yapılandırma tuzaklarına](https://github.com/pointfreeco/swift-sharing/issues/150#issuecomment-2797107032) sahiptir.

Aşağıdaki yapılandırma her şeyi dinamik olarak bağlar; böylece uygulama + test hedefleri ve SwiftUI önizlemeleri çalışır.

> [!TIP]
> **Statik mi dinamik mi**
>
> Dinamik bağlantı her zaman önerilmez. Daha fazla ayrıntı için [Statik mi dinamik mi](#static-or-dynamic) bölümüne bakın. Bu örnekte, basitlik adına tüm bağımlılıklar koşulsuz olarak dinamik şekilde bağlanmıştır.


```swift [Tuist/Package.swift]
// swift-tools-version: 6.0
import PackageDescription

#if TUIST
import enum ProjectDescription.Environment
import struct ProjectDescription.PackageSettings

let packageSettings = PackageSettings(
    productTypes: [
        "CasePaths": .framework,
        "CasePathsCore": .framework,
        "Clocks": .framework,
        "CombineSchedulers": .framework,
        "ComposableArchitecture": .framework,
        "ConcurrencyExtras": .framework,
        "CustomDump": .framework,
        "Dependencies": .framework,
        "DependenciesTestSupport": .framework,
        "IdentifiedCollections": .framework,
        "InternalCollectionsUtilities": .framework,
        "IssueReporting": .framework,
        "IssueReportingPackageSupport": .framework,
        "IssueReportingTestSupport": .framework,
        "OrderedCollections": .framework,
        "Perception": .framework,
        "PerceptionCore": .framework,
        "Sharing": .framework,
        "SnapshotTesting": .framework,
        "SwiftNavigation": .framework,
        "SwiftUINavigation": .framework,
        "UIKitNavigation": .framework,
        "XCTestDynamicOverlay": .framework
    ],
    targetSettings: [
        "ComposableArchitecture": .settings(base: [
            "OTHER_SWIFT_FLAGS": ["-module-alias", "Sharing=SwiftSharing"]
        ]),
        "Sharing": .settings(base: [
            "PRODUCT_NAME": "SwiftSharing",
            "OTHER_SWIFT_FLAGS": ["-module-alias", "Sharing=SwiftSharing"]
        ])
    ]
)
#endif
```

> [!WARNING]
> `import Sharing` yerine `import SwiftSharing` kullanmanız gerekecektir.


### Geçişli statik bağımlılıkların `.swiftmodule` üzerinden sızması {#transitive-static-dependencies-leaking-through-swiftmodule}

Dinamik bir çerçeve veya kütüphane, `import StaticSwiftModule` aracılığıyla statik olanlara bağımlı olduğunda, semboller dinamik çerçevenin veya kütüphanenin `.swiftmodule` dosyasına dahil edilir ve bu durum derlemenin <.localized_link href="https://forums.swift.org/t/compiling-a-dynamic-framework-with-a-statically-linked-library-creates-dependencies-in-swiftmodule-file/22708/1">başarısız olmasına neden olabilir</.localized_link>. Bunu önlemek için statik bağımlılığı <.localized_link href="https://github.com/swiftlang/swift-evolution/blob/main/proposals/0409-access-level-on-imports.md">`internal import`</.localized_link> kullanarak içe aktarmanız gerekir:

```swift
internal import StaticModule
```

> [!NOTE]
> İçe aktarmalarda erişim düzeyi Swift 6 ile eklendi. Swift'in daha eski sürümlerini kullanıyorsanız bunun yerine <.localized_link href="https://github.com/apple/swift/blob/main/docs/ReferenceGuides/UnderscoredAttributes.md#_implementationonly">`@_implementationOnly`</.localized_link> kullanmanız gerekir:


```swift
@_implementationOnly import StaticModule
```

## İlgili {#related}

[monday.com'un Tuist ile modüler proje grafiğini nasıl benimsediğini](https://tuist.dev/customers/monday) okuyun; en az bağımlılığı olan hedeflerden başlayın.
