---
{
  "title": "Sentetik dosyalar",
  "titleTemplate": ":title · Projeler · Özellikler · Kılavuzlar · Tuist",
  "description": "Tuist projelerindeki sentetik dosyalar hakkında bilgi edinin."
}
---
# Oluşturulan dosyalar {#synthesized-files}

Tuist, Xcode projelerini yönetirken ve üzerinde çalışırken kolaylık sağlamak amacıyla oluşturma sırasında dosya ve kod üretebilir. Bu sayfada bu işlevi ve projelerinizde nasıl kullanabileceğinizi öğreneceksiniz.

## Hedef kaynakları {#target-resources}

Xcode projeleri hedeflere kaynak eklemeyi destekler. Ancak özellikle kaynakların ve dosyaların sıkça yer değiştirdiği modüler projelerde ekipler için bazı zorluklar ortaya çıkar:

- **Tutarsız çalışma zamanı erişimi**: Kaynakların nihai üründe nereye yerleştirildiği ve bunlara nasıl erişildiği hedefin ürün türüne bağlıdır. Örneğin hedefiniz bir uygulamayı temsil ediyorsa kaynaklar uygulama paketine kopyalanır. Bu durum, paket yapısı hakkında varsayımlar yapan ve kodun anlaşılmasını zorlaştıran, kaynakların taşınmasını güçleştiren bir erişim biçimine yol açar ki bu ideal değildir.
- **Kaynakları desteklemeyen ürünler**: Statik kütüphaneler gibi bazı ürün türleri paket değildir ve dolayısıyla kaynakları desteklemez. Bu nedenle projenize veya uygulamanıza ek yük getirebilecek farklı bir ürün türüne, örneğin çerçevelere başvurmanız gerekebilir. Örneğin statik çerçeveler nihai ürüne statik olarak bağlanır ve yalnızca kaynakların nihai ürüne kopyalanması için bir derleme aşaması gerekir. Dinamik çerçevelerde ise Xcode hem ikili dosyayı hem de kaynakları nihai ürüne kopyalar; ancak çerçevenin dinamik olarak yüklenmesi gerektiğinden uygulamanızın başlangıç süresi artar.
- **Çalışma zamanı hatalarına yatkın**: Kaynaklar ad ve uzantılarıyla (dizgeler) tanımlanır. Bu değerlerden herhangi birinde yazım hatası olması, kaynağa erişilmeye çalışıldığında çalışma zamanı hatasına yol açar. Derleme zamanında yakalanmaması ve yayında çökmelere neden olabilmesi nedeniyle bu durum ideal değildir.

Tuist, yukarıdaki sorunları uygulama ayrıntılarını soyutlayan **kaynaklara ve paketlere erişim için birleşik bir arayüz oluşturarak** çözer.

> [!WARNING]
> **Önerilir**
>
> Kaynaklara Tuist tarafından oluşturulan arayüz üzerinden erişmek zorunlu olmasa da kodun anlaşılmasını kolaylaştırdığı ve kaynakların taşınmasını basitleştirdiği için bunu öneriyoruz.


## Kaynaklar {#resources}

Tuist, `Info.plist` veya yetki dosyaları gibi dosyaların içeriğini Swift ile bildirmek için arayüzler sağlar. Bu, hedefler ve projeler arasında tutarlılığı güvence altına almak ve derleme zamanında sorunları yakalamak için derleyiciden yararlanmak açısından faydalıdır. İçeriği modellemek ve hedefler ile projeler arasında paylaşmak için kendi soyutlamalarınızı da geliştirebilirsiniz.

Projeniz oluşturulduğunda Tuist, bu dosyaların içeriğini sentezleyerek onları tanımlandıkları projeyi içeren dizine göreli `Derived` dizinine yazar.

> [!TIP]
> **Derived dizinini .gitignore’a ekleyin**
>
> Projenizin `.gitignore` dosyasına `Derived` dizinini eklemenizi öneririz.


## Paket erişimcileri {#bundle-accessors}

Tuist, hedef kaynaklarını içeren pakete erişim için bir arayüz oluşturur.

### Swift {#swift}

Hedef, paketi sunan `Bundle` türünün bir uzantısını içerir:

```swift
let bundle = Bundle.module
```

### Objective-C {#objectivec}

