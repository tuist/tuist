---
{
  "title": "Swift paketi",
  "titleTemplate": ":title · Swift · Paket Kayıtları · Özellikler · Kılavuzlar · Tuist",
  "description": "Tuist Registry'nin bir Swift paketinde nasıl kullanılacağını öğrenin."
}
---
# Swift paketi {#swift-package}

Bir Swift paketi üzerinde çalışıyorsanız, bağımlılıklar mevcutsa bunları kayıt defterinden çözmek için `--replace-scm-with-registry` bayrağını kullanabilirsiniz:

```bash
swift package --replace-scm-with-registry resolve
```

Bağımlılıkları her çözdüğünüzde kayıt defterinin kullanılmasını sağlamak istiyorsanız, URL yerine kayıt defteri tanımlayıcısını kullanmak üzere `Package.swift` dosyanızdaki `dependencies` öğesini güncellemeniz gerekir.

<!-- @snippet: ./_registry-identifier -->
