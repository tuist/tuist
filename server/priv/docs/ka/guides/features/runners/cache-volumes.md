---
{
  "title": "ქეშის ტომები",
  "titleTemplate": ":title · გამშვებები · ფუნქციები · სახელმძღვანელოები · Tuist",
  "description": "შეინახეთ Xcode-ის, მოდულების და Gradle-ის ქეში, ასევე ნებისმიერი სხვა დირექტორია Tuist-ის Linux ან macOS გამშვებ ჯობებს შორის GitHub Actions-ით, Buildkite-ით და GitLab CI-ით."
}
---
# ქეშის ტომები {#cache-volumes}

Tuist-ის რანერებს შეუძლიათ შეინარჩუნონ ქეში ჯობებს შორის, რათა ახალმა რანერმა „თბილად“ დაიწყოს. თითოეული ჯობა იღებს ბოლოს შენახული შინაარსის პირად, ჩაწერად ასლს.

- **მართული ქეშები** ინახავს Xcode-ის კომპილაციის ქეშს, Tuist-ის მოდულის ქეშს და Gradle-ის ქეშებს თითო-თითო ნაბიჯით. Tuist-მა იცის, სად მდებარეობს თითოეული ქეში და ინახავს მას თავის საცავში.
- **მორგებული ტომები** ინახავს ნებისმიერ სხვა დირექტორიას, მაგალითად, პაკეტის მენეჯერის ჩამოტვირთვის ქეშს, თქვენ მიერ არჩეული გასაღების სახელით.

დაამატეთ ეს ნაბიჯები checkout-ის შემდეგ და იმ ბრძანებებამდე, რომლებიც იყენებენ ქეშებს. რანერებზე, რომლებიც არ არიან Tuist-ის რანერები, ისინი არაფერს აკეთებენ და ქეშის პრობლემა არასდროს ავარებს ჯობას: ნაბიჯი წერს გაფრთხილებას და ჯობა გრძელდება ცარიელი ქეშით.

## მართული ქეშები {#managed-caches}

ნაბიჯები მხოლოდ განსაზღვრავენ, სად მდებარეობს ქეშები. შეინარჩუნეთ თქვენი არსებული ქეშის კონფიგურაცია: `tuist setup cache` ან ააწყვეთ ბილდის პარამეტრები, რომლებიც რთავენ კომპილაციის ქეშირებას (იხილეთ <.localized_link href="/guides/features/cache/xcode-cache">Xcode cache guide</.localized_link>), მოდულის ქეშის ავტორიზაცია და <.localized_link href="/guides/features/cache/gradle-cache">Tuist Gradle plugin</.localized_link> Gradle-ის დისტანციური ბილდის ქეშისთვის. GitLab CI-ში გააერთიანეთ ფრაგმენტები `!reference`-ით, რადგან `extends` ცვლის `before_script`-ს.

### Xcode cache {#xcode-cache}

ინახავს Xcode-ის კომპილაციის ქეშის საცავს macOS რანერებზე.

::: code-group

```yaml [GitHub Actions]
jobs:
  build:
    runs-on: tuist-macos
    steps:
      - uses: actions/checkout@v4
      - uses: tuist/xcode-cache@v1
      - run: xcodebuild build -scheme App -destination 'generic/platform=iOS Simulator' COMPILATION_CACHE_ENABLE_CACHING=YES
```

```yaml [Buildkite]
steps:
  - label: Build
    agents:
      queue: tuist-macos
    plugins:
      - tuist/xcode-cache#v1: ~
    command: xcodebuild build -scheme App -destination 'generic/platform=iOS Simulator' COMPILATION_CACHE_ENABLE_CACHING=YES
```

```yaml [GitLab CI]
include:
  - remote: https://raw.githubusercontent.com/tuist/xcode-cache-gitlab/v1/xcode-cache.yml

build:
  tags: [tuist-macos]
  before_script:
    - !reference [.tuist-xcode-cache, before_script]
  script:
    - xcodebuild build -scheme App -destination 'generic/platform=iOS Simulator' COMPILATION_CACHE_ENABLE_CACHING=YES
```
<!-- -->
:::

