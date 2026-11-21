---
{
  "title": "Sentetik dosyalar",
  "titleTemplate": ":title · Projeler · Özellikler · Kılavuzlar · Tuist",
  "description": "Tuist projelerindeki sentetik dosyalar hakkında bilgi edinin."
}
---
# Sentetik dosyalar {#synthesized-files}

Tuist, Xcode projelerini yönetirken ve üzerinde çalışırken kolaylık sağlamak amacıyla oluşturma sırasında dosya ve kod üretebilir. Bu sayfada bu işlevi ve projelerinizde nasıl kullanabileceğinizi öğreneceksiniz.

## Hedef kaynakları {#target-resources}

Xcode projeleri hedeflere kaynak eklemeyi destekler. Ancak bu durum, özellikle kaynakların ve kodun sıkça taşındığı modüler projelerde ekipler için bazı zorluklar doğurur:

- **Tutarlı olmayan çalışma zamanı erişimi**: Kaynakların nihai üründe nereye yerleştirildiği ve bunlara nasıl erişildiği hedefin ürün türüne bağlıdır. Örneğin, hedefiniz bir uygulamayı temsil ediyorsa kaynaklar uygulama paketine kopyalanır. Bu durum, paket yapısına ilişkin varsayımlar yapan ve kodun anlaşılmasını zorlaştıran, kaynakların taşınmasını güçleştiren bir kod yapısına yol açtığı için ideal değildir.
- **Kaynakları desteklemeyen ürünler**: Statik kütüphaneler gibi bazı ürün türleri paket değildir ve bu nedenle kaynakları desteklemez. Bu durumda, projenize veya uygulamanıza ek yük getirebilecek farklı bir ürün türüne, örneğin çerçevelere (frameworks) başvurmanız gerekir. Örneğin, statik çerçeveler nihai ürüne statik olarak bağlanır ve yalnızca kaynakların nihai ürüne kopyalanması için bir derleme aşaması gereklidir. Dinamik çerçevelerde ise Xcode hem ikili dosyayı hem de kaynakları nihai ürüne kopyalar; ancak çerçevenin dinamik olarak yüklenmesi gerektiğinden uygulamanızın başlangıç süresi artar.
- **Çalışma zamanı hatalarına yatkınlık**: Kaynaklar adları ve uzantıları (dizeler) ile tanımlanır. Bu nedenle, bunlardan herhangi birinde yapılan bir yazım hatası, kaynağa erişilmeye çalışıldığında çalışma zamanı hatasına yol açar. Bu durum derleme zamanında yakalanmadığı ve yayın sürümünde çökmelere neden olabileceği için ideal değildir.

Tuist, yukarıdaki sorunları **paketlere ve kaynaklara erişim için soyutlanmış, birleşik bir arayüz sentezleyerek** çözer.

> [!WARNING]
> **Önerilir**
>
> Kaynaklara Tuist tarafından sentezlenen arayüz üzerinden erişmek zorunlu olmasa da, kodun anlaşılmasını kolaylaştırdığı ve kaynakların taşınmasını basitleştirdiği için bunu öneriyoruz.


## Kaynaklar {#resources}

Tuist, `Info.plist` veya yetkiler gibi dosyaların içeriğini Swift içinde bildirmek için arayüzler sağlar. Bu, hedefler ve projeler arasında tutarlılığı sağlamaya ve derleme zamanında sorunları yakalamak için derleyiciden yararlanmaya yardımcı olur. İçeriği modellemek ve hedefler ile projeler arasında paylaşmak için kendi soyutlamalarınızı da oluşturabilirsiniz.

Projeniz oluşturulduğunda, Tuist bu dosyaların içeriğini sentezler ve bunları, kendilerini tanımlayan projeyi içeren dizine göreli `Derived` dizinine yazar.

> [!TIP]
> **Derived dizinini .gitignore’a ekleyin**
>
> Projenizin `.gitignore` dosyasına `Derived` dizinini eklemenizi öneririz.


## Paket erişimcileri {#bundle-accessors}

Tuist, hedef kaynaklarını içeren pakete erişim sağlayan bir arayüz sentezler.

