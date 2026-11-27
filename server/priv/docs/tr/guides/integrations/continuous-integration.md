---
{
  "title": "Sürekli Entegrasyon (CI)",
  "titleTemplate": ":title · Otomasyon · Kılavuzlar · Tuist",
  "description": "Tuist'i CI iş akışlarınızda nasıl kullanacağınızı öğrenin."
}
---
# Sürekli Entegrasyon (CI) {#continuous-integration-ci}

Tuist komutlarını [sürekli entegrasyon](https://en.wikipedia.org/wiki/Continuous_integration) iş akışlarınızda çalıştırmak için, CI ortamınıza kurmanız gerekir. 

Kimlik doğrulama isteğe bağlıdır ancak <.localized_link href="/guides/features/cache">önbellek</.localized_link> gibi sunucu tarafı özellikleri kullanmak istiyorsanız gereklidir. Tuist kurulduktan sonra CI çalıştırma sürelerini kısaltmak ve maliyetlerini düşürmek için [Yavaş derlemeler](https://tuist.dev/solutions/slow-builds) ve [CI maliyetleri](https://tuist.dev/solutions/ci-costs) bölümlerine bakın.

Aşağıdaki bölümler, bunu farklı CI platformlarında nasıl yapacağınıza dair örnekler sunar. Struo, kendi yerel Tuist sağlayıcısı üzerinden bağlanır; Tuist CLI'ye ihtiyaç duymaz. Bu iş akışı için [Struo](#struo) bölümüne bakın.

## Struo {#struo}

<a id="once"></a>

Sağlayıcıyı ve önbellek bağlamasını <.localized_link href="/guides/get-started/struo-project">Struo ile başlayın</.localized_link> kılavuzundan commit edin. Struo'yu iş içinde [Struo'nun kurulum talimatları](https://struo.run/docs/guide/getting-started)nı kullanarak kurun, ardından önbelleğe alınabilir işleri çalıştırmadan önce kimlik doğrulaması yapın.

GitHub Actions, CircleCI ve Bitrise, Struo'nun etkileşimsiz OpenID Connect girişini destekler. Depoyu Tuist projenize <.localized_link href="/guides/server/authentication#oidc-tokens">OIDC kimlik doğrulaması</.localized_link> bölümünde açıklandığı şekilde bağlayın. GitHub Actions'ta identity-token iznini verin:

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

Hedeflerinizin gerektirdiği araç zincirlerine sahip bir işletim sistemi seçin. `MyTarget` yerine hedefinizi yazın ve Struo'yu mevcut araç kurulum iş akışınız üzerinden sabitleyin. Elde edilen oturum, iş sırasında önbellek erişimi, raporlama ve yapıt yayınlama için yeniden kullanılır.

Diğer sağlayıcılarda, ihtiyacınız olan işlemler için yetkilendirilmiş bir <.localized_link href="/guides/server/authentication#account-tokens">hesap jetonu</.localized_link> kullanmak üzere `TUIST_TOKEN` değerini ayarlayın. Bunu CI gizli depo alanında saklayın; asla `struo.toml` veya iş akışı kaynağında tutmayın. Bu jetonu kullanırken etkileşimli bir giriş adımına gerek yoktur.

Çoklu çalışan grupları için <.localized_link href="/guides/features/test-sharding/struo">Struo test parçalama</.localized_link> kılavuzunu takip edin. Uygulamaları yayınlamak için açık bir <.localized_link href="/guides/features/previews/struo">Struo önizleme yayınlama</.localized_link> adımı ekleyin. Normal derlemeler önizlemeleri örtük olarak yayınlamaz.

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
> OIDC kimlik doğrulamasını kullanmadan önce, GitHub deponuzu Tuist projenize <.localized_link href="/guides/integrations/gitforge/github">bağlamanız</.localized_link> gerekir. OIDC'nin çalışması için `permissions: id-token: write` gereklidir. Tuist 4.218.0'dan itibaren CLI, ilk isteğinde kimlik jetonunu değiştirir, bu nedenle iş akışında `tuist auth login` adımına gerek yoktur; önceki sürümlerde diğer Tuist komutlarından önce `tuist auth login` çalıştırın. Alternatif olarak, `TUIST_TOKEN` gizli anahtarıyla bir <.localized_link href="/guides/server/authentication#account-tokens">hesap jetonu</.localized_link> kullanabilirsiniz.


> [!TIP]
> Tuist projelerinizde `mise use --pin` kullanarak Tuist sürümünü ortamlar arasında sabitlemenizi öneririz. Bu komut, Tuist sürümünü `mise.toml` dosyanıza sabitler.


### Xcode Cloud {#xcode-cloud}

Gerçek kaynak olarak Xcode projelerini kullanan [Xcode Cloud](https://developer.apple.com/xcode-cloud/)'da, Tuist'i kurmak ve ihtiyaç duyduğunuz komutları çalıştırmak için bir [post-clone](https://developer.apple.com/documentation/xcode/writing-custom-build-scripts#Create-a-custom-build-script) betiği eklemeniz gerekir, örneğin `tuist generate`:

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
> Xcode Cloud iş akışı ayarlarınızda `TUIST_TOKEN` ortam değişkenini ayarlayarak bir <.localized_link href="/guides/server/authentication#account-tokens">hesap jetonu</.localized_link> kullanın.


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
> OIDC kimlik doğrulamasını kullanmadan önce, GitHub deponuzu Tuist projenize <.localized_link href="/guides/integrations/gitforge/github">bağlamanız</.localized_link> gerekir. CircleCI OIDC jetonları, bağlı GitHub deponuzu içerir; Tuist bunu projelerinize erişimi yetkilendirmek için kullanır. Tuist 4.218.0'dan itibaren CLI, ilk isteğinde kimlik jetonunu değiştirir, bu nedenle `tuist auth login` adımına gerek yoktur; önceki sürümlerde diğer Tuist komutlarından önce `mise exec -- tuist auth login` çalıştırın. Alternatif olarak, `TUIST_TOKEN` ortam değişkeniyle bir <.localized_link href="/guides/server/authentication#account-tokens">hesap jetonu</.localized_link> kullanabilirsiniz.


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
> OIDC kimlik doğrulamasını kullanmadan önce, GitHub deponuzu Tuist projenize <.localized_link href="/guides/integrations/gitforge/github">bağlamanız</.localized_link> gerekir. Bitrise OIDC jetonları, bağlı GitHub deponuzu içerir; Tuist bunu projelerinize erişimi yetkilendirmek için kullanır. Tuist 4.218.0'dan itibaren CLI, ilk isteğinde kimlik jetonunu değiştirir, bu nedenle `tuist auth login` adımına gerek yoktur; önceki sürümlerde diğer Tuist komutlarından önce `mise exec -- tuist auth login` çalıştırın. Alternatif olarak, `TUIST_TOKEN` ortam değişkeniyle bir <.localized_link href="/guides/server/authentication#account-tokens">hesap jetonu</.localized_link> kullanabilirsiniz.


### Codemagic {#codemagic}

[Codemagic](https://codemagic.io)'de, Tuist'i kurmak için iş akışınıza ek bir adım ekleyebilirsiniz:

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
> Bir <.localized_link href="/guides/server/authentication#account-tokens">hesap jetonu</.localized_link> oluşturun ve bunu `TUIST_TOKEN` adlı gizli bir ortam değişkeni olarak ekleyin.

### Appcircle {#appcircle}

[Appcircle](https://appcircle.io)'de, yerleşik [Tuist Install](https://docs.appcircle.io/workflows/ios-specific-workflow-steps/tuist-install) ve [Tuist Commands](https://docs.appcircle.io/workflows/ios-specific-workflow-steps/tuist-commands) iş akışı adımlarını kullanabilir veya Tuist'i kendiniz kurmak için **Git Clone** adımından sonra bir **Custom Script** adımı ekleyebilirsiniz:

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
> Tuist Install adımı, Tuist'i Homebrew ile kurar ve `tuist generate` komutunu çalıştırır. Sürümü sabitlemek için **Tuist Version** girdisini ayarlayın, ardından `tuist test` veya `tuist build` gibi komutları çalıştırmak üzere bir Tuist Commands adımı ekleyin.

> [!NOTE]
> **Kimlik Doğrulama**
>
> Bir <.localized_link href="/guides/server/authentication#account-tokens">hesap jetonu</.localized_link> oluşturun, bunu bir [ortam değişkeni grubuna](https://docs.appcircle.io/build/build-environment-variables) `TUIST_TOKEN` adlı bir değişken olarak ekleyin ve derleme yapılandırmanızda bu grubu seçin. Değişkeni kilit simgesiyle gizli olarak işaretleyin.

## xcodebuild çıktı biçimlendirme {#xcodebuild-output-formatting}

`tuist build`, `tuist test`, `tuist xcodebuild build` ve `tuist xcodebuild test`, `xcodebuild` çıktısını [xcbeautify](https://github.com/cpisciotta/xcbeautify) biçimlendiricisiyle biçimlendirir; bu nedenle bu komutları kendiniz xcbeautify üzerinden yönlendirmenize gerek yoktur. GitHub Actions'ta, `GITHUB_ACTIONS` ortam değişkeni aracılığıyla algılanır ve Tuist, xcbeautify'ın GitHub Actions oluşturucusunu kullanır; bu oluşturucu, derleyici uyarılarını, hataları ve test başarısızlıklarını çalıştırma özetinde ve çekme isteğinde açıklama olarak gösterir. Diğer tüm yerlerde terminal oluşturucusunu kullanır; çıktı başka bir yere yönlendirilmedikçe veya `NO_COLOR` ayarlanmadıkça renklidir.

Net bir hata olmadan bir derleme başarısız olduğunda olduğu gibi, `xcodebuild` biçimlendirilmemiş çıktısını yazdırmak için `--verbose` parametresini geçirin.

Bir iş `xcodebuild` komutunu Tuist üzerinden değil de doğrudan çağırıyorsa, bunu kendiniz xcbeautify üzerinden yönlendirin ve başarısız bir derlemenin adımı yine de başarısız kılması için `pipefail` ayarını yapın:

```bash
set -o pipefail
xcodebuild test -scheme App | xcbeautify --renderer github-actions
```

## Çalıştırma raporu {#run-report}

Tuist bir çalıştırmayı yüklediğinde, buna ait panodaki URL'ler günlüklere yazdırılır. Günlükleri kazımadan bunlara erişmek için — örneğin bir iş başarısız olduğunda test raporu bağlantısını Slack'e göndermek veya bir çalıştırmayı kendi araçlarınıza aktarmak amacıyla — `tuist test`, `tuist xcodebuild test` veya `tuist xcodebuild build` komutlarına `--run-report-path` parametresini geçirin (veya `TUIST_RUN_REPORT_PATH` ayarlayın). Tuist, çalıştırma yüklendikten sonra JSON raporunu belirtilen yola yazar:

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
| `runId` | dize | Çalıştırmanın benzersiz tanımlayıcısı. |
| `status` | dize | `"success"` veya `"failure"`. |
| `runURL` | dize | Çalıştırma için panodaki URL. Her zaman mevcuttur. |
| `testRunURL` | dize? | Test çalıştırması için panodaki URL; komut testleri çalıştırdığında mevcuttur. |
| `buildRunURL` | dize? | Derleme çalıştırması için panodaki URL; komut derleme yaptığında mevcuttur. |
| `testRuns` | dizi | Şema başına test sonuçları: `scheme`, `succeeded`, `totalTests`, `skippedTests`, `ranTests`, `failedTestNames`, `ranTestModules` ve `skippedTestModules`. Test sayıları test durumlarını ifade eder ve `skippedTests` sonuç paketinin atlanmış olarak bildirdiği testlerin sayısını verir. `skippedTestModules`, <.localized_link href="/guides/features/selective-testing">seçici test</.localized_link> tarafından atlanan test modüllerinin sayısını verir ve seçici test uygulanmadığında veya çalıştırma bir test parçası olduğunda atlanır. |
| `buildRuns` | dizi | Şema başına derleme sonuçları: `scheme`, `succeeded`, `durationInSeconds`. |

`testRunURL` ve `buildRunURL` bağımsızdır: hem derleme hem de test yapan bir komut her ikisini de yazar; oysa günlükler bunu yapamaz — çalıştırma başına yalnızca bir URL yazdırırlar.

> [!NOTE]
> **Raporun ne zaman yazıldığı**
>
> Rapor yalnızca sunucuya yüklenen çalıştırmalar için yazılır; bu işlem kimlik doğrulama gerektirir ve CI üzerinde otomatik olarak gerçekleşir. Yol, her çalıştırmanın başında temizlenir; bu nedenle rapor üretmeyen bir çalıştırma, önceki bir çalıştırmadan kalan eski bir rapor yerine hiçbir şey bırakmaz.

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
