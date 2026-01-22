---
{
  "title": "Dependencies",
  "titleTemplate": ":title · Projects · Features · Guides · Tuist",
  "description": "Learn how to declare dependencies in your Tuist project."
}
---
# Bağımlılıklar {#dependencies}

Bir proje büyüdüğünde, kodu paylaşmak, sınırları tanımlamak ve derleme
sürelerini iyileştirmek için projeyi birden fazla hedefe bölmek yaygın bir
uygulamadır. Birden fazla hedef, aralarında bağımlılıklar tanımlayarak
**bağımlılık grafiği** oluşturmak anlamına gelir. Bu grafik, harici
bağımlılıkları da içerebilir.

## XcodeProj kodlu grafikler {#xcodeprojcodified-graphs}

Xcode ve XcodeProj'un tasarımı nedeniyle, bağımlılık grafiğinin bakımı sıkıcı ve
hataya açık bir görev olabilir. Karşılaşabileceğiniz sorunlara ilişkin bazı
örnekler şunlardır:

- Xcode'un derleme sistemi, projenin tüm ürünlerini türetilmiş verilerdeki aynı
  dizine çıktılar, hedefler içermemesi gereken ürünleri içerebilir. Derlemeler,
  temiz derlemelerin daha yaygın olduğu CI'da veya daha sonra farklı bir
  yapılandırma kullanıldığında başarısız olabilir.
- Hedefin geçişli dinamik bağımlılıkları, `LD_RUNPATH_SEARCH_PATHS` derleme
  ayarının bir parçası olan dizinlerden herhangi birine kopyalanmalıdır. Aksi
  takdirde, hedef bunları çalışma zamanında bulamaz. Grafik küçük olduğunda bunu
  düşünmek ve ayarlamak kolaydır, ancak grafik büyüdükçe bu bir sorun haline
  gelir.
