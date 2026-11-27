---
{
  "title": "Meta veri etiketleri",
  "titleTemplate": ":title · Projeler · Özellikler · Kılavuzlar · Tuist",
  "description": "Projenizin belirli bölümlerini organize etmek ve bunlara odaklanmak için hedef meta veri etiketlerini nasıl kullanacağınızı öğrenin"
}
---
# Meta veri etiketleri {#metadata-tags}

Projeler büyüdükçe ve karmaşıklıkları arttıkça, tüm kod tabanı ile aynı anda çalışmak verimsiz hale gelebilir. Tuist, hedefleri mantıksal gruplara ayırmanın ve geliştirme sırasında projenizin belirli bölümlerine odaklanmanın bir yolu olarak **meta veri etiketleri** sunar.

## Meta veri etiketleri nelerdir? {#what-are-metadata-tags}

Meta veri etiketleri, projenizdeki hedeflere ekleyebileceğiniz dize etiketleridir. Şunları yapmanızı sağlayan işaretçiler olarak hizmet ederler:

- **İlgili hedefleri gruplandırma** - Aynı özelliğe, ekibe veya mimari katmana ait hedefleri etiketleyin
- **Çalışma alanınıza odaklanma** - Yalnızca belirli etiketlere sahip hedefleri içeren projeler oluşturun
- **İş akışınızı optimize etme** - Kod tabanınızın ilgisiz kısımlarını yüklemeden belirli özellikler üzerinde çalışın
- **Kaynak olarak tutulacak hedefleri seçme** - Önbelleğe alırken hangi hedef grubunu kaynak olarak tutmak istediğinizi seçin

Etiketler, hedeflerdeki `metadata` özelliği kullanılarak tanımlanır ve bir dize dizisi olarak saklanır.

## Meta veri etiketlerini tanımlama {#defining-metadata-tags}

Proje manifest dosyanızdaki herhangi bir hedefe etiket ekleyebilirsiniz:

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

Hedeflerinizi etiketledikten sonra, yalnızca belirli hedefleri içeren odaklanmış bir proje oluşturmak için `tuist generate` komutunu kullanabilirsiniz:

### Etikete göre odaklanma

Belirli bir etiketle eşleşen tüm hedefleri içeren bir proje oluşturmak için `tag:` ön ekini kullanın:

```bash
# Generate project with all authentication-related targets
tuist generate tag:feature:auth

# Generate project with all targets owned by the identity team
tuist generate tag:team:identity
```

### İsme göre odaklanma

Belirli hedeflere isme göre de odaklanabilirsiniz:

```bash
# Generate project with the Authentication target
tuist generate Authentication
```

### Odaklanma nasıl çalışır

Hedeflere odaklandığınızda:

1. **Dahil edilen hedefler** - Sorgunuzla eşleşen hedefler oluşturulan projeye dahil edilir
2. **Bağımlılıklar** - Odaklanılan hedeflerin tüm bağımlılıkları otomatik olarak dahil edilir
3. **Test hedefleri** - Odaklanılan hedefler için test hedefleri dahil edilir
4. **Dışlama** - Diğer tüm hedefler çalışma alanından dışlanır

Bu, özelliğiniz üzerinde çalışmak için ihtiyacınız olanları içeren daha küçük ve yönetilebilir bir çalışma alanına sahip olduğunuz anlamına gelir.

## Etiket adlandırma kuralları {#tag-naming-conventions}

Etiket olarak herhangi bir dize kullanabilmenize rağmen, tutarlı bir adlandırma kuralı izlemek etiketlerinizi düzenli tutmanıza yardımcı olur:

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

`feature:`, `team:` veya `layer:` gibi ön ekler kullanmak, her bir etiketin amacını anlamayı ve adlandırma çakışmalarını önlemeyi kolaylaştırır.

## Sistem etiketleri {#system-tags}

Tuist, sistem tarafından yönetilen etiketler için `tuist:` ön ekini kullanır. Bu etiketler Tuist tarafından otomatik olarak uygulanır ve oluşturulan içeriğin belirli türlerini hedeflemek için önbellek profillerinde kullanılabilir.

### Kullanılabilir sistem etiketleri

