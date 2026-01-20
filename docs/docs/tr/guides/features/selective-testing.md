---
{
  "title": "Selective testing",
  "titleTemplate": ":title · Features · Guides · Tuist",
  "description": "Use selective testing to run only the tests that have changed since the last successful test run."
}
---
# Seçmeli test {#selective-testing}

Projeniz büyüdükçe testlerinizin miktarı da artar. Uzun bir süre boyunca, her
PR'de tüm testleri çalıştırmak veya `ana` adresine göndermek onlarca saniye
sürer. Ancak bu çözüm, ekibinizin sahip olabileceği binlerce teste ölçeklenemez.

CI üzerindeki her test çalışmasında, değişikliklerden bağımsız olarak büyük
olasılıkla tüm testleri yeniden çalıştırırsınız. Tuist'in seçmeli testi,
<LocalizedLink href="/guides/features/projects/hashing">hashing algoritmamıza</LocalizedLink> dayalı olarak yalnızca son başarılı test
çalışmasından bu yana değişen testleri çalıştırarak testlerin çalıştırılmasını
büyük ölçüde hızlandırmanıza yardımcı olur.

Seçmeli test, herhangi bir Xcode projesini destekleyen `xcodebuild` ile çalışır
veya projelerinizi Tuist ile oluşturuyorsanız, bunun yerine
<LocalizedLink href="/guides/features/cache">binary cache</LocalizedLink> ile
entegrasyon gibi bazı ekstra kolaylıklar sağlayan `tuist test` komutunu
kullanabilirsiniz. Seçmeli teste başlamak için proje kurulumunuza göre
talimatları izleyin:

- <LocalizedLink href="/guides/features/selective-testing/xcode-project">xcodebuild</LocalizedLink>
- <LocalizedLink href="/guides/features/selective-testing/generated-project">Oluşturulmuş proje</LocalizedLink>

::: warning MODULE VS FILE-LEVEL GRANULARITY
<!-- -->
Testler ve kaynaklar arasındaki kod içi bağımlılıkları tespit etmenin
imkansızlığı nedeniyle, seçmeli testin maksimum ayrıntı düzeyi hedef
düzeyindedir. Bu nedenle, seçmeli testin faydalarını en üst düzeye çıkarmak için
hedeflerinizi küçük ve odaklanmış tutmanızı öneririz.
<!-- -->
:::

::: warning TEST COVERAGE
<!-- -->
Test kapsama araçları, tüm test paketinin bir kerede çalıştığını varsayar, bu da
onları seçici test çalıştırmalarıyla uyumsuz hale getirir - bu, test seçimi
kullanılırken kapsama verilerinin gerçeği yansıtmayabileceği anlamına gelir. Bu
bilinen bir sınırlamadır ve yanlış bir şey yaptığınız anlamına gelmez. Ekipleri,
kapsamın bu bağlamda hala anlamlı bilgiler sağlayıp sağlamadığı konusunda
düşünmeye teşvik ediyoruz ve eğer öyleyse, kapsamın gelecekte seçici
çalıştırmalarla nasıl düzgün çalışacağını düşündüğümüzden emin olabilirsiniz.
<!-- -->
:::


## Çekme/birleştirme isteği yorumları {#pullmerge-request-comments}

::: warning INTEGRATION WITH GIT PLATFORM REQUIRED
<!-- -->
Otomatik çekme/birleştirme isteği yorumları almak için
<LocalizedLink href="/guides/server/accounts-and-projects">Tuist projenizi</LocalizedLink> bir
<LocalizedLink href="/guides/server/authentication">Git platformuyla</LocalizedLink> entegre edin.
<!-- -->
:::

Tuist projeniz [GitHub](https://github.com) gibi Git platformunuza bağlandığında
ve CI wortkflow'unuzun bir parçası olarak `tuist xcodebuild test` veya `tuist
test` kullanmaya başladığınızda, Tuist doğrudan çekme/birleştirme isteklerinizde
hangi testlerin çalıştırıldığını ve hangilerinin atlandığını içeren bir yorum
yayınlayacaktır: ![Tuist Önizleme bağlantısı içeren GitHub uygulaması
yorumu](/images/guides/features/selective-testing/github-app-comment.png)
