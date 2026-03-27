---
{
  "title": "The Modular Architecture (TMA)",
  "titleTemplate": ":title · Projects · Features · Guides · Tuist",
  "description": "Learn about The Modular Architecture (TMA) and how to structure your projects using it."
}
---
# Modüler Mimari (TMA) {#the-modular-architecture-tma}

TMA, ölçeklenebilirliği sağlamak, derleme ve test döngülerini optimize etmek ve
ekibinizde iyi uygulamalar sağlamak için Apple OS uygulamalarını yapılandırmaya
yönelik mimari bir yaklaşımdır. Temel fikri, uygulamalarınızı açık ve özlü
API'ler kullanarak birbirine bağlı bağımsız özellikler oluşturarak inşa
etmektir.

Bu kılavuz, mimarinin ilkelerini tanıtarak uygulama özelliklerinizi farklı
katmanlarda tanımlamanıza ve düzenlemenize yardımcı olur. Ayrıca, bu mimariyi
kullanmaya karar vermeniz halinde size ipuçları, araçlar ve tavsiyeler de sunar.

::: info µFEATURES
<!-- -->
Bu mimari daha önce µFeatures olarak biliniyordu. Amacını ve arkasındaki
ilkeleri daha iyi yansıtması için adını The Modular Architecture (TMA) olarak
değiştirdik.
<!-- -->
:::

## Temel ilke {#core-principle}

Geliştiriciler, UI önizlemeleri, kod tamamlama ve hata ayıklama gibi Xcode
özelliklerinin güvenilir bir şekilde çalışmasını sağlarken, ana uygulamadan
bağımsız olarak **özelliklerini hızlı bir şekilde oluşturabilmeli, test
edebilmeli ve** deneyebilmelidir.

## Modül nedir {#what-is-a-module}

Bir modül bir uygulama özelliğini temsil eder ve aşağıdaki beş hedefin
birleşimidir (burada hedef bir Xcode hedefini ifade eder):

