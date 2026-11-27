---
{
  "title": "Xcode Test Parçalama",
  "titleTemplate": ":title · Test Parçalama · Özellikler · Kılavuzlar · Tuist",
  "description": "Tuist Test Parçalama ile Xcode testlerini birden fazla CI çalıştırıcısına dağıtın."
}
---
# Xcode test sharding {#xcode-test-sharding}

> [!IMPORTANT]
> **Gereksinimler**
>
> - <.localized_link href="/guides/features/test-insights/xcode">Xcode test insights</.localized_link> yapılandırılmış olmalıdır. Sharding, shard'ları dengelemek için son 30 güne ait test zamanlama verilerini kullanır; içgörüler olmadan her shard, suite bilinmiyormuş gibi çalışır.

Xcode projeleri için test sharding, bir shard planı oluşturmak üzere `tuist xcodebuild build-for-testing` ve her shard'ı yürütmek üzere `tuist xcodebuild test` komutlarını kullanır.

## Nasıl çalışır {#how-it-works}

Test sharding iki aşamalı bir iş akışı izler:

1. **Oluşturma aşaması:** Tuist, derlenen `.xctestrun` dosyasından test modüllerini okur ve sunucuda bir **shard planı** oluşturur. Sunucu, her shard'ın yaklaşık olarak aynı sürede tamamlanmasını sağlamak için son 30 güne ait geçmiş test zamanlama verilerini kullanarak testleri shard'lara dağıtır. Oluşturma aşaması, CI sisteminizin paralel runner'lar başlatmak için kullandığı bir **shard matrisi** çıktısı verir.
2. **Test aşaması:** Her sürekli entegrasyon runner'ı bir **shard indeksi** ve tam **shard planı tanımlayıcısını** alır, ardından o planın test seçimini yürütür.

Suite granülerliği ile sunucu, mevcut `.xctestrun` içindeki her modül için dalınızda yapılan son CI çalışmaları tarafından bildirilen suite'leri kullanır; dal geçmişi olmayan modüller için projenin varsayılan dalına geri döner. Birden fazla çalışmayı birleştirmek, parçalı veya seçici bir çalışmanın en son raporda dışladığı suite'leri korur.

`--shard-granularity suite` kullanıldığında, Tuist bilinen suite'leri istenen shard sayısı arasında dengeler ve son shard'ı yakalayıcı (catch-all) olarak kullanır. Örneğin, `--shard-total 5` `0` ile `4` arasında shard indeksleri üretir; yakalayıcı olarak shard indeksi `4` kullanılır. Normal shard'lar, atanmış suite'leri için `-only-testing` ile çalışır. Son shard, `-only-testing` olmadan çalışır ve önceki shard'lara atanmış her suite için `-skip-testing` parametresini iletir; böylece planlanan suite'lerin yanı sıra yeni eklenen suite'leri veya geçmiş envanterde eksik olan suite'leri de çalıştırır. Modül granülerliğinin yakalayıcıya ihtiyacı yoktur çünkü `.xctestrun` dosyası modül listesini sağlar.

## Oluşturma aşaması {#build-phase}

Testlerinizi derleyin ve bir shard planı oluşturun:

```sh
tuist xcodebuild build-for-testing \
  -scheme MyScheme \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  --shard-total 5
```

Bu komut:
1. Testlerinizi `xcodebuild build-for-testing` ile derler
2. Geçmiş zamanlama verilerini kullanarak Tuist sunucusunda bir shard planı oluşturur
3. `.xctestproducts` paketini yükler veya shard runner'ların kullanımı için bir shard arşivi yazar
4. CI sisteminiz için bir shard matrisi çıktısı verir

<!-- @snippet: ./_xcode-build-options -->

## Test aşaması {#test-phase}

Her shard runner, kendisine atanan testleri yürütür:

```sh
tuist xcodebuild test \
  -scheme MyScheme \
  -destination 'platform=iOS Simulator,name=iPhone 16'
```

<!-- @snippet: ./_xcode-test-options -->

## Sürekli entegrasyon {#continuous-integration}

<!-- @snippet: ./_ci-providers -->

### GitHub Actions {#github-actions}

Shard'ları paralel olarak çalıştırmak için bir matris stratejisi kullanın:

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

