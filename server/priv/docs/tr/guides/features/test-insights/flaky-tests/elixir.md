---
{
  "title": "Elixir Kararsız Testler",
  "titleTemplate": ":title · Kararsız Testler · Test Analizleri · Özellikler · Kılavuzlar · Tuist",
  "description": "Mix ile oluşturulan Elixir projelerinde kararsız testleri tespit edin ve yönetin."
}
---
# Elixir kararsız testleri {#elixir-flaky-tests}

> [!IMPORTANT]
> **Gereksinimler**
>
> - Test çalıştırmalarınızı raporlamak için <.localized_link href="/guides/get-started/elixir-project">paylaşılan Elixir kurulumunu</.localized_link> tamamlayın

<!-- @snippet: ./_intro -->

![Bir Phoenix uygulamasının kararsız testleri](/images/guides/features/elixir/flaky-tests.png)

## Kararsızlık algılamanın nasıl çalıştığı {#how-it-works}

Tuist, kararsız testleri iki şekilde algılar:

### Test yeniden denemeleri {#test-retries}

ExUnit her testi bir kez çalıştırır; bu nedenle aralıklı olarak başarısız olan bir test, bozuk bir testle aynı görünür. Yeniden denemeler etkinleştirildiğinde Hex paketi, ayarladığınız sayıya kadar başarısız olan testleri tekrar çalıştırır. Yeniden denemede geçen bir test kararsız olarak bildirilir ve tüm başarısız testler sonunda geçerse çalışma başarılı olur.

Yeniden denemeler varsayılan olarak kapalıdır. Bunları etkinleştirmek için `mix.exs` içindeki mevcut Tuist seçeneklerine `test_retries` ekleyin:

```elixir
tuist: [project: "account/project", cache: true, test_retries: 2]
```

Veya tek bir çalıştırma için bir bayrak veya ortam değişkeni kullanın:

```bash
mix test --retries 2
TUIST_TEST_RETRIES=2 mix test
```

Bayrak ortam değişkenine, ortam değişkeni de `mix.exs` dosyasına göre önceliklidir.

Yalnızca başarısız olan testler, `mix test --failed` komutunun onları çalıştırma biçiminde tekrar çalıştırılır ve pano her test girişimini ne kadar sürdüğünü gösterir. ExUnit’in `--max-failures` nedeniyle erken durdurduğu bir çalışma yeniden denenmez. Başarısız testlerin tamamı zaman aşımına uğrayan bir çalışma da yeniden denenmez, çünkü her yeniden deneme tüm zaman aşımlarını tekrar bekletir. Yeniden denemeler ayrıca `--warnings-as-errors` ile atlanır; bu durumda `mix test` artık bunu zorlamaz ve umbrella projesinin kökünden çalıştırıldığında da atlanır; bunları yeniden denemek için testleri projenin uygulamalarından birinin içinde çalıştırın.

![Kararsız bir ExUnit testi ve geçmişi](/images/guides/features/elixir/flaky-test-case.png)

### Çalışmalar arası algılama {#cross-run-detection}

Test yeniden denemeleri olmasa bile Tuist, aynı commit üzerindeki farklı CI çalıştırmalarının sonuçlarını karşılaştırarak kararsız testleri algılayabilir. Bir test aynı commit ve şema etiketi (`--scheme`) için bir CI çalıştırmasında geçer, başka bir çalıştırmada başarısız olursa başarısız yürütme kararsız olarak işaretlenir.

Bu, yeniden denemelerle yakalanacak kadar tutarlı başarısız olmasa da yine de aralıklı CI hatalarına neden olan kararsız testleri yakalamak için özellikle yararlıdır.

<!-- @snippet: ./_managing -->

## Kararsız testleri karantinaya alma {#quarantining}

Karantinaya alma, düzeltirken kararsız bir testin CI’yi engellemesini önler. Panoda bir testin sayfasında durumunu **Susturulmuş** veya **Atlandı** olarak değiştirin ya da **Ayarlar → Otomasyonlar** altında, test kararsız hale geldiğinde onu susturan veya atlayan ve iyileştiğinde yeniden etkinleştiren bir otomasyon yapılandırın. Testleri çalıştırmadan önce `mix test`, projedeki karantinaya alınmış her testi okur ve uygular:

- **Susturulmuş**: test çalışır ve başarısızlığı yine raporlanır, ancak yalnızca susturulmuş testlerin başarısız olduğu bir çalışma başarılı sayılır. Yeniden denemeler başarısız olan susturulmuş bir testi hâlâ tekrar çalıştırır; böylece kararsız bir test geçebilir ve kararsız olarak bildirilebilir.
- **Atlandı**: test çalışmaz. `mix test`, çalışma başlamadan önce atlanan testleri listeler.

