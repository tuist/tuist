---
{
  "title": "ქეშის ტომები",
  "titleTemplate": ":title · გამშვებები · ფუნქციები · სახელმძღვანელოები · Tuist",
  "description": "შეინახეთ Xcode-ის, მოდულებისა და Gradle-ის ქეში და ნებისმიერი სხვა დირექტორია Tuist-ის Linux ან macOS გამშვებ ჯობებს შორის GitHub Actions-, Buildkite- და GitLab CI-ს გამოყენებით."
}
---
# ქეშის ტომები {#cache-volumes}

Tuist-ის რანერებს შეუძლიათ შეინარჩუნონ ქეში ჯობებს შორის, რათა ახალმა რანერმა თბილად დაიწყოს. თითოეული ჯობა იღებს უახლესი შენახული შინაარსის პირად წასაკითხ-ჩასაწერ ასლს.

- **მართული ქეშები** ინახავენ Xcode-ის კომპილაციის ქეშს, Tuist-ის მოდულის ქეშს და Gradle-ის ქეშებს თითო ნაბიჯით. Tuist-მა იცის, სად მდებარეობს თითოეული ქეში და ინახავს მას თავის საცავში.
- **მორგებული ტომები** ინახავენ ნებისმიერ სხვა დირექტორიას, მაგალითად, პაკეტების მენეჯერის ჩამოტვირთვის ქეშს, თქვენ მიერ არჩეული გასაღების ქვეშ.

დაამატეთ ნაბიჯები checkout-ის შემდეგ და ბრძანებებამდე, რომლებიც იყენებენ ქეშებს. რანერებზე, რომლებიც არ არის Tuist-ის რანერები, ისინი არაფერს აკეთებენ და ქეშის პრობლემა არასდროს ავარებს ჯობას: ნაბიჯი აღრიცხავს გაფრთხილებას და ჯობა გრძელდება ცარიელი ქეშით.

## მართული ქეშები {#managed-caches}

ნაბიჯები მხოლოდ განსაზღვრავენ, სად მდებარეობენ ქეშები. შეინარჩუნეთ თქვენი არსებული ქეშის კონფიგურაცია: `tuist setup cache` ან აგების პარამეტრები, რომლებიც რთავენ კომპილაციის ქეშირებას (იხილეთ <.localized_link href="/guides/features/cache/xcode-cache">Xcode-ის ქეშის სახელმძღვანელო</.localized_link>), მოდულის ქეშის ავტორიზაცია და <.localized_link href="/guides/features/cache/gradle-cache">Tuist Gradle-ის პლაგინი</.localized_link> Gradle-ის დისტანციური აგების ქეშისთვის. GitLab CI-ში გააერთიანეთ ფრაგმენტები `!reference`-ით, რადგან `extends` ცვლის `before_script`-ს.

### Xcode-ის ქეში {#xcode-cache}

ინახავს Xcode-ის კომპილაციის ქეშის საცავს macOS-ის რანერებზე.

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

### მოდულის ქეში {#module-cache}

ინახავს Tuist-ის ლოკალურ ქეშს macOS-ის რანერებზე: <.localized_link href="/guides/features/cache/module-cache">მოდულის ქეშის</.localized_link> ბინარები, კომპილირებული მანიფესტები, პლაგინები და შერჩევითი ტესტირების შედეგები.

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

### Gradle-ის ქეში {#gradle-cache}

ინახავს `caches` და `wrapper` დირექტორიებს Gradle-ის მომხმარებლის საწყის დირექტორიაში Linux-ისა და macOS-ის რანერებზე: დამოკიდებულებები, ტრანსფორმირებული jar-ფაილები, კომპილირებული აგების სკრიპტები და Gradle-ის დისტრიბუციები. დააყენეთ `GRADLE_USER_HOME` ნაბიჯამდე, თუ იყენებთ მას, და გამორთეთ ამ დირექტორიების სხვა ქეშირება, მაგალითად, `cache: gradle` `actions/setup-java`-ზე.

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

## მორგებული ტომები {#custom-volumes}

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

ტომს შეუძლია შეინახოს რამდენიმე დირექტორია. GitHub Actions-ში ჩამოთვალეთ ერთი გზა ხაზზე; Buildkite-ში დააყენეთ `path` სიად; GitLab CI-ში გადაეცით `--path` თითო დირექტორიისთვის ერთხელ. ცარიელი ხაზები და გარშემო სივრცეები იგნორირდება.

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

