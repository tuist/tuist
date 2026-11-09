---
{
  "title": "Manifestler",
  "titleTemplate": ":title · Projeler · Özellikler · Kılavuzlar · Tuist",
  "description": "Tuist projelerinizi, çalışma alanlarınızı ve oluşturma yapılandırmanızı tanımlayan manifest dosyaları."
}
---
# Manifestler {#manifests}

Tuist, projeleri ve çalışma alanlarını tanımlamak ve oluşturma sürecini yapılandırmak için varsayılan olarak Swift dosyalarını kullanır. Bu dosyalara belgelerin genelinde **manifest dosyaları** adı verilir.

Swift kullanma kararı, paketleri tanımlamak için yine Swift dosyalarını kullanan [Swift Package Manager](https://www.swift.org/documentation/package-manager/) tarafından esinlenmiştir. Swift kullanımı sayesinde, içeriğin doğruluğunu doğrulamak ve farklı manifest dosyaları arasında kodu yeniden kullanmak için derleyiciden yararlanabiliriz; ayrıca sözdizimi vurgulama, otomatik tamamlama ve doğrulama özellikleriyle Xcode’un birinci sınıf bir düzenleme deneyimi sunmasından faydalanabiliriz.

> [!NOTE]
> **Önbellekleme**
>
> Manifest dosyaları derlenmesi gereken Swift dosyaları olduğundan, Tuist ayrıştırma sürecini hızlandırmak için derleme sonuçlarını önbelleğe alır. Bu nedenle, Tuist’i ilk çalıştırdığınızda projenin oluşturulmasının biraz daha uzun sürebileceğini fark edeceksiniz. Sonraki çalıştırmalar daha hızlı olacaktır.


## Project.swift {#projectswift}

[`Project.swift`](https://projectdescription.tuist.dev/documentation/projectdescription/project) manifesti bir Xcode projesi bildirir. Proje, manifest dosyasının bulunduğu dizinde, `name` özelliğinde belirtilen adla oluşturulur.

```swift
// Project.swift
let project = Project(
    name: "App",
    targets: [
        // ....
    ]
)
```


> [!WARNING]
> **Kök değişkenler**
>
> Manifestin kök düzeyinde bulunması gereken tek değişken `let project = Project(...)` şeklindedir. Manifestin çeşitli bölümlerinde kodu yeniden kullanmanız gerekiyorsa Swift fonksiyonlarını kullanabilirsiniz.


## Workspace.swift {#workspaceswift}

Varsayılan olarak Tuist, oluşturulan projeyi ve bağımlılıklarının projelerini içeren bir [Xcode Workspace](https://developer.apple.com/documentation/xcode/projects-and-workspaces) oluşturur. Herhangi bir nedenle çalışma alanını özelleştirerek ek projeler eklemek veya dosya ve grupları dahil etmek isterseniz, bunu bir [`Workspace.swift`](https://projectdescription.tuist.dev/documentation/projectdescription/workspace) manifesti tanımlayarak yapabilirsiniz.

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

> [!NOTE]
> Tuist bağımlılık grafını çözecek ve bağımlılıkların projelerini çalışma alanına dahil edecektir. Bunları manuel olarak eklemenize gerek yoktur. Bu, derleme sisteminin bağımlılıkları doğru şekilde çözmesi için gereklidir.


### Çoklu veya tek proje {#multi-or-monoproject}

Sıkça sorulan bir soru, bir çalışma alanında tek bir proje mi yoksa birden fazla proje mi kullanılacağıdır. Tuist’in olmadığı bir dünyada, tek proje kurulumu sık Git çakışmalarına yol açacağından çalışma alanlarının kullanımı teşvik edilir. Ancak, Tuist tarafından oluşturulan Xcode projelerini Git deposuna dahil etmeyi önermediğimiz için Git çakışmaları bir sorun değildir. Dolayısıyla, bir çalışma alanında tek bir proje mi yoksa birden fazla proje mi kullanılacağına karar vermek size kalmıştır.

Tuist projesinde, soğuk oluşturma süresi daha hızlı olduğu (derlenecek daha az manifest dosyası) ve kapsülleme birimi olarak <.localized_link href="/guides/features/projects/code-sharing">proje açıklama yardımcıları</.localized_link>nı kullandığımız için tek projelere yöneliyoruz. Ancak, uygulamanızın farklı alanlarını temsil etmek için Xcode projelerini bir kapsülleme birimi olarak kullanmak isteyebilirsiniz; bu yaklaşım, Xcode’un önerdiği proje yapısıyla daha uyumludur.

## Tuist.swift {#tuistswift}

Tuist, proje yapılandırmasını basitleştirmek için <.localized_link href="/contributors/principles#default-to-conventions">mantıklı varsayılanlar</.localized_link> sunar. Ancak, projenin kök dizininde bir [`Tuist.swift`](https://projectdescription.tuist.dev/documentation/projectdescription/tuist) tanımlayarak yapılandırmayı özelleştirebilirsiniz; bu dosya, Tuist tarafından projenin kökünü belirlemek için kullanılır.

```swift
import ProjectDescription

let tuist = Tuist(
    project: .tuist(generationOptions: .options(registryEnabled: true))
)
```
