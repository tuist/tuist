---
{
  "title": "Selective testing",
  "titleTemplate": ":title · Features · Guides · Tuist",
  "description": "Use selective testing to run only the tests that have changed since the last successful test run."
}
---
# Seçmeli test {#selective-testing}

Projeniz büyüdükçe, testlerinizin sayısı da artar. Uzun bir süre boyunca, her PR
veya `ana` adresine yapılan her push için tüm testleri çalıştırmak onlarca
saniye sürer. Ancak bu çözüm, ekibinizin sahip olabileceği binlerce teste
ölçeklenemez.

CI'da her test çalıştırmasında, değişikliklerden bağımsız olarak büyük
olasılıkla tüm testleri yeniden çalıştırırsınız. Tuist'in seçmeli test özelliği,
<LocalizedLink href="/guides/features/projects/hashing">hashing
algoritmamız</LocalizedLink> temelinde son başarılı test çalıştırmasından bu
yana değişen testleri çalıştırarak testlerin çalıştırılma hızını önemli ölçüde
artırmanıza yardımcı olur.

<LocalizedLink href="/guides/features/projects">Oluşturulmuş
proje</LocalizedLink> ile testleri seçici olarak çalıştırmak için, `tuist test`
komutunu kullanın. Komut,
<LocalizedLink href="/guides/features/projects/hashing">hashes</LocalizedLink>
Xcode projenizi <LocalizedLink href="/guides/features/cache/module-cache">modül
önbelleği</LocalizedLink> için yaptığı gibi aynı şekilde hashler ve başarılı
olursa, gelecekteki çalışmalarda neyin değiştiğini belirlemek için hashleri
kalıcı hale getirir. Gelecekteki çalışmalarda, `tuist test` komutu, testleri
filtrelemek ve son başarılı test çalışmasından bu yana değişenleri çalıştırmak
için hash'leri şeffaf bir şekilde kullanır.

`tuist test`, test paketinizi çalıştırırken derleme süresini iyileştirmek için
yerel veya uzak depolama alanınızdan çok sayıda ikili dosyayı kullanmak üzere
doğrudan ikili önbelleğe alma ile entegre olur. İkili önbellekleme ile seçmeli
test kombinasyonu, CI'nızda testleri çalıştırmak için gereken süreyi önemli
ölçüde azaltabilir.

::: warning MODULE VS FILE-LEVEL GRANULARITY
<!-- -->
Testler ve kaynaklar arasındaki kod içi bağımlılıkları tespit etmenin
imkansızlığı nedeniyle, seçmeli testlerin maksimum ayrıntı düzeyi hedef
düzeyindedir. Bu nedenle, seçmeli testlerin faydalarını en üst düzeye çıkarmak
için hedeflerinizi küçük ve odaklanmış tutmanızı öneririz.
<!-- -->
:::

::: warning TEST COVERAGE
<!-- -->
Test kapsamı araçları, tüm test grubunun bir kerede çalıştığını varsayar, bu da
onları seçici test çalıştırmalarıyla uyumsuz hale getirir. Bu, test seçimi
kullanıldığında kapsam verilerinin gerçeği yansıtmayabileceği anlamına gelir. Bu
bilinen bir sınırlamadır ve yanlış bir şey yaptığınız anlamına gelmez.
Ekiplerin, bu bağlamda kapsamın hala anlamlı içgörüler sağladığını düşünmelerini
öneririz. Eğer öyleyse, gelecekte seçici çalıştırmalarda kapsamın düzgün
çalışmasını sağlamak için halihazırda çözümler üzerinde çalıştığımızdan emin
olabilirsiniz.
<!-- -->
:::


## Çekme/birleştirme isteği yorumları {#pullmerge-request-comments}

::: warning INTEGRATION WITH GIT PLATFORM REQUIRED
<!-- -->
Otomatik çekme/birleştirme isteği yorumları almak için
<LocalizedLink href="/guides/server/accounts-and-projects">Tuist
projenizi</LocalizedLink> bir
<LocalizedLink href="/guides/server/authentication">Git
platformuyla</LocalizedLink> entegre edin.
<!-- -->
:::

Tuist projeniz [GitHub](https://github.com) gibi Git platformunuzla bağlandıktan
ve CI iş akışınızın bir parçası olarak `tuist test` kullanmaya başladıktan
sonra, Tuist hangi testlerin çalıştırıldığını ve hangilerinin atlandığını içeren
bir yorumunuzu doğrudan çekme/birleştirme isteklerinize ekleyecektir: ![Tuist
Önizleme bağlantısı içeren GitHub uygulaması
yorumu](/images/guides/features/selective-testing/github-app-comment.png)
