---
{
  "title": "Directory structure",
  "titleTemplate": ":title · Projects · Features · Guides · Tuist",
  "description": "Learn about the structure of Tuist projects and how to organize them."
}
---
# Dizin yapısı {#directory-structure}

Tuist projeleri genellikle Xcode projelerinin yerine kullanılır, ancak bu
kullanımla sınırlı değildir. Tuist projeleri, SPM paketleri, şablonlar,
eklentiler ve görevler gibi diğer proje türlerini oluşturmak için de kullanılır.
Bu belgede, Tuist projelerinin yapısı ve nasıl düzenleneceği açıklanmaktadır.
Sonraki bölümlerde şablonları, eklentileri ve görevleri nasıl tanımlayacağınızı
ele alacağız.

## Standart Tuist projeleri {#standard-tuist-projects}

Tuist projeleri, Tuist tarafından oluşturulan en yaygın proje türüdür. **** Bu
projeler, uygulamalar, çerçeveler ve kütüphaneler oluşturmak için kullanılır.
Xcode projelerinden farklı olarak, Tuist projeleri Swift ile tanımlanır, bu da
onları daha esnek ve bakımı daha kolay hale getirir. Tuist projeleri ayrıca daha
açıklayıcıdır, bu da onları daha kolay anlaşılır ve mantıklı hale getirir.
Aşağıdaki yapı, bir Xcode projesi oluşturan tipik bir Tuist projesini
göstermektedir:

```bash
Tuist.swift
Tuist/
  Package.swift
  ProjectDescriptionHelpers/
Projects/
  App/
    Project.swift
  Feature/
    Project.swift
Workspace.swift
```

- **Tuist dizini:** Bu dizinin iki amacı vardır. İlk olarak, projenin kök
  dizinini** olarak **belirtir. Bu, projenin kök dizinine göre yollar
  oluşturulmasına ve ayrıca proje içindeki herhangi bir dizinden Tuist
  komutlarının çalıştırılmasına olanak tanır. İkinci olarak, aşağıdaki
  dosyaların bulunduğu bir konteynerdir:
  - **ProjectDescriptionHelpers:** Bu dizin, tüm manifest dosyalarında
    paylaşılan Swift kodunu içerir. Manifest dosyaları, bu dizinde tanımlanan
    kodu kullanmak için `import ProjectDescriptionHelpers` komutunu
    kullanabilir. Kod paylaşımı, yinelemeleri önlemek ve projeler arasında
    tutarlılığı sağlamak için yararlıdır.
  - **Package.swift:** Bu dosya, Tuist'in Xcode projeleri ve hedefleri
    ([CocoaPods](https://cococapods)) kullanarak entegre edebileceği,
    yapılandırılabilir ve optimize edilebilir Swift paketi bağımlılıklarını
    içerir. Daha fazla bilgi için
    <LocalizedLink href="/guides/features/projects/dependencies">buraya</LocalizedLink>bakın.

- **Kök dizin**: Projenizin kök dizini, aynı zamanda `Tuist` dizinini de içerir.
  - <LocalizedLink href="/guides/features/projects/manifests#tuistswift"><bold>Tuist.swift:</bold></LocalizedLink>
    Bu dosya, tüm projeler, çalışma alanları ve ortamlar arasında paylaşılan
    Tuist yapılandırmasını içerir. Örneğin, şemaların otomatik olarak
    oluşturulmasını devre dışı bırakmak veya projelerin dağıtım hedefini
    tanımlamak için kullanılabilir.
  - <LocalizedLink href="/guides/features/projects/manifests#workspace-swift"><bold>Workspace.swift:</bold></LocalizedLink>
    Bu manifest, bir Xcode çalışma alanını temsil eder. Diğer projeleri
    gruplandırmak için kullanılır ve ek dosyalar ve şemalar da ekleyebilir.
  - <LocalizedLink href="/guides/features/projects/manifests#project-swift"><bold>Project.swift:</bold></LocalizedLink>
    Bu manifest, bir Xcode projesini temsil eder. Projenin bir parçası olan
    hedefleri ve bunların bağımlılıklarını tanımlamak için kullanılır.

Yukarıdaki projeyle etkileşimde bulunurken, komutlar çalışma dizininde veya
`--path` bayrağıyla belirtilen dizinde `Workspace.swift` veya `Project.swift`
dosyasını bulmayı bekler. Manifest, projenin kökünü temsil eden `Tuist` dizini
içeren bir dizinde veya alt dizinde bulunmalıdır.

::: tip
<!-- -->
Xcode çalışma alanları, birleştirme çakışmalarının olasılığını azaltmak için
projeleri birden fazla Xcode projesine bölmeye izin veriyordu. Çalışma
alanlarını bu amaçla kullanıyorsanız, Tuist'te bunlara ihtiyacınız yoktur.
Tuist, bir projeyi ve bağımlılık projelerini içeren bir çalışma alanını otomatik
olarak oluşturur.
<!-- -->
:::

## Swift paketi <Badge type="warning" text="beta" /> {#swift-package-badge-typewarning-textbeta-}

Tuist, SPM paket projelerini de destekler. SPM paketi üzerinde çalışıyorsanız,
herhangi bir güncelleme yapmanız gerekmez. Tuist, kök `Package.swift` dosyasını
otomatik olarak algılar ve Tuist'in tüm özellikleri, `Project.swift` manifest
dosyasıymış gibi çalışır.

Başlamak için, SPM paketinizde `tuist install` ve `tuist generate` komutlarını
çalıştırın. Projeniz artık, standart Xcode SPM entegrasyonunda gördüğünüz tüm
şemalara ve dosyalara sahip olmalıdır. Ancak, artık
<LocalizedLink href="/guides/features/cache">`tuist cache`</LocalizedLink>
komutunu da çalıştırabilir ve SPM bağımlılıklarınızın ve modüllerinizin çoğunu
önceden derleyerek sonraki derlemeleri son derece hızlı hale getirebilirsiniz.
