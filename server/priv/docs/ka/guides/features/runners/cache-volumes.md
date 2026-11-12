---
{
  "title": "ქეშის ტომები",
  "titleTemplate": ":title · გამშვებები · ფუნქციები · სახელმძღვანელოები · Tuist",
  "description": "შეინახეთ Xcode-ის, მოდულებისა და Gradle-ის ქეში, ასევე ნებისმიერი სხვა დირექტორია Tuist-ის Linux ან macOS გამშვებ სამუშაოებს შორის GitHub Actions-ის, Buildkite-ისა და GitLab CI-ის გამოყენებით."
}
---
# ქეშის ტომები {#cache-volumes}

Tuist-ის რანერებს შეუძლიათ შეინარჩუნონ ქეში ჯობებს შორის, ასე რომ ახალი რანერი „თბილად“ იწყება. თითოეული ჯობა იღებს ბოლოს შენახული შინაარსის პირად, ჩაწერად ასლს.

- **მართული ქეშები** ინახავენ Xcode-ის კომპილაციის ქეშს, Tuist-ის მოდულის ქეშს და Gradle-ის ქეშებს თითო ნაბიჯით. Tuist-მა იცის, სად მდებარეობს თითოეული ქეში და ინახავს მას თავის საცავში.
- **მორგებული ტომები** ინახავენ ნებისმიერ სხვა დირექტორიას, მაგალითად პაკეტების მენეჯერის ჩამოტვირთვის ქეშს, თქვენ მიერ არჩეული გასაღებით.

დაამატეთ ეს ნაბიჯები checkout-ის შემდეგ და იმ ბრძანებებამდე, რომლებიც იყენებენ ქეშებს. რანერებზე, რომლებიც არ არიან Tuist-ის რანერები, ისინი არაფერს აკეთებენ და ქეშის პრობლემა არასდროს ავარდება ჯობას: ნაბიჯი წერს გაფრთხილებას და ჯობა გრძელდება ცარიელი ქეშით.

## მართული ქეშები {#managed-caches}

ნაბიჯები მხოლოდ განსაზღვრავენ, სად მდებარეობენ ქეშები. შეინარჩუნეთ თქვენი არსებული ქეშის კონფიგურაცია: `tuist setup cache` ან ააწყვეთ კომპილაციის ქეშირება (იხილეთ <.localized_link href="/guides/features/cache/xcode-cache">Xcode-ის ქეშის სახელმძღვანელო</.localized_link>), მოდულის ქეშის ავტორიზაცია და <.localized_link href="/guides/features/cache/gradle-cache">Tuist Gradle პლაგინი</.localized_link> Gradle-ის დისტანციური ბილდის ქეშისთვის. GitLab CI-ში გააერთიანეთ ფრაგმენტები `!reference`-ით, რადგან `extends` ცვლის `before_script`-ს.

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

ინახავს Gradle-ის მომხმარებლის საწყისი საქაღალდის `caches` და `wrapper` დირექტორიებს Linux-ისა და macOS-ის რანერებზე: დამოკიდებულებები, ტრანსფორმირებული jar-ფაილები, კომპილირებული ბილდის სკრიპტები და Gradle-ის დისტრიბუციები. დააყენეთ `GRADLE_USER_HOME` ნაბიჯამდე, თუ იყენებთ მას და გამორთეთ ამ დირექტორიების სხვა ქეშირება, მაგალითად `cache: gradle` `actions/setup-java`-ზე.

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

ტომს შეუძლია შეიცავდეს რამდენიმე დირექტორიას. GitHub Actions-ში ჩამოთვალეთ ერთი გზა ხაზზე; Buildkite-ში დააყენეთ `path` სიად; GitLab CI-ში გადაეცით `--path` ერთხელ თითო დირექტორიისთვის. ცარიელი ხაზები და გარემომყოფი თეთრი სივრცე უგულებელყოფილია.

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

