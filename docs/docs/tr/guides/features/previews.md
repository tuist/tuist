---
{
  "title": "Previews",
  "titleTemplate": ":title · Features · Guides · Tuist",
  "description": "Learn how to generate and share previews of your apps with anyone."
}
---
# Önizlemeler {#previews}

::: warning REQUIREMENTS
<!-- -->
- A <LocalizedLink href="/guides/server/accounts-and-projects">Tuist hesabı ve
  projesi</LocalizedLink>
<!-- -->
:::

Bir uygulama oluştururken, geri bildirim almak için onu başkalarıyla paylaşmak
isteyebilirsiniz. Geleneksel olarak, ekipler bunu uygulamalarını oluşturup
imzalayarak ve Apple'ın [TestFlight](https://developer.apple.com/testflight/)
gibi platformlara yükleyerek yaparlar. Ancak, özellikle bir iş arkadaşınızdan
veya arkadaşınızdan hızlı geri bildirim almak istediğinizde, bu süreç zahmetli
ve yavaş olabilir.

Bu süreci daha verimli hale getirmek için Tuist, uygulamalarınızın
önizlemelerini oluşturup herkesle paylaşma imkanı sunar.

::: warning DEVICE BUILDS NEED TO BE SIGNED
<!-- -->
Cihaz için derleme yaparken, uygulamanın doğru şekilde imzalandığından emin
olmak şu anda sizin sorumluluğunuzdadır. Gelecekte bu süreci kolaylaştırmayı
planlıyoruz.
<!-- -->
:::

::: code-group
```bash [Tuist Project]
tuist generate App
xcodebuild build -scheme App -workspace App.xcworkspace -configuration Debug -sdk iphonesimulator # Build the app for the simulator
xcodebuild build -scheme App -workspace App.xcworkspace -configuration Debug -destination 'generic/platform=iOS' # Build the app for the device
tuist share App
```
```bash [Xcode Project]
xcodebuild -scheme App -project App.xcodeproj -configuration Debug # Build the app for the simulator
xcodebuild -scheme App -project App.xcodeproj -configuration Debug -destination 'generic/platform=iOS' # Build the app for the device
tuist share App --configuration Debug --platforms iOS
tuist share App.ipa # Share an existing .ipa file
```
<!-- -->
:::

Komut, uygulamayı çalıştırmak için simülatörde veya gerçek bir cihazda herkesle
paylaşabileceğiniz bir bağlantı oluşturacaktır. Tek yapmaları gereken aşağıdaki
komutu çalıştırmaktır:

```bash
tuist run {url}
tuist run --device "My iPhone" {url} # Run the app on a specific device
```

`.ipa` dosyasını paylaşırken, Önizleme bağlantısını kullanarak uygulamayı
doğrudan mobil cihazdan indirebilirsiniz. `.ipa` önizlemelerine giden
bağlantılar varsayılan olarak _private_ şeklindedir, yani alıcı uygulamayı
indirmek için Tuist hesabıyla kimlik doğrulaması yapmalıdır. Uygulamayı herkesle
paylaşmak istiyorsanız, bunu proje ayarlarından genel olarak
değiştirebilirsiniz.

`tuist run` ayrıca `latest` gibi bir belirteç, dal adı veya belirli bir commit
hash'i temel alarak en son önizlemeyi çalıştırmanıza da olanak tanır:

```bash
tuist run App@latest # Runs latest App preview associated with the project's default branch
tuist run App@my-feature-branch # Runs latest App preview associated with a given branch
tuist run App@00dde7f56b1b8795a26b8085a781fb3715e834be # Runs latest App preview associated with a given git commit sha
```

::: warning UNIQUE BUILD NUMBERS IN CI
<!-- -->
`CFBundleVersion` (derleme sürümü) değerinin, çoğu CI sağlayıcısının sunduğu CI
çalıştırma numarasını kullanarak benzersiz olduğundan emin olun. Örneğin, GitHub
Actions'da `CFBundleVersion` değerini <code v-pre>${{ github.run_number
}}</code> değişkenine ayarlayabilirsiniz.

Aynı ikili dosya (derleme) ve aynı `CFBundleVersion` ile önizleme yüklemek
başarısız olacaktır.
<!-- -->
:::

## Parçalar {#tracks}

Parçalar, önizlemelerinizi adlandırılmış gruplar halinde düzenlemenizi sağlar.
Örneğin, iç test kullanıcıları için `beta` parçası ve otomatik derlemeler için
`nightly` parçası olabilir. Parçalar otomatik olarak oluşturulur — paylaşırken
bir parça adı belirtmeniz yeterlidir, mevcut değilse otomatik olarak
oluşturulur.

