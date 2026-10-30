---
{
  "title": "Gradle ტესტების შარდინგი",
  "titleTemplate": ":title · ტესტების შარდინგი · ფუნქციები · სახელმძღვანელოები · Tuist",
  "description": "გაანაწილეთ Gradle ტესტები რამდენიმე CI გამშვებზე Tuist Test Sharding-ის გამოყენებით."
}
---
# Gradle ტესტების დაშლა {#gradle-test-sharding}

Tuist-ის Gradle პლაგინი შეიცავს ჩაშენებულ მხარდაჭერას ტესტების დასალად. ის გეგმავს ტესტების ნაკრებებს, რომლებიც Tuist-მა ჩაწერა თქვენი პროექტების ტესტის ამოცანების წინა CI გაშვებებში, და იყენებს Tuist სერვერს ბალანსირებული დაშლის გეგმების შესაქმნელად ისტორიული დროის მონაცემების საფუძველზე.

> [!IMPORTANT] REQUIREMENTS
> - <.localized_link href="/guides/features/test-insights/gradle">ტესტების ინსაიტები</.localized_link> უნდა იყოს კონფიგურირებული

## როგორ მუშაობს {#how-it-works}

ტესტების დაშლა მიჰყვება ორეტაპიან სამუშაო პროცესს:

1. **აგების ეტაპი:** Tuist ქმნის **დაშლის გეგმას** სერვერზე თქვენი პროექტებისთვის ჩაწერილი ტესტების ნაკრებებიდან. სერვერი იყენებს ბოლო 30 დღის ისტორიულ ტესტის დროის მონაცემებს ტესტების დასანაწილებლად დაშლებზე ისე, რომ თითოეულ დაშლას დაახლოებით ერთი და იგივე დრო სჭირდებოდეს. აგების ეტაპი გამოაქვს **დაშლის მატრიცა**, რომელსაც თქვენი CI სისტემა იყენებს პარალელური გამშვებების შესაქმნელად.
2. **ტესტირების ეტაპი:** თითოეული CI გამშვები იღებს **დაშლის ინდექსს** და ასრულებს მხოლოდ იმ ტესტებს, რომლებიც მინიჭებულია ამ დაშლას. ბოლო დაშლა ასევე ასრულებს ყველა ტესტის ნაკრებს, რომელიც არ არის მინიჭებული სხვა დაშლას.

## აგების ეტაპი {#build-phase}

მოამზადეთ ტესტების დაშლები `tuistPrepareTestShards` ამოცანის გამოყენებით:

```sh
./gradlew tuistPrepareTestShards \
  -PtuistShardMax=5
```

ეს ამოცანა:
1. პოულობს პროექტებს, რომლებსაც აქვთ დასალადი ტესტის ამოცანა, მათი კომპილაციის გარეშე
2. ქმნის დაშლის გეგმას Tuist სერვერზე იმ პროექტებისთვის ჩაწერილი ტესტების ნაკრებებიდან და დროებიდან ბოლო 30 დღის განმავლობაში
3. გამოაქვს დაშლის მატრიცა თქვენი CI სისტემისთვის

როდესაც ჯერ არ არის ჩაწერილი ტესტების ნაკრებები, მაგალითად, პირველ გაშვებაზე, გეგმა შეიცავს ერთ დაშლას, რომელიც ასრულებს ყველა ტესტს.

### აგების პარამეტრები {#build-options}

კონფიგურირება დაშლისთვის Gradle პროექტის თვისებების მეშვეობით:

| თვისება | აღწერა |
|----------|-------------|
| `-PtuistShardMax=<N>` | დაშლების მაქსიმალური რაოდენობა (ნაგულისხმები: 2) |
| `-PtuistShardMin=<N>` | დაშლების მინიმალური რაოდენობა |
| `-PtuistShardMaxDuration=<MS>` | მიზნობრივი მაქსიმალური ხანგრძლივობა თითოეული დაშლისთვის მილიწამებში |
| `-PtuistShardTestTask=<NAME>` | ტესტის ამოცანა, რომლის ტესტებიც ნაწილდება, მაგალითად `testDebugUnitTest`. ნაგულისხმევია ყველა ტესტის ამოცანა აგებაში |

Android პროექტებს რამდენიმე აგების ვარიანტით აქვთ ერთი ერთეულოვანი ტესტის ამოცანა თითოეული ვარიანტისთვის. დააყენეთ `-PtuistShardTestTask` იმ ვარიანტზე, რომელსაც თქვენი დაშლები ასრულებენ, ისე რომ დაგეგმილი იყოს მხოლოდ ის პროექტები, რომლებსაც ის აქვთ:

```sh
./gradlew tuistPrepareTestShards \
  -PtuistShardMax=5 \
  -PtuistShardTestTask=testDebugUnitTest
```

