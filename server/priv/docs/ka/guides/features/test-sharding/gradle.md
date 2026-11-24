---
{
  "title": "Gradle ტესტების შარდინგი",
  "titleTemplate": ":title · ტესტების შარდინგი · ფუნქციები · სახელმძღვანელოები · Tuist",
  "description": "გაანაწილეთ Gradle ტესტები რამდენიმე CI გამშვებზე Tuist Test Sharding-ის გამოყენებით."
}
---
# Gradle ტესტების დაყოფა {#gradle-test-sharding}

Tuist-ის Gradle პლაგინი შეიცავს ჩაშენებულ მხარდაჭერას ტესტების დაყოფისთვის. ის გეგმავს ტესტების ნაკრებებს, რომლებიც Tuist-მა ჩაწერა თქვენი პროექტების ტესტის ამოცანების წინა CI გაშვებებისას და იყენებს Tuist სერვერს ბალანსირებული დაყოფის გეგმების შესაქმნელად ისტორიული დროის მონაცემების საფუძველზე.

> [!IMPORTANT]
> **მოთხოვნები**
>
> - <.localized_link href="/guides/features/test-insights/gradle">ტესტების ინსაიტები</.localized_link> უნდა იყოს კონფიგურირებული

## როგორ მუშაობს {#how-it-works}

ტესტების დაყოფა მიჰყვება ორეტაპიან სამუშაო პროცესს:

1. **აგების ეტაპი:** Tuist ქმნის **დაყოფის გეგმას** სერვერზე თქვენი პროექტებისთვის ჩაწერილი ტესტების ნაკრებებიდან. სერვერი იყენებს ბოლო 30 დღის ისტორიულ ტესტის დროის მონაცემებს ტესტების დასანაწილებლად დაყოფებში ისე, რომ თითოეულ დაყოფას დაახლოებით ერთი და იგივე დრო დასჭირდეს. აგების ეტაპი გამოიმუშავებს **დაყოფის მატრიცას**, რომელსაც თქვენი CI სისტემა იყენებს პარალელური გამშვებების შესაქმნელად.
2. **ტესტირების ეტაპი:** თითოეული CI გამშვები იღებს **დაყოფის ინდექსს** და ასრულებს მხოლოდ იმ ტესტებს, რომლებიც ამ დაყოფას არის მინიჭებული. ბოლო დაყოფა ასევე ასრულებს ყველა ტესტის ნაკრებს, რომელიც სხვა დაყოფას არ არის მინიჭებული.

## აგების ეტაპი {#build-phase}

მოამზადეთ ტესტების დაყოფები `tuistPrepareTestShards` ამოცანის გამოყენებით:

```sh
./gradlew tuistPrepareTestShards \
  -PtuistShardMax=5
```

ეს ამოცანა:
1. პოულობს პროექტებს, რომლებსაც აქვთ დასაყოფი ტესტის ამოცანა, მათი კომპილაციის გარეშე
2. ქმნის დაყოფის გეგმას Tuist სერვერზე იმ პროექტებისთვის ჩაწერილი ტესტების ნაკრებებიდან და დროებიდან ბოლო 30 დღის განმავლობაში
3. გამოიმუშავებს დაყოფის მატრიცას თქვენი CI სისტემისთვის

როდესაც ტესტების ნაკრებები ჯერ არ არის ჩაწერილი, მაგალითად, პირველ გაშვებაზე, გეგმას აქვს ერთი დაყოფა, რომელიც ასრულებს ყველა ტესტს.

### აგების პარამეტრები {#build-options}

კონფიგურაცია დაყოფისთვის Gradle პროექტის თვისებების მეშვეობით:

| თვისება | აღწერა |
|----------|-------------|
| `-PtuistShardMax=<N>` | დაყოფების მაქსიმალური რაოდენობა (ნაგულისხმები: 2) |
| `-PtuistShardMin=<N>` | დაყოფების მინიმალური რაოდენობა |
| `-PtuistShardMaxDuration=<MS>` | მიზნობრივი მაქსიმალური ხანგრძლივობა თითოეული დაყოფისთვის მილიწამებში |
| `-PtuistShardTestTask=<NAME>` | ტესტის ამოცანა, რომლის ტესტებიც იყოფა, მაგალითად `testDebugUnitTest`. ნაგულისხმევად არის ყველა ტესტის ამოცანა აგებაში |

Android პროექტებს მრავალი აგების ვარიანტით აქვთ ერთი ერთეულოვანი ტესტის ამოცანა თითოეული ვარიანტისთვის. დააყენეთ `-PtuistShardTestTask` იმ ვარიანტზე, რომელსაც თქვენი დაყოფები ასრულებენ, ისე რომ დაიგეგმოს მხოლოდ ის პროექტები, რომლებსაც ის აქვთ:

```sh
./gradlew tuistPrepareTestShards \
  -PtuistShardMax=5 \
  -PtuistShardTestTask=testDebugUnitTest
```

დაყოფის მითითება ავტომატურად მიიღება CI გარემოს ცვლადებიდან (`GITHUB_RUN_ID`, `CI_PIPELINE_ID` და ა.შ.) ან შეიძლება პირდაპირ დაყენდეს `TUIST_SHARD_REFERENCE` გარემოს ცვლადის მეშვეობით.

## ტესტირების ეტაპი {#test-phase}

