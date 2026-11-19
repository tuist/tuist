---
{
  "title": "Elixir projesi",
  "titleTemplate": ":title · Başlangıç · Kılavuzlar · Tuist",
  "description": "Elixir bağımlılık önbellekleme, derleme ve test içgörüsü, kararsız test tespiti ve isteğe bağlı test parçalama için Tuist'i bir kez kurun."
}
---
# Elixir projesi {#elixir-project}

::: code-group

```text [Agent prompt]
Help me get started with Tuist. Follow the setup at:
https://tuist.dev/en/docs/guides/get-started/elixir-project
```

:::

Tuist'i bir kez kurun, ardından `mix compile` ve `mix test` komutlarını kullanmaya devam edin. `tuist_ex` Hex paketi desteklenen bağımlılıkları önbelleğe alır ve derlemeler ile test çalıştırmalarını panonuzda raporlar.

## Ön Koşullar

- Elixir 1.18 veya üzeri sürümde Mix ile oluşturulmuş bir Elixir projesi.
- Bir Tuist hesabı.

## Tuist'i kurma {#set-up-tuist}

Tuist kontrol panelinde bir proje oluşturun ve derleme sistemi olarak **Mix (Elixir)** seçeneğini belirleyin. Paketi `mix.exs` dosyanızdaki bağımlılıklara ekleyin:

<!-- @snippet: ../_tuist-ex-dependency -->

Paketi indirin, projenizi yapılandırın ve giriş yapın:

```bash
mix deps.get
mix tuist.setup --project account/project
mix tuist.login
```

Kurulum işlemi `mix.exs` dosyasını proje tanıtıcınızla günceller, bağımlılık önbelleğini etkinleştirir ve derleme ile test için takma adları yükler. Diğer ayarları ve Phoenix'in veritabanı kurulumu gibi standart test hazırlıklarını korur. Özel bir takma adı güvenli bir şekilde entegre edemezse, dosyada değişiklik yapmadan işlemi durdurur.

Ekibinizin ve CI sisteminizin aynı kurulumu kullanması için güncellenmiş `mix.exs` dosyasını commit edin. Kopyalanacak betik veya değerlendirme kodu yoktur. Giriş yapmak bir tarayıcı açar; headless giriş ve CI kimlik bilgileri için <.localized_link href="/guides/install-hex-package#authenticate">kimlik doğrulama</.localized_link> bölümüne bakın.

Şimdi alıştığınız komutları çalıştırın:

```bash
mix compile
mix test
```

Derlemeler **Derlemeler**, test çalıştırmaları **Testler** ve bağımlılık önbellek aktivitesi **Mix önbelleği** altında görünür. Bu, üçü için ortak kurulumdur. Kararsız test tespiti raporlanan çalıştırmaları kullanır; yeniden denemeler ve CI parçalama isteğe bağlıdır.

## Bağımlılık Önbellekleme

Tuist, bir bağımlılık listesine gerek kalmadan desteklenen Hex ve Git bağımlılıklarını otomatik olarak seçer. Bir önbellek ıskalaması normal derleme yapar ve sonucu kaydeder; bir isabet ise sonucu geri yükler. Yerel/özel derleme ve yerel bağımlılıklar Mix ile kalır.

Derleme tekrarlanabilir olmalıdır: ek derleme zamanı girdilerini bildirin ve modellenmemiş girdilere veya zorunlu yan etkilere sahip bağımlılıkları hariç tutun. Desteklenen girdiler, önbellek doğrulama ve özelleştirme için <.localized_link href="/guides/features/cache/elixir">Elixir önbelleği</.localized_link> bölümüne bakın.

## Derleme İçgörüler

Derleme süreleri, dosyalarınız arasındaki bağımlılık grafiği ve bunların zaman içindeki değişimi, derleme grafiğinizi optimize etmeniz ve derlemenin gerçekleştiği ortamda mevcut tüm çekirdeklerden en iyi şekilde yararlanmanız için ihtiyacınız olan verileri sağlar.

`compile` takma adı yerindeyken Tuist her derlemeyi raporlar: ne kadar sürdüğü, uyarıları ve hataları, her dosyanın derlenmesinin ne kadar sürdüğü ve bağımlı olduğu dosyalar. Bir sonraki `mix compile` komutundan sonra kontrol panelindeki **Derlemeler** bölümünü açarak bu verilere ulaşabilirsiniz.

## Test İçgörüler

Tuist, her `mix test` çalıştırmasındaki her testin sonucunu ve süresini kaydeder, böylece test paketinizin zaman içinde nasıl geliştiğini görebilir, yavaşlayan testleri bulabilir ve CI'da bir çalıştırmanın neden başarısız olduğunu anlayabilirsiniz. Bunları kontrol panelindeki **Testler** bölümünde, modül düzeyinden `describe` bloğuna ve teste kadar inceleyebilirsiniz.

## Kararsız Testler

Kararsız bir test, aynı kodla bazen geçer bazen başarısız olur. Tuist, CI'da aynı commit'te hem başarısız olup hem de geçen bir testi kararsız olarak işaretler. Başarısız olan testlerin pakette yeniden denenmesini sağlayarak bunları tek bir çalıştırmada tespit edebilirsiniz:

```elixir
tuist: [project: "account/project", cache: true, test_retries: 2]
```

Yeniden denemede geçen bir test kararsız olarak raporlanır ve çalıştırma başarılı olur. **Kararsız Testler** sayfası bunları listeler.

## Test Parçalama

Test parçalama, test paketinizi CI çalıştırıcıları arasında dağıtır. Tuist, önceki çalıştırmalarda her test dosyasının ne kadar sürdüğünü kullanarak parçaları dengeler; projeyi bir kez derler ve bu derlemeyi her çalıştırıcıyla paylaşır. Tek bir komut parçaları planlar:

```bash
mix tuist.test.build --shard-max 4
```

Her çalıştırıcı, `TUIST_SHARD_INDEX` ayarıyla kendi payını çalıştırır ve sonuçlar kontrol panelinde tek bir test çalıştırması olarak görünür:

```bash
TUIST_SHARD_INDEX=0 mix test
```

## Ekibi Dahil Edin

İçgörüler, projeye bağlı kişi sayısı arttıkça çoğalır. Kontrol panelindeki hesap ayarlarından ekip arkadaşlarınızı organizasyona davet edin ve <.localized_link href="/guides/integrations/authentication/sso">Tek Oturum Açma</.localized_link> (Google, Okta, Microsoft) kurulumunu yaparak kişisel `mix tuist.login` yerine tek tıklamayla katılım sağlayın.

CI için kişisel giriş kullanmayın. GitHub Actions, CircleCI ve Bitrise OpenID Connect üzerinden kimlik doğrulaması yapabilir; diğer sağlayıcılarda kapsamı belirlenmiş bir `TUIST_TOKEN` ayarlayın. <.localized_link href="/guides/install-hex-package#authenticate">CI kimlik doğrulama adımlarını</.localized_link> takip edin.
