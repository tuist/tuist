---
{
  "title": "Get started",
  "titleTemplate": ":title · Quick-start · Guides · Tuist",
  "description": "Learn how to install Tuist in your environment."
}
---
# Başlayın {#get-started}

Herhangi bir dizinde veya Xcode projenizin veya çalışma alanınızın dizininde
Tuist ile başlamanın en kolay yolu:

::: code-group

```bash [Mise]
mise x tuist@latest -- tuist init
```

```bash [Global Tuist (Homebrew)]
tuist init
```
<!-- -->
:::

Komut, <LocalizedLink href="/guides/features/projects">oluşturulmuş proje</LocalizedLink> oluşturma veya mevcut bir Xcode projesini ya da çalışma alanını entegre etme adımlarında size yol gösterecektir. Kurulumunuzu uzak sunucuya bağlamanıza yardımcı olarak <LocalizedLink href="/guides/features/selective-testing">seçmeli test</LocalizedLink>, <LocalizedLink href="/guides/features/previews">önizleme</LocalizedLink> ve <LocalizedLink href="/guides/features/registry">kayıt</LocalizedLink> gibi özelliklere erişmenizi sağlar.

::: info MIGRATE AN EXISTING PROJECT
<!-- -->
Geliştirici deneyimini iyileştirmek ve
<LocalizedLink href="/guides/features/cache">önbelleğimizden</LocalizedLink>
yararlanmak için mevcut bir projeyi oluşturulan projele'ye taşımak istiyorsanız,
<LocalizedLink href="/guides/features/projects/adoption/migrate/xcode-project">göç kılavuzumuza</LocalizedLink> göz atın.
<!-- -->
:::