თითოეული დაყოფის გამშვები ასრულებს მისთვის მინიჭებულ ტესტებს სტანდარტული `test` ამოცანის გამოყენებით. როდესაც `TUIST_SHARD_INDEX` დაყენებულია, პლაგინი ავტომატურად იღებს დაყოფის მინიჭებას სერვერიდან და ფილტრავს ტესტის შესრულებას ისე, რომ შეიცავდეს მხოლოდ მინიჭებულ ტესტების ნაკრებებს. ტესტის ამოცანები პროექტებში, სადაც დაყოფისთვის არ არის მინიჭებული ნაკრებები, გამოტოვებულია.

ბოლო დაყოფა ასრულებს ყველა ტესტის ამოცანას და გამორიცხავს სხვა დაყოფებისთვის მინიჭებულ ნაკრებებს, ისე რომ ნაკრებები, რომლებსაც ჯერ არ აქვთ ჩაწერილი გაშვებები, როგორიცაა ახლად დამატებული, მაინც შესრულდება.

```sh
TUIST_SHARD_INDEX=0 ./gradlew test
```

თუ აგების ეტაპზე დააყენებთ `-PtuistShardTestTask`, გაუშვით იგივე ამოცანა თითოეულ დაყოფაში, მაგალითად `./gradlew testDebugUnitTest`.

## უწყვეტი ინტეგრაცია {#continuous-integration}

<!-- @snippet: ./_ci-providers -->

ყველა აგების და დაყოფის სამუშაოს სჭირდება ავთენტიკაცია Gradle-ის გაშვებამდე. ან დააინსტალირეთ Tuist CLI და გაუშვით `tuist auth login` თქვენი CI მომწოდებლის OIDC იდენტობით, ან გახადეთ ხელმისაწვდომი ანგარიშის ტოკენი როგორც `TUIST_TOKEN`. იხილეთ <.localized_link href="/guides/server/authentication#gradle-plugin-authentication">Gradle პლაგინის ავთენტიკაცია</.localized_link>. ქვემოთ მოყვანილ მაგალითებში ეს ნაბიჯი გამოტოვებულია.

### GitHub Actions {#github-actions}

გამოიყენეთ მატრიცის სტრატეგია დაყოფების პარალელურად გასაშვებად:

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
      - run: ./gradlew test
```

### GitLab CI {#gitlab-ci}

Tuist წარმოქმნის `.tuist-shard-child-pipeline.yml`-ს, რომელსაც თქვენ აღძრავთ როგორც [შვილობილ პაიპლაინს](https://docs.gitlab.com/ci/pipelines/downstream_pipelines/#parent-child-pipelines). განსაზღვრეთ `.tuist-shard` შაბლონის სამუშაო, რომელსაც წარმოქმნილი დაყოფის სამუშაოები გააფართოვებენ:

```yaml
# .gitlab-ci.yml
stages:
  - build
  - test

build-shards:
  stage: build
  script:
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
    - ./gradlew test
```

### CircleCI {#circleci}

Tuist წარმოქმნის `.tuist-shard-continuation.json`-ს პარამეტრებით [გაგრძელების ორბისთვის](https://circleci.com/developer/orbs/orb/circleci/continuation):

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

Tuist წარმოქმნის `.tuist-shard-pipeline.yml`-ს ერთი ნაბიჯით თითოეული დაყოფისთვის. ატვირთეთ ის `buildkite-agent pipeline upload`-ის გამოყენებით:

```yaml
# pipeline.yml
steps:
  - label: "Build test shards"
    command: |
      ./gradlew tuistPrepareTestShards -PtuistShardMax=5
      buildkite-agent pipeline upload .tuist-shard-pipeline.yml
```

თითოეულ წარმოქმნილ ნაბიჯს გარემოში აქვს მინიჭებული `TUIST_SHARD_INDEX`. დაამატეთ ტესტის ბრძანება თითოეულ დაყოფის ნაბიჯზე საერთო სკრიპტის გამოყენებით:

```bash
# .buildkite/shard-step.sh
#!/bin/bash
./gradlew test
```

### Codemagic {#codemagic}

Codemagic არ უჭერს მხარს დინამიურ მატრიცულ სამუშაოებს, ამიტომ განსაზღვრეთ ცალკეული სამუშაო ნაკადი თითოეული დაყოფისთვის. Tuist წერს `TUIST_SHARD_MATRIX`-ს და `TUIST_SHARD_COUNT`-ს `CM_ENV` ფაილში, რათა ისინი გამოყენებულ იქნას თითოეულ სამუშაო ნაკადში:

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

Bitrise-ზე Tuist წერს `.tuist-shard-matrix.json`-ს `BITRISE_DEPLOY_DIR`-ში, რაც ხელმისაწვდომს ხდის მას როგორც აგების არტეფაქტს მომდევნო პაიპლაინის ეტაპებისთვის. გამოიყენეთ Bitrise Pipelines წინასწარ განსაზღვრული პარალელური სამუშაო ნაკადებით:

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
                ./gradlew tuistPrepareTestShards -PtuistShardMax=5

  test-shard-0: &shard-workflow
    envs:
      - TUIST_SHARD_INDEX: 0
    steps:
      - script:
          title: Run shard
          inputs:
            - content: |
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
> Bitrise არ უჭერს მხარს დინამიურ პარალელურ სამუშაოების შექმნას შესრულების დროს. განსაზღვრეთ დაყოფის სამუშაო ნაკადების ფიქსირებული რაოდენობა თქვენს პაიპლაინის ეტაპებში — ერთი ეტაპის ფარგლებში არსებული სამუშაო ნაკადები ავტომატურად პარალელურად სრულდება.
