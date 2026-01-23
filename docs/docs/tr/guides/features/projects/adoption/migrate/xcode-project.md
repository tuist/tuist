---
{
  "title": "Migrate an Xcode project",
  "titleTemplate": ":title · Migrate · Adoption · Projects · Features · Guides · Tuist",
  "description": "Learn how to migrate an Xcode project to a Tuist project."
}
---
# Xcode projesini taşıma {#migrate-an-xcode-project}

Tuist kullanarak yeni bir proje oluşturmadığınız sürece, her şey otomatik olarak
yapılandırılır, Tuist'in temel öğelerini kullanarak Xcode projelerinizi
tanımlamanız gerekir. Bu işlemin ne kadar sıkıcı olduğu, projelerinizin
karmaşıklığına bağlıdır.

Muhtemelen bildiğiniz gibi, Xcode projeleri zamanla karmaşık ve dağınık hale
gelebilir: dizin yapısıyla uyuşmayan gruplar, hedefler arasında paylaşılan
dosyalar veya var olmayan dosyalara işaret eden dosya referansları (bunlardan
bazıları). Biriken tüm bu karmaşıklık, projeyi güvenilir bir şekilde taşıyacak
bir komut sunmamızı zorlaştırıyor.

Ayrıca, manuel geçiş, projelerinizi temizlemek ve basitleştirmek için mükemmel
bir egzersizdir. Projenizdeki geliştiriciler bunun için minnettar olacaklar,
aynı zamanda Xcode da projeleri daha hızlı işleyip indeksleyecektir. Tuist'i tam
olarak benimsediğinizde, projelerin tutarlı bir şekilde tanımlandığından ve
basit kaldığından emin olabilirsiniz.

Bu işi kolaylaştırmak amacıyla, kullanıcılardan aldığımız geri bildirimlere
dayanarak size bazı yönergeler sunuyoruz.

## Proje iskeleti oluşturun {#create-project-scaffold}

Öncelikle, aşağıdaki Tuist dosyalarıyla projeniz için bir iskelet oluşturun:

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

`Project.swift`, projenizi tanımlayacağınız manifest dosyasıdır ve
`Package.swift`, bağımlılıklarınızı tanımlayacağınız manifest dosyasıdır.
`Tuist.swift` dosyası, projeniz için proje kapsamındaki Tuist ayarlarını
tanımlayabileceğiniz dosyadır.

::: tip PROJECT NAME WITH -TUIST SUFFIX
<!-- -->
Mevcut Xcode projesiyle çakışmayı önlemek için, proje adına `-Tuist` sonekini
eklemenizi öneririz. Projenizi Tuist'e tamamen taşıdıktan sonra bu soneki
silebilirsiniz.
<!-- -->
:::

## CI'da Tuist projesini oluşturun ve test edin. {#build-and-test-the-tuist-project-in-ci}

Her değişikliğin geçerli bir şekilde taşınmasını sağlamak için, sürekli
entegrasyonunuzu genişleterek Tuist tarafından manifest dosyanızdan oluşturulan
projeyi derlemenizi ve test etmenizi öneririz:

```bash
tuist install
tuist generate
xcodebuild build {xcodebuild flags} # or tuist test
```

## Proje yapı ayarlarını `.xcconfig` dosyalarına çıkarın. {#extract-the-project-build-settings-into-xcconfig-files}

Projeyi daha yalın ve taşınması daha kolay hale getirmek için, proje ayarlarını
bir `.xcconfig` dosyasına çıkarın. Aşağıdaki komutu kullanarak proje ayarlarını
bir `.xcconfig` dosyasına çıkarabilirsiniz:


```bash
mkdir -p xcconfigs/
tuist migration settings-to-xcconfig -p MyApp.xcodeproj -x xcconfigs/MyApp-Project.xcconfig
```

Ardından, `Project.swift` dosyasını, az önce oluşturduğunuz `.xcconfig`
dosyasını gösterecek şekilde güncelleyin:

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

