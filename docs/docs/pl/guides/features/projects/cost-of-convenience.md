---
{
  "title": "The cost of convenience",
  "titleTemplate": ":title · Projects · Features · Guides · Tuist",
  "description": "Learn about the cost of convenience in Xcode and how Tuist helps you prevent the issues that come with it."
}
---
# Koszt wygody {#the-cost-of-convenience}

Zaprojektowanie edytora kodu, z którego może korzystać całe spektrum **od małych
do dużych projektów** jest trudnym zadaniem. Wiele narzędzi podchodzi do tego
problemu poprzez warstwowanie swoich rozwiązań i zapewnianie rozszerzalności.
Najniższa warstwa jest bardzo niskopoziomowa i bliska bazowemu systemowi
kompilacji, a najwyższa warstwa jest wysokopoziomową abstrakcją, która jest
wygodna w użyciu, ale mniej elastyczna. W ten sposób sprawiają, że proste rzeczy
są łatwe, a wszystko inne jest możliwe.

Jednak **[Apple](https://www.apple.com) zdecydował się przyjąć inne podejście w
Xcode**. Powód jest nieznany, ale prawdopodobnie optymalizacja pod kątem wyzwań
związanych z dużymi projektami nigdy nie była ich celem. Przeinwestowali w
wygodę dla małych projektów, zapewnili niewielką elastyczność i silnie powiązali
narzędzia z bazowym systemem kompilacji. Aby osiągnąć wygodę, zapewnili rozsądne
ustawienia domyślne, które można łatwo zastąpić, i dodali wiele niejawnych
zachowań związanych z czasem kompilacji, które są winowajcą wielu problemów na
dużą skalę.

## Wyrazistość i skala {#explicitness-and-scale}

Podczas pracy na dużą skalę, jawność **jest kluczowa**. Pozwala to systemowi
kompilacji analizować i rozumieć strukturę projektu oraz zależności z
wyprzedzeniem, a także wykonywać optymalizacje, które w przeciwnym razie byłyby
niemożliwe. Ta sama jednoznaczność jest również kluczem do zapewnienia, że
funkcje edytora, takie jak [Podgląd
SwiftUI](https://developer.apple.com/documentation/swiftui/previews-in-xcode)
lub [Makra
Swift](https://docs.swift.org/swift-book/documentation/the-swift-programming-language/macros/)
działają niezawodnie i przewidywalnie. Ponieważ Xcode i projekty Xcode przyjęły
niejawność jako ważny wybór projektowy w celu osiągnięcia wygody, zasadę, którą
odziedziczył Menedżer pakietów Swift, trudności związane z używaniem Xcode są
również obecne w Menedżerze pakietów Swift.

:: info ROLA TUISTA
<!-- -->
Możemy podsumować rolę Tuist jako narzędzia, które zapobiega niejawnie
zdefiniowanym projektom i wykorzystuje jawność w celu zapewnienia lepszego
doświadczenia programisty (np. walidacje, optymalizacje). Narzędzia takie jak
[Bazel](https://bazel.build) idą dalej, przenosząc je na poziom systemu
kompilacji.
<!-- -->
:::

Jest to kwestia, która jest ledwo dyskutowana w społeczności, ale jest bardzo
istotna. Podczas pracy nad Tuist zauważyliśmy, że wiele organizacji i
deweloperów myśli, że obecne wyzwania, przed którymi stoją, zostaną rozwiązane
przez [Swift Package
Manager](https://www.swift.org/documentation/package-manager/), ale nie zdają
sobie sprawy, że ponieważ opiera się on na tych samych zasadach, nawet jeśli
łagodzi tak dobrze znane konflikty Git, pogarszają one wrażenia programistów w
innych obszarach i nadal sprawiają, że projekty nie są optymalne.

W poniższych sekcjach omówimy kilka rzeczywistych przykładów tego, jak
niejawność wpływa na doświadczenie programisty i kondycję projektu. Lista ta nie
jest wyczerpująca, ale powinna dać ci dobre wyobrażenie o wyzwaniach, które
możesz napotkać podczas pracy z projektami Xcode lub pakietami Swift.

## Wygoda na twojej drodze {#convenience-getting-in-your-way}

### Współdzielony katalog zbudowanych produktów {#shared-built-products-directory}.

Xcode używa katalogu wewnątrz katalogu danych pochodnych dla każdego produktu.
Wewnątrz niego przechowywane są artefakty kompilacji, takie jak skompilowane
pliki binarne, pliki dSYM i dzienniki. Ponieważ wszystkie produkty projektu
trafiają do tego samego katalogu, który jest domyślnie widoczny z innych
obiektów docelowych, z którymi można je połączyć, **może skończyć się z
obiektami docelowymi, które niejawnie zależą od siebie nawzajem.** Chociaż może
to nie być problemem, gdy masz tylko kilka celów, może to objawiać się jako
nieudane kompilacje, które są trudne do debugowania, gdy projekt się rozrasta.

Konsekwencją tej decyzji projektowej jest to, że wiele projektów przypadkowo
kompiluje się z grafem, który nie jest dobrze zdefiniowany.

::: tip TUIST DETECTION OF IMPLICIT DEPENDENCIES
<!-- -->
Tuist udostępnia polecenie
<LocalizedLink href="/guides/features/inspect/implicit-dependencies"></LocalizedLink>
do wykrywania niejawnych zależności. Możesz użyć tego polecenia, aby sprawdzić w
CI, czy wszystkie zależności są jawne.
<!-- -->
:::

### Znajdź niejawne zależności w schematach {#find-implicit-dependencies-in-schemes}.

Definiowanie i utrzymywanie grafu zależności w Xcode staje się coraz trudniejsze
wraz z rozwojem projektu. Jest to trudne, ponieważ są one skodyfikowane w
plikach `.pbxproj` jako fazy kompilacji i ustawienia kompilacji, nie ma narzędzi
do wizualizacji i pracy z wykresem, a zmiany w wykresie (np. dodanie nowego
dynamicznego prekompilowanego frameworka) mogą wymagać zmian konfiguracji w górę
strumienia (np. dodanie nowej fazy kompilacji w celu skopiowania frameworka do
pakietu).

Apple zdecydowało w pewnym momencie, że zamiast ewoluować model grafu w coś
łatwiejszego w zarządzaniu, bardziej sensowne będzie dodanie opcji rozwiązywania
niejawnych zależności w czasie kompilacji. Jest to ponownie wątpliwy wybór
projektowy, ponieważ może skończyć się wolniejszymi czasami kompilacji lub
nieprzewidywalnymi kompilacjami. Na przykład, kompilacja może przejść lokalnie z
powodu pewnego stanu w danych pochodnych, który działa jak
[singleton](https://en.wikipedia.org/wiki/Singleton_pattern), ale następnie nie
skompilować się na CI, ponieważ stan jest inny.

::: napiwek
<!-- -->
Zalecamy wyłączenie tej opcji w schematach projektu i korzystanie z Tuist, który
ułatwia zarządzanie grafem zależności.
<!-- -->
:::

### SwiftUI Previews and static libraries/frameworks {#swiftui-previews-and-static-librariesframeworks}.

Niektóre funkcje edytora, takie jak SwiftUI Previews lub Swift Macros, wymagają
kompilacji wykresu zależności z edytowanego pliku. Ta integracja między edytorem
wymaga, aby system kompilacji rozwiązał wszelkie niejawności i wyprowadził
odpowiednie artefakty, które są niezbędne do działania tych funkcji. Jak można
sobie wyobrazić, **im bardziej niejawny jest wykres, tym trudniejsze jest
zadanie dla systemu kompilacji**, a zatem nie jest zaskakujące, że wiele z tych
funkcji nie działa niezawodnie. Często słyszymy od deweloperów, że przestali
używać podglądów SwiftUI dawno temu, ponieważ były one zbyt zawodne. Zamiast
tego używają przykładowych aplikacji lub unikają pewnych rzeczy, takich jak
korzystanie z bibliotek statycznych lub faz kompilacji skryptów, ponieważ
powodują one uszkodzenie funkcji.

### Biblioteki łączone {#mergeable-libraries}

Dynamiczne frameworki, choć bardziej elastyczne i łatwiejsze w użyciu, mają
negatywny wpływ na czas uruchamiania aplikacji. Z drugiej strony, biblioteki
statyczne są szybsze do uruchomienia, ale wpływają na czas kompilacji i są nieco
trudniejsze w pracy, szczególnie w złożonych scenariuszach graficznych. *Czy nie
byłoby wspaniale, gdybyś mógł przełączać się między jednym lub drugim w
zależności od konfiguracji?* Tak właśnie musiało myśleć Apple, kiedy zdecydowało
się pracować nad bibliotekami, które można łączyć. Ale po raz kolejny przenieśli
więcej wnioskowania w czasie kompilacji do czasu kompilacji. Jeśli chodzi o
wykres zależności, wyobraź sobie, że musisz to zrobić, gdy statyczna lub
dynamiczna natura celu zostanie rozwiązana w czasie kompilacji na podstawie
niektórych ustawień kompilacji w niektórych celach. Życzę powodzenia w
zapewnieniu niezawodnego działania przy jednoczesnym zapewnieniu, że funkcje
takie jak podgląd SwiftUI nie ulegną uszkodzeniu.

**Wielu użytkowników zgłasza się do Tuist chcąc korzystać z bibliotek, które
można łączyć, a nasza odpowiedź jest zawsze taka sama. Nie ma takiej potrzeby.**
Możesz kontrolować statyczną lub dynamiczną naturę swoich obiektów docelowych w
czasie generowania, co prowadzi do projektu, którego graf jest znany przed
kompilacją. Żadne zmienne nie muszą być rozwiązywane w czasie kompilacji.

```bash
# The value of TUIST_DYNAMIC can be read from the project {#the-value-of-tuist_dynamic-can-be-read-from-the-project}
# to set the product as static or dynamic based on the value. {#to-set-the-product-as-static-or-dynamic-based-on-the-value}
TUIST_DYNAMIC=1 tuist generate
```

## Wyraźny, wyraźny i wyraźny {#wyraźny-wyraźny-i-wyraźny}

Jeśli istnieje ważna niepisana zasada, którą zalecamy każdemu programiście lub
organizacji, która chce skalować swój rozwój za pomocą Xcode, to powinna ona
obejmować jawność. A jeśli trudno jest zarządzać jawnością w surowych projektach
Xcode, powinni rozważyć coś innego, albo [Tuist](https://tuist.io), albo
[Bazel](https://bazel.build). **Tylko wtedy niezawodność, przewidywalność i
optymalizacje będą możliwe.**

## Przyszłość {#future}

Nie wiadomo, czy Apple zrobi coś, aby zapobiec wszystkim powyższym problemom.
Ich ciągłe decyzje wbudowane w Xcode i Swift Package Manager nie sugerują, że
tak się stanie. Po zezwoleniu na niejawną konfigurację jako prawidłowy stan,
**trudno jest przejść od tego bez wprowadzania przełomowych zmian.** Powrót do
pierwszych zasad i ponowne przemyślenie projektu narzędzi może doprowadzić do
zerwania wielu projektów Xcode, które przypadkowo kompilowały się przez lata.
Wyobraźmy sobie wrzawę społeczności, gdyby tak się stało.

Apple znalazło się trochę w kłopotliwej sytuacji. Wygoda jest tym, co pomaga
programistom szybko rozpocząć pracę i tworzyć więcej aplikacji dla ich
ekosystemu. Ale ich decyzje, aby zapewnić wygodę w tej skali, utrudniają im
zapewnienie niezawodnego działania niektórych funkcji Xcode.

Ponieważ przyszłość jest nieznana, staramy się **być jak najbliżej standardów
branżowych i projektów Xcode**. Zapobiegamy powyższym problemom i wykorzystujemy
wiedzę, którą posiadamy, aby zapewnić lepsze wrażenia programistyczne. W
idealnym przypadku nie musielibyśmy uciekać się do generowania projektów, ale
brak rozszerzalności Xcode i menedżera pakietów Swift sprawiają, że jest to
jedyna realna opcja. Jest to również bezpieczna opcja, ponieważ będą musieli
złamać projekty Xcode, aby złamać projekty Tuist.

Idealnie byłoby, gdyby **system kompilacji był bardziej rozszerzalny**, ale czy
nie byłoby złym pomysłem posiadanie wtyczek / rozszerzeń, które zawierają umowy
ze światem niejawności? Nie wydaje się to dobrym pomysłem. Wygląda więc na to,
że będziemy potrzebować zewnętrznych narzędzi, takich jak Tuist lub
[Bazel](https://bazel.build), aby zapewnić lepsze wrażenia programistyczne. A
może Apple zaskoczy nas wszystkich i sprawi, że Xcode będzie bardziej
rozszerzalny i jawny...

Dopóki tak się nie stanie, musisz wybrać, czy chcesz przyjąć na siebie konwencję
Xcode i wziąć na siebie dług, który się z tym wiąże, czy też zaufać nam w tej
podróży, aby zapewnić lepsze wrażenia programistyczne. Nie zawiedziemy cię.