Belirli bir parçanın önizlemesini paylaşmak için `--track` seçeneğini kullanın:

```bash
tuist share App --track beta
tuist share App --track nightly
```

Bu, aşağıdakiler için yararlıdır:
- **Önizlemeleri düzenleme**: Önizlemeleri amaca göre gruplandırın (ör. `beta`,
  `nightly`, `internal`)
- **Uygulama içi güncellemeler**: Tuist SDK, kullanıcılara hangi güncellemelerin
  bildirileceğini belirlemek için izleri kullanır.
- ****'ı filtreleme: Tuist panosunda parçalara göre önizlemeleri kolayca bulun
  ve yönetin

::: warning PREVIEWS' VISIBILITY
<!-- -->
Yalnızca projenin ait olduğu kuruluşa erişimi olan kişiler önizlemelere
erişebilir. Süresi dolan bağlantılar için destek eklemeyi planlıyoruz.
<!-- -->
:::

## Tuist macOS uygulaması {#tuist-macos-app}

<div style="display: flex; flex-direction: column; align-items: center;">
    <img src="/logo.png" style="height: 100px;" />
    <h1>Tuist</h1>
    <a href="https://tuist.dev/download" style="text-decoration: none;">Download</a>
    <img src="/images/guides/features/menu-bar-app.png" style="width: 300px;" />
</div>

