---
{
  "title": "Once önizlemeleri",
  "titleTemplate": ":title · Önizlemeler · Tuist",
  "description": "Android, Apple simülatörü ve macOS uygulama önizlemelerini Once'ın yerel Tuist sağlayıcısı üzerinden yayınlayın."
}
---
# Once önizlemeleri {#once-previews}

[Once](https://buildonce.dev/docs/guide/infrastructure/tuist#publish-application-previews), uygulama yapıtlarını Tuist’e yayınlayabilir; böylece ekip arkadaşları yerel olarak yeniden derlemeden bir derlemeyi deneyebilir. Bunun için Once 0.74.0+ ve yapıt alıcısına sahip bir Tuist sunucusu gerekir. Once 0.73.x bunun yerine eski tek yük bağdaştırıcısını kullanır.

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

Alıcı, bilinmeyen arayüzler dahil olmak üzere tam kümeyi, üye bildirimlerini ve yükleri saklar. Desteklenen yerel arayüzler, projenin varsayılan görünürlük, erişim ve dağıtım ayarlarını kullanarak eşzamanlı olmayan şekilde önizlemelere yansıtılır. Genel yapıt içerikleri, herkese açık projelerde bile özel kalır. Bir makbuz, önizleme işlemenin tamamlandığını değil, yalnızca yapıt depolamasını onaylar; URL’si projenin önizleme listesini açar.

## Uygun uygulamalar

Apple yansıtması, macOS’ta dışa aktarılan ad-hoc imzalı macOS ve simülatör uygulamaları için `dev.once.apple-install.v2` meta verilerini kabul eder. Fiziksel cihaz uygulamaları uygun değildir. Android yansıtması, doğrulanmış imzaya sahip `dev.once.android-install.v1` meta verilerini kabul eder. Once, otomatik yayınlamayı yalnızca hata ayıklama imzalı, enstrümantasyon içermeyen APK’lar için onaylar. Bilinmeyen arayüzler, önizleme oluşturmadan yapıt olarak indirilebilir durumda kalır. Android kurulum bağlantıları, yükler içerik özetleri altında depolanmasına rağmen bir `.apk` dosya adını korur.

## Derlemeler sonrası yayınlamaya katılma

```toml
[infrastructure]
publish_on_build = ["MyApplication"]
```

```bash
once artifact publish MyApplication --allow-on-build
once build MyApplication
```

Talep edilen tüm derlemelerin başarılı olması gerekir. Otomatik yayınlama ayrıca üreticinin tüm kapamayı onaylamasını ve bu makine, çalışma alanı, kesin uç nokta, hedef ve kararlı Tuist proje hedefi için yerel yetkilendirme yapılmasını gerektirir. Politika veya yetkilendirme olmadığında yapıt yayınlama ağ istekleri gerçekleşmez. Normal Once derlemeleri, örtülü yayınlama yan etkilerinden arındırılmıştır.

Aynı saklanmış yayınlamayı yeniden oynatmak uzak makbuzu doğrular ve başka bir yüklemeyi önler. Bu, `tuist share` içindeki yinelenen derleme davranışından farklıdır.

## Saklama

Yapıt yayınlamaları, barındırılan Tuist’te 30 gün sonra sona erer. Kendi kendine barındırılan örnekler `TUIST_APP_PREVIEW_RETENTION_DAYS` kullanır; bu değişken ayarlanmadığında bu aile için süre sonu devre dışı bırakılır. Süresi dolmuş kayıtlar mezar taşı olarak kalır ve aynı niyet yeniden oynatılarak yeniden etkinleştirilemez. Mevcut `tuist share` imzalama, görünürlük ve dağıtım iş akışları değişmeden kalır.

Yayınlanan derlemeleri çalıştırmak, erişim, izler ve README rozetleri için bkz. <.localized_link href="/guides/features/previews#run-a-preview">Önizleme çalıştırma</.localized_link>.

## Apple önizlemeleri

Uygun Apple simülatör ve macOS önizlemeleri için bkz. <.localized_link href="/guides/features/previews/run/macos">Tuist macOS yardımcı uygulama talimatları</.localized_link>. Fiziksel cihaz uygulamaları Once yayınlaması için uygun olmaya devam eder.
