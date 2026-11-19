---
{
  "title": "ქეშის ტომები",
  "titleTemplate": ":title · გამშვებები · ფუნქციები · სახელმძღვანელოები · Tuist",
  "description": "შეინახეთ Xcode-ის, მოდულისა და Gradle-ის ქეში, ასევე ნებისმიერი სხვა დირექტორია Tuist-ის Linux ან macOS გამშვების ჯობებს შორის GitHub Actions-ის, Buildkite-ისა და GitLab CI-ის გამოყენებით."
}
---
# ქეშის ტომები {#cache-volumes}

Tuist-ის გამშვებებს (runners) შეუძლიათ ქეში სამუშაოებს შორის შეინარჩუნონ, რათა ახალმა გამშვებმა „გახურებული“ მდგომარეობით დაიწყოს. თითოეული სამუშაო იღებს ბოლოს შენახული შინაარსის პირად, ჩაწერად ასლს.

- **მართული ქეშები** ინახავს Xcode-ის კომპილაციის ქეშს, Tuist-ის მოდულის ქეშს და Gradle-ის ქეშებს — თითოეულს ერთი ნაბიჯით. Tuist-მა იცის, სად მდებარეობს თითოეული ქეში და ინახავს მას თავის საცავში.
- **მორგებული ტომები** ინახავს ნებისმიერ სხვა დირექტორიას, მაგალითად, პაკეტების მენეჯერის ჩამოტვირთვის ქეშს, თქვენს მიერ არჩეული გასაღებით.

დაამატეთ ნაბიჯები checkout-ის შემდეგ და იმ ბრძანებებამდე, რომლებიც იყენებენ ქეშებს. გამშვებებზე, რომლებიც არ არიან Tuist-ის გამშვებები, ისინი არაფერს აკეთებენ და ქეშის პრობლემა არასდროს აფრთხილებს სამუშაოს: ნაბიჯი აღრიცხავს გაფრთხილებას და სამუშაო გრძელდება ცარიელი ქეშით.

## მართული ქეშები {#managed-caches}

ნაბიჯები მხოლოდ განსაზღვრავენ, სად მდებარეობენ ქეშები. შეინარჩუნეთ თქვენი არსებული ქეშის კონფიგურაცია: `tuist setup cache` ან ააწყვეთ ბილდის პარამეტრები, რომლებიც რთავენ კომპილაციის ქეშირებას (იხილეთ <.localized_link href="/guides/features/cache/xcode-cache">Xcode-ის ქეშის სახელმძღვანელო</.localized_link>), მოდულის ქეშის ავტორიზაცია და <.localized_link href="/guides/features/cache/gradle-cache">Tuist Gradle პლაგინი</.localized_link> Gradle-ის დაშორებული ბილდის ქეშისთვის. GitLab CI-ში გააერთიანეთ ფრაგმენტები `!reference`-ით, რადგან `extends` ცვლის `before_script`-ს.

### Xcode-ის ქეში {#xcode-cache}

ინახავს Xcode-ის კომპილაციის ქეშის საცავს macOS-ის გამშვებებზე.

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

ინახავს Tuist-ის ლოკალურ ქეშს macOS-ის გამშვებებზე: <.localized_link href="/guides/features/cache/module-cache">მოდულის ქეშის</.localized_link> ბინარები, კომპილირებული მანიფესტები, პლაგინები და შერჩევითი ტესტირების შედეგები.

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

ინახავს `caches` და `wrapper` დირექტორიებს Gradle-ის მომხმარებლის საწყის საქაღალდეში Linux-ისა და macOS-ის გამშვებებზე: დამოკიდებულებები, ტრანსფორმირებული jars, კომპილირებული ბილდის სკრიპტები და Gradle-ის დისტრიბუციები. დააყენეთ `GRADLE_USER_HOME` ნაბიჯამდე, თუ იყენებთ მას და გამორთეთ ამ დირექტორიების სხვა ქეშირება, მაგალითად, `cache: gradle` `actions/setup-java`-ზე.

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

