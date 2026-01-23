---
{
  "title": "Metadata tags",
  "titleTemplate": ":title · Projects · Features · Guides · Tuist",
  "description": "Learn how to use target metadata tags to organize and focus on specific parts of your project"
}
---
# Meta veri etiketleri {#metadata-tags}

Projeler büyüdükçe ve karmaşıklaştıkça, tüm kod tabanını aynı anda çalışmak
verimsiz hale gelebilir. Tuist, hedefleri mantıksal gruplar halinde düzenlemek
ve geliştirme sırasında projenizin belirli kısımlarına odaklanmak için **meta
veri etiketleri** sağlar.

## Meta veri etiketleri nedir? {#what-are-metadata-tags}

Meta veri etiketleri, projenizdeki hedeflere ekleyebileceğiniz dize
etiketleridir. Aşağıdakileri yapmanızı sağlayan işaretler görevi görürler:

- **İlgili hedefleri gruplandırın** - Aynı özelliğe, ekibe veya mimari katmana
  ait hedefleri etiketleyin
- **Çalışma alanınıza odaklanın** - Yalnızca belirli etiketlere sahip hedefleri
  içeren projeler oluşturun
- **** ile iş akışınızı optimize edin - Kod tabanınızın ilgisiz kısımlarını
  yüklemeden belirli özellikler üzerinde çalışın
- **Kaynak olarak saklanacak hedefleri seçin** - Önbelleğe alırken kaynak olarak
  saklamak istediğiniz hedef grubunu seçin

Etiketler, hedeflerdeki `meta verisi` özelliği kullanılarak tanımlanır ve bir
dizi dizesi olarak saklanır.

## Meta veri etiketlerini tanımlama {#defining-metadata-tags}

Proje manifestosundaki herhangi bir hedefe etiket ekleyebilirsiniz:

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

## Etiketli hedeflere odaklanma {#focusing-on-tagged-targets}

Hedeflerinizi etiketledikten sonra, `tuist generate` komutunu kullanarak
yalnızca belirli hedefleri içeren odaklanmış bir proje oluşturabilirsiniz:

### Etikete göre odaklanma

`etiketini kullanın:` önekini kullanarak belirli bir etiketle eşleşen tüm
hedefleri içeren bir proje oluşturun:

```bash
# Generate project with all authentication-related targets
tuist generate tag:feature:auth

# Generate project with all targets owned by the identity team
tuist generate tag:team:identity
```

### Adına göre odaklan

Ayrıca, isme göre belirli hedeflere odaklanabilirsiniz:

```bash
# Generate project with the Authentication target
tuist generate Authentication
```

### Odaklama nasıl çalışır?

Hedeflere odaklandığınızda:

1. **Dahil edilen hedefler** - Sorgunuzla eşleşen hedefler, oluşturulmuş projede
   yer almaktadır.
2. **Bağımlılıklar** - Odaklanılan hedeflerin tüm bağımlılıkları otomatik olarak
   dahil edilir.
3. **Test hedefleri** - Odaklanan hedefler için test hedefleri dahil edilmiştir
4. **Hariç tutma** - Diğer tüm hedefler çalışma alanından hariç tutulur.

Bu, yalnızca özelliğiniz üzerinde çalışmak için ihtiyacınız olanları içeren daha
küçük ve daha yönetilebilir bir çalışma alanı elde edeceğiniz anlamına gelir.

## Etiket adlandırma kuralları {#tag-naming-conventions}

Herhangi bir dizeyi etiket olarak kullanabilirsiniz, ancak tutarlı bir
adlandırma kuralı izlemek etiketlerinizi düzenli tutmanıza yardımcı olur:

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

`özelliği:`, `ekibi:` veya `katman:` gibi önekler kullanmak, her bir etiketin
amacını anlamayı kolaylaştırır ve adlandırma çakışmalarını önler.

## Sistem etiketleri {#system-tags}

Tuist, sistem tarafından yönetilen etiketler için `tuist:` önekini kullanır. Bu
etiketler Tuist tarafından otomatik olarak uygulanır ve belirli türde
oluşturulan içeriği hedeflemek için önbellek profillerinde kullanılabilir.

### Kullanılabilir sistem etiketleri

| Etiket              | Açıklama                                                                                                                                                                                                          |
| ------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `tuist:synthesized` | Tuist'in statik kütüphanelerde ve statik çerçevelerde kaynak yönetimi için oluşturduğu sentezlenmiş paket hedeflerine uygulanır. Bu paketler, kaynak erişim API'leri sağlamak için tarihsel nedenlerle mevcuttur. |

