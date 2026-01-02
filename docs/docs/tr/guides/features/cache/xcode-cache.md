---
{
  "title": "Xcode cache",
  "titleTemplate": ":title · Cache · Features · Guides · Tuist",
  "description": "Enable Xcode compilation cache for your existing Xcode projects to improve build times both locally and on the CI."
}
---
# Xcode önbelleği {#xcode-cache}

Tuist, derleme sisteminin önbelleğe alma özelliklerinden yararlanarak ekiplerin
derleme eserlerini paylaşmasına olanak tanıyan Xcode derleme önbelleği için
destek sağlar.

## Kurulum {#setup}

::: warning REQUIREMENTS
<!-- -->
- A <LocalizedLink href="/guides/server/accounts-and-projects">Tuist hesabı ve
  projesi</LocalizedLink>
- Xcode 26.0 veya üstü
<!-- -->
:::

Henüz bir Tuist hesabınız ve projeniz yoksa, çalıştırarak bir tane
oluşturabilirsiniz:

```bash
tuist init
```

Bir `Tuist.swift` dosyanız olduğunda, `fullHandle` dosyanızı referans alarak,
projeniz için önbelleğe alma işlemini çalıştırarak ayarlayabilirsiniz:

```bash
tuist setup cache
```

Bu komut, Swift [build system](https://github.com/swiftlang/swift-build) derleme
eserlerini paylaşmak için kullandığı yerel bir önbellek hizmetini başlangıçta
çalıştırmak için bir
[LaunchAgent](https://developer.apple.com/library/archive/documentation/MacOSX/Conceptual/BPSystemStartup/Chapters/CreatingLaunchdJobs.html)
oluşturur. Bu komutun hem yerel hem de CI ortamlarınızda bir kez çalıştırılması
gerekir.

CI'da önbelleği ayarlamak için
<LocalizedLink href="/guides/integrations/continuous-integration#authentication">authenticated</LocalizedLink>
olduğunuzdan emin olun.

### Xcode Derleme Ayarlarını Yapılandırma {#configure-xcode-build-settings}

Xcode projenize aşağıdaki derleme ayarlarını ekleyin:

```
COMPILATION_CACHE_ENABLE_CACHING = YES
COMPILATION_CACHE_REMOTE_SERVICE_PATH = $HOME/.local/state/tuist/your_org_your_project.sock
COMPILATION_CACHE_ENABLE_PLUGIN = YES
COMPILATION_CACHE_ENABLE_DIAGNOSTIC_REMARKS = YES
```

`COMPILATION_CACHE_REMOTE_SERVICE_PATH` ve `COMPILATION_CACHE_ENABLE_PLUGIN`
öğelerinin, Xcode'un derleme ayarları kullanıcı arayüzünde doğrudan
gösterilmedikleri için **kullanıcı tanımlı derleme ayarları** olarak eklenmesi
gerektiğini unutmayın:

::: info SOCKET PATH
<!-- -->
Soket yolu `tuist setup cache` adresini çalıştırdığınızda görüntülenecektir.
Projenizin tam tanıtıcısına dayanır ve eğik çizgiler alt çizgilerle
değiştirilir.
<!-- -->
:::

Bu ayarları `xcodebuild` adresini çalıştırırken aşağıdaki gibi bayraklar
ekleyerek de belirtebilirsiniz:

```
xcodebuild build -project YourProject.xcodeproj -scheme YourScheme \
    COMPILATION_CACHE_ENABLE_CACHING=YES \
    COMPILATION_CACHE_REMOTE_SERVICE_PATH=$HOME/.local/state/tuist/your_org_your_project.sock \
    COMPILATION_CACHE_ENABLE_PLUGIN=YES \
    COMPILATION_CACHE_ENABLE_DIAGNOSTIC_REMARKS=YES
```

::: info GENERATED PROJECTS
<!-- -->
Projeniz Tuist tarafından oluşturulduysa ayarların manuel olarak yapılması
gerekmez.

Bu durumda tek yapmanız gereken `enableCaching: true` ifadesini `Tuist.swift`
dosyanıza eklemektir:
```swift
import ProjectDescription

let tuist = Tuist(
    fullHandle: "your-org/your-project",
    project: .tuist(
        generationOptions: .options(
            enableCaching: true
        )
    )
)
```
<!-- -->
:::

### Sürekli entegrasyon #{continuous-integration}

CI ortamınızda önbelleğe almayı etkinleştirmek için yerel ortamlarda olduğu gibi
aynı komutu çalıştırmanız gerekir: `tuist setup cache`.

Kimlik doğrulama için ya
<LocalizedLink href="/guides/server/authentication#oidc-tokens">OIDC kimlik
doğrulamasını</LocalizedLink> (desteklenen CI sağlayıcıları için önerilir) ya da
`TUIST_TOKEN` ortam değişkeni aracılığıyla bir
<LocalizedLink href="/guides/server/authentication#account-tokens">hesap
belirtecini</LocalizedLink> kullanabilirsiniz.

OIDC kimlik doğrulamasını kullanan GitHub Eylemleri için örnek bir iş akışı:
```yaml
name: Build

permissions:
  id-token: write
  contents: read

jobs:
  build:
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v4
      - uses: jdx/mise-action@v2
      - run: tuist auth login
      - run: tuist setup cache
      - # Your build steps
```

Token tabanlı kimlik doğrulama ve Xcode Cloud, CircleCI, Bitrise ve Codemagic
gibi diğer CI platformları da dahil olmak üzere daha fazla örnek için
<LocalizedLink href="/guides/integrations/continuous-integration">Sürekli
Entegrasyon kılavuzuna</LocalizedLink> bakın.