Tuist, bir [alt pipeline](https://docs.gitlab.com/ci/pipelines/downstream_pipelines/#parent-child-pipelines) olarak tetikleyeceğiniz bir `.tuist-shard-child-pipeline.yml` oluşturur. Oluşturulan shard job'larının genişleteceği bir `.tuist-shard` şablon job'u tanımlayın:

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

Tuist, [süreklilik orb'u](https://circleci.com/developer/orbs/orb/circleci/continuation) için parametreler içeren bir `.tuist-shard-continuation.json` oluşturur. `shard-plan-id` parametresi, devam eden yapılandırmanızda bildirilmelidir:

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

Tuist, shard başına bir adım içeren bir `.tuist-shard-pipeline.yml` oluşturur. Bunu `buildkite-agent pipeline upload` ile yükleyin:

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

Oluşturulan her adımda ortamında `TUIST_SHARD_INDEX` ve `TUIST_SHARD_PLAN_ID` ayarlanır. Paylaşılan bir betik kullanarak her shard adımına test komutunu ekleyin:

```bash
# .buildkite/shard-step.sh
#!/bin/bash
tuist auth login
tuist xcodebuild test \
  -scheme MyScheme \
  -destination 'platform=iOS Simulator,name=iPhone 16'
```

### Codemagic {#codemagic}

Codemagic dinamik matris job'larını desteklemez, bu nedenle shard başına ayrı bir iş akışı tanımlayın. Tuist, derleme iş akışı içinde kullanılmak üzere `TUIST_SHARD_MATRIX` ve `TUIST_SHARD_COUNT` değerlerini `CM_ENV` dosyasına yazar. Codemagic'in `CM_ENV` kapsamı iş akışı düzeyindedir, bu nedenle tam shard planı tanımlayıcısı iş akışı sınırlarını aşmaz; test iş akışları referans tabanlı shard aramasına geri döner:

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

Bitrise'te Tuist, `BITRISE_DEPLOY_DIR` konumuna (`shard_plan_id` dahil) `.tuist-shard-matrix.json` yazar ve bunu aşağı akış pipeline aşamaları için bir derleme artefaktı olarak kullanılabilir hale getirir. Her test iş akışı, test komutunun ortamına ulaşması için indirilen artefaktan plan kimliğini `envman` kullanarak çıkarır:

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
> Bitrise, çalışma zamanında dinamik paralel job oluşturmayı desteklemez. Pipeline aşamalarınızda sabit sayıda shard iş akışı tanımlayın; bir aşama içindeki iş akışları otomatik olarak paralel çalışır.

## Paylaşılan birimler {#shared-volumes}

Varsayılan olarak, oluşturma aşaması `.xctestproducts` paketini uzak depolamaya yükler ve her shard runner bunu indirir. CI sağlayıcınız **paylaşılan birimleri** (job'lar arasında monte edilen kalıcı depolama) destekliyorsa, test ürünlerini paylaşılan bir dosya sistemi üzerinden geçirerek bu yükleme/indirme işlemini tamamen atlayabilirsiniz.

Bu, özellikle büyük test paketleri için shard başlangıç süresini önemli ölçüde azaltabilir.

Paylaşılan birimleri kullanmak için:

1. **Oluşturma aşamasında**, paylaşılan birime işaret eden `-testProductsPath` parametresini iletin ve uzak yüklemeyi atlamak için `--shard-skip-upload` ekleyin:

```sh
tuist xcodebuild build-for-testing \
  -scheme MyScheme \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  --shard-total 5 \
  --shard-skip-upload \
  -testProductsPath /path/to/shared/volume/$UNIQUE_ID/MyScheme.xctestproducts
```

2. **Test aşamasında**, Tuist'in test ürünlerini indirmek yerine yerel olarak okuması için aynı `-testProductsPath` parametresini iletin:

```sh
tuist xcodebuild test \
  -scheme MyScheme \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  -testProductsPath /path/to/shared/volume/$UNIQUE_ID/MyScheme.xctestproducts
```

> [!IMPORTANT]
> Eşzamanlı çalıştırmalar arasında çakışmaları önlemek için her iş akışı çalıştırmasında benzersiz bir yol kullanın (örneğin, CI çalıştırma kimliğini ekleyin). Birimde eski verilerin birikmesini önlemek için shardlama tamamlandıktan sonra test ürünlerini de temizlemelisiniz.

| Bayrak | Ortam değişkeni | Açıklama |
|------|---------------------|-------------|
| `--shard-skip-upload` | `TUIST_TEST_SHARD_SKIP_UPLOAD` | Test ürünleri paketinin uzak depolamaya yüklenmesini atla |

## Kendi yönettiğiniz artefaktlar {#self-managed-artifacts}

CI sağlayıcınızda zaten artefakt yükleme ve indirme adımları varsa, aktarımı CI'nızın halletmesine izin verirken arşivleme ve çıkarma işlemlerini Tuist'in yapmasını sağlayabilirsiniz.

1. **Oluşturma aşamasında**, Tuist'in test ürünlerini yüklemek yerine optimize edilmiş shard arşivini yerel olarak yazması için `--shard-archive-path` parametresini iletin:

```sh
tuist xcodebuild build-for-testing \
  -scheme MyScheme \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  --shard-total 5 \
  --shard-archive-path /tmp/shards/${UNIQUE_ID}/bundle.aar
```

2. Bu arşivi CI sisteminizin yerel artefakt adımını kullanarak yükleyin.

3. Her **test aşaması** job'ında arşivi indirin ve aynı yolu tekrar Tuist'e iletin:

```sh
tuist xcodebuild test \
  -scheme MyScheme \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  --shard-archive-path /tmp/shards/${UNIQUE_ID}/bundle.aar
```

`--shard-archive-path` ayarlandığında, Tuist uzak test ürünü transferini atlar ve bunun yerine yerel arşivi kullanır. Ayrıca `--shard-skip-upload` parametresini de iletirseniz, arşiv yolu öncelik kazanır.

### Namespace {#namespace}

[Namespace](https://namespace.so) runner'ları GitHub Actions artefaktlarıyla iyi çalışır. Derleme job'unun shard arşivini yerel olarak yazması, yüklenmesi ve `tuist xcodebuild test` komutunu çalıştırmadan önce her shard job'unda indirilmesi için `TUIST_TEST_SHARD_ARCHIVE_PATH` değerini bir kez ayarlayın:

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
