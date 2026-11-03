---
{
  "title": "Xcode ტესტების შარდინგი",
  "titleTemplate": ":title · ტესტების შარდინგი · ფუნქციები · სახელმძღვანელოები · Tuist",
  "description": "გაანაწილეთ Xcode ტესტები მრავალ CI გამშვებზე Tuist Test Sharding-ის საშუალებით."
}
---
# Xcode-ის ტესტების დაყოფა {#xcode-test-sharding}

> [!WARNING]
> **მოთხოვნები**
>
> - <.localized_link href="/guides/features/test-insights/xcode">Xcode-ის ტესტების ანალიტიკა</.localized_link> კონფიგურირებული. დაყოფა იყენებს ბოლო 30 დღის ტესტების შესრულების დროს, რათა დააბალანსოს ნაწილები, ხოლო ანალიტიკის გარეშე თითოეული ნაწილი მუშაობს ისე, თითქოს ტესტების ჯგუფი უცნობი იყოს.

Xcode-ის პროექტებისთვის ტესტების დაყოფა იყენებს `tuist xcodebuild build-for-testing` ნაწილების გეგმის შესაქმნელად და `tuist xcodebuild test` თითოეული ნაწილის შესასრულებლად.

## როგორ მუშაობს {#how-it-works}

ტესტების დაყოფა მიჰყვება ორეტაპიან სამუშაო პროცესს:

1. **აგების ეტაპი:** Tuist კითხულობს ტესტების მოდულებს აგებული `.xctestrun` ფაილიდან და ქმნის **ნაწილების გეგმას** სერვერზე. სერვერი იყენებს ბოლო 30 დღის ისტორიულ მონაცემებს ტესტების შესრულების დროის შესახებ, რათა გაანაწილოს ტესტები ნაწილებში ისე, რომ თითოეულმა ნაწილმა დაახლოებით ერთნაირი დრო დახარჯოს. აგების ეტაპი გამოიტანს **ნაწილების მატრიცას**, რომელსაც თქვენი CI სისტემა იყენებს პარალელური გამშვებების შესაქმნელად.
2. **ტესტირების ეტაპი:** თითოეული უწყვეტი ინტეგრაციის გამშვები იღებს **ნაწილის ინდექსს** და ზუსტ **ნაწილების გეგმის იდენტიფიკატორს**, შემდეგ ასრულებს ამ გეგმის ტესტების შერჩევას.

სუიტის სიზუსტით, სერვერი ირჩევს ცნობილ სუიტებს თითოეული მოდულისთვის: მიმდინარე `.xctestrun`-ში არსებული თითოეული მოდულისთვის ის აერთიანებს ბოლო რამდენიმე CI გაშვების სუიტებს იმ ბრენჩზე, რომელიც აგდება, და გადადის პროექტის საწყის ბრენჩზე იმ მოდულებისთვის, რომლებსაც არ აქვთ ბრენჩის ისტორია. რამდენიმე გაშვების წაკითხვა ბოლო გაშვების ნაცვლად მნიშვნელოვანია, რადგან დაყოფილი გაშვება ატვირთავს ერთ ტესტის გაშვებას თითოეული ნაწილისთვის მისი დასრულებისთანავე, ამიტომ ყველაზე ახლანდელი გაშვება შეიცავს მხოლოდ მოდულის იმ ნაწილს, რომელიც ამ დრომდე დამუშავდა, და ასევე ეს ხელს უშლის შერჩევითი ტესტირების გაშვებებს დამალონ სუიტები, რომლებიც გამოტოვებული იყო ბრენჩის ბოლო გაშვებაში.

