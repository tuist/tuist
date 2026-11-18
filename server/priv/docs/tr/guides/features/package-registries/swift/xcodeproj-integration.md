---
{
  "title": "XcodeProj tabanlı paket entegrasyonuyla oluşturulan proje",
  "titleTemplate": ":title · Swift · Paket Kayıtları · Özellikler · Kılavuzlar · Tuist",
  "description": "Oluşturulan projelerde XcodeProj tabanlı paket entegrasyonu ile Tuist Registry'yi kullanın."
}
---
# XcodeProj tabanlı paket entegrasyonu ile oluşturulan proje {#generated-project-with-xcodeproj-based-integration}

<.localized_link href="/guides/features/projects/dependencies#tuists-xcodeprojbased-integration">XcodeProj tabanlı entegrasyon</.localized_link> kullanırken, bağımlılıklar mevcutsa bunları kayıt defterinden çözmek için `--replace-scm-with-registry` bayrağını kullanabilirsiniz. Bunu `Tuist.swift` dosyanızdaki `installOptions` bölümüne ekleyin:
```swift
import ProjectDescription

let tuist = Tuist(
    fullHandle: "{account-handle}/{project-handle}",
    project: .tuist(
        installOptions: .options(passthroughSwiftPackageManagerArguments: ["--replace-scm-with-registry"])
    )
)
```

Bağımlılıkları her çözdüğünüzde kayıt defterinin kullanılmasını sağlamak istiyorsanız, `Tuist/Package.swift` dosyanızdaki `dependencies` bölümünü bir URL yerine kayıt defteri tanımlayıcısını kullanacak şekilde güncellemeniz gerekir.

<!-- @snippet: ./_registry-identifier -->
