---
{
  "title": "The Modular Architecture (TMA)",
  "titleTemplate": ":title · Projects · Features · Guides · Tuist",
  "description": "Learn about The Modular Architecture (TMA) and how to structure your projects using it."
}
---
# Architektura modułowa (TMA) {#the-modular-architecture-tma}

TMA to podejście architektoniczne do strukturyzacji aplikacji Apple OS, które
umożliwia skalowalność, optymalizację cykli kompilacji i testowania oraz
zapewnia dobre praktyki w zespole. Jego podstawową ideą jest tworzenie aplikacji
poprzez budowanie niezależnych funkcji, które są połączone za pomocą jasnych i
zwięzłych interfejsów API.

W niniejszych wytycznych przedstawiono zasady architektury, które pomogą Ci
zidentyfikować i uporządkować funkcje aplikacji w różnych warstwach. Zawierają
one również wskazówki, narzędzia i porady dotyczące korzystania z tej
architektury.

::: info µFEATURES
<!-- -->
Architektura ta była wcześniej znana jako µFeatures. Zmieniliśmy jej nazwę na
The Modular Architecture (TMA), aby lepiej odzwierciedlała jej cel i zasady, na
których się opiera.
<!-- -->
:::

## Podstawowa zasada {#core-principle}

Programiści powinni mieć możliwość szybkiego tworzenia, testowania i
wypróbowywania swoich funkcji **** niezależnie od głównej aplikacji, przy
jednoczesnym zapewnieniu niezawodnego działania funkcji Xcode, takich jak
podgląd interfejsu użytkownika, autouzupełnianie kodu i debugowanie.

## Co to jest moduł? {#what-is-a-module}

Moduł reprezentuje funkcję aplikacji i jest kombinacją następujących pięciu
celów (gdzie cel odnosi się do celu Xcode):

- **Źródło:** Zawiera kod źródłowy funkcji (Swift, Objective-C, C++,
  JavaScript...) oraz jej zasoby (obrazy, czcionki, scenariusze, xibs).
- **Interfejs:** Jest to cel towarzyszący, który zawiera publiczny interfejs i
  modele funkcji.
- **Testy:** Zawiera testy jednostkowe i integracyjne funkcji.
- **Testowanie:** Zawiera dane testowe, które można wykorzystać w testach i
  przykładowej aplikacji. Zawiera również makiety klas modułów i protokołów,
  które mogą być wykorzystane przez inne funkcje, jak zobaczymy później.
- **Przykład:** Zawiera przykładową aplikację, której programiści mogą używać do
  wypróbowania funkcji w określonych warunkach (różne języki, rozmiary ekranu,
  ustawienia).

Zalecamy stosowanie konwencji nazewnictwa dla celów, którą można egzekwować w
projekcie dzięki DSL Tuist.

| Cel                  | Zależności                      | Treść                            |
| -------------------- | ------------------------------- | -------------------------------- |
| `Funkcja`            | `FeatureInterface`              | Kod źródłowy i zasoby            |
| `FeatureInterface`   | -                               | Interfejs publiczny i modele     |
| `Testy funkcji`      | `Funkcja`, `FeatureTesting`     | Testy jednostkowe i integracyjne |
| `Testowanie funkcji` | `FeatureInterface`              | Dane testowe i makiety           |
| `FunkcjaPrzykład`    | `Testowanie funkcji`, `Funkcja` | Przykładowa aplikacja            |

::: tip UI Previews
<!-- -->
`Funkcja` może korzystać z `FeatureTesting` jako zasobu programistycznego, aby
umożliwić podgląd interfejsu użytkownika.
<!-- -->
:::

::: warning COMPILER DIRECTIVES INSTEAD OF TESTING TARGETS
<!-- -->
Alternatywnie można użyć dyrektyw kompilatora, aby dołączyć dane testowe i
makiety do celów `Feature` lub `FeatureInterface` podczas kompilacji dla
`Debug`. Upraszczasz wykres, ale w rezultacie skompilujesz kod, który nie będzie
potrzebny do uruchomienia aplikacji.
<!-- -->
:::

