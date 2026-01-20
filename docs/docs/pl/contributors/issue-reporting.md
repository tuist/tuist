---
{
  "title": "Issue reporting",
  "titleTemplate": ":title · Contributors · Tuist",
  "description": "Learn how to contribute to Tuist by reporting bugs"
}
---
# Zgłaszanie problemów {#issue-reporting}

Jako użytkownik Tuist możesz natknąć się na błędy lub nieoczekiwane zachowania.
Jeśli tak się stanie, zachęcamy do ich zgłaszania, abyśmy mogli je naprawić.

## GitHub issues to nasza platforma do obsługi zgłoszeń {#github-issues-is-our-ticketing-platform}

Problemy powinny być zgłaszane na GitHubie jako [GitHub
issues](https://github.com/tuist/tuist/issues), a nie na Slacku czy innych
platformach. GitHub jest lepszy do śledzenia i zarządzania zgłoszeniami, jest
bliżej bazy kodu i pozwala nam śledzić postępy w zgłaszaniu zgłoszeń. Co więcej,
zachęca do długiego opisu problemu, co zmusza zgłaszającego do zastanowienia się
nad problemem i zapewnienia szerszego kontekstu.

## Kontekst ma kluczowe znaczenie {#context-is-crucial}

Zgłoszenie bez wystarczającego kontekstu zostanie uznane za niekompletne, a
autor zostanie poproszony o podanie dodatkowego kontekstu. Jeśli nie zostaną one
dostarczone, zgłoszenie zostanie zamknięte. Pomyśl o tym w ten sposób: im więcej
kontekstu podasz, tym łatwiej będzie nam zrozumieć problem i go naprawić. Jeśli
więc chcesz, aby Twój problem został naprawiony, podaj jak najwięcej kontekstu.
Spróbuj odpowiedzieć na następujące pytania:

- Co próbowałeś zrobić?
- Jak wygląda wykres?
- Jakiej wersji Tuist używasz?
- Czy to cię blokuje?

Wymagamy również dostarczenia minimalnego projektu **do odtworzenia**.

## Projekt wielokrotnego użytku {#reproducible-project}

### Czym jest powtarzalny projekt? {#what-is-a-reproducible-project}

Odtwarzalny projekt to mały projekt Tuist mający na celu zademonstrowanie
problemu - często problem ten jest spowodowany błędem w Tuist. Odtwarzalny
projekt powinien zawierać minimum funkcji potrzebnych do zademonstrowania błędu.

### Dlaczego warto tworzyć powtarzalne przypadki testowe? {#why-should-you-create-a-reproducible-test-case}

Odtwarzalne projekty pozwalają nam wyizolować przyczynę problemu, co jest
pierwszym krokiem do jego naprawienia! Najważniejszą częścią każdego zgłoszenia
błędu jest opisanie dokładnych kroków potrzebnych do jego odtworzenia.

Odtwarzalny projekt to świetny sposób na udostępnienie określonego środowiska,
które powoduje błąd. Twój odtwarzalny projekt to najlepszy sposób, by pomóc
ludziom, którzy chcą pomóc tobie.

### Kroki tworzenia powtarzalnego projektu {#steps-to-create-a-reproducible-project}

- Utwórz nowe repozytorium git.
- Zainicjuj projekt za pomocą `tuist init` w katalogu repozytorium.
- Dodaj kod potrzebny do odtworzenia błędu.
- Opublikuj kod (dobrym miejscem do tego jest konto GitHub), a następnie utwórz
  link do niego podczas tworzenia zgłoszenia.

### Korzyści z powtarzalnych projektów {#benefits-of-reproducible-projects}

- **Mniejsza powierzchnia:** Usuwając wszystko poza błędem, nie musisz kopać,
  aby znaleźć błąd.
- **Nie ma potrzeby publikowania tajnego kodu:** Możesz nie być w stanie
  opublikować swojej głównej strony (z wielu powodów). Przerobienie niewielkiej
  jej części na powtarzalny przypadek testowy pozwala publicznie zademonstrować
  problem bez ujawniania tajnego kodu.
- **Dowód błędu:** Czasami błąd jest spowodowany pewną kombinacją ustawień na
  komputerze. Odtwarzalny przypadek testowy pozwala współtwórcom na pobranie
  kompilacji i przetestowanie jej również na swoich komputerach. Pomaga to
  zweryfikować i zawęzić przyczynę problemu.
- **Uzyskaj pomoc w naprawieniu błędu:** Jeśli ktoś inny jest w stanie odtworzyć
  twój problem, często ma duże szanse na jego naprawienie. Naprawienie błędu bez
  jego wcześniejszego odtworzenia jest prawie niemożliwe.
