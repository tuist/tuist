---
{
  "title": "Bundle insights",
  "titleTemplate": ":title · Features · Guides · Tuist",
  "description": "Find out how to make and keep your app's memory footprint as small as possible."
}
---
# Informacje o pakiecie {#bundle-size}

::: ostrzeżenie WYMAGANIA
<!-- -->
- Konto i projekt <LocalizedLink href="/guides/server/accounts-and-projects"> Tuist</LocalizedLink>
<!-- -->
:::

W miarę dodawania kolejnych funkcji do aplikacji, rozmiar pakietu aplikacji
stale rośnie. Podczas gdy wzrost rozmiaru pakietu jest nieunikniony w miarę
dostarczania większej ilości kodu i zasobów, istnieje wiele sposobów na
zminimalizowanie tego wzrostu, na przykład poprzez zapewnienie, że zasoby nie są
duplikowane w pakietach lub usuwanie nieużywanych symboli binarnych. Tuist
zapewnia narzędzia i analizy, które pomagają utrzymać niewielki rozmiar
aplikacji - a także monitorujemy jej rozmiar w czasie.

## Użycie {#usage}

Aby przeanalizować pakiet, można użyć polecenia `tuist inspect bundle`:

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

Polecenie `tuist inspect bundle` analizuje pakiet i udostępnia łącze do
szczegółowego przeglądu pakietu, w tym skanowania zawartości pakietu lub
podziału modułów:

![Analizowany pakiet](/images/guides/features/bundle-size/analyzed-bundle.png)

## Ciągła integracja {#continuous-integration}

Aby śledzić rozmiar pakietu w czasie, należy przeanalizować pakiet na CI. Po
pierwsze, należy upewnić się, że CI jest
<LocalizedLink href="/guides/integrations/continuous-integration#authentication">uwierzytelniony</LocalizedLink>:

Przykładowy przepływ pracy dla GitHub Actions mógłby wyglądać następująco:

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

Po skonfigurowaniu będziesz mógł zobaczyć, jak rozmiar pakietu zmienia się w
czasie:

![Wykres rozmiaru
pakietu](/images/guides/features/bundle-size/bundle-size-graph.png)

## Komentarze do żądań ściągnięcia/łączenia {#pullmerge-request-comments}

::: warning INTEGRATION WITH GIT PLATFORM REQUIRED
<!-- -->
Aby uzyskać automatyczne komentarze do pull/merge requestów, zintegruj projekt
<LocalizedLink href="/guides/server/accounts-and-projects">Tuist</LocalizedLink>
z platformą
<LocalizedLink href="/guides/server/authentication">Git</LocalizedLink>.
<!-- -->
:::

Po połączeniu projektu Tuist z platformą Git, taką jak
[GitHub](https://github.com), Tuist opublikuje komentarz bezpośrednio w
żądaniach ściągnięcia/łączenia za każdym razem, gdy uruchomisz `tuist inspect
bundle`: ![Komentarz aplikacji GitHub ze sprawdzonymi
pakietami](/images/guides/features/bundle-size/github-app-with-bundles.png).
