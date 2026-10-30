---
{
  "title": "გენერირებული Xcode პროექტი",
  "titleTemplate": ":title · ტესტების დაყოფა · ფუნქციები · სახელმძღვანელოები · Tuist",
  "description": "გაანაწილეთ ტესტები Tuist-ით გენერირებულ Xcode პროექტში რამდენიმე CI გამშვებზე Tuist Test Sharding-ის გამოყენებით."
}
---
# გენერირებული Xcode პროექტი {#generated-xcode-project-test-sharding}

გენერირებული პროექტების ტესტების შარდინგი იყენებს `tuist test` როგორც აგების, ისე ტესტირების ეტაპებზე.

## როგორ მუშაობს {#how-it-works}

ტესტების შარდინგი მიჰყვება ორეტაპიან სამუშაო პროცესს:

1. **აგების ეტაპი:** Tuist კითხულობს ტესტის მოდულებს აგებული `.xctestrun` ფაილიდან და ქმნის **შარდის გეგმას** სერვერზე. სერვერი იყენებს ბოლო 30 დღის ისტორიულ ტესტების დროის მონაცემებს, რათა გაანაწილოს ტესტები შარდებში ისე, რომ თითოეულ შარდს დაახლოებით ერთი და იგივე დრო დასჭირდეს. აგების ეტაპი გამოაქვს **შარდის მატრიცა**, რომელსაც თქვენი CI სისტემა იყენებს პარალელური გამშვებების შესაქმნელად.
2. **ტესტირების ეტაპი:** თითოეული უწყვეტი ინტეგრაციის გამშვები იღებს **შარდის ინდექსს** და ზუსტ **შარდის გეგმის იდენტიფიკატორს**, შემდეგ ასრულებს ამ გეგმის ტესტების შერჩევას.

როდესაც გამოიყენება `--shard-granularity suite`, Tuist არ ტვირთავს ყოველ ტესტურ ბანდლს სუიტების ჩამოსათვლელად აგების ეტაპზე. ამის ნაცვლად, მიმდინარე `.xctestrun` ფაილი უზრუნველყოფს მოდულების სიას, ხოლო სერვერი ირჩევს ცნობილ სუიტებს თითოეული მოდულისთვის: თითოეული მოდულისთვის ის აერთიანებს ბოლო რამდენიმე CI გაშვების სუიტებს იმ ბრენჩზე, რომელიც აგდება. თუ მოდულს არ აქვს ისტორია ამ ბრენჩზე, სერვერი გადადის პროექტის ნაგულისხმევ ბრენჩზე. რამდენიმე გაშვების წაკითხვა ბოლო ერთის ნაცვლად მნიშვნელოვანია, რადგან შარდირებული გაშვება ატვირთავს ერთ ტესტის გაშვებას შარდზე, როგორც კი თითოეული შარდი დასრულდება, ამიტომ ყველაზე ბოლო გაშვება შეიცავს მხოლოდ მოდულის იმ ნაწილს, რომელიც ამ დრომდე იქნა მიღებული, და რადგან ეს ხელს უშლის შერჩევითი ტესტირების გაშვებებს დაფარონ სუიტები, რომლებიც გამოტოვებული იყო ბრენჩის ბოლო გაშვებაში. სერვერი მაინც იყენებს სუიტების დროის ბოლო 30 დღის მონაცემებს ხანგრძლივობის შესაფასებლად.

Tuist აბალანსებს ამ ცნობილ სუიტებს მოთხოვნილ შარდების რაოდენობაზე და იყენებს ბოლო შარდს, როგორც საყოველთაოს. მაგალითად, `--shard-total 5` ქმნის შარდის ინდექსებს `0`-დან `4`-მდე, სადაც შარდის ინდექსი `4` არის საყოველთაო. ჩვეულებრივი შარდები მუშაობენ `-only-testing`-ით მათთვის განკუთვნილი სუიტებისთვის. ბოლო შარდი მუშაობს `-only-testing`-ის გარეშე და გადასცემს `-skip-testing`-ს ყოველი სუიტისთვის, რომელიც განკუთვნილია ადრეული შარდებისთვის, ამიტომ ის ასევე ასრულებს ახლად დამატებულ სუიტებს, სახელშეცვლილ სუიტებს ან ისტორიული ინვენტარიდან გამორჩენილ სუიტებს. მოდულის გრანულარობას არ სჭირდება საყოველთაო, რადგან `.xctestrun` ფაილი უზრუნველყოფს მოდულების სიას.

