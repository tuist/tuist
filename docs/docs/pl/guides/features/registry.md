---
{
  "title": "Registry",
  "titleTemplate": ":title · Features · Guides · Tuist",
  "description": "Optimize your Swift package resolution times by leveraging the Tuist Registry."
}
---
# Rejestr {#registry}

Wraz ze wzrostem liczby zależności rośnie czas ich rozwiązywania. Podczas gdy
inne menedżery pakietów, takie jak [CocoaPods](https://cocoapods.org/) lub
[npm](https://www.npmjs.com/) są scentralizowane, Swift Package Manager nie
jest. Z tego powodu SwiftPM musi rozwiązywać zależności poprzez głębokie
klonowanie każdego repozytorium, co może być czasochłonne i zajmuje więcej
pamięci niż podejście scentralizowane. Aby temu zaradzić, Tuist zapewnia
implementację [Rejestru
pakietów](https://github.com/swiftlang/swift-package-manager/blob/main/Documentation/PackageRegistry/PackageRegistryUsage.md),
dzięki czemu można pobrać tylko te zatwierdzenia, których _faktycznie
potrzebujesz_. Pakiety w rejestrze są oparte na [Swift Package
Index](https://swiftpackageindex.com/). - jeśli można tam znaleźć pakiet, jest
on również dostępny w rejestrze Tuist. Ponadto pakiety są dystrybuowane na całym
świecie przy użyciu pamięci masowej typu edge storage w celu zminimalizowania
opóźnień podczas ich rozwiązywania.

## Użycie {#usage}

Aby skonfigurować rejestr, uruchom następujące polecenie w katalogu projektu:

```bash
tuist registry setup
```

To polecenie generuje plik konfiguracyjny rejestru, który włącza rejestr dla
projektu. Upewnij się, że plik ten został zatwierdzony, aby Twój zespół również
mógł korzystać z rejestru.

### Uwierzytelnianie (opcjonalne) {#authentication}

Uwierzytelnianie jest **opcjonalne**. Bez uwierzytelniania można korzystać z
rejestru z limitem szybkości **1000 żądań na minutę** na adres IP. Aby uzyskać
wyższy limit szybkości, wynoszący **20 000 żądań na minutę**, można
uwierzytelnić się, uruchamiając:

```bash
tuist registry login
```

:: info
<!-- -->
Uwierzytelnianie wymaga konta
<LocalizedLink href="/guides/server/accounts-and-projects">Tuist i projektu</LocalizedLink>.
<!-- -->
:::

### Rozwiązywanie zależności {#resolving-dependencies}

Aby rozwiązać zależności z rejestru zamiast z kontroli źródła, kontynuuj
czytanie w oparciu o konfigurację projektu:
- <LocalizedLink href="/guides/features/registry/xcode-project">Projekt Xcode</LocalizedLink>
- <LocalizedLink href="/guides/features/registry/generated-project">Wygenerowany projekt z integracją pakietu Xcode</LocalizedLink>
- <LocalizedLink href="/guides/features/registry/xcodeproj-integration">Wygenerowany projekt z integracją pakietów opartą na XcodeProj</LocalizedLink>
- <LocalizedLink href="/guides/features/registry/swift-package">Paczka Swift</LocalizedLink>

Aby skonfigurować rejestr na CI, postępuj zgodnie z tym przewodnikiem:
<LocalizedLink href="/guides/features/registry/continuous-integration">Ciągła integracja</LocalizedLink>.

### Identyfikatory rejestru pakietów {#package-registry-identifiers}

W przypadku korzystania z identyfikatorów rejestru pakietów w pliku
`Package.swift` lub `Project.swift` należy przekonwertować adres URL pakietu na
konwencję rejestru. Identyfikator rejestru ma zawsze postać
`{organization}.{repository}`. Na przykład, aby użyć rejestru dla pakietu
`https://github.com/pointfreeco/swift-composable-architecture`, identyfikatorem
rejestru pakietu będzie `pointfreeco.swift-composable-architecture`.

:: info
<!-- -->
Identyfikator nie może zawierać więcej niż jedną kropkę. Jeśli nazwa
repozytorium zawiera kropkę, jest ona zastępowana podkreśleniem. Na przykład
pakiet `https://github.com/groue/GRDB.swift` miałby identyfikator rejestru
`groue.GRDB_swift`.
<!-- -->
:::
