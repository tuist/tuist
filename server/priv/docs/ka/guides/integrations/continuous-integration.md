---
{
  "title": "უწყვეტი ინტეგრაცია (CI)",
  "titleTemplate": ":title · ავტომატიზაცია · სახელმძღვანელოები · Tuist",
  "description": "შეიტყვეთ, როგორ გამოიყენოთ Tuist თქვენს CI სამუშაო პროცესებში."
}
---
# უწყვეტი ინტეგრაცია (CI) {#continuous-integration-ci}

იმისთვის, რომ Tuist-ის ბრძანებები გაუშვათ თქვენს [უწყვეტი ინტეგრაციის](https://en.wikipedia.org/wiki/Continuous_integration) სამუშაო პროცესებში, საჭიროა მისი დაყენება თქვენს CI გარემოში. 

ავტორიზაცია არის სურვილისამებრ, მაგრამ აუცილებელია, თუ გსურთ გამოიყენოთ სერვერის მხარის ფუნქციები, როგორიცაა <.localized_link href="/guides/features/cache">ქეში</.localized_link>. იმისათვის, რომ შეამციროთ CI გაშვების ხანგრძლივობა და ხარჯები Tuist-ის დაყენების შემდეგ, იხილეთ [ნელი ბილდები](https://tuist.dev/solutions/slow-builds) და [CI ხარჯები](https://tuist.dev/solutions/ci-costs).

შემდეგი განყოფილებები მოიცავს მაგალითებს, თუ როგორ უნდა გააკეთოთ ეს სხვადასხვა CI პლატფორმაზე. Once უკავშირდება საკუთარი ნატიური Tuist პროვაიდერის მეშვეობით; მას არ სჭირდება Tuist CLI. ამ სამუშაო პროცესის შესახებ იხილეთ [Once](#once).

## Once {#once}

ჩააკომიტეთ პროვაიდერი და ქეშის მიბმა <.localized_link href="/guides/get-started/once-project">Once-თან დაწყება</.localized_link>-დან. დააყენეთ Once ჯობში [Once-ის დაყენების ინსტრუქციების](https://buildonce.dev/docs/guide/getting-started) გამოყენებით, შემდეგ კი გაიარეთ ავტორიზაცია ქეშირებადი სამუშაოს შესრულებამდე.

GitHub Actions, CircleCI და Bitrise მხარდაჭერენ Once-ის უინტერფეისო OpenID Connect შესვლას. დააკავშირეთ რეპოზიტორი თქვენს Tuist პროექტთან, როგორც აღწერილია <.localized_link href="/guides/server/authentication#oidc-tokens">OIDC ავტორიზაციაში</.localized_link>. GitHub Actions-ზე მიანიჭეთ identity-token ნებართვა:

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

აირჩიეთ OS, რომელსაც აქვს თქვენი ტარგეტებისთვის საჭირო ტულჩეინები. ჩაანაცვლეთ `MyTarget` თქვენი ტარგეტით და დააფიქსირეთ Once თქვენი არსებული ინსტრუმენტების დაყენების სამუშაო პროცესის მეშვეობით. მიღებული სესია ხელახლა გამოიყენება ქეშზე წვდომის, ანგარიშგებისა და არტეფაქტების გამოქვეყნებისთვის ჯობის დროს.

სხვა პროვაიდერებზე, დააყენეთ `TUIST_TOKEN` <.localized_link href="/guides/server/authentication#account-tokens">ანგარიშის ტოკენად</.localized_link>, რომელიც ავტორიზებულია თქვენთვის საჭირო ოპერაციებისთვის. შეინახეთ ის CI საიდუმლოების საცავში, არასდროს `once.toml`-ში ან სამუშაო პროცესის წყაროში. ამ ტოკენის გამოყენებისას ინტერაქტიული შესვლის ეტაპი არ არის საჭირო.

მრავალმუშაკიანი ნაკრებებისთვის, მიჰყევით <.localized_link href="/guides/features/test-sharding/once">Once ტესტების შარდინგს</.localized_link>. აპლიკაციების გამოსაქვეყნებლად, დაამატეთ ცალსახა <.localized_link href="/guides/features/previews/once">Once პრივიუს გამოქვეყნების</.localized_link> ეტაპი. ჩვეულებრივი ბილდები არ აქვეყნებენ პრივიუსებს იმპლიციტურად.

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
> OIDC ავტორიზაციის გამოყენებამდე, თქვენ უნდა <.localized_link href="/guides/integrations/gitforge/github">დააკავშიროთ თქვენი GitHub რეპოზიტორი</.localized_link> თქვენს Tuist პროექტთან. `permissions: id-token: write` აუცილებელია OIDC-ის მუშაობისთვის. Tuist 4.218.0-დან, CLI ცვლის იდენტობის ტოკენს თავის პირველ მოთხოვნაზე, ამიტომ სამუშაო პროცესს არ სჭირდება `tuist auth login` ეტაპი; ადრეულ ვერსიებზე, გაუშვით `tuist auth login` სხვა Tuist ბრძანებებამდე. ალტერნატიულად, შეგიძლიათ გამოიყენოთ <.localized_link href="/guides/server/authentication#account-tokens">ანგარიშის ტოკენი</.localized_link> `TUIST_TOKEN` საიდუმლოებით.


> [!TIP]
> ჩვენ გირჩევთ გამოიყენოთ `mise use --pin` თქვენს Tuist პროექტებში, რათა დააფიქსიროთ Tuist-ის ვერსია გარემოებს შორის. ბრძანება აფიქსირებს Tuist-ის ვერსიას თქვენს `mise.toml` ფაილში.


### Xcode Cloud {#xcode-cloud}

[Xcode Cloud-ში](https://developer.apple.com/xcode-cloud/), რომელიც იყენებს Xcode პროექტებს, როგორც სანდო წყაროს, დაგჭირდებათ [post-clone](https://developer.apple.com/documentation/xcode/writing-custom-build-scripts#Create-a-custom-build-script) სკრიპტის დამატება Tuist-ის დასაყენებლად და საჭირო ბრძანებების გასაშვებად, მაგალითად `tuist generate`:

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
> OIDC ავტორიზაციის გამოყენებამდე, თქვენ უნდა <.localized_link href="/guides/integrations/gitforge/github">დააკავშიროთ თქვენი GitHub რეპოზიტორი</.localized_link> თქვენს Tuist პროექტთან. CircleCI OIDC ტოკენები მოიცავს თქვენს დაკავშირებულ GitHub რეპოზიტორს, რომელსაც Tuist იყენებს თქვენს პროექტებზე წვდომის ავტორიზაციისთვის. Tuist 4.218.0-დან, CLI ცვლის იდენტობის ტოკენს თავის პირველ მოთხოვნაზე, ამიტომ `tuist auth login` ეტაპი არ არის საჭირო; ადრეულ ვერსიებზე, გაუშვით `mise exec -- tuist auth login` სხვა Tuist ბრძანებებამდე. ალტერნატიულად, შეგიძლიათ გამოიყენოთ <.localized_link href="/guides/server/authentication#account-tokens">ანგარიშის ტოკენი</.localized_link> `TUIST_TOKEN` გარემოს ცვლადით.


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
> OIDC ავტორიზაციის გამოყენებამდე, თქვენ უნდა <.localized_link href="/guides/integrations/gitforge/github">დააკავშიროთ თქვენი GitHub რეპოზიტორი</.localized_link> თქვენს Tuist პროექტთან. Bitrise OIDC ტოკენები მოიცავს თქვენს დაკავშირებულ GitHub რეპოზიტორს, რომელსაც Tuist იყენებს თქვენს პროექტებზე წვდომის ავტორიზაციისთვის. Tuist 4.218.0-დან, CLI ცვლის იდენტობის ტოკენს თავის პირველ მოთხოვნაზე, ამიტომ `tuist auth login` ეტაპი არ არის საჭირო; ადრეულ ვერსიებზე, გაუშვით `mise exec -- tuist auth login` სხვა Tuist ბრძანებებამდე. ალტერნატიულად, შეგიძლიათ გამოიყენოთ <.localized_link href="/guides/server/authentication#account-tokens">ანგარიშის ტოკენი</.localized_link> `TUIST_TOKEN` გარემოს ცვლადით.


### Codemagic {#codemagic}

[Codemagic-ში](https://codemagic.io), შეგიძლიათ დაამატოთ დამატებითი ეტაპი თქვენს სამუშაო პროცესში Tuist-ის დასაყენებლად:

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
> შექმენით <.localized_link href="/guides/server/authentication#account-tokens">ანგარიშის ტოკენი</.localized_link> და დაამატეთ ის, როგორც საიდუმლო გარემოს ცვლადი სახელით `TUIST_TOKEN`.

### Appcircle {#appcircle}

[Appcircle-ში](https://appcircle.io), შეგიძლიათ გამოიყენოთ ჩაშენებული [Tuist Install](https://docs.appcircle.io/workflows/ios-specific-workflow-steps/tuist-install) და [Tuist Commands](https://docs.appcircle.io/workflows/ios-specific-workflow-steps/tuist-commands) სამუშაო პროცესის ეტაპები, ან დაამატოთ **Custom Script** ეტაპი **Git Clone** ეტაპის შემდეგ Tuist-ის დამოუკიდებლად დასაყენებლად:

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
> Tuist Install ეტაპი აყენებს Tuist-ს Homebrew-ით და ასრულებს `tuist generate`. დააყენეთ **Tuist Version** შეყვანა ვერსიის ფიქსაციისთვის, შემდეგ დაამატეთ Tuist Commands ეტაპი ისეთი ბრძანებების გასაშვებად, როგორიცაა `tuist test` ან `tuist build`.

> [!NOTE]
> **ავტორიზაცია**
>
> შექმენით <.localized_link href="/guides/server/authentication#account-tokens">ანგარიშის ტოკენი</.localized_link>, დაამატეთ ის, როგორც ცვლადი სახელით `TUIST_TOKEN` [გარემოს ცვლადების ჯგუფში](https://docs.appcircle.io/build/build-environment-variables) და აირჩიეთ ეს ჯგუფი თქვენს აწყობის კონფიგურაციაში. მონიშნეთ ცვლადი, როგორც საიდუმლო, ჩაკეტვის ხატულას გამოყენებით.

## xcodebuild-ის გამომავალი მონაცემების ფორმატირება {#xcodebuild-output-formatting}

`tuist build`, `tuist test`, `tuist xcodebuild build` და `tuist xcodebuild test` აფორმატებენ `xcodebuild`-ის გამომავალ მონაცემებს [xcbeautify](https://github.com/cpisciotta/xcbeautify)-ის ფორმატერით, ამიტომ არ გჭირდებათ ამ ბრძანებების xcbeautify-ში გადატანა. GitHub Actions-ზე, რომელიც აღმოჩენილია `GITHUB_ACTIONS` გარემოს ცვლადის მეშვეობით, Tuist იყენებს xcbeautify-ის GitHub Actions რენდერერს, რომელიც კომპილატორის გაფრთხილებებს, შეცდომებს და ტესტების შეცდომებს აჩვენებს ანოტაციების სახით გაშვების შეჯამებაში და pull request-ზე. სხვა ყველგან ის იყენებს ტერმინალის რენდერერს, ფერადს, თუ გამომავალი მონაცემები არ არის გადატანილი ან `NO_COLOR` არ არის დაყენებული.

გადაეცით `--verbose` `xcodebuild`-ის დაუფორმატებელი გამომავალი მონაცემების დასაბეჭდად, მაგალითად, როდესაც აწყობა იჭედება ცხადი შეცდომის გარეშე.

თუ სამუშაო პირდაპირ უწოდებს `xcodebuild`-ს Tuist-ის ნაცვლად, გადაიტანეთ ის xcbeautify-ში და დააყენეთ `pipefail`, რათა ჩავარდნილმა აწყობამ მაინც ჩააგდოს ეტაპი:

```bash
set -o pipefail
xcodebuild test -scheme App | xcbeautify --renderer github-actions
```

## გაშვების ანგარიში {#run-report}

როდესაც Tuist ატვირთავს გაშვებას, მისი dashboard-ის URL-ები იბეჭდება ლოგებში. მათ მიღებისთვის ლოგების დამუშავების გარეშე — მაგალითად, ტესტის ანგარიშის ბმულის Slack-ზე გასაგზავნად სამუშაოს ჩავარდნისას, ან გაშვების თქვენს ინსტრუმენტებში გადასაცემად — გადაეცით `--run-report-path` (ან დააყენეთ `TUIST_RUN_REPORT_PATH`) `tuist test`-ს, `tuist xcodebuild test`-ს ან `tuist xcodebuild build`-ს. Tuist წერს JSON ანგარიშს ამ გზაზე გაშვების ატვირთვის შემდეგ:

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
| `runURL` | სტრიქონი | გაშვების dashboard-ის URL. ყოველთვის არსებობს. |
| `testRunURL` | სტრიქონი? | ტესტების გაშვების dashboard-ის URL, არსებობს, როდესაც ბრძანებამ გაუშვა ტესტები. |
| `buildRunURL` | სტრიქონი? | აწყობის გაშვების dashboard-ის URL, არსებობს, როდესაც ბრძანებამ შექმნა აწყობა. |
| `testRuns` | მასივი | სქემების მიხედვით ტესტის შედეგები: `scheme`, `succeeded`, `totalTests`, `skippedTests`, `ranTests`, `failedTestNames`, `ranTestModules` და `skippedTestModules`. ტესტების რაოდენობა არის ტესტის საქმეები, ხოლო `skippedTests` ითვლის იმას, რასაც შედეგების პაკეტი აცხადებს, როგორც გამოტოვებულს. `skippedTestModules` ითვლის ტესტის მოდულებს, რომლებიც <.localized_link href="/guides/features/selective-testing">შერჩევითმა ტესტირებამ</.localized_link> გამოტოვა, და გამოტოვებულია, როდესაც შერჩევითი ტესტირება არ გამოიყენებოდა ან გაშვება არის ტესტის ნაწილი. |
| `buildRuns` | მასივი | სქემების მიხედვით აწყობის შედეგები: `scheme`, `succeeded`, `durationInSeconds`. |

`testRunURL` და `buildRunURL` დამოუკიდებელია: ბრძანება, რომელიც ერთდროულად ქმნის აწყობას და ასრულებს ტესტებს, წერს ორივეს, რასაც ლოგები ვერ აკეთებენ — ისინი მხოლოდ ერთ URL-ს ბეჭდავენ თითოეული გაშვებისთვის.

> [!NOTE]
> **როდესაც იწერება ანგარიში**
>
> ანგარიში იწერება მხოლოდ იმ გაშვებებისთვის, რომლებიც აიტვირთება სერვერზე, რაც მოითხოვს ავტორიზაციას და ხდება ავტომატურად CI-ზე. გზა იშლება ყოველი გაშვების დასაწყისში, ამიტომ გაშვება, რომელიც არ ქმნის ანგარიშს, არაფერს ტოვებს, ნაცვლად წინა გაშვების მოძველებულისა.

GitLab CI-ზე, გავრცელებული გამოყენება არის URL-ის გამოტანა მოგვიანებითი სამუშაოებისთვის [`dotenv` ანგარიშის](https://docs.gitlab.com/ci/yaml/artifacts_reports/#artifactsreportsdotenv) მეშვეობით:

```yaml
test:
  script:
    - tuist test --run-report-path tuist-run.json
    - echo "TUIST_TEST_RUN_URL=$(jq -r '.testRunURL // empty' tuist-run.json)" >> run.env
  artifacts:
    reports:
      dotenv: run.env
```
