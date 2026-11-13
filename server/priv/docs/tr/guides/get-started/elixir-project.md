---
{
  "title": "Elixir projesi",
  "titleTemplate": ":title · Başlangıç · Kılavuzlar · Tuist",
  "description": "Elixir bağımlılık önbellekleme, derleme ve test analizleri, kararsız test tespiti ve isteğe bağlı test parçalama için Tuist'i bir kez yapılandırın."
}
---
# Elixir projesi {#elixir-project}

::: code-group

```text [Agent prompt]
Help me get started with Tuist. Follow the setup at:
https://tuist.dev/en/docs/guides/get-started/elixir-project
```

:::

Tuist’i bir kez kurun, ardından `mix compile` ve `mix test` kullanmaya devam edin. `tuist_ex` Hex paketi desteklenen bağımlılıkları önbelleğe alır ve derlemeler ile test çalıştırmalarını panonuzda raporlar.

## Ön koşullar

- Mix ile oluşturulmuş, Elixir 1.18 veya üzeri bir Elixir projesi.
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

Kurulum, `mix.exs` dosyasını proje tanıtıcınızla günceller, bağımlılık önbellekleme özelliğini etkinleştirir ve derleme ile test takma adlarını yükler. Diğer ayarları ve Phoenix’in veritabanı kurulumu gibi standart test hazırlıklarını korur. Özel bir takma adı güvenli bir şekilde entegre edemezse, dosyayı değiştirmeden işlemi durdurur.

Ekibinizin ve CI sisteminizin aynı kurulumu kullanması için güncellenmiş `mix.exs` dosyasını commit edin. Kopyalanacak betik veya değerlendirme kodu yok. Giriş yapmak bir tarayıcı açar; headless giriş ve CI kimlik bilgileri için <.localized_link href="/guides/install-hex-package#authenticate">kimlik doğrulama</.localized_link> bölümüne bakın.

Şimdi alıştığınız komutları çalıştırın:

```bash
mix compile
mix test
```

Derlemeler **Derlemeler**, test çalıştırmaları **Testler** ve bağımlılık önbellek etkinliği **Mix önbelleği** altında görünür. Bu üçü için ortak kurulum budur. Kararsız test algılama bildirilen çalıştırmaları kullanır; yeniden denemeler ve CI parçalama isteğe bağlıdır.

## Bağımlılık önbellekleme

Tuist, bir bağımlılık listesi gerektirmeden desteklenen Hex ve Git bağımlılıklarını otomatik olarak seçer. Önbellek ıskalaması normal derleme yapar ve sonucu kaydeder; önbellek isabeti sonucu geri yükler. Yerel/özel derleme ve yerel bağımlılıklar Mix ile kalır.

Derleme tekrarlanabilir olmalıdır: ek derleme zamanı girdilerini tanımlayın ve modellenmemiş girdilere veya zorunlu yan etkilere sahip bağımlılıkları hariç tutun. Desteklenen girdiler, önbellek doğrulama ve özelleştirme için <.localized_link href="/guides/features/cache/elixir">Elixir önbelleği</.localized_link> bölümüne bakın.

## Derleme içgörüler

Derleme süreleri, dosyalarınız arasındaki bağımlılık grafiği ve her ikisinin zaman içindeki değişimi, derleme grafiğinizi optimize etmeniz ve derlemenin gerçekleştiği ortamda bulunan tüm çekirdeklerden en iyi şekilde yararlanmanız için ihtiyacınız olanı sağlar.

`compile` takma adı yerindeyken Tuist her derlemeyi raporlar: ne kadar sürdüğü, uyarıları ve hataları, her dosyanın derlenmesinin ne kadar sürdüğü ve bağımlı olduğu dosyalar. Bir sonraki `mix compile` komutundan sonra panodaki **Derlemeler** bölümünü açarak bunları görebilirsiniz.

## Test içgörüler

Tuist, her `mix test` çalıştırmasındaki her testin sonucunu ve süresini kaydeder; böylece test paketinizin zaman içinde nasıl değiştiğini görebilir, yavaşlayan veya yavaşlamış testleri bulabilir ve bir çalıştırmanın CI’da neden başarısız olduğunu anlayabilirsiniz. Bunları panodaki **Testler** bölümünde modül düzeyinden `describe` bloğuna ve teste kadar bulabilirsiniz.

## Kararsız testler

Kararsız bir test aynı kodla bazen geçer bazen başarısız olur. Tuist, CI’da aynı commit üzerinde hem başarısız olup hem de geçen bir testi kararsız olarak işaretler. Başarısız olan testlerin pakette yeniden denenmesini sağlayarak bunları tek bir çalıştırmada tespit edebilirsiniz:

```elixir
tuist: [project: "account/project", cache: true, test_retries: 2]
```

Yeniden denemede geçen bir test kararsız olarak raporlanır ve çalıştırma başarılı olur. **Kararsız Testler** sayfası bunları listeler.

## Test parçalama

Test parçalama, test paketinizi CI çalıştırıcılarına dağıtır. Tuist, önceki çalıştırmalarda her test dosyasının ne kadar sürdüğünü kullanarak parçaları dengeler; projeyi bir kez derler ve bu derlemeyi her çalıştırıcıyla paylaşır. Parçaları planlamak için tek bir komut yeterlidir:

```bash
mix tuist.test.build --shard-max 4
```

Her çalıştırıcı daha sonra `TUIST_SHARD_INDEX` ayarlanmış olarak kendi parçasını çalıştırır ve sonuçlar panoda tek bir test çalıştırması olarak görünür:

```bash
TUIST_SHARD_INDEX=0 mix test
```

## Ekibi dahil edin

İçgörüler, projeye bağlı kişi sayısı arttıkça çoğalır. Ekibinizdeki kişileri panodaki hesap ayarlarından organizasyona davet edin ve <.localized_link href="/guides/integrations/authentication/sso">Tek Oturum Açma</.localized_link> (Google, Okta, Microsoft) özelliğini yapılandırın; böylece kayıt işlemi kişi başına `mix tuist.login` yerine tek bir tıklama olur.

CI için kişisel giriş kullanmayın. GitHub Actions, CircleCI ve Bitrise OpenID Connect üzerinden kimlik doğrulayabilir; diğer sağlayıcılarda kapsamı kısıtlanmış bir `TUIST_TOKEN` ayarlayın. <.localized_link href="/guides/install-hex-package#authenticate">CI kimlik doğrulama adımları</.localized_link>nı izleyin.
