---
{
  "title": "Sürekli Entegrasyon (CI)",
  "titleTemplate": ":title · Otomasyon · Kılavuzlar · Tuist",
  "description": "Tuist'i CI iş akışlarınızda nasıl kullanacağınızı öğrenin."
}
---
# Sürekli Entegrasyon (CI) {#continuous-integration-ci}

[Sürekli entegrasyon](https://en.wikipedia.org/wiki/Continuous_integration) iş akışlarınızda Tuist komutlarını çalıştırmak için onu CI ortamınıza yüklemeniz gerekir. 

Kimlik doğrulama isteğe bağlıdır, ancak <.localized_link href="/guides/features/cache">önbellek</.localized_link> gibi sunucu tarafı özellikleri kullanmak istiyorsanız gereklidir. Tuist yüklendikten sonra CI çalıştırma sürelerini kısaltmak ve maliyetlerini düşürmek için [Yavaş derlemeler](https://tuist.dev/solutions/slow-builds) ve [CI maliyetleri](https://tuist.dev/solutions/ci-costs) bölümlerine bakın.

Aşağıdaki bölümler bunu farklı CI platformlarında nasıl yapacağınıza ilişkin örnekler sunar. Struo, kendi yerel Tuist sağlayıcısı üzerinden bağlanır; Tuist CLI’ye ihtiyaç duymaz. Bu iş akışı için [Struo](#struo) bölümüne bakın.

## Struo {#struo}

<a id="once"></a>

Sağlayıcıyı ve önbellek bağlamasını <.localized_link href="/guides/get-started/struo-project">Struo ile başlayın</.localized_link> kılavuzundaki talimatlara göre commit edin. Struo’yu iş içinde [Struo’nun kurulum talimatları](https://struo.run/docs/guide/getting-started)nı kullanarak yükleyin, ardından önbelleklenebilir işleri çalıştırmadan önce kimlik doğrulaması yapın.

GitHub Actions, CircleCI ve Bitrise, Struo’nun tarayıcı gerektirmeyen OpenID Connect oturum açma yöntemini destekler. Depoyu Tuist projenize <.localized_link href="/guides/server/authentication#oidc-tokens">OIDC kimlik doğrulaması</.localized_link> bölümünde açıklandığı gibi bağlayın. GitHub Actions üzerinde identity-token iznini verin:

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
      # Pin Struo in your repository's mise.toml.
      - run: struo auth login --provider tuist --no-browser
      - run: struo build MyTarget
      - run: struo test
```

Hedeflerinizin gerektirdiği araç zincirlerine sahip bir işletim sistemi seçin. `MyTarget` ifadesini hedefinizle değiştirin ve Struo’yu mevcut araç yükleme iş akışınız aracılığıyla sabitleyin. Elde edilen oturum, iş sırasında önbellek erişimi, raporlama ve yapıt yayınlama için yeniden kullanılır.

Diğer sağlayıcılarda, ihtiyacınız olan işlemler için yetkilendirilmiş bir <.localized_link href="/guides/server/authentication#account-tokens">hesap jetonu</.localized_link> kullanmak üzere `TUIST_TOKEN` değişkenini ayarlayın. Bunu CI gizli depo alanında saklayın; asla `struo.toml` dosyasında veya iş akışı kaynak kodunda tutmayın. Bu jetonu kullanırken etkileşimli bir oturum açma adımına gerek yoktur.

Çoklu çalışanlı paketler için <.localized_link href="/guides/features/test-sharding/struo">Struo test parçalama</.localized_link> kılavuzunu takip edin. Uygulamaları yayınlamak için açık bir <.localized_link href="/guides/features/previews/struo">Struo önizleme yayınlama</.localized_link> adımı ekleyin. Normal derlemeler önizlemeleri örtük olarak yayınlamaz.

## Örnekler {#examples}

### GitHub Actions {#github-actions}

[GitHub Actions](https://docs.github.com/en/actions) üzerinde güvenli ve gizli anahtar gerektirmeyen kimlik doğrulama için <.localized_link href="/guides/server/authentication#oidc-tokens">OIDC kimlik doğrulaması</.localized_link>nı kullanabilirsiniz:

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
> OIDC kimlik doğrulamasını kullanmadan önce GitHub deponuzu Tuist projenize <.localized_link href="/guides/integrations/gitforge/github">bağlamanız</.localized_link> gerekir. OIDC’nin çalışması için `permissions: id-token: write` gereklidir. Tuist 4.218.0’dan itibaren CLI, ilk isteğinde kimlik jetonunu takas eder; bu nedenle iş akışında `tuist auth login` adımına gerek yoktur; daha eski sürümlerde diğer Tuist komutlarından önce `tuist auth login` komutunu çalıştırın. Alternatif olarak, `TUIST_TOKEN` gizli değişkeniyle birlikte bir <.localized_link href="/guides/server/authentication#account-tokens">hesap jetonu</.localized_link> kullanabilirsiniz.


> [!TIP]
> Tuist sürümünü ortamlar arasında sabitlemek için Tuist projelerinizde `mise use --pin` kullanımını öneririz. Bu komut, Tuist sürümünü `mise.toml` dosyanıza sabitler.


### Xcode Cloud {#xcode-cloud}

Gerçek kaynak olarak Xcode projelerini kullanan [Xcode Cloud](https://developer.apple.com/xcode-cloud/) ortamında, Tuist’i yüklemek ve ihtiyacınız olan komutları çalıştırmak için bir [post-clone](https://developer.apple.com/documentation/xcode/writing-custom-build-scripts#Create-a-custom-build-script) betiği eklemeniz gerekir; örneğin `tuist generate`:

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
> **Kimlik doğrulama**
>
> Xcode Cloud iş akışı ayarlarınızda `TUIST_TOKEN` ortam değişkenini ayarlayarak bir <.localized_link href="/guides/server/authentication#account-tokens">hesap jetonu</.localized_link> kullanın.


### CircleCI {#circleci}

[CircleCI](https://circleci.com) üzerinde güvenli ve gizli anahtar gerektirmeyen kimlik doğrulama için <.localized_link href="/guides/server/authentication#oidc-tokens">OIDC kimlik doğrulaması</.localized_link>nı kullanabilirsiniz:

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
> **Kimlik doğrulama**
>
> OIDC kimlik doğrulamasını kullanmadan önce GitHub deponuzu Tuist projenize <.localized_link href="/guides/integrations/gitforge/github">bağlamanız</.localized_link> gerekir. CircleCI OIDC jetonları, bağlı GitHub deponuzu içerir; Tuist bunu projelerinize erişimi yetkilendirmek için kullanır. Tuist 4.218.0’dan itibaren CLI, ilk isteğinde kimlik jetonunu takas eder; bu nedenle `tuist auth login` adımına gerek yoktur; daha eski sürümlerde diğer Tuist komutlarından önce `mise exec -- tuist auth login` komutunu çalıştırın. Alternatif olarak, `TUIST_TOKEN` ortam değişkeniyle birlikte bir <.localized_link href="/guides/server/authentication#account-tokens">hesap jetonu</.localized_link> kullanabilirsiniz.


### Bitrise {#bitrise}

[Bitrise](https://bitrise.io) üzerinde güvenli ve gizli anahtar gerektirmeyen kimlik doğrulama için <.localized_link href="/guides/server/authentication#oidc-tokens">OIDC kimlik doğrulaması</.localized_link>nı kullanabilirsiniz:

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
> **Kimlik doğrulama**
>
> OIDC kimlik doğrulamasını kullanmadan önce GitHub deponuzu Tuist projenize <.localized_link href="/guides/integrations/gitforge/github">bağlamanız</.localized_link> gerekir. Bitrise OIDC jetonları, bağlı GitHub deponuzu içerir; Tuist bunu projelerinize erişimi yetkilendirmek için kullanır. Tuist 4.218.0’dan itibaren CLI, ilk isteğinde kimlik jetonunu takas eder; bu nedenle `tuist auth login` adımına gerek yoktur; daha eski sürümlerde diğer Tuist komutlarından önce `mise exec -- tuist auth login` komutunu çalıştırın. Alternatif olarak, `TUIST_TOKEN` ortam değişkeniyle birlikte bir <.localized_link href="/guides/server/authentication#account-tokens">hesap jetonu</.localized_link> kullanabilirsiniz.


### Codemagic {#codemagic}

[Codemagic](https://codemagic.io) üzerinde, Tuist’i yüklemek için iş akışınıza ek bir adım ekleyebilirsiniz:

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
> **Kimlik doğrulama**
>
> Bir <.localized_link href="/guides/server/authentication#account-tokens">hesap jetonu</.localized_link> oluşturun ve bunu `TUIST_TOKEN` adlı gizli bir ortam değişkeni olarak ekleyin.

### Appcircle {#appcircle}

[Appcircle](https://appcircle.io) üzerinde, yerleşik [Tuist Install](https://docs.appcircle.io/workflows/ios-specific-workflow-steps/tuist-install) ve [Tuist Commands](https://docs.appcircle.io/workflows/ios-specific-workflow-steps/tuist-commands) iş akışı adımlarını kullanabilir veya Tuist’i kendiniz yüklemek için **Git Clone** adımından sonra bir **Custom Script** adımı ekleyebilirsiniz:

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
> Tuist Install adımı, Tuist’i Homebrew ile yükler ve `tuist generate` komutunu çalıştırır. Sürümü sabitlemek için **Tuist Version** girişini ayarlayın, ardından `tuist test` veya `tuist build` gibi komutları çalıştırmak üzere bir Tuist Commands adımı ekleyin.

> [!NOTE]
> **Kimlik doğrulama**
>
> Bir <.localized_link href="/guides/server/authentication#account-tokens">hesap jetonu</.localized_link> oluşturun, bunu bir [ortam değişkeni grubuna](https://docs.appcircle.io/build/build-environment-variables) `TUIST_TOKEN` adlı bir değişken olarak ekleyin ve derleme yapılandırmanızda bu grubu seçin. Değişkeni kilit simgesiyle gizli olarak işaretleyin.

## xcodebuild çıktı biçimlendirme {#xcodebuild-output-formatting}

`tuist build`, `tuist test`, `tuist xcodebuild build` ve `tuist xcodebuild test`, `xcodebuild` çıktısını [xcbeautify](https://github.com/cpisciotta/xcbeautify) biçimlendiricisiyle biçimlendirir; bu nedenle bu komutları kendiniz xcbeautify üzerinden geçirmenize gerek yoktur. GitHub Actions üzerinde, `GITHUB_ACTIONS` ortam değişkeni aracılığıyla algılanarak, Tuist xcbeautify’ın GitHub Actions oluşturucusunu kullanır; bu da derleyici uyarılarını, hataları ve test başarısızlıklarını çalışma özetinde ve çekme isteğinde açıklama olarak gösterir. Diğer tüm yerlerde terminal oluşturucusunu kullanır; çıktı başka bir komuta yönlendirilmediyse veya `NO_COLOR` ayarlanmadıysa renklidir.

Açık bir hata olmadan derleme başarısız olduğunda olduğu gibi, `xcodebuild` biçimlendirilmemiş çıktısını yazdırmak için `--verbose` parametresini iletin.

Bir iş `xcodebuild` komutunu Tuist üzerinden değil de doğrudan çağırıyorsa, bunu kendiniz xcbeautify üzerinden geçirin ve başarısız bir derlemenin adımı yine de başarısız kılması için `pipefail` ayarını yapın:

```bash
set -o pipefail
xcodebuild test -scheme App | xcbeautify --renderer github-actions
```

## Çalışma raporu {#run-report}

Tuist bir çalışmayı yüklediğinde, buna ait pano URL’leri günlüklerine yazdırılır. Günlükleri ayrıştırmadan bunlara erişmek için — örneğin bir iş başarısız olduğunda test raporu bağlantısını Slack’e göndermek veya bir çalışmayı kendi araç zincirinize aktarmak amacıyla — `tuist test`, `tuist xcodebuild test` veya `tuist xcodebuild build` komutlarına `--run-report-path` parametresini iletin (veya `TUIST_RUN_REPORT_PATH` ayarını yapın). Tuist, çalışma yüklendikten sonra belirtilen yola bir JSON raporu yazar:

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
| `runId` | dize | Çalışmanın benzersiz tanımlayıcısı. |
| `status` | dize | `"success"` veya `"failure"`. |
| `runURL` | dize | Çalışma için pano URL’si. Her zaman mevcuttur. |
| `testRunURL` | dize? | Test çalışması için pano URL’si; komut testleri çalıştırdığında mevcuttur. |
| `buildRunURL` | dize? | Derleme çalışması için pano URL’si; komut derleme yaptığında mevcuttur. |
| `testRuns` | dizi | Şema başına test sonuçları: `scheme`, `succeeded`, `totalTests`, `skippedTests`, `ranTests`, `failedTestNames`, `ranTestModules` ve `skippedTestModules`. Test sayıları test senaryolarını ifade eder; `skippedTests` ise sonuç paketinde atlanmış olarak bildirilenleri sayar. `skippedTestModules`, <.localized_link href="/guides/features/selective-testing">seçici test</.localized_link> tarafından atlanan test modüllerini sayar ve seçici test uygulanmadığında veya çalışma bir test parçası olduğunda atlanır. |
| `buildRuns` | dizi | Şema başına derleme sonuçları: `scheme`, `succeeded`, `durationInSeconds`. |

`testRunURL` ve `buildRunURL` bağımsızdır: hem derleme hem de test yapan bir komut her ikisini de yazar; günlükler bunu yapamaz — çalışma başına yalnızca bir URL yazdırırlar.

> [!NOTE]
> **Raporun ne zaman yazıldığı**
>
> Rapor yalnızca sunucuya yüklenen çalışmalar için yazılır; bu işlem kimlik doğrulama gerektirir ve CI üzerinde otomatik olarak gerçekleşir. Yol, her çalışmanın başında temizlenir; bu nedenle rapor üretmeyen bir çalışma, önceki bir çalışmadan kalan eski bir rapor yerine hiçbir şey bırakmaz.

GitLab CI üzerinde, yaygın bir kullanım durumu bir URL’yi sonraki işlere bir [`dotenv` raporu](https://docs.gitlab.com/ci/yaml/artifacts_reports/#artifactsreportsdotenv) aracılığıyla açmaktır:

```yaml
test:
  script:
    - tuist test --run-report-path tuist-run.json
    - echo "TUIST_TEST_RUN_URL=$(jq -r '.testRunURL // empty' tuist-run.json)" >> run.env
  artifacts:
    reports:
      dotenv: run.env
```
