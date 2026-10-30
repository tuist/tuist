---
{
  "title": "Xcode ტესტების შარდირება",
  "titleTemplate": ":title · ტესტების შარდირება · ფუნქციები · სახელმძღვანელოები · Tuist",
  "description": "გაანაწილეთ Xcode-ის ტესტები რამდენიმე CI გამშვებზე Tuist Test Sharding-ით."
}
---
# Xcode-ის ტესტების დაყოფა {#xcode-test-sharding}

> [!WARNING]
> **მოთხოვნები**
>
> - <.localized_link href="/guides/features/test-insights/xcode">Xcode-ის ტესტების ინსაიტები</.localized_link> კონფიგურირებული. დაყოფა იყენებს ბოლო 30 დღის ტესტების შესრულების დროის მონაცემებს შარდების გასათანაბრებლად, ხოლო ინსაიტების გარეშე თითოეული შარდი ისე მუშაობს, თითქოს საწყობი უცნობი იყოს.

Xcode-ის პროექტებისთვის ტესტების დაყოფა იყენებს `tuist xcodebuild build-for-testing` შარდის გეგმის შესაქმნელად და `tuist xcodebuild test` თითოეული შარდის შესასრულებლად.

## როგორ მუშაობს {#how-it-works}

ტესტების დაყოფა ორეტაპიან სამუშაო პროცესს მიჰყვება:

1. **აგების ეტაპი:** Tuist კითხულობს ტესტის მოდულებს აგებული `.xctestrun` ფაილიდან და ქმნის **შარდის გეგმას** სერვერზე. სერვერი იყენებს ბოლო 30 დღის ისტორიულ ტესტების შესრულების დროის მონაცემებს ტესტების შარდებში გასანაწილებლად, რათა თითოეულ შარდს დაახლოებით ერთი და იგივე დრო დასჭირდეს. აგების ეტაპი გამოიმუშავებს **შარდების მატრიცას**, რომელსაც თქვენი CI სისტემა იყენებს პარალელური გამშვებების გასაშვებად.
2. **ტესტირების ეტაპი:** თითოეული უწყვეტი ინტეგრაციის გამშვები იღებს **შარდის ინდექსს** და ზუსტ **შარდის გეგმის იდენტიფიკატორს**, შემდეგ ასრულებს ამ გეგმის ტესტების შერჩევას.

საწყობის სიზუსტით, სერვერი ირჩევს ცნობილ საწყობებს თითოეული მოდულისთვის: მიმდინარე `.xctestrun`-ში არსებული თითოეული მოდულისთვის ის აერთიანებს ბოლო რამდენიმე CI გაშვების საწყობებს შექმნად ბრენჩზე, ხოლო ბრენჩის ისტორიის არმქონე მოდულებისთვის გადადის პროექტის ნაგულისხმევ ბრენჩზე. რამდენიმე გაშვების წაკითხვა ბოლოს ნაცვლად მნიშვნელოვანია, რადგან დაყოფილი გაშვება ტვირთავს ერთ ტესტის გაშვებას თითოეული შარდის დასრულებისთანავე, ამიტომ ყველაზე ბოლო გაშვება შეიცავს მხოლოდ მოდულის იმ ნაწილს, რომელიც ამ დროისთვის ჩატვირთულია, და ასევე ხელს უშლის შერჩევითი ტესტირების გაშვებებს დაფარონ საწყობები, რომლებიც გამოტოვებული იყო ბრენჩის ბოლო გაშვებაში.

