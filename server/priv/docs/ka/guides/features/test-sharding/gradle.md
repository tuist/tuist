---
{
  "title": "Gradle ტესტების შარდინგი",
  "titleTemplate": ":title · ტესტების შარდინგი · ფუნქციები · სახელმძღვანელოები · Tuist",
  "description": "გაანაწილეთ Gradle ტესტები რამდენიმე CI გამშვებზე Tuist Test Sharding-ის მეშვეობით."
}
---
# Gradle ტესტების დაშლა {#gradle-test-sharding}

Tuist-ის Gradle პლაგინი შეიცავს ჩაშენებულ მხარდაჭერას ტესტების დასალად. ის გეგმავს ტესტების სუიტებს, რომლებიც Tuist-მა ჩაწერა თქვენი პროექტების ტესტების ამოცანების წინა CI გაშვებების დროს და იყენებს Tuist სერვერს ბალანსირებული დაშლის გეგმების შესაქმნელად ისტორიული დროის მონაცემების საფუძველზე.

> [!IMPORTANT] REQUIREMENTS
> - <.localized_link href="/guides/features/test-insights/gradle">ტესტების ანალიტიკა</.localized_link> უნდა იყოს კონფიგურირებული

## როგორ მუშაობს {#how-it-works}

ტესტების დაშლა მიჰყვება ორეტაპიან სამუშაო პროცესს:

1. **აგების ეტაპი:** Tuist ქმნის **დაშლის გეგმას** სერვერზე თქვენი პროექტებისთვის ჩაწერილი ტესტების სუიტებიდან. სერვერი იყენებს ბოლო 30 დღის ისტორიულ ტესტების დროის მონაცემებს ტესტების დასაშლად ისე, რომ თითოეულმა ნაწილმა დაახლოებით თანაბარი დრო დაჰხარჯოს. აგების ეტაპი გამოაქვს **დაშლის მატრიცა**, რომელსაც თქვენი CI სისტემა იყენებს პარალელური გამშვებების შესაქმნელად.
2. **ტესტირების ეტაპი:** თითოეული CI გამშვები იღებს **დაშლის ინდექსს** და ასრულებს მხოლოდ იმ ტესტებს, რომლებიც ამ ნაწილს არის მინიჭებული. ბოლო ნაწილი ასევე ასრულებს ყველა ტესტების სუიტას, რომელიც სხვა ნაწილს არ არის მინიჭებული.

## აგების ეტაპი {#build-phase}

მოამზადეთ ტესტების ნაწილები `tuistPrepareTestShards` ამოცანის გამოყენებით:

```sh
./gradlew tuistPrepareTestShards \
  -PtuistShardMax=5
```

ეს ამოცანა:
1. პოულობს პროექტებს, რომლებსაც აქვთ დასალადი ტესტების ამოცანა, მათი კომპილაციის გარეშე
2. ქმნის დაშლის გეგმას Tuist სერვერზე ბოლო 30 დღის განმავლობაში ამ პროექტებისთვის ჩაწერილი ტესტების სუიტებიდან და დროის მონაცემებიდან
3. გამოაქვს დაშლის მატრიცა თქვენი CI სისტემისთვის

როდესაც ტესტების სუიტები ჯერ არ არის ჩაწერილი, მაგალითად პირველ გაშვებაზე, გეგმა შეიცავს ერთ ნაწილს, რომელიც ასრულებს ყველა ტესტს.

### აგების პარამეტრები {#build-options}

დაშლის კონფიგურაცია Gradle პროექტის თვისებების მეშვეობით:

| თვისება | აღწერა |
|----------|-------------|
| `-PtuistShardMax=<N>` | ნაწილების მაქსიმალური რაოდენობა (ნაგულისხმები: 2) |
| `-PtuistShardMin=<N>` | ნაწილების მინიმალური რაოდენობა |
| `-PtuistShardMaxDuration=<MS>` | მიზნობრივი მაქსიმალური ხანგრძლივობა თითოეული ნაწილისთვის მილიწამებში |
| `-PtuistShardTestTask=<NAME>` | ტესტების ამოცანა, რომლის ტესტებიც იშლება, მაგალითად `testDebugUnitTest`. ნაგულისხმევად მოქმედებს აგებაში არსებულ ყველა ტესტების ამოცანაზე |

Android პროექტებს მრავალი აგების ვარიანტით აქვთ ერთი ერთეულოვანი ტესტების ამოცანა თითოეული ვარიანტისთვის. დააყენეთ `-PtuistShardTestTask` იმ ვარიანტზე, რომელსაც თქვენი ნაწილები ასრულებენ, ისე რომ დაიგეგმოს მხოლოდ ის პროექტები, რომლებსაც ის აქვთ:

