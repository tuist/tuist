---
{
  "title": "Principles",
  "titleTemplate": ":title · Contributors · Tuist",
  "description": "This document describes the principles that guide the development of Tuist."
}
---
# Zasady {#principles}

Ta strona opisuje zasady, które stanowią filary projektowania i rozwoju Tuist.
Ewolucjonują one wraz z projektem i mają na celu zapewnienie zrównoważonego
rozwoju, który jest dobrze dostosowany do podstaw projektu.

## Domyślnie stosuj konwencje. {#default-to-conventions}

Jednym z powodów istnienia Tuist jest to, że Xcode ma słabe konwencje, co
prowadzi do powstawania złożonych projektów, które są trudne do skalowania i
utrzymania. Z tego powodu Tuist przyjmuje inne podejście, domyślnie stosując
proste i dokładnie zaprojektowane konwencje. **Programiści mogą zrezygnować z
konwencji, ale jest to świadoma decyzja, która nie wydaje się naturalna.**

Na przykład istnieje konwencja definiowania zależności między celami za pomocą
dostarczonego interfejsu publicznego. Dzięki temu Tuist zapewnia, że projekty są
generowane z odpowiednimi konfiguracjami, aby łączenie działało. Programiści
mają możliwość zdefiniowania zależności poprzez ustawienia kompilacji, ale robią
to w sposób niejawny, co powoduje naruszenie funkcji Tuist, takich jak `tuist
graph` lub `tuist cache`, które opierają się na przestrzeganiu pewnych
konwencji.

Powodem, dla którego domyślnie stosujemy konwencje, jest to, że im więcej
decyzji możemy podjąć w imieniu programistów, tym bardziej będą oni mogli skupić
się na tworzeniu funkcji dla swoich aplikacji. Gdy nie mamy żadnych konwencji,
jak ma to miejsce w przypadku wielu projektów, musimy podejmować decyzje, które
ostatecznie będą niespójne z innymi decyzjami, a w konsekwencji pojawi się
przypadkowa złożoność, która będzie trudna do opanowania.

## Manifesty są źródłem prawdy. {#manifests-are-the-source-of-truth}

Wiele warstw konfiguracji i umów między nimi powoduje, że konfiguracja projektu
jest trudna do zrozumienia i utrzymania. Pomyśl przez chwilę o przeciętnym
projekcie. Definicja projektu znajduje się w katalogach `.xcodeproj`, CLI w
skryptach (np. `Fastfiles`), a logika CI w potokach. Są to trzy warstwy z
umowami między nimi, które musimy utrzymywać. *Jak często zdarzało Ci się
zmienić coś w swoich projektach, a tydzień później zdałeś sobie sprawę, że
skrypty wydania przestały działać?*

Możemy to uprościć, korzystając z jednego źródła informacji, czyli plików
manifestu. Pliki te dostarczają Tuistowi informacji potrzebnych do generowania
projektów Xcode, które programiści mogą wykorzystać do edycji swoich plików.
Ponadto umożliwiają one stosowanie standardowych poleceń do tworzenia projektów
ze środowiska lokalnego lub CI.

**Tuist powinien przejąć odpowiedzialność za złożoność i udostępnić prosty,
bezpieczny i przyjemny interfejs, aby opisać swoje projekty w sposób jak
najbardziej jednoznaczny.**

## Wyraź to, co jest domyślne. {#make-the-implicit-explicit}

Xcode obsługuje konfiguracje domyślne. Dobrym przykładem jest wnioskowanie o
domyślnie zdefiniowanych zależnościach. Chociaż domyślność jest odpowiednia w
przypadku małych projektów, gdzie konfiguracje są proste, to w przypadku
większych projektów może powodować spowolnienie lub dziwne zachowania.

Tuist powinien zapewniać wyraźne interfejsy API dla niejawnych zachowań Xcode.
Powinien również obsługiwać definiowanie niejawności Xcode, ale zaimplementowane
w taki sposób, aby zachęcać programistów do wyboru podejścia jawnego. Obsługa
niejawności i zawiłości Xcode ułatwia przyjęcie Tuist, po czym zespoły mogą
poświęcić trochę czasu na pozbycie się niejawności.

Dobrym przykładem jest definicja zależności. Chociaż programiści mogą definiować
zależności poprzez ustawienia kompilacji i fazy, Tuist zapewnia piękny interfejs
API, który zachęca do jego stosowania.

**Projektowanie API w sposób jednoznaczny pozwala Tuist na przeprowadzanie
pewnych kontroli i optymalizacji projektów, które w innym przypadku nie byłyby
możliwe.** Ponadto umożliwia to korzystanie z funkcji takich jak `tuist graph`,
która eksportuje reprezentację wykresu zależności, lub `tuist cache`, która
buforuje wszystkie cele jako pliki binarne.

::: napiwek
<!-- -->
Każde żądanie przeniesienia funkcji z Xcode powinniśmy traktować jako okazję do
uproszczenia koncepcji za pomocą prostych i jednoznacznych interfejsów API.
<!-- -->
:::

## Postaraj się, aby tekst był prosty. {#keep-it-simple}

Jednym z głównych wyzwań podczas skalowania projektów Xcode jest fakt, że
**Xcode jest bardzo złożony dla użytkowników.** Z tego powodu zespoły mają
wysoki współczynnik bus factor i tylko kilka osób w zespole rozumie projekt i
błędy zgłaszane przez system kompilacji. Jest to zła sytuacja, ponieważ zespół
polega na kilku osobach.

