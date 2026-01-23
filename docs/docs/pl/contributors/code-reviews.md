---
{
  "title": "Code reviews",
  "titleTemplate": ":title · Contributors · Tuist",
  "description": "Learn how to contribute to Tuist by reviewing code"
}
---
# Recenzje kodu {#code-reviews}

Sprawdzanie pull requestów to częsty rodzaj wkładu. Mimo że ciągła integracja
(CI) gwarantuje, że kod działa tak, jak powinien, to nie wystarczy. Są pewne
cechy wkładu, których nie da się zautomatyzować: projekt, struktura i
architektura kodu, jakość testów czy literówki. Poniższe sekcje przedstawiają
różne aspekty procesu sprawdzania kodu.

## Czytelność {#readability}

Czy kod jasno wyraża swój zamysł? **Jeśli musisz poświęcić dużo czasu na
zrozumienie działania kodu, oznacza to, że jego implementacja wymaga poprawy.**
Zaproponuj podzielenie kodu na mniejsze, łatwiejsze do zrozumienia abstrakcje.
Alternatywnie, w ostateczności, można dodać komentarz wyjaśniający uzasadnienie
takiego rozwiązania. Zadaj sobie pytanie, czy w najbliższej przyszłości byłbyś w
stanie zrozumieć kod bez dodatkowego kontekstu, takiego jak opis pull requestu.

## Małe pull requesty {#small-pull-requests}

Duże pull requesty są trudne do przejrzenia i łatwiej przeoczyć w nich
szczegóły. Jeśli pull request staje się zbyt duży i trudny do opanowania,
zasugeruj autorowi, aby go podzielił.

::: info EXCEPTIONS
<!-- -->
Istnieje kilka scenariuszy, w których podział pull requestu nie jest możliwy,
np. gdy zmiany są ściśle powiązane i nie można ich rozdzielić. W takich
przypadkach autor powinien przedstawić jasne wyjaśnienie zmian i uzasadnienie
ich wprowadzenia.
<!-- -->
:::

## Spójność {#consistency}

Ważne jest, aby zmiany były spójne z resztą projektu. Niespójności utrudniają
konserwację, dlatego należy ich unikać. Jeśli istnieje podejście do wyświetlania
komunikatów dla użytkownika lub zgłaszania błędów, należy się go trzymać. Jeśli
autor nie zgadza się ze standardami projektu, zaproponuj mu otwarcie zgłoszenia,
w którym będziemy mogli omówić te kwestie.

## Testy {#tests}

Testy pozwalają na pewną zmianę kodu. Kod w pull requestach powinien być
przetestowany, a wszystkie testy powinny zakończyć się powodzeniem. Dobry test
to taki, który konsekwentnie daje ten sam wynik i jest łatwy do zrozumienia i
utrzymania. Recenzenci spędzają większość czasu na przeglądaniu kodu
implementacyjnego, ale testy są równie ważne, ponieważ również stanowią kod.

## Zmiany wprowadzające istotne modyfikacje {#breaking-changes}

Zmiany powodujące niekompatybilność są niekorzystne dla użytkowników Tuist.
Przyczyniając się do rozwoju projektu, należy unikać wprowadzania zmian
powodujących niekompatybilność, chyba że jest to absolutnie konieczne. Istnieje
wiele funkcji językowych, które możemy wykorzystać do rozwoju interfejsu Tuist
bez uciekania się do zmian powodujących niekompatybilność. To, czy zmiana
powoduje niekompatybilność, może nie być oczywiste. Metodą weryfikacji, czy
zmiana jest przełomowa, jest uruchomienie Tuist na projektach w katalogu
fixtures. Wymaga to postawienia się w sytuacji użytkownika i wyobrażenia sobie,
jak zmiany wpłyną na niego.
