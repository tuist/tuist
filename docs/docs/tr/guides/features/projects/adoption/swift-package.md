---
{
  "title": "Use Tuist with a Swift Package",
  "titleTemplate": ":title · Adoption · Projects · Features · Guides · Tuist",
  "description": "Learn how to use Tuist with a Swift Package."
}
---
# Tuist'i bir Swift paketi ile Kullanma <Badge type="warning" text="beta" /> {#using-tuist-with-a-swift-package-badge-typewarning-textbeta-}

Tuist, `Package.swift` adresini projeleriniz için bir DSL olarak kullanmayı
destekler ve paket hedeflerinizi yerel bir Xcode projesine ve hedeflerine
dönüştürür.

::: warning
<!-- -->
Bu özelliğin amacı, geliştiricilerin Swift paketi içinde Tuist'i benimsemenin
etkisini değerlendirmeleri için kolay bir yol sağlamaktır. Bu nedenle, Swift
paketi Paket Yöneticisi özelliklerinin tamamını desteklemeyi veya Tuist'in
<LocalizedLink href="/guides/features/projects/code-sharing">proje açıklama yardımcıları</LocalizedLink> gibi benzersiz özelliklerini paketler dünyasına
getirmeyi planlamıyoruz.
<!-- -->
:::

::: info ROOT DIRECTORY
<!-- -->
Tuist komutları, kökü bir `Tuist` veya bir `.git` dizini ile tanımlanan belirli
bir
<LocalizedLink href="/guides/features/projects/directory-structure#standard-tuist-projects">dizin yapısı</LocalizedLink> bekler.
<!-- -->
:::

## Tuist'i bir Swift paketi ile Kullanma {#using-tuist-with-a-swift-package}

Tuist'in bir Swift paketi içeren [TootSDK
Package](https://github.com/TootSDK/TootSDK) deposu ile kullanacağız. Yapmamız
gereken ilk şey depoyu klonlamak:

```bash
git clone https://github.com/TootSDK/TootSDK
cd TootSDK
```

Depo dizinine girdikten sonra, Swift paketi Paket Yöneticisi bağımlılıklarını
yüklememiz gerekiyor:

```bash
tuist install
```

Kaputun altında `tuist install` Swift paketi bağımlılıklarını çözmek ve çekmek
için Swift paketi Yöneticisini kullanır. Çözümleme tamamlandıktan sonra projeyi
oluşturabilirsiniz:

```bash
tuist generate
```

İşte bu! Açıp üzerinde çalışmaya başlayabileceğiniz yerel bir Xcode projeniz
var.
