---
{
  "title": "Bir Xcode projesini taşıma",
  "titleTemplate": ":title · Taşıma · Benimseme · Projeler · Özellikler · Kılavuzlar · Tuist",
  "description": "Bir Xcode projesinin nasıl Tuist projesine taşınacağını öğrenin."
}
---
# Bir Xcode projesini taşıma {#migrate-an-xcode-project}

<.localized_link href="/guides/features/projects/adoption/new-project">Tuist kullanarak yeni bir proje oluşturmadığınız</.localized_link> sürece, bu durumda her şey otomatik olarak yapılandırılır, Xcode projelerinizi Tuist'in temel bileşenlerini kullanarak tanımlamanız gerekir. Bu sürecin ne kadar zahmetli olduğu, projelerinizin karmaşıklığına bağlıdır.

Muhtemelen bildiğiniz gibi, Xcode projeleri zamanla dağınık ve karmaşık hale gelebilir: dizin yapısıyla eşleşmeyen gruplar, hedefler arasında paylaşılan dosyalar veya var olmayan dosyalara işaret eden dosya referansları (bazı örnekler). Biriken bu karmaşıklık, projeleri güvenilir bir şekilde taşıyan bir komut sunmamızı zorlaştırıyor.

Dahası, manuel taşıma projelerinizi temizlemek ve basitleştirmek için mükemmel bir alıştırmadır. Buna sadece projenizdeki geliştiriciler değil, onları daha hızlı işleyip indeksleyen Xcode da minnettar olacaktır. Tuist'i tamamen benimsediğinizde, projelerin tutarlı bir şekilde tanımlandığını ve basit kaldığını sağlar.

Bu işi kolaylaştırmak amacıyla, kullanıcılardan aldığımız geri bildirimlere dayalı bazı yönergeler sunuyoruz.

## Proje iskeleti oluşturma {#create-project-scaffold}

İlk olarak, aşağıdaki Tuist dosyalarını kullanarak projeniz için bir iskelet oluşturun:

::: code-group

```js [Tuist.swift]
import ProjectDescription

let tuist = Tuist()
```

```js [Project.swift]
import ProjectDescription

let project = Project(
    name: "MyApp-Tuist",
    targets: [
        /** Targets will go here **/
    ]
)
```

```js [Tuist/Package.swift]
// swift-tools-version: 5.9
import PackageDescription

#if TUIST
    import ProjectDescription

    let packageSettings = PackageSettings(
        // Customize the product types for specific package product
        // Default is .staticFramework
        // productTypes: ["Alamofire": .framework,]
        productTypes: [:]
    )
#endif

let package = Package(
    name: "MyApp",
    dependencies: [
        // Add your own dependencies here:
        // .package(url: "https://github.com/Alamofire/Alamofire", from: "5.0.0"),
        // You can read more about dependencies here: https://tuist.dev/en/docs/guides/features/projects/dependencies
    ]
)
```
<!-- -->
:::

`Project.swift`, projenizi tanımlayacağınız manifest dosyasıdır ve `Package.swift`, bağımlılıklarınızı tanımlayacağınız manifest dosyasıdır. `Tuist.swift` dosyası, projeniz için proje kapsamındaki Tuist ayarlarını tanımlayabileceğiniz yerdir.

> [!TIP]
> **-Tuist sonekli proje adı**
>
> Mevcut Xcode projesiyle çakışmaları önlemek için, proje adına `-Tuist` sonekini eklemenizi öneririz. Projenizi Tuist'e tamamen taşıdığınızda bu soneki kaldırabilirsiniz.


## Tuist projesini CI'da derleme ve test etme {#build-and-test-the-tuist-project-in-ci}

Her değişikliğin taşınmasının geçerli olduğundan emin olmak için, sürekli entegrasyonunuzu genişleterek manifest dosyanızdan Tuist tarafından oluşturulan projeyi derlemeyi ve test etmeyi öneririz:

```bash
tuist install
tuist generate
xcodebuild build {xcodebuild flags} # or tuist test
```

## Proje derleme ayarlarını `.xcconfig` dosyalarına çıkarma {#extract-the-project-build-settings-into-xcconfig-files}

Projeyi daha yalın ve taşınması daha kolay hale getirmek için derleme ayarlarını projeden bir `.xcconfig` dosyasına çıkarın. Derleme ayarlarını projeden bir `.xcconfig` dosyasına çıkarmak için aşağıdaki komutu kullanabilirsiniz:


```bash
mkdir -p xcconfigs/
tuist migration settings-to-xcconfig -p MyApp.xcodeproj -x xcconfigs/MyApp-Project.xcconfig
```

Ardından, `Project.swift` dosyanızı az önce oluşturduğunuz `.xcconfig` dosyasını gösterecek şekilde güncelleyin:

```swift
import ProjectDescription

let project = Project(
    name: "MyApp",
    settings: .settings(configurations: [
        .debug(name: "Debug", xcconfig: "./xcconfigs/MyApp-Project.xcconfig"),
        .release(name: "Release", xcconfig: "./xcconfigs/MyApp-Project.xcconfig"),
    ]),
    targets: [
        /** Targets will go here **/
    ]
)
```

Ardından, derleme ayarlarına yapılan değişikliklerin doğrudan `.xcconfig` dosyalarına yapılmasını sağlamak için sürekli entegrasyon hattınızı aşağıdaki komutu çalıştıracak şekilde genişletin:

```bash
tuist migration check-empty-settings -p Project.xcodeproj
```

