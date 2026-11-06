---
{
  "title": "Tuist'i Swift Package ile Kullanma",
  "titleTemplate": ":title · Benimseme · Projeler · Özellikler · Kılavuzlar · Tuist",
  "description": "Tuist'in Swift Package ile nasıl kullanılacağını öğrenin."
}
---
# Swift Package ile Tuist Kullanımı <Badge type="warning" text="beta" /> {#using-tuist-with-a-swift-package-badge-typewarning-textbeta-}

Tuist, projelerinizde DSL olarak `Package.swift` kullanımını destekler ve paket hedeflerinizi yerel bir Xcode projesine ve hedeflerine dönüştürür.

> [!WARNING]
> Bu özelliğin amacı, geliştiricilerin Swift Paketlerinde Tuist benimsemenin etkisini değerlendirmeleri için kolay bir yol sunmaktır. Bu nedenle, Swift Package Manager özelliklerinin tamamını desteklemeyi veya <.localized_link href="/guides/features/projects/code-sharing">proje açıklama yardımcıları</.localized_link> gibi Tuist'in benzersiz özelliklerini paket dünyasına getirmeyi planlamıyoruz.


> [!NOTE]
> **Kök dizin**
>
> Tuist komutları, kökü bir `Tuist` veya `.git` diziniyle tanımlanan belirli bir <.localized_link href="/guides/features/projects/directory-structure#standard-tuist-projects">dizin yapısı</.localized_link> bekler.


## Swift Package ile Tuist Kullanımı {#using-tuist-with-a-swift-package}

Bir Swift Package içeren [TootSDK Paketi](https://github.com/TootSDK/TootSDK) deposuyla Tuist kullanacağız. Yapmamız gereken ilk şey depoyu klonlamak:

```bash
git clone https://github.com/TootSDK/TootSDK
cd TootSDK
```

Deponun dizinine girdikten sonra, Swift Package Manager bağımlılıklarını yüklememiz gerekir:

```bash
tuist install
```

Arka planda `tuist install`, paketin bağımlılıklarını çözmek ve çekmek için Swift Package Manager'ı kullanır. Çözümleme tamamlandıktan sonra projeyi oluşturabilirsiniz:

```bash
tuist generate
```

İşte bu kadar! Açabilir ve üzerinde çalışmaya başlayabileceğiniz yerel bir Xcode projeniz var.
