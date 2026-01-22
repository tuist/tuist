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

To run tests selectively with your
<LocalizedLink href="/guides/features/projects">generated
project</LocalizedLink>, use the `tuist test` command. The command
<LocalizedLink href="/guides/features/projects/hashing">hashes</LocalizedLink>
your Xcode project the same way it does for the
<LocalizedLink href="/guides/features/cache/module-cache">module
cache</LocalizedLink>, and on success, it persists the hashes to determine what
has changed in future runs. In future runs, `tuist test` transparently uses the
hashes to filter down the tests and run only the ones that have changed since
the last successful test run.

`tuist test` integrates directly with the
<LocalizedLink href="/guides/features/cache/module-cache">module
cache</LocalizedLink> to use as many binaries from your local or remote storage
to improve the build time when running your test suite. The combination of
selective testing with module caching can dramatically reduce the time it takes
to run tests on your CI.

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

Once your Tuist project is connected with your Git platform such as
[GitHub](https://github.com), and you start using `tuist test` as part of your
CI workflow, Tuist will post a comment directly in your pull/merge requests,
including which tests were run and which skipped: ![GitHub app comment with a
Tuist Preview
link](/images/guides/features/selective-testing/github-app-comment.png)
