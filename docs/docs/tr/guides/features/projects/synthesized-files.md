---
{
  "title": "Synthesized files",
  "titleTemplate": ":title · Projects · Features · Guides · Tuist",
  "description": "Learn about synthesized files in Tuist projects."
}
---
# Sentezlenmiş dosyalar {#synthesized-files}

Tuist, Xcode projelerini yönetmeye ve bunlarla çalışmaya bazı kolaylıklar
getirmek için oluşturma zamanında dosya ve kod oluşturabilir. Bu sayfada bu
işlevsellik hakkında bilgi edinecek ve projelerinizde nasıl kullanabileceğinizi
öğreneceksiniz.

## Hedef kaynaklar {#target-resources}

Xcode projeleri hedeflere kaynak eklemeyi destekler. Bununla birlikte, özellikle
kaynakların ve kaynakların sık sık yer değiştirdiği modüler bir projeyle
çalışırken ekiplere bazı zorluklar sunarlar:

- **Tutarsız çalışma zamanı erişimi**: Kaynakların nihai üründe nereye gideceği
  ve bunlara nasıl erişeceğiniz hedef ürüne bağlıdır. Örneğin, hedefiniz bir
  uygulamayı temsil ediyorsa, kaynaklar uygulama paketine kopyalanır. Bu durum,
  kaynaklara erişen kodun paket yapısı üzerinde varsayımlarda bulunmasına neden
  olur ki bu da ideal değildir çünkü kodun mantık yürütmesini ve kaynakların
  hareket etmesini zorlaştırır.
- **Kaynakları desteklemeyen ürünler**: Statik kütüphaneler gibi paket olmayan
  ve bu nedenle kaynakları desteklemeyen bazı ürünler vardır. Bu nedenle,
  projenize veya uygulamanıza bazı ek yükler getirebilecek farklı bir ürün
  türüne, örneğin çerçevelere başvurmanız gerekir. Örneğin, statik çerçeveler
  nihai ürüne statik olarak bağlanır ve yalnızca kaynakları nihai ürüne
  kopyalamak için bir derleme aşaması gerekir. Ya da Xcode'un hem ikili dosyayı
  hem de kaynakları nihai ürüne kopyalayacağı dinamik çerçeveler, ancak
  çerçevenin dinamik olarak yüklenmesi gerektiğinden uygulamanızın başlangıç
  süresini artıracaktır.
- **Çalışma zamanı hatalarına eğilimli**: Kaynaklar adları ve uzantıları
  (dizeler) ile tanımlanır. Bu nedenle, bunlardan herhangi birindeki bir yazım
  hatası, kaynağa erişmeye çalışırken bir çalışma zamanı hatasına yol açacaktır.
  Bu ideal değildir çünkü derleme zamanında yakalanmaz ve sürümde çökmelere yol
  açabilir.

Tuist yukarıdaki sorunları **demetlere ve kaynaklara erişmek için** uygulama
ayrıntılarını soyutlayan birleşik bir arayüz sentezleyerek çözmektedir.

::: warning RECOMMENDED
<!-- -->
Kaynaklara Tuist tarafından sentezlenen arayüz üzerinden erişmek zorunlu olmasa
da, kod hakkında mantık yürütmeyi ve kaynakların hareket etmesini
kolaylaştırdığı için bunu öneriyoruz.
<!-- -->
:::

## Kaynaklar {#resources}

Tuist, `Info.plist` veya Swift'teki yetkilendirmeler gibi dosyaların içeriğini
bildirmek için arayüzler sağlar. Bu, hedefler ve projeler arasında tutarlılığı
sağlamak ve derleme zamanında sorunları yakalamak için derleyiciden yararlanmak
için kullanışlıdır. Ayrıca içeriği modellemek ve hedefler ve projeler arasında
paylaşmak için kendi soyutlamalarınızı da oluşturabilirsiniz.

Projeniz oluşturulduğunda, Tuist bu dosyaların içeriğini sentezleyecek ve
bunları tanımlayan projeyi içeren dizine göre `Türetilmiş` dizinine yazacaktır.

::: tip GITIGNORE THE DERIVED DIRECTORY
<!-- -->
`Derived` dizinini projenizin `.gitignore` dosyasına eklemenizi öneririz.
<!-- -->
:::

## Paket erişimcileri {#bundle-accessors}

Tuist, hedef kaynakları içeren pakete erişmek için bir arayüz sentezler.

