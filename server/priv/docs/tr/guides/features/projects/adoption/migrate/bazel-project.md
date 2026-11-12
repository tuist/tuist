---
{
  "title": "Bazel projesini geçiş yapma",
  "titleTemplate": ":title · Geçiş · Benimseme · Projeler · Özellikler · Kılavuzlar · Tuist",
  "description": "Projelerinizi Bazel'den Tuist'e nasıl geçireceğinizi öğrenin."
}
---
# Bazel projesini taşıma {#migrate-a-bazel-project}

[Bazel](https://bazel.build), Google tarafından 2015 yılında açık kaynak hale getirilen bir derleme sistemidir. Her ölçekteki yazılımı hızlı ve güvenilir bir şekilde derlemenize ve test etmenize olanak tanıyan güçlü bir araçtır. [Spotify](https://engineering.atspotify.com/2023/10/switching-build-systems-seamlessly/), [Tinder](https://medium.com/tinder/bazel-hermetic-toolchain-and-tooling-migration-c244dc0d3ae) veya [Lyft](https://semaphoreci.com/blog/keith-smiley-bazel) gibi bazı büyük kuruluşlar bunu kullanmaktadır; ancak, teknolojiyi öğrenmek gibi ilk aşamada ve Xcode güncellemelerini takip etmek gibi sürekli yatırım gerektiren bir süreçtir. Bazı kuruluşlar bunu çapraz bir sorumluluk olarak ele alıp bu yaklaşımı benimserken, ürün geliştirmeye odaklanmak isteyen diğerleri için en uygun çözüm olmayabilir. Örneğin, iOS platform ekibi Bazel'i tanıtan ancak çabayı yürüten mühendisler şirketten ayrıldıktan sonra bunu bırakmak zorunda kalan kuruluşlar gördük. Apple'ın Xcode ile derleme sistemi arasındaki sıkı bağımlılık konusundaki tutumu da zaman içinde Bazel projelerini sürdürmeyi zorlaştıran başka bir faktördür.

> [!TIP]
> **Tuist'in benzersizliği inceliğinde yatar**
>
> Tuist, Xcode ve Xcode projeleriyle mücadele etmek yerine onları benimser. Aynı kavramlar (örneğin hedefler, şemalar, derleme ayarları), tanıdık bir dil (yani Swift) ve projelerin bakımını ve ölçeklendirmesini herkesin işi haline getiren, sadece iOS platform ekibinin değil, basit ve keyifli bir deneyim sunar.


## Kurallar {#rules}

Bazel, yazılımın nasıl derleneceğini ve test edileceğini tanımlamak için kuralları kullanır. Kurallar, Python benzeri bir dil olan [Starlark](https://github.com/bazelbuild/starlark) ile yazılır. Tuist, yapılandırma dili olarak Swift'i kullanır ve bu sayede geliştiricilere Xcode'un otomatik tamamlama, tür denetimi ve doğrulama özelliklerini kullanma kolaylığı sağlar. Örneğin, aşağıdaki kural Bazel'de bir Swift kitaplığının nasıl derleneceğini açıklar:

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

Bazel'de, Swift Paketlerini bağımlılık olarak kullanmak için [`rules_swift_package_manager`](https://github.com/cgrindel/rules_swift_package_manager) [Gazelle](https://github.com/bazelbuild/bazel-gazelle/blob/master/extend.md) eklentisini kullanabilirsiniz. Eklenti, bağımlılıklar için tek doğruluk kaynağı olarak bir `Package.swift` dosyası gerektirir. Bu açıdan Tuist'in arayüzü Bazel'e benzer. Paketin bağımlılıklarını çözümlemek ve çekmek için `tuist install` komutunu kullanabilirsiniz. Çözümleme tamamlandıktan sonra projeyi `tuist generate` komutuyla oluşturabilirsiniz.

```bash
tuist install # Fetch dependencies defined in Tuist/Package.swift
tuist generate # Generate an Xcode project
```

## Proje oluşturma {#project-generation}

Topluluk, Bazel ile tanımlanmış projelerden Xcode projeleri oluşturmak için [rules_xcodeproj](https://github.com/MobileNativeFoundation/rules_xcodeproj) adlı bir dizi kural sağlar. Bazel'de `BUILD` dosyanıza bazı yapılandırmalar eklemeniz gerekirken, Tuist hiçbir yapılandırma gerektirmez. Projenizin kök dizininde `tuist generate` çalıştırabilirsiniz ve Tuist sizin için bir Xcode projesi oluşturacaktır.
