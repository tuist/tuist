---
{
  "title": "Xcode Test Sharding",
  "titleTemplate": ":title · Test Sharding · Features · Guides · Tuist",
  "description": "Distribute Xcode tests across multiple CI runners with Tuist Test Sharding."
}
---
# Xcode ტესტების დაყოფა {#xcode-test-sharding}

> [!WARNING]
> **მოთხოვნები**
>
> - <.localized_link href="/guides/features/test-insights/xcode">Xcode ტესტების ანალიტიკა</.localized_link> კონფიგურირებული. დაყოფა იყენებს ბოლო 30 დღის ტესტების შესრულების დროის მონაცემებს, რათა გაანაწილოს ტესტები თანაბრად; ანალიტიკის გარეშე ყოველი ნაწილი ისე მოქმედებს, თითქოს ტესტების სიუიტა უცნობი იყოს.

Xcode პროექტებისთვის ტესტების დაყოფა იყენებს `tuist xcodebuild build-for-testing` shard-გეგმის შესაქმნელად და `tuist xcodebuild test` თითოეული shard-ის შესასრულებლად.

## როგორ მუშაობს {#how-it-works}

ტესტების დაყოფა ორეტაპიან სამუშაო პროცესს მიჰყვება:

1. **აგების ეტაპი:** Tuist კითხულობს ტესტის მოდულებს აგებული `.xctestrun` ფაილიდან და ქმნის **shard-გეგმას** სერვერზე. სერვერი იყენებს ბოლო 30 დღის ისტორიულ დროის მონაცემებს, რათა ტესტები გაანაწილოს shard-ებში ისე, რომ თითოეულ shard-ს დაახლოებით ერთი და იგივე დრო დასჭირდეს. აგების ეტაპი გამოაქვს **shard-მატრიცა**, რომელსაც თქვენი CI სისტემა იყენებს პარალელური გამშვებების (runners) შესაქმნელად.
2. **ტესტირების ეტაპი:** თითოეული ინტეგრაციის გამშვები (runner) იღებს **shard-ინდექსს** და ზუსტ **shard-გეგმის იდენტიფიკატორს**, შემდეგ ასრულებს ამ გეგმის ტესტების შერჩევას.

სიუიტის დონის დაყოფისას სერვერი ირჩევს ცნობილ სიუიტებს თითოეული მოდულისთვის: მიმდინარე `.xctestrun`-ში არსებული თითოეული მოდულისთვის ის აერთიანებს ბოლო რამდენიმე CI გაშვების სიუიტებს იმ განშტოებაზე, რომელიც აგდება, ხოლო ისეთი მოდულებისთვის, რომლებსაც განშტოების ისტორია არ აქვთ, გადადის პროექტის საწყის (default) განშტოებაზე. რამდენიმე გაშვების წაკითხვა უკანასკნელის ნაცვლად მნიშვნელოვანია, რადგან დაყოფილი გაშვებისას თითოეული shard-ის დასრულებისთანავე იტვირთება ერთი ტესტის გაშვება, ამიტომ უახლესი გაშვება შეიცავს მხოლოდ მოდულის იმ ნაწილს, რომელიც ამ დრომდეა ჩატვირთული; ასევე ეს ხელს უშლის შერჩევითი ტესტირების გაშვებებს დამალონ სიუიტები, რომლებიც გამოტოვებული იყო უახლეს განშტოების გაშვებაში.

