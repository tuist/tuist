---
{
  "title": "Struo önizlemeleri",
  "titleTemplate": ":title · Önizlemeler · Tuist",
  "description": "Android, Apple simülatörü ve macOS uygulama önizlemelerini Struo'nun yerel Tuist sağlayıcısı aracılığıyla yayınlayın."
}
---
# Struo önizlemeleri {#struo-previews}

<a id="once-previews"></a>

[Struo](https://struo.run/docs/guide/infrastructure/tuist#publish-application-previews), uygulama yapıtlarını Tuist’e yayınlayarak ekip arkadaşlarınızın yerel olarak yeniden derlemeden bir deneme yapmasını sağlar. [Struo 1.0.0](https://github.com/tuist/struo/releases/tag/1.0.0) veya sonraki bir sürümü ve yapıt alıcısına sahip bir Tuist sunucusu kullanın.

## Hedefi yapılandırma

<.localized_link href="/guides/get-started/struo-project">Struo ile çalışmaya başlama</.localized_link> adımını tamamlayın, ardından çalışma alanının `struo.toml` dosyasına yapıt bağlamasını ekleyin. Önbellekleme için zaten yapılandırılmışsa sağlayıcıyı yeniden kullanın:

```toml
[infrastructures.tuist]
kind = "tuist"
account = "acme"
project = "app"

[infrastructure.artifacts]
name = "tuist"
```

```bash
struo auth login --provider tuist
struo artifact publish MyApplication --track review
```

Alıcı, bilinmeyen arayüzler dahil olmak üzere tam kümeyi, üye bildirimlerini ve yükleri saklar. Desteklenen yerel arayüzler, projenin varsayılan görünürlük, erişim ve dağıtım ayarları kullanılarak eşzamanlı olmayan şekilde önizlemelere yansıtılır. Genel yapıt içerikleri, herkese açık projelerde bile özel kalır. Bir makbuz, önizleme işlemenin tamamlandığını değil, yapıtın depolandığını onaylar; URL’si projenin önizleme listesini açar.

## Uygun uygulamalar

Apple projeksiyonu, macOS üzerinde dışa aktarılan ad-hoc imzalı macOS ve simülatör uygulamaları için `dev.struo.apple-install.v2` meta verilerini kabul eder. Fiziksel cihaz uygulamaları uygun değildir. Android projeksiyonu, doğrulanmış imzaya sahip `dev.struo.android-install.v1` meta verilerini kabul eder. Struo, otomatik yayınlamayı yalnızca hata ayıklama imzalı, enstrümantasyon içermeyen APK'lar için onaylar. Bilinmeyen arayüzler, önizleme oluşturulmadan artefakt olarak indirilebilir durumda kalır. Android kurulum bağlantıları, yüklerin içerik özetleri altında saklanmasına rağmen bir `.apk` dosya adını korur.

## Derlemelerden sonra yayınlamayı etkinleştirme

```toml
[infrastructure]
publish_on_build = ["MyApplication"]
```

```bash
struo artifact publish MyApplication --allow-on-build
struo build MyApplication
```

Talep edilen tüm derlemelerin başarılı olması gerekir. Otomatik yayınlama ayrıca tüm bağımlılık kümesinin üretici onayını ve bu makine, çalışma alanı, tam uç nokta, hedef ve sabit Tuist proje hedefi için yerel yetkilendirmeyi gerektirir. Politika veya yetkilendirme olmadığında yapıt yayınlama ağ isteği oluşmaz. Normal Struo derlemeleri, örtülü yayınlama yan etkilerinden arındırılmıştır.

Aynı saklanan yayınlamanın tekrarlanması uzak makbuzu doğrular ve başka bir yüklemeyi önler. Bu durum, `tuist share` öğesinin yinelenen derleme davranışından farklıdır.

## Saklama süresi

Barındırılan Tuist’te yapıt yayınlamaları 30 gün sonra sona erer. Kendi kendine barındırılan örnekler `TUIST_APP_PREVIEW_RETENTION_DAYS` kullanır; bu değer ayarlanmadığında bu aile için sona erme devre dışı bırakılır. Süresi dolmuş kayıtlar silinmiş kayıt olarak kalır ve aynı niyetin tekrarlanmasıyla yeniden etkinleştirilemez. Mevcut `tuist share` imzalama, görünürlük ve dağıtım iş akışları değişmez.

Yayınlanan derlemeleri çalıştırmak, erişim, izler ve README rozetleri için <.localized_link href="/guides/features/previews#run-a-preview">Bir önizleme çalıştırma</.localized_link> bölümüne bakın.

## Apple önizlemeleri

Uygun Apple simülatör ve macOS önizlemeleri için <.localized_link href="/guides/features/previews/run/macos">Tuist macOS yardımcı uygulama talimatları</.localized_link> sayfasına bakın. Fiziksel cihaz uygulamaları Struo yayınlaması için uygun değildir.
