---
{
  "title": "გენერირებული Xcode პროექტი",
  "titleTemplate": ":title · ტესტების დაშლა · ფუნქციები · სახელმძღვანელოები · Tuist",
  "description": "გაანაწილეთ ტესტები Tuist-ით გენერირებულ Xcode პროექტში რამდენიმე CI გამშვებზე Tuist Test Sharding-ის გამოყენებით."
}
---
# გენერირებული Xcode პროექტი {#generated-xcode-project-test-sharding}

გენერირებული პროექტების ტესტების დაყოფა იყენებს `tuist test` როგორც კომპილაციის, ისე ტესტირების ეტაპებზე.

## როგორ მუშაობს {#how-it-works}

ტესტების დაყოფა მიჰყვება ორეტაპიან სამუშაო პროცესს:

1. **კომპილაციის ეტაპი:** Tuist კითხულობს ტესტის მოდულებს აწყობილი `.xctestrun` ფაილიდან და ქმნის **დაყოფის გეგმას** სერვერზე. სერვერი იყენებს ბოლო 30 დღის ისტორიულ ტესტების დროის მონაცემებს, რათა გაანაწილოს ტესტები ნაწილებად ისე, რომ თითოეულმა ნაწილმა დაახლოებით ერთნაირი დრო დახარჯოს. კომპილაციის ეტაპი გამოაქვს **დაყოფის მატრიცა**, რომელსაც თქვენი CI სისტემა იყენებს პარალელური გამშვებების შესაქმნელად.
2. **ტესტირების ეტაპი:** თითოეული უწყვეტი ინტეგრაციის გამშვები იღებს **ნაწილის ინდექსს** და ზუსტ **ნაწილის გეგმის იდენტიფიკატორს**, შემდეგ ასრულებს ამ გეგმის ტესტების შერჩევას.

როდესაც გამოიყენება `--shard-granularity suite`, სერვერი იყენებს სუიტებს, რომლებიც ბოლო CI გაშვებებმა თქვენს ბრენჩზე შეატყობინეს თითოეული მოდულისთვის მიმდინარე `.xctestrun`-ში, ხოლო ბრენჩის ისტორიის არმქონე მოდულებისთვის გადადის პროექტის საწყის ბრენჩზე. რამდენიმე გაშვების გაერთიანება ინარჩუნებს სუიტებს, რომლებიც დაყოფილმა ან შერჩევითმა გაშვებამ გამოტოვა ბოლო ანგარიშში. სერვერი იყენებს ბოლო 30 დღის სუიტების დროის მონაცემებს ხანგრძლივობის შესაფასებლად.

Tuist აბალანსებს ცნობილ სუიტებს მოთხოვნილი ნაწილების რაოდენობაზე და იყენებს ბოლო ნაწილს, როგორც ყველაფრის შემკრებს. მაგალითად, `--shard-total 5` ქმნის ნაწილის ინდექსებს `0`-დან `4`-მდე, სადაც ნაწილის ინდექსი `4` არის ყველაფრის შემკრები. ჩვეულებრივი ნაწილები გაშვებულია `-only-testing`-ით მათთვის განკუთვნილი სუიტებისთვის. ბოლო ნაწილი გაშვებულია `-only-testing`-ის გარეშე და გადასცემს `-skip-testing`-ს ყოველი სუიტისთვის, რომელიც განაწილებულია ადრეულ ნაწილებზე, ამიტომ ის ასევე ასრულებს ახლად დამატებულ სუიტებს, სახელშეცვლილ სუიტებს ან სუიტებს, რომლებიც აკლია ისტორიულ ინვენტარს. მოდულის დონის დაყოფას არ სჭირდება ყველაფრის შემკრები, რადგან `.xctestrun` ფაილი უზრუნველყოფს მოდულების სიას.

## კომპილაციის ეტაპი {#build-phase}

გენერირეთ თქვენი პროექტი, ააწყვეთ თქვენი ტესტები და შექმენით დაყოფის გეგმა:

```sh
tuist test --build-only --shard-total 5
```

`--build-only` ფლაგი ეუბნება Tuist-ს, რომ ააწყოს ტესტები მათი გაშვების გარეშე. Tuist შეცდომას გამოიტანს, თუ გადასცემთ დაყოფის გეგმის ფლაგებს (`--shard-min`/`--shard-max`/`--shard-total`) `--build-only`-ის გარეშე.

ეს ბრძანება:
1. აგენერირებს Xcode პროექტს თქვენი მანიფესტებიდან
2. აწყობს თქვენს ტესტებს
3. ქმნის დაყოფის გეგმას Tuist სერვერზე ისტორიული დროის მონაცემების გამოყენებით
4. ატვირთავს `.xctestproducts` ბანდლს ან წერს ნაწილის არქივს ნაწილის გამშვებებისთვის გამოსაყენებლად
5. გამოაქვს დაყოფის მატრიცა თქვენი CI სისტემისთვის
6. ინახავს <.localized_link href="/guides/features/selective-testing">შერჩევითი ტესტირების</.localized_link> გრაფს (თუ applicable) ისე, რომ ნაწილის გამშვებებმა არ საჭიროებდნენ პროექტის ხელახლა გენერირებას

