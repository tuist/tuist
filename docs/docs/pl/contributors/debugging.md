---
{
  "title": "Debugging",
  "titleTemplate": ":title · Contributors · Tuist",
  "description": "Use coding agents and local runs to debug issues in Tuist."
}
---
# Debugowanie {#debugging}

Otwartość ma praktyczną zaletę: kod jest dostępny, można go uruchomić lokalnie i
można używać agentów kodujących, aby szybciej odpowiadać na pytania i debugować
potencjalne błędy w kodzie źródłowym.

Jeśli podczas debugowania znajdziesz brakującą lub niekompletną dokumentację,
zaktualizuj angielską dokumentację pod adresem `docs/` i otwórz PR.

## Używaj agentów kodujących. {#use-coding-agents}

Agenci kodujący są przydatni w następujących przypadkach:

- Skanowanie kodu źródłowego w celu znalezienia miejsca, w którym
  zaimplementowano dane zachowanie.
- Odtwarzanie problemów lokalnie i szybkie powtarzanie.
- Śledzenie przepływu danych wejściowych przez Tuist w celu znalezienia
  przyczyny źródłowej.

Podaj jak najmniejszy fragment kodu i wskaż agentowi konkretny komponent (CLI,
serwer, pamięć podręczna, dokumentacja lub podręcznik). Im bardziej konkretny
zakres, tym szybszy i dokładniejszy proces debugowania.

### Często potrzebne podpowiedzi (FNP) {#frequently-needed-prompts}

#### Nieoczekiwane generowanie projektu {#unexpected-project-generation}

Generowanie projektu daje mi coś, czego się nie spodziewałem. Uruchom Tuist CLI
dla mojego projektu pod adresem `/path/to/project`, aby zrozumieć, dlaczego tak
się dzieje. Prześledź potok generatora i wskaż ścieżki kodu odpowiedzialne za
wynik.

#### Powtarzalny błąd w wygenerowanych projektach {#reproducible-bug-in-generated-projects}

Wygląda to na błąd w generowanych projektach. Utwórz projekt, który można
odtworzyć, w folderze `examples/`, korzystając z istniejących przykładów jako
odniesienia. Dodaj test akceptacyjny, który zakończy się niepowodzeniem, uruchom
go za pomocą `xcodebuild`, wybierając tylko ten test, napraw problem, ponownie
uruchom test, aby potwierdzić, że zakończył się powodzeniem, i otwórz PR.
