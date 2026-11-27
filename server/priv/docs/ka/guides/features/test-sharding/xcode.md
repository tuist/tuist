---
{
  "title": "Xcode ტესტების შარდინგი",
  "titleTemplate": ":title · ტესტების შარდინგი · ფუნქციები · სახელმძღვანელოები · Tuist",
  "description": "გაანაწილეთ Xcode ტესტები მრავალ CI გამშვებზე Tuist Test Sharding-ის საშუალებით."
}
---
# Xcode-ის ტესტების შარდირება {#xcode-test-sharding}

> [!IMPORTANT]
> **მოთხოვნები**
>
> - <.localized_link href="/guides/features/test-insights/xcode">Xcode-ის ტესტების ინსაიტები</.localized_link> კონფიგურირებული. შარდირება იყენებს ბოლო 30 დღის ტესტების შესრულების დროს შარდების გასათანაბრებლად და ინსაიტების გარეშე ყოველი შარდი ისე მუშაობს, თითქოს ტესტების ნაკრები უცნობი იყოს.

Xcode-ის პროექტებისთვის ტესტების შარდირება იყენებს `tuist xcodebuild build-for-testing` შარდების გეგმის შესაქმნელად და `tuist xcodebuild test` თითოეული შარდის შესასრულებლად.

## როგორ მუშაობს {#how-it-works}

ტესტების შარდირება ორეტაპიან სამუშაო პროცესს მიჰყვება:

1. **აგების ეტაპი:** Tuist კითხულობს ტესტების მოდულებს აგებული `.xctestrun` ფაილიდან და ქმნის **შარდების გეგმას** სერვერზე. სერვერი იყენებს ბოლო 30 დღის ისტორიულ ტესტების შესრულების დროს, რათა ტესტები შარდებს შორის ისე გაანაწილოს, რომ თითოეულ შარდს დაახლოებით ერთი და იგივე დრო დასჭირდეს. აგების ეტაპი გამოაქვს **შარდების მატრიცა**, რომელსაც თქვენი CI სისტემა იყენებს პარალელური გამშვებების გასაშვებად.
2. **ტესტირების ეტაპი:** თითოეული უწყვეტი ინტეგრაციის გამშვები იღებს **შარდის ინდექსს** და ზუსტ **შარდების გეგმის იდენტიფიკატორს**, შემდეგ ასრულებს ამ გეგმის ტესტების შერჩევას.

ნაკრების დონის სიზუსტით, სერვერი იყენებს ნაკრებებს, რომლებიც ბოლო CI გაშვებებმა თქვენს ბრენჩზე შეატყობინეს თითოეული მოდულისთვის მიმდინარე `.xctestrun`-ში, ხოლო ბრენჩის ისტორიის არმქონე მოდულებისთვის გადადის პროექტის ნაგულისხმევ ბრენჩზე. რამდენიმე გაშვების გაერთიანება ინარჩუნებს ნაკრებებს, რომლებიც შარდირებულმა ან შერჩევითმა გაშვებამ ბოლო ანგარიშში ვერ მოიცვა.

როდესაც გამოიყენება `--shard-granularity suite`, Tuist ათანაბრებს ცნობილ ნაკრებებს მოთხოვნილ შარდების რაოდენობაზე და საბოლოო შარდს იყენებს როგორც „ყველაფრის დამჭერს“. მაგალითად, `--shard-total 5` ქმნის შარდების ინდექსებს `0`-დან `4`-მდე, სადაც შარდის ინდექსი `4` არის „ყველაფრის დამჭერი“. ჩვეულებრივი შარდები მუშაობენ `-only-testing`-ით მათთვის განკუთვნილი ნაკრებებისთვის. საბოლოო შარდი მუშაობს `-only-testing`-ის გარეშე და გადასცემს `-skip-testing`-ს ყოველი ნაკრებისთვის, რომელიც ადრეულ შარდებს მიენიჭა, რითაც ის ასრულებს დაგეგმილ ნაკრებებს პლუს ახლად დამატებულ ნაკრებებს ან ისტორიული ინვენტარიდან ამოვარდნილ ნაკრებებს. მოდულის დონის სიზუსტეს არ სჭირდება „ყველაფრის დამჭერი“, რადგან `.xctestrun` ფაილი უზრუნველყოფს მოდულების სიას.

## აგების ეტაპი {#build-phase}

ააგეთ თქვენი ტესტები და შექმენით შარდების გეგმა:

```sh
tuist xcodebuild build-for-testing \
  -scheme MyScheme \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  --shard-total 5
```

ეს ბრძანება:
1. აგებს თქვენს ტესტებს `xcodebuild build-for-testing`-ით
2. ქმნის შარდების გეგმას Tuist-ის სერვერზე ისტორიული შესრულების დროის მონაცემების გამოყენებით
3. ატვირთავს `.xctestproducts` ბანდლს ან წერს შარდების არქივს შარდების გამშვებებისთვის
4. გამოაქვს შარდების მატრიცა თქვენი CI სისტემისთვის

<!-- @snippet: ./_xcode-build-options -->

## ტესტირების ეტაპი {#test-phase}

თითოეული შარდის გამშვები ასრულებს მისთვის განკუთვნილ ტესტებს:

```sh
tuist xcodebuild test \
  -scheme MyScheme \
  -destination 'platform=iOS Simulator,name=iPhone 16'
```

<!-- @snippet: ./_xcode-test-options -->

## უწყვეტი ინტეგრაცია {#continuous-integration}

<!-- @snippet: ./_ci-providers -->

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

Tuist ქმნის `.tuist-shard-child-pipeline.yml`-ს, რომელსაც თქვენ იწვევთ როგორც [შვილობილ პაიპლაინს](https://docs.gitlab.com/ci/pipelines/downstream_pipelines/#parent-child-pipelines). განსაზღვრეთ `.tuist-shard` შაბლონური სამუშაო, რომელსაც გენერირებული შარდების სამუშაოები გააფართოებენ:

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

Tuist ქმნის `.tuist-shard-continuation.json`-ს პარამეტრებით [გაგრძელების orb-ისთვის](https://circleci.com/developer/orbs/orb/circleci/continuation). `shard-plan-id` პარამეტრი უნდა იყოს გამოცხადებული თქვენს გაგრძელებულ კონფიგურაციაში:

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

Tuist ქმნის `.tuist-shard-pipeline.yml`-ს ერთი ნაბიჯით თითოეული შარდისთვის. ატვირთეთ ის `buildkite-agent pipeline upload`-ით:

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

Codemagic არ უჭერს მხარს დინამიურ მატრიცულ სამუშაოებს, ამიტომ განსაზღვრეთ ცალკეული სამუშაო ნაკადი თითოეული შარდისთვის. Tuist წერს `TUIST_SHARD_MATRIX`-ს და `TUIST_SHARD_COUNT`-ს `CM_ENV` ფაილში აგების სამუშაო ნაკადში გამოყენებისთვის. Codemagic-ის `CM_ENV` არის სამუშაო ნაკადის ფარგლებში, ამიტომ ზუსტი შარდების გეგმის იდენტიფიკატორი არ კვეთს სამუშაო ნაკადის საზღვრებს; ტესტირების სამუშაო ნაკადები გადადიან მითითებაზე დაფუძნებულ შარდების ძიებაზე:

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

Bitrise-ზე, Tuist წერს `.tuist-shard-matrix.json`-ს (`shard_plan_id`-ის ჩათვლით) `BITRISE_DEPLOY_DIR`-ში, რაც ხდის მას ხელმისაწვდომს როგორც აგების არტეფაქტს ქვემოთ მიმდინარე პაიპლაინის ეტაპებისთვის. თითოეული ტესტირების სამუშაო ნაკადი ამოიღებს გეგმის ID-ს ჩამოტვირთული არტეფაქტიდან `envman`-ის გამოყენებით, რათა ის მოხვდეს ტესტირების ბრძანების გარემოში:

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
> Bitrise არ უჭერს მხარს დინამიურ პარალელურ სამუშაოების შექმნას შესრულების დროს. განსაზღვრეთ შარდების სამუშაო ნაკადების ფიქსირებული რაოდენობა თქვენს პაიპლაინის ეტაპებში — ეტაპის ფარგლებში სამუშაო ნაკადები ავტომატურად პარალელურად მუშაობენ.

## გაზიარებული ტომები {#shared-volumes}

ნაგულისხმევად, აგების ეტაპი ტვირთავს `.xctestproducts` ბანდლს დაშორებულ საცავში და თითოეული შარდის გამშვები მას ჩამოტვირთავს. თუ თქვენი CI პროვაიდერი უჭერს მხარს **გაზიარებულ ტომებს** (მუდმივი საცავი, რომელიც მონტირებულია სამუშაოებს შორის), შეგიძლიათ სრულიად გამოტოვოთ ეს ატვირთვა/ჩამოტვირთვა ტესტების პროდუქტების გაზიარებული ფაილური სისტემის მეშვეობით გადაცემით.

ეს შეიძლება მნიშვნელოვნად შეამციროს შარდების გაშვების დრო, განსაკუთრებით დიდი ტესტების ბანდლებისთვის.

გაზიარებული ტომების გამოყენებისთვის:

1. **აგების ეტაპზე**, გადაეცით `-testProductsPath`, რომელიც მიუთითებს გაზიარებულ ტომზე და დაამატეთ `--shard-skip-upload` დაშორებული ატვირთვის გამოსატოვებლად:

```sh
tuist xcodebuild build-for-testing \
  -scheme MyScheme \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  --shard-total 5 \
  --shard-skip-upload \
  -testProductsPath /path/to/shared/volume/$UNIQUE_ID/MyScheme.xctestproducts
```

2. **ტესტირების ეტაპზე**, გადაეცით იგივე `-testProductsPath`, რათა Tuist წაიკითხოს ტესტების პროდუქტები ლოკალურად ჩამოტვირთვის ნაცვლად:

```sh
tuist xcodebuild test \
  -scheme MyScheme \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  -testProductsPath /path/to/shared/volume/$UNIQUE_ID/MyScheme.xctestproducts
```

> [!IMPORTANT]
> გამოიყენეთ უნიკალური გზა თითოეული სამუშაო ნაკადის გაშვებისთვის (მაგ., ჩართეთ CI გაშვების ID), რათა თავიდან აიცილოთ კონფლიქტები პარალელურად მიმდინარე გაშვებებს შორის. ასევე, გაასუფთავეთ ტესტების პროდუქტები შარდინგის დასრულების შემდეგ, რათა თავიდან აიცილოთ მოძველებული მონაცემების დაგროვება ტომზე.

| ფლაგი | გარემოს ცვლადი | აღწერა |
|------|---------------------|-------------|
| `--shard-skip-upload` | `TUIST_TEST_SHARD_SKIP_UPLOAD` | გამოტოვეთ ტესტების პროდუქტების ბანდლის ატვირთვა დაშორებულ საცავში |

## თვითმართვადი არტიფაქტები {#self-managed-artifacts}

თუ თქვენს CI პროვაიდერს უკვე აქვს არტიფაქტების ატვირთვისა და ჩამოტვირთვის ეტაპები, შეგიძლიათ Tuist-ს მიაკისროთ არქივირება და ამოღება, ხოლო თქვენს CI-ს — ტრანსპორტირება.

1. **აგების ეტაპზე**, გადაეცით `--shard-archive-path`, რათა Tuist-მა ჩაწეროს ოპტიმიზებული შარდის არქივი ლოკალურად ტესტების პროდუქტების ატვირთვის ნაცვლად:

```sh
tuist xcodebuild build-for-testing \
  -scheme MyScheme \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  --shard-total 5 \
  --shard-archive-path /tmp/shards/${UNIQUE_ID}/bundle.aar
```

2. ატვირთეთ ეს არქივი თქვენი CI-ის ნატიური არტიფაქტების ეტაპის გამოყენებით.

3. თითოეულ **ტესტირების ეტაპის** სამუშაოში, ჩამოტვირთეთ არქივი და გადაეცით იგივე გზა უკან Tuist-ს:

```sh
tuist xcodebuild test \
  -scheme MyScheme \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  --shard-archive-path /tmp/shards/${UNIQUE_ID}/bundle.aar
```

როდესაც `--shard-archive-path` დაყენებულია, Tuist ტოვებს ტესტების პროდუქტების დაშორებულ გადაცემას და იყენებს ლოკალურ არქივს. თუ ასევე გადასცემთ `--shard-skip-upload`, არქივის გზას ენიჭება უპირატესობა.

### Namespace {#namespace}

[Namespace](https://namespace.so)-ის გამშვებები კარგად მუშაობენ GitHub Actions-ის არტიფაქტებთან. დააყენეთ `TUIST_TEST_SHARD_ARCHIVE_PATH` ერთხელ, რათა აგების სამუშაომ ჩაწეროს შარდის არქივი ლოკალურად, ატვირთოთ ის და ჩამოტვირთოთ თითოეულ შარდის სამუშაოში `tuist xcodebuild test`-ის გაშვებამდე:

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
