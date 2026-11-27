---
{
  "title": "Swift",
  "titleTemplate": ":title · Paket Kayıt Defterleri · Özellikler · Kılavuzlar · Tuist",
  "description": "Tuist'in küresel önbellek ağıyla desteklenen Tuist Swift paket kayıt defteri sayesinde Swift Package Manager çözümleme süresini dakikalardan saniyelere düşürün."
}
---
# Swift Package Registry {#swift-package-registry}

Bağımlılık sayısı arttıkça, bunların çözülme süresi de uzar. [CocoaPods](https://cocoapods.org/) veya [npm](https://www.npmjs.com/) gibi diğer paket yöneticileri merkeziyken, Swift Package Manager merkezi değildir. Bu nedenle SwiftPM, her depoyu derin klonlayarak bağımlılıkları çözmek zorunda kalır; bu işlem zaman alıcıdır ve merkezi bir yaklaşıma kıyasla daha fazla bellek tüketir. Tuist bu sorunu ele almak için [Package Registry](https://github.com/swiftlang/swift-package-manager/blob/main/Documentation/PackageRegistry/PackageRegistryUsage.md) uygulamasını sunar, böylece yalnızca _gerçekten ihtiyaç duyduğunuz_ commit’leri indirebilirsiniz. Kayıttaki paketler [Swift Package Index](https://swiftpackageindex.com/) temel alınır -- bir paketi orada bulabiliyorsanız, o paket Tuist Registry’de de mevcuttur. Ayrıca paketler, çözümleme sırasında minimum gecikme sağlamak amacıyla küresel ölçekte edge depolama üzerinden dağıtılır.

## Kullanım {#usage}

Kaydı yapılandırmanın iki yolu vardır:

### Seçenek 1: Üretim sırasında otomatik kurulum (önerilen) {#automatic-setup}

Projenizi oluşturmak için Tuist kullanıyorsanız, `Tuist.swift` yapılandırmanızda `registryEnabled` seçeneğini ayarlayarak kaydı etkinleştirebilirsiniz:

```swift
import ProjectDescription

let tuist = Tuist(
    project: .tuist(
        generationOptions: .options(
            registryEnabled: true
        )
    )
)
```

Bu seçenekle `tuist generate`, çalışma alanınızda kayıt yapılandırma dosyasını otomatik olarak oluşturur. Böylece `tuist registry setup` komutunu ayrı olarak çalıştırmanıza gerek kalmaz.

> [!TIP]
> `registryEnabled`, bağımlılıkları Tuist’in XcodeProj tabanlı entegrasyonu yerine Xcode’un varsayılan Swift Package Manager entegrasyonu üzerinden projelere ekleyen projeler için de kaydı yapılandırır. Kaynak denetimi URL’siyle bildirilen paketlerin kayıttan çözülmesi için Xcode’u yapılandırmaz. Bunun için, <.localized_link href="/guides/features/package-registries/swift/xcode-project#resolving-source-control-packages">Kaynak denetimi paketlerini çözme</.localized_link> bölümünde açıklandığı gibi her makinede bir kez `tuist registry setup` komutunu çalıştırın.


### Seçenek 2: Manuel kurulum {#manual-setup}

Kaydı manuel olarak yapılandırmak için projenizin dizininde aşağıdaki komutu çalıştırın:

```bash
tuist registry setup
```

Bu komut, projeniz için kaydı etkinleştiren bir kayıt yapılandırma dosyası oluşturur. Ekibinizin de kayıttan yararlanabilmesi için bu dosyanın sürüm kontrolüne işlendiğinden emin olun.

### Kimlik doğrulama (isteğe bağlı) {#authentication}

Kimlik doğrulama **isteğe bağlıdır**. Kimlik doğrulama olmadan, kayıt IP adresi başına dakikada **1.000 istek** hız sınırıyla kullanılabilir. Dakikada **20.000 istek** gibi daha yüksek bir hız sınırına ulaşmak için şu komutu çalıştırarak kimlik doğrulaması yapabilirsiniz:

```bash
tuist registry login
```

> [!NOTE]
> Kimlik doğrulama için bir <.localized_link href="/guides/server/accounts-and-projects">Tuist hesabı ve projesi</.localized_link> gerekir.


### Bağımlılıkları çözme {#resolving-dependencies}

Bağımlılıkları kaynak denetimi yerine kayıttan çözmek için proje kurulumunuza göre okumaya devam edin:
- <.localized_link href="/guides/features/package-registries/swift/xcode-project">Xcode project</.localized_link>
- <.localized_link href="/guides/features/package-registries/swift/generated-project">Generated project with the Xcode package integration</.localized_link>
- <.localized_link href="/guides/features/package-registries/swift/xcodeproj-integration">Generated project with the XcodeProj-based package integration</.localized_link>
- <.localized_link href="/guides/features/package-registries/swift/swift-package">Swift package</.localized_link>

Kaydı CI üzerinde yapılandırmak için şu kılavuzu izleyin: <.localized_link href="/guides/features/package-registries/swift/continuous-integration">Sürekli entegrasyon</.localized_link>.

### Paket kaydı tanımlayıcıları {#package-registry-identifiers}

Bir `Package.swift` veya `Project.swift` dosyasında paket kaydı tanımlayıcılarını kullandığınızda, paketin URL’sini kayıt kuralına dönüştürmeniz gerekir. Kayıt tanımlayıcısı her zaman `{organization}.{repository}` biçimindedir. Örneğin, `https://github.com/pointfreeco/swift-composable-architecture` paketi için kaydı kullanmak istediğinizde paket kaydı tanımlayıcısı `pointfreeco.swift-composable-architecture` olur.

> [!NOTE]
> Tanımlayıcı birden fazla nokta içeremez. Depo adında nokta varsa, alt çizgi ile değiştirilir. Örneğin, `https://github.com/groue/GRDB.swift` paketinin kayıt tanımlayıcısı `groue.GRDB_swift` olacaktır.
