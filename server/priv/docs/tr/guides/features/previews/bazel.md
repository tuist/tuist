---
{
  "title": "Bazel önizlemeleri",
  "titleTemplate": ":title · Önizlemeler · Tuist",
  "description": "Android uygulamalarını, Apple uygulamalarını ve komut satırı araçlarını Bazel'den önizleme olarak yayınlayın."
}
---
# Bazel önizlemeleri

Mevcut Bazel hedeflerinizden Android APK’ları, Apple simülatör ve macOS uygulamaları ile komut satırı araçlarını yayınlayın. Paylaşmak istediğiniz her çıktı için bir önizleme hedefi ekleyin; normal derlemeleriniz değişmez.

## Kurulum

Kullanmak istediğiniz commit’i sabitleyerek [`rules_tuist` Tuist deposundan](https://github.com/tuist/tuist/tree/main/bazel) `MODULE.bazel` dosyasına ekleyin:

```starlark
bazel_dep(name = "rules_tuist")

git_override(
    module_name = "rules_tuist",
    remote = "https://github.com/tuist/tuist.git",
    commit = "FULL_COMMIT_SHA",
    strip_prefix = "bazel",
)
```

Mevcut uygulama hedeflerinizi, yerel SDK’larınızı ve imzalama ayarlarınızı koruyun. Yayınlama araçlarını Bazel sağlar.

Doğrudan Bazel üzerinden giriş yapın:

```bash
bazel run @rules_tuist//:login
```

Bu, kimlik bilgilerini Tuist CLI ve Gradle eklentisiyle paylaşır; mevcut bir oturum da çalışır. CI’da `TUIST_TOKEN` kullanın veya Tuist’in <.localized_link href="/guides/integrations/continuous-integration">OIDC kimlik doğrulaması</.localized_link> ile login hedefini çalıştırın. Kimlik bilgilerini asla BUILD dosyalarına veya kural özniteliklerine koymayın. Kendi barındırdığınız bir örneğe giriş yapmak için `-- --url https://tuist.example.com` parametresini iletin.

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

Çalıştırılabilir önizleme, hedefin belirttiği çalışma zamanı dosyalarını içerir. Aracınızın ihtiyaç duyduğu kitaplıkları ve kaynakları Bazel hedefinizde bildirin ve derleme dizininiz dışında çalışan yollar kullanın.

## Derleme ve yayınlama

```bash
bazel run //:preview_android -- \
  --publish --project acme/app --track review
bazel run //:preview_ios --platforms=//platforms:ios_simulator -- \
  --publish --project acme/app --track review
bazel run //:preview_macos -- --publish --project acme/app --track review
bazel run //:preview_cli -- --publish --project acme/app --track review
```

Uygulama ve simülatör platform etiketlerini kendi etiketlerinizle değiştirin. Kendi barındırdığınız Tuist kaynağı için `--url` ve bir Git commit’i ilişkilendirmek için `--revision` parametresini iletin.

Başarılı bir derlemeyi paylaşmak için `--publish --project account/project` parametresini iletin. `--publish` olmadan veya `--no-publish` ile hiçbir şey yüklenmez ve giriş gerekmez. Normal `bazel build` asla yayınlama yapmaz; önbellek isabetlerinde bile. `tuist bazel setup` önbellekleme ve içgörüler sağlar, yayınlama sağlamaz.

## Desteklenen çıktılar

- **Android:** hata ayıklama derlemeleri dahil olmak üzere imzalı uygulama APK’ları. Android SDK yapı araçlarını ve komut satırı araçlarını kurun ve `ANDROID_HOME` veya `ANDROID_SDK_ROOT` ortam değişkenlerini ayarlayın. Test APK’ları ve Android App Bundle’lar desteklenmez.
- **Apple:** macOS üzerinde derlenen ve doğrulanan, ad-hoc imzalı simülatör ve macOS uygulamaları. Fiziksel cihaz derlemeleri, framework’ler, uzantılar ve testler desteklenmez. Deneysel ağaç arşivleri yerine arşiv çıktısını kullanın.
- **Komut satırı araçları:** arm64 veya x86_64 için macOS veya Linux çalıştırılabilirleri; evrensel macOS ikilileri dahil. Betikler, alıcı sisteminde bir shebang ve yorumlayıcı gerektirir. Çalışma zamanı bağımlılıklarını hedefinizde bildirin; Tuist eksik kitaplıkları veya dil çalışma zamanlarını yüklemez.

## Önbellek yeniden oynatma, hatalar ve saklama

Aynı yayınlamayı tekrarlamak, Bazel derlemeyi önbellekten geri yüklese bile mevcut önizlemeyi yeniden kullanarak tekrar yüklemez. Çıktıyı, track’i veya revizyonu değiştirmek yeni bir yayınlama oluşturur. Yükleme hatası komutu başarısız kılar; tekrar denemeden önce yayınlamanın tamamlanıp tamamlanmadığını kontrol etmek için komutu yeniden çalıştırabilirsiniz.

Komut, projenizin önizlemelerine bağlantı verir; burada işleme kısa bir süre alabilir. Önizlemeler, projenin varsayılan görünürlüğünü kullanır.

Barındırılan Tuist’te yapıt yayınlamaları 30 gün sonra sona erer. Kendi barındırdığınız örnekler `TUIST_APP_PREVIEW_RETENTION_DAYS` kullanır; bu ayarı boş bırakmak bu aile için sona ermeyi devre dışı bırakır. Süresi dolmuş yayınlama kayıtları, aynı niyeti yeniden oynatarak canlandırılamaz.

Yayınlanan derlemeleri çalıştırmak, erişim, track’ler ve README rozetleri için <.localized_link href="/guides/features/previews#run-a-preview">Önizleme çalıştırma</.localized_link> bölümüne bakın.

## Apple önizlemeleri

Apple simülatör ve macOS önizlemeleri için <.localized_link href="/guides/features/previews/run/macos">Tuist macOS yardımcı uygulama talimatları</.localized_link> sayfasına bakın. Bunlar, Bazel’in uygulama uygunluğu veya imzalama gereksinimlerini değiştirmez.

## İlgili iş akışları {#publish-from-once}

Mevcut Once entegrasyonlarının ayrı bir <.localized_link href="/guides/features/previews/once">yapıt yayınlama kılavuzu</.localized_link> vardır. Her iki iş akışı da yayınlamayı, önbelleğe alınmış grafik yürütmesinden ayrı tutar.