როდესაც გამოიყენება `--shard-granularity suite`, Tuist ანაწილებს ცნობილ სიუიტებს მოთხოვნილი shard-ების რაოდენობაზე და ბოლო shard-ს იყენებს როგორც „ყველა დანარჩენის“ (catch-all) კონტეინერს. მაგალითად, `--shard-total 5` ქმნის shard-ინდექსებს `0`-დან `4`-მდე, სადაც shard-ინდექსი `4` არის catch-all. ჩვეულებრივი shard-ები ასრულებენ `-only-testing`-ით მათთვის განკუთვნილ სიუიტებს. ბოლო shard-ი ასრულებს `-only-testing`-ის გარეშე და გადასცემს `-skip-testing`-ს ყოველი სიუიტისთვის, რომელიც ადრეულ shard-ებს მიენიჭა, ამიტომ ის ასრულებს თავის დაგეგმილ სიუიტებს პლუს ახლად დამატებულ ან ისტორიული ინვენტარიდან გამორჩენილ სიუიტებს. მოდულის დონის დაყოფას არ სჭირდება catch-all, რადგან `.xctestrun` ფაილი უზრუნველყოფს მოდულების სიას.

## აგების ეტაპი {#build-phase}

ააგეთ თქვენი ტესტები და შექმენით shard-გეგმა:

```sh
tuist xcodebuild build-for-testing \
  -scheme MyScheme \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  --shard-total 5
```

ეს ბრძანება:
1. აგებს თქვენს ტესტებს `xcodebuild build-for-testing`-ით
2. ქმნის shard-გეგმას Tuist სერვერზე ისტორიული დროის მონაცემების გამოყენებით
3. ტვირთავს `.xctestproducts` ბანდლს ან წერს shard-არქივს shard-გამშვებების (runners) მიერ გამოსაყენებლად
4. გამოაქვს shard-მატრიცა თქვენი CI სისტემისთვის

### აგების პარამეტრები {#build-options}

| ფლაგი | გარემოს ცვლადი | აღწერა |
|------|---------------------|-------------|
| `--shard-max <N>` | `TUIST_TEST_SHARD_MAX` | Shard-ების მაქსიმალური რაოდენობა. გამოიყენება `--shard-max-duration`-თან ერთად shard-ების რაოდენობის შესაზღუდად |
| `--shard-min <N>` | `TUIST_TEST_SHARD_MIN` | Shard-ების მინიმალური რაოდენობა |
| `--shard-total <N>` | `TUIST_TEST_SHARD_TOTAL` | Shard-ების ზუსტი რაოდენობა (ურთიერთგამომრიცხავია `--shard-min`/`--shard-max`-თან). სიუიტის დონის დაყოფისას ბოლო shard-ი არის catch-all |
| `--shard-max-duration <MS>` | `TUIST_TEST_SHARD_MAX_DURATION` | მიზნობრივი მაქსიმალური ხანგრძლივობა თითოეული shard-ისთვის მილიწამებში |
| `--shard-granularity <LEVEL>` | `TUIST_TEST_SHARD_GRANULARITY` | `module` (ნაგულისხმები) ანაწილებს მთლიან ტესტის მოდულებს shard-ებში; `suite` ანაწილებს ინდივიდუალურ ტესტის კლასებს უფრო ზუსტი ბალანსირებისთვის |
| `--shard-reference <REF>` | `TUIST_SHARD_REFERENCE` | შარდ-გეგმის უნიკალური იდენტიფიკატორი (ავტომატურად განისაზღვრება მხარდაჭერილ CI პროვაიდერებზე) |
| `--shard-archive-path <PATH>` | `TUIST_TEST_SHARD_ARCHIVE_PATH` | გზა, სადაც Tuist წერს ოპტიმიზებულ shard-არქივს ტესტის პროდუქტების удаленное საცავში ატვირთვის ნაცვლად |

## ტესტირების ეტაპი {#test-phase}

თითოეული shard-გამშვები (runner) ასრულებს მისთვის განკუთვნილ ტესტებს:

```sh
tuist xcodebuild test \
  -scheme MyScheme \
  -destination 'platform=iOS Simulator,name=iPhone 16'
```

### ტესტირების პარამეტრები {#test-options}