### Module cache {#module-cache}

ინახავს Tuist-ის ლოკალურ ქეშს macOS რანერებზე: <.localized_link href="/guides/features/cache/module-cache">module cache</.localized_link> ბინარები, კომპილირებული მანიფესტები, პლაგინები და შერჩევითი ტესტირების შედეგები.

::: code-group

```yaml [GitHub Actions]
jobs:
  test:
    runs-on: tuist-macos
    permissions:
      contents: read
      id-token: write
    steps:
      - uses: actions/checkout@v4
      - uses: tuist/module-cache@v1
      - uses: jdx/mise-action@v4
      - run: tuist auth login
      - run: tuist install
      - run: tuist generate --no-open
      - run: tuist test
```

```yaml [Buildkite]
steps:
  - label: Test
    agents:
      queue: tuist-macos
    plugins:
      - tuist/module-cache#v1: ~
    command: |
      mise install
      tuist auth login
      tuist install
      tuist generate --no-open
      tuist test
```

```yaml [GitLab CI]
include:
  - remote: https://raw.githubusercontent.com/tuist/module-cache-gitlab/v1/module-cache.yml

test:
  tags: [tuist-macos]
  before_script:
    - !reference [.tuist-module-cache, before_script]
  script:
    - mise install
    - tuist auth login
    - tuist install
    - tuist generate --no-open
    - tuist test
```
<!-- -->
:::

### Gradle cache {#gradle-cache}

ინახავს `caches` და `wrapper` დირექტორიებს Gradle-ის მომხმარებლის საწყის საქაღალდეში Linux და macOS რანერებზე: დამოკიდებულებები, ტრანსფორმირებული jar-ები, კომპილირებული ბილდის სკრიპტები და Gradle-ის დისტრიბუციები. დააყენეთ `GRADLE_USER_HOME` ნაბიჯამდე, თუ იყენებთ მას, და გამორთეთ ამ დირექტორიების სხვა ქეშირება, მაგალითად, `cache: gradle` `actions/setup-java`-ზე.

::: code-group

```yaml [GitHub Actions]
jobs:
  test:
    runs-on: tuist-linux
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-java@v4
        with:
          distribution: temurin
          java-version: '21'
      - uses: tuist/gradle-cache@v1
      - run: ./gradlew test
```

```yaml [Buildkite]
steps:
  - label: Test
    agents:
      queue: tuist-linux
    plugins:
      - tuist/gradle-cache#v1: ~
    command: ./gradlew test
```

```yaml [GitLab CI]
include:
  - remote: https://raw.githubusercontent.com/tuist/gradle-cache-gitlab/v1/gradle-cache.yml

test:
  tags: [tuist-linux]
  before_script:
    - !reference [.tuist-gradle-cache, before_script]
  script:
    - ./gradlew test
```
<!-- -->
:::

## Custom volumes {#custom-volumes}