## აგების ეტაპი {#build-phase}

გააგენერეთ თქვენი პროექტი, ააგეთ თქვენი ტესტები და შექმენით შარდის გეგმა:

```sh
tuist test --build-only --shard-total 5
```

`--build-only` ფლაგი ეუბნება Tuist-ს, რომ ააგოს ტესტები მათი გაშვების გარეშე. Tuist შეცდომას აბრუნებს, თუ შარდის დაგეგმვის ფლაგებს (`--shard-min`/`--shard-max`/`--shard-total`) გადასცემთ `--build-only`-ის გარეშე.

ეს ბრძანება:
1. აგენერირებს Xcode პროექტს თქვენი მანიფესტებიდან
2. აგებს თქვენს ტესტებს
3. ქმნის შარდის გეგმას Tuist სერვერზე ისტორიული დროის მონაცემების გამოყენებით
4. ატვირთავს `.xctestproducts` ბანდლს ან წერს შარდის არქივს შარდის გამშვებების მიერ გამოსაყენებლად
5. გამოაქვს შარდის მატრიცა თქვენი CI სისტემისთვის
6. ინახავს <.localized_link href="/guides/features/selective-testing">შერჩევითი ტესტირების</.localized_link> გრაფს (თუ გამოიყენება), რათა შარდის გამშვებებმა არ დასჭირდეთ პროექტის ხელახლა გენერირება

### აგების პარამეტრები {#build-options}

| ფლაგი | გარემოს ცვლადი | აღწერა |
|------|---------------------|-------------|
| `--shard-max <N>` | `TUIST_TEST_SHARD_MAX` | შარდების მაქსიმალური რაოდენობა. გამოიყენება `--shard-max-duration`-თან ერთად შარდების რაოდენობის შესაზღუდად |
| `--shard-min <N>` | `TUIST_TEST_SHARD_MIN` | შარდების მინიმალური რაოდენობა |
| `--shard-total <N>` | `TUIST_TEST_SHARD_TOTAL` | შარდების ზუსტი რაოდენობა (ურთიერთგამომრიცხავია `--shard-min`/`--shard-max`-თან). სუიტის გრანულარობით, ბოლო შარდი არის საყოველთაო |
| `--shard-max-duration <MS>` | `TUIST_TEST_SHARD_MAX_DURATION` | მიზნობრივი მაქსიმალური ხანგრძლივობა თითოეული შარდისთვის მილიწამებში |
| `--shard-granularity <LEVEL>` | `TUIST_TEST_SHARD_GRANULARITY` | `module` (ნაგულისხმევი) ანაწილებს მთლიან ტესტურ მოდულებს შარდებში; `suite` ანაწილებს ინდივიდუალურ ტესტურ კლასებს უფრო დეტალური ბალანსირებისთვის |
| `--shard-reference <REF>` | `TUIST_SHARD_REFERENCE` | შარდის გეგმის უნიკალური იდენტიფიკატორი (ავტომატურად მიღებული მხარდაჭერილ CI პროვაიდერებზე) |
| `--shard-archive-path <PATH>` | `TUIST_TEST_SHARD_ARCHIVE_PATH` | გზა, სადაც Tuist წერს ოპტიმიზირებულ შარდის არქივს ტესტური პროდუქტების დისტანციურ საცავში ატვირთვის ნაცვლად |

## ტესტირების ეტაპი {#test-phase}

თითოეული შარდის გამშვები ასრულებს მისთვის განკუთვნილ ტესტებს:

```sh
tuist test --without-building
```

`--without-building` ფლაგი ეუბნება Tuist-ს, რომ გაუშვას ტესტები ადრე აგებული პროდუქტების გამოყენებით ხელახლა აგების ნაცვლად. Tuist შეცდომას აბრუნებს, თუ `TUIST_SHARD_INDEX` / `--shard-index` დაყენებულია `--without-building`-ის გარეშე.