როდესაც გამოიყენება `--shard-granularity suite`, Tuist აბალანსებს ცნობილ სუიტებს მოთხოვნილ ნაწილების რაოდენობაზე და იყენებს ბოლო ნაწილს როგორც „ყველას შემკრებს“. მაგალითად, `--shard-total 5` ქმნის ნაწილების ინდექსებს `0`-დან `4`-მდე, სადაც ნაწილის ინდექსი `4` არის „ყველას შემკრები“. ჩვეულებრივი ნაწილები მუშაობენ `-only-testing`-ით მათთვის განკუთვნილი სუიტებისთვის. ბოლო ნაწილი მუშაობს `-only-testing`-ის გარეშე და გადასცემს `-skip-testing`-ს თითოეული სუიტისთვის, რომელიც მიკუთვნებულია ადრეულ ნაწილებს, ამიტომ ის ასრულებს დაგეგმილ სუიტებს პლუს ახლად დამატებულ სუიტებს ან სუიტებს, რომლებიც აკლია ისტორიულ ინვენტარს. მოდულის სიზუსტეს არ სჭირდება „ყველას შემკრები“, რადგან `.xctestrun` ფაილი უზრუნველყოფს მოდულების სიას.

## აგების ეტაპი {#build-phase}

ააგეთ თქვენი ტესტები და შექმენით ნაწილების გეგმა:

```sh
tuist xcodebuild build-for-testing \
  -scheme MyScheme \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  --shard-total 5
```

ეს ბრძანება:
1. აგებს თქვენს ტესტებს `xcodebuild build-for-testing`-ით
2. ქმნის ნაწილების გეგმას Tuist-ის სერვერზე ისტორიული დროის მონაცემების გამოყენებით
3. ატვირთავს `.xctestproducts` ბანდლს ან წერს ნაწილების არქივს ნაწილების გამშვებებისთვის
4. გამოაქვს ნაწილების მატრიცა თქვენი CI სისტემისთვის

### აგების პარამეტრები {#build-options}

| ფლაგი | გარემოს ცვლადი | აღწერა |
|------|---------------------|-------------|
| `--shard-max <N>` | `TUIST_TEST_SHARD_MAX` | ნაწილების მაქსიმალური რაოდენობა. გამოიყენება `--shard-max-duration`-თან ერთად ნაწილების რაოდენობის შესაზღუდად |
| `--shard-min <N>` | `TUIST_TEST_SHARD_MIN` | ნაწილების მინიმალური რაოდენობა |
| `--shard-total <N>` | `TUIST_TEST_SHARD_TOTAL` | ნაწილების ზუსტი რაოდენობა (ურთიერთგამომრიცხავია `--shard-min`/`--shard-max`-თან). სუიტის სიზუსტით, ბოლო ნაწილი არის „ყველას შემკრები“ |
| `--shard-max-duration <MS>` | `TUIST_TEST_SHARD_MAX_DURATION` | სამიზნე მაქსიმალური ხანგრძლივობა თითოეული ნაწილისთვის მილიწამებში |
| `--shard-granularity <LEVEL>` | `TUIST_TEST_SHARD_GRANULARITY` | `module` (ნაგულისხმევი) ანაწილებს მთლიან ტესტების მოდულებს ნაწილებში; `suite` ანაწილებს ინდივიდუალურ ტესტების კლასებს უფრო ზუსტი ბალანსისთვის |
| `--shard-reference <REF>` | `TUIST_SHARD_REFERENCE` | ნაწილების გეგმის უნიკალური იდენტიფიკატორი (ავტომატურად მიღებული მხარდაჭერილ CI პროვაიდერებზე) |
| `--shard-archive-path <PATH>` | `TUIST_TEST_SHARD_ARCHIVE_PATH` | გზა, სადაც Tuist წერს ოპტიმიზირებულ ნაწილების არქივს ტესტების პროდუქტების დისტანციურ საცავში ატვირთვის ნაცვლად |

## ტესტირების ეტაპი {#test-phase}

თითოეული ნაწილის გამშვები ასრულებს მისთვის განკუთვნილ ტესტებს:

```sh
tuist xcodebuild test \
  -scheme MyScheme \
  -destination 'platform=iOS Simulator,name=iPhone 16'
```

### ტესტირების პარამეტრები {#test-options}

