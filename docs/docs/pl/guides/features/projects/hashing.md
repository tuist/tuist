---
{
  "title": "Hashing",
  "titleTemplate": ":title · Projects · Features · Guides · Tuist",
  "description": "Learn about Tuist's hashing logic upon which features like binary caching and selective testing are built."
}
---
# Hashing {#hashing}

Funkcje takie jak
<LocalizedLink href="/guides/features/cache">caching</LocalizedLink> lub
selektywne wykonywanie testów wymagają sposobu na określenie, czy cel uległ
zmianie. Tuist oblicza skrót dla każdego celu w grafie zależności, aby określić,
czy cel został zmieniony. Hash jest obliczany na podstawie następujących
atrybutów:

- Atrybuty celu (np. nazwa, platforma, produkt itp.).
- Pliki celu
- Skrót zależności celu

### Atrybuty pamięci podręcznej {#cache-attributes}

Dodatkowo, obliczając hash dla
<LocalizedLink href="/guides/features/cache">caching</LocalizedLink>, hashujemy
również następujące atrybuty.

#### Wersja Swift {#swift-version}

Skracamy wersję Swift uzyskaną po uruchomieniu polecenia `/usr/bin/xcrun swift
--version`, aby zapobiec błędom kompilacji spowodowanym niezgodnością wersji
Swift między celami a plikami binarnymi.

::: info STABILNOŚĆ MODUŁU
<!-- -->
Poprzednie wersje buforowania binarnego opierały się na ustawieniu kompilacji
`BUILD_LIBRARY_FOR_DISTRIBUTION`, aby włączyć [stabilność
modułu](https://www.swift.org/blog/library-evolution#enabling-library-evolution-support)
i umożliwić korzystanie z plików binarnych z dowolną wersją kompilatora.
Powodowało to jednak problemy z kompilacją w projektach z celami, które nie
obsługują stabilności modułów. Wygenerowane pliki binarne są powiązane z wersją
Swift użytą do ich kompilacji, a wersja Swift musi być zgodna z wersją użytą do
kompilacji projektu.
<!-- -->
:::

#### Konfiguracja {#configuration}

Ideą flagi `-configuration` było zapewnienie, że pliki binarne debugowania nie
będą używane w kompilacjach wydania i odwrotnie. Nadal jednak brakuje nam
mechanizmu usuwania innych konfiguracji z projektów, aby zapobiec ich użyciu.

## Debugowanie {#debugging}

Jeśli zauważysz niedeterministyczne zachowanie podczas korzystania z buforowania
w różnych środowiskach lub wywołaniach, może to być związane z różnicami między
środowiskami lub błędem w logice mieszania. Zalecamy wykonanie poniższych kroków
w celu debugowania problemu:

1. Uruchom `tuist hash cache` lub `tuist hash selective-testing` (hashe dla
   <LocalizedLink href="/guides/features/cache">binary caching</LocalizedLink>
   lub <LocalizedLink href="/guides/features/selective-testing">selective testing</LocalizedLink>), skopiuj hashe, zmień nazwę katalogu projektu i
   uruchom polecenie ponownie. Skróty powinny się zgadzać.
2. Jeśli skróty nie są zgodne, prawdopodobnie wygenerowany projekt zależy od
   środowiska. Uruchom `tuist graph --format json` w obu przypadkach i porównaj
   wykresy. Alternatywnie, wygeneruj projekty i porównaj ich pliki
   `project.pbxproj` za pomocą narzędzia do porównywania, takiego jak
   [Diffchecker](https://www.diffchecker.com).
3. Jeśli skróty są takie same, ale różnią się w różnych środowiskach (na
   przykład CI i lokalnym), upewnij się, że wszędzie używana jest ta sama
   [konfiguracja](#configuration) i [wersja Swift](#swift-version). Wersja Swift
   jest powiązana z wersją Xcode, więc upewnij się, że wersje Xcode są zgodne.

Jeśli hashe nadal są niedeterministyczne, daj nam znać, a my pomożemy w
debugowaniu.


::: info PLANOWANE LEPSZE DOŚWIADCZENIE DEBUGOWANIA
<!-- -->
Ulepszenie naszego doświadczenia w debugowaniu jest na naszej mapie drogowej.
Polecenie print-hashes, któremu brakuje kontekstu do zrozumienia różnic,
zostanie zastąpione bardziej przyjaznym dla użytkownika poleceniem, które
wykorzystuje strukturę podobną do drzewa, aby pokazać różnice między hashami.
<!-- -->
:::
