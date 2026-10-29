---
{
  "title": "Continuous Integration (CI)",
  "titleTemplate": ":title · Automate · Guides · Tuist",
  "description": "Learn how to use Tuist in your CI workflows."
}
---
# უწყვეტი ინტეგრაცია (CI) {#continuous-integration-ci}

იმისათვის, რომ Tuist-ის ბრძანებები შეასრულოთ თქვენს [უწყვეტი ინტეგრაციის](https://en.wikipedia.org/wiki/Continuous_integration) სამუშაო ნაკადებში, საჭიროა მისი დაყენება თქვენს CI გარემოში. 

ავტორიზაცია არის სავალდებულო მხოლოდ იმ შემთხვევაში, თუ გსურთ გამოიყენოთ სერვერის მხარეს განთავსებული ფუნქციები, როგორიცაა <.localized_link href="/guides/features/cache">cache</.localized_link>. 

შემდეგი სექციები წარმოადგენს მაგალითებს, თუ როგორ უნდა გააკეთოთ ეს სხვადასხვა CI პლატფორმაზე.

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
> **Oidc Setup**
>
> OIDC ავტორიზაციის გამოყენებამდე, თქვენ უნდა <.localized_link href="/guides/integrations/gitforge/github">მიუერთოთ თქვენი GitHub რეპოზიტორია</.localized_link> თქვენს Tuist პროექტს. `permissions: id-token: write` აუცილებელია OIDC-ის მუშაობისთვის. ალტერნატიულად, შეგიძლიათ გამოიყენოთ <.localized_link href="/guides/server/authentication#account-tokens">account token</.localized_link> `TUIST_TOKEN` საიდუმლოსთან ერთად.


> [!TIP]
> ჩვენ გირჩევთ გამოიყენოთ `mise use --pin` თქვენს Tuist პროექტებში, რათა დააფიქსიროთ Tuist-ის ვერსია ყველა გარემოში. ეს ბრძანება შექმნის `.tool-versions` ფაილს, რომელიც შეიცავს Tuist-ის ვერსიას.


### Xcode Cloud {#xcode-cloud}

[Xcode Cloud](https://developer.apple.com/xcode-cloud/)-ში, რომელიც იყენებს Xcode პროექტებს როგორც ჭეშმარიტების წყაროს, თქვენ უნდა დაამატოთ [post-clone](https://developer.apple.com/documentation/xcode/writing-custom-build-scripts#Create-a-custom-build-script) სკრიპტი Tuist-ის დასაყენებლად და საჭირო ბრძანებების შესასრულებლად, მაგალითად `tuist generate`:

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
> **Authentication**
>
> გამოიყენეთ <.localized_link href="/guides/server/authentication#account-tokens">account token</.localized_link>, `TUIST_TOKEN` გარემოს ცვლადის დაყენებით თქვენს Xcode Cloud სამუშაო ნაკადის პარამეტრებში.


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
> **Authentication**
>
> OIDC ავტორიზაციის გამოყენებამდე, თქვენ უნდა <.localized_link href="/guides/integrations/gitforge/github">მიუერთოთ თქვენი GitHub რეპოზიტორია</.localized_link> თქვენს Tuist პროექტს. CircleCI OIDC ტოკენები მოიცავს თქვენს მიერთებულ GitHub რეპოზიტორიას, რომელსაც Tuist იყენებს თქვენს პროექტებზე წვდომის ავტორიზაციისთვის. ალტერნატიულად, შეგიძლიათ გამოიყენოთ <.localized_link href="/guides/server/authentication#account-tokens">account token</.localized_link> `TUIST_TOKEN` გარემოს ცვლადთან ერთად.


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
> **Authentication**
>
> OIDC ავტორიზაციის გამოყენებამდე, თქვენ უნდა <.localized_link href="/guides/integrations/gitforge/github">მიუერთოთ თქვენი GitHub რეპოზიტორია</.localized_link> თქვენს Tuist პროექტს. Bitrise OIDC ტოკენები მოიცავს თქვენს მიერთებულ GitHub რეპოზიტორიას, რომელსაც Tuist იყენებს თქვენს პროექტებზე წვდომის ავტორიზაციისთვის. ალტერნატიულად, შეგიძლიათ გამოიყენოთ <.localized_link href="/guides/server/authentication#account-tokens">account token</.localized_link> `TUIST_TOKEN` გარემოს ცვლადთან ერთად.


### Codemagic {#codemagic}

[Codemagic](https://codemagic.io)-ში, შეგიძლიათ დაამატოთ დამატებითი ნაბიჯი თქვენს სამუშაო ნაკადში Tuist-ის დასაყენებლად:

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
> **Authentication**
>
> შექმენით <.localized_link href="/guides/server/authentication#account-tokens">account token</.localized_link> და დაამატეთ ის როგორც საიდუმლო გარემოს ცვლადი სახელით `TUIST_TOKEN`.

### Appcircle {#appcircle}

[Appcircle](https://appcircle.io)-ში, შეგიძლიათ გამოიყენოთ ჩაშენებული [Tuist Install](https://docs.appcircle.io/workflows/ios-specific-workflow-steps/tuist-install) და [Tuist Commands](https://docs.appcircle.io/workflows/ios-specific-workflow-steps/tuist-commands) სამუშაო ნაკადის ნაბიჯები, ან დაამატოთ **Custom Script** ნაბიჯი **Git Clone** ნაბიჯის შემდეგ, რათა თავად დააყენოთ Tuist:

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
> **Workflow steps**
>
> Tuist Install ნაბიჯი აყენებს Tuist-ს Homebrew-ით და ასრულებს `tuist generate`. დააყენეთ **Tuist Version** შეყვანა ვერსიის დასაფიქსირებლად, შემდეგ დაამატეთ Tuist Commands ნაბიჯი ისეთი ბრძანებების შესასრულებლად, როგორიცაა `tuist test` ან `tuist build`.

> [!NOTE]
> **Authentication**
>
> შექმენით <.localized_link href="/guides/server/authentication#account-tokens">account token</.localized_link>, დაამატეთ ის როგორც ცვლადი სახელით `TUIST_TOKEN` [environment variable group](https://docs.appcircle.io/build/build-environment-variables)-ში და აირჩიეთ ეს ჯგუფი თქვენს build კონფიგურაციაში. მონიშნეთ ცვლადი როგორც საიდუმლო ჩაკეტვის ხატულით.

## Run report {#run-report}

როდესაც Tuist ატვირთავს run-ს, მისი dashboard URL-ები იბეჭდება ლოგებში. მათ მისაღებად ლოგების სკრეპინგის გარეშე - მაგალითად, Slack-ში ტესტის ანგარიშის ბმულის გასაზიარებლად, როდესაც სამუშაო ვერ ხერხდება, ან run-ის თქვენს საკუთარ ინსტრუმენტებში გადასაცემად - გადაეცით `--run-report-path` (ან დააყენეთ `TUIST_RUN_REPORT_PATH`) `tuist test`-ს, `tuist xcodebuild test`-ს ან `tuist xcodebuild build`-ს. Tuist წერს JSON ანგარიშს ამ გზაზე, როგორც კი run აიტვირთება:

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
| `runId` | სტრიქონი | run-ის უნიკალური იდენტიფიკატორი. |
| `status` | სტრიქონი | `"success"` ან `"failure"`. |
| `runURL` | სტრიქონი | dashboard URL run-ისთვის. ყოველთვის არსებობს. |
| `testRunURL` | სტრიქონი? | dashboard URL ტესტის run-ისთვის, არსებობს, როდესაც ბრძანებამ გაუშვა ტესტები. |
| `buildRunURL` | სტრიქონი? | dashboard URL build run-ისთვის, არსებობს, როდესაც ბრძანებამ შეასრულა build. |
| `testRuns` | მასივი | ტესტის შედეგები სქემის მიხედვით: `scheme`, `succeeded`, `totalTests`, `skippedTests`, `ranTests`, `failedTestNames`, `ranTestModules` და `skippedTestModules`. ტესტების რაოდენობა ეხება სატესტო შემთხვევებს, ხოლო `skippedTests` ითვლის მათ, რომლებიც შედეგების კომპლექტში აღნიშნულია როგორც გამოტოვებული. `skippedTestModules` ითვლის სატესტო მოდულებს, რომლებიც <.localized_link href="/guides/features/selective-testing">selective testing</.localized_link>-მა გამოტოვა და გამოტოვებულია, როდესაც selective testing არ გამოყენებულა ან run არის ტესტის ნაწილი (shard). |
| `buildRuns` | მასივი | build-ის შედეგები სქემის მიხედვით: `scheme`, `succeeded`, `durationInSeconds`. |

`testRunURL` და `buildRunURL` დამოუკიდებელია: ბრძანება, რომელიც ასრულებს build-საც და ტესტსაც, წერს ორივეს, რასაც ლოგები ვერ აკეთებენ — ისინი მხოლოდ ერთ URL-ს ბეჭდავენ თითოეული run-ისთვის.

> [!NOTE]
> **როდესაც იწერება ანგარიში**
>
> ანგარიში იწერება მხოლოდ იმ run-ებისთვის, რომლებიც აიტვირთება სერვერზე, რაც მოითხოვს ავთენტიკაციას და ავტომატურად ხდება CI-ზე. გზა იშლება ყოველი run-ის დასაწყისში, ამიტომ run, რომელიც არ ქმნის ანგარიშს, არაფერს ტოვებს, ვიდრე ძველ ანგარიშს წინა run-დან.

GitLab CI-ზე, ჩვეულებრივი გამოყენებაა URL-ის გამოჩენა მოგვიანებითი სამუშაოებისთვის [`dotenv` report](https://docs.gitlab.com/ci/yaml/artifacts_reports/#artifactsreportsdotenv)-ის მეშვეობით:

```yaml
test:
  script:
    - tuist test --run-report-path tuist-run.json
    - echo "TUIST_TEST_RUN_URL=$(jq -r '.testRunURL // empty' tuist-run.json)" >> run.env
  artifacts:
    reports:
      dotenv: run.env
```