### Önbellek profilleriyle sistem etiketlerini kullanma

Önbellek profillerinde sistem etiketlerini kullanarak sentezlenmiş hedefleri
dahil edebilir veya hariç tutabilirsiniz:

```swift
import ProjectDescription

let tuist = Tuist(
    project: .tuist(
        cacheOptions: .options(
            profiles: .profiles(
                [
                    "development": .profile(
                        .onlyExternal,
                        and: ["tag:tuist:synthesized"]  // Also cache synthesized bundles
                    )
                ],
                default: .onlyExternal
            )
        )
    )
)
```

::: tip SYNTHESIZED BUNDLES INHERIT PARENT TAGS
<!-- -->
Sentezlenmiş paket hedefleri, `tuist:synthesized` etiketini almanın yanı sıra,
üst hedeflerinden tüm etiketleri devralır. Bu, bir statik kütüphaneyi
`feature:auth` ile etiketlerseniz, sentezlenmiş kaynak paketinin hem
`feature:auth` hem de `tuist:synthesized` etiketlerine sahip olacağı anlamına
gelir.
<!-- -->
:::

## Proje açıklaması yardımcılarıyla etiketleri kullanma {#using-tags-with-helpers}

<LocalizedLink href="/guides/features/projects/code-sharing">proje açıklaması
yardımcıları</LocalizedLink> kullanarak, projenizde etiketlerin nasıl
uygulanacağını standart hale getirebilirsiniz:

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

Ardından bunu manifestolarınızda kullanın:

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

## Meta veri etiketlerini kullanmanın avantajları {#benefits}

### Geliştirme deneyimi iyileştirildi

Projenizin belirli kısımlarına odaklanarak şunları yapabilirsiniz:

- **Xcode proje boyutunu azaltın** - Açılması ve gezinmesi daha hızlı olan daha
  küçük projelerle çalışın
- **** 'da derlemeleri hızlandırın - Yalnızca mevcut çalışmanız için gerekli
  olanları derleyin
- **** 'da odaklanmayı geliştirin - İlgisiz kodlardan kaynaklanan dikkat
  dağınıklığını önleyin
- **** 'da indekslemeyi optimize edin - Xcode daha az kod indeksler, böylece
  otomatik tamamlama daha hızlı olur

### Daha iyi proje organizasyonu

Etiketler, kod tabanınızı düzenlemek için esnek bir yol sağlar:

- **Çoklu boyutlar** - Hedefleri özellik, ekip, katman, platform veya başka
  herhangi bir boyuta göre etiketleyin.
- **Yapısal değişiklik yok** - Dizin düzenini değiştirmeden organizasyon
  yapısını ekleyin
- **Çapraz kesen konular** - Tek bir hedef birden fazla mantıksal gruba ait
  olabilir

### Önbellekleme ile entegrasyon

Meta veri etiketleri, <LocalizedLink href="/guides/features/cache">Tuist'in
önbellek özellikleriyle</LocalizedLink> sorunsuz bir şekilde çalışır:

```bash
# Cache all targets
tuist cache

# Focus on targets with a specific tag and use cached dependencies
tuist generate tag:feature:payment
```

## En iyi uygulamalar {#best-practices}

1. **Basit başlayın** - Tek bir etiketleme boyutu (ör. özellikler) ile başlayın
   ve gerektiğinde genişletin.
2. **Tutarlı olun** - Tüm manifestolarınızda aynı adlandırma kurallarını
   kullanın
3. **Etiketlerinizi belgelendirin** - Projenizin belgelerinde kullanılabilir
   etiketlerin ve anlamlarının bir listesini tutun.
4. **Yardımcıları kullanın** - Etiket uygulamasını standartlaştırmak için proje
   açıklaması yardımcılarını kullanın
5. **** 'yi düzenli olarak gözden geçirin - Projeniz geliştikçe, etiketleme
   stratejinizi gözden geçirin ve güncelleyin

## İlgili özellikler {#related-features}

- <LocalizedLink href="/guides/features/projects/code-sharing">Kod
  paylaşımı</LocalizedLink> - Etiket kullanımını standartlaştırmak için proje
  açıklaması yardımcılarını kullanın.
- <LocalizedLink href="/guides/features/cache">Önbellek</LocalizedLink> - En iyi
  derleme performansı için etiketleri önbellekleme ile birleştirin
- <LocalizedLink href="/guides/features/selective-testing">Seçmeli
  test</LocalizedLink> - Yalnızca değiştirilen hedefler için testler çalıştırın
