---
{
  "title": "ქეშის ტომები",
  "titleTemplate": ":title · გამშვებები · ფუნქციები · სახელმძღვანელოები · Tuist",
  "description": "შეინარჩუნეთ Xcode-ის, მოდულისა და Gradle-ის ქეში, ასევე ნებისმიერი სხვა დირექტორია Tuist-ის Linux ან macOS გამშვების ჯობებს შორის GitHub Actions-თან, Buildkite-თან და GitLab CI-თან ერთად."
}
---
# ქეშის ტომები {#cache-volumes}

Tuist-ის რანერებს შეუძლიათ ჯობებს შორის ქეშების შენახვა, ასე რომ ახალი რანერი „თბილი“ მდგომარეობით იწყება. თითოეულ ჯობას ეძლევა ბოლო შენახული შინაარსის პირადი, ჩაწერადი ასლი.

- **მართული ქეშები** ინახავს Xcode-ის კომპილაციის ქეშს, Tuist-ის მოდულის ქეშს და Gradle-ის ქეშებს — თითოეული ერთი ნაბიჯით. Tuist-მა იცის, სად მდებარეობს თითოეული ქეში და ინახავს მას თავის საცავში.
- **მორგებული ტომები** ინახავს ნებისმიერ სხვა დირექტორიას, მაგალითად პაკეტის მენეჯერის ჩამოტვირთვის ქეშს, თქვენ მიერ არჩეული გასაღების სახელით.

დაამატეთ ნაბიჯები checkout-ის შემდეგ და იმ ბრძანებებამდე, რომლებიც ქეშებს იყენებენ. რანერებზე, რომლებიც არ არის Tuist-ის რანერები, ისინი არაფერს აკეთებენ და ქეშის პრობლემა არასდროს აცდენს ჯობას: ნაბიჯი აღრიცხავს გაფრთხილებას და ჯობა გრძელდება ცარიელი ქეშით.

## მართული ქეშები {#managed-caches}

ნაბიჯები მხოლოდ განსაზღვრავენ, სად მდებარეობს ქეშები. შეინარჩუნეთ თქვენი არსებული ქეშის კონფიგურაცია: `tuist setup cache` ან ბილდის პარამეტრები, რომლებიც რთავენ კომპილაციის ქეშირებას (იხილეთ <.localized_link href="/guides/features/cache/xcode-cache">Xcode-ის ქეშის სახელმძღვანელო</.localized_link>), მოდულის ქეშის ავტორიზაცია და <.localized_link href="/guides/features/cache/gradle-cache">Tuist Gradle პლაგინი</.localized_link> Gradle-ის დისტანციური ბილდის ქეშისთვის. GitLab CI-ში გაერთიანეთ ფრაგმენტები `!reference`-ით, რადგან `extends` ცვლის `before_script`-ს.

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

ინახავს Gradle-ის მომხმარებლის საწყისი დირექტორიის `caches` და `wrapper` საქაღალდეებს Linux-ისა და macOS-ის რანერებზე: დამოკიდებულებები, ტრანსფორმირებული jar-ფაილები, კომპილირებული ბილდის სკრიპტები და Gradle-ის დისტრიბუციები. დააყენეთ `GRADLE_USER_HOME` ნაბიჯამდე, თუ იყენებთ მას, და გამორთეთ ამ დირექტორიების სხვა ქეშირება, მაგალითად `cache: gradle` `actions/setup-java`-ზე.

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

