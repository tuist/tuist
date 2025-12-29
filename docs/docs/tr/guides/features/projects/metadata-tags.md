---
{
  "title": "Metadata tags",
  "titleTemplate": ":title · Projects · Features · Guides · Tuist",
  "description": "Learn how to use target metadata tags to organize and focus on specific parts of your project"
}
---
# Meta veri etiketleri {#metadata-tags}

Projelerin boyutu ve karmaşıklığı arttıkça, tüm kod tabanı ile aynı anda
çalışmak verimsiz hale gelebilir. Tuist, hedefleri mantıksal gruplar halinde
düzenlemenin ve geliştirme sırasında projenizin belirli bölümlerine odaklanmanın
bir yolu olarak **meta veri etiketlerini** sağlar.

## Meta veri etiketleri nedir? {#what-are-metadata-tags}

Meta veri etiketleri, projenizdeki hedeflere ekleyebileceğiniz dize
etiketleridir. Aşağıdakileri yapmanıza olanak tanıyan işaretleyiciler olarak
hizmet ederler:

- **İlgili hedefleri gruplayın** - Aynı özelliğe, ekibe veya mimari katmana ait
  hedefleri etiketleyin
- **Çalışma alanınıza odaklanın** - Yalnızca belirli etiketlere sahip hedefleri
  içeren projeler oluşturun
- **İş akışınızı optimize edin** - Kod tabanınızın ilgisiz bölümlerini
  yüklemeden belirli özellikler üzerinde çalışın
- **Kaynak olarak tutulacak hedefleri seçin** - Önbelleğe alırken hangi hedef
  grubunu kaynak olarak tutmak istediğinizi seçin

Etiketler, hedeflerde `metadata` özelliği kullanılarak tanımlanır ve bir dizeler
dizisi olarak saklanır.

## Meta veri etiketlerini tanımlama {#defining-metadata-tags}

Proje bildiriminizdeki herhangi bir hedefe etiket ekleyebilirsiniz:

```swift
import ProjectDescription

let project = Project(
    name: "MyApp",
    targets: [
        .target(
            name: "Authentication",
            destinations: .iOS,
            product: .framework,
            bundleId: "com.example.authentication",
            sources: ["Sources/**"],
            metadata: .metadata(tags: ["feature:auth", "team:identity"])
        ),
        .target(
            name: "Payment",
            destinations: .iOS,
            product: .framework,
            bundleId: "com.example.payment",
            sources: ["Sources/**"],
            metadata: .metadata(tags: ["feature:payment", "team:commerce"])
        ),
        .target(
            name: "App",
            destinations: .iOS,
            product: .app,
            bundleId: "com.example.app",
            sources: ["Sources/**"],
            dependencies: [
                .target(name: "Authentication"),
                .target(name: "Payment")
            ]
        )
    ]
)
```

## Etiketlenmiş hedeflere odaklanma {#focusing-on-tagged-targets}

Hedeflerinizi etiketledikten sonra, yalnızca belirli hedefleri içeren odaklanmış
bir proje oluşturmak için `tuist generate` komutunu kullanabilirsiniz:

### Etikete göre odaklanın

Belirli bir etiketle eşleşen tüm hedefleri içeren bir proje oluşturmak için
`tag:` önekini kullanın:

```bash
# Generate project with all authentication-related targets
tuist generate tag:feature:auth

# Generate project with all targets owned by the identity team
tuist generate tag:team:identity
```

### İsme göre odaklanın

Ayrıca isme göre belirli hedeflere de odaklanabilirsiniz:

```bash
# Generate project with the Authentication target
tuist generate Authentication
```

### Odaklanma nasıl çalışır?

Hedeflere odaklandığınızda:

1. **Dahil edilen hedefler** - Sorgunuzla eşleşen hedefler oluşturulmuş projele
   dahil edilir
2. **Bağımlılıklar** - Odaklanılan hedeflerin tüm bağımlılıkları otomatik olarak
   dahil edilir
3. **Test hedefleri** - Odaklanılan hedefler için test hedefleri dahildir
4. **Dışlama** - Diğer tüm hedefler çalışma alanından çıkarılır

Bu, yalnızca özelliğiniz üzerinde çalışmak için ihtiyacınız olan şeyleri içeren
daha küçük, daha yönetilebilir bir çalışma alanına sahip olacağınız anlamına
gelir.

## Etiket adlandırma kuralları {#tag-naming-conventions}

Herhangi bir dizeyi etiket olarak kullanabilseniz de, tutarlı bir adlandırma
kuralını takip etmek etiketlerinizin düzenli kalmasına yardımcı olur:

