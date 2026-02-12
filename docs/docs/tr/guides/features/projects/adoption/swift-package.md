---
{
  "title": "Use Tuist with a Swift Package",
  "titleTemplate": ":title · Adoption · Projects · Features · Guides · Tuist",
  "description": "Learn how to use Tuist with a Swift Package."
}
---
# Tuist'i Swift package ile kullanma <Badge type="warning" text="beta" /> {#using-tuist-with-a-swift-package-badge-typewarning-textbeta-}

Tuist, projeleriniz için DSL olarak `Package.swift` kullanımını destekler ve
paket hedeflerinizi yerel bir Xcode projesi ve hedeflerine dönüştürür.

::: warning
<!-- -->
Bu özelliğin amacı, geliştiricilere Swift Package'lerde Tuist'i kullanmanın
etkisini kolayca değerlendirebilmeleri için bir yol sunmaktır. Bu nedenle, Swift
Package Yöneticisi'nin tüm özelliklerini desteklemeyi veya
<LocalizedLink href="/guides/features/projects/code-sharing">proje açıklaması
yardımcıları</LocalizedLink> gibi Tuist'in tüm benzersiz özelliklerini paket
dünyasına getirmeyi planlamıyoruz.
<!-- -->
:::

::: info ROOT DIRECTORY
<!-- -->
Tuist komutları, kökü `Tuist` veya `.git` dizininde tanımlanan belirli bir
<LocalizedLink href="/guides/features/projects/directory-structure#standard-tuist-projects">dizin
yapısı</LocalizedLink> bekler.
<!-- -->
:::

## Tuist'i Swift package ile kullanma {#using-tuist-with-a-swift-package}

Tuist'i, Swift package'ini içeren [TootSDK
Paketi](https://github.com/TootSDK/TootSDK) deposuyla kullanacağız. Yapmamız
gereken ilk şey, depoyu klonlamaktır:

```bash
git clone https://github.com/TootSDK/TootSDK
cd TootSDK
```

Deponun dizinine girdikten sonra, Swift package paket yöneticisi
bağımlılıklarını yüklememiz gerekir:

```bash
tuist install
```

Arka planda `tuist install`, Swift package manager'ı kullanarak paketin
bağımlılıklarını çözer ve çeker. Çözümleme tamamlandıktan sonra projeyi
oluşturabilirsiniz:

```bash
tuist generate
```

Voilà! Açıp üzerinde çalışmaya başlayabileceğiniz yerel bir Xcode projeniz var.
