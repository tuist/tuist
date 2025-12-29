---
{
  "title": "Manifests",
  "titleTemplate": ":title · Projects · Features · Guides · Tuist",
  "description": "Learn about the manifest files that Tuist uses to define projects and workspaces and configure the generation process."
}
---
# Manifestolar {#manifests}

Tuist, projeleri ve çalışma alanlarını tanımlamanın ve oluşturma sürecini
yapılandırmanın birincil yolu olarak Swift dosyalarını varsayılan olarak
kullanır. Bu dosyalar, dokümantasyon boyunca **manifest dosyaları** olarak
adlandırılır.

Swift kullanma kararı, Swift paketi tanımlamak için Swift dosyalarını da
kullanan [Swift Paket
Yöneticisi](https://www.swift.org/documentation/package-manager/)'nden
esinlenilmiştir. Swift kullanımı sayesinde, içeriğin doğruluğunu doğrulamak ve
farklı manifesto dosyalarında kodu yeniden kullanmak için derleyiciden ve
sözdizimi vurgulama, otomatik tamamlama ve doğrulama sayesinde birinci sınıf bir
düzenleme deneyimi sağlamak için Xcode'dan yararlanabiliyoruz.

::: info CACHING
<!-- -->
Manifest dosyaları derlenmesi gereken Swift dosyaları olduğundan, Tuist
ayrıştırma işlemini hızlandırmak için derleme sonuçlarını önbelleğe alır. Bu
nedenle, Tuist'i ilk kez çalıştırdığınızda, projeyi oluşturmanın biraz daha uzun
sürebileceğini fark edeceksiniz. Sonraki çalıştırmalar daha hızlı olacaktır.
<!-- -->
:::

## Proje.swift {#projectswift}

<LocalizedLink href="/references/project-description/project">`Project.swift`</LocalizedLink> manifestosu bir Xcode projesi bildirir. Proje,
manifesto dosyasının bulunduğu dizinde `name` özelliğinde belirtilen adla
oluşturulur.

```swift
// Project.swift
let project = Project(
    name: "App",
    targets: [
        // ....
    ]
)
```


::: warning ROOT VARIABLES
<!-- -->
Manifestonun kökünde olması gereken tek değişken `let project = Project(...)`.
Manifestonun çeşitli bölümlerinde kodu yeniden kullanmanız gerekiyorsa Swift
fonksiyonlarını kullanabilirsiniz.
<!-- -->
:::

## Çalışma Alanı.swift {#workspaceswift}

Tuist varsayılan olarak, oluşturulan projeyi ve bağımlılıklarının projelerini
içeren bir [Xcode
Workspace](https://developer.apple.com/documentation/xcode/projects-and-workspaces)
oluşturur. Herhangi bir nedenle çalışma alanını ek projeler eklemek veya dosya
ve grupları dahil etmek için özelleştirmek isterseniz, bunu bir
<LocalizedLink href="/references/project-description/structs/workspace">`Workspace.swift`</LocalizedLink>
manifestosu tanımlayarak yapabilirsiniz.

```swift
// Workspace.swift
import ProjectDescription

let workspace = Workspace(
    name: "App-Workspace",
    projects: [
        "./App", // Path to directory containing the Project.swift file
    ]
)
```

::: info
<!-- -->
Tuist bağımlılık grafiğini çözecek ve bağımlılıkların projelerini çalışma
alanına dahil edecektir. Bunları manuel olarak eklemenize gerek yoktur. Bu,
derleme sisteminin bağımlılıkları doğru şekilde çözümlemesi için gereklidir.
<!-- -->
:::

### Çoklu veya tekli proje {#multi-or-monoproject}

Sıklıkla gündeme gelen bir soru, bir çalışma alanında tek bir proje mi yoksa
birden fazla proje mi kullanılacağıdır. Tek proje kurulumunun sık sık Git
çakışmalarına yol açacağı Tuist'in olmadığı bir dünyada, çalışma alanlarının
kullanımı teşvik edilir. Ancak, Tuist tarafından oluşturulan Xcode projelerinin
Git deposuna dahil edilmesini önermediğimiz için, Git çakışmaları bir sorun
değildir. Bu nedenle, bir çalışma alanında tek bir proje veya birden fazla proje
kullanma kararı size kalmıştır.

Tuist projesinde, soğuk üretim süresi daha hızlı olduğu için (derlenecek daha az
manifesto dosyası) ve bir kapsülleme birimi olarak
<LocalizedLink href="/guides/features/projects/code-sharing">proje açıklama yardımcılarından</LocalizedLink> yararlandığımız için mono-projelere
dayanıyoruz. Bununla birlikte, uygulamanızın farklı alanlarını temsil etmek için
Xcode projelerini bir kapsülleme birimi olarak kullanmak isteyebilirsiniz, bu da
Xcode'un önerilen proje yapısıyla daha yakından uyumludur.

## Tuist.swift {#tuistswift}

Tuist, proje yapılandırmasını basitleştirmek için
<LocalizedLink href="/contributors/principles.html#default-to-conventions">uygun varsayılanlar</LocalizedLink> sağlar. Ancak, projenin kökünde Tuist tarafından
projenin kökünü belirlemek için kullanılan bir
<LocalizedLink href="/references/project-description/structs/tuist">`Tuist.swift`</LocalizedLink>
tanımlayarak yapılandırmayı özelleştirebilirsiniz.

```swift
import ProjectDescription

let tuist = Tuist(
    project: .tuist(generationOptions: .options(enforceExplicitDependencies: true))
)
```
