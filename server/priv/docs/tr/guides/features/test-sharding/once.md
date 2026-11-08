---
{
  "title": "Once Test Bölümleme",
  "titleTemplate": ":title · Test Bölümleme · Özellikler · Kılavuzlar · Tuist",
  "description": "Once test partilerini Tuist üzerinden planlayın, CI çalışanlarına dağıtın ve birleştirilmiş bir test çalıştırmasını inceleyin."
}
---
# Once test bölümlendirme {#once-test-sharding}

Test paketiniz tek bir makineyi aştığında, Once Tuist'ten keşfedilen test gruplarını CI çalışanlarına dağıtmasını isteyebilir. Çalışanlar atamalarını Once üzerinden yürütür ve Tuist raporlarını tek bir test çalıştırmasında birleştirir.

> [!IMPORTANT]
> **Gereksinimler**
>
> - <.localized_link href="/guides/get-started/once-project">Once ile başlayın</.localized_link> adımını tamamlayın.
> - `once query test-plan --shards` ve `once test --shard-plan` komutlarını sunan bir Once sürümü kullanın. Once 0.71.0 yalnızca taşınabilir planları destekler; bu barındırılan iş akışını desteklemez.
> - Seçili test hedefleri için tam keşif yapın ve çalışanlarda aynı kod kopyası ile test ortamının mevcut olduğundan emin olun.

Tuist CLI sarmalayıcısı gerekmez. Once yerel Tuist sağlayıcısını ve kimlik bilgilerini kullanır.

## Testlerinizi keşfedin {#discover-your-tests}

Planlamadan önce keşfi oluşturmak için seçili testleri çalıştırın:

```bash
once test MyTests --format json
```

Kullanılabilir grup granülerliği çalıştırıcıya bağlıdır. Bazı test hedefleri dosya veya durum bazlı grupları destekler; diğerleri hedef düzeyinde kalır. Keşif ve gruplama yetenekleri için [Once'ın test kılavuzunu](https://buildonce.dev/docs/guide/graph/testing) takip edin.

## Barındırılan bir plan oluşturun {#create-a-hosted-plan}

Planlama işinde, bu CI yürütmesi tarafından paylaşılan bir referans kullanın:

```bash
once query test-plan --shards 4 --reference "$CI_EXECUTION_ID" --format json
```

Yanıt, barındırılan bir plan kimliği ve gerçek çalışan indekslerini içerir:

```json
{"shard_plan_id":"<UUID>","shards":[0,1,2,3]}
```

CI matrisinizi `shards` değerinden oluşturun; dört girdi içerdiğini varsaymayın. Boş bir plan boş bir kimlik ve dizi döndürür, bu nedenle hiçbir çalışanın başlamasına gerek yoktur. Planı daraltmak için `--target` parametresini iletin veya Once'ın graf tabanlı seçimini kullanmak için `--changed-path` parametresini tekrarlayın.

Referans varsayılan olarak `TUIST_SHARD_REFERENCE` veya algılanan CI çalıştırmasıdır. Ortamda desteklenen bir CI tanımlayıcısı yoksa açıkça belirtin.

## Her bölümü yürütün {#execute-each-shard}

Her çalışana dönen plan kimliğini ve kendi indeksini verin:

```bash
once test --shard-plan "$SHARD_PLAN_ID" --shard-index "$SHARD_INDEX" --jobs 4
```

Alternatif olarak, `TUIST_SHARD_PLAN_ID` ve `TUIST_SHARD_INDEX` değişkenlerini ayarlayın. Çalışanlar tam UUID ile bağlı planı indirir ve yalnızca kendilerine atanmış grupları yürütür. Boş atama hiçbir şey çalıştırmaz; eksik sonuçlar, başarısız işlemler ve kesintiye uğrayan işler bölümü geçemez.

Bu, önceden derlenmiş bir test-derleme arşivi değil, bir test planı dağıtır. Gerekli kaynakları, araçları ve keşfi çalışanlarda hazırlayın; paylaşılan önbellekleme uygun derleme işlerinin tekrarlanmasını önleyebilir.

## Yeniden çalıştırmalar ve sonuçlar {#reruns-and-results}

Yeniden çalıştırma için `--shard-attempt` değerini artırın veya `TUIST_SHARD_ATTEMPT` değerini ayarlayın. Aksi takdirde Once GitHub çalıştırma denemesini kullanır, ardından varsayılan olarak 1 olur. `--shard-report-revision` varsayılan olarak 0'dır ve aynı deneme içinde bir raporu düzeltirken artırılabilir. Bu sayaçlar, bir testin yeniden denemelerinden bağımsızdır.

Planı, dengeliği ve bildirilen çalışanları incelemek için **Tests → Shards** bölümünü açın, ardından bireysel sonuçlar için birleştirilmiş test çalıştırmasını açın. Once'ın zamanlama birimleri **Batches** olarak etiketlenir; durumlar yerel hedef, paket ve test adlarını korur.

Raporlama ayrıntıları ve kapsam sınırlamaları için <.localized_link href="/guides/features/test-insights/once">Once test içgörülerine</.localized_link> bakın.
