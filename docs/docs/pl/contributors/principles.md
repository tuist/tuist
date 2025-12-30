---
{
  "title": "Principles",
  "titleTemplate": ":title · Contributors · Tuist",
  "description": "This document describes the principles that guide the development of Tuist."
}
---
# Zasady {#principles}

Ta strona opisuje zasady, które są filarami projektowania i rozwoju Tuist.
Ewoluują one wraz z projektem i mają na celu zapewnienie zrównoważonego rozwoju,
który jest dobrze dostosowany do założeń projektu.

## Domyślne konwencje {#default-to-conventions}

Jednym z powodów, dla których Tuist istnieje, jest to, że Xcode jest słaby pod
względem konwencji, co prowadzi do złożonych projektów, które są trudne do
skalowania i utrzymania. Z tego powodu Tuist przyjmuje inne podejście, domyślnie
stosując proste i starannie zaprojektowane konwencje. **Programiści mogą
zrezygnować z konwencji, ale jest to świadoma decyzja, która nie wydaje się
naturalna.**

Na przykład, istnieje konwencja definiowania zależności między obiektami
docelowymi za pomocą udostępnionego interfejsu publicznego. W ten sposób Tuist
zapewnia, że projekty są generowane z odpowiednimi konfiguracjami, aby łączenie
działało. Programiści mają możliwość zdefiniowania zależności za pomocą ustawień
kompilacji, ale robią to niejawnie, a tym samym łamią funkcje Tuist, takie jak
`tuist graph` lub `tuist cache`, które opierają się na przestrzeganiu pewnych
konwencji.

Powodem, dla którego domyślnie stosujemy konwencje, jest to, że im więcej
decyzji możemy podjąć w imieniu programistów, tym bardziej będą oni mogli skupić
się na tworzeniu funkcji dla swoich aplikacji. Kiedy nie mamy żadnych konwencji,
jak ma to miejsce w wielu projektach, musimy podejmować decyzje, które
ostatecznie nie będą spójne z innymi decyzjami, a w konsekwencji pojawi się
przypadkowa złożoność, którą trudno będzie zarządzać.

## Manifesty są źródłem prawdy {#manifests-are-the-source-of-truth}

Posiadanie wielu warstw konfiguracji i umów między nimi skutkuje konfiguracją
projektu, która jest trudna do zrozumienia i utrzymania. Pomyśl przez chwilę o
przeciętnym projekcie. Definicja projektu znajduje się w katalogach
`.xcodeproj`, CLI w skryptach (np. `Fastfiles`), a logika CI w potokach. Są to
trzy warstwy z umowami między nimi, które musimy utrzymywać. *Jak często byłeś w
sytuacji, w której zmieniłeś coś w swoich projektach, a tydzień później zdałeś
sobie sprawę, że skrypty wydania się zepsuły?*

Możemy to uprościć, mając jedno źródło prawdy - pliki manifestu. Pliki te
dostarczają Tuist informacji potrzebnych do generowania projektów Xcode, których
programiści mogą używać do edycji swoich plików. Co więcej, pozwala to na
posiadanie standardowych poleceń do budowania projektów ze środowiska lokalnego
lub CI.

**Tuist powinien być właścicielem złożoności i udostępniać prosty, bezpieczny i
przyjemny interfejs do opisywania swoich projektów tak wyraźnie, jak to tylko
możliwe.**

## Uczyń ukryte jawnym {#make-the-implicit-explicit}

Xcode obsługuje niejawne konfiguracje. Dobrym tego przykładem jest wnioskowanie
o niejawnie zdefiniowanych zależnościach. Chociaż niejawność jest w porządku w
przypadku małych projektów, w których konfiguracje są proste, w miarę jak
projekty stają się większe, może to powodować spowolnienie lub dziwne
zachowania.

Tuist powinien zapewniać jawne interfejsy API dla niejawnych zachowań Xcode.
Powinien również wspierać definiowanie niejawności Xcode, ale zaimplementowanej
w taki sposób, aby zachęcić programistów do wyboru podejścia jawnego. Obsługa
niejawności i zawiłości Xcode ułatwia przyjęcie Tuist, po czym zespoły mogą
poświęcić trochę czasu na pozbycie się niejawności.

Dobrym tego przykładem jest definiowanie zależności. Podczas gdy programiści
mogą definiować zależności za pomocą ustawień kompilacji i faz, Tuist zapewnia
piękny interfejs API, który zachęca do jego przyjęcia.

**Zaprojektowanie interfejsu API tak, aby był jawny, pozwala Tuist na
przeprowadzanie pewnych kontroli i optymalizacji projektów, które w przeciwnym
razie nie byłyby możliwe.** Co więcej, umożliwia to korzystanie z funkcji takich
jak `tuist graph`, która eksportuje reprezentację grafu zależności, lub `tuist
cache`, która buforuje wszystkie cele jako pliki binarne.

::: napiwek
<!-- -->
Powinniśmy traktować każdą prośbę o przeniesienie funkcji z Xcode jako okazję do
uproszczenia koncepcji za pomocą prostych i wyraźnych interfejsów API.
<!-- -->
:::

## Zachowaj prostotę {#keep-it-simple}

Jednym z głównych wyzwań podczas skalowania projektów Xcode jest fakt, że
**Xcode naraża użytkowników na dużą złożoność.** Z tego powodu zespoły mają
wysoki współczynnik magistrali i tylko kilka osób w zespole rozumie projekt i
błędy, które wyrzuca system kompilacji. To zła sytuacja, ponieważ zespół polega
na kilku osobach.