<!-- @snippet: ./_xcode-build-options -->

## ტესტირების ეტაპი {#test-phase}

თითოეული ნაწილის გამშვები ასრულებს მისთვის განკუთვნილ ტესტებს:

```sh
tuist test --without-building
```

`--without-building` ფლაგი ეუბნება Tuist-ს, რომ გაუშვას ტესტები ადრე აწყობილი პროდუქტების გამოყენებით ხელახლა აწყობის ნაცვლად. Tuist შეცდომას გამოიტანს, თუ `TUIST_SHARD_INDEX` / `--shard-index` დაყენებულია `--without-building`-ის გარეშე.

<!-- @snippet: ./_xcode-test-options -->

> [!TIP]
> **შერჩევითი ტესტირება**
>
> ტესტების დაყოფა უპრობლემოდ მუშაობს <.localized_link href="/guides/features/selective-testing">შერჩევით ტესტირებათან</.localized_link>. შერჩევითი ტესტირების გრაფი ინახება კომპილაციის ეტაპზე და აღდგება თითოეული ნაწილისთვის, ამიტომ გამშვებებს არ სჭირდებათ პროექტის ხელახლა გენერირება.

## უწყვეტი ინტეგრაცია {#continuous-integration}

<!-- @snippet: ./_ci-providers -->

### GitHub Actions {#github-actions}

გამოიყენეთ მატრიცის სტრატეგია ნაწილების პარალელურად გასაშვებად:

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

