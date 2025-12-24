---
{
  "title": "Migrate an Xcode project",
  "titleTemplate": ":title · Migrate · Adoption · Projects · Features · Guides · Tuist",
  "description": "Learn how to migrate an Xcode project to a Tuist project."
}
---
# Bir Xcode projesini taşıma {#migrate-an-xcode-project}

Tuist<LocalizedLink href="/guides/features/projects/adoption/new-project"> kullanarak yeni bir proje oluşturmadığınız sürece</LocalizedLink>, bu durumda
her şey otomatik olarak yapılandırılır, Xcode projelerinizi Tuist'in ilkellerini
kullanarak tanımlamanız gerekir. Bu sürecin ne kadar sıkıcı olduğu,
projelerinizin ne kadar karmaşık olduğuna bağlıdır.

Muhtemelen bildiğiniz gibi, Xcode projeleri zaman içinde dağınık ve karmaşık
hale gelebilir: dizin yapısıyla eşleşmeyen gruplar, hedefler arasında paylaşılan
dosyalar veya mevcut olmayan dosyalara işaret eden dosya referansları
(bazılarından bahsetmek gerekirse). Tüm bu birikmiş karmaşıklık, projeyi
güvenilir bir şekilde taşıyan bir komut sağlamamızı zorlaştırıyor.

Dahası, manuel geçiş projelerinizi temizlemek ve basitleştirmek için mükemmel
bir uygulamadır. Bunun için sadece projenizdeki geliştiriciler değil, onları
daha hızlı işleyen ve indeksleyen Xcode da minnettar olacaktır. Tuist'i tamamen
benimsediğinizde, projelerin tutarlı bir şekilde tanımlanmasını ve basit
kalmasını sağlayacaktır.

Bu işi kolaylaştırmak amacıyla, kullanıcılardan aldığımız geri bildirimlere
dayanarak size bazı yönergeler sunuyoruz.

## Proje iskelesi oluşturun {#create-project-scaffold}

Öncelikle aşağıdaki Tuist dosyaları ile projeniz için bir iskele oluşturun:

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
        // You can read more about dependencies here: https://docs.tuist.io/documentation/tuist/dependencies
    ]
)
```
<!-- -->
:::

`Project.swift` projenizi tanımlayacağınız manifesto dosyasıdır ve
`Package.swift` bağımlılıklarınızı tanımlayacağınız manifesto dosyasıdır. `
Tuist.swift` dosyası, projeniz için proje kapsamındaki Tuist ayarlarını
tanımlayabileceğiniz yerdir.

::: tip PROJECT NAME WITH -TUIST SUFFIX
<!-- -->
Mevcut Xcode projesiyle çakışmaları önlemek için, proje adına `-Tuist` son ekini
eklemenizi öneririz. Projenizi Tuist'e tam olarak geçirdikten sonra bunu
bırakabilirsiniz.
<!-- -->
:::

## Tuist projesini CI'da derleyin ve test edin {#build-and-test-the-tuist-project-in-ci}

Her değişikliğin geçişinin geçerli olduğundan emin olmak için, Tuist tarafından
manifesto dosyanızdan oluşturulan projeyi derlemek ve test etmek için sürekli
entegrasyonunuzu genişletmenizi öneririz:

```bash
tuist install
tuist generate
xcodebuild build {xcodebuild flags} # or tuist test
```

## Proje derleme ayarlarını `.xcconfig` dosyalarına çıkarın {#extract-the-project-build-settings-into-xcconfig-files}

Projeyi daha yalın hale getirmek ve taşımayı kolaylaştırmak için derleme
ayarlarını projeden bir `.xcconfig` dosyasına çıkarın. Projedeki derleme
ayarlarını bir `.xcconfig` dosyasına çıkarmak için aşağıdaki komutu
kullanabilirsiniz:


```bash
mkdir -p xcconfigs/
tuist migration settings-to-xcconfig -p MyApp.xcodeproj -x xcconfigs/MyApp-Project.xcconfig
```

Ardından `Project.swift` dosyanızı yeni oluşturduğunuz `.xcconfig` dosyasına
işaret edecek şekilde güncelleyin:

```swift
import ProjectDescription

let project = Project(
    name: "MyApp",
    settings: .settings(configurations: [
        .debug(name: "Debug", xcconfig: "./xcconfigs/MyApp-Project.xcconfig"), // [!code ++]
        .release(name: "Release", xcconfig: "./xcconfigs/MyApp-Project.xcconfig"), // [!code ++]
    ]),
    targets: [
        /** Targets will go here **/
    ]
)
```

Ardından, derleme ayarlarında yapılan değişikliklerin doğrudan `.xcconfig`
dosyalarında yapılmasını sağlamak için aşağıdaki komutu çalıştırmak üzere
sürekli entegrasyon işlem hattınızı genişletin:

```bash
tuist migration check-empty-settings -p Project.xcodeproj
```

## Paket bağımlılıklarını ayıklayın {#extract-package-dependencies}

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
        // You can read more about dependencies here: https://docs.tuist.io/documentation/tuist/dependencies
        .package(url: "https://github.com/onevcat/Kingfisher", .upToNextMajor(from: "7.12.0")) // [!code ++]
    ]
)
```

