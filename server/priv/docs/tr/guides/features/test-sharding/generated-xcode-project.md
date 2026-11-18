---
{
  "title": "Oluşturulan Xcode projesi",
  "titleTemplate": ":title · Test parçalama · Özellikler · Kılavuzlar · Tuist",
  "description": "Tuist Test Parçalama ile, Tuist tarafından oluşturulan bir Xcode projesindeki testleri birden fazla CI çalıştırıcısına dağıtın."
}
---
# Oluşturulan Xcode projesi {#generated-xcode-project-test-sharding}

Oluşturulan projeler için test parçalama, hem derleme hem de test aşamalarında `tuist test` kullanır.

## Nasıl çalışır {#how-it-works}

Test parçalama iki aşamalı bir iş akışı izler:

1. **Derleme aşaması:** Tuist, oluşturulmuş `.xctestrun` dosyasından test modüllerini okur ve sunucuda bir **parça planı** oluşturur. Sunucu, her parçanın yaklaşık olarak aynı süreyi alması için testleri parçalara dağıtmak amacıyla son 30 güne ait geçmiş test zamanlama verilerini kullanır. Derleme aşaması, CI sisteminizin paralel çalıştırıcıları başlatmak için kullandığı bir **parça matrisi** çıktısı verir.
2. **Test aşaması:** Her sürekli entegrasyon çalıştırıcısı bir **parça dizini** ve tam **parça planı tanımlayıcısını** alır, ardından o planın test seçimini yürütür.

`--shard-granularity suite` kullanıldığında, sunucu mevcut `.xctestrun` içindeki her modül için dalınızda yapılan son CI çalıştırmalarının bildirdiği paketleri kullanır; dal geçmişi olmayan modüller için projenin varsayılan dalına geri döner. Birden fazla çalıştırmayı birleştirmek, parçalı veya seçici bir çalıştırmanın en son raporda dışarıda bıraktığı paketleri korur. Sunucu, süreleri tahmin etmek için son 30 güne ait paket zamanlamalarını kullanır.

Tuist, bilinen bu paketleri istenen parça sayısı arasında dengeler ve son parçayı yakalayıcı olarak kullanır. Örneğin, `--shard-total 5` `0` ile `4` arasında parça dizinleri üretir; burada `4` parça dizini yakalayıcıdır. Normal parçalar, atanmış paketleri için `-only-testing` ile çalışır. Son parça `-only-testing` olmadan çalışır ve önceki parçalara atanmış her paket için `-skip-testing` geçirir; böylece yeni eklenen paketleri, yeniden adlandırılan paketleri veya geçmiş envanterde eksik olan paketleri de çalıştırır. Modül granülaritesi bir yakalayıcıya ihtiyaç duymaz çünkü `.xctestrun` dosyası modül listesini sağlar.

## Derleme aşaması {#build-phase}

Projenizi oluşturun, testlerinizi derleyin ve bir parça planı oluşturun:

```sh
tuist test --build-only --shard-total 5
```

`--build-only` bayrağı, Tuist’e testleri çalıştırmadan derlemesini söyler. Parça planlama bayraklarını (`--shard-min`/`--shard-max`/`--shard-total`) `--build-only` olmadan geçerseniz Tuist hata verir.

Bu komut:
1. Manifest’lerinizden Xcode projesini oluşturur
2. Testlerinizi derler
3. Geçmiş zamanlama verilerini kullanarak Tuist sunucusunda bir parça planı oluşturur
4. `.xctestproducts` paketini yükler veya parça çalıştırıcılarının kullanımı için bir parça arşivi yazar
5. CI sisteminiz için bir parça matrisi çıktısı verir
6. Parça çalıştırıcılarının projeyi yeniden oluşturmasına gerek kalmaması için (varsa) <.localized_link href="/guides/features/selective-testing">seçici test</.localized_link> grafiğini kalıcı hale getirir

<!-- @snippet: ./_xcode-build-options -->

## Test aşaması {#test-phase}

Her parça çalıştırıcısı kendisine atanan testleri yürütür:

```sh
tuist test --without-building
```

`--without-building` bayrağı, Tuist’e testleri yeniden derlemek yerine önceden derlenmiş ürünleri kullanarak çalıştırmasını söyler. `TUIST_SHARD_INDEX` / `--shard-index` ayarlandığında `--without-building` olmadan Tuist hata verir.

<!-- @snippet: ./_xcode-test-options -->

> [!TIP]
> **Seçici test**
>
> Test parçalama, <.localized_link href="/guides/features/selective-testing">seçici test</.localized_link> ile sorunsuz çalışır. Seçici test grafiği derleme aşamasında kalıcı hale getirilir ve her parça için geri yüklenir, böylece çalıştırıcıların projeyi yeniden oluşturmasına gerek kalmaz.

## Sürekli entegrasyon {#continuous-integration}

<!-- @snippet: ./_ci-providers -->

### GitHub Actions {#github-actions}

Parçaları paralel çalıştırmak için bir matris stratejisi kullanın:

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

