---
{
  "title": "Dependencies",
  "titleTemplate": ":title · Projects · Features · Guides · Tuist",
  "description": "Learn how to declare dependencies in your Tuist project."
}
---
# Bağımlılıklar {#dependencies}

Bir proje büyüdüğünde, kodu paylaşmak, sınırları tanımlamak ve derleme
sürelerini iyileştirmek için birden fazla hedefe bölmek yaygındır. Birden fazla
hedef, aralarında bir **bağımlılık grafiği** oluşturan bağımlılıkların
tanımlanması anlamına gelir ve bu bağımlılıklar harici bağımlılıkları da
içerebilir.

## XcodeProj kodlu grafikler {#xcodeprojcodified-graphs}

Xcode ve XcodeProj'un tasarımı nedeniyle, bir bağımlılık grafiğinin bakımı
sıkıcı ve hataya açık bir görev olabilir. Burada karşılaşabileceğiniz sorunlara
bazı örnekler verilmiştir:

- Xcode'un derleme sistemi, projenin tüm ürünlerini türetilmiş verilerde aynı
  dizine çıkardığı için, hedefler almamaları gereken ürünleri alabilir.
  Derlemeler, temiz derlemelerin daha yaygın olduğu CI'da veya daha sonra farklı
  bir yapılandırma kullanıldığında başarısız olabilir.
- Bir hedefin geçişli dinamik bağımlılıklarının `LD_RUNPATH_SEARCH_PATHS`
  derleme ayarının parçası olan dizinlerden herhangi birine kopyalanması
  gerekir. Eğer kopyalanmazlarsa, hedef çalışma zamanında onları bulamayacaktır.
  Çizge küçük olduğunda bunu düşünmek ve ayarlamak kolaydır, ancak çizge
  büyüdükçe bir sorun haline gelir.