::: tip PRODUCT TYPES
<!-- -->
Belirli bir paket için ürün türünü `PackageSettings` yapısındaki `productTypes`
sözlüğüne ekleyerek geçersiz kılabilirsiniz. Tuist varsayılan olarak tüm
paketlerin statik çerçeveler olduğunu varsayar.
<!-- -->
:::


## Geçiş sırasını belirleyin {#determine-the-migration-order}

Hedefleri en çok bağımlı olandan en az bağımlı olana doğru taşımanızı öneririz.
Bir projenin hedeflerini bağımlılık sayısına göre sıralayarak listelemek için
aşağıdaki komutu kullanabilirsiniz:

```bash
tuist migration list-targets -p Project.xcodeproj
```

Hedefleri taşımaya listenin en üstünden başlayın, çünkü en çok bağlı olanlar
bunlardır.


## Hedefleri taşıma {#migrate-targets}

Hedefleri teker teker taşıyın. Birleştirmeden önce değişikliklerin gözden
geçirildiğinden ve test edildiğinden emin olmak için her hedef için bir çekme
isteği yapmanızı öneririz.

### Hedef derleme ayarlarını `.xcconfig` dosyalarına çıkarın {#extract-the-target-build-settings-into-xcconfig-files}

Proje derleme ayarlarında yaptığınız gibi, hedefi daha yalın ve taşıması daha
kolay hale getirmek için hedef derleme ayarlarını bir `.xcconfig` dosyasına
çıkarın. Hedeften derleme ayarlarını bir `.xcconfig` dosyasına çıkarmak için
aşağıdaki komutu kullanabilirsiniz:

```bash
tuist migration settings-to-xcconfig -p MyApp.xcodeproj -t TargetX -x xcconfigs/TargetX.xcconfig
```

### Hedefi `Project.swift` dosyasında tanımlayın {#define-the-target-in-the-projectswift-file}

Hedefi `Project.targets` adresinde tanımlayın:

```swift
import ProjectDescription

let project = Project(
    name: "MyApp",
    settings: .settings(configurations: [
        .debug(name: "Debug", xcconfig: "./xcconfigs/Project.xcconfig"),
        .release(name: "Release", xcconfig: "./xcconfigs/Project.xcconfig"),
    ]),
    targets: [
        .target( // [!code ++]
            name: "TargetX", // [!code ++]
            destinations: .iOS, // [!code ++]
            product: .framework, // [!code ++] // or .staticFramework, .staticLibrary...
            bundleId: "dev.tuist.targetX", // [!code ++]
            sources: ["Sources/TargetX/**"], // [!code ++]
            dependencies: [ // [!code ++]
                /** Dependencies go here **/ // [!code ++]
                /** .external(name: "Kingfisher") **/ // [!code ++]
                /** .target(name: "OtherProjectTarget") **/ // [!code ++]
            ], // [!code ++]
            settings: .settings(configurations: [ // [!code ++]
                .debug(name: "Debug", xcconfig: "./xcconfigs/TargetX.xcconfig"), // [!code ++]
                .debug(name: "Release", xcconfig: "./xcconfigs/TargetX.xcconfig"), // [!code ++]
            ]) // [!code ++]
        ), // [!code ++]
    ]
)
```

::: info TEST TARGETS
<!-- -->
Hedefin ilişkili bir test hedefi varsa, aynı adımları tekrarlayarak bunu
`Project.swift` dosyasında da tanımlamalısınız.
<!-- -->
:::

### Hedef geçişi doğrulayın {#validate-the-target-migration}

Projenin derlendiğinden emin olmak için `tuist generate` ardından `xcodebuild
build` ve testlerin geçtiğinden emin olmak için `tuist test` çalıştırın. Ek
olarak, değişikliklerin doğru olduğundan emin olmak için oluşturulan Xcode
projesini mevcut projeyle karşılaştırmak için
[xcdiff](https://github.com/bloomberg/xcdiff) kullanabilirsiniz.

### Tekrarla {#repeat}

Tüm hedefler tamamen taşınana kadar tekrarlayın. İşiniz bittiğinde, `tuist
generate` ve ardından `xcodebuild build` ve `tuist test` kullanarak projeyi
derlemek ve test etmek için CI ve CD boru hatlarınızı güncellemenizi öneririz.

## Sorun Giderme {#troubleshooting}

### Eksik dosyalar nedeniyle derleme hataları. {#compilation-errors-due-to-missing-files}

Xcode proje hedeflerinizle ilişkili dosyaların tümü hedefi temsil eden bir dosya
sistemi dizininde bulunmuyorsa, derlenmeyen bir projeyle karşılaşabilirsiniz.
Tuist ile projeyi oluşturduktan sonra dosya listesinin Xcode projesindeki dosya
listesiyle eşleştiğinden emin olun ve dosya yapısını hedef yapıyla hizalama
fırsatını değerlendirin.
