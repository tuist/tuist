---
{
  "title": "Bazel projesi",
  "titleTemplate": ":title · Başlangıç · Kılavuzlar · Tuist",
  "description": "Herhangi bir BUILD dosyasını değiştirmeden, CI ortamında ortak bir uzak önbellek ve derleme ile test içgörülerinden yararlanmak için bir Bazel çalışma alanını Tuist ile entegre edin."
}
---
# Bazel projesi {#bazel-project}

::: code-group

```text [Agent prompt]
Help me get started with Tuist. Follow the setup at:
https://tuist.dev/en/docs/guides/get-started/bazel-project
```

:::

Mevcut bir Bazel çalışma alanını Tuist’e bağlamak için bu yolu izleyin. Tuist, Bazel’in uzak önbellek olarak bağlandığı bir [Remote Execution API](https://github.com/bazelbuild/remote-apis) önbelleği ve her derleme ile testi panoda görünür verilere dönüştüren bir Build Event Service akışı sunar. Tuist’in Bazel’e neler kattığına genel bakış için [Bazel with Tuist](https://tuist.dev/build-systems/bazel) sayfasına bakın. Başka bir Bazel sağlayıcısından geçiş yapıyorsanız, değişiklikleri [BuildBuddy](https://tuist.dev/compare/buildbuddy) ve [EngFlow](https://tuist.dev/compare/engflow) karşılaştırmaları ele alır.

Aşağıdaki her bölüm, bugün eksik olan şeyle başlar ve ardından boşluğu dolduran özelliği adım adım gösterir.

## Ön koşullar

- Bir Bazel çalışma alanı (kökünde bir `WORKSPACE` veya `MODULE.bazel`) ve `PATH` üzerinde bulunan Bazel.
- <.localized_link href="/guides/install-tuist">Tuist komut satırı arayüzü</.localized_link>.

## Çalışma alanını bağla

Bazel çalışma alanının kökünden `tuist init` komutunu çalıştırın. Tuist, `WORKSPACE` / `MODULE.bazel` dosyalarını algılar ve **Bir Bazel çalışma alanını entegre et** seçeneğini sunar. Tarayıcıda kimlik doğrulaması yapın ve projenin sahibi olması gereken hesabı seçin.

```bash
tuist init
```

Bunu bir kodlama ajanı veya betik üzerinden yürütüyorsanız, önce `tuist auth login` komutunu çalıştırın (tarayıcı akışı Enter tuşuna basmanızı bekler), ardından etkileşimsiz formu kullanın:

```bash
tuist init --build-system bazel --name <project-handle> --account <account>
```

init tamamlandığında Tuist:

1. Proje tanıtıcısıyla birlikte çalışma alanı köküne bir `tuist.toml` yazar.
2. `.bazelrc` dosyanızın yanına, en yakın Tuist önbellek bölgesine bağlı ve çalışma alanı başına kimlik bilgisi yardımcısı üzerinden kimliği doğrulanmış bir `.bazelrc.tuist` yazar.
3. `.bazelrc` dosyanıza bir `try-import %workspace%/.bazelrc.tuist` satırı ekler.

`try-import` satırını commit edin. Her makinede aynıdır. `.bazelrc.tuist` dosyasını `.gitignore` dosyanıza ekleyin. Kimlik bilgisi yardımcısı yolu kullanıcı başına, önbellek bölgesi ise konum başına olduğundan paylaşılmamalıdır.

Çalışma alanı bağlandığında aşağıdaki her şey otomatik olarak etkinleşir.

## Uzak önbellek

Bazel’in kendi yerel disk önbelleği `~/.cache/bazel` altında (veya `--disk_cache` parametresinin işaret ettiği yerde) bulunur. Bir geliştiricinin makinesindeki bir önbellek isabeti başkasına ulaşmaz ve CI iş kapsayıcıları her çalıştırmada boş bir önbellekle başlar.

Bazel’in [Remote Execution API](https://github.com/bazelbuild/remote-apis), aynı önbelleği paylaşılan bir uç noktaya genişletmek için kullanılan protokoldür. Tuist bu protokolü destekler. `.bazelrc.tuist` hazır olduğunda, Bazel çıktıları zaten paylaşılan önbellekte bulunan eylemleri atlar ve bunları bunun yerine indirir. Bir makinedeki iş, aynı revizyonu derleyen diğer tüm makinelerin yararına olur.

Aynı revizyona karşı iki temiz derlemeyle doğrulayın (yerel olarak veya biri yerel + biri CI):

```bash
bazel clean
bazel build //...
```

İkinci çalıştırmanın özeti önbellek isabetlerini raporlamalıdır. Zaman içindeki isabet oranlarını görmek için panoda **Cache** bölümünü açın.

## Derleme ve test içgörileri

Bazel’in derleme olay akışı ve test başına XML raporları her çağrıda yayımlanır. Bir hafta boyunca hedef düzeyindeki süreleri karşılaştırmak veya birkaç CI çalıştırması boyunca kararsız hale gelen bir testi fark etmek, bu olayları bir yerde toplayıp toplamayı gerektirir.

Bazel’in zaten yayımladığı Build Event Service protokolü tam da bunun için tasarlanmıştır. `tuist init` tarafından yazılan `.bazelrc.tuist`, BES akışını Tuist’e göre yapılandırır; böylece derleme ve test içgörileri sonraki `bazel build` ve `bazel test` komutlarında akmaya başlar. Ekstra yapılandırma gerekmez. Verileri görmek için panoda **Builds** ve **Tests** bölümlerini açın.

## Ekibi dahil edin

Önbellek isabetleri ve içgörüler, projeye bağlı kişi sayısı arttıkça katlanarak büyür. Panodaki hesap ayarlarından takım arkadaşlarınızı organizasyona davet edin ve kişisel `tuist auth login` yerine tek tıkla katılım sağlamak için <.localized_link href="/guides/integrations/authentication/sso">Single Sign-On</.localized_link> (Google, Okta, Microsoft) kurulumunu yapın.
