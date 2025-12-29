---
{
  "title": "Editing",
  "titleTemplate": ":title · Projects · Features · Guides · Tuist",
  "description": "Learn how to use Tuist's edit workflow to declare your project leveraging Xcode's build system and editor capabilities."
}
---
# Düzenleme {#editing}

Değişikliklerin Xcode'un kullanıcı arayüzü üzerinden yapıldığı geleneksel Xcode
projelerinin veya Swift paketi olan Swift paketi projelerinin aksine, Tuist
tarafından yönetilen projeler **manifest dosyalarında** bulunan Swift kodunda
tanımlanır. Swift paketi ve `Package.swift` dosyasını biliyorsanız, yaklaşım çok
benzerdir.

Bu dosyaları herhangi bir metin düzenleyici kullanarak düzenleyebilirsiniz,
ancak bunun için Tuist tarafından sağlanan iş akışını kullanmanızı öneririz,
`tuist edit`. İş akışı, tüm manifesto dosyalarını içeren bir Xcode projesi
oluşturur ve bunları düzenlemenize ve derlemenize olanak tanır. Xcode kullanımı
sayesinde **kod tamamlama, sözdizimi vurgulama ve hata denetiminin tüm
avantajlarından yararlanabilirsiniz**.

## Projeyi düzenleyin {#edit-the-project}

Projenizi düzenlemek için, bir Tuist proje dizininde veya bir alt dizinde
aşağıdaki komutu çalıştırabilirsiniz:

```bash
tuist edit
```

Komut, genel bir dizinde bir Xcode projesi oluşturur ve bunu Xcode'da açar.
Proje, tüm manifestolarınızın geçerli olduğundan emin olmak için
oluşturabileceğiniz bir `Manifests` dizini içerir.

::: info GLOB-RESOLVED MANIFESTS
<!-- -->
`tuist edit`, projenin kök dizininden ( `Tuist.swift` dosyasını içeren)
`**/{Manifest}.swift` glob'unu kullanarak dahil edilecek manifestoları çözümler.
Projenin kök dizininde geçerli bir `Tuist.swift` dosyası olduğundan emin olun.
<!-- -->
:::

### Manifesto dosyalarını yok sayma {#ignoring-manifest-files}

Projeniz, gerçek Tuist manifestoları olmayan alt dizinlerde manifesto
dosyalarıyla aynı ada sahip Swift dosyaları içeriyorsa (örneğin,
`Project.swift`), bunları düzenleme projesinden hariç tutmak için projenizin kök
dizininde bir `.tuistignore` dosyası oluşturabilirsiniz.

`.tuistignore` dosyası, hangi dosyaların göz ardı edileceğini belirtmek için
glob kalıpları kullanır:

```gitignore
# Ignore all Project.swift files in the Sources directory
Sources/**/Project.swift

# Ignore specific subdirectories
Tests/Fixtures/**/Workspace.swift
```

Bu, özellikle Tuist bildirim dosyalarıyla aynı adlandırma kuralını kullanan test
fikstürleriniz veya örnek kodunuz olduğunda kullanışlıdır.

## İş akışını düzenleme ve oluşturma {#edit-and-generate-workflow}

Fark etmiş olabileceğiniz gibi, düzenleme oluşturulan Xcode projesinden
yapılamaz. Bu, oluşturulmuş projelenin Tuist'e bağımlı olmasını önlemek ve
gelecekte Tuist'ten çok az çabayla geçebilmenizi sağlamak için tasarım
gereğidir.

Bir proje üzerinde yineleme yaparken, projeyi düzenlemek üzere bir Xcode projesi
almak için bir terminal oturumundan `tuist edit` çalıştırmanızı ve `tuist
generate` çalıştırmak için başka bir terminal oturumu kullanmanızı öneririz.
