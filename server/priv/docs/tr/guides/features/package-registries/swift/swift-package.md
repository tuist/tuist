---
{
  "title": "Swift paketi",
  "titleTemplate": ":title · Swift · Paket Kayıtları · Özellikler · Kılavuzlar · Tuist",
  "description": "Tuist Registry'nin bir Swift paketinde nasıl kullanılacağını öğrenin."
}
---
# Swift paketi {#swift-package}

Bir Swift paketi üzerinde çalışıyorsanız, bağımlılıklar kayıt defterinde mevcutsa bunları çözmek için `--replace-scm-with-registry` bayrağını kullanabilirsiniz:

```bash
swift package --replace-scm-with-registry resolve
```

Bağımlılıkları her çözdüğünüzde kayıt defterinin kullanılmasını sağlamak istiyorsanız, bir URL yerine kayıt defteri tanımlayıcısını kullanmak için `Package.swift` dosyanızdaki `dependencies` alanını güncellemeniz gerekir.

<!-- @snippet: ./_registry-identifier -->
