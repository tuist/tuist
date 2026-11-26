---
{
  "title": "ქეშის ტომები",
  "titleTemplate": ":title · გამშვებები · ფუნქციები · სახელმძღვანელოები · Tuist",
  "description": "შეინარჩუნეთ Xcode-ის, მოდულის და Gradle-ის ქეშები, ისევე როგორც ნებისმიერი სხვა დირექტორია, Tuist-ის Linux ან macOS გამშვებების ამოცანებს შორის GitHub Actions-ში, Buildkite-სა და GitLab CI-ში."
}
---
# კეშის ტომები {#cache-volumes}

Tuist-ის რანერებს შეუძლიათ შეინარჩუნონ კეში ჯობებს შორის, ისე რომ ახალი რანერი თბილად იწყებოდეს. თითოეულ ჯობას ეძლევა ბოლოს შენახული შინაარსის პირადი, ჩაწერადი ასლი.

- **მართული კეშები** ინახავენ Xcode-ის კომპილაციის კეშს, Tuist-ის მოდულის კეშს და Gradle-ის კეშებს თითო-თითო ნაბიჯით. Tuist-მა იცის, სად მდებარეობს თითოეული კეში და ინახავს მას თავის საცავში.
- **მორგებული ტომები** ინახავენ ნებისმიერ სხვა დირექტორიას, მაგალითად, პაკეტების მენეჯერის ჩამოტვირთვის კეშს, თქვენ მიერ არჩეული გასაღების ქვეშ.

დაამატეთ ეს ნაბიჯები checkout-ის შემდეგ და იმ ბრძანებებამდე, რომლებიც იყენებენ კეშებს. რანერებზე, რომლებიც არ არის Tuist-ის რანერები, ისინი არაფერს აკეთებენ და კეშის პრობლემა არასდროს ავარებს ჯობას: ნაბიჯი წერს გაფრთხილებას და ჯობა გრძელდება ცარიელი კეშით.

> [!NOTE]
> macOS 27-ზე მყოფი რანერები ჯერ არ ამაგრებენ კეშის ტომებს ან კეშირებულ checkout-ებს. მათი კეშის ნაბიჯები წერენ გაფრთხილებას და ჯობა გრძელდება ცარიელი კეშით, ხოლო `actions/checkout` კლონავს რეპოზიტორიას როგორც ჩვეულებრივ.

## მართული კეშები {#managed-caches}

ნაბიჯები მხოლოდ განსაზღვრავენ, სად მდებარეობს კეშები. შეინარჩუნეთ თქვენი არსებული კეშის კონფიგურაცია: `tuist setup cache` ან აგების პარამეტრები, რომლებიც რთავენ კომპილაციის კეშირებას (იხილეთ <.localized_link href="/guides/features/cache/xcode-cache">Xcode-ის კეშის სახელმძღვანელო</.localized_link>), მოდულის კეშის ავტორიზაცია და <.localized_link href="/guides/features/cache/gradle-cache">Tuist Gradle პლაგინი</.localized_link> Gradle-ის დისტანციური აგების კეშისთვის. GitLab CI-ში გააერთიანეთ სნიპეტები `!reference`-ით, რადგან `extends` ცვლის `before_script`-ს.

### Xcode-ის კეში {#xcode-cache}

ინახავს Xcode-ის კომპილაციის კეშის საცავს macOS რანერებზე.

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

### მოდულის კეში {#module-cache}

ინახავს Tuist-ის ლოკალურ კეშს macOS რანერებზე: <.localized_link href="/guides/features/cache/module-cache">მოდულის კეშის</.localized_link> ბინარები, კომპილირებული მანიფესტები, პლაგინები და შერჩევითი ტესტირების შედეგები.

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

### Gradle-ის კეში {#gradle-cache}

ინახავს `caches` და `wrapper` დირექტორიებს Gradle-ის მომხმარებლის საწყის დირექტორიაში Linux და macOS რანერებზე: დამოკიდებულებები, ტრანსფორმირებული jar ფაილები, კომპილირებული აგების სკრიპტები და Gradle-ის დისტრიბუციები. დააყენეთ `GRADLE_USER_HOME` ნაბიჯამდე, თუ იყენებთ მას და გამორთეთ ამ დირექტორიების სხვა კეშირება, მაგალითად, `cache: gradle` `actions/setup-java`-ზე.

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

