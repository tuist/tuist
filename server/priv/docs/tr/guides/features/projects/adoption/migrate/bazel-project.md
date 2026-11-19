---
{
  "title": "Bazel projesini taşıma",
  "titleTemplate": ":title · Taşıma · Benimseme · Projeler · Özellikler · Kılavuzlar · Tuist",
  "description": "Projelerinizi Bazel'den Tuist'e nasıl taşıyacağınızı öğrenin."
}
---
# Bir Bazel projesini taşıma {#migrate-a-bazel-project}

[Bazel](https://bazel.build), Google'ın 2015 yılında açık kaynak hale getirdiği bir derleme sistemidir. Her ölçekteki yazılımı hızlı ve güvenilir bir şekilde derlemenize ve test etmenize olanak tanıyan güçlü bir araçtır. [Spotify](https://engineering.atspotify.com/2023/10/switching-build-systems-seamlessly/), [Tinder](https://medium.com/tinder/bazel-hermetic-toolchain-and-tooling-migration-c244dc0d3ae) veya [Lyft](https://semaphoreci.com/blog/keith-smiley-bazel) gibi bazı büyük kuruluşlar bunu kullanır; ancak, teknolojiyi öğrenmek gibi başlangıçta ve Xcode güncellemelerini takip etmek gibi sürekli yatırım gerektirir. Bu durum, bunu çapraz bir konu olarak ele alan bazı kuruluşlar için işe yarasa da, ürün geliştirmeye odaklanmak isteyen diğerleri için en uygun çözüm olmayabilir. Örneğin, iOS platform ekibi Bazel'i tanıtan ve ardından bu çabayı yöneten mühendisler şirketten ayrılınca onu bırakmak zorunda kalan kuruluşlar gördük. Apple'ın Xcode ile derleme sistemi arasındaki sıkı bağlantı konusundaki duruşu, Bazel projelerinin zaman içinde bakımını zorlaştıran başka bir faktördür.

> [!TIP]
> **Tuist'in benzersizliği zarafetinde yatar**
>
> Xcode ve Xcode projeleriyle savaşmak yerine Tuist onu kucaklar. Aynı kavramlar (örneğin hedefler, şemalar, derleme ayarları), tanıdık bir dil (yani Swift) ve projelerin bakımını ve ölçeklendirilmesini herkesin işi haline getiren, sadece iOS platform ekibinin değil, basit ve keyifli bir deneyim sunar.


## Kurallar {#rules}

Bazel, yazılımın nasıl derleneceğini ve test edileceğini tanımlamak için kuralları kullanır. Kurallar, Python benzeri bir dil olan [Starlark](https://github.com/bazelbuild/starlark) ile yazılır. Tuist, yapılandırma dili olarak Swift'i kullanır ve bu, geliştiricilere Xcode'un otomatik tamamlama, tür denetimi ve doğrulama özelliklerini kullanma kolaylığı sağlar. Örneğin, aşağıdaki kural Bazel'de bir Swift kitaplığının nasıl derleneceğini açıklar:

::: code-group
```txt [BUILD (Bazel)]
swift_library(
    name = "MyLibrary.library",
    srcs = glob(["**/*.swift"]),
    module_name = "MyLibrary"
)
```

```swift [Project.swift (Tuist)]
let project = Project(
    // ...
    targets: [
        .target(
            name: "MyLibrary",
            destinations: .iOS,
            product: .staticLibrary,
            bundleId: "dev.tuist.MyLibrary",
            sources: ["**/*.swift"]
        )
    ]
)
```
<!-- -->
:::

İşte başka bir örnek, ancak Bazel ve Tuist'te birim testlerinin nasıl tanımlandığını karşılaştırıyor:

::: code-group
```txt [BUILD (Bazel)]
ios_unit_test(
    name = "MyLibraryTests",
    bundle_id = "dev.tuist.MyLibraryTests",
    minimum_os_version = "16.0",
    test_host = "//MyApp:MyLibrary",
    deps = [":MyLibraryTests.library"],
)

```
```swift [Project.swift (Tuist)]
let project = Project(
    // ...
    targets: [
        .target(
            name: "MyLibraryTests",
            destinations: .iOS,
            product: .unitTests,
            bundleId: "dev.tuist.MyLibraryTests",
            sources: "Tests/MyLibraryTests/**",
            dependencies: [
                .target(name: "MyLibrary"),
            ]
        )
    ]
)
```
<!-- -->
:::


## Swift Package Manager bağımlılıkları {#swift-package-manager-dependencies}

Bazel'de, Swift Paketlerini bağımlılık olarak kullanmak için [`rules_swift_package_manager`](https://github.com/cgrindel/rules_swift_package_manager) [Gazelle](https://github.com/bazelbuild/bazel-gazelle/blob/master/extend.md) eklentisini kullanabilirsiniz. Eklenti, bağımlılıklar için tek gerçeklik kaynağı olarak bir `Package.swift` dosyası gerektirir. Tuist'in arayüzü bu anlamda Bazel'e benzer. Paketin bağımlılıklarını çözmek ve çekmek için `tuist install` komutunu kullanabilirsiniz. Çözümleme tamamlandıktan sonra, projeyi `tuist generate` komutuyla oluşturabilirsiniz.

```bash
tuist install # Fetch dependencies defined in Tuist/Package.swift
tuist generate # Generate an Xcode project
```

## Proje oluşturma {#project-generation}

Topluluk, Bazel ile tanımlanmış projelerden Xcode projeleri oluşturmak için [rules_xcodeproj](https://github.com/MobileNativeFoundation/rules_xcodeproj) adlı bir dizi kural sağlar. Bazel'de `BUILD` dosyanıza bazı yapılandırmalar eklemeniz gerekirken, Tuist hiçbir yapılandırma gerektirmez. Projenizin kök dizininde `tuist generate` çalıştırabilirsiniz ve Tuist sizin için bir Xcode projesi oluşturacaktır.
