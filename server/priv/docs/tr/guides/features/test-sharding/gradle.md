---
{
  "title": "Gradle Test Parçalama",
  "titleTemplate": ":title · Test Parçalama · Özellikler · Kılavuzlar · Tuist",
  "description": "Gradle testlerini Tuist Test Parçalama ile birden fazla CI çalıştırıcısına dağıtın."
}
---
# Gradle test sharding {#gradle-test-sharding}

Tuist Gradle eklentisi, test sharding için yerleşik destek sunar. Tuist, projelerinizin test görevlerinin önceki CI çalıştırmalarında kaydettiği test paketlerini planlar ve geçmiş zamanlama verilerine dayalı olarak dengeli shard planları oluşturmak için Tuist sunucusunu kullanır.

> [!IMPORTANT]
> **Gereksinimler**
>
> - <.localized_link href="/guides/features/test-insights/gradle">Test içgörüsü</.localized_link> yapılandırılmalıdır

## Nasıl çalışır {#how-it-works}

Test sharding iki aşamalı bir iş akışı izler:

1. **Derleme aşaması:** Tuist, projeleriniz için kaydedilen test paketlerinden sunucuda bir **shard planı** oluşturur. Sunucu, her shard’ın yaklaşık aynı sürede tamamlanması için testleri shard’lara dağıtmak amacıyla son 30 güne ait geçmiş test zamanlama verilerini kullanır. Derleme aşaması, CI sisteminizin paralel çalıştırıcıları başlatmak için kullandığı bir **shard matrisi** çıktısı verir.
2. **Test aşaması:** Her CI çalıştırıcısı bir **shard indeksi** alır ve yalnızca o shard’a atanan testleri yürütür. Son shard, başka bir shard’a atanmamış olan her test paketini de çalıştırır.

## Derleme aşaması {#build-phase}

Test shard’larını `tuistPrepareTestShards` görevini kullanarak hazırlayın:

```sh
./gradlew tuistPrepareTestShards \
  -PtuistShardMax=5
```

Bu görev:
1. Shard’lanacak test görevine sahip projeleri derlemeden bulur
2. Son 30 gün içinde bu projeler için kaydedilen test paketleri ve zamanlamalardan Tuist sunucusunda bir shard planı oluşturur
3. CI sisteminiz için bir shard matrisi çıktısı verir

Henüz hiçbir test paketi kaydedilmediğinde, örneğin ilk çalıştırmada, plan tüm testleri çalıştıran tek bir shard içerir.

### Derleme seçenekleri {#build-options}

Sharding’i Gradle proje özellikleri üzerinden yapılandırın:

| Özellik | Açıklama |
|----------|-------------|
| `-PtuistShardMax=<N>` | Maksimum shard sayısı (varsayılan: 2) |
| `-PtuistShardMin=<N>` | Minimum shard sayısı |
| `-PtuistShardMaxDuration=<MS>` | Shard başına hedeflenen maksimum süre (milisaniye cinsinden) |
| `-PtuistShardTestTask=<NAME>` | Testleri shard’lanan test görevi, örneğin `testDebugUnitTest`. Varsayılan olarak derlemedeki her test görevidir. |

Birden fazla derleme varyantına sahip Android projelerinde varyant başına bir birim test görevi bulunur. Shard’larınızın çalıştıracağı varyanta `-PtuistShardTestTask` ayarlayın, böylece yalnızca bu varyanta sahip projeler planlanır:

```sh
./gradlew tuistPrepareTestShards \
  -PtuistShardMax=5 \
  -PtuistShardTestTask=testDebugUnitTest
```

Shard referansı otomatik olarak CI ortam değişkenlerinden (`GITHUB_RUN_ID`, `CI_PIPELINE_ID` vb.) türetilir veya `TUIST_SHARD_REFERENCE` ortam değişkeni aracılığıyla açıkça ayarlanabilir.

## Test aşaması {#test-phase}