როდესაც გამოიყენება `--shard-granularity suite`, Tuist ანაწილებს ცნობილ საწყობებს მოთხოვნილ შარდების რაოდენობაზე და იყენებს ბოლო შარდს როგორც „ყველასმომცველს“. მაგალითად, `--shard-total 5` ქმნის შარდის ინდექსებს `0`-დან `4`-მდე, სადაც შარდის ინდექსი `4` არის „ყველასმომცველი“. ჩვეულებრივი შარდები მუშაობენ `-only-testing`-ით მათთვის განკუთვნილი საწყობებისთვის. ბოლო შარდი მუშაობს `-only-testing`-ის გარეშე და გადასცემს `-skip-testing` თითოეული საწყობისთვის, რომელიც განკუთვნილი იყო ადრეული შარდებისთვის, რითაც ის ასრულებს დაგეგმილ საწყობებს პლიუს ახლად დამატებულ საწყობებს ან ისტორიული ჩამონათვალიდან ამოვარდნილ საწყობებს. მოდულის სიზუსტეს არ სჭირდება „ყველასმომცველი“, რადგან `.xctestrun` ფაილი უზრუნველყოფს მოდულების სიას.

## აგების ეტაპი {#build-phase}

ააწყეთ თქვენი ტესტები და შექმენით შარდის გეგმა:

```sh
tuist xcodebuild build-for-testing \
  -scheme MyScheme \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  --shard-total 5
```

ეს ბრძანება:
1. აწყობს თქვენს ტესტებს `xcodebuild build-for-testing`-ით
2. ქმნის შარდის გეგმას Tuist-ის სერვერზე ისტორიული დროის მონაცემების გამოყენებით
3. ტვირთავს `.xctestproducts` ბანდლს ან წერს შარდის არქივს შარდის გამშვებების გამოსაყენებლად
4. გამოიმუშავებს შარდების მატრიცას თქვენი CI სისტემისთვის

### აგების პარამეტრები {#build-options}

| ფლაგი | გარემოს ცვლადი | აღწერა |
|------|---------------------|-------------|
| `--shard-max <N>` | `TUIST_TEST_SHARD_MAX` | შარდების მაქსიმალური რაოდენობა. გამოიყენება `--shard-max-duration`-თან ერთად შარდების რაოდენობის შესაზღუდად |
| `--shard-min <N>` | `TUIST_TEST_SHARD_MIN` | შარდების მინიმალური რაოდენობა |
| `--shard-total <N>` | `TUIST_TEST_SHARD_TOTAL` | შარდების ზუსტი რაოდენობა (ურთიერთგამომრიცხავია `--shard-min`/`--shard-max`-თან). საწყობის სიზუსტით, ბოლო შარდი არის „ყველასმომცველი“ |
| `--shard-max-duration <MS>` | `TUIST_TEST_SHARD_MAX_DURATION` | სამიზნე მაქსიმალური ხანგრძლივობა თითოეული შარდისთვის მილიწამებში |
| `--shard-granularity <LEVEL>` | `TUIST_TEST_SHARD_GRANULARITY` | `module` (ნაგულისხმევი) ანაწილებს მთლიან ტესტის მოდულებს შარდებში; `suite` ანაწილებს ინდივიდუალურ ტესტის კლასებს უფრო დეტალური გათანაბრებისთვის |
| `--shard-reference <REF>` | `TUIST_SHARD_REFERENCE` | შარდის გეგმის უნიკალური იდენტიფიკატორი (ავტომატურად მიღებული მხარდაჭერილ CI პროვაიდერებზე) |
| `--shard-archive-path <PATH>` | `TUIST_TEST_SHARD_ARCHIVE_PATH` | გზა, სადაც Tuist წერს ოპტიმიზირებულ შარდის არქივს ტესტის პროდუქტების დისტანციურ საცავში ატვირთვის ნაცვლად |

## ტესტირების ეტაპი {#test-phase}

თითოეული შარდის გამშვები ასრულებს მისთვის განკუთვნილ ტესტებს:

```sh
tuist xcodebuild test \
  -scheme MyScheme \
  -destination 'platform=iOS Simulator,name=iPhone 16'
```

### ტესტირების პარამეტრები {#test-options}

