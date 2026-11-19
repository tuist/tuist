---
{
  "title": "Elixir projesi",
  "titleTemplate": ":title · Başlangıç · Kılavuzlar · Tuist",
  "description": "Elixir bağımlılık önbellekleme, derleme ve test içgörüsü, kararsız test tespiti ve isteğe bağlı test bölümlendirme için Tuist'i bir kez kurun."
}
---
# Elixir projesi {#elixir-project}

::: code-group

```text [Agent prompt]
Help me get started with Tuist. Follow the setup at:
https://tuist.dev/en/docs/guides/get-started/elixir-project
```

:::

Tuist’i bir kez kurun, ardından `mix compile` ve `mix test` komutlarını kullanmaya devam edin. `tuist_ex` Hex paketi desteklenen bağımlılıkları önbelleğe alır ve derlemeler ile test çalıştırmalarını panonuzda raporlar.

## Ön koşullar

- Elixir 1.18 veya üzeri sürümde Mix ile oluşturulmuş bir Elixir projesi.
- Bir Tuist hesabı.

## Tuist’i kurma {#set-up-tuist}

Tuist panosunda bir proje oluşturun ve derleme sistemi olarak **Mix (Elixir)** seçeneğini belirleyin. Paketi `mix.exs` dosyanızdaki bağımlılıklara ekleyin:

<!-- @snippet: ../_tuist-ex-dependency -->

Paketi indirin, projenizi yapılandırın ve giriş yapın:

```bash
mix deps.get
mix tuist.setup --project account/project
mix tuist.login
```

Kurulum, `mix.exs` dosyasını proje kimliğinizle günceller, bağımlılık önbelleğini etkinleştirir ve compile ile test alias’larını yükler. Diğer ayarları ve Phoenix’in veritabanı kurulumu gibi standart test hazırlıklarını korur. Özel bir alias’ı güvenli bir şekilde entegre edemezse, dosyayı değiştirmeden işlemi durdurur.

Ekibinizin ve CI sisteminizin aynı kurulumu kullanması için güncellenmiş `mix.exs` dosyasını commit edin. Kopyalanacak betik veya değerlendirme kodu yok. Giriş bir tarayıcı açar; headless giriş ve CI kimlik bilgileri için <.localized_link href="/guides/install-hex-package#authenticate">kimlik doğrulama</.localized_link> bölümüne bakın.

Şimdi alışıldık komutlarınızı çalıştırın:

```bash
mix compile
mix test
```

Derlemeler **Builds** altında, test çalıştırmaları **Tests** altında ve bağımlılık önbelleği etkinlikleri **Mix cache** altında görünür. Bu üçü için ortak kurulum budur. Kararsız test algılama bildirilen çalıştırmaları kullanır; yeniden denemeler ve CI sharding isteğe bağlıdır.

## Bağımlılık önbelleği

Tuist, desteklenen Hex ve Git bağımlılıklarını otomatik olarak seçer; bir bağımlılık listesine gerek yoktur. Önbellek ıskalaması normal şekilde derlenir ve sonucu kaydeder; önbellek isabeti ise sonucu geri yükler. Yerel/özel derlemeler ve yerel bağımlılıklar Mix ile kalır.

Derlemenin tekrarlanabilir olması gerekir: ek derleme zamanı girdilerini bildirin ve modellenmemiş girdilere veya zorunlu yan etkilere sahip bağımlılıkları hariç tutun. Desteklenen girdiler, önbellek doğrulama ve özelleştirme için <.localized_link href="/guides/features/cache/elixir">Elixir cache</.localized_link> bölümüne bakın.

## Derleme içgörüler

Derleme süreleri, dosyalarınız arasındaki bağımlılık grafiği ve bunların zaman içindeki değişimi, derleme grafiğinizi optimize etmeniz ve derlemenin gerçekleştiği ortamda mevcut tüm çekirdeklerden en iyi şekilde yararlanmanız için ihtiyacınız olanı sağlar.

`compile` alias’ı etkin olduğunda Tuist her derlemeyi raporlar: ne kadar sürdüğü, uyarıları ve hataları, her dosyanın derlenme süresi ve bağımlı olduğu dosyalar. Bir sonraki `mix compile` komutundan sonra panoda **Builds** bölümünü açarak bu bilgilere ulaşabilirsiniz.

## Test içgörüler

Tuist, her `mix test` çalıştırmasındaki her testin sonucunu ve süresini kaydeder; böylece test paketinizin zaman içinde nasıl değiştiğini görebilir, yavaşlayan veya yavaş olan testleri bulabilir ve CI’da bir çalıştırmanın neden başarısız olduğunu anlayabilirsiniz. Bunları panoda **Tests** altında modüle, `describe` bloğuna ve teste kadar inerek bulabilirsiniz.

## Kararsız testler

Kararsız bir test aynı kodla bazen geçer bazen başarısız olur. Tuist, CI’da aynı commit üzerinde hem başarısız hem de geçen bir testi kararsız olarak işaretler. Başarısız olan testlerin yeniden denenmesini sağlayarak bunları tek bir çalıştırmada tespit edebilirsiniz:

```elixir
tuist: [project: "account/project", cache: true, test_retries: 2]
```

Yeniden denemede geçen bir test kararsız olarak raporlanır ve çalıştırma başarılı olur. **Flaky Tests** sayfası bunları listeler.

## Test sharding

Test sharding, test paketinizi CI runner’ları arasında dağıtır. Tuist, önceki çalıştırmalarda her test dosyasının ne kadar sürdüğünü kullanarak shard’ları dengeler; projeyi bir kez derler ve bu derlemeyi her runner ile paylaşır. Shard’ları planlamak için tek bir komut yeterlidir:

```bash
mix tuist.test.build --shard-max 4
```

Her runner, `TUIST_SHARD_INDEX` ayarlanmış olarak kendi payını çalıştırır ve sonuçlar panoda tek bir test çalıştırması olarak görünür:

```bash
TUIST_SHARD_INDEX=0 mix test
```

## Ekibi dahil edin

İçgörüler, projeye bağlı kişi sayısı arttıkça katlanarak değer kazanır. Ekibinizi panodaki hesap ayarlarından organizasyona davet edin ve <.localized_link href="/guides/integrations/authentication/sso">Single Sign-On</.localized_link> (Google, Okta, Microsoft) kurulumunu yaparak kişi başına `mix tuist.login` yerine tek tıklamayla onboarding sağlayın.

CI için kişisel bir giriş kullanmayın. GitHub Actions, CircleCI ve Bitrise OpenID Connect üzerinden kimlik doğrulaması yapabilir; diğer sağlayıcılarda kapsamı daraltılmış bir `TUIST_TOKEN` ayarlayın. <.localized_link href="/guides/install-hex-package#authenticate">CI kimlik doğrulama adımlarını</.localized_link> izleyin.
