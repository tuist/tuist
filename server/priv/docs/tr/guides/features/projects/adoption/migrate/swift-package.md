---
{
  "title": "Swift Paketini Taşıma",
  "titleTemplate": ":title · Taşıma · Benimseme · Projeler · Özellikler · Kılavuzlar · Tuist",
  "description": "Swift Package Manager proje yönetiminden Tuist'e geçiş yapın."
}
---
# Swift Paketini Taşıma {#migrate-a-swift-package}

Swift Package Manager, Swift kodları için bir bağımlılık yöneticisi olarak ortaya çıktı ve yanlışlıkla proje yönetimi sorununu çözmek ve Objective-C gibi diğer programlama dillerini desteklemek durumunda kaldı. Araç farklı bir amaçla tasarlandığından, Tuist'in sunduğu esneklik, performans ve güçten yoksun olduğu için büyük ölçekli projeleri yönetmek amacıyla kullanılması zor olabilir. Bu durum, Swift Package Manager ile yerel Xcode projelerinin performansını karşılaştıran aşağıdaki tabloyu içeren [Scaling iOS at Bumble](https://medium.com/bumble-tech/scaling-ios-at-bumble-239e0fa009f2) makalesinde iyi şekilde özetlenmiştir:

<img style="max-width: 400px;" alt="SPM kullanıldığında yerel Xcode projelerine kıyasla performanstaki gerilemeyi karşılaştıran bir tablo" src="/images/guides/start/migrate/performance-table.webp">

Swift Package Manager'ın benzer bir proje yönetimi rolü üstlenebileceğini düşünerek Tuist'in gerekliliğine meydan okuyan geliştiriciler ve kuruluşlarla sıkça karşılaşıyoruz. Bazıları taşınma girişiminde bulunuyor ve daha sonra geliştirici deneyimlerinin önemli ölçüde kötüleştiğini fark ediyor. Örneğin, bir dosyanın yeniden adlandırılması yeniden indeksleme için 15 saniyeye kadar sürebilir. 15 saniye!

**Apple'ın Swift Package Manager'ı büyük ölçekli kullanım için tasarlanmış bir proje yöneticisine dönüştürüp dönüştürmeyeceği belirsiz.** Ancak bunun gerçekleştiğine dair herhangi bir işaret görmüyoruz. Aslında tam tersini görüyoruz. Apple, örtük yapılandırmalar aracılığıyla kolaylık sağlamak gibi Xcode'dan esinlenen kararlar alıyor; bu durum <.localized_link href="/guides/features/projects/cost-of-convenience">bildiğiniz gibi,</.localized_link> büyük ölçekte karmaşıklıkların kaynağıdır. Apple'ın temel prensiplere dönerek bağımlılık yöneticisi olarak mantıklı olan ancak proje yöneticisi olarak olmayan bazı kararları, örneğin projeleri tanımlamak için derlenmiş bir dilin arayüz olarak kullanılmasını, yeniden gözden geçirmesi gerektiğine inanıyoruz.

> [!TIP]
> **Sadece bir bağımlılık yöneticisi olarak SwiftPM**
>
> Tuist, Swift Package Manager'ı bir bağımlılık yöneticisi olarak ele alır ve bu konuda oldukça iyidir. Bağımlılıkları çözmek ve derlemek için onu kullanıyoruz. Projeleri tanımlamak için kullanmıyoruz çünkü bu amaçla tasarlanmamıştır. Yan yana bir karşılaştırma için bkz. [Swift Package Manager vs Tuist](https://tuist.dev/compare/swift-package-manager).


## Swift Package Manager'dan Tuist'e Geçiş {#migrating-from-swift-package-manager-to-tuist}

Swift Package Manager ile Tuist arasındaki benzerlikler, geçiş sürecini basit hale getirir. Temel fark, projelerinizi `Package.swift` yerine Tuist'in DSL'sini kullanarak tanımlayacak olmanızdır.

İlk olarak, `Package.swift` dosyanızın yanına bir `Project.swift` dosyası oluşturun. `Project.swift` dosyası projenizin tanımını içerecektir. İşte tek bir hedef içeren bir projeyi tanımlayan bir `Project.swift` dosyasına örnek:

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

- **ProjectDescription**: `PackageDescription` kullanmak yerine `ProjectDescription` kullanacaksınız.
- **Proje:** Bir `package` örneğini dışa aktarmak yerine bir `project` örneğini dışa aktaracaksınız.
- **Xcode dili:** Projenizi tanımlamak için kullandığınız temel öğeler Xcode'un dilini taklit eder, bu nedenle şemalar, hedefler ve derleme aşamaları gibi öğeleri bulacaksınız.

Ardından aşağıdaki içeriğe sahip bir `Tuist.swift` dosyası oluşturun:

```swift
import ProjectDescription

let tuist = Tuist()
```

`Tuist.swift`, projenizin yapılandırmasını içerir ve yolu projenizin kökünü belirlemek için referans olarak hizmet eder. Tuist projelerinin yapısı hakkında daha fazla bilgi edinmek için <.localized_link href="/guides/features/projects/directory-structure">dizin yapısı</.localized_link> belgesine göz atabilirsiniz.

## Projeyi Düzenleme {#editing-the-project}

Projeyi Xcode'da düzenlemek için <.localized_link href="/guides/features/projects/editing">`tuist edit`</.localized_link> komutunu kullanabilirsiniz. Komut, açıp üzerinde çalışmaya başlayabileceğiniz bir Xcode projesi oluşturacaktır.

```bash
tuist edit
```

Projenin boyutuna bağlı olarak, bunu tek seferde veya kademeli olarak kullanmayı düşünebilirsiniz. DSL ve iş akışına alışmak için küçük bir projeden başlamanızı öneririz. Tavsiyemiz her zaman en çok bağımlılık alınan hedeften başlayıp en üst düzey hedefe doğru ilerlemektir.
