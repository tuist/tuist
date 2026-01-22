---
{
  "title": "The Modular Architecture (TMA)",
  "titleTemplate": ":title · Projects · Features · Guides · Tuist",
  "description": "Learn about The Modular Architecture (TMA) and how to structure your projects using it."
}
---
# Modüler Mimari (TMA) {#the-modular-architecture-tma}

TMA, Apple OS uygulamalarını ölçeklenebilirlik sağlamak, derleme ve test
döngülerini optimize etmek ve ekibinizde iyi uygulamaları garantilemek için
yapılandırmaya yönelik bir mimari yaklaşımdır. Temel fikri, açık ve özlü API'ler
kullanılarak birbirine bağlanan bağımsız özellikler oluşturarak uygulamalarınızı
geliştirmektir.

Bu kılavuz, mimarinin ilkelerini tanıtarak, uygulama özelliklerinizi farklı
katmanlarda tanımlamanıza ve düzenlemenize yardımcı olur. Ayrıca, bu mimariyi
kullanmaya karar verirseniz, ipuçları, araçlar ve tavsiyeler de sunar.

::: info µFEATURES
<!-- -->
Bu mimari daha önce µFeatures olarak biliniyordu. Amacını ve arkasındaki
ilkeleri daha iyi yansıtmak için adını Modüler Mimari (TMA) olarak değiştirdik.
<!-- -->
:::

## Temel ilke {#core-principle}

Geliştiriciler, ana uygulamadan bağımsız olarak ve UI önizlemeleri, kod
tamamlama ve hata ayıklama gibi Xcode özelliklerinin güvenilir bir şekilde
çalıştığından emin olarak, özelliklerini hızlı bir şekilde **oluşturmalı, test
etmeli ve** denemelidir.

## Modül nedir? {#what-is-a-module}

Modül, bir uygulama özelliğini temsil eder ve aşağıdaki beş hedefin birleşimidir
(hedef, Xcode hedefini ifade eder):

- **Kaynak:** Özellik kaynak kodunu (Swift, Objective-C, C++, JavaScript...) ve
  kaynaklarını (görüntüler, yazı tipleri, storyboard'lar, xib'ler) içerir.
- **Arayüz:** Bu, özelliğin genel arayüzünü ve modellerini içeren bir eşlik eden
  hedeftir.
- **Testler:** Özellik birimi ve entegrasyon testlerini içerir.
- **Test:** Testlerde ve örnek uygulamada kullanılabilecek test verileri sağlar.
  Ayrıca, daha sonra göreceğimiz gibi, diğer özellikler tarafından
  kullanılabilecek modül sınıfları ve protokoller için sahte veriler sağlar.
- **Örnek:** Geliştiricilerin belirli koşullar altında (farklı diller, ekran
  boyutları, ayarlar) özelliği denemek için kullanabilecekleri bir örnek
  uygulama içerir.

Hedefler için bir adlandırma kuralı izlemenizi öneririz. Tuist'in DSL'i
sayesinde bunu projenizde uygulayabilirsiniz.

| Hedef              | Bağımlılıklar               | İçerik                         |
| ------------------ | --------------------------- | ------------------------------ |
| `Özellik`          | `FeatureInterface`          | Kaynak kodu ve kaynaklar       |
| `FeatureInterface` | -                           | Genel arayüz ve modeller       |
| `Özellik Testleri` | `Özellik`, `ÖzellikTesting` | Birim ve entegrasyon testleri  |
| `Özellik Testi`    | `FeatureInterface`          | Test verileri ve sahte veriler |
| `ÖzellikÖrnek`     | `FeatureTesting`, `Feature` | Örnek uygulama                 |

::: tip UI Previews
<!-- -->
`Özellik`, `FeatureTesting` 'yi bir geliştirme varlığı olarak kullanarak UI
önizlemelerine izin verebilir.
<!-- -->
:::

::: warning COMPILER DIRECTIVES INSTEAD OF TESTING TARGETS
<!-- -->
Alternatif olarak, derleyici yönergelerini kullanarak `Feature` veya
`FeatureInterface` hedeflerine test verilerini ve sahte verileri
ekleyebilirsiniz. `Debug` için derleme yaparken. Grafiği basitleştirirsiniz,
ancak uygulamayı çalıştırmak için ihtiyacınız olmayan kodları derlemiş
olursunuz.
<!-- -->
:::

