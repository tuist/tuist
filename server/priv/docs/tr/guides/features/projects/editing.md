---
{
  "title": "Düzenleme",
  "titleTemplate": ":title · Projeler · Özellikler · Kılavuzlar · Tuist",
  "description": "Tuist proje bildirimlerini Xcode otomatik tamamlama ve derleme doğrulama ile düzenleyin."
}
---
# Düzenleme {#editing}

Değişikliklerin Xcode arayüzü üzerinden yapıldığı geleneksel Xcode projelerinin veya Swift Paketlerinin aksine, Tuist ile yönetilen projeler **manifest dosyaları** içinde yer alan Swift koduyla tanımlanır. Swift Paketlerine ve `Package.swift` dosyasına aşinaysanız yaklaşım oldukça benzerdir.

Bu dosyaları herhangi bir metin düzenleyiciyle düzenleyebilirsiniz, ancak bunun için Tuist tarafından sağlanan iş akışını, yani `tuist edit` kullanmanızı öneririz. Bu iş akışı, tüm manifest dosyalarını içeren bir Xcode projesi oluşturur ve bunları düzenlemenize ve derlemenize olanak tanır. Xcode kullandığınız için **otomatik tamamlama, sözdizimi vurgulama ve hata denetimi** gibi tüm avantajlardan yararlanırsınız.

## Projeyi düzenle {#edit-the-project}

Projenizi düzenlemek için bir Tuist proje dizininde veya alt dizininde aşağıdaki komutu çalıştırabilirsiniz:

```bash
tuist edit
```

Komut, genel bir dizinde bir Xcode projesi oluşturur ve bunu Xcode’da açar. Proje, tüm manifestlerinizin geçerli olduğundan emin olmak için derleyebileceğiniz bir `Manifests` dizini içerir.

> [!NOTE]
> **Glob ile çözümlenen manifestler**
>
> `tuist edit`, projenin kök dizininden (`Tuist.swift` dosyasını içeren dizin) `**/{Manifest}.swift` glob desenini kullanarak dahil edilecek manifestleri çözümler. Projenin kökünde geçerli bir `Tuist.swift` bulunduğundan emin olun.


### Manifest dosyalarını yoksayma {#ignoring-manifest-files}

Projenizde, gerçek Tuist manifestleri olmayan alt dizinlerde manifest dosyalarıyla aynı ada sahip Swift dosyaları (örneğin `Project.swift`) varsa, bunları düzenleme projesinden dışlamak için projenizin kökünde bir `.tuistignore` dosyası oluşturabilirsiniz.

`.tuistignore` dosyası, hangi dosyaların yoksayılması gerektiğini belirtmek için glob desenlerini kullanır:

```gitignore
# Ignore all Project.swift files in the Sources directory
Sources/**/Project.swift

# Ignore specific subdirectories
Tests/Fixtures/**/Workspace.swift
```

Bu durum, test sabitleri veya örnek kodunuzun Tuist manifest dosyalarıyla aynı adlandırma kuralını kullanması durumunda özellikle yararlıdır.

## Düzenleme ve oluşturma iş akışı {#edit-and-generate-workflow}

Fark etmiş olabileceğiniz gibi, düzenleme işlemi oluşturulan Xcode projesinden yapılamaz. Bu, oluşturulan projenin Tuist’e bağımlı olmasını önlemek amacıyla tasarlanmıştır; böylece gelecekte Tuist’ten minimum çabayla ayrılabilirsiniz.

Bir proje üzerinde yinelemeli çalışırken, projeyi düzenlemek için bir Xcode projesi elde etmek üzere bir terminal oturumunda `tuist edit` çalıştırmanızı ve `tuist generate` çalıştırmak için başka bir terminal oturumu kullanmanızı öneririz.
