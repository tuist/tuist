---
{
  "title": "Principles",
  "titleTemplate": ":title · Contributors · Tuist",
  "description": "This document describes the principles that guide the development of Tuist."
}
---
# İlkeler {#principles}

Bu sayfa, Tuist'in tasarım ve geliştirilmesinin temelini oluşturan ilkeleri
açıklamaktadır. Bu ilkeler projeyle birlikte gelişir ve proje temeli ile uyumlu,
sürdürülebilir bir büyüme sağlamayı amaçlar.

## Varsayılan kurallara uyun {#default-to-conventions}

Tuist'in var olmasının nedenlerinden biri, Xcode'un kurallara zayıf olması ve
bunun da ölçeklendirilmesi ve bakımı zor olan karmaşık projelere yol açmasıdır.
Bu nedenle Tuist, basit ve kapsamlı bir şekilde tasarlanmış kuralları varsayılan
olarak kullanarak farklı bir yaklaşım benimsemiştir. **Geliştiriciler bu
kuralları devre dışı bırakabilir, ancak bu doğal olmayan bilinçli bir
karardır.**

Örneğin, sağlanan genel arayüzü kullanarak hedefler arasındaki bağımlılıkları
tanımlamak için bir kural vardır. Tuist, bunu yaparak projelerin bağlantının
çalışması için doğru yapılandırmalarla oluşturulmasını sağlar. Geliştiriciler,
derleme ayarları aracılığıyla bağımlılıkları tanımlama seçeneğine sahiptir,
ancak bunu örtük olarak yaparlar ve bu nedenle, bazı kurallara bağlı olan `tuist
graph` veya `tuist cache` gibi Tuist özelliklerini bozarlar.

Varsayılan olarak kuralları kullanmamızın nedeni, geliştiriciler adına ne kadar
çok karar verirsek, onların uygulamaları için özellikler geliştirmeye o kadar
çok odaklanabilecekleridir. Birçok projede olduğu gibi, kurallarımız yoksa,
diğer kararlarla tutarlı olmayan kararlar almak zorunda kalırız ve sonuç olarak,
yönetilmesi zor olan istenmeyen bir karmaşıklık ortaya çıkar.

## Manifestolar gerçeğin kaynağıdır. {#manifests-are-the-source-of-truth}

Aralarında birçok yapılandırma ve sözleşme katmanı olması, projenin kurulumu ve
bakımı konusunda zorluklara neden olur. Ortalama bir projeyi bir saniye düşünün.
Projenin tanımı `.xcodeproj` dizinlerinde, CLI komut dosyalarında (ör.
`Fastfiles`) ve CI mantığı boru hatlarında bulunur. Bunlar, bakımını yapmamız
gereken, aralarında sözleşmeler bulunan üç katmandır. *Projelerinizde bir
değişiklik yaptığınızda, bir hafta sonra sürüm komut dosyalarının bozulduğunu
fark ettiğiniz durumlarla ne sıklıkla karşılaşıyorsunuz?*

Bunu, tek bir doğru kaynak olan manifest dosyalarını kullanarak
basitleştirebiliriz. Bu dosyalar, Tuist'e geliştiricilerin dosyalarını
düzenlemek için kullanabilecekleri Xcode projelerini oluşturmak için ihtiyaç
duyduğu bilgileri sağlar. Ayrıca, yerel veya CI ortamından projeler oluşturmak
için standart komutların kullanılmasına olanak tanır.

**Tuist, karmaşıklığı üstlenmeli ve projelerini olabildiğince açık bir şekilde
tanımlamak için basit, güvenli ve keyifli bir arayüz sunmalıdır.**

## Örtük olanı açık hale getirin {#make-the-implicit-explicit}

Xcode, örtük yapılandırmaları destekler. Bunun iyi bir örneği, örtük olarak
tanımlanmış bağımlılıkları çıkarsamaktır. Yapılandırmaların basit olduğu küçük
projeler için örtüklik sorun teşkil etmezken, projeler büyüdükçe yavaşlamaya
veya garip davranışlara neden olabilir.

Tuist, örtük Xcode davranışları için açık API'ler sağlamalıdır. Ayrıca, Xcode
örtükliğini tanımlamayı desteklemeli, ancak geliştiricileri açık yaklaşımı
tercih etmeye teşvik edecek şekilde uygulanmalıdır. Xcode örtüklüğünü ve
karmaşıklıklarını desteklemek, Tuist'in benimsenmesini kolaylaştırır. Ardından
ekipler, örtüklüğü ortadan kaldırmak için biraz zaman ayırabilirler.

Bağımlılıkların tanımı bunun iyi bir örneğidir. Geliştiriciler, derleme ayarları
ve aşamaları aracılığıyla bağımlılıkları tanımlayabilirken, Tuist,
benimsenmesini teşvik eden güzel bir API sağlar.

**API'yi açık bir şekilde tasarlayarak, Tuist, aksi takdirde mümkün olmayacak
bazı kontroller ve optimizasyonlar yapabilir.** Ayrıca, bağımlılık grafiğinin
bir temsilini dışa aktaran `tuist graph` veya tüm hedefleri ikili dosyalar
olarak önbelleğe alan `tuist cache` gibi özellikleri de etkinleştirir.

::: tip
<!-- -->
Xcode'dan özellikleri aktarma taleplerini, kavramları basit ve açık API'lerle
basitleştirme fırsatı olarak değerlendirmeliyiz.
<!-- -->
:::

## Basit tutun. {#keep-it-simple}

