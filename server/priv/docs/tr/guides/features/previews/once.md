---
{
  "title": "Once önizlemeleri",
  "titleTemplate": ":title · Önizlemeler · Tuist",
  "description": "Android, Apple simülatörü ve macOS uygulama önizlemelerini Once'ın yerel Tuist sağlayıcısı aracılığıyla yayınlayın."
}
---
# Once önizlemeleri {#once-previews}

[Once](https://buildonce.dev/docs/guide/infrastructure/tuist#publish-application-previews), uygulama yapıtlarını Tuist’e yayınlayabilir; böylece ekip arkadaşlarınız yerel ortamda yeniden derlemeden bir derlemeyi deneyebilir. Bunun için Once 0.74.0+ ve yapıt alıcısına sahip bir Tuist sunucusu gerekir. Once 0.73.x bunun yerine eski tek yük uyarlayıcısını kullanır.

## Hedefi yapılandırma

<.localized_link href="/guides/get-started/once-project">Once ile başlayın</.localized_link> kılavuzunu tamamlayın, ardından çalışma alanının `once.toml` dosyasına yapıt bağlamasını ekleyin. Önbellekleme için zaten yapılandırılmışsa sağlayıcıyı yeniden kullanın:

```toml
[infrastructures.tuist]
kind = "tuist"
account = "acme"
project = "app"

[infrastructure.artifacts]
name = "tuist"
```

```bash
once auth login --provider tuist
once artifact publish MyApplication --track review
```

Alıcı, bilinmeyen arayüzler de dahil olmak üzere tam küme, üye bildirimlerini ve yükleri saklar. Desteklenen yerel arayüzler, projenin varsayılan görünürlük, erişim ve dağıtım ayarlarını kullanarak eşzamanlı olmayan şekilde önizlemelere yansıtılır. Genel yapıt içerikleri, herkese açık projelerde bile özel kalır. Bir makbuz, yapıt depolamasını onaylar; önizleme işlemenin tamamlandığını değil. URL’si projenin önizlemeler listesini açar.

## Uygun uygulamalar

Apple yansıtması, macOS’ta dışa aktarılan ad-hoc imzalı macOS ve simülatör uygulamaları için `dev.once.apple-install.v2` meta verilerini kabul eder. Fiziksel cihaz uygulamaları uygun değildir. Android yansıtması, doğrulanmış imzaya sahip `dev.once.android-install.v1` meta verilerini kabul eder. Once, yalnızca hata ayıklama imzalı, enstrümantasyon içermeyen APK’lar için otomatik yayınlamayı onaylar. Bilinmeyen arayüzler, önizleme oluşturulmadan yapıt olarak indirilebilir durumda kalır. Android kurulum bağlantıları, yükler içerik özetleriyle saklansa bile `.apk` dosya adını korur.

## Derlemelerden sonra yayınlamaya katılma

```toml
[infrastructure]
publish_on_build = ["MyApplication"]
```

```bash
once artifact publish MyApplication --allow-on-build
once build MyApplication
```

İstenen tüm derlemeler başarılı olmalıdır. Otomatik yayınlama ayrıca üreticinin tüm kapanışı onaylamasını ve bu makine, çalışma alanı, tam uç nokta, hedef ve kararlı Tuist proje hedefi için yerel yetkilendirmeyi gerektirir. Politika veya yetkilendirme olmadan yapıt yayınlama ağ istekleri gerçekleşmez. Normal Once derlemeleri, örtülü yayınlama yan etkilerinden arındırılmıştır.

Aynı saklanmış yayınlamayı yeniden oynatmak, uzak makbuzu doğrular ve başka bir yüklemeyi önler. Bu, `tuist share` içindeki yinelenen derleme davranışından farklıdır.

## Saklama

Barındırılan Tuist’te yapıt yayınlamaları 30 gün sonra sona erer. Kendi kendine barındırılan örnekler `TUIST_APP_PREVIEW_RETENTION_DAYS` kullanır; ayarlanmaması bu aile için sona ermeyi devre dışı bırakır. Süresi dolmuş kayıtlar silinmiş kayıt olarak kalır ve aynı niyetin yeniden oynatılmasıyla yeniden etkinleştirilemez. Mevcut `tuist share` imzalama, görünürlük ve dağıtım iş akışları değişmeden kalır.

Yayınlanan derlemeleri çalıştırmak, erişim, kanallar ve README rozetleri için <.localized_link href="/guides/features/previews#run-a-preview">Bir önizlemeyi çalıştırma</.localized_link> bölümüne bakın.

## Apple önizlemeleri

Uygun Apple simülatörü ve macOS önizlemeleri için <.localized_link href="/guides/features/previews/run/macos">Tuist macOS yardımcı uygulama talimatlarına</.localized_link> bakın. Fiziksel cihaz uygulamaları Once yayınlaması için uygun olmaya devam etmez.
