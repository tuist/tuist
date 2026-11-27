---
{
  "title": "გენერირებული Xcode პროექტი",
  "titleTemplate": ":title · ტესტების შარდინგი · ფუნქციები · სახელმძღვანელოები · Tuist",
  "description": "Tuist-ის მიერ გენერირებულ Xcode პროექტში ტესტების რამდენიმე CI გამშვებზე გადანაწილება Tuist Test Sharding-ით."
}
---
# გენერირებული Xcode პროექტი {#generated-xcode-project-test-sharding}

გენერირებული პროექტების ტესტების დაყოფა იყენებს `tuist test` როგორც აგების, ისე ტესტირების ეტაპებზე.

## როგორ მუშაობს {#how-it-works}

ტესტების დაყოფა მიჰყვება ორეტაპიან სამუშაო პროცესს:

1. **აგების ეტაპი:** Tuist კითხულობს ტესტის მოდულებს აგებული `.xctestrun` ფაილიდან და ქმნის **დაყოფის გეგმას** სერვერზე. სერვერი იყენებს ბოლო 30 დღის ისტორიულ ტესტირების დროის მონაცემებს, რათა გაანაწილოს ტესტები დაყოფებში ისე, რომ თითოეულმა დაყოფამ დაახლოებით თანაბარი დრო დახარჯოს. აგების ეტაპი გამოაქვს **დაყოფის მატრიცა**, რომელსაც თქვენი CI სისტემა იყენებს პარალელური გამშვებების შესაქმნელად.
2. **ტესტირების ეტაპი:** თითოეული უწყვეტი ინტეგრაციის გამშვები იღებს **დაყოფის ინდექსს** და ზუსტ **დაყოფის გეგმის იდენტიფიკატორს**, შემდეგ ასრულებს ამ გეგმის ტესტების შერჩევას.

როდესაც გამოიყენება `--shard-granularity suite`, სერვერი იყენებს იმ სუიტებს, რომლებიც ბოლო CI გაშვებებმა თქვენს ბრენჩზე შეატყობინეს თითოეული მოდულისთვის მიმდინარე `.xctestrun`-ში, ხოლო ბრენჩის ისტორიის არმქონე მოდულებისთვის გადადის პროექტის ნაგულისხმევ ბრენჩზე. რამდენიმე გაშვების გაერთიანება ინარჩუნებს იმ სუიტებს, რომლებიც დაყოფილმა ან შერჩევითმა გაშვებამ ვერ მოხვდა ბოლო ანგარიშში. სერვერი იყენებს ბოლო 30 დღის სუიტების დროის მონაცემებს ხანგრძლივობის შესაფასებლად.

Tuist აბალანსებს ცნობილ სუიტებს მოთხოვნილი დაყოფების რაოდენობაზე და იყენებს ბოლო დაყოფას საყოველთაოდ. მაგალითად, `--shard-total 5` წარმოქმნის დაყოფის ინდექსებს `0`-დან `4`-მდე, სადაც დაყოფის ინდექსი `4` არის საყოველთაო. ჩვეულებრივი დაყოფები გადიან `-only-testing`-ით მათთვის განკუთვნილი სუიტებისთვის. ბოლო დაყოფა გადის `-only-testing`-ის გარეშე და ატარებს `-skip-testing` ყოველი სუიტისთვის, რომელიც ადრეულ დაყოფებს მიენიჭა, რითაც ასევე ასრულებს ახლად დამატებულ სუიტებს, სახელშეცვლილ სუიტებს ან ისტორიული ინვენტარიდან ამოვარდნილ სუიტებს. მოდულის დონის დაყოფას არ სჭირდება საყოველთაო დაყოფა, რადგან `.xctestrun` ფაილი უზრუნველყოფს მოდულების სიას.

## აგების ეტაპი {#build-phase}

გააგენერეთ თქვენი პროექტი, ააგეთ თქვენი ტესტები და შექმენით დაყოფის გეგმა:

```sh
tuist test --build-only --shard-total 5
```

`--build-only` ფლაგი ეუბნება Tuist-ს, რომ ააგოს ტესტები მათი გაშვების გარეშე. Tuist შეცდომას აბრუნებს, თუ დაყოფის გეგმის ფლაგებს (`--shard-min`/`--shard-max`/`--shard-total`) გადასცემთ `--build-only`-ის გარეშე.