```text
Tuist: skipping 1 quarantined test:
  MyApp.CheckoutTest: create_order/2 times out
Tuist: 1 muted test run, and their failures do not fail the run.
```

Susturulmamış herhangi bir test başarısız olduğunda veya ExUnit `--max-failures` nedeniyle erken durduğunda çalışma olağan şekilde başarısız olur.

> [!WARNING]
> **Sınırlamalar**
>
> - Yalnızca Hex paketinin son sürümleri karantinayı uygular. Daha eski sürümler susturulmuş ve atlanmış testleri diğerleri gibi çalıştırır; bu nedenle susturulmuş bir testin başarısızlığı çalışmayı hâlâ başarısız kılar. Buna güvenmeden önce `tuist_ex` paketini güncelleyin.
> - Susturulmuş testler `--warnings-as-errors` ile veya umbrella projesinin kökünden uygulanmaz. Bu durumda onların başarısızlıkları çalışmayı başarısız kılar. Bunun yerine testleri umbrella’daki her uygulamanın içinde çalıştırın.
> - Atlama, bir testi modülüne göre değil, describe bloğu ve adına göre eşleştirir. Başka bir modülde aynı describe bloğuna ve ada sahip bir test de atlanır. Bkz. [atlamanın testleri nasıl seçtiği](#how-skipping-selects-tests).
> - Bir atlanmış test, onu `--only`, `--include` veya `path:line` ile seçtiğinizde ya da `test` ile bildirilmediğinde (örneğin bir StreamData `property` özelliği) hâlâ çalışır.
> - `mix test` karantinaya alınmış testleri okuyamazsa her testi çalıştırır ve her başarısızlığı sayar.
> - Karantinaya alınmış testleri okumak, herkese açık bir proje için bile kimlik bilgileri gerektirir. `TUIST_TOKEN`, bir `mix tuist.login` oturumu veya sürekli entegrasyon kimlik belirteci olmadan yapılan bir çalıştırmada karantina uygulanmaz. Buna, genellikle gizli anahtarlar olmadan çalışan fork’lardan gelen çekme istekleri de dahildir.
> - `--cover` ile atlanmış bir test kaldırılmış sayılır: yalnızca onun kapsadığı satırlar kapsam dışı olarak raporlanır.
>
> `mix test`, atlama tarafından yanlışlıkla dışarıda bırakılan testleri ve yine de çalışan atlanmış testleri özetinden sonra adlandırır.

### Atlamanın testleri nasıl seçtiği {#how-skipping-selects-tests}

Atlanmış bir test, tam adına yönelik bir ExUnit filtresiyle dışarıda bırakılır; örneğin `--exclude "test:test create_order/2 times out"`. ExUnit filtreleri modülü de eşleştiremez, bu nedenle:

- Başka bir modülde aynı describe bloğuna ve ada sahip bir test de dışarıda bırakılır. `mix test`, bu testleri çalıştırmadan sonra adlandırır.
- `--only`, `--include` veya `path:line` ile seçtiğiniz bir test, ExUnit dahil etme filtrelerini dışlama filtrelerinden sonra uyguladığı için atlanmış olsa bile çalışır. `test` ile bildirilmeyen bir test de (örneğin bir StreamData `property` özelliği) aynı şekilde çalışır. `mix test`, bu testleri çalıştırmadan sonra adlandırır.

### Karantinaya alınmış testleri tekrar çalıştırma {#running-quarantined-tests-again}

Her testi çalıştırmak ve her başarısızlığı saymak (örneğin bir düzeltmeyi kontrol etmek) için `--no-quarantine` parametresini iletin:

```bash
mix test --no-quarantine
```

Sonraki çalıştırmalara dahil etmek için testin sayfasında durumu **Etkin** olarak geri döndürün. Atlanmış bir test, tekrar çalışana kadar yeni sonuç üretmez.

`mix test` karantinaya alınmış testleri okuyamazsa bir uyarı yazdırır ve onlar olmadan her testi çalıştırır. Kimlik bilgileri veya yapılandırılmış bir proje yoksa uyarı vermeden her testi çalıştırır.

Hex paketi henüz yeni testleri stres testine tabi tutmuyor.

<!-- @snippet: ./_slack -->

## Kararsız durumu sorgulama {#querying}

Veriler HTTP üzerinden erişilebilir. Rotaların, filtrelerin ve yanıt alanlarının tam listesi için API referansındaki [Test Senaryoları uç noktalarını](https://tuist.dev/api/docs#tag/test-cases) inceleyin. Bir test senaryosunu kararsız olarak işaretlemek veya işaretini kaldırmak için `is_flaky` ile birlikte `PATCH /api/projects/{account_handle}/{project_handle}/tests/test-cases/{test_case_id}` isteği gönderin ya da `update_test_case` Model Bağlam Protokolü aracını kullanın.
