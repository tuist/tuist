---
{
  "title": "Oluşturulan Xcode projesi",
  "titleTemplate": ":title · Anlık Görüntüler · Özellikler · Kılavuzlar · Tuist",
  "description": "Tuist tarafından oluşturulan bir projedeki her SwiftUI önizlemesinin anlık görüntüsünü alın ve değişiklikleri Tuist'te inceleyin."
}
---
# Oluşturulan Xcode proje anlık görüntüleri {#generated-xcode-project-snapshots}

> [!IMPORTANT]
> **Gereksinimler**
>
> - Hesabınız için anlık görüntüler etkinleştirildi. Şu anda yalnızca davetiyeyle erişilebilir: Erişim talep etmek için [bize ulaşın](mailto:contact@tuist.dev) veya [topluluk Slack](https://slack.tuist.dev) kanalında bize mesaj atın.
> - Tuist’e <.localized_link href="/guides/get-started/generated-xcode-project">bağlı bir proje</.localized_link>.
> - Önizlemeleri oluşturmak için iOS 17 veya macOS 14.

[tuist/snapshots](https://github.com/tuist/snapshots) kitaplığı, uygulamanızdaki her SwiftUI önizlemesini bir görsele dönüştürür; böylece anlık görüntü testlerini elle yazmanıza gerek kalmaz. `tuist test` çalıştırmadan sonra görselleri yükler ve Tuist bunları <.localized_link href="/guides/features/snapshots#how-it-works">temel çizgi</.localized_link> ile karşılaştırır.

## Kurulum {#set-up}

Paketi `Tuist/Package.swift` dosyasına ekleyin:

```swift
let package = Package(
    name: "App",
    dependencies: [
        .package(url: "https://github.com/tuist/snapshots", .upToNextMinor(from: "0.1.0")),
    ]
)
```

Ardından uygulamanıza ve `TuistSnapshotsTesting` bağımlılığı olan bir birim testi hedefi ile bunu çalıştıran bir şema ekleyin. Şema, anlık görüntü kümesine ad verir:

```swift
import ProjectDescription

let project = Project(
    name: "App",
    targets: [
        // Your app target, named "App".
        .target(
            name: "AppSnapshotTests",
            destinations: .iOS,
            product: .unitTests,
            bundleId: "dev.tuist.app-snapshot-tests",
            deploymentTargets: .iOS("17.0"),
            sources: ["Tests/AppSnapshotTests/**"],
            dependencies: [
                .target(name: "App"),
                .external(name: "TuistSnapshotsTesting"),
            ]
        ),
    ],
    schemes: [
        .scheme(
            name: "AppSnapshots",
            buildAction: .buildAction(targets: [.target("App")]),
            testAction: .targets([.testableTarget(target: "AppSnapshotTests")])
        ),
    ]
)
```

Hedefe bir test sınıfı ekleyin. Her önizleme kendi testine dönüşür:

```swift
import TuistSnapshotsTesting

final class PreviewSnapshotTests: PreviewSnapshotTestCase {}
```

Paketi almak için `tuist install` komutunu çalıştırın.

## Çalıştırma {#run}

Şemayı `tuist test` ile çalıştırın; her zaman aynı simülatörde çalıştırın çünkü farklı cihazlar farklı boyutlarda görseller oluşturur:

```bash
tuist test AppSnapshots --device "iPhone 17"
```

CI ortamında, testlerin oluşturduğu görseller çalıştırmadan sonra yüklenir ve görseller değiştiğinde ancak kimse değişiklikleri onaylamadığında komut başarısız olur. Yerel çalıştırmalar hiçbir şey yüklemez çünkü işlenmemiş değişiklikleri yüklerlerdi.

> [!TIP]
> <.localized_link href="/guides/features/selective-testing">Seçici test</.localized_link> ile, bir anlık görüntü test hedefi yalnızca görselleri geçtiğinde veya onaylandığında atlanır; bu sayede değişiklikleri kimsenin incelemediği bir hedef yeniden çalıştırmada atlanamaz. Bir çalıştırma hedefleri atladığında, oluşturmadığı görseller kaldırılmış değil, atlanmış olarak sayılır.

<!-- @snippet: ./_previews-library -->