### Swift {#swift}

Hedef, paketi ortaya çıkaran `Bundle` türünün bir uzantısını içerir:

```swift
let bundle = Bundle.module
```

### Objective-C {#objectivec}

Objective-C’de, pakete erişmek için `{Target}Resources` adlı bir arayüz elde edersiniz:

```objc
NSBundle *bundle = [MyFeatureResources bundle];
```

> [!WARNING]
> **Dahili hedeflerle ilgili sınırlama**
>
> Şu anda Tuist, yalnızca Objective-C kaynakları içeren dahili hedefler için kaynak paketi erişimcileri oluşturmaz. Bu, [#6456 numaralı sorun](https://github.com/tuist/tuist/issues/6456) altında izlenen bilinen bir sınırlamadır.


> [!TIP]
> **Kütüphanelerde paketler aracılığıyla kaynak desteği**
>
> Bir hedef ürünü, örneğin bir kütüphane, kaynakları desteklemiyorsa Tuist kaynakları `bundle` ürün türündeki bir hedefe dahil eder; böylece kaynaklar nihai üründe yer alır ve arayüz doğru paketi işaret eder. Bu sentezlenen paketler otomatik olarak `tuist:synthesized` etiketiyle işaretlenir ve üst hedeflerinden tüm etiketleri devralır; bu sayede bunları <.localized_link href="/guides/features/projects/metadata-tags#system-tags">önbellek profillerinde</.localized_link> hedefleyebilirsiniz.


## Kaynak erişimcileri {#resource-accessors}

Kaynaklar, dizeler kullanılarak ad ve uzantılarıyla tanımlanır. Bu durum derleme zamanında yakalanmadığı ve yayın sürümünde çökmelere neden olabileceği için ideal değildir. Bunu önlemek için Tuist, proje oluşturma sürecine [SwiftGen](https://github.com/SwiftGen/SwiftGen) entegre ederek kaynaklara erişim için bir arayüz sentezler. Bu sayede, derleyiciden yararlanarak herhangi bir sorunu güvenle yakalayabilir ve kaynaklara emin bir şekilde erişebilirsiniz.

Tuist, varsayılan olarak aşağıdaki kaynak türleri için erişimcileri sentezlemek üzere [şablonlar](https://github.com/tuist/tuist/tree/main/cli/Sources/TuistGenerator/Templates) içerir:

| Kaynak türü | Sentezlenen dosya |
| --- | ---- |
| Görseller ve renkler | `Assets+{Target}.swift` |
| Dizeler | `Strings+{Target}.swift` |
| Plist dosyaları | `{NameOfPlist}.swift` |
| Yazı tipleri | `Fonts+{Target}.swift` |
| Dosyalar | `Files+{Target}.swift` |

> Not: Proje seçeneklerine `disableSynthesizedResourceAccessors` seçeneğini geçirerek kaynak erişimcilerinin sentezlenmesini proje bazında devre dışı bırakabilirsiniz.

### Özel şablonlar {#custom-templates}

[SwiftGen](https://github.com/SwiftGen/SwiftGen) tarafından desteklenen diğer kaynak türleri için erişimcileri sentezlemek amacıyla kendi şablonlarınızı sağlamak istiyorsanız, bunları `Tuist/ResourceSynthesizers/{name}.stencil` konumunda oluşturabilirsiniz; burada ad, kaynağın camelCase biçimidir.

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

Erişimcileri sentezlemek istediğiniz kaynak türlerinin listesini yapılandırmak için, kullanmak istediğiniz kaynak sentezleyicilerinin listesini geçirerek `Project.resourceSynthesizers` özelliğini kullanabilirsiniz:

```swift
let project = Project(name: "App", resourceSynthesizers: [.strings(), .fonts()])
```

> [!NOTE]
> **Kaynak**
>
> Kaynaklara erişimcileri sentezlemek için özel şablonların nasıl kullanılacağını görmek üzere [bu örneği](https://github.com/tuist/tuist/tree/main/examples/xcode/generated_ios_app_with_templates) inceleyebilirsiniz.
