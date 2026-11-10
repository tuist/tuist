---
{
  "title": "Gradle önizlemeleri",
  "titleTemplate": ":title · Önizlemeler · Tuist",
  "description": "Tuist Previews ile Gradle projelerinden Android uygulamaları ve yerel komut satırı araçları oluşturun ve paylaşın."
}
---
# Gradle önizlemeleri

Android uygulamalarını ve yerel komut satırı araçlarını doğrudan Gradle üzerinden derleyin ve paylaşın. Projeyi bağlamak ve kimlik doğrulaması yapmak için <.localized_link href="/guides/get-started/gradle-project">Gradle proje rehberi</.localized_link> ile başlayın.

## Android uygulamaları

```bash
./gradlew :app:tuistShareDebug
```

`dev.tuist` ayarlar eklentisi, Android Gradle Plugin (8.8.2 veya üzeri) tarafından sağlanan her uygulama varyantı için bir `tuistShare<Variant>` görevi kaydeder. `app` ve `Debug` değerlerini kendi uygulama modülünüz ve varyantınızla değiştirin; örneğin bir ürün çeşidi için `:app:tuistShareDemoDebug`. Görev, APK'yı yayınlamadan önce Gradle'ın bildirilen yapıt bağımlılıkları aracılığıyla derler. Derleme çıktıları güncel olduğunda veya derleme önbelleğinden geri yüklendiğinde de çalışır.

Yalnızca tek, imzalı ve evrensel bir uygulama APK'sı desteklenir. Android'in hata ayıklama varyantı normalde bir hata ayıklama imzalama anahtarı kullanır; sürüm varyantları kendi imzalama yapılandırmanızı gerektirir. Görev, kimlik doğrulama veya yükleme öncesinde APK imzasını doğrular. İmzasız, geçersiz, enstrümantasyon ve bölünmüş APK'lar reddedilir. Kütüphane modülleri, test APK'ları ve Android Uygulama Paketleri (`.aab`) yayın hedefi değildir.

## Yerel komut satırı araçları

Gradle'ın `cpp-application` veya `swift-application` eklentisini kullanan projeler, her yerel ikili dosya için bir paylaşım görevi alır:

```bash
./gradlew :app:tuistShareMainDebug
```

Görev, yüklenen dağıtımı, başlatıcısı ve çalışma zamanı kütüphaneleri dahil olmak üzere derler ve paketler. Sürüm ikili dosyası için `tuistShareMainRelease` kullanın. Birden fazla makineyi hedefleyen projelerde her ikili dosya için bir görev bulunur; adlarını bulmak için `./gradlew :app:tasks --all` komutunu çalıştırın.

arm64 veya x86_64 için yerel macOS ve Linux çalıştırılabilir dosyaları desteklenir. Gradle eklentinizin gerektirdiği araç zinciriyle hedef platformda derleme yapın. JVM uygulamaları ve oluşturulan başlatıcı betikleri bu entegrasyon tarafından desteklenmez.

## Yayınlama davranışı

Paylaşım görevleri, Tuist CLI'yı çağırmadan eklentinin mevcut Tuist kimlik bilgilerini kullanarak yayın yapar. Normal `assemble`, `build` ve test görevleri asla önizleme yayınlamaz.

Paylaşım sonrası, bağlantıyı kopyalamak için projenizde **Önizlemeler** bölümünü açın. Aynı derleme ve iz için paylaşımı tekrarlamak, önbellek isabeti sonrasında bile yayınlamayı yeniden kullanır. Başarısız veya onaylanmamış yüklemeler paylaşım görevini başarısız kılar; başarılı önizlemeler olarak raporlanmazlar.

## CI ve izler

Eklentinin diğer kimlik doğrulamalı özelliklerinde kullandığınız aynı kimlik bilgileriyle <.localized_link href="/guides/integrations/continuous-integration">CI kimlik doğrulaması</.localized_link> yapılandırın, ardından yayınlamayı açıkça isteyin:

```bash
./gradlew :app:tuistShareDebug --track nightly
```

`--track nightly` ifadesini yerel bir paylaşım görevine aynı şekilde ekleyin. Görevler, yapılandırılmış Tuist projesini, sunucu URL'sini ve proxy ayarlarını kullanır. Önizleme yayınlaması her zaman kimlik doğrulama gerektirir. Git revizyon meta verileri, sürüm notları ve otomatik çekme isteği yorumları bu görevler tarafından eklenmez.

Barındırılan Tuist'te yapıt yayınlamaları 30 gün sonra sona erer. Kendi kendine barındırılan örnekler `TUIST_APP_PREVIEW_RETENTION_DAYS` kullanır; bu değişkeni ayarlamamak, bu aile için sona ermeyi devre dışı bırakır. Süresi dolmuş yayınlamalar, aynı niyeti tekrarlayarak canlandırılamaz.

## Mevcut bir APK'yı paylaşın

Bu iş akışının dışında derlenen bir APK için veya eski yükleme akışıyla birlikte sürüm notları eklemek amacıyla CLI hala kullanılabilir:

```bash
tuist share app/build/outputs/apk/debug/app-debug.apk \
  --track nightly --release-notes "Improve checkout"
```

Yayınlanan derlemeleri çalıştırmak, erişim, izler ve README rozetleri için <.localized_link href="/guides/features/previews#run-a-preview">Bir önizlemeyi çalıştır</.localized_link> bölümüne bakın.

<!-- @snippet: ./_tuist-share -->
