---
{
  "title": "Migrate a Swift Package",
  "titleTemplate": ":title · Migrate · Adoption · Projects · Features · Guides · Tuist",
  "description": "Learn how to migrate from Swift Package Manager as a solution for managing your projects to Tuist projects."
}
---
# Swift paketi taşıma {#migrate-a-swift-package}

Swift paketi, Swift kodu için bir bağımlılık yöneticisi olarak ortaya çıktı ve
istemeden de olsa projelerin yönetilmesi ve Objective-C gibi diğer programlama
dillerinin desteklenmesi sorununu çözdü. Bu araç farklı bir amaçla
tasarlandığından, Tuist'in sağladığı esneklik, performans ve güce sahip olmadığı
için büyük ölçekli projeleri yönetmek için kullanmak zor olabilir. Bu durum,
Swift paketi ve yerel Xcode projelerinin performansını karşılaştıran aşağıdaki
tabloyu içeren [Scaling iOS at
Bumble](https://medium.com/bumble-tech/scaling-ios-at-bumble-239e0fa009f2)
makalesinde iyi bir şekilde ele alınmıştır:

<img style="max-width: 400px;" alt="A table that compares the regression in performance when using SPM over native Xcode projects" src="/images/guides/start/migrate/performance-table.webp">

Swift paketi'nin benzer bir proje yönetimi rolü üstlenebileceğini düşünerek
Tuist'in gerekliliğini sorgulayan geliştiriciler ve kuruluşlarla sık sık
karşılaşıyoruz. Bazıları geçiş yapmaya karar veriyor, ancak daha sonra
geliştirici deneyimlerinin önemli ölçüde kötüleştiğini fark ediyor. Örneğin, bir
dosyanın yeniden adlandırılması için yeniden indeksleme işlemi 15 saniye kadar
sürebilir. 15 saniye!

**Apple'ın Swift paketi yöneticisini ölçeklenebilir bir proje yöneticisi haline
getirip getirmeyeceği belirsizdir.** Ancak, bunun olacağına dair herhangi bir
işaret görmüyoruz. Aslında, tam tersini görüyoruz. Xcode'dan esinlenen kararlar
alıyorlar, örneğin örtük yapılandırmalarla kolaylık sağlama gibi, ki
<LocalizedLink href="/guides/features/projects/cost-of-convenience">bildiğiniz
gibi,</LocalizedLink> bu ölçeklendirmede karmaşıklığa neden oluyor. Apple'ın
temel ilkelere dönmesi ve bağımlılık yöneticisi olarak mantıklı olan ancak proje
yöneticisi olarak mantıklı olmayan bazı kararları yeniden gözden geçirmesi
gerektiğini düşünüyoruz, örneğin projeleri tanımlamak için arayüz olarak
derlenmiş bir dilin kullanılması gibi.

::: tip SPM AS JUST A DEPENDENCY MANAGER
<!-- -->
Tuist, Swift paketi yöneticisini bir bağımlılık yöneticisi olarak görür ve bu
harika bir şeydir. Bağımlılıkları çözmek ve bunları oluşturmak için kullanırız.
Projeleri tanımlamak için kullanmayız çünkü bunun için tasarlanmamıştır.
<!-- -->
:::

## Swift paket yöneticisinden Tuist'e geçiş {#migrating-from-swift-package-manager-to-tuist}

Swift paketi ile Tuist arasındaki benzerlikler, geçiş sürecini kolaylaştırır.
Temel fark, projelerinizi `Package.swift` yerine Tuist'in DSL'sini kullanarak
tanımlayacak olmanızdır.

İlk olarak, `Project.swift` dosyasını `Package.swift` dosyasının yanına
oluşturun. `Project.swift` dosyası projenizin tanımını içerecektir. Aşağıda, tek
bir hedef içeren bir projeyi tanımlayan `Project.swift` dosyasının bir örneği
verilmiştir:

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

Dikkat edilmesi gereken bazı noktalar:

- **ProjectDescription**: `PackageDescription` yerine, `ProjectDescription`
  kullanacaksınız.
- **Proje:** ` paketini` örneğini dışa aktarmak yerine, `projesini` örneğini
  dışa aktaracaksınız.
- **Xcode dili:** Projenizi tanımlamak için kullandığınız temel öğeler Xcode
  dilini taklit eder, bu nedenle şemalar, hedefler ve derleme aşamaları gibi
  öğeler bulacaksınız.

Ardından, aşağıdaki içeriğe sahip bir `Tuist.swift` dosyası oluşturun:

```swift
import ProjectDescription

let tuist = Tuist()
```

`Tuist.swift`, projenizin yapılandırmasını içerir ve yolu, projenizin kökünü
belirlemek için referans görevi görür. Tuist projelerinin yapısı hakkında daha
fazla bilgi edinmek için
<LocalizedLink href="/guides/features/projects/directory-structure">dizin
yapısı</LocalizedLink> belgesini inceleyebilirsiniz.

## Projeyi düzenleme {#editing-the-project}

Xcode'da projeyi düzenlemek için
<LocalizedLink href="/guides/features/projects/editing">`tuist
edit`</LocalizedLink> komutunu kullanabilirsiniz. Bu komut, açıp üzerinde
çalışmaya başlayabileceğiniz bir Xcode projesi oluşturacaktır.

```bash
tuist edit
```

Projenin büyüklüğüne bağlı olarak, tek seferde veya aşamalı olarak kullanmayı
düşünebilirsiniz. DSL ve iş akışına aşina olmak için küçük bir projeyle
başlamanızı öneririz. Tavsiyemiz, her zaman en çok bağımlı olan hedeften
başlayıp en üst düzey hedefe kadar ilerlemenizdir.
