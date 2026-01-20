---
{
  "title": "Authentication",
  "titleTemplate": ":title | Server | Guides | Tuist",
  "description": "Learn how to authenticate with the Tuist server from the CLI."
}
---
# Uwierzytelnianie {#authentication}

Aby wejść w interakcję z serwerem, CLI musi uwierzytelnić żądania za pomocą
[uwierzytelniania na
okaziciela](https://swagger.io/docs/specification/authentication/bearer-authentication/).
CLI obsługuje uwierzytelnianie jako użytkownik, jako konto lub przy użyciu
tokena OIDC.

## Jako użytkownik {#as-a-user}

W przypadku korzystania z interfejsu CLI lokalnie na komputerze zalecamy
uwierzytelnienie jako użytkownik. Aby uwierzytelnić się jako użytkownik, należy
uruchomić następujące polecenie:

```bash
tuist auth login
```

Polecenie przeprowadzi użytkownika przez proces uwierzytelniania internetowego.
Po uwierzytelnieniu CLI będzie przechowywać długotrwały token odświeżania i
krótkotrwały token dostępu pod adresem `~/.config/tuist/credentials`. Każdy plik
w katalogu reprezentuje domenę, w której dokonano uwierzytelnienia, co domyślnie
powinno mieć postać `tuist.dev.json`. Informacje przechowywane w tym katalogu są
wrażliwe, więc **upewnij się, że są bezpieczne**.

CLI automatycznie wyszuka poświadczenia podczas wykonywania żądań do serwera.
Jeśli token dostępu wygasł, CLI użyje tokenu odświeżania, aby uzyskać nowy token
dostępu.

## Tokeny OIDC {#oidc-tokens}

W przypadku środowisk CI, które obsługują OpenID Connect (OIDC), Tuist może
uwierzytelniać się automatycznie, bez konieczności zarządzania długotrwałymi
sekretami. Po uruchomieniu w obsługiwanym środowisku CI, CLI automatycznie
wykryje dostawcę tokenów OIDC i wymieni token dostarczony przez CI na token
dostępu Tuist.

### Wspierani dostawcy usług CI {#supported-ci-providers}

- Działania GitHub
- CircleCI
- Bitrise

### Konfigurowanie uwierzytelniania OIDC {#setting-up-oidc-authentication}

1. **Połącz swoje repozytorium z Tuist**: Postępuj zgodnie z
   <LocalizedLink href="/guides/integrations/gitforge/github"> przewodnikiem integracji GitHub</LocalizedLink>, aby połączyć swoje repozytorium GitHub z
   projektem Tuist.

2. **Uruchom `tuist auth login`**: W przepływie pracy CI należy uruchomić `tuist
   auth login` przed poleceniami wymagającymi uwierzytelnienia. Interfejs CLI
   automatycznie wykryje środowisko CI i uwierzytelni się przy użyciu OIDC.

Przykłady konfiguracji dla poszczególnych dostawców można znaleźć w przewodniku
<LocalizedLink href="/guides/integrations/continuous-integration">Continuous Integration</LocalizedLink>.

### Zakresy tokenów OIDC {#oidc-token-scopes}

Tokenom OIDC przyznawana jest grupa `ci` scope, która zapewnia dostęp do
wszystkich projektów połączonych z repozytorium. Zobacz [Grupy
zakresów](#scope-groups) by dowiedzieć się więcej o tym, co zawiera zakres `ci`.

::: tip SECURITY BENEFITS
<!-- -->
Uwierzytelnianie OIDC jest bezpieczniejsze niż długotrwałe tokeny, ponieważ
- Brak sekretów do rotacji lub zarządzania
- Tokeny są krótkotrwałe i przypisane do poszczególnych przepływów pracy
- Uwierzytelnianie jest powiązane z tożsamością repozytorium.
<!-- -->
:::

## Tokeny konta {#account-tokens}

W przypadku środowisk ciągłej integracji, które nie obsługują OIDC, lub gdy
potrzebna jest precyzyjna kontrola nad uprawnieniami, można użyć tokenów kont.
Tokeny kont umożliwiają dokładne określenie zakresów i projektów, do których
token może uzyskać dostęp.

### Tworzenie tokenu konta {#creating-an-account-token}

```bash
tuist account tokens create my-account \
  --scopes project:cache:read project:cache:write \
  --name ci-cache-token \
  --expires 1y
```

Polecenie akceptuje następujące opcje:

| Opcja        | Opis                                                                                                                                                                       |
| ------------ | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `--zakresy`  | Wymagane. Oddzielona przecinkami lista zakresów, w których ma zostać przyznany token.                                                                                      |
| `--name`     | Wymagane. Unikalny identyfikator tokena (1-32 znaki, wyłącznie alfanumeryczne, myślniki i podkreślniki).                                                                   |
| `--wygasa`   | Opcjonalnie. Kiedy token powinien wygasnąć. Użyj formatu takiego jak `30d` (dni), `6m` (miesiące) lub `1y` (lata). Jeśli nie zostanie określony, token nigdy nie wygaśnie. |
| `--projekty` | Ogranicza token do określonych uchwytów projektów. Jeśli nie określono inaczej, token ma dostęp do wszystkich projektów.                                                   |

### Dostępne zakresy {#available-scopes}

| Zakres                   | Opis                                          |
| ------------------------ | --------------------------------------------- |
| `account:members:read`   | Przeczytaj członków konta                     |
| `account:members:write`  | Zarządzanie członkami konta                   |
| `account:registry:read`  | Odczyt z rejestru pakietów Swift              |
| `account:registry:write` | Publikowanie w rejestrze pakietów Swift       |
| `project:previews:read`  | Pobieranie podglądów                          |
| `project:previews:write` | Przesyłanie podglądów                         |
| `project:admin:read`     | Odczyt ustawień projektu                      |
| `project:admin:write`    | Zarządzanie ustawieniami projektu             |
| `project:cache:read`     | Pobieranie buforowanych plików binarnych      |
| `project:cache:write`    | Przesyłanie buforowanych plików binarnych     |
| `project:bundles:read`   | Wyświetl pakiety                              |
| `project:bundles:write`  | Przesyłanie pakietów                          |
| `project:tests:read`     | Odczyt wyników testu                          |
| `project:tests:write`    | Prześlij wyniki testu                         |
| `project:builds:read`    | Czytaj analizy kompilacji                     |
| `project:builds:write`   | Prześlij dane analityczne kompilacji          |
| `project:runs:read`      | Uruchomione polecenie odczytu                 |
| `project:runs:write`     | Tworzenie i aktualizowanie przebiegów poleceń |

### Grupy zakresów {#scope-groups}

Grupy zakresów zapewniają wygodny sposób przyznawania wielu powiązanych zakresów
za pomocą jednego identyfikatora. Gdy używasz grupy zakresów, automatycznie
rozszerza się ona, aby objąć wszystkie indywidualne zakresy, które zawiera.

| Grupa Scope | Dołączone lunety                                                                                                                              |
| ----------- | --------------------------------------------------------------------------------------------------------------------------------------------- |
| `ci`        | `project:cache:write`, `project:previews:write`, `project:bundles:write`, `project:tests:write`, `project:builds:write`, `project:runs:write` |

### Ciągła integracja {#continuous-integration}

W przypadku środowisk ciągłej integracji, które nie obsługują OIDC, można
utworzyć token konta z grupą zakresu `ci` w celu uwierzytelnienia przepływów
pracy ciągłej integracji:

```bash
tuist account tokens create my-account --scopes ci --name ci
```

Spowoduje to utworzenie tokenu ze wszystkimi zakresami potrzebnymi do typowych
operacji CI (pamięć podręczna, podglądy, pakiety, testy, kompilacje i
uruchomienia). Wygenerowany token należy przechowywać jako sekret w środowisku
CI i ustawić go jako zmienną środowiskową `TUIST_TOKEN`.

### Zarządzanie tokenami konta {#managing-account-tokens}

Aby wyświetlić listę wszystkich tokenów dla konta:

```bash
tuist account tokens list my-account
```

Aby odwołać token według nazwy:

```bash
tuist account tokens revoke my-account ci-cache-token
```

### Korzystanie z tokenów konta {#using-account-tokens}

Tokeny konta powinny być zdefiniowane jako zmienna środowiskowa `TUIST_TOKEN`:

```bash
export TUIST_TOKEN=your-account-token
```

::: tip WHEN TO USE ACCOUNT TOKENS
<!-- -->
Korzystaj z tokenów konta, gdy tego potrzebujesz:
- Uwierzytelnianie w środowiskach CI, które nie obsługują OIDC
- Szczegółowa kontrola nad tym, jakie operacje może wykonywać token
- Token umożliwiający dostęp do wielu projektów w ramach konta
- Ograniczone czasowo tokeny, które automatycznie wygasają
<!-- -->
:::
