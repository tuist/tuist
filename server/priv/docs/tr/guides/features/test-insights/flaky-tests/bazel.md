---
{
  "title": "Bazel Kararsız Testler",
  "titleTemplate": ":title · Kararsız Testler · Test İçgörüleri · Özellikler · Kılavuzlar · Tuist",
  "description": "Kararsız Bazel testlerini tespit edin, hatalarını sessize alın ve karantinaya alınan hedefleri atlayın."
}
---
# Bazel kararsız testleri {#bazel-flaky-tests}

> [!IMPORTANT]
> **Gereksinimler**
>
> - <.localized_link href="/guides/features/test-insights/bazel">Bazel test içgörülerinin</.localized_link> `tuist bazel setup` aracılığıyla yapılandırılması gerekir.

<!-- @snippet: ./_intro -->

## Kararsızlık algılamanın nasıl çalıştığı {#how-it-works}

Tuist, Bazel'in `test.xml` raporlarından gelen tekil test vakalarını kullanarak sürekli entegrasyonda aynı commit ve hedef seçiminin yeniden denemeleri ve farklı çalıştırmaları arasındaki tutarsız sonuçları tespit eder. Yerel çalıştırmalar görünür kalır ancak test vakalarını otomatik olarak kararsız olarak işaretlemez.

### Test yeniden denemeleri {#test-retries}

Yeniden denemeler isteğe bağlıdır ve karantinadan bağımsızdır. `--flaky_test_attempts=3`, test başına en fazla **üç toplam Bazel denemesi** sağlar; bu, üç ek yeniden deneme anlamına gelmez. Mevcut yeniden deneme yapılandırmanızı `.bazelrc` içinde tutun veya açıkça belirtin:

```sh
tuist bazel test -- --flaky_test_attempts=3 //app:tests
```

Tuist'in sonuçları gözlemleyebilmesi için yeniden denemelerin gerçekten çalışması gerekir. Bir Bazel hedefinin kararsızlık özeti tek başına hangi tekil vakanın kararsız olduğunu belirlemez.

### Çalıştırma karşılaştırmalı algılama {#cross-run-detection}

Çalıştırmaları karşılaştırmak için commit ve dal meta verilerine ihtiyaç vardır. Derleme ortamınız bunları zaten yayınlamıyorsa sağlayın:

```sh
tuist bazel test -- \
  --build_metadata=CI=true \
  --build_metadata=GIT_COMMIT="$GIT_COMMIT" \
  --build_metadata=GIT_BRANCH="$GIT_BRANCH" //app:tests
```

Vakalar, <.localized_link href="/guides/features/test-insights/bazel">Bazel test içgörülerinde</.localized_link> açıklandığı gibi hedef etiketi, sınıf adı (yoksa paket adı) ve test adına göre tanımlanır.

<!-- @snippet: ./_managing -->

## Kararsız testlerin karantinaya alınması {#quarantining}

<!-- @snippet: ./_quarantine-intro -->

`tuist bazel test`, her çağrıdan önce karantina politikasını alır ve bunu alttaki `bazel test` çalıştırmasına uygular. Normal `bazel test` yine test sonuçlarını bildirir ancak karantinayı uygulamaz:

```sh
tuist bazel test -- //app:tests
```

`--` sonrasındaki argümanlar `bazel test` öğesine iletilir. Projeyi ve çalışma dizinini seçmek için `--path`, `bazelisk` gibi farklı bir yürütülebilir dosya seçmek için `--bazel` kullanın. `--config=ci` gibi adlandırılmış bir Bazel yapılandırması isteğe bağlıdır ve aynı şekilde çalışır.

### Sustur {#mute}

Birincil karantina iş akışı olarak **Sustur** seçeneğini kullanın. Susturulan vakalar çalışmaya devam eder, hataları görünür kalır ve sağlıklı diğer vakalar sonucu etkilemeye devam eder. Tuist, Bazel'in test hatası çıkış kodunu yalnızca raporlar, başarısız olan her hedefdeki tüm hataları susturulmuş bir vakaya atfettiğinde başarıya dönüştürür. Derleme hataları, zaman aşımları, kesintiye uğramış çalıştırmalar, eksik veya tamamlanmamış raporlar ve susturulan küme dışındaki hatalar Bazel'in hata durumunu korur.

### Atla {#skip}

Atlama işlemi Bazel hedefi bazında çalışır: bir vakayı atlamak, Bazel her test çerçevesi için tekil vakaları filtreleyemediğinden sağlıklı vakalar dahil olmak üzere tüm hedefi dışlar. Tüm hedefi hariç tutmayı amaçlamıyorsanız **Sustur** seçeneğini tercih edin. Komut, hariç tutulan her hedef etiketini yazdırır; böylece derleme günlüklerinde karantina politikasının neleri dışladığı görülür.

Atlanan bir hedef artık mevcut değilse, Tuist bunu bir uyarıda belirtir ve bu dışlama olmadan çalıştırır. Politikalarını kalıcı olarak kaldırmak için eski vakaları **Etkin** durumuna geri döndürün. Hiç test hedefi kalmazsa, Bazel normal "test bulunamadı" çıkış durumunu korur.

<!-- @snippet: ./_quarantined-passing -->

### Karantinaya alınan testleri yeniden çalıştırma {#running-quarantined-tests-again}

Bir düzeltmeyi incelemek veya doğrulamak için karantina politikasını bypass edin:

```sh
tuist bazel test --no-quarantine -- --nocache_test_results //app:tests
```

Hedefini sonraki normal çalıştırmalara dahil etmek için vakayı **Etkin** durumuna geri döndürün. Atlanan vakalar, açıkça dahil edilene kadar yeni yürütme oluşturmaz; bu nedenle başarılı yeni çalıştırmalara dayanan bir otomasyonun bunları kurtarmadan önce bir doğrulama çalıştırmasına ihtiyacı vardır.

### Sınırlamalar {#limitations}

- Açık bir `--build_event_json_file` veya `--target_pattern_file`, aktif karantinayla birleştirilemez. Hedef kalıplarını doğrudan iletin.
- Tuist karantina politikasını alamazsa, komut testleri çalıştırmadan önce durur. Asla kısmi bir politika uygulamaz. Bilerek politika olmadan çalıştırmak istediğinizde `--no-quarantine` kullanın.
- Eski paket tabanlı kimlik altında kaydedilmiş bir susturma ile eşleşen bir hata engelleyici olmaya devam eder ve komut, uygulanacak politikayı adlandırır.

Altta yatan davranış için Bazel'in [test filtrelerine](https://bazel.build/docs/user-manual#test-filter), [komut seçeneklerine](https://bazel.build/reference/command-line-reference) ve [derleme olayı açıklamalarına](https://bazel.build/remote/bep-glossary) bakın.

<!-- @snippet: ./_slack -->

<!-- @snippet: ./_querying -->
