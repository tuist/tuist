---
{
  "title": "İlkeler",
  "titleTemplate": ":title · Katkıda Bulunanlar · Tuist",
  "description": "Bu belge, Tuist'in geliştirilmesine rehberlik eden ilkeleri açıklar."
}
---
# İlkeler {#principles}

Bu sayfa, Tuist’in tasarım ve geliştirilmesinin temelini oluşturan ilkeleri açıklar. Bu ilkeler projeyle birlikte evrilir ve projenin temelleriyle uyumlu, sürdürülebilir bir büyümeyi güvence altına almayı amaçlar.

## Varsayılan olarak kurallara uyun {#default-to-conventions}

Tuist’in var olma nedenlerinden biri, Xcode’un kurallar konusunda zayıf olması ve bunun ölçeklenmesi ve bakımı zor karmaşık projelere yol açmasıdır. Bu nedenle Tuist, basit ve özenle tasarlanmış kuralları varsayılan olarak benimseyen farklı bir yaklaşım izler. **Geliştiriciler bu kuralların dışına çıkabilir, ancak bu doğal hissettirmeyen bilinçli bir karardır.**

Örneğin, hedefler arasındaki bağımlılıkları sağlanan genel arayüzü kullanarak tanımlamak için bir kural vardır. Bunu yaparak Tuist, projelerin bağlantının çalışması için doğru yapılandırmalarla oluşturulmasını sağlar. Geliştiriciler bağımlılıkları derleme ayarları aracılığıyla tanımlama seçeneğine sahiptir, ancak bunu örtülü olarak yapacakları için `tuist graph` veya `tuist cache` gibi belirli kuralların izlenmesine dayanan Tuist özelliklerini bozmuş olurlar.

Kuralları varsayılan olarak benimsememizin nedeni, geliştiriciler adına verebileceğimiz karar sayısı arttıkça, onların uygulamaları için özellikler geliştirmeye daha fazla odaklanabilmesidir. Birçok projede olduğu gibi hiçbir kuralımız olmadığında, diğer kararlarla tutarlı olmayan kararlar vermek zorunda kalırız ve bunun sonucunda yönetilmesi zor olan kazara bir karmaşıklık ortaya çıkar.

## Manifest dosyaları tek gerçek kaynağıdır {#manifests-are-the-source-of-truth}

Birbirleriyle çok sayıda yapılandırma katmanı ve sözleşme bulunması, anlaşılması ve bakımı zor bir proje kurulumuyla sonuçlanır. Ortalama bir projeyi bir an düşünün. Projenin tanımı `.xcodeproj` dizinlerinde, CLI betiklerde (örneğin `Fastfiles`) ve CI mantığı ise ardışık düzenlerde yer alır. Bunlar, aralarında sürdürmemiz gereken sözleşmeler bulunan üç katmandır. *Projelerinizde bir şeyi değiştirdiğiniz ve bir hafta sonra dağıtım betiklerinin bozulduğunu fark ettiğiniz durumlarla ne sıklıkla karşılaştınız?*

Bunu tek bir gerçek kaynağı olan manifest dosyalarına sahip olarak basitleştirebiliriz. Bu dosyalar, Tuist’e geliştiricilerin dosyalarını düzenlemek için kullanabileceği Xcode projelerini oluşturmak için ihtiyaç duyduğu bilgileri sağlar. Ayrıca, yerel veya CI ortamından projeleri derlemek için standart komutların kullanılmasına olanak tanır.

**Tuist karmaşıklığı üstlenmeli ve projelerini mümkün olduğunca açık bir şekilde tanımlamak için basit, güvenli ve keyifli bir arayüz sunmalıdır.**

## Örtülü olanı açık hale getirin {#make-the-implicit-explicit}

Xcode örtülü yapılandırmaları destekler. Buna iyi bir örnek, örtülü olarak tanımlanan bağımlılıkların çıkarılmasıdır. Örtülük, yapılandırmaların basit olduğu küçük projeler için uygun olsa da projeler büyüdükçe yavaşlamaya veya garip davranışlara neden olabilir.

Tuist, örtülü Xcode davranışları için açık API’ler sağlamalıdır. Ayrıca Xcode örtülüğünün tanımlanmasını desteklemeli, ancak bunu geliştiricileri açık yaklaşımı tercih etmeye teşvik edecek şekilde uygulamalıdır. Xcode örtülüğünü ve inceliklerini desteklemek, Tuist’in benimsenmesini kolaylaştırır; ardından ekipler örtülüğü ortadan kaldırmak için zaman ayırabilir.

Bağımlılık tanımı buna iyi bir örnektir. Geliştiriciler bağımlılıkları derleme ayarları ve aşamaları aracılığıyla tanımlayabilirken, Tuist benimsenmesini teşvik eden zarif bir API sunar.

**API’nin açık olacak şekilde tasarlanması, Tuist’in projelerde aksi takdirde mümkün olmayacak bazı kontrolleri ve optimizasyonları çalıştırmasına olanak tanır.** Ayrıca, bağımlılık grafiğinin bir temsilini dışa aktaran `tuist graph` veya tüm hedefleri ikili dosya olarak önbelleğe alan `tuist cache` gibi özellikleri etkinleştirir.

> [!TIP]
> Xcode’dan özellik taşıma isteklerinin her birini, kavramları basit ve açık API’lerle basitleştirmek için bir fırsat olarak görmeliyiz.


## Basit tutun {#keep-it-simple}

