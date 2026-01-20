---
{
  "title": "Principles",
  "titleTemplate": ":title · Contributors · Tuist",
  "description": "This document describes the principles that guide the development of Tuist."
}
---
# Prensipler {#principles}

Bu sayfada, Tuist'in tasarım ve geliştirilmesinde temel teşkil eden ilkeler
açıklanmaktadır. Bunlar projeyle birlikte gelişir ve proje temeliyle uyumlu
sürdürülebilir bir büyüme sağlamayı amaçlar.

## Varsayılan kurallar {#default-to-conventions}

Tuist'in var olma nedenlerinden biri, Xcode'un kurallar konusunda zayıf olması
ve bunun da ölçeklendirilmesi ve bakımı zor olan karmaşık projelere yol
açmasıdır. Bu nedenle Tuist, basit ve kapsamlı bir şekilde tasarlanmış kuralları
varsayılan olarak kabul ederek farklı bir yaklaşım benimsiyor. **Geliştiriciler
kurallardan vazgeçebilir, ancak bu doğal hissettirmeyen bilinçli bir karardır.**

Örneğin, sağlanan genel arayüzü kullanarak hedefler arasındaki bağımlılıkları
tanımlamak için bir kural vardır. Tuist bunu yaparak, projelerin bağlantıların
çalışması için doğru konfigürasyonlarla oluşturulmasını sağlar. Geliştiriciler
bağımlılıkları derleme ayarları aracılığıyla tanımlama seçeneğine sahiptir,
ancak bunu örtük olarak yaparlar ve bu nedenle bazı kuralların izlenmesine
dayanan `tuist graph` veya `tuist cache` gibi Tuist özelliklerini bozarlar.

Kurallara bağlı kalmamızın nedeni, geliştiriciler adına ne kadar çok karar
verebilirsek, uygulamaları için özellik oluşturmaya o kadar çok odaklanabilecek
olmalarıdır. Birçok projede olduğu gibi elimizde hiçbir kural olmadığında, diğer
kararlarla tutarlı olmayan kararlar almak zorunda kalırız ve bunun sonucunda da
yönetilmesi zor bir karmaşıklık ortaya çıkar.

## Manifestolar gerçeğin kaynağıdır {#manifests-are-the-source-of-truth}

Çok sayıda konfigürasyon katmanına ve bunlar arasında sözleşmelere sahip olmak,
mantık yürütmesi ve sürdürmesi zor bir proje kurulumuyla sonuçlanır. Ortalama
bir proje üzerinde bir saniye düşünün. Projenin tanımı `.xcodeproj`
dizinlerinde, CLI komut dosyalarında (örneğin `Fastfiles`) ve CI mantığı boru
hatlarında bulunur. Bunlar, aralarında sürdürmemiz gereken sözleşmeler olan üç
katmandır. *Ne sıklıkla projelerinizde bir şeyleri değiştirdiğiniz ve bir hafta
sonra sürüm betiklerinin bozulduğunu fark ettiğiniz bir durumda kaldınız?*

Tek bir doğruluk kaynağına, yani manifesto dosyalarına sahip olarak bunu
basitleştirebiliriz. Bu dosyalar Tuist'e, geliştiricilerin dosyalarını
düzenlemek için kullanabilecekleri Xcode projeleri oluşturmak için ihtiyaç
duyduğu bilgileri sağlar. Ayrıca, yerel veya CI ortamından projeler oluşturmak
için standart komutlara sahip olmayı sağlar.

**Tuist, karmaşıklığı sahiplenmeli ve projelerini olabildiğince açık bir şekilde
tanımlamak için basit, güvenli ve eğlenceli bir arayüz ortaya koymalıdır.**

## Örtülü olanı açık hale getirin {#make-the-implicit-explicit}

