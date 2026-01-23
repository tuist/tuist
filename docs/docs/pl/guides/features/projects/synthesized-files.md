---
{
  "title": "Synthesized files",
  "titleTemplate": ":title · Projects · Features · Guides · Tuist",
  "description": "Learn about synthesized files in Tuist projects."
}
---
# Syntetyzowane pliki {#synthesized-files}

Tuist może generować pliki i kod w czasie generowania, aby ułatwić zarządzanie
projektami Xcode i pracę z nimi. Na tej stronie dowiesz się więcej o tej funkcji
i o tym, jak możesz ją wykorzystać w swoich projektach.

## Zasoby docelowe {#target-resources}

Projekty Xcode obsługują dodawanie zasobów do celów. Stanowią one jednak pewne
wyzwanie dla zespołów, zwłaszcza podczas pracy z projektami modułowymi, w
których źródła i zasoby są często przenoszone:

- **Niespójny dostęp w czasie wykonywania**: Miejsce, w którym zasoby trafiają
  do produktu końcowego, oraz sposób uzyskiwania do nich dostępu zależą od
  produktu docelowego. Na przykład, jeśli produkt docelowy stanowi aplikacja,
  zasoby są kopiowane do pakietu aplikacji. Prowadzi to do sytuacji, w której
  kod uzyskujący dostęp do zasobów opiera się na założeniach dotyczących
  struktury pakietu, co nie jest idealnym rozwiązaniem, ponieważ utrudnia
  zrozumienie kodu i przenoszenie zasobów.
- **Produkty, które nie obsługują zasobów**: Istnieją pewne produkty, takie jak
  biblioteki statyczne, które nie są pakietami i dlatego nie obsługują zasobów.
  Z tego powodu musisz skorzystać z innego typu produktu, na przykład
  frameworków, co może spowodować dodatkowe obciążenie projektu lub aplikacji.
  Na przykład frameworki statyczne będą statycznie połączone z produktem
  końcowym, a faza kompilacji jest wymagana tylko do skopiowania zasobów do
  produktu końcowego. Lub frameworki dynamiczne, w których Xcode skopiuje
  zarówno plik binarny, jak i zasoby do produktu końcowego, ale zwiększy to czas
  uruchamiania aplikacji, ponieważ framework musi być ładowany dynamicznie.
- **Podatność na błędy wykonania**: Zasoby są identyfikowane na podstawie ich
  nazwy i rozszerzenia (ciągi znaków). Dlatego też literówka w dowolnym z tych
  elementów spowoduje błąd wykonania podczas próby uzyskania dostępu do zasobu.
  Nie jest to idealne rozwiązanie, ponieważ nie jest wykrywane w czasie
  kompilacji i może prowadzić do awarii w wersji produkcyjnej.

Tuist rozwiązuje powyższe problemy poprzez **syntezę ujednoliconego interfejsu
dostępu do pakietów i zasobów**, który abstrahuje szczegóły implementacji.

::: warning RECOMMENDED
<!-- -->
Chociaż dostęp do zasobów za pośrednictwem interfejsu syntetyzowanego przez
Tuist nie jest obowiązkowy, zalecamy go, ponieważ ułatwia on rozumienie kodu i
poruszanie się po zasobach.
<!-- -->
:::

## Zasoby {#resources}

Tuist udostępnia interfejsy do deklarowania zawartości plików, takich jak
`Info.plist` lub uprawnień w Swift. Jest to przydatne do zapewnienia spójności
między celami i projektami oraz wykorzystania kompilatora do wykrywania
problemów w czasie kompilacji. Możesz również stworzyć własne abstrakcje do
modelowania zawartości i udostępniać je między celami i projektami.

Po wygenerowaniu projektu Tuist zsyntetyzuje zawartość tych plików i zapisze je
w katalogu `Derived` względem katalogu zawierającego projekt, który je
definiuje.

::: tip GITIGNORE THE DERIVED DIRECTORY
<!-- -->
Zalecamy dodanie katalogu `Derived` do pliku `.gitignore` projektu.
<!-- -->
:::

## Akcesory pakietu {#bundle-accessors}

Tuist syntetyzuje interfejs umożliwiający dostęp do pakietu zawierającego
docelowe zasoby.

### Swift {#swift}

Cel będzie zawierał rozszerzenie typu` typu `Bundle, które ujawnia pakiet:

```swift
let bundle = Bundle.module
```

### Objective-C {#objectivec}

