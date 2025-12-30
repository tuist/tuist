---
{
  "title": "Synthesized files",
  "titleTemplate": ":title · Projects · Features · Guides · Tuist",
  "description": "Learn about synthesized files in Tuist projects."
}
---
# Syntetyzowane pliki {#synthesized-files}

Tuist może generować pliki i kod w czasie generowania, aby ułatwić zarządzanie
projektami Xcode i pracę z nimi. Na tej stronie dowiesz się więcej o tej
funkcjonalności i o tym, jak możesz ją wykorzystać w swoich projektach.

## Zasoby docelowe {#target-resources}

Projekty Xcode obsługują dodawanie zasobów do obiektów docelowych. Stawiają one
jednak przed zespołami kilka wyzwań, zwłaszcza podczas pracy z projektem
modułowym, w którym źródła i zasoby są często przenoszone:

- **Niespójny dostęp runtime**: To, gdzie zasoby trafiają do produktu końcowego
  i jak można uzyskać do nich dostęp, zależy od produktu docelowego. Na
  przykład, jeśli cel reprezentuje aplikację, zasoby są kopiowane do pakietu
  aplikacji. Prowadzi to do kodu uzyskującego dostęp do zasobów, który przyjmuje
  założenia dotyczące struktury pakietu, co nie jest idealne, ponieważ utrudnia
  rozumowanie kodu i przemieszczanie zasobów.
- **Produkty, które nie obsługują zasobów**: Istnieją pewne produkty, takie jak
  biblioteki statyczne, które nie są pakietami i dlatego nie obsługują zasobów.
  Z tego powodu musisz albo uciec się do innego typu produktu, na przykład
  frameworków, które mogą zwiększyć obciążenie projektu lub aplikacji. Na
  przykład statyczne frameworki będą połączone statycznie z produktem końcowym,
  a faza kompilacji jest wymagana tylko do skopiowania zasobów do produktu
  końcowego. Lub dynamiczne frameworki, w których Xcode skopiuje zarówno plik
  binarny, jak i zasoby do produktu końcowego, ale wydłuży to czas uruchamiania
  aplikacji, ponieważ framework musi być ładowany dynamicznie.
- **Podatne na błędy uruchomieniowe**: Zasoby są identyfikowane przez ich nazwę
  i rozszerzenie (ciągi znaków). Dlatego literówka w którymkolwiek z nich
  doprowadzi do błędu podczas próby uzyskania dostępu do zasobu. Nie jest to
  idealne rozwiązanie, ponieważ nie jest wychwytywane w czasie kompilacji i może
  prowadzić do awarii w wersji.

Tuist rozwiązuje powyższe problemy poprzez **syntezę ujednoliconego interfejsu
dostępu do pakietów i zasobów**, który abstrahuje od szczegółów implementacji.

::: warning RECOMMENDED
<!-- -->
Chociaż dostęp do zasobów za pośrednictwem interfejsu zsyntetyzowanego przez
Tuist nie jest obowiązkowy, zalecamy go, ponieważ ułatwia on rozumowanie kodu i
poruszanie się po zasobach.
<!-- -->
:::

## Zasoby {#resources}

Tuist zapewnia interfejsy do deklarowania zawartości plików takich jak
`Info.plist` lub uprawnień w Swift. Jest to przydatne do zapewnienia spójności
między celami i projektami oraz wykorzystania kompilatora do wychwytywania
błędów w czasie kompilacji. Można również wymyślić własne abstrakcje do
modelowania zawartości i udostępniania jej między celami i projektami.

Gdy projekt zostanie wygenerowany, Tuist zsyntetyzuje zawartość tych plików i
zapisze je w katalogu `Derived` względem katalogu zawierającego projekt, który
je definiuje.

::: tip GITIGNORE THE DERIVED DIRECTORY
<!-- -->
Zalecamy dodanie katalogu `Derived` do pliku `.gitignore` projektu.
<!-- -->
:::

## Akcesory pakietu {#bundle-accessors}

Tuist syntetyzuje interfejs umożliwiający dostęp do pakietu zawierającego zasoby
docelowe.

### Swift {#swift}

