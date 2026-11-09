---
{
  "title": "Elixir Test Parçalama",
  "titleTemplate": ":title · Test Parçalama · Özellikler · Kılavuzlar · Tuist",
  "description": "Tuist Test Parçalama ile Elixir projenizin testlerini birden fazla CI çalıştırıcısına dağıtın."
}
---
# Elixir testlerini parçalara ayırma {#elixir-test-sharding}

Tuist Hex paketi, bir Elixir projesinin testlerini parçalara ayırmak için yerleşik destek sunar. Geçmiş zamanlama verilerine dayalı dengeli parça planları oluşturmak için Tuist sunucusunu kullanır ve projenizi bir kez derler, böylece her çalıştırıcı doğrudan testleri çalıştırmaya geçebilir.

> [!IMPORTANT]
> **Gereksinimler**
>
> - CI parça işlerinizi yapılandırmadan önce <.localized_link href="/guides/get-started/elixir-project">paylaşılan Elixir kurulumunu</.localized_link> tamamlayın

## Nasıl çalışır {#how-it-works}

Test parçalama iki aşamalı bir iş akışını takip eder:

1. **Derleme aşaması:** Tuist projenizi test için derler, test dosyalarınızı listeler ve sunucuda bir **parça planı** oluşturur. Sunucu, son 30 günlük geçmiş test zamanlama verilerini kullanarak testleri parçalar arasında dağıtır, böylece her parça yaklaşık olarak aynı sürede tamamlanır. Derleme aşaması derlemeyi yükler ve CI sisteminizin paralel çalıştırıcılar başlatmak için kullandığı bir **parça matrisi** çıktılar.
2. **Test aşaması:** Her CI çalıştırıcısı bir **parça dizini** alır, derlemeyi indirir ve yalnızca o parçaya atanan testleri yürütür.

> [!NOTE]
> Kayıtlı Tuist Linux çalıştırıcılarında, parça derlemeleri yerel yapıt depolamayı kullanabilir. Böyle bir derlemeyi kullanan tüm parçaların aynı sitedeki kayıtlı çalıştırıcılarda çalışması gerekir; iş akışını diğer çalıştırıcılara taşırken yerel depolamayı devre dışı bırakarak derlemeyi yeniden çalıştırın.

Testler dosya bazında dağıtılır: bir dosyadaki her test aynı parçada çalışır. Tuist'in henüz görmediği testler için bir tahmin yapılır, bu nedenle bir projenin ilk planları sonrakilere göre daha az dengelidir.

## Derleme aşaması {#build-phase}

Test parçalarını `tuist.test.build` görevini kullanarak hazırlayın:

```sh
MIX_ENV=test mix compile --warnings-as-errors
MIX_ENV=test mix tuist.test.build --shard-max 5
```

Parçalama görevini çağırmadan önce paylaşılan kurulum tarafından yüklenen takma ad üzerinden derleme yapın. Soğuk bir çekimde Mix, `tuist.test.build` öğesini keşfederken bağımlılıkları derleyebilir ve bu, Tuist'in bağımlılık önbelleğinin bunları geri yükleme fırsatı bulmasından önce gerçekleşir. Açık derleme, parçalama göreviyle aynı test ortamında çalışır.

Bu görev:
1. Projeyi test ortamında derler
2. Geçmiş zamanlama verilerini kullanarak Tuist sunucusunda bir parça planı oluşturur
3. Parçaların tekrar derlenmemesi için derlemeyi yükler
4. CI sisteminiz için bir parça matrisi çıktılar

### Derleme seçenekleri {#build-options}

| Seçenek | Açıklama |
|--------|-------------|
| `--shard-max <N>` | Maksimum parça sayısı (varsayılan: 2) |
| `--shard-min <N>` | Minimum parça sayısı |
| `--shard-total <N>` | Bir aralık yerine kesin parça sayısı |
| `--shard-max-duration <MS>` | Parça başına hedeflenen maksimum süre (milisaniye cinsinden) |
| `--shard-reference <REF>` | Parçaların planı bulmak için kullandığı ad |
| `--no-upload` | Derlemeyi yüklemeden parçaları planla; her parça kendi kendine derlenir |

Diğer tüm argümanlar `mix compile` öğesine iletilir.