დაშლის მითითება ავტომატურად მიიღება CI გარემოს ცვლადებიდან (`GITHUB_RUN_ID`, `CI_PIPELINE_ID` და ა.შ.) ან შეიძლება პირდაპირ დაყენდეს `TUIST_SHARD_REFERENCE` გარემოს ცვლადის მეშვეობით.

## ტესტირების ეტაპი {#test-phase}

თითოეული დაშლის გამშვები ასრულებს მისთვის მინიჭებულ ტესტებს სტანდარტული `test` ამოცანის გამოყენებით. როდესაც `TUIST_SHARD_INDEX` დაყენებულია, პლაგინი ავტომატურად იღებს დაშლის განაწილებას სერვერიდან და ფილტრავს ტესტის შესრულებას ისე, რომ მოიცვას მხოლოდ მინიჭებული ტესტების ნაკრებები. ტესტის ამოცანები პროექტებში, სადაც დაშლისთვის არ არის მინიჭებული ნაკრებები, გამოტოვებულია.

ბოლო დაშლა ასრულებს ყველა ტესტის ამოცანას და გამორიცხავს სხვა დაშლებისთვის მინიჭებულ ნაკრებებს, ისე რომ ნაკრებები, რომლებსაც ჯერ არ აქვთ ჩაწერილი გაშვებები, როგორიცაა ახლად დამატებული, მაინც შესრულდება.

```sh
TUIST_SHARD_INDEX=0 ./gradlew test
```

თუ აგების ეტაპზე დააყენეთ `-PtuistShardTestTask`, გაუშვით იგივე ამოცანა თითოეულ დაშლაში, მაგალითად `./gradlew testDebugUnitTest`.

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

გამოიყენეთ მატრიცული სტრატეგია დაშლების პარალელურად გასაშვებად:

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

Tuist ქმნის `.tuist-shard-child-pipeline.yml`, რომელსაც თქვენ იწყებთ როგორც [შვილობილ პაიპლაინს](https://docs.gitlab.com/ee/ci/pipelines/downstream_pipelines.html#parent-child-pipelines). განსაზღვრეთ `.tuist-shard` შაბლონური სამუშაო, რომელსაც გენერირებული დაშლის სამუშაოები გააფართოებენ:

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

შვილობილ პაიპლაინს სჭირდება `.tuist-shard` სამუშოს შაბლონი:

```yaml
# .gitlab/shard-template.yml
.tuist-shard:
  script:
    - tuist auth login
    - ./gradlew test
```

### CircleCI {#circleci}

Tuist ქმნის `.tuist-shard-continuation.json`-ს პარამეტრებით [გაგრძელების orb-ისთვის](https://circleci.com/developer/orbs/orb/circleci/continuation):

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

Tuist ქმნის `.tuist-shard-pipeline.yml`-ს ერთი ნაბიჯით თითოეული დაშლისთვის. ატვირთეთ ის `buildkite-agent pipeline upload`-ის გამოყენებით:

```yaml
# pipeline.yml
steps:
  - label: "Build test shards"
    command: |
      tuist auth login
      ./gradlew tuistPrepareTestShards -PtuistShardMax=5
      buildkite-agent pipeline upload .tuist-shard-pipeline.yml
```

თითოეულ გენერირებულ ნაბიჯს გარემოში აქვს დაყენებული `TUIST_SHARD_INDEX`. დაამატეთ ტესტის ბრძანება თითოეულ დაშლის ნაბიჯზე საერთო სკრიპტის გამოყენებით:

```bash
# .buildkite/shard-step.sh
#!/bin/bash
tuist auth login
./gradlew test
```

### Codemagic {#codemagic}

Codemagic არ უჭერს მხარს დინამიურ მატრიცულ სამუშაოებს, ამიტომ განსაზღვრეთ ცალკეული სამუშაო ნაკადი თითოეული დაშლისთვის. Tuist წერს `TUIST_SHARD_MATRIX`-ს და `TUIST_SHARD_COUNT`-ს `CM_ENV` ფაილში თითოეულ სამუშაო ნაკადში გამოსაყენებლად:

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

Bitrise-ზე, Tuist წერს `.tuist-shard-matrix.json`-ს `BITRISE_DEPLOY_DIR`-ში, რაც ხდის მას ხელმისაწვდომს აგების არტიფაქტად შემდგომი პაიპლაინის ეტაპებისთვის. გამოიყენეთ Bitrise Pipelines წინასწარ განსაზღვრული პარალელური სამუშაო ნაკადებით:

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
> Bitrise არ უჭერს მხარს დინამიურ პარალელურ სამუშაოების შექმნას შესრულების დროს. განსაზღვრეთ ფიქსირებული რაოდენობის დაშლის სამუშაო ნაკადები თქვენს პაიპლაინის ეტაპებში — ეტაპის შიგნით არსებული სამუშაო ნაკადები ავტომატურად პარალელურად სრულდება.