Xcode to świetne narzędzie, ale wiele lat ulepszeń, nowych platform i języków
programowania odbija się na jego powierzchni, która stara się pozostać prosta.

Touist powinien skorzystać z okazji, aby zachować prostotę, ponieważ praca nad
prostymi rzeczami jest zabawna i motywuje nas. Nikt nie chce spędzać czasu na
debugowaniu błędu, który pojawia się na samym końcu procesu kompilacji, ani na
zrozumieniu, dlaczego nie jest w stanie uruchomić aplikacji na swoich
urządzeniach. Xcode deleguje zadania do swojego bazowego systemu kompilacji i w
niektórych przypadkach bardzo słabo radzi sobie z tłumaczeniem błędów na
elementy, które można wykorzystać. Czy kiedykolwiek otrzymałeś błąd *"nie
znaleziono frameworka X"* i nie wiedziałeś, co zrobić? Wyobraź sobie, że
otrzymujemy listę potencjalnych przyczyn błędu.

## Zacznij od doświadczenia dewelopera {#start-from-the-developers-experience}

Jednym z powodów, dla których w Xcode brakuje innowacji, lub mówiąc inaczej, nie
ma ich tyle, co w innych środowiskach programistycznych, jest to, że **często
zaczynamy analizować problemy od istniejących rozwiązań.** W konsekwencji
większość rozwiązań, które obecnie znajdujemy, obraca się wokół tych samych
pomysłów i przepływów pracy. Chociaż dobrze jest uwzględnić istniejące
rozwiązania w równaniach, nie powinniśmy pozwolić, aby ograniczały one naszą
kreatywność.

Lubimy myśleć tak, jak ujął to [Tom Preston](https://tom.preston-werner.com/) w
[tym podcaście](https://tom.preston-werner.com/): *"Większość rzeczy można
osiągnąć, cokolwiek masz w głowie, prawdopodobnie możesz zrealizować za pomocą
kodu, o ile jest to możliwe w ramach ograniczeń wszechświata".* Jeśli
**wyobrazimy sobie, jak chcielibyśmy, aby wyglądało doświadczenie dewelopera**,
to tylko kwestia czasu, aby to osiągnąć - rozpoczęcie analizy problemów od
doświadczenia dewelopera daje nam unikalny punkt widzenia, który doprowadzi nas
do rozwiązań, z których użytkownicy będą chętnie korzystać.

Możemy odczuwać pokusę podążania za tym, co robią wszyscy, nawet jeśli oznacza
to trzymanie się niedogodności, na które wszyscy wciąż narzekają. Nie róbmy
tego. Jak wyobrażam sobie archiwizację mojej aplikacji? Jak chciałbym, aby
wyglądało podpisywanie kodu? Jakie procesy mogę usprawnić dzięki Tuist? Na
przykład, dodanie wsparcia dla [Fastlane](https://fastlane.tools/) jest
rozwiązaniem problemu, który musimy najpierw zrozumieć. Możemy dotrzeć do źródła
problemu, zadając pytania "dlaczego". Gdy zawęzimy źródło motywacji, możemy
zastanowić się, w jaki sposób Tuist może im najlepiej pomóc. Być może
rozwiązaniem jest integracja z Fastlane, ale ważne jest, abyśmy nie lekceważyli
innych równie ważnych rozwiązań, które możemy przedstawić przed dokonaniem
kompromisów.

## Błędy mogą i będą się zdarzać {#errors-can-and-will-happen}

My, programiści, mamy nieodłączną pokusę, by lekceważyć fakt, że błędy mogą się
zdarzyć. W rezultacie projektujemy i testujemy oprogramowanie, biorąc pod uwagę
tylko idealny scenariusz.

Swift, jego system typów i dobrze zaprojektowany kod mogą pomóc w zapobieganiu
niektórym błędom, ale nie wszystkim, ponieważ niektóre z nich są poza naszą
kontrolą. Nie możemy zakładać, że użytkownik zawsze będzie miał połączenie z
Internetem lub że polecenia systemowe zwrócą pomyślnie wynik. Środowiska, w
których działa Tuist, nie są piaskownicami, które kontrolujemy, dlatego musimy
starać się zrozumieć, w jaki sposób mogą się one zmieniać i wpływać na Tuist.

Źle obsługiwane błędy skutkują złym doświadczeniem użytkownika, a użytkownicy
mogą stracić zaufanie do projektu. Chcemy, aby użytkownicy cieszyli się każdym
elementem Tuist, nawet sposobem, w jaki prezentujemy im błędy.

Powinniśmy postawić się w sytuacji użytkowników i wyobrazić sobie, czego
oczekujemy od błędu. Jeśli język programowania jest kanałem komunikacyjnym,
przez który rozprzestrzeniają się błędy, a użytkownicy są miejscem docelowym
błędów, powinny one być napisane w tym samym języku, w którym mówią docelowi
(użytkownicy). Powinny one zawierać wystarczającą ilość informacji, aby
wiedzieć, co się stało i ukrywać informacje, które nie są istotne. Powinny być
również wykonalne, informując użytkowników, jakie kroki mogą podjąć, aby je
naprawić.

I wreszcie, co nie mniej ważne, nasze przypadki testowe powinny uwzględniać
scenariusze niepowodzenia. Nie tylko zapewniają one, że radzimy sobie z błędami
tak, jak powinniśmy, ale także uniemożliwiają przyszłym programistom złamanie
tej logiki.
