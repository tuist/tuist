---
{
  "title": "უწყვეტი ინტეგრაცია (CI)",
  "titleTemplate": ":title · ავტომატიზაცია · სახელმძღვანელოები · Tuist",
  "description": "ისწავლეთ, როგორ გამოიყენოთ Tuist თქვენს CI სამუშაო პროცესებში."
}
---
# უწყვეტი ინტეგრაცია (CI) {#continuous-integration-ci}

იმისათვის, რომ Tuist-ის ბრძანებები შეასრულოთ თქვენს [უწყვეტი ინტეგრაციის](https://en.wikipedia.org/wiki/Continuous_integration) სამუშაო ნაკადებში, უნდა დააინსტალიროთ ის თქვენს CI გარემოში. 

ავტორიზაცია არასავალდებულოა, მაგრამ აუცილებელია, თუ გსურთ სერვერის მხარეს განლაგებული ფუნქციების გამოყენება, როგორიცაა <.localized_link href="/guides/features/cache">ქეში</.localized_link>. CI გაშვებების დროის შესამცირებლად და ხარჯების შესამცირებლად Tuist-ის დაინსტალირების შემდეგ, იხილეთ [ნელი ბილდები](https://tuist.dev/solutions/slow-builds) და [CI ხარჯები](https://tuist.dev/solutions/ci-costs).

შემდეგი სექციები მოიცავს მაგალითებს, თუ როგორ უნდა გააკეთოთ ეს სხვადასხვა CI პლატფორმაზე. Struo უკავშირდება საკუთარი ნატიური Tuist პროვაიდერის მეშვეობით; მას არ სჭირდება Tuist CLI. ამ სამუშაო ნაკადისთვის იხილეთ [Struo](#struo).

## Struo {#struo}

<a id="once"></a>

დააკომიტეთ პროვაიდერი და ქეშთან მიბმა <.localized_link href="/guides/get-started/struo-project">Struo-ს დაწყება</.localized_link>-დან. დააინსტალირეთ Struo ჯობში [Struo-ს დაინსტალირების ინსტრუქციების](https://struo.run/docs/guide/getting-started) გამოყენებით, შემდეგ კი გაიარეთ ავტორიზაცია ქეშირებადი სამუშაოს შესრულებამდე.

GitHub Actions, CircleCI და Bitrise მხარს უჭერენ Struo-ს უინტერფეისო OpenID Connect შესვლას. დააკავშირეთ რეპოზიტორია თქვენს Tuist პროექტთან, როგორც აღწერილია <.localized_link href="/guides/server/authentication#oidc-tokens">OIDC ავტორიზაციაში</.localized_link>. GitHub Actions-ზე მიანიჭეთ identity-token ნებართვა:

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

აირჩიეთ ოპერაციული სისტემა თქვენი ტარგეტებისთვის საჭირო ტულჩეინებით. ჩაანაცვლეთ `MyTarget` თქვენი ტარგეტით და დააფიქსირეთ Struo თქვენი არსებული ინსტრუმენტების დაინსტალირების ნაკადის მეშვეობით. მიღებული სესია ხელახლა გამოიყენება ქეშზე წვდომის, ანგარიშგებისა და არტეფაქტების გამოქვეყნებისთვის ჯობის განმავლობაში.

სხვა პროვაიდერებზე, დააყენეთ `TUIST_TOKEN` <.localized_link href="/guides/server/authentication#account-tokens">ანგარიშის ტოკენად</.localized_link>, რომელიც ავტორიზებულია თქვენთვის საჭირო ოპერაციებისთვის. შეინახეთ ის CI საიდუმლოების საცავში, არასდროს `struo.toml`-ში ან ნაკადის წყაროში. ამ ტოკენის გამოყენებისას ინტერაქტიული შესვლის ეტაპი არ არის საჭირო.

მრავალმუშაკიანი სუიტებისთვის მიჰყევით <.localized_link href="/guides/features/test-sharding/struo">Struo ტესტების შარდინგს</.localized_link>. აპლიკაციების გამოქვეყნებისთვის დაამატეთ ცალსახა <.localized_link href="/guides/features/previews/struo">Struo პრივიუს გამოქვეყნების</.localized_link> ეტაპი. ჩვეულებრივი ბილდები არ აქვეყნებენ პრივიუსებს იმპლიციტურად.

## მაგალითები {#examples}

### GitHub Actions {#github-actions}

[GitHub Actions](https://docs.github.com/en/actions)-ზე შეგიძლიათ გამოიყენოთ <.localized_link href="/guides/server/authentication#oidc-tokens">OIDC ავტორიზაცია</.localized_link> უსაფრთხო, საიდუმლოების გარეშე ავტორიზაციისთვის:

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
> **OIDC დაყენება**
>
> OIDC ავტორიზაციის გამოყენებამდე უნდა <.localized_link href="/guides/integrations/gitforge/github">დააკავშიროთ თქვენი GitHub რეპოზიტორია</.localized_link> თქვენს Tuist პროექტთან. OIDC-ს მუშაობისთვის აუცილებელია `permissions: id-token: write`. Tuist 4.218.0-დან, CLI ცვლის იდენტობის ტოკენს თავის პირველ მოთხოვნაზე, ამიტომ ნაკადს არ სჭირდება `tuist auth login` ეტაპი; ადრეულ ვერსიებზე, გაუშვით `tuist auth login` სხვა Tuist ბრძანებებამდე. ალტერნატიულად, შეგიძლიათ გამოიყენოთ <.localized_link href="/guides/server/authentication#account-tokens">ანგარიშის ტოკენი</.localized_link> `TUIST_TOKEN` საიდუმლოებით.


> [!TIP]
> ჩვენ გირჩევთ გამოიყენოთ `mise use --pin` თქვენს Tuist პროექტებში Tuist-ის ვერსიის დასაფიქსირებლად გარემოებს შორის. ბრძანება აფიქსირებს Tuist-ის ვერსიას თქვენს `mise.toml` ფაილში.


### Xcode Cloud {#xcode-cloud}

[Xcode Cloud](https://developer.apple.com/xcode-cloud/)-ში, რომელიც Xcode პროექტებს იყენებს როგორც ჭეშმარიტების წყაროს, უნდა დაამატოთ [post-clone](https://developer.apple.com/documentation/xcode/writing-custom-build-scripts#Create-a-custom-build-script) სკრიპტი Tuist-ის დასაინსტალირებლად და საჭირო ბრძანებების შესასრულებლად, მაგალითად `tuist generate`:

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
> გამოიყენეთ <.localized_link href="/guides/server/authentication#account-tokens">ანგარიშის ტოკენი</.localized_link> `TUIST_TOKEN` გარემოს ცვლადის დაყენებით თქვენს Xcode Cloud ნაკადის პარამეტრებში.


### CircleCI {#circleci}

[CircleCI](https://circleci.com)-ზე შეგიძლიათ გამოიყენოთ <.localized_link href="/guides/server/authentication#oidc-tokens">OIDC ავტორიზაცია</.localized_link> უსაფრთხო, საიდუმლოების გარეშე ავტორიზაციისთვის:

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
> **ავტორიზაცია**
>
> OIDC ავტორიზაციის გამოყენებამდე უნდა <.localized_link href="/guides/integrations/gitforge/github">დააკავშიროთ თქვენი GitHub რეპოზიტორია</.localized_link> თქვენს Tuist პროექტთან. CircleCI OIDC ტოკენები მოიცავს თქვენს დაკავშირებულ GitHub რეპოზიტორიას, რომელსაც Tuist იყენებს თქვენს პროექტებზე წვდომის ავტორიზაციისთვის. Tuist 4.218.0-დან, CLI ცვლის იდენტობის ტოკენს თავის პირველ მოთხოვნაზე, ამიტომ `tuist auth login` ეტაპი არ არის საჭირო; ადრეულ ვერსიებზე, გაუშვით `mise exec -- tuist auth login` სხვა Tuist ბრძანებებამდე. ალტერნატიულად, შეგიძლიათ გამოიყენოთ <.localized_link href="/guides/server/authentication#account-tokens">ანგარიშის ტოკენი</.localized_link> `TUIST_TOKEN` გარემოს ცვლადით.


### Bitrise {#bitrise}

[Bitrise](https://bitrise.io)-ზე შეგიძლიათ გამოიყენოთ <.localized_link href="/guides/server/authentication#oidc-tokens">OIDC ავტორიზაცია</.localized_link> უსაფრთხო, საიდუმლოების გარეშე ავტორიზაციისთვის:

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
> **ავტორიზაცია**
>
> OIDC ავტორიზაციის გამოყენებამდე უნდა <.localized_link href="/guides/integrations/gitforge/github">დააკავშიროთ თქვენი GitHub რეპოზიტორია</.localized_link> თქვენს Tuist პროექტთან. Bitrise OIDC ტოკენები მოიცავს თქვენს დაკავშირებულ GitHub რეპოზიტორიას, რომელსაც Tuist იყენებს თქვენს პროექტებზე წვდომის ავტორიზაციისთვის. Tuist 4.218.0-დან, CLI ცვლის იდენტობის ტოკენს თავის პირველ მოთხოვნაზე, ამიტომ `tuist auth login` ეტაპი არ არის საჭირო; ადრეულ ვერსიებზე, გაუშვით `mise exec -- tuist auth login` სხვა Tuist ბრძანებებამდე. ალტერნატიულად, შეგიძლიათ გამოიყენოთ <.localized_link href="/guides/server/authentication#account-tokens">ანგარიშის ტოკენი</.localized_link> `TUIST_TOKEN` გარემოს ცვლადით.


### Codemagic {#codemagic}

[Codemagic](https://codemagic.io)-ში, შეგიძლიათ დაამატოთ დამატებითი ეტაპი თქვენს ნაკადში Tuist-ის დასაინსტალირებლად:

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

[Appcircle](https://appcircle.io)-ში, შეგიძლიათ გამოიყენოთ ჩაშენებული [Tuist Install](https://docs.appcircle.io/workflows/ios-specific-workflow-steps/tuist-install) და [Tuist Commands](https://docs.appcircle.io/workflows/ios-specific-workflow-steps/tuist-commands) ნაკადის ეტაპები, ან დაამატოთ **Custom Script** ეტაპი **Git Clone** ეტაპის შემდეგ Tuist-ის თავად დასაინსტალირებლად:

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
> **ნაკადის ეტაპები**
>
> Tuist Install ეტაპი აყენებს Tuist-ს Homebrew-ით და ასრულებს `tuist generate`. დააყენეთ **Tuist Version** შეყვანა ვერსიის ფიქსაციისთვის, შემდეგ დაამატეთ Tuist Commands ეტაპი ისეთი ბრძანებების გასაშვებად, როგორიცაა `tuist test` ან `tuist build`.

> [!NOTE]
> **ავტორიზაცია**
>
> შექმენით <.localized_link href="/guides/server/authentication#account-tokens">ანგარიშის ტოკენი</.localized_link>, დაამატეთ ის როგორც ცვლადი სახელით `TUIST_TOKEN` [გარემოს ცვლადების ჯგუფში](https://docs.appcircle.io/build/build-environment-variables) და აირჩიეთ ეს ჯგუფი თქვენს აგების კონფიგურაციაში. მონიშნეთ ცვლადი როგორც საიდუმლო ჩაკეტვის ხატულით.

## xcodebuild-ის გამოტანის ფორმატირება {#xcodebuild-output-formatting}

`tuist build`, `tuist test`, `tuist xcodebuild build` და `tuist xcodebuild test` აფორმატებენ `xcodebuild`-ის გამოტანას [xcbeautify](https://github.com/cpisciotta/xcbeautify)-ის ფორმატერით, ამიტომ არ გჭირდებათ ამ ბრძანებების xcbeautify-ში გადაყვანა. GitHub Actions-ზე, რომელიც აღმოჩენილია `GITHUB_ACTIONS` გარემოს ცვლადით, Tuist იყენებს xcbeautify-ის GitHub Actions რენდერს, რომელიც კომპილატორის გაფრთხილებებს, შეცდომებს და ტესტების წუნებს გამოაჩენს როგორც ანოტაციებს გაშვების შეჯამებაში და პულ-რეკვესტზე. სხვაგან ის იყენებს ტერმინალის რენდერს, შეღებილს, თუ გამოტანა არ არის მილში ან `NO_COLOR` არ არის დაყენებული.

გადაეცით `--verbose` `xcodebuild`-ის დაუფორმატებელი გამოტანის დაბეჭდვისთვის, მაგალითად, როცა აგება მარცხდება ცხადი შეცდომის გარეშე.

თუ სამუშაო პირდაპირ უწოდებს `xcodebuild`-ს Tuist-ის ნაცვლად, თავად გადაიყვანეთ ის xcbeautify-ში და დააყენეთ `pipefail`, რათა წუნის მქონე აგებამ მაინც ჩააგდოს ეტაპი:

```bash
set -o pipefail
xcodebuild test -scheme App | xcbeautify --renderer github-actions
```

## გაშვების ანგარიში {#run-report}

როცა Tuist ატვირთავს გაშვებას, მისი დაფის URL-ები იბეჭდება ლოგებში. მათ მისაღებად ლოგების გრეპინგის გარეშე — მაგალითად, ტესტის ანგარიშის ბმულის Slack-ში გასაგზავნად სამუშაოს ჩავარდნისას, ან გაშვების თქვენს ინსტრუმენტებში შესაყვანად — გადაეცით `--run-report-path` (ან დააყენეთ `TUIST_RUN_REPORT_PATH`) `tuist test`-ს, `tuist xcodebuild test`-ს ან `tuist xcodebuild build`-ს. Tuist წერს JSON ანგარიშს იმ გზაზე გაშვების ატვირთვის შემდეგ:

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
| `runURL` | სტრიქონი | გაშვების დაფის URL. ყოველთვის არსებობს. |
| `testRunURL` | სტრიქონი? | ტესტების გაშვების დაფის URL, არსებობს, როცა ბრძანებამ გაუშვა ტესტები. |
| `buildRunURL` | სტრიქონი? | აგების გაშვების დაფის URL, არსებობს, როცა ბრძანებამ ააგო. |
| `testRuns` | მასივი | სქემის მიხედვით ტესტების შედეგები: `scheme`, `succeeded`, `totalTests`, `skippedTests`, `ranTests`, `failedTestNames`, `ranTestModules` და `skippedTestModules`. ტესტების რაოდენობა არის ტესტის საქმეები, და `skippedTests` ითვლის მათ, რომელთაც შედეგების ბუნდლი აღნიშნავს როგორც გამოტოვებულს. `skippedTestModules` ითვლის ტესტის მოდულებს, რომლებიც <.localized_link href="/guides/features/selective-testing">შერჩევითმა ტესტირებამ</.localized_link> გამოტოვა, და გამოტოვებულია, როცა შერჩევითი ტესტირება არ მოქმედებდა ან გაშვება არის ტესტის შარდი. |
| `buildRuns` | მასივი | სქემის მიხედვით აგების შედეგები: `scheme`, `succeeded`, `durationInSeconds`. |

`testRunURL` და `buildRunURL` დამოუკიდებელია: ბრძანება, რომელიც ერთდროულად აგებს და ტესტავს, წერს ორივეს, რასაც ლოგები ვერ აკეთებენ — ისინი მხოლოდ ერთ URL-ს ბეჭდავენ გაშვებაზე.

> [!NOTE]
> **როცა იწერება ანგარიში**
>
> ანგარიში იწერება მხოლოდ იმ გაშვებებისთვის, რომლებიც აიტვირთა სერვერზე, რაც მოითხოვს ავტორიზაციას და ხდება ავტომატურად CI-ზე. გზა იშლება ყოველი გაშვების დასაწყისში, ამიტომ გაშვება, რომელიც არ ქმნის ანგარიშს, არაფერს ტოვებს უკან, ვიდრე ძველს წინა გაშვებიდან.

GitLab CI-ზე, ჩვეულებრივი გამოყენებაა URL-ის გამოჩენა მოგვიანებითი სამუშაოებისთვის [`dotenv` ანგარიშის](https://docs.gitlab.com/ci/yaml/artifacts_reports/#artifactsreportsdotenv) მეშვეობით:

```yaml
test:
  script:
    - tuist test --run-report-path tuist-run.json
    - echo "TUIST_TEST_RUN_URL=$(jq -r '.testRunURL // empty' tuist-run.json)" >> run.env
  artifacts:
    reports:
      dotenv: run.env
```