- **გაზიარებული ტევადობა.** ყველა გზა იზიარებს ტომის ტევადობას და ერთად აღდგება და ინახება.
- **დააჯგუფეთ პატარა, დაკავშირებული დირექტორიები.** დიდ ან სწრაფად ცვალებად დირექტორიას მიანიჭეთ საკუთარი ტომი.
- **არ არის ჩადგმა.** ერთი ტომის გზები არ უნდა შეიცავდნენ ერთმანეთს.
- **სიის შეცვლა ცივად იწყება.** თითოეული გზა ინახება ტომის შიგნით საკუთარ დირექტორიაში, იდენტიფიცირებული გზის ჩაწერის მიხედვით. გადასვლა ერთ გზასა და რამდენიმეს შორის, ან გზის დამატება, წაშლა ან გადაწერა ცვლის ამ განლაგებას: ცვლილების შემდეგ პირველი ჯობა იწყება ცივად დაზარალებული გზებისთვის. გზების შინაარსი, რომლებიც აღარ არის ჩამოთვლილი, რჩება ტომში მისი წაშლამდე.

### როგორ მუშაობენ გასაღებები {#how-keys-work}

გასაღები არქვავს ტომს, რომელიც დროთა განმავლობაში იცვლება; ეს არ არის ფიქსირებული სნეპშოტის სახელი, როგორც `actions/cache` გასაღები.

- **ერთი ტომი თითო გასაღებზე.** თითოეული გასაღები შეზღუდულია რეპოზიტორიით (Buildkite-ზე — პაიპლაინით; GitLab CI-ზე — პროექტით), პლატფორმით, CPU-ის არქიტექტურით და მომხმარებლით. ყოველი ჯობა, რომელიც მას მიამაგრებს, იწყება უახლესი შენახული შინაარსიდან, და შესაბამისი ჯობები ინახავენ ცვლილებებს იმავე ტომში.
- **შეინარჩუნეთ გასაღებები სტაბილურად.** არ ჩასვათ ვერსიები ან lockfile-ის ჰეშები გასაღებში. `actions/cache`-თან ერთად, გასაღები, როგორიცაა `deps-${{ hashFiles('Package.resolved') }}`, ქმნის ახალ ჩანაწერს თითო ცვლილებისთვის, და `restore-keys` ბრუნდება ძველთან. აქ, ახალი გასაღები არის ახალი, ცარიელი ტომი: ყოველი ცვლილების შემდეგ პირველი ჯობა იწყება ცივად, და ძველი ტომები რჩებიან მათი ვადაგასვლამდე. შეინარჩუნეთ გასაღები და მიეცით თქვენს ინსტრუმენტს შინაარსის განახლების საშუალება; პაკეტების მენეჯერები ხელახლა იყენებენ იმას, რაც კვლავ ვალიდურია.
- **არ არის ნაწილობრივი დამთხვევები.** არ არსებობს აღდგენის გასაღებები. გასაღები, რომელიც ჯერ არ არის შენახული, იწყება ცარიელად.
- **გასაღებები, რომლებიც იწყება `tuist-`-ით, რეზერვირებულია** Tuist-ის საკუთარი ქეშებისთვის და უარყოფილია ტომის მიმაგრებამდე.
- **დაიწყეთ თავიდან განზრახ.** შეცვალეთ გასაღები, ან წაშალეთ ტომი, როდესაც გსურთ, რომ ჯობა დაიწყოს ცარიელად.
- **დატოვეთ `tuist-` გასაღებები Tuist-ს.** მართული ქეშები იყენებენ გასაღებებს, რომლებიც იწყება `tuist-`-ით, ამიტომ აირჩიეთ სხვა სახელი თქვენი საკუთარი ტომებისთვის.

Linux-ზე, გზები მიმაგრებულია როგორც ჩვეულებრივი დირექტორიები, ამიტომ ინსტრუმენტებს შეუძლიათ გამოიყენონ ჩვეულებრივი ადგილები, როგორიცაა `deps`, `_build` და `node_modules`. შეინარჩუნეთ თქვენი ჩვეულებრივი `.gitignore` წესები. macOS-ზე, გზები არის სიმბოლური ბმულები: გამოიყენეთ ჩამოტვირთვის ქეშები, როგორიცაა `~/.npm`; `node_modules` და ინსტრუმენტები, რომლებიც ცვლიან თავიანთ ქეშის დირექტორიას, არ არის მხარდაჭერილი. იგნორირეთ სამუშაო სივრცის ბმულები დახურულ ხაზის გარეშე `.gitignore`-ში.