Tuist აგენერირებს `.tuist-shard-child-pipeline.yml`-ს, რომელსაც თქვენ იწყებთ, როგორც [შვილ პაიპლაინს](https://docs.gitlab.com/ci/pipelines/downstream_pipelines/#parent-child-pipelines). განსაზღვრეთ `.tuist-shard` შაბლონური სამუშაო, რომელსაც გენერირებული ნაწილის სამუშაოები გააგრძელებენ:

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

Tuist აგენერირებს `.tuist-shard-continuation.json`-ს პარამეტრებით [გაგრძელების orb-ისთვის](https://circleci.com/developer/orbs/orb/circleci/continuation). `shard-plan-id` პარამეტრი უნდა იყოს გამოცხადებული თქვენს გაგრძელებულ კონფიგურაციაში:

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

Tuist აგენერირებს `.tuist-shard-pipeline.yml`-ს ერთი ნაბიჯით თითოეული ნაწილისთვის. ატვირთეთ ის `buildkite-agent pipeline upload`-ით:

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

თითოეულ გენერირებულ ნაბიჯს აქვს `TUIST_SHARD_INDEX` და `TUIST_SHARD_PLAN_ID` დაყენებული მის გარემოში. დაამატეთ ტესტის ბრძანება თითოეულ ნაწილის ნაბიჯზე საერთო სკრიპტის გამოყენებით:

```bash
# .buildkite/shard-step.sh
#!/bin/bash
tuist auth login
tuist test --without-building
```

### Codemagic {#codemagic}

Codemagic არ უჭერს მხარს დინამიურ მატრიცულ სამუშაოებს, ამიტომ განსაზღვრეთ ცალკეული სამუშაო ნაკადი თითოეული ნაწილისთვის. Tuist წერს `TUIST_SHARD_MATRIX`-ს და `TUIST_SHARD_COUNT`-ს `CM_ENV` ფაილში კომპილაციის სამუშაო ნაკადში გამოსაყენებლად. Codemagic-ის `CM_ENV` არის სამუშაო ნაკადის მასშტაბის, ამიტომ ზუსტი ნაწილის გეგმის იდენტიფიკატორი არ კვეთს სამუშაო ნაკადის საზღვრებს; ტესტირების სამუშაო ნაკადები გადადიან მითითებაზე დაფუძნებულ ნაწილის ძიებაზე:

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

Bitrise-ზე, Tuist წერს `.tuist-shard-matrix.json`-ს (`shard_plan_id`-ის ჩათვლით) `BITRISE_DEPLOY_DIR`-ში, რაც ხდის მას ხელმისაწვდომს, როგორც აწყობის არტეფაქტს ქვემოთ მომდევნო პაიპლაინის ეტაპებისთვის. თითოეული ტესტირების სამუშაო ნაკადი ამოიღებს გეგმის ID-ს ჩამოტვირთული არტეფაქტიდან `envman`-ის გამოყენებით, რათა ის მოხვდეს ტესტის ბრძანების გარემოში:

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
> Bitrise არ უჭერს მხარს დინამიურ პარალელურ სამუშაოების შექმნას შესრულების დროს. განსაზღვრეთ ფიქსირებული რაოდენობის ნაწილის სამუშაო ნაკადები თქვენს პაიპლაინის ეტაპებში — ეტაპის შიგნით არსებული სამუშაო ნაკადები ავტომატურად გაშვებულია პარალელურად.

## გაზიარებული ტომები {#shared-volumes}

ნაგულისხმევად, კომპილაციის ეტაპი ტვირთავს `.xctestproducts` ბანდლს შორეულ საცავში და თითოეული ნაწილის გამშვები ჩამოტვირთავს მას. თუ თქვენი CI პროვაიდერი უჭერს მხარს **გაზიარებულ ტომებს** (მუდმივი საცავი, რომელიც მიმაგრებულია სამუშაოებს შორის), შეგიძლიათ სრულიად გამოტოვოთ ეს ატვირთვა/ჩამოტვირთვა ტესტის პროდუქტების გაზიარებული ფაილური სისტემის მეშვეობით გადაცემით.

ეს შეიძლება მნიშვნელოვნად შეამციროს ნაწილის გაშვების დრო, განსაკუთრებით დიდი ტესტის ბანდლებისთვის.

გაზიარებული ტომების გამოყენება:

1. **კომპილაციის ეტაპზე**, გადაეცით `-testProductsPath` (`--`-ის შემდეგ), რომელიც მიუთითებს გაზიარებულ ტომზე და დაამატეთ `--shard-skip-upload` შორეული ატვირთვის გამოსატოვებლად:

```sh
tuist test \
  --build-only \
  --shard-total 5 \
  --shard-skip-upload \
  -- \
  -testProductsPath /path/to/shared/volume/$UNIQUE_ID/MyScheme.xctestproducts
```

2. **ტესტირების ეტაპზე**, გადაეცით იგივე `-testProductsPath`, რათა Tuist წაიკითხოს ტესტის პროდუქტები ლოკალურად ჩამოტვირთვის ნაცვლად:

```sh
tuist test --without-building -- -testProductsPath /path/to/shared/volume/$UNIQUE_ID/MyScheme.xctestproducts
```

| ფლაგი | გარემოს ცვლადი | აღწერა |
|------|---------------------|-------------|
| `--shard-skip-upload` | `TUIST_TEST_SHARD_SKIP_UPLOAD` | გამოტოვეთ ტესტის პროდუქტების ბანდლის შორეულ საცავში ატვირთვა |

## თვითმართვადი არტეფაქტები {#self-managed-artifacts}

თუ თქვენს CI პროვაიდერს უკვე აქვს არტეფაქტების ატვირთვისა და ჩამოტვირთვის ეტაპები, შეგიძლიათ Tuist-ს მიაწოდოთ არქივაციისა და ამოღების მართვა, ხოლო თქვენმა CI-მ გადაზიდვა შეასრულოს.

1. **კომპილაციის ეტაპზე**, გადაეცით `--shard-archive-path`, რათა Tuist-მა დაწეროს ოპტიმიზირებული ნაწილის არქივი ლოკალურად ტესტის პროდუქტების ატვირთვის ნაცვლად:

```sh
tuist test \
  --build-only \
  --shard-total 5 \
  --shard-archive-path /tmp/shards/${UNIQUE_ID}/bundle.aar
```

2. ატვირთეთ ეს არქივი თქვენი CI-ის ნატიური არტეფაქტის ეტაპის გამოყენებით.

3. თითოეულ **ტესტირების ეტაპის** სამუშაოში, ჩამოტვირთეთ არქივი და გადაეცით იგივე გზა უკან Tuist-ს:

```sh
tuist test \
  --without-building \
  --shard-archive-path /tmp/shards/${UNIQUE_ID}/bundle.aar
```

როდესაც `--shard-archive-path` დაყენებულია, Tuist ტოვებს შორეულ ტესტ-პროდუქტების გადაცემას და იყენებს ლოკალურ არქივს. თუ ასევე გადასცემთ `--shard-skip-upload`, არქივის გზას ენიჭება უპირატესობა.

როდესაც გასაშვები ტესტები არ არის, მაგალითად, იმიტომ რომ შერჩევითმა ტესტირებამ გამოტოვა ყველა ტესტის მიზანი, კომპილაციის ეტაპი გამოიტანს ცარიელ ნაწილის მატრიცას და არ წერს არქივს. ატვირთვის ეტაპი გაუშვით მხოლოდ მაშინ, როდესაც მატრიცა შეიცავს ნაწილებს.

> [!IMPORTANT]
> გამოიყენეთ უნიკალური გზა თითოეული სამუშაო ნაკადის გაშვებისთვის (მაგ., ჩართეთ CI გაშვების ID), რათა თავიდან აიცილოთ კონფლიქტები პარალელურ გაშვებებს შორის. ასევე, გაასუფთავეთ ნაწილის არქივი ნაწილობრივი გაშვების დასრულების შემდეგ, რათა თავიდან აიცილოთ მოძველებული მონაცემების დაგროვება გამშვებზე.

### Namespace {#namespace}

[Namespace](https://namespace.so) გამშვებები კარგად მუშაობენ GitHub Actions არტეფაქტებთან. დააყენეთ `TUIST_TEST_SHARD_ARCHIVE_PATH` ერთხელ, რათა აწყობის სამუშაომ დაწეროს ნაწილის არქივი ლოკალურად, ატვირთოთ ის და ჩამოტვირთოთ თითოეულ ნაწილის სამუშაოში `tuist test`-ის გაშვებამდე:

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
