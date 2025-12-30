---
{
  "title": "Dynamic configuration",
  "titleTemplate": ":title · Projects · Features · Guides · Tuist",
  "description": "Learn how how to use environment variables to dynamically configure your project."
}
---
# Dinamik yapılandırma {#dynamic-configuration}

Projenizi oluşturma sırasında dinamik olarak yapılandırmanız gerekebilecek bazı
senaryolar vardır. Örneğin, projenin oluşturulduğu ortama bağlı olarak
uygulamanın adını, paket tanımlayıcısını veya dağıtım hedefini değiştirmek
isteyebilirsiniz. Tuist, manifesto dosyalarından erişilebilen ortam değişkenleri
aracılığıyla bunu destekler.

## Ortam değişkenleri aracılığıyla yapılandırma {#configuration-through-environment-variables}

Tuist, manifesto dosyalarından erişilebilen ortam değişkenleri aracılığıyla
yapılandırmanın aktarılmasına izin verir. Örneğin:

```bash
TUIST_APP_NAME=MyApp tuist generate
```

Birden fazla ortam değişkeni aktarmak istiyorsanız, bunları bir boşlukla
ayırmanız yeterlidir. Örneğin:

```bash
TUIST_APP_NAME=MyApp TUIST_APP_LOCALE=pl tuist generate
```

## Ortam değişkenlerini manifestolardan okuma {#reading-the-environment-variables-from-manifests}

Değişkenlere
<LocalizedLink href="/references/project-description/enums/environment">`Ortam`</LocalizedLink>
tipi kullanılarak erişilebilir. Ortamda tanımlanan veya komutları çalıştırırken
Tuist'e aktarılan `TUIST_XXX` kuralını izleyen tüm değişkenlere `Ortam` türü
kullanılarak erişilebilir. Aşağıdaki örnek `TUIST_APP_NAME` değişkenine nasıl
eriştiğimizi göstermektedir:

```swift
func appName() -> String {
    if case let .string(environmentAppName) = Environment.appName {
        return environmentAppName
    } else {
        return "MyApp"
    }
}
```

Değişkenlere erişim, aşağıdaki değerlerden herhangi birini alabilen
`Environment.Value?` türünde bir örnek döndürür:

| Dava              | Açıklama                                         |
| ----------------- | ------------------------------------------------ |
| `.string(String)` | Değişken bir dizeyi temsil ettiğinde kullanılır. |

Ayrıca aşağıda tanımlanan yardımcı yöntemlerden birini kullanarak string veya
boolean `Environment` değişkenini de alabilirsiniz, bu yöntemler kullanıcının
her seferinde tutarlı sonuçlar almasını sağlamak için varsayılan bir değerin
geçirilmesini gerektirir. Bu, yukarıda tanımlanan appName() fonksiyonunu
tanımlama ihtiyacını ortadan kaldırır.

::: code-group

```swift [String]
Environment.appName.getString(default: "TuistServer")
```

```swift [Boolean]
Environment.isCI.getBoolean(default: false)
```
<!-- -->
:::
