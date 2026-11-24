---
{
  "title": "Dinamik yapılandırma",
  "titleTemplate": ":title · Projeler · Özellikler · Kılavuzlar · Tuist",
  "description": "Projenizi dinamik olarak yapılandırmak için ortam değişkenlerini nasıl kullanacağınızı öğrenin."
}
---
# Dinamik yapılandırma {#dynamic-configuration}

Projenizi oluşturma sırasında dinamik olarak yapılandırmanız gereken durumlar olabilir. Örneğin, uygulamanın adını, paket tanımlayıcısını veya dağıtım hedefini projenin oluşturulduğu ortama göre değiştirmek isteyebilirsiniz. Tuist bunu, bildirim dosyalarından erişilebilen ortam değişkenleri aracılığıyla destekler.

## Ortam değişkenleri aracılığıyla yapılandırma {#configuration-through-environment-variables}

Tuist, bildirim dosyalarından erişilebilen ortam değişkenleri üzerinden yapılandırma aktarmanıza olanak tanır. Örneğin:

```bash
TUIST_APP_NAME=MyApp tuist generate
```

Birden fazla ortam değişkeni aktarmak istiyorsanız bunları boşlukla ayırmanız yeterlidir. Örneğin:

```bash
TUIST_APP_NAME=MyApp TUIST_APP_LOCALE=pl tuist generate
```

## Bildirimlerden ortam değişkenlerini okuma {#reading-the-environment-variables-from-manifests}

Değişkenlere [`Environment`](https://projectdescription.tuist.dev/documentation/projectdescription/environment) türü kullanılarak erişilebilir. Ortamda tanımlanan veya komutlar çalıştırılırken Tuist’e iletilen ve `TUIST_XXX` kuralına uyan tüm değişkenlere `Environment` türü aracılığıyla erişilebilir. Erişimciler, `TUIST_` ön eki olmadan camelCase biçimindeki değişken adını kullanır; bu nedenle `TUIST_APP_NAME` değeri `Environment.appName` olarak, `TUIST_ENABLE_ANALYTICS` değeri ise `Environment.enableAnalytics` olarak okunur. Bildirimin CI üzerinde değerlendirilip değerlendirilmediğini kontrol etmek için `Environment.isCI` Boole değerini kullanın. Aşağıdaki örnek `TUIST_APP_NAME` değerini okur:

```swift
func appName() -> String {
    if case let .string(environmentAppName) = Environment.appName {
        return environmentAppName
    } else {
        return "MyApp"
    }
}
```

Değişkenlere erişim, aşağıdaki değerlerden herhangi birini alabilen `Environment.Value?` türünde bir örnek döndürür:

| Durum | Açıklama |
| --- | --- |
| `.string(String)` | Değişken bir dizeyi temsil ettiğinde kullanılır. |

Ayrıca, aşağıda tanımlanan yardımcı yöntemlerden birini kullanarak dize veya boolean `Environment` değişkenini alabilirsiniz; bu yöntemler, kullanıcının her seferinde tutarlı sonuçlar elde etmesini sağlamak için bir varsayılan değer geçirilmesini gerektirir. Bu, yukarıda tanımlanan appName() işlevini tanımlama ihtiyacını ortadan kaldırır.

::: code-group

```swift [String]
Environment.appName.getString(default: "MyApp")
```

```swift [Boolean]
Environment.enableAnalytics.getBoolean(default: false)
```
<!-- -->
:::

## Ek ortam değişkenlerini bildirimlere iletme {#forwarding-additional-environment-variables-to-manifests}

Varsayılan olarak, yalnızca `TUIST_` ön ekine sahip değişkenler ile `CI` ve `DEVELOPER_DIR` değişkenleri, `Project.swift`, `Workspace.swift`, `Package.swift` ve proje açıklama yardımcılarını değerlendiren alt sürece iletilir. Bu, oluşturma işlemini deterministik tutar ve ilgisiz kabuk veya CI değişkenlerinin bildirim önbelleğini geçersiz kılmasını engeller.

Bir bildirimin kontrolünüz dışında olan değişkenleri okuması gerektiğinde (örneğin, zaten `OPENSWIFTUI_LIBRARY_TYPE` değerini okuyan üçüncü taraf bir `Package.swift`), bunları oluşturma seçeneklerinde `manifestEnvironment` aracılığıyla `Tuist.swift` içinde bildirin. Her giriş ya tam bir ad ya da ön eşleştirme için `*` ile biten bir addır:

```swift
import ProjectDescription

let tuist = Tuist(
    project: .tuist(
        generationOptions: .options(
            manifestEnvironment: [
                "OPENSWIFTUI_*",
                "MY_VAR",
            ]
        )
    )
)
```

Listelenen değişkenler bildirim önbellek karmasına dahil edilir, bu nedenle değerlerindeki değişiklikler beklendiği gibi önbelleği geçersiz kılar. Listelenmeyen değişkenler bildirim değerlendirmesinden gizli kalır.
