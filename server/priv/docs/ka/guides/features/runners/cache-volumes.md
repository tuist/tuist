---
{
  "title": "Cache volumes",
  "titleTemplate": ":title · Runners · Features · Guides · Tuist",
  "description": "Keep the Xcode, module and Gradle caches and any other directory between Tuist Linux or macOS runner jobs with GitHub Actions, Buildkite, and GitLab CI."
}
---
# ქეშის ტომები {#cache-volumes}

Tuist-ის რანერებს შეუძლიათ ქეშების შენარჩუნება ჯობებს შორის, ისე რომ ახალი რანერი „თბილად“ იწყებდეს მუშაობას. თითოეულ ჯობას ენიჭება ბოლოს შენახული შინაარსის პირადი, ჩაწერადი ასლი.

- **მართვადი ქეშები** ინახავენ Xcode-ის კომპილაციის ქეშს, Tuist-ის მოდულის ქეშს და Gradle-ის ქეშებს — თითოეულს ერთი ნაბიჯით. Tuist-მა იცის, სად მდებარეობს თითოეული ქეში და ინახავს მას თავის საცავში.
- **მორგებული ტომები** ინახავენ ნებისმიერ სხვა დირექტორიას, მაგალითად პაკეტების მენეჯერის ჩამოტვირთვის ქეშს, თქვენ მიერ არჩეული გასაღების ქვეშ.

დაამატეთ ნაბიჯები checkout-ის შემდეგ და იმ ბრძანებებამდე, რომლებიც იყენებენ ქეშებს. რანერებზე, რომლებიც არ არიან Tuist-ის რანერები, ისინი არაფერს აკეთებენ და ქეშის პრობლემა არასდროს აფერხებს ჯობას: ნაბიჯი აღრიცხავს გაფრთხილებას და ჯობა გრძელდება ცარიელი ქეშით.

## მართვადი ქეშები {#managed-caches}

ნაბიჯები მხოლოდ განსაზღვრავენ, სად მდებარეობენ ქეშები. შეინარჩუნეთ თქვენი არსებული ქეშის კონფიგურაცია: `tuist setup cache` ან აგების პარამეტრები, რომლებიც რთავენ კომპილაციის ქეშირებას (იხილეთ <.localized_link href="/guides/features/cache/xcode-cache">Xcode-ის ქეშის სახელმძღვანელო</.localized_link>), მოდულის ქეშის ავტორიზაცია და <.localized_link href="/guides/features/cache/gradle-cache">Tuist Gradle პლაგინი</.localized_link> Gradle-ის დაშორებული აგების ქეშისთვის. GitLab CI-ში გააერთიანეთ ფრაგმენტები `!reference`-თან, რადგან `extends` ცვლის `before_script`-ს.

### Xcode-ის ქეში {#xcode-cache}

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

### მოდულის ქეში {#module-cache}

ინახავს Tuist-ის ლოკალურ ქეშს macOS რანერებზე: <.localized_link href="/guides/features/cache/module-cache">მოდულის ქეშის</.localized_link> ბინარები, კომპილირებული მანიფესტები, პლაგინები და შერჩევითი ტესტირების შედეგები.

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

ინახავს `caches` და `wrapper` დირექტორიებს Gradle-ის მომხმარებლის საწყის დირექტორიაში Linux და macOS რანერებზე: დამოკიდებულებები, ტრანსფორმირებული jars, კომპილირებული აგების სკრიპტები და Gradle-ის დისტრიბუციები. დააყენეთ `GRADLE_USER_HOME` ნაბიჯამდე, თუ იყენებთ მას, და გამორთეთ ამ დირექტორიების სხვა ქეშირება, როგორიცაა `cache: gradle` `actions/setup-java`-ზე.

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