Xcode örtük yapılandırmaları destekler. Bunun iyi bir örneği, örtük olarak
tanımlanmış bağımlılıkların çıkarılmasıdır. Yapılandırmaların basit olduğu küçük
projeler için örtüklük iyi olsa da, projeler büyüdükçe yavaşlığa veya garip
davranışlara neden olabilir.

Tuist, örtük Xcode davranışları için açık API'ler sağlamalıdır. Ayrıca Xcode
örtüklüğünün tanımlanmasını desteklemeli ancak geliştiricileri açık yaklaşımı
tercih etmeye teşvik edecek şekilde uygulanmalıdır. Xcode örtüklüğünü ve
karmaşıklıklarını desteklemek Tuist'in benimsenmesini kolaylaştırır, ardından
ekiplerin örtüklükten kurtulması biraz zaman alabilir.

Bağımlılıkların tanımlanması buna iyi bir örnektir. Geliştiriciler
bağımlılıkları derleme ayarları ve aşamaları aracılığıyla tanımlayabilirken,
Tuist bunun benimsenmesini teşvik eden güzel bir API sağlar.

**API'nin açık olacak şekilde tasarlanması, Tuist'in projeler üzerinde aksi
takdirde mümkün olmayacak bazı kontroller ve optimizasyonlar yapmasını sağlar.**
Ayrıca, bağımlılık grafiğinin bir temsilini dışa aktaran `tuist graph` veya tüm
hedefleri ikili dosyalar olarak önbelleğe alan `tuist cache` gibi özellikleri
etkinleştirir.

::: tip
<!-- -->
Xcode'dan özelliklerin taşınmasına yönelik her talebi, basit ve açık API'lerle
kavramları basitleştirmek için bir fırsat olarak değerlendirmeliyiz.
<!-- -->
:::

## Basit tutun {#keep-it-simple}

Xcode projelerini ölçeklendirirken karşılaşılan temel zorluklardan biri,
**Xcode'un kullanıcılara çok fazla karmaşıklık sunmasından kaynaklanmaktadır.**
Bu nedenle, ekipler yüksek bir veri yolu faktörüne sahiptir ve ekipteki yalnızca
birkaç kişi projeyi ve derleme sisteminin attığı hataları anlar. Bu içinde
bulunulması kötü bir durum çünkü ekip birkaç kişiye güveniyor.

Xcode harika bir araç, ancak yıllarca süren iyileştirmeler, yeni platformlar ve
programlama dilleri, basit kalmak için mücadele eden yüzeyine yansıyor.

Tuist, işleri basit tutma fırsatını değerlendirmelidir çünkü basit şeyler
üzerinde çalışmak eğlencelidir ve bizi motive eder. Hiç kimse derleme sürecinin
en sonunda meydana gelen bir hatayı ayıklamak veya uygulamayı cihazlarında neden
çalıştıramadıklarını anlamak için zaman harcamak istemez. Xcode, görevleri temel
derleme sistemine devrediyor ve bazı durumlarda hataları eyleme geçirilebilir
öğelere dönüştürme konusunda çok kötü bir iş çıkarıyor. Hiç *"framework X not
found"* hatası aldınız ve ne yapacağınızı bilemediniz mi? Hatanın olası kök
nedenlerinin bir listesini aldığımızı hayal edin.

## Geliştiricinin deneyiminden yola çıkın {#start-from-the-developers-experience}

Xcode'da yenilik eksikliğinin ya da başka bir deyişle diğer programlama
ortamlarında olduğu kadar yenilik olmamasının bir nedeni de **sorunları analiz
etmeye genellikle mevcut çözümlerden başlamamızdır.** Sonuç olarak, bugünlerde
bulduğumuz çözümlerin çoğu aynı fikirler ve iş akışları etrafında dönüyor.
Mevcut çözümleri denklemlere dahil etmek iyi olsa da, bunların yaratıcılığımızı
kısıtlamasına izin vermemeliyiz.

