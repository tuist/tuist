---
{
  "title": "Swift package",
  "titleTemplate": ":title · Registry · Features · Guides · Tuist",
  "description": "Learn how to use the Tuist Registry in a Swift package."
}
---
# Swift paketi {#swift-package}

Swift paketi üzerinde çalışıyorsanız, Kayıt’tan bağımlılıkları çözmek için
`--replace-scm-with-registry` bayrağını kullanabilirsiniz:

```bash
swift package --replace-scm-with-registry resolve
```

Bağımlılıkları her çözdüğünüzde kayıt defterinin kullanılmasını sağlamak
istiyorsanız, `dependencies` adresindeki `Package.swift` dosyanızı güncelleyerek
URL yerine kayıt defteri tanımlayıcısını kullanmanız gerekir. Kayıt defteri
tanımlayıcısı her zaman `{organization}.{repository}` biçimindedir. Örneğin,
`swift-composable-architecture` paketinin kayıt defterini kullanmak için
aşağıdakileri yapın:
```diff
dependencies: [
-   .package(url: "https://github.com/pointfreeco/swift-composable-architecture", from: "0.1.0")
+   .package(id: "pointfreeco.swift-composable-architecture", from: "0.1.0")
]
```
