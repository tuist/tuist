---
{
  "title": "Migrate a Bazel project",
  "titleTemplate": ":title · Migrate · Adoption · Projects · Features · Guides · Tuist",
  "description": "Learn how to migrate your projects from Bazel to Tuist."
}
---
# Bazel projesini taşıma {#migrate-a-bazel-project}

[Bazel](https://bazel.build) Google'ın 2015 yılında açık kaynak olarak sunduğu
bir derleme sistemidir. Her boyuttaki yazılımı hızlı ve güvenilir bir şekilde
oluşturmanıza ve test etmenize olanak tanıyan güçlü bir araçtır.
Spotify](https://engineering.atspotify.com/2023/10/switching-build-systems-seamlessly/),
[Tinder](https://medium.com/tinder/bazel-hermetic-toolchain-and-tooling-migration-c244dc0d3ae)
veya [Lyft](https://semaphoreci.com/blog/keith-smiley-bazel) gibi bazı büyük
kuruluşlar Bazel'i kullanmaktadır, ancak bu sistemi tanıtmak ve sürdürmek için
ön hazırlık (yani teknolojiyi öğrenmek) ve sürekli yatırım (yani Xcode
güncellemelerini takip etmek) gerekmektedir. Bu durum, Xcode'u çok yönlü bir
konu olarak ele alan bazı kuruluşlar için uygun olsa da, ürün geliştirmeye
odaklanmak isteyen diğer kuruluşlar için uygun olmayabilir. Örneğin, iOS
platform ekibi Bazel'i tanıtan ve bu çabaya öncülük eden mühendisler şirketten
ayrıldıktan sonra Bazel'i bırakmak zorunda kalan kuruluşlar gördük. Apple'ın
Xcode ve yapı sistemi arasındaki güçlü bağlantı konusundaki tutumu da Bazel
projelerinin zaman içinde sürdürülmesini zorlaştıran bir başka faktördür.

::: tip TUIST UNIQUENESS LIES IN ITS FINESSE
<!-- -->
Tuist, Xcode ve Xcode projeleriyle savaşmak yerine onları kucaklıyor. Aynı
kavramlar (örn. hedefler, şemalar, derleme ayarları), tanıdık bir dil (örn.
Swift) ve projeleri sürdürmeyi ve ölçeklendirmeyi yalnızca iOS platform ekibinin
değil herkesin işi haline getiren basit ve keyifli bir deneyim.
<!-- -->
:::

## Kurallar {#rules}

Bazel, yazılımın nasıl oluşturulacağını ve test edileceğini tanımlamak için
kurallar kullanır. Kurallar Python benzeri bir dil olan
[Starlark](https://github.com/bazelbuild/starlark) ile yazılmıştır. Tuist,
geliştiricilere Xcode'un otomatik tamamlama, tür denetimi ve doğrulama
özelliklerini kullanma kolaylığı sağlayan bir yapılandırma dili olarak Swift'i
kullanır. Örneğin, aşağıdaki kural Bazel'de bir Swift kütüphanesinin nasıl
oluşturulacağını açıklamaktadır:

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

İşte Bazel ve Tuist'te birim testlerinin nasıl tanımlanacağını karşılaştıran
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

Bazel'de
[`rules_swift_package_manager`](https://github.com/cgrindel/rules_swift_package_manager)
kullanabilirsiniz. Swift paketi bağımlılıkları olarak kullanmak için
[Gazelle](https://github.com/bazelbuild/bazel-gazelle/blob/master/extend.md)
eklentisi. Eklenti, bağımlılıklar için bir doğruluk kaynağı olarak bir
`Package.swift` gerektirir. Tuist'in arayüzü bu anlamda Bazel'inkine benzer.
Paketin bağımlılıklarını çözümlemek ve çekmek için `tuist install` komutunu
kullanabilirsiniz. Çözümleme tamamlandıktan sonra `tuist generate` komutu ile
projeyi oluşturabilirsiniz.

```bash
tuist install # Fetch dependencies defined in Tuist/Package.swift
tuist generate # Generate an Xcode project
```

## Proje üretimi {#project-generation}

Topluluk, Bazel tarafından bildirilen projelerden Xcode projeleri oluşturmak
için
[rules_xcodeproj](https://github.com/MobileNativeFoundation/rules_xcodeproj)
adında bir dizi kural sağlar. ` BUILD` dosyanıza bazı yapılandırmalar eklemeniz
gereken Bazel'in aksine, Tuist herhangi bir yapılandırma gerektirmez. Projenizin
kök dizininde `tuist generate` komutunu çalıştırabilirsiniz ve Tuist sizin için
bir Xcode projesi oluşturacaktır.
