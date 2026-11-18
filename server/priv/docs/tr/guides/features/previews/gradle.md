---
{
  "title": "Gradle önizlemeleri",
  "titleTemplate": ":title · Önizlemeler · Tuist",
  "description": "Tuist Previews ile Gradle projelerinden Android uygulamaları ve yerel komut satırı araçları oluşturun ve paylaşın."
}
---
# Gradle önizlemeleri

Android uygulamalarını ve yerel komut satırı araçlarını doğrudan Gradle'dan oluşturun ve paylaşın. Projeyi bağlamak ve kimlik doğrulaması yapmak için <.localized_link href="/guides/get-started/gradle-project">Gradle proje kılavuzu</.localized_link> ile başlayın.

## Android uygulamaları

```bash
./gradlew :app:tuistShareDebug
```

`dev.tuist` ayarlar eklentisi, Android Gradle Plugin (8.8.2 veya üzeri) tarafından sağlanan her uygulama varyantı için bir `tuistShare<Variant>` görevi kaydeder. `app` ve `Debug` değerlerini kendi uygulama modülünüz ve varyantınızla değiştirin; örneğin bir ürün çeşidi için `:app:tuistShareDemoDebug`. Görev, APK'yı yayınlamadan önce Gradle'ın bildirilen yapıt bağımlılıkları aracılığıyla oluşturur. Yapı çıktıları güncel olduğunda veya yapı önbelleğinden geri yüklendiğinde de çalışır.

Yalnızca tek, imzalı, evrensel bir uygulama APK'sı desteklenir. Android'in hata ayıklama varyantı normalde bir hata ayıklama imzalama anahtarı kullanır; sürüm varyantları kendi imzalama yapılandırmanızı gerektirir. Görev, kimlik doğrulama veya yükleme öncesinde APK imzasını doğrular. İmzasız, geçersiz, enstrümantasyon ve bölünmüş APK'lar reddedilir. Kütüphane modülleri, test APK'ları ve Android Uygulama Paketleri (`.aab`) yayın hedefi değildir.

## Yerel komut satırı araçları

Gradle'ın `cpp-application` veya `swift-application` eklentisini kullanan projeler, her yerel ikili dosya için bir paylaşım görevi alır:

```bash
./gradlew :app:tuistShareMainDebug
```

Görev, başlatıcısı ve çalışma zamanı kütüphaneleri dahil olmak üzere kurulu dağıtımı oluşturur ve paketler. Sürüm ikilisi için `tuistShareMainRelease` kullanın. Birden fazla makineyi hedefleyen projelerde her ikili dosya için bir görev bulunur; adlarını bulmak için `./gradlew :app:tasks --all` çalıştırın.

arm64 veya x86_64 için yerel macOS ve Linux yürütülebilir dosyaları desteklenir. Gradle eklentinizin gerektirdiği araç zinciriyle hedef platformda derleme yapın. JVM uygulamaları ve bunların oluşturulan başlatıcı betikleri bu entegrasyon tarafından desteklenmez.

## Yayınlama davranışı

Paylaşım görevleri, Tuist CLI'yı çağırmadan eklentinin mevcut Tuist kimlik bilgilerini kullanarak yayın yapar. Normal `assemble`, `build` ve test görevleri asla önizleme yayınlamaz.

Paylaşım sonrası, bağlantıyı kopyalamak için projenizde **Önizlemeler** bölümünü açın. Aynı yapı ve kanalın paylaşımını tekrarlamak, önbellek isabeti sonrasında bile yayını yeniden kullanır. Başarısız veya onaylanmamış yüklemeler paylaşım görevini başarısız kılar; başarılı önizlemeler olarak raporlanmazlar.

## CI ve kanallar

Eklentinin diğer kimlik doğrulamalı özelliklerinde kullandığınız aynı kimlik bilgileriyle <.localized_link href="/guides/integrations/continuous-integration">CI kimlik doğrulamasını</.localized_link> yapılandırın, ardından yayınlamayı açıkça isteyin:

```bash
./gradlew :app:tuistShareDebug --track nightly
```

Aynı şekilde bir yerel paylaşım görevine `--track nightly` ekleyin. Görevler, yapılandırılmış Tuist projesini, sunucu URL'sini ve proxy ayarlarını kullanır. Önizleme yayınlaması her zaman kimlik doğrulaması gerektirir. Git revizyon meta verileri, sürüm notları ve otomatik çekme isteği yorumları bu görevler tarafından eklenmez.

Barındırılan Tuist'te yapıt yayınları 30 gün sonra sona erer. Kendi kendine barındırılan örnekler `TUIST_APP_PREVIEW_RETENTION_DAYS` kullanır; ayarlanmamış bırakılması bu aile için süresi dolmayı devre dışı bırakır. Süresi dolmuş yayınlar, aynı niyeti tekrarlayarak canlandırılamaz.

## Mevcut bir APK'yı paylaşma

Bu iş akışının dışında oluşturulan bir APK için veya eski yükleme akışıyla sürüm notları eklemek amacıyla CLI hala kullanılabilir:

```bash
tuist share app/build/outputs/apk/debug/app-debug.apk \
  --track nightly --release-notes "Improve checkout"
```

Yayınlanan yapıları çalıştırmak, erişim, kanallar ve README rozetleri için <.localized_link href="/guides/features/previews#run-a-preview">Bir önizleme çalıştırma</.localized_link> bölümüne bakın.

<!-- @snippet: ./_tuist-share -->
