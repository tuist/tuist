---
{
  "title": "Xcode ტესტების შარდინგი",
  "titleTemplate": ":title · ტესტების შარდინგი · ფუნქციები · სახელმძღვანელოები · Tuist",
  "description": "გაანაწილეთ Xcode-ის ტესტები მრავალ CI გამშვებზე Tuist Test Sharding-ის გამოყენებით."
}
---
# Xcode ტესტების დაშლა {#xcode-test-sharding}

> [!IMPORTANT]
> **მოთხოვნები**
>
> - <.localized_link href="/guides/features/test-insights/xcode">Xcode-ის ტესტების ანალიტიკა</.localized_link> კონფიგურირებული. შარდინგი იყენებს ბოლო 30 დღის ტესტების შესრულების დროს შარდების დასაბალანსებლად, ხოლო ანალიტიკის გარეშე თითოეული შარდი ისე მუშაობს, თითქოს საიტის სტრუქტურა უცნობი იყოს.

Xcode პროექტებისთვის ტესტების შარდინგი იყენებს `tuist xcodebuild build-for-testing` შარდის გეგმის შესაქმნელად და `tuist xcodebuild test` თითოეული შარდის შესასრულებლად.

## როგორ მუშაობს {#how-it-works}

ტესტების შარდინგი ორეტაპიან სამუშაო პროცესს მიჰყვება:

1. **კომპილაციის ეტაპი:** Tuist კითხულობს ტესტის მოდულებს აწყობილი `.xctestrun` ფაილიდან და ქმნის **დაშლის გეგმას** სერვერზე. სერვერი იყენებს ბოლო 30 დღის ისტორიულ ტესტირების დროის მონაცემებს, რათა გაანაწილოს ტესტები ნაწილებად ისე, რომ თითოეულმა ნაწილმა დაახლოებით ერთი და იგივე დრო დაჰყოს. კომპილაციის ეტაპი გამოიმუშავებს **დაშლის მატრიცას**, რომელსაც თქვენი CI სისტემა იყენებს პარალელური გამშვებების შესაქმნელად.
2. **ტესტირების ეტაპი:** თითოეული უწყვეტი ინტეგრაციის გამშვები (runner) იღებს **შარდის ინდექსს** და ზუსტ **შარდის გეგმის იდენტიფიკატორს**, შემდეგ ასრულებს ამ გეგმის ტესტების შერჩევას.

საიტის სტრუქტურის (suite) დონეზე, სერვერი იყენებს საიტებს, რომლებიც ბოლო CI გაშვებებმა თქვენს ბრენჩზე აღრიცხეს თითოეული მოდულისთვის მიმდინარე `.xctestrun`-ში, ხოლო ბრენჩის ისტორიის არმქონე მოდულებისთვის ეყრდნობა პროექტის ნაგულისხმევ ბრენჩს. რამდენიმე გაშვების გაერთიანება ინარჩუნებს საიტებს, რომლებიც შარდირებულმა ან შერჩევითმა გაშვებამ გამოტოვა ბოლო ანგარიშში.

როდესაც გამოიყენება `--shard-granularity suite`, Tuist აბალანსებს ცნობილ საიტებს მოთხოვნილ შარდების რაოდენობაზე და იყენებს ბოლო შარდს როგორც „ყველაფრის ჩამთვლელს“ (catch-all). მაგალითად, `--shard-total 5` ქმნის შარდის ინდექსებს `0`-დან `4`-მდე, სადაც შარდის ინდექსი `4` არის „ყველაფრის ჩამთვლელი“. ჩვეულებრივი შარდები მუშაობენ `-only-testing`-ით მათთვის მინიჭებული საიტებისთვის. ბოლო შარდი მუშაობს `-only-testing`-ის გარეშე და გადასცემს `-skip-testing` ყველა საიტისთვის, რომელიც ადრეულ შარდებს მიენიჭა, რითაც ასრულებს დაგეგმილ საიტებს პლუს ახლად დამატებულ საიტებს ან საიტებს, რომლებიც აკლია ისტორიულ ინვენტარს. მოდულის დონეზე არ არის საჭირო „ყველაფრის ჩამთვლელი“, რადგან `.xctestrun` ფაილი უზრუნველყოფს მოდულების სიას.

## კომპილაციის ეტაპი {#build-phase}

