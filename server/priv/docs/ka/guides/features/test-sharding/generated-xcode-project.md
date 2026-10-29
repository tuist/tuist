---
{
  "title": "Generated Xcode project",
  "titleTemplate": ":title · Test sharding · Features · Guides · Tuist",
  "description": "Distribute tests in a Tuist-generated Xcode project across multiple CI runners with Tuist Test Sharding."
}
---
# გენერირებული Xcode პროექტი {#generated-xcode-project-test-sharding}

გენერირებული პროექტებისთვის ტესტების დაყოფა იყენებს `tuist test` როგორც აგების, ისე ტესტირების ეტაპებზე.

## როგორ მუშაობს {#how-it-works}

ტესტების დაყოფა მიჰყვება ორეტაპიან სამუშაო ნაკადს:

1. **აგების ეტაპი:** Tuist კითხულობს ტესტის მოდულებს აგებული `.xctestrun` ფაილიდან და ქმნის **დაყოფის გეგმას** სერვერზე. სერვერი იყენებს ბოლო 30 დღის ისტორიულ ტესტირების დროის მონაცემებს ტესტების დასანაწილებლად დაყოფებში ისე, რომ თითოეულ დაყოფას დაახლოებით ერთი და იგივე დრო სჭირდებოდეს. აგების ეტაპი გამოაქვს **დაყოფის მატრიცა**, რომელსაც თქვენი CI სისტემა იყენებს პარალელური გამშვებების შესაქმნელად.
2. **ტესტირების ეტაპი:** თითოეული უწყვეტი ინტეგრაციის გამშვები იღებს **დაყოფის ინდექსს** და ზუსტ **დაყოფის გეგმის იდენტიფიკატორს**, შემდეგ ასრულებს ამ გეგმის ტესტების შერჩევას.

როდესაც გამოიყენება `--shard-granularity suite`, Tuist არ ტვირთავს ყველა ტესტის ბანდლს სუიტების ჩამოსათვლელად აგების ეტაპზე. ამის ნაცვლად, მიმდინარე `.xctestrun` ფაილი უზრუნველყოფს მოდულების სიას, ხოლო სერვერი ირჩევს ცნობილ სუიტებს თითოეული მოდულისთვის: თითოეული მოდულისთვის ის აერთიანებს ბოლო რამდენიმე CI გაშვების სუიტებს იმ განშტოებაზე, რომელიც აგდება. თუ მოდულს არ აქვს ისტორია ამ განშტოებაზე, სერვერი გადადის პროექტის ნაგულისხმევ განშტოებაზე. რამდენიმე გაშვების წაკითხვა ბოლოსთან შედარებით მნიშვნელოვანია, რადგან დაყოფილი გაშვება ტვირთავს ერთ ტესტის გაშვებას თითოეული დაყოფისთვის, როგორც კი დაყოფა დასრულდება, ამიტომ უახლესი გაშვება შეიცავს მხოლოდ მოდულის იმ ნაწილს, რომელიც ამ დრომდე იქნა მიღებული, და ასევე ეს ხელს უშლის შერჩევითი ტესტირების გაშვებებს დამალონ სუიტები, რომლებიც გამოტოვებული იყო ბოლო განშტოების გაშვებაში. სერვერი მაინც იყენებს ბოლო 30 დღის სუიტების დროს ხანგრძლივობების შესაფასებლად.

Tuist აბალანსებს ამ ცნობილ სუიტებს მოთხოვნილ დაყოფების რაოდენობაზე და იყენებს საბოლოო დაყოფას როგორც „ყველაფრის შემკრებს“. მაგალითად, `--shard-total 5` ქმნის დაყოფის ინდექსებს `0`-დან `4`-მდე, სადაც დაყოფის ინდექსი `4` არის „ყველაფრის შემკრები“. ჩვეულებრივი დაყოფები მუშაობენ `-only-testing`-ით მათთვის მინიჭებული სუიტებისთვის. საბოლოო დაყოფა მუშაობს `-only-testing`-ის გარეშე და გადასცემს `-skip-testing`-ს ყოველი სუიტისთვის, რომელიც მინიჭებული იყო ადრეულ დაყოფებზე, ამიტომ ის ასევე ასრულებს ახლად დამატებულ სუიტებს, სახელშეცვლილ სუიტებს ან სუიტებს, რომლებიც აკლია ისტორიულ ინვენტარს. მოდულის სიზუსტეს არ სჭირდება „ყველაფრის შემკრები“, რადგან `.xctestrun` ფაილი უზრუნველყოფს მოდულების სიას.

## აგების ეტაპი {#build-phase}

გააგენერირეთ თქვენი პროექტი, ააგეთ თქვენი ტესტები და შექმენით დაყოფის გეგმა:

