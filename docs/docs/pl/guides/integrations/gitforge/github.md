---
{
  "title": "GitHub",
  "titleTemplate": ":title | Git forges | Integrations | Guides | Tuist",
  "description": "Learn how to integrate Tuist with GitHub for enhanced workflows."
}
---
# Integracja z GitHub {#github}

Repozytoria Git stanowią centralny element większości projektów
programistycznych. Integrujemy się z GitHub, aby zapewnić wgląd w Tuist
bezpośrednio w żądaniach ściągnięcia i zaoszczędzić trochę konfiguracji, takich
jak synchronizacja domyślnej gałęzi.

## Konfiguracja {#setup}

Musisz zainstalować aplikację Tuist GitHub w zakładce Integracje` w
sekcji `swojej organizacji: ![Obraz przedstawiający zakładkę
integracji](/images/guides/integrations/gitforge/github/integrations.png)

Następnie możesz dodać połączenie między repozytorium GitHub a projektem Tuist:

![Obraz przedstawiający dodanie połączenia
projektu](/images/guides/integrations/gitforge/github/add-project-connection.png)

## Komentarze do żądań ściągnięcia/łączenia {#pullmerge-request-comments}

Aplikacja GitHub publikuje raport z działania Tuist, który zawiera podsumowanie
PR, w tym linki do najnowszych
<LocalizedLink href="/guides/features/previews#pullmerge-request-comments">podglądów</LocalizedLink>
lub
<LocalizedLink href="/guides/features/selective-testing#pullmerge-request-comments">testów</LocalizedLink>:

![Obraz przedstawiający komentarz do pull
requestu](/images/guides/integrations/gitforge/github/pull-request-comment.png)

::: info REQUIREMENTS
<!-- -->
Komentarz zostanie opublikowany dopiero po
<LocalizedLink href="/guides/integrations/continuous-integration#authentication">uwierzytelnieniu</LocalizedLink>
Twoich operacji CI.
<!-- -->
:::

::: info GITHUB_REF
<!-- -->
Jeśli masz niestandardowy przepływ pracy, który nie jest uruchamiany po
zatwierdzeniu PR, ale na przykład po komentarzu GitHub, może być konieczne
upewnienie się, że zmienna `GITHUB_REF` jest ustawiona na
`refs/pull/<pr_number>/merge` lub
`refs/pull/<pr_number>/head`.</pr_number></pr_number>

Możesz uruchomić odpowiednie polecenie, np. `tuist share`, z prefiksem
`GITHUB_REF` zmienna środowiskowa: <code v-pre>GITHUB_REF="refs/pull/${{
github.event.issue.number }}/head" tuist share</code>
<!-- -->
:::
