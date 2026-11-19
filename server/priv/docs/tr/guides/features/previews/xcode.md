---
{
  "title": "Xcode önizlemeleri",
  "titleTemplate": ":title · Önizlemeler · Tuist",
  "description": "Mevcut Xcode projelerinden ve Tuist tarafından oluşturulan projelerden uygulama önizlemelerini paylaşın."
}
---
# Xcode önizlemeleri

Uygulamanızı derleyin ve `tuist share` kullanarak Tuist projenize yayınlayın. Projenizi öncelikle <.localized_link href="/guides/get-started/existing-xcode-project">mevcut Xcode projesi</.localized_link> veya <.localized_link href="/guides/get-started/generated-xcode-project">oluşturulmuş proje</.localized_link> kılavuzunu kullanarak bağlayın.

## Derleme ve paylaşım

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

Şema, proje ve çalışma alanı adlarını kendi adlarınızla değiştirin. Bir Release derlemesini paylaşmak için derleme sırasında `-configuration Release`, paylaşım sırasında ise `--configuration Release` kullanın.

## Fiziksel cihazlar

Cihaz derlemelerini, alıcının cihazına kurulmasına olanak tanıyan bir sağlama profiliyle imzalamaktan siz sorumlusunuz. Simülatör SDK’sı yerine bir cihaz hedefiyle derleme yapın:

```bash
tuist xcodebuild build -scheme App -project App.xcodeproj \
  -configuration Debug -destination 'generic/platform=iOS'
tuist share App --configuration Debug --platforms iOS
```

Zaten dışa aktarılmış bir IPA dosyasını da paylaşabilirsiniz:

```bash
tuist share App.ipa
```

Alıcılar, uygulamayı yüklemek için mobil cihazlarında bir IPA önizleme bağlantısını açabilir. Kimlik doğrulama ve projenin önizleme görünürlüğü kuralları hâlâ geçerlidir.

## CI ve derleme numaraları

Mevcut <.localized_link href="/guides/integrations/continuous-integration">CI kimlik doğrulaması</.localized_link>nızı kullanın ve her yeni derleme için `CFBundleVersion` değerini benzersiz yapın. Örneğin, GitHub Actions’ın <code v-pre>${{ github.run_number }}</code> değişkenini kullanın. Aynı ikili dosya ve derleme numarasını `tuist share` aracılığıyla tekrar yüklemek, yinelenen bir kopya oluşturmak yerine başarısız olur.

```bash
tuist share App --track beta --release-notes "Fix sign-in"
```

Yayınlanan derlemeleri çalıştırmak, erişim, kanallar ve README rozetleri için <.localized_link href="/guides/features/previews#run-a-preview">Önizleme çalıştırma</.localized_link> kılavuzuna bakın.

<!-- @snippet: ./_tuist-share -->

Alıcılar, derleme sistemi entegrasyonundan bağımsız olarak <.localized_link href="/guides/features/previews/run/macos">Tuist macOS uygulamasını</.localized_link> veya <.localized_link href="/guides/features/previews/run/ios">iPhone uygulamasını</.localized_link> kullanabilir. iPhone kılavuzu ayrıca Tuist SDK ile <.localized_link href="/guides/features/previews/run/ios#in-app-update-notifications">uygulama içi güncelleme bildirimlerini</.localized_link> de kapsar.