Tom Preston](https://tom.preston-werner.com/)'ın [bu
podcast](https://tom.preston-werner.com/)'de belirttiği gibi düşünmeyi
seviyoruz: *"Çoğu şey başarılabilir, kafanızda ne varsa muhtemelen evrenin
kısıtlamaları dahilinde mümkün olduğu sürece kodla başarabilirsiniz".* Eğer
**geliştirici deneyiminin nasıl olmasını istediğimizi hayal edersek**, bunu
başarmak sadece zaman meselesidir - sorunları geliştirici deneyiminden analiz
etmeye başlamak bize kullanıcıların severek kullanacağı çözümlere götürecek
benzersiz bir bakış açısı sağlar.

Herkesin şikayet etmeye devam ettiği rahatsızlıklara katlanmak anlamına gelse
bile, herkesin yaptığını takip etmek bize cazip gelebilir. Bunu yapmayalım.
Uygulamamı arşivlemeyi nasıl hayal ediyorum? Kod imzalamanın nasıl olmasını
isterdim? Tuist ile hangi süreçleri kolaylaştırmaya yardımcı olabilirim?
Örneğin, [Fastlane](https://fastlane.tools/) için destek eklemek, önce anlamamız
gereken bir soruna çözümdür. "Neden" sorusunu sorarak sorunun kökenine
inebiliriz. Motivasyonun nereden geldiğini daralttıktan sonra, Tuist'in onlara
en iyi nasıl yardımcı olabileceğini düşünebiliriz. Belki de çözüm Fastlane ile
entegre olmaktır, ancak değiş tokuş yapmadan önce masaya koyabileceğimiz eşit
derecede geçerli diğer çözümleri göz ardı etmememiz önemlidir.

## Hatalar olabilir ve olacaktır {#errors-can-and-will-happen}

Biz geliştiricilerin doğasında hataların olabileceğini göz ardı etme eğilimi
vardır. Sonuç olarak, yazılımı yalnızca ideal senaryoyu göz önünde bulundurarak
tasarlıyor ve test ediyoruz.

Swift, tip sistemi ve iyi tasarlanmış bir kod bazı hataları önlemeye yardımcı
olabilir, ancak hepsini değil çünkü bazıları bizim kontrolümüz dışında.
Kullanıcının her zaman internet bağlantısına sahip olacağını ya da sistem
komutlarının başarıyla geri döneceğini varsayamayız. Tuist'in çalıştığı ortamlar
bizim kontrolümüzde olan kum havuzları değildir ve bu nedenle bunların nasıl
değişebileceğini ve Tuist'i nasıl etkileyebileceğini anlamak için çaba
göstermemiz gerekir.

Kötü ele alınan hatalar kötü kullanıcı deneyimine neden olur ve kullanıcılar
projeye olan güvenlerini kaybedebilir. Kullanıcıların Tuist'in her bir
parçasından, hatta hataları onlara sunma şeklimizden bile keyif almalarını
istiyoruz.

Kendimizi kullanıcıların yerine koymalı ve hatanın bize ne söylemesini
beklediğimizi hayal etmeliyiz. Eğer programlama dili hataların yayıldığı bir
iletişim kanalı ve kullanıcılar da hataların hedefi ise, hatalar hedefin
(kullanıcıların) konuştuğu dilde yazılmalıdır. Ne olduğunu bilmek için yeterli
bilgi içermeli ve ilgili olmayan bilgileri gizlemelidirler. Ayrıca,
kullanıcılara bu hatalardan kurtulmak için hangi adımları atabileceklerini
söyleyerek eyleme geçirilebilir olmalıdırlar.

Ve son olarak, test senaryolarımız başarısızlık senaryolarını düşünmelidir.
Bunlar yalnızca hataları olması gerektiği gibi ele aldığımızdan emin olmamızı
sağlamakla kalmaz, aynı zamanda gelecekteki geliştiricilerin bu mantığı
bozmasını da önler.