- Bir hedef statik bir
  [XCFramework](https://developer.apple.com/documentation/xcode/creating-a-multi-platform-binary-framework-bundle)
  bağladığında, hedefin Xcode'un paketi işlemesi ve mevcut platform ve mimari
  için doğru ikili dosyayı çıkarması için ek bir derleme aşamasına ihtiyacı
  vardır. Bu derleme aşaması otomatik olarak eklenmez ve eklemeyi unutmak
  kolaydır.

Yukarıdakiler sadece birkaç örnek, ancak yıllar içinde karşılaştığımız daha pek
çok örnek var. Bir bağımlılık grafiğini korumak ve geçerliliğini sağlamak için
bir mühendis ekibine ihtiyacınız olduğunu düşünün. Ya da daha da kötüsü,
karmaşıklıkların derleme zamanında kontrol edemediğiniz veya
özelleştiremediğiniz kapalı kaynaklı bir derleme sistemi tarafından çözüldüğünü.
Tanıdık geliyor mu? Apple'ın Xcode ve XcodeProj ile benimsediği ve Swift paketi
Yöneticisi'nin miras aldığı yaklaşım budur.

Bağımlılık grafiğinin **açık** ve **statik** olması gerektiğine inanıyoruz çünkü
ancak o zaman **doğrulanabilir** ve **optimize edilebilir**. Tuist ile siz neyin
neye bağlı olduğunu açıklamaya odaklanın, gerisini biz hallederiz.
Karmaşıklıklar ve uygulama detayları sizden soyutlanır.

Aşağıdaki bölümlerde projenizde bağımlılıkları nasıl bildireceğinizi
öğreneceksiniz.

::: tip GRAPH VALIDATION
<!-- -->
Tuist, hiçbir döngü olmadığından ve tüm bağımlılıkların geçerli olduğundan emin
olmak için projeyi oluştururken grafiği doğrular. Bu sayede, herhangi bir ekip
bağımlılık grafiğini bozma endişesi olmadan geliştirmeye katılabilir.
<!-- -->
:::

## Yerel bağımlılıklar {#local-dependencies}

Hedefler aynı veya farklı projelerdeki diğer hedeflere ve ikili dosyalara
bağımlı olabilir. Bir `Hedefini` örneklendirirken, `bağımlılıkları` bağımsız
değişkenini aşağıdaki seçeneklerden herhangi biriyle iletebilirsiniz:

- `Hedef`: Aynı proje içinde bir hedef ile bağımlılık bildirir.
- `Proje`: Farklı bir projede hedefi olan bir bağımlılık bildirir.
- `Çerçeve`: İkili bir çerçeve ile bağımlılık bildirir.
- `Kütüphane`: İkili bir kütüphane ile bağımlılık bildirir.
- `XCFramework`: İkili XCFramework ile bir bağımlılık bildirir.
- `SDK`: Bir sistem SDK'sı ile bağımlılık bildirir.
- `XCTest`: XCTest ile bir bağımlılık bildirir.

::: info DEPENDENCY CONDITIONS
<!-- -->
Her bağımlılık türü, bağımlılığı platforma göre koşullu olarak bağlamak için bir
`condition` seçeneğini kabul eder. Varsayılan olarak, hedefin desteklediği tüm
platformlar için bağımlılığı bağlar.
<!-- -->
:::

## Dış bağımlılıklar {#external-dependencies}

Tuist ayrıca projenizde harici bağımlılıkları beyan etmenize de olanak tanır.

### Swift paketi {#swift-packages}

Swift paketi, projenizdeki bağımlılıkları bildirmek için önerdiğimiz yoldur.
Bunları Xcode'un varsayılan entegrasyon mekanizmasını kullanarak veya Tuist'in
XcodeProj tabanlı entegrasyonunu kullanarak entegre edebilirsiniz.

#### Tuist'in XcodeProj tabanlı entegrasyonu {#tuists-xcodeprojbased-integration}

Xcode'un varsayılan entegrasyonu en kullanışlı entegrasyon olmakla birlikte,
orta ve büyük ölçekli projeler için gerekli olan esneklik ve kontrolden
yoksundur. Bunun üstesinden gelmek için Tuist, XcodeProj'un hedeflerini
kullanarak Swift paketi'ni projenize entegre etmenize olanak tanıyan XcodeProj
tabanlı bir entegrasyon sunuyor. Bu sayede, entegrasyon üzerinde daha fazla
kontrol sahibi olmanızı sağlamakla kalmıyor, aynı zamanda
<LocalizedLink href="/guides/features/cache">caching</LocalizedLink> ve
<LocalizedLink href="/guides/features/test/selective-testing">selective test runs</LocalizedLink> gibi iş akışlarıyla uyumlu hale getirebiliyoruz.

XcodeProj'un entegrasyonu, yeni Swift paketi özelliklerini desteklemek veya daha
fazla paket yapılandırmasını işlemek için daha fazla zaman alabilir. Bununla
birlikte, Swift paketi ve XcodeProj hedefleri arasındaki eşleme mantığı açık
kaynaklıdır ve topluluk tarafından katkıda bulunulabilir. Bu, Xcode'un kapalı
kaynaklı olan ve Apple tarafından sürdürülen varsayılan entegrasyonunun
tersidir.

Dış bağımlılıkları eklemek için, `Tuist/` altında ya da projenin kökünde bir
`Package.swift` oluşturmanız gerekir.

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

::: tip PACKAGE SETTINGS
<!-- -->
Bir derleyici yönergesine sarılmış `PackageSettings` örneği, paketlerin nasıl
entegre edileceğini yapılandırmanıza olanak tanır. Örneğin, yukarıdaki örnekte
paketler için kullanılan varsayılan ürün türünü geçersiz kılmak için kullanılır.
Varsayılan olarak buna ihtiyacınız olmamalıdır.
<!-- -->
:::

> [!ÖNEMLİ] ÖZEL DERLEME YAPILANDIRMALARI Projeniz özel derleme yapılandırmaları
> kullanıyorsa (standart `Debug` ve `Release` dışındaki yapılandırmalar),
> bunları `baseSettings` kullanarak `PackageSettings` içinde belirtmeniz
> gerekir. Harici bağımlılıkların doğru şekilde derlenebilmesi için projenizin
> yapılandırmaları hakkında bilgi sahibi olması gerekir. Örneğin:
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
> Daha fazla ayrıntı için [#8345](https://github.com/tuist/tuist/issues/8345)
> bölümüne bakın.

`Package.swift` dosyası sadece dış bağımlılıkları bildirmek için bir arayüzdür,
başka bir şey değildir. Bu yüzden pakette herhangi bir hedef veya ürün
tanımlamazsınız. Bağımlılıkları tanımladıktan sonra, bağımlılıkları çözümlemek
ve `Tuist/Dependencies` dizinine çekmek için aşağıdaki komutu
çalıştırabilirsiniz:

```bash
tuist install
# Resolving and fetching dependencies. {#resolving-and-fetching-dependencies}
# Installing Swift Package Manager dependencies. {#installing-swift-package-manager-dependencies}
```

Fark etmiş olabileceğiniz gibi, bağımlılıkların çözümlenmesinin kendi komutu
olduğu [CocoaPods](https://cocoapods.org)' benzeri bir yaklaşım benimsiyoruz.
Bu, kullanıcılara bağımlılıkların ne zaman çözülmesini ve güncellenmesini
istedikleri konusunda kontrol sağlar ve projede Xcode'un açılmasına ve derlemeye
hazır olmasına izin verir. Bu, Apple'ın Swift paketi ile entegrasyonunun
sağladığı geliştirici deneyiminin proje büyüdükçe zaman içinde azaldığına
inandığımız bir alandır.

Daha sonra proje hedeflerinizden `TargetDependency.external` bağımlılık türünü
kullanarak bu bağımlılıklara başvurabilirsiniz:

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
                .external(name: "Alamofire"), // [!code ++]
            ]
        ),
    ]
)
```
<!-- -->
:::

::: info NO SCHEMES GENERATED FOR EXTERNAL PACKAGES
<!-- -->
**şemaları** şemalar listesini temiz tutmak için Swift paketi projeleri için
otomatik olarak oluşturulmaz. Bunları Xcode'un kullanıcı arayüzü aracılığıyla
oluşturabilirsiniz.
<!-- -->
:::

#### Xcode'un varsayılan entegrasyonu {#xcodes-default-integration}

Xcode'un varsayılan entegrasyon mekanizmasını kullanmak istiyorsanız, bir
projeyi başlatırken `paketleri` listesini iletebilirsiniz:

```swift
let project = Project(name: "MyProject", packages: [
    .remote(url: "https://github.com/krzyzanowskim/CryptoSwift", requirement: .exact("1.8.0"))
])
```

Ve sonra hedeflerinizden onlara referans verin:

```swift
let target = .target(name: "MyTarget", dependencies: [
    .package(product: "CryptoSwift", type: .runtime)
])
```

Swift Makroları ve Derleme Aracı Eklentileri için sırasıyla `.macro` ve
`.plugin` türlerini kullanmanız gerekir.

::: warning SPM Build Tool Plugins
<!-- -->
SPM derleme aracı eklentileri, proje bağımlılıklarınız için Tuist'in [XcodeProj
tabanlı entegrasyonunu](#tuist-s-xcodeproj-based-integration) kullanırken bile
[Xcode'un varsayılan entegrasyonu](#xcode-s-default-integration) mekanizması
kullanılarak bildirilmelidir.
<!-- -->
:::

Bir SPM derleme aracı eklentisinin pratik bir uygulaması, Xcode'un "Derleme
Aracı Eklentilerini Çalıştır" derleme aşaması sırasında kod tiftikleme
gerçekleştirmektir. Bir paket bildiriminde bu aşağıdaki gibi tanımlanır:

```swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Framework",
    products: [
        .library(name: "Framework", targets: ["Framework"]),
    ],
    dependencies: [
        .package(url: "https://github.com/SimplyDanny/SwiftLintPlugins", .upToNextMajor(from: "0.56.1")),
    ],
    targets: [
        .target(
            name: "Framework",
            plugins: [
                .plugin(name: "SwiftLint", package: "SwiftLintPlugin"),
            ]
        ),
    ]
)
```

Yapı aracı eklentisi bozulmadan bir Xcode projesi oluşturmak için, paketi proje
bildiriminin `packages` dizisinde bildirmeniz ve ardından bir hedefin
bağımlılıklarına `.plugin` türünde bir paket eklemeniz gerekir.

```swift
import ProjectDescription