## ცვლილებების შენახვა {#saving-changes}

მართული ქეშები და მორგებული ტომები ინახავენ წარმატებული ჯობების ცვლილებებს თქვენი საკუთარი რეპოზიტორიიდან, ნებისმიერ ბრენჩზე:

| პროვაიდერი | ჯობები, რომლებიც ინახავენ ცვლილებებს |
| --- | --- |
| GitHub Actions | Push, განრიგი, ხელით გაშვება და pull request ჯობები თავად რეპოზიტორიიდან |
| Buildkite | Webhook და განრიგითი ბილდები პაიპლაინის რეპოზიტორიისთვის, მათ შორის მისი pull requests-ებისთვის |
| GitLab CI | პროექტის Push, განრიგითი და ვებ-პაიპლაინები, ასევე საკუთარი merge request-ების პაიპლაინები, როდესაც კავშირს აქვს <.localized_link href="/guides/features/runners/ci-providers/gitlab-ci#merge-request-pipelines">API წვდომის ტოკენი</.localized_link> |

სხვა ჯობებს შეუძლიათ გამოიყენონ ქეში, მაგრამ მათი ცვლილებები იკარგება. ეს მოიცავს fork pull requests-ებს, `pull_request_target` ჯობებს, Buildkite ბილდებს, რომლებიც გაშვებულია API-დან ან დაფიდან, GitLab merge requests-ებს ფორკებიდან ან API წვდომის ტოკენის გარეშე, და თეგებს. ჯობა, რომელიც არ ცვლის ტომს, ტოვებს შენახულ ვერსიას უცვლელად. შეგიძლიათ შეზღუდოთ, თუ რომელი ბრენჩები ინახავენ მონაცემებს რანერის პროფილზე; იხილეთ [აირჩიეთ, რომელი ბრენჩები შეინახონ](#choose-which-branches-save).

პარალელური ჯობები მუშაობენ დამოუკიდებლად; სხვადასხვა ჯობების ცვლილებები არ ერწყმის ერთმანეთს. არასდროს შეინახოთ ქეშში სერთიფიკატები ან ჩაუნაცვლებელი მონაცემები.

### აირჩიეთ, რომელი ბრენჩები შეინახონ {#choose-which-branches-save}

შეგიძლიათ შეცვალოთ, თუ რომელი ბრენჩები ინახავენ მართულ ქეშებს და მორგებულ ტომებს. გახსენით **Runners → Profiles**, დაარედაქტირეთ პროფილი, რომელსაც თქვენი ჯობები იყენებენ, და გააფართოვეთ **Save cache from**. ჯობები იყენებენ იმ პროფილს, რომელსაც ისინი ითხოვენ: `runs-on:`-ში GitHub Actions-ზე, როგორც რიგს Buildkite-ზე, ან `tags:`-ში GitLab CI-ზე. პარამეტრები ვრცელდება ყველა ტომზე, რომელსაც ამ პროფილის ჯობები იყენებენ, მათ შორის მოგვიანებით შექმნილ ტომებზე.

![რანერის პროფილის ფორმა გაფართოებული „Save cache from“ სექციით, სადაც ჩართულია Default branch და დამატებულია develop და release/* როგორც დამატებითი ბრენჩები](/images/guides/features/runners/save-cache-from.png)

ნაგულისხმევად, რეპოზიტორიის ყოველი წარმატებული ჯობა ინახავს თავის ცვლილებებს. მხოლოდ ზოგიერთი ბრენჩიდან შესანახად, ჩართეთ **Limit to specific branches**:

- **Default branch** საშუალებას აძლევს თითოეული რეპოზიტორიის ნაგულისხმევ ბრენჩზე შემდეგ ჯობებს შეინახონ მონაცემები. გამორთეთ ის, თუ გსურთ შეინახოთ მხოლოდ დამატებითი ბრენჩებიდან.
- **Additional branches**-ის ქვეშ, დაამატეთ 20-მდე ბრენჩის სახელი, რომლებიც ასევე შეინახავენ მონაცემებს. გამოიყენეთ `*` როგორც ვაილდქარდი: `release/*` ემთხვევა `release/1.0`-ს.

ჯობები, რომლებიც ჩამოთვლილია [ცვლილებების შენახვა](#saving-changes)-ში, ინახავენ თავიანთ ცვლილებებს, როდესაც მათი ბრენჩი ემთხვევა. GitHub Actions-ის push და ხელით გაშვების შემთხვევებში, შესაბამისი სახელის მქონე თეგი ასევე ემთხვევა.

სხვა ბრენჩებზე შემდეგ ჯობებს შეუძლიათ გამოიყენონ ქეში, მაგრამ მათი ცვლილებები იკარგება. ჯობები, რომლებიც არასდროს ინახავენ მონაცემებს, როგორიცაა fork pull requests, არ ინახავენ მონაცემებს შესაბამის ბრენჩზეც კი. ამ პარამეტრების შეზღუდვა ან პროფილის წაშლა იწვევს იმ მოლოდინში მყოფი ცვლილებების დაკარგვას, რომლებსაც ისინი აღარ უშვებენ; წაშლილი პროფილი ბრუნდება ყველა ბრენჩიდან შენახვის რეჟიმზე.

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

Gradle ქეში და მორგებული ტომები იღებენ იმავე `size` შეყვანას (`TUIST_GRADLE_CACHE_SIZE` და `TUIST_VOLUME_SIZE` GitLab CI-ში, `--size` `tuist-cache-volume`-ისთვის). უფრო დიდი ზომა ზრდის ტომს, ინარჩუნებს მის შიგთავსს, შემდეგი ჯობიდან. უფრო მცირე ზომა მოქმედებს ტომის შემდეგი წაშლის ან ვადის გასვლის შემდეგ. როდესაც ჯობები ითხოვენ ერთი ქეშის სხვადასხვა ზომას, მოქმედებს უდიდესი, ამიტომ გამოაცხადეთ თითოეული ზომა ერთ ადგილას.

ყველა მათგანი ვადას კარგავს **7 დღის განმავლობაში ჯობის მიმაგრების გარეშე**, და შემდეგი ჯობა იწყება ცარიელი ტომით ვადის გასვლის შემდეგ. Tuist ასუფთავებს Xcode და მოდულის ქეშებს მათი მოცულობის შესაბამისად, ხოლო Gradle ქეშის ნაბიჯი აიძულებს Gradle-ს წაშალოს ჩანაწერები, რომლებიც შვიდი დღის განმავლობაში არ გამოუყენებია ყოველი ბილდის შემდეგ.

მორგებული ტომები არ ასუფთავებენ ძველ დამოკიდებულებებს: გამოიყენეთ თქვენი ინსტრუმენტის გასუფთავების პარამეტრები, რათა შეინარჩუნოთ ისინი მცირე ზომის. ჩაწერა სავსე ტომში შეიძლება გამოიწვიოს ჯობის შეცდომა. როდესაც შენახული შიგთავსი აღწევს ტომის მოცულობის **80%**-ს და ჯობას ელევა ადგილი მათზე, შემდეგი ჯობა იწყება ცარიელი ტომით და მისი ცვლილებები იწყებენ ახალ შენახულ მდგომარეობას.

## ტომების ინსპექტირება და წაშლა {#inspecting-and-clearing-volumes}

გახსენით **Runners → Volumes**, რათა შეამოწმოთ გამოყენებული სივრცე, ქეშში მოხვედრის მაჩვენებელი და ჯობების ისტორია. Xcode, მოდულის და Gradle ქეშები ასევე ჩანს იქ.

ანგარიშის ადმინისტრატორებს შეუძლიათ აირჩიონ **Delete volume**, რათა წაშალონ ტომი და მისი შენახული შიგთავსი. მიმდინარე ჯობები ინარჩუნებენ თავიანთ პირად ასლებს, მაგრამ ვერ შეინახავენ მათ უკან, და შემდეგი ჯობა, რომელიც იყენებს იმავე გასაღებს, იწყება ცარიელი ტომით. წაშლილი ტომები აღარ ჩანს სიაში.

ტომის წასაშლელად ტერმინალიდან ან სამუშაო ნაკადიდან, მოიძიეთ მისი ID და გადაეცით ის `tuist runner volume delete`-ს:

```bash
tuist runner volume list --account my-org --name gradle-build-cache --json
tuist runner volume delete <volume-id> --account my-org --yes
```

იგივე ოპერაცია ხელმისაწვდომია [API](https://tuist.dev/api/docs#tag/runners)-ის მეშვეობით, როგორც `DELETE /api/accounts/{account_handle}/runners/volumes/{volume_id}`, და [MCP სერვერის](/guides/features/agentic-coding/mcp) მეშვეობით, როგორც `delete_runner_volume`. ყველა მათგანი მოითხოვს ანგარიშის ადმინისტრაციას ან ტოკენს `account:runners:write` სკოპით.
