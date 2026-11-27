---
{
  "title": "უწყვეტი ინტეგრაცია (CI)",
  "titleTemplate": ":title · ავტომატიზაცია · სახელმძღვანელოები · Tuist",
  "description": "შეიტყვეთ, როგორ გამოიყენოთ Tuist თქვენს CI სამუშაო პროცესებში."
}
---
# უწყვეტი ინტეგრაცია (CI) {#continuous-integration-ci}

იმისათვის, რომ Tuist-ის ბრძანებები შეასრულოთ თქვენს [უწყვეტი ინტეგრაციის](https://en.wikipedia.org/wiki/Continuous_integration) სამუშაო პროცესებში, უნდა დააინსტალიროთ ის თქვენს CI გარემოში. 

ავტორიზაცია არის სურვილისამებრ, მაგრამ აუცილებელია, თუ გსურთ გამოიყენოთ სერვერის მხარეს არსებული ფუნქციები, როგორიცაა <.localized_link href="/guides/features/cache">ქეში</.localized_link>. CI გაშვებების ხანგრძლივობის შესამცირებლად და მათი ღირებულების დასაწევად Tuist-ის დაინსტალირების შემდეგ, იხილეთ [ნელი კომპილაციები](https://tuist.dev/solutions/slow-builds) და [CI ხარჯები](https://tuist.dev/solutions/ci-costs).

შემდეგი სექციები მოიცავს მაგალითებს, თუ როგორ განახორციელოთ ეს სხვადასხვა CI პლატფორმაზე. Struo უკავშირდება საკუთარი ნატიური Tuist პროვაიდერის მეშვეობით; მას არ სჭირდება Tuist CLI. ამ სამუშაო პროცესისთვის იხილეთ [Struo](#struo).

## Struo {#struo}

<a id="once"></a>

დააკომიტეთ პროვაიდერი და ქეშის მიბმა <.localized_link href="/guides/get-started/struo-project">Struo-სთან დაწყება</.localized_link>-დან. დააინსტალირეთ Struo ჯობში [Struo-ს დაინსტალირების ინსტრუქციების](https://struo.run/docs/guide/getting-started) გამოყენებით, შემდეგ კი გაიარეთ ავტორიზაცია ქეშირებადი სამუშაოს შესრულებამდე.

GitHub Actions, CircleCI და Bitrise მხარს უჭერენ Struo-ს უხილავ OpenID Connect შესვლას. დააკავშირეთ რეპოზიტორი თქვენს Tuist პროექტთან, როგორც აღწერილია <.localized_link href="/guides/server/authentication#oidc-tokens">OIDC ავტორიზაციაში</.localized_link>. GitHub Actions-ზე მიანიჭეთ identity-token ნებართვა:

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

აირჩიეთ ოპერაციული სისტემა თქვენი ტარგეტებისთვის საჭირო ინსტრუმენტთა ჯაჭვებით. ჩაანაცვლეთ `MyTarget` თქვენი ტარგეტით და დააფიქსირეთ Struo თქვენი არსებული ინსტრუმენტების დაინსტალირების სამუშაო პროცესის მეშვეობით. მიღებული სესია ხელახლა გამოიყენება ქეშზე წვდომის, ანგარიშგებისა და არტეფაქტების გამოქვეყნებისთვის ჯობის განმავლობაში.

სხვა პროვაიდერებზე, დააყენეთ `TUIST_TOKEN` <.localized_link href="/guides/server/authentication#account-tokens">ანგარიშის ტოკენზე</.localized_link>, რომელიც ავტორიზებულია თქვენთვის საჭირო ოპერაციებისთვის. შეინახეთ ის CI საიდუმლოების საცავში, არასდროს `struo.toml`-ში ან სამუშაო პროცესის წყაროში. ამ ტოკენის გამოყენებისას ინტერაქტიული შესვლის ეტაპი არ არის საჭირო.

მრავალმუშაკიანი ნაკრებებისთვის მიჰყევით <.localized_link href="/guides/features/test-sharding/struo">Struo ტესტების შარდინგს</.localized_link>. აპლიკაციების გამოქვეყნებისთვის დაამატეთ ცალსახა <.localized_link href="/guides/features/previews/struo">Struo პრივიუს გამოქვეყნების</.localized_link> ეტაპი. ჩვეულებრივი კომპილაციები არ აქვეყნებენ პრივიუსებს არაცხადი გზით.

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
> OIDC ავტორიზაციის გამოყენებამდე, უნდა <.localized_link href="/guides/integrations/gitforge/github">დააკავშიროთ თქვენი GitHub რეპოზიტორი</.localized_link> თქვენს Tuist პროექტთან. `permissions: id-token: write` აუცილებელია OIDC-ის მუშაობისთვის. Tuist 4.218.0-დან, CLI ცვლის იდენტობის ტოკენს თავის პირველ მოთხოვნაზე, ამიტომ სამუშაო პროცესს არ სჭირდება `tuist auth login` ეტაპი; უფრო ადრეულ ვერსიებზე, გაუშვით `tuist auth login` სხვა Tuist ბრძანებებამდე. ალტერნატიულად, შეგიძლიათ გამოიყენოთ <.localized_link href="/guides/server/authentication#account-tokens">ანგარიშის ტოკენი</.localized_link> `TUIST_TOKEN` საიდუმლოსთან ერთად.


> [!TIP]
> ჩვენ გირჩევთ გამოიყენოთ `mise use --pin` თქვენს Tuist პროექტებში Tuist-ის ვერსიის დასაფიქსირებლად გარემოებს შორის. ბრძანება აფიქსირებს Tuist-ის ვერსიას თქვენს `mise.toml` ფაილში.


### Xcode Cloud {#xcode-cloud}

[Xcode Cloud-ში](https://developer.apple.com/xcode-cloud/), რომელიც იყენებს Xcode პროექტებს როგორც სიმართლის ერთადერთ წყაროს, უნდა დაამატოთ [post-clone](https://developer.apple.com/documentation/xcode/writing-custom-build-scripts#Create-a-custom-build-script) სკრიპტი Tuist-ის დასაინსტალირებლად და საჭირო ბრძანებების შესასრულებლად, მაგალითად `tuist generate`:

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
> გამოიყენეთ <.localized_link href="/guides/server/authentication#account-tokens">ანგარიშის ტოკენი</.localized_link> `TUIST_TOKEN` გარემოს ცვლადის დაყენებით თქვენს Xcode Cloud სამუშაო პროცესის პარამეტრებში.


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
> OIDC ავტორიზაციის გამოყენებამდე, უნდა <.localized_link href="/guides/integrations/gitforge/github">დააკავშიროთ თქვენი GitHub რეპოზიტორი</.localized_link> თქვენს Tuist პროექტთან. CircleCI OIDC ტოკენები მოიცავს თქვენს დაკავშირებულ GitHub რეპოზიტორს, რომელსაც Tuist იყენებს თქვენს პროექტებზე წვდომის ავტორიზაციისთვის. Tuist 4.218.0-დან, CLI ცვლის იდენტობის ტოკენს თავის პირველ მოთხოვნაზე, ამიტომ `tuist auth login` ეტაპი არ არის საჭირო; უფრო ადრეულ ვერსიებზე, გაუშვით `mise exec -- tuist auth login` სხვა Tuist ბრძანებებამდე. ალტერნატიულად, შეგიძლიათ გამოიყენოთ <.localized_link href="/guides/server/authentication#account-tokens">ანგარიშის ტოკენი</.localized_link> `TUIST_TOKEN` გარემოს ცვლადთან ერთად.


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
> OIDC ავტორიზაციის გამოყენებამდე, უნდა <.localized_link href="/guides/integrations/gitforge/github">დააკავშიროთ თქვენი GitHub რეპოზიტორი</.localized_link> თქვენს Tuist პროექტთან. Bitrise OIDC ტოკენები მოიცავს თქვენს დაკავშირებულ GitHub რეპოზიტორს, რომელსაც Tuist იყენებს თქვენს პროექტებზე წვდომის ავტორიზაციისთვის. Tuist 4.218.0-დან, CLI ცვლის იდენტობის ტოკენს თავის პირველ მოთხოვნაზე, ამიტომ `tuist auth login` ეტაპი არ არის საჭირო; უფრო ადრეულ ვერსიებზე, გაუშვით `mise exec -- tuist auth login` სხვა Tuist ბრძანებებამდე. ალტერნატიულად, შეგიძლიათ გამოიყენოთ <.localized_link href="/guides/server/authentication#account-tokens">ანგარიშის ტოკენი</.localized_link> `TUIST_TOKEN` გარემოს ცვლადთან ერთად.


### Codemagic {#codemagic}

[Codemagic-ში](https://codemagic.io), შეგიძლიათ დაამატოთ დამატებითი ეტაპი თქვენს სამუშაო პროცესში Tuist-ის დასაინსტალირებლად:

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

[Appcircle-ში](https://appcircle.io), შეგიძლიათ გამოიყენოთ ჩაშენებული [Tuist Install](https://docs.appcircle.io/workflows/ios-specific-workflow-steps/tuist-install) და [Tuist Commands](https://docs.appcircle.io/workflows/ios-specific-workflow-steps/tuist-commands) სამუშაო პროცესის ეტაპები, ან დაამატოთ **Custom Script** ეტაპი **Git Clone** ეტაპის შემდეგ Tuist-ის დამოუკიდებლად დასაინსტალირებლად:

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
> **სამუშაო პროცესის ეტაპები**
>
> Tuist Install ეტაპი აინსტალირებს Tuist-ს Homebrew-ით და ასრულებს `tuist generate`. დააყენეთ **Tuist Version** შეყვანა ვერსიის ფიქსაციისთვის, შემდეგ დაამატეთ Tuist Commands ეტაპი ისეთი ბრძანებების შესასრულებლად, როგორიცაა `tuist test` ან `tuist build`.

> [!NOTE]
> **ავტორიზაცია**
>
> შექმენით <.localized_link href="/guides/server/authentication#account-tokens">ანგარიშის ტოკენი</.localized_link>, დაამატეთ ის როგორც ცვლადი სახელით `TUIST_TOKEN` [გარემოს ცვლადების ჯგუფში](https://docs.appcircle.io/build/build-environment-variables) და აირჩიეთ ეს ჯგუფი თქვენს აწყობის კონფიგურაციაში. მონიშნეთ ცვლადი როგორც საიდუმლო ჩაკეტვის ხატულით.

## xcodebuild გამოტანის ფორმატირება {#xcodebuild-output-formatting}

`tuist build`, `tuist test`, `tuist xcodebuild build` და `tuist xcodebuild test` აფორმატებენ `xcodebuild`-ის გამოტანას [xcbeautify](https://github.com/cpisciotta/xcbeautify)-ის ფორმატერით, ამიტომ არ გჭირდებათ ამ ბრძანებების xcbeautify-ში გატარება. GitHub Actions-ზე, რომელიც აღმოჩენილია `GITHUB_ACTIONS` გარემოს ცვლადით, Tuist იყენებს xcbeautify-ის GitHub Actions რენდერს, რომელიც აჩენს კომპილატორის გაფრთხილებებს, შეცდომებს და ტესტების ჩავარდნებს როგორც ანოტაციებს გაშვების შეჯამებაში და pull request-ზე. ყველა სხვა ადგილას ის იყენებს ტერმინალის რენდერს, ფერადს, თუ გამოტანა არ არის მილში გატარებული ან `NO_COLOR` არ არის დაყენებული.

გადაეცით `--verbose` `xcodebuild`-ის დაუფორმატებელი გამოტანის დასაბეჭდად, მაგალითად, როდესაც აწყობა ვერ ხერხდება ცხადი შეცდომის გარეშე.

თუ სამუშაო პირდაპირ უწოდებს `xcodebuild`-ს Tuist-ის ნაცვლად, გაატარეთ ის xcbeautify-ში და დააყენეთ `pipefail`, რათა ჩავარდნილმა აწყობამ მაინც ჩააგდოს ეტაპი:

```bash
set -o pipefail
xcodebuild test -scheme App | xcbeautify --renderer github-actions
```

## გაშვების ანგარიში {#run-report}

როდესაც Tuist ატვირთავს გაშვებას, მისი დაფის URL-ები იბეჭდება ლოგებში. მათ მისაღებად ლოგების სკრეპინგის გარეშე — მაგალითად, ტესტის ანგარიშის ბმულის Slack-ზე გასაგზავნად სამუშაოს ჩავარდნისას, ან გაშვების თქვენს ინსტრუმენტებში გადასაცემად — გადაეცით `--run-report-path` (ან დააყენეთ `TUIST_RUN_REPORT_PATH`) `tuist test`, `tuist xcodebuild test` ან `tuist xcodebuild build`-ს. Tuist წერს JSON ანგარიშს ამ გზაზე მას შემდეგ, რაც გაშვება აიტვირთება:

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
| `buildRunURL` | სტრიქონი? | დაფის URL აწყობის გაშვებისთვის, არსებობს, როდესაც ბრძანებამ ააწყო. |
| `testRuns` | მასივი | სქემის მიხედვით ტესტის შედეგები: `scheme`, `succeeded`, `totalTests`, `skippedTests`, `ranTests`, `failedTestNames`, `ranTestModules` და `skippedTestModules`. ტესტების რაოდენობა არის ტესტის საქმეები, და `skippedTests` ითვლის მათ, რომლებიც შედეგების პაკეტში მოხსენებულია როგორც გამოტოვებული. `skippedTestModules` ითვლის ტესტის მოდულებს, რომლებიც <.localized_link href="/guides/features/selective-testing">შერჩევითმა ტესტირებამ</.localized_link> გამოტოვა, და გამოტოვებულია, როდესაც შერჩევითი ტესტირება არ გამოიყენებოდა ან გაშვება არის ტესტის ნაწილი. |
| `buildRuns` | მასივი | სქემის მიხედვით აწყობის შედეგები: `scheme`, `succeeded`, `durationInSeconds`. |

`testRunURL` და `buildRunURL` დამოუკიდებელია: ბრძანება, რომელიც ერთდროულად აწყობს და ტესტავს, წერს ორივეს, რასაც ლოგები ვერ აკეთებენ — ისინი ბეჭდავენ მხოლოდ ერთ URL-ს გაშვებაზე.

> [!NOTE]
> **როდის იწერება ანგარიში**
>
> ანგარიში იწერება მხოლოდ იმ გაშვებებისთვის, რომლებიც აიტვირთება სერვერზე, რაც მოითხოვს ავტორიზაციას და ხდება ავტომატურად CI-ზე. გზა იწმინდება ყოველი გაშვების დასაწყისში, ამიტომ გაშვება, რომელიც არ ქმნის ანგარიშს, არაფერს ტოვებს, ვიდრე ძველს წინა გაშვებიდან.

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