- Hedef, statik
  [XCFramework](https://developer.apple.com/documentation/xcode/creating-a-multi-platform-binary-framework-bundle)
  ile bağlantı kurduğunda, Xcode'un paketi işlemesi ve mevcut platform ve mimari
  için doğru ikili dosyayı çıkarması için hedefte ek bir derleme aşaması
  gerekir. Bu derleme aşaması otomatik olarak eklenmez ve eklenmesi kolayca
  unutulabilir.

Yukarıdakiler sadece birkaç örnektir, ancak yıllar boyunca karşılaştığımız daha
birçok örnek vardır. Bir mühendis ekibinden bağımlılık grafiğini korumalarını ve
geçerliliğini sağlamalarını istediğinizi düşünün. Daha da kötüsü, karmaşık
sorunların, kontrol edemediğiniz veya özelleştiremediğiniz kapalı kaynaklı bir
derleme sistemi tarafından derleme sırasında çözülmesi. Tanıdık geliyor mu? Bu,
Apple'ın Xcode ve XcodeProj ile benimsediği ve Swift paketi yöneticisinin miras
aldığı yaklaşımdır.

Bağımlılık grafiğinin **açık** ve **statik** olması gerektiğine inanıyoruz,
çünkü ancak bu şekilde **doğrulanabilir** ve **optimize edilebilir**. Tuist ile,
siz neyin neye bağlı olduğunu açıklamaya odaklanın, gerisini biz hallederiz.
Karmaşık ayrıntılar ve uygulama detayları sizden uzaklaştırılır.

Aşağıdaki bölümlerde, projenizde bağımlılıkları nasıl bildireceğinizi
öğreneceksiniz.

::: tip GRAPH VALIDATION
<!-- -->
Tuist, projeyi oluştururken grafiği doğrular ve döngü olmadığından ve tüm
bağımlılıkların geçerli olduğundan emin olur. Bu sayede, herhangi bir ekip,
grafiği bozma endişesi duymadan bağımlılık grafiğinin geliştirilmesine
katılabilir.
<!-- -->
:::

## Yerel bağımlılıklar {#local-dependencies}

Hedefler, aynı ve farklı projelerdeki diğer hedeflere ve ikili dosyalara bağlı
olabilir. `Target` örneğini oluştururken, `dependencies` argümanını aşağıdaki
seçeneklerden herhangi biriyle geçebilirsiniz:

- `Hedef`: Aynı proje içindeki bir hedefle bağımlılık bildirir.
- `Proje`: Farklı bir projedeki hedefle bir bağımlılık bildirir.
- `Çerçeve`: İkili bir çerçeve ile bağımlılık bildirir.
- `Kütüphane`: İkili kütüphane ile bir bağımlılık bildirir.
- `XCFramework`: İkili bir XCFramework ile bağımlılık bildirir.
- `SDK`: Sistem SDK'sı ile bir bağımlılık bildirir.
- `XCTest`: XCTest ile bir bağımlılık bildirir.

::: info DEPENDENCY CONDITIONS
<!-- -->
Her bağımlılık türü, platform temelinde bağımlılığı koşullu olarak bağlamak için
`koşul` seçeneğini kabul eder. Varsayılan olarak, hedef platformun desteklediği
tüm platformlar için bağımlılığı bağlar.
<!-- -->
:::

## Dış bağımlılıklar {#external-dependencies}

Tuist ayrıca projenizde harici bağımlılıkları beyan etmenize de olanak tanır.

### Swift paketi {#swift-packages}

Swift paketi, projenizde bağımlılıkları bildirmek için önerdiğimiz yöntemdir.
Bunları Xcode'un varsayılan entegrasyon mekanizmasını veya Tuist'in XcodeProj
tabanlı entegrasyonunu kullanarak entegre edebilirsiniz.

#### Tuist'in XcodeProj tabanlı entegrasyonu {#tuists-xcodeprojbased-integration}

Xcode'un varsayılan entegrasyonu en kullanışlı olanı olmakla birlikte, orta ve
büyük ölçekli projeler için gerekli olan esneklik ve kontrolü sağlamamaktadır.
Bu sorunu aşmak için Tuist, XcodeProj hedeflerini kullanarak Swift paketlerini
projenize entegre etmenizi sağlayan XcodeProj tabanlı bir entegrasyon
sunmaktadır. Bu sayede, entegrasyon üzerinde daha fazla kontrol sahibi olmanızı
sağlamakla kalmaz, aynı zamanda
<LocalizedLink href="/guides/features/cache">önbellekleme</LocalizedLink> ve
<LocalizedLink href="/guides/features/test/selective-testing">Seçmeli test
çalıştırmaları</LocalizedLink> gibi iş akışlarıyla da uyumlu hale getiririz.

XcodeProj entegrasyonunun yeni Swift paketi özelliklerini desteklemesi veya daha
fazla paket yapılandırmasını işlemesi daha fazla zaman alabilir. Ancak, Swift
paketleri ve XcodeProj hedefleri arasındaki eşleme mantığı açık kaynaklıdır ve
topluluk tarafından katkıda bulunulabilir. Bu, kapalı kaynaklı ve Apple
tarafından yönetilen Xcode'un varsayılan entegrasyonunun aksine bir durumdur.

Harici bağımlılıklar eklemek için, `Package.swift` dosyasını `Tuist/` altında
veya projenin kök dizininde oluşturmanız gerekir.

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
`Paket Ayarları Derleyici yönergesi ile sarılmış` örneği, paketlerin nasıl
entegre edileceğini yapılandırmanıza olanak tanır. Örneğin, yukarıdaki örnekte
paketler için kullanılan varsayılan ürün türünü geçersiz kılmak için kullanılır.
Varsayılan olarak, buna ihtiyacınız olmamalıdır.
<!-- -->
:::

> [!ÖNEMLİ] ÖZEL DERLEME YAPILANDIRMALARI Projeniz özel derleme yapılandırmaları
> kullanıyorsa ( `Debug` ve `Release` standart yapılandırmaları dışındaki
> yapılandırmalar), bunları `PackageSettings` kullanarak `baseSettings`
> belirtmelisiniz. Harici bağımlılıklar, projenizin yapılandırmalarını doğru bir
> şekilde derlemek için bilmelidir. Örneğin:
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
> adresine bakın.

`Package.swift` dosyası, harici bağımlılıkları beyan etmek için kullanılan bir
arayüzdür, başka bir şey değildir. Bu nedenle, pakette herhangi bir hedef veya
ürün tanımlamazsınız. Bağımlılıkları tanımladıktan sonra, aşağıdaki komutu
çalıştırarak bağımlılıkları çözebilir ve `Tuist/Dependencies` dizinine
çekebilirsiniz:

```bash
tuist install
# Resolving and fetching dependencies. {#resolving-and-fetching-dependencies}
# Installing Swift Package Manager dependencies. {#installing-swift-package-manager-dependencies}
```

Fark etmiş olabileceğiniz gibi, bağımlılıkların çözülmesinin kendi komutu olduğu
[CocoaPods](https://cocoapods.org)'e benzer bir yaklaşım benimsiyoruz. Bu,
kullanıcılara bağımlılıkların ne zaman çözülüp güncelleneceğini kontrol etme
imkanı verir ve Xcode'u projede açıp derlemeye hazır hale getirir. Bu, Apple'ın
Swift paketi ile entegrasyonunun sağladığı geliştirici deneyiminin, proje
büyüdükçe zamanla bozulduğuna inandığımız bir alandır.

Proje hedeflerinizden, `TargetDependency.external` bağımlılık türünü kullanarak
bu bağımlılıklara başvurabilirsiniz:

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
**şemaları**, şema listesini temiz tutmak için Swift paketi projeleri için
otomatik olarak oluşturulmaz. Bunları Xcode'un kullanıcı arayüzü üzerinden
oluşturabilirsiniz.
<!-- -->
:::

#### Xcode'un varsayılan entegrasyonu {#xcodes-default-integration}

Xcode'un varsayılan entegrasyon mekanizmasını kullanmak istiyorsanız, bir
projeyi oluştururken `paketleri` listesini geçebilirsiniz:

```swift
let project = Project(name: "MyProject", packages: [
    .remote(url: "https://github.com/krzyzanowskim/CryptoSwift", requirement: .exact("1.8.0"))
])
```

Ve sonra hedeflerinizden bunlara referans verin:

```swift
let target = .target(name: "MyTarget", dependencies: [
    .package(product: "CryptoSwift", type: .runtime)
])
```

Swift Makroları ve Derleme Aracı Eklentileri için sırasıyla `.macro` ve
`.plugin` türlerini kullanmanız gerekir.

::: warning SPM Build Tool Plugins
<!-- -->
SPM derleme aracı eklentileri, projenizin bağımlılıkları için Tuist'in
[XcodeProj tabanlı entegrasyonu](#tuist-s-xcodeproj-based-integration)
kullanıldığında bile [Xcode'un varsayılan
entegrasyonu](#xcode-s-default-integration) mekanizması kullanılarak
bildirilmelidir.
<!-- -->
:::

SPM derleme aracı eklentisinin pratik bir uygulaması, Xcode'un "Derleme Aracı
Eklentilerini Çalıştır" derleme aşamasında kod linting işlemini
gerçekleştirmektir. Paket manifestosunda bu, aşağıdaki gibi tanımlanmıştır:

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

Derleme aracı eklentisi bozulmadan bir Xcode projesi oluşturmak için, proje
manifestosunun `paketleri` dizisinde paketi beyan etmeniz ve ardından bir
hedefin bağımlılıklarına `.plugin` türünde bir paket eklemeniz gerekir.

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

[Carthage](https://github.com/carthage/carthage) `frameworks` veya
`xcframeworks` çıktısını verdiği için, `carthage update` komutunu çalıştırarak
`Carthage/Build` dizininde bağımlılıkları çıktı alabilir ve ardından
`.framework` veya `.xcframework` hedef bağımlılık türünü kullanarak
hedefinizdeki bağımlılığı bildirebilirsiniz. Bunu, projeyi oluşturmadan önce
çalıştırabileceğiniz bir komut dosyasına ekleyebilirsiniz.

```bash
#!/usr/bin/env bash

carthage update
tuist generate
```

::: warning BUILD AND TEST
<!-- -->
Projenizi `xcodebuild build` ve `tuist test` ile oluşturup test ediyorsanız,
benzer şekilde, oluşturma veya test etmeden önce `carthage update` komutunu
çalıştırarak Carthage tarafından çözülen bağımlılıkların mevcut olduğundan emin
olmanız gerekir.
<!-- -->
:::

### CocoaPods {#cocoapods}

[CocoaPods](https://cocoapods.org), bağımlılıkları entegre etmek için bir Xcode
projesi gerektirir. Tuist'i kullanarak projeyi oluşturabilir ve ardından `pod
install` komutunu çalıştırarak projenizi ve Pods bağımlılıklarını içeren bir
çalışma alanı oluşturarak bağımlılıkları entegre edebilirsiniz. Bunu, projeyi
oluşturmadan önce çalıştırabileceğiniz bir komut dosyasına ekleyebilirsiniz.

```bash
#!/usr/bin/env bash

tuist generate
pod install
```

::: warning
<!-- -->
CocoaPods bağımlılıkları, oluşturulmuş projeden hemen sonra `xcodebuild`
komutunu çalıştıran `build` veya `test` gibi iş akışlarıyla uyumlu değildir.
Ayrıca, parmak izi mantığı Pods bağımlılıklarını hesaba katmadığından, ikili
önbellekleme ve seçmeli testlerle de uyumsuzdur.
<!-- -->
:::

## Statik veya dinamik {#static-or-dynamic}

Çerçeveler ve kütüphaneler statik veya dinamik olarak bağlanabilir, **bu seçim,
uygulama boyutu ve başlatma süresi gibi hususlar açısından önemli sonuçlar
doğurur**. Önemine rağmen, bu karar genellikle fazla düşünülmeden verilir.

**'ın genel kuralı**, hızlı önyükleme süreleri elde etmek için sürüm
derlemelerinde mümkün olduğunca çok şeyin statik olarak bağlanmasını ve hızlı
yineleme süreleri elde etmek için hata ayıklama derlemelerinde mümkün olduğunca
çok şeyin dinamik olarak bağlanmasını istemenizdir.

Proje grafiğinde statik ve dinamik bağlantı arasında geçiş yapmanın zorluğu,
Xcode'da bu işlemin basit olmamasıdır, çünkü bir değişiklik tüm grafik üzerinde
zincirleme etki yaratır (örneğin, kütüphaneler kaynak içeremez, statik
çerçevelerin gömülmesine gerek yoktur). Apple, Swift paketi'nin statik ve
dinamik bağlantılar arasında otomatik karar verme özelliği veya
[Birleştirilebilir
Kütüphaneler](https://developer.apple.com/documentation/xcode/configuring-your-project-to-use-mergeable-libraries)
gibi derleme zamanı çözümleriyle bu sorunu çözmeye çalıştı. Ancak bu, derleme
grafiğine yeni dinamik değişkenler ekleyerek yeni belirsizlik kaynakları yaratır
ve derleme grafiğine dayanan Swift Previews gibi bazı özelliklerin
güvenilirliğini azaltabilir.

Neyse ki Tuist, statik ve dinamik arasında geçiş yapmanın karmaşıklığını
kavramsal olarak sıkıştırır ve bağlantı türleri arasında standart olan
<LocalizedLink href="/guides/features/projects/synthesized-files#bundle-accessors">bundle
accessors</LocalizedLink>'yi sentezler.
<LocalizedLink href="/guides/features/projects/dynamic-configuration">dynamic
configurations via environment variables</LocalizedLink> ile birlikte, çağırma
sırasında bağlantı türünü aktarabilir ve manifestolarınızdaki değeri kullanarak
hedeflerinizin ürün türünü ayarlayabilirsiniz.

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

Tuist <LocalizedLink href="/guides/features/projects/cost-of-convenience">,
maliyetleri nedeniyle</LocalizedLink> örtük yapılandırma yoluyla varsayılan
olarak kolaylık sağlamaz. Bunun anlamı, sonuçta ortaya çıkan ikili dosyaların
doğru olmasını sağlamak için bağlantı türünü ve bazen gerekli olan [`-ObjC`
bağlantı
bayrağı](https://github.com/pointfreeco/swift-composable-architecture/discussions/1657#discussioncomment-4119184)
gibi ek derleme ayarlarını sizin belirlemenize güveniyoruz. Bu nedenle, doğru
kararları vermeniz için size genellikle belgeler şeklinde kaynaklar sunmayı
tercih ediyoruz.

::: tip EXAMPLE: THE COMPOSABLE ARCHITECTURE
<!-- -->
Birçok projenin entegre ettiği bir Swift paketi [The Composable
Architecture](https://github.com/pointfreeco/swift-composable-architecture)'dir.
Daha fazla ayrıntı için [bu bölüme](#the-composable-architecture) bakın.
<!-- -->
:::

### Senaryolar {#scenarios}

Bağlantıyı tamamen statik veya dinamik olarak ayarlamanın mümkün olmadığı veya
iyi bir fikir olmadığı bazı senaryolar vardır. Aşağıda, statik ve dinamik
bağlantıları karıştırmanız gerekebileceği senaryoların kapsamlı olmayan bir
listesi bulunmaktadır:

- **Uzantıları olan uygulamalar:** Uygulamalar ve uzantıları kodu paylaşmak
  zorunda olduğundan, bu hedefleri dinamik hale getirmeniz gerekebilir. Aksi
  takdirde, uygulama ve uzantıda aynı kodun kopyalanmasıyla sonuçlanır ve ikili
  dosya boyutu artar.
- **Önceden derlenmiş harici bağımlılıklar:** Bazen statik veya dinamik önceden
  derlenmiş ikili dosyalar sağlanır. Statik ikili dosyalar, dinamik olarak
  bağlanmak üzere dinamik çerçeveler veya kitaplıklar içine alınabilir.

Grafikte değişiklik yaparken, Tuist bunu analiz eder ve "statik yan etki" tespit
ederse bir uyarı görüntüler. Bu uyarı, dinamik hedefler aracılığıyla statik bir
hedefe geçişli olarak bağlı olan bir hedefi statik olarak bağlamaktan
kaynaklanabilecek sorunları belirlemenize yardımcı olmak içindir. Bu yan etkiler
genellikle artan ikili boyut veya en kötü durumda çalışma zamanı çökmeleri
şeklinde ortaya çıkar.

## Sorun Giderme {#troubleshooting}

### Objective-C Bağımlılıkları {#objectivec-dependencies}

Objective-C bağımlılıklarını entegre ederken, [Apple Teknik Soru-Cevap
QA1490](https://developer.apple.com/library/archive/qa/qa1490/_index.html)
bölümünde ayrıntılı olarak açıklandığı gibi, çalışma zamanı çökmelerini önlemek
için tüketen hedefte belirli bayrakların eklenmesi gerekebilir.

Derleme sistemi ve Tuist, bayrağın gerekli olup olmadığını anlamanın bir yolu
olmadığı ve bayrağın potansiyel olarak istenmeyen yan etkileri olduğu için,
Tuist bu bayrakların hiçbirini otomatik olarak uygulamaz. Ayrıca Swift paketi,
`-ObjC` 'yi `.unsafeFlag` aracılığıyla dahil edilmiş olarak kabul ettiğinden,
çoğu paket gerektiğinde bunu varsayılan bağlantı ayarlarının bir parçası olarak
dahil edemez.

Objective-C bağımlılıklarının (veya dahili Objective-C hedeflerinin)
kullanıcıları, gerektiğinde `-ObjC` veya `-force_load` bayraklarını, tüketen
hedeflerde `OTHER_LDFLAGS` ayarını yaparak uygulamalıdır.

### Firebase ve Diğer Google Kütüphaneleri {#firebase-other-google-libraries}

Google'ın açık kaynak kütüphaneleri, güçlü olmalarına rağmen, genellikle
standart olmayan mimari ve teknikler kullanarak oluşturuldukları için Tuist'e
entegre edilmesi zor olabilir.

Firebase ve Google'ın diğer Apple platformu kitaplıklarını entegre etmek için
izlemeniz gereken birkaç ipucu:

#### `-ObjC` 'nin `OTHER_LDFLAGS'a eklendiğinden emin olun.` {#ensure-objc-is-added-to-other_ldflags}

Google'ın kitaplıklarının çoğu Objective-C ile yazılmıştır. Bu nedenle, herhangi
bir tüketen hedef, `-ObjC` etiketini `OTHER_LDFLAGS` yapı ayarına eklemelidir.
Bu, `.xcconfig` dosyasında ayarlanabilir veya Tuist manifestolarındaki hedef
ayarlarında manuel olarak belirtilebilir. Örnek:

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

#### `FBLPromises` için ürün türünü dinamik çerçeve olarak ayarlayın. {#set-the-product-type-for-fblpromises-to-dynamic-framework}

Bazı Google kitaplıkları, Google'ın başka bir kitaplığı olan `FBLPromises`'e
bağlıdır. `FBLPromises`'i belirten ve aşağıdaki gibi görünen bir çökmeyle
karşılaşabilirsiniz:

```
NSInvalidArgumentException. Reason: -[FBLPromise HTTPBody]: unrecognized selector sent to instance 0x600000cb2640.
```

`Package.swift` dosyanızda `FBLPromises` ürün türünü `.framework` olarak açıkça
ayarlamak sorunu çözmelidir:

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

[Burada](https://github.com/pointfreeco/swift-composable-architecture/discussions/1657#discussioncomment-4119184)
ve [sorun giderme bölümünde](#troubleshooting) açıklandığı gibi, paketleri
statik olarak bağlarken (Tuist'in varsayılan bağlama türü), `OTHER_LDFLAGS`
derleme ayarını `$(inherited) -ObjC` olarak ayarlamanız gerekir. Alternatif
olarak, paketin ürün türünü dinamik olarak geçersiz kılabilirsiniz. Statik
olarak bağlanırken, test ve uygulama hedefleri genellikle sorunsuz çalışır,
ancak SwiftUI önizlemeleri bozulur. Bu, her şeyi dinamik olarak bağlayarak
çözülebilir. Aşağıdaki örnekte
[Paylaşım](https://github.com/pointfreeco/swift-sharing) de bir bağımlılık
olarak eklenmiştir, çünkü genellikle The Composable Architecture ile birlikte
kullanılır ve kendi [yapılandırma
tuzakları](https://github.com/pointfreeco/swift-sharing/issues/150#issuecomment-2797107032)
vardır.

Aşağıdaki yapılandırma her şeyi dinamik olarak bağlayacaktır - böylece uygulama
+ test hedefleri ve SwiftUI önizlemeleri çalışacaktır.

::: tip STATIC OR DYNAMIC
<!-- -->
Dinamik bağlama her zaman önerilmez. Daha fazla ayrıntı için [Statik veya
dinamik](#static-or-dynamic) bölümüne bakın. Bu örnekte, basitlik için tüm
bağımlılıklar koşulsuz olarak dinamik olarak bağlanmıştır.
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
`import Sharing` yerine, `import SwiftSharing` yazmanız gerekir.
<!-- -->
:::

### `.swiftmodule aracılığıyla sızan geçişli statik bağımlılıklar` {#transitive-static-dependencies-leaking-through-swiftmodule}

Dinamik bir çerçeve veya kütüphane, `import StaticSwiftModule` yoluyla statik
çerçeve veya kütüphanelere bağımlıysa, semboller dinamik çerçeve veya
kütüphanenin `.swiftmodule` dosyasına dahil edilir ve bu da
<LocalizedLink href="https://forums.swift.org/t/compiling-a-dynamic-framework-with-a-statically-linked-library-creates-dependencies-in-swiftmodule-file/22708/1">derleme
hatasına neden olabilir</LocalizedLink>. Bunu önlemek için,
<LocalizedLink href="https://github.com/swiftlang/swift-evolution/blob/main/proposals/0409-access-level-on-imports.md">`internal
import`</LocalizedLink> kullanarak statik bağımlılığı içe aktarmanız gerekir:

```swift
internal import StaticModule
```

::: info
<!-- -->
İçe aktarmalarda erişim düzeyi Swift 6'ya dahil edildi. Swift'in eski
sürümlerini kullanıyorsanız, bunun yerine
<LocalizedLink href="https://github.com/apple/swift/blob/main/docs/ReferenceGuides/UnderscoredAttributes.md#_implementationonly">`@_implementationOnly`</LocalizedLink>
kullanmanız gerekir:
<!-- -->
:::

```swift
@_implementationOnly import StaticModule
```
