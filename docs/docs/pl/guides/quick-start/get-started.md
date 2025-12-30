---
{
  "title": "Get started",
  "titleTemplate": ":title · Quick-start · Guides · Tuist",
  "description": "Learn how to install Tuist in your environment."
}
---
# Rozpocznij {#get-started}

Najprostszym sposobem na rozpoczęcie pracy z Tuist jest umieszczenie go w
dowolnym katalogu lub w katalogu projektu lub obszaru roboczego Xcode:

::: code-group

```bash [Mise]
mise x tuist@latest -- tuist init
```

```bash [Global Tuist (Homebrew)]
tuist init
```
<!-- -->
:::

Polecenie przeprowadzi Cię przez kolejne kroki
<LocalizedLink href="/guides/features/projects">tworzenia wygenerowanego projektu</LocalizedLink> lub integracji istniejącego projektu Xcode lub obszaru
roboczego. Pomaga ono połączyć konfigurację ze zdalnym serwerem, dając dostęp do
takich funkcji jak
<LocalizedLink href="/guides/features/selective-testing">selektywne testowanie</LocalizedLink>,
<LocalizedLink href="/guides/features/previews">przeglądy</LocalizedLink> i
<LocalizedLink href="/guides/features/registry">rejestr</LocalizedLink>.

::: info MIGRATE AN EXISTING PROJECT
<!-- -->
Jeśli chcesz zmigrować istniejący projekt do wygenerowanych projektów, aby
poprawić doświadczenie programisty i skorzystać z naszej
<LocalizedLink href="/guides/features/cache"> pamięci podręcznej</LocalizedLink>, zapoznaj się z naszym
<LocalizedLink href="/guides/features/projects/adoption/migrate/xcode-project"> przewodnikiem migracji</LocalizedLink>.
<!-- -->
:::