ტომს შეუძლია შეიცავდეს რამდენიმე დირექტორიას. GitHub Actions-ში ჩამოთვალეთ ერთი გზა ხაზზე; Buildkite-ში დააყენეთ `path` სიად; GitLab CI-ში გადაეცით `--path` ერთხელ თითოეული დირექტორიისთვის. ცარიელი ხაზები და გარემომცველი თეთრი სივრცე იგნორირდება.

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
- **დააჯგუფეთ მცირე, დაკავშირებული დირექტორიები.** დიდ ან სწრაფად ცვალებად დირექტორიას მიანიჭეთ საკუთარი ტომი.
- **არ არის ჩადგმა.** ერთი ტომის გზები არ უნდა შეიცავდნენ ერთმანეთს.
- **სიის ცვლილება იწყება „ცივად“.** თითოეული გზა ინახება საკუთარ დირექტორიაში ტომის შიგნით, იდენტიფიცირდება იმით, თუ როგორ არის გზა დაწერილი. ერთ გზასა და რამდენიმეს შორის გადართვა, ან გზის დამატება, წაშლა ან გადაწერა ცვლის ამ განლაგებას: ცვლილების შემდგომი პირველი ჯობა იწყება „ცივად“ დაზარალებული გზებისთვის. იმ გზების შინაარსი, რომლებიც აღარ არის ჩამოთვლილი, რჩება ტომში მანამ, სანამ არ გაასუფთავებთ მას.

### როგორ მუშაობენ გასაღებები {#how-keys-work}

გასაღები არქმევს ტომს, რომელიც დროთა განმავლობაში იცვლება; ეს არ არის ფიქსირებული სნეპშოტის სახელი, როგორიცაა `actions/cache` გასაღები.

- **ერთი ტომი თითოეული გასაღებისთვის.** თითოეული გასაღები შეზღუდულია რეპოზიტორიით (Buildkite-ზე — პაიპლაინით; GitLab CI-ზე — პროექტით), პლატფორმით, CPU არქიტექტურით და მომხმარებლით. ყოველი ჯობა, რომელიც მას ამაგრებს, იწყება ბოლოს შენახული შინაარსიდან, და შესაბამისი ჯობები ინახავენ თავიანთ ცვლილებებს იმავე ტომში.
- **შეინარჩუნეთ გასაღებების სტაბილურობა.** არ ჩადოთ ვერსიები ან lockfile-ის ჰეშები გასაღებში. `actions/cache`-თან ერთად, გასაღები, როგორიცაა `deps-${{ hashFiles('Package.resolved') }}`, ქმნის ახალ ჩანაწერს თითოეული ცვლილებისთვის, და `restore-keys` ბრუნდება ძველთან. აქ ახალი გასაღები ნიშნავს ახალ, ცარიელ ტომს: ყოველი ცვლილების შემდგომი პირველი ჯობა იწყება „ცივად“, და ძველი ტომები რჩებიან მანამ, სანამ არ ამოიწურებათ ვადა. შეინარჩუნეთ გასაღები და მიეცით თქვენს ინსტრუმენტს შინაარსის განახლების საშუალება; პაკეტების მენეჯერები ხელახლა იყენებენ ყველაფერს, რაც კვლავ ვალიდურია.
- **არ არის ნაწილობრივი დამთხვევები.** არ არსებობს აღდგენის გასაღებები. გასაღები, რომელიც ჯერ არ არის შენახული, იწყება ცარიელი.
- **განზრახ დაიწყეთ თავიდან.** შეცვალეთ გასაღები, ან გაასუფთავეთ ტომი დაშბორდზე, როდესაც გსურთ, რომ ჯობა დაიწყოს ცარიელი.
- **დატოვეთ `tuist-` გასაღებები Tuist-ისთვის.** მართვადი ქეშები იყენებენ გასაღებებს, რომლებიც იწყება `tuist-`-ით, ამიტომ აირჩიეთ სხვა სახელი თქვენი საკუთარი ტომებისთვის.

Linux-ზე გზები მაუნტდება როგორც ჩვეულებრივი დირექტორიები, ამიტომ ინსტრუმენტებს შეუძლიათ გამოიყენონ ჩვეულებრივი ადგილები, როგორიცაა `deps`, `_build` და `node_modules`. შეინარჩუნეთ თქვენი ჩვეულებრივი `.gitignore` წესები. macOS-ზე გზები არის სიმლინკები: გამოიყენეთ ჩამოტვირთვის ქეშები, როგორიცაა `~/.npm`; `node_modules` და ინსტრუმენტები, რომლებიც ცვლიან თავიანთ ქეშის დირექტორიას, არ არის მხარდაჭერილი. იგნორირეთ სამუშაო სივრცის ბმულები დახრილი ხაზის გარეშე `.gitignore`-ში.