| Etiket | Açıklama |
| --- | --- |
| `tuist:synthesized` | Statik kütüphanelerde ve statik çerçevelerde kaynak işleme için Tuist'in oluşturduğu sentezlenmiş paket hedeflerine uygulanır. Bu paketler, kaynak erişimci API'leri sağlamak amacıyla tarihsel nedenlerle mevcuttur. |

### Sistem etiketlerini önbellek profilleriyle kullanma

Sentezlenmiş hedefleri dahil etmek veya dışlamak için önbellek profillerinde sistem etiketlerini kullanabilirsiniz:

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

> [!TIP]
> **Sentezlenmiş paketler üst etiketleri miras alır**
>
> Sentezlenmiş paket hedefleri, `tuist:synthesized` etiketini almanın yanı sıra üst hedeflerinden gelen tüm etiketleri miras alır. Bu, statik bir kütüphaneyi `feature:auth` ile etiketlerseniz, sentezlenmiş kaynak paketinin hem `feature:auth` hem de `tuist:synthesized` etiketlerine sahip olacağı anlamına gelir.


## Proje açıklama yardımcılarını etiketlerle kullanma {#using-tags-with-helpers}

Etiketlerin projeniz genelinde nasıl uygulandığını standartlaştırmak için <.localized_link href="/guides/features/projects/code-sharing">proje açıklama yardımcılarını</.localized_link> kullanabilirsiniz:

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

Ardından bunu manifest dosyalarınızda kullanın:

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

- **Xcode proje boyutunu azaltın** - Açılması ve gezinmesi daha hızlı olan daha küçük projelerle çalışın
- **Derlemeleri hızlandırın** - Yalnızca mevcut işiniz için ihtiyaç duyduğunuz şeyleri derleyin
- **Odağı artırın** - İlgisiz koddan kaynaklanan dikkat dağıtıcı unsurlardan kaçının
- **Dizine eklemeyi optimize edin** - Xcode daha az kodu dizine ekler, bu da otomatik tamamlamayı hızlandırır

### Daha iyi proje organizasyonu

Etiketler, kod tabanınızı organize etmek için esnek bir yol sunar:

- **Çoklu boyutlar** - Hedefleri özelliğe, ekibe, katmana, platforma veya başka herhangi bir boyuta göre etiketleyin
- **Yapısal değişiklik yok** - Dizin düzenini değiştirmeden organizasyonel yapı ekleyin
- **Kesimsel kaygılar** - Tek bir hedef birden fazla mantıksal gruba ait olabilir

### Önbellekleme ile entegrasyon

Meta veri etiketleri <.localized_link href="/guides/features/cache">Tuist'in önbellekleme özellikleriyle</.localized_link> sorunsuz çalışır:

```bash
# Cache all targets
tuist cache

# Focus on targets with a specific tag and use cached dependencies
tuist generate tag:feature:payment
```

## En iyi uygulamalar {#best-practices}

1. **Basit başlayın** - Tek bir etiketleme boyutuyla (örneğin, özellikler) başlayın ve gerektiğinde genişletin
2. **Tutarlı olun** - Tüm manifest dosyalarınızda aynı adlandırma kurallarını kullanın
3. **Etiketlerinizi belgeleyin** - Projenizin belgelerinde mevcut etiketlerin ve anlamlarının listesini tutun
4. **Yardımcıları kullanın** - Etiket uygulamasını standartlaştırmak için proje açıklama yardımcılarını kullanın
5. **Periyodik olarak gözden geçirin** - Projeniz geliştikçe etiketleme stratejinizi gözden geçirin ve güncelleyin

## İlgili özellikler {#related-features}

- <.localized_link href="/guides/features/projects/code-sharing">Kod paylaşımı</.localized_link> - Etiket kullanımını standartlaştırmak için proje açıklama yardımcılarını kullanın
- <.localized_link href="/guides/features/cache">Önbellek</.localized_link> - Optimum derleme performansı için etiketleri önbellekleme ile birleştirin
- <.localized_link href="/guides/features/selective-testing">Seçici test</.localized_link> - Testleri yalnızca değişen hedefler için çalıştırın