ეს ბრძანება:
1. აგენერებს Xcode პროექტს თქვენი მანიფესტებიდან
2. აგებს თქვენს ტესტებს
3. ქმნის დაყოფის გეგმას Tuist სერვერზე ისტორიული დროის მონაცემების გამოყენებით
4. ატვირთავს `.xctestproducts` ბანდლს ან წერს დაყოფის არქივს დაყოფის გამშვებებისთვის
5. გამოაქვს დაყოფის მატრიცა თქვენი CI სისტემისთვის
6. ინახავს <.localized_link href="/guides/features/selective-testing">შერჩევითი ტესტირების</.localized_link> გრაფს (თუ applicable), რათა დაყოფის გამშვებებმა არ დასჭირდეთ პროექტის ხელახლა გენერირება

<!-- @snippet: ./_xcode-build-options -->

## ტესტირების ეტაპი {#test-phase}

თითოეული დაყოფის გამშვები ასრულებს მისთვის განკუთვნილ ტესტებს:

```sh
tuist test --without-building
```

`--without-building` ფლაგი ეუბნება Tuist-ს, რომ გაუშვას ტესტები ადრე აგებული პროდუქტების გამოყენებით ხელახლა აგების ნაცვლად. Tuist შეცდომას აბრუნებს, თუ `TUIST_SHARD_INDEX` / `--shard-index` დაყენებულია `--without-building`-ის გარეშე.

<!-- @snippet: ./_xcode-test-options -->

> [!TIP]
> **შერჩევითი ტესტირება**
>
> ტესტების დაყოფა უპრობლემოდ მუშაობს <.localized_link href="/guides/features/selective-testing">შერჩევით ტესტირებათან</.localized_link>. შერჩევითი ტესტირების გრაფი ინახება აგების ეტაპზე და აღდგება თითოეული დაყოფისთვის, რითაც გამშვებებს არ სჭირდებათ პროექტის ხელახლა გენერირება.

## უწყვეტი ინტეგრაცია {#continuous-integration}

<!-- @snippet: ./_ci-providers -->

### GitHub Actions {#github-actions}

გამოიყენეთ მატრიცული სტრატეგია დაყოფების პარალელურად გასაშვებად:

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