Her shard çalıştırıcısı, atanan testlerini standart `test` görevini kullanarak yürütür. `TUIST_SHARD_INDEX` ayarlandığında, eklenti shard atamasını sunucudan otomatik olarak alır ve test yürütmesini yalnızca atanan test paketlerini içerecek şekilde filtreler. Shard’a atanmış paketi olmayan projelerdeki test görevleri atlanır.

Son shard, her test görevini çalıştırır ve diğer shard’lara atanmış paketleri dışlar; böylece henüz kayıtlı çalıştırması olmayan paketler, örneğin yeni eklenenler, yine de çalıştırılır.

```sh
TUIST_SHARD_INDEX=0 ./gradlew test
```

Derleme aşamasında `-PtuistShardTestTask` ayarladıysanız, her shard’da aynı görevi çalıştırın, örneğin `./gradlew testDebugUnitTest`.

## Sürekli entegrasyon {#continuous-integration}

<!-- @snippet: ./_ci-providers -->

Her derleme ve shard işinin Gradle’ı çalıştırmadan önce kimlik doğrulaması yapması gerekir. Ya Tuist CLI’yi yükleyip CI sağlayıcınızın OIDC kimliğiyle `tuist auth login` komutunu çalıştırın ya da bir hesap token’ını `TUIST_TOKEN` olarak erişime açın. Bkz. <.localized_link href="/guides/server/authentication#gradle-plugin-authentication">Gradle eklentisi kimlik doğrulaması</.localized_link>. Aşağıdaki örnekler bu adımı atlar.

### GitHub Actions {#github-actions}

Shard’ları paralel çalıştırmak için bir matris stratejisi kullanın:

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

Tuist, bir [alt pipeline](https://docs.gitlab.com/ci/pipelines/downstream_pipelines/#parent-child-pipelines) olarak tetikleyebileceğiniz bir `.tuist-shard-child-pipeline.yml` dosyası oluşturur. Oluşturulan shard işlerinin genişlettiği bir `.tuist-shard` şablon işi tanımlayın:

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

Alt pipeline’ın bir `.tuist-shard` iş şablonuna ihtiyacı vardır:

```yaml
# .gitlab/shard-template.yml
.tuist-shard:
  script:
    - ./gradlew test
```

### CircleCI {#circleci}

Tuist, [süreklilik orb’ı](https://circleci.com/developer/orbs/orb/circleci/continuation) için parametreler içeren bir `.tuist-shard-continuation.json` dosyası oluşturur:

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

Tuist, shard başına bir adım içeren bir `.tuist-shard-pipeline.yml` dosyası oluşturur. Dosyayı `buildkite-agent pipeline upload` ile yükleyin:

```yaml
# pipeline.yml
steps:
  - label: "Build test shards"
    command: |
      ./gradlew tuistPrepareTestShards -PtuistShardMax=5
      buildkite-agent pipeline upload .tuist-shard-pipeline.yml
```

Oluşturulan her adımda ortamında `TUIST_SHARD_INDEX` ayarlıdır. Paylaşılan bir betik kullanarak her shard adımına test komutunu ekleyin:

```bash
# .buildkite/shard-step.sh
#!/bin/bash
./gradlew test
```

### Codemagic {#codemagic}

Codemagic dinamik matris işlerini desteklemez, bu nedenle shard başına ayrı bir iş akışı tanımlayın. Tuist, her iş akışı içinde kullanılmak üzere `TUIST_SHARD_MATRIX` ve `TUIST_SHARD_COUNT` değerlerini `CM_ENV` dosyasına yazar:

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

Bitrise’ta Tuist, `.tuist-shard-matrix.json` dosyasını `BITRISE_DEPLOY_DIR` dizinine yazar ve bunu sonraki pipeline aşamaları için bir derleme yapıtı olarak kullanılabilir hale getirir. Önceden tanımlanmış paralel iş akışlarıyla Bitrise Pipelines’ı kullanın:

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
> Bitrise, çalışma zamanında dinamik paralel iş oluşturmayı desteklemez. Pipeline aşamalarınızda sabit sayıda shard iş akışı tanımlayın — bir aşama içindeki iş akışları otomatik olarak paralel çalışır.
