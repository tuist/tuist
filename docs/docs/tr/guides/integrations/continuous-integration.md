---
{
  "title": "Continuous Integration (CI)",
  "titleTemplate": ":title · Automate · Guides · Tuist",
  "description": "Learn how to use Tuist in your CI workflows."
}
---
# Sürekli Entegrasyon (CI) {#continuous-integration-ci}

Tuist komutlarını [sürekli
entegrasyon](https://en.wikipedia.org/wiki/Continuous_integration) iş
akışlarınızda çalıştırmak için, CI ortamınıza yüklemeniz gerekir.

Kimlik doğrulama isteğe bağlıdır ancak
<LocalizedLink href="/guides/features/cache">cache</LocalizedLink> gibi sunucu
tarafı özelliklerini kullanmak istiyorsanız gereklidir.

Aşağıdaki bölümlerde bunun farklı CI platformlarında nasıl yapılacağına dair
örnekler verilmektedir.

## Örnekler {#examples}

### GitHub Eylemleri {#github-actions}

GitHub Actions](https://docs.github.com/en/actions) üzerinde güvenli, gizlilik
içermeyen kimlik doğrulaması için
<LocalizedLink href="/guides/server/authentication#oidc-tokens">OIDC kimlik doğrulamasını</LocalizedLink> kullanabilirsiniz:

::: code-group
```yaml [OIDC (Mise)]
name: Build Application
on:
  pull_request:
    branches:
      - main
  push:
    branches:
      - main

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
```
```yaml [OIDC (Homebrew)]
name: Build Application
on:
  pull_request:
    branches:
      - main
  push:
    branches:
      - main

permissions:
  id-token: write
  contents: read

jobs:
  build:
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v4
      - run: brew install --formula tuist@x.y.z
      - run: tuist auth login
      - run: tuist setup cache
```
```yaml [Project token (Mise)]
name: Build Application
on:
  pull_request:
    branches:
      - main
  push:
    branches:
      - main

env:
  TUIST_TOKEN: ${{ secrets.TUIST_TOKEN }}

jobs:
  build:
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v4
      - uses: jdx/mise-action@v2
      - run: tuist setup cache
```
```yaml [Project token (Homebrew)]
name: Build Application
on:
  pull_request:
    branches:
      - main
  push:
    branches:
      - main

env:
  TUIST_TOKEN: ${{ secrets.TUIST_TOKEN }}

jobs:
  build:
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v4
      - run: brew install --formula tuist@x.y.z
      - run: tuist setup cache
```
<!-- -->
:::

::: info OIDC SETUP
<!-- -->
OIDC kimlik doğrulamasını kullanmadan önce,
<LocalizedLink href="/guides/integrations/gitforge/github"> GitHub deponuzu</LocalizedLink> Tuist projenize bağlamanız gerekir. OIDC'nin çalışması
için `permissions: id-token: write` gereklidir. Alternatif olarak, `TUIST_TOKEN`
secret ile bir
<LocalizedLink href="/guides/server/authentication#project-tokens">proje belirteci</LocalizedLink> kullanabilirsiniz.
<!-- -->
:::

::: tip
<!-- -->
Tuist'in sürümünü ortamlar arasında sabitlemek için Tuist projelerinizde `mise
use --pin` kullanmanızı öneririz. Komut, Tuist sürümünü içeren bir
`.tool-versions` dosyası oluşturacaktır.
<!-- -->
:::

### Xcode Bulut {#xcode-cloud}

Xcode projelerini doğruluk kaynağı olarak kullanan [Xcode
Cloud](https://developer.apple.com/xcode-cloud/)'da, Tuist'i yüklemek ve
ihtiyacınız olan komutları çalıştırmak için bir
[post-clone](https://developer.apple.com/documentation/xcode/writing-custom-build-scripts#Create-a-custom-build-script)
komut dosyası eklemeniz gerekir, örneğin `tuist generate`:

::: code-group

```bash [Mise]
#!/bin/sh

# Mise installation taken from https://mise.jdx.dev/continuous-integration.html#xcode-cloud
curl https://mise.run | sh # Install Mise
export PATH="$HOME/.local/bin:$PATH"

mise install # Installs the version from .mise.toml

# Runs the version of Tuist indicated in the .mise.toml file {#runs-the-version-of-tuist-indicated-in-the-misetoml-file}
mise exec -- tuist install --path ../ # `--path` needed as this is run from within the `ci_scripts` directory
mise exec -- tuist generate -p ../ --no-open # `-p` needed as this is run from within the `ci_scripts` directory
```
```bash [Homebrew]
#!/bin/sh
brew install --formula tuist@x.y.z

tuist generate
```
<!-- -->
:::

::: info AUTHENTICATION
<!-- -->
Xcode Cloud iş akışı ayarlarınızda `TUIST_TOKEN` ortam değişkenini ayarlayarak
bir <LocalizedLink href="/guides/server/authentication#project-tokens">proje belirteci</LocalizedLink> kullanın.
<!-- -->
:::

### CircleCI {#circleci}

CircleCI](https://circleci.com) üzerinde güvenli, gizlilik içermeyen kimlik
doğrulaması için
<LocalizedLink href="/guides/server/authentication#oidc-tokens">OIDC kimlik doğrulamasını</LocalizedLink> kullanabilirsiniz:

::: code-group
```yaml [OIDC (Mise)]
version: 2.1
jobs:
  build:
    macos:
      xcode: "15.0.1"
    steps:
      - checkout
      - run:
          name: Install Mise
          command: |
            curl https://mise.jdx.dev/install.sh | sh
            echo 'export PATH="$HOME/.local/bin:$PATH"' >> $BASH_ENV
      - run:
          name: Install Tuist
          command: mise install
      - run:
          name: Authenticate
          command: mise exec -- tuist auth login
      - run:
          name: Build
          command: mise exec -- tuist setup cache
```
```yaml [Project token (Mise)]
version: 2.1
jobs:
  build:
    macos:
      xcode: "15.0.1"
    environment:
      TUIST_TOKEN: $TUIST_TOKEN
    steps:
      - checkout
      - run:
          name: Install Mise
          command: |
            curl https://mise.jdx.dev/install.sh | sh
            echo 'export PATH="$HOME/.local/bin:$PATH"' >> $BASH_ENV
      - run:
          name: Install Tuist
          command: mise install
      - run:
          name: Build
          command: mise exec -- tuist setup cache
```
<!-- -->
:::

::: info AUTHENTICATION
<!-- -->
OIDC kimlik doğrulamasını kullanmadan önce
<LocalizedLink href="/guides/integrations/gitforge/github"> GitHub deponuzu</LocalizedLink> Tuist projenize bağlamanız gerekir. CircleCI OIDC
belirteçleri, Tuist'in projelerinize erişimi yetkilendirmek için kullandığı
bağlı GitHub deponuzu içerir. Alternatif olarak, `TUIST_TOKEN` ortam değişkeni
ile bir <LocalizedLink href="/guides/server/authentication#project-tokens">proje belirteci</LocalizedLink> kullanabilirsiniz.
<!-- -->
:::

### Bitrise {#bitrise}

Bitrise](https://bitrise.io) üzerinde güvenli, gizlilik içermeyen kimlik
doğrulaması için
<LocalizedLink href="/guides/server/authentication#oidc-tokens">OIDC kimlik doğrulamasını</LocalizedLink> kullanabilirsiniz:

::: code-group
```yaml [OIDC (Mise)]
workflows:
  build:
    steps:
      - git-clone@8: {}
      - script@1:
          title: Install Mise
          inputs:
            - content: |
                curl https://mise.jdx.dev/install.sh | sh
                echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
      - script@1:
          title: Install Tuist
          inputs:
            - content: mise install
      - get-identity-token@0:
          inputs:
          - audience: tuist
      - script@1:
          title: Authenticate
          inputs:
            - content: mise exec -- tuist auth login
      - script@1:
          title: Build
          inputs:
            - content: mise exec -- tuist setup cache
```
```yaml [Project token (Mise)]
workflows:
  build:
    steps:
      - git-clone@8: {}
      - script@1:
          title: Install Mise
          inputs:
            - content: |
                curl https://mise.jdx.dev/install.sh | sh
                echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
      - script@1:
          title: Install Tuist
          inputs:
            - content: mise install
      - script@1:
          title: Build
          inputs:
            - content: mise exec -- tuist setup cache
```
<!-- -->
:::

::: info AUTHENTICATION
<!-- -->
OIDC kimlik doğrulamasını kullanmadan önce,
<LocalizedLink href="/guides/integrations/gitforge/github"> GitHub deponuzu</LocalizedLink> Tuist projenize bağlamanız gerekir. Bitrise OIDC
belirteçleri, Tuist'in projelerinize erişimi yetkilendirmek için kullandığı
bağlı GitHub deponuzu içerir. Alternatif olarak, `TUIST_TOKEN` ortam değişkeni
ile bir <LocalizedLink href="/guides/server/authentication#project-tokens">proje belirteci</LocalizedLink> kullanabilirsiniz.
<!-- -->
:::

### Codemagic {#codemagic}

Codemagic](https://codemagic.io)'de, Tuist'i yüklemek için iş akışınıza ek bir
adım ekleyebilirsiniz:

::: code-group
```yaml [Mise]
workflows:
  build:
    name: Build
    max_build_duration: 30
    environment:
      xcode: 15.0.1
      vars:
        TUIST_TOKEN: ${{ secrets.TUIST_TOKEN }}
    scripts:
      - name: Install Mise
        script: |
          curl https://mise.jdx.dev/install.sh | sh
          mise install # Installs the version from .mise.toml
      - name: Build
        script: mise exec -- tuist setup cache
```
```yaml [Homebrew]
workflows:
  build:
    name: Build
    max_build_duration: 30
    environment:
      xcode: 15.0.1
      vars:
        TUIST_TOKEN: ${{ secrets.TUIST_TOKEN }}
    scripts:
      - name: Install Tuist
        script: |
          brew install --formula tuist@x.y.z
      - name: Build
        script: tuist setup cache
```
<!-- -->
:::

::: info AUTHENTICATION
<!-- -->
Bir <LocalizedLink href="/guides/server/authentication#project-tokens">proje belirteci</LocalizedLink> oluşturun ve bunu `TUIST_TOKEN` adlı gizli bir ortam
değişkeni olarak ekleyin.
<!-- -->
:::
