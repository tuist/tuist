---
{
  "title": "Editing",
  "titleTemplate": ":title · Projects · Features · Guides · Tuist",
  "description": "Learn how to use Tuist's edit workflow to declare your project leveraging Xcode's build system and editor capabilities."
}
---
# Düzenleme {#editing}

Değişikliklerin Xcode'un kullanıcı arayüzü üzerinden yapıldığı geleneksel Xcode
projeleri veya Swift Package'lerden farklı olarak, Tuist tarafından yönetilen
projeler **manifest dosyalarında** bulunan Swift kodunda tanımlanır. Swift
Package'ler ve `Package.swift` dosyasına aşina iseniz, yaklaşım çok benzerdir.

Bu dosyaları herhangi bir metin düzenleyici kullanarak düzenleyebilirsiniz,
ancak bunun için Tuist tarafından sağlanan iş akışını kullanmanızı öneririz:
`tuist edit`. İş akışı, tüm manifest dosyalarını içeren bir Xcode projesi
oluşturur ve bunları düzenlemenize ve derlemenize olanak tanır. Xcode'u
kullanarak, **kod tamamlama, sözdizimi vurgulama ve hata denetimi** gibi tüm
avantajlardan yararlanabilirsiniz.

## Projeyi düzenleyin {#edit-the-project}

Projenizi düzenlemek için, Tuist proje dizininde veya alt dizininde aşağıdaki
komutu çalıştırabilirsiniz:

```bash
tuist edit
```

Komut, global bir dizinde bir Xcode projesi oluşturur ve bunu Xcode'da açar.
Proje, tüm manifestolarınızın geçerli olduğundan emin olmak için
derleyebileceğiniz bir `Manifests` dizini içerir.

::: info GLOB-RESOLVED MANIFESTS
<!-- -->
`tuist edit`, projenin kök dizininden ( `Tuist.swift` dosyasını içeren dizin)
glob `**/{Manifest}.swift` kullanarak dahil edilecek manifestleri çözer.
Projenin kök dizininde geçerli bir `Tuist.swift` dosyası olduğundan emin olun.
<!-- -->
:::

### Manifest dosyalarını yok sayma {#ignoring-manifest-files}

Projenizde, gerçek Tuist manifestoları olmayan alt dizinlerde manifest
dosyalarıyla aynı ada sahip Swift dosyaları (ör. `Project.swift`) varsa, bunları
düzenleme projesinden hariç tutmak için projenizin kök dizininde `.tuistignore`
dosyası oluşturabilirsiniz.

`.tuistignore` dosyası, hangi dosyaların yok sayılacağını belirtmek için glob
desenleri kullanır:

```gitignore
# Ignore all Project.swift files in the Sources directory
Sources/**/Project.swift

# Ignore specific subdirectories
Tests/Fixtures/**/Workspace.swift
```

Bu, Tuist manifest dosyalarında kullanılan isimlendirme kuralını kullanan test
donanımları veya örnek kodlar olduğunda özellikle yararlıdır.

## İş akışını düzenleyin ve oluşturun {#edit-and-generate-workflow}

Fark etmiş olabileceğiniz gibi, düzenleme oluşturulmuş Xcode projesinden
yapılamaz. Bu, oluşturulmuş projenin Tuist'e bağımlı olmasını önlemek ve
gelecekte Tuist'ten kolayca ayrılabilmenizi sağlamak için tasarlanmıştır.

Bir projeyi yinelerken, projeyi düzenlemek için bir Xcode projesi elde etmek
üzere terminal oturumundan `tuist edit` komutunu çalıştırmanızı ve başka bir
terminal oturumunda `tuist generate` komutunu çalıştırmanızı öneririz.
