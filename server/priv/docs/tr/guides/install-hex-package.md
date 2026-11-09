---
{
  "title": "Hex paketini kurun",
  "titleTemplate": ":title · Kılavuzlar · Tuist",
  "description": "Tuist'in Hex paketinin Elixir projenize nasıl kurulacağını ve yapılandırılacağını öğrenin."
}
---
# Hex paketini kurun {#install-the-hex-package}

Tuist, Elixir projenizle entegre olan ve <.localized_link href="/guides/features/build-insights/elixir">derleme içgörüler</.localized_link> ile <.localized_link href="/guides/features/test-insights/elixir">test içgörüler</.localized_link> gibi özellikleri etkinleştiren bir [Hex](https://hex.pm/packages/tuist_ex) paketi olan `tuist_ex` sunar. Bu kılavuz, paketi kurmanıza ve yapılandırmanıza yardımcı olur.

Paket, Elixir 1.18 veya sonraki sürümleri gerektirir. Tuist komut satırı arayüzüne ihtiyaç duymaz.

## 1. Projeyi oluşturun {#create-the-project}

Tuist kontrol panelinde bir proje oluşturun ve derleme sistemi olarak **Mix (Elixir)** seçeneğini belirleyin. Projenizin tanıtıcısı olan `account/project`, Mix projenizi Tuist projesine bağlar.

## 2. Paketi ekleyin {#add-the-package}

`tuist_ex` öğesini `mix.exs` dosyanızdaki bağımlılıklara ekleyin:

<!-- @snippet: ./_tuist-ex-dependency -->

Ardından paketi indirin:

```bash
mix deps.get
```

`runtime: false`, Tuist'i çalışan uygulamanızın dışında tutar. Önbelleğe alma, derleme içgörüler ve test içgörüler birlikte yapılandırmak için <.localized_link href="/guides/get-started/elixir-project#set-up-tuist">Elixir ile başlayın</.localized_link> bölümüne devam edin. Aşağıdaki bölümler kimlik doğrulama ve yapılandırma ayrıntılarını kapsar.

## 3. Ekibinizi ve sürekli entegrasyonu doğrulayın {#authenticate}

Her ekip üyesi, makinesindeki Tuist özelliklerine erişim sağlamak için aşağıdakileri çalıştırır:

```bash
mix tuist.login
```

Kısa bir giriş kodu yazdırır, kodu gireceğiniz bir tarayıcı açar ve yetkilendirmenizi bekler. Tarayıcı olmadan giriş yapmak için kimlik bilgilerinizi geçirin:

```bash
mix tuist.login --email person@example.com --password secret
```

Kendi barındırdığınız veya yerel bir Tuist sunucusu kullanıyorsanız, temel URL'sini `mix.exs` içinde ayarlayın veya `--url` ile geçirin:

```bash
mix tuist.login --url http://localhost:8080
```

Ana bilgisayar adı yazımını tutarlı tutun. Örneğin, `localhost` için saklanan bir giriş, `127.0.0.1` için saklanandan ayrıdır.

GitHub Actions, CircleCI ve Bitrise'te sürekli entegrasyon için giriş adımı gerekmez. Bir görev ilk kez rapor gönderdiğinde, sağlayıcının OpenID Connect jetonunu bir Tuist jetonuyla değiştirir. GitHub deposunuzu <.localized_link href="/guides/integrations/gitforge/github">Tuist projenize bağlayın</.localized_link> ve GitHub Actions'ta işe `id-token: write` iznini verin:

```yaml
jobs:
  test:
    runs-on: ubuntu-latest
    permissions:
      contents: read
      id-token: write
    steps:
      - uses: actions/checkout@v4
      - uses: erlef/setup-beam@v1
        with:
          elixir-version: '1.18'
          otp-version: '27'
      - run: mix deps.get
      - run: mix test
```

Fly.io Machines gibi diğer OpenID Connect kimlik sağlayıcılarıyla, hesabınızın **Ayarlar → Kimlik Doğrulama** sayfasındaki **İş Yükü Kimlikleri** bölümünde bir iş yükü kimliği güven politikası yapılandırın; bu politika, söz konusu hesaba ait mevcut ve gelecekteki tüm projelere CI erişimi sağlar. Projeye sahip olan Tuist hesabını `TUIST_OIDC_ACCOUNT` olarak ayarlayın ve politikanın hedef kitlesine sahip yeni oluşturulmuş bir kimlik jetonunu `TUIST_OIDC_TOKEN` aracılığıyla sağlayın. Entegrasyon, hesap jetonu veya geçerli saklanmış bir giriş olmadığında bunu otomatik olarak değiştirir; `mix tuist.login` ayrıca CI dışında da bunu kabul eder. Otomatik değişimler, yalnızca aynı sunucu, hesap ve sağlanan kimlik jetonu için süresi dolmamış bir oturumu yeniden kullanır. Kimliğin değiştirilmesi yeni bir değişimi tetikler ve boş sağlanan kimlik, önceki bir oturumu yeniden kullanmak yerine başarısız olur. Tuist oturumları yenileme jetonları olmadan bir saat sürer, bu nedenle daha uzun süreli iş yükleri için oturum sona ermeden önce yeni bir kimlik jetonu oluşturun ve `mix tuist.login` komutunu tekrar çalıştırın. <.localized_link href="/guides/server/authentication#workload-identity-trust-policies">iş yükü kimliği kurulumu</.localized_link> ve <.localized_link href="/guides/server/authentication#flyio-machines">Fly.io örneği</.localized_link> bölümlerini takip edin.

Fork'lardan gelen çekme istekleri OpenID Connect jetonu almaz, bu nedenle çalıştırmaları raporlanmaz ve her zamanki gibi başarılı veya başarısız olur. Diğer sağlayıcılarda, bir hesap jetonu için `TUIST_TOKEN` ortam değişkenini ayarlayın. Bir tane oluşturmak için <.localized_link href="/guides/server/authentication#continuous-integration">sürekli entegrasyon kimlik doğrulama kılavuzunu</.localized_link> takip edin.

## 4. `mix test` ve `mix compile` kullanmaya devam edin {#aliases}

<.localized_link href="/guides/get-started/elixir-project#set-up-tuist">paylaşılan kurulum</.localized_link>, derleme ve test takma adlarını sizin için yükler. `mix test test/my_app_test.exs:12 --trace`, çalıştırmayı aynı çıktı ve çıkış koduyla raporlar ve derleme entegrasyonu, `mix test` veya `mix phx.server` tarafından tetiklenen derlemeleri kapsar. Yapılacak bir şey bulamayan bir derleme raporlanmaz.

Görevler, kendi adlarıyla çağırdığınızda da çalışır. Mix, bu şekilde yazılan bir görevi `dev` ortamında başlatır, bu nedenle görevin test ortamı için ikinci bir süreçte yeniden başlaması gerekir. Bunu atlamak için görevleri tercih edilen ortamlara ekleyin:

```elixir
def cli do
  [preferred_envs: ["tuist.test": :test, "tuist.test.build": :test]]
end
```

## Yapılandırma referansı {#configuration-reference}

`mix.exs` dosyasındaki proje seçeneklerinde `tuist` altında aşağıdaki seçenekler mevcuttur:

| Seçenek | Tür | Varsayılan | Açıklama |
| --- | --- | --- | --- |
| `project` | `String` | yok (gerekli) | `account/project` formatındaki proje tanımlayıcısı. |
| `url` | `String` | `"https://tuist.dev"` | Tuist sunucusunun temel URL'si. |
| `cache` | `boolean` veya anahtar kelime listesi | devre dışı | Kurulum, bağımlılık önbelleğe almayı etkinleştirir. Hariç tutmalar ve ekstra girişler için <.localized_link href="/guides/features/cache/elixir">Elixir önbelleği</.localized_link> bölümüne bakın. |
| `test_retries` | `integer` | `0` | Başarısız olan testlerin kaç kez yeniden denenmesi gerektiği; bkz. <.localized_link href="/guides/features/test-insights/flaky-tests/elixir#test-retries">test yeniden denemeleri</.localized_link>. |
| `tags` | `String` listesi | `[]` | Her derlemeye eklenecek etiketler; bkz. <.localized_link href="/guides/features/build-insights/elixir#custom-metadata">özel meta veriler</.localized_link>. |
| `values` | harita | `%{}` | Her derlemeye eklenecek anahtar-değer verisi. |

Ortam değişkenleri `mix.exs` üzerinde önceliklidir:

| Değişken | Açıklama |
| --- | --- |
| `TUIST_PROJECT` | `account/project` formatındaki proje tanımlayıcısı. |
| `TUIST_URL` | Tuist sunucusunun temel URL'si. |
| `TUIST_TOKEN` | Kayıtlı giriş yerine kimlik doğrulama için kullanılacak jeton. |
| `TUIST_OIDC_TOKEN` | Tuist jetonuyla değiştirilen, yeni oluşturulmuş bir OpenID Connect kimlik jetonu. GitHub Actions ve Bitrise için hedef kitlesi `tuist` olmalı, diğer sağlayıcılar için hesabın iş yükü kimliğiyle eşleşmelidir. Hesap jetonu veya geçerli kayıtlı giriş olmadığında `mix tuist.login` tarafından veya yedek olarak kullanılır. |
| `TUIST_OIDC_ACCOUNT` | Projenin sahibi olan Tuist hesap tanıtıcısı. Bir hesap iş yükü kimliği aracılığıyla jeton değişimi yaparken gereklidir. Mevcut iş yükü kimlikleri arasında seçim yapar ve tek başına erişim izni vermez. |
| `TUIST_TEST_RETRIES` | Başarısız olan testlerin kaç kez yeniden denenmesi gerektiği. |
| `TUIST_TAGS` | Derlemeye eklenecek, virgülle ayrılmış etiketler. |
| `TUIST_VALUES` | Derlemeye eklenecek, virgülle ayrılmış `key=value` çiftleri. |
| `TUIST_DEBUG` | Bir raporun neden gönderilemediğini yazdırmak için `1` olarak ayarlayın. |

Raporlama, `mix test` veya `mix compile` çıkış kodunu asla değiştirmez. Bir rapor gönderilemezse, `TUIST_DEBUG=1` ayarlanmadığı sürece görev herhangi bir çıktı vermez.

## Sonraki adımlar {#next-steps}

Paket yüklendikten ve yapılandırıldıktan sonra şunları kullanabilirsiniz:

- Derlenmiş bağımlılıkları yerel olarak ve CI derlemeleri genelinde yeniden kullanmak için <.localized_link href="/guides/features/cache/elixir">Bağımlılık önbelleğe alma</.localized_link>.
- Derleme sürelerini, uyarıları ve derlemelerinizi yavaşlatan unsurları izlemek için <.localized_link href="/guides/features/build-insights/elixir">Derleme içgörüleri</.localized_link>.
- Test performansını her bir teste kadar izlemek için <.localized_link href="/guides/features/test-insights/elixir">Test içgörüleri</.localized_link>.
- Aralıklı olarak başarısız olan testleri tespit etmek ve izlemek için <.localized_link href="/guides/features/test-insights/flaky-tests/elixir">Kararsız testler</.localized_link>.
- Testlerinizi sürekli entegrasyon çalıştırıcıları arasında bölmek için <.localized_link href="/guides/features/test-sharding/elixir">Test parçalama</.localized_link>.
