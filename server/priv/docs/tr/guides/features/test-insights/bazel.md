---
{
  "title": "Bazel Test Analizleri",
  "titleTemplate": ":title · Test Analizleri · Özellikler · Kılavuzlar · Tuist",
  "description": "Test performansını ve güvenilirliğini izlemek için Bazel test analizlerini Tuist panosunda takip edin."
}
---
# Bazel test içgörüleri {#bazel-test-insights}

> [!IMPORTANT]
> **Gereksinimler**
>
> - <.localized_link href="/guides/get-started/bazel-project">Bir Bazel projesiyle başlayın</.localized_link> bölümünde açıklandığı gibi, `tuist bazel setup` aracılığıyla bağlanan bir Bazel çalışma alanı.

`tuist bazel setup`, `.bazelrc.tuist` içinde senaryo bazlı raporlamayı yapılandırır; böylece normal bir `bazel test` komutu, diğer tüm derleme sistemlerinin kullandığı aynı panolara bireysel test senaryolarını bildirir:

```bash
bazel test //app:tests
```

<.localized_link href="/guides/features/test-insights/flaky-tests/bazel">karantinaya alma</.localized_link> özelliğini de uygulamak için testleri bunun yerine Tuist sarmalayıcısı üzerinden çalıştırın. `--` sonrasındaki argümanlar `bazel test` komutuna iletilir:

```bash
tuist bazel test -- //app:tests
```

## Neler izlenir {#what-is-tracked}

Tuist, `test.xml` raporlarını ayrıştırır ve Bazel’in her test hedefi için ürettiği `test.log` çıktısını yakalar, ardından bunları ortak test çalıştırmaları modelinde birleştirir. Her çalıştırma şunları kaydeder:

- Süre bilgisiyle birlikte bireysel test senaryosunun başarılı, başarısız veya atlanmış durumu.
- Test hedefi, sınıf ve test paketi yapısı.
- Bazel kararsız testleri yeniden deneyecek şekilde yapılandırıldığında yapılan yeniden deneme girişimleri.
- Hedefin `test.log` dosyasından yakalanan hata çıktısı.

**Test Çalıştırmaları**, **Test Senaryoları** ve bireysel test sayfaları, Bazel için diğer derleme sistemlerinde olduğu gibi aynı şekilde çalışır.

## Senaryo bazlı JUnit raporlarının oluşturulması {#per-case-junit-reports}

Senaryo bazlı satırlar, test hedefinin Bazel’in sağladığı `$XML_OUTPUT_FILE` yoluna bir JUnit `test.xml` dosyası yazmasına bağlıdır. Çalıştırıcı böyle bir dosya yazmadığında, Bazel hedef adıyla adlandırılan sentetik tek senaryolu bir rapora geri döner ve Tuist, Test Senaryoları listesinde **Bazel hedefi** olarak etiketlenen hedef başına tek bir satır gösterir; ham `test.log` çıktısı yine de çalıştırma sayfasında kullanılabilir durumda kalır.

Çoğu Bazel test kuralı zaten gerçek bir `test.xml` üretir:

- `java_test` ve `kt_jvm_test`: JUnit yerleşiktir.
- GoogleTest ile `cc_test`: Çalıştırıcı, güncel bir gtest’e karşı derlendiğinde JUnit yazar; eski kurulumlar `--gtest_output=xml:$XML_OUTPUT_FILE` gerektirir.
- `py_test`: pytest’i `--junitxml=$XML_OUTPUT_FILE` ile kullanın veya `rules_python` pytest çalıştırıcısını tercih edin.
- `go_test`: `go test -json` çıktısını `gotestsum --junitfile=$XML_OUTPUT_FILE` üzerinden aktarın veya JUnit üreten bir yardımcı ile sarmalayın.

`rules_rust` ve `rules_rs` paketlerindeki `rust_test`, standart `libtest` altyapısını çalıştırır; bu altyapı kararlı Rust sürümünde JUnit yazmaz. Test hedefini, `libtest` çıktısını ayrıştırıp JUnit’i `$XML_OUTPUT_FILE` konumuna yazan bir betikle sarın; böylece Tuist’te senaryo bazlı satırları korurken aynı çalıştırma tek bir Bazel test hedefi olarak kalır.

## Test kimliği {#test-identity}

Senaryolar, hedef etiketi, sınıf adı (yoksa paket adı) ve test adı ile tanımlanır. Bu sayede farklı sınıflardaki aynı ada sahip yöntemler ayrı tutulur. Farklı bir kapsayan paket adı kullanan eski raporlar, geçmişlerini eski kimlik altında saklar; eski kimliğe uygulanan durum değişikliklerinin yeni kimliğe yeniden uygulanması gerekir ve komut, bir başarısızlık eski kimlikle eşleştiğinde hangi politikayı taşımanız gerektiğini bilmeniz için sizi uyarır.

## CI bağlamının sağlanması {#providing-ci-context}

Tuist, git commit ve dal bilgilerini Bazel’in derleme meta verilerinden okur; böylece aynı commit üzerindeki çalıştırmalar ortamlar arasında karşılaştırılabilir. Çoğu sürekli entegrasyon sistemi bu değerleri zaten ayarlar; sizin sisteminiz ayarlamıyorsa bunları açıkça iletin:

```bash
tuist bazel test -- \
  --build_metadata=CI=true \
  --build_metadata=GIT_COMMIT="$GIT_COMMIT" \
  --build_metadata=GIT_BRANCH="$GIT_BRANCH" //app:tests
```

Aynı `--build_metadata` bayrağı, çağrıları etiketlemek için <.localized_link href="/guides/features/build-insights/bazel#custom-metadata">Bazel derleme içgörüleri</.localized_link> sayfasında da açıklanmıştır; dolayısıyla tek bir bayrak seti her iki yüzeyi de kapsar.

## Kararsız testler ve karantina {#flaky-tests-and-quarantine}

Yeniden denemeler, çalıştırmalar arası kararsızlık tespiti ve senaryo bazlı karantina (Sustur ve Atla) işlevlerinin tamamı `tuist bazel test` üzerinden çalışır. Tam iş akışı için <.localized_link href="/guides/features/test-insights/flaky-tests/bazel">Bazel kararsız testleri</.localized_link> bölümüne bakın.

## Veri saklama {#data-retention}

Tuist, bir test çalıştırmasını üreten Bazel çağrısını, günlüklerini ve bekleyen test alım kayıtlarını 90 gün boyunca saklar. Test senaryoları ve çalıştırma geçmişleri, diğer tüm derleme sistemleriyle aynı modeli kullanır ve bu süre penceresine dahil değildir. Tam politika için <.localized_link href="/guides/server/data-retention">veri saklama</.localized_link> bölümüne bakın.