## Paket bağımlılıklarını çıkarma {#extract-package-dependencies}

Projenizin tüm bağımlılıklarını `Tuist/Package.swift` dosyasına çıkarın:

```swift
// swift-tools-version: 5.9
import PackageDescription

#if TUIST
    import ProjectDescription

    let packageSettings = PackageSettings(
        // Customize the product types for specific package product
        // Default is .staticFramework
        // productTypes: ["Alamofire": .framework,]
        productTypes: [:]
    )
#endif

let package = Package(
    name: "MyApp",
    dependencies: [
        // Add your own dependencies here:
        // .package(url: "https://github.com/Alamofire/Alamofire", from: "5.0.0"),
        // You can read more about dependencies here: https://tuist.dev/en/docs/guides/features/projects/dependencies
        .package(url: "https://github.com/onevcat/Kingfisher", .upToNextMajor(from: "7.12.0"))
    ]
)
```

> [!TIP]
> **Ürün türleri**
>
> Belirli bir paketin ürün türünü, `PackageSettings` yapısındaki `productTypes` sözlüğüne ekleyerek geçersiz kılabilirsiniz. Varsayılan olarak Tuist, tüm paketlerin statik çerçeveler olduğunu varsayar.


## Taşıma sırasını belirleme {#determine-the-migration-order}

Hedefleri, en çok bağımlı olunanlardan en az bağımlı olanlara doğru taşımanızı öneririz. Bir projenin hedeflerini bağımlılık sayısına göre sıralanmış olarak listelemek için aşağıdaki komutu kullanabilirsiniz:

```bash
tuist migration list-targets -p Project.xcodeproj
```

Listedeki en üstten başlayarak hedefleri taşıyın, çünkü bunlar en çok bağımlı olunanlardır.


## Hedefleri taşıma {#migrate-targets}

Hedefleri tek tek taşıyın. Değişikliklerin birleştirilmeden önce gözden geçirilip test edilmesini sağlamak için her hedef için bir pull request açmanızı öneririz.

### Hedef derleme ayarlarını `.xcconfig` dosyalarına çıkarma {#extract-the-target-build-settings-into-xcconfig-files}

Proje derleme ayarlarında yaptığınız gibi, hedefi daha yalın ve taşınması daha kolay hale getirmek için hedef derleme ayarlarını bir `.xcconfig` dosyasına çıkarın. Derleme ayarlarını hedeften bir `.xcconfig` dosyasına çıkarmak için aşağıdaki komutu kullanabilirsiniz:

```bash
tuist migration settings-to-xcconfig -p MyApp.xcodeproj -t TargetX -x xcconfigs/TargetX.xcconfig
```

### Hedefi `Project.swift` dosyasında tanımlama {#define-the-target-in-the-projectswift-file}

Hedefi `Project.targets` içinde tanımlayın:

```swift
import ProjectDescription

let project = Project(
    name: "MyApp",
    settings: .settings(configurations: [
        .debug(name: "Debug", xcconfig: "./xcconfigs/Project.xcconfig"),
        .release(name: "Release", xcconfig: "./xcconfigs/Project.xcconfig"),
    ]),
    targets: [
        .target(
            name: "TargetX",
            destinations: .iOS,
            product: .framework, // or .staticFramework, .staticLibrary...
            bundleId: "dev.tuist.targetX",
            sources: ["Sources/TargetX/**"],
            dependencies: [
                /** Dependencies go here **/
                /** .external(name: "Kingfisher") **/
                /** .target(name: "OtherProjectTarget") **/
            ],
            settings: .settings(configurations: [
                .debug(name: "Debug", xcconfig: "./xcconfigs/TargetX.xcconfig"),
                .release(name: "Release", xcconfig: "./xcconfigs/TargetX.xcconfig"),
            ])
        ),
    ]
)
```

> [!NOTE]
> **Test hedefleri**
>
> Hedefin ilişkili bir test hedefi varsa, aynı adımları tekrarlayarak bunu `Project.swift` dosyasında da tanımlamalısınız.


### Hedef taşınmasını doğrulama {#validate-the-target-migration}

Projenin derlendiğinden emin olmak için `tuist generate`'i ardından `xcodebuild build`'i çalıştırın ve testlerin geçtiğinden emin olmak için `tuist test`'i çalıştırın. Ek olarak, değişikliklerin doğru olduğundan emin olmak için oluşturulan Xcode projesini mevcut olanla karşılaştırmak üzere [xcdiff](https://github.com/bloomberg/xcdiff) kullanabilirsiniz.

### Tekrarlama {#repeat}

Tüm hedefler tamamen taşınana kadar tekrarlayın. İşiniz bittiğinde, projeyi `tuist generate`'i ardından `xcodebuild build` ve `tuist test`'ü kullanarak derlemek ve test etmek için CI ve CD hatlarınızı güncellemenizi öneririz.

## Sorun giderme {#troubleshooting}

### Eksik dosyalardan kaynaklanan derleme hataları. {#compilation-errors-due-to-missing-files}

Xcode proje hedeflerinizle ilişkili dosyaların tamamı hedefi temsil eden bir dosya sistemi dizininde bulunmuyorsa, derlenmeyen bir projeyle karşılaşabilirsiniz. Tuist ile projeyi oluşturduktan sonraki dosya listesinin Xcode projesindeki dosya listesiyle eşleştiğinden emin olun ve dosya yapısını hedef yapısıyla hizalama fırsatını değerlendirin.