Cel będzie zawierał rozszerzenie typu `Bundle`, które eksponuje pakiet:

```swift
let bundle = Bundle.module
```

### Objective-C {#objectivec}

W Objective-C dostępny jest interfejs `{Target}Resources` umożliwiający dostęp
do pakietu:

```objc
NSBundle *bundle = [MyFeatureResources bundle];
```

::: warning LIMITATION WITH INTERNAL TARGETS
<!-- -->
Obecnie Tuist nie generuje akcesorów pakietów zasobów dla wewnętrznych celów,
które zawierają tylko źródła Objective-C. Jest to znane ograniczenie śledzone w
[wydaniu #6456](https://github.com/tuist/tuist/issues/6456).
<!-- -->
:::

::: tip SUPPORTING RESOURCES IN LIBRARIES THROUGH BUNDLES
<!-- -->
Jeśli produkt docelowy, na przykład biblioteka, nie obsługuje zasobów, Tuist
umieści zasoby w produkcie docelowym typu `bundle`, zapewniając, że trafią one
do produktu końcowego, a interfejs wskaże właściwy pakiet.
<!-- -->
:::

## Accessory zasobów {#resource-accessors}

Zasoby są identyfikowane przez ich nazwę i rozszerzenie za pomocą ciągów znaków.
Nie jest to idealne rozwiązanie, ponieważ nie jest wychwytywane w czasie
kompilacji i może prowadzić do awarii w wersji release. Aby temu zapobiec, Tuist
integruje [SwiftGen](https://github.com/SwiftGen/SwiftGen) z procesem
generowania projektu w celu syntezy interfejsu dostępu do zasobów. Dzięki temu
można bez obaw uzyskać dostęp do zasobów, wykorzystując kompilator do
wychwycenia wszelkich problemów.

Tuist zawiera
[szablony](https://github.com/tuist/tuist/tree/main/Sources/TuistGenerator/Templates)
do domyślnej syntezy akcesorów dla następujących typów zasobów:

| Typ zasobu      | Syntetyzowane pliki      |
| --------------- | ------------------------ |
| Obrazy i kolory | `Assets+{Target}.swift`  |
| Struny          | `Strings+{Target}.swift` |
| Listy           | `{NameOfPlist}.swift`    |
| Czcionki        | `Fonts+{Target}.swift`   |
| Pliki           | `Files+{Target}.swift`   |

> Uwaga: Można wyłączyć syntezę akcesorów zasobów dla poszczególnych projektów,
> przekazując opcję `disableSynthesizedResourceAccessors` do opcji projektu.

#### Szablony niestandardowe {#custom-templates}

Jeśli chcesz dostarczyć własne szablony do syntezy akcesorów do innych typów
zasobów, które muszą być obsługiwane przez
[SwiftGen](https://github.com/SwiftGen/SwiftGen), możesz je utworzyć pod adresem
`Tuist/ResourceSynthesizers/{name}.stencil`, gdzie nazwa jest wersją zasobu
pisaną wielkimi literami.

| Zasoby           | Nazwa szablonu             |
| ---------------- | -------------------------- |
| ciągi            | `Strings.stencil`          |
| aktywa           | `Assets.stencil`           |
| plisty           | `Plists.stencil`           |
| czcionki         | `Fonts.stencil`            |
| coreData         | `CoreData.stencil`         |
| interfaceBuilder | `InterfaceBuilder.stencil` |
| json             | `JSON.stencil`             |
| yaml             | `YAML.stencil`             |
| pliki            | `Files.stencil`            |

Jeśli chcesz skonfigurować listę typów zasobów do syntezy akcesorów, możesz użyć
właściwości `Project.resourceSynthesizers`, przekazując listę syntezatorów
zasobów, których chcesz użyć:

```swift
let project = Project(resourceSynthesizers: [.string(), .fonts()])
```

::: info REFERENCE
<!-- -->
Możesz sprawdzić [this
fixture](https://github.com/tuist/tuist/tree/main/cli/Fixtures/ios_app_with_templates),
aby zobaczyć przykład użycia niestandardowych szablonów do syntezy akcesorów do
zasobów.
<!-- -->
:::
