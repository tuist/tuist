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
- A <LocalizedLink href="/guides/server/accounts-and-projects">Tuist hesabı ve projesi</LocalizedLink>
<!-- -->
:::

Bir uygulama geliştirirken, geri bildirim almak için başkalarıyla paylaşmak
isteyebilirsiniz. Geleneksel olarak bu, ekiplerin uygulamalarını oluşturarak,
imzalayarak ve Apple'ın [TestFlight](https://developer.apple.com/testflight/)
gibi platformlarına göndererek yaptıkları bir şeydir. Ancak bu süreç, özellikle
de sadece bir iş arkadaşınızdan veya bir arkadaşınızdan hızlı geri bildirim
almak istediğinizde zahmetli ve yavaş olabilir.

Bu süreci daha kolay hale getirmek için Tuist, uygulamalarınızın önizlemelerini
oluşturmanın ve herkesle paylaşmanın bir yolunu sunuyor.

::: warning DEVICE BUILDS NEED TO BE SIGNED
<!-- -->
Cihaz için oluştururken, uygulamanın doğru şekilde imzalandığından emin olmak şu
anda sizin sorumluluğunuzdadır. Gelecekte bunu kolaylaştırmayı planlıyoruz.
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

Komut, uygulamayı simülatörde veya gerçek bir cihazda çalıştırmak için herhangi
biriyle paylaşabileceğiniz bir bağlantı oluşturacaktır. Tek yapmaları gereken
aşağıdaki komutu çalıştırmak:

```bash
tuist run {url}
tuist run --device "My iPhone" {url} # Run the app on a specific device
```

Bir `.ipa` dosyasını paylaşırken, Önizleme bağlantısını kullanarak uygulamayı
doğrudan mobil cihazdan indirebilirsiniz. ` .ipa` önizleme bağlantıları
varsayılan olarak _herkese açık_. Gelecekte, bunları özel yapma seçeneğiniz
olacak, böylece bağlantının alıcısının uygulamayı indirmek için Tuist hesabıyla
kimlik doğrulaması yapması gerekecektir.

`tuist run` ayrıca `latest`, branch name veya belirli bir commit hash gibi bir
belirticiye dayalı olarak en son önizlemeyi çalıştırmanızı sağlar:

```bash
tuist run App@latest # Runs latest App preview associated with the project's default branch
tuist run App@my-feature-branch # Runs latest App preview associated with a given branch
tuist run App@00dde7f56b1b8795a26b8085a781fb3715e834be # Runs latest App preview associated with a given git commit sha
```

::: warning UNIQUE BUILD NUMBERS IN CI
<!-- -->
Çoğu CI sağlayıcısının ortaya çıkardığı bir CI çalışma numarasından yararlanarak
`CFBundleVersion` (derleme sürümü) öğesinin benzersiz olduğundan emin olun.
Örneğin, GitHub Actions'ta `CFBundleVersion` adresini <code v-pre>${{
github.run_number }}</code> değişkenine ayarlayabilirsiniz.

Aynı ikili dosyaya (derleme) ve aynı `CFBundleVersion` adresine sahip bir
önizleme yüklemek başarısız olacaktır.
<!-- -->
:::

## Parçalar {#tracks}

Parçalar, önizlemelerinizi adlandırılmış gruplar halinde düzenlemenizi sağlar.
Örneğin, dahili test kullanıcıları için bir `beta` izi ve otomatik derlemeler
için bir `nightly` iziniz olabilir. Parçalar tembel bir şekilde oluşturulur -
paylaşırken bir parça adı belirtmeniz yeterlidir; mevcut değilse otomatik olarak
oluşturulacaktır.

Belirli bir parçada önizleme paylaşmak için `--track` seçeneğini kullanın:

```bash
tuist share App --track beta
tuist share App --track nightly
```

Bu şunlar için yararlıdır:
- **Önizlemeleri düzenleme**: Önizlemeleri amaca göre gruplama (örneğin, `beta`,
  `gecelik`, `dahili`)
- **Uygulama içi güncellemeler**: Tuist SDK, kullanıcıları hangi güncellemeler
  hakkında bilgilendireceğini belirlemek için izleri kullanır
- **Filtreleme**: Tuist kontrol panelinde parçaya göre önizlemeleri kolayca
  bulun ve yönetin

::: warning PREVIEWS' VISIBILITY
<!-- -->
Önizlemelere yalnızca projenin ait olduğu kuruluşa erişimi olan kişiler
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

