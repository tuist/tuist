---
{
  "title": "The cost of convenience",
  "titleTemplate": ":title · Projects · Features · Guides · Tuist",
  "description": "Learn about the cost of convenience in Xcode and how Tuist helps you prevent the issues that come with it."
}
---
# Kolaylığın bedeli {#the-cost-of-convenience}

Küçük ölçekli projelerden büyük ölçekli projelere kadar geniş bir yelpazede
kullanılabilen bir kod editörü tasarlamak **** zorlu bir görevdir. Birçok araç,
çözümlerini katmanlara ayırarak ve genişletilebilirlik sağlayarak bu soruna
yaklaşır. En alt katman çok düşük seviyededir ve temel yapı sistemine yakındır,
en üst katman ise kullanımı kolay ancak esnekliği daha az olan yüksek seviyeli
bir soyutlamadır. Bu sayede, basit şeyleri kolaylaştırır ve diğer her şeyi
mümkün kılarlar.

Ancak, **[Apple](https://www.apple.com) Xcode** ile farklı bir yaklaşım
benimsemeye karar verdi. Nedeni bilinmemekle birlikte, büyük ölçekli projelerin
zorluklarına yönelik optimizasyonun hiçbir zaman hedefleri olmamış olması
muhtemeldir. Küçük projeler için kolaylık sağlamak için aşırı yatırım yaptılar,
çok az esneklik sağladılar ve araçları altta yatan derleme sistemiyle güçlü bir
şekilde bağladılar. Kolaylık sağlamak için, kolayca değiştirebileceğiniz
mantıklı varsayılanlar sağladılar ve büyük ölçekte birçok sorunun nedeni olan
birçok örtük derleme zamanında çözülen davranış eklediler.

## Açıklık ve ölçek {#explicitness-and-scale}

Büyük ölçekli çalışmalarda, **açıklık çok önemlidir**. Bu, derleme sisteminin
proje yapısını ve bağımlılıkları önceden analiz edip anlamasını ve aksi takdirde
imkansız olan optimizasyonları gerçekleştirmesini sağlar. Aynı açıklık, [SwiftUI
önizlemeleri](https://developer.apple.com/documentation/swiftui/previews-in-xcode)
veya [Swift
Makroları](https://docs.swift.org/swift-book/documentation/the-swift-programming-language/macros/)
gibi düzenleyici özelliklerinin güvenilir ve öngörülebilir bir şekilde
çalışmasını sağlamak için de çok önemlidir. Xcode ve Xcode projeleri, kolaylık
sağlamak için geçerli bir tasarım seçeneği olarak belirsizliği benimsediğinden,
Swift Package Yöneticisi de bu ilkeyi miras almıştır. Bu nedenle, Xcode'u
kullanmanın zorlukları Swift Package Yöneticisi'nde de mevcuttur.

::: info THE ROLE OF TUIST
<!-- -->
Tuist'in rolünü, örtük olarak tanımlanmış projeleri önleyen ve açık bir şekilde
ifade edilmesini sağlayarak daha iyi bir geliştirici deneyimi (ör. doğrulamalar,
optimizasyonlar) sunan bir araç olarak özetleyebiliriz.
[Bazel](https://bazel.build) gibi araçlar, bunu bir adım daha ileri götürerek
derleme sistemi düzeyine indirger.
<!-- -->
:::

Bu, toplulukta pek tartışılmayan, ancak önemli bir konudur. Tuist üzerinde
çalışırken, birçok kuruluş ve geliştiricinin karşılaştıkları mevcut zorlukların
[Swift package manager](https://www.swift.org/documentation/package-manager/)
tarafından çözüleceğini düşündüklerini fark ettik, ancak fark etmedikleri şey,
aynı ilkeler üzerine kurulu olduğu için, çok iyi bilinen Git çakışmalarını
azaltmasına rağmen, diğer alanlarda geliştirici deneyimini bozduğu ve projeleri
optimize edilemez hale getirmeye devam ettiği.

Aşağıdaki bölümlerde, örtükliğin geliştirici deneyimini ve projenin sağlığını
nasıl etkilediğine dair bazı gerçek örnekler ele alacağız. Bu liste eksiksiz
değildir, ancak Xcode projeleri veya Swift package'ları ile çalışırken
karşılaşabileceğiniz zorluklar hakkında size iyi bir fikir verecektir.

## Rahatlık yolunuza çıkıyor {#convenience-getting-in-your-way}

### Paylaşılan derlenmiş ürünler dizini {#shared-built-products-directory}

Xcode, her ürün için türetilmiş veri dizinindeki bir dizini kullanır. Bu
dizinde, derlenmiş ikili dosyalar, dSYM dosyaları ve günlükler gibi derleme
artefaktları depolanır. Bir projenin tüm ürünleri, varsayılan olarak diğer
hedeflerden bağlantı kurulacak şekilde görülebilen aynı dizine
yerleştirildiğinden, **birbirine dolaylı olarak bağımlı hedefler elde
edebilirsiniz.** Hedef sayısı az olduğunda bu bir sorun olmayabilir, ancak proje
büyüdükçe hata ayıklaması zor olan derleme hataları ortaya çıkabilir.

Bu tasarım kararının sonucu, birçok projenin yanlışlıkla iyi tanımlanmamış bir
grafikle derlenmesi olmuştur.

::: tip TUIST DETECTION OF IMPLICIT DEPENDENCIES
<!-- -->
Tuist, örtük bağımlılıkları tespit etmek için
<LocalizedLink href="/guides/features/inspect/implicit-dependencies">komut</LocalizedLink>
sağlar. Bu komutu kullanarak CI'da tüm bağımlılıklarınızın açık olduğunu
doğrulayabilirsiniz.
<!-- -->
:::

### Şemalarda örtük bağımlılıkları bulun {#find-implicit-dependencies-in-schemes}

Xcode'da bağımlılık grafiği tanımlamak ve sürdürmek, proje büyüdükçe zorlaşır.
Bu zorluk, bağımlılıkların `.pbxproj` dosyalarında derleme aşamaları ve derleme
ayarları olarak kodlanmış olmasından, grafiği görselleştirmek ve üzerinde
çalışmak için herhangi bir araç bulunmamasından ve grafikteki değişikliklerin
(örneğin, yeni bir dinamik önceden derlenmiş çerçeve eklemek) yukarı akışta
yapılandırma değişiklikleri gerektirebilmesinden kaynaklanmaktadır (örneğin,
çerçeveyi pakete kopyalamak için yeni bir derleme aşaması eklemek).

Apple, bir noktada grafik modelini daha yönetilebilir bir hale getirmek yerine,
derleme sırasında örtük bağımlılıkları çözmek için bir seçenek eklemenin daha
mantıklı olacağına karar verdi. Bu, yine tartışmalı bir tasarım seçimi çünkü
derleme sürelerinin uzamasına veya öngörülemeyen derlemelere neden olabilir.
Örneğin, bir derleme,
[singleton](https://en.wikipedia.org/wiki/Singleton_pattern) görevi gören
türetme verilerindeki bir durum nedeniyle yerel olarak geçebilir, ancak durum
farklı olduğu için CI'da derleme başarısız olabilir.

::: tip
<!-- -->
Proje şemalarınızda bunu devre dışı bırakmanızı ve bağımlılık grafiğinin
yönetimini kolaylaştıran Tuist gibi bir araç kullanmanızı öneririz.
<!-- -->
:::

### SwiftUI Önizlemeleri ve statik kütüphaneler/çerçeveler {#swiftui-previews-and-static-librariesframeworks}

SwiftUI Önizlemeleri veya Swift Makroları gibi bazı düzenleyici özellikleri,
düzenlenmekte olan dosyadan bağımlılık grafiğinin derlenmesini gerektirir.
Düzenleyici arasındaki bu entegrasyon, derleme sisteminin tüm örtüklikleri
çözmesini ve bu özelliklerin çalışması için gerekli olan doğru yapıları
çıktısını almasını gerektirir. Tahmin edebileceğiniz gibi, **grafik ne kadar
örtükse, derleme sistemi için görev o kadar zorlaşır** ve bu nedenle bu
özelliklerin çoğunun güvenilir bir şekilde çalışmaması şaşırtıcı değildir.
Geliştiricilerden, SwiftUI önizlemelerini çok uzun zaman önce kullanmayı
bıraktıklarını, çünkü çok güvenilmez olduklarını sık sık duyuyoruz. Bunun
yerine, örnek uygulamaları kullanıyorlar veya statik kütüphanelerin veya komut
dosyası derleme aşamalarının kullanımı gibi belirli şeylerden kaçınıyorlar,
çünkü bunlar özelliğin bozulmasına neden oluyor.

### Birleştirilebilir kütüphaneler {#mergeable-libraries}

Dinamik çerçeveler daha esnek ve kullanımı daha kolay olsa da, uygulamaların
başlatılma süresini olumsuz etkiler. Öte yandan, statik kütüphaneler daha hızlı
başlatılır, ancak derleme süresini etkiler ve özellikle karmaşık grafik
senaryolarında kullanımı biraz daha zordur. *Yapılandırmaya bağlı olarak
birinden diğerine geçebilseydiniz ne kadar harika olurdu, değil mi?* Apple,
birleştirilebilir kütüphaneler üzerinde çalışmaya karar verdiğinde böyle
düşünmüş olmalı. Ancak bir kez daha, derleme zamanı çıkarımını derleme zamanına
taşıdılar. Bağımlılık grafiği hakkında akıl yürütme yaparken, hedefin statik
veya dinamik yapısının bazı hedeflerdeki bazı derleme ayarlarına göre derleme
zamanında çözüleceğini düşünün. SwiftUI önizlemeleri gibi özelliklerin
bozulmamasını sağlarken bunu güvenilir bir şekilde çalıştırmayı başarabilmek
için bol şans.

**Birçok kullanıcı birleştirilebilir kütüphaneleri kullanmak için Tuist'e
geliyor ve bizim cevabımız her zaman aynı. Buna gerek yok.** Hedeflerinizin
statik veya dinamik yapısını oluşturma sırasında kontrol edebilir ve böylece
derleme öncesinde grafiği bilinen bir proje elde edebilirsiniz. Derleme
sırasında hiçbir değişkenin çözülmesi gerekmez.

```bash
# The value of TUIST_DYNAMIC can be read from the project {#the-value-of-tuist_dynamic-can-be-read-from-the-project}
# to set the product as static or dynamic based on the value. {#to-set-the-product-as-static-or-dynamic-based-on-the-value}
TUIST_DYNAMIC=1 tuist generate
```

## Açık, açık ve açık {#explicit-explicit-and-explicit}

Xcode ile geliştirme çalışmalarını ölçeklendirmek isteyen her geliştirici veya
kuruluşa tavsiye ettiğimiz önemli bir yazılı olmayan ilke varsa, o da açıklığı
benimsemeleri gerektiğidir. Açıklığı ham Xcode projeleriyle yönetmek zorsa,
[Tuist](https://tuist.io) veya [Bazel](https://bazel.build) gibi başka bir
seçenek düşünmelidirler. **Ancak o zaman güvenilirlik, öngörülebilirlik ve
optimizasyonlar mümkün olacaktır.**

## Gelecek {#future}

Apple'ın yukarıdaki sorunların tümünü önlemek için bir şeyler yapıp yapmayacağı
bilinmiyor. Xcode ve Swift package Manager'a yerleştirdikleri sürekli kararlar,
bunu yapacaklarını düşündürmüyor. Örtük yapılandırmayı geçerli bir durum olarak
kabul ettiğinizde, **büyük değişiklikler yapmadan bu durumdan kurtulmak
zorlaşır.** İlk ilkelere geri dönüp araçların tasarımını yeniden düşünmek,
yıllardır yanlışlıkla derlenen birçok Xcode projesinin bozulmasına neden
olabilir. Böyle bir durumda topluluğun tepkisini bir düşünün.

Apple, bir nevi tavuk-yumurta problemiyle karşı karşıya. Kolaylık,
geliştiricilerin hızlı bir şekilde işe başlamasına ve ekosistemleri için daha
fazla uygulama geliştirmesine yardımcı olur. Ancak, bu ölçekte kolaylık sağlamak
için aldıkları kararlar, Xcode özelliklerinin bazılarının güvenilir bir şekilde
çalışmasını sağlamalarını zorlaştırıyor.

Gelecek bilinmez olduğu için, **endüstri standartlarına ve Xcode projelerine**
mümkün olduğunca yakın olmaya çalışıyoruz. Yukarıdaki sorunları önlüyor ve daha
iyi bir geliştirici deneyimi sunmak için sahip olduğumuz bilgileri kullanıyoruz.
İdeal olarak, bunun için proje oluşturmaya başvurmamız gerekmezdi, ancak Xcode
ve Swift package Yöneticisi'nin genişletilebilir olmaması, bunu tek geçerli
seçenek haline getiriyor. Ayrıca, Tuist projelerini bozmak için Xcode
projelerini bozmak zorunda kalacakları için bu, güvenli bir seçenek.

İdeal olarak, **derleme sistemi daha genişletilebilir olsaydı**, ancak örtük bir
dünyayla sözleşme yapan eklentiler/uzantılar olması kötü bir fikir olmaz mıydı?
Bu iyi bir fikir gibi görünmüyor. Bu nedenle, daha iyi bir geliştirici deneyimi
sağlamak için Tuist veya [Bazel](https://bazel.build) gibi harici araçlara
ihtiyacımız olacak gibi görünüyor. Ya da belki Apple hepimizi şaşırtacak ve
Xcode'u daha genişletilebilir ve açık hale getirecek...

Bu gerçekleşene kadar, Xcode'un sunduğu kolaylığı kabul edip bunun getirdiği
yükümlülükleri üstlenmek mi, yoksa daha iyi bir geliştirici deneyimi sunmak için
bu yolculukta bize güvenmek mi istediğinize karar vermelisiniz. Sizi hayal
kırıklığına uğratmayacağız.