| ფლაგი | გარემოს ცვლადი | აღწერა |
|------|---------------------|-------------|
| `--shard-index <N>` | `TUIST_SHARD_INDEX` | შესასრულებელი shard-ის ნულოვანი ინდექსი |
| `--shard-plan-id <IDENTIFIER>` | `TUIST_SHARD_PLAN_ID` | ზუსტი shard-გეგმის იდენტიფიკატორი, რომელიც გამოიცემა აგების ეტაპზე. გენერირებული პროვაიდერის გამოსავალი ავტომატურად შეიცავს ამ მნიშვნელობას |
| `--shard-reference <REF>` | `TUIST_SHARD_REFERENCE` | შარდ-გეგმის უნიკალური იდენტიფიკატორი (ავტომატურად განისაზღვრება მხარდაჭერილ CI პროვაიდერებზე) |
| `--shard-archive-path <PATH>` | `TUIST_TEST_SHARD_ARCHIVE_PATH` | გზა ლოკალურად მართულ shard-არქივამდე; Tuist ამოიღებს მას ტესტის პროდუქტების удаленное საცავიდან ჩამოტვირთვის ნაცვლად |

Tuist ჩამოტვირთავს `.xctestproducts` ბანდლს და ფილტრავს მას ისე, რომ შეიცავდეს მხოლოდ იმ ტესტებს, რომლებიც ამ shard-ს მიენიჭა.

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

გამოიყენეთ მატრიცული სტრატეგია shard-ების პარალელურად გასაშვებად:

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

