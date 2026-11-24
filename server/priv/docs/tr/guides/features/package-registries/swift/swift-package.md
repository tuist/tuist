---
{
  "title": "Swift paketi",
  "titleTemplate": ":title · Swift · Paket Kayıt Defterleri · Özellikler · Kılavuzlar · Tuist",
  "description": "Tuist Registry'yi bir Swift paketinde nasıl kullanacağınızı öğrenin."
}
---
# Swift paketi {#swift-package}

Bir Swift paketi üzerinde çalışıyorsanız, bağımlılıklar varsa bunları kayıt defterinden çözmek için `--replace-scm-with-registry` bayrağını kullanabilirsiniz:

```bash
swift package --replace-scm-with-registry resolve
```

Bağımlılıkları her çözümlediğinizde kayıt defterinin kullanılmasını sağlamak istiyorsanız, bir URL yerine kayıt tanımlayıcısını kullanmak için `Package.swift` dosyanızdaki `dependencies` alanını güncellemeniz gerekir.

<!-- @snippet: ./_registry-identifier -->