| ფლაგი | გარემოს ცვლადი | აღწერა |
|------|---------------------|-------------|
| `--shard-index <N>` | `TUIST_SHARD_INDEX` | ნულოვანი ინდექსის მქონე ნაწილის ინდექსი შესასრულებლად |
| `--shard-plan-id <IDENTIFIER>` | `TUIST_SHARD_PLAN_ID` | ნაწილების გეგმის ზუსტი იდენტიფიკატორი, რომელიც გამოიცემა აგების ეტაპის მიერ. გენერირებული პროვაიდერის გამონატანები ავტომატურად შეიცავს ამ მნიშვნელობას |
| `--shard-reference <REF>` | `TUIST_SHARD_REFERENCE` | ნაწილების გეგმის უნიკალური იდენტიფიკატორი (ავტომატურად მიღებული მხარდაჭერილ CI პროვაიდერებზე) |
| `--shard-archive-path <PATH>` | `TUIST_TEST_SHARD_ARCHIVE_PATH` | გზა ლოკალურად მართვად ნაწილების არქივამდე; Tuist ამოიღებს მას ტესტების პროდუქტების დისტანციური საცავიდან ჩამოტვირთვის ნაცვლად |

Tuist ჩამოტვირთავს `.xctestproducts` ბანდლს და ფილტრავს მას ისე, რომ შეიცავდეს მხოლოდ იმ ტესტებს, რომლებიც მიკუთვნებულია ამ ნაწილს.

## უწყვეტი ინტეგრაცია {#continuous-integration}

Tuist ავტომატურად ამოიცნობს შემდეგ CI პროვაიდერებს:

- [GitHub Actions](#github-actions)
- [GitLab CI](#gitlab-ci)
- [CircleCI](#circleci)
- [Buildkite](#buildkite)
- [Codemagic](#codemagic)
- [Bitrise](#bitrise)

სხვა პროვაიდერებისთვის, მიმართეთ `.tuist-shard-matrix.json` ფაილს პარალელური სამუშაოების დასაყენებლად.

### GitHub Actions {#github-actions}

გამოიყენეთ მატრიცული სტრატეგია ნაწილების პარალელურად გასაშვებად:

```yaml
name: Tests
on: [pull_request]

jobs:
  build:
    name: Build test shards
    runs-on: macos-latest
    outputs:
      matrix: ${{ steps.build.outputs.matrix }}
    steps:
      - uses: actions/checkout@v4
      - uses: jdx/mise-action@v2
      - run: tuist auth login
      - id: build
        run: |
          tuist xcodebuild build-for-testing \
            -scheme MyScheme \
            -destination 'platform=iOS Simulator,name=iPhone 16' \
            --shard-total 5

  test:
    name: "Shard #${{ matrix.shard }}"
    needs: build
    runs-on: macos-latest
    strategy:
      fail-fast: false
      matrix: ${{ fromJson(needs.build.outputs.matrix) }}
    env:
      TUIST_SHARD_INDEX: ${{ matrix.shard }}
      TUIST_SHARD_PLAN_ID: ${{ matrix.shard_plan_id }}
    steps:
      - uses: actions/checkout@v4
      - uses: jdx/mise-action@v2
      - run: tuist auth login
      - run: |
          tuist xcodebuild test \
            -scheme MyScheme \
            -destination 'platform=iOS Simulator,name=iPhone 16'
```

### GitLab CI {#gitlab-ci}

Tuist გენერირებს `.tuist-shard-child-pipeline.yml`, რომელსაც იწვევთ როგორც [შვილობილ პაიპლაინს](https://docs.gitlab.com/ee/ci/pipelines/downstream_pipelines.html#parent-child-pipelines). განსაზღვრეთ `.tuist-shard` შაბლონის სამუშაო, რომელსაც გაფართოვებული ნაწილების სამუშაოები გამოიყენებენ:

```yaml
# .gitlab-ci.yml
stages:
  - build
  - test

build-shards:
  stage: build
  tags: [macos]
  script:
    - tuist auth login
    - |
      tuist xcodebuild build-for-testing \
        -scheme MyScheme \
        -destination 'platform=iOS Simulator,name=iPhone 16' \
        --shard-total 5
  artifacts:
    paths:
      - .tuist-shard-child-pipeline.yml

test-shards:
  stage: test
  needs: [build-shards]
  trigger:
    include:
      - artifact: .tuist-shard-child-pipeline.yml
        job: build-shards
    strategy: depend
```

```yaml
# .gitlab/shard-template.yml
.tuist-shard:
  tags: [macos]
  script:
    - tuist auth login
    - |
      tuist xcodebuild test \
        -scheme MyScheme \
        -destination 'platform=iOS Simulator,name=iPhone 16'
```

### CircleCI {#circleci}

Tuist გენერირებს `.tuist-shard-continuation.json` პარამეტრებით [გაგრძელების orb-ისთვის](https://circleci.com/developer/orbs/orb/circleci/continuation). `shard-plan-id` პარამეტრი უნდა იყოს გამოცხადებული თქვენს გაგრძელებულ კონფიგურაციაში:

```yaml
# .circleci/config.yml
version: 2.1
setup: true

orbs:
  continuation: circleci/continuation@1

jobs:
  build-shards:
    macos:
      xcode: "16.0"
    steps:
      - checkout
      - run:
          name: Build and plan shards
          command: |
            tuist auth login
            tuist xcodebuild build-for-testing \
              -scheme MyScheme \
              -destination 'platform=iOS Simulator,name=iPhone 16' \
              --shard-total 5
      - continuation/continue:
          configuration_path: .circleci/continue-config.yml
          parameters: .tuist-shard-continuation.json

workflows:
  setup:
    jobs:
      - build-shards
```

```yaml
# .circleci/continue-config.yml
version: 2.1

parameters:
  shard-indices:
    type: string
    default: ""
  shard-count:
    type: integer
    default: 0
  shard-plan-id:
    type: string
    default: ""

jobs:
  test-shard:
    macos:
      xcode: "16.0"
    parameters:
      shard-index:
        type: integer
    steps:
      - checkout
      - run:
          name: Run shard
          command: |
            export TUIST_SHARD_INDEX=<< parameters.shard-index >>
            export TUIST_SHARD_PLAN_ID=<< pipeline.parameters.shard-plan-id >>
            tuist auth login
            tuist xcodebuild test \
              -scheme MyScheme \
              -destination 'platform=iOS Simulator,name=iPhone 16'

workflows:
  test:
    jobs:
      - test-shard:
          matrix:
            parameters:
              shard-index: [<< pipeline.parameters.shard-indices >>]
```

### Buildkite {#buildkite}

Tuist გენერირებს `.tuist-shard-pipeline.yml` ერთი ნაბიჯით თითოეული ნაწილისთვის. ატვირთეთ ის `buildkite-agent pipeline upload`-ით:

```yaml
# pipeline.yml
steps:
  - label: "Build test shards"
    command: |
      tuist auth login
      tuist xcodebuild build-for-testing \
        -scheme MyScheme \
        -destination 'platform=iOS Simulator,name=iPhone 16' \
        --shard-total 5
      buildkite-agent pipeline upload .tuist-shard-pipeline.yml
    agents:
      queue: macos
```

თითოეულ გენერირებულ ნაბიჯს აქვს `TUIST_SHARD_INDEX` და `TUIST_SHARD_PLAN_ID` დაყენებული გარემოში. დაამატეთ ტესტირების ბრძანება თითოეულ ნაწილის ნაბიჯზე საერთო სკრიპტის გამოყენებით:

```bash
# .buildkite/shard-step.sh
#!/bin/bash
tuist auth login
tuist xcodebuild test \
  -scheme MyScheme \
  -destination 'platform=iOS Simulator,name=iPhone 16'
```

### Codemagic {#codemagic}

Codemagic არ უჭერს მხარს დინამიურ მატრიცულ სამუშაოებს, ამიტომ განსაზღვრეთ ცალკეული სამუშაო ნაკადი თითოეული ნაწილისთვის. Tuist წერს `TUIST_SHARD_MATRIX` და `TUIST_SHARD_COUNT` `CM_ENV` ფაილში აგების სამუშაო ნაკადში გამოსაყენებლად. Codemagic-ის `CM_ENV` შეზღუდულია სამუშაო ნაკადით, ამიტომ ზუსტი ნაწილების გეგმის იდენტიფიკატორი არ კვეთს სამუშაო ნაკადის საზღვრებს; ტესტირების სამუშაო ნაკადები გადადიან რეფერენსზე დაფუძნებულ ნაწილების ძიებაზე:

```yaml
# codemagic.yaml
workflows:
  build-shards:
    name: Build test shards
    instance_type: mac_mini_m2
    environment:
      xcode: latest
    scripts:
      - name: Build and plan shards
        script: |
          tuist auth login
          tuist xcodebuild build-for-testing \
            -scheme MyScheme \
            -destination 'platform=iOS Simulator,name=iPhone 16' \
            --shard-total 5

  test-shard-0: &shard-workflow
    name: "Shard #0"
    instance_type: mac_mini_m2
    environment:
      xcode: latest
      vars:
        TUIST_SHARD_INDEX: 0
    scripts:
      - name: Run shard
        script: |
          tuist auth login
          tuist xcodebuild test \
            -scheme MyScheme \
            -destination 'platform=iOS Simulator,name=iPhone 16'

  test-shard-1:
    <<: *shard-workflow
    name: "Shard #1"
    environment:
      xcode: latest
      vars:
        TUIST_SHARD_INDEX: 1

  test-shard-2:
    <<: *shard-workflow
    name: "Shard #2"
    environment:
      xcode: latest
      vars:
        TUIST_SHARD_INDEX: 2

  test-shard-3:
    <<: *shard-workflow
    name: "Shard #3"
    environment:
      xcode: latest
      vars:
        TUIST_SHARD_INDEX: 3

  test-shard-4:
    <<: *shard-workflow
    name: "Shard #4"
    environment:
      xcode: latest
      vars:
        TUIST_SHARD_INDEX: 4
```

### Bitrise {#bitrise}

Bitrise-ზე, Tuist წერს `.tuist-shard-matrix.json` (`shard_plan_id`-ის ჩათვლით) `BITRISE_DEPLOY_DIR`-ში, რაც ხელმისაწვდომს ხდის მას აგების არტიფაქტად ქვემო ნაკადის ეტაპებისთვის. თითოეული ტესტირების სამუშაო ნაკადი ამოიღებს გეგმის ID-ს ჩამოტვირთული არტიფაქტიდან `envman`-ის გამოყენებით, რათა ის მოხვდეს ტესტირების ბრძანების გარემოში:

```yaml
# bitrise.yml
pipelines:
  test-pipeline:
    stages:
      - build-stage: {}
      - test-stage: {}

stages:
  build-stage:
    workflows:
      - build-shards: {}
  test-stage:
    workflows:
      - test-shard-0: {}
      - test-shard-1: {}
      - test-shard-2: {}
      - test-shard-3: {}
      - test-shard-4: {}

workflows:
  build-shards:
    steps:
      - script:
          title: Build and plan shards
          inputs:
            - content: |
                tuist auth login
                tuist xcodebuild build-for-testing \
                  -scheme MyScheme \
                  -destination 'platform=iOS Simulator,name=iPhone 16' \
                  --shard-total 5
      - deploy-to-bitrise-io: {}

  test-shard-0: &shard-workflow
    envs:
      - TUIST_SHARD_INDEX: 0
    steps:
      - pull-intermediate-files: {}
      - script:
          title: Set shard plan ID from artifact
          inputs:
            - content: |
                PLAN_ID=$(jq -r '.shard_plan_id' "$BITRISE_DEPLOY_DIR/.tuist-shard-matrix.json")
                envman add --key TUIST_SHARD_PLAN_ID --value "$PLAN_ID"
      - script:
          title: Run shard
          inputs:
            - content: |
                tuist auth login
                tuist xcodebuild test \
                  -scheme MyScheme \
                  -destination 'platform=iOS Simulator,name=iPhone 16'
  test-shard-1:
    <<: *shard-workflow
    envs:
      - TUIST_SHARD_INDEX: 1
  test-shard-2:
    <<: *shard-workflow
    envs:
      - TUIST_SHARD_INDEX: 2
  test-shard-3:
    <<: *shard-workflow
    envs:
      - TUIST_SHARD_INDEX: 3
  test-shard-4:
    <<: *shard-workflow
    envs:
      - TUIST_SHARD_INDEX: 4
```

> [!TIP]
> Bitrise არ უჭერს მხარს დინამიურ პარალელურ სამუშაოების შექმნას შესრულების დროს. განსაზღვრეთ ფიქსირებული რაოდენობის ნაწილების სამუშაო ნაკადები თქვენს პაიპლაინის ეტაპებში — ეტაპის შიგნით არსებული სამუშაო ნაკადები ავტომატურად პარალელურად მუშაობენ.

## გაზიარებული ტომები {#shared-volumes}

ნაგულისხმევად, აგების ეტაპი ტვირთავს `.xctestproducts` ბანდლს დისტანციურ საცავში და თითოეული ნაწილის გამშვები ჩამოტვირთავს მას. თუ თქვენი CI პროვაიდერი უჭერს მხარს **გაზიარებულ ტომებს** (მუდმივი საცავი, რომელიც მიმაგრებულია სამუშაოებს შორის), შეგიძლიათ სრულიად გამოტოვოთ ეს ატვირთვა/ჩამოტვირთვა ტესტების პროდუქტების გაზიარებული ფაილური სისტემით გადაცემით.

ეს შეიძლება მნიშვნელოვნად შეამციროს ნაწილის გაშვების დრო, განსაკუთრებით დიდი ტესტების ბანდლებისთვის.

გაზიარებული ტომების გამოყენებისთვის:

1. **აგების ეტაპზე**, გადაეცით `-testProductsPath`, რომელიც მიუთითებს გაზიარებულ ტომზე და დაამატეთ `--shard-skip-upload` დისტანციური ატვირთვის გამოტოვებისთვის:

```sh
tuist xcodebuild build-for-testing \
  -scheme MyScheme \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  --shard-total 5 \
  --shard-skip-upload \
  -testProductsPath /path/to/shared/volume/$UNIQUE_ID/MyScheme.xctestproducts
```

2. **ტესტირების ეტაპზე**, გადაეცით იგივე `-testProductsPath`, რათა Tuist წაიკითხოს ტესტების პროდუქტები ლოკალურად მათი ჩამოტვირთვის ნაცვლად:

```sh
tuist xcodebuild test \
  -scheme MyScheme \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  -testProductsPath /path/to/shared/volume/$UNIQUE_ID/MyScheme.xctestproducts
```

> [!IMPORTANT]
> გამოიყენეთ უნიკალური გზა თითოეული სამუშაო ნაკადის გაშვებისთვის (მაგ., ჩართეთ CI გაშვების ID) პარალელური გაშვებების შერევის თავიდან ასაცილებლად. ასევე, უნდა გაასუფთაოთ ტესტების პროდუქტები ნაწილების დასრულების შემდეგ, რათა თავიდან აიცილოთ მოძველებული მონაცემების დაგროვება ტომზე.

| ფლაგი | გარემოს ცვლადი | აღწერა |
|------|---------------------|-------------|
| `--shard-skip-upload` | `TUIST_TEST_SHARD_SKIP_UPLOAD` | გამოტოვეთ ტესტების პროდუქტების ბანდლის ატვირთვა დისტანციურ საცავში |

## თვითმართვადი არტიფაქტები {#self-managed-artifacts}

თუ თქვენს CI პროვაიდერს უკვე აქვს არტიფაქტების ატვირთვისა და ჩამოტვირთვის ნაბიჯები, შეგიძლიათ მიანდოთ Tuist-ს არქივაციისა და ამოღების მართვა, ხოლო თქვენს CI-ს — ტრანსპორტირება.

1. **აგების ეტაპზე**, გადაეცით `--shard-archive-path`, რათა Tuist-მა ჩაწეროს ოპტიმიზირებული ნაწილების არქივი ლოკალურად ტესტების პროდუქტების ატვირთვის ნაცვლად:

```sh
tuist xcodebuild build-for-testing \
  -scheme MyScheme \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  --shard-total 5 \
  --shard-archive-path /tmp/shards/${UNIQUE_ID}/bundle.aar
```

2. ატვირთეთ ეს არქივი თქვენი CI-ის ნატიური არტიფაქტის ნაბიჯის გამოყენებით.

3. თითოეულ **ტესტირების ეტაპის** სამუშაოში, ჩამოტვირთეთ არქივი და გადაეცით იგივე გზა უკან Tuist-ს:

```sh
tuist xcodebuild test \
  -scheme MyScheme \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  --shard-archive-path /tmp/shards/${UNIQUE_ID}/bundle.aar
```

როდესაც `--shard-archive-path` დაყენებულია, Tuist ტოვებს ტესტების პროდუქტების დისტანციურ გადაცემას და იყენებს ლოკალურ არქივს. თუ ასევე გადასცემთ `--shard-skip-upload`, არქივის გზას ენიჭება უპირატესობა.

### Namespace {#namespace}

[Namespace](https://namespace.so)-ის გამშვებები კარგად მუშაობენ GitHub Actions-ის არტიფაქტებთან. ერთხელ დააყენეთ `TUIST_TEST_SHARD_ARCHIVE_PATH`, რათა აგების სამუშაომ ჩაწეროს ნაწილების არქივი ლოკალურად, ატვირთოთ ის და ჩამოტვირთოთ თითოეულ ნაწილის სამუშაოში `tuist xcodebuild test`-ის გაშვებამდე:

```yaml
name: Tests
on: [pull_request]

env:
  TUIST_TEST_SHARD_ARCHIVE_PATH: /tmp/shards/${{ github.run_id }}/bundle.aar

jobs:
  build:
    name: Build test shards
    runs-on: namespace-profile-default-macos
    outputs:
      matrix: ${{ steps.build.outputs.matrix }}
    steps:
      - uses: actions/checkout@v4
      - uses: jdx/mise-action@v2
      - run: tuist auth login
      - id: build
        run: |
          tuist xcodebuild build-for-testing \
            -scheme MyScheme \
            -destination 'platform=iOS Simulator,name=iPhone 16' \
            --shard-total 5
      - uses: actions/upload-artifact@v4
        with:
          name: test-shard-archive
          path: ${{ env.TUIST_TEST_SHARD_ARCHIVE_PATH }}
      - if: always()
        run: rm -rf /tmp/shards/${{ github.run_id }}

  test:
    name: "Shard #${{ matrix.shard }}"
    needs: build
    runs-on: namespace-profile-default-macos
    strategy:
      fail-fast: false
      matrix: ${{ fromJson(needs.build.outputs.matrix) }}
    env:
      TUIST_SHARD_INDEX: ${{ matrix.shard }}
      TUIST_SHARD_PLAN_ID: ${{ matrix.shard_plan_id }}
    steps:
      - uses: actions/checkout@v4
      - uses: jdx/mise-action@v2
      - run: tuist auth login
      - uses: actions/download-artifact@v4
        with:
          name: test-shard-archive
          path: /tmp/shards/${{ github.run_id }}
      - run: |
          tuist xcodebuild test \
            -scheme MyScheme \
            -destination 'platform=iOS Simulator,name=iPhone 16'
      - if: always()
        run: rm -rf /tmp/shards/${{ github.run_id }}
```
