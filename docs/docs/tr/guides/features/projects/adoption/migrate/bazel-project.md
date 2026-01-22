---
{
  "title": "Migrate a Bazel project",
  "titleTemplate": ":title · Migrate · Adoption · Projects · Features · Guides · Tuist",
  "description": "Learn how to migrate your projects from Bazel to Tuist."
}
---
# Bazel projesini taşıma {#migrate-a-bazel-project}

[Bazel](https://bazel.build), Google'ın 2015 yılında açık kaynak olarak
yayınladığı bir derleme sistemidir. Her boyuttaki yazılımı hızlı ve güvenilir
bir şekilde derlemenizi ve test etmenizi sağlayan güçlü bir araçtır.
[Spotify](https://engineering.atspotify.com/2023/10/switching-build-systems-seamlessly/),
[Tinder](https://medium.com/tinder/bazel-hermetic-toolchain-and-tooling-migration-c244dc0d3ae)
veya [Lyft](https://semaphoreci.com/blog/keith-smiley-bazel) gibi bazı büyük
kuruluşlar bu aracı kullanmaktadır, ancak bu aracı tanıtmak ve sürdürmek için
önceden (yani teknolojiyi öğrenmek) ve sürekli yatırım (yani Xcode
güncellemelerini takip etmek) gereklidir. Bu, onu çapraz kesen bir sorun olarak
gören bazı kuruluşlar için işe yararken, ürün geliştirmeye odaklanmak isteyen
diğerleri için en uygun seçenek olmayabilir. Örneğin, iOS platform ekibi Bazel'i
tanıtan ve bu çalışmayı yöneten mühendisler şirketten ayrıldıktan sonra onu
bırakmak zorunda kalan kuruluşlar gördük. Apple'ın Xcode ve derleme sistemi
arasındaki güçlü bağa ilişkin tutumu, Bazel projelerini zaman içinde sürdürmeyi
zorlaştıran bir başka faktördür.

::: tip TUIST UNIQUENESS LIES IN ITS FINESSE
<!-- -->
Tuist, Xcode ve Xcode projeleriyle mücadele etmek yerine onları benimser. Aynı
kavramlar (ör. hedefler, şemalar, derleme ayarları), tanıdık bir dil (yani
Swift) ve basit ve keyifli bir deneyim sayesinde, projelerin bakımı ve
ölçeklendirilmesi sadece iOS platform ekibinin değil, herkesin işi haline gelir.
<!-- -->
:::

## Kurallar {#rules}

Bazel, yazılımın nasıl derleneceğini ve test edileceğini tanımlamak için
kurallar kullanır. Kurallar, Python benzeri bir dil olan
[Starlark](https://github.com/bazelbuild/starlark) ile yazılır. Tuist,
yapılandırma dili olarak Swift kullanır ve bu da geliştiricilere Xcode'un
otomatik tamamlama, tür denetimi ve doğrulama özelliklerini kullanma kolaylığı
sağlar. Örneğin, aşağıdaki kural Bazel'de bir Swift kütüphanesinin nasıl
derleneceğini açıklar:

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
        .target(name: "MyLibrary", product: .staticLibrary, sources: ["**/*.swift"])
    ]
)
```
<!-- -->
:::

İşte Bazel ve Tuist'te birim testlerinin nasıl tanımlandığını karşılaştıran
başka bir örnek:

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


## Swift paketi Yöneticisi bağımlılıkları {#swift-package-manager-dependencies}

Bazel'de, Swift paketlerini bağımlılık olarak kullanmak için
[`rules_swift_package_manager`](https://github.com/cgrindel/rules_swift_package_manager)
[Gazelle](https://github.com/bazelbuild/bazel-gazelle/blob/master/extend.md)
eklentisini kullanabilirsiniz. Eklenti, bağımlılıklar için doğru kaynak olarak
`Package.swift` gerektirir. Tuist'in arayüzü bu anlamda Bazel'inkine benzer.
`tuist install` komutunu kullanarak paketin bağımlılıklarını çözebilir ve
çekebilirsiniz. Çözümleme tamamlandıktan sonra, `tuist generate` komutuyla
projeyi oluşturabilirsiniz.

```bash
tuist install # Fetch dependencies defined in Tuist/Package.swift
tuist generate # Generate an Xcode project
```

## Proje oluşturma {#project-generation}

Topluluk, Bazel ile tanımlanmış projelerden Xcode projeleri oluşturmak için bir
dizi kural
[rules_xcodeproj](https://github.com/MobileNativeFoundation/rules_xcodeproj)
sağlar. Bazel'de `BUILD` dosyasına bazı yapılandırmalar eklemeniz gerekirken,
Tuist'te hiçbir yapılandırma gerekmez. Projenizin kök dizininde `tuist generate`
komutunu çalıştırabilirsiniz. Tuist sizin için bir Xcode projesi oluşturacaktır.