Tuist ქმნის `.tuist-shard-child-pipeline.yml`, რომელიც თქვენ იწვევთ როგორც [child pipeline](https://docs.gitlab.com/ee/ci/pipelines/downstream_pipelines.html#parent-child-pipelines). განსაზღვრეთ `.tuist-shard` შაბლონური სამუშაო, რომელსაც გენერირებული shard-სამუშაოები გააფართოებენ:

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

Tuist ქმნის `.tuist-shard-continuation.json` პარამეტრებით [continuation orb](https://circleci.com/developer/orbs/orb/circleci/continuation)-ისთვის. `shard-plan-id` პარამეტრი უნდა იყოს გამოცხადებული თქვენს გაგრძელებულ კონფიგურაციაში:

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

Tuist ქმნის `.tuist-shard-pipeline.yml` ერთი ნაბიჯით თითოეული shard-ისთვის. ატვირთეთ ის `buildkite-agent pipeline upload`-ით:

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

თითოეულ გენერირებულ ნაბიჯს აქვს `TUIST_SHARD_INDEX` და `TUIST_SHARD_PLAN_ID` მითითებული მის გარემოში. დაამატეთ ტესტირების ბრძანება თითოეულ shard-ნაბიჯზე საერთო სკრიპტის გამოყენებით:

```bash
# .buildkite/shard-step.sh
#!/bin/bash
tuist auth login
tuist xcodebuild test \
  -scheme MyScheme \
  -destination 'platform=iOS Simulator,name=iPhone 16'
```

### Codemagic {#codemagic}

Codemagic არ უჭერს მხარს დინამიურ მატრიცულ სამუშაოებს, ამიტომ განსაზღვრეთ ცალკეული workflow თითოეული shard-ისთვის. Tuist წერს `TUIST_SHARD_MATRIX` და `TUIST_SHARD_COUNT` `CM_ENV` ფაილში build workflow-ში გამოსაყენებლად. Codemagic-ის `CM_ENV` არის workflow-ის ფარგლებში შეზღუდული, ამიტომ ზუსტი shard-გეგმის იდენტიფიკატორი არ კვეთს workflow-ის საზღვრებს; ტესტირების workflows გადადიან reference-based shard ძიებაზე:

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

Bitrise-ზე, Tuist წერს `.tuist-shard-matrix.json` (`shard_plan_id`-ის ჩათვლით) `BITRISE_DEPLOY_DIR`-ში, რაც ხდის მას ხელმისაწვდომს როგორც build artifact-ს downstream pipeline ეტაპებისთვის. თითოეული ტესტირების workflow ამოიღებს გეგმის ID-ს ჩამოტვირთული artifact-დან `envman`-ის გამოყენებით, რათა ის მოხვდეს ტესტირების ბრძანების გარემოში:

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
> Bitrise არ უჭერს მხარს დინამიურ პარალელურ სამუშაოების შექმნას runtime-ზე. განსაზღვრეთ ფიქსირებული რაოდენობის shard workflows თქვენს pipeline ეტაპებში — ეტაპის ფარგლებში workflows ავტომატურად მუშაობენ პარალელურად.

## გაზიარებული ტომები {#shared-volumes}

ნაგულისხმევად, აგების ეტაპი ტვირთავს `.xctestproducts` ბანდლს удаленное საცავში და თითოეული shard-გამშვები (runner) ჩამოტვირთავს მას. თუ თქვენი CI პროვაიდერი უჭერს მხარს **გაზიარებულ ტომებს** (მუდმივი საცავი, რომელიც მაუნტდება სამუშაოებს შორის), შეგიძლიათ სრულიად გამოტოვოთ ეს ატვირთვა/ჩამოტვირთვა ტესტის პროდუქტების გაზიარებული ფაილური სისტემის მეშვეობით გადაცემით.

ამას შეუძლია მნიშვნელოვნად შეამციროს shard-ის გაშვების დრო, განსაკუთრებით დიდი ტესტის ბანდლებისთვის.

გაზიარებული ტომების გამოყენებისთვის:

1. **აგების ეტაპზე**, გადაეცით `-testProductsPath`, რომელიც მიუთითებს გაზიარებულ ტომზე და დაამატეთ `--shard-skip-upload` удаленное ატვირთვის გამოტოვებისთვის:

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
> გამოიყენეთ უნიკალური გზა თითოეული workflow-ის გაშვებისთვის (მაგ., ჩართეთ CI გაშვების ID), რათა თავიდან აიცილოთ კოლიზიები პარალელურ გაშვებებს შორის. ასევე, უნდა გაასუფთაოთ ტესტის პროდუქტები sharding-ის დასრულების შემდეგ, რათა თავიდან აიცილოთ მოძველებული მონაცემების დაგროვება ტომზე.

| ფლაგი | გარემოს ცვლადი | აღწერა |
|------|---------------------|-------------|
| `--shard-skip-upload` | `TUIST_TEST_SHARD_SKIP_UPLOAD` | გამოტოვეთ ტესტის პროდუქტების ბანდლის ატვირთვა удаленное საცავში |

## თვითმართვადი არტიფაქტები {#self-managed-artifacts}

თუ თქვენს CI პროვაიდერს უკვე აქვს არტიფაქტების ატვირთვისა და ჩამოტვირთვის ნაბიჯები, შეგიძლიათ მიანდოთ Tuist-ს არქივირება და ამოღება, ხოლო თქვენს CI-ს — ტრანსპორტირება.

1. **აგების ეტაპზე**, გადაეცით `--shard-archive-path`, რათა Tuist დაწეროს ოპტიმიზებული shard-არქივი ლოკალურად ტესტის პროდუქტების ატვირთვის ნაცვლად:

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

როდესაც `--shard-archive-path` არის მითითებული, Tuist ტოვებს удаленное ტესტ-პროდუქტების გადაცემას და იყენებს ლოკალურ არქივს. თუ ასევე გადასცემთ `--shard-skip-upload`, არქივის გზას აქვს უპირატესობა.

### Namespace {#namespace}

[Namespace](https://namespace.so)-ის რანერები კარგად მუშაობენ GitHub Actions-ის არტიფაქტებთან. დააყენეთ `TUIST_TEST_SHARD_ARCHIVE_PATH` ერთხელ, რათა აგების სამუშაომ ჩაწეროს shard-არქივი ლოკალურად, ატვირთოთ ის და ჩამოტვირთოთ თითოეულ shard-სამუშაოში `tuist xcodebuild test`-ის გაშვებამდე:

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
