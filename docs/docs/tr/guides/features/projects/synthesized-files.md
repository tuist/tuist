---
{
  "title": "Synthesized files",
  "titleTemplate": ":title · Projects · Features · Guides · Tuist",
  "description": "Learn about synthesized files in Tuist projects."
}
---
# Sentezlenmiş dosyalar {#synthesized-files}

Tuist, Xcode projelerini yönetmeyi ve bunlarla çalışmayı kolaylaştırmak için
oluşturma sırasında dosyalar ve kodlar oluşturabilir. Bu sayfada, bu işlevsellik
ve projelerinizde nasıl kullanabileceğiniz hakkında bilgi edineceksiniz.

## Hedef kaynaklar {#target-resources}

Xcode projeleri, hedeflere kaynak eklemeyi destekler. Ancak, özellikle
kaynakların ve kaynakların sık sık taşındığı modüler projelerde çalışırken,
ekiplere bazı zorluklar çıkarır:

- **Tutarsız çalışma zamanı erişimi**: Kaynakların nihai üründe nereye
  yerleştirileceği ve bunlara nasıl erişileceği, hedef ürüne bağlıdır. Örneğin,
  hedefiniz bir uygulamayı temsil ediyorsa, kaynaklar uygulama paketine
  kopyalanır. Bu, kaynaklara erişen kodun paket yapısı hakkında varsayımlarda
  bulunmasına neden olur. Bu durum, kodun anlaşılmasını ve kaynakların
  taşınmasını zorlaştırdığı için ideal değildir.
- **Kaynakları desteklemeyen ürünler**: Statik kütüphaneler gibi, paket olmayan
  ve bu nedenle kaynakları desteklemeyen belirli ürünler vardır. Bu nedenle,
  projenize veya uygulamanıza ek yük getirebilecek farklı bir ürün türüne,
  örneğin çerçevelere başvurmanız gerekir. Örneğin, statik çerçeveler nihai
  ürüne statik olarak bağlanacak ve kaynakları nihai ürüne kopyalamak için bir
  derleme aşaması gerekecektir. Ya da dinamik çerçevelerde, Xcode hem ikili
  dosyayı hem de kaynakları nihai ürüne kopyalayacaktır, ancak çerçevenin
  dinamik olarak yüklenmesi gerektiğinden uygulamanızın başlatma süresi
  artacaktır.
- **Çalışma zamanı hatalarına yatkın**: Kaynaklar, adları ve uzantıları
  (diziler) ile tanımlanır. Bu nedenle, bunlardan herhangi birinde yazım hatası
  olması, kaynağa erişmeye çalışırken çalışma zamanı hatasına yol açar. Bu,
  derleme sırasında yakalanmadığı ve sürümde çökmelere yol açabileceği için
  ideal değildir.

Tuist, **'ı kullanarak yukarıdaki sorunları çözer ve uygulama ayrıntılarını
soyutlayan, paketlere ve kaynaklara erişmek için birleşik bir arayüz
oluşturur**.

::: warning RECOMMENDED
<!-- -->
Tuist tarafından sentezlenen arayüz üzerinden kaynaklara erişmek zorunlu olmasa
da, kodun anlaşılmasını ve kaynakların taşınmasını kolaylaştırdığı için bunu
öneririz.
<!-- -->
:::

## Kaynaklar {#resources}

Tuist, `Info.plist` gibi dosyaların içeriğini veya Swift'teki yetkileri beyan
etmek için arayüzler sağlar. Bu, hedefler ve projeler arasında tutarlılığı
sağlamak ve derleme sırasında sorunları yakalamak için derleyiciyi kullanmak
açısından yararlıdır. Ayrıca, içeriği modellemek ve hedefler ve projeler
arasında paylaşmak için kendi soyutlamalarınızı da oluşturabilirsiniz.

Projeniz oluşturulduğunda, Tuist bu dosyaların içeriğini sentezleyecek ve
bunları tanımlayan projeyi içeren dizine göre `Derived` dizinine yazacaktır.

::: tip GITIGNORE THE DERIVED DIRECTORY
<!-- -->
`'un Derived` dizinini projenizin `.gitignore` dosyasına eklemenizi öneririz.
<!-- -->
:::

## Paket erişimcileri {#bundle-accessors}

Tuist, hedef kaynakları içeren pakete erişmek için bir arayüz oluşturur.

### Swift {#swift}

Hedef, paketi ortaya çıkaran `Bundle` türünde bir uzantı içerecektir:

```swift
let bundle = Bundle.module
```

### Objective-C {#objectivec}

