---
{
  "title": "GitHub",
  "titleTemplate": ":title | Git forges | Integrations | Guides | Tuist",
  "description": "Learn how to integrate Tuist with GitHub for enhanced workflows."
}
---
# Integracja z serwisem GitHub {#github}

Repozytoria Git stanowią centralny element większości projektów
programistycznych. Zintegrowaliśmy się z GitHub, aby zapewnić wgląd w Tuist
bezpośrednio w żądaniach ściągnięcia i zaoszczędzić trochę konfiguracji, takich
jak synchronizacja domyślnej gałęzi.

## Konfiguracja {#setup}

Aplikację Tuist GitHub należy zainstalować w zakładce `Integrations` swojej
organizacji: ![Obrazek przedstawiający zakładkę
integracji](/images/guides/integrations/gitforge/github/integrations.png)

Następnie można dodać połączenie projektu między repozytorium GitHub a projektem
Tuist:

![Obraz przedstawiający dodawanie połączenia
projektu](/images/guides/integrations/gitforge/github/add-project-connection.png)

## Komentarze do żądań ściągnięcia/łączenia {#pull-merge-request-comments}

Aplikacja GitHub publikuje raport z uruchomienia Tuist, który zawiera
podsumowanie PR, w tym linki do najnowszych
<LocalizedLink href="/guides/features/previews#pullmerge-request-comments">przeglądów</LocalizedLink>
lub
<LocalizedLink href="/guides/features/selective-testing#pullmerge-request-comments">testów</LocalizedLink>:

![Obrazek przedstawiający komentarz do pull
requesta](/images/guides/integrations/gitforge/github/pull-request-comment.png)

::: info REQUIREMENTS
<!-- -->
Komentarz jest publikowany tylko wtedy, gdy uruchomienia CI są
<LocalizedLink href="/guides/integrations/continuous-integration#authentication">uwierzytelnione</LocalizedLink>.
<!-- -->
:::

::: info GITHUB_REF
<!-- -->
Jeśli masz niestandardowy przepływ pracy, który nie jest wyzwalany przez
zatwierdzenie PR, ale na przykład komentarz GitHub, może być konieczne
upewnienie się, że zmienna `GITHUB_REF` jest ustawiona na
`refs/pull/<pr_number>/merge` lub
`refs/pull/<pr_number>/head`.</pr_number></pr_number>

Możesz uruchomić odpowiednie polecenie, takie jak `tuist share`, z prefiksem
`GITHUB_REF` zmienna środowiskowa: <code v-pre>GITHUB_REF="refs/pull/${{
github.event.issue.number }}/head" tuist share</code>
<!-- -->
:::
