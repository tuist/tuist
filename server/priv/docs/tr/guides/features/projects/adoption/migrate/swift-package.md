---
{
  "title": "Migrate a Swift Package",
  "titleTemplate": ":title · Migrate · Adoption · Projects · Features · Guides · Tuist",
  "description": "Learn how to migrate from Swift Package Manager as a solution for managing your projects to Tuist projects."
}
---
# Bir Swift paketi taşıma {#migrate-a-swift-package}

Swift paketi, Swift kodu için bir bağımlılık yöneticisi olarak ortaya çıktı ve
istemeden kendini projeleri yönetme ve Objective-C gibi diğer programlama
dillerini destekleme sorununu çözerken buldu. Araç farklı bir amaç göz önünde
bulundurularak tasarlandığından, Tuist'in sağladığı esneklik, performans ve
güçten yoksun olduğu için ölçekli projeleri yönetmek için kullanmak zor
olabilir. Bu durum, Swift paketi Yöneticisi ve yerel Xcode projelerinin
performansını karşılaştıran aşağıdaki tabloyu içeren [Scaling iOS at
Bumble](https://medium.com/bumble-tech/scaling-ios-at-bumble-239e0fa009f2)
makalesinde iyi bir şekilde ele alınmıştır:

<img style="max-width: 400px;" alt="A table that compares the regression in performance when using SPM over native Xcode projects" src="/images/guides/start/migrate/performance-table.webp">

Swift paketi paket yöneticisinin benzer bir proje yönetimi rolü
üstlenebileceğini düşünerek Tuist'e duyulan ihtiyacı sorgulayan geliştiriciler
ve kuruluşlarla sık sık karşılaşıyoruz. Bazıları, daha sonra geliştirici
deneyimlerinin önemli ölçüde azaldığını fark etmek için bir geçişe girişiyor.
Örneğin, bir dosyanın yeniden adlandırılması, yeniden endekslenmesi 15 saniye
kadar sürebilir. 15 saniye!

**Apple'ın Swift paketi Paket Yöneticisini ölçekli bir proje yöneticisi haline
getirip getirmeyeceği belirsiz.** Ancak, bunun gerçekleştiğine dair herhangi bir
işaret görmüyoruz. Aslında tam tersini görüyoruz. Örtük yapılandırmalar yoluyla
kolaylık sağlamak gibi Xcode'dan esinlenen kararlar alıyorlar ki bu da
<LocalizedLink href="/guides/features/projects/cost-of-convenience"> bildiğiniz gibi </LocalizedLink> ölçekte komplikasyonların kaynağıdır. Apple'ın ilk
ilkelere dönmesi ve bir bağımlılık yöneticisi olarak mantıklı olan ancak bir
proje yöneticisi olarak mantıklı olmayan, örneğin projeleri tanımlamak için bir
arayüz olarak derlenmiş bir dilin kullanılması gibi bazı kararları yeniden
gözden geçirmesi gerektiğine inanıyoruz.

::: tip SPM AS JUST A DEPENDENCY MANAGER
<!-- -->
Tuist, Swift paketi Paket Yöneticisi'ni bir bağımlılık yöneticisi olarak ele
alıyor ve bu harika bir şey. Onu bağımlılıkları çözmek ve inşa etmek için
kullanıyoruz. Projeleri tanımlamak için kullanmıyoruz çünkü bunun için
tasarlanmadı.
<!-- -->
:::

## Swift paketi Yöneticisinden Tuist'e Geçiş {#migrating-from-swift-package-manager-to-tuist}

Swift paketi Yöneticisi ve Tuist arasındaki benzerlikler geçiş sürecini
basitleştirir. Temel fark, projelerinizi `Package.swift` yerine Tuist'in
DSL'sini kullanarak tanımlayacak olmanızdır.

Öncelikle, `Package.swift` dosyanızın yanında bir `Project.swift` dosyası
oluşturun. ` Project.swift` dosyası projenizin tanımını içerecektir. İşte tek
hedefli bir projeyi tanımlayan bir `Project.swift` dosyası örneği:

```swift
import ProjectDescription

let project = Project(
    name: "App",
    targets: [
        .target(
            name: "App",
            destinations: .iOS,
            product: .app,
            bundleId: "dev.tuist.App",
            sources: ["Sources/**/*.swift"]*
        ),
    ]
)
```

Dikkat edilmesi gereken bazı şeyler:

- **ProjectDescription**: ` PackageDescription` kullanmak yerine
  `ProjectDescription` kullanacaksınız.
- **Proje:** Bir `paketi` örneğini dışa aktarmak yerine, bir `projesi` örneğini
  dışa aktaracaksınız.
- **Xcode dili:** Projenizi tanımlamak için kullandığınız ilkeller Xcode'un
  dilini taklit eder, bu nedenle diğerlerinin yanı sıra şemalar, hedefler ve
  derleme aşamaları bulacaksınız.

Ardından aşağıdaki içeriğe sahip bir `Tuist.swift` dosyası oluşturun:

```swift
import ProjectDescription

let tuist = Tuist()
```

`Tuist.swift` projenizin yapılandırmasını içerir ve yolu projenizin kökünü
belirlemek için bir referans görevi görür. Tuist projelerinin yapısı hakkında
daha fazla bilgi edinmek için
<LocalizedLink href="/guides/features/projects/directory-structure">directory structure</LocalizedLink> belgesine göz atabilirsiniz.

## Projenin düzenlenmesi {#editing-the-project}

Xcode'da projeyi düzenlemek için
<LocalizedLink href="/guides/features/projects/editing">`tuist edit`</LocalizedLink> komutunu kullanabilirsiniz. Komut, açıp üzerinde çalışmaya
başlayabileceğiniz bir Xcode projesi oluşturacaktır.

```bash
tuist edit
```

Projenin boyutuna bağlı olarak, tek seferde veya aşamalı olarak kullanmayı
düşünebilirsiniz. DSL ve iş akışına aşina olmak için küçük bir proje ile
başlamanızı öneririz. Tavsiyemiz her zaman en çok bağımlı olunan hedeften
başlamak ve en üst düzey hedefe kadar ilerlemektir.