Objective-C'de, pakete erişmek için bir arayüz elde edersiniz
`{Target}Resources`:

```objc
NSBundle *bundle = [MyFeatureResources bundle];
```

::: warning LIMITATION WITH INTERNAL TARGETS
<!-- -->
Şu anda Tuist, yalnızca Objective-C kaynakları içeren dahili hedefler için
kaynak paketi erişimcileri oluşturmamaktadır. Bu, [sorun
#6456](https://github.com/tuist/tuist/issues/6456) numaralı bilinen bir
sınırlamadır.
<!-- -->
:::

::: tip SUPPORTING RESOURCES IN LIBRARIES THROUGH BUNDLES
<!-- -->
Hedef ürün, örneğin bir kütüphane, kaynakları desteklemiyorsa, Tuist kaynakları
ürün türü `bundle` hedefine dahil ederek, bunların nihai ürüne eklenmesini ve
arayüzün doğru pakete yönlendirilmesini sağlar. Bu sentezlenmiş paketler
otomatik olarak `tuist:synthesized` ile etiketlenir ve ana hedeflerinden tüm
etiketleri devralır, böylece bunları
<LocalizedLink href="/guides/features/projects/metadata-tags#system-tags">cache
profiles</LocalizedLink> içinde hedefleyebilirsiniz.
<!-- -->
:::

## Kaynak erişimcileri {#resource-accessors}

Kaynaklar, dizeler kullanılarak adları ve uzantıları ile tanımlanır. Bu ideal
bir durum değildir, çünkü derleme sırasında yakalanmaz ve sürümde çökmelere
neden olabilir. Bunu önlemek için Tuist, kaynaklara erişmek için bir arayüz
oluşturmak üzere [SwiftGen](https://github.com/SwiftGen/SwiftGen) projesini
proje oluşturma sürecine entegre eder. Bu sayede, derleyiciyi kullanarak
herhangi bir sorunu yakalayarak kaynaklara güvenle erişebilirsiniz.

Tuist, varsayılan olarak aşağıdaki kaynak türleri için erişimcileri sentezlemek
üzere
[şablonlar](https://github.com/tuist/tuist/tree/main/Sources/TuistGenerator/Templates)
içerir:

| Kaynak türü           | Sentezlenmiş dosyalar     |
| --------------------- | ------------------------- |
| Görüntüler ve renkler | `Assets+{Hedef}.swift`    |
| Diziler               | `Strings+{Target}.swift`  |
| Plistler              | `{NameOfPlist}.swift`     |
| Yazı tipleri          | `Fonts+{Target}.swift`    |
| Dosyalar              | `Dosyaları+{Hedef}.swift` |

> Not: `disableSynthesizedResourceAccessors` seçeneğini proje seçeneklerine
> aktararak, proje bazında kaynak erişimcilerin sentezlenmesini devre dışı
> bırakabilirsiniz.

#### Özel şablonlar {#custom-templates}

[SwiftGen](https://github.com/SwiftGen/SwiftGen) tarafından desteklenmesi
gereken diğer kaynak türlerine erişim sağlayıcıları sentezlemek için kendi
şablonlarınızı sağlamak istiyorsanız, bunları
`Tuist/ResourceSynthesizers/{name}.stencil` adresinde oluşturabilirsiniz. Burada
name, kaynağın camel-case versiyonudur.

| Kaynaklar        | Şablon adı                 |
| ---------------- | -------------------------- |
| diziler          | `Strings.stencil`          |
| varlıklar        | `Assets.stencil`           |
| plists           | `Plists.stencil`           |
| yazı tipleri     | `Fonts.stencil`            |
| coreData         | `CoreData.stencil`         |
| interfaceBuilder | `InterfaceBuilder.stencil` |
| json             | `JSON.stencil`             |
| yaml             | `YAML.stencil`             |
| dosyaları        | `Files.stencil`            |

Erişimcileri sentezlemek için kaynak türleri listesini yapılandırmak
istiyorsanız, `Project.resourceSynthesizers` özelliğini kullanarak kullanmak
istediğiniz kaynak sentezleyicilerin listesini geçebilirsiniz:

```swift
let project = Project(resourceSynthesizers: [.string(), .fonts()])
```

::: info REFERENCE
<!-- -->
Kaynaklara erişim sağlayıcıları sentezlemek için özel şablonların nasıl
kullanıldığına dair bir örnek görmek için [bu
örneği](https://github.com/tuist/tuist/tree/main/examples/xcode/generated_ios_app_with_templates)
inceleyebilirsiniz.
<!-- -->
:::
