---
{
  "title": "Authentication",
  "titleTemplate": ":title | Server | Guides | Tuist",
  "description": "Learn how to authenticate with the Tuist server from the CLI."
}
---
# Uwierzytelnianie {#authentication}

Aby nawiązać połączenie z serwerem, CLI musi uwierzytelnić żądania za pomocą
[uwierzytelniania
nosiciela](https://swagger.io/docs/specification/authentication/bearer-authentication/).
CLI obsługuje uwierzytelnianie jako użytkownik, jako konto lub za pomocą tokenu
OIDC.

## Jako użytkownik {#as-a-user}

W przypadku korzystania z CLI lokalnie na komputerze zalecamy uwierzytelnianie
jako użytkownik. Aby uwierzytelnić się jako użytkownik, należy uruchomić
następujące polecenie:

```bash
tuist auth login
```

Polecenie przeprowadzi Cię przez proces uwierzytelniania internetowego. Po
uwierzytelnieniu CLI zapisze długotrwały token odświeżania i krótkotrwały token
dostępu w katalogu `~/.config/tuist/credentials`. Każdy plik w katalogu
reprezentuje domenę, w której przeprowadzono uwierzytelnianie, która domyślnie
powinna być `tuist.dev.json`. Informacje przechowywane w tym katalogu są poufne,
więc **należy je przechowywać w bezpiecznym miejscu**.

CLI automatycznie wyszuka poświadczenia podczas wysyłania żądań do serwera.
Jeśli token dostępu wygasł, CLI użyje tokenu odświeżającego, aby uzyskać nowy
token dostępu.

## Tokeny OIDC {#oidc-tokens}

W środowiskach CI obsługujących OpenID Connect (OIDC) Tuist może automatycznie
uwierzytelniać użytkowników bez konieczności zarządzania długotrwałymi
sekretami. Podczas działania w obsługiwanym środowisku CI interfejs CLI
automatycznie wykrywa dostawcę tokenów OIDC i wymienia token dostarczony przez
CI na token dostępu Tuist.

### Obsługiwani dostawcy CI {#supported-ci-providers}

- GitHub Actions
- CircleCI
- Bitrise

### Konfiguracja uwierzytelniania OIDC {#setting-up-oidc-authentication}

1. **Połącz swoje repozytorium z Tuist**: Postępuj zgodnie z
   <LocalizedLink href="/guides/integrations/gitforge/github">instrukcją
   integracji GitHub</LocalizedLink>, aby połączyć swoje repozytorium GitHub z
   projektem Tuist.

2. **Uruchom `tuist auth login`**: W swoim przepływie pracy CI uruchom `tuist
   auth login` przed wykonaniem jakichkolwiek poleceń wymagających
   uwierzytelnienia. CLI automatycznie wykryje środowisko CI i przeprowadzi
   uwierzytelnienie przy użyciu OIDC.

Przykłady konfiguracji specyficznej dla dostawcy można znaleźć w
<LocalizedLink href="/guides/integrations/continuous-integration">przewodniku
dotyczącym ciągłej integracji</LocalizedLink>.

### Zakresy tokenów OIDC {#oidc-token-scopes}

Tokeny OIDC otrzymują grupę zakresu `ci`, która zapewnia dostęp do wszystkich
projektów połączonych z repozytorium. Szczegółowe informacje na temat zakresu
`ci` można znaleźć w sekcji [Grupy zakresów](#scope-groups).

::: tip SECURITY BENEFITS
<!-- -->
Uwierzytelnianie OIDC jest bezpieczniejsze niż tokeny długotrwałe, ponieważ:
- Nie ma żadnych sekretów dotyczących obracania lub zarządzania
- Tokeny są krótkotrwałe i mają zakres ograniczony do poszczególnych przebiegów
  przepływu pracy.
- Uwierzytelnianie jest powiązane z tożsamością repozytorium.
<!-- -->
:::

## Tokeny konta {#account-tokens}

W środowiskach CI, które nie obsługują OIDC, lub gdy potrzebna jest precyzyjna
kontrola uprawnień, można użyć tokenów konta. Tokeny konta pozwalają dokładnie
określić, do jakich zakresów i projektów token ma dostęp.

### Tworzenie tokenu konta {#creating-an-account-token}

```bash
tuist account tokens create my-account \
  --scopes project:cache:read project:cache:write \
  --name ci-cache-token \
  --expires 1y
```

Polecenie akceptuje następujące opcje:

| Opcja        | Opis                                                                                                                                                                          |
| ------------ | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `--scopes`   | Wymagane. Lista zakresów, którym należy przyznać token, oddzielonych przecinkami.                                                                                             |
| `--name`     | Wymagane. Unikalny identyfikator tokenu (1–32 znaki, tylko litery, cyfry, myślniki i znaki podkreślenia).                                                                     |
| `--expires`  | Opcjonalnie. Kiedy token powinien wygasnąć. Użyj formatu takiego jak `30d` (dni), `6m` (miesiące) lub `1y` (lata). Jeśli nie zostanie to określone, token nigdy nie wygaśnie. |
| `--projekty` | Ogranicz token do określonych uchwytów projektu. Jeśli nie zostanie to określone, token ma dostęp do wszystkich projektów.                                                    |

### Dostępne zakresy {#available-scopes}

| Zakres                   | Opis                                           |
| ------------------------ | ---------------------------------------------- |
| `account:members:read`   | Przeczytaj członków konta                      |
| `account:members:write`  | Zarządzaj członkami konta                      |
| `account:registry:read`  | Przeczytaj z rejestru pakietów Swift.          |
| `account:registry:write` | Opublikuj w rejestrze pakietów Swift.          |
| `project:previews:read`  | Pobierz podglądy                               |
| `project:previews:write` | Prześlij podgląd                               |
| `project:admin:read`     | Przeczytaj ustawienia projektu                 |
| `project:admin:write`    | Zarządzaj ustawieniami projektu                |
| `project:cache:read`     | Pobierz pliki binarne z pamięci podręcznej     |
| `project:cache:write`    | Prześlij zbuforowane pliki binarne             |
| `project:bundles:read`   | Wyświetl pakiety                               |
| `project:bundles:write`  | Prześlij pakiety                               |
| `project:tests:read`     | Przeczytaj wyniki testu                        |
| `project:tests:write`    | Prześlij wyniki testu                          |
| `project:builds:read`    | Przeczytaj analizę kompilacji                  |
| `project:builds:write`   | Prześlij dane analityczne dotyczące kompilacji |
| `project:runs:read`      | Uruchom polecenie read.                        |
| `project:runs:write`     | Utwórz i zaktualizuj polecenie uruchamiania    |

### Grupy zakresu {#scope-groups}

Grupy zakresów zapewniają wygodny sposób przyznawania wielu powiązanych zakresów
za pomocą jednego identyfikatora. Kiedy używasz grupy zakresów, automatycznie
rozszerza się ona, aby objąć wszystkie zawarte w niej indywidualne zakresy.

| Grupa zakresu | Zakresy objęte                                                                                                                                |
| ------------- | --------------------------------------------------------------------------------------------------------------------------------------------- |
| `ci`          | `project:cache:write`, `project:previews:write`, `project:bundles:write`, `project:tests:write`, `project:builds:write`, `project:runs:write` |

### Ciągła integracja {#continuous-integration}

W środowiskach CI, które nie obsługują OIDC, można utworzyć token konta z grupą
zakresów `ci` w celu uwierzytelnienia przepływów pracy CI:

```bash
tuist account tokens create my-account --scopes ci --name ci
```

Tworzy to token z wszystkimi zakresami potrzebnymi do typowych operacji CI
(pamięć podręczna, podglądy, pakiety, testy, kompilacje i uruchomienia).
Przechowuj wygenerowany token jako sekret w swoim środowisku CI i ustaw go jako
zmienną środowiskową `TUIST_TOKEN`.

### Zarządzanie tokenami konta {#managing-account-tokens}

Aby wyświetlić listę wszystkich tokenów dla konta:

```bash
tuist account tokens list my-account
```

Aby cofnąć token według nazwy:

```bash
tuist account tokens revoke my-account ci-cache-token
```

### Korzystanie z tokenów konta {#using-account-tokens}

Tokeny kont powinny być zdefiniowane jako zmienne środowiskowe `TUIST_TOKEN`:

```bash
export TUIST_TOKEN=your-account-token
```

::: tip WHEN TO USE ACCOUNT TOKENS
<!-- -->
Używaj tokenów konta, gdy jest to konieczne:
- Uwierzytelnianie w środowiskach CI, które nie obsługują OIDC
- Precyzyjna kontrola nad operacjami, które może wykonywać token
- Token umożliwiający dostęp do wielu projektów w ramach jednego konta
- Tokeny ograniczone czasowo, które automatycznie wygasają
<!-- -->
:::