- **გაზიარებული სივრცე.** ყველა გზა იზიარებს ტომის სივრცეს და ერთად აღდგება და ინახება.
- **დააჯგუფეთ პატარა, დაკავშირებული დირექტორიები.** დიდ ან სწრაფად ცვლად დირექტორიას მიანიჭეთ საკუთარი ტომი.
- **არ არის ჩადგმა.** ერთი ტომის გზები არ უნდა შეიცავდნენ ერთმანეთს.
- **სიის ცვლილება იწყება „ცივად“.** თითოეული გზა ინახება ტომის შიგნით საკუთარ დირექტორიაში, რომელიც იდენტიფიცირდება გზის ჩაწერის მიხედვით. გადასვლა ერთ გზასა და რამდენიმეს შორის, ან გზის დამატება, წაშლა ან გადაწერა ცვლის ამ განლაგებას: ცვლილების შემდეგ პირველი ჯობა იწყება „ცივად“ შესაბამისი გზებისთვის. იმ გზების შინაარსი, რომლებიც აღარ არის სიაში, რჩება ტომში მანამ, სანამ არ წაშლით მას.

### როგორ მუშაობენ გასაღებები {#how-keys-work}

გასაღები არქმევს ტომს, რომელიც იცვლება დროთა განმავლობაში; ეს არ არის ფიქსირებული სნეპშოტის სახელი, როგორც `actions/cache` გასაღები.

- **ერთი ტომი თითო გასაღებზე.** თითოეული გასაღები შეზღუდულია რეპოზიტორიით (Buildkite-ზე — პაიპლაინით; GitLab CI-ზე — პროექტით), პლატფორმით, CPU-ის არქიტექტურით და მომხმარებლით. თითოეული ჯობა, რომელიც მას ამიგრებს, იწყება ბოლოს შენახული შინაარსიდან და შესაბამისი ჯობები ინახავენ ცვლილებებს იმავე ტომში.
- **შეინარჩუნეთ გასაღებების სტაბილურობა.** არ ჩასვათ ვერსიები ან lockfile-ის ჰეშები გასაღებში. `actions/cache`-თან ერთად, გასაღები, როგორიცაა `deps-${{ hashFiles('Package.resolved') }}`, ქმნის ახალ ჩანაწერს თითო ცვლილებისთვის, ხოლო `restore-keys` ბრუნდება ძველთან. აქ ახალი გასაღები არის ახალი, ცარიელი ტომი: ყოველი ცვლილების შემდეგ პირველი ჯობა იწყება „ცივად“, ხოლო ძველი ტომები რჩებიან მანამ, სანამ არ ამოიწურება. შეინარჩუნეთ გასაღები და მიეცით თქვენს ინსტრუმენტს შინაარსის განახლების საშუალება; პაკეტების მენეჯერები ხელახლა იყენებენ იმას, რაც კვლავ ვალიდურია.
- **არ არის ნაწილობრივი დამთხვევები.** არ არსებობს აღდგენის გასაღებები. გასაღები, რომელიც ჯერ არ არის შენახული, იწყება ცარიელად.
- **გასაღებები, რომლებიც იწყება `tuist-`-ით, რეზერვირებულია** Tuist-ის საკუთარი ქეშებისთვის და უარყოფილია ტომის მიმაგრებამდე.
- **დაიწყეთ თავიდან განზრახვით.** შეცვალეთ გასაღები ან წაშალეთ ტომი, როცა გინდათ, რომ ჯობა დაიწყოს ცარიელად.
- **დატოვეთ `tuist-` გასაღებები Tuist-ისთვის.** მართული ქეშები იყენებენ გასაღებებს, რომლებიც იწყება `tuist-`-ით, ასე რომ აირჩიეთ სხვა სახელი თქვენი ტომებისთვის.

Linux-ზე გზები მაუნტდება როგორც ჩვეულებრივი დირექტორიები, ასე რომ ინსტრუმენტებს შეუძლიათ გამოიყენონ ჩვეულებრივი მდებარეობები, როგორიცაა `deps`, `_build` და `node_modules`. შეინარჩუნეთ თქვენი ჩვეულებრივი `.gitignore` წესები. macOS-ზე გზები არის symlink-ები: გამოიყენეთ ჩამოტვირთვის ქეშები, როგორიცაა `~/.npm`; `node_modules` და ინსტრუმენტები, რომლებიც ცვლიან თავიანთ ქეშის დირექტორიას, არ არის მხარდაჭერილი. უგულებელყავით სამუშაო სივრცის ბმულები ბოლო slash-ის გარეშე `.gitignore`-ში.

## ცვლილებების შენახვა {#saving-changes}

მართული ქეშები და მორგებული ტომები ინახავენ წარმატებული ჯობების ცვლილებებს თქვენი საკუთარი რეპოზიტორიიდან, ნებისმიერ ბრენჩზე:

