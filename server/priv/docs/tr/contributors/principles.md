---
{
  "title": "İlkeler",
  "titleTemplate": ":title · Katkıda Bulunanlar · Tuist",
  "description": "Bu belge, Tuist'in geliştirilmesine rehberlik eden ilkeleri açıklar."
}
---
# İlkeler {#principles}

Bu sayfa, Tuist’in tasarım ve geliştirilmesinin temelini oluşturan ilkeleri açıklar. Bu ilkeler projeyle birlikte evrilir ve projenin temelleriyle uyumlu, sürdürülebilir bir büyümeyi sağlamayı amaçlar.

## Varsayılan olarak kurallara uyun {#default-to-conventions}

Tuist’in varoluş nedenlerinden biri, Xcode’un kurallar konusunda zayıf olması ve bunun ölçeklenmesi ve bakımı zor karmaşık projelere yol açmasıdır. Bu nedenle Tuist, basit ve özenle tasarlanmış kuralları varsayılan olarak benimseyen farklı bir yaklaşım izler. **Geliştiriciler bu kurallardan çıkabilir, ancak bu doğal hissettirmeyen bilinçli bir karardır.**

Örneğin, hedefler arasındaki bağımlılıkları sağlanan genel arayüzü kullanarak tanımlamak için bir kural vardır. Bunu yaparak Tuist, projelerin bağlantının çalışması için doğru yapılandırmalarla oluşturulmasını sağlar. Geliştiriciler bağımlılıkları derleme ayarları aracılığıyla tanımlama seçeneğine sahiptir, ancak bunu örtük olarak yapacakları için `tuist graph` veya `tuist cache` gibi bazı kuralların takip edilmesine dayanan Tuist özelliklerini bozmuş olurlar.

Kuralları varsayılan olarak benimsememizin nedeni, geliştiriciler adına verebileceğimiz karar sayısı arttıkça, uygulamaları için özellikler geliştirmeye daha fazla odaklanabilmeleridir. Birçok projede olduğu gibi hiçbir kural olmadığında, diğer kararlarla tutarlı olmayan kararlar vermek zorunda kalırız ve bunun sonucunda yönetilmesi zor kazara oluşan bir karmaşıklık ortaya çıkar.

## Manifest dosyaları tek doğruluk kaynağıdır {#manifests-are-the-source-of-truth}

Birçok yapılandırma katmanı ve bunlar arasındaki sözleşmeler, anlaşılması ve bakımı zor bir proje kurulumuyla sonuçlanır. Ortalama bir projeyi bir an düşünün. Projenin tanımı `.xcodeproj` dizinlerinde, CLI betiklerde (örneğin `Fastfiles`) ve CI mantığı boru hatlarında yer alır. Bunlar, aralarında sürdürmemiz gereken sözleşmeler bulunan üç katmandır. *Projelerinizde bir şeyi değiştirdiğiniz ve bir hafta sonra yayınlama betiklerinin bozulduğunu fark ettiğiniz bir durumda kaç kez bulundunuz?*

Bunu, tek bir doğruluk kaynağı olan manifest dosyalarına sahip olarak basitleştirebiliriz. Bu dosyalar, Tuist’e geliştiricilerin dosyalarını düzenlemek için kullanabileceği Xcode projelerini oluşturmak için ihtiyaç duyduğu bilgileri sağlar. Ayrıca, yerel veya CI ortamından projeleri derlemek için standart komutların kullanılmasına olanak tanır.

**Tuist karmaşıklığı üstlenmeli ve projelerini mümkün olduğunca açık bir şekilde tanımlamak için basit, güvenli ve keyifli bir arayüz sunmalıdır.**

## Örtük olanı açık hale getirin {#make-the-implicit-explicit}

Xcode örtük yapılandırmaları destekler. Buna iyi bir örnek, örtük olarak tanımlanan bağımlılıkların çıkarılmasıdır. Örtüklük, yapılandırmaların basit olduğu küçük projeler için uygun olsa da, projeler büyüdükçe yavaşlamaya veya garip davranışlara neden olabilir.

Tuist, örtük Xcode davranışları için açık API’ler sağlamalıdır. Ayrıca Xcode örtüklüğünü tanımlamayı desteklemeli, ancak bunu geliştiricileri açık yaklaşımı tercih etmeye teşvik edecek şekilde uygulamalıdır. Xcode örtüklüğünü ve inceliklerini desteklemek, Tuist’in benimsenmesini kolaylaştırır; ardından ekipler örtüklükten kurtulmak için biraz zaman ayırabilir.

Bağımlılık tanımı buna iyi bir örnektir. Geliştiriciler bağımlılıkları derleme ayarları ve aşamaları aracılığıyla tanımlayabilse de, Tuist benimsenmesini teşvik eden güzel bir API sunar.

**API’yi açık olacak şekilde tasarlamak, Tuist’in aksi takdirde mümkün olmayacak bazı kontrolleri ve optimizasyonları projelerde çalıştırmasına olanak tanır.** Ayrıca, bağımlılık grafiğinin bir temsilini dışa aktaran `tuist graph` veya tüm hedefleri ikili dosya olarak önbelleğe alan `tuist cache` gibi özellikleri etkinleştirir.

> [!TIP]
> Xcode’dan özellik taşıma isteklerinin her birini, kavramları basit ve açık API’lerle basitleştirme fırsatı olarak görmeliyiz.


## Basit tutun {#keep-it-simple}