აირჩიეთ სტაბილური `key` და `path`, შემდეგ დაამაგრეთ ტომი დამოკიდებულებების ინსტალაციამდე. გზა უნდა იყოს ცარიელი ან არ არსებობდეს. წაშალეთ ნებისმიერი არქივის კეში ან არტეფაქტის აღდგენა, რომელიც წერს იმავე დირექტორიაში. რამდენიმე დირექტორიის ერთ ტომში შესანახად, იხილეთ [რამდენიმე დირექტორია ერთ ტომში](#several-directories-in-one-volume).

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

ტომს შეუძლია შეიცავდეს რამდენიმე დირექტორიას. GitHub Actions-ში ჩამოთვალეთ ერთი გზა თითო ხაზზე; Buildkite-ში დააყენეთ `path` სიად; GitLab CI-ში გადაეცით `--path` ერთხელ თითო დირექტორიისთვის. ცარიელი ხაზები და გარშემო თეთრი სივრცე იგნორირდება.

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
- **დააჯგუფეთ პატარა, დაკავშირებული დირექტორიები.** დიდ ან სწრაფად ცვალებად დირექტორიას მიეცით საკუთარი ტომი.
- **არ არის ჩადგმა.** ერთი ტომის გზები არ უნდა შეიცავდნენ ერთმანეთს.
- **სიის ცვლილება ცივად იწყება.** თითოეული გზა ინახება თავის საკუთარ დირექტორიაში ტომის შიგნით, იდენტიფიცირდება გზის ჩაწერის მიხედვით. ერთ გზასა და რამდენიმეს შორის გადართვა, ან გზის დამატება, წაშლა ან გადაწერა ცვლის ამ განლაგებას: ცვლილების შემდეგ პირველი ჯობა ცივად იწყება დაზარალებული გზებისთვის. იმ გზების შინაარსი, რომლებიც აღარ არის სიაში, რჩება ტომში მანამ, სანამ არ წაშლით მას.

### როგორ მუშაობს გასაღებები {#how-keys-work}

გასაღები ასახელებს ტომს, რომელიც დროთა განმავლობაში იცვლება; ეს არ არის ფიქსირებული სნაპშოტის სახელი, როგორც `actions/cache` გასაღები.

- **ერთი ტომი თითო გასაღებზე.** თითოეული გასაღები შეზღუდულია რეპოზიტორიით (Buildkite-ზე - პაიპლაინით; GitLab CI-ზე - პროექტით), პლატფორმით, CPU არქიტექტურით და მომხმარებლით. ყოველი ჯობა, რომელიც ამაგრებს მას, იწყება ბოლოს შენახული შინაარსიდან და შესაბამისი ჯობები ინახავენ თავიანთ ცვლილებებს იმავე ტომში.
- **შეინარჩუნეთ გასაღებების სტაბილურობა.** არ ჩასვათ ვერსიები ან lockfile-ის ჰეშები გასაღებში. `actions/cache`-თან ერთად, გასაღები, როგორიცაა `deps-${{ hashFiles('Package.resolved') }}`, ქმნის ახალ ჩანაწერს თითო ცვლილებისთვის და `restore-keys` ბრუნდება ძველთან. აქ ახალი გასაღები ნიშნავს ახალ, ცარიელ ტომს: ყოველი ცვლილების შემდეგ პირველი ჯობა ცივად იწყება და ძველი ტომები რჩებიან მანამ, სანამ არ ამოიწურებიან. შეინარჩუნეთ გასაღები და მიეცით თქვენს ინსტრუმენტს შინაარსის განახლების საშუალება; პაკეტების მენეჯერები ხელახლა იყენებენ იმას, რაც კვლავ ვალიდურია.
- **არ არის ნაწილობრივი დამთხვევები.** არ არსებობს აღდგენის გასაღებები. გასაღები, რომელიც ჯერ არ შენახულა, იწყება ცარიელი.
- **`tuist-`-ით დაწყებული გასაღებები რეზერვირებულია** Tuist-ის საკუთარი კეშებისთვის და უარყოფილია ტომის მიმაგრებამდე.
- **მიზანმიმართულად დაიწყეთ თავიდან.** შეცვალეთ გასაღები ან წაშალეთ ტომი, როდესაც გსურთ, რომ ჯობა ცარიელიდან დაიწყოს.
- **დატოვეთ `tuist-` გასაღებები Tuist-ისთვის.** მართული კეშები იყენებენ გასაღებებს, რომლებიც იწყება `tuist-`-ით, ამიტომ აირჩიეთ სხვა სახელი თქვენი საკუთარი ტომებისთვის.

Linux-ზე გზები მაუნტდება როგორც ჩვეულებრივი დირექტორიები, ამიტომ ინსტრუმენტებს შეუძლიათ გამოიყენონ ჩვეულებრივი ადგილები, როგორიცაა `deps`, `_build` და `node_modules`. შეინარჩუნეთ თქვენი ჩვეულებრივი `.gitignore` წესები. macOS-ზე გზები არის symlink-ები: გამოიყენეთ ჩამოტვირთვის კეშები, როგორიცაა `~/.npm`; `node_modules` და ინსტრუმენტები, რომლებიც ცვლიან თავიანთ კეშის დირექტორიას, მხარდაუჭერელია. იგნორირეთ workspace ბმულები ბოლო სლეშის გარეშე `.gitignore`-ში.

## ცვლილებების შენახვა {#saving-changes}

მართული კეშები და მორგებული ტომები ინახავენ წარმატებული ჯობების ცვლილებებს თქვენი საკუთარი რეპოზიტორიიდან, ნებისმიერ ბრენჩზე:

| მოწოდება | ჯობები, რომლებიც ინახავენ ცვლილებებს |
| --- | --- |
| GitHub Actions | Push, დაგეგმილი, ხელით გაშვებული და pull request ჯობები თავად რეპოზიტორიიდან |
| Buildkite | Webhook და დაგეგმილი ბილდები პაიპლაინის რეპოზიტორიისთვის, მათ შორის მისი pull requests |
| GitLab CI | პროექტის push, დაგეგმილი და web პაიპლაინები, ასევე საკუთარი merge request-ების პაიპლაინები, როდესაც კავშირს აქვს <.localized_link href="/guides/features/runners/ci-providers/gitlab-ci#merge-request-pipelines">API წვდომის ტოკენი</.localized_link> |

სხვა ჯობებს შეუძლიათ გამოიყენონ კეში, მაგრამ მათი ცვლილებები იკარგება. ეს მოიცავს fork pull request-ებს, `pull_request_target` ჯობებს, Buildkite ბილდებს, რომლებიც დაწყებულია API-დან ან დაფიდან, GitLab merge request-ებს ფორკებიდან ან API წვდომის ტოკენის გარეშე, და თეგებს. ჯობა, რომელიც არ ცვლის ტომს, ტოვებს შენახულ ვერსიას ადგილზე. შეგიძლიათ შეზღუდოთ, თუ რომელი ბრენჩები ინახავენ რანერის პროფილზე; იხილეთ [აირჩიეთ, რომელი ბრენჩები შეინახონ](#choose-which-branches-save).

პარალელური ჯობები მუშაობენ დამოუკიდებლად; სხვადასხვა ჯობების ცვლილებები არ ერწყმის ერთმანეთს. არასდროს შეინახოთ სერთიფიკატები ან ჩაუნაცვლებელი მონაცემები.

### აირჩიეთ, რომელი ბრენჩები შეინახონ {#choose-which-branches-save}

შეგიძლიათ შეცვალოთ, თუ რომელი ბრენჩები ინახავენ მართულ კეშებს და მორგებულ ტომებს. გახსენით **Runners → Profiles**, ჩაასწორეთ პროფილი, რომელსაც თქვენი ჯობები იყენებენ, და გაშალეთ **Save cache from**. ჯობები იყენებენ პროფილს, რომელსაც ისინი ითხოვენ: `runs-on:`-ში GitHub Actions-ზე, როგორც რიგს Buildkite-ზე, ან `tags:`-ში GitLab CI-ზე. პარამეტრები ვრცელდება ყველა ტომზე, რომელსაც ამ პროფილის ჯობები იყენებენ, მათ შორის მოგვიანებით შექმნილ ტომებზე.

![რანერის პროფილის ფორმა გაშლილი „Save cache from“ სექციით, სადაც ჩართულია Default branch და დამატებულია develop და release/* როგორც დამატებითი ბრენჩები](/images/guides/features/runners/save-cache-from.png)

ნაგულისხმევად რეპოზიტორიის ყოველი წარმატებული ჯობა ინახავს თავის ცვლილებებს. მხოლოდ ზოგიერთი ბრენჩიდან შესანახად, ჩართეთ **Limit to specific branches**:

- **Default branch** საშუალებას აძლევს თითოეული რეპოზიტორიის ნაგულისხმევ ბრენჩზე ჯობებს შეინახონ. გამორთეთ ის, რომ შეინახოთ მხოლოდ დამატებითი ბრენჩებიდან.
- **Additional branches**-ის ქვეშ, დაამატეთ 20-მდე ბრენჩის სახელი, რომლებიც ასევე შეინახავენ. გამოიყენეთ `*` როგორც ვაილდქარდი: `release/*` ემთხვევა `release/1.0`-ს.

ჯობები, ჩამოთვლილი [ცვლილებების შენახვა](#saving-changes)-ში, ინახავენ თავიანთ ცვლილებებს, როდესაც მათი ბრენჩი ემთხვევა. GitHub Actions-ის push და ხელით გაშვებულ გაშვებებზე, შესაბამისი სახელის მქონე თეგი ასევე ემთხვევა.

სხვა ბრენჩებზე ჯობებს მაინც შეუძლიათ გამოიყენონ კეში, მაგრამ მათი ცვლილებები იკარგება. ჯობები, რომლებიც არასდროს ინახავენ, როგორიცაა fork pull request-ები, არ ინახავენ შესაბამის ბრენჩზეც. ამ პარამეტრების შეზღუდვა ან პროფილის წაშლა იწვევს გადაუდებელი ცვლილებების დაკარგვას, რომლებსაც ისინი აღარ უშვებენ; წაშლილი პროფილი ბრუნდება ყველა ბრენჩიდან შენახვაზე.

## მოცულობა და შენახვა {#capacity-and-retention}

Xcode კეში იწყება **30 GB**-ით. მოდულის კეში, Gradle კეში და თითოეული მორგებული ტომი იწყება **20 GB**-ით. დააყენეთ ზომა, რათა მიანიჭოთ კეშს ან ტომს სხვა მოცულობა, GB-ის მთელი რიცხვი `1gb`-დან `100gb`-მდე:

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

Gradle კეში და მორგებული ტომები იღებენ იგივე `size` შეყვანას (`TUIST_GRADLE_CACHE_SIZE` და `TUIST_VOLUME_SIZE` GitLab CI-ში, `--size` `tuist-cache-volume`-ისთვის). უფრო დიდი ზომა ზრდის ტომს, ინარჩუნებს მის შიგთავსს, შემდეგი ჯობიდან. უფრო მცირე ზომა ვრცელდება ტომის შემდეგი წაშლის ან ვადის გასვლის შემდეგ. როდესაც ჯობები ითხოვენ ერთი კეშის სხვადასხვა ზომებს, ვრცელდება უდიდესი, ამიტომ გამოაცხადეთ თითოეული ზომა ერთ ადგილას.

ყველა მათგანი იწურება **7 დღის განმავლობაში ჯობის მიმაგრების გარეშე**, და შემდეგი ჯობა იწყება ცარიელი ტომით ვადის გასვლის შემდეგ. Tuist ასუფთავებს Xcode და მოდულის კეშებს მათი მოცულობის შესაბამისად, ხოლო Gradle კეშის ნაბიჯი აიძულებს Gradle-ს წაშალოს ჩანაწერები, რომლებიც შვიდი დღის განმავლობაში არ გამოუყენებია ყოველი ბილდის შემდეგ.

მორგებული ტომები არ ასუფთავებენ ძველ დამოკიდებულებებს: გამოიყენეთ თქვენი ინსტრუმენტის გასუფთავების პარამეტრები, რათა შეინარჩუნოთ ისინი მცირე ზომის. სრულ ტომზე ჩაწერამ შეიძლება გამოიწვიოს ჯობის შეცდომა. როდესაც შენახული შიგთავსი აღწევს ტომის მოცულობის **80%**-ს და ჯობას ელევა ადგილი მათზე, შემდეგი ჯობა იწყება ცარიელი ტომით და მისი ცვლილებები იწყებენ ახალ შენახულ მდგომარეობას.

## ტომების ინსპექტირება და წაშლა {#inspecting-and-clearing-volumes}

გახსენით **Runners → Volumes**, რათა შეამოწმოთ გამოყენებული სივრცე, ქეშში მოხვედრის მაჩვენებელი და ჯობების ისტორია. Xcode, მოდულის და Gradle კეშები ასევე ჩანს იქ.

ანგარიშის ადმინისტრატორებს შეუძლიათ აირჩიონ **Delete volume**, რათა წაშალონ ტომი და მისი შენახული შიგთავსი. მიმდინარე ჯობები ინარჩუნებენ თავიანთ პირად ასლებს, მაგრამ ვერ ინახავენ მათ უკან, და შემდეგი ჯობა, რომელიც იყენებს იგივე გასაღებს, იწყება ცარიელი ტომით. წაშლილი ტომები აღარ ჩანს სიაში.

ტომის წასაშლელად ტერმინალიდან ან სამუშაო ნაკადიდან, მოიძიეთ მისი ID და გადაეცით ის `tuist runner volume delete`-ს:

```bash
tuist runner volume list --account my-org --name gradle-build-cache --json
tuist runner volume delete <volume-id> --account my-org --yes
```

იგივე ოპერაცია ხელმისაწვდომია [API](https://tuist.dev/api/docs#tag/runners)-ით როგორც `DELETE /api/accounts/{account_handle}/runners/volumes/{volume_id}` და [MCP სერვერით](/guides/features/agentic-coding/mcp) როგორც `delete_runner_volume`. ყველა მათგანი მოითხოვს ანგარიშის ადმინისტრაციას ან ტოკენს `account:runners:write` სკოპით.