აირჩიეთ სტაბილური `key` და `path`, შემდეგ მიამაგრეთ ტომი დამოკიდებულებების ინსტალაციამდე. გზა უნდა იყოს ცარიელი ან არარსებული. წაშალეთ ნებისმიერი არქივის ქეში ან არტეფაქტის აღდგენა, რომელიც წერს იმავე დირექტორიაში. რამდენიმე დირექტორიის ერთ ტომში შესანახად, იხილეთ [რამდენიმე დირექტორია ერთ ტომში](#several-directories-in-one-volume).

::: code-group

```yaml [GitHub Actions]
jobs:
  test:
    runs-on: tuist-linux
    steps:
      - uses: actions/checkout@v4
      - uses: tuist/cache-volume@v1
        with:
          key: npm
          path: ~/.npm
      - run: npm ci
      - run: npm test
```

```yaml [Buildkite]
steps:
  - label: Test
    agents:
      queue: tuist-linux
    plugins:
      - tuist/cache-volume#v1:
          volumes:
            - key: npm
              path: ~/.npm
    command: |
      npm ci
      npm test
```

```yaml [GitLab CI]
test:
  tags: [tuist-linux]
  before_script:
    - tuist-cache-volume --key npm --path ~/.npm
  script:
    - npm ci
    - npm test
```
<!-- -->
:::

### რამდენიმე დირექტორია ერთ ტომში {#several-directories-in-one-volume}

ტომს შეუძლია შეინახოს რამდენიმე დირექტორია. GitHub Actions-ში ჩამოთვალეთ თითო გზა ხაზზე; Buildkite-ში დააყენეთ `path` სიად; GitLab CI-ში გადაეცით `--path` თითო დირექტორიისთვის ერთხელ. ცარიელი ხაზები და გარშემო სივრცეები იგნორირდება.

::: code-group

```yaml [GitHub Actions]
jobs:
  lint:
    runs-on: tuist-linux
    steps:
      - uses: actions/checkout@v4
      - uses: tuist/cache-volume@v1
        with:
          key: python-tools
          path: |
            ~/.cache/pip
            ~/.cache/pre-commit
      - run: pip install pre-commit
      - run: pre-commit run --all-files
```

```yaml [Buildkite]
steps:
  - label: Lint
    agents:
      queue: tuist-linux
    plugins:
      - tuist/cache-volume#v1:
          volumes:
            - key: python-tools
              path:
                - ~/.cache/pip
                - ~/.cache/pre-commit
    command: |
      pip install pre-commit
      pre-commit run --all-files
```

```yaml [GitLab CI]
lint:
  tags: [tuist-linux]
  before_script:
    - tuist-cache-volume --key python-tools --path ~/.cache/pip --path ~/.cache/pre-commit
  script:
    - pip install pre-commit
    - pre-commit run --all-files
```
<!-- -->
:::

- **გაზიარებული სიმძლავრე.** ყველა გზა იზიარებს ტომის სიმძლავრეს და ერთად აღდგება და ინახება.
- **დააჯგუფეთ მცირე, დაკავშირებული დირექტორიები.** დიდ ან სწრაფად ცვალებად დირექტორიას მიანიჭეთ საკუთარი ტომი.
- **არ არის ჩადგმა.** ერთი ტომის გზები არ უნდა შეიცავდნენ ერთმანეთს.
- **სიის ცვლილება იწყება ცივად.** თითოეული გზა ინახება ტომის შიგნით საკუთარ დირექტორიაში, რომელიც იდენტიფიცირდება გზის ჩაწერის მიხედვით. გადასვლა ერთ გზასა და რამდენიმეს შორის, ან გზის დამატება, წაშლა ან გადაწერა ცვლის ამ განლაგებას: ცვლილების შემდეგ პირველი ჯობა იწყება ცივად დაზარალებული გზებისთვის. იმ გზების შინაარსი, რომლებიც აღარ არის სიაში, რჩება ტომში მანამ, სანამ არ გაასუფთავებთ მას.

### როგორ მუშაობს გასაღებები {#how-keys-work}

გასაღები ასახელებს ტომს, რომელიც დროთა განმავლობაში იცვლება; ის არ არის ფიქსირებული სნაპშოტის სახელი, როგორც `actions/cache` გასაღები.

- **ერთი ტომი თითო გასაღებზე.** თითოეული გასაღები შეზღუდულია რეპოზიტორიით (Buildkite-ზე — პაიპლაინით; GitLab CI-ზე — პროექტით), პლატფორმით, CPU არქიტექტურით და მომხმარებლით. ყოველი ჯობა, რომელიც მას მიამაგრებს, იწყებს ბოლოს შენახული შინაარსიდან და შესაბამისი ჯობები ინახავენ თავიანთ ცვლილებებს იმავე ტომში.
- **შეინარჩუნეთ გასაღებების სტაბილურობა.** არ ჩასვათ ვერსიები ან lockfile-ის ჰეშები გასაღებში. `actions/cache`-თან ერთად, გასაღები, როგორიცაა `deps-${{ hashFiles('Package.resolved') }}`, ქმნის ახალ ჩანაწერს თითო ცვლილებისთვის, ხოლო `restore-keys` ბრუნდება ძველთან. აქ ახალი გასაღები ნიშნავს ახალ, ცარიელ ტომს: ყოველი ცვლილების შემდეგ პირველი ჯობა იწყება ცივად, ხოლო ძველი ტომები რჩებიან მანამ, სანამ არ ამოიწურებიან. შეინარჩუნეთ გასაღები და მიეცით თქვენს ინსტრუმენტს შინაარსის განახლების საშუალება; პაკეტის მენეჯერები ხელახლა იყენებენ ყველაფერს, რაც კვლავ ვალიდურია.
- **არ არის ნაწილობრივი დამთხვევები.** არ არსებობს აღდგენის გასაღებები. გასაღები, რომელიც ჯერ არ შენახულა, იწყება ცარიელი.
- **`tuist-`-ით დაწყებული გასაღებები რეზერვირებულია** Tuist-ის საკუთარი ქეშებისთვის და უარყოფილია ტომის მიმაგრებამდე.
- **განახლებით დაწყება.** შეცვალეთ გასაღები ან გაასუფთავეთ ტომი დაფაზე, როდესაც გსურთ, რომ ჯობა დაიწყოს ცარიელი.
- **`tuist-` გასაღებები დაუტოვეთ Tuist-ს.** მართული ქეშები იყენებენ გასაღებებს, რომლებიც იწყება `tuist-`-ით, ამიტომ აირჩიეთ სხვა სახელი თქვენი საკუთარი ტომებისთვის.

Linux-ზე გზები მაუნტდება როგორც ჩვეულებრივი დირექტორიები, ამიტომ ინსტრუმენტებს შეუძლიათ გამოიყენონ ჩვეულებრივი ადგილები, როგორიცაა `deps`, `_build` და `node_modules`. შეინარჩუნეთ თქვენი ჩვეულებრივი `.gitignore` წესები. macOS-ზე გზები არის სიმლინკები: გამოიყენეთ ჩამოტვირთვის ქეშები, როგორიცაა `~/.npm`; `node_modules` და ინსტრუმენტები, რომლებიც ცვლიან თავიანთ ქეშის დირექტორიას, არ არის მხარდაჭერილი. იგნორირეთ სამუშაო სივრცის სიმლინკები ბოლო სლეშის გარეშე `.gitignore`-ში.

## ცვლილებების შენახვა {#saving-changes}

მართული ქეშები და მორგებული ტომები ინახავენ თქვენი საკუთარი რეპოზიტორიის წარმატებული ჯობების ცვლილებებს, ნებისმიერ ბრენჩზე:

| პროვაიდერი | ჯობები, რომლებიც ინახავენ ცვლილებებს |
| --- | --- |
| GitHub Actions | Push, დაგეგმილი, ხელით გაშვებული და pull request ჯობები თავად რეპოზიტორიიდან |
| Buildkite | Webhook და დაგეგმილი ბილდები პაიპლაინის რეპოზიტორიისთვის, მათ შორის მისი pull requests |
| GitLab CI | პროექტის push, დაგეგმილი და web პაიპლაინები, ასევე საკუთარი merge request-ების პაიპლაინები, როდესაც კავშირს აქვს <.localized_link href="/guides/features/runners/ci-providers/gitlab-ci#merge-request-pipelines">API access token</.localized_link> |

სხვა ჯობებს შეუძლიათ გამოიყენონ ქეში, მაგრამ მათი ცვლილებები იკარგება. ეს მოიცავს fork pull request-ებს, `pull_request_target` ჯობებს, Buildkite ბილდებს, რომლებიც გაშვებულია API-დან ან დაფიდან, GitLab merge request-ებს ფორკებიდან ან API access token-ის გარეშე, და თეგებს. ჯობა, რომელიც არ ცვლის ტომს, ტოვებს შენახულ ვერსიას უცვლელად. შეგიძლიათ შეზღუდოთ, თუ რომელი ბრენჩები ინახავენ მონაცემებს runner პროფილზე; იხილეთ [აირჩიეთ, რომელი ბრენჩები შეინახოს](#choose-which-branches-save).

პარალელური ჯობები მუშაობენ დამოუკიდებლად; სხვადასხვა ჯობების ცვლილებები არ ერწყმის ერთმანეთს. არასოდეს შეინახოთ ქეშში მონაცემები ან შეუცვლელი ინფორმაცია.

### აირჩიეთ, რომელი ბრენჩები შეინახოს {#choose-which-branches-save}

შეგიძლიათ შეცვალოთ, თუ რომელი ბრენჩები ინახავენ მართულ ქეშებს და მორგებულ ტომებს. გახსენით **Runners → Profiles**, ჩაასწორეთ პროფილი, რომელსაც იყენებენ თქვენი ჯობები, და გაშალეთ **Save cache from**. ჯობები იყენებენ პროფილს, რომელსაც ისინი ითხოვენ: `runs-on:`-ში GitHub Actions-ზე, როგორც რიგს Buildkite-ზე, ან `tags:`-ში GitLab CI-ზე. პარამეტრები ვრცელდება ყველა ტომზე, რომელსაც იყენებენ ჯობები ამ პროფილზე, მათ შორის მოგვიანებით შექმნილ ტომებზე.

![runner პროფილის ფორმა გაშლილი "Save cache from" სექციით, ჩართული "Default branch" და დამატებული develop და release/* როგორც დამატებითი ბრენჩები](/images/guides/features/runners/save-cache-from.png)

ნაგულისხმევად, რეპოზიტორიის ყოველი წარმატებული ჯობა ინახავს თავის ცვლილებებს. მხოლოდ ზოგიერთი ბრენჩიდან შესანახად, ჩართეთ **Limit to specific branches**:

- **Default branch** საშუალებას აძლევს ჯობებს თითოეული რეპოზიტორიის ნაგულისხმევ ბრენჩზე შეინახონ მონაცემები. გამორთეთ ის, თუ გსურთ შენახვა მხოლოდ დამატებითი ბრენჩებიდან.
- **Additional branches**-ის ქვეშ, დაამატეთ 20-მდე ბრენჩის სახელი, რომლებიც ასევე შეინახავენ მონაცემებს. გამოიყენეთ `*` როგორც ვაილდქარდი: `release/*` ემთხვევა `release/1.0`-ს.

ჯობები, რომლებიც ჩამოთვლილია [ცვლილებების შენახვა](#saving-changes)-ში, ინახავენ თავიანთ ცვლილებებს, როდესაც მათი ბრენჩი ემთხვევა. GitHub Actions push და ხელით გაშვებულ ჯობებზე, შესაბამისი სახელის მქონე თეგი ასევე ემთხვევა.

სხვა ბრენჩებზე მყოფ ჯობებს შეუძლიათ კვლავ გამოიყენონ ქეში, მაგრამ მათი ცვლილებები იკარგება. ჯობები, რომლებიც არასოდეს ინახავენ მონაცემებს, მაგალითად fork pull request-ები, ასევე არ ინახავენ შესაბამის ბრენჩზეც. ამ პარამეტრების შეზღუდვა ან პროფილის წაშლა იწვევს გადაუდებელი ცვლილებების დაკარგვას, რომლებსაც ისინი აღარ უშვებენ; წაშლილი პროფილი ბრუნდება ყველა ბრენჩიდან შენახვის რეჟიმზე.

## მოცულობა და შენახვა {#capacity-and-retention}

Xcode ქეში იწყება **30 GB**-ით. მოდულის ქეში, Gradle ქეში და თითოეული მორგებული ტომი იწყება **20 GB**-ით. დააყენეთ ზომა, რათა მიანიჭოთ ქეშს ან ტომს სხვა მოცულობა, GB-ის მთელი რიცხვი `1gb`-დან `100gb`-მდე:

::: code-group

```yaml [GitHub Actions]
- uses: tuist/xcode-cache@v1
  with:
    size: 50gb
- uses: tuist/module-cache@v1
  with:
    size: 40gb
```

```yaml [Buildkite]
plugins:
  - tuist/xcode-cache#v1:
      size: 50gb
  - tuist/module-cache#v1:
      size: 40gb
```

```yaml [GitLab CI]
build:
  variables:
    TUIST_XCODE_CACHE_SIZE: 50gb
    TUIST_MODULE_CACHE_SIZE: 40gb
```
<!-- -->
:::

Gradle ქეში და მორგებული ტომები იღებენ იგივე `size` შეყვანას (`TUIST_GRADLE_CACHE_SIZE` და `TUIST_VOLUME_SIZE` GitLab CI-ში, `--size` `tuist-cache-volume`-ისთვის). უფრო დიდი ზომა ზრდის ტომს, ინარჩუნებს მის შიგთავსს, შემდეგი ჯობიდან. უფრო მცირე ზომა მოქმედებს ტომის შემდეგი გასუფთავების ან ვადის გასვლის შემდეგ. როდესაც ჯობები ითხოვენ ერთი ქეშის სხვადასხვა ზომას, მოქმედებს უდიდესი, ამიტომ გამოაცხადეთ თითოეული ზომა ერთ ადგილას.

ყველა მათგანი ვადა გაუდის **7 დღის განმავლობაში ჯობის მაუნტის გარეშე**, და შემდეგი ჯობა იწყება ცარიელი ტომით ვადის გასვლის შემდეგ. Tuist ასუფთავებს Xcode და მოდულის ქეშებს მათი მოცულობის შესაბამისად, ხოლო Gradle ქეშის ნაბიჯი აიძულებს Gradle-ს წაშალოს ჩანაწერები, რომლებიც შვიდი დღის განმავლობაში არ გამოუყენებია ყოველი ბილდის შემდეგ.

მორგებული ტომები არ ასუფთავებენ ძველ დამოკიდებულებებს: გამოიყენეთ თქვენი ინსტრუმენტის გასუფთავების პარამეტრები, რათა შეინარჩუნოთ ისინი მცირე ზომის. ჩაწერა სავსე ტომში შეიძლება გამოიწვიოს ჯობის შეცდომა. როდესაც შენახული შიგთავსი აღწევს ტომის მოცულობის **80%**-ს და ჯობას ელევა ადგილი მათზე, შემდეგი ჯობა იწყება ცარიელი ტომით და მისი ცვლილებები იწყებენ ახალ შენახულ მდგომარეობას.

## ტომების ინსპექტირება და გასუფთავება {#inspecting-and-clearing-volumes}

გახსენით **Runners → Volumes**, რათა შეამოწმოთ გამოყენებული ადგილი, ქეშში მოხვედრის მაჩვენებელი და ჯობების ისტორია. ანგარიშის ადმინისტრატორებს შეუძლიათ აირჩიონ **Clear volume**, რათა მომავალი ჯობები დაიწყონ ცარიელი მდგომარეობით. მიმდინარე ჯობები ინარჩუნებენ თავიანთ პირად ასლებს, მაგრამ ვერ შეინახავენ მათ უკან. Xcode და მოდულის ქეშები ასევე ჩანს იქ, მაგრამ მათი გასუფთავება შეუძლებელია.
