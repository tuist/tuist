---
{
  "title": "უწყვეტი ინტეგრაცია (CI)",
  "titleTemplate": ":title · ავტომატიზაცია · სახელმძღვანელოები · Tuist",
  "description": "შეიტყვეთ, როგორ გამოიყენოთ Tuist თქვენს CI სამუშაო ნაკადებში."
}
---
# უწყვეტი ინტეგრაცია (CI) {#continuous-integration-ci}

იმისათვის, რომ Tuist-ის ბრძანებები შეასრულოთ თქვენს [უწყვეტი ინტეგრაციის](https://en.wikipedia.org/wiki/Continuous_integration) სამუშაო პროცესებში, ის უნდა დააინსტალიროთ თქვენს CI გარემოში. 

ავტორიზაცია არასავალდებულოა, მაგრამ აუცილებელია, თუ გსურთ სერვერის მხარეს არსებული ფუნქციების გამოყენება, როგორიცაა <.localized_link href="/guides/features/cache">კეში</.localized_link>. 

შემდეგ სექციებში მოცემულია მაგალითები იმისა, თუ როგორ გააკეთოთ ეს სხვადასხვა CI პლატფორმაზე.

## მაგალითები {#examples}

### GitHub Actions {#github-actions}

[GitHub Actions](https://docs.github.com/en/actions)-ზე შეგიძლიათ გამოიყენოთ <.localized_link href="/guides/server/authentication#oidc-tokens">OIDC ავტორიზაცია</.localized_link> უსაფრთხო, საიდუმლოების გარეშე შესასვლელად:

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

> [!NOTE]
> **Oidc-ის კონფიგურაცია**
>
> OIDC ავტორიზაციის გამოყენებამდე უნდა <.localized_link href="/guides/integrations/gitforge/github">დააკავშიროთ თქვენი GitHub რეპოზიტორია</.localized_link> თქვენს Tuist პროექტთან. OIDC-ის მუშაობისთვის აუცილებელია `permissions: id-token: write`. ალტერნატიულად, შეგიძლიათ გამოიყენოთ <.localized_link href="/guides/server/authentication#account-tokens">ანგარიშის ტოკენი</.localized_link> `TUIST_TOKEN` საიდუმლოებით.


> [!TIP]
> ჩვენ გირჩევთ გამოიყენოთ `mise use --pin` თქვენს Tuist პროექტებში, რათა დააფიქსიროთ Tuist-ის ვერსია ყველა გარემოში. ბრძანება შექმნის `.tool-versions` ფაილს, რომელიც შეიცავს Tuist-ის ვერსიას.


### Xcode Cloud {#xcode-cloud}

[Xcode Cloud](https://developer.apple.com/xcode-cloud/)-ში, რომელიც Xcode პროექტებს იყენებს როგორც ჭეშმარიტების წყაროს, უნდა დაამატოთ [post-clone](https://developer.apple.com/documentation/xcode/writing-custom-build-scripts#Create-a-custom-build-script) სკრიპტი Tuist-ის დასაინსტალირებლად და საჭირო ბრძანებების შესასრულებლად, მაგალითად `tuist generate`:

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

> [!NOTE]
> **ავტორიზაცია**
>
> გამოიყენეთ <.localized_link href="/guides/server/authentication#account-tokens">ანგარიშის ტოკენი</.localized_link> `TUIST_TOKEN` გარემოს ცვლადის დაყენებით თქვენს Xcode Cloud სამუშაო პროცესის პარამეტრებში.


### CircleCI {#circleci}

[CircleCI](https://circleci.com)-ზე შეგიძლიათ გამოიყენოთ <.localized_link href="/guides/server/authentication#oidc-tokens">OIDC ავტორიზაცია</.localized_link> უსაფრთხო, საიდუმლოების გარეშე შესასვლელად:

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

> [!NOTE]
> **ავტორიზაცია**
>
> OIDC ავტორიზაციის გამოყენებამდე უნდა <.localized_link href="/guides/integrations/gitforge/github">დააკავშიროთ თქვენი GitHub რეპოზიტორია</.localized_link> თქვენს Tuist პროექტთან. CircleCI OIDC ტოკენები შეიცავენ თქვენს დაკავშირებულ GitHub რეპოზიტორიას, რომელსაც Tuist იყენებს თქვენს პროექტებზე წვდომის ავტორიზაციისთვის. ალტერნატიულად, შეგიძლიათ გამოიყენოთ <.localized_link href="/guides/server/authentication#account-tokens">ანგარიშის ტოკენი</.localized_link> `TUIST_TOKEN` გარემოს ცვლადით.


### Bitrise {#bitrise}

[Bitrise](https://bitrise.io)-ზე შეგიძლიათ გამოიყენოთ <.localized_link href="/guides/server/authentication#oidc-tokens">OIDC ავტორიზაცია</.localized_link> უსაფრთხო, საიდუმლოების გარეშე შესასვლელად:

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

> [!NOTE]
> **ავტორიზაცია**
>
> OIDC ავტორიზაციის გამოყენებამდე უნდა <.localized_link href="/guides/integrations/gitforge/github">დააკავშიროთ თქვენი GitHub რეპოზიტორია</.localized_link> თქვენს Tuist პროექტთან. Bitrise OIDC ტოკენები შეიცავენ თქვენს დაკავშირებულ GitHub რეპოზიტორიას, რომელსაც Tuist იყენებს თქვენს პროექტებზე წვდომის ავტორიზაციისთვის. ალტერნატიულად, შეგიძლიათ გამოიყენოთ <.localized_link href="/guides/server/authentication#account-tokens">ანგარიშის ტოკენი</.localized_link> `TUIST_TOKEN` გარემოს ცვლადით.


### Codemagic {#codemagic}

[Codemagic](https://codemagic.io)-ში, შეგიძლიათ დაამატოთ დამატებითი ნაბიჯი თქვენს სამუშაო პროცესში Tuist-ის დასაინსტალირებლად:

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

> [!NOTE]
> **ავტორიზაცია**
>
> შექმენით <.localized_link href="/guides/server/authentication#account-tokens">ანგარიშის ტოკენი</.localized_link> და დაამატეთ ის როგორც საიდუმლო გარემოს ცვლადი სახელით `TUIST_TOKEN`.

### Appcircle {#appcircle}

[Appcircle](https://appcircle.io)-ში, შეგიძლიათ გამოიყენოთ ჩაშენებული [Tuist Install](https://docs.appcircle.io/workflows/ios-specific-workflow-steps/tuist-install) და [Tuist Commands](https://docs.appcircle.io/workflows/ios-specific-workflow-steps/tuist-commands) სამუშაო პროცესის ნაბიჯები, ან დაამატოთ **Custom Script** ნაბიჯი **Git Clone** ნაბიჯის შემდეგ Tuist-ის თავად დასაინსტალირებლად:

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
> **სამუშაო პროცესის ნაბიჯები**
>
> Tuist Install ნაბიჯი აინსტალირებს Tuist-ს Homebrew-ით და ასრულებს `tuist generate`. დააყენეთ **Tuist Version** შეყვანა ვერსიის დასაფიქსირებლად, შემდეგ დაამატეთ Tuist Commands ნაბიჯი ისეთი ბრძანებების შესასრულებლად, როგორიცაა `tuist test` ან `tuist build`.

> [!NOTE]
> **ავტორიზაცია**
>
> შექმენით <.localized_link href="/guides/server/authentication#account-tokens">ანგარიშის ტოკენი</.localized_link>, დაამატეთ ის როგორც ცვლადი სახელით `TUIST_TOKEN` [გარემოს ცვლადების ჯგუფში](https://docs.appcircle.io/build/build-environment-variables) და აირჩიეთ ეს ჯგუფი თქვენს აგების კონფიგურაციაში. მონიშნეთ ცვლადი როგორც საიდუმლო ჩაკეტვის ხატულით.

## გაშვების ანგარიში {#run-report}

როდესაც Tuist ატვირთავს გაშვებას, მისი დაფის URL-ები იბეჭდება ლოგებში. მათ მიღება ლოგების სკრაპინგის გარეშე — მაგალითად, ტესტის ანგარიშის ბმულის Slack-ში გასაგზავნად სამუშაოს ჩავარდნისას, ან გაშვების თქვენს ინსტრუმენტებში გადასაცემად — შეგიძლიათ გადასცეთ `--run-report-path` (ან დააყენოთ `TUIST_RUN_REPORT_PATH`) `tuist test`-ს, `tuist xcodebuild test`-ს ან `tuist xcodebuild build`-ს. Tuist წერს JSON ანგარიშს ამ გზაზე გაშვების ატვირთვის შემდეგ:

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
| `testRunURL` | სტრიქონი? | დაფის URL ტესტების გაშვებისთვის, არსებობს, როცა ბრძანებამ ტესტები გაუშვა. |
| `buildRunURL` | სტრიქონი? | დაფის URL აგების გაშვებისთვის, არსებობს, როცა ბრძანებამ ააგო. |
| `testRuns` | მასივი | თითოეული სქემის ტესტის შედეგები: `scheme`, `succeeded`, `totalTests`, `skippedTests`, `ranTests`, `failedTestNames`, `ranTestModules` და `skippedTestModules`. ტესტების რაოდენობა ეხება სატესტო შემთხვევებს, ხოლო `skippedTests` ითვლის მათ, რომლებიც შედეგების კრებული გამოტოვებულად მიიჩნია. `skippedTestModules` ითვლის სატესტო მოდულებს, რომლებიც <.localized_link href="/guides/features/selective-testing">შერჩევითმა ტესტირებამ</.localized_link> გამოტოვა, და ის გამოტოვებულია, როცა შერჩევითი ტესტირება არ გამოყენებულა ან გაშვება არის ტესტის ნაწილი. |
| `buildRuns` | მასივი | თითოეული სქემის აგების შედეგები: `scheme`, `succeeded`, `durationInSeconds`. |

`testRunURL` და `buildRunURL` დამოუკიდებელია: ბრძანება, რომელიც ერთდროულად აგებს და ასრულებს ტესტებს, წერს ორივეს, რაც ლოგებს არ შეუძლიათ — ისინი მხოლოდ ერთ URL-ს ბეჭდავენ თითოეული გაშვებისთვის.

> [!NOTE]
> **როდის იწერება ანგარიში**
>
> ანგარიში იწერება მხოლოდ იმ გაშვებებისთვის, რომლებიც აიტვირთება სერვერზე, რაც მოითხოვს ავტორიზაციას და ავტომატურად ხდება CI-ზე. გზა იშლება ყოველი გაშვების დასაწყისში, ამიტომ გაშვება, რომელიც არ ქმნის ანგარიშს, არაფერს ტოვებს, ვიდრე ძველ ანგარიშს წინა გაშვებიდან.

GitLab CI-ზე, გავრცელებული გამოყენებაა URL-ის გახსნა მომდევნო სამუშაოებისთვის [`dotenv` ანგარიშის](https://docs.gitlab.com/ci/yaml/artifacts_reports/#artifactsreportsdotenv) მეშვეობით:

```yaml
test:
  script:
    - tuist test --run-report-path tuist-run.json
    - echo "TUIST_TEST_RUN_URL=$(jq -r '.testRunURL // empty' tuist-run.json)" >> run.env
  artifacts:
    reports:
      dotenv: run.env
```
