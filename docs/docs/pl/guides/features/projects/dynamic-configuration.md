---
{
  "title": "Dynamic configuration",
  "titleTemplate": ":title · Projects · Features · Guides · Tuist",
  "description": "Learn how how to use environment variables to dynamically configure your project."
}
---
# Konfiguracja dynamiczna {#dynamic-configuration}

Istnieją pewne scenariusze, w których może być konieczne dynamiczne
skonfigurowanie projektu w trakcie generacji. Na przykład, możesz chcieć zmienić
nazwę aplikacji, identyfikator lub wspieraną urządzenia w zależności od
środowiska, dla którego projekt jest generowany. Tuist obsługuje to poprzez
zmienne środowiskowe, do których można uzyskać dostęp w plikach manifestu.

## Konfiguracja poprzez zmienne środowiskowe {#configuration-through-environment-variables}

Tuist umożliwia przekazywanie konfiguracji poprzez zmienne środowiskowe, do
których można uzyskać dostęp z plików manifestu. Na przykład:

```bash
TUIST_APP_NAME=MyApp tuist generate
```

Jeśli chcesz przekazać wiele zmiennych środowiskowych, po prostu oddziel je
spacją. Na przykład:

```bash
TUIST_APP_NAME=MyApp TUIST_APP_LOCALE=pl tuist generate
```

## Odczytywanie zmiennych środowiskowych z manifestów {#reading-the-environment-variables-from-manifests}

Dostęp do zmiennych można uzyskać za pomocą typu
<LocalizedLink href="/references/project-description/enums/environment">`Environment`</LocalizedLink>.
Wszelkie zmienne zgodne z konwencją `TUIST_XXX` zdefiniowane w środowisku lub
przekazane do Tuist podczas uruchamiania poleceń będą dostępne przy użyciu typu
`Environment`. Poniższy przykład pokazuje, jak uzyskać dostęp do zmiennej
`TUIST_APP_NAME`:

```swift
func appName() -> String {
    if case let .string(environmentAppName) = Environment.appName {
        return environmentAppName
    } else {
        return "MyApp"
    }
}
```

Dostęp do zmiennych zwraca instancję typu `Environment.Value?`, która może
przyjąć dowolną z następujących wartości:

| Przypadek         | Opis                                           |
| ----------------- | ---------------------------------------------- |
| `.string(String)` | Używany, gdy zmienna reprezentuje ciąg znaków. |

Możesz również pobrać zmienną `Environment` typu string lub boolean za pomocą
jednej z metod pomocniczych zdefiniowanych poniżej, metody te wymagają
przekazania wartości domyślnej, aby zapewnić użytkownikowi spójne wyniki za
każdym razem. Pozwala to uniknąć konieczności definiowania funkcji appName()
zdefiniowanej powyżej.

::: code-group

```swift [String]
Environment.appName.getString(default: "TuistServer")
```

```swift [Boolean]
Environment.isCI.getBoolean(default: false)
```
<!-- -->
:::
