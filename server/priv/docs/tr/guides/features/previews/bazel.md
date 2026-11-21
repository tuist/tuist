---
{
  "title": "Bazel önizlemeleri",
  "titleTemplate": ":title · Önizlemeler · Tuist",
  "description": "Android uygulamalarını, Apple uygulamalarını ve komut satırı araçlarını Bazel'den önizleme olarak yayınlayın."
}
---
# Bazel önizlemeleri

Mevcut Bazel hedeflerinizden Android APK'ları, Apple simülatör ve macOS uygulamalarını ve komut satırı araçlarını yayınlayın. Paylaşmak istediğiniz her çıktı için bir önizleme hedefi ekleyin; normal derlemeleriniz değişmeden kalır.

## Kurulum

Tuist deposundan [`rules_tuist` öğesini](https://github.com/tuist/tuist/tree/main/bazel) `MODULE.bazel` dosyasına ekleyin ve kullanmak istediğiniz commit'i sabitleyin:

```starlark
bazel_dep(name = "rules_tuist")

git_override(
    module_name = "rules_tuist",
    remote = "https://github.com/tuist/tuist.git",
    commit = "FULL_COMMIT_SHA",
    strip_prefix = "bazel",
)
```

Mevcut uygulama hedeflerinizi, yerel SDK'larınızı ve imzalama ayarlarınızı koruyun. Yayınlama araçlarını Bazel sağlar.

Doğrudan Bazel üzerinden giriş yapın:

```bash
bazel run @rules_tuist//:login
```

Bu işlem kimlik bilgilerini Tuist CLI ve Gradle eklentisiyle paylaşır; mevcut bir giriş de çalışır. CI'da `TUIST_TOKEN` kullanın veya Tuist'in <.localized_link href="/guides/integrations/continuous-integration">OIDC kimlik doğrulaması</.localized_link> ile giriş hedefini çalıştırın. Kimlik bilgilerini asla BUILD dosyalarına veya kural özniteliklerine koymayın. Kendi barındırdığınız bir örneğe giriş yapmak için `-- --url https://tuist.example.com` parametresini iletin.

`BUILD.bazel` dosyanızda yalnızca ihtiyacınız olan adaptörü yükleyin:

```starlark
load("@rules_tuist//:android.bzl", "android_preview")

android_preview(name = "preview_android", app = ":android_app")
```

Apple uygulamaları için:

```starlark
load("@rules_tuist//:apple.bzl", "apple_preview")

apple_preview(name = "preview_ios", app = ":ios_app")
apple_preview(name = "preview_macos", app = ":macos_app")
```

`cc_binary` gibi çalıştırılabilir hedefler için:

```starlark
load("@rules_tuist//:executable.bzl", "executable_preview")

executable_preview(name = "preview_cli", binary = ":my_tool")
```

Çalıştırılabilir önizleme, hedefin bildirilen çalışma zamanı dosyalarını içerir. Aracınızın ihtiyaç duyduğu kütüphaneleri ve kaynakları Bazel hedefinizde bildirin ve derleme dizininizin dışında çalışan yollar kullanın.

## Derleme ve yayınlama

```bash
bazel run //:preview_android -- \
  --publish --project acme/app --track review
bazel run //:preview_ios --platforms=//platforms:ios_simulator -- \
  --publish --project acme/app --track review
bazel run //:preview_macos -- --publish --project acme/app --track review
bazel run //:preview_cli -- --publish --project acme/app --track review
```

Uygulama ve simülatör platformu etiketlerini kendi etiketlerinizle değiştirin. Kendi barındırdığınız Tuist kaynağı için `--url` ve bir Git commit'ini ilişkilendirmek için `--revision` parametresini iletin.

Başarılı bir derlemeyi paylaşmak için `--publish --project account/project` parametresini iletin. `--publish` olmadan veya `--no-publish` ile hiçbir şey yüklenmez ve giriş gerekmez. Normal `bazel build` komutu, önbellek isabetlerinde bile asla yayınlama yapmaz. `tuist bazel setup` yayınlamayı değil, önbelleğe almayı ve içgörüler etkinleştirir.

## Desteklenen çıktılar

- **Android:** hata ayıklama derlemeleri dahil olmak üzere imzalı uygulama APK'ları. Android SDK derleme araçlarını ve komut satırı araçlarını kurun ve `ANDROID_HOME` veya `ANDROID_SDK_ROOT` ortam değişkenlerini ayarlayın. Test APK'ları ve Android App Bundle'ları desteklenmez.
- **Apple:** macOS üzerinde derlenen ve doğrulanan, ad-hoc imzalı simülatör ve macOS uygulamaları. Fiziksel cihaz derlemeleri, çerçeveler, uzantılar ve testler desteklenmez. Deneysel ağaç arşivleri yerine arşiv çıktısını kullanın.
- **Komut satırı araçları:** arm64 veya x86_64 için macOS veya Linux çalıştırılabilirleri, evrensel macOS ikilileri dahil. Betikler, alıcının sisteminde bir shebang ve yorumlayıcı gerektirir. Çalışma zamanı bağımlılıklarını hedefinizde bildirin; Tuist eksik kütüphaneleri veya dil çalışma zamanlarını yüklemez.

## Önbellek tekrarı, hatalar ve saklama

Aynı yayınlamayı tekrarlamak, Bazel derlemeyi önbellekten geri yüklese bile mevcut önizlemeyi yeniden yüklemeksizin yeniden kullanır. Çıktıyı, kanalı veya revizyonu değiştirmek yeni bir yayınlama oluşturur. Bir yükleme hatası komutu başarısız kılar; tekrar denemeden önce yayınlamanın tamamlanıp tamamlanmadığını kontrol etmek için komutu yeniden çalıştırabilirsiniz.

Komut, projenizin önizlemelerine bağlantı verir; burada işleme kısa bir süre alabilir. Önizlemeler, projenin varsayılan görünürlüğünü kullanır.

Barındırılan Tuist'te yapıt yayınlamaları 30 gün sonra sona erer. Kendi barındırdığınız örnekler `TUIST_APP_PREVIEW_RETENTION_DAYS` kullanır; bu ayarı boş bırakmak bu aile için sona ermeyi devre dışı bırakır. Süresi dolmuş yayınlama kayıtları, aynı niyeti tekrarlayarak canlandırılamaz.

Yayınlanan derlemeleri çalıştırmak, erişim, kanallar ve README rozetleri için <.localized_link href="/guides/features/previews#run-a-preview">Önizleme çalıştırma</.localized_link> bölümüne bakın.

## Apple önizlemeleri

Apple simülatör ve macOS önizlemeleri için <.localized_link href="/guides/features/previews/run/macos">Tuist macOS yardımcı uygulama talimatlarına</.localized_link> bakın. Bunlar, Bazel'in uygulama uygunluğu veya imzalama gereksinimlerini değiştirmez.

## İlgili iş akışları {#publish-from-once}

Mevcut Struo entegrasyonlarının ayrı bir <.localized_link href="/guides/features/previews/struo">yapıt yayınlama kılavuzu</.localized_link> vardır. Her iki iş akışı da yayınlamayı, önbelleğe alınmış grafik yürütmesinden ayrı tutar.