აირჩიეთ სტაბილური `key` და `path`, შემდეგ მიამაგრეთ ტომი დამოკიდებულებების ინსტალაციამდე. გზა უნდა იყოს ცარიელი ან არ არსებობდეს. წაშალეთ ნებისმიერი არქივის ქეში ან არტეფაქტის აღდგენა, რომელიც იმავე დირექტორიაში წერს. რამდენიმე დირექტორიის ერთ ტომში შესანახად, იხილეთ [რამდენიმე დირექტორია ერთ ტომში](#several-directories-in-one-volume).

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

ტომს შეუძლია რამდენიმე დირექტორიის შენახვა. GitHub Actions-ში ჩამოთვალეთ თითო გზა ხაზზე; Buildkite-ში დააყენეთ `path` სიად; GitLab CI-ში გადაეცით `--path` თითო დირექტორიისთვის ერთხელ. ცარიელი ხაზები და მიმდებარე თეთრი სივრცეები უგულებელყოფილია.

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
- **დააჯგუფეთ მცირე, დაკავშირებული დირექტორიები.** დიდ ან სწრაფად ცვალებად დირექტორიას მიეცით საკუთარი ტომი.
- **არ არის ჩადგმა.** ერთი ტომის გზები არ უნდა შეიცავდნენ ერთმანეთს.
- **სიის ცვლილება იწყება ცივად.** თითოეული გზა ინახება ტომის შიგნით საკუთარ დირექტორიაში, რომელიც იდენტიფიცირდება იმით, თუ როგორ არის გზა დაწერილი. გადასვლა ერთ გზასა და რამდენიმეს შორის, ან გზის დამატება, წაშლა ან გადაწერა ცვლის ამ განლაგებას: ცვლილების შემდეგ პირველი ჯობა იწყება ცივად დაზარალებული გზებისთვის. იმ გზების შინაარსი, რომლებიც აღარ არის სიაში, რჩება ტომში მანამ, სანამ არ გაასუფთავებთ მას.

### როგორ მუშაობს გასაღებები {#how-keys-work}

გასაღები არქმევს ტომს, რომელიც დროთა განმავლობაში იცვლება; ეს არ არის ფიქსირებული სნეპშოტის სახელი, როგორც `actions/cache` გასაღები.

- **ერთი ტომი თითო გასაღებზე.** თითოეული გასაღები შეზღუდულია რეპოზიტორიით (Buildkite-ზე — პაიპლაინით; GitLab CI-ზე — პროექტით), პლატფორმით, CPU-ის არქიტექტურით და მომხმარებლით. თითოეული ჯობა, რომელიც მას მიამაგრებს, იწყება ბოლო შენახული შინაარსიდან და შესაბამისი ჯობები ინახავენ თავიანთ ცვლილებებს იმავე ტომში.
- **შეინარჩუნეთ გასაღებები სტაბილური.** არ ჩასვათ ვერსიები ან lockfile-ის ჰეშები გასაღებში. `actions/cache`-თან ერთად, გასაღები, როგორიცაა `deps-${{ hashFiles('Package.resolved') }}`, ქმნის ახალ ჩანაწერს თითო ცვლილებისთვის და `restore-keys` ბრუნდება ძველთან. აქ ახალი გასაღები ნიშნავს ახალ, ცარიელ ტომს: ყოველი ცვლილების შემდეგ პირველი ჯობა იწყება ცივად, ხოლო ძველი ტომები რჩებიან მანამ, სანამ არ ამოიწურებიან. შეინარჩუნეთ გასაღები და მიეცით თქვენს ინსტრუმენტს შინაარსის განახლების საშუალება; პაკეტის მენეჯერები ხელახლა იყენებენ ყველაფერს, რაც კიდევ ვალიდურია.
- **არ არის ნაწილობრივი დამთხვევები.** არ არსებობს აღდგენის გასაღებები. გასაღები, რომელიც ჯერ არ შენახულა, იწყება ცარიელი.
- **განახლებით დაწყება განზრახ.** შეცვალეთ გასაღები, ან გაასუფთავეთ ტომი დაშბორდზე, როცა გინდათ, რომ ჯობა ცარიელი დაიწყოს.
- **`tuist-` გასაღებები დაუტოვეთ Tuist-ს.** მართული ქეშები იყენებენ გასაღებებს, რომლებიც იწყება `tuist-`-ით, ამიტომ აირჩიეთ სხვა სახელი თქვენი საკუთარი ტომებისთვის.

Linux-ზე გზები მიმაგრებულია როგორც ჩვეულებრივი დირექტორიები, ამიტომ ინსტრუმენტებს შეუძლიათ გამოიყენონ ჩვეულებრივი ადგილები, როგორიცაა `deps`, `_build` და `node_modules`. შეინარჩუნეთ თქვენი ჩვეულებრივი `.gitignore` წესები. macOS-ზე გზები არის სიმბმულები: გამოიყენეთ ჩამოტვირთვის ქეშები, როგორიცაა `~/.npm`; `node_modules` და ინსტრუმენტები, რომლებიც ცვლიან თავიანთ ქეშის დირექტორიას, არ არის მხარდაჭერილი. უგულებელყავით სამუშაო სივრცის ბმულები ბოლო სლეშის გარეშე `.gitignore`-ში.

## ცვლილებების შენახვა {#saving-changes}

მართული ქეშები და მორგებული ტომები ინახავენ წარმატებული ჯობების ცვლილებებს თქვენი საკუთარი რეპოზიტორიიდან, ნებისმიერ ბრენჩზე:

| მოწოდება | ჯობები, რომლებიც ინახავენ ცვლილებებს |
| --- | --- |
| GitHub Actions | Push, განრიგი, ხელით გაშვება და pull request ჯობები თავად რეპოზიტორიიდან |
| Buildkite | Webhook და განრიგით გაშვებული ბილდები პაიპლაინის რეპოზიტორიისთვის, მათ შორის მისი pull request-ებისთვის |
| GitLab CI | Push, განრიგი და ვებ-პაიპლაინები პროექტისთვის, ასევე საკუთარი merge request-ების პაიპლაინები, როცა კავშირს აქვს <.localized_link href="/guides/features/runners/ci-providers/gitlab-ci#merge-request-pipelines">API წვდომის ტოკენი</.localized_link> |

სხვა ჯობებს შეუძლიათ ქეშის გამოყენება, მაგრამ მათი ცვლილებები იკარგება. ეს მოიცავს fork-დან მოსულ pull request-ებს, `pull_request_target` ჯობებს, Buildkite-ზე API-დან ან დაშბორდიდან გაშვებულ ბილდებს, GitLab-ის merge request-ებს fork-ებიდან ან API წვდომის ტოკენის გარეშე, და თეგებს. ჯობა, რომელიც არ ცვლის ტომს, ტოვებს შენახულ ვერსიას უცვლელად. შეგიძლიათ შეზღუდოთ, თუ რომელი ბრენჩები ინახავენ მონაცემებს რანერის პროფილში; იხილეთ [აირჩიეთ, რომელი ბრენჩები შეინახავენ](#choose-which-branches-save).

პარალელურად მომუშავე ჯობები დამოუკიდებლად მუშაობენ; სხვადასხვა ჯობის ცვლილებები არ ერთიანდება. არასდროს შეინახოთ ქეშში მონაცემები წვდომის შესახებ ან შეუცვლელი მონაცემები.

### აირჩიეთ, რომელი ბრენჩები შეინახავენ {#choose-which-branches-save}

შეგიძლიათ შეცვალოთ, თუ რომელი ბრენჩები ინახავენ მართულ ქეშებს და მორგებულ ტომებს. გახსენით **რანერები → პროფილები**, ჩაასწორეთ პროფილი, რომელსაც თქვენი ჯობები იყენებენ, და გაშალეთ **ქეშის შენახვის წყარო**. ჯობები იყენებენ პროფილს, რომელსაც ისინი ითხოვენ: `runs-on:`-ში GitHub Actions-ზე, როგორც რიგს Buildkite-ზე, ან `tags:`-ში GitLab CI-ზე. პარამეტრები ვრცელდება ყველა ტომზე, რომელსაც ამ პროფილის ჯობები იყენებენ, მათ შორის მოგვიანებით შექმნილ ტომებზე.

![რანერის პროფილის ფორმა გაშლილი „ქეშის შენახვის წყაროს“ სექციით, სადაც ჩართულია ნაგულისხმევი ბრენჩი და დამატებულია develop და release/* როგორც დამატებითი ბრენჩები](/images/guides/features/runners/save-cache-from.png)

ნაგულისხმევად რეპოზიტორიის ყოველი წარმატებული ჯობა ინახავს თავის ცვლილებებს. რომ შეინახოთ მხოლოდ ზოგიერთი ბრენჩიდან, ჩართეთ **შეზღუდვა კონკრეტულ ბრენჩებზე**:

- **ნაგულისხმევი ბრენჩი** საშუალებას აძლევს თითოეული რეპოზიტორიის ნაგულისხმევ ბრენჩზე მომუშავე ჯობებს შეინახონ მონაცემები. გამორთეთ ის, თუ გინდათ, რომ შენახვა მოხდეს მხოლოდ დამატებითი ბრენჩებიდან.
- **დამატებითი ბრენჩების** ქვეშ დაამატეთ 20-მდე ბრენჩის სახელი, რომლებიც ასევე შეინახავენ. გამოიყენეთ `*` როგორც ვაილდკარდი: `release/*` ემთხვევა `release/1.0`-ს.

ჯობები, რომლებიც ჩამოთვლილია [ცვლილებების შენახვაში](#saving-changes), ინახავენ თავიანთ ცვლილებებს, როცა მათი ბრენჩი ემთხვევა. GitHub Actions-ზე push და ხელით გაშვების შემთხვევებში, თეგი შესაბამისი სახელით ასევე ემთხვევა.

სხვა ბრენჩებზე მომუშავე ჯობებს კვლავ შეუძლიათ ქეშის გამოყენება, მაგრამ მათი ცვლილებები იკარგება. ჯობები, რომლებიც არასდროს ინახავენ, მაგალითად fork-დან მოსული pull request-ები, ასევე არ ინახავენ შესაბამის ბრენჩზეც. ამ პარამეტრების შევიწროება ან პროფილის წაშლა იწვევს იმ მოლოდინში მყოფი ცვლილებების დაკარგვას, რომლებსაც ისინი აღარ უშვებენ; წაშლილი პროფილი ბრუნდება ყველა ბრენჩიდან შენახვის რეჟიმზე.

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

Gradle-ის ქეში და მორგებული ტომები იღებენ იგივე `size` შეყვანას (`TUIST_GRADLE_CACHE_SIZE` და `TUIST_VOLUME_SIZE` GitLab CI-ში, `--size` `tuist-cache-volume`-სთვის). უფრო დიდი ზომა ზრდის ტომს, ინარჩუნებს მის შიგთავსს, მომდევნო ჯობიდან. უფრო მცირე ზომა მოქმედებს ტომის შემდეგი გასუფთავების ან ვადის ამოწურვის შემდეგ. როცა ჯობები ითხოვენ ერთი ქეშის სხვადასხვა ზომას, მოქმედებს უდიდესი, ამიტომ გამოაცხადეთ თითოეული ზომა ერთ ადგილას.

ყველა მათგანი იწურება **7 დღის განმავლობაში ჯობის მიმაგრების გარეშე**, და მომდევნო ჯობა იწყება ცარიელი ტომით ვადის ამოწურვის შემდეგ. Tuist ასუფთავებს Xcode-ის და მოდულის ქეშებს მათი მოცულობის შესაბამისად, ხოლო Gradle-ის ქეშის ნაბიჯი აიძულებს Gradle-ს წაშალოს ჩანაწერები, რომლებიც შვიდი დღის განმავლობაში არ გამოუყენებია ყოველი ბილდის შემდეგ.

მორგებული ტომები არ ასუფთავებენ ძველ დამოკიდებულებებს: გამოიყენეთ თქვენი ინსტრუმენტის გასუფთავების პარამეტრები, რათა შეინარჩუნოთ ისინი მცირე ზომის. სრულ ტომზე ჩაწერამ შეიძლება გამოიწვიოს ჯობის შეცდომა. როცა შენახული შიგთავსი აღწევს ტომის მოცულობის **80%**-ს და ჯობას ელევა ადგილი მათზე, მომდევნო ჯობა იწყება ცარიელი ტომით და მისი ცვლილებები იწყებენ ახალ შენახულ მდგომარეობას.

## ტომების შემოწმება და გასუფთავება {#inspecting-and-clearing-volumes}

გახსენით **რანერები → ტომები**, რათა შეამოწმოთ გამოყენებული სივრცე, ქეშში მოხვედრის მაჩვენებელი და ჯობების ისტორია. ანგარიშის ადმინისტრატორებს შეუძლიათ აირჩიონ **ტომის გასუფთავება**, რათა მომავალი ჯობები ცარიელი დაიწყონ. მიმდინარე ჯობები ინარჩუნებენ თავიანთ პირად ასლებს, მაგრამ ვერ შეინახავენ მათ უკან. Xcode-ის და მოდულის ქეშებიც ჩანს იქ, მაგრამ მათი გასუფთავება შეუძლებელია.