Xcode projelerini ölçeklendirirken karşılaşılan temel zorluklardan biri, **Xcode’un kullanıcılara çok fazla karmaşıklık sunmasıdır.** Bunun nedeniyle, ekiplerde yüksek "bus factor" riski vardır ve projeyi ile derleme sisteminin ürettiği hataları yalnızca birkaç kişi anlayabilir. Ekip birkaç kişiye güvendiği için bu kötü bir durumdur.

Xcode harika bir araçtır, ancak yıllar süren iyileştirmeler, yeni platformlar ve programlama dilleri yüzeyine yansımış ve basit kalmakta zorlanmıştır.

Tuist, işleri basit tutma fırsatını değerlendirmelidir çünkü basit şeylerle çalışmak eğlencelidir ve motive edicidir. Kimse derleme sürecinin en sonunda oluşan bir hatayı ayıklamaya veya uygulamasını cihazlarında neden çalıştıramadıklarını anlamaya zaman harcamak istemez. Xcode görevleri alttaki derleme sistemine devreder ve bazı durumlarda hataları eyleme dönüştürülebilir öğelere çevirmekte oldukça yetersiz kalır. Hiç *“framework X not found”* hatası alıp ne yapacağınızı bilemediğiniz oldu mu? Hatanın olası kök nedenlerinin bir listesini aldığımızı hayal edin.

## Geliştirici deneyiminden başlayın {#start-from-the-developers-experience}

Xcode çevresinde yenilik eksikliğinin, başka bir deyişle diğer programlama ortamlarındaki kadar yenilik olmamasının nedenlerinden biri, **sorunları genellikle mevcut çözümlerden analiz etmeye başlamamızdır.** Sonuç olarak, günümüzde bulduğumuz çoğu çözüm aynı fikirler ve iş akışları etrafında dönüyor. Mevcut çözümleri denkleme dahil etmek iyi olsa da, bunların yaratıcılığımızı kısıtlamasına izin vermemeliyiz.

[Tom Preston](https://tom.preston-werner.com/)’ın [bu podcast](https://tom.preston-werner.com/)te belirttiği gibi düşünmeyi seviyoruz: *“Çoğu şey başarılabilir; aklınızda ne varsa, evrenin kısıtlamaları içinde mümkün olduğu sürece kodla büyük olasılıkla gerçekleştirebilirsiniz.”* Eğer **geliştirici deneyiminin nasıl olmasını istediğimizi hayal edersek**, bunu gerçekleştirmek sadece bir zaman meselesidir — sorunları geliştirici deneyiminden analiz etmeye başlamak, kullanıcıların kullanmayı seveceği çözümlere bizi yönlendirecek benzersiz bir bakış açısı sağlar.

Herkesin ne yaptığını takip etmeye, hatta herkesin şikayet etmeye devam ettiği rahatsızlıklara katlanmak anlamına gelse bile, kendimizi kaptırabiliriz. Bunu yapmayalım. Uygulamamı arşivlemeyi nasıl hayal ediyorum? Kod imzalamanın nasıl olmasını isterdim? Tuist ile hangi süreçleri daha verimli hale getirebilirim? Örneğin, [Fastlane](https://fastlane.tools/) desteği eklemek, öncelikle anlamamız gereken bir soruna yönelik bir çözümdür. “Neden” sorularını sorarak sorunun köküne inebiliriz. Motivasyonun kaynağını daralttığımızda, Tuist’in onlara en iyi nasıl yardımcı olabileceğini düşünebiliriz. Belki çözüm Fastlane ile entegre olmaktır, ancak ödünleşimlere gitmeden önce masaya koyabileceğimiz diğer eşit derecede geçerli çözümleri göz ardı etmemek önemlidir.

## Hatalar olabilir ve olacaktır {#errors-can-and-will-happen}

Biz geliştiriciler olarak, hataların olabileceğini görmezden gelme eğilimindeyiz. Sonuç olarak, yazılımı yalnızca ideal senaryoyu dikkate alarak tasarlıyor ve test ediyoruz.

Swift, tip sistemi ve iyi mimarlanmış kod bazı hataları önlemeye yardımcı olabilir, ancak hepsini değil; çünkü bazıları kontrolümüz dışındadır. Kullanıcının her zaman internet bağlantısına sahip olacağını veya sistem komutlarının başarılı bir şekilde döneceğini varsayamayız. Tuist’in çalıştığı ortamlar kontrol ettiğimiz sanal alanlar değildir; bu nedenle, bu ortamların nasıl değişebileceğini ve Tuist’i nasıl etkileyebileceğini anlamak için çaba göstermemiz gerekir.

Kötü yönetilen hatalar kötü bir kullanıcı deneyimine yol açar ve kullanıcılar projeye olan güvenlerini kaybedebilir. Kullanıcıların Tuist’in her parçasından, hatta hataları onlara sunma biçimimizden bile keyif almalarını istiyoruz.

Kendimizi kullanıcıların yerine koymalı ve hatanın bize ne söylemesini bekleyeceğimizi hayal etmeliyiz. Programlama dili hataların yayıldığı iletişim kanalıysa ve kullanıcılar hataların hedefiyse, hatalar hedef kitlenin (kullanıcıların) konuştuğu dilde yazılmalıdır. Ne olduğunu anlamak için yeterli bilgi içermeli ve ilgili olmayan bilgileri gizlemelidir. Ayrıca, kullanıcıların toparlanmak için atabilecekleri adımları belirterek eyleme dönüştürülebilir olmalıdır.

Son olarak, test durumlarımız başarısız senaryoları da kapsamalıdır. Bu sadece hataları olması gerektiği gibi ele aldığımızdan emin olmakla kalmaz, aynı zamanda gelecekteki geliştiricilerin bu mantığı bozmasını da engeller.
