---
{
  "title": "Sürekli Entegrasyon (CI)",
  "titleTemplate": ":title · Otomasyon · Kılavuzlar · Tuist",
  "description": "Tuist'i CI iş akışlarınızda nasıl kullanacağınızı öğrenin."
}
---
# Sürekli Entegrasyon (CI) {#continuous-integration-ci}

Tuist komutlarını [sürekli entegrasyon](https://en.wikipedia.org/wiki/Continuous_integration) iş akışlarınızda çalıştırmak için CI ortamınıza kurmanız gerekir. 

Kimlik doğrulama isteğe bağlıdır ancak <.localized_link href="/guides/features/cache">önbellek</.localized_link> gibi sunucu tarafı özellikleri kullanmak istiyorsanız gereklidir. 

Aşağıdaki bölümler, bunu farklı CI platformlarında nasıl yapacağınıza dair örnekler sunar. Once, kendi yerel Tuist sağlayıcısı üzerinden bağlanır; Tuist CLI'ye ihtiyaç duymaz. Bu iş akışı için bkz. [Once](#once).

## Once {#once}

Sağlayıcıyı ve önbellek bağlamasını <.localized_link href="/guides/get-started/once-project">Once ile Başlangıç</.localized_link> kılavuzundan commit edin. [Once'in kurulum talimatları](https://buildonce.dev/docs/guide/getting-started)nı kullanarak Once'i job'a kurun, ardından önbelleklenebilir işleri çalıştırmadan önce kimlik doğrulaması yapın.

GitHub Actions, CircleCI ve Bitrise, Once'in etkileşimsiz OpenID Connect girişini destekler. Depoyu Tuist projenize <.localized_link href="/guides/server/authentication#oidc-tokens">OIDC kimlik doğrulaması</.localized_link> bölümünde açıklandığı gibi bağlayın. GitHub Actions'ta identity-token iznini verin:

```yaml
permissions:
  id-token: write
  contents: read

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v6
      - uses: jdx/mise-action@v2
      # Pin Once in your repository's mise.toml.
      - run: once auth login --provider tuist --no-browser
      - run: once build MyTarget
      - run: once test
```

Hedeflerinizin gerektirdiği araç zincirlerine sahip bir işletim sistemi seçin. `MyTarget` yerine hedefinizi yazın ve mevcut araç kurulum iş akışınız aracılığıyla Once sürümünü sabitleyin. Elde edilen oturum, job sırasında önbellek erişimi, raporlama ve yapıt yayınlama için yeniden kullanılır.

Diğer sağlayıcılarda, ihtiyacınız olan işlemler için yetkilendirilmiş bir <.localized_link href="/guides/server/authentication#account-tokens">hesap token'ı</.localized_link> kullanmak üzere `TUIST_TOKEN` değerini ayarlayın. Bunu CI gizli depo alanında saklayın; asla `once.toml` veya iş akışı kaynağında tutmayın. Bu token'ı kullanırken etkileşimli bir giriş adımına gerek yoktur.

Çoklu çalışanlı kümeler için <.localized_link href="/guides/features/test-sharding/once">Once test parçalama</.localized_link> kılavuzunu takip edin. Uygulamaları yayınlamak için açık bir <.localized_link href="/guides/features/previews/once">Once önizleme yayınlama</.localized_link> adımı ekleyin. Normal derlemeler önizlemeleri örtük olarak yayınlamaz.

## Örnekler {#examples}

### GitHub Actions {#github-actions}

[GitHub Actions](https://docs.github.com/en/actions) üzerinde güvenli ve gizli anahtarsız kimlik doğrulama için <.localized_link href="/guides/server/authentication#oidc-tokens">OIDC kimlik doğrulaması</.localized_link>nı kullanabilirsiniz:

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
```yaml [Account token (Mise)]
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
```yaml [Account token (Homebrew)]
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

> [!NOTE]
> **OIDC kurulumu**
>
> OIDC kimlik doğrulamasını kullanmadan önce GitHub deponuzu Tuist projenize <.localized_link href="/guides/integrations/gitforge/github">bağlamanız</.localized_link> gerekir. OIDC'nin çalışması için `permissions: id-token: write` gereklidir. Alternatif olarak, `TUIST_TOKEN` gizli anahtarıyla birlikte bir <.localized_link href="/guides/server/authentication#account-tokens">hesap token'ı</.localized_link> kullanabilirsiniz.


> [!TIP]
> Tuist sürümünü ortamlar arasında sabitlemek için Tuist projelerinizde `mise use --pin` kullanımını öneririz. Bu komut, Tuist sürümünü `mise.toml` dosyanıza sabitler.


### Xcode Cloud {#xcode-cloud}

Kaynak doğruluk olarak Xcode projelerini kullanan [Xcode Cloud](https://developer.apple.com/xcode-cloud/) ortamında, Tuist'i kurmak ve ihtiyacınız olan komutları çalıştırmak için bir [post-clone](https://developer.apple.com/documentation/xcode/writing-custom-build-scripts#Create-a-custom-build-script) betiği eklemeniz gerekir, örneğin `tuist generate`:

::: code-group

```bash [Mise]
#!/bin/sh

# Mise installation taken from https://mise.jdx.dev/continuous-integration.html#xcode-cloud
curl https://mise.run | sh # Install Mise
export PATH="$HOME/.local/bin:$PATH"

mise install # Installs the version from mise.toml

# Runs the version of Tuist indicated in the mise.toml file
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

> [!NOTE]
> **Kimlik Doğrulama**
>
> Xcode Cloud iş akışı ayarlarınızda `TUIST_TOKEN` ortam değişkenini ayarlayarak bir <.localized_link href="/guides/server/authentication#account-tokens">hesap token'ı</.localized_link> kullanın.


### CircleCI {#circleci}

[CircleCI](https://circleci.com) üzerinde güvenli ve gizli anahtarsız kimlik doğrulama için <.localized_link href="/guides/server/authentication#oidc-tokens">OIDC kimlik doğrulaması</.localized_link>nı kullanabilirsiniz:

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
```yaml [Account token (Mise)]
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

> [!NOTE]
> **Kimlik Doğrulama**
>
> OIDC kimlik doğrulamasını kullanmadan önce GitHub deponuzu Tuist projenize <.localized_link href="/guides/integrations/gitforge/github">bağlamanız</.localized_link> gerekir. CircleCI OIDC token'ları, bağlı GitHub deponuzu içerir; Tuist bunu projelerinize erişimi yetkilendirmek için kullanır. Alternatif olarak, `TUIST_TOKEN` ortam değişkeniyle birlikte bir <.localized_link href="/guides/server/authentication#account-tokens">hesap token'ı</.localized_link> kullanabilirsiniz.


### Bitrise {#bitrise}

[Bitrise](https://bitrise.io) üzerinde güvenli ve gizli anahtarsız kimlik doğrulama için <.localized_link href="/guides/server/authentication#oidc-tokens">OIDC kimlik doğrulaması</.localized_link>nı kullanabilirsiniz:

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
```yaml [Account token (Mise)]
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

> [!NOTE]
> **Kimlik Doğrulama**
>
> OIDC kimlik doğrulamasını kullanmadan önce GitHub deponuzu Tuist projenize <.localized_link href="/guides/integrations/gitforge/github">bağlamanız</.localized_link> gerekir. Bitrise OIDC token'ları, bağlı GitHub deponuzu içerir; Tuist bunu projelerinize erişimi yetkilendirmek için kullanır. Alternatif olarak, `TUIST_TOKEN` ortam değişkeniyle birlikte bir <.localized_link href="/guides/server/authentication#account-tokens">hesap token'ı</.localized_link> kullanabilirsiniz.


### Codemagic {#codemagic}

[Codemagic](https://codemagic.io) içinde, Tuist'i kurmak için iş akışınıza ek bir adım ekleyebilirsiniz:

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
          mise install # Installs the version from mise.toml
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

> [!NOTE]
> **Kimlik Doğrulama**
>
> Bir <.localized_link href="/guides/server/authentication#account-tokens">hesap token'ı</.localized_link> oluşturun ve bunu `TUIST_TOKEN` adlı gizli bir ortam değişkeni olarak ekleyin.

### Appcircle {#appcircle}

[Appcircle](https://appcircle.io) içinde, yerleşik [Tuist Install](https://docs.appcircle.io/workflows/ios-specific-workflow-steps/tuist-install) ve [Tuist Commands](https://docs.appcircle.io/workflows/ios-specific-workflow-steps/tuist-commands) iş akışı adımlarını kullanabilir veya Tuist'i kendiniz kurmak için **Git Clone** adımından sonra bir **Custom Script** adımı ekleyebilirsiniz:

::: code-group
```bash [Mise]
cd $AC_REPOSITORY_DIR
curl https://mise.jdx.dev/install.sh | sh
export PATH="$HOME/.local/bin:$PATH"
mise install
mise exec -- tuist setup cache
```
```bash [Homebrew]
cd $AC_REPOSITORY_DIR
brew install --formula tuist@x.y.z
tuist setup cache
```
<!-- -->
:::

> [!NOTE]
> **İş akışı adımları**
>
> Tuist Install adımı, Tuist'i Homebrew ile kurar ve `tuist generate` komutunu çalıştırır. Sürümü sabitlemek için **Tuist Version** girişini ayarlayın, ardından `tuist test` veya `tuist build` gibi komutları çalıştırmak için bir Tuist Commands adımı ekleyin.

> [!NOTE]
> **Kimlik Doğrulama**
>
> Bir <.localized_link href="/guides/server/authentication#account-tokens">hesap token'ı</.localized_link> oluşturun, bunu bir [ortam değişkeni grubuna](https://docs.appcircle.io/build/build-environment-variables) `TUIST_TOKEN` adlı bir değişken olarak ekleyin ve derleme yapılandırmanızda bu grubu seçin. Değişkeni kilit simgesiyle gizli olarak işaretleyin.

## Çalıştırma raporu {#run-report}

Tuist bir çalıştırmayı yüklediğinde, buna ait gösterge paneli URL'leri günlüklere yazdırılır. Günlükleri ayrıştırmadan bu URL'lere ulaşmak için — örneğin bir iş başarısız olduğunda test raporu bağlantısını Slack'e göndermek veya bir çalıştırmayı kendi araçlarınıza aktarmak amacıyla — `tuist test`, `tuist xcodebuild test` veya `tuist xcodebuild build` komutlarına `--run-report-path` parametresini geçirin (veya `TUIST_RUN_REPORT_PATH` ortam değişkenini ayarlayın). Tuist, çalıştırma yüklendikten sonra belirtilen yola bir JSON raporu yazar:

```json
{
  "runId": "0193f8c1-...",
  "status": "success",
  "runURL": "https://tuist.dev/acme/app/runs/0193f8c1-...",
  "testRunURL": "https://tuist.dev/acme/app/tests/test-runs/...",
  "buildRunURL": "https://tuist.dev/acme/app/builds/build-runs/...",
  "testRuns": [
    {
      "scheme": "App",
      "succeeded": true,
      "totalTests": 42,
      "skippedTests": 0,
      "ranTests": 42,
      "failedTestNames": [],
      "ranTestModules": 3,
      "skippedTestModules": 5
    }
  ],
  "buildRuns": [
    { "scheme": "App", "succeeded": true, "durationInSeconds": 12.3 }
  ]
}
```

| Alan | Tür | Açıklama |
| - | - | - |
| `runId` | string | Çalıştırmanın benzersiz tanımlayıcısı. |
| `status` | string | `"success"` veya `"failure"`. |
| `runURL` | string | Çalıştırma için gösterge paneli URL'si. Her zaman mevcuttur. |
| `testRunURL` | string? | Test çalıştırması için gösterge paneli URL'si; komut testleri çalıştırdığında mevcuttur. |
| `buildRunURL` | string? | Derleme çalıştırması için gösterge paneli URL'si; komut derleme yaptığında mevcuttur. |
| `testRuns` | array | Şema başına test sonuçları: `scheme`, `succeeded`, `totalTests`, `skippedTests`, `ranTests`, `failedTestNames`, `ranTestModules` ve `skippedTestModules`. Test sayıları test senaryolarını ifade eder; `skippedTests` ise sonuç paketinin atlanmış olarak bildirdiği senaryo sayısını verir. `skippedTestModules`, <.localized_link href="/guides/features/selective-testing">seçici test</.localized_link> tarafından atlanan test modüllerinin sayısını verir ve seçici test uygulanmadığında veya çalıştırma bir test parçası olduğunda bu alan dahil edilmez. |
| `buildRuns` | array | Şema başına derleme sonuçları: `scheme`, `succeeded`, `durationInSeconds`. |

`testRunURL` ve `buildRunURL` bağımsızdır: hem derleme hem de test yapan bir komut her iki URL'yi de yazar; oysa günlükler bunu yapamaz — çalıştırma başına yalnızca bir URL yazdırırlar.

> [!NOTE]
> **Raporun ne zaman yazıldığı**
>
> Rapor yalnızca sunucuya yüklenen çalıştırmalar için yazılır; bu işlem kimlik doğrulama gerektirir ve CI ortamlarında otomatik olarak gerçekleşir. Yol, her çalıştırmanın başında temizlenir; böylece rapor üretmeyen bir çalıştırma, önceki bir çalıştırmadan kalan eski bir rapor yerine hiçbir şey bırakmaz.

GitLab CI'da yaygın bir kullanım, bir URL'yi sonraki işlere bir [`dotenv` raporu](https://docs.gitlab.com/ci/yaml/artifacts_reports/#artifactsreportsdotenv) aracılığıyla açmaktır:

```yaml
test:
  script:
    - tuist test --run-report-path tuist-run.json
    - echo "TUIST_TEST_RUN_URL=$(jq -r '.testRunURL // empty' tuist-run.json)" >> run.env
  artifacts:
    reports:
      dotenv: run.env
```
