---
{
  "title": "Dizin yapısı",
  "titleTemplate": ":title · Projeler · Özellikler · Kılavuzlar · Tuist",
  "description": "Tuist projelerinin yapısını ve bunları nasıl düzenleyeceğinizi öğrenin."
}
---
# Dizin yapısı {#directory-structure}

Tuist projeleri genellikle Xcode projelerinin yerini almak için kullanılsa da, bu kullanım durumuyla sınırlı değildir. Tuist projeleri ayrıca SPM paketleri, şablonlar, eklentiler ve görevler gibi diğer proje türlerini oluşturmak için de kullanılır. Bu belge, Tuist projelerinin yapısını ve bunların nasıl organize edileceğini açıklar. İlerleyen bölümlerde şablonların, eklentilerin ve görevlerin nasıl tanımlanacağını ele alacağız.

## Standart Tuist projeleri {#standard-tuist-projects}

Tuist projeleri, **Tuist tarafından oluşturulan en yaygın proje türüdür.** Uygulamalar, çerçeveler ve kütüphaneler gibi birçok şeyi derlemek için kullanılırlar. Xcode projelerinden farklı olarak, Tuist projeleri Swift ile tanımlanır; bu da onları daha esnek ve bakımı daha kolay hale getirir. Tuist projeleri ayrıca daha bildirimseldir, bu da anlaşılmasını ve mantık yürütülmesini kolaylaştırır. Aşağıdaki yapı, bir Xcode projesi oluşturan tipik bir Tuist projesini göstermektedir:

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

- **Tuist dizini:** Bu dizinin iki amacı vardır. İlk olarak, **projenin kök dizininin nerede olduğunu** belirtir. Bu, projenin kök dizinine göre yollar oluşturmayı ve proje içindeki herhangi bir dizinden Tuist komutlarını çalıştırmayı mümkün kılar. İkinci olarak, aşağıdaki dosyalar için bir kapsayıcıdır:
  - **ProjectDescriptionHelpers:** Bu dizin, tüm bildirim dosyalarında paylaşılan Swift kodunu içerir. Bildirim dosyaları, bu dizinde tanımlanan kodu kullanmak için `import ProjectDescriptionHelpers` içe aktarabilir. Kod paylaşımı, tekrarlamalardan kaçınmak ve projeler arasında tutarlılığı sağlamak açısından faydalıdır.
  - **Package.swift:** Bu dosya, Tuist’in bunları yapılandırılabilir ve optimize edilebilir Xcode projeleri ve hedefleri aracılığıyla entegre etmesi için gereken Swift Package bağımlılıklarını (örneğin [CocoaPods](https://cocoapods.org)) içerir. Daha fazla bilgi için <.localized_link href="/guides/features/projects/dependencies">buraya</.localized_link> göz atın.

- **Kök dizin**: Projenizin kök dizini olup aynı zamanda `Tuist` dizinini de içerir.
  - <.localized_link href="/guides/features/projects/manifests#tuistswift"><strong>Tuist.swift:</strong></.localized_link> Bu dosya, tüm projeler, çalışma alanları ve ortamlar arasında paylaşılan Tuist yapılandırmasını içerir. Örneğin, şemaların otomatik oluşturulmasını devre dışı bırakmak veya projelerin dağıtım hedefini tanımlamak için kullanılabilir.
  - <.localized_link href="/guides/features/projects/manifests#workspaceswift"><strong>Workspace.swift:</strong></.localized_link> Bu bildirim, bir Xcode çalışma alanını temsil eder. Diğer projeleri gruplamak için kullanılır ve ek dosyalar ile şemalar da ekleyebilir.
  - <.localized_link href="/guides/features/projects/manifests#projectswift"><strong>Project.swift:</strong></.localized_link> Bu bildirim, bir Xcode projesini temsil eder. Projeye ait hedefleri ve bunların bağımlılıklarını tanımlamak için kullanılır.

Yukarıdaki projeyle etkileşim kurarken, komutlar çalışma dizininde veya `--path` bayrağıyla belirtilen dizinde ya bir `Workspace.swift` ya da bir `Project.swift` dosyası bulmayı bekler. Bildirim dosyası, projenin kökünü temsil eden bir `Tuist` dizini içeren bir dizinde veya alt dizininde olmalıdır.

> [!TIP]
> Xcode çalışma alanları, birleştirme çakışmalarının olasılığını azaltmak amacıyla projeleri birden çok Xcode projesine bölmeye olanak tanır. Çalışma alanlarını bu amaçla kullanıyorsanız, Tuist’te bunlara ihtiyacınız yoktur. Tuist, bir projeyi ve bağımlılıklarının projelerini içeren bir çalışma alanını otomatik olarak oluşturur.


## Swift Paketi <Badge type="warning" text="beta" /> {#swift-package-badge-typewarning-textbeta-}

Tuist ayrıca SPM paket projelerini de destekler. Bir SPM paketi üzerinde çalışıyorsanız, herhangi bir güncelleme yapmanıza gerek kalmaz. Tuist, kök `Package.swift` dosyanızı otomatik olarak algılar ve Tuist’in tüm özellikleri, sanki bir `Project.swift` bildirimiymiş gibi çalışır.

Başlamak için SPM paketinizde `tuist install` ve `tuist generate` komutlarını çalıştırın. Projeniz artık standart Xcode SPM entegrasyonunda göreceğiniz tüm şema ve dosyalara sahip olacaktır. Ancak artık <.localized_link href="/guides/features/cache">`tuist cache`</.localized_link> komutunu da çalıştırabilir ve SPM bağımlılıklarınızın ve modüllerinizin çoğunun önceden derlenmiş halini kullanarak sonraki derlemeleri son derece hızlı hale getirebilirsiniz.
