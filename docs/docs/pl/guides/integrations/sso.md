---
{
  "title": "SSO",
  "titleTemplate": ":title | Integrations | Guides | Tuist",
  "description": "Learn how to set up Single Sign-On (SSO) with your organization."
}
---
# SSO {#sso}

## Google {#google}

Jeśli masz organizację Google Workspace i chcesz, aby każdy programista, który
zaloguje się za pomocą tej samej domeny hostowanej przez Google, został dodany
do Twojej organizacji Tuist, możesz to skonfigurować za pomocą:
```bash
tuist organization update sso my-organization --provider google --organization-id my-google-domain.com
```

::: warning
<!-- -->
Musisz być uwierzytelniony w Google przy użyciu adresu e-mail powiązanego z
organizacją, której domenę konfigurujesz.
<!-- -->
:::

## Okta {#okta}

SSO z Okta jest dostępne tylko dla klientów korporacyjnych. Jeśli jesteś
zainteresowany jego konfiguracją, skontaktuj się z nami pod adresem
[contact@tuist.dev](mailto:contact@tuist.dev).

W trakcie tego procesu zostanie ci przydzielony punkt kontaktowy, który pomoże
ci skonfigurować Okta SSO.

Po pierwsze, należy utworzyć aplikację Okta i skonfigurować ją do pracy z Tuist:
1. Przejdź do panelu administracyjnego Okta
2. Aplikacje > Aplikacje > Utwórz integrację aplikacji
3. Wybierz "OIDC - OpenID Connect" i "Aplikacja internetowa".
4. Wprowadź nazwę wyświetlaną aplikacji, na przykład "Tuist". Prześlij logo
   Tuist znajdujące się pod adresem [ten
   URL](https://tuist.dev/images/tuist_dashboard.png).
5. URI przekierowania logowania należy na razie pozostawić bez zmian.
6. W sekcji "Przypisania" wybierz żądaną kontrolę dostępu do aplikacji SSO i
   zapisz.
7. Po zapisaniu dostępne będą ogólne ustawienia aplikacji. Skopiuj
   "Identyfikator klienta" i "Sekret klienta" - będziesz musiał bezpiecznie
   udostępnić je swojemu punktowi kontaktowemu.
8. Zespół Tuist będzie musiał ponownie wdrożyć serwer Tuist z dostarczonym
   identyfikatorem klienta i kluczem tajnym. Może to potrwać do jednego dnia
   roboczego.
9. Po wdrożeniu serwera kliknij przycisk "Edytuj" w ustawieniach ogólnych.
10. Wklej następujący adres URL przekierowania:
    `https://tuist.dev/users/auth/okta/callback`
13. Zmień "Login initiated by" na "Either Okta or App".
14. Wybierz opcję "Wyświetl ikonę aplikacji użytkownikom"
15. Zaktualizuj "Initiate login URL" za pomocą
    `https://tuist.dev/users/auth/okta?organization_id=1`. Identyfikator
    `organization_id` zostanie dostarczony przez punkt kontaktowy.
16. Kliknij "Zapisz".
17. Zainicjuj logowanie Tuist z pulpitu nawigacyjnego Okta.
18. Udziel automatycznego dostępu do organizacji Tuist użytkownikom podpisanym z
    domeny Okta, uruchamiając następujące polecenie:
```bash
tuist organization update sso my-organization --provider okta --organization-id my-okta-domain.com
```

::: warning
<!-- -->
Użytkownicy muszą początkowo zalogować się za pośrednictwem pulpitu
nawigacyjnego Okta, ponieważ Tuist obecnie nie obsługuje automatycznego
przydzielania i usuwania użytkowników z organizacji Okta. Po zalogowaniu się za
pośrednictwem pulpitu nawigacyjnego Okta zostaną oni automatycznie dodani do
organizacji Tuist.
<!-- -->
:::
