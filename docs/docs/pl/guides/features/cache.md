---
{
  "title": "Cache",
  "titleTemplate": ":title · Features · Guides · Tuist",
  "description": "Optimize your build times with Tuist Cache."
}
---
# Pamięć podręczna {#cache}

System kompilacji Xcode zapewnia [przyrostowe
kompilacje](https://en.wikipedia.org/wiki/Incremental_build_model), zwiększając
wydajność na pojedynczej maszynie. Artefakty kompilacji nie są jednak
udostępniane w różnych środowiskach, co zmusza do ciągłego przebudowywania tego
samego kodu - zarówno w środowiskach [ciągłej integracji
(CI)](https://en.wikipedia.org/wiki/Continuous_integration), jak i lokalnych
środowiskach programistycznych (komputer Mac).

Tuist odpowiada na te wyzwania dzięki funkcji buforowania, znacznie skracając
czas kompilacji zarówno w lokalnych środowiskach programistycznych, jak i
środowiskach CI. Takie podejście nie tylko przyspiesza pętle sprzężenia
zwrotnego, ale także minimalizuje potrzebę przełączania kontekstu, ostatecznie
zwiększając produktywność.

Oferujemy dwa rodzaje buforowania:
- <LocalizedLink href="/guides/features/cache/module-cache">Buforowanie modułu</LocalizedLink>
- <LocalizedLink href="/guides/features/cache/xcode-cache">Buforowanie Xcode</LocalizedLink>

## Pamięć podręczna modułów {#module-cache}

W przypadku projektów korzystających z funkcji generowania
<LocalizedLink href="/guides/features/projects">projektów</LocalizedLink> Tuist,
zapewniamy potężny system buforowania, który buforuje poszczególne moduły jako
pliki binarne i udostępnia je w całym zespole i środowiskach CI.

Chociaż można również korzystać z nowej pamięci podręcznej Xcode, funkcja ta
jest obecnie zoptymalizowana pod kątem lokalnych kompilacji i prawdopodobnie
wskaźnik trafień w pamięci podręcznej będzie niższy niż w przypadku buforowania
wygenerowanego projektu. Decyzja o wyborze rozwiązania do buforowania zależy
jednak od konkretnych potrzeb i preferencji. Można również połączyć oba
rozwiązania buforowania, aby osiągnąć najlepsze wyniki.

<LocalizedLink href="/guides/features/cache/module-cache">Dowiedz się więcej o module pamięci podręcznej →</LocalizedLink>

## Pamięć podręczna Xcode {#xcode-cache}

::: warning XCODE CACHE STATE
<!-- -->
Buforowanie Xcode jest obecnie zoptymalizowane pod kątem lokalnych kompilacji
przyrostowych, a całe spektrum zadań kompilacji nie jest jeszcze niezależne od
ścieżki. Mimo to możesz doświadczyć korzyści, podłączając zdalną pamięć
podręczną Tuist i spodziewamy się, że czasy kompilacji poprawią się z czasem, w
miarę jak możliwości systemu kompilacji będą się poprawiać.
<!-- -->
:::

Apple pracuje nad nowym rozwiązaniem buforowania na poziomie kompilacji,
podobnym do innych systemów kompilacji, takich jak Bazel i Buck. Nowa funkcja
buforowania jest dostępna od Xcode 26, a Tuist płynnie się z nią integruje -
niezależnie od tego, czy korzystasz z funkcji <LocalizedLink href="/guides/features/projects">generowania projektów</LocalizedLink>, czy nie.

<LocalizedLink href="/guides/features/cache/xcode-cache">Dowiedz się więcej o pamięci podręcznej Xcode →</LocalizedLink>