let project = Project(
    name: "Framework",
    packages: [
        .remote(url: "https://github.com/SimplyDanny/SwiftLintPlugins", requirement: .upToNextMajor(from: "0.56.1")),
    ],
    targets: [
        .target(
            name: "Framework",
            dependencies: [
                .package(product: "SwiftLintBuildToolPlugin", type: .plugin),
            ]
        ),
    ]
)
```

### Kartaca {#carthage}

[Carthage](https://github.com/carthage/carthage) `frameworks` veya `xcframeworks`
çıktılarını verdiğinden, `Carthage/Build` dizinindeki bağımlılıkların çıktısını
almak için `carthage update` çalıştırabilir ve ardından hedefinizdeki
bağımlılığı bildirmek için `.framework` veya `.xcframework` target bağımlılık
türünü kullanabilirsiniz. Bunu, projeyi oluşturmadan önce çalıştırabileceğiniz
bir komut dosyasına sarabilirsiniz.

```bash
#!/usr/bin/env bash

carthage update
tuist generate
```

::: warning BUILD AND TEST
<!-- -->
Projenizi `xcodebuild build` ve `tuist test` aracılığıyla derler ve test
ederseniz, benzer şekilde, derlemeden veya test etmeden önce `carthage update`
komutunu çalıştırarak Carthage tarafından çözülen bağımlılıkların mevcut
olduğundan emin olmanız gerekir.
<!-- -->
:::

### CocoaPods {#cocoapods}

[CocoaPods](https://cocoapods.org) bağımlılıkları entegre etmek için bir Xcode
projesi bekler. Projeyi oluşturmak için Tuist'i kullanabilir ve ardından
projenizi ve Pods bağımlılıklarını içeren bir çalışma alanı oluşturarak
bağımlılıkları entegre etmek için `pod install` adresini çalıştırabilirsiniz.
Bunu, projeyi oluşturmadan önce çalıştırabileceğiniz bir komut dosyasına
sarabilirsiniz.

```bash
#!/usr/bin/env bash

