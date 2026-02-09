---
{
  "title": "Get started",
  "titleTemplate": ":title · Quick-start · Guides · Tuist",
  "description": "Learn how to install Tuist in your environment."
}
---
# Başlayın {#get-started}

Tuist'i herhangi bir dizinde veya Xcode projenizin veya çalışma alanınızın
dizininde kullanmaya başlamanın en kolay yolu:

::: code-group

```bash [Mise]
mise x tuist@latest -- tuist init
```

```bash [Global Tuist (Homebrew)]
tuist init
```
<!-- -->
:::

Komut, <LocalizedLink href="/guides/features/projects">oluşturulmuş bir projele
oluşturma</LocalizedLink> veya mevcut bir Xcode projesini veya çalışma alanını
entegre etme adımlarını size gösterecektir. Kurulumunuzu uzak sunucuya
bağlamanıza yardımcı olur ve
<LocalizedLink href="/guides/features/selective-testing">seçmeli
test</LocalizedLink>,
<LocalizedLink href="/guides/features/previews">önizleme</LocalizedLink> ve
<LocalizedLink href="/guides/features/registry">kayıt</LocalizedLink> gibi
özelliklere erişmenizi sağlar.

::: info MIGRATE AN EXISTING PROJECT
<!-- -->
Geliştirici deneyimini iyileştirmek ve
<LocalizedLink href="/guides/features/cache">önbellek</LocalizedLink>
avantajından yararlanmak için mevcut bir projeyi oluşturulmuş projelere taşımak
istiyorsanız,
<LocalizedLink href="/guides/features/projects/adoption/migrate/xcode-project">taşıma
kılavuzumuza</LocalizedLink> göz atın.
<!-- -->
:::