Xcode projelerini ölçeklendirirken karşılaşılan en büyük zorluklardan biri,
**Xcode'un kullanıcılara çok karmaşık bir yapı sunmasıdır.** Bu nedenle, ekipler
yüksek bir otobüs faktörüne sahiptir ve ekipte sadece birkaç kişi projeyi ve
derleme sisteminin verdiği hataları anlayabilmektedir. Ekip birkaç kişiye bağlı
olduğu için bu durum oldukça kötüdür.

Xcode harika bir araçtır, ancak yıllar süren iyileştirmeler, yeni platformlar ve
programlama dilleri, basit kalmaya çalışan arayüzüne yansımıştır.

Tuist, işleri basit tutma fırsatını değerlendirmelidir, çünkü basit işler
üzerinde çalışmak eğlencelidir ve bizi motive eder. Kimse, derleme sürecinin en
sonunda meydana gelen bir hatayı gidermek veya uygulamayı cihazlarında neden
çalıştıramadıklarını anlamak için zaman harcamak istemez. Xcode, görevleri altta
yatan derleme sistemine devreder ve bazı durumlarda hataları eyleme
geçirilebilir öğelere çevirme konusunda çok başarısızdır. *'da "framework X not
found"* hatası aldınız ve ne yapacağınızı bilemediniz mi? Hatanın olası kök
nedenlerinin bir listesini aldığımızı hayal edin.

## Geliştiricinin deneyiminden başlayın {#start-from-the-developers-experience}

Xcode çevresinde yenilik eksikliğinin bir nedeni, veya başka bir deyişle, diğer
programlama ortamlarına göre daha az yenilik olmasının bir nedeni, **genellikle
sorunları mevcut çözümlerden yola çıkarak analiz etmeye başlamamızdır.** Sonuç
olarak, günümüzde bulduğumuz çözümlerin çoğu aynı fikirler ve iş akışları
etrafında dönmektedir. Mevcut çözümleri denklemlerin içine dahil etmek iyi olsa
da, bunların yaratıcılığımızı kısıtlamasına izin vermemeliyiz.

Tom Preston](https://tom.preston-werner.com/)'ın [bu
podcast](https://tom.preston-werner.com/)'de belirttiği gibi düşünmeyi
seviyoruz: *"Çoğu şey başarılabilir, kafanızda ne varsa, evrenin kısıtlamaları
dahilinde mümkün olduğu sürece muhtemelen kodla başarabilirsiniz".* Eğer
**geliştirici deneyiminin nasıl olmasını istediğimizi hayal edersek**, bunu
başarmak sadece zaman meselesidir - sorunları geliştirici deneyiminden analiz
etmeye başlamak bize kullanıcıların severek kullanacağı çözümlere götürecek
benzersiz bir bakış açısı sağlar.

Herkesin yaptığı şeyi takip etmek cazip gelebilir, ancak bu, herkesin şikayet
etmeye devam ettiği rahatsızlıklara katlanmak anlamına gelse bile. Bunu
yapmayalım. Uygulamamı nasıl arşivleyeceğimi hayal ediyorum? Kod imzalama nasıl
olsun isterim? Tuist ile hangi süreçleri kolaylaştırabilirim? Örneğin,
[Fastlane](https://fastlane.tools/) desteği eklemek, önce anlamamız gereken bir
soruna çözümdür. "Neden" soruları sorarak sorunun köküne inebiliriz.
Motivasyonun nereden geldiğini belirledikten sonra, Tuist'in onlara en iyi
şekilde nasıl yardımcı olabileceğini düşünebiliriz. Belki de çözüm Fastlane ile
entegrasyondur, ancak ödün vermeden önce masaya koyabileceğimiz diğer eşit
derecede geçerli çözümleri göz ardı etmememiz önemlidir.

## Hatalar olabilir ve olacaktır. {#errors-can-and-will-happen}

Biz geliştiriciler, hataların olabileceğini göz ardı etme eğilimindeyiz. Sonuç
olarak, yazılımları yalnızca ideal senaryoyu göz önünde bulundurarak tasarlar ve
test ederiz.

Swift, onun tip sistemi ve iyi tasarlanmış bir kod bazı hataları önlemeye
yardımcı olabilir, ancak bazıları bizim kontrolümüz dışında olduğu için hepsini
önleyemez. Kullanıcının her zaman internet bağlantısı olacağını veya sistem
komutlarının başarılı bir şekilde geri döneceğini varsayamayız. Tuist'in
çalıştığı ortamlar bizim kontrol ettiğimiz sanal ortamlar değildir ve bu nedenle
bunların nasıl değişebileceğini ve Tuist'i nasıl etkileyebileceğini anlamak için
çaba sarf etmemiz gerekir.

Kötü yönetilen hatalar, kötü bir kullanıcı deneyimine yol açar ve kullanıcılar
projeye olan güvenlerini kaybedebilir. Kullanıcıların Tuist'in her bir
parçasını, hatta hataları onlara sunma şeklimizi bile sevmelerini istiyoruz.

Kendimizi kullanıcıların yerine koymalı ve hatanın bize ne söylemesini
beklediğimizi hayal etmeliyiz. Programlama dili, hataların yayıldığı iletişim
kanalıysa ve kullanıcılar hataların hedefi ise, hatalar hedef kitlenin
(kullanıcıların) konuştuğu dilde yazılmalıdır. Ne olduğunu anlamak için yeterli
bilgi içermeli ve alakasız bilgileri gizlemelidir. Ayrıca, kullanıcılara
hataları gidermek için atabilecekleri adımları söyleyerek eyleme geçirilebilir
olmalıdır.

Son olarak, test senaryolarımız başarısızlık senaryolarını da dikkate almalıdır.
Bu senaryolar, hataları gerektiği gibi ele aldığımızdan emin olmakla kalmaz,
gelecekteki geliştiricilerin bu mantığı bozmasını da önler.