| მოწოდება | ჯობები, რომლებიც ინახავენ ცვლილებებს |
| --- | --- |
| GitHub Actions | პუში, დაგეგმილი, ხელით გაშვებული და pull request ჯობები თავად რეპოზიტორიიდან |
| Buildkite | Webhook-ით და დაგეგმილი ბილდები პაიპლაინის რეპოზიტორიისთვის, მათ შორის მისი pull requests |
| GitLab CI | პროექტის პუში, დაგეგმილი და ვებ-პაიპლაინები, ასევე მისი საკუთარი merge request-ების პაიპლაინები, როცა კავშირს აქვს <.localized_link href="/guides/features/runners/ci-providers/gitlab-ci#merge-request-pipelines">API წვდომის ტოკენი</.localized_link> |

სხვა ჯობებს შეუძლიათ გამოიყენონ ქეში, მაგრამ მათი ცვლილებები იკარგება. ეს მოიცავს fork-ის pull requests-ებს, `pull_request_target` ჯობებს, Buildkite ბილდებს, რომლებიც გაშვებულია API-დან ან დაშბორდიდან, GitLab merge requests-ებს fork-ებიდან ან API წვდომის ტოკენის გარეშე, და თეგებს. ჯობა, რომელიც არ ცვლის ტომს, ტოვებს შენახულ ვერსიას ადგილზე. შეგიძლიათ შეზღუდოთ, რომელი ბრენჩები ინახავენ რანერის პროფილზე; იხილეთ [აირჩიეთ, რომელი ბრენჩები ინახავენ](#choose-which-branches-save).

პარალელური ჯობები მუშაობენ დამოუკიდებლად; სხვადასხვა ჯობის ცვლილებები არ ერწყმის ერთმანეთს. არასდროს შეინახოთ ქეშში სერთიფიკატები ან შეუცვლელი მონაცემები.

### აირჩიეთ, რომელი ბრენჩები ინახავენ {#choose-which-branches-save}

შეგიძლიათ შეცვალოთ, რომელი ბრენჩები ინახავენ მართულ ქეშებს და მორგებულ ტომებს. გახსენით **Runners → Profiles**, ჩაასწორეთ პროფილი, რომელსაც იყენებენ თქვენი ჯობები, და გაშალეთ **Save cache from**. ჯობები იყენებენ პროფილს, რომელსაც ისინი ითხოვენ: `runs-on:`-ში GitHub Actions-ზე, როგორც რიგს Buildkite-ზე, ან `tags:`-ში GitLab CI-ზე. პარამეტრები ვრცელდება ყველა ტომზე, რომელსაც იყენებენ ჯობები ამ პროფილზე, მათ შორის მოგვიანებით შექმნილ ტომებზე.

![რანერის პროფილის ფორმა გაშლილი Save cache from სექციით, სადაც Default branch ჩართულია და develop და release/* დამატებულია როგორც დამატებითი ბრენჩები](/images/guides/features/runners/save-cache-from.png)

ნაგულისხმევად რეპოზიტორიის ყოველი წარმატებული ჯობა ინახავს თავის ცვლილებებს. მხოლოდ ზოგიერთი ბრენჩიდან შესანახად ჩართეთ **Limit to specific branches**:

- **Default branch** საშუალებას აძლევს თითოეული რეპოზიტორიის ნაგულისხმევ ბრენჩზე ჯობებს შეინახონ. გამორთეთ ის, რომ შეინახოთ მხოლოდ დამატებითი ბრენჩებიდან.
- **Additional branches**-ის ქვეშ, დაამატეთ 20-მდე ბრენჩის სახელი, რომლებიც ასევე ინახავენ. გამოიყენეთ `*` როგორც ვაილდქარდი: `release/*` ემთხვევა `release/1.0`-ს.

ჯობები, რომლებიც ჩამოთვლილია [ცვლილებების შენახვა](#saving-changes)-ში, ინახავენ თავიანთ ცვლილებებს, როცა მათი ბრენჩი ემთხვევა. GitHub Actions პუშისა და ხელით გაშვების შემთხვევებში, შესაბამისი სახელის მქონე თეგი ასევე ემთხვევა.

სხვა ბრენჩებზე ჯობებს მაინც შეუძლიათ გამოიყენონ ქეში, მაგრამ მათი ცვლილებები იკარგება. ჯობები, რომლებიც არასდროს ინახავენ, როგორიცაა fork-ის pull requests, არ ინახავენ შესაბამის ბრენჩზეც კი. ამ პარამეტრების შეზღუდვა ან პროფილის წაშლა იწვევს გადაუდებელი ცვლილებების დაკარგვას, რომლებსაც ისინი აღარ უშვებენ; წაშლილი პროფილი ბრუნდება ყველა ბრენჩიდან შენახვაზე.

## მოცულობა და შენახვა {#capacity-and-retention}

Xcode ქეში იწყება **30 GB**-ით. მოდულის ქეში, Gradle ქეში და თითოეული მორგებული ტომი იწყება **20 GB**-ით. დააყენეთ ზომა, რომ მიანიჭოთ ქეშს ან ტომს სხვა მოცულობა, GB-ის მთელი რიცხვი `1gb`-დან `100gb`-მდე:

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

Gradle ქეში და მორგებული ტომები იღებენ იმავე `size` შეყვანას (`TUIST_GRADLE_CACHE_SIZE` და `TUIST_VOLUME_SIZE` GitLab CI-ში, `--size` `tuist-cache-volume`-ისთვის). უფრო დიდი ზომა ზრდის ტომს, ინარჩუნებს მის შიგთავსს, მომდევნო ჯობიდან. უფრო მცირე ზომა ვრცელდება ტომის შემდეგი წაშლის ან ვადის გასვლის შემდეგ. როცა ჯობები ითხოვენ ერთი ქეშის სხვადასხვა ზომას, ვრცელდება უდიდესი, ამიტომ გამოაცხადეთ თითოეული ზომა ერთ ადგილას.

ყველა მათგანი იწურება **7 დღის განმავლობაში ჯობის მიმაგრების გარეშე**, და მომდევნო ჯობა იწყება ცარიელი ტომით ვადის გასვლის შემდეგ. Tuist ასუფთავებს Xcode და მოდულის ქეშებს მათი მოცულობის შესაბამისად, და Gradle ქეშის ნაბიჯი აიძულებს Gradle-ს წაშალოს ჩანაწერები, რომლებიც შვიდი დღის განმავლობაში არ გამოუყენებია ყოველი ბილდის შემდეგ.

მორგებული ტომები არ ასუფთავებენ ძველ დამოკიდებულებებს: გამოიყენეთ თქვენი ინსტრუმენტის გასუფთავების პარამეტრები, რომ შეინარჩუნოთ ისინი მცირე ზომის. ჩაწერა სავსე ტომში შეიძლება გააფუჭოს ჯობა. როცა შენახული შიგთავსი აღწევს ტომის მოცულობის **80%**-ს და ჯობას ელევა ადგილი მათზე, მომდევნო ჯობა იწყება ცარიელი ტომით და მისი ცვლილებები იწყებენ ახალ შენახულ მდგომარეობას.

## ტომების ინსპექტირება და წაშლა {#inspecting-and-clearing-volumes}

გახსენით **Runners → Volumes**, რომ შეამოწმოთ გამოყენებული სივრცე, ქეშში მოხვედრის მაჩვენებელი და ჯობების ისტორია. Xcode, მოდულის და Gradle ქეშები ასევე ჩანს იქ.

ანგარიშის ადმინისტრატორებს შეუძლიათ აირჩიონ **Delete volume**, რომ წაშალონ ტომი და მისი შენახული შიგთავსი. მიმდინარე ჯობები ინარჩუნებენ თავიანთ პირად ასლებს, მაგრამ ვერ ინახავენ მათ უკან, და მომდევნო ჯობა, რომელიც იყენებს იმავე გასაღებს, იწყება ცარიელი ტომით. წაშლილი ტომები აღარ ჩანს სიაში.

ტომის წასაშლელად ტერმინალიდან ან სამუშაო ნაკადიდან, მოძებნეთ მისი ID და გადაეცით ის `tuist runner volume delete`-ს:

```bash
tuist runner volume list --account my-org --name gradle-build-cache --json
tuist runner volume delete <volume-id> --account my-org --yes
```

იგივე ოპერაცია ხელმისაწვდომია [API](https://tuist.dev/api/docs#tag/runners)-ის მეშვეობით, როგორც `DELETE /api/accounts/{account_handle}/runners/volumes/{volume_id}`, და [MCP სერვერის](/guides/features/agentic-coding/mcp) მეშვეობით, როგორც `delete_runner_volume`. ყველა მათგანი მოითხოვს ანგარიშის ადმინისტრაციას ან ტოკენს `account:runners:write` სკოპით.
