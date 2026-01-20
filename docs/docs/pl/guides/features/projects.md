---
{
  "title": "Projects",
  "titleTemplate": ":title · Features · Guides · Tuist",
  "description": "Learn about Tuist's DSL for defining Xcode projects."
}
---
# Wygenerowane projekty {#generated-projects}

Generated to realna alternatywa, która pomaga sprostać tym wyzwaniom,
jednocześnie utrzymując złożoność i koszty na akceptowalnym poziomie. Traktuje
projekty Xcode jako podstawowy element, zapewniając odporność na przyszłe
aktualizacje Xcode i wykorzystuje generowanie projektów Xcode, aby zapewnić
zespołom deklaratywny interfejs API skoncentrowany na modularyzacji. Tuist
wykorzystuje deklarację projektu, aby uprościć złożoność modularyzacji**,
zoptymalizować przepływy pracy, takie jak kompilacja lub testowanie w różnych
środowiskach, a także ułatwić i zdemokratyzować ewolucję projektów Xcode.

## Jak to działa? {#how-does-it-work}

Aby rozpocząć pracę z wygenerowanymi projektami, wystarczy zdefiniować swój
projekt przy użyciu **Tuist's Domain Specific Language (DSL)**. Wymaga to użycia
plików manifestu, takich jak `Workspace.swift` lub `Project.swift`. Jeśli
wcześniej pracowałeś z menedżerem pakietów Swift, podejście jest bardzo podobne.

Po zdefiniowaniu projektu Tuist oferuje różne przepływy pracy do zarządzania nim
i interakcji z nim:

- **Generuj:** Jest to podstawowy przepływ pracy. Użyj go, aby utworzyć projekt
  Xcode, który jest kompatybilny z Xcode.
- **<LocalizedLink href="/guides/features/build">Build</LocalizedLink>:** Ten
  przepływ pracy nie tylko generuje projekt Xcode, ale także wykorzystuje
  `xcodebuild` do jego kompilacji.
- **<LocalizedLink href="/guides/features/test">Test</LocalizedLink>:** Działa
  podobnie do przepływu kompilacji, nie tylko generuje projekt Xcode, ale
  wykorzystuje `xcodebuild` do jego przetestowania.

## Wyzwania związane z projektami Xcode {#challenges-with-xcode-projects}

Wraz z rozwojem projektów Xcode, organizacje **mogą stanąć w obliczu spadku
produktywności** z powodu kilku czynników, w tym niewiarygodnych kompilacji
przyrostowych, częstego czyszczenia globalnej pamięci podręcznej Xcode przez
programistów napotykających problemy i niestabilnych konfiguracji projektu. Aby
utrzymać szybki rozwój funkcji, organizacje zazwyczaj badają różne strategie.

Niektóre organizacje decydują się na ominięcie kompilatora poprzez abstrakcję
platformy przy użyciu dynamicznych środowisk uruchomieniowych opartych na
JavaScript, takich jak [React Native](https://reactnative.dev/). Chociaż
podejście to może być skuteczne, [komplikuje dostęp do natywnych funkcji
platformy](https://shopify.engineering/building-app-clip-react-native). Inne
organizacje decydują się na **modularyzację bazy kodu**, która pomaga ustalić
wyraźne granice, ułatwiając pracę z bazą kodu i poprawiając niezawodność czasu
kompilacji. Jednak format projektu Xcode nie został zaprojektowany z myślą o
modułowości i skutkuje niejawnymi konfiguracjami, które niewielu rozumie i
częstymi konfliktami. Prowadzi to do złego współczynnika magistrali i chociaż
przyrostowe kompilacje mogą się poprawić, programiści mogą nadal często czyścić
pamięć podręczną kompilacji Xcode (tj. dane pochodne), gdy kompilacje się nie
powiodą. Aby temu zaradzić, niektóre organizacje decydują się **porzucić system
kompilacji Xcode** i przyjąć alternatywy, takie jak [Buck](https://buck.build/)
lub [Bazel](https://bazel.build/). Wiąże się to jednak z [dużą złożonością i
obciążeniem konserwacyjnym](https://bazel.build/migrate/xcode).


## Alternatywy {#alternatywy}

### Menedżer pakietów Swift {#swift-package-manager}.

Podczas gdy Swift Package Manager (SPM) koncentruje się głównie na
zależnościach, Tuist oferuje inne podejście. W Tuist nie tylko definiujesz
pakiety do integracji z SPM; kształtujesz swoje projekty przy użyciu znanych
pojęć, takich jak projekty, obszary robocze, cele i schematy.

### XcodeGen {#xcodegen}

[XcodeGen](https://github.com/yonaskolb/XcodeGen) to dedykowany generator
projektów zaprojektowany w celu zmniejszenia konfliktów we współpracujących
projektach Xcode i uproszczenia niektórych zawiłości wewnętrznego działania
Xcode. Projekty są jednak definiowane przy użyciu formatów serializowalnych,
takich jak [YAML](https://yaml.org/). W przeciwieństwie do języka Swift, nie
pozwala to programistom na budowanie abstrakcji lub kontroli bez włączania
dodatkowych narzędzi. Chociaż XcodeGen oferuje sposób mapowania zależności na
wewnętrzną reprezentację w celu walidacji i optymalizacji, nadal naraża
programistów na niuanse Xcode. Może to sprawić, że XcodeGen będzie odpowiednim
fundamentem dla [narzędzi do
budowania](https://github.com/MobileNativeFoundation/rules_xcodeproj), jak widać
w społeczności Bazel, ale nie jest optymalny dla integracyjnej ewolucji
projektu, która ma na celu utrzymanie zdrowego i produktywnego środowiska.

### Bazel {#bazel}

[Bazel](https://bazel.build) to zaawansowany system kompilacji znany z funkcji
zdalnego buforowania, który zyskał popularność w społeczności Swift głównie
dzięki tej możliwości. Biorąc jednak pod uwagę ograniczoną rozszerzalność Xcode
i jego systemu kompilacji, zastąpienie go systemem Bazel wymaga znacznego
wysiłku i konserwacji. Tylko kilka firm z dużymi zasobami jest w stanie
udźwignąć te koszty, o czym świadczy wybrana lista firm inwestujących znaczne
środki w integrację Bazel z Xcode. Co ciekawe, społeczność stworzyła
[narzędzie](https://github.com/MobileNativeFoundation/rules_xcodeproj), które
wykorzystuje Bazel's XcodeGen do generowania projektu Xcode. Skutkuje to zawiłym
łańcuchem konwersji: od plików Bazel do XcodeGen YAML i wreszcie do projektów
Xcode. Takie warstwowe pośrednictwo często komplikuje rozwiązywanie problemów,
utrudniając ich diagnozowanie i rozwiązywanie.
