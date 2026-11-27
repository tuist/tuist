---
{
  "title": "Struo projesi",
  "titleTemplate": ":title · Başlangıç · Kılavuzlar · Tuist",
  "description": "Paylaşımlı önbellekleme, canlı derleme ve test içgörülerinden yararlanmak, testleri parçalara ayırmak ve uygulama ön izlemelerini kullanmak için Struo'yu Tuist ile entegre edin."
}
---
# Struo projesi {#struo-project}

<a id="once-project"></a>

::: code-group

```text [Agent prompt]
Help me get started with Tuist. Follow the setup at:
https://tuist.dev/en/docs/guides/get-started/struo-project
```

:::

[Struo](https://struo.run), önbelleklenebilir betikleri ve derleme grafiklerini çalıştırır. Önbelleğe alınmış işleri makineler arasında paylaşmak, çalışmaları canlı izlemek ve ekibinizin denemesi için uygulamaları yayınlamak üzere Tuist ile entegre edin. Mevcut proje kaynaklarınızı ve derleme tanımlarınızı koruyun; entegrasyon `struo.toml` içinde yer alır.

## Önkoşullar

- [Struo 1.0.0](https://github.com/tuist/struo/releases/tag/1.0.0) veya sonraki bir sürümün kurulu olması ve bir çalışma alanı ya da önbelleklenebilir betik gerekir. [Kurulum kılavuzunu](https://struo.run/docs/guide/getting-started) takip edin veya mise ile sabitleyin:

  ```bash
  mise use -g github:tuist/struo@1.0.0
  ```

- Bir Tuist hesabı. Struo entegrasyonu için Tuist CLI gerekli değildir.

## Once’ten yükseltme {#upgrading-from-once}

Struo, Once’in yeni adıdır. `once.toml` dosyalarını `struo.toml` olarak yeniden adlandırın, mise sabitlemelerini `github:tuist/once` değerinden `github:tuist/struo` değerine güncelleyin ve `once` komutlarını `struo` ile değiştirin. Betik başlıklarını `# once` değerinden `# struo` değerine ve shebang satırlarını `#!/usr/bin/env -S struo exec -- bash` değerine güncelleyin. `ONCE_*` ortam değişkenlerini `STRUO_*` olarak yeniden adlandırın; örneğin `STRUO_CACHE_PROVIDER`. Tuist kimlik bilgileri hâlâ `TUIST_TOKEN` kullanır.

Yoksayma dosyalarındaki `.once/` girdilerini `.struo/` olarak değiştirin. Çıktılar artık `.struo/out/` altında bulunur ve paylaşılan yerel içerik önbelleği `$XDG_CACHE_HOME/struo/cas` kullanır (varsayılan olarak `~/.cache/struo/cas`). Önbellek anahtarları ve yerel depolama yeni adı kullandığından, eski önbellek girdilerini taşımak yerine yükseltmeden sonra soğuk bir yerel önbellek bekleyin. `struo auth login --provider tuist` ile tekrar oturum açın.

Yeniden adlandırma, Tuist’in uyumluluk uç noktalarını değiştirmez: canlı raporlama hâlâ `once.events.v1` kullanır ve mevcut `/api/.../once` rotaları desteklenmeye devam eder. [Upstream yeniden adlandırma kılavuzuna](https://struo.run/changelog/2026-11-18-once-is-now-struo) bakın.

## Projeyi bağlama {#connect-the-project}

Depo kök dizininizden şunu çalıştırın:

```bash
struo connect --provider tuist --create
```

Struo gerektiğinde sizi oturum açtırır, kişisel hesabınız altında bir Tuist projesi oluşturur ve sağlayıcı bağlantısını `struo.toml` dosyasına yazar. Başka bir hesap veya mevcut bir proje seçmek için [Bir projeyi bağla](https://struo.run/docs/guide/infrastructure/connect) bölümüne bakın.

Mevcut bir Tuist projesi için sağlayıcı ve önbellek bağlantısını kendiniz yapılandırın:

```toml
[infrastructures.tuist]
kind = "tuist"
account = "acme"
project = "app"
# url = "https://your-tuist-server.example.com"

[infrastructure.cache]
provider = "tuist"
```

`acme` ve `app` değerlerini kendi hesap ve proje tanıtıcılarınızla değiştirin, ardından kimlik doğrulaması yapın:

```bash
struo auth login --provider tuist
```

Kimlik bilgilerinizi değil, hedefi ekip arkadaşlarınız ve CI ile paylaşmanız için `struo.toml` dosyasını commit edin. Her geliştirici kendi makinesinde oturum açar.

## Paylaşılan önbellek

Yerel önbellek yalnızca onu dolduran makineye yardımcı olur. Tuist yapılandırıldığında, Struo aynı işi tekrar çalıştırmak yerine başka bir geliştirici veya CI tarafından üretilen eşleşen sonuçları geri yükleyebilir.

Önbelleklenebilir betiğinizi veya bir grafik hedefini her zamanki gibi çalıştırın:

```bash
struo build MyApplication
```

Uzak önbellek etkinliğini incelemek için panoda **Struo Cache** öğesini açın. Kurulum ve makineler arası yeniden kullanım kontrolü için <.localized_link href="/guides/features/cache/struo">Struo önbelleği</.localized_link> bölümüne bakın.

## Derleme içgörüler

Struo, bir çalışma başladığında pano bağlantısını yazdırır. Çalışma ilerlerken grafiği, eylem durumunu ve önbellek kararlarını takip etmek için bu bağlantıyı açın. Yerel ve CI performansını karşılaştırmak ve başarısız eylemleri araştırmak için **Builds** öğesini kullanın. Tam süreç çıktısı için CI günlüklerini saklayın; ham eylem günlüğü alımı şu anda kullanılamamaktadır.

Nelerin kaydedildiğini ve kodlama ajanlarından veya Grafana’dan buna nasıl erişileceğini öğrenmek için <.localized_link href="/guides/features/build-insights/struo">Struo derleme içgörülerine</.localized_link> bakın.

## Test içgörüler ve parçalara ayırma

Struo test hedeflerinizi çalıştırın:

```bash
struo test
```

Bildirilen test paketlerini, senaryoları, süreleri ve hataları incelemek için **Tests** öğesini açın. Sonuçlar, test hedefinin raporlama yeteneklerine bağlıdır; bir test sürecini çalıştıran bir eylem otomatik olarak senaryo bazlı bir test raporu oluşturmaz.

Test paketi tek bir makinenin kapasitesini aştığında, barındırılan bir parçalama planı oluşturun ve partilerini CI çalışanlarına dağıtın. <.localized_link href="/guides/features/test-insights/struo">Struo test içgörülerine</.localized_link> ve <.localized_link href="/guides/features/test-sharding/struo">Struo test parçalamaya</.localized_link> bakın.

## Önizlemeler ve paket boyutu

Desteklenen Android, Apple simülatör ve macOS uygulamalarını yayınlamak için aynı sağlayıcıya bir yapıt bağlantısı ekleyin:

```toml
[infrastructure.artifacts]
name = "tuist"
```

```bash
struo artifact publish MyApplication --track review
```

Dönen bağlantı projenizin önizlemelerini açar; işleme biraz zaman alabilir. İmzalama gereksinimleri ve derlemeler sonrası isteğe bağlı yayınlama için <.localized_link href="/guides/features/previews/struo">Struo önizlemelerine</.localized_link> bakın.

Paket boyutunu izlemek için Tuist CLI’yi ayrı olarak derlenmiş bir `.app`, `.ipa`, `.xcarchive`, `.apk` veya `.aab` üzerinde kullanın. <.localized_link href="/guides/features/bundle-insights">Apple veya Android paket içgörüleri kılavuzunu</.localized_link> takip edin; bir Struo yapıtı yayınlamak otomatik olarak bir paket boyutu raporu yüklemez.

## Sürekli entegrasyon

Projenin işlemleri için yetkilendirilmiş bir hesap jetonunu `TUIST_TOKEN` içinde kullanın veya desteklenen bir CI sağlayıcısının OpenID Connect kimliği üzerinden kimlik doğrulaması yapın:

```bash
struo auth login --provider tuist --no-browser
struo build MyApplication
struo test
```

GitHub Actions’da işe `id-token: write` ve `contents: read` izinlerini verin. Örnek için <.localized_link href="/guides/integrations/continuous-integration#struo">Sürekli entegrasyonda Struo</.localized_link> bölümünü takip edin. Kişisel bir geliştirici oturumu bir CI kimlik bilgisi değildir.

## Uzaktan yürütme

Uzaktan yürütme etkinleştirilmiş hesaplar, uygun grafik komut eylemlerini Tuist’in Linux çalışanlarında da çalıştırabilir. Bu, önbelleğe alınmış sonuçları paylaşmaktan ve tüm bir CI iş akışını çalıştırmaktan ayrıdır. Çalışan gereksinimleri ve kurulumu için <.localized_link href="/guides/features/runners/struo">Struo uzaktan yürütme</.localized_link> bölümüne bakın.
