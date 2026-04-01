---
{
  "title": "Authentication",
  "titleTemplate": ":title | Server | Guides | Tuist",
  "description": "Learn how to authenticate with the Tuist server from the CLI."
}
---
# Uwierzytelnianie {#authentication}

Aby nawiązać komunikację z serwerem, CLI musi uwierzytelnić żądania przy użyciu
[uwierzytelniania
bearer](https://swagger.io/docs/specification/authentication/bearer-authentication/).
CLI obsługuje uwierzytelnianie jako użytkownik, jako konto lub przy użyciu
tokenu OIDC.

## Jako użytkownik {#as-a-user}

Podczas korzystania z CLI lokalnie na swoim komputerze zalecamy uwierzytelnienie
się jako użytkownik. Aby uwierzytelnić się jako użytkownik, należy uruchomić
następujące polecenie:

```bash
tuist auth login
```

Polecenie przeprowadzi Cię przez proces uwierzytelniania w sieci. Po
uwierzytelnieniu CLI zapisze token odświeżający o długim okresie ważności oraz
token dostępu o krótkim okresie ważności w katalogu
`~/.config/tuist/credentials`. Każdy plik w tym katalogu odpowiada domenie, w
której nastąpiło uwierzytelnienie, a domyślnie powinny to być pliki
`tuist.dev.json`. Informacje przechowywane w tym katalogu są poufne, więc
**zadbaj o ich bezpieczeństwo**.

Interfejs CLI automatycznie sprawdzi poświadczenia podczas wysyłania żądań do
serwera. Jeśli token dostępu wygasł, interfejs CLI użyje tokenu odświeżającego,
aby uzyskać nowy token dostępu.

## Tokeny OIDC {#oidc-tokens}

W środowiskach CI obsługujących OpenID Connect (OIDC) Tuist może uwierzytelniać
się automatycznie bez konieczności zarządzania długotrwałymi sekretami. Podczas
działania w obsługiwanym środowisku CI interfejs CLI automatycznie wykryje
dostawcę tokenów OIDC i wymieni token dostarczony przez CI na token dostępu
Tuist.

### Obsługiwani dostawcy CI {#supported-ci-providers}

- GitHub Actions
- CircleCI
- Bitrise

### Konfiguracja uwierzytelniania OIDC {#setting-up-oidc-authentication}

1. **Połącz swoje repozytorium z Tuist**: Postępuj zgodnie z
   <LocalizedLink href="/guides/integrations/gitforge/github">przewodnikiem po
   integracji z GitHubem</LocalizedLink>, aby połączyć swoje repozytorium GitHub
   z projektem Tuist.

2. **Uruchom `tuist auth login`**: W swoim przepływie pracy CI uruchom `tuist
   auth login` przed każdym poleceniem wymagającym uwierzytelnienia. Interfejs
   CLI automatycznie wykryje środowisko CI i uwierzytelni się przy użyciu OIDC.

Przykłady konfiguracji dla poszczególnych dostawców można znaleźć w
<LocalizedLink href="/guides/integrations/continuous-integration">przewodniku po
ciągłej integracji</LocalizedLink>.

### Zakresy tokenów OIDC {#oidc-token-scopes}

Tokenom OIDC przyznawana jest grupa zakresu `ci`, która zapewnia dostęp do
wszystkich projektów powiązanych z repozytorium. Szczegółowe informacje na temat
zakresu `ci` można znaleźć w sekcji [Grupy zakresu](#scope-groups).

::: tip SECURITY BENEFITS
<!-- -->
Uwierzytelnianie OIDC jest bezpieczniejsze niż tokeny długotrwałe, ponieważ:
- Nie ma żadnych tajemnic dotyczących rotacji ani zarządzania
- Tokeny mają krótki czas życia i są ograniczone do poszczególnych przebiegów
  przepływu pracy
- Uwierzytelnianie jest powiązane z tożsamością Twojego repozytorium
<!-- -->
:::

## Tokeny konta {#account-tokens}

W środowiskach CI, które nie obsługują OIDC, lub gdy potrzebujesz precyzyjnej
kontroli nad uprawnieniami, możesz użyć tokenów konta. Tokeny konta pozwalają
dokładnie określić, do jakich zakresów i projektów token ma dostęp.

### Tworzenie tokenu konta {#creating-an-account-token}

```bash
tuist account tokens create my-account \
  --scopes project:cache:read project:cache:write \
  --name ci-cache-token \
  --expires 1y
```

Polecenie akceptuje następujące opcje:

| Opcja        | Opis                                                                                                                                                                  |
| ------------ | --------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `--zakresy`  | Wymagane. Rozdzielona przecinkami lista zakresów, do których należy przyznać token.                                                                                   |
| `--name`     | Wymagane. Unikalny identyfikator tokenu (1–32 znaki, wyłącznie znaki alfanumeryczne, łączniki i podkreślenia).                                                        |
| `--wygasają` | Opcjonalnie. Okres ważności tokenu. Użyj formatu takiego jak `30d` (dni), `6m` (miesiące) lub `1y` (lata). Jeśli nie zostanie to określone, token nigdy nie wygaśnie. |
| `--projekty` | Ogranicz token do określonych identyfikatorów projektów. Jeśli nie zostanie to określone, token ma dostęp do wszystkich projektów.                                    |

### Dostępne zakresy {#available-scopes}

| Zakres                   | Opis                                           |
| ------------------------ | ---------------------------------------------- |
| `account:members:read`   | Przeczytaj członków konta                      |
| `account:members:write`  | Zarządzaj członkami konta                      |
| `account:registry:read`  | Odczytaj z rejestru pakietów Swift             |
| `account:registry:write` | Opublikuj w rejestrze pakietów Swift           |
| `project:previews:read`  | Pobierz podglądy                               |
| `project:previews:write` | Przeglądaj podglądy                            |
| `project:admin:read`     | Przeczytaj ustawienia projektu                 |
| `project:admin:write`    | Zarządzaj ustawieniami projektu                |
| `project:cache:read`     | Pobierz pliki binarne z pamięci podręcznej     |
| `project:cache:write`    | Prześlij pliki binarne z pamięci podręcznej    |
| `project:bundles:read`   | Wyświetl pakiety                               |
| `project:bundles:write`  | Prześlij pakiety                               |
| `project:tests:read`     | Przeczytaj wyniki testu                        |
| `project:tests:write`    | Prześlij wyniki testu                          |
| `project:builds:read`    | Przeczytaj statystyki kompilacji               |
| `project:builds:write`   | Prześlij dane analityczne dotyczące kompilacji |
| `project:runs:read`      | Polecenie „read” działa                        |
| `project:runs:write`     | Tworzenie i aktualizacja uruchomień poleceń    |

### Grupy zakresu {#scope-groups}

Grupy zakresów to wygodny sposób na przypisanie wielu powiązanych zakresów za
pomocą jednego identyfikatora. Kiedy używasz grupy zakresów, automatycznie
rozszerza się ona, żeby uwzględnić wszystkie pojedyncze zakresy, które zawiera.

| Grupa zakresu | Zakresy objęte tłumaczeniem                                                                                                                   |
| ------------- | --------------------------------------------------------------------------------------------------------------------------------------------- |
| `ci`          | `project:cache:write`, `project:previews:write`, `project:bundles:write`, `project:tests:write`, `project:builds:write`, `project:runs:write` |

### Ciągła integracja {#continuous-integration}

W środowiskach CI, które nie obsługują OIDC, możesz utworzyć token konta z grupą
zakresów `ci` w celu uwierzytelniania swoich procesów CI:

```bash
tuist account tokens create my-account --scopes ci --name ci
```

Powoduje to utworzenie tokenu zawierającego wszystkie zakresy potrzebne do
typowych operacji CI (pamięć podręczna, podglądy, pakiety, testy, kompilacje i
uruchomienia). Zapisz wygenerowany token jako sekret w swoim środowisku CI i
ustaw go jako zmienną środowiskową `TUIST_TOKEN`.

### Zarządzanie tokenami konta {#managing-account-tokens}

Aby wyświetlić listę wszystkich tokenów dla konta:

```bash
tuist account tokens list my-account
```

Aby unieważnić token według nazwy:

```bash
tuist account tokens revoke my-account ci-cache-token
```

### Korzystanie z tokenów konta {#using-account-tokens}

Tokeny konta powinny być zdefiniowane jako zmienne środowiskowe `TUIST_TOKEN`:

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