tuist generate
pod install
```

::: warning
<!-- -->
CocoaPods bağımlılıkları, oluşturulmuş projele `xcodebuild` çalıştıran `build`
veya `test` gibi iş akışlarıyla uyumlu değildir. Ayrıca, parmak izi mantığı Pods
bağımlılıklarını hesaba katmadığı için ikili önbelleğe alma ve seçmeli test ile
de uyumsuzdurlar.
<!-- -->
:::

## Statik veya dinamik {#static-or-dynamic}

Çerçeveler ve kütüphaneler statik ya da dinamik olarak bağlanabilir **bu seçim
uygulama boyutu ve açılış zamanı gibi hususlar üzerinde önemli etkilere
sahiptir**. Önemine rağmen, bu karar genellikle fazla düşünülmeden verilir.

**genel kuralı**, hızlı önyükleme süreleri elde etmek için sürüm derlemelerinde
mümkün olduğunca çok şeyin statik olarak bağlanmasını ve hızlı yineleme süreleri
elde etmek için hata ayıklama derlemelerinde mümkün olduğunca çok şeyin dinamik
olarak bağlanmasını istemenizdir.

Bir proje grafiğinde statik ve dinamik bağlama arasında geçiş yapmanın zorluğu,
Xcode'da önemsiz olmamasıdır, çünkü bir değişiklik tüm grafik üzerinde basamaklı
etkiye sahiptir (örneğin, kütüphaneler kaynak içeremez, statik çerçevelerin
gömülmesi gerekmez). Apple, Swift paketi Yöneticisi'nin statik ve dinamik
bağlama arasında otomatik karar vermesi veya [Birleştirilebilir
Kütüphaneler](https://developer.apple.com/documentation/xcode/configuring-your-project-to-use-mergeable-libraries)
gibi derleme zamanı çözümleriyle sorunu çözmeye çalıştı. Ancak bu, derleme
grafiğine yeni dinamik değişkenler ekleyerek yeni belirsizlik kaynakları
yaratıyor ve Swift Önizlemeleri gibi derleme grafiğine dayanan bazı özelliklerin
güvenilmez hale gelmesine neden olabiliyor.

Neyse ki Tuist, statik ve dinamik arasında geçiş yapmakla ilişkili karmaşıklığı kavramsal olarak sıkıştırır ve bağlama türleri arasında standart olan <LocalizedLink href="/guides/features/projects/synthesized-files#bundle-accessors">bundle accessors</LocalizedLink> sentezler. <LocalizedLink href="/guides/features/projects/dynamic-configuration">Ortam değişkenleri aracılığıyla dinamik yapılandırmalarla</LocalizedLink> birlikte, çağırma sırasında bağlama türünü iletebilir ve hedeflerinizin ürün türünü ayarlamak için manifestlerinizdeki değeri kullanabilirsiniz.

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

Tuist'in <LocalizedLink href="/guides/features/projects/cost-of-convenience">maliyetleri nedeniyle örtük yapılandırma yoluyla varsayılan olarak kolaylık sağlamadığını</LocalizedLink> unutmayın. Bunun anlamı, ortaya çıkan ikili dosyaların doğru olmasını sağlamak için bağlama türünü ve [`-ObjC` bağlayıcı bayrağı](https://github.com/pointfreeco/swift-composable-architecture/discussions/1657#discussioncomment-4119184) gibi bazen gerekli olan ek derleme ayarlarını yapmanıza güvendiğimizdir. Bu nedenle, doğru kararları verebilmeniz için size genellikle dokümantasyon şeklinde kaynaklar sağlıyoruz.

::: tip EXAMPLE: THE COMPOSABLE ARCHITECTURE
<!-- -->
Birçok projenin entegre ettiği bir Swift paketi [The Composable
Architecture](https://github.com/pointfreeco/swift-composable-architecture).
Daha fazla ayrıntı için [bu bölüme](#the-composable-architecture) bakın.
<!-- -->
:::

### Senaryolar {#scenarios}

Bağlantıyı tamamen statik veya dinamik olarak ayarlamanın mümkün olmadığı veya
iyi bir fikir olmadığı bazı senaryolar vardır. Aşağıda, statik ve dinamik
bağlantıyı karıştırmanız gerekebilecek senaryoların kapsamlı olmayan bir listesi
bulunmaktadır:

- **Uzantıları olan uygulamalar:** Uygulamalar ve uzantılarının kod paylaşması
  gerektiğinden, bu hedefleri dinamik hale getirmeniz gerekebilir. Aksi
  takdirde, aynı kodu hem uygulamada hem de uzantıda çoğaltarak ikili boyutun
  artmasına neden olursunuz.
- **Önceden derlenmiş harici bağımlılıklar:** Bazen size statik veya dinamik
  önceden derlenmiş ikili dosyalar sağlanır. Statik ikililer dinamik olarak
  bağlanmak üzere dinamik çerçevelere veya kütüphanelere sarılabilir.

Grafikte değişiklik yaparken, Tuist grafiği analiz edecek ve bir "statik yan
etki" tespit ederse bir uyarı görüntüleyecektir. Bu uyarı, dinamik hedefler
aracılığıyla statik bir hedefe geçişli olarak bağlı olan bir hedefi statik
olarak bağlamaktan kaynaklanabilecek sorunları belirlemenize yardımcı olmayı
amaçlamaktadır. Bu yan etkiler genellikle artan ikili boyut veya en kötü
durumlarda çalışma zamanı çökmeleri olarak ortaya çıkar.

## Sorun Giderme {#troubleshooting}

### Objective-C Bağımlılıkları {#objectivec-dependencies}

Objective-C bağımlılıklarını entegre ederken, [Apple Technical Q&A
QA1490](https://developer.apple.com/library/archive/qa/qa1490/_index.html)'de
ayrıntılı olarak açıklandığı gibi çalışma zamanı çökmelerini önlemek için
tüketen hedefe belirli bayrakların eklenmesi gerekebilir.

Derleme sistemi ve Tuist'in bu bayrağın gerekli olup olmadığını anlamasının bir
yolu olmadığından ve bayrak potansiyel olarak istenmeyen yan etkilere sahip
olduğundan, Tuist bu bayrakların hiçbirini otomatik olarak uygulamayacaktır ve
Swift paketi Yöneticisi `-ObjC` adresinin bir `.unsafeFlag` aracılığıyla dahil
edildiğini düşündüğünden, çoğu paketi gerektiğinde varsayılan bağlama
ayarlarının bir parçası olarak bunu dahil edemez.

Objective-C bağımlılıklarının (veya dahili Objective-C hedeflerinin)
tüketicileri, tüketen hedeflerde `OTHER_LDFLAGS` ayarını yaparak gerektiğinde
`-ObjC` veya `-force_load` bayraklarını uygulamalıdır.

### Firebase ve Diğer Google Kütüphaneleri {#firebase-other-google-libraries}

Google'ın açık kaynak kütüphaneleri güçlü olmakla birlikte, oluşturulma
biçimlerinde genellikle standart olmayan mimari ve teknikler kullandıkları için
Tuist'e entegre edilmeleri zor olabilir.

Firebase ve Google'ın diğer Apple-platform kütüphanelerini entegre etmek için
takip edilmesi gerekebilecek birkaç ipucunu burada bulabilirsiniz:

#### `-ObjC` adresinin `OTHER_LDFLAGS adresine eklendiğinden emin olun` {#ensure-objc-is-added-to-other_ldflags}

Google'ın kütüphanelerinin çoğu Objective-C dilinde yazılmıştır. Bu nedenle,
tüketen herhangi bir hedefin `-ObjC` etiketini `OTHER_LDFLAGS` derleme ayarına
dahil etmesi gerekecektir. Bu, bir `.xcconfig` dosyasında ayarlanabilir veya
Tuist manifestlerinizdeki hedefin ayarlarında manuel olarak belirtilebilir. Bir
örnek:

```swift
Target.target(
    ...
    settings: .settings(
        base: ["OTHER_LDFLAGS": "$(inherited) -ObjC"]
    )
    ...
)
```

Daha fazla ayrıntı için yukarıdaki [Objective-C
Bağımlılıkları](#objective-c-dependencies) bölümüne bakın.

#### `FBLPromises` için ürün türünü dinamik çerçeveye ayarlayın {#set-the-product-type-for-fblpromises-to-dynamic-framework}

Bazı Google kütüphaneleri, Google'ın bir başka kütüphanesi olan `FBLPromises`'a
bağlıdır. Şuna benzer bir şekilde `FBLPromises` adresinden bahseden bir çökmeyle
karşılaşabilirsiniz:

```
NSInvalidArgumentException. Reason: -[FBLPromise HTTPBody]: unrecognized selector sent to instance 0x600000cb2640.
```

`FBLPromises` ürün türünü `.framework` olarak `Package.swift` dosyanızda açıkça
ayarlamanız sorunu çözecektir:

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

### Birleştirilebilir Mimari {#the-composable-architecture}

[Burada](https://github.com/pointfreeco/swift-composable-architecture/discussions/1657#discussioncomment-4119184) ve [sorun giderme bölümünde](#troubleshooting) açıklandığı gibi, paketleri
Tuist'in varsayılan bağlama türü olan statik olarak bağlarken `OTHER_LDFLAGS`
derleme ayarını `$(inherited) -ObjC` olarak ayarlamanız gerekir. Alternatif
olarak, paketin dinamik olması için ürün türünü geçersiz kılabilirsiniz. Statik
olarak bağlandığında, test ve uygulama hedefleri genellikle sorunsuz çalışır,
ancak SwiftUI önizlemeleri bozulur. Bu, her şeyi dinamik olarak bağlayarak
çözülebilir. Aşağıdaki örnekte
[Sharing](https://github.com/pointfreeco/swift-sharing) de bir bağımlılık olarak
eklenmiştir, çünkü genellikle The Composable Architecture ile birlikte
kullanılır ve kendi [yapılandırma
tuzakları](https://github.com/pointfreeco/swift-sharing/issues/150#issuecomment-2797107032)
vardır.

Aşağıdaki yapılandırma her şeyi dinamik olarak bağlayacaktır - böylece uygulama
+ test hedefleri ve SwiftUI önizlemeleri çalışır.

::: tip STATIC OR DYNAMIC
<!-- -->
Dinamik bağlama her zaman önerilmez. Daha fazla ayrıntı için [Statik veya
dinamik](#static-or-dynamic) bölümüne bakın. Bu örnekte, tüm bağımlılıklar
basitlik için koşulsuz olarak dinamik olarak bağlanmıştır.
<!-- -->
:::

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

::: warning
<!-- -->
`import Sharing` yerine `import SwiftSharing` yapmanız gerekecektir.
<!-- -->
:::

### `.swiftmodule aracılığıyla sızan geçişli statik bağımlılıklar` {#transitive-static-dependencies-leaking-through-swiftmodule}

Dinamik bir çerçeve veya kütüphane `import StaticSwiftModule` aracılığıyla
statik olanlara bağımlı olduğunda, semboller dinamik çerçeve veya kütüphanenin
`.swiftmodule` içine dahil edilir ve potansiyel olarak
<LocalizedLink href="https://forums.swift.org/t/compiling-a-dynamic-framework-with-a-statically-linked-library-creates-dependencies-in-swiftmodule-file/22708/1">derlemenin başarısız olmasına neden olur</LocalizedLink>. Bunu önlemek için, statik
bağımlılığı
<LocalizedLink href="https://github.com/swiftlang/swift-evolution/blob/main/proposals/0409-access-level-on-imports.md">`internal import`</LocalizedLink> kullanarak içe aktarmanız gerekir:

```swift
internal import StaticModule
```

::: info
<!-- -->
İçe aktarmalarda erişim seviyesi Swift 6'ya dahil edildi. Swift'in eski
sürümlerini kullanıyorsanız, bunun yerine
<LocalizedLink href="https://github.com/apple/swift/blob/main/docs/ReferenceGuides/UnderscoredAttributes.md#_implementationonly">`@_implementationOnly`</LocalizedLink>
kullanmanız gerekir:
<!-- -->
:::

```swift
@_implementationOnly import StaticModule
```
