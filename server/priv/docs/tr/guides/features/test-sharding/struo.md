---
{
  "title": "Struo Test Parçalama",
  "titleTemplate": ":title · Test Parçalama · Özellikler · Kılavuzlar · Tuist",
  "description": "Tuist üzerinden Struo test gruplarını planlayın, bunları CI çalışanlarına dağıtın ve birleştirilmiş bir test çalıştırmasını inceleyin."
}
---
# Struo test parçalama {#struo-test-sharding}

<a id="once-test-sharding"></a>

Test paketiniz tek bir makineyi aştığında, Struo keşfedilen test yığınlarını CI çalışanlarına dağıtmak için Tuist'i kullanabilir. Çalışanlar atamalarını Struo üzerinden yürütür ve Tuist raporlarını tek bir test çalıştırmasında birleştirir.

> [!IMPORTANT]
> **Gereksinimler**
>
> - <.localized_link href="/guides/get-started/struo-project">Struo ile başlayın</.localized_link> kılavuzunu tamamlayın.
> - [Struo 1.0.0](https://github.com/tuist/struo/releases/tag/1.0.0) veya sonraki bir sürümü, `struo query test-plan --shards` ve `struo test --shard-plan` komutlarıyla kullanın.
> - Seçili test hedefleri için tam keşif yapın ve çalışanlarda aynı kod deposu kopyası ile test ortamının mevcut olduğundan emin olun.

Tuist CLI sarmalayıcısı gerekmez. Struo, yerel Tuist sağlayıcısını ve kimlik bilgilerini kullanır.

## Testlerinizi keşfedin {#discover-your-tests}

Planlamadan önce keşfi oluşturmak için seçili testleri çalıştırın:

```bash
struo test MyTests --format json
```

Kullanılabilir yığın granülerliği çalıştırıcıya bağlıdır. Bazı test hedefleri dosya veya test durumu yığınlarını destekler; diğerleri hedef düzeyinde kalır. Keşif ve yığın oluşturma yetenekleri için [Struo'nun test kılavuzu](https://struo.run/docs/guide/graph/testing)nu takip edin.

## Barındırılan bir plan oluşturun {#create-a-hosted-plan}

Planlama işinde, bu CI yürütmesi tarafından paylaşılan bir referans kullanın:

```bash
struo query test-plan --shards 4 --reference "$CI_EXECUTION_ID" --format json
```

Yanıt, barındırılan bir plan kimliği ve gerçek çalışan indekslerini içerir:

```json
{"shard_plan_id":"<UUID>","shards":[0,1,2,3]}
```

CI matrisinizi `shards` değerinden oluşturun; dört giriş içerdiğini varsaymayın. Boş bir plan boş bir kimlik ve dizi döndürür, bu nedenle hiçbir çalışanın başlatılması gerekmez. Planı daraltmak için `--target` parametresini iletin veya Struo'nun grafik tabanlı seçimini kullanmak için `--changed-path` parametresini tekrarlayın.

Referans varsayılan olarak `TUIST_SHARD_REFERENCE` veya algılanan CI çalıştırmasıdır. Ortamda desteklenen bir CI tanımlayıcısı yoksa açıkça iletin.

## Her parçayı yürütün {#execute-each-shard}

Her çalışana döndürülen plan kimliğini ve kendi indeksini verin:

```bash
struo test --shard-plan "$SHARD_PLAN_ID" --shard-index "$SHARD_INDEX" --jobs 4
```

Alternatif olarak, `TUIST_SHARD_PLAN_ID` ve `TUIST_SHARD_INDEX` değişkenlerini ayarlayın. Çalışanlar tam olarak UUID ile bağlanmış planı indirir ve yalnızca kendilerine atanan yığınları yürütür. Boş bir atama hiçbir şey çalıştırmaz; eksik sonuçlar, başarısız süreçler ve kesintiye uğramış işler bölümü geçemez.

Bu işlem bir test planını dağıtır, önceden derlenmiş bir test-derleme arşivini değil. Gerekli kaynakları, araçları ve keşfi çalışanlarda hazırlayın; paylaşılan önbellekleme uygun derleme işlerinin tekrarlanmasını önleyebilir.

## Yeniden çalıştırmalar ve sonuçlar {#reruns-and-results}

Yeniden çalıştırma için `--shard-attempt` değerini artırın veya `TUIST_SHARD_ATTEMPT` değişkenini ayarlayın. Aksi takdirde Struo GitHub çalıştırma denemesini kullanır ve varsayılan olarak 1'e ayarlar. `--shard-report-revision` varsayılan olarak 0'dır ve aynı deneme içinde bir raporu düzeltirken artırılabilir. Bu sayaçlar, bir testin yeniden denemelerinden bağımsızdır.

Planı, dengeli dağılımı ve bildirilen çalışanları incelemek için **Tests → Shards** bölümünü açın, ardından bireysel sonuçlar için birleştirilmiş test çalıştırmasını açın. Struo'nun zamanlama birimleri **Batches** olarak etiketlenir; test durumları kendi hedef, paket ve test adlarını korur.

Raporlama ayrıntıları ve kapsam sınırlamaları için <.localized_link href="/guides/features/test-insights/struo">Struo test içgörülerine</.localized_link> bakın.