### ტესტირების პარამეტრები {#test-options}

| ფლაგი | გარემოს ცვლადი | აღწერა |
|------|---------------------|-------------|
| `--shard-index <N>` | `TUIST_SHARD_INDEX` | შასრულებელი შარდის ნულოვანი ინდექსი |
| `--shard-plan-id <IDENTIFIER>` | `TUIST_SHARD_PLAN_ID` | აგების ეტაპის მიერ გამოცემული შარდის გეგმის ზუსტი იდენტიფიკატორი. გენერირებული პროვაიდერის გამონატანები ავტომატურად შეიცავს ამ მნიშვნელობას |
| `--shard-reference <REF>` | `TUIST_SHARD_REFERENCE` | შარდის გეგმის უნიკალური იდენტიფიკატორი (ავტომატურად მიღებული მხარდაჭერილ CI პროვაიდერებზე) |
| `--shard-archive-path <PATH>` | `TUIST_TEST_SHARD_ARCHIVE_PATH` | გზა ლოკალურად მართულ შარდის არქივამდე; Tuist ამოიღებს მას ტესტური პროდუქტების დისტანციური საცავიდან ჩამოტვირთვის ნაცვლად |

Tuist ჩამოტვირთავს `.xctestproducts` ბანდლს და ფილტრავს მას ისე, რომ შეიცავდეს მხოლოდ იმ ტესტებს, რომლებიც ამ შარდს მიენიჭა.

> [!TIP]
> **შერჩევითი ტესტირება**
>
> ტესტების შარდებად დაყოფა უპრობლემოდ მუშაობს <.localized_link href="/guides/features/selective-testing">შერჩევით ტესტირებათან</.localized_link>. შერჩევითი ტესტირების გრაფი ინახება აგების ეტაპზე და აღდგება თითოეული შარდისთვის, რათა გამშვებებმა არ საჭიროებდნენ პროექტის ხელახლა გენერირებას.

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
        run: tuist test --build-only --shard-total 5

  test:
    name: "Shard #${{ matrix.shard }}"
    needs: build
    if: toJSON(fromJSON(needs.build.outputs.matrix).shard) != '[]'
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
      - run: tuist test --without-building
```

### GitLab CI {#gitlab-ci}

Tuist ქმნის `.tuist-shard-child-pipeline.yml`-ს, რომელსაც თქვენ იწვევთ როგორც [შვილობილ პაიპლაინს](https://docs.gitlab.com/ee/ci/pipelines/downstream_pipelines.html#parent-child-pipelines). განსაზღვრეთ `.tuist-shard` შაბლონური სამუშაო, რომელსაც გენერირებული შარდის სამუშაოები გააფართოვებენ:

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
    - tuist test --build-only --shard-total 5
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
    - tuist test --without-building
```

### CircleCI {#circleci}