## Neden bir modül? {#why-a-module}

### Açık ve özlü API'ler {#clear-and-concise-apis}

Tüm uygulama kaynak kodu aynı hedefte yer aldığında, kodda örtük bağımlılıklar
oluşturmak ve sonuçta çok iyi bilinen spagetti koduyla karşılaşmak çok kolaydır.
Her şey birbirine sıkı sıkıya bağlıdır, durum bazen öngörülemez olabilir ve yeni
değişiklikler yapmak bir kabusa dönüşebilir. Özellikleri bağımsız hedeflerde
tanımladığımızda, özellik uygulamamızın bir parçası olarak genel API'ler
tasarlamamız gerekir. Neyin genel olması gerektiğini, özelliğimizin nasıl
kullanılması gerektiğini, neyin özel kalması gerektiğini belirlememiz gerekir.
Özellik istemcilerimizin özelliği nasıl kullanmasını istediğimiz üzerinde daha
fazla kontrolümüz olur ve güvenli API'ler tasarlayarak iyi uygulamaları zorunlu
kılabiliriz.

### Küçük modüller {#small-modules}

[Böl ve fethet](https://en.wikipedia.org/wiki/Divide_and_conquer). Küçük
modüller halinde çalışmak, daha fazla odaklanmanıza ve özelliği ayrı ayrı test
etmenize ve denemenize olanak tanır. Ayrıca, özelliğin çalışması için gerekli
olan bileşenleri derleyerek daha seçici bir derleme yaptığımızdan, geliştirme
döngüleri çok daha hızlıdır. Uygulamanın tamamının derlenmesi, yalnızca
çalışmamızın en sonunda, özelliği uygulamaya entegre etmemiz gerektiğinde
gereklidir.

### Yeniden kullanılabilirlik {#reusability}

Uygulamalar ve uzantılar gibi diğer ürünlerde kodun yeniden kullanılması,
çerçeveler veya kütüphaneler kullanılarak teşvik edilir. Modülleri yeniden
kullanarak bunları oluşturmak oldukça basittir. Mevcut modülleri birleştirip
(gerekirse) __ platformuna özgü UI katmanları ekleyerek iMessage uzantısı, Today
Extension veya watchOS uygulaması oluşturabiliriz.

## Bağımlılıklar {#dependencies}

Bir modül başka bir modüle bağlıysa, arayüz hedefine karşı bir bağımlılık
bildirir. Bunun iki avantajı vardır. Bir modülün uygulamasının başka bir modülün
uygulamasına bağlanmasını önler ve yalnızca özelliğimizin uygulamasını ve
doğrudan ve geçişli bağımlılıkların arayüzlerini derlemek gerektiğinden temiz
derlemeleri hızlandırır. Bu yaklaşım, SwiftRock'un [Arayüz Modülleri Kullanarak
iOS Derleme Sürelerini
Azaltma](https://swiftrocks.com/reducing-ios-build-times-by-using-interface-targets)
fikrinden esinlenmiştir.

Arayüzlere bağlı olarak, uygulamaların çalışma zamanında uygulamaların grafiğini
oluşturması ve bunu ihtiyaç duyan modüllere bağımlılık enjeksiyonu ile eklemesi
gerekir. TMA bu konuda bir görüş belirtmemekle birlikte, bağımlılık enjeksiyonu
çözümleri veya desenleri ya da derleme zamanında dolaylı ifadeler eklemeyen veya
bu amaç için tasarlanmamış platform API'leri kullanmayan çözümleri kullanmanızı
öneririz.

## Ürün türleri {#product-types}

Bir modül oluştururken, hedefler iç **kütüphaneleri ve çerçeveleri** ve **statik
ve dinamik bağlantılar** arasından seçim yapabilirsiniz. Tuist olmadan,
bağımlılık grafiğini manuel olarak yapılandırmanız gerektiğinden bu kararı
vermek biraz daha karmaşıktır. Ancak, Tuist Projects sayesinde bu artık bir
sorun değildir.

Geliştirme sırasında,
<LocalizedLink href="/guides/features/projects/synthesized-files#bundle-accessors">paket
erişimcileri</LocalizedLink> kullanarak paket erişim mantığını hedefin kütüphane
veya çerçeve yapısından ayırmak için dinamik kütüphaneler veya çerçeveler
kullanmanızı öneririz. Bu, hızlı derleme süreleri ve [SwiftUI
Önizlemeleri](https://developer.apple.com/documentation/swiftui/previews-in-xcode)'nin
güvenilir bir şekilde çalışmasını sağlamak için çok önemlidir. Ayrıca,
uygulamanın hızlı bir şekilde başlatılmasını sağlamak için sürüm derlemeleri
için statik kütüphaneler veya çerçeveler kullanın. Ürün türünü oluşturma
sırasında değiştirmek için
<LocalizedLink href="/guides/features/projects/dynamic-configuration#configuration-through-environment-variables">dinamik
yapılandırma</LocalizedLink> özelliğinden yararlanabilirsiniz:

```bash
# You'll have to read the value of the variable from the manifest {#youll-have-to-read-the-value-of-the-variable-from-the-manifest}
# and use it to change the linking type {#and-use-it-to-change-the-linking-type}
TUIST_PRODUCT_TYPE=static-library tuist generate
```

```swift
// You can place this in your manifest files or helpers
// and use the returned value when instantiating targets.
func productType() -> Product {
    if case let .string(productType) = Environment.productType {
        return productType == "static-library" ? .staticLibrary : .framework
    } else {
        return .framework
    }
}
```


::: warning MERGEABLE LIBRARIES
<!-- -->
Apple, [birleştirilebilir
kütüphaneler](https://developer.apple.com/documentation/xcode/configuring-your-project-to-use-mergeable-libraries)
özelliğini sunarak statik ve dinamik kütüphaneler arasında geçiş yapmanın
zorluğunu azaltmaya çalıştı. Ancak bu, derleme zamanında belirsizlik yaratarak
derlemenizin tekrarlanabilirliğini ve optimize edilebilirliğini zorlaştırır, bu
nedenle bu özelliği kullanmanızı önermiyoruz.
<!-- -->
:::

## Kod {#code}

TMA, modüllerinizin kod mimarisi ve kalıpları konusunda herhangi bir görüş
belirtmez. Ancak, deneyimlerimize dayanarak bazı ipuçları paylaşmak isteriz:

- **Derleyiciyi kullanmak harika bir şeydir.** Derleyiciyi aşırı kullanmak
  verimsiz olabilir ve önizleme gibi bazı Xcode özelliklerinin güvenilir
  çalışmamasına neden olabilir. Derleyiciyi, iyi uygulamaları uygulamak ve
  hataları erken yakalamak için kullanmanızı öneririz, ancak kodun okunmasını ve
  bakımını zorlaştıracak kadar kullanmayın.
- **Swift Makrolarını ölçülü kullanın.** Çok güçlü olabilirler, ancak kodun
  okunmasını ve bakımını zorlaştırabilirler.
- **Platformu ve dili benimseyin, soyutlamayın.** Ayrıntılı soyutlama katmanları
  oluşturmaya çalışmak, ters etki yaratabilir. Platform ve dil, ek soyutlama
  katmanlarına ihtiyaç duymadan harika uygulamalar oluşturmak için yeterince
  güçlüdür. Özelliklerinizi oluşturmak için iyi programlama ve tasarım
  modellerini referans olarak kullanın.

## Kaynaklar {#resources}

- [µFeatures oluşturma](https://speakerdeck.com/pepibumur/building-ufeatures)
- [Çerçeve Odaklı
  Programlama](https://speakerdeck.com/pepibumur/framework-oriented-programming-mobilization-dot-pl)
- [Çerçeveler ve Swift'e Bir
  Yolculuk](https://speakerdeck.com/pepibumur/a-journey-into-frameworks-and-swift)
- [iOS'ta geliştirme sürecimizi hızlandırmak için çerçevelerden yararlanma -
  Bölüm
  1](https://developers.soundcloud.com/blog/leveraging-frameworks-to-speed-up-our-development-on-ios-part-1)
- [Kütüphane Odaklı
  Programlama](https://academy.realm.io/posts/justin-spahr-summers-library-oriented-programming/)
- [Modern Çerçeveler
  Oluşturmak](https://developer.apple.com/videos/play/wwdc2014/416/)
- [xcconfig dosyalarına ilişkin resmi olmayan
  kılavuz](https://pewpewthespells.com/blog/xcconfig_guide.html)
- [Statik ve Dinamik
  Kütüphaneler](https://pewpewthespells.com/blog/static_and_dynamic_libraries.html)
