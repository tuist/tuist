---
{
  "title": "Xcode önizlemeleri",
  "titleTemplate": ":title · Önizlemeler · Tuist",
  "description": "Mevcut Xcode projelerinden ve Tuist tarafından oluşturulan projelerden uygulama önizlemelerini paylaşın."
}
---
# Xcode önizlemeleri

Uygulamanızı derleyin, ardından `tuist share` kullanarak Tuist projenize yayınlayın. Projenizi öncelikle <.localized_link href="/guides/get-started/existing-xcode-project">mevcut Xcode projesi</.localized_link> veya <.localized_link href="/guides/get-started/generated-xcode-project">oluşturulmuş proje</.localized_link> kılavuzunu kullanarak bağlayın.

## Derleme ve paylaşma

Tuist tarafından oluşturulan bir proje için:

```bash
tuist generate App
tuist xcodebuild build -scheme App -workspace App.xcworkspace \
  -configuration Debug -sdk iphonesimulator
tuist share App
```

Mevcut bir Xcode projesi için:

```bash
tuist xcodebuild build -scheme App -project App.xcodeproj \
  -configuration Debug -sdk iphonesimulator
tuist share App --configuration Debug --platforms iOS
```

Şema, proje ve çalışma alanı adlarını kendi adlarınızla değiştirin. Bir Release derlemesini paylaşmak için derlerken `-configuration Release`, paylaşırken ise `--configuration Release` kullanın.

## Fiziksel cihazlar

Cihaz derlemelerini, alıcının cihazına yüklemeye izin veren bir sağlama profiliyle imzalamaktan siz sorumlusunuz. Simülatör SDK'sı yerine bir cihaz hedefiyle derleyin:

```bash
tuist xcodebuild build -scheme App -project App.xcodeproj \
  -configuration Debug -destination 'generic/platform=iOS'
tuist share App --configuration Debug --platforms iOS
```

Zaten dışa aktarılmış bir IPA dosyasını da paylaşabilirsiniz:

```bash
tuist share App.ipa
```

Alıcılar, uygulamayı yüklemek için mobil cihazlarında bir IPA önizleme bağlantısını açabilir. Kimlik doğrulama ve projenin önizleme görünürlük ayarları hâlâ geçerlidir.

## CI ve derleme numaraları

Mevcut <.localized_link href="/guides/integrations/continuous-integration">CI kimlik doğrulamanızı</.localized_link> kullanın ve her yeni derleme için `CFBundleVersion` değerini benzersiz yapın. Örneğin, GitHub Actions'ın <code v-pre>${{ github.run_number }}</code> değerini kullanın. Aynı ikili dosyayı ve derleme numarasını `tuist share` aracılığıyla tekrar yüklemek, çoğaltma oluşturmak yerine başarısız olur.

```bash
tuist share App --track beta --release-notes "Fix sign-in"
```

Yayınlanan derlemeleri çalıştırmak, erişim, kanallar ve README rozetleri için <.localized_link href="/guides/features/previews#run-a-preview">Önizleme çalıştırma</.localized_link> bölümüne bakın.

<!-- @snippet: ./_tuist-share -->

Alıcılar, derleme sistemi entegrasyonundan bağımsız olarak <.localized_link href="/guides/features/previews/run/macos">Tuist macOS uygulamasını</.localized_link> veya <.localized_link href="/guides/features/previews/run/ios">iPhone uygulamasını</.localized_link> kullanabilir. iPhone kılavuzu ayrıca Tuist SDK ile <.localized_link href="/guides/features/previews/run/ios#in-app-update-notifications">uygulama içi güncelleme bildirimlerini</.localized_link> de kapsar.
