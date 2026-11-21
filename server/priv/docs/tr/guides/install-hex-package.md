---
{
  "title": "Hex paketini kurun",
  "titleTemplate": ":title · Kılavuzlar · Tuist",
  "description": "Tuist'in Hex paketini Elixir projenize nasıl kuracağınızı ve yapılandıracağınızı öğrenin."
}
---
# Hex paketini yükleyin {#install-the-hex-package}

Tuist, Elixir projenizle entegre olan ve <.localized_link href="/guides/features/build-insights/elixir">derleme içgörüler</.localized_link> ile <.localized_link href="/guides/features/test-insights/elixir">test içgörüler</.localized_link> gibi özellikleri etkinleştiren bir [Hex](https://hex.pm/packages/tuist_ex) paketi olan `tuist_ex` sunar. Bu kılavuz, kurulum ve yapılandırma adımlarında size rehberlik eder.

Paket, Elixir 1.18 veya sonraki sürümleri gerektirir. Tuist komut satırı arayüzüne ihtiyaç duymaz.

## 1. Projeyi oluşturun {#create-the-project}

Tuist kontrol panelinde bir proje oluşturun ve derleme sistemi olarak **Mix (Elixir)** seçeneğini belirleyin. Hesap tanıtıcısı olan `account/project`, Mix projenizi bu projeye bağlar.

## 2. Paketi ekleyin {#add-the-package}

`tuist_ex` öğesini `mix.exs` dosyanızdaki bağımlılıklara ekleyin:

<!-- @snippet: ./_tuist-ex-dependency -->

Ardından indirin:

```bash
mix deps.get
```

`runtime: false`, Tuist'i çalışan uygulamanızın dışında tutar. Önbellekleme, derleme içgörüler ve test içgörüler birlikte yapılandırmak için <.localized_link href="/guides/get-started/elixir-project#set-up-tuist">Elixir ile başlayın</.localized_link> bölümüne devam edin. Aşağıdaki bölümler kimlik doğrulama ve yapılandırma ayrıntılarını kapsar.

## 3. Ekibinizi ve sürekli entegrasyonu doğrulayın {#authenticate}

Her ekip üyesi, makinesindeki Tuist özelliklerine erişim sağlamak için aşağıdakileri çalıştırır:

```bash
mix tuist.login
```

Kısa bir oturum açma kodu yazdırır, kodu girmeniz için bir tarayıcı açar ve yetkilendirmenizi bekler. Tarayıcı olmadan giriş yapmak için kimlik bilgilerinizi iletin:

```bash
mix tuist.login --email person@example.com --password secret
```

Kendi barındırdığınız veya yerel bir Tuist sunucusu kullanıyorsanız, temel URL'sini `mix.exs` içinde ayarlayın veya `--url` ile iletin:

```bash
mix tuist.login --url http://localhost:8080
```

Ana bilgisayar adı yazımını tutarlı tutun. Örneğin, `localhost` için saklanan bir oturum açma işlemi, `127.0.0.1` için saklanandan ayrıdır.

GitHub Actions, CircleCI ve Bitrise'te sürekli entegrasyon için oturum açma adımı gerekmez. Bir görev ilk kez rapor gönderdiğinde, sağlayıcının OpenID Connect jetonunu bir Tuist jetonuyla değiştirir. GitHub deposunuzu <.localized_link href="/guides/integrations/gitforge/github">Tuist projenize bağlayın</.localized_link> ve GitHub Actions'ta işe `id-token: write` iznini verin:

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

Fly.io Machines gibi diğer OpenID Connect kimlik sağlayıcılarıyla, hesabınızın **Ayarlar → Kimlik Doğrulama** sayfasındaki **İş Yükü Kimlikleri** bölümünde bir iş yükü kimliği güven politikası yapılandırın; bu politika, CI'ya o hesaba ait tüm mevcut ve gelecekteki projelere erişim izni verir. `TUIST_OIDC_ACCOUNT` değerini projenin sahibi olan Tuist hesabına ayarlayın ve politikanın hedef kitlesine sahip yeni basılmış bir kimlik jetonunu `TUIST_OIDC_TOKEN` aracılığıyla sağlayın. Entegrasyon, hesap jetonu veya geçerli saklanmış bir oturum açma bilgisi olmadığında bunu otomatik olarak değiştirir; `mix tuist.login` ayrıca CI dışındaki durumlarda da bunu kabul eder. Otomatik değişimler, yalnızca aynı sunucu, hesap ve sağlanan kimlik jetonu için süresi dolmamış bir oturumu yeniden kullanır. Bu kimliğin değiştirilmesi yeni bir değişimi tetikler ve boş bir kimlik sağlanması önceki bir oturumu yeniden kullanmak yerine başarısız olur. Tuist oturumları yenileme jetonları olmadan bir saat sürer, bu nedenle daha uzun süren iş yükleri için oturum sona ermeden önce yeni bir kimlik jetonu oluşturun ve `mix tuist.login` komutunu tekrar çalıştırın. <.localized_link href="/guides/server/authentication#workload-identity-trust-policies">iş yükü kimliği kurulumu</.localized_link> ve <.localized_link href="/guides/server/authentication#flyio-machines">Fly.io örneği</.localized_link> bölümlerini takip edin.

Çatallardan gelen çekme istekleri OpenID Connect jetonu almaz, bu nedenle çalıştırmaları raporlanmaz ve her zamanki gibi başarılı veya başarısız olur. Diğer sağlayıcılarda, `TUIST_TOKEN` ortam değişkenini bir hesap jetonuna ayarlayın. Bir tane oluşturmak için <.localized_link href="/guides/server/authentication#continuous-integration">sürekli entegrasyon kimlik doğrulama kılavuzunu</.localized_link> takip edin.

## 4. `mix test` ve `mix compile` kullanmaya devam edin {#aliases}

<.localized_link href="/guides/get-started/elixir-project#set-up-tuist">paylaşılan kurulum</.localized_link>, derleme ve test takma adlarını sizin için yükler. `mix test test/my_app_test.exs:12 --trace`, çalıştırmayı aynı çıktı ve çıkış koduyla raporlar ve derleme entegrasyonu, `mix test` veya `mix phx.server` tarafından tetiklenen derlemeleri kapsar. Yapılacak bir şey bulamayan bir derleme raporlanmaz.

Görevler kendi adlarıyla çağrıldığınızda da çalışır. Mix, bu şekilde yazılan bir görevi `dev` ortamında başlatır, bu nedenle görevin test ortamı için ikinci bir süreçte yeniden başlaması gerekir. Bunu atlamak için görevleri tercih edilen ortamlara ekleyin:

```elixir
def cli do
  [preferred_envs: ["tuist.test": :test, "tuist.test.build": :test]]
end
```

## Yapılandırma referansı {#configuration-reference}

`mix.exs` projesi seçeneklerinde `tuist` altında aşağıdaki seçenekler mevcuttur:

| Seçenek | Tür | Varsayılan | Açıklama |
| --- | --- | --- | --- |
| `project` | `String` | yok (zorunlu) | Proje tanımlayıcısı `account/project` formatındadır. |
| `url` | `String` | `"https://tuist.dev"` | Tuist sunucusunun temel URL'si. |
| `cache` | `boolean` veya anahtar kelime listesi | devre dışı | Kurulum, bağımlılık önbelleğe almayı etkinleştirir. Hariç tutmalar ve ek girdiler için <.localized_link href="/guides/features/cache/elixir">Elixir önbelleği</.localized_link> bölümüne bakın. |
| `test_retries` | `integer` | `0` | Başarısız olan testlerin kaç kez yeniden deneneceği; bkz. <.localized_link href="/guides/features/test-insights/flaky-tests/elixir#test-retries">test yeniden denemeleri</.localized_link>. |
| `tags` | `String` listesi | `[]` | Her derlemeye eklenecek etiketler; bkz. <.localized_link href="/guides/features/build-insights/elixir#custom-metadata">özel meta veriler</.localized_link>. |
| `values` | harita | `%{}` | Her derlemeye eklenecek anahtar-değer verileri. |

Ortam değişkenleri `mix.exs` üzerinde önceliklidir:

| Değişken | Açıklama |
| --- | --- |
| `TUIST_PROJECT` | Proje tanımlayıcısı `account/project` formatındadır. |
| `TUIST_URL` | Tuist sunucusunun temel URL'si. |
| `TUIST_TOKEN` | Kayıtlı oturum açma bilgisi yerine kimlik doğrulaması için kullanılacak jeton. |
| `TUIST_OIDC_TOKEN` | Yeni oluşturulmuş bir OpenID Connect kimlik jetonu, Tuist jetonu ile değiştirilir. GitHub Actions ve Bitrise için hedef kitlesi `tuist` olmalı veya diğer sağlayıcılar için hesabın iş yükü kimliğiyle eşleşmelidir. Hesap jetonu veya geçerli kayıtlı oturum açma bilgisi olmadığında `mix tuist.login` tarafından veya yedek olarak kullanılır. |
| `TUIST_OIDC_ACCOUNT` | Projeye sahip olan Tuist hesap tanıtıcısı. Bir hesap iş yükü kimliği aracılığıyla jeton değiştirirken gereklidir. Mevcut iş yükü kimlikleri arasında seçim yapar ve tek başına erişim sağlamaz. |
| `TUIST_TEST_RETRIES` | Başarısız olan testlerin kaç kez yeniden deneneceği. |
| `TUIST_TAGS` | Derlemeye eklenecek virgülle ayrılmış etiketler. |
| `TUIST_VALUES` | Derlemeye eklenecek virgülle ayrılmış `key=value` çiftleri. |
| `TUIST_DEBUG` | Bir raporun neden gönderilemediğini yazdırmak için `1` olarak ayarlayın. |

Raporlama, `mix test` veya `mix compile` çıkış kodunu asla değiştirmez. Bir rapor gönderilemezse, `TUIST_DEBUG=1` ayarlanmadığı sürece görev herhangi bir şey söylemez.

## Sonraki adımlar {#next-steps}

Paket kurulup yapılandırıldıktan sonra şunları kullanabilirsiniz:

- Derlenmiş bağımlılıkları yerel olarak ve CI derlemeleri arasında yeniden kullanmak için <.localized_link href="/guides/features/cache/elixir">Bağımlılık önbelleğe alma</.localized_link>.
- Derleme sürelerini, uyarıları ve derlemelerinizi neyin geciktirdiğini izlemek için <.localized_link href="/guides/features/build-insights/elixir">Derleme içgörüler</.localized_link>.
- Test performansını her bir teste kadar izlemek için <.localized_link href="/guides/features/test-insights/elixir">Test içgörüler</.localized_link>.
- Aralıklı olarak başarısız olan testleri tespit etmek ve izlemek için <.localized_link href="/guides/features/test-insights/flaky-tests/elixir">Kararsız testler</.localized_link>.
- Testlerinizi sürekli entegrasyon çalıştırıcılarına bölmek için <.localized_link href="/guides/features/test-sharding/elixir">Test parçalama</.localized_link>.