```sh
tuist test --build-only --shard-total 5
```

`--build-only` ფლაგი ეუბნება Tuist-ს, რომ ააგოს ტესტები მათი გაშვების გარეშე. Tuist გამოაქვს შეცდომა, თუ გადასცემთ დაყოფის გეგმის ფლაგებს (`--shard-min`/`--shard-max`/`--shard-total`) `--build-only`-ის გარეშე.

ეს ბრძანება:
1. აგენერირებს Xcode პროექტს თქვენი მანიფესტებიდან
2. აგებს თქვენს ტესტებს
3. ქმნის დაყოფის გეგმას Tuist სერვერზე ისტორიული დროის მონაცემების გამოყენებით
4. ტვირთავს `.xctestproducts` ბანდლს ან წერს დაყოფის არქივს დაყოფის გამშვებების მიერ გამოყენებისთვის
5. გამოაქვს დაყოფის მატრიცა თქვენი CI სისტემისთვის
6. ინახავს <.localized_link href="/guides/features/selective-testing">შერჩევითი ტესტირების</.localized_link> გრაფს (თუ გამოიყენება), რათა დაყოფის გამშვებებმა არ საჭიროებდნენ პროექტის ხელახლა გენერირებას

### აგების პარამეტრები {#build-options}

| ფლაგი | გარემოს ცვლადი | აღწერა |
|------|---------------------|-------------|
| `--shard-max <N>` | `TUIST_TEST_SHARD_MAX` | დაყოფების მაქსიმალური რაოდენობა. გამოიყენება `--shard-max-duration`-თან ერთად დაყოფების რაოდენობის შესაზღუდად |
| `--shard-min <N>` | `TUIST_TEST_SHARD_MIN` | დაყოფების მინიმალური რაოდენობა |
| `--shard-total <N>` | `TUIST_TEST_SHARD_TOTAL` | დაყოფების ზუსტი რაოდენობა (ურთიერთგამომრიცხავია `--shard-min`/`--shard-max`-თან). სუიტის სიზუსტით, საბოლოო დაყოფა არის „ყველაფრის შემკრები“ |
| `--shard-max-duration <MS>` | `TUIST_TEST_SHARD_MAX_DURATION` | მიზნობრივი მაქსიმალური ხანგრძლივობა თითოეული დაყოფისთვის მილიწამებში |
| `--shard-granularity <LEVEL>` | `TUIST_TEST_SHARD_GRANULARITY` | `module` (ნაგულისხმევი) ანაწილებს მთლიან ტესტის მოდულებს დაყოფებზე; `suite` ანაწილებს ინდივიდუალურ ტესტის კლასებს უფრო წვრილმარცვლოვანი ბალანსირებისთვის |
| `--shard-reference <REF>` | `TUIST_SHARD_REFERENCE` | უნიკალური იდენტიფიკატორი დაყოფის გეგმისთვის (ავტომატურად მიღებული მხარდაჭერილ CI პროვაიდერებზე) |
| `--shard-archive-path <PATH>` | `TUIST_TEST_SHARD_ARCHIVE_PATH` | გზა, სადაც Tuist წერს ოპტიმიზირებულ დაყოფის არქივს ტესტის პროდუქტების დისტანციურ საცავში ატვირთვის ნაცვლად |

## ტესტირების ეტაპი {#test-phase}

თითოეული დაყოფის გამშვები ასრულებს მისთვის მინიჭებულ ტესტებს:

```sh
tuist test --without-building
```

`--without-building` ფლაგი ეუბნება Tuist-ს, რომ გაუშვას ტესტები ადრე აგებული პროდუქტების გამოყენებით ხელახლა აგების ნაცვლად. Tuist გამოაქვს შეცდომა, თუ `TUIST_SHARD_INDEX` / `--shard-index` დაყენებულია `--without-building`-ის გარეშე.

### ტესტირების პარამეტრები {#test-options}

| ფლაგი | გარემოს ცვლადი | აღწერა |
|------|---------------------|-------------|
| `--shard-index <N>` | `TUIST_SHARD_INDEX` | ნულოვანი ინდექსის დაყოფა, რომელიც უნდა შესრულდეს |
| `--shard-plan-id <IDENTIFIER>` | `TUIST_SHARD_PLAN_ID` | ზუსტი დაყოფის გეგმის იდენტიფიკატორი, რომელიც გამოიცემა აგების ეტაპზე. გენერირებული პროვაიდერის გამოტანები ავტომატურად შეიცავს ამ მნიშვნელობას |
| `--shard-reference <REF>` | `TUIST_SHARD_REFERENCE` | უნიკალური იდენტიფიკატორი დაყოფის გეგმისთვის (ავტომატურად მიღებული მხარდაჭერილ CI პროვაიდერებზე) |
| `--shard-archive-path <PATH>` | `TUIST_TEST_SHARD_ARCHIVE_PATH` | გზა ადგილობრივად მართულ დაყოფის არქივამდე; Tuist ამოიღებს მას ტესტის პროდუქტების დისტანციური საცავიდან ჩამოტვირთვის ნაცვლად |

