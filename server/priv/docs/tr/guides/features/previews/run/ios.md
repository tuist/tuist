---
{
  "title": "Önizlemeleri iPhone uygulamasıyla çalıştırın",
  "titleTemplate": ":title · Önizlemeler · Tuist",
  "description": "Tuist iOS uygulamasıyla Apple önizlemelerini bulun, filtreleyin ve erişin."
}
---
# Önizlemeleri iPhone uygulamasıyla çalıştırın

Apple önizlemelerinizi bulmak ve erişmek için [App Store’dan Tuist iOS uygulamasını](https://apps.apple.com/us/app/tuist/id6748460335) yükleyin. Yayınlama iş akışının imzalama ve cihaz uygunluğu gereksinimleri hala geçerlidir.

<div style="display: flex; flex-direction: column; align-items: center;">
    <img src="/images/guides/features/ios-icon.png" style="height: 100px;" />
    <img src="/images/guides/features/tuist-app.png" style="width: 220px; padding-top: 8px;" />
    <a href="https://apps.apple.com/us/app/tuist/id6748460335" target="_blank" style="padding-top: 10px;">
        <img src="https://developer.apple.com/assets/elements/badges/download-on-the-app-store.svg" alt="App Store’dan İndir" style="height: 40px;">
    </a>
</div>

Uygulama adına veya sürüm notlarına göre arama yapın, ardından önizlemeleri filtrelemek için bir kanal seçin. Kanalı olmayan önizlemeler dahil her kanala göz atmak için **Tümü** seçeneğini belirleyin. Tam sürüm notlarını okumak için bir önizlemeyi açın.

## İstemci ve sunucu uyumluluğu {#client-and-server-compatibility}

Tuist uygulamasını güncel tutun. Tuist’i kendi sunucunuzda barındırıyorsanız, kanal filtreleme ve sürüm notlarını kullanmak için sunucunuzu güncelleyin. Eski sunucularda filtreleme olmadan hâlâ önizlemelere göz atabilirsiniz.

## Uygulama içi güncelleme bildirimleri {#in-app-update-notifications}

[Tuist SDK](https://github.com/tuist/sdk), Apple uygulamanızın daha yeni bir önizlemeyi algılamasını ve test edenlere bildirim göndermesini sağlar. Güncellemeleri aynı **önizleme kanalı** içinde kontrol eder. `tuist share --track` ile yayımlanan önizlemeler için bu açık kanalı kullanır. Açık bir kanal belirtilmemişse git dalı kullanılır; bu nedenle `main` dalından oluşturulan bir önizleme yalnızca `main` dalındaki daha yeni önizlemeler hakkında bildirim gönderir.

### Kurulum {#sdk-installation}

Tuist SDK’yı Swift Package bağımlılığı olarak ekleyin:

```swift
.package(url: "https://github.com/tuist/sdk", .upToNextMajor(from: "0.1.0"))
```

### Güncellemeleri izleme {#sdk-monitor-updates}

Yeni önizleme sürümlerini periyodik olarak kontrol etmek için `monitorPreviewUpdates` kullanın:

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

### Tek seferlik güncelleme kontrolü {#sdk-single-check}

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

`monitorPreviewUpdates`, iptal edilebilen bir `Task` döndürür:

```swift
let task = sdk.monitorPreviewUpdates { preview in
    // Handle update
}

// Later, to stop monitoring:
task.cancel()
```

> [!NOTE]
> Güncelleme kontrolü, simülatörlerde ve App Store yapılarında otomatik olarak devre dışı bırakılır.
