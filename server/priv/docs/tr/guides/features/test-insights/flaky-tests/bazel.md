---
{
  "title": "Bazel Kararsız Testleri",
  "titleTemplate": ":title · Kararsız Testler · Test İçgörüler · Özellikler · Kılavuzlar · Tuist",
  "description": "Kararsız Bazel testlerini tespit edin, hatalarını sessize alın ve karantinaya alınan hedefleri atlayın."
}
---
# Bazel kararsız testleri {#bazel-flaky-tests}

> [!IMPORTANT]
> **Gereksinimler**
>
> - <.localized_link href="/guides/features/test-insights/bazel">Bazel test içgörüsü</.localized_link>, `tuist bazel setup` aracılığıyla yapılandırılır.

<!-- @snippet: ./_intro -->

## Kararsızlık algılama nasıl çalışır {#how-it-works}

Tuist, Bazel'in `test.xml` raporlarından alınan tekil test senaryolarını kullanarak sürekli entegrasyonda aynı commit ve hedef seçiminin yeniden denemeleri ve farklı çalıştırmaları arasındaki tutarsız sonuçları tespit eder. Yerel çalıştırmalar görünür kalır ancak test senaryolarını otomatik olarak kararsız olarak işaretlemeyebilir.

### Test yeniden denemeleri {#test-retries}

Yeniden denemeler isteğe bağlıdır ve karantinadan bağımsızdır. `--flaky_test_attempts=3`, test başına ek üç yeniden deneme değil, toplamda en fazla **üç Bazel denemesi** sağlar. Mevcut yeniden deneme yapılandırmanızı `.bazelrc` içinde saklayın veya açıkça iletin:

```sh
tuist bazel test -- --flaky_test_attempts=3 //app:tests
```

Tuist'in sonuçları gözlemleyebilmesi için yeniden denemelerin gerçekten çalıştırılması gerekir. Bir Bazel hedefinin kararsızlık özeti tek başına hangi tekil senaryonun kararsız olduğunu belirlemez.

### Çapraz çalışma algılama {#cross-run-detection}

Çalıştırmaları karşılaştırmak için commit ve dal meta verilerine ihtiyaç vardır. Derleme ortamınız bunları zaten yayınlamıyorsa sağlayın:

```sh
tuist bazel test -- \
  --build_metadata=CI=true \
  --build_metadata=GIT_COMMIT="$GIT_COMMIT" \
  --build_metadata=GIT_BRANCH="$GIT_BRANCH" //app:tests
```

Senaryolar; hedef etiketi, sınıf adı (yoksa suite adı) ve test adı ile tanımlanır; ayrıntılar için bkz. <.localized_link href="/guides/features/test-insights/bazel">Bazel test içgörüsü</.localized_link>.

<!-- @snippet: ./_managing -->

## Kararsız testlerin karantinaya alınması {#quarantining}

<!-- @snippet: ./_quarantine-intro -->

`tuist bazel test`, her çağrıdan önce karantina politikasını alır ve bunu alttaki `bazel test` çalıştırmasına uygular. Normal `bazel test` hâlâ test sonuçlarını raporlar ancak karantina uygulamaz:

```sh
tuist bazel test -- //app:tests
```

`--` sonrasındaki argümanlar `bazel test` adresine iletilir. Projeyi ve çalışma dizinini seçmek için `--path`, `bazelisk` gibi farklı bir yürütülebilir dosya seçmek için `--bazel` kullanın. `--config=ci` gibi adlandırılmış bir Bazel yapılandırması isteğe bağlıdır ve aynı şekilde çalışır.

### Sustur {#mute}

Birincil karantina iş akışı olarak **Sustur** seçeneğini kullanın. Susturulan senaryolar çalışmaya devam eder, hataları görünür kalır ve sağlıklı diğer senaryolar sonucu etkilemeye devam eder. Tuist, Bazel'in test hatası çıkış kodunu yalnızca raporlar her başarısız hedefdeki tüm hataları susturulmuş bir senaryoya atfettiğinde başarıya dönüştürür. Derleme hataları, zaman aşımları, kesintiye uğrayan çalıştırmalar, eksik veya tamamlanmamış raporlar ve susturulan küme dışındaki hatalar Bazel'in hata durumunu korur.

### Atla {#skip}

Atlama Bazel hedefi bazında çalışır: bir senaryoyu atlamak, Bazel her test çerçevesi için tekil senaryoları filtreleyemediğinden sağlıklı senaryolar da dahil olmak üzere ilgili hedefin tamamını dışlar. Tüm hedefi hariç tutmayı amaçlamıyorsanız **Sustur** seçeneğini tercih edin. Komut, hariç tutulan her hedef etiketini yazdırarak derleme günlüklerinde karantina politikasının neleri dışladığını gösterir.

Atlanan bir hedef artık mevcut değilse, Tuist bunu bir uyarıda belirtir ve bu dışlama olmadan çalıştırma yapar. Politikalarını kalıcı olarak kaldırmak için eski senaryoları **Etkin** durumuna geri döndürün. Hiçbir test hedefi kalmazsa, Bazel normal "test bulunamadı" çıkış durumunu korur.

<!-- @snippet: ./_quarantined-passing -->

### Karantinaya alınan testleri tekrar çalıştırma {#running-quarantined-tests-again}

Bir düzeltmeyi incelemek veya doğrulamak için karantina politikasını bypass edin:

```sh
tuist bazel test --no-quarantine -- --nocache_test_results //app:tests
```

Hedefini sonraki normal çalıştırmalara dahil etmek için senaryoyu **Etkin** durumuna geri döndürün. Atlanan senaryolar açıkça dahil edilene kadar yeni yürütme oluşturmaz; bu nedenle başarılı yeni çalıştırmalara dayalı bir otomasyonun bunları kurtarmadan önce bir doğrulama çalıştırmasına ihtiyacı vardır.

### Sınırlamalar {#limitations}

- Açık bir `--build_event_json_file` veya `--target_pattern_file`, etkin karantina ile birleştirilemez. Hedef kalıplarını doğrudan iletin.
- Tuist karantina politikasını alamazsa, komut testleri çalıştırmadan önce durur. Kısmi bir politika asla uygulanmaz. Bilerek politika olmadan çalıştırmak istediğinizde `--no-quarantine` kullanın.
- Eski suite tabanlı kimlik altında kaydedilmiş bir susturma ile eşleşen bir hata engellemeye devam eder ve komut, yeniden uygulanacak politikayı adlandırır.

Altta yatan davranış için Bazel'in [test filtrelerine](https://bazel.build/docs/user-manual#test-filter), [komut seçeneklerine](https://bazel.build/reference/command-line-reference) ve [derleme olayı açıklamalarına](https://bazel.build/remote/bep-glossary) bakın.

<!-- @snippet: ./_slack -->

<!-- @snippet: ./_querying -->
