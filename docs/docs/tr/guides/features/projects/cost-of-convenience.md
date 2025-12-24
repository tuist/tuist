---
{
  "title": "The cost of convenience",
  "titleTemplate": ":title · Projects · Features · Guides · Tuist",
  "description": "Learn about the cost of convenience in Xcode and how Tuist helps you prevent the issues that come with it."
}
---
# Rahatlığın bedeli {#the-cost-of-convenience}

Küçük ölçekli projelerden büyük ölçekli projelere kadar **spektrumunun**
kullanabileceği bir kod editörü tasarlamak zorlu bir görevdir. Birçok araç,
çözümlerini katmanlandırarak ve genişletilebilirlik sağlayarak soruna yaklaşır.
En alttaki katman çok düşük seviyeli ve altta yatan derleme sistemine yakındır
ve en üstteki katman, kullanımı kolay ancak daha az esnek olan yüksek seviyeli
bir soyutlamadır. Bunu yaparak basit şeyleri kolaylaştırıyor ve diğer her şeyi
mümkün kılıyorlar.

Ancak, **[Apple](https://www.apple.com) Xcode** ile farklı bir yaklaşım
benimsemeye karar verdi. Nedeni bilinmiyor, ancak büyük ölçekli projelerin
zorlukları için optimizasyon yapmak hiçbir zaman hedefleri olmamış olabilir.
Küçük projeler için kolaylığa aşırı yatırım yaptılar, çok az esneklik sağladılar
ve araçları altta yatan derleme sistemiyle güçlü bir şekilde birleştirdiler.
Kolaylık sağlamak için, kolayca değiştirebileceğiniz mantıklı varsayılanlar
sağladılar ve ölçekteki birçok sorunun sorumlusu olan çok sayıda örtük derleme
zamanı çözümlü davranış eklediler.

## Açıklık ve ölçek {#explicitness-and-scale}

Geniş ölçekte çalışırken, **açıklığı çok önemlidir**. Derleme sisteminin proje
yapısını ve bağımlılıklarını önceden analiz edip anlamasını ve aksi takdirde
imkansız olacak optimizasyonları gerçekleştirmesini sağlar. Aynı açıklık,
[SwiftUI
önizlemeleri](https://developer.apple.com/documentation/swiftui/previews-in-xcode)
veya [Swift
Makroları](https://docs.swift.org/swift-book/documentation/the-swift-programming-language/macros/)
gibi editör özelliklerinin güvenilir ve tahmin edilebilir şekilde çalışmasını
sağlamada da kilit öneme sahiptir. Xcode ve Xcode projeleri, Swift paketi
yöneticisinin miras aldığı bir ilke olan kolaylığı sağlamak için geçerli bir
tasarım seçimi olarak örtüklüğü benimsediğinden, Xcode kullanmanın zorlukları
Swift paketi yöneticisinde de mevcuttur.

::: info THE ROLE OF TUIST
<!-- -->
Tuist'in rolünü, örtük olarak tanımlanmış projeleri önleyen ve daha iyi bir
geliştirici deneyimi (örn. doğrulamalar, optimizasyonlar) sağlamak için
açıklıktan yararlanan bir araç olarak özetleyebiliriz.
Bazel](https://bazel.build) gibi araçlar bunu derleme sistemi seviyesine
indirerek daha da ileri götürmektedir.
<!-- -->
:::

Bu, toplulukta çok az tartışılan bir konudur, ancak önemli bir konudur. Tuist
üzerinde çalışırken, birçok kuruluşun ve geliştiricinin karşılaştıkları mevcut
zorlukların [Swift paketi](https://www.swift.org/documentation/package-manager/)
tarafından ele alınacağını düşündüğünü fark ettik, ancak fark etmedikleri şey,
aynı ilkeler üzerine inşa edildiğinden, çok iyi bilinen Git çakışmalarını
hafifletse bile, diğer alanlarda geliştirici deneyimini bozdukları ve projeleri
optimize edilemez hale getirmeye devam ettikleri.

Aşağıdaki bölümlerde, örtüklüğün geliştirici deneyimini ve projenin sağlığını
nasıl etkilediğine dair bazı gerçek örnekleri tartışacağız. Liste kapsamlı
değildir, ancak Xcode projeleri veya Swift paketi ile çalışırken
karşılaşabileceğiniz zorluklar hakkında size iyi bir fikir vermelidir.

## Kolaylık yolunuza çıkıyor {#convenience-getting-in-your-way}

### Paylaşılan yerleşik ürünler dizini {#shared-built-products-directory}

Xcode, her ürün için türetilmiş veri dizininin içinde bir dizin kullanır. Bunun
içinde, derlenmiş ikili dosyalar, dSYM dosyaları ve günlükler gibi derleme
eserlerini saklar. Bir projenin tüm ürünleri aynı dizine girdiğinden ve bu dizin
varsayılan olarak bağlantı kurulacak diğer hedefler tarafından
görülebildiğinden, **dolaylı olarak birbirine bağlı hedeflerle
karşılaşabilirsiniz.** Sadece birkaç hedefe sahipken bu bir sorun olmasa da,
proje büyüdüğünde hata ayıklaması zor olan başarısız derlemeler olarak ortaya
çıkabilir.

Bu tasarım kararının sonucu, birçok projenin tesadüfen iyi tanımlanmamış bir
grafikle derlenmesidir.

::: tip TUIST DETECTION OF IMPLICIT DEPENDENCIES
<!-- -->
Tuist, örtük bağımlılıkları tespit etmek için bir
<LocalizedLink href="/guides/features/inspect/implicit-dependencies">komut</LocalizedLink>
sağlar. CI'da tüm bağımlılıklarınızın açık olduğunu doğrulamak için bu komutu
kullanabilirsiniz.
<!-- -->
:::

### Şemalardaki örtük bağımlılıkları bulun {#find-implicit-dependencies-in-schemes}

Xcode'da bir bağımlılık grafiği tanımlamak ve sürdürmek proje büyüdükçe
zorlaşır. Zordur çünkü `.pbxproj` dosyalarında derleme aşamaları ve derleme
ayarları olarak kodlanırlar, grafiği görselleştirmek ve grafikle çalışmak için
herhangi bir araç yoktur ve grafikteki değişiklikler (örneğin, yeni bir dinamik
önceden derlenmiş çerçeve eklemek), yukarı akışta yapılandırma değişiklikleri
gerektirebilir (örneğin, çerçeveyi pakete kopyalamak için yeni bir derleme
aşaması eklemek).

Apple bir noktada grafik modelini daha yönetilebilir bir hale getirmek yerine,
örtük bağımlılıkları derleme zamanında çözmek için bir seçenek eklemenin daha
mantıklı olacağına karar verdi. Bu bir kez daha sorgulanabilir bir tasarım
tercihidir çünkü daha yavaş derleme süreleri veya öngörülemeyen derlemelerle
sonuçlanabilirsiniz. Örneğin, bir derleme,
[singleton](https://en.wikipedia.org/wiki/Singleton_pattern) gibi davranan
türetme verilerindeki bazı durumlar nedeniyle yerel olarak geçebilir, ancak daha
sonra durum farklı olduğu için CI'da derlenemeyebilir.

::: tip
<!-- -->
Proje şemalarınızda bunu devre dışı bırakmanızı ve bağımlılık grafiğinin
yönetimini kolaylaştıran Tuist gibi kullanmanızı öneririz.
<!-- -->
:::

### SwiftUI Önizlemeleri ve statik kütüphaneler/çerçeveler {#swiftui-previews-and-static-librariesframeworks}

SwiftUI Önizlemeleri veya Swift Makroları gibi bazı editör özellikleri,
düzenlenmekte olan dosyadan bağımlılık grafiğinin derlenmesini gerektirir.
Düzenleyici arasındaki bu entegrasyon, derleme sisteminin herhangi bir örtüklüğü
çözmesini ve bu özelliklerin çalışması için gerekli olan doğru yapıların
çıktısını almasını gerektirir. Tahmin edebileceğiniz gibi **grafik ne kadar
örtük olursa** derleme sistemi için görev o kadar zorlaşır ve bu nedenle bu
özelliklerin çoğunun güvenilir bir şekilde çalışmaması şaşırtıcı değildir.
Geliştiricilerden sık sık SwiftUI önizlemelerini çok güvenilmez oldukları için
uzun zaman önce kullanmayı bıraktıklarını duyuyoruz. Bunun yerine ya örnek
uygulamalar kullanıyorlar ya da özelliğin bozulmasına neden olduğu için statik
kütüphanelerin kullanımı veya komut dosyası oluşturma aşamaları gibi belirli
şeylerden kaçınıyorlar.

### Birleştirilebilir kütüphaneler {#mergeable-libraries}

Dinamik çerçeveler daha esnek ve kullanımı daha kolay olsa da uygulamaların
başlatılma süresinde olumsuz bir etkiye sahiptir. Diğer taraftan, statik
kütüphanelerin başlatılması daha hızlıdır, ancak derleme süresini etkiler ve
özellikle karmaşık grafik senaryolarında çalışmak biraz daha zordur.
*Yapılandırmaya bağlı olarak biri ya da diğeri arasında geçiş yapabilseydiniz
harika olmaz mıydı?* Apple birleştirilebilir kütüphaneler üzerinde çalışmaya
karar verdiğinde böyle düşünmüş olmalı. Ancak bir kez daha, derleme zamanı
çıkarımını derleme zamanına taşıdılar. Bir bağımlılık grafiği hakkında akıl
yürütüyorsanız, hedefin statik veya dinamik doğası bazı hedeflerdeki bazı
derleme ayarlarına dayalı olarak derleme zamanında çözüleceği zaman bunu yapmak
zorunda olduğunuzu hayal edin. SwiftUI önizlemeleri gibi özelliklerin
bozulmamasını sağlarken bunun güvenilir bir şekilde çalışmasını sağlamada iyi
şanslar.

**Tuist'e gelen birçok kullanıcı birleştirilebilir kütüphaneler kullanmak
istiyor ve bizim cevabımız hep aynı. Buna ihtiyacınız yok.** Hedeflerinizin
statik veya dinamik yapısını üretim zamanında kontrol edebilir ve böylece
grafiği derleme öncesinde bilinen bir proje elde edebilirsiniz. Derleme
zamanında hiçbir değişkenin çözümlenmesine gerek yoktur.

```bash
# The value of TUIST_DYNAMIC can be read from the project {#the-value-of-tuist_dynamic-can-be-read-from-the-project}
# to set the product as static or dynamic based on the value. {#to-set-the-product-as-static-or-dynamic-based-on-the-value}
TUIST_DYNAMIC=1 tuist generate
```

## Açık, açık ve açık {#explicit-explicit-and-explicit}

Xcode ile geliştirmelerinin ölçeklenmesini isteyen her geliştiriciye veya
kuruluşa önerdiğimiz önemli bir yazılı olmayan ilke varsa, o da açıklığı
benimsemeleridir. Ve eğer açıklığı ham Xcode projeleriyle yönetmek zorsa,
[Tuist](https://tuist.io) ya da [Bazel](https://bazel.build) gibi başka bir şey
düşünmelidirler. **Ancak o zaman güvenilirlik, öngörülebilirlik ve
optimizasyonlar mümkün olacaktır.**

## Gelecek {#future}

Apple'ın yukarıdaki tüm sorunları önlemek için bir şey yapıp yapmayacağı
bilinmiyor. Xcode ve Swift paketi Yöneticisi'ne yerleştirilmiş sürekli
kararları, bunu yapacaklarını göstermiyor. Örtük yapılandırmaya geçerli bir
durum olarak izin verdiğinizde, **kırıcı değişiklikler getirmeden oradan hareket
etmek zordur.** İlk ilkelere geri dönmek ve araçların tasarımını yeniden
düşünmek, yıllardır yanlışlıkla derlenen birçok Xcode projesinin bozulmasına
neden olabilir. Bunun gerçekleşmesi halinde topluluğun nasıl bir tepki
vereceğini hayal edin.

Apple kendini biraz tavuk-yumurta probleminin içinde buluyor. Kolaylık,
geliştiricilerin hızlı bir şekilde başlamasına ve ekosistemleri için daha fazla
uygulama oluşturmasına yardımcı olan şeydir. Ancak deneyimi bu ölçekte kolay
hale getirme kararları, bazı Xcode özelliklerinin güvenilir bir şekilde
çalışmasını sağlamalarını zorlaştırıyor.

Gelecek bilinmediği için **endüstri standartlarına ve Xcode projelerine** mümkün
olduğunca yakın olmaya çalışıyoruz. Yukarıdaki sorunları önlüyor ve daha iyi bir
geliştirici deneyimi sağlamak için sahip olduğumuz bilgiden yararlanıyoruz.
İdeal olarak bunun için proje oluşturmaya başvurmak zorunda kalmayız, ancak
Xcode'un ve Swift paketi Paket Yöneticisinin genişletilebilirlik eksikliği bunu
tek uygulanabilir seçenek haline getiriyor. Ayrıca bu güvenli bir seçenek çünkü
Tuist projelerini bozmak için Xcode projelerini bozmaları gerekecek.

İdeal olarak, **derleme sistemi daha genişletilebilirdi**, ancak bir örtüklük
dünyasıyla sözleşme yapan eklentilere / uzantılara sahip olmak kötü bir fikir
olmaz mıydı? Bu iyi bir fikir gibi görünmüyor. Bu nedenle, daha iyi bir
geliştirici deneyimi sağlamak için Tuist veya [Bazel](https://bazel.build) gibi
harici araçlara ihtiyacımız olacak gibi görünüyor. Ya da belki Apple hepimizi
şaşırtır ve Xcode'u daha genişletilebilir ve açık hale getirir...

Bu gerçekleşene kadar, Xcode'un ikna ediciliğini benimsemek ve bununla birlikte
gelen borcu üstlenmek mi yoksa daha iyi bir geliştirici deneyimi sağlamak için
bu yolculukta bize güvenmek mi istediğinize karar vermelisiniz. Sizi hayal
kırıklığına uğratmayacağız.
