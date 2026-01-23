---
{
  "title": "Get started",
  "titleTemplate": ":title · Quick-start · Guides · Tuist",
  "description": "Learn how to install Tuist in your environment."
}
---
# Rozpocznij {#get-started}

Najłatwiejszym sposobem rozpoczęcia pracy z Tuist jest umieszczenie go w
dowolnym katalogu lub w katalogu projektu Xcode lub obszaru roboczego:

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
<LocalizedLink href="/guides/features/projects">tworzenia wygenerowanego
projektu</LocalizedLink> lub integracji istniejącego projektu lub obszaru
roboczego Xcode. Pomaga ono połączyć konfigurację z serwerem zdalnym,
zapewniając dostęp do funkcji takich jak
<LocalizedLink href="/guides/features/selective-testing">selektywne
testowanie</LocalizedLink>,
<LocalizedLink href="/guides/features/previews">podgląd</LocalizedLink> i
<LocalizedLink href="/guides/features/registry">rejestr</LocalizedLink>.

::: info MIGRATE AN EXISTING PROJECT
<!-- -->
Jeśli chcesz przenieść istniejący projekt do projektów generowanych, aby
poprawić komfort pracy programistów i skorzystać z naszej
<LocalizedLink href="/guides/features/cache">pamięci podręcznej</LocalizedLink>,
zapoznaj się z naszym
<LocalizedLink href="/guides/features/projects/adoption/migrate/xcode-project">przewodnikiem
migracji</LocalizedLink>.
<!-- -->
:::
