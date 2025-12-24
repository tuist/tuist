---
{
  "title": "The Modular Architecture (TMA)",
  "titleTemplate": ":title · Projects · Features · Guides · Tuist",
  "description": "Learn about The Modular Architecture (TMA) and how to structure your projects using it."
}
---
# Architektura modułowa (TMA) {#the-modular-architecture-tma}

TMA to podejście architektoniczne do strukturyzacji aplikacji Apple OS w celu
zapewnienia skalowalności, optymalizacji cykli kompilacji i testowania oraz
zapewnienia dobrych praktyk w zespole. Jego podstawową ideą jest tworzenie
aplikacji poprzez budowanie niezależnych funkcji, które są ze sobą połączone za
pomocą jasnych i zwięzłych interfejsów API.

Niniejsze wytyczne wprowadzają zasady architektury, pomagając zidentyfikować i
zorganizować funkcje aplikacji w różnych warstwach. Przedstawia również
wskazówki, narzędzia i porady, jeśli zdecydujesz się użyć tej architektury.

::: info µFEATURES
<!-- -->
Architektura ta była wcześniej znana jako µFeatures. Zmieniliśmy jej nazwę na
The Modular Architecture (TMA), aby lepiej odzwierciedlić jej cel i zasady,
które za nią stoją.
<!-- -->
:::

## Podstawowa zasada {#core-principle}

** Deweloperzy powinni mieć możliwość szybkiego tworzenia, testowania i
wypróbowywania **swoich funkcji, niezależnie od głównej aplikacji, przy
jednoczesnym zapewnieniu niezawodnego działania funkcji Xcode, takich jak
podgląd interfejsu użytkownika, uzupełnianie kodu i debugowanie.

## Co to jest moduł {#what-is-a-module}

Moduł reprezentuje funkcję aplikacji i jest kombinacją następujących pięciu
celów (gdzie cel odnosi się do celu Xcode):

- **Źródło:** Zawiera kod źródłowy funkcji (Swift, Objective-C, C++,
  JavaScript...) i jego zasoby (obrazy, czcionki, storyboardy, xibs).
- **Interfejs:** Jest to cel towarzyszący, który zawiera publiczny interfejs i
  modele funkcji.
- **Testy:** Zawiera testy jednostkowe i integracyjne funkcji.
- **Testowanie:** Zapewnia dane testowe, które można wykorzystać w testach i
  przykładowej aplikacji. Zapewnia również makiety dla klas modułów i
  protokołów, które mogą być używane przez inne funkcje, jak zobaczymy później.
- **Przykład:** Zawiera przykładową aplikację, którą deweloperzy mogą
  wykorzystać do wypróbowania funkcji w określonych warunkach (różne języki,
  rozmiary ekranu, ustawienia).

Zalecamy przestrzeganie konwencji nazewnictwa obiektów docelowych, co można
wymusić w swoim projekcie dzięki DSL Tuist.

| Cel                | Zależności                  | Treść                            |
| ------------------ | --------------------------- | -------------------------------- |
| `Cecha`            | `FeatureInterface`          | Kod źródłowy i zasoby            |
| `FeatureInterface` | -                           | Interfejs publiczny i modele     |
| `FeatureTests`     | `Feature`, `FeatureTesting` | Testy jednostkowe i integracyjne |
| `FeatureTesting`   | `FeatureInterface`          | Testowanie danych i makiet       |
| `FeatureExample`   | `FeatureTesting`, `Feature` | Przykładowa aplikacja            |

::: tip UI Previews
<!-- -->
`Funkcja` może korzystać z `FeatureTesting` jako zasobu deweloperskiego, aby
umożliwić podgląd interfejsu użytkownika.
<!-- -->
:::

::: warning COMPILER DIRECTIVES INSTEAD OF TESTING TARGETS
<!-- -->
Alternatywnie można użyć dyrektyw kompilatora, aby dołączyć dane testowe i
makiety do celów `Feature` lub `FeatureInterface` podczas kompilacji dla
`Debug`. Uprościsz wykres, ale ostatecznie skompilujesz kod, który nie będzie
potrzebny do uruchomienia aplikacji.
<!-- -->
:::