Parça referansı otomatik olarak CI ortam değişkenlerinden (`GITHUB_RUN_ID`, `CI_PIPELINE_ID`, `CIRCLE_WORKFLOW_ID`, `BUILDKITE_BUILD_ID`) türetilir veya `TUIST_SHARD_REFERENCE` ortam değişkeni aracılığıyla açıkça ayarlanabilir. Bu sağlayıcıların dışında, bunu derleme aşamasının ve tek bir boru hattı çalıştırmasının parçalarının paylaştığı bir değere ayarlamanız gerekir. GitHub Actions'ta referanslar çalıştırma denemesini de içerir: yalnızca başarısız olan işleri yeniden çalıştırırken, parça işlerinde yeni bir tane türetmek yerine orijinal derleme işinin referansını iletin.

## Test aşaması {#test-phase}

`TUIST_SHARD_INDEX` ayarlandığında, paket sunucudan parça atamasını alır, derlemeyi indirir ve derleme yapmadan yalnızca atanan test dosyalarını çalıştırır. Soğuk bir çalıştırıcıda, görevi çağırmadan önce SDK'yı önyükleyin ve yollarını yükleyin:

```sh
MIX_ENV=test TUIST_SHARD_INDEX=0 mix do deps.compile tuist_ex --include-children + deps.loadpaths --no-compile --no-deps-check + tuist.test
```

SDK'nın Mix'in çalışan süreçlerinde derlenmesi, onu üst süreçte yüklemez. Açık `deps.loadpaths` adımı, derlemeyi indirmeden önce kalan bağımlılıkların derlenmesini engelleyerek görev keşfini önler. Bu tek komutlu form, projenizin test hazırlık takma adını korur. Kurulum komutları derlemeyi tetikliyorsa, aşağıdaki ayrı kurulum sırasını kullanın.

İlettiğiniz herhangi bir test dosyası veya dizini parçayı daha da daraltır: hem parçada hem de seçiminizde olan dosyalar çalışır. Sonunda hiç testi kalmayan bir parça başarıyla çıkar.

Tüm parçaların sonuçları panoya tek bir test çalıştırması olarak gelir ve **Parçalar** bölümü her birinin ne kadar sürdüğünü gösterir.

Kurulum testlerden önce çalışmak zorundaysa, uygulamayı başlatmadan önce derlemeyi indirin:

```sh
MIX_ENV=test TUIST_SHARD_INDEX=0 mix do deps.compile tuist_ex --include-children + deps.loadpaths --no-compile --no-deps-check + tuist.test --prepare-only
```

Kurulumunuzu derleme devre dışı bırakılmış ayrı bir süreçte çalıştırın. Örneğin, bir Ecto projesi veritabanlarını şu şekilde oluşturup migrate edebilir:

```sh
MIX_ENV=test mix run --no-start --no-compile --no-deps-check -e 'Mix.Tasks.Ecto.Create.run([]); Mix.Tasks.Ecto.Migrate.run([])'
```

Diğer projeye özel hazırlıkları bu aşamada tutun. Derleme takma adınız da önyükleme işini yapmadan önce `--no-compile` seçeneğine uymalıdır: Mix bayrakları yalnızca liste takma adının son görevine iletir, bu nedenle daha önceki koşulsuz `deps.compile` yine de çalışır. <.localized_link href="/guides/features/cache/elixir-advanced#manual-compile-integration">manuel derleme entegrasyonu</.localized_link> içindeki korumalı takma ada bakın.

Ardından, parçayı yürütmeden önce geri yüklenen SDK'yı derleme yapmadan yükleyin. Bu ayrıca, kaynakları indirilen derlemeden daha yeni olduğunda bir yol bağımlılığının derlenmesini görev keşfi tarafından engeller:

```sh
MIX_ENV=test TUIST_SHARD_INDEX=0 mix do deps.loadpaths --no-compile --no-deps-check + tuist.test --no-download
```