Xcode to świetne narzędzie, ale lata ulepszeń, nowe platformy i języki
programowania odbiły się na jego wyglądzie, który z trudem zachował prostotę.

Tuist powinien wykorzystać okazję, aby zachować prostotę, ponieważ praca nad
prostymi rzeczami jest przyjemna i motywująca. Nikt nie chce tracić czasu na
debugowanie błędu, który pojawia się na samym końcu procesu kompilacji, ani na
zrozumienie, dlaczego nie można uruchomić aplikacji na swoich urządzeniach.
Xcode przekazuje zadania do swojego podstawowego systemu kompilacji i w
niektórych przypadkach bardzo słabo radzi sobie z przekładaniem błędów na
działania, które można podjąć. Czy kiedykolwiek otrzymałeś komunikat „ *”
„framework X not found” „* ” i nie wiedziałeś, co zrobić? Wyobraź sobie, że
otrzymaliśmy listę potencjalnych przyczyn błędu.

## Zacznij od doświadczenia programisty. {#start-from-the-developers-experience}

Jednym z powodów, dla których brakuje innowacji w Xcode, lub inaczej mówiąc, nie
ma ich tak wiele jak w innych środowiskach programistycznych, jest to, że
**często zaczynamy analizować problemy od istniejących rozwiązań.** W rezultacie
większość rozwiązań, które obecnie znajdujemy, opiera się na tych samych
pomysłach i procesach. Chociaż dobrze jest uwzględniać istniejące rozwiązania w
równaniach, nie powinniśmy pozwolić, aby ograniczały one naszą kreatywność.

Podoba nam się sposób myślenia [Toma Prestona](https://tom.preston-werner.com/)
przedstawiony w [tym podcaście](https://tom.preston-werner.com/): *„Większość
rzeczy można osiągnąć, wszystko, co masz w głowie, prawdopodobnie uda ci się
zrealizować za pomocą kodu, o ile jest to możliwe w ramach ograniczeń
wszechświata”.* Jeśli **wyobrażamy sobie, jak chcielibyśmy, aby wyglądało
doświadczenie programisty**, to jest to tylko kwestia czasu, aby to osiągnąć —
rozpoczęcie analizy problemów z punktu widzenia doświadczenia programisty daje
nam unikalny punkt widzenia, który doprowadzi nas do rozwiązań, które
użytkownicy będą chętnie stosować.

Możemy ulec pokusie, aby podążać za tym, co robią wszyscy, nawet jeśli oznacza
to znoszenie niedogodności, na które wszyscy nadal narzekają. Nie róbmy tego.
Jak wyobrażam sobie archiwizację mojej aplikacji? Jak chciałbym, aby wyglądało
podpisywanie kodu? Jakie procesy mogę usprawnić dzięki Tuist? Na przykład
dodanie obsługi [Fastlane](https://fastlane.tools/) jest rozwiązaniem problemu,
który musimy najpierw zrozumieć. Możemy dotrzeć do sedna problemu, zadając
pytania „dlaczego”. Kiedy już zawężymy źródło motywacji, możemy pomyśleć o tym,
jak Tuist może najlepiej pomóc. Być może rozwiązaniem jest integracja z
Fastlane, ale ważne jest, abyśmy nie lekceważyli innych, równie ważnych
rozwiązań, które możemy rozważyć przed podjęciem decyzji.

## Błędy mogą się zdarzyć i zdarzają się. {#errors-can-and-will-happen}

My, programiści, mamy wrodzoną skłonność do ignorowania faktu, że mogą wystąpić
błędy. W rezultacie projektujemy i testujemy oprogramowanie, biorąc pod uwagę
wyłącznie idealny scenariusz.

Swift, jego system typów i dobrze zaprojektowany kod mogą pomóc w zapobieganiu
niektórym błędom, ale nie wszystkim, ponieważ niektóre z nich są poza naszą
kontrolą. Nie możemy zakładać, że użytkownik zawsze będzie miał połączenie z
Internetem lub że polecenia systemowe zostaną pomyślnie wykonane. Środowiska, w
których działa Tuist, nie są piaskownicami, które kontrolujemy, dlatego musimy
starać się zrozumieć, jak mogą się one zmieniać i wpływać na Tuist.

Źle obsłużone błędy powodują złe wrażenia użytkowników, którzy mogą stracić
zaufanie do projektu. Chcemy, aby użytkownicy cieszyli się każdym elementem
Tuist, nawet sposobem, w jaki prezentujemy im błędy.

Powinniśmy postawić się w sytuacji użytkowników i wyobrazić sobie, czego
oczekiwalibyśmy od komunikatu o błędzie. Jeśli język programowania jest kanałem
komunikacyjnym, przez który propagowane są błędy, a użytkownicy są odbiorcami
tych błędów, powinny one być napisane w tym samym języku, którym posługują się
odbiorcy (użytkownicy). Powinny zawierać wystarczającą ilość informacji, aby
zrozumieć, co się stało, i ukrywać informacje, które nie są istotne. Ponadto
powinny być praktyczne, informując użytkowników, jakie kroki mogą podjąć, aby je
naprawić.

I wreszcie, co nie mniej ważne, nasze przypadki testowe powinny uwzględniać
scenariusze niepowodzeń. Nie tylko zapewniają one, że obsługujemy błędy tak, jak
powinniśmy, ale także zapobiegają naruszeniu tej logiki przez przyszłych
programistów.
