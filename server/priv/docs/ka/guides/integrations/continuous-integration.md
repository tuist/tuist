---
{
  "title": "უწყვეტი ინტეგრაცია (CI)",
  "titleTemplate": ":title · ავტომატიზაცია · სახელმძღვანელოები · Tuist",
  "description": "შეიტყვეთ, როგორ გამოიყენოთ Tuist თქვენს CI სამუშაო პროცესებში."
}
---
# უწყვეტი ინტეგრაცია (CI) {#continuous-integration-ci}

იმისთვის, რომ Tuist-ის ბრძანებები შეასრულოთ თქვენს [უწყვეტი ინტეგრაციის](https://en.wikipedia.org/wiki/Continuous_integration) სამუშაო ნაკადებში, საჭიროა მისი დაყენება თქვენს CI გარემოში. 

ავტორიზაცია არ არის სავალდებულო, მაგრამ აუცილებელია, თუ გსურთ სერვერული ფუნქციების, მაგალითად <.localized_link href="/guides/features/cache">ქეშის</.localized_link>, გამოყენება. 

შემდეგ განყოფილებებში მოცემულია მაგალითები იმის შესახებ, თუ როგორ გააკეთოთ ეს სხვადასხვა CI პლატფორმაზე. Once უკავშირდება საკუთარი ნატიური Tuist პროვაიდერის მეშვეობით; მას Tuist CLI არ სჭირდება. ამ სამუშაო ნაკადის შესახებ იხილეთ [Once](#once).

## Once {#once}

ჩააკომიტეთ პროვაიდერი და ქეშის მიბმა <.localized_link href="/guides/get-started/once-project">Once-ის გამოყენების დაწყებიდან</.localized_link>. დააინსტალირეთ Once ჯობში [Once-ის დაყენების ინსტრუქციების](https://buildonce.dev/docs/guide/getting-started) გამოყენებით, შემდეგ კი გაიარეთ ავტორიზაცია ქეშირებადი სამუშაოს შესრულებამდე.

GitHub Actions, CircleCI და Bitrise მხარს უჭერენ Once-ის OpenID Connect-ით თავდაუსწრებელ შესვლას. დააკავშირეთ რეპოზიტორია თქვენს Tuist პროექტთან, როგორც აღწერილია <.localized_link href="/guides/server/authentication#oidc-tokens">OIDC ავტორიზაციაში</.localized_link>. GitHub Actions-ზე მიანიჭეთ identity-token წვდომა:

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

აირჩიეთ ოპერაციული სისტემა თქვენი ტარგეტებისთვის საჭირო ხელსაწყოთა ჯაჭვებით. ჩაანაცვლეთ `MyTarget` თქვენი ტარგეტით და დააფიქსირეთ Once თქვენი არსებული ხელსაწყოების დაყენების სამუშაო ნაკადის მეშვეობით. მიღებული სესია ხელახლა გამოიყენება ქეშზე წვდომის, ანგარიშგებისა და არტეფაქტების გამოქვეყნებისთვის ჯობის დროს.

სხვა პროვაიდერებზე, დააყენეთ `TUIST_TOKEN` <.localized_link href="/guides/server/authentication#account-tokens">ანგარიშის ტოკენზე</.localized_link>, რომელიც ავტორიზებულია თქვენთვის საჭირო ოპერაციებისთვის. შეინახეთ ის CI საიდუმლოების საცავში, არასდროს `once.toml`-ში ან სამუშაო ნაკადის წყაროში. ამ ტოკენის გამოყენებისას ინტერაქტიული შესვლის ეტაპი არ არის საჭირო.

მრავალმუშაკიანი სიუიტებისთვის მიჰყევით <.localized_link href="/guides/features/test-sharding/once">Once-ის ტესტების დაშლას</.localized_link>. აპლიკაციების გამოქვეყნებისთვის დაამატეთ ცალსახა <.localized_link href="/guides/features/previews/once">Once-ის პრივიუების გამოქვეყნების</.localized_link> ეტაპი. ჩვეულებრივი ბილდები არ აქვეყნებენ პრივიუებს იმპლიციტურად.

## მაგალითები {#examples}

### GitHub Actions {#github-actions}

[GitHub Actions-ზე](https://docs.github.com/en/actions) შეგიძლიათ გამოიყენოთ <.localized_link href="/guides/server/authentication#oidc-tokens">OIDC ავტორიზაცია</.localized_link> უსაფრთხო, საიდუმლოების გარეშე ავტორიზაციისთვის:

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
> **OIDC-ის დაყენება**
>
> OIDC ავტორიზაციის გამოყენებამდე საჭიროა თქვენი GitHub რეპოზიტორიის <.localized_link href="/guides/integrations/gitforge/github">დაკავშირება</.localized_link> თქვენს Tuist პროექტთან. OIDC-ის მუშაობისთვის აუცილებელია `permissions: id-token: write`. ალტერნატიულად, შეგიძლიათ გამოიყენოთ <.localized_link href="/guides/server/authentication#account-tokens">ანგარიშის ტოკენი</.localized_link> `TUIST_TOKEN` საიდუმლოსთან ერთად.


> [!TIP]
> გირჩევთ გამოიყენოთ `mise use --pin` თქვენს Tuist პროექტებში, რათა დააფიქსიროთ Tuist-ის ვერსია გარემოებს შორის. ბრძანება აფიქსირებს Tuist-ის ვერსიას თქვენს `mise.toml` ფაილში.


### Xcode Cloud {#xcode-cloud}

[Xcode Cloud-ში](https://developer.apple.com/xcode-cloud/), რომელიც Xcode პროექტებს იყენებს როგორც ჭეშმარიტების წყაროს, საჭიროა დაამატოთ [post-clone](https://developer.apple.com/documentation/xcode/writing-custom-build-scripts#Create-a-custom-build-script) სკრიპტი Tuist-ის დასაყენებლად და საჭირო ბრძანებების შესასრულებლად, მაგალითად `tuist generate`:

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
> **ავტორიზაცია**
>
> გამოიყენეთ <.localized_link href="/guides/server/authentication#account-tokens">ანგარიშის ტოკენი</.localized_link> `TUIST_TOKEN` გარემოს ცვლადის დაყენებით თქვენს Xcode Cloud სამუშაო ნაკადის პარამეტრებში.


### CircleCI {#circleci}

[CircleCI-ზე](https://circleci.com) შეგიძლიათ გამოიყენოთ <.localized_link href="/guides/server/authentication#oidc-tokens">OIDC ავტორიზაცია</.localized_link> უსაფრთხო, საიდუმლოების გარეშე ავტორიზაციისთვის:

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
> **ავტორიზაცია**
>
> OIDC ავტორიზაციის გამოყენებამდე საჭიროა თქვენი GitHub რეპოზიტორიის <.localized_link href="/guides/integrations/gitforge/github">დაკავშირება</.localized_link> თქვენს Tuist პროექტთან. CircleCI OIDC ტოკენები შეიცავენ თქვენს დაკავშირებულ GitHub რეპოზიტორიას, რომელსაც Tuist იყენებს თქვენს პროექტებზე წვდომის ავტორიზაციისთვის. ალტერნატიულად, შეგიძლიათ გამოიყენოთ <.localized_link href="/guides/server/authentication#account-tokens">ანგარიშის ტოკენი</.localized_link> `TUIST_TOKEN` გარემოს ცვლადთან ერთად.


### Bitrise {#bitrise}

[Bitrise-ზე](https://bitrise.io) შეგიძლიათ გამოიყენოთ <.localized_link href="/guides/server/authentication#oidc-tokens">OIDC ავტორიზაცია</.localized_link> უსაფრთხო, საიდუმლოების გარეშე ავტორიზაციისთვის:

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
> **ავტორიზაცია**
>
> OIDC ავტორიზაციის გამოყენებამდე საჭიროა თქვენი GitHub რეპოზიტორიის <.localized_link href="/guides/integrations/gitforge/github">დაკავშირება</.localized_link> თქვენს Tuist პროექტთან. Bitrise OIDC ტოკენები შეიცავენ თქვენს დაკავშირებულ GitHub რეპოზიტორიას, რომელსაც Tuist იყენებს თქვენს პროექტებზე წვდომის ავტორიზაციისთვის. ალტერნატიულად, შეგიძლიათ გამოიყენოთ <.localized_link href="/guides/server/authentication#account-tokens">ანგარიშის ტოკენი</.localized_link> `TUIST_TOKEN` გარემოს ცვლადთან ერთად.


### Codemagic {#codemagic}

[Codemagic-ში](https://codemagic.io) შეგიძლიათ დაამატოთ დამატებითი ეტაპი თქვენს სამუშაო ნაკადში Tuist-ის დასაყენებლად:

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
> **ავტორიზაცია**
>
> შექმენით <.localized_link href="/guides/server/authentication#account-tokens">ანგარიშის ტოკენი</.localized_link> და დაამატეთ ის როგორც საიდუმლო გარემოს ცვლადი სახელით `TUIST_TOKEN`.

### Appcircle {#appcircle}

[Appcircle-ში](https://appcircle.io) შეგიძლიათ გამოიყენოთ ჩაშენებული [Tuist Install](https://docs.appcircle.io/workflows/ios-specific-workflow-steps/tuist-install) და [Tuist Commands](https://docs.appcircle.io/workflows/ios-specific-workflow-steps/tuist-commands) სამუშაო ნაკადის ეტაპები, ან დაამატოთ **Custom Script** ეტაპი **Git Clone** ეტაპის შემდეგ Tuist-ის დამოუკიდებლად დასაყენებლად:

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
> **სამუშაო ნაკადის ეტაპები**
>
> Tuist Install ეტაპი აყენებს Tuist-ს Homebrew-ით და ასრულებს `tuist generate`. მიუთითეთ **Tuist Version** ვერსია ფიქსაციისთვის, შემდეგ დაამატეთ Tuist Commands ეტაპი ისეთი ბრძანებების შესასრულებლად, როგორიცაა `tuist test` ან `tuist build`.

> [!NOTE]
> **ავტორიზაცია**
>
> შექმენით <.localized_link href="/guides/server/authentication#account-tokens">ანგარიშის ტოკენი</.localized_link>, დაამატეთ ის როგორც ცვლადი სახელით `TUIST_TOKEN` [გარემოს ცვლადების ჯგუფში](https://docs.appcircle.io/build/build-environment-variables) და აირჩიეთ ეს ჯგუფი თქვენს აგების კონფიგურაციაში. მონიშნეთ ცვლადი როგორც საიდუმლო ჩაკეტვის ხატულათი.

## გაშვების ანგარიში {#run-report}

როდესაც Tuist ატვირთავს გაშვებას, მისი დაფის URL-ები იბეჭდება ლოგებში. მათ მისაღებად ლოგების სკრაპინგის გარეშე — მაგალითად, სამუშაოს ჩავარდნისას Slack-ზე ტესტის ანგარიშის ბმულის გამოსაქვეყნებლად, ან გაშვების თქვენს ინსტრუმენტებში გადასაცემად — გადაეცით `--run-report-path` (ან დააყენეთ `TUIST_RUN_REPORT_PATH`) `tuist test`-ს, `tuist xcodebuild test`-ს ან `tuist xcodebuild build`-ს. Tuist წერს JSON ანგარიშს ამ გზაზე გაშვების ატვირთვის შემდეგ:

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

| ველი | ტიპი | აღწერა |
| - | - | - |
| `runId` | სტრიქონი | გაშვების უნიკალური იდენტიფიკატორი. |
| `status` | სტრიქონი | `"success"` ან `"failure"`. |
| `runURL` | სტრიქონი | დაფის URL გაშვებისთვის. ყოველთვის არსებობს. |
| `testRunURL` | სტრიქონი? | დაფის URL ტესტების გაშვებისთვის, არსებობს, როდესაც ბრძანებამ გაუშვა ტესტები. |
| `buildRunURL` | სტრიქონი? | დაფის URL აგების გაშვებისთვის, არსებობს, როდესაც ბრძანებამ შეასრულა აგება. |
| `testRuns` | მასივი | სქემის მიხედვით ტესტის შედეგები: `scheme`, `succeeded`, `totalTests`, `skippedTests`, `ranTests`, `failedTestNames`, `ranTestModules` და `skippedTestModules`. ტესტების რაოდენობა ეხება ტესტის საქეისებს, ხოლო `skippedTests` ითვლის მათ, რომლებიც შედეგების ბუნდლში აღნიშნულია როგორც გამოტოვებული. `skippedTestModules` ითვლის ტესტის მოდულებს, რომლებიც <.localized_link href="/guides/features/selective-testing">შერჩევითმა ტესტირებამ</.localized_link> გამოტოვა, და არ იწერება, როდესაც შერჩევითი ტესტირება არ გამოყენებულა ან გაშვება არის ტესტის შარდი. |
| `buildRuns` | მასივი | სქემის მიხედვით აგების შედეგები: `scheme`, `succeeded`, `durationInSeconds`. |

`testRunURL` და `buildRunURL` დამოუკიდებელია: ბრძანება, რომელიც ერთდროულად ასრულებს აგებას და ტესტირებას, წერს ორივეს, რასაც ლოგები ვერ აკეთებენ — ისინი მხოლოდ ერთ URL-ს ბეჭდავენ თითოეული გაშვებისთვის.

> [!NOTE]
> **როდესაც იწერება ანგარიში**
>
> ანგარიში იწერება მხოლოდ იმ გაშვებებისთვის, რომლებიც აიტვირთება სერვერზე, რაც მოითხოვს ავტორიზაციას და ავტომატურად ხდება CI-ზე. გზა იწმინდება ყოველი გაშვების დასაწყისში, ამიტომ გაშვება, რომელიც არ ქმნის ანგარიშს, არაფერს ტოვებს, ვიდრე წინა გაშვების მოძველებულ ანგარიშს.

GitLab CI-ზე, გავრცელებული გამოყენებაა URL-ის ხელმისაწვდომობა მომდევნო სამუშაოებისთვის [`dotenv` ანგარიშის](https://docs.gitlab.com/ci/yaml/artifacts_reports/#artifactsreportsdotenv) მეშვეობით:

```yaml
test:
  script:
    - tuist test --run-report-path tuist-run.json
    - echo "TUIST_TEST_RUN_URL=$(jq -r '.testRunURL // empty' tuist-run.json)" >> run.env
  artifacts:
    reports:
      dotenv: run.env
```