| ფლაგი | გარემოს ცვლადი | აღწერა |
|------|---------------------|-------------|
| `--shard-index <N>` | `TUIST_SHARD_INDEX` | შესასრულებელი შარდის ნულოვანი ინდექსი |
| `--shard-plan-id <IDENTIFIER>` | `TUIST_SHARD_PLAN_ID` | აგების ეტაპის მიერ გამოცემული შარდის გეგმის ზუსტი იდენტიფიკატორი. გენერირებული პროვაიდერის გამონატანები ავტომატურად შეიცავს ამ მნიშვნელობას |
| `--shard-reference <REF>` | `TUIST_SHARD_REFERENCE` | შარდის გეგმის უნიკალური იდენტიფიკატორი (ავტომატურად მიღებული მხარდაჭერილ CI პროვაიდერებზე) |
| `--shard-archive-path <PATH>` | `TUIST_TEST_SHARD_ARCHIVE_PATH` | გზა ლოკალურად მართულ შარდის არქივამდე; Tuist ამოიღებს მას ტესტის პროდუქტების დისტანციური საცავიდან ჩამოტვირთვის ნაცვლად |

Tuist ჩამოტვირთავს `.xctestproducts` ბანდლს და ფილტრავს მას ისე, რომ შეიცავდეს მხოლოდ იმ ტესტებს, რომლებიც განკუთვნილია ამ შარდისთვის.

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

გამოიყენეთ მატრიცული სტრატეგია შარდების პარალელურად გასაშვებად:

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