### Swift {#swift}

Hedef, paketi açığa çıkaran `Bundle` türünde bir uzantı içerecektir:

```swift
let bundle = Bundle.module
```

### Objective-C {#objectivec}

Objective-C'de, pakete erişmek için `{Target}Resources` şeklinde bir arayüz elde
edersiniz:

```objc
NSBundle *bundle = [MyFeatureResources bundle];
```

::: warning LIMITATION WITH INTERNAL TARGETS
<!-- -->
Şu anda Tuist, yalnızca Objective-C kaynakları içeren dahili hedefler için
kaynak paketi erişicileri oluşturmamaktadır. Bu, [issue
#6456](https://github.com/tuist/tuist/issues/6456)'de izlenen bilinen bir
sınırlamadır.
<!-- -->
:::

::: tip SUPPORTING RESOURCES IN LIBRARIES THROUGH BUNDLES
<!-- -->
Bir hedef ürün, örneğin bir kütüphane, kaynakları desteklemiyorsa, Tuist
kaynakları `bundle` ürün türündeki bir hedefe dahil ederek nihai ürüne
ulaşmasını ve arayüzün doğru pakete işaret etmesini sağlayacaktır.
<!-- -->
:::

## Kaynak erişimcileri {#resource-accessors}

Kaynaklar, dizeler kullanılarak adları ve uzantılarıyla tanımlanır. Bu ideal
değildir çünkü derleme zamanında yakalanmaz ve sürümde çökmelere neden olabilir.
Bunu önlemek için Tuist, kaynaklara erişmek için bir arayüz sentezlemek üzere
proje oluşturma sürecine [SwiftGen](https://github.com/SwiftGen/SwiftGen)
entegre eder. Bu sayede, herhangi bir sorunu yakalamak için derleyiciden
yararlanarak kaynaklara güvenle erişebilirsiniz.

Tuist, varsayılan olarak aşağıdaki kaynak türleri için erişimcileri sentezlemek
üzere
[templates](https://github.com/tuist/tuist/tree/main/Sources/TuistGenerator/Templates)
içerir:

| Kaynak türü           | Sentezlenmiş dosyalar    |
| --------------------- | ------------------------ |
| Görüntüler ve renkler | `Assets+{Target}.swift`  |
| Dizeler               | `Strings+{Target}.swift` |
| Plistler              | `{NameOfPlist}.swift`    |
| Yazı Tipleri          | `Fonts+{Target}.swift`   |
| Dosyalar              | `Files+{Target}.swift`   |

> Not: Proje seçeneklerine `disableSynthesizedResourceAccessors` seçeneğini
> aktararak kaynak erişimcilerinin sentezlenmesini proje bazında devre dışı
> bırakabilirsiniz.

#### Özel şablonlar {#custom-templates}

SwiftGen](https://github.com/SwiftGen/SwiftGen) tarafından desteklenmesi gereken
diğer kaynak türlerine erişimcileri sentezlemek için kendi şablonlarınızı
sağlamak istiyorsanız, bunları `Tuist/ResourceSynthesizers/{name}.stencil`
adresinde oluşturabilirsiniz; burada ad, kaynağın deve harfi versiyonudur.

| Kaynaklar        | Şablon adı                 |
| ---------------- | -------------------------- |
| dizeler          | `Dizeler.şablon`           |
| varlıklar        | `Assets.stencil`           |
| plists           | `Plists.stencil`           |
| yazı tipleri     | `Fonts.stencil`            |
| coreData         | `CoreData.stencil`         |
| interfaceBuilder | `InterfaceBuilder.stencil` |
| json             | `JSON.stencil`             |
| yaml             | `YAML.stencil`             |
| dosyalar         | `Dosyalar.şablon`          |

Erişicilerin sentezleneceği kaynak türlerinin listesini yapılandırmak
istiyorsanız, kullanmak istediğiniz kaynak sentezleyicilerinin listesini aktaran
`Project.resourceSynthesizers` özelliğini kullanabilirsiniz:

```swift
let project = Project(resourceSynthesizers: [.string(), .fonts()])
```

::: info REFERENCE
<!-- -->
Kaynaklara erişimcileri sentezlemek için özel şablonların nasıl kullanılacağına
dair bir örnek görmek için [this
fixture](https://github.com/tuist/tuist/tree/main/cli/Fixtures/ios_app_with_templates)
sayfasına göz atabilirsiniz.
<!-- -->
:::
