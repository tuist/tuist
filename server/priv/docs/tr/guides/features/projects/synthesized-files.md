---
{
  "title": "Oluşturulan dosyalar",
  "titleTemplate": ":title · Projeler · Özellikler · Kılavuzlar · Tuist",
  "description": "Tuist projelerinde oluşturulan dosyalar hakkında bilgi edinin."
}
---
# Oluşturulan dosyalar {#synthesized-files}

Tuist, Xcode projelerini yönetirken ve üzerinde çalışırken kolaylık sağlamak amacıyla oluşturma sırasında dosya ve kod üretebilir. Bu sayfada bu işlevselliği ve projelerinizde nasıl kullanabileceğinizi öğreneceksiniz.

## Hedef kaynakları {#target-resources}

Xcode projeleri hedeflere kaynak eklemeyi destekler. Ancak özellikle kaynakların ve kodun sıkça yer değiştirdiği modüler projelerde ekipler için bazı zorluklar ortaya çıkar:

- **Tutarsız çalışma zamanı erişimi**: Kaynakların nihai üründe nereye yerleştiği ve bunlara nasıl erişildiğiniz hedefin ürün türüne bağlıdır. Örneğin, hedefiniz bir uygulamayı temsil ediyorsa kaynaklar uygulama paketinin içine kopyalanır. Bu durum, kaynaklara erişen kodun paket yapısı hakkında varsayımlar yapmasına yol açar; bu da kodun anlaşılmasını zorlaştırır ve kaynakların taşınmasını güçleştirir, dolayısıyla ideal değildir.
- **Kaynakları desteklemeyen ürünler**: Statik kütüphaneler gibi bazı ürün türleri paket değildir ve bu nedenle kaynakları desteklemez. Bu yüzden projenize veya uygulamanıza ek yük getirebilecek farklı bir ürün türüne, örneğin çerçevelere (framework) başvurmanız gerekebilir. Örneğin statik çerçeveler nihai ürüne statik olarak bağlanır ve kaynakların yalnızca nihai ürüne kopyalanması için bir derleme aşaması gerekir. Dinamik çerçevelerde ise Xcode hem ikili dosyayı hem de kaynakları nihai ürüne kopyalar; ancak çerçevenin dinamik olarak yüklenmesi gerektiğinden uygulamanızın başlangıç süresi artar.
- **Çalışma zamanı hatalarına yatkınlık**: Kaynaklar adları ve uzantıları (dizeler) ile tanımlanır. Bu nedenle herhangi birinde yapılan bir yazım hatası, kaynağa erişmeye çalışıldığında çalışma zamanı hatasına yol açar. Derleme zamanında yakalanmaması ve yayınlamada çökmelere neden olabilmesi nedeniyle bu durum ideal değildir.

Tuist, yukarıdaki sorunları **paketlere ve kaynaklara erişim için tek bir arayüz sentezleyerek** ve uygulama ayrıntılarını soyutlayarak çözer.

> [!WARNING]
> **Önerilir**
>
> Kaynaklara Tuist tarafından sentezlenen arayüz üzerinden erişmek zorunlu olmasa da, kodun anlaşılmasını kolaylaştırdığı ve kaynakların taşınmasını basitleştirdiği için bunu öneriyoruz.


## Kaynaklar {#resources}

Tuist, `Info.plist` veya yetkilendirmeler gibi dosyaların içeriğini Swift ile bildirmek için arayüzler sağlar. Bu, hedefler ve projeler arasında tutarlılığı sağlamaya ve derleme zamanında sorunları yakalamak için derleyiciden yararlanmaya yardımcı olur. İçeriği modellemek ve bunu hedefler ve projeler arasında paylaşmak için kendi soyutlamalarınızı da oluşturabilirsiniz.

Projeniz oluşturulduğunda Tuist, bu dosyaların içeriğini sentezler ve bunları, kendilerini tanımlayan projeyi içeren dizine göreli olarak `Derived` dizinine yazar.