## Dlaczego moduł {#why-a-module}

### Przejrzyste i zwięzłe interfejsy API {#clear-and-concise-apis}

Gdy cały kod źródłowy aplikacji znajduje się w tym samym miejscu docelowym,
bardzo łatwo jest zbudować ukryte zależności w kodzie i skończyć z tak dobrze
znanym kodem spaghetti. Wszystko jest silnie powiązane, stan jest czasami
nieprzewidywalny, a wprowadzanie nowych zmian staje się koszmarem. Kiedy
definiujemy funkcje w niezależnych celach, musimy zaprojektować publiczne
interfejsy API jako część naszej implementacji funkcji. Musimy zdecydować, co
powinno być publiczne, jak nasza funkcja powinna być konsumowana, a co powinno
pozostać prywatne. Mamy większą kontrolę nad tym, w jaki sposób chcemy, aby nasi
klienci korzystali z funkcji i możemy egzekwować dobre praktyki poprzez
projektowanie bezpiecznych interfejsów API.

### Małe moduły {#small-modules}

[Dziel i zwyciężaj](https://en.wikipedia.org/wiki/Divide_and_conquer). Praca w
małych modułach pozwala bardziej skupić się na testowaniu i wypróbowywaniu
funkcji w izolacji. Co więcej, cykle rozwoju są znacznie szybsze, ponieważ mamy
bardziej selektywną kompilację, kompilując tylko te komponenty, które są
niezbędne do uruchomienia naszej funkcji. Kompilacja całej aplikacji jest
konieczna tylko na samym końcu naszej pracy, kiedy musimy zintegrować funkcję z
aplikacją.

### Możliwość ponownego użycia {#reusability}

Ponowne wykorzystanie kodu w aplikacjach i innych produktach, takich jak
rozszerzenia, jest zalecane przy użyciu frameworków lub bibliotek. Tworząc
moduły, ich ponowne wykorzystanie jest dość proste. Możemy zbudować rozszerzenie
iMessage, rozszerzenie Today lub aplikację watchOS, po prostu łącząc istniejące
moduły i dodając _(w razie potrzeby)_ warstwy interfejsu użytkownika specyficzne
dla platformy.

## Zależności {#dependencies}

Gdy moduł zależy od innego modułu, deklaruje zależność od swojego interfejsu
docelowego. Korzyść z tego jest dwojaka. Zapobiega to sprzężeniu implementacji
modułu z implementacją innego modułu i przyspiesza czyste kompilacje, ponieważ
muszą one skompilować tylko implementację naszej funkcji oraz interfejsy
bezpośrednich i przechodnich zależności. Podejście to jest inspirowane pomysłem
SwiftRock [Reducing iOS Build Times by using Interface
Modules](https://swiftrocks.com/reducing-ios-build-times-by-using-interface-targets).

Zależność od interfejsów wymaga od aplikacji budowania grafu implementacji w
czasie wykonywania i wstrzykiwania zależności do modułów, które go potrzebują.
Chociaż TMA nie wypowiada się na temat tego, jak to zrobić, zalecamy korzystanie
z rozwiązań lub wzorców wstrzykiwania zależności lub rozwiązań, które nie dodają
pośredników w czasie wbudowanym ani nie używają interfejsów API platformy, które
nie zostały zaprojektowane do tego celu.

## Rodzaje produktów {#product-types}

Podczas tworzenia modułu można wybrać pomiędzy **bibliotekami i frameworkami**,
a **statycznym i dynamicznym linkowaniem** dla celów. Bez Tuist podjęcie tej
decyzji jest nieco bardziej skomplikowane, ponieważ trzeba ręcznie skonfigurować
wykres zależności. Jednak dzięki Tuist Projects nie stanowi to już problemu.

Zalecamy korzystanie z dynamicznych bibliotek lub frameworków podczas
programowania przy użyciu
<LocalizedLink href="/guides/features/projects/synthesized-files#bundle-accessors">bundle accessors</LocalizedLink>, aby oddzielić logikę dostępu do pakietów od
biblioteki lub frameworka docelowego. Ma to kluczowe znaczenie dla szybkiego
czasu kompilacji i zapewnienia niezawodnego działania [SwiftUI
Previews](https://developer.apple.com/documentation/swiftui/previews-in-xcode).
A statyczne biblioteki lub frameworki dla kompilacji wydania, aby zapewnić
szybkie uruchamianie aplikacji. Możesz wykorzystać
<LocalizedLink href="/guides/features/projects/dynamic-configuration#configuration-through-environment-variables"> konfigurację dynamiczną</LocalizedLink>, aby zmienić typ produktu w czasie
generowania:

```bash
# You'll have to read the value of the variable from the manifest {#youll-have-to-read-the-value-of-the-variable-from-the-manifest}
# and use it to change the linking type {#and-use-it-to-change-the-linking-type}
TUIST_PRODUCT_TYPE=static-library tuist generate
```

```swift
// You can place this in your manifest files or helpers
// and use the returned value when instantiating targets.
func productType() -> Product {
    if case let .string(productType) = Environment.productType {
        return productType == "static-library" ? .staticLibrary : .framework
    } else {
        return .framework
    }
}
```


::: warning MERGEABLE LIBRARIES
<!-- -->
Apple próbowało złagodzić uciążliwość przełączania się między bibliotekami
statycznymi i dynamicznymi, wprowadzając [mergeable
libraries](https://developer.apple.com/documentation/xcode/configuring-your-project-to-use-mergeable-libraries).
Wprowadza to jednak niedeterminizm w czasie kompilacji, który sprawia, że
kompilacja nie jest odtwarzalna i trudniejsza do optymalizacji, więc nie
zalecamy jej używania.
<!-- -->
:::

## Kod {#code}

TMA nie wypowiada się na temat architektury kodu i wzorców dla modułów.
Chcielibyśmy jednak podzielić się kilkoma wskazówkami opartymi na naszym
doświadczeniu:

- **Wykorzystanie kompilatora jest świetne.** Nadmierne wykorzystanie
  kompilatora może okazać się nieproduktywne i spowodować, że niektóre funkcje
  Xcode, takie jak podglądy, będą działać zawodnie. Zalecamy korzystanie z
  kompilatora w celu egzekwowania dobrych praktyk i wczesnego wychwytywania
  błędów, ale nie do tego stopnia, aby utrudniało to czytanie i konserwację
  kodu.
- **Makr Swift należy używać oszczędnie.** Mogą one być bardzo potężne, ale mogą
  również utrudniać czytanie i utrzymanie kodu.
- **Uwzględnij platformę i język, nie abstrahuj od nich.** Próba wymyślenia
  rozbudowanych warstw abstrakcji może przynieść efekt przeciwny do
  zamierzonego. Platforma i język są wystarczająco potężne, aby tworzyć świetne
  aplikacje bez potrzeby tworzenia dodatkowych warstw abstrakcji. Używaj dobrych
  wzorców programistycznych i projektowych jako odniesienia do budowania swoich
  funkcji.

## Zasoby {#resources}

- [Budowanie µFeatures](https://speakerdeck.com/pepibumur/building-ufeatures)
- [Programowanie zorientowane
  ramowo](https://speakerdeck.com/pepibumur/framework-oriented-programming-mobilization-dot-pl).
- [Podróż do frameworków i
  Swift](https://speakerdeck.com/pepibumur/a-journey-into-frameworks-and-swift).
- [Wykorzystanie frameworków do przyspieszenia rozwoju na iOS - część
  1](https://developers.soundcloud.com/blog/leveraging-frameworks-to-speed-up-our-development-on-ios-part-1)
- [Programowanie zorientowane na
  biblioteki](https://academy.realm.io/posts/justin-spahr-summers-library-oriented-programming/).
- [Budowanie nowoczesnych
  frameworków](https://developer.apple.com/videos/play/wwdc2014/416/).
- [Nieoficjalny przewodnik po plikach
  xcconfig](https://pewpewthespells.com/blog/xcconfig_guide.html)
- [Biblioteki statyczne i
  dynamiczne](https://pewpewthespells.com/blog/static_and_dynamic_libraries.html).