W Objective-C uzyskasz interfejs `{Target}Resources`, aby uzyskać dostęp do
pakietu:

```objc
NSBundle *bundle = [MyFeatureResources bundle];
```

::: warning LIMITATION WITH INTERNAL TARGETS
<!-- -->
Obecnie Tuist nie generuje akcesorów pakietów zasobów dla celów wewnętrznych,
które zawierają wyłącznie źródła Objective-C. Jest to znane ograniczenie
śledzone w [problemie nr 6456](https://github.com/tuist/tuist/issues/6456).
<!-- -->
:::

::: tip SUPPORTING RESOURCES IN LIBRARIES THROUGH BUNDLES
<!-- -->
Jeśli produkt docelowy, na przykład biblioteka, nie obsługuje zasobów, Tuist
dołączy zasoby do produktu docelowego typu `bundle`, zapewniając, że trafią one
do produktu końcowego, a interfejs będzie wskazywał właściwy pakiet. Te
syntetyczne pakiety są automatycznie oznaczane tagiem `tuist:synthesized` i
dziedziczą wszystkie tagi z nadrzędnego produktu docelowego, co pozwala kierować
je do profili
<LocalizedLink href="/guides/features/projects/metadata-tags#system-tags">cache</LocalizedLink>.
<!-- -->
:::

## Accessory zasobów {#resource-accessors}

Zasoby są identyfikowane na podstawie ich nazwy i rozszerzenia przy użyciu
ciągów znaków. Nie jest to idealne rozwiązanie, ponieważ nie jest wykrywane w
czasie kompilacji i może prowadzić do awarii w wersji produkcyjnej. Aby temu
zapobiec, Tuist integruje [SwiftGen](https://github.com/SwiftGen/SwiftGen) z
procesem generowania projektu w celu syntezy interfejsu umożliwiającego dostęp
do zasobów. Dzięki temu można bezpiecznie uzyskać dostęp do zasobów,
wykorzystując kompilator do wykrywania wszelkich problemów.

Tuist zawiera
[szablony](https://github.com/tuist/tuist/tree/main/Sources/TuistGenerator/Templates)
do syntezy akcesorów dla następujących typów zasobów domyślnie:

| Typ zasobu      | Syntetyzowane pliki       |
| --------------- | ------------------------- |
| Obrazy i kolory | `Assets+{Target}.swift`   |
| Ciągi znaków    | `Strings+{Target}.swift`  |
| Plisty          | `{NazwaPlist}.swift`      |
| Czcionki        | `Czcionki+{Target}.swift` |
| Pliki           | `Pliki+{Target}.swift`    |

> Uwaga: Możesz wyłączyć syntezę akcesorów zasobów dla poszczególnych projektów,
> przekazując opcję `disableSynthesizedResourceAccessors` do opcji projektu.

#### Szablony niestandardowe {#custom-templates}

Jeśli chcesz udostępnić własne szablony do syntezy akcesorów do innych typów
zasobów, które muszą być obsługiwane przez
[SwiftGen](https://github.com/SwiftGen/SwiftGen), możesz je utworzyć w
`Tuist/ResourceSynthesizers/{nazwa}.stencil`, gdzie nazwa jest wersją zasobu
zapisana w stylu camel case.

| Zasoby           | Nazwa szablonu             |
| ---------------- | -------------------------- |
| ciągi znaków     | `Strings.stencil`          |
| zasoby           | `Assets.stencil`           |
| plisty           | `Plists.stencil`           |
| czcionki         | `Fonts.stencil`            |
| coreData         | `CoreData.stencil`         |
| interfaceBuilder | `InterfaceBuilder.stencil` |
| json             | `JSON.stencil`             |
| yaml             | `YAML.stencil`             |
| pliki            | `Pliki.szablon`            |

Jeśli chcesz skonfigurować listę typów zasobów, dla których mają być
syntetyzowane akcesory, możesz użyć właściwości `Project.resourceSynthesizers`,
przekazując listę syntezatorów zasobów, których chcesz użyć:

```swift
let project = Project(resourceSynthesizers: [.string(), .fonts()])
```

::: info REFERENCE
<!-- -->
Możesz sprawdzić [ten
przykład](https://github.com/tuist/tuist/tree/main/examples/xcode/generated_ios_app_with_templates),
aby zobaczyć, jak używać niestandardowych szablonów do syntezy akcesorów do
zasobów.
<!-- -->
:::