Tuist, bir [alt boru hattı](https://docs.gitlab.com/ci/pipelines/downstream_pipelines/#parent-child-pipelines) olarak tetikleyeceğiniz bir `.tuist-shard-child-pipeline.yml` oluşturur. Oluşturulan parça işlerinin genişleteceği bir `.tuist-shard` şablon işi tanımlayın:

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

Tuist, [süreklilik orb’ı](https://circleci.com/developer/orbs/orb/circleci/continuation) için parametreler içeren bir `.tuist-shard-continuation.json` oluşturur. `shard-plan-id` parametresi devam eden yapılandırmanızda bildirilmelidir:

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

Tuist, parça başına bir adım içeren bir `.tuist-shard-pipeline.yml` oluşturur. Bunu `buildkite-agent pipeline upload` ile yükleyin:

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

Oluşturulan her adımda ortamında `TUIST_SHARD_INDEX` ve `TUIST_SHARD_PLAN_ID` ayarlanır. Paylaşılan bir betik kullanarak her parça adımına test komutunu ekleyin:

```bash
# .buildkite/shard-step.sh
#!/bin/bash
tuist auth login
tuist test --without-building
```

### Codemagic {#codemagic}

Codemagic dinamik matris işlerini desteklemez, bu nedenle parça başına ayrı bir iş akışı tanımlayın. Tuist, derleme iş akışı içinde kullanım için `TUIST_SHARD_MATRIX` ve `TUIST_SHARD_COUNT` değerlerini `CM_ENV` dosyasına yazar. Codemagic’in `CM_ENV` iş akışı kapsamındadır, bu nedenle tam parça planı tanımlayıcısı iş akışı sınırlarını aşmaz; test iş akışları referans tabanlı parça aramasına geri döner:

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

Bitrise’te Tuist, `.tuist-shard-matrix.json` (`shard_plan_id` dahil) dosyasını `BITRISE_DEPLOY_DIR` konumuna yazar ve bunu aşağı akış boru hattı aşamaları için bir derleme yapıtı olarak kullanılabilir hale getirir. Her test iş akışı, plan kimliğini indirilen yapıttan `envman` kullanarak çıkarır ve böylece test komutunun ortamına ulaşır:

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
> Bitrise çalışma zamanında dinamik paralel iş oluşturmayı desteklemez. Boru hattı aşamalarınızda sabit sayıda parça iş akışı tanımlayın — bir aşama içindeki iş akışları otomatik olarak paralel çalışır.

## Paylaşılan birimler {#shared-volumes}

Varsayılan olarak, derleme aşaması `.xctestproducts` paketini uzak depolamaya yükler ve her parça çalıştırıcısı bunu indirir. CI sağlayıcınız **paylaşılan birimleri** (işler arasında monte edilen kalıcı depolama) destekliyorsa, test ürünlerini paylaşılan bir dosya sistemi üzerinden geçirerek bu yükleme/indirme işlemini tamamen atlayabilirsiniz.

Bu, özellikle büyük test paketleri için parça başlatma süresini önemli ölçüde azaltabilir.

Paylaşılan birimleri kullanmak için:

1. **Derleme aşamasında**, paylaşılan birimi işaret eden `-testProductsPath` (`--` sonrası) parametresini geçin ve uzak yüklemeyi atlamak için `--shard-skip-upload` ekleyin:

```sh
tuist test \
  --build-only \
  --shard-total 5 \
  --shard-skip-upload \
  -- \
  -testProductsPath /path/to/shared/volume/$UNIQUE_ID/MyScheme.xctestproducts
```

2. **Test aşamasında**, Tuist'in test ürünlerini indirmek yerine yerel olarak okuması için aynı `-testProductsPath` parametresini geçin:

```sh
tuist test --without-building -- -testProductsPath /path/to/shared/volume/$UNIQUE_ID/MyScheme.xctestproducts
```

| Bayrak | Ortam değişkeni | Açıklama |
|------|---------------------|-------------|
| `--shard-skip-upload` | `TUIST_TEST_SHARD_SKIP_UPLOAD` | Test ürünleri paketinin uzak depolamaya yüklenmesini atla |

## Kendi yönettiğiniz yapıtlar {#self-managed-artifacts}

CI sağlayıcınızda zaten yapıt yükleme ve indirme adımları varsa, arka plan aktarımını CI'nızın halletmesine izin verirken arşivleme ve çıkarma işlemlerini Tuist'e bırakabilirsiniz.

1. **Derleme aşamasında**, Tuist'in test ürünlerini yüklemek yerine optimize edilmiş parça arşivini yerel olarak yazması için `--shard-archive-path` parametresini geçin:

```sh
tuist test \
  --build-only \
  --shard-total 5 \
  --shard-archive-path /tmp/shards/${UNIQUE_ID}/bundle.aar
```

2. Bu arşivi CI sisteminizin yerel yapıt adımı kullanarak yükleyin.

3. Her **test aşaması** işinde arşivi indirin ve aynı yolu tekrar Tuist'e geçin:

```sh
tuist test \
  --without-building \
  --shard-archive-path /tmp/shards/${UNIQUE_ID}/bundle.aar
```

`--shard-archive-path` ayarlandığında, Tuist uzak test ürünü aktarımını atlar ve bunun yerine yerel arşivi kullanır. Ayrıca `--shard-skip-upload` geçerseniz, arşiv yolu öncelik kazanır.

Örneğin seçici test her test hedefini atladığı için çalıştırılacak test olmadığında, derleme aşaması boş bir parça matrisi çıktılar ve hiçbir arşiv yazmaz. Yükleme adımını yalnızca matriste parçalar olduğunda çalıştırın.

> [!IMPORTANT]
> Eşzamanlı çalıştırmalar arasında çakışmaları önlemek için iş akışı çalıştırması başına benzersiz bir yol kullanın (örneğin CI çalıştırma kimliğini dahil edin). Çalıştırıcıda eski verilerin birikmesini önlemek için parçalama tamamlandıktan sonra parça arşivini de temizlemelisiniz.

### Namespace {#namespace}

[Namespace](https://namespace.so) çalıştırıcıları GitHub Actions yapıtlarıyla iyi çalışır. Derleme işinin parça arşivini yerel olarak yazması, yüklenmesi ve her parça işinde `tuist test` çalıştırılmadan önce indirilmesi için `TUIST_TEST_SHARD_ARCHIVE_PATH` değerini bir kez ayarlayın:

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