```sh
./gradlew tuistPrepareTestShards \
  -PtuistShardMax=5 \
  -PtuistShardTestTask=testDebugUnitTest
```

დაშლის მითითება ავტომატურად მიიღება CI გარემოს ცვლადებიდან (`GITHUB_RUN_ID`, `CI_PIPELINE_ID` და ა.შ.) ან შეიძლება ცალსახად დაყენდეს `TUIST_SHARD_REFERENCE` გარემოს ცვლადის მეშვეობით.

## ტესტირების ეტაპი {#test-phase}

თითოეული დაშლის გამშვები ასრულებს მისთვის მინიჭებულ ტესტებს სტანდარტული `test` ამოცანის გამოყენებით. როდესაც `TUIST_SHARD_INDEX` დაყენებულია, პლაგინი ავტომატურად იღებს დაშლის განაწილებას სერვერიდან და ფილტრავს ტესტების შესრულებას ისე, რომ შეიცავდეს მხოლოდ მინიჭებულ ტესტების სუიტებს. ტესტების ამოცანები პროექტებში, სადაც ნაწილისთვის არ არის მინიჭებული სუიტები, გამოტოვებულია.

ბოლო ნაწილი ასრულებს ყველა ტესტების ამოცანას და გამორიცხავს სხვა ნაწილებისთვის მინიჭებულ სუიტებს, ისე რომ სუიტები, რომლებსაც ჯერ არ აქვთ ჩაწერილი გაშვებები, მაგალითად ახლად დამატებულები, მაინც შესრულდება.

```sh
TUIST_SHARD_INDEX=0 ./gradlew test
```

თუ აგების ეტაპზე დააყენებთ `-PtuistShardTestTask`, გაუშვით იგივე ამოცანა თითოეულ ნაწილში, მაგალითად `./gradlew testDebugUnitTest`.

## უწყვეტი ინტეგრაცია {#continuous-integration}

Tuist ავტომატურად აღმოაჩენს შემდეგ CI პროვაიდერებს:

- [GitHub Actions](#github-actions)
- [GitLab CI](#gitlab-ci)
- [CircleCI](#circleci)
- [Buildkite](#buildkite)
- [Codemagic](#codemagic)
- [Bitrise](#bitrise)

სხვა პროვაიდერებისთვის, მიმართეთ `.tuist-shard-matrix.json` ფაილს პარალელური სამუშაოების დასაყენებლად.

### GitHub Actions {#github-actions}

გამოიყენეთ მატრიცის სტრატეგია ნაწილების პარალელურად გასაშვებად:

```yaml
name: Tests
on: [pull_request]

jobs:
  build:
    name: Build test shards
    runs-on: ubuntu-latest
    outputs:
      matrix: ${{ steps.build.outputs.matrix }}
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-java@v4
        with:
          distribution: 'temurin'
          java-version: '17'
      - uses: gradle/actions/setup-gradle@v4
      - run: tuist auth login
      - id: build
        run: ./gradlew tuistPrepareTestShards -PtuistShardMax=5

  test:
    name: "Shard #${{ matrix.shard }}"
    needs: build
    runs-on: ubuntu-latest
    strategy:
      fail-fast: false
      matrix:
        shard: ${{ fromJson(needs.build.outputs.matrix).shard }}
    env:
      TUIST_SHARD_INDEX: ${{ matrix.shard }}
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-java@v4
        with:
          distribution: 'temurin'
          java-version: '17'
      - uses: gradle/actions/setup-gradle@v4
      - run: tuist auth login
      - run: ./gradlew test
```

### GitLab CI {#gitlab-ci}

Tuist ქმნის `.tuist-shard-child-pipeline.yml`, რომელსაც თქვენ იწვევთ როგორც [შვილობილ პაიპლაინს](https://docs.gitlab.com/ee/ci/pipelines/downstream_pipelines.html#parent-child-pipelines). განსაზღვრეთ `.tuist-shard` შაბლონური სამუშაო, რომელსაც გენერირებული ნაწილების სამუშაოები აფართოებენ:

```yaml
# .gitlab-ci.yml
stages:
  - build
  - test

build-shards:
  stage: build
  script:
    - tuist auth login
    - ./gradlew tuistPrepareTestShards -PtuistShardMax=5
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

შვილობილ პაიპლაინს სჭირდება `.tuist-shard` სამუშაოს შაბლონი:

```yaml
# .gitlab/shard-template.yml
.tuist-shard:
  script:
    - tuist auth login
    - ./gradlew test
```

### CircleCI {#circleci}

Tuist ქმნის `.tuist-shard-continuation.json` პარამეტრებით [გაგრძელების orb-ისთვის](https://circleci.com/developer/orbs/orb/circleci/continuation):

```yaml
# .circleci/config.yml
version: 2.1
setup: true

orbs:
  continuation: circleci/continuation@1

jobs:
  build-shards:
    docker:
      - image: cimg/openjdk:17.0
    steps:
      - checkout
      - run:
          name: Build and plan shards
          command: |
            tuist auth login
            ./gradlew tuistPrepareTestShards -PtuistShardMax=5
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

jobs:
  test-shard:
    docker:
      - image: cimg/openjdk:17.0
    parameters:
      shard-index:
        type: integer
    steps:
      - checkout
      - run:
          name: Run shard
          command: |
            export TUIST_SHARD_INDEX=<< parameters.shard-index >>
            tuist auth login
            ./gradlew test

workflows:
  test:
    jobs:
      - test-shard:
          matrix:
            parameters:
              shard-index: [<< pipeline.parameters.shard-indices >>]
```

### Buildkite {#buildkite}

Tuist ქმნის `.tuist-shard-pipeline.yml` ერთი ნაბიჯით თითოეული ნაწილისთვის. ატვირთეთ ის `buildkite-agent pipeline upload`-ის გამოყენებით:

```yaml
# pipeline.yml
steps:
  - label: "Build test shards"
    command: |
      tuist auth login
      ./gradlew tuistPrepareTestShards -PtuistShardMax=5
      buildkite-agent pipeline upload .tuist-shard-pipeline.yml
```

თითოეულ გენერირებულ ნაბიჯს აქვს `TUIST_SHARD_INDEX` დაყენებული მის გარემოში. დაამატეთ ტესტის ბრძანება თითოეულ ნაწილის ნაბიჯზე საერთო სკრიპტის გამოყენებით:

```bash
# .buildkite/shard-step.sh
#!/bin/bash
tuist auth login
./gradlew test
```

### Codemagic {#codemagic}

Codemagic არ უჭერს მხარს დინამიურ მატრიცულ სამუშაოებს, ამიტომ განსაზღვრეთ ცალკე სამუშაო ნაკადი თითოეული ნაწილისთვის. Tuist წერს `TUIST_SHARD_MATRIX` და `TUIST_SHARD_COUNT` `CM_ENV` ფაილში, რათა გამოყენებულ იქნას თითოეულ სამუშაო ნაკადში:

```yaml
# codemagic.yaml
workflows:
  build-shards:
    name: Build test shards
    instance_type: linux_x2
    environment:
      java: 17
    scripts:
      - name: Build and plan shards
        script: |
          tuist auth login
          ./gradlew tuistPrepareTestShards -PtuistShardMax=5

  test-shard-0: &shard-workflow
    name: "Shard #0"
    instance_type: linux_x2
    environment:
      java: 17
      vars:
        TUIST_SHARD_INDEX: 0
    scripts:
      - name: Run shard
        script: |
          tuist auth login
          ./gradlew test

  test-shard-1:
    <<: *shard-workflow
    name: "Shard #1"
    environment:
      java: 17
      vars:
        TUIST_SHARD_INDEX: 1

  test-shard-2:
    <<: *shard-workflow
    name: "Shard #2"
    environment:
      java: 17
      vars:
        TUIST_SHARD_INDEX: 2

  test-shard-3:
    <<: *shard-workflow
    name: "Shard #3"
    environment:
      java: 17
      vars:
        TUIST_SHARD_INDEX: 3

  test-shard-4:
    <<: *shard-workflow
    name: "Shard #4"
    environment:
      java: 17
      vars:
        TUIST_SHARD_INDEX: 4
```

### Bitrise {#bitrise}

Bitrise-ზე, Tuist წერს `.tuist-shard-matrix.json` `BITRISE_DEPLOY_DIR`-ში, რაც ხდის მას ხელმისაწვდომს როგორც აგების არტეფაქტს შემდგომი პაიპლაინის ეტაპებისთვის. გამოიყენეთ Bitrise Pipelines წინასწარ განსაზღვრული პარალელური სამუშაო ნაკადებით:

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
                ./gradlew tuistPrepareTestShards -PtuistShardMax=5

  test-shard-0: &shard-workflow
    envs:
      - TUIST_SHARD_INDEX: 0
    steps:
      - script:
          title: Run shard
          inputs:
            - content: |
                tuist auth login
                ./gradlew test
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
> Bitrise არ უჭერს მხარს დინამიურ პარალელურ სამუშაოების შექმნას შესრულების დროს. განსაზღვრეთ ფიქსირებული რაოდენობის ნაწილების სამუშაო ნაკადები თქვენს პაიპლაინის ეტაპებში — ეტაპის შიგნით არსებული სამუშაო ნაკადები ავტომატურად პარალელურად მუშაობს.