## ცვლილებების შენახვა {#saving-changes}

მართვადი ქეშები და მორგებული ტომები ინახავენ თქვენი საკუთარი რეპოზიტორიის წარმატებული ჯობების ცვლილებებს, ნებისმიერ ბრენჩზე:

| პროვაიდერი | ჯობები, რომლებიც ინახავენ ცვლილებებს |
| --- | --- |
| GitHub Actions | Push, განრიგი, ხელით გაშვება და pull request ჯობები თავად რეპოზიტორიიდან |
| Buildkite | Webhook-ით და განრიგით გაშვებული ბილდები პაიპლაინის რეპოზიტორიისთვის, მათ შორის მისი pull request-ებისთვის |
| GitLab CI | Push, განრიგი და ვებ-პაიპლაინები პროექტისთვის, ასევე საკუთარი merge request-ების პაიპლაინები, როდესაც კავშირს აქვს <.localized_link href="/guides/features/runners/ci-providers/gitlab-ci#merge-request-pipelines">API წვდომის ტოკენი</.localized_link> |

სხვა ჯობებს შეუძლიათ გამოიყენონ ქეში, მაგრამ მათი ცვლილებები იკარგება. ეს მოიცავს fork-ის pull request-ებს, `pull_request_target` ჯობებს, Buildkite-ის ბილდებს, რომლებიც გაშვებულია API-დან ან დაშბორდიდან, GitLab-ის merge request-ებს fork-ებიდან ან API წვდომის ტოკენის გარეშე, და თეგებს. ჯობა, რომელიც არ ცვლის ტომს, ტოვებს შენახულ ვერსიას ადგილზე. შეგიძლიათ შეზღუდოთ, თუ რომელი ბრენჩები ინახავენ მონაწილე პროფილზე; იხილეთ [აირჩიეთ, რომელი ბრენჩები შეინახონ](#choose-which-branches-save).

პარალელური ჯობები მუშაობენ დამოუკიდებლად; სხვადასხვა ჯობის ცვლილებები არ ერთიანდება. არასდროს შეინახოთ სერთიფიკატები ან შეუცვლელი მონაცემები.

### აირჩიეთ, რომელი ბრენჩები შეინახონ {#choose-which-branches-save}

შეგიძლიათ შეცვალოთ, თუ რომელი ბრენჩები ინახავენ მართვად ქეშებს და მორგებულ ტომებს. გახსენით **მონაწილეები → პროფილები**, დაარედაქტირეთ პროფილი, რომელსაც თქვენი ჯობები იყენებენ, და გაშალეთ **ქეშის შენახვის წყარო**. ჯობები იყენებენ პროფილს, რომელსაც ისინი ითხოვენ: `runs-on:`-ში GitHub Actions-ზე, როგორც რიგს Buildkite-ზე, ან `tags:`-ში GitLab CI-ზე. პარამეტრები ვრცელდება ყველა ტომზე, რომელსაც იყენებენ ჯობები ამ პროფილზე, მათ შორის მოგვიანებით შექმნილ ტომებზე.

![მონაწილის პროფილის ფორმა გაშლილი „ქეშის შენახვის წყაროს“ სექციით, ჩართული ნაგულისხმები ბრენჩით და დამატებული develop და release/* როგორც დამატებითი ბრენჩები](/images/guides/features/runners/save-cache-from.png)

ნაგულისხმევად, რეპოზიტორიის ყოველი წარმატებული ჯობა ინახავს თავის ცვლილებებს. მხოლოდ ზოგიერთი ბრენჩიდან შესანახად, ჩართეთ **შეზღუდვა კონკრეტულ ბრენჩებამდე**:

- **ნაგულისხმები ბრენჩი** საშუალებას აძლევს ჯობებს თითოეული რეპოზიტორიის ნაგულისხმევ ბრენჩზე შეინახონ. გამორთეთ ის, რათა შეინახოთ მხოლოდ დამატებითი ბრენჩებიდან.
- **დამატებითი ბრენჩების** ქვეშ, დაამატეთ 20-მდე ბრენჩის სახელი, რომლებიც ასევე შეინახავენ. გამოიყენეთ `*` როგორც ვაილდქარდი: `release/*` ემთხვევა `release/1.0`-ს.

ჯობები, ჩამოთვლილი [ცვლილებების შენახვაში](#saving-changes), ინახავენ თავიანთ ცვლილებებს, როდესაც მათი ბრენჩი ემთხვევა. GitHub Actions-ის push და ხელით გაშვებულ გაშვებებზე, თეგი შესაბამისი სახელით ასევე ემთხვევა.

სხვა ბრენჩებზე მყოფ ჯობებს შეუძლიათ კვლავ გამოიყენონ ქეში, მაგრამ მათი ცვლილებები იკარგება. ჯობები, რომლებიც არასდროს ინახავენ, როგორიცაა fork-ის pull request-ები, ასევე არ ინახავენ შესაბამის ბრენჩზეც. ამ პარამეტრების შევიწროვება ან პროფილის წაშლა იწვევს გადაუდებელი ცვლილებების დაკარგვას, რომლებსაც ისინი აღარ უშვებენ; წაშლილი პროფილი ბრუნდება ყველა ბრენჩიდან შენახვაზე.

## მოცულობა და შენახვის ვადა {#capacity-and-retention}

Xcode-ის ქეში იწყება **30 GB**-ით. მოდულის ქეში, Gradle-ის ქეში და თითოეული მორგებული ტომი იწყება **20 GB**-ით. დააყენეთ ზომა, რათა მიანიჭოთ ქეშს ან ტომს სხვა მოცულობა, GB-ის მთელი რიცხვი `1gb`-დან `100gb`-მდე:

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

Gradle-ის ქეში და მორგებული ტომები იღებენ იმავე `size` შეყვანას (`TUIST_GRADLE_CACHE_SIZE` და `TUIST_VOLUME_SIZE` GitLab CI-ში, `--size` `tuist-cache-volume`-ისთვის). უფრო დიდი ზომა ზრდის ტომს, ინარჩუნებს მის შიგთავსს, შემდეგი ჯობიდან. უფრო მცირე ზომა ვრცელდება ტომის შემდეგი გასუფთავების ან ვადის გასვლის შემდეგ. როდესაც ჯობები ითხოვენ ერთი ქეშის სხვადასხვა ზომებს, ვრცელდება უდიდესი, ამიტომ გამოაცხადეთ თითოეული ზომა ერთ ადგილას.

ყველა მათგანი იწურება **7 დღის განმავლობაში ჯობის მაუნტის გარეშე**, და შემდეგი ჯობა იწყება ცარიელი ტომით ვადის გასვლის შემდეგ. Tuist ასუფთავებს Xcode-ის და მოდულის ქეშებს მათი მოცულობის შესაბამისად, ხოლო Gradle-ის ქეშის ნაბიჯი აიძულებს Gradle-ს წაშალოს ჩანაწერები, რომლებიც შვიდი დღის განმავლობაში არ გამოუყენებიათ ყოველი ბილდის შემდეგ.

მორგებული ტომები არ ასუფთავებენ ძველ დამოკიდებულებებს: გამოიყენეთ თქვენი ინსტრუმენტის გასუფთავების პარამეტრები, რათა შეინარჩუნოთ ისინი მცირე ზომის. ჩაწერა სავსე ტომში შეიძლება გამოიწვიოს ჯობის შეცდომა. როდესაც შენახული შიგთავსი აღწევს ტომის მოცულობის **80%**-ს და ჯობას ელევა ადგილი მათზე, შემდეგი ჯობა იწყება ცარიელი ტომით და მისი ცვლილებები იწყებენ ახალ შენახულ მდგომარეობას.

## ტომების შემოწმება და გასუფთავება {#inspecting-and-clearing-volumes}

გახსენით **მონაწილეები → ტომები**, რათა შეამოწმოთ გამოყენებული სივრცე, ქეშის მოხვედრის მაჩვენებელი და ჯობების ისტორია. ანგარიშის ადმინისტრატორებს შეუძლიათ აირჩიონ **ტომის გასუფთავება**, რათა მომავალი ჯობები დაიწყონ ცარიელი მდგომარეობით. მიმდინარე ჯობები ინარჩუნებენ თავიანთ პირად კოპიებს, მაგრამ ვერ შეინახავენ მათ უკან. Xcode-ის და მოდულის ქეშები ასევე ჩანს იქ, მაგრამ მათი გასუფთავება შეუძლებელია.
