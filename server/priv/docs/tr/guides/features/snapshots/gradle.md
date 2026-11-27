---
{
  "title": "Gradle",
  "titleTemplate": ":title · Anlık Görüntüler · Özellikler · Kılavuzlar · Tuist",
  "description": "Tuist Gradle eklentisiyle her Compose ön izlemesinin anlık görüntüsünü alın veya Paparazzi ve Roborazzi tarafından kaydedilenleri yükleyin."
}
---
# Gradle anlık görüntüleri {#gradle-snapshots}

> [!IMPORTANT]
> **Gereksinimler**
>
> - Hesabınız için anlık görüntüler etkinleştirildi. Şu anda yalnızca davetle erişilebilir: erişim istemek için [bize ulaşın](mailto:contact@tuist.dev) veya [topluluk Slack](https://slack.tuist.dev) kanalında bize yazın.
> - <.localized_link href="/guides/install-gradle-plugin">Tuist Gradle eklentisi</.localized_link>.
> - Anlık görüntü aldığınız modüllerde [Paparazzi](https://github.com/cashapp/paparazzi) veya [Roborazzi](https://github.com/takahirom/roborazzi).

Tuist Gradle eklentisi, Paparazzi ve Roborazzi'nin kaydettiği görselleri yükler ve Tuist bunları <.localized_link href="/guides/features/snapshots#how-it-works">temel çizgi</.localized_link> ile karşılaştırır. Paparazzi uygulayan modüllerde eklenti, her Compose `@Preview` önizlemesini işleyen bir test de oluşturur; böylece anlık görüntü testlerini elle yazmanıza gerek kalmaz.

## Kurulum {#set-up}

`settings.gradle.kts` dosyanızda anlık görüntüleri etkinleştirin:

```kotlin
tuist {
    snapshots {
        enabled = true
        set = "android-phone" // Defaults to the Gradle project's path.
    }
}
```

## Çalıştırma {#run}

CI ortamında `./gradlew test` önizlemeleri işler ve yükler; değişiklik olduğunda ve kimse onaylamadığında derleme başarısız olur. Yerel çalıştırmalar hiçbir şey yüklemez çünkü işlenmemiş değişiklikleri yüklemiş olurlardı. CI'da yüklemeleri kapatmak için `-Ptuist.snapshots=false` parametresini geçirin.

Paparazzi ve Roborazzi kayıt görevleri, örneğin `recordPaparazziDebug`, anlık görüntüler etkin olduğunda her zaman yükleme yapar.

## Seçenekler {#options}

`snapshots` bloğu şu seçenekleri alır:

- `enabled`: anlık görüntülerin yüklenip yüklenmeyeceği. Varsayılan değer `false`.
- `set`: derlemelerin karşılaştırıldığı küme. Varsayılan olarak Gradle projesinin yolu kullanılır.
- `directory`: yüklenecek görsellerin bulunduğu dizin, Gradle projesine göreli. Varsayılan olarak oluşturulan önizleme testinin veya anlık görüntü kitaplığının yazdığı konum kullanılır.
- `failOnChanges`: kimse tarafından onaylanmamış değişikliklerde derlemenin başarısız olup olmayacağı. Varsayılan değer `true`.
- `diffThreshold`: bir görselin değişmiş sayılması için farklılaşabilecek piksel oranı (0 ile 1 arasında). Varsayılan değer `0`.
- `previews { generateTests }`: Compose önizleme testinin oluşturulup oluşturulmayacağı. Varsayılan değer `true`.
- `previews { packageTrees }`: önizlemeler için taranan paketler. Varsayılan olarak Android ad alanı kullanılır.
- `previews { includePrivatePreviews }`: özel `@Preview` fonksiyonlarının da işlenip işlenmeyeceği. Varsayılan değer `false`.
- `previews { theme }`: Android teması önizlemelerinin işlendiği tema. Varsayılan olarak Paparazzi'nin teması kullanılır.