## Dlaczego moduł? {#why-a-module}

### Przejrzyste i zwięzłe interfejsy API {#clear-and-concise-apis}

Gdy cały kod źródłowy aplikacji znajduje się w tym samym miejscu docelowym,
bardzo łatwo jest stworzyć niejawne zależności w kodzie i skończyć z dobrze
znanym kodem spaghetti. Wszystko jest silnie powiązane, stan jest czasami
nieprzewidywalny, a wprowadzanie nowych zmian staje się koszmarem. Kiedy
definiujemy funkcje w niezależnych miejscach docelowych, musimy zaprojektować
publiczne interfejsy API jako część implementacji naszych funkcji. Musimy
zdecydować, co powinno być publiczne, w jaki sposób nasza funkcja powinna być
wykorzystywana i co powinno pozostać prywatne. Mamy większą kontrolę nad tym, w
jaki sposób klienci naszej funkcji powinni z niej korzystać, i możemy egzekwować
dobre praktyki, projektując bezpieczne interfejsy API.

### Małe moduły {#small-modules}

[Dziel i rządź](https://en.wikipedia.org/wiki/Divide_and_conquer). Praca w
małych modułach pozwala na większą koncentrację oraz testowanie i wypróbowywanie
funkcji w izolacji. Ponadto cykle rozwoju są znacznie szybsze, ponieważ mamy
bardziej selektywną kompilację, kompilując tylko te komponenty, które są
niezbędne do działania naszej funkcji. Kompilacja całej aplikacji jest konieczna
dopiero na samym końcu naszej pracy, kiedy musimy zintegrować funkcję z
aplikacją.

### Możliwość ponownego wykorzystania {#reusability}

Zachęcamy do ponownego wykorzystywania kodu w aplikacjach i innych produktach,
takich jak rozszerzenia, przy użyciu frameworków lub bibliotek. Dzięki tworzeniu
modułów ich ponowne wykorzystanie jest dość proste. Możemy zbudować rozszerzenie
iMessage, rozszerzenie Today lub aplikację watchOS, po prostu łącząc istniejące
moduły i dodając _(w razie potrzeby)_ warstwy interfejsu użytkownika specyficzne
dla platformy.

## Zależności {#dependencies}

Gdy moduł jest zależny od innego modułu, deklaruje zależność względem docelowego
interfejsu. Ma to dwie zalety. Zapobiega to powiązaniu implementacji modułu z
implementacją innego modułu oraz przyspiesza czyste kompilacje, ponieważ
wymagają one jedynie kompilacji implementacji naszej funkcji oraz interfejsów
bezpośrednich i przejściowych zależności. Podejście to zostało zainspirowane
pomysłem SwiftRock dotyczącym [skrócenia czasu kompilacji iOS poprzez użycie
modułów
interfejsowych](https://swiftrocks.com/reducing-ios-build-times-by-using-interface-targets).

W zależności od interfejsów aplikacje muszą tworzyć wykres implementacji w
czasie wykonywania i wstrzykiwać zależności do modułów, które ich potrzebują.
Chociaż TMA nie ma zdania na temat sposobu realizacji tego zadania, zalecamy
stosowanie rozwiązań lub wzorców wstrzykiwania zależności, które nie dodają
pośrednich odwołań w czasie kompilacji ani nie wykorzystują interfejsów API
platformy, które nie zostały zaprojektowane do tego celu.

## Rodzaje produktów {#product-types}

Podczas tworzenia modułu można wybierać między bibliotekami i frameworkami **,**
oraz **, a także statycznym i dynamicznym łączeniem** dla celów. Bez Tuist
podjęcie tej decyzji jest nieco bardziej skomplikowane, ponieważ konieczne jest
ręczne skonfigurowanie wykresu zależności. Jednak dzięki Tuist Projects nie
stanowi to już problemu.

Zalecamy używanie bibliotek dynamicznych lub frameworków podczas programowania
przy użyciu
<LocalizedLink href="/guides/features/projects/synthesized-files#bundle-accessors">akcesorów
pakietów</LocalizedLink>, aby oddzielić logikę dostępu do pakietów od charakteru
biblioteki lub frameworka docelowego. Ma to kluczowe znaczenie dla szybkiego
kompilowania i zapewnienia niezawodnego działania [SwiftUI
Previews](https://developer.apple.com/documentation/swiftui/previews-in-xcode).
W przypadku kompilacji wydawniczych należy używać bibliotek statycznych lub
frameworków, aby zapewnić szybkie uruchamianie aplikacji. Możesz wykorzystać
<LocalizedLink href="/guides/features/projects/dynamic-configuration#configuration-through-environment-variables">konfigurację
dynamiczną</LocalizedLink>, aby zmienić typ produktu w momencie generowania:

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
Firma Apple próbowała złagodzić uciążliwość przełączania się między bibliotekami
statycznymi i dynamicznymi, wprowadzając [biblioteki
scalane](https://developer.apple.com/documentation/xcode/configuring-your-project-to-use-mergeable-libraries).
Jednak powoduje to nieokreśloność czasu kompilacji, co sprawia, że kompilacja
jest niepowtarzalna i trudniejsza do optymalizacji, dlatego nie zalecamy jej
stosowania.
<!-- -->
:::

## Kod {#code}

TMA nie ma zdania na temat architektury kodu i wzorców dla modułów. Chcielibyśmy
jednak podzielić się kilkoma wskazówkami opartymi na naszym doświadczeniu:

- **Wykorzystanie kompilatora jest świetnym rozwiązaniem.** Nadmierne
  wykorzystanie kompilatora może okazać się nieproduktywne i spowodować, że
  niektóre funkcje Xcode, takie jak podgląd, będą działać nieprawidłowo.
  Zalecamy używanie kompilatora do egzekwowania dobrych praktyk i wczesnego
  wykrywania błędów, ale nie do tego stopnia, aby utrudniało to czytanie i
  utrzymanie kodu.
- **Używaj makr Swift z umiarem.** Mogą one być bardzo potężnym narzędziem, ale
  mogą również utrudniać czytanie i utrzymanie kodu.
- **Wykorzystaj platformę i język, nie abstrahuj od nich.** Próby tworzenia
  rozbudowanych warstw abstrakcji mogą przynieść efekt przeciwny do
  zamierzonego. Platforma i język są wystarczająco potężne, aby tworzyć świetne
  aplikacje bez potrzeby stosowania dodatkowych warstw abstrakcji. Korzystaj z
  dobrych wzorców programowania i projektowania jako punktu odniesienia do
  tworzenia swoich funkcji.

## Zasoby {#resources}

- [Budowanie µFeatures](https://speakerdeck.com/pepibumur/building-ufeatures)
- [Programowanie zorientowane na
  framework](https://speakerdeck.com/pepibumur/framework-oriented-programming-mobilization-dot-pl)
- [Podróż do frameworków i języka
  Swift](https://speakerdeck.com/pepibumur/a-journey-into-frameworks-and-swift)
- [Wykorzystanie frameworków do przyspieszenia rozwoju na iOS – część
  1](https://developers.soundcloud.com/blog/leveraging-frameworks-to-speed-up-our-development-on-ios-part-1)
- [Programowanie zorientowane na
  bibliotekę](https://academy.realm.io/posts/justin-spahr-summers-library-oriented-programming/)
- [Budowanie nowoczesnych
  frameworków](https://developer.apple.com/videos/play/wwdc2014/416/)
- [Nieoficjalny przewodnik po plikach
  xcconfig](https://pewpewthespells.com/blog/xcconfig_guide.html)
- [Biblioteki statyczne i
  dynamiczne](https://pewpewthespells.com/blog/static_and_dynamic_libraries.html)