Tuist Önizlemelerini çalıştırmayı daha da kolaylaştırmak için bir Tuist macOS
menü çubuğu uygulaması geliştirdik. Tuist CLI aracılığıyla Önizlemeleri
çalıştırmak yerine, macOS uygulamasını
[indirebilirsiniz](https://tuist.dev/download). Uygulamayı `brew install --cask
tuist/tuist/tuist` çalıştırarak da yükleyebilirsiniz.

Şimdi Önizleme sayfasında "Çalıştır "a tıkladığınızda, macOS uygulaması otomatik
olarak o anda seçili cihazınızda başlatılacaktır.

::: warning REQUIREMENTS
<!-- -->
Xcode'un yerel olarak yüklü olması ve macOS 14 veya sonraki bir sürümü
kullanıyor olmanız gerekir.
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

MacOS uygulamasına benzer şekilde, Tuist iOS uygulamaları da önizlemelerinize
erişmeyi ve çalıştırmayı kolaylaştırıyor.

## Çekme/birleştirme isteği yorumları {#pullmerge-request-comments}

::: warning INTEGRATION WITH GIT PLATFORM REQUIRED
<!-- -->
Otomatik çekme/birleştirme isteği yorumları almak için
<LocalizedLink href="/guides/server/accounts-and-projects">uzak projenizi</LocalizedLink> bir
<LocalizedLink href="/guides/server/authentication">Git platformu</LocalizedLink> ile entegre edin.
<!-- -->
:::

Yeni işlevlerin test edilmesi, her kod incelemesinin bir parçası olmalıdır.
Ancak bir uygulamayı yerel olarak derlemek zorunda kalmak gereksiz sürtüşmeler
yaratır ve genellikle geliştiricilerin cihazlarındaki işlevselliği test etmeyi
atlamasına neden olur. Ancak *her çekme isteği, uygulamayı Tuist macOS
uygulamasında seçtiğiniz bir cihazda otomatik olarak çalıştıracak yapıya bir
bağlantı içeriyor olsaydı ne olurdu?*

Tuist projeniz [GitHub](https://github.com) gibi Git platformunuza bağlandıktan
sonra, CI iş akışınıza bir <LocalizedLink href="/cli/share">`tuist share MyApp`</LocalizedLink> ekleyin. Tuist daha sonra doğrudan çekme isteklerinizde
bir Önizleme bağlantısı yayınlayacaktır: ![Tuist Önizleme bağlantısı içeren
GitHub uygulama yorumu](/images/guides/features/github-app-with-preview.png)


## Uygulama içi güncelleme bildirimleri {#in-app-update-notifications}

Tuist SDK](https://github.com/tuist/sdk), uygulamanızın daha yeni bir önizleme
sürümünün mevcut olduğunu algılamasını ve kullanıcıları bilgilendirmesini
sağlar. Bu, test kullanıcılarını en son sürümde tutmak için kullanışlıdır.

SDK, aynı **önizleme izi** içindeki güncellemeleri kontrol eder. Bir önizlemeyi
`--track` kullanarak açık bir parça ile paylaştığınızda, SDK bu parçadaki
güncellemeleri arayacaktır. Herhangi bir iz belirtilmezse, git dalı iz olarak
kullanılır - bu nedenle `ana` dalından oluşturulan bir önizleme yalnızca `ana`
dalından da oluşturulan daha yeni önizlemeler hakkında bildirimde bulunacaktır.

### Kurulum {#sdk-installation}

Tuist SDK'yı bir Swift paketi bağımlılığı olarak ekleyin:

```swift
.package(url: "https://github.com/tuist/sdk", .upToNextMajor(from: "0.1.0"))
```

### Güncellemeler için izleyin {#sdk-monitor-updates}

Yeni önizleme sürümlerini periyodik olarak kontrol etmek için
`monitorPreviewUpdates` adresini kullanın:

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

### Tek güncelleme kontrolü {#sdk-single-check}

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

`monitorPreviewUpdates` iptal edilebilen bir `Task` döndürür:

```swift
let task = sdk.monitorPreviewUpdates { preview in
    // Handle update
}

// Later, to stop monitoring:
task.cancel()
```

::: info
<!-- -->
Güncelleme denetimi simülatörlerde ve App Store yapılarında otomatik olarak
devre dışı bırakılır.
<!-- -->
:::

## README rozeti {#readme-badge}

Tuist Önizlemelerini deponuzda daha görünür kılmak için, `README` dosyanıza en
son Tuist Önizlemesine işaret eden bir rozet ekleyebilirsiniz:

[![Tuist
Önizleme](https://tuist.dev/Dimillian/IcySky/previews/latest/badge.svg)](https://tuist.dev/Dimillian/IcySky/previews/latest)

Rozeti `README` adresinize eklemek için aşağıdaki işaretlemeyi kullanın ve hesap
ve proje tanıtıcılarını kendi tanıtıcılarınızla değiştirin:
```
[![Tuist Preview](https://tuist.dev/{account-handle}/{project-handle}/previews/latest/badge.svg)](https://tuist.dev/{account-handle}/{project-handle}/previews/latest)
```

Projeniz farklı paket tanımlayıcılarına sahip birden fazla uygulama içeriyorsa,
`bundle-id` sorgu parametresini ekleyerek hangi uygulamanın önizlemesine
bağlantı verileceğini belirtebilirsiniz:
```
[![Tuist Preview](https://tuist.dev/{account-handle}/{project-handle}/previews/latest/badge.svg)](https://tuist.dev/{account-handle}/{project-handle}/previews/latest?bundle-id=com.example.app)
```

## Otomasyonlar {#automations}

`tuist share` komutundan bir JSON çıktısı almak için `--json` bayrağını
kullanabilirsiniz:
```
tuist share --json
```

JSON çıktısı, CI sağlayıcınızı kullanarak bir Slack mesajı göndermek gibi özel
otomasyonlar oluşturmak için kullanışlıdır. JSON, tam önizleme bağlantısını
içeren bir `url` anahtarı ve gerçek bir cihazdan önizlemeleri indirmeyi
kolaylaştırmak için QR kod görüntüsünün URL'sini içeren bir `qrCodeURL` anahtarı
içerir. JSON çıktısının bir örneği aşağıdadır:
```json
{
  "id": 1234567890,
  "url": "https://cloud.tuist.io/preview/1234567890",
  "qrCodeURL": "https://cloud.tuist.io/preview/1234567890/qr-code.svg"
}
```
