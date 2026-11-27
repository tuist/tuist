---
{
  "title": "Önizlemeler",
  "titleTemplate": ":title · Özellikler · Kılavuzlar · Tuist",
  "description": "Mobil uygulamaları, masaüstü uygulamalarını ve komut satırı araçlarını Tuist Önizlemeleri ile paylaşın; böylece ekip arkadaşlarınız bir derlemeyi yerel olarak yeniden derlemeden deneyebilir."
}
---
# Önizlemeler {#previews}

Tuist Önizlemeleri, ekip arkadaşlarınızın mobil uygulamaları, masaüstü uygulamalarını ve komut satırı araçlarını yerel olarak yeniden derlemeden denemesine olanak tanır. Bir yapıyı Tuist projenize yayınlayın, ardından önizleme bağlantısını paylaşın.

## Neyi önizleyebilirsiniz {#what-you-can-preview}

- **Mobil uygulamalar:** Android APK’ları ve Apple uygulama paketleri veya IPA’lar. Desteklenen cihazlar, simülatörler ve imzalama gereksinimleri yayınlama iş akışına bağlıdır.
- **Masaüstü uygulamaları:** macOS uygulama paketleri.
- **Komut satırı araçları:** tek başına veya bağımlılıklarıyla birlikte paketlenmiş macOS veya Linux çalıştırılabilir dosyaları.

Paketleme ve uyumluluk gereksinimleri için <.localized_link href="/guides/features/previews/types">Desteklenen türler</.localized_link> sayfasına bakın. Yapıt türü, bir önizlemenin nerede çalışabileceğini belirler; hangi derleme sisteminin onu ürettiğini dikte etmez.

## Bir önizleme yayınla {#publish-a-preview}

Kurulum ve yayınlama komutları için derleme sisteminizi seçin:

<.home_cards>
  <.home_card
    title="Xcode"
    details="Mevcut Xcode projelerinden veya Tuist tarafından oluşturulan projelerden uygulamaları paylaşın."
    link="/guides/features/previews/xcode"
  />
  <.home_card
    title="Gradle"
    details="Gradle projelerinden Android uygulamalarını ve yerel komut satırı araçlarını paylaşın."
    link="/guides/features/previews/gradle"
  />
  <.home_card
    title="Bazel"
    details="Eşlik eden Bazel kurallarıyla Android uygulamalarını, Apple uygulamalarını ve komut satırı araçlarını paylaşın."
    link="/guides/features/previews/bazel"
  />
  <.home_card
    title="Struo"
    details="Uygun Android, Apple simülatörü ve macOS uygulamalarını Struo’nun yerel yapıt sağlayıcısıyla yayınlayın."
    link="/guides/features/previews/struo"
  />
</.home_cards>

Zaten desteklenen bir yapınız varsa, derleme sistemi entegrasyonu olmadan yayınlamak için <.localized_link href="/cli/share">`tuist share`</.localized_link> kullanın. Paketleme ve imzalama gereksinimleri yine de geçerlidir.

## Bir önizleme çalıştır {#run-a-preview}

Alıcıların, önizlemeyi üreten derleme sistemine ihtiyacı yoktur. Uygun bir yapıya nasıl erişeceğinizi seçin:

<.home_cards>
  <.home_card
    title="CLI"
    details="Mobil uygulamaları, macOS uygulamalarını ve komut satırı önizlemelerini tuist run ile çalıştırın."
    link="/guides/features/previews/run/cli"
  />
  <.home_card
    title="macOS uygulaması"
    details="Uyumlu Apple önizlemelerini Tuist menü çubuğu uygulaması üzerinden çalıştırın."
    link="/guides/features/previews/run/macos"
  />
  <.home_card
    title="iPhone uygulaması"
    details="Apple önizlemelerinizi iPhone’da bulun ve erişin."
    link="/guides/features/previews/run/ios"
  />
</.home_cards>

## Görünürlük {#visibility}

Önizlemeler projenin varsayılan görünürlüğünü kullanır. Özel önizlemeler kimlik doğrulama ve proje erişimi gerektirir. Önizlemeleri proje ayarlarında yalnızca yapı herkesle paylaşılabiliyorsa herkese açık yapın. Herkese açık görünürlük, platform imzalama veya cihaz kurulum gereksinimlerini atlamaz.

## Kanallar {#tracks}

Kanallar, önizlemeleri adlandırılmış gruplara ayırır; örneğin dahili test kullanıcıları için `beta` veya otomatik yapılar için `nightly`. İş akışınız için yayınlama komutuyla bir kanal belirtin; kanallar ilk kullanıldığında tembel yüklenerek oluşturulur. Bunları önizlemeleri amaca göre gruplamak ve Tuist panosunda filtrelemek için kullanın.

## README rozeti {#readme-badge}

En son önizlemeye işaret eden bir rozeti deponuzun `README` dosyasına ekleyin:

[![Tuist Önizlemesi](https://tuist.dev/Dimillian/IcySky/previews/latest/badge.svg)](https://tuist.dev/Dimillian/IcySky/previews/latest)

Hesap ve proje tanıtıcılarını kendi bilgilerinizle değiştirin:

```markdown
[![Tuist Preview](https://tuist.dev/{account-handle}/{project-handle}/previews/latest/badge.svg)](https://tuist.dev/{account-handle}/{project-handle}/previews/latest)
```

Proje farklı paket tanımlayıcılarına sahip birden çok uygulama içeriyorsa, uygulamayı seçmek için bir `bundle-id` sorgu parametresi ekleyin:

```markdown
[![Tuist Preview](https://tuist.dev/{account-handle}/{project-handle}/previews/latest/badge.svg)](https://tuist.dev/{account-handle}/{project-handle}/previews/latest?bundle-id=com.example.app)
```