> [!TIP]
> **Derived dizinini .gitignore’a ekleyin**
>
> Projenizin `.gitignore` dosyasına `Derived` dizinini eklemenizi öneririz.


## Paket erişimcileri {#bundle-accessors}

Tuist, hedef kaynaklarını içeren pakete erişim için bir arayüz sentezler.

### Swift {#swift}

Hedef, paketi dışa aktaran `Bundle` türünün bir uzantısını içerir:

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
> Şu anda Tuist, yalnızca Objective-C kaynakları içeren dahili hedefler için kaynak paketi erişimcileri oluşturmaz. Bu, [#6456 numaralı sorunda](https://github.com/tuist/tuist/issues/6456) izlenen bilinen bir sınırlamadır.


> [!TIP]
> **Kütüphanelerde paketler aracılığıyla kaynak desteği**
>
> Bir hedef ürünü, örneğin bir kütüphane, kaynakları desteklemiyorsa Tuist kaynakları `bundle` ürün türüne sahip bir hedefe dahil eder; böylece kaynakların nihai üründe yer alması ve arayüzün doğru paketi işaret etmesi sağlanır. Bu sentezlenen paketler otomatik olarak `tuist:synthesized` etiketiyle işaretlenir ve üst hedeflerinden tüm etiketleri devralır; bu sayede bunları <.localized_link href="/guides/features/projects/metadata-tags#system-tags">önbellek profillerinde</.localized_link> hedefleyebilirsiniz.


## Kaynak erişimcileri {#resource-accessors}

Kaynaklar, dizeler kullanılarak ad ve uzantılarıyla tanımlanır. Bu durum derleme zamanında yakalanmadığı ve yayınlamada çökmelere yol açabildiği için ideal değildir. Bunu önlemek için Tuist, kaynaklara erişim için bir arayüz sentezlemek üzere [SwiftGen](https://github.com/SwiftGen/SwiftGen) entegrasyonunu proje oluşturma sürecine dahil eder. Bu sayede derleyiciden yararlanarak herhangi bir sorunu güvenle yakalayabilir ve kaynaklara emin bir şekilde erişebilirsiniz.

Tuist, varsayılan olarak aşağıdaki kaynak türleri için erişimciler sentezlemek üzere [şablonlar](https://github.com/tuist/tuist/tree/main/cli/Sources/TuistGenerator/Templates) içerir:

| Kaynak türü | Sentezlenen dosya |
| --- | ---- |
| Görseller ve renkler | `Assets+{Target}.swift` |
| Dizeler | `Strings+{Target}.swift` |
| Plist dosyaları | `{NameOfPlist}.swift` |
| Yazı tipleri | `Fonts+{Target}.swift` |
| Dosyalar | `Files+{Target}.swift` |

> Not: Proje seçeneklerine `disableSynthesizedResourceAccessors` seçeneğini geçirerek kaynak erişimcilerinin sentezlenmesini proje bazında devre dışı bırakabilirsiniz.

### Özel şablonlar {#custom-templates}

Diğer kaynak türleri için erişimciler sentezlemek amacıyla kendi şablonlarınızı sağlamak isterseniz ([SwiftGen](https://github.com/SwiftGen/SwiftGen) tarafından desteklenmelidir), bunları `Tuist/ResourceSynthesizers/{name}.stencil` konumunda oluşturabilirsiniz; burada ad, kaynağın camelCase biçimidir.

| Kaynak | Şablon adı |
| --- | --- |
| dizeler | `Strings.stencil` |
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
> **Kaynak**
>
> Kaynaklara erişimciler sentezlemek için özel şablonların nasıl kullanılacağını gösteren bir örnek için [bu örneğe](https://github.com/tuist/tuist/tree/main/examples/xcode/generated_ios_app_with_templates) göz atabilirsiniz.