Xcode projelerini ölçeklendirirken karşılaşılan temel zorluklardan biri, **Xcode’un kullanıcılara çok fazla karmaşıklık sunmasıdır.** Bu nedenle, ekiplerde yüksek "bus factor" riski bulunur ve projeyi ile derleme sisteminin ürettiği hataları yalnızca birkaç kişi anlar. Ekip birkaç kişiye bağımlı olduğu için bu kötü bir durumdur.

Xcode harika bir araçtır, ancak yıllar süren iyileştirmeler, yeni platformlar ve programlama dilleri yüzeyine yansımış ve basit kalmakta zorlanmıştır.

Tuist, işleri basit tutma fırsatını değerlendirmelidir çünkü basit şeyler üzerinde çalışmak eğlencelidir ve motive edicidir. Kimse derleme sürecinin en sonunda oluşan bir hatayı ayıklamaya veya uygulamasını cihazlarında çalıştıramamanın nedenini anlamaya zaman harcamak istemez. Xcode görevleri altındaki derleme sistemine devreder ve bazı durumlarda hataları eyleme dönüştürülebilir adımlara çevirmekte oldukça yetersiz kalır. Hiç *“framework X not found”* hatası alıp ne yapacağınızı bilemediğiniz oldu mu? Hatanın olası kök nedenlerinin bir listesini aldığımızı hayal edin.

## Geliştirici deneyiminden başlayın {#start-from-the-developers-experience}

Xcode çevresindeki yenilik eksikliğinin, başka bir deyişle diğer programlama ortamlarındaki kadar yenilik olmamasının nedenlerinden biri, **sorunları genellikle mevcut çözümlerden başlayarak analiz etmemizdir.** Sonuç olarak, günümüzde bulduğumuz çoğu çözüm aynı fikirler ve iş akışları etrafında döner. Mevcut çözümleri denkleme dahil etmek iyi olsa da, bunların yaratıcılığımızı kısıtlamasına izin vermemeliyiz.

[Tom Preston](https://tom.preston-werner.com/)’ın [bu podcast](https://tom.preston-werner.com/)te belirttiği gibi düşünmeyi seviyoruz: *“Çoğu şey başarılabilir; aklınızda ne varsa, evrenin kısıtlamaları dahilinde mümkün olduğu sürece kodla büyük olasılıkla hayata geçirebilirsiniz.”* Eğer **geliştirici deneyiminin nasıl olmasını istediğimizi hayal edersek**, bunu gerçekleştirmek sadece bir zaman meselesidir — sorunları geliştirici deneyiminden başlayarak analiz etmek, kullanıcıların kullanmaktan keyif alacağı çözümlere bizi yönlendirecek benzersiz bir bakış açısı sağlar.

Herkesin yaptığını takip etme, hatta herkesin şikayet ettiği rahatsızlıklara katlanma anlamına gelse bile, buna karşı direnmek zor olabilir. Bunu yapmayalım. Uygulamamı arşivlemeyi nasıl hayal ediyorum? Kod imzalamanın nasıl olmasını isterdim? Tuist ile hangi süreçleri daha verimli hale getirebilirim? Örneğin, [Fastlane](https://fastlane.tools/) desteği eklemek, öncelikle anlamamız gereken bir soruna çözüm sunar. “Neden” sorularını sorarak sorunun köküne inebiliriz. Motivasyonun kaynağını daralttığımızda, Tuist’in onlara en iyi şekilde nasıl yardımcı olabileceğini düşünebiliriz. Çözüm Fastlane ile entegrasyon olabilir, ancak ödün vermeden önce masaya koyabileceğimiz diğer eşit derecede geçerli çözümleri göz ardı etmememiz önemlidir.

## Hatalar olabilir ve olacaktır {#errors-can-and-will-happen}

Biz geliştiriciler olarak, hataların olabileceğini görmezden gelme eğilimindeyizdir. Sonuç olarak, yazılımı yalnızca ideal senaryoyu dikkate alarak tasarlar ve test ederiz.

Swift, tip sistemi ve iyi kurgulanmış kod bazı hataları önlemeye yardımcı olabilir, ancak hepsini değil; çünkü bazıları kontrolümüz dışındadır. Kullanıcının her zaman internet bağlantısına sahip olacağını veya sistem komutlarının başarıyla döneceğini varsayamayız. Tuist’in çalıştığı ortamlar kontrol ettiğimiz sanal alanlar değildir; bu nedenle, bu ortamların nasıl değişebileceğini ve Tuist’i nasıl etkileyebileceğini anlamak için çaba göstermemiz gerekir.

Kötü yönetilen hatalar kötü kullanıcı deneyimine yol açar ve kullanıcılar projeye olan güvenlerini kaybedebilir. Kullanıcıların Tuist’in her parçasından, hatta hataları onlara sunma biçimimizden bile keyif almalarını istiyoruz.

Kendimizi kullanıcıların yerine koyup hatanın bize ne söylemesini bekleyeceğimizi hayal etmeliyiz. Eğer programlama dili hataların yayıldığı iletişim kanalıysa ve kullanıcılar hataların hedefiyse, hatalar hedef kitlenin (kullanıcıların) konuştuğu dilde yazılmalıdır. Ne olduğunu anlamak için yeterli bilgi içermeli ve ilgili olmayan bilgileri gizlemelidir. Ayrıca, kullanıcıların toparlanmak için atabilecekleri adımları belirterek eyleme dönüştürülebilir olmalıdır.

Son olarak, test durumlarımız başarısız senaryoları da kapsamalıdır. Bu sadece hataları olması gerektiği gibi ele aldığımızdan emin olmamızı sağlamakla kalmaz, aynı zamanda gelecekteki geliştiricilerin bu mantığı bozmasını da engeller.