- **Kaynak:** Özellik kaynak kodunu (Swift, Objective-C, C++, JavaScript...) ve
  kaynaklarını (görüntüler, yazı tipleri, storyboard'lar, xibs) içerir.
- **Arayüz:** Özelliğin genel arayüzünü ve modellerini içeren tamamlayıcı bir
  hedeftir.
- **Testler:** Özellik birim ve entegrasyon testlerini içerir.
- **Test:** Testlerde ve örnek uygulamada kullanılabilecek test verileri sağlar.
  Ayrıca, daha sonra göreceğimiz gibi diğer özellikler tarafından
  kullanılabilecek modül sınıfları ve protokolleri için mock'lar sağlar.
- **Örnek:** Geliştiricilerin özelliği belirli koşullar altında (farklı diller,
  ekran boyutları, ayarlar) denemek için kullanabilecekleri örnek bir uygulama
  içerir.

Tuist'in DSL'si sayesinde projenizde uygulayabileceğiniz hedefler için bir
adlandırma kuralını izlemenizi öneririz.

| Hedef              | Bağımlılıklar               | İçerik                        |
| ------------------ | --------------------------- | ----------------------------- |
| `Özellik`          | `FeatureInterface`          | Kaynak kodu ve kaynaklar      |
| `FeatureInterface` | -                           | Genel arayüz ve modeller      |
| `ÖzellikTestleri`  | `Özellik`, `ÖzellikTesti`   | Birim ve entegrasyon testleri |
| `ÖzellikTesti`     | `FeatureInterface`          | Test verileri ve mock'lar     |
| `ÖzellikÖrnek`     | `FeatureTesting`, `Feature` | Örnek uygulama                |

::: tip UI Previews
<!-- -->
`Özellik`, UI önizlemelerine izin vermek için `FeatureTesting` adresini
Geliştirme Varlığı olarak kullanabilir
<!-- -->
:::

::: warning COMPILER DIRECTIVES INSTEAD OF TESTING TARGETS
<!-- -->
Alternatif olarak, `Debug` için derleme yaparken test verilerini ve mock'ları
`Feature` veya `FeatureInterface` hedeflerine dahil etmek için derleyici
yönergelerini kullanabilirsiniz. Grafiği basitleştirirsiniz, ancak uygulamayı
çalıştırmak için ihtiyaç duymayacağınız kodu derlemiş olursunuz.
<!-- -->
:::

## Neden bir modül {#why-a-module}

### Açık ve öz API'ler {#clear-and-concise-apis}

Tüm uygulama kaynak kodu aynı hedefte bulunduğunda, kodda örtük bağımlılıklar
oluşturmak ve çok iyi bilinen spagetti koduyla sonuçlanmak çok kolaydır. Her şey
güçlü bir şekilde birbirine bağlıdır, durum bazen öngörülemez ve yeni
değişiklikler yapmak bir kabusa dönüşür. Özellikleri bağımsız hedeflerde
tanımladığımızda, özellik uygulamamızın bir parçası olarak genel API'ler
tasarlamamız gerekir. Neyin herkese açık olması gerektiğine, özelliğimizin nasıl
tüketilmesi gerektiğine, neyin özel kalması gerektiğine karar vermemiz gerekir.
Özellik istemcilerimizin özelliği nasıl kullanmasını istediğimiz üzerinde daha
fazla kontrole sahibiz ve güvenli API'ler tasarlayarak iyi uygulamaları
zorlayabiliriz.

### Küçük modüller {#small-modules}

[Böl ve fethet](https://en.wikipedia.org/wiki/Divide_and_conquer). Küçük
modüller halinde çalışmak, daha fazla odaklanmanıza ve özelliği izole bir
şekilde test edip denemenize olanak tanır. Ayrıca, daha seçici bir derleme
yaptığımız için geliştirme döngüleri çok daha hızlıdır, yalnızca özelliğimizi
çalıştırmak için gerekli olan bileşenleri derleriz. Tüm uygulamanın derlenmesi
yalnızca çalışmamızın en sonunda, özelliği uygulamaya entegre etmemiz
gerektiğinde gereklidir.

### Yeniden Kullanılabilirlik {#reusability}

Uygulamalar ve uzantılar gibi diğer ürünler arasında kodun yeniden kullanılması,
çerçeveler veya kütüphaneler kullanılarak teşvik edilir. Modüller oluşturarak
bunları yeniden kullanmak oldukça basittir. Sadece mevcut modülleri
birleştirerek ve _(gerektiğinde)_ platforma özgü kullanıcı arayüzü katmanları
ekleyerek bir iMessage uzantısı, bir Bugün Uzantısı veya bir watchOS uygulaması
oluşturabiliriz.

## Bağımlılıklar {#dependencies}

Bir modül başka bir modüle bağımlı olduğunda, arayüz hedefine karşı bir
bağımlılık bildirir. Bunun faydası iki yönlüdür. Bir modülün uygulamasının başka
bir modülün uygulamasına bağlanmasını önler ve temiz derlemeleri hızlandırır
çünkü yalnızca özelliğimizin uygulamasını ve doğrudan ve geçişli bağımlılıkların
arayüzlerini derlemeleri gerekir. Bu yaklaşım SwiftRock'ın [Arayüz Modülleri
Kullanarak iOS Derleme Sürelerini
Azaltma](https://swiftrocks.com/reducing-ios-build-times-by-using-interface-targets)
fikrinden esinlenmiştir.

Arayüzlere bağlı olmak, uygulamaların çalışma zamanında uygulama grafiğini
oluşturmasını ve buna ihtiyaç duyan modüllere bağımlılık enjekte etmesini
gerektirir. TMA bunun nasıl yapılacağı konusunda görüş bildirmese de, bağımlılık
enjekte etme çözümlerinin veya kalıplarının ya da inşa zamanı dolaylamaları
eklemeyen veya bu amaç için tasarlanmamış platform API'lerini kullanmayan
çözümlerin kullanılmasını öneriyoruz.

## Ürün tipleri {#product-types}

Bir modül oluştururken, hedefler için **kütüphaneler ve çerçeveler** ile
**statik ve dinamik bağlama** arasında seçim yapabilirsiniz. Tuist olmadan, bu
kararı vermek biraz daha karmaşıktır çünkü bağımlılık grafiğini manuel olarak
yapılandırmanız gerekir. Ancak Tuist Projects sayesinde bu artık bir sorun
olmaktan çıkmıştır.

Geliştirme sırasında, paket erişim mantığını hedefin kütüphane veya çerçeve
yapısından ayırmak için
<LocalizedLink href="/guides/features/projects/synthesized-files#bundle-accessors">bundle accessors</LocalizedLink> kullanarak dinamik kütüphaneler veya çerçeveler
kullanmanızı öneririz. Bu, hızlı derleme süreleri ve [SwiftUI
Önizlemelerinin](https://developer.apple.com/documentation/swiftui/previews-in-xcode)
güvenilir bir şekilde çalışmasını sağlamak için çok önemlidir. Ve uygulamanın
hızlı önyükleme yapmasını sağlamak için sürüm derlemeleri için statik
kütüphaneler veya çerçeveler. Ürün türünü oluşturma zamanında değiştirmek için
<LocalizedLink href="/guides/features/projects/dynamic-configuration#configuration-through-environment-variables">dinamik yapılandırmadan</LocalizedLink> yararlanabilirsiniz:

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
Apple, statik ve dinamik kütüphaneler arasında geçiş yapmanın zahmetini
[birleştirilebilir
kütüphaneler](https://developer.apple.com/documentation/xcode/configuring-your-project-to-use-mergeable-libraries)
sunarak hafifletmeye çalışmıştır. Ancak bu, derlemenizi tekrar üretilemez hale
getiren ve optimize etmeyi zorlaştıran derleme zamanı belirsizliklerini
beraberinde getirir, bu nedenle kullanmanızı önermiyoruz.
<!-- -->
:::

## Kod {#code}

TMA, modülleriniz için kod mimarisi ve kalıpları hakkında görüş bildirmez.
Ancak, deneyimlerimize dayanarak bazı ipuçlarını paylaşmak istiyoruz:

- **Derleyiciden yararlanmak harikadır.** Derleyiciden fazla yararlanmak
  verimsiz olabilir ve önizleme gibi bazı Xcode özelliklerinin güvenilmez
  şekilde çalışmasına neden olabilir. Derleyiciyi iyi uygulamaları zorunlu
  kılmak ve hataları erken yakalamak için kullanmanızı öneririz, ancak kodun
  okunmasını ve bakımını zorlaştıracak kadar değil.
- **Swift Makrolarını idareli kullanın.** Çok güçlü olabilirler ancak aynı
  zamanda kodun okunmasını ve bakımını zorlaştırabilirler.
- **Platformu ve dili benimseyin, onları soyutlamayın.** Ayrıntılı soyutlama
  katmanları bulmaya çalışmak ters etki yaratabilir. Platform ve dil, ek
  soyutlama katmanlarına ihtiyaç duymadan harika uygulamalar oluşturmak için
  yeterince güçlüdür. Özelliklerinizi oluşturmak için referans olarak iyi
  programlama ve tasarım modellerini kullanın.

## Kaynaklar {#resources}

- [Building µFeatures](https://speakerdeck.com/pepibumur/building-ufeatures)
- [Çerçeve Odaklı Programlama]
  (https://speakerdeck.com/pepibumur/framework-oriented-programming-mobilization-dot-pl)
- [A Journey into frameworks and
  Swift](https://speakerdeck.com/pepibumur/a-journey-into-frameworks-and-swift)
- [iOS'ta geliştirmemizi hızlandırmak için çerçevelerden yararlanma - Bölüm
  1](https://developers.soundcloud.com/blog/leveraging-frameworks-to-speed-up-our-development-on-ios-part-1)
- [Kütüphane Odaklı Programlama]
  (https://academy.realm.io/posts/justin-spahr-summers-library-oriented-programming/)
- [Building Modern
  Frameworks](https://developer.apple.com/videos/play/wwdc2014/416/)
- [xcconfig dosyaları için Resmi Olmayan
  Kılavuz](https://pewpewthespells.com/blog/xcconfig_guide.html)
- [Statik ve Dinamik
  Kütüphaneler](https://pewpewthespells.com/blog/static_and_dynamic_libraries.html)
