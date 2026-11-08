---
{
  "title": "Once projesi",
  "titleTemplate": ":title · Başlarken · Kılavuzlar · Tuist",
  "description": "Paylaşımlı önbellekleme, canlı derleme ve test içgörüleri, test parçalama ve uygulama önizlemeleri için Once'i Tuist'e bağlayın."
}
---
# Once projesi {#once-project}

::: code-group

```text [Agent prompt]
Help me get started with Tuist. Follow the setup at:
https://tuist.dev/en/docs/guides/get-started/once-project
```

:::

[Once](https://buildonce.dev), önbelleğe alınabilen betikleri ve derleme grafiklerini çalıştırır. Önbelleğe alınmış işleri makineler arasında paylaşmak, çalışmaları canlı olarak izlemek ve ekibinizin denemesi için uygulamaları yayınlamak amacıyla Tuist ile entegre edin. Mevcut proje kaynaklarınızı ve derleme tanımlarınızı koruyun; entegrasyon `once.toml` içinde yer alır.

## Ön Koşullar

- [Once](https://buildonce.dev/docs/guide/getting-started) kurulu olmalı ve bir çalışma alanı veya önbelleğe alınabilen bir betik bulunmalıdır.
- Bir Tuist hesabı. Once entegrasyonu için Tuist CLI gerekli değildir.

## Projeyi bağlayın {#connect-the-project}

Depo kök dizininizden şunu çalıştırın:

```bash
once connect --provider tuist --create
```

Once gerektiğinde sizi oturum açtırır, kişisel hesabınız altında bir Tuist projesi oluşturur ve sağlayıcı bağlantısını `once.toml` dosyasına yazar. Başka bir hesap veya mevcut bir proje seçmek için bkz. [Bir projeyi bağlama](https://buildonce.dev/docs/guide/infrastructure/connect).

Mevcut bir Tuist projesi için sağlayıcıyı ve önbellek bağlantısını kendiniz yapılandırın:

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
once auth login --provider tuist
```

Kimlik bilgilerinizi değil, hedefi ekip arkadaşlarınız ve CI ile paylaşmak için `once.toml` dosyasını commit edin. Her geliştirici kendi makinesinde oturum açar.

## Paylaşılan önbellek

Yerel bir önbellek yalnızca onu dolduran makineye yardımcı olur. Tuist yapılandırıldığında, Once aynı işi tekrar çalıştırmak yerine başka bir geliştirici veya CI tarafından üretilen eşleşen sonuçları geri yükleyebilir.

Önbelleğe alınabilen betiğinizi veya bir grafik hedefini her zamanki gibi çalıştırın:

```bash
once build MyApplication
```

Uzak önbellek etkinliğini incelemek için panoda **Once Cache** öğesini açın. Kurulum ve makineler arası yeniden kullanım kontrolü için bkz. <.localized_link href="/guides/features/cache/once">Once önbelleği</.localized_link>.

## Derleme içgörileri

Once, bir çalışma başladığında bir pano bağlantısı yazdırır. Çalışma ilerlerken grafiği, eylem durumunu ve önbellek kararlarını takip etmek için bu bağlantıyı açın. Yerel ve CI performansını karşılaştırmak ve başarısız eylemleri araştırmak için **Derlemeler** bölümünü kullanın. Tam süreç çıktısı için CI günlüklerini saklayın; ham eylem günlüğü alımı şu anda kullanılamamaktadır.

Nelerin kaydedildiğini ve kodlama ajanlarından veya Grafana'dan buna nasıl erişileceğini öğrenmek için bkz. <.localized_link href="/guides/features/build-insights/once">Once derleme içgörileri</.localized_link>.

## Test içgörileri ve parçalama

Once test hedeflerinizi çalıştırın:

```bash
once test
```

Bildirilen paketleri, durumları, süreleri ve hataları incelemek için **Testler** bölümünü açın. Sonuçlar, test hedefinin raporlama yeteneklerine bağlıdır; bir test sürecini çalıştıran bir eylem otomatik olarak durum başına test raporu oluşturmaz.

Paket tek bir makineyi aştığında, barındırılan bir parçalama planı oluşturun ve partilerini CI çalışanlarına dağıtın. Bkz. <.localized_link href="/guides/features/test-insights/once">Once test içgörileri</.localized_link> ve <.localized_link href="/guides/features/test-sharding/once">Once test parçalama</.localized_link>.

## Önizlemeler ve paket boyutu

Desteklenen Android, Apple simülatörü ve macOS uygulamalarını yayınlamak için aynı sağlayıcıya bir yapıt bağlantısı ekleyin:

```toml
[infrastructure.artifacts]
name = "tuist"
```

```bash
once artifact publish MyApplication --track review
```

Dönen bağlantı projenizin önizlemelerini açar; işleme biraz zaman alabilir. İmzalama gereksinimleri ve derlemeler sonrası isteğe bağlı yayınlama için bkz. <.localized_link href="/guides/features/previews/once">Once önizlemeleri</.localized_link>.

Paket boyutunu izlemek için, derlenmiş bir `.app`, `.ipa`, `.xcarchive`, `.apk` veya `.aab` üzerinde Tuist CLI'yi ayrı olarak kullanın. <.localized_link href="/guides/features/bundle-insights">Apple veya Android paket içgörileri kılavuzu</.localized_link>nu takip edin; bir Once yapıtı yayınlamak otomatik olarak bir paket boyutu raporu yüklemez.

## Sürekli entegrasyon

Projenin işlemleri için yetkilendirilmiş bir hesap jetonunu `TUIST_TOKEN` içinde kullanın veya desteklenen bir CI sağlayıcısının OpenID Connect kimliği üzerinden kimlik doğrulaması yapın:

```bash
once auth login --provider tuist --no-browser
once build MyApplication
once test
```

GitHub Actions'da işe `id-token: write` ve `contents: read` izinlerini verin. Bir örnek için bkz. <.localized_link href="/guides/integrations/continuous-integration#once">Sürekli entegrasyonda Once</.localized_link>. Kişisel bir geliştirici oturumu bir CI kimlik bilgisi değildir.

## Uzak yürütme

Uzak yürütme etkinleştirilmiş hesaplar, uygun grafik komut eylemlerini Tuist'in Linux çalışanlarında da çalıştırabilir. Bu, önbelleğe alınmış sonuçları paylaşmaktan ve tüm bir CI iş akışını çalıştırmaktan ayrıdır. Çalışan gereksinimleri ve kurulumu için bkz. <.localized_link href="/guides/features/runners/once">Once uzak yürütme</.localized_link>.
