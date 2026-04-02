---
{
  "title": "Xcode cache",
  "titleTemplate": ":title · Cache · Features · Guides · Tuist",
  "description": "Enable Xcode compilation cache for your existing Xcode projects to improve build times both locally and on the CI."
}
---
# Xcode önbelleği {#xcode-cache}

Tuist, Xcode derleme önbelleği desteği sunar; bu sayede ekipler, derleme
sisteminin önbellekleme özelliklerinden yararlanarak derleme çıktılarını
paylaşabilir.

## Kurulum {#setup}

::: warning REQUIREMENTS
<!-- -->
- A <LocalizedLink href="/guides/server/accounts-and-projects">Tuist hesabı ve
  projesi</LocalizedLink>
- Xcode 26.0 veya üstü
<!-- -->
:::

Henüz bir Tuist hesabınız ve projeniz yoksa, aşağıdakini çalıştırarak bir tane
oluşturabilirsiniz:

```bash
tuist init
```

`fullHandle` dosyasına referans veren bir `Tuist.swift` dosyanız olduğunda,
aşağıdakini çalıştırarak projeniz için önbelleklemeyi ayarlayabilirsiniz:

```bash
tuist setup cache
```

Bu komut, Swift [derleme sistemi](https://github.com/swiftlang/swift-build)'nin
derleme çıktılarını paylaşmak için kullandığı yerel önbellek hizmetini
başlangıçta çalıştırmak üzere bir
[LaunchAgent](https://developer.apple.com/library/archive/documentation/MacOSX/Conceptual/BPSystemStartup/Chapters/CreatingLaunchdJobs.html)
oluşturur. Bu komutun hem yerel hem de CI ortamlarınızda bir kez çalıştırılması
gerekir.

CI'da önbelleği ayarlamak için
<LocalizedLink href="/guides/integrations/continuous-integration#authentication">kimlik
doğrulamanızın</LocalizedLink> yapıldığından emin olun.

### Xcode Derleme Ayarlarını Yapılandırın {#configure-xcode-build-settings}

Xcode projenize aşağıdaki derleme ayarlarını ekleyin:

```
COMPILATION_CACHE_ENABLE_CACHING = YES
COMPILATION_CACHE_REMOTE_SERVICE_PATH = $HOME/.local/state/tuist/your_org_your_project.sock
COMPILATION_CACHE_ENABLE_PLUGIN = YES
COMPILATION_CACHE_ENABLE_DIAGNOSTIC_REMARKS = YES
```

`, COMPILATION_CACHE_REMOTE_SERVICE_PATH,` ve `,
COMPILATION_CACHE_ENABLE_PLUGIN,`, Xcode'un derleme ayarları kullanıcı
arayüzünde doğrudan görünmedikleri için **kullanıcı tanımlı derleme ayarları**
olarak eklenmeleri gerektiğini unutmayın:

::: info SOCKET PATH
<!-- -->
`tuist setup cache` komutunu çalıştırdığınızda soket yolu görüntülenir. Bu yol,
projenizin tam tanıtıcısına dayanır ve eğik çizgiler alt çizgilerle
değiştirilir.
<!-- -->
:::

`xcodebuild` komutunu çalıştırırken aşağıdaki bayrakları ekleyerek bu ayarları
da belirtebilirsiniz:

```
xcodebuild build -project YourProject.xcodeproj -scheme YourScheme \
    COMPILATION_CACHE_ENABLE_CACHING=YES \
    COMPILATION_CACHE_REMOTE_SERVICE_PATH=$HOME/.local/state/tuist/your_org_your_project.sock \
    COMPILATION_CACHE_ENABLE_PLUGIN=YES \
    COMPILATION_CACHE_ENABLE_DIAGNOSTIC_REMARKS=YES
```

::: info GENERATED PROJECTS
<!-- -->
Projeniz Tuist tarafından oluşturulmuşsa, ayarları manuel olarak yapmanız
gerekmez.

Bu durumda, tek yapmanız gereken `Tuist.swift` dosyanıza `enableCaching: true`
eklemektir:
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

CI ortamınızda önbelleklemeyi etkinleştirmek için, yerel ortamlarda olduğu gibi
şu komutu çalıştırmanız gerekir: `tuist setup cache`.

Kimlik doğrulama için,
<LocalizedLink href="/guides/server/authentication#oidc-tokens">OIDC kimlik
doğrulama</LocalizedLink> (desteklenen CI sağlayıcıları için önerilir) veya
`TUIST_TOKEN` ortam değişkeni aracılığıyla bir
<LocalizedLink href="/guides/server/authentication#account-tokens">hesap
jetonu</LocalizedLink> kullanabilirsiniz.

OIDC kimlik doğrulamasını kullanan GitHub Actions için örnek bir iş akışı:
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
gibi diğer CI platformları dahil olmak üzere daha fazla örnek için
<LocalizedLink href="/guides/integrations/continuous-integration">Sürekli
Entegrasyon kılavuzuna</LocalizedLink> bakın.