```swift
// Organize by feature
metadata: .metadata(tags: ["feature:authentication", "feature:payment"])

// Organize by team ownership
metadata: .metadata(tags: ["team:identity", "team:commerce"])

// Organize by architectural layer
metadata: .metadata(tags: ["layer:ui", "layer:business", "layer:data"])

// Organize by platform
metadata: .metadata(tags: ["platform:ios", "platform:macos"])

// Combine multiple dimensions
metadata: .metadata(tags: ["feature:auth", "team:identity", "layer:ui"])
```

`feature:`, `team:`, veya `layer:` gibi ön ekler kullanmak her bir etiketin
amacını anlamayı kolaylaştırır ve adlandırma çakışmalarını önler.

## Etiketleri proje açıklama yardımcıları ile kullanma {#using-tags-with-helpers}

Projenizde etiketlerin nasıl uygulanacağını standartlaştırmak için
<LocalizedLink href="/guides/features/projects/code-sharing">proje açıklama yardımcılarından</LocalizedLink> yararlanabilirsiniz:

```swift
// Tuist/ProjectDescriptionHelpers/Project+Templates.swift
import ProjectDescription

extension Target {
    public static func feature(
        name: String,
        team: String,
        dependencies: [TargetDependency] = []
    ) -> Target {
        .target(
            name: name,
            destinations: .iOS,
            product: .framework,
            bundleId: "com.example.\(name.lowercased())",
            sources: ["Sources/**"],
            dependencies: dependencies,
            metadata: .metadata(tags: [
                "feature:\(name.lowercased())",
                "team:\(team.lowercased())"
            ])
        )
    }
}
```

Sonra bunu manifestolarınızda kullanın:

```swift
import ProjectDescription
import ProjectDescriptionHelpers

let project = Project(
    name: "Features",
    targets: [
        .feature(name: "Authentication", team: "Identity"),
        .feature(name: "Payment", team: "Commerce"),
    ]
)
```

## Meta veri etiketlerini kullanmanın faydaları {#benefits}

### Geliştirilmiş geliştirme deneyimi

Projenizin belirli bölümlerine odaklanarak şunları yapabilirsiniz:

- **Xcode proje boyutunu azaltın** - Açılması ve gezinmesi daha hızlı olan daha
  küçük projelerle çalışın
- **Yapıları hızlandırın** - Yalnızca mevcut işiniz için ihtiyacınız olanı
  oluşturun
- **Odaklanmayı iyileştirin** - İlgisiz kodların dikkatinizi dağıtmasını önleyin
- **İndekslemeyi optimize edin** - Xcode daha az kod indeksleyerek otomatik
  tamamlamayı daha hızlı hale getirir

### Daha iyi proje organizasyonu

Etiketler kod tabanınızı düzenlemek için esnek bir yol sağlar:

- **Birden fazla boyut** - Hedefleri özellik, ekip, katman, platform veya başka
  bir boyuta göre etiketleyin
- **Yapısal değişiklik yok** - Dizin düzenini değiştirmeden organizasyonel yapı
  ekleyin
- **Kesişen kaygılar** - Tek bir hedef birden fazla mantıksal gruba ait olabilir

### Önbellekleme ile entegrasyon

Meta veri etiketleri <LocalizedLink href="/guides/features/cache">Tuist'in önbelleğe alma özellikleriyle</LocalizedLink> sorunsuz bir şekilde çalışır:

```bash
# Cache all targets
tuist cache

# Focus on targets with a specific tag and use cached dependencies
tuist generate tag:feature:payment
```

## En iyi uygulamalar {#best-practices}

1. **Basit başlayın** - Tek bir etiketleme boyutuyla başlayın (ör. özellikler)
   ve gerektiğinde genişletin
2. **Tutarlı olun** - Tüm manifestolarınızda aynı adlandırma kurallarını
   kullanın
3. **Etiketlerinizi belgeleyin** - Projenizin belgelerinde mevcut etiketlerin ve
   anlamlarının bir listesini tutun
4. **Yardımcıları kullanın** - Etiket uygulamasını standartlaştırmak için proje
   açıklama yardımcılarından yararlanın
5. **Periyodik olarak gözden geçirin** - Projeniz geliştikçe etiketleme
   stratejinizi gözden geçirin ve güncelleyin

## İlgili özellikler {#related-features}

- <LocalizedLink href="/guides/features/projects/code-sharing">Kod paylaşımı</LocalizedLink> - Etiket kullanımını standartlaştırmak için proje
  açıklama yardımcılarını kullanın
- <LocalizedLink href="/guides/features/cache">Önbellek</LocalizedLink> -
  Optimum derleme performansı için etiketleri önbelleğe alma ile birleştirin
- <LocalizedLink href="/guides/features/selective-testing">Seçmeli test</LocalizedLink> - Testleri yalnızca değiştirilen hedefler için çalıştırın