Tuist ქმნის `.tuist-shard-child-pipeline.yml`, რომელსაც იწყებთ როგორც [შვილობილ პაიპლაინს](https://docs.gitlab.com/ee/ci/pipelines/downstream_pipelines.html#parent-child-pipelines). განსაზღვრეთ `.tuist-shard` შაბლონური სამუშაო, რომელსაც გენერირებული შარდის სამუშაოები გააფართოებენ:

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

Tuist ქმნის `.tuist-shard-continuation.json` პარამეტრებით [continuation orb-ისთვის](https://circleci.com/developer/orbs/orb/circleci/continuation). `shard-plan-id` პარამეტრი უნდა იყოს გამოცხადებული თქვენს გაგრძელებულ კონფიგურაციაში:

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

Tuist ქმნის `.tuist-shard-pipeline.yml` ერთი ნაბიჯით თითოეული შარდისთვის. ატვირთეთ ის `buildkite-agent pipeline upload`-ის საშუალებით:

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

თითოეულ გენერირებულ ნაბიჯს აქვს `TUIST_SHARD_INDEX` და `TUIST_SHARD_PLAN_ID` მითითებული გარემოში. დაამატეთ ტესტირების ბრძანება თითოეულ შარდის ნაბიჯზე საერთო სკრიპტის გამოყენებით:

```bash
# .buildkite/shard-step.sh
#!/bin/bash
tuist auth login
tuist xcodebuild test \
  -scheme MyScheme \
  -destination 'platform=iOS Simulator,name=iPhone 16'
```

### Codemagic {#codemagic}

Codemagic არ უჭერს მხარს დინამიურ მატრიცულ სამუშაოებს, ამიტომ განსაზღვრეთ ცალკეული სამუშაო ნაკადი თითოეული შარდისთვის. Tuist წერს `TUIST_SHARD_MATRIX` და `TUIST_SHARD_COUNT` `CM_ENV` ფაილში აგების სამუშაო ნაკადში გამოსაყენებლად. Codemagic-ის `CM_ENV` შეზღუდულია სამუშაო ნაკადის ფარგლებში, ამიტომ ზუსტი შარდის გეგმის იდენტიფიკატორი არ გადაკვეთს სამუშაო ნაკადის საზღვრებს; ტესტირების სამუშაო ნაკადები გადადიან რეფერენსზე დაფუძნებულ შარდის ძებნაზე:

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

Bitrise-ზე, Tuist წერს `.tuist-shard-matrix.json` (`shard_plan_id`-ის ჩათვლით) `BITRISE_DEPLOY_DIR`-ში, რაც ხდის მას ხელმისაწვდომს აგების არტიფაქტად ქვედა ნაკადის ეტაპებისთვის. თითოეული ტესტირების სამუშაო ნაკადი ამოიღებს გეგმის ID-ს ჩამოტვირთული არტიფაქტიდან `envman`-ის გამოყენებით, რათა ის მოხვდეს ტესტირების ბრძანების გარემოში:

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
> Bitrise არ უჭერს მხარს დინამიურ პარალელურ სამუშაოების შექმნას შესრულების დროს. განსაზღვრეთ ფიქსირებული რაოდენობის შარდის სამუშაო ნაკადები თქვენს პაიპლაინის ეტაპებში — ეტაპის შიგნით არსებული სამუშაო ნაკადები ავტომატურად პარალელურად მუშაობენ.

## გაზიარებული ტომები {#shared-volumes}

ნაგულისხმევად, აგების ეტაპი ტვირთავს `.xctestproducts` ბანდლს დისტანციურ საცავში და თითოეული შარდის გამშვები ჩამოტვირთავს მას. თუ თქვენი CI პროვაიდერი უჭერს მხარს **გაზიარებულ ტომებს** (მუდმივი საცავი, რომელიც მიმაგრებულია სამუშაოებს შორის), შეგიძლიათ სრულიად გამოტოვოთ ეს ატვირთვა/ჩამოტვირთვა ტესტის პროდუქტების გაზიარებული ფაილური სისტემის მეშვეობით გადაცემით.

ეს შეიძლება მნიშვნელოვნად შეამციროს შარდის გაშვების დრო, განსაკუთრებით დიდი ტესტის ბანდლებისთვის.

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

2. **ტესტირების ეტაპზე**, გადაეცით იგივე `-testProductsPath`, რათა Tuist წაიკითხოს ტესტის პროდუქტები ლოკალურად მათი ჩამოტვირთვის ნაცვლად:

```sh
tuist xcodebuild test \
  -scheme MyScheme \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  -testProductsPath /path/to/shared/volume/$UNIQUE_ID/MyScheme.xctestproducts
```

> [!IMPORTANT]
> გამოიყენეთ უნიკალური გზა თითოეული სამუშაო ნაკადის გაშვებისთვის (მაგ., ჩართეთ CI გაშვების ID) პარალელური გაშვებების შეჯახების თავიდან ასაცილებლად. ასევე, გაასუფთავეთ ტესტის პროდუქტები შარდინგის დასრულების შემდეგ, რათა თავიდან აიცილოთ მოძველებული მონაცემების დაგროვება ტომზე.

| ფლაგი | გარემოს ცვლადი | აღწერა |
|------|---------------------|-------------|
| `--shard-skip-upload` | `TUIST_TEST_SHARD_SKIP_UPLOAD` | გამოტოვეთ ტესტის პროდუქტების ბანდლის ატვირთვა დისტანციურ საცავში |

## თვითმართვადი არტიფაქტები {#self-managed-artifacts}

თუ თქვენს CI პროვაიდერს უკვე აქვს არტიფაქტების ატვირთვისა და ჩამოტვირთვის ნაბიჯები, შეგიძლიათ მიანდოთ Tuist-ს არქივაციისა და ამოღების მართვა, ხოლო თქვენს CI-ს — ტრანსპორტირება.

1. **აგების ეტაპზე**, გადაეცით `--shard-archive-path`, რათა Tuist-მა ჩაწეროს ოპტიმიზირებული შარდის არქივი ლოკალურად ტესტის პროდუქტების ატვირთვის ნაცვლად:

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

როდესაც `--shard-archive-path` დაყენებულია, Tuist ტოვებს ტესტის პროდუქტების დისტანციურ გადაცემას და იყენებს ლოკალურ არქივს. თუ ასევე გადასცემთ `--shard-skip-upload`, არქივის გზას ენიჭება უპირატესობა.

### Namespace {#namespace}

[Namespace](https://namespace.so)-ის რანერები კარგად მუშაობენ GitHub Actions-ის არტიფაქტებთან. დააყენეთ `TUIST_TEST_SHARD_ARCHIVE_PATH` ერთხელ, რათა აგების სამუშაომ შარდის არქივი ლოკალურად ჩაწეროს, შემდეგ ატვირთოთ ის და ჩამოტვირთოთ თითოეულ შარდის სამუშაოში `tuist xcodebuild test`-ის გაშვებამდე:

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
