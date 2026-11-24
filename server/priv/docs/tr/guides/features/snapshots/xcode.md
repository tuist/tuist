---
{
  "title": "Xcode",
  "titleTemplate": ":title · Anlık Görüntüler · Özellikler · Kılavuzlar · Tuist",
  "description": "Bir Xcode projesinin her SwiftUI önizlemesinin anlık görüntüsünü alın ve değişiklikleri Tuist'te inceleyin."
}
---
# Xcode anlık görüntüleri {#xcode-snapshots}

> [!IMPORTANT]
> **Gereksinimler**
>
> - Hesabınız için anlık görüntüler etkinleştirildi. Şu anda yalnızca davetle erişilebilir: Erişim talep etmek için [bize ulaşın](mailto:contact@tuist.dev) veya [topluluk Slack kanalında](https://slack.tuist.dev) bize mesaj atın.
> - Bir proje <.localized_link href="/guides/get-started/existing-xcode-project">Tuist’e bağlı</.localized_link>.
> - Önizlemeleri oluşturmak için iOS 17 veya macOS 14 gerekir.

[tuist/snapshots](https://github.com/tuist/snapshots) kitaplığı, uygulamanızdaki her SwiftUI önizlemesini bir görüntüye dönüştürür; böylece anlık görüntü testlerini elle yazmanıza gerek kalmaz. `tuist xcodebuild test` çalıştırma sonrasında görüntüleri yükler ve Tuist bunları <.localized_link href="/guides/features/snapshots#how-it-works">temel sürümle</.localized_link> karşılaştırır.

## Kurulum {#set-up}

1. Xcode’da, `0.1.0` sürümünden başlayarak `https://github.com/tuist/snapshots` paketini ekleyin.
2. Uygulamanız tarafından barındırılan bir birim testi hedefi oluşturun, örneğin `AppSnapshotTests`, ve paketin `TuistSnapshotsTesting` ürününü bu hedefe bağlayın.
3. Bu hedefe bir test sınıfı ekleyin. Her önizleme kendi testine dönüşür:

```swift
import TuistSnapshotsTesting

final class PreviewSnapshotTests: PreviewSnapshotTestCase {}
```

4. Hedefi çalıştıran bir şema ekleyin, örneğin `AppSnapshots`. Şema, anlık görüntü kümesine ad verir.

## Çalıştırma {#run}

Testleri `tuist xcodebuild test` aracılığıyla çalıştırın ve her zaman aynı simülatörde yürütün; çünkü farklı bir cihaz farklı boyutlarda görüntüler oluşturur:

```bash
tuist xcodebuild test -scheme AppSnapshots -destination 'platform=iOS Simulator,name=iPhone 17'
```

CI ortamında, testlerin oluşturduğu görüntüler çalıştırma sonrasında yüklenir ve görüntüler değiştiğinde, değişiklikleri kimse onaylamadıysa komut başarısız olur. Yerel çalıştırmalar hiçbir şey yüklemez, çünkü işlenmemiş değişiklikleri yüklemiş olurlardı.

<!-- @snippet: ./_previews-library -->