Tuist Önizlemelerini daha da kolay hale getirmek için, Tuist macOS menü çubuğu
uygulamasını geliştirdik. Tuist CLI üzerinden Önizlemeleri çalıştırmak yerine,
macOS uygulamasını [indirebilirsiniz](https://tuist.dev/download). Uygulamayı
`brew install --cask tuist/tuist/tuist` komutunu çalıştırarak da
yükleyebilirsiniz.

Önizleme sayfasında "Çalıştır" düğmesine tıkladığınızda, macOS uygulaması seçili
cihazınızda otomatik olarak başlatılır.

::: warning REQUIREMENTS
<!-- -->
Xcode'un yerel olarak yüklü olması ve macOS 14 veya üstü bir sürümde çalışıyor
olmanız gerekir.
<!-- -->
:::

## Tuist iOS uygulaması {#tuist-ios-app}

<div style="display: flex; flex-direction: column; align-items: center;">
    <img src="/images/guides/features/ios-icon.png" style="height: 100px;" />
    <h1 style="padding-top: 2px;">Tuist</h1>
    <img src="/images/guides/features/tuist-app.png" style="width: 300px; padding-top: 8px;" />
    <a href="https://apps.apple.com/us/app/tuist/id6748460335" target="_blank" style="padding-top: 10px;">
        <img src="https://developer.apple.com/assets/elements/badges/download-on-the-app-store.svg" alt="Download on the App Store" style="height: 40px;">
    </a>
</div>

macOS uygulamasına benzer şekilde, Tuist iOS uygulamaları önizlemelerinize
erişmeyi ve bunları çalıştırmayı kolaylaştırır.

## Çekme/birleştirme isteği yorumları {#pullmerge-request-comments}

::: warning INTEGRATION WITH GIT PLATFORM REQUIRED
<!-- -->
Otomatik çekme/birleştirme isteği yorumları almak için
<LocalizedLink href="/guides/server/accounts-and-projects">uzak
projenizi</LocalizedLink> bir
<LocalizedLink href="/guides/server/authentication">Git
platformuyla</LocalizedLink> entegre edin.
<!-- -->
:::

Yeni işlevlerin test edilmesi, her kod incelemesinin bir parçası olmalıdır.
Ancak uygulamayı yerel olarak derlemek zorunda kalmak, gereksiz bir zorluk
yaratır ve genellikle geliştiricilerin cihazlarında test işlevlerini tamamen
atlamasına neden olur. Peki, her pull isteği, Tuist macOS uygulamasında
seçtiğiniz bir cihazda uygulamayı otomatik olarak çalıştıracak derleme
bağlantısı içerse ne olurl *?*

Tuist projeniz [GitHub](https://github.com) gibi Git platformunuzla bağlandıktan
sonra, CI iş akışınıza <LocalizedLink href="/cli/share">`tuist share
MyApp`</LocalizedLink> ekleyin. Tuist, pull isteklerinize doğrudan bir Önizleme
bağlantısı ekleyecektir: ![GitHub uygulaması yorumu ve Tuist Önizleme
bağlantısı](/images/guides/features/github-app-with-preview.png)


## Uygulama içi güncelleme bildirimleri {#in-app-update-notifications}

[Tuist SDK](https://github.com/tuist/sdk), uygulamanızın daha yeni bir önizleme
sürümünün mevcut olduğunu algılamasını ve kullanıcıları bilgilendirmesini
sağlar. Bu, test kullanıcılarının en son sürümü kullanmasını sağlamak için
yararlıdır.

SDK, aynı **önizleme izinde** güncellemeleri kontrol eder. `--track` kullanarak
açık bir izle önizlemeyi paylaştığınızda, SDK o izde güncellemeleri arar. Hiçbir
iz belirtilmezse, git dalı iz olarak kullanılır; bu nedenle, `ana` dalından
oluşturulan bir önizleme, yalnızca `ana` dalından da oluşturulan daha yeni
önizlemeler hakkında bildirimde bulunur.

### Kurulum {#sdk-installation}

Tuist SDK'yı Swift paketi bağımlılığı olarak ekleyin:

```swift
.package(url: "https://github.com/tuist/sdk", .upToNextMajor(from: "0.1.0"))
```

### Güncellemeleri izleyin {#sdk-monitor-updates}

`monitorPreviewUpdates` adresini kullanarak yeni önizleme sürümlerini düzenli
olarak kontrol edin:

```swift
import TuistSDK

struct MyApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .task {
                    TuistSDK(
                        fullHandle: "myorg/myapp",
                        apiKey: "your-api-key"
                    )
                    .monitorPreviewUpdates()
                }
        }
    }
}
```

### Tekli güncelleme kontrolü {#sdk-single-check}

Manuel güncelleme kontrolü için:

```swift
let sdk = TuistSDK(
    fullHandle: "myorg/myapp",
    apiKey: "your-api-key"
)

if let preview = try await sdk.checkForUpdate() {
    print("New version available: \(preview.version ?? "unknown")")
}
```

### Güncelleme izlemeyi durdurma {#sdk-stop-monitoring}

`monitorPreviewUpdates` iptal edilebilen bir `Görev` döndürür:

```swift
let task = sdk.monitorPreviewUpdates { preview in
    // Handle update
}

// Later, to stop monitoring:
task.cancel()
```

::: info
<!-- -->
Güncelleme kontrolü, simülatörlerde ve App Store sürümlerinde otomatik olarak
devre dışı bırakılır.
<!-- -->
:::

## README rozeti {#readme-badge}

Tuist Önizlemelerini deponuzda daha görünür hale getirmek için, `README`
dosyasına en son Tuist Önizlemesine yönlendiren bir rozet ekleyebilirsiniz:

[![Tuist
Önizleme](https://tuist.dev/Dimillian/IcySky/previews/latest/badge.svg)](https://tuist.dev/Dimillian/IcySky/previews/latest)

`'nizin README` dosyasına rozeti eklemek için aşağıdaki markdown'u kullanın ve
hesap ve proje adlarını kendi adlarınızla değiştirin:
```
[![Tuist Preview](https://tuist.dev/{account-handle}/{project-handle}/previews/latest/badge.svg)](https://tuist.dev/{account-handle}/{project-handle}/previews/latest)
```

Projeniz farklı paket tanımlayıcılarına sahip birden fazla uygulama içeriyorsa,
`bundle-id` sorgu parametresini ekleyerek hangi uygulamanın önizlemesine
bağlanılacağını belirtebilirsiniz:
```
[![Tuist Preview](https://tuist.dev/{account-handle}/{project-handle}/previews/latest/badge.svg)](https://tuist.dev/{account-handle}/{project-handle}/previews/latest?bundle-id=com.example.app)
```

## Otomasyonlar {#automations}

`--json` bayrağını kullanarak `tuist share` komutundan JSON çıktısı
alabilirsiniz:
```
tuist share --json
```

JSON çıktısı, CI sağlayıcınızı kullanarak Slack mesajı göndermek gibi özel
otomasyonlar oluşturmak için kullanışlıdır. JSON, gerçek bir cihazdan
önizlemeleri daha kolay indirmek için tam önizleme bağlantısını içeren `url`
anahtarı ve QR kodu görüntüsünün URL'sini içeren `qrCodeURL` anahtarı içerir.
JSON çıktısının bir örneği aşağıdadır:
```json
{
  "id": 1234567890,
  "url": "https://cloud.tuist.io/preview/1234567890",
  "qrCodeURL": "https://cloud.tuist.io/preview/1234567890/qr-code.svg"
}
```
