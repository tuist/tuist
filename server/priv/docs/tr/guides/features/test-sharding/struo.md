---
{
  "title": "Struo Test Parçalama",
  "titleTemplate": ":title · Test Parçalama · Özellikler · Kılavuzlar · Tuist",
  "description": "Struo test gruplarını Tuist üzerinden planlayın, CI çalışanlarına dağıtın ve birleştirilmiş bir test çalıştırmasını inceleyin."
}
---
# Struo test parçalama {#struo-test-sharding}

<a id="once-test-sharding"></a>

Test suite'unuz tek bir makineyi aştığında, Struo Tuist'ten keşfedilen test yığınlarını CI çalışanlarına dağıtmasını isteyebilir. Çalışanlar atamalarını Struo üzerinden yürütür ve Tuist raporlarını tek bir test çalıştırmasında birleştirir.

> [!IMPORTANT]
> **Gereksinimler**
>
> - <.localized_link href="/guides/get-started/struo-project">Struo ile başlayın</.localized_link> kılavuzunu tamamlayın.
> - [Struo 1.0.0](https://github.com/tuist/struo/releases/tag/1.0.0) veya sonraki bir sürümü kullanın; `struo query test-plan --shards` ve `struo test --shard-plan` komutları gereklidir.
> - Seçili test hedefleri için tam keşif sağlayın ve çalışanlarda aynı checkout ile test ortamının mevcut olduğundan emin olun.

Tuist CLI sarmalayıcısı gerekmez. Struo, yerel Tuist sağlayıcısını ve kimlik bilgilerini kullanır.

## Testlerinizi keşfedin {#discover-your-tests}

Planlamadan önce keşfi sağlamak için seçili testleri çalıştırın:

```bash
struo test MyTests --format json
```

Kullanılabilir yığın granülerliği çalıştırıcıya bağlıdır. Bazı test hedefleri dosya veya durum bazlı yığınları destekler; diğerleri hedef düzeyinde kalır. Keşif ve yığın oluşturma yetenekleri için [Struo'nun test kılavuzu](https://struo.run/docs/guide/graph/testing)nu takip edin.

## Barındırılan bir plan oluşturun {#create-a-hosted-plan}

Planlama işinde, bu CI yürütmesi tarafından paylaşılan bir referans kullanın:

```bash
struo query test-plan --shards 4 --reference "$CI_EXECUTION_ID" --format json
```

Yanıt, barındırılan bir plan kimliği ve gerçek çalışan indekslerini içerir:

```json
{"shard_plan_id":"<UUID>","shards":[0,1,2,3]}
```

CI matrisinizi `shards` değerinden oluşturun; dört giriş içerdiğini varsaymayın. Boş bir plan boş bir kimlik ve dizi döndürür, bu nedenle hiçbir çalışanın başlamasına gerek kalmaz. Planı daraltmak için `--target` parametresini geçirin veya Struo'nun graf tabanlı seçimini kullanmak için `--changed-path` parametresini tekrarlayın.

Referans varsayılan olarak `TUIST_SHARD_REFERENCE` veya algılanan CI çalıştırmasıdır. Ortamda desteklenen bir CI tanımlayıcısı yoksa açıkça belirtin.

## Her parçayı yürütün {#execute-each-shard}

Her çalışana döndürülen plan kimliğini ve kendi indeksini verin:

```bash
struo test --shard-plan "$SHARD_PLAN_ID" --shard-index "$SHARD_INDEX" --jobs 4
```

Alternatif olarak, `TUIST_SHARD_PLAN_ID` ve `TUIST_SHARD_INDEX` değişkenlerini ayarlayın. Çalışanlar tam UUID ile bağlı planı indirir ve yalnızca kendilerine atanan yığınları yürütür. Boş bir atama hiçbir şey çalıştırmaz; eksik sonuçlar, başarısız işlemler ve kesintiye uğramış işler bölümden geçemez.

Bu işlem bir test planı dağıtır, önceden derlenmiş bir test-derleme arşivi değil. Gerekli kaynakları, araçları ve keşfi çalışanlarda hazırlayın; paylaşımlı önbellekleme uygun yapılandırma işlerinin tekrarlanmasını önleyebilir.

## Yeniden çalıştırmalar ve sonuçlar {#reruns-and-results}

Yeniden çalıştırma için `--shard-attempt` değerini artırın veya `TUIST_SHARD_ATTEMPT` değişkenini ayarlayın. Aksi takdirde Struo GitHub çalıştırma denemesini kullanır, ardından varsayılan olarak 1'e ayarlar. `--shard-report-revision` varsayılan olarak 0'dır ve aynı deneme içinde bir raporu düzeltirken artırılabilir. Bu sayaçlar, bir testin yeniden denemelerinden bağımsızdır.

Planı, dengelenmeyi ve bildirilen çalışanları incelemek için **Tests → Shards** bölümünü açın, ardından bireysel sonuçlar için birleştirilmiş test çalıştırmasını açın. Struo'nun zamanlama birimleri **Batches** olarak etiketlenir; durumlar yerel hedef, paket ve test adlarını korur.

Raporlama ayrıntıları ve kapsam sınırlamaları için <.localized_link href="/guides/features/test-insights/struo">Struo test içgörülerine</.localized_link> bakın.
