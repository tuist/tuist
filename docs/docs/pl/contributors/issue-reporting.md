---
{
  "title": "Issue reporting",
  "titleTemplate": ":title · Contributors · Tuist",
  "description": "Learn how to contribute to Tuist by reporting bugs"
}
---
# Zgłaszanie problemów {#issue-reporting}

Jako użytkownik Tuist możesz napotkać błędy lub nieoczekiwane zachowania. Jeśli
tak się stanie, zachęcamy do zgłaszania ich, abyśmy mogli je naprawić.

## GitHub issues to nasza platforma do zgłaszania problemów. {#github-issues-is-our-ticketing-platform}

Problemy należy zgłaszać na GitHubie jako [GitHub
issues](https://github.com/tuist/tuist/issues), a nie na Slacku lub innych
platformach. GitHub jest lepszy do śledzenia i zarządzania problemami, jest
bliższy kodowi źródłowemu i pozwala nam śledzić postępy w rozwiązywaniu
problemów. Ponadto zachęca do długiego opisu problemu, co zmusza zgłaszającego
do przemyślenia problemu i podania większej ilości kontekstu.

## Kontekst ma kluczowe znaczenie. {#context-is-crucial}

Problem bez wystarczającego kontekstu zostanie uznany za niekompletny, a autor
zostanie poproszony o dodatkowy kontekst. Jeśli nie zostanie on dostarczony,
problem zostanie zamknięty. Pomyśl o tym w ten sposób: im więcej kontekstu
dostarczysz, tym łatwiej będzie nam zrozumieć problem i go naprawić. Jeśli więc
chcesz, aby Twój problem został rozwiązany, dostarcz jak najwięcej kontekstu.
Spróbuj odpowiedzieć na następujące pytania:

- Co próbowałeś zrobić?
- Jak wygląda Twój wykres?
- Z jakiej wersji Tuist korzystasz?
- Czy to Ci przeszkadza?

Wymagamy również dostarczenia minimalnego projektu, który można odtworzyć na
**** .

## Projekt powtarzalny {#reproducible-project}

### Czym jest projekt powtarzalny? {#what-is-a-reproducible-project}

Projekt powtarzalny to niewielki projekt Tuist służący do zademonstrowania
problemu — często problem ten jest spowodowany błędem w Tuist. Twój projekt
powtarzalny powinien zawierać minimalną liczbę funkcji niezbędnych do wyraźnego
zademonstrowania błędu.

### Dlaczego warto tworzyć powtarzalne przypadki testowe? {#why-should-you-create-a-reproducible-test-case}

Powtarzalne projekty pozwalają nam wyizolować przyczynę problemu, co jest
pierwszym krokiem do jego rozwiązania! Najważniejszą częścią każdego zgłoszenia
błędu jest opisanie dokładnych kroków niezbędnych do odtworzenia błędu.

Projekt powtarzalny to świetny sposób na udostępnienie konkretnego środowiska,
które powoduje błąd. Twój projekt powtarzalny to najlepszy sposób, aby pomóc
osobom, które chcą Ci pomóc.

### Kroki niezbędne do stworzenia projektu, który można odtworzyć {#steps-to-create-a-reproducible-project}

- Utwórz nowe repozytorium git.
- Zainicjuj projekt, używając polecenia ` `tuist init` ` w katalogu
  repozytorium.
- Dodaj kod potrzebny do odtworzenia zaobserwowanego błędu.
- Opublikuj kod (dobrym miejscem do tego jest Twoje konto GitHub), a następnie
  podaj link do niego podczas tworzenia zgłoszenia.

### Korzyści płynące z projektów, które można odtworzyć {#benefits-of-reproducible-projects}

- **Mniejsza powierzchnia:** Usuwając wszystko oprócz błędu, nie musisz szukać
  błędu.
- **Nie ma potrzeby publikowania tajnego kodu:** Być może nie będziesz w stanie
  opublikować swojej głównej strony (z wielu powodów). Przerobienie jej
  niewielkiej części na powtarzalny przypadek testowy pozwala publicznie
  zademonstrować problem bez ujawniania tajnego kodu.
- **Dowód błędu:** Czasami błąd jest spowodowany kombinacją ustawień na Twoim
  komputerze. Powtarzalny przypadek testowy pozwala współpracownikom pobrać
  Twoją kompilację i przetestować ją również na swoich komputerach. Pomaga to
  zweryfikować i zawęzić przyczynę problemu.
- **Pomoc w naprawianiu błędów:** Jeśli ktoś inny może odtworzyć Twój problem,
  często ma duże szanse na jego naprawienie. Naprawienie błędu bez możliwości
  jego odtworzenia jest prawie niemożliwe.