Tuist აგენერებს `.tuist-shard-child-pipeline.yml`-ს, რომელსაც იწვევთ როგორც [შვილობილ პაიპლაინს](https://docs.gitlab.com/ci/pipelines/downstream_pipelines/#parent-child-pipelines). განსაზღვრეთ `.tuist-shard` შაბლონური სამუშაო, რომელსაც გენერირებული დაყოფის სამუშაოები გააფართოებენ:

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

Tuist აგენერებს `.tuist-shard-continuation.json`-ს პარამეტრებით [continuation orb](https://circleci.com/developer/orbs/orb/circleci/continuation)-ისთვის. `shard-plan-id` პარამეტრი უნდა იყოს გამოცხადებული თქვენს გაგრძელებულ კონფიგურაციაში:

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

Tuist აგენერებს `.tuist-shard-pipeline.yml`-ს ერთი ნაბიჯით თითოეული დაყოფისთვის. ატვირთეთ ის `buildkite-agent pipeline upload`-ით:

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

თითოეულ გენერირებულ ნაბიჯს აქვს `TUIST_SHARD_INDEX` და `TUIST_SHARD_PLAN_ID` გარემოში. დაამატეთ ტესტის ბრძანება თითოეულ დაყოფის ნაბიჯზე საერთო სკრიპტის გამოყენებით:

```bash
# .buildkite/shard-step.sh
#!/bin/bash
tuist auth login
tuist test --without-building
```

### Codemagic {#codemagic}

Codemagic არ უჭერს მხარს დინამიურ მატრიცულ სამუშაოებს, ამიტომ განსაზღვრეთ ცალკეული სამუშაო ნაკადი თითოეული დაყოფისთვის. Tuist წერს `TUIST_SHARD_MATRIX`-ს და `TUIST_SHARD_COUNT`-ს `CM_ENV` ფაილში აგების სამუშაო ნაკადში გამოყენებისთვის. Codemagic-ის `CM_ENV` არის სამუშაო ნაკადის მასშტაბის, ამიტომ ზუსტი დაყოფის გეგმის იდენტიფიკატორი არ კვეთს სამუშაო ნაკადის საზღვრებს; ტესტირების სამუშაო ნაკადები გადადიან მითითებაზე დაფუძნებულ დაყოფის ძიებაზე:

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

Bitrise-ზე Tuist წერს `.tuist-shard-matrix.json`-ს (`shard_plan_id`-ის ჩათვლით) `BITRISE_DEPLOY_DIR`-ში, რითაც ის ხელმისაწვდომი ხდება აგების არტეფაქტად შემდგომი პაიპლაინის ეტაპებისთვის. თითოეული ტესტირების სამუშაო ნაკადი ამოიღებს გეგმის ID-ს ჩამოტვირთული არტეფაქტიდან `envman`-ის გამოყენებით, რათა ის მოხვდეს ტესტის ბრძანების გარემოში:

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
> Bitrise არ უჭერს მხარს დინამიურ პარალელურ სამუშაოების შექმნას შესრულების დროს. განსაზღვრეთ ფიქსირებული რაოდენობის დაყოფის სამუშაო ნაკადები თქვენს პაიპლაინის ეტაპებში — ეტაპის შიგნით სამუშაო ნაკადები ავტომატურად პარალელურად მიმდინარეობს.

## გაზიარებული ტომები {#shared-volumes}

ნაგულისხმევად, აგების ეტაპი ტვირთავს `.xctestproducts` ბანდლს შორეულ საცავში და თითოეული დაყოფის გამშვები ჩამოტვირთავს მას. თუ თქვენი CI პროვაიდერი უჭერს მხარს **გაზიარებულ ტომებს** (მუდმივი საცავი, რომელიც მიმაგრებულია სამუშაოებს შორის), შეგიძლიათ მთლიანად გამოტოვოთ ეს ატვირთვა/ჩამოტვირთვა ტესტის პროდუქტების გაზიარებული ფაილური სისტემის მეშვეობით გადაცემით.

ეს შეიძლება მნიშვნელოვნად შეამციროს დაყოფის გაშვების დრო, განსაკუთრებით დიდი ტესტის ბანდლებისთვის.

გაზიარებული ტომების გამოყენება:

1. **აგების ეტაპზე**, გადაეცით `-testProductsPath` (`--`-ის შემდეგ), რომელიც მიუთითებს გაზიარებულ ტომზე და დაამატეთ `--shard-skip-upload`, რათა გამოტოვოთ შორეული ატვირთვა:

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

თუ თქვენს CI პროვაიდერს უკვე აქვს არტეფაქტების ატვირთვისა და ჩამოტვირთვის ეტაპები, შეგიძლიათ Tuist-ს დაავალოთ არქივირება და ამოღება, ხოლო თქვენს CI-ს — ტრანსპორტირება.

1. **აგების ეტაპზე**, გადაეცით `--shard-archive-path`, რათა Tuist-მა ჩაწეროს ოპტიმიზირებული დაყოფის არქივი ლოკალურად ტესტის პროდუქტების ატვირთვის ნაცვლად:

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

როდესაც `--shard-archive-path` დაყენებულია, Tuist ტოვებს ტესტის პროდუქტების შორეულ გადაცემას და იყენებს ლოკალურ არქივს. თუ ასევე გადასცემთ `--shard-skip-upload`-ს, არქივის გზას ენიჭება უპირატესობა.

როდესაც არ არის გასაშვები ტესტები, მაგალითად, იმიტომ რომ შერჩევითმა ტესტირებამ გამოტოვა ყველა ტესტის მიზანი, აგების ეტაპი გამოიტანს ცარიელ დაყოფის მატრიცას და არ ქმნის არქივს. ატვირთვის ეტაპი გაუშვით მხოლოდ მაშინ, როდესაც მატრიცაში არის დაყოფები.

> [!IMPORTANT]
> გამოიყენეთ უნიკალური გზა თითოეული სამუშაო ნაკადის გაშვებისთვის (მაგ., ჩართეთ CI გაშვების ID), რათა თავიდან აიცილოთ კონფლიქტები პარალელურ გაშვებებს შორის. ასევე, უნდა გაასუფთაოთ დაყოფის არქივი დაყოფის დასრულების შემდეგ, რათა თავიდან აიცილოთ მოძველებული მონაცემების დაგროვება გამშვებზე.

### Namespace {#namespace}

[Namespace](https://namespace.so)-ის გამშვებები კარგად მუშაობენ GitHub Actions არტეფაქტებთან. დააყენეთ `TUIST_TEST_SHARD_ARCHIVE_PATH` ერთხელ, რათა აგების სამუშაომ ჩაწეროს დაყოფის არქივი ლოკალურად, ატვირთეთ ის და ჩამოტვირთეთ თითოეულ დაყოფის სამუშაოში `tuist test`-ის გაშვებამდე:

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