ააწყეთ თქვენი ტესტები და შექმენით შარდის გეგმა:

```sh
tuist xcodebuild build-for-testing \
  -scheme MyScheme \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  --shard-total 5
```

ეს ბრძანება:
1. აწყობს თქვენს ტესტებს `xcodebuild build-for-testing`-ით
2. ქმნის შარდის გეგმას Tuist სერვერზე ისტორიული დროის მონაცემების გამოყენებით
3. ტვირთავს `.xctestproducts` ბანდლს ან წერს შარდის არქივს შარდის გამშვებების (runners) მიერ გამოყენებისთვის
4. გამოაქვს შარდის მატრიცა თქვენი CI სისტემისთვის

<!-- @snippet: ./_xcode-build-options -->

## ტესტირების ეტაპი {#test-phase}

თითოეული შარდის გამშვები (runner) ასრულებს მისთვის განკუთვნილ ტესტებს:

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

Tuist ქმნის `.tuist-shard-child-pipeline.yml`-ს, რომელსაც თქვენ იწვევთ როგორც [შვილ პაიპლაინს](https://docs.gitlab.com/ci/pipelines/downstream_pipelines/#parent-child-pipelines). განსაზღვრეთ `.tuist-shard` შაბლონური სამუშაო, რომელსაც გენერირებული შარდის სამუშაოები გააფართოვებენ:

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

თითოეულ გენერირებულ ნაბიჯს აქვს `TUIST_SHARD_INDEX` და `TUIST_SHARD_PLAN_ID` დაყენებული მის გარემოში. დაამატეთ ტესტის ბრძანება თითოეულ შარდის ნაბიჯში საერთო სკრიპტის გამოყენებით:

```bash
# .buildkite/shard-step.sh
#!/bin/bash
tuist auth login
tuist xcodebuild test \
  -scheme MyScheme \
  -destination 'platform=iOS Simulator,name=iPhone 16'
```

### Codemagic {#codemagic}

Codemagic არ უჭერს მხარს დინამიურ მატრიცულ სამუშაოებს, ამიტომ განსაზღვრეთ ცალკეული სამუშაო ნაკადი თითოეული შარდისთვის. Tuist წერს `TUIST_SHARD_MATRIX`-ს და `TUIST_SHARD_COUNT`-ს `CM_ENV` ფაილში აწყობის სამუშაო ნაკადში გამოყენებისთვის. Codemagic-ის `CM_ENV` არის სამუშაო ნაკადის მასშტაბით, ამიტომ ზუსტი შარდის გეგმის იდენტიფიკატორი არ კვეთს სამუშაო ნაკადის საზღვრებს; ტესტირების სამუშაო ნაკადები ეყრდნობიან მითითებაზე დაფუძნებულ შარდის ძიებას:

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

Bitrise-ზე, Tuist წერს `.tuist-shard-matrix.json`-ს (`shard_plan_id`-ის ჩათვლით) `BITRISE_DEPLOY_DIR`-ში, რაც ხელმისაწვდომს ხდის მას როგორც აწყობის არტეფაქტს ქვედა ნაკადის ეტაპებისთვის. თითოეული ტესტირების სამუშაო ნაკადი ამოიღებს გეგმის ID-ს ჩამოტვირთული არტეფაქტიდან `envman`-ის გამოყენებით, რათა ის მოხვდეს ტესტის ბრძანების გარემოში:

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
> Bitrise არ უჭერს მხარს დინამიურ პარალელურ სამუშაოების შექმნას შესრულების დროს. განსაზღვრეთ ფიქსირებული რაოდენობის შარდის სამუშაო ნაკადები თქვენს პაიპლაინის ეტაპებში — ერთ ეტაპში არსებული სამუშაო ნაკადები ავტომატურად მუშაობენ პარალელურად.

## გაზიარებული ტომები {#shared-volumes}

ნაგულისხმევად, აწყობის ეტაპი ტვირთავს `.xctestproducts` ბანდლს დაშორებულ საცავში და თითოეული შარდის გამშვები (runner) ტვირთავს მას. თუ თქვენი CI პროვაიდერი უჭერს მხარს **გაზიარებულ ტომებს** (მუდმივი საცავი, რომელიც მაუნტდება სამუშაოებს შორის), შეგიძლიათ სრულიად გამოტოვოთ ეს ატვირთვა/ჩამოტვირთვა ტესტის პროდუქტების გაზიარებული ფაილური სისტემის მეშვეობით გადაცემით.

ეს შეიძლება მნიშვნელოვნად შეამციროს შარდის გაშვების დრო, განსაკუთრებით დიდი ტესტის ბანდლებისთვის.

გაზიარებული ტომების გამოყენებისთვის:

1. **აწყობის ეტაპზე**, გადაეცით `-testProductsPath`, რომელიც მიუთითებს გაზიარებულ ტომზე და დაამატეთ `--shard-skip-upload` დაშორებული ატვირთვის გამოტოვებისთვის:

```sh
tuist xcodebuild build-for-testing \
  -scheme MyScheme \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  --shard-total 5 \
  --shard-skip-upload \
  -testProductsPath /path/to/shared/volume/$UNIQUE_ID/MyScheme.xctestproducts
```

2. **ტესტირების ეტაპზე**, გადაეცით იგივე `-testProductsPath`, რათა Tuist წაიკითხოს ტესტის პროდუქტები ლოკალურად ჩამოტვირთვის ნაცვლად:

```sh
tuist xcodebuild test \
  -scheme MyScheme \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  -testProductsPath /path/to/shared/volume/$UNIQUE_ID/MyScheme.xctestproducts
```

> [!IMPORTANT]
> გამოიყენეთ უნიკალური გზა თითოეული სამუშაო ნაკადის გაშვებისთვის (მაგ., ჩართეთ CI გაშვების ID), რათა თავიდან აიცილოთ კონფლიქტები პარალელურად მიმდინარე გაშვებებს შორის. ასევე, გაასუფთავეთ ტესტის პროდუქტები შარდინგის დასრულების შემდეგ, რათა თავიდან აიცილოთ მოძველებული მონაცემების დაგროვება ტომზე.

| ფლაგი | გარემოს ცვლადი | აღწერა |
|------|---------------------|-------------|
| `--shard-skip-upload` | `TUIST_TEST_SHARD_SKIP_UPLOAD` | გამოტოვეთ ტესტის პროდუქტების ბანდლის ატვირთვა დაშორებულ საცავში |

## თვითმართვადი არტიფაქტები {#self-managed-artifacts}

თუ თქვენს CI პროვაიდერს უკვე აქვს არტიფაქტების ატვირთვისა და ჩამოტვირთვის ეტაპები, შეგიძლიათ Tuist-ს დაავალოთ არქივაციისა და ამოღების მართვა, ხოლო თქვენს CI-ს — ტრანსპორტირება.

1. **აწყობის ეტაპზე**, გადაეცით `--shard-archive-path`, რათა Tuist-მა ლოკალურად ჩაწეროს ოპტიმიზებული შარდის არქივი ტესტის პროდუქტების ატვირთვის ნაცვლად:

```sh
tuist xcodebuild build-for-testing \
  -scheme MyScheme \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  --shard-total 5 \
  --shard-archive-path /tmp/shards/${UNIQUE_ID}/bundle.aar
```

2. ატვირთეთ ეს არქივი თქვენი CI-ის ნატიური არტიფაქტის ეტაპის გამოყენებით.

3. თითოეულ **ტესტირების ეტაპის** სამუშაოში, ჩამოტვირთეთ არქივი და გადაეცით იგივე გზა უკან Tuist-ს:

```sh
tuist xcodebuild test \
  -scheme MyScheme \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  --shard-archive-path /tmp/shards/${UNIQUE_ID}/bundle.aar
```

როდესაც `--shard-archive-path` დაყენებულია, Tuist ტოვებს ტესტის პროდუქტების დაშორებულ გადაცემას და იყენებს ლოკალურ არქივს. თუ ასევე გადასცემთ `--shard-skip-upload`, არქივის გზას ენიჭება უპირატესობა.

### Namespace {#namespace}

[Namespace](https://namespace.so)-ის გამშვებები (runners) კარგად მუშაობენ GitHub Actions არტიფაქტებთან. ერთხელ დააყენეთ `TUIST_TEST_SHARD_ARCHIVE_PATH`, რათა აწყობის სამუშაომ ლოკალურად ჩაწეროს შარდის არქივი, ატვირთოთ ის და ჩამოტვირთოთ თითოეულ შარდის სამუშაოში `tuist xcodebuild test`-ის გაშვებამდე:

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
