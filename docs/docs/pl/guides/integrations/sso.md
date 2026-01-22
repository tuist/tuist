---
{
  "title": "SSO",
  "titleTemplate": ":title | Integrations | Guides | Tuist",
  "description": "Learn how to set up Single Sign-On (SSO) with your organization."
}
---
# SSO {#sso}

## Google {#google}

Jeśli posiadasz organizację Google Workspace i chcesz, aby każdy programista
logujący się przy użyciu tej samej domeny hostowanej przez Google został dodany
do Twojej organizacji Tuist, możesz to skonfigurować za pomocą:
```bash
tuist organization update sso my-organization --provider google --organization-id my-google-domain.com
```

::: warning
<!-- -->
Musisz być uwierzytelniony w Google za pomocą adresu e-mail powiązanego z
organizacją, której domenę konfigurujesz.
<!-- -->
:::

## Okta {#okta}

SSO z Okta jest dostępne tylko dla klientów korporacyjnych. Jeśli jesteś
zainteresowany jego konfiguracją, skontaktuj się z nami pod adresem
[contact@tuist.dev](mailto:contact@tuist.dev).

W trakcie procesu zostanie Ci przydzielona osoba kontaktowa, która pomoże Ci
skonfigurować Okta SSO.

Najpierw musisz utworzyć aplikację Okta i skonfigurować ją do współpracy z
Tuist:
1. Przejdź do panelu administracyjnego Okta.
2. Aplikacje > Aplikacje > Utwórz integrację aplikacji
3. Wybierz „OIDC — OpenID Connect” i „Aplikacja internetowa”.
4. Wprowadź nazwę wyświetlaną aplikacji, na przykład „Tuist”. Prześlij logo
   Tuist znajdujące się pod adresem [ten adres
   URL](https://tuist.dev/images/tuist_dashboard.png).
5. Na razie pozostaw adresy URI przekierowania logowania bez zmian.
6. W sekcji „Zadania” wybierz żądaną kontrolę dostępu do aplikacji SSO i zapisz.
7. Po zapisaniu dostępne będą ogólne ustawienia aplikacji. Skopiuj „Client ID” i
   „Client Secret” – musisz bezpiecznie udostępnić te dane osobie kontaktowej.
8. Zespół Tuist będzie musiał ponownie wdrożyć serwer Tuist przy użyciu
   dostarczonego identyfikatora klienta i klucza tajnego. Może to potrwać do
   jednego dnia roboczego.
9. Po wdrożeniu serwera kliknij przycisk „Edytuj” w ustawieniach ogólnych.
10. Wklej następujący adres przekierowania:
    `https://tuist.dev/users/auth/okta/callback`
13. Zmień „Logowanie zainicjowane przez” na „Okta lub aplikacja”.
14. Wybierz opcję „Wyświetlaj ikonę aplikacji użytkownikom”.
15. Zaktualizuj „Adres URL inicjowania logowania” na
    `https://tuist.dev/users/auth/okta?organization_id=1`. `organization_id`
    zostanie podany przez osobę kontaktową.
16. Kliknij „Zapisz”.
17. Zainicjuj logowanie Tuist z pulpitu nawigacyjnego Okta.
18. Aby zapewnić automatyczny dostęp do organizacji Tuist użytkownikom
    zalogowanym z domeny Okta, należy uruchomić następujące polecenie:
```bash
tuist organization update sso my-organization --provider okta --organization-id my-okta-domain.com
```

::: warning
<!-- -->
Użytkownicy muszą najpierw zalogować się za pośrednictwem pulpitu nawigacyjnego
Okta, ponieważ Tuist obecnie nie obsługuje automatycznego przydzielania i
odbierania uprawnień użytkownikom z organizacji Okta. Po zalogowaniu się za
pośrednictwem pulpitu nawigacyjnego Okta zostaną oni automatycznie dodani do
organizacji Tuist.
<!-- -->
:::