Her iki komut da aynı parça referansına ihtiyaç duyar. `--prepare-only` yüklenmiş bir derleme gerektirir ve hazırlanan uygulama yapıtı eksikse `--no-download` başarısız olur. `--no-download` projenizin test hazırlık takma adını açıkça atlar, yeniden denemelerde dahil olmak üzere, ve kurulum adımlarını atlarken bir bildirim yazdırır. Normal çalıştırmalar, `--no-compile --no-deps-check` iletseniz bile takma adlarını korur. Veritabanı migrasyonlarını ayrı bir süreçte tutmak, migrasyon regresyon testleri bu modülleri kendileri yüklediğinde modül yeniden tanımlama uyarılarını da önler.

Farklı ortamları test ederken, `--scheme clickhouse-current` veya `--scheme clickhouse-floor` gibi kararlı bir `--scheme` etiketi iletin. Farklı etiketlere sahip sonuçlar, aynı konfigürasyonun kararsız yeniden çalıştırmaları olarak değerlendirilmez.

### Parçaların ihtiyaç duyduğu şeyler {#what-the-shards-need}

Yüklenen derleme `_build/test` dizinidir. Her parça çalıştırıcısının hâlâ şunlara ihtiyacı vardır:
- Derleme aşamasıyla aynı kontrol kopyası
- Aynı Elixir ve Erlang/OTP sürümleri
- `mix deps.get` ile alınan bağımlılık kaynakları

Şemsiye projenin kökünden parçalama henüz desteklenmemektedir. Her iki aşamayı da uygulamalarından birinin içinde çalıştırın.

## Sürekli entegrasyon {#continuous-integration}

### GitHub Actions {#github-actions}

GitHub Actions'ta derleme aşaması, parça indekslerini adımının `matrix` çıktısına yazar. Parçaları paralel çalıştırmak için matris stratejisi kullanın:

```yaml
name: Tests
on: [pull_request]

env:
  MIX_ENV: test
  TUIST_TOKEN: ${{ secrets.TUIST_TOKEN }}

jobs:
  build:
    name: Build test shards
    runs-on: ubuntu-latest
    outputs:
      matrix: ${{ steps.build.outputs.matrix }}
    steps:
      - uses: actions/checkout@v4
      - uses: erlef/setup-beam@v1
        with:
          elixir-version: '1.18'
          otp-version: '27'
      - run: mix deps.get
      - run: mix compile --warnings-as-errors
      - id: build
        run: mix tuist.test.build --shard-max 5

  test:
    name: "Shard #${{ matrix.shard }}"
    needs: build
    runs-on: ubuntu-latest
    strategy:
      fail-fast: false
      matrix:
        shard: ${{ fromJson(needs.build.outputs.matrix).shard }}
    env:
      TUIST_SHARD_INDEX: ${{ matrix.shard }}
    steps:
      - uses: actions/checkout@v4
      - uses: erlef/setup-beam@v1
        with:
          elixir-version: '1.18'
          otp-version: '27'
      - run: mix deps.get
      - run: mix do deps.compile tuist_ex --include-children + deps.loadpaths --no-compile --no-deps-check + tuist.test --prepare-only
      # Ecto example: keep all project-specific test preparation here.
      # The project's compile alias must honor --no-compile (see above).
      - run: mix run --no-start --no-compile --no-deps-check -e 'Mix.Tasks.Ecto.Create.run([]); Mix.Tasks.Ecto.Migrate.run([])'
      - run: mix do deps.loadpaths --no-compile --no-deps-check + tuist.test --no-download
```

### Diğer sağlayıcılar {#other-providers}

GitHub Actions dışındaki sağlayıcılarda derleme aşaması planı `.tuist-shard-matrix.json` dosyasına yazar:

```json
{
  "reference": "gitlab-1234",
  "shard_count": 2,
  "shards": [
    {
      "index": 0,
      "test_targets": ["MyApp.AccountsTest", "MyApp.CheckoutTest"],
      "estimated_duration_ms": 41000
    },
    {
      "index": 1,
      "test_targets": ["MyAppWeb.PageControllerTest"],
      "estimated_duration_ms": 39500
    }
  ]
}
```

Paralel işlerinizi kurmak için `shard_count` kullanın ve her işe `0` ile `shard_count - 1` arasında bir `TUIST_SHARD_INDEX` atayın. Tuist'in referansı türetmediği bir sağlayıcıda ayrıca her işe aynı `TUIST_SHARD_REFERENCE` değerini verin.
