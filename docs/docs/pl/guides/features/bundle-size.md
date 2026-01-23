---
{
  "title": "Bundle insights",
  "titleTemplate": ":title · Features · Guides · Tuist",
  "description": "Find out how to make and keep your app's memory footprint as small as possible."
}
---
# Pakiet spostrzeżeń {#bundle-size}

::: ostrzeżenie WYMAGANIA
<!-- -->
- Konto <LocalizedLink href="/guides/server/accounts-and-projects">Tuist i
  projekt</LocalizedLink>
<!-- -->
:::

W miarę dodawania kolejnych funkcji do aplikacji rozmiar pakietu aplikacji stale
rośnie. Chociaż wzrost rozmiaru pakietu jest nieunikniony w miarę dodawania
kolejnych fragmentów kodu i zasobów, istnieje wiele sposobów na zminimalizowanie
tego wzrostu, np. poprzez upewnienie się, że zasoby nie są powielane w
pakietach, lub usuwanie nieużywanych symboli binarnych. Tuist zapewnia narzędzia
i informacje, które pomagają utrzymać niewielki rozmiar aplikacji — monitorujemy
również rozmiar aplikacji w czasie.

## Użycie {#usage}

Aby przeanalizować pakiet, możesz użyć polecenia `tuist inspect bundle`:

::: code-group
```bash [Analyze an .ipa]
tuist inspect bundle App.ipa
```
```bash [Analyze an .xcarchive]
tuist inspect bundle App.xcarchive
```
```bash [Analyze an app bundle]
tuist inspect bundle App.app
```
<!-- -->
:::

`Polecenie tuist inspect bundle` analizuje pakiet i udostępnia link do
szczegółowego przeglądu pakietu, w tym skan zawartości pakietu lub podział
modułów:

![Analizowany pakiet](/images/guides/features/bundle-size/analyzed-bundle.png)

## Ciągła integracja {#continuous-integration}

Aby śledzić rozmiar pakietu w czasie, należy przeanalizować pakiet w CI.
Najpierw należy upewnić się, że CI jest
<LocalizedLink href="/guides/integrations/continuous-integration#authentication">uwierzytelnione</LocalizedLink>:

Przykładowy przebieg pracy dla GitHub Actions mógłby wyglądać następująco:

```yaml
name: Build

jobs:
  build:
    steps:
      - # Build your app
      - name: Analyze bundle
        run: tuist inspect bundle App.ipa
        env:
          TUIST_TOKEN: ${{ secrets.TUIST_TOKEN }}
```

Po skonfigurowaniu będziesz mógł zobaczyć, jak zmienia się rozmiar pakietu w
czasie:

![Wykres rozmiaru
pakietu](/images/guides/features/bundle-size/bundle-size-graph.png)

## Komentarze do żądań ściągnięcia/łączenia {#pullmerge-request-comments}

::: warning INTEGRATION WITH GIT PLATFORM REQUIRED
<!-- -->
Aby uzyskać automatyczne komentarze do pull/merge request, zintegruj swój
<LocalizedLink href="/guides/server/accounts-and-projects">projekt
Tuist</LocalizedLink> z
<LocalizedLink href="/guides/server/authentication">platformą
Git</LocalizedLink>.
<!-- -->
:::

Gdy projekt Tuist zostanie połączony z platformą Git, taką jak
[GitHub](https://github.com), Tuist będzie publikować komentarz bezpośrednio w
żądaniach pull/merge za każdym razem, gdy uruchomisz `tuist inspect bundle`:
![Komentarz aplikacji GitHub z sprawdzonymi
pakietami](/images/guides/features/bundle-size/github-app-with-bundles.png)