Tuist ჩამოტვირთავს `.xctestproducts` ბანდლს და ფილტრავს მას ისე, რომ შეიცავდეს მხოლოდ იმ ტესტებს, რომლებიც ამ დაყოფას მიენიჭა.

> [!TIP]
> **შერჩევითი ტესტირება**
>
> ტესტების დაყოფა უპრობლემოდ მუშაობს <.localized_link href="/guides/features/selective-testing">შერჩევით ტესტირებათან</.localized_link>. შერჩევითი ტესტირების გრაფი ინახება აგების ეტაპზე და აღდგება თითოეული დაყოფისთვის, რათა გამშვებებმა არ მოუწიოთ პროექტის ხელახლა გენერირება.

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

გამოიყენეთ მატრიცის სტრატეგია დაყოფების პარალელურად გასაშვებად:

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

Tuist ქმნის `.tuist-shard-child-pipeline.yml`-ს, რომელსაც იწვევთ როგორც [შვილობილ პაიპლაინს](https://docs.gitlab.com/ee/ci/pipelines/downstream_pipelines.html#parent-child-pipelines). განსაზღვრეთ `.tuist-shard` შაბლონური სამუშაო, რომელსაც გაფართოებული დაყოფის სამუშაოები გამოიყენებენ:

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

Tuist ქმნის `.tuist-shard-pipeline.yml`-ს ერთი ნაბიჯით თითოეული დაყოფისთვის. ატვირთეთ ის `buildkite-agent pipeline upload`-ის გამოყენებით:

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

თითოეულ გენერირებულ ნაბიჯს აქვს `TUIST_SHARD_INDEX` და `TUIST_SHARD_PLAN_ID` მითითებული გარემოში. დაამატეთ ტესტის ბრძანება თითოეულ დაყოფის ნაბიჯზე საერთო სკრიპტის გამოყენებით:

```bash
# .buildkite/shard-step.sh
#!/bin/bash
tuist auth login
tuist test --without-building
```

### Codemagic {#codemagic}

Codemagic არ უჭერს მხარს დინამიურ მატრიცულ სამუშაოებს, ამიტომ განსაზღვრეთ ცალკეული სამუშაო ნაკადი თითოეული დაყოფისთვის. Tuist წერს `TUIST_SHARD_MATRIX`-ს და `TUIST_SHARD_COUNT`-ს `CM_ENV` ფაილში აგების სამუშაო ნაკადში გამოყენებისთვის. Codemagic-ის `CM_ENV` არის სამუშაო ნაკადის მასშტაბის, ამიტომ ზუსტი დაყოფის გეგმის იდენტიფიკატორი არ კვეთს სამუშაო ნაკადის საზღვრებს; ტესტის სამუშაო ნაკადები გადადიან მითითებაზე დაფუძნებულ დაყოფის ძებნაზე:

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

Bitrise-ზე, Tuist წერს `.tuist-shard-matrix.json`-ს (`shard_plan_id`-ის ჩათვლით) `BITRISE_DEPLOY_DIR`-ში, რაც ხელმისაწვდომს ხდის მას აგების არტეფაქტად შემდგომი პაიპლაინის ეტაპებისთვის. თითოეული ტესტის სამუშაო ნაკადი ამოიღებს გეგმის ID-ს ჩამოტვირთული არტეფაქტიდან `envman`-ის გამოყენებით, რათა ის მოხვდეს ტესტის ბრძანების გარემოში:

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
> Bitrise არ უჭერს მხარს დინამიურ პარალელურ სამუშაოების შექმნას შესრულების დროს. განსაზღვრეთ ფიქსირებული რაოდენობის დაყოფის სამუშაო ნაკადები თქვენს პაიპლაინის ეტაპებში — ეტაპის შიგნით სამუშაო ნაკადები ავტომატურად პარალელურად მუშაობენ.

## გაზიარებული ტომები {#shared-volumes}

ნაგულისხმევად, აგების ეტაპი ტვირთავს `.xctestproducts` ბანდლს დისტანციურ საცავში და თითოეული დაყოფის გამშვები ჩამოტვირთავს მას. თუ თქვენი CI პროვაიდერი უჭერს მხარს **გაზიარებულ ტომებს** (მუდმივი საცავი, რომელიც მიმაგრებულია სამუშაოებს შორის), შეგიძლიათ სრულიად გამოტოვოთ ეს ატვირთვა/ჩამოტვირთვა ტესტის პროდუქტების გაზიარებული ფაილური სისტემის მეშვეობით გადაცემით.

ეს შეიძლება მნიშვნელოვნად შეამციროს დაყოფის გაშვების დრო, განსაკუთრებით დიდი ტესტის ბანდლებისთვის.

გაზიარებული ტომების გამოყენებისთვის:

1. **აგების ეტაპზე**, გადაეცით `-testProductsPath` (`--`-ის შემდეგ), რომელიც მიუთითებს გაზიარებულ ტომზე და დაამატეთ `--shard-skip-upload` დისტანციური ატვირთვის გამოსატოვებლად:

```sh
tuist test \
  --build-only \
  --shard-total 5 \
  --shard-skip-upload \
  -- \
  -testProductsPath /path/to/shared/volume/$UNIQUE_ID/MyScheme.xctestproducts
```

2. **ტესტირების ეტაპზე**, გადაეცით იგივე `-testProductsPath`, რათა Tuist წაიკითხოს ტესტის პროდუქტები ადგილობრივად ჩამოტვირთვის ნაცვლად:

```sh
tuist test --without-building -- -testProductsPath /path/to/shared/volume/$UNIQUE_ID/MyScheme.xctestproducts
```

| ფლაგი | გარემოს ცვლადი | აღწერა |
|------|---------------------|-------------|
| `--shard-skip-upload` | `TUIST_TEST_SHARD_SKIP_UPLOAD` | გამოტოვეთ ტესტის პროდუქტების ბანდლის ატვირთვა დისტანციურ საცავში |

## თვითმართვადი არტეფაქტები {#self-managed-artifacts}

თუ თქვენს CI პროვაიდერს უკვე აქვს არტეფაქტების ატვირთვისა და ჩამოტვირთვის ნაბიჯები, შეგიძლიათ Tuist-ს დაავალოთ არქივირება და ამოღება, ხოლო თქვენს CI-ს — ტრანსპორტირება.

1. **აგების ეტაპზე**, გადაეცით `--shard-archive-path`, რათა Tuist-მა ჩაწეროს ოპტიმიზირებული დაყოფის არქივი ადგილობრივად ტესტის პროდუქტების ატვირთვის ნაცვლად:

```sh
tuist test \
  --build-only \
  --shard-total 5 \
  --shard-archive-path /tmp/shards/${UNIQUE_ID}/bundle.aar
```

2. ატვირთეთ ეს არქივი თქვენი CI-ის ნატიური არტეფაქტის ნაბიჯის გამოყენებით.

3. თითოეულ **ტესტირების ეტაპის** სამუშაოში, ჩამოტვირთეთ არქივი და გადაეცით იგივე გზა Tuist-ს:

```sh
tuist test \
  --without-building \
  --shard-archive-path /tmp/shards/${UNIQUE_ID}/bundle.aar
```

როდესაც `--shard-archive-path` დაყენებულია, Tuist ტოვებს დისტანციურ ტესტ-პროდუქტების გადაცემას და იყენებს ადგილობრივ არქივს. თუ ასევე გადასცემთ `--shard-skip-upload`, არქივის გზას ენიჭება უპირატესობა.

როდესაც გასაშვები ტესტები არ არის, მაგალითად, სელექციური ტესტირების გამო ყველა ტესტის მიზანი გამოტოვებულია, აგების ეტაპი გამოიტანს ცარიელ დაყოფის მატრიცას და არ ჩაწერს არქივს. ატვირთვის ნაბიჯი გაუშვით მხოლოდ მაშინ, როცა მატრიცა შეიცავს დაყოფებს.

> [!IMPORTANT]
> გამოიყენეთ უნიკალური გზა თითოეული სამუშაო ნაკადის გაშვებისთვის (მაგ., ჩართეთ CI გაშვების ID), რათა თავიდან აიცილოთ კონფლიქტები პარალელურ გაშვებებს შორის. ასევე, გაასუფთავეთ დაყოფის არქივი დაყოფის დასრულების შემდეგ, რათა თავიდან აიცილოთ მოძველებული მონაცემების დაგროვება გამშვებზე.

### Namespace {#namespace}

[Namespace](https://namespace.so) გამშვებები კარგად მუშაობენ GitHub Actions არტეფაქტებთან. ერთხელ დააყენეთ `TUIST_TEST_SHARD_ARCHIVE_PATH`, რათა აგების სამუშაომ ჩაწეროს დაყოფის არქივი ადგილობრივად, ატვირთოთ ის და ჩამოტვირთოთ თითოეულ დაყოფის სამუშაოში `tuist test`-ის გაშვებამდე:

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
