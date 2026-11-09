---
{
  "title": "Kolaylığın bedeli",
  "titleTemplate": ":title · Projeler · Özellikler · Kılavuzlar · Tuist",
  "description": "Xcode'un örtük davranışlarının nasıl sorunlara yol açtığını ve Tuist'in bunları nasıl önlediğini öğrenin."
}
---
# Kullanım kolaylığının bedeli {#the-cost-of-convenience}

**Küçükten büyük ölçeğe her boyuttaki proje** için çalışan bir kod düzenleyici tasarlamak zorlu bir görevdir. Birçok araç, çözümünü katmanlayarak ve genişletilebilirlik sağlayarak bu soruna yaklaşır. En alttaki katman çok düşük seviyededir ve temel derleme sistemine yakındır; en üstteki katman ise kullanımı kolay ancak daha az esnek olan yüksek seviyeli bir soyutlamadır. Bu sayede basit işleri kolaylaştırır, geri kalan her şeyi de mümkün kılarlar.

Ancak, **[Apple](https://www.apple.com) Xcode ile farklı bir yaklaşım benimsemeyi tercih etti**. Nedeni bilinmiyor, ancak büyük ölçekli projelerin zorluklarına yönelik optimizasyonun asla hedefleri olmaması muhtemeldir. Küçük projeler için kullanım kolaylığına aşırı yatırım yaptılar, çok az esneklik sağladılar ve araçları temel derleme sistemiyle güçlü bir şekilde bağladılar. Kullanım kolaylığını sağlamak için kolayca değiştirebileceğiniz makul varsayılan değerler sundular ve ölçek büyüdükçe birçok sorunun kaynağı olan çok sayıda örtülü derleme zamanında çözülen davranış eklediler.

## Açıklık ve ölçek {#explicitness-and-scale}

Ölçekte çalışırken **açıklık anahtardır**. Derleme sisteminin proje yapısını ve bağımlılıkları önceden analiz edip anlamasını ve aksi takdirde imkânsız olacak optimizasyonları gerçekleştirmesini sağlar. Aynı açıklık, [SwiftUI önizlemeleri](https://developer.apple.com/documentation/swiftui/previews-in-xcode) veya [Swift Makroları](https://docs.swift.org/swift-book/documentation/the-swift-programming-language/macros/) gibi düzenleyici özelliklerinin güvenilir ve öngörülebilir şekilde çalışmasını sağlamada da kilit rol oynar. Xcode ve Xcode projeleri, kullanım kolaylığı sağlamak amacıyla örtülülüğü geçerli bir tasarım tercihi olarak benimsediğinden ve bu ilkeyi Swift Package Manager miras aldığından, Xcode kullanmanın zorlukları Swift Package Manager'da da mevcuttur.

> [!NOTE]
> **Tuist'in rolü**
>
> Tuist'in rolünü, örtülü olarak tanımlanmış projeleri önleyen ve daha iyi bir geliştirici deneyimi sunmak için açıklamadan yararlanan (örn. doğrulamalar, optimizasyonlar) bir araç olarak özetleyebiliriz. [Bazel](https://bazel.build) gibi araçlar bunu derleme sistemi seviyesine indirerek daha da ileri götürür.


Bu, toplulukta neredeyse hiç tartışılmayan ancak önemli bir sorundur. Tuist üzerinde çalışırken, birçok kuruluşun ve geliştiricinin karşılaştıkları mevcut zorlukların [Swift Package Manager](https://www.swift.org/documentation/package-manager/) tarafından ele alınacağını düşündüğünü fark ettik; ancak anlamadıkları şey, aynı ilkeler üzerine inşa edildiği için, iyi bilinen Git çakışmalarını hafifletse bile, geliştirici deneyimini diğer alanlarda kötüleştirdikleri ve projeleri optimize edilemez hale getirmeye devam ettikleridir.

Aşağıdaki bölümlerde, örtülülüğün geliştirici deneyimini ve projenin sağlığını nasıl etkilediğine dair bazı gerçek örnekleri tartışacağız. Liste kapsamlı değildir, ancak Xcode projeleri veya Swift Paketleriyle çalışırken karşılaşabileceğiniz zorluklar hakkında size iyi bir fikir verecektir.

## Kullanım kolaylığının önünüzde engel olması {#convenience-getting-in-your-way}

### Paylaşılan derlenmiş ürün dizini {#shared-built-products-directory}

Xcode, her ürün için türetilmiş veri dizini içinde bir dizin kullanır. İçinde derlenmiş ikili dosyalar, dSYM dosyaları ve günlükler gibi derleme yapıtlarını saklar. Bir projenin tüm ürünleri aynı dizine gittiğinden ve bu dizin varsayılan olarak diğer hedefler tarafından bağlanmak üzere görülebildiğinden, **biri diğerine örtülü olarak bağımlı olan hedeflerle karşılaşabilirsiniz.** Bu, yalnızca birkaç hedefiniz varsa sorun olmayabilir, ancak proje büyüdükte hata ayıklaması zor olan başarısız derlemeler olarak ortaya çıkabilir.

Bu tasarım kararının sonucu, birçok projenin yanlışlıkla iyi tanımlanmamış bir grafikle derlenmesidir.

> [!TIP]
> **Tuist'in örtülü bağımlılıkları tespit etmesi**
>
> Tuist, örtülü bağımlılıkları tespit etmek için bir <.localized_link href="/guides/features/projects/inspect/implicit-dependencies">komut</.localized_link> sağlar. Tüm bağımlılıklarınızın açık olduğunu CI'da doğrulamak için bu komutu kullanabilirsiniz.


### Şemalarda örtülü bağımlılıkları bulma {#find-implicit-dependencies-in-schemes}

Xcode'da bir bağımlılık grafiğini tanımlamak ve sürdürmek, proje büyüdükçe zorlaşır. Zordur çünkü bunlar `.pbxproj` dosyalarında derleme aşamaları ve derleme ayarları olarak kodlanır, grafiği görselleştirmek ve üzerinde çalışmak için araç yoktur ve grafikteki değişiklikler (örn. yeni bir dinamik önceden derlenmiş çerçeve ekleme), yukarı akışta yapılandırma değişiklikleri gerektirebilir (örn. çerçeveyi pakete kopyalamak için yeni bir derleme aşaması ekleme).

Apple bir noktada, grafik modelini daha yönetilebilir bir hale getirmek yerine, derleme zamanında örtülü bağımlılıkları çözmek için bir seçenek eklemenin daha mantıklı olacağına karar verdi. Bu, yine sorgulanabilir bir tasarım tercihidir çünkü daha yavaş derleme süreleri veya öngörülemez derlemelerle karşılaşabilirsiniz. Örneğin, bir derleme, türetilmiş verilerdeki bazı durumlar nedeniyle yerel olarak geçebilir; bu durum bir [singleton](https://en.wikipedia.org/wiki/Singleton_pattern) gibi davranır, ancak durum farklı olduğu için CI'da derleme başarısız olabilir.

> [!TIP]
> Bunu proje şemalarınızda devre dışı bırakmanızı ve bağımlılık grafiği yönetimini kolaylaştıran Tuist gibi bir araç kullanmanızı öneririz.


### SwiftUI Önizlemeleri ve statik kütüphaneler/çerçeveler {#swiftui-previews-and-static-librariesframeworks}

SwiftUI Önizlemeleri veya Swift Makroları gibi bazı düzenleyici özellikleri, düzenlenen dosyadan bağımlılık grafiğinin derlenmesini gerektirir. Düzenleyici ile bu entegrasyon, derleme sisteminin herhangi bir örtülülüğü çözmesini ve bu özelliklerin çalışması için gerekli olan doğru yapıtları üretmesini gerektirir. Tahmin edebileceğiniz gibi, **grafik ne kadar örtük olursa, derleme sistemi için görev o kadar zorlaşır** ve bu nedenle bu özelliklerin çoğunun güvenilir çalışmaması şaşırtıcı değildir. Geliştiricilerden sıkça, SwiftUI önizlemelerini çok güvensiz oldukları için uzun zaman önce kullanmayı bıraktıklarını duyuyoruz. Bunun yerine, ya örnek uygulamalar kullanıyorlar ya da özelliğin bozulmasına neden oldukları için statik kütüphane kullanımı veya betik derleme aşamaları gibi belirli şeylerden kaçınıyorlar.

### Birleştirilebilir kütüphaneler {#mergeable-libraries}

Dinamik çerçeveler daha esnek ve kullanımı kolay olsa da uygulamaların başlatma süresini olumsuz etkiler. Öte yandan, statik kütüphaneler daha hızlı başlatılır ancak derleme süresini etkiler ve özellikle karmaşık grafik senaryolarında kullanımı biraz daha zordur. *Yapılandırmaya bağlı olarak ikisi arasında geçiş yapabilmek harika olmaz mıydı?* Apple’ın birleştirilebilir kütüphaneler üzerinde çalışmaya karar verirken düşündüğü muhtemelen buydu. Ancak yine de daha fazla derleme zamanı çıkarımını derleme zamanına taşıdılar. Bir bağımlılık grafiği hakkında akıl yürütmeniz gerektiğini düşünün; hedefin statik mi yoksa dinamik mi olacağının, bazı hedeflerdeki derleme ayarlarına göre derleme zamanında çözüleceği bir durumda bunu yapmak zorunda kaldığınızı hayal edin. SwiftUI önizlemeleri gibi özelliklerin bozulmamasını sağlarken bunun güvenilir çalışmasını başarmanız dileğiyle.

**Birçok kullanıcı birleştirilebilir kütüphaneleri kullanmak isteğiyle Tuist’e geliyor ve cevabımız her zaman aynı: Buna ihtiyacınız yok.** Hedeflerinizin statik veya dinamik doğasını oluşturma zamanında kontrol edebilir, böylece grafiği derlemeden önce bilinen bir proje elde edersiniz. Derleme zamanında çözülmesi gereken değişken yoktur.

```bash
# The value of TUIST_DYNAMIC can be read from the project {#the-value-of-tuist_dynamic-can-be-read-from-the-project}
# to set the product as static or dynamic based on the value.
TUIST_DYNAMIC=1 tuist generate
```

## Açıklık, açıklık ve açıklık {#explicit-explicit-and-explicit}

Xcode ile geliştirmeyi ölçeklendirmek isteyen her geliştiriciye veya kuruluşa önerdiğimiz yazılı olmayan önemli bir ilke varsa, o da açıklığı benimsemeleridir. Ve eğer açıklığı ham Xcode projeleriyle yönetmek zorsa, başka bir şeyi, ya [Tuist](https://tuist.dev) ya da [Bazel](https://bazel.build)’i düşünmelidirler. **Yalnızca o zaman güvenilirlik, öngörülebilirlik ve optimizasyonlar mümkün olur.**

## Gelecek {#future}

Apple’ın yukarıdaki tüm sorunları önlemek için bir şey yapıp yapmayacağı bilinmiyor. Xcode ve Swift Package Manager’a yerleşmiş sürekli kararları, bunu yapacaklarını göstermiyor. Örtülü yapılandırmayı geçerli bir durum olarak kabul ettiğiniz anda, **bozucu değişiklikler getirmeden oradan çıkmak zordur.** İlk prensiplere dönüp araçların tasarımını yeniden düşünmek, yıllardır kazara derlenen birçok Xcode projesini bozabilir. Böyle bir şey olsaydı toplulukta çıkacak gürültüyü hayal edin.

Apple, bir tür tavuk-yumurta problemiyle karşı karşıya. Kolaylık, geliştiricilerin hızlıca başlamasına ve ekosistemleri için daha fazla uygulama inşa etmesine yardımcı olan şeydir. Ancak deneyimi bu ölçekte kolay hale getirme kararları, Xcode özelliklerinden bazılarının güvenilir çalışmasını sağlamalarını zorlaştırıyor.

Gelecek belirsiz olduğu için, **sektör standartlarına ve Xcode projelerine mümkün olduğunca yakın olmaya** çalışıyoruz. Yukarıdaki sorunları önlüyor ve daha iyi bir geliştirici deneyimi sunmak için sahip olduğumuz bilgiden yararlanıyoruz. İdeal olarak bunun için proje oluşturmaya başvurmak zorunda kalmazdık, ancak Xcode ve Swift Package Manager’ın genişletilebilirlik eksikliği bunu tek uygulanabilir seçenek haline getiriyor. Bu aynı zamanda güvenli bir seçenek çünkü Tuist projelerini bozmak için Xcode projelerini bozmak zorunda kalacaklar.

İdeal olarak, **derleme sistemi daha genişletilebilir olurdu**, ancak örtülülük dünyasıyla sözleşme yapan eklentilerin/uzantıların olması kötü bir fikir olmaz mıydı? İyi bir fikir gibi görünmüyor. Dolayısıyla daha iyi bir geliştirici deneyimi sunmak için Tuist veya [Bazel](https://bazel.build) gibi dış araçlara ihtiyacımız olacak gibi görünüyor. Ya da belki Apple hepimizi şaşırtır ve Xcode’u daha genişletilebilir ve açık hale getirir...

Bu gerçekleşene kadar, Xcode’un kolaylığını benimseyip bununla gelen teknik borcu üstlenmeyi mi, yoksa daha iyi bir geliştirici deneyimi sunma yolculuğunda bize güvenmeyi mi seçmeniz gerekiyor. Sizi hayal kırıklığına uğratmayacağız.