Ardından, sürekli entegrasyon ardışık düzeninizi genişleterek aşağıdaki komutu
çalıştırın ve yapı ayarlarında yapılan değişikliklerin doğrudan `.xcconfig`
dosyalarına yansıtıldığından emin olun:

```bash
tuist migration check-empty-settings -p Project.xcodeproj
```

## Paket bağımlılıklarını çıkarın {#extract-package-dependencies}

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
`ürün türlerini` sözlüğüne ekleyerek belirli bir paket için ürün türünü geçersiz
kılabilirsiniz. `PackageSettings` yapısı. Varsayılan olarak, Tuist tüm
paketlerin statik çerçeveler olduğunu varsayar.
<!-- -->
:::


## Geçiş sırasını belirleyin {#determine-the-migration-order}

Hedefleri en bağımlı olandan en az bağımlı olana doğru taşıma öneririz.
Aşağıdaki komutu kullanarak bir projenin hedeflerini bağımlılık sayısına göre
sıralayabilirsiniz:

```bash
tuist migration list-targets -p Project.xcodeproj
```

En çok ihtiyaç duyulan hedefler listesinin en üstünden başlayarak hedefleri
taşıma işlemine başlayın.


## Hedefleri taşıma {#migrate-targets}

Hedefleri tek tek taşıyın. Değişikliklerin birleştirilmeden önce gözden
geçirilip test edilmesini sağlamak için her hedef için bir çekme isteği
yapmanızı öneririz.

### Hedef yapı ayarlarını `.xcconfig` dosyalarına çıkarın. {#extract-the-target-build-settings-into-xcconfig-files}

Proje derleme ayarlarında yaptığınız gibi, hedef derleme ayarlarını bir
`.xcconfig` dosyasına çıkararak hedefi daha yalın ve taşınması daha kolay hale
getirin. Aşağıdaki komutu kullanarak derleme ayarlarını hedeften bir `.xcconfig`
dosyasına çıkarabilirsiniz:

```bash
tuist migration settings-to-xcconfig -p MyApp.xcodeproj -t TargetX -x xcconfigs/TargetX.xcconfig
```

### `'da hedefi tanımlayın. Project.swift` dosyası {#define-the-target-in-the-projectswift-file}

`'da hedefi tanımlayın. Project.targets`:

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

`komutunu çalıştırın. tuist generate` komutunu çalıştırın. Ardından `xcodebuild
build` komutunu çalıştırarak projenin derlendiğinden emin olun ve `tuist test`
komutunu çalıştırarak testlerin başarılı olduğundan emin olun. Ayrıca,
[xcdiff](https://github.com/bloomberg/xcdiff) komutunu kullanarak oluşturulan
Xcode projesini mevcut projeyle karşılaştırarak değişikliklerin doğru olduğundan
emin olabilirsiniz.

### Tekrarla {#repeat}

Tüm hedefler tamamen taşınana kadar bu işlemi tekrarlayın. İşlemi tamamladıktan
sonra, CI ve CD boru hatlarınızı güncelleyerek projeyi `tuist generate` komutunu
kullanarak derlemenizi ve test etmenizi öneririz. Ardından `xcodebuild build` ve
`tuist test` komutlarını kullanın.

## Sorun Giderme {#troubleshooting}

### Eksik dosyalar nedeniyle derleme hataları. {#compilation-errors-due-to-missing-files}

Xcode proje hedeflerinizle ilişkili dosyaların tümü, hedefi temsil eden bir
dosya sistemi dizininde bulunmuyorsa, derlenemeyen bir projeyle
karşılaşabilirsiniz. Tuist ile projeyi oluşturduktan sonra, dosyaların
listesinin Xcode projesindeki dosyaların listesiyle eşleştiğinden emin olun ve
bu fırsatı değerlendirerek dosya yapısını hedef yapıya uyarlayın.
