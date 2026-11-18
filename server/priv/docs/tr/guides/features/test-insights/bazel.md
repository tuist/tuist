---
{
  "title": "Bazel Test İçgörüler",
  "titleTemplate": ":title · Test İçgörüler · Özellikler · Kılavuzlar · Tuist",
  "description": "Test performansını ve güvenilirliğini izlemek için Bazel test analizlerini Tuist kontrol panelinde takip edin."
}
---
# Bazel test içgörüleri {#bazel-test-insights}

> [!IMPORTANT]
> **Gereksinimler**
>
> - `tuist bazel setup` aracılığıyla bağlanan bir Bazel çalışma alanı; bkz. <.localized_link href="/guides/get-started/bazel-project">Bir Bazel projesiyle başlayın</.localized_link>.

`tuist bazel setup`, `.bazelrc.tuist` içinde senaryo bazında raporlamayı yapılandırır; böylece sıradan bir `bazel test` komutu, diğer tüm derleme sistemlerinin kullandığı aynı panolara tekil test senaryolarını bildirir:

```bash
bazel test //app:tests
```

<.localized_link href="/guides/features/test-insights/flaky-tests/bazel">karantinaya alma</.localized_link> özelliğini de uygulamak için testleri bunun yerine Tuist sarmalayıcısı üzerinden çalıştırın. `--` sonrasındaki argümanlar `bazel test` komutuna iletilir:

```bash
tuist bazel test -- //app:tests
```

## Neler izlenir {#what-is-tracked}

Tuist, `test.xml` raporlarını ayrıştırır ve Bazel'in her test hedefi için ürettiği `test.log` çıktısını yakalar; ardından bunları ortak test çalıştırmaları modelinde birleştirir. Her çalıştırma şunları kaydeder:

- Tekil test senaryosunun başarılı, başarısız ve atlanmış durumu ile süresi.
- Test hedefi, sınıf ve test paketi yapısı.
- Bazel kararsız testleri yeniden deneyecek şekilde yapılandırıldığında yeniden deneme girişimleri.
- Hedefin `test.log` dosyasından yakalanan hata çıktısı.

**Test Çalıştırmaları**, **Test Senaryoları** ve tekil test sayfaları, Bazel için diğer derleme sistemlerinde olduğu gibi aynı şekilde çalışır.

## Senaryo bazında JUnit raporları oluşturma {#per-case-junit-reports}

Senaryo bazındaki satırlar, test hedefinin Bazel'in sağladığı `$XML_OUTPUT_FILE` yoluna bir JUnit `test.xml` dosyası yazmasına bağlıdır. Çalıştırıcı böyle bir dosya yazmadığında, Bazel hedef adıyla anılan sentetik tek senaryolu bir rapora geri döner ve Tuist, hedef başına tek bir satır gösterir (Test Senaryoları listesinde **Bazel hedefi** olarak etiketlenir); ham `test.log` çıktısı çalıştırma sayfasında hâlâ kullanılabilir durumdadır.

Çoğu Bazel test kuralı zaten gerçek bir `test.xml` üretir:

- `java_test` ve `kt_jvm_test`: JUnit yerleşiktir.
- GoogleTest ile `cc_test`: Çalıştırıcı, güncel bir gtest'e karşı derlendiğinde JUnit yazar; eski kurulumlar için `--gtest_output=xml:$XML_OUTPUT_FILE` gerekir.
- `py_test`: `--junitxml=$XML_OUTPUT_FILE` ile pytest kullanın veya `rules_python` pytest çalıştırıcısını tercih edin.
- `go_test`: `go test -json` çıktısını `gotestsum --junitfile=$XML_OUTPUT_FILE` üzerinden aktarın veya JUnit üreten bir yardımcıyla sarın.

`rules_rust` ve `rules_rs` paketlerinden gelen `rust_test`, standart `libtest` test altyapısını çalıştırır; bu altyapı kararlı Rust'ta JUnit yazmaz. Test hedefini, `libtest` çıktısını ayrıştırıp JUnit'i `$XML_OUTPUT_FILE` konumuna yazan bir betikle sarın; böylece Tuist'te senaryo bazlı satırları korurken aynı çalıştırma tek bir Bazel test hedefi olarak kalır.

## Test kimliği {#test-identity}

Senaryolar; hedef etiketi, sınıf adı (yoksa test paketi adı) ve test adı ile tanımlanır. Bu, farklı sınıflardaki aynı ada sahip yöntemlerin ayrı tutulmasını sağlar. Farklı bir kapsayan test paketi adı kullanan eski raporlar, geçmişlerini eski kimlik altında saklar; eski kimliğe uygulanan durum değişikliklerinin yeni kimliğe yeniden uygulanması gerekir ve komut, bir hatanın eski kimlikle eşleştiğinde sizi uyararak hangi politikayı taşımanız gerektiğini belirtir.

## CI bağlamı sağlama {#providing-ci-context}

Tuist, git commit ve dal bilgilerini Bazel'in derleme meta verilerinden okur; böylece aynı commit üzerindeki çalıştırmalar ortamlar arasında karşılaştırılabilir. Çoğu sürekli entegrasyon sistemi bunları zaten ayarlar; sizin sisteminiz ayarlamıyorsa, bunları açıkça iletin:

```bash
tuist bazel test -- \
  --build_metadata=CI=true \
  --build_metadata=GIT_COMMIT="$GIT_COMMIT" \
  --build_metadata=GIT_BRANCH="$GIT_BRANCH" //app:tests
```

Aynı `--build_metadata` bayrağı, <.localized_link href="/guides/features/build-insights/bazel#custom-metadata">Bazel derleme içgörüleri</.localized_link> sayfasında çağrıları etiketlemek için açıklanan bayraktır; dolayısıyla tek bir bayrak kümesi her iki arayüzü de kapsar.

## Kararsız testler ve karantina {#flaky-tests-and-quarantine}

Yeniden denemeler, çalıştırmalar arası kararsızlık algılama ve senaryo bazında karantina (Sustur ve Atla) işlemlerinin tamamı `tuist bazel test` üzerinden çalışır. Tam iş akışı için <.localized_link href="/guides/features/test-insights/flaky-tests/bazel">Bazel kararsız testleri</.localized_link> sayfasına bakın.

## Veri saklama {#data-retention}

Tuist, bir test çalıştırmasını üreten Bazel çağrısını, ilgili günlükleri ve bekleyen test alım kayıtlarını 90 gün boyunca saklar. Test senaryoları ve çalıştırma geçmişleri diğer tüm derleme sistemleriyle aynı modeli kullanır ve bu süre penceresine tabi değildir. Tam politika için <.localized_link href="/guides/server/data-retention">veri saklama</.localized_link> sayfasına bakın.