Tuist ქმნის `.tuist-shard-continuation.json`-ს პარამეტრებით [გაგრძელების ორბისთვის](https://circleci.com/developer/orbs/orb/circleci/continuation). `shard-plan-id` პარამეტრი უნდა იყოს გამოცხადებული თქვენს გაგრძელებულ კონფიგურაციაში:

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
            tuist test --build-only --shard-total 5
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
            tuist test --without-building

workflows:
  test:
    jobs:
      - test-shard:
          matrix:
            parameters:
              shard-index: [<< pipeline.parameters.shard-indices >>]
```

### Buildkite {#buildkite}

Tuist ქმნის `.tuist-shard-pipeline.yml`-ს ერთი ნაბიჯით თითოეული შარდისთვის. ატვირთეთ ის `buildkite-agent pipeline upload`-ის გამოყენებით:

```yaml
# pipeline.yml
steps:
  - label: "Build test shards"
    command: |
      tuist auth login
      tuist test --build-only --shard-total 5
      buildkite-agent pipeline upload .tuist-shard-pipeline.yml
    agents:
      queue: macos
```

თითოეულ გენერირებულ ნაბიჯს აქვს `TUIST_SHARD_INDEX` და `TUIST_SHARD_PLAN_ID` მითითებული მის გარემოში. დაამატეთ ტესტის ბრძანება თითოეულ შარდის ნაბიჯზე საერთო სკრიპტის გამოყენებით:

```bash
# .buildkite/shard-step.sh
#!/bin/bash
tuist auth login
tuist test --without-building
```

### Codemagic {#codemagic}

Codemagic არ უჭერს მხარს დინამიურ მატრიცულ სამუშაოებს, ამიტომ განსაზღვრეთ ცალკეული სამუშაო ნაკადი თითოეული შარდისთვის. Tuist წერს `TUIST_SHARD_MATRIX`-ს და `TUIST_SHARD_COUNT`-ს `CM_ENV` ფაილში აგების სამუშაო ნაკადში გამოსაყენებლად. Codemagic-ის `CM_ENV` არის სამუშაო ნაკადის ფარგლებში, ამიტომ შარდის გეგმის ზუსტი იდენტიფიკატორი არ კვეთს სამუშაო ნაკადის საზღვრებს; ტესტის სამუშაო ნაკადები გადადიან მითითებაზე დაფუძნებულ შარდის ძებნაზე:

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
          tuist test --build-only --shard-total 5

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
          tuist test --without-building

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

Bitrise-ზე, Tuist წერს `.tuist-shard-matrix.json`-ს (`shard_plan_id`-ის ჩათვლით) `BITRISE_DEPLOY_DIR`-ში, რაც მას ხელმისაწვდომს ხდის აგების არტეფაქტად მომდევნო პაიპლაინის ეტაპებისთვის. თითოეული ტესტის სამუშაო ნაკადი ამოიღებს გეგმის ID-ს ჩამოტვირთული არტეფაქტიდან `envman`-ის გამოყენებით, რათა ის მოხვდეს ტესტის ბრძანების გარემოში:

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
                tuist test --build-only --shard-total 5
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
                tuist test --without-building
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
> Bitrise არ უჭერს მხარს დინამიურ პარალელურ სამუშაოების შექმნას შესრულების დროს. განსაზღვრეთ ფიქსირებული რაოდენობის შარდის სამუშაო ნაკადები თქვენს პაიპლაინის ეტაპებში — ეტაპის შიგნით არსებული სამუშაო ნაკადები ავტომატურად მუშაობენ პარალელურად.

## გაზიარებული ტომები {#shared-volumes}

ნაგულისხმევად, აგების ეტაპი ტვირთავს `.xctestproducts` ბანდლს დისტანციურ საცავში და თითოეული შარდის გამშვები ჩამოტვირთავს მას. თუ თქვენი CI პროვაიდერი უჭერს მხარს **გაზიარებულ ტომებს** (მუდმივ საცავს, რომელიც მიმაგრებულია სამუშაოებზე), შეგიძლიათ სრულიად გამოტოვოთ ეს ატვირთვა/ჩამოტვირთვა ტესტური პროდუქტების გაზიარებული ფაილური სისტემის მეშვეობით გადაცემით.

ეს შეიძლება მნიშვნელოვნად შეამციროს შარდის გაშვების დრო, განსაკუთრებით დიდი ტესტური ბანდლებისთვის.

გაზიარებული ტომების გამოყენებისთვის:

1. **აგების ეტაპზე**, გადაეცით `-testProductsPath` (`--`-ის შემდეგ), რომელიც მიუთითებს გაზიარებულ ტომზე და დაამატეთ `--shard-skip-upload` დისტანციური ატვირთვის გამოტოვებისთვის:

```sh
tuist test \
  --build-only \
  --shard-total 5 \
  --shard-skip-upload \
  -- \
  -testProductsPath /path/to/shared/volume/$UNIQUE_ID/MyScheme.xctestproducts
```

2. **ტესტირების ეტაპზე**, გადაეცით იგივე `-testProductsPath`, რათა Tuist წაიკითხოს ტესტური პროდუქტები ლოკალურად მათი ჩამოტვირთვის ნაცვლად:

```sh
tuist test --without-building -- -testProductsPath /path/to/shared/volume/$UNIQUE_ID/MyScheme.xctestproducts
```

| ფლაგი | გარემოს ცვლადი | აღწერა |
|------|---------------------|-------------|
| `--shard-skip-upload` | `TUIST_TEST_SHARD_SKIP_UPLOAD` | გამოტოვოს ტესტური პროდუქტების ბანდლის ატვირთვა დისტანციურ საცავში |

## თვითმართვადი არტეფაქტები {#self-managed-artifacts}

თუ თქვენს CI პროვაიდერს უკვე აქვს არტეფაქტების ატვირთვისა და ჩამოტვირთვის ნაბიჯები, შეგიძლიათ Tuist-ს დაუტოვოთ არქივაციისა და ამოღების მართვა, ხოლო თქვენს CI-ს — ტრანსპორტირება.

1. **აგების ეტაპზე**, გადაეცით `--shard-archive-path`, რათა Tuist-მა დაწეროს თავისი ოპტიმიზირებული შარდის არქივი ლოკალურად ტესტური პროდუქტების ატვირთვის ნაცვლად:

```sh
tuist test \
  --build-only \
  --shard-total 5 \
  --shard-archive-path /tmp/shards/${UNIQUE_ID}/bundle.aar
```

2. ატვირთეთ ეს არქივი თქვენი CI-ის ნატიური არტეფაქტის ნაბიჯის გამოყენებით.

3. ყველა **ტესტირების ეტაპის** სამუშაოში, ჩამოტვირთეთ არქივი და გადაეცით იგივე გზა Tuist-ს:

```sh
tuist test \
  --without-building \
  --shard-archive-path /tmp/shards/${UNIQUE_ID}/bundle.aar
```

როდესაც `--shard-archive-path` დაყენებულია, Tuist ტოვებს ტესტური პროდუქტების დისტანციურ გადაცემას და იყენებს ლოკალურ არქივს. თუ ასევე გადასცემთ `--shard-skip-upload`, არქივის გზას ენიჭება უპირატესობა.

როდესაც გასაშვები ტესტები არ არის, მაგალითად, შერჩევითი ტესტირების გამო ყველა ტესტური მიზანი გამოტოვებულია, აგების ეტაპი გამოიტანს ცარიელ შარდულ მატრიცას და არ ქმნის არქივს. ატვირთვის ნაბიჯი შეასრულეთ მხოლოდ მაშინ, როცა მატრიცა შეიცავს შარდებს.

> [!IMPORTANT]
> გამოიყენეთ უნიკალური გზა თითოეული სამუშაო ნაკადის შესრულებისთვის (მაგ., ჩართეთ CI შესრულების ID), რათა თავიდან აიცილოთ კონფლიქტები პარალელურ შესრულებებს შორის. ასევე, გაასუფთავეთ შარდის არქივი შარდინგის დასრულების შემდეგ, რათა თავიდან აიცილოთ მოძველებული მონაცემების დაგროვება გამშვებზე.

### Namespace {#namespace}

[Namespace](https://namespace.so)-ის გამშვებები კარგად მუშაობენ GitHub Actions არტეფაქტებთან. ერთხელ დააყენეთ `TUIST_TEST_SHARD_ARCHIVE_PATH`, რათა აგების სამუშაომ დაწეროს შარდის არქივი ლოკალურად, ატვირთეთ ის და ჩამოტვირთეთ ყველა შარდულ სამუშაოში `tuist test`-ის გაშვებამდე:

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
        run: tuist test --build-only --shard-total 5
      - if: toJSON(fromJSON(steps.build.outputs.matrix).shard) != '[]'
        uses: actions/upload-artifact@v4
        with:
          name: test-shard-archive
          path: ${{ env.TUIST_TEST_SHARD_ARCHIVE_PATH }}
      - if: always()
        run: rm -rf /tmp/shards/${{ github.run_id }}

  test:
    name: "Shard #${{ matrix.shard }}"
    needs: build
    if: toJSON(fromJSON(needs.build.outputs.matrix).shard) != '[]'
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
      - run: tuist test --without-building
      - if: always()
        run: rm -rf /tmp/shards/${{ github.run_id }}
```
