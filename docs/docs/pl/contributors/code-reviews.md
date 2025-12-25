---
{
  "title": "Code reviews",
  "titleTemplate": ":title · Contributors · Tuist",
  "description": "Learn how to contribute to Tuist by reviewing code"
}
---
# Recenzje kodów {#code-reviews}

Przeglądanie pull requestów jest powszechnym rodzajem wkładu. Pomimo ciągłej
integracji (CI) zapewniającej, że kod robi to, co powinien, to nie wystarczy.
Istnieją cechy wkładu, których nie można zautomatyzować: projekt, struktura i
architektura kodu, jakość testów lub literówki. Poniższe sekcje przedstawiają
różne aspekty procesu przeglądu kodu.

## Czytelność {#readability}

Czy kod jasno wyraża swoje intencje? **Jeśli musisz spędzić dużo czasu na
zastanawianiu się, co robi kod, należy poprawić jego implementację.** Zasugeruj
podzielenie kodu na mniejsze abstrakcje, które są łatwiejsze do zrozumienia.
Alternatywnie i jako ostatni zasób, mogą dodać komentarz wyjaśniający
rozumowanie, które za tym stoi. Zadaj sobie pytanie, czy byłbyś w stanie
zrozumieć kod w niedalekiej przyszłości, bez otaczającego kontekstu, takiego jak
opis pull requesta.

## Małe pull requesty {#small-pull-requests}

Duże pull requesty są trudne do przejrzenia i łatwiej jest przeoczyć szczegóły.
Jeśli pull request staje się zbyt duży i niemożliwy do zarządzania, zasugeruj
autorowi jego rozbicie.

::: info EXCEPTIONS
<!-- -->
Istnieje kilka scenariuszy, w których podział pull requesta nie jest możliwy, na
przykład gdy zmiany są ściśle powiązane i nie można ich podzielić. W takich
przypadkach autor powinien przedstawić jasne wyjaśnienie zmian i ich
uzasadnienie.
<!-- -->
:::

## Spójność {#consistency}

Ważne jest, aby zmiany były spójne z resztą projektu. Niespójności komplikują
konserwację, dlatego powinniśmy ich unikać. Jeśli istnieje podejście do
wysyłania komunikatów do użytkownika lub zgłaszania błędów, powinniśmy się go
trzymać. Jeśli autor nie zgadza się ze standardami projektu, zasugeruj mu
otwarcie tematu, w którym możemy omówić je dalej.

## Testy {#tests}

Testy pozwalają na pewną zmianę kodu. Kod w pull requestach powinien być
przetestowany, a wszystkie testy powinny przejść pomyślnie. Dobry test to taki,
który konsekwentnie daje ten sam wynik i jest łatwy do zrozumienia i utrzymania.
Recenzenci spędzają większość czasu na przeglądaniu kodu implementacji, ale
testy są równie ważne, ponieważ również są kodem.

## Przełomowe zmiany {#breaking-changes}

Uszkadzające zmiany są złym doświadczeniem dla użytkowników Tuist. Wkład
powinien unikać wprowadzania przełomowych zmian, chyba że jest to absolutnie
konieczne. Istnieje wiele funkcji językowych, które możemy wykorzystać do
ewolucji interfejsu Tuist bez uciekania się do łamania zmian. To, czy zmiana
jest łamiąca czy nie, może nie być oczywiste. Metodą na sprawdzenie, czy zmiana
jest szkodliwa, jest uruchomienie Tuist względem projektów w katalogu fixtures.
Wymaga to postawienia się w sytuacji użytkownika i wyobrażenia sobie, jak zmiany
wpłyną na niego.
