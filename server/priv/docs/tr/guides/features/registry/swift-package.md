---
{
  "title": "Swift package",
  "titleTemplate": ":title · Registry · Features · Guides · Tuist",
  "description": "Learn how to use the Tuist Registry in a Swift package."
}
---
# Swift paketi {#swift-package}

Bir Swift paketi üzerinde çalışıyorsanız, mevcutsa bağımlılıkları kayıt
defterinden çözmek için `--replace-scm-with-registry` bayrağını
kullanabilirsiniz:

```bash
swift package --replace-scm-with-registry resolve
```

Bağımlılıkları her çözümlediğinizde kayıt defterinin kullanıldığından emin olmak
istiyorsanız, `Package.swift` dosyanızdaki `dependencies` adresini URL yerine
kayıt defteri tanımlayıcısını kullanacak şekilde güncellemeniz gerekir. Kayıt
tanımlayıcısı her zaman `{organization}.{repository}` biçimindedir. Örneğin,
`swift-composable-architecture` Swift paketi'nin kayıt defterini kullanmak için
aşağıdakileri yapın:
```diff
dependencies: [
-   .package(url: "https://github.com/pointfreeco/swift-composable-architecture", from: "0.1.0")
+   .package(id: "pointfreeco.swift-composable-architecture", from: "0.1.0")
]
```