Objective-C’de pakete erişmek için `{Target}Resources` adlı bir arayüz elde edersiniz:

```objc
NSBundle *bundle = [MyFeatureResources bundle];
```

> [!WARNING]
> **Dahili hedeflerle ilgili sınırlama**
>
> Şu anda Tuist, yalnızca Objective-C kaynakları içeren dahili hedefler için kaynak paketi erişimcileri oluşturmaz. Bu bilinen bir sınırlamadır ve [#6456 numaralı sorun](https://github.com/tuist/tuist/issues/6456) kapsamında takip edilmektedir.


> [!TIP]
> **Kütüphanelerde paketler aracılığıyla kaynak desteği**
>
> Bir hedefin ürünü, örneğin bir kütüphane, kaynakları desteklemiyorsa Tuist kaynakları `bundle` ürün türündeki bir hedefe dahil ederek bunların nihai üründe yer almasını ve arayüzün doğru paketi işaret etmesini sağlar. Bu şekilde oluşturulan paketler otomatik olarak `tuist:synthesized` etiketiyle işaretlenir ve üst hedeflerinden tüm etiketleri miras alır; böylece bunları <.localized_link href="/guides/features/projects/metadata-tags#system-tags">önbellek profillerinde</.localized_link> hedefleyebilirsiniz.


## Kaynak erişimcileri {#resource-accessors}

Kaynaklar ad ve uzantılarıyla dizgeler kullanılarak tanımlanır. Bu yaklaşım derleme zamanında yakalanmadığı ve yayında çökmelere yol açabildiği için ideal değildir. Bunu önlemek için Tuist, proje oluşturma sürecine [SwiftGen](https://github.com/SwiftGen/SwiftGen) entegre ederek kaynaklara erişim için bir arayüz sentezler. Bu sayede derleyiciden yararlanarak sorunları güvenle yakalayabilir ve kaynaklara emin adımlarla erişebilirsiniz.

Tuist, varsayılan olarak aşağıdaki kaynak türleri için erişimciler sentezlemek üzere [şablonlar](https://github.com/tuist/tuist/tree/main/cli/Sources/TuistGenerator/Templates) içerir:

| Kaynak türü | Oluşturulan dosya |
| --- | ---- |
| Görseller ve renkler | `Assets+{Target}.swift` |
| Dizgeler | `Strings+{Target}.swift` |
| Plist dosyaları | `{NameOfPlist}.swift` |
| Yazı tipleri | `Fonts+{Target}.swift` |
| Dosyalar | `Files+{Target}.swift` |

> Not: Proje seçeneklerine `disableSynthesizedResourceAccessors` seçeneğini geçirerek kaynak erişimcilerinin sentezlenmesini proje bazında devre dışı bırakabilirsiniz.

### Özel şablonlar {#custom-templates}

[SwiftGen](https://github.com/SwiftGen/SwiftGen) tarafından desteklenen diğer kaynak türleri için erişimciler sentezlemek amacıyla kendi şablonlarınızı sağlamak isterseniz bunları `Tuist/ResourceSynthesizers/{name}.stencil` konumunda oluşturabilirsiniz; burada ad, kaynağın camelCase biçimidir.

| Kaynak | Şablon adı |
| --- | --- |
| dizgeler | `Strings.stencil` |
| varlıklar | `Assets.stencil` |
| plist dosyaları | `Plists.stencil` |
| yazı tipleri | `Fonts.stencil` |
| coreData | `CoreData.stencil` |
| interfaceBuilder | `InterfaceBuilder.stencil` |
| json | `JSON.stencil` |
| yaml | `YAML.stencil` |
| dosyalar | `Files.stencil` |

Erişimciler sentezlenecek kaynak türlerinin listesini yapılandırmak isterseniz, kullanmak istediğiniz kaynak sentezleyicilerinin listesini geçirerek `Project.resourceSynthesizers` özelliğini kullanabilirsiniz:

```swift
let project = Project(name: "App", resourceSynthesizers: [.strings(), .fonts()])
```

> [!NOTE]
> **Kaynakça**
>
> Kaynaklara erişim sentezlemek için özel şablonların nasıl kullanılacağını görmek üzere [bu örneğe](https://github.com/tuist/tuist/tree/main/examples/xcode/generated_ios_app_with_templates) göz atabilirsiniz.
