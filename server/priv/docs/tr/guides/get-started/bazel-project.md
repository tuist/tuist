---
{
  "title": "Bazel projesi",
  "titleTemplate": ":title · Başlangıç · Kılavuzlar · Tuist",
  "description": "Bir Bazel çalışma alanını, hiçbir BUILD dosyasını değiştirmeden, CI üzerinde paylaşılan bir uzaktan önbellek ve derleme ile test içgörüleri için Tuist'e bağlayın."
}
---
# Bazel projesi {#bazel-project}

::: code-group

```text [Agent prompt]
Help me get started with Tuist. Follow the setup at:
https://tuist.dev/en/docs/guides/get-started/bazel-project
```

:::

Mevcut bir Bazel çalışma alanını Tuist’e entegre etmek için bu yolu izleyin. Tuist, Bazel’in uzak önbellek olarak bağlandığı bir [Remote Execution API](https://github.com/bazelbuild/remote-apis) önbelleği ve her derleme ile testi panoda görünür verilere dönüştüren bir Build Event Service akışı sunar.

Aşağıdaki her bölüm, bugün eksik olanla başlar ve ardından bu boşluğu dolduran özelliği adım adım açıklar.

## Ön koşullar

- Bir Bazel çalışma alanı (kökünde bir `WORKSPACE` veya `MODULE.bazel`) ve `PATH` üzerinde bulunan Bazel.
- <.localized_link href="/guides/install-tuist">Tuist komut satırı arayüzü</.localized_link>.

## Çalışma alanını bağla

Bazel çalışma alanının kökünden `tuist init` komutunu çalıştırın. Tuist, `WORKSPACE` / `MODULE.bazel` dosyalarını algılar ve **Bir Bazel çalışma alanını entegre et** seçeneğini sunar. Tarayıcıda kimlik doğrulaması yapın ve projenin sahibi olması gereken hesabı seçin.

```bash
tuist init
```

Bu işlemi bir kodlama aracısı veya betik üzerinden yürütüyorsanız, önce `tuist auth login` komutunu çalıştırın (tarayıcı akışı Enter tuşuna basmanızı bekler), ardından etkileşimsiz formu kullanın:

```bash
tuist init --build-system bazel --name <project-handle> --account <account>
```

init tamamlandığında Tuist:

1. Proje tanıtıcısıyla birlikte çalışma alanının köküne bir `tuist.toml` yazar.
2. `.bazelrc` dosyanızın yanına, en yakın Tuist önbellek bölgesine bağlanan ve çalışma alanı başına kimlik bilgisi yardımcısı üzerinden kimlik doğrulaması yapan bir `.bazelrc.tuist` yazar.
3. `.bazelrc` dosyanıza bir `try-import %workspace%/.bazelrc.tuist` satırı ekler.

`try-import` satırını commit edin. Bu satır her makinede aynıdır. `.bazelrc.tuist` dosyasını `.gitignore` dosyanıza ekleyin. Kimlik bilgisi yardımcısının yolu kullanıcı başına, önbellek bölgesi ise konum başına olduğundan paylaşılmamalıdır.

Çalışma alanı bağlandıktan sonra aşağıdakilerin tümü otomatik olarak etkinleşir.

## Uzak önbellek

Bazel’in yerel disk önbelleği `~/.cache/bazel` altında (veya `--disk_cache` nereyi gösteriyorsa orada) bulunur. Bir geliştiricinin makinesindeki bir önbellek isabeti başkalarına ulaşmaz ve CI iş kapsayıcıları her çalıştırmada boş bir önbellekle başlar.

Bazel’in [Remote Execution API](https://github.com/bazelbuild/remote-apis), aynı önbelleği paylaşılan bir uç noktaya genişletmek için kullanılan protokoldür. Tuist bu protokolü destekler. `.bazelrc.tuist` hazır olduğunda, Bazel çıktıları zaten paylaşılan önbellekte bulunan eylemleri atlar ve bunları bunun yerine indirir. Bir makinedeki çalışma, aynı revizyonu derleyen diğer tüm makinelerin yararına olur.

Aynı revizyona karşı iki temiz derlemeyle doğrulayın (yerel olarak veya biri yerel + biri CI):

```bash
bazel clean
bazel build //...
```

İkinci çalıştırmanın özeti önbellek isabetlerini raporlamalıdır. Zaman içindeki isabet oranlarını görmek için panoda **Önbellek** bölümünü açın.

## Derleme ve test içgörileri

Bazel’in derleme olayı akışı ve test başına XML raporları her çağrıda yayımlanır. Bir hafta boyunca hedef düzeyindeki süreleri karşılaştırmak veya birkaç CI çalıştırması boyunca kararsız hale gelen bir testi tespit etmek, bu olayların bir yerde toplanmasını ve агрегasyonunu gerektirir.

Bazel’in zaten yayımladığı Build Event Service protokolü tam da bunun için tasarlanmıştır. `tuist init` tarafından yazılan `.bazelrc.tuist`, BES akışını Tuist’e göre yapılandırır; böylece derleme ve test içgörüleriniz sonraki `bazel build` ve `bazel test` komutlarında akmaya başlar. Ekstra yapılandırma gerekmez. Verileri görmek için panoda **Derlemeler** ve **Testler** bölümlerini açın.

## Ekibi dahil edin

Önbellek isabetleri ve içgörüler, projeye bağlı kişi sayısı arttıkça katlanarak büyür. Ekip arkadaşlarınızı panodaki hesap ayarlarından organizasyona davet edin ve kayıt sürecinin kişi başına `tuist auth login` yerine tek tıklama olması için <.localized_link href="/guides/integrations/authentication/sso">Tek Oturum Açma</.localized_link> (Google, Okta, Microsoft) kurulumunu yapın.
