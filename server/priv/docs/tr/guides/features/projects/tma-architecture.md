---
{
  "title": "Modüler Mimari (TMA)",
  "titleTemplate": ":title · Projeler · Özellikler · Kılavuzlar · Tuist",
  "description": "Modüler Mimari (TMA) hakkında bilgi edinin ve projelerinizi bu mimariyi kullanarak nasıl yapılandıracağınızı öğrenin."
}
---
# Modüler Mimari (TMA) {#the-modular-architecture-tma}

TMA, uygulamaları ölçeklenebilir hale getirmek, derleme ve test döngülerini optimize etmek ve ekibinizde iyi uygulamaları sağlamak için yapılandırmaya yönelik bir mimari yaklaşımdır. Temel fikri, açık ve öz API'ler aracılığıyla birbirine bağlanan bağımsız özellikler oluşturarak uygulamalarınızı inşa etmektir.

Bu yönergeler, mimarinin ilkelerini tanıtarak uygulama özelliklerinizi farklı katmanlarda tanımlamanıza ve düzenlemenize yardımcı olur. Ayrıca bu mimariyi kullanmaya karar verirseniz ipuçları, araçlar ve tavsiyeler sunar.

> [!NOTE]
> **µFeatures**
>
> Bu mimari daha önce µFeatures olarak biliniyordu. Amacını ve arkasındaki ilkeleri daha iyi yansıtması için adını Modüler Mimari (TMA) olarak değiştirdik.


## Temel ilke {#core-principle}

Geliştiriciler, özelliklerini ana uygulamadan bağımsız olarak hızlıca **oluşturabilmeli, test edebilmeli ve deneyebilmelidir**; bu sırada UI önizlemeleri, kod tamamlama ve hata ayıklama gibi Xcode özelliklerinin güvenilir şekilde çalışmasını sağlamalıdır.

## Modül nedir {#what-is-a-module}

Bir modül, bir uygulama özelliğini temsil eder ve aşağıdaki beş hedefin birleşiminden oluşur (burada hedef, bir Xcode hedefini ifade eder):

