---
{
  "title": "Elixir Kararsız Testler",
  "titleTemplate": ":title · Kararsız Testler · Test İçgörüler · Özellikler · Kılavuzlar · Tuist",
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

ExUnit her testi bir kez çalıştırır, bu nedenle aralıklı olarak başarısız olan bir test bozuk olanla aynı görünür. Yeniden denemeler etkinleştirildiğinde, Hex paketi ayarladığınız sayıya kadar başarısız olan testleri tekrar çalıştırır. Yeniden denemede geçen bir test kararsız olarak bildirilir ve tüm başarısız testler sonunda geçerse çalışma başarılı olur.

Yeniden denemeler varsayılan olarak kapalıdır. Bunları etkinleştirmek için `mix.exs` içindeki mevcut Tuist seçeneklerinize `test_retries` ekleyin:

```elixir
tuist: [project: "account/project", cache: true, test_retries: 2]
```

Veya tek bir çalışma için, bir bayrak veya ortam değişkeni ile:

```bash
mix test --retries 2
TUIST_TEST_RETRIES=2 mix test
```

Bayrak, ortam değişkenine göre önceliklidir ve ortam değişkeni de `mix.exs` dosyasına göre önceliklidir.

Sadece başarısız olan testler tekrar çalıştırılır; tıpkı `mix test --failed` komutunun onları çalıştırması gibi. Kontrol paneli, her bir test denemesini ve ne kadar sürdüğünü gösterir. ExUnit’in `--max-failures` nedeniyle erken durdurduğu bir çalışma yeniden denenmez. Başarısız testlerinin tümü zaman aşımına uğrayan bir çalışma da yeniden denenmez, çünkü her yeniden deneme tüm zaman aşımlarını tekrar bekletecektir. Yeniden denemeler ayrıca `--warnings-as-errors` ile de atlanır; bu durumda `mix test` artık bunu zorlamaz. Ayrıca şemsiye (umbrella) projenin kökünden çalıştırıldığında da atlanır; bunları yeniden denemek için testleri uygulamalarından birinin içinde çalıştırın.

![Kararsız bir ExUnit testi ve geçmişi](/images/guides/features/elixir/flaky-test-case.png)

### Çapraz çalışma algılama {#cross-run-detection}

Test yeniden denemeleri olmasa bile, Tuist aynı commit üzerindeki farklı CI çalıştırmaları arasındaki sonuçları karşılaştırarak kararsız testleri algılayabilir. Bir test aynı commit ve şema etiketi (`--scheme`) için bir CI çalıştırmasında geçip diğerinde başarısız olursa, başarısız yürütme kararsız olarak işaretlenir.

Bu, tutarlı bir şekilde başarısız olmadığı için yeniden denemelerle yakalanamayan ancak yine de aralıklı CI hatalarına neden olan kararsız testleri yakalamak için özellikle kullanışlıdır.

<!-- @snippet: ./_managing -->

## Kararsız testleri karantinaya alma {#quarantining}

Karantinaya alma, düzeltirken kararsız bir testin CI’yi engellemesini önler. Kontrol panelindeki test sayfasında durumunu **Sessize Alınmış** veya **Atlanmış** olarak değiştirin ya da **Ayarlar → Otomasyonlar** altında, test kararsız hale geldiğinde onu sessize alan veya atlayan ve iyileştiğinde tekrar etkinleştiren bir otomasyon yapılandırın. Testleri çalıştırmadan önce `mix test`, projedeki karantinadaki tüm testleri okur ve uygular:

- **Sessize Alınmış**: test çalışır ve başarısızlığı yine de bildirilir, ancak yalnızca sessize alınmış testlerin başarısız olduğu bir çalışma başarılı sayılır. Yeniden denemeler, başarısız olan sessize alınmış testi yine de tekrar çalıştırır, böylece kararsız bir test geçebilir ve kararsız olarak bildirilebilir.
- **Atlanmış**: test çalışmaz. `mix test`, çalışma başlamadan önce atlanan testleri listeler.

```text
Tuist: skipping 1 quarantined test:
  MyApp.CheckoutTest: create_order/2 times out
Tuist: 1 muted test run, and their failures do not fail the run.
```

Sessize alınmamış herhangi bir test başarısız olduğunda veya ExUnit `--max-failures` nedeniyle erken durduğunda çalışma her zamanki gibi başarısız olur.

> [!WARNING]
> **Sınırlamalar**
>
> - Yalnızca Hex paketinin son sürümleri karantinayı uygular. Daha eski sürümler sessize alınmış ve atlanmış testleri diğerleri gibi çalıştırır, bu nedenle sessize alınmış bir testin başarısızlığı yine de çalışmayı başarısız kılar. Buna güvenmeden önce `tuist_ex` paketini güncelleyin.
> - Sessize alınmış testler `--warnings-as-errors` ile veya şemsiye (umbrella) projenin kökünden çalıştırıldığında uygulanmaz. Bu durumda onların başarısızlıkları çalışmayı başarısız kılar. Bunun yerine testleri şemsiye projenin her bir uygulamasının içinde çalıştırın.
> - Atlama, bir testi modülüne göre değil, describe bloğuna ve adına göre eşleştirir. Başka bir modülde aynı describe bloğuna ve ada sahip bir test de atlanır. Bkz. [atlamanın testleri nasıl seçtiği](#how-skipping-selects-tests).
> - Bir atlanan test, onu `--only`, `--include` veya `path:line` ile seçtiğinizde ya da `test` ile bildirilmediğinde (örneğin bir StreamData `property` özelliği) yine de çalışır.
> - Eğer `mix test` karantinadaki testleri okuyamazsa, her testi çalıştırır ve her başarısızlığı sayar.
> - Karantinadaki testleri okumak, herkese açık bir proje için bile kimlik bilgileri gerektirir. `TUIST_TOKEN`, bir `mix tuist.login` oturumu veya sürekli entegrasyon kimlik belirteci olmadan yapılan bir çalışma hiçbir karantina uygulamaz. Buna, genellikle gizli anahtarlar olmadan çalışan fork’lardan gelen çekme istekleri de dahildir.
> - `--cover` ile, atlanan bir test kaldırılmış olarak sayılır: yalnızca onun kapsadığı satırlar kapsanmamış olarak bildirilir.
>
> `mix test`, özetinden sonra yanlışlıkla dışarıda bırakılan atlanan testleri ve yine de çalışan atlanan testleri isimlendirir.

### Atlamanın testleri nasıl seçtiği {#how-skipping-selects-tests}

Atlanan bir test, tam adına yönelik bir ExUnit filtresiyle dışarıda bırakılır; örneğin `--exclude "test:test create_order/2 times out"`. ExUnit filtreleri modülü de eşleştiremez, bu nedenle:

- Başka bir modülde aynı describe bloğuna ve ada sahip bir test de dışarıda bırakılır. `mix test`, bu testleri çalıştırmadan sonra isimlendirir.
- `--only`, `--include` veya `path:line` ile seçtiğiniz bir test, atlanmış olsa bile çalışır çünkü ExUnit dahil etme filtrelerini dışlama filtrelerinden sonra uygular. `test` ile bildirilmeyen bir test de (örneğin bir StreamData `property` özelliği) aynı şekilde çalışır. `mix test`, bu testleri çalıştırmadan sonra isimlendirir.

### Karantinadaki testleri tekrar çalıştırma {#running-quarantined-tests-again}

Her testi çalıştırmak ve her başarısızlığı saymak için `--no-quarantine` parametresini iletin; örneğin bir düzeltmeyi kontrol etmek için:

```bash
mix test --no-quarantine
```

Testi sonraki çalışmalara dahil etmek için sayfasında durumunu **Etkin** olarak geri getirin. Atlanan bir test, tekrar çalışana kadar yeni sonuç üretmez.

Eğer `mix test` karantinadaki testleri okuyamazsa, bir uyarı yazdırır ve onlar olmadan her testi çalıştırır. Kimlik bilgileri veya yapılandırılmış bir proje olmadığında, her testi uyarı vermeden çalıştırır.

Hex paketi henüz yeni testleri stres testine tabi tutmuyor.

<!-- @snippet: ./_slack -->

## Kararsız durumu sorgulama {#querying}

Veriler HTTP üzerinden erişilebilir. Rotaların, filtrelerin ve yanıt alanlarının tam listesi için API referansındaki [Test Senaryoları uç noktalarını](https://tuist.dev/api/docs#tag/test-cases) inceleyin. Bir test senaryosunu kararsız olarak işaretlemek veya işaretini kaldırmak için `is_flaky` ile birlikte `PATCH /api/projects/{account_handle}/{project_handle}/tests/test-cases/{test_case_id}` gönderin ya da `update_test_case` Model Bağlam Protokolü aracını kullanın.
