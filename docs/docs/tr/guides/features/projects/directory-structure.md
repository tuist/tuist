---
{
  "title": "Directory structure",
  "titleTemplate": ":title · Projects · Features · Guides · Tuist",
  "description": "Learn about the structure of Tuist projects and how to organize them."
}
---
# Dizin yapısı {#directory-structure}

Tuist projeleri genellikle Xcode projelerinin yerini almak için kullanılsa da,
bu kullanım durumuyla sınırlı değildir. Tuist projeleri ayrıca SPM paketleri,
şablonlar, eklentiler ve görevler gibi diğer proje türlerini oluşturmak için de
kullanılır. Bu belgede Tuist projelerinin yapısı ve nasıl organize edileceği
açıklanmaktadır. Daha sonraki bölümlerde, şablonların, eklentilerin ve
görevlerin nasıl tanımlanacağını ele alacağız.

## Standart Tuist projeleri {#standard-tuist-projects}

Tuist projeleri **Tuist tarafından üretilen en yaygın proje türüdür.**
Diğerlerinin yanı sıra uygulamalar, çerçeveler ve kütüphaneler oluşturmak için
kullanılırlar. Xcode projelerinin aksine, Tuist projeleri Swift'te tanımlanır,
bu da onları daha esnek ve bakımı daha kolay hale getirir. Tuist projeleri
ayrıca daha açıklayıcıdır, bu da onları anlamayı ve hakkında mantık yürütmeyi
kolaylaştırır. Aşağıdaki yapı, bir Xcode projesi oluşturan tipik bir Tuist
projesini göstermektedir:

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

- **Tuist dizini:** Bu dizinin iki amacı vardır. Birincisi, **adresine projenin
  kökünün nerede olduğunu bildirir**. Bu, projenin köküne göre yolların
  oluşturulmasına ve ayrıca Tuist komutlarının proje içindeki herhangi bir
  dizinden çalıştırılmasına olanak tanır. İkinci olarak, aşağıdaki dosyalar için
  bir kapsayıcıdır:
  - **ProjectDescriptionHelpers:** Bu dizin, tüm manifesto dosyalarında
    paylaşılan Swift kodunu içerir. Manifest dosyaları, bu dizinde tanımlanan
    kodu kullanmak için `import ProjectDescriptionHelpers` adresini
    kullanabilir. Kod paylaşımı, tekrarları önlemek ve projeler arasında
    tutarlılık sağlamak için yararlıdır.
  - **Package.swift:** Bu dosya, Tuist'in yapılandırılabilir ve optimize
    edilebilir Xcode projeleri ve hedefleri ([CocoaPods](https://cococapods)
    gibi) kullanarak entegre etmesi için Swift paketi bağımlılıklarını içerir.
    Daha fazla bilgi
    <LocalizedLink href="/guides/features/projects/dependencies">burada</LocalizedLink>.

- **Kök dizin**: Projenizin `Tuist` dizinini de içeren kök dizini.
  - <LocalizedLink href="/guides/features/projects/manifests#tuistswift"><bold>Tuist.swift:</bold></LocalizedLink>
    Bu dosya, Tuist için tüm projeler, çalışma alanları ve ortamlar arasında
    paylaşılan yapılandırmayı içerir. Örneğin, şemaların otomatik olarak
    oluşturulmasını devre dışı bırakmak veya projelerin dağıtım hedefini
    tanımlamak için kullanılabilir.
  - <LocalizedLink href="/guides/features/projects/manifests#workspace-swift"><bold>Workspace.swift:</bold></LocalizedLink>
    Bu bildirim bir Xcode çalışma alanını temsil eder. Diğer projeleri gruplamak
    için kullanılır ve ayrıca ek dosyalar ve şemalar ekleyebilir.
  - <LocalizedLink href="/guides/features/projects/manifests#project-swift"><bold>Project.swift:</bold></LocalizedLink>
    Bu manifesto bir Xcode projesini temsil eder. Projenin bir parçası olan
    hedefleri ve bunların bağımlılıklarını tanımlamak için kullanılır.

Yukarıdaki proje ile etkileşime girerken, komutlar çalışma dizininde veya
`--path` bayrağı ile belirtilen dizinde bir `Workspace.swift` veya bir
`Project.swift` dosyası bulmayı bekler. Bildirim, projenin kökünü temsil eden
bir `Tuist` dizini içeren bir dizinde veya dizinin alt dizininde olmalıdır.

::: tip
<!-- -->
Xcode çalışma alanları, birleştirme çakışması olasılığını azaltmak için
projeleri birden fazla Xcode projesine bölmeye izin veriyordu. Eğer çalışma
alanlarını bunun için kullanıyorsanız, Tuist'te bunlara ihtiyacınız yok. Tuist,
bir projeyi ve bağımlılıklarının projelerini içeren bir çalışma alanını otomatik
olarak oluşturur.
<!-- -->
:::

## Swift paketi <Badge type="warning" text="beta" /> {#swift-package-badge-typewarning-textbeta-}

Tuist ayrıca SPM paket projelerini de desteklemektedir. Eğer bir SPM paketi
üzerinde çalışıyorsanız, hiçbir şeyi güncellemenize gerek yoktur. Tuist, kök
`Package.swift` dosyanızı otomatik olarak alır ve Tuist'in tüm özellikleri sanki
bir `Project.swift` manifestosuymuş gibi çalışır.

Başlamak için SPM paketinizde `tuist install` ve `tuist generate` komutlarını
çalıştırın. Projeniz artık vanilla Xcode SPM entegrasyonunda göreceğiniz tüm
aynı şemalara ve dosyalara sahip olmalıdır. Bununla birlikte, artık
<LocalizedLink href="/guides/features/cache">`tuist cache`</LocalizedLink>
çalıştırabilir ve SPM bağımlılıklarınızın ve modüllerinizin çoğunun önceden
derlenmiş olmasını sağlayarak sonraki derlemeleri son derece hızlı hale
getirebilirsiniz.