- **Kaynak:** Özellik kaynak kodunu (Swift, Objective-C, C++, JavaScript...) ve kaynaklarını (resimler, yazı tipleri, storyboard'lar, xib dosyaları) içerir.
- **Arayüz:** Özelliğin genel arayüzünü ve modellerini içeren eşlik eden bir hedeftir.
- **Testler:** Özellik birim ve entegrasyon testlerini içerir.
- **Test Desteği:** Testlerde ve örnek uygulamada kullanılabilecek test verilerini sağlar. Daha sonra göreceğimiz gibi, diğer özellikler tarafından kullanılabilecek modül sınıfları ve protokolleri için mock'lar da sağlar.
- **Örnek:** Geliştiricilerin özelliği belirli koşullar altında (farklı diller, ekran boyutları, ayarlar) denemesi için bir örnek uygulama içerir.

Hedefler için bir adlandırma kuralı izlemenizi öneririz; bunu Tuist'in DSL'si sayesinde projenizde uygulayabilirsiniz.

| Hedef | Bağımlılıklar | İçerik |
| ---- | ---- | ---- |
| `Feature` | `FeatureInterface` | Kaynak kod ve kaynaklar |
| `FeatureInterface` | - | Genel arayüz ve modeller |
| `FeatureTests` | `Feature`, `FeatureTesting` | Birim ve entegrasyon testleri |
| `FeatureTesting` | `FeatureInterface` | Test verileri ve mock'lar |
| `FeatureExample` | `FeatureTesting`, `Feature` | Örnek uygulama |

> [!TIP]
> **UI önizlemeleri**
>
> `Feature`, UI önizlemelerine olanak tanımak için `FeatureTesting` öğesini Geliştirme Varlığı olarak kullanabilir


> [!WARNING]
> **Test hedefleri yerine derleyici yönergeleri**
>
> Alternatif olarak, `Debug` için derleme yaparken test verilerini ve mock'ları `Feature` veya `FeatureInterface` hedeflerine dahil etmek için derleyici yönergelerini kullanabilirsiniz. Grafik sadeleşir ancak uygulamayı çalıştırmak için ihtiyaç duymayacağınız kodları da derlemiş olursunuz.


## Neden modül {#why-a-module}

### Açık ve öz API'ler {#clear-and-concise-apis}

Tüm uygulama kaynak kodu aynı hedefde bulunduğunda, kodda örtük bağımlılıklar oluşturmak ve iyi bilinen spagetti kodla karşılaşmak çok kolaydır. Her şey sıkı bağlıdır, durum bazen öngörülemezdir ve yeni değişiklikler yapmak kabusa dönüşür. Özellikleri bağımsız hedeflerde tanımladığımızda, özellik uygulamamızın bir parçası olarak genel API'ler tasarlamamız gerekir. Neyin genel olması gerektiğine, özelliğimizin nasıl tüketileceğine ve neyin özel kalması gerektiğine karar vermeliyiz. Özellik istemcilerimizin özelliği nasıl kullanmasını istediğimiz üzerinde daha fazla kontrolümüz olur ve güvenli API'ler tasarlayarak iyi uygulamaları zorunlu kılabiliriz.

### Küçük modüller {#small-modules}

[Böl ve yönet](https://en.wikipedia.org/wiki/Divide_and_conquer). Küçük modüllerle çalışmak, daha fazla odaklanmanızı ve özelliği izole olarak test edip denemenizi sağlar. Ayrıca, yalnızca özelliğimizin çalışması için gerekli bileşenleri derlediğimiz daha seçici bir derleme sürecine sahip olduğumuzdan geliştirme döngüleri çok daha hızlıdır. Tüm uygulamanın derlenmesi yalnızca işimizin en sonunda, özelliği uygulamaya entegre etmemiz gerektiğinde gereklidir.

### Yeniden kullanılabilirlik {#reusability}

Uygulamalar ve uzantılar gibi diğer ürünler arasında kod yeniden kullanımını çerçeveler veya kütüphaneler kullanarak teşvik ediyoruz. Modüller oluşturarak bunları yeniden kullanmak oldukça basittir. Mevcut modülleri birleştirerek ve _(gerektiğinde)_ platforma özgü UI katmanları ekleyerek bir iMessage uzantısı, Bir Bugün Uzantısı veya bir watchOS uygulaması oluşturabiliriz.

## Bağımlılıklar {#dependencies}

Bir modül başka bir modüle bağımlı olduğunda, arayüz hedefine karşı bir bağımlılık bildirir. Bunun faydası iki yönlüdür. Bir modülün uygulamasının başka bir modülün uygulamasına bağlı olmasını engeller ve temiz derlemeleri hızlandırır çünkü yalnızca özelliğimizin uygulamasını ve doğrudan ile dolaylı bağımlılıkların arayüzlerini derlemeleri gerekir. Bu yaklaşım, SwiftRock'un [Arayüz Modüllerini Kullanarak iOS Derleme Sürelerini Azaltma](https://swiftrocks.com/reducing-ios-build-times-by-using-interface-targets) fikrinden esinlenmiştir.

Arayüzlere bağımlı olmak, uygulamaların çalışma zamanında uygulama grafiğini oluşturmasını ve bunu ihtiyaç duyan modüllere bağımlılık enjeksiyonu yoluyla sağlamasını gerektirir. TMA bunu nasıl yapacağınız konusunda katı kurallar koymasa da, derleme zamanında dolaylılık eklemeyen veya bu amaç için tasarlanmamış platform API'lerini kullanmayan bağımlılık enjeksiyonu çözümleri veya desenleri kullanmanızı öneririz.

## Ürün türleri {#product-types}

Bir modül oluştururken, hedefler için **kütüphaneler ve çerçeveler** ile **statik ve dinamik bağlama** arasında seçim yapabilirsiniz. Tuist olmadan, bağımlılık grafiğini manuel olarak yapılandırmanız gerektiğinden bu kararı vermek biraz daha karmaşıktır. Ancak Tuist Projects sayesinde bu artık bir sorun değil.

Geliştirme sırasında, paket erişim mantığını hedefin kütüphane veya çerçeve niteliğinden ayırmak için <.localized_link href="/guides/features/projects/synthesized-files#bundle-accessors">paket erişimcilerini</.localized_link> kullanarak dinamik kütüphaneler veya çerçeveler kullanmanızı öneririz. Bu, hızlı derleme süreleri için ve [SwiftUI Önizlemeleri](https://developer.apple.com/documentation/swiftui/previews-in-xcode)'nin güvenilir çalışmasını sağlamak için kritiktir. Uygulamanın hızlı başlamasını sağlamak için sürüm derlemelerinde statik kütüphaneler veya çerçeveler kullanın. Ürün türünü oluşturma zamanında değiştirmek için <.localized_link href="/guides/features/projects/dynamic-configuration#configuration-through-environment-variables">dinamik yapılandırmadan</.localized_link> yararlanabilirsiniz:

```bash
# You'll have to read the value of the variable from the manifest
# and use it to change the linking type
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


> [!WARNING]
> **Birleştirilebilir kütüphaneler**
>
> Apple, statik ve dinamik kütüphaneler arasında geçiş yapmanın zorluğunu azaltmak için [birleştirilebilir kütüphaneleri](https://developer.apple.com/documentation/xcode/configuring-your-project-to-use-mergeable-libraries) tanıttı. Ancak bu, derleme zamanında belirsizlik getirerek derlemenizi tekrarlanamaz hale getirir ve optimizasyonu zorlaştırır, bu nedenle kullanmanızı önermiyoruz.


## Kod {#code}

TMA, modülleriniz için kod mimarisi ve desenleri konusunda katı kurallar koymaz. Ancak deneyimlerimize dayalı bazı ipuçlarını paylaşmak istiyoruz:

- **Derleyiciden yararlanmak harikadır.** Derleyiciyi aşırı kullanmak verimsiz olabilir ve önizlemeler gibi bazı Xcode özelliklerinin güvenilir çalışmamasına neden olabilir. Derleyiciyi iyi uygulamaları zorlamak ve hataları erken yakalamak için kullanmanızı öneririz, ancak bunu kodun okunmasını ve bakımını zorlaştıracak noktaya getirmeyin.
- **Swift Makrolarını tutumlu kullanın.** Çok güçlü olabilirler ancak kodun okunmasını ve bakımını da zorlaştırabilirler.
- **Platformu ve dili benimseyin, onları soyutlamayın.** Ayrıntılı soyutlama katmanları oluşturmaya çalışmak ters tepebilir. Platform ve dil, ek soyutlama katmanlarına ihtiyaç duymadan harika uygulamalar oluşturmak için yeterince güçlüdür. Özelliklerinizi oluştururken referans olarak iyi programlama ve tasarım desenlerini kullanın.


## Kaynaklar {#resources}

- [µFeatures Oluşturma](https://speakerdeck.com/pepibumur/building-ufeatures)
- [Çerçeve Odaklı Programlama](https://speakerdeck.com/pepibumur/framework-oriented-programming-mobilization-dot-pl)
- [Çerçevelere ve Swift'e Bir Yolculuk](https://speakerdeck.com/pepibumur/a-journey-into-frameworks-and-swift)
- [iOS'ta Geliştirmemizi Hızlandırmak İçin Çerçevelerden Yararlanma - Bölüm 1](https://developers.soundcloud.com/blog/leveraging-frameworks-to-speed-up-our-development-on-ios-part-1)
- [Kütüphane Odaklı Programlama](https://academy.realm.io/posts/justin-spahr-summers-library-oriented-programming/)
- [Modern Çerçeveler Oluşturma](https://developer.apple.com/videos/play/wwdc2014/416/)
- [xcconfig Dosyaları İçin Resmi Olmayan Kılavuz](https://pewpewthespells.com/blog/xcconfig_guide.html)
- [Statik ve Dinamik Kütüphaneler](https://pewpewthespells.com/blog/static_and_dynamic_libraries.html)