აირჩიეთ სტაბილური `key` და `path`, შემდეგ მიამაგრეთ ტომი დამოკიდებულებების ინსტალაციამდე. გზა უნდა იყოს ცარიელი ან არ არსებობდეს. წაშალეთ ნებისმიერი არქივის ქეში ან არტეფაქტის აღდგენა, რომელიც იგივე დირექტორიაში წერს. რამდენიმე დირექტორიის ერთ ტომში შესანახად, იხილეთ [რამდენიმე დირექტორია ერთ ტომში](#several-directories-in-one-volume).

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

ტომს შეუძლია რამდენიმე დირექტორიის შენახვა. GitHub Actions-ში ჩამოთვალეთ თითო გზა ხაზზე; Buildkite-ში დააყენეთ `path` სიად; GitLab CI-ში გადაეცით `--path` თითო დირექტორიისთვის ერთხელ. ცარიელი ხაზები და გარშემო თეთრი სივრცე უგულებელყოფილია.

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
- **დააჯგუფეთ პატარა, დაკავშირებული დირექტორიები.** დიდ ან სწრაფად ცვლილ დირექტორიას მიანიჭეთ საკუთარი ტომი.
- **არა ჩადგმა.** ერთი ტომის გზები არ უნდა შეიცავდნენ ერთმანეთს.
- **სიის შეცვლა ცივი სტარტით იწყება.** თითოეული გზა ინახება ტომის შიგნით საკუთარ დირექტორიაში, რომელიც იდენტიფიცირდება გზის ჩაწერის მიხედვით. ერთ გზასა და რამდენიმეს შორის გადართვა, ან გზის დამატება, წაშლა ან გადაწერა ცვლის ამ განლაგებას: ცვლილების შემდგომი პირველი სამუშაო დაზარალებული გზებისთვის ცივად იწყება. გზების შინაარსი, რომლებიც აღარ არის ჩამოთვლილი, რჩება ტომში მანამ, სანამ არ წაშლით მას.

### როგორ მუშაობს გასაღებები {#how-keys-work}

გასაღები არქმევს ტომს, რომელიც დროთა განმავლობაში იცვლება; ეს არ არის ფიქსირებული სნაპშოტის სახელი, როგორც `actions/cache` გასაღები.

- **ერთი ტომი თითო გასაღებზე.** თითოეული გასაღები მიბმულია რეპოზიტორიზე (Buildkite-ზე — პაიპლაინზე; GitLab CI-ზე — პროექტზე), პლატფორმაზე, CPU არქიტექტურასა და მომხმარებელზე. თითოეული სამუშაო, რომელიც მას ამაგრებს, იწყება ბოლოს შენახული შინაარსიდან და შესაბამისი სამუშაოები ინახავენ ცვლილებებს იმავე ტომში.
- **შეინარჩუნეთ გასაღებების სტაბილურობა.** არ ჩაწეროთ ვერსიები ან lockfile-ის ჰეშები გასაღებში. `actions/cache`-თან ერთად, გასაღები, როგორიცაა `deps-${{ hashFiles('Package.resolved') }}`, ქმნის ახალ ჩანაწერს თითო ცვლილებისთვის, ხოლო `restore-keys` ბრუნდება ძველთან. აქ ახალი გასაღები ნიშნავს ახალ, ცარიელ ტომს: ყოველი ცვლილების შემდგომი პირველი სამუშაო იწყება ცივად, ხოლო ძველი ტომები რჩებიან მანამ, სანამ არ ამოიწურებიან. შეინარჩუნეთ გასაღები და მიეცით თქვენს ინსტრუმენტს შინაარსის განახლების საშუალება; პაკეტების მენეჯერები ხელახლა იყენებენ ყველაფერს, რაც კიდევ ვალიდურია.
- **არა ნაწილობრივი დამთხვევები.** არ არსებობს აღდგენის გასაღებები. გასაღები, რომელიც ჯერ არ შენახულა, იწყება ცარიელი.
- **გასაღებები, რომლებიც იწყება `tuist-`-ით, რეზერვირებულია** Tuist-ის საკუთარი ქეშებისთვის და უარყოფილია ტომის მიმაგრებამდე.
- **განზრახვით თავიდან დაწყება.** შეცვალეთ გასაღები ან წაშალეთ ტომი, როდესაც გსურთ, რომ სამუშაო ცარიელი დაიწყოს.
- **`tuist-` გასაღებები დაუტოვეთ Tuist-ს.** მართული ქეშები იყენებენ გასაღებებს, რომლებიც იწყება `tuist-`-ით, ამიტომ აირჩიეთ სხვა სახელი თქვენი საკუთარი ტომებისთვის.

Linux-ზე გზები მიმაგრებულია როგორც ჩვეულებრივი დირექტორიები, ამიტომ ინსტრუმენტებს შეუძლიათ გამოიყენონ ჩვეულებრივი ადგილები, როგორიცაა `deps`, `_build` და `node_modules`. შეინარჩუნეთ თქვენი ჩვეულებრივი `.gitignore` წესები. macOS-ზე გზები არის სიმბმულები: გამოიყენეთ ჩამოტვირთვის ქეშები, როგორიცაა `~/.npm`; `node_modules` და ინსტრუმენტები, რომლებიც ცვლიან თავიანთ ქეშის დირექტორიას, მხარდაუჭერელია. უგულებელყავით სამუშაო სივრცის ბმულები ბოლო სლешის გარეშე `.gitignore`-ში.

## ცვლილებების შენახვა {#saving-changes}

მართული ქეშები და მორგებული ტომები ინახავენ წარმატებული სამუშაოების ცვლილებებს თქვენი საკუთარი რეპოზიტორიდან, ნებისმიერ ბრენჩზე:

| მოწოდება | სამუშაოები, რომლებიც ინახავენ ცვლილებებს |
| --- | --- |
| GitHub Actions | Push-ის, დაგეგმილი, ხელით გაშვებული და pull request სამუშაოები თავად რეპოზიტორიდან |
| Buildkite | Webhook-ისა და დაგეგმილი აწყობები პაიპლაინის რეპოზიტორისთვის, მათ შორის მისი pull requests-ებისთვის |
| GitLab CI | პროექტის push-ის, დაგეგმილი და ვებ-პაიპლაინები, ასევე საკუთარი merge request-ების პაიპლაინები, როდესაც კავშირს აქვს <.localized_link href="/guides/features/runners/ci-providers/gitlab-ci#merge-request-pipelines">API წვდომის ტოკენი</.localized_link> |

სხვა სამუშაოებს შეუძლიათ გამოიყენონ ქეში, მაგრამ მათი ცვლილებები იკარგება. ეს მოიცავს fork-ის pull request-ებს, `pull_request_target` სამუშაოებს, Buildkite აწყობებს, რომლებიც დაწყებულია API-დან ან დაფიდან, GitLab merge request-ებს fork-ებიდან ან API წვდომის ტოკენის გარეშე, და თეგებს. სამუშაო, რომელიც არ ცვლის ტომს, ტოვებს შენახულ ვერსიას უცვლელად. შეგიძლიათ შეზღუდოთ, თუ რომელი ბრენჩები ინახავენ მონაცემებს რანერის პროფილზე; იხილეთ [აირჩიეთ, რომელი ბრენჩები შეინახოს](#choose-which-branches-save).

პარალელური სამუშაოები დამოუკიდებლად მუშაობენ; სხვადასხვა სამუშაოდან მიღებული ცვლილებები არ ერწყმის ერთმანეთს. არასდროს შეინახოთ ქეშში სერთიფიკატები ან ჩაუნაცვლებელი მონაცემები.

### აირჩიეთ, რომელი ბრენჩები შეინახოს {#choose-which-branches-save}

შეგიძლიათ შეცვალოთ, თუ რომელი ბრენჩები ინახავენ მართულ ქეშებსა და მორგებულ ტომებს. გახსენით **Runners → Profiles**, დაარედაქტირეთ პროფილი, რომელსაც თქვენი სამუშაოები იყენებენ, და გააფართოვეთ **Save cache from**. სამუშაოები იყენებენ იმ პროფილს, რომელსაც ისინი ითხოვენ: `runs-on:`-ში GitHub Actions-ზე, როგორც რიგს Buildkite-ზე, ან `tags:`-ში GitLab CI-ზე. პარამეტრები ვრცელდება ყველა ტომზე, რომელსაც ამ პროფილის სამუშაოები იყენებენ, მათ შორის მოგვიანებით შექმნილ ტომებზე.

![რანერის პროფილის ფორმა გაფართოებული Save cache from სექციით, სადაც Default branch ჩართულია და develop და release/* დამატებულია როგორც დამატებითი ბრენჩები](/images/guides/features/runners/save-cache-from.png)

ნაგულისხმევად რეპოზიტორიდან ყოველი წარმატებული სამუშაო ინახავს თავის ცვლილებებს. მხოლოდ ზოგიერთი ბრენჩიდან შესანახად, ჩართეთ **Limit to specific branches**:

- **Default branch** საშუალებას აძლევს თითოეული რეპოზიტორის ნაგულისხმევ ბრენჩზე შესრულებულ სამუშაოებს შეინახონ მონაცემები. გამორთეთ ის, თუ გსურთ შეინახოთ მხოლოდ დამატებითი ბრენჩებიდან.
- **Additional branches**-ის ქვეშ, დაამატეთ 20-მდე ბრენჩის სახელი, რომლებიც ასევე შეინახავენ მონაცემებს. გამოიყენეთ `*` როგორც ვილდქარდი: `release/*` ემთხვევა `release/1.0`-ს.

[Saving changes](#saving-changes)-ში ჩამოთვლილი სამუშაოები ინახავენ თავიანთ ცვლილებებს, როდესაც მათი ბრენჩი ემთხვევა. GitHub Actions-ის push-ისა და ხელით გაშვების შემთხვევებში, შესაბამისი სახელის მქონე თეგი ასევე ითვლება დამთხვევად.

სხვა ბრენჩებზე შესრულებულ სამუშაოებს შეუძლიათ კვლავ გამოიყენონ ქეში, მაგრამ მათი ცვლილებები იკარგება. სამუშაოები, რომლებიც არასდროს ინახავენ მონაცემებს, როგორიცაა fork-ის pull request-ები, ასევე არ ინახავენ შესაბამის ბრენჩზეც. ამ პარამეტრების შეზღუდვა ან პროფილის წაშლა იწვევს იმ მოლოდინში მყოფი ცვლილებების დაკარგვას, რომლებსაც ისინი აღარ უშვებენ; წაშლილი პროფილი ბრუნდება ყველა ბრენჩიდან შენახვის რეჟიმზე.

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

Gradle ქეში და მორგებული ტომები იღებენ იმავე `size` შეყვანას (`TUIST_GRADLE_CACHE_SIZE` და `TUIST_VOLUME_SIZE` GitLab CI-ში, `--size` `tuist-cache-volume`-სთვის). უფრო დიდი ზომა ზრდის ტომს, ინარჩუნებს მის შიგთავსს, შემდეგი სამუშაოდან დაწყებით. უფრო მცირე ზომა ვრცელდება ტომის შემდეგი წაშლის ან ვადის ამოწურვის შემდეგ. როდესაც სამუშაოები ითხოვენ ერთი ქეშის სხვადასხვა ზომებს, ვრცელდება უდიდესი, ამიტომ განაცხადეთ თითოეული ზომა ერთ ადგილას.

ყველა მათგანი იწურება **7 დღის განმავლობაში სამუშაოს მიმაგრების გარეშე**, და შემდეგი სამუშაო იწყება ცარიელი ტომით ვადის ამოწურვის შემდეგ. Tuist ასუფთავებს Xcode-ისა და მოდულის ქეშებს მათი მოცულობის შესაბამისად, ხოლო Gradle ქეშის ნაბიჯი აიძულებს Gradle-ს წაშალოს ჩანაწერები, რომლებიც შვიდი დღის განმავლობაში არ გამოუყენებია ყოველი აწყობის შემდეგ.

მორგებული ტომები არ ასუფთავებენ ძველ დამოკიდებულებებს: გამოიყენეთ თქვენი ინსტრუმენტის გასუფთავების პარამეტრები, რათა შეინარჩუნოთ ისინი მცირე ზომის. სრულ ტომზე ჩაწერამ შეიძლება გამოიწვიოს სამუშაოს შეცდომა. როდესაც შენახული შიგთავსი აღწევს ტომის მოცულობის **80%**-ს და სამუშაოს ელევა ადგილი მათზე, შემდეგი სამუშაო იწყება ცარიელი ტომით და მისი ცვლილებები იწყებენ ახალ შენახულ მდგომარეობას.

## ტომების ინსპექტირება და წაშლა {#inspecting-and-clearing-volumes}

გახსენით **Runners → Volumes**, რათა შეამოწმოთ გამოყენებული სივრცე, ქეშში მოხვედრის მაჩვენებელი და სამუშაოების ისტორია. Xcode-ის, მოდულისა და Gradle-ის ქეშებიც ჩანს იქ.

ანგარიშის ადმინისტრატორებს შეუძლიათ აირჩიონ **Delete volume**, რათა წაშალონ ტომი და მისი შენახული შიგთავსი. მიმდინარე სამუშაოები ინარჩუნებენ თავიანთ პირად ასლებს, მაგრამ ვერ შეინახავენ მათ უკან, და შემდეგი სამუშაო, რომელიც იყენებს იმავე გასაღებს, იწყება ცარიელი ტომით. წაშლილი ტომები აღარ ჩანს სიაში.

ტერმინალიდან ან სამუშაო ნაკადიდან ტომის წასაშლელად, მოძებნეთ მისი ID და გადაეცით ის `tuist runner volume delete`-ს:

```bash
tuist runner volume list --account my-org --name gradle-build-cache --json
tuist runner volume delete <volume-id> --account my-org --yes
```

იგივე ოპერაცია ხელმისაწვდომია [API](https://tuist.dev/api/docs#tag/runners)-ის მეშვეობით, როგორც `DELETE /api/accounts/{account_handle}/runners/volumes/{volume_id}`, და [MCP სერვერის](/guides/features/agentic-coding/mcp) მეშვეობით, როგორც `delete_runner_volume`. ყველა მათგანი მოითხოვს ანგარიშის ადმინისტრაციას ან ტოკენს `account:runners:write` სკოპით.
