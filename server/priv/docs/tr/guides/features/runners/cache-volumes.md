---
{
  "title": "Önbellek birimleri",
  "titleTemplate": ":title · Çalıştırıcılar · Özellikler · Kılavuzlar · Tuist",
  "description": "GitHub Actions, Buildkite ve GitLab CI ile Tuist Linux veya macOS çalıştırıcı işleri arasında Xcode, modül ve Gradle önbelleklerini ve diğer dizinleri koruyun."
}
---
# Önbellek birimleri {#cache-volumes}

Tuist runner'ları işler arasında önbellekleri saklayabilir, böylece yeni bir runner sıcak başlar. Her iş, en son kaydedilen içeriğin özel, yazılabilir bir kopyasını alır.

- **Yönetilen önbellekler**, Xcode derleme önbelleğini, Tuist'in modül önbelleğini ve Gradle'ın önbelleklerini her biri için tek bir adımla saklar. Tuist, her önbelleğin nerede bulunduğunu bilir ve onu kendi depolama alanında tutar.
- **Özel birimler**, seçtiğiniz bir anahtar altında paket yöneticisinin indirme önbelleği gibi başka dizinleri saklar.

Adımları checkout'tan sonra ve önbellekleri kullanan komutlardan önce ekleyin. Tuist runner'ı olmayan runner'larda hiçbir işlem yapmazlar ve bir önbellek sorunu asla işi başarısız kılmaz: adım bir uyarı günlüğe kaydeder ve iş boş bir önbellekle devam eder.

## Yönetilen önbellekler {#managed-caches}

Adımlar yalnızca önbelleklerin nerede bulunacağını belirler. Mevcut önbellek kurulumunuzu koruyun: `tuist setup cache` veya derleme önbelleğini açan derleme ayarları (bkz. <.localized_link href="/guides/features/cache/xcode-cache">Xcode önbellek kılavuzu</.localized_link>), modül önbelleği için kimlik doğrulama ve Gradle'ın uzak derleme önbelleği için <.localized_link href="/guides/features/cache/gradle-cache">Tuist Gradle eklentisi</.localized_link>. GitLab CI'da snippet'leri `!reference` ile birleştirin, çünkü `extends`, `before_script` yerine geçer.

### Xcode önbelleği {#xcode-cache}

macOS runner'larda Xcode'un derleme önbelleği deposunu saklar.

::: code-group

```yaml [GitHub Actions]
jobs:
  build:
    runs-on: tuist-macos
    steps:
      - uses: actions/checkout@v4
      - uses: tuist/xcode-cache@v1
      - run: xcodebuild build -scheme App -destination 'generic/platform=iOS Simulator' COMPILATION_CACHE_ENABLE_CACHING=YES
```

```yaml [Buildkite]
steps:
  - label: Build
    agents:
      queue: tuist-macos
    plugins:
      - tuist/xcode-cache#v1: ~
    command: xcodebuild build -scheme App -destination 'generic/platform=iOS Simulator' COMPILATION_CACHE_ENABLE_CACHING=YES
```

```yaml [GitLab CI]
include:
  - remote: https://raw.githubusercontent.com/tuist/xcode-cache-gitlab/v1/xcode-cache.yml

build:
  tags: [tuist-macos]
  before_script:
    - !reference [.tuist-xcode-cache, before_script]
  script:
    - xcodebuild build -scheme App -destination 'generic/platform=iOS Simulator' COMPILATION_CACHE_ENABLE_CACHING=YES
```
<!-- -->
:::

### Modül önbelleği {#module-cache}

macOS runner'larda Tuist'in yerel önbelleğini saklar: <.localized_link href="/guides/features/cache/module-cache">modül önbelleği</.localized_link> ikili dosyaları, derlenmiş manifestolar, eklentiler ve seçici test sonuçları.

::: code-group

```yaml [GitHub Actions]
jobs:
  test:
    runs-on: tuist-macos
    permissions:
      contents: read
      id-token: write
    steps:
      - uses: actions/checkout@v4
      - uses: tuist/module-cache@v1
      - uses: jdx/mise-action@v4
      - run: tuist auth login
      - run: tuist install
      - run: tuist generate --no-open
      - run: tuist test
```

```yaml [Buildkite]
steps:
  - label: Test
    agents:
      queue: tuist-macos
    plugins:
      - tuist/module-cache#v1: ~
    command: |
      mise install
      tuist auth login
      tuist install
      tuist generate --no-open
      tuist test
```

```yaml [GitLab CI]
include:
  - remote: https://raw.githubusercontent.com/tuist/module-cache-gitlab/v1/module-cache.yml

test:
  tags: [tuist-macos]
  before_script:
    - !reference [.tuist-module-cache, before_script]
  script:
    - mise install
    - tuist auth login
    - tuist install
    - tuist generate --no-open
    - tuist test
```
<!-- -->
:::

### Gradle önbelleği {#gradle-cache}

Linux ve macOS runner'larda Gradle'ın kullanıcı ev dizinindeki `caches` ve `wrapper` dizinlerini saklar: bağımlılıklar, dönüştürülmüş jar dosyaları, derlenmiş derleme betikleri ve Gradle dağıtımları. Kullanıyorsanız adımdan önce `GRADLE_USER_HOME` ayarlayın ve bu dizinlerin diğer önbelleğe alma işlemlerini, örneğin `actions/setup-java` üzerindeki `cache: gradle` gibi, kapatın.

::: code-group

```yaml [GitHub Actions]
jobs:
  test:
    runs-on: tuist-linux
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-java@v4
        with:
          distribution: temurin
          java-version: '21'
      - uses: tuist/gradle-cache@v1
      - run: ./gradlew test
```

```yaml [Buildkite]
steps:
  - label: Test
    agents:
      queue: tuist-linux
    plugins:
      - tuist/gradle-cache#v1: ~
    command: ./gradlew test
```

```yaml [GitLab CI]
include:
  - remote: https://raw.githubusercontent.com/tuist/gradle-cache-gitlab/v1/gradle-cache.yml

test:
  tags: [tuist-linux]
  before_script:
    - !reference [.tuist-gradle-cache, before_script]
  script:
    - ./gradlew test
```
<!-- -->
:::

## Özel birimler {#custom-volumes}

Kararlı bir `key` ve bir `path` seçin, ardından bağımlılıkları yüklemeden önce birimi bağlayın. Yol boş olmalı veya mevcut olmamalıdır. Aynı dizine yazan herhangi bir arşiv önbelleğini veya yapıt geri yüklemesini kaldırın. Tek bir birimde birden çok dizini saklamak için bkz. [Bir birimde birden çok dizin](#several-directories-in-one-volume).

::: code-group

```yaml [GitHub Actions]
jobs:
  test:
    runs-on: tuist-linux
    steps:
      - uses: actions/checkout@v4
      - uses: tuist/cache-volume@v1
        with:
          key: npm
          path: ~/.npm
      - run: npm ci
      - run: npm test
```

```yaml [Buildkite]
steps:
  - label: Test
    agents:
      queue: tuist-linux
    plugins:
      - tuist/cache-volume#v1:
          volumes:
            - key: npm
              path: ~/.npm
    command: |
      npm ci
      npm test
```

```yaml [GitLab CI]
test:
  tags: [tuist-linux]
  before_script:
    - tuist-cache-volume --key npm --path ~/.npm
  script:
    - npm ci
    - npm test
```
<!-- -->
:::

### Bir birimde birden çok dizin {#several-directories-in-one-volume}

Bir birim birden çok dizin barındırabilir. GitHub Actions'ta satır başına bir yol listeleyin; Buildkite'ta `path` değerini bir listeye ayarlayın; GitLab CI'da dizin başına bir kez `--path` geçirin. Boş satırlar ve çevredeki boşluklar yoksayılır.

::: code-group

```yaml [GitHub Actions]
jobs:
  lint:
    runs-on: tuist-linux
    steps:
      - uses: actions/checkout@v4
      - uses: tuist/cache-volume@v1
        with:
          key: python-tools
          path: |
            ~/.cache/pip
            ~/.cache/pre-commit
      - run: pip install pre-commit
      - run: pre-commit run --all-files
```

```yaml [Buildkite]
steps:
  - label: Lint
    agents:
      queue: tuist-linux
    plugins:
      - tuist/cache-volume#v1:
          volumes:
            - key: python-tools
              path:
                - ~/.cache/pip
                - ~/.cache/pre-commit
    command: |
      pip install pre-commit
      pre-commit run --all-files
```

```yaml [GitLab CI]
lint:
  tags: [tuist-linux]
  before_script:
    - tuist-cache-volume --key python-tools --path ~/.cache/pip --path ~/.cache/pre-commit
  script:
    - pip install pre-commit
    - pre-commit run --all-files
```
<!-- -->
:::

- **Paylaşılan kapasite.** Tüm yollar birimin kapasitesini paylaşır ve birlikte geri yüklenip kaydedilir.
- **Küçük, ilişkili dizinleri gruplayın.** Büyük veya hızlı değişen bir dizine kendi birimini verin.
- **İç içe geçme yok.** Bir birimdeki yollar birbirini içermemelidir.
- **Listeyi değiştirmek soğuk başlatır.** Her yol, birim içindeki kendi dizininde saklanır ve yolun yazım şekliyle tanımlanır. Tek bir yol ile birkaç yol arasında geçiş yapmak veya bir yol eklemek, kaldırmak ya da yeniden yazmak bu düzeni değiştirir: değişiklikten sonraki ilk iş, etkilenen yollar için soğuk başlar. Artık listede olmayan yolların içeriği, siz silene kadar birimde kalır.

### Anahtarlar nasıl çalışır {#how-keys-work}

Bir anahtar, zamanla değişen bir birimi adlandırır; `actions/cache` anahtarı gibi sabit bir anlık görüntünün adı değildir.

- **Anahtar başına bir birim.** Her anahtar depo (Buildkite'ta pipeline; GitLab CI'da proje), platform, CPU mimarisi ve kullanıcı ile sınırlıdır. Onu bağlayan her iş en son kaydedilen içerikten başlar ve uygun işler değişikliklerini aynı birime geri kaydeder.
- **Anahtarları kararlı tutun.** Anahtara sürümleri veya kilit dosyası hash'lerini koymayın. `actions/cache` ile `deps-${{ hashFiles('Package.resolved') }}` gibi bir anahtar her değişiklik için yeni bir giriş oluşturur ve `restore-keys` daha eski birine geri döner. Burada yeni bir anahtar yeni, boş bir birimdir: her değişiklikten sonraki ilk iş soğuk başlar ve eski birimler süresi dolana kadar kalır. Anahtarı koruyun ve aracınızın içeriği güncellemesine izin verin; paket yöneticileri hâlâ geçerli olanları yeniden kullanır.
- **Kısmi eşleşme yok.** Geri yükleme anahtarları yoktur. Henüz kaydedilmemiş bir anahtar boş başlar.
- **`tuist-` ile başlayan anahtarlar ayrılmıştır** ve Tuist'in kendi önbellekleri için kullanılır; birim bağlanmadan önce reddedilirler.
- **Bilerek yeniden başlatın.** Bir işin boş başlamasını istediğinizde anahtarı değiştirin veya birimi silin.
- **`tuist-` anahtarlarını Tuist'e bırakın.** Yönetilen önbellekler `tuist-` ile başlayan anahtarlar kullanır, bu nedenle kendi birimleriniz için farklı bir ad seçin.

Linux'ta yollar normal dizinler olarak bağlanır, bu nedenle araçlar `deps`, `_build` ve `node_modules` gibi alışıldık konumlarını kullanabilir. Normal `.gitignore` kurallarınızı koruyun. macOS'ta yollar sembolik bağlantılardır: `~/.npm` gibi indirme önbelleklerini kullanın; `node_modules` ve önbellek dizinini değiştiren araçlar desteklenmez. `.gitignore` içinde sondaki eğik çizgi olmadan çalışma alanı bağlantılarını yoksayın.

## Değişiklikleri kaydetme {#saving-changes}

Yönetilen önbellekler ve özel birimler, kendi deponuzdaki başarılı işlerin değişikliklerini herhangi bir dalda kaydeder:

| Sağlayıcı | Değişiklikleri kaydeden işler |
| --- | --- |
| GitHub Actions | Depodan gelen push, zamanlanmış, manuel tetiklenen ve pull request işleri |
| Buildkite | Pipeline deposunun webhook ve zamanlanmış derlemeleri, pull request'leri dahil |
| GitLab CI | Projenin push, zamanlanmış ve web pipeline'ları ve bağlantının bir <.localized_link href="/guides/features/runners/ci-providers/gitlab-ci#merge-request-pipelines">API erişim belirteci</.localized_link> olduğunda kendi merge request'lerinin pipeline'ları |

Diğer işler önbelleği kullanabilir ancak değişiklikleri atılır. Buna fork pull request'leri, `pull_request_target` işleri, API veya panelden başlatılan Buildkite derlemeleri, fork'lardan gelen veya API erişim belirteci olmayan GitLab merge request'leri ve etiketler dahildir. Bir birimi değiştirmeyen iş, kaydedilen sürümü olduğu gibi bırakır. Runner profilinde hangi dalların kaydedeceğini daraltabilirsiniz; bkz. [Kaydetme için hangi dalları seçin](#choose-which-branches-save).

Eşzamanlı işler bağımsız çalışır; farklı işlerden gelen değişiklikler birleştirilmez. Kimlik bilgilerini veya yerine konulamaz verileri asla önbelleğe almayın.

### Kaydetme için hangi dalları seçin {#choose-which-branches-save}

Yönetilen önbelleklerin ve özel birimlerin kaydedileceği dalları değiştirebilirsiniz. **Runner'lar → Profiller** bölümünü açın, işlerinizin kullandığı profili düzenleyin ve **Şuradan önbelleği kaydet** seçeneğini genişletin. İşler istedikleri profili kullanır: GitHub Actions'ta `runs-on:`, Buildkite'ta kuyruk olarak veya GitLab CI'da `tags:` içinde. Ayarlar, o profildeki işler tarafından kullanılan tüm birimler için geçerlidir; sonradan oluşturulan birimler de buna dahildir.

![Varsayılan dal açıkken ve ek dallar olarak develop ile release/* eklenmiş şekilde, Kaydetme kaynağı bölümü genişletilmiş runner profili formu](/images/guides/features/runners/save-cache-from.png)

Varsayılan olarak depodan gelen her başarılı iş değişikliklerini kaydeder. Yalnızca bazı dallardan kaydetmek için **Belirli dallarla sınırla** seçeneğini açın:

- **Varsayılan dal**, her deponun varsayılan dalındaki işlerin kaydetmesine olanak tanır. Yalnızca ek dallardan kaydetmek için bunu kapatın.
- **Ek dallar** altında, ayrıca kaydedecek en fazla 20 dal adı ekleyin. Joker karakter olarak `*` kullanın: `release/*`, `release/1.0` ile eşleşir.

[Değişiklikleri kaydetme](#saving-changes) bölümünde listelenen işler, dalları eşleştiğinde değişikliklerini kaydeder. GitHub Actions push ve manuel tetikleme çalıştırmalarında, eşleşen ada sahip bir etiket de eşleşir.

Diğer dallardaki işler hâlâ önbelleği kullanabilir ancak değişiklikleri atılır. Fork pull request'leri gibi hiçbir zaman kaydetmeyen işler, eşleşen bir dalda da kaydetmez. Bu ayarları daraltmak veya profili silmek, artık izin vermedikleri bekleyen değişiklikleri atar; silinen bir profil, her daldan kaydetmeye geri döner.

## Kapasite ve saklama {#capacity-and-retention}

Xcode önbelleği **30 GB** ile başlar. Modül önbelleği, Gradle önbelleği ve her özel birim **20 GB** ile başlar. Bir önbelleğe veya birime farklı bir kapasite vermek için `1gb` ile `100gb` arasında tam sayı GB cinsinden bir boyut ayarlayın:

::: code-group

```yaml [GitHub Actions]
- uses: tuist/xcode-cache@v1
  with:
    size: 50gb
- uses: tuist/module-cache@v1
  with:
    size: 40gb
```

```yaml [Buildkite]
plugins:
  - tuist/xcode-cache#v1:
      size: 50gb
  - tuist/module-cache#v1:
      size: 40gb
```

```yaml [GitLab CI]
build:
  variables:
    TUIST_XCODE_CACHE_SIZE: 50gb
    TUIST_MODULE_CACHE_SIZE: 40gb
```
<!-- -->
:::

Gradle önbelleği ve özel birimler aynı `size` girişini alır (GitLab CI'da `TUIST_GRADLE_CACHE_SIZE` ve `TUIST_VOLUME_SIZE`, `tuist-cache-volume` için `--size`). Daha büyük bir boyut, içeriğini koruyarak birimi sonraki işinden itibaren büyütür. Daha küçük bir boyut, birim bir sonraki silindiğinde veya süresi dolduğunda uygulanır. İşler tek bir önbellek için farklı boyutlar istediğinde en büyük olanı uygulanır, bu nedenle her boyutu tek bir yerde belirtin.

Tümü, **bir iş bağlaması olmadan 7 gün** sonra süresi dolar ve süresi dolduktan sonra sonraki iş boş bir birimle başlar. Tuist, Xcode ve modül önbelleklerini kapasitelerine sığacak şekilde budar ve Gradle önbelleği adımı, her derlemeden sonra yedi gün boyunca kullanılmayan girdileri Gradle tarafından kaldırtır.

Özel birimler eski bağımlılıkları budamaz: bunları küçük tutmak için aracınızın temizleme ayarlarını kullanın. Dolu bir birime yazma işlemi işi başarısız kılabilir. Kaydedilen içerikler birimin kapasitesinin **%80**'ine ulaştığında ve bir iş üzerinde alan bittiğinde, sonraki iş boş bir birimle başlar ve değişiklikleri yeni bir kaydedilen durum başlatır.

## Birimleri inceleme ve silme {#inspecting-and-clearing-volumes}

Kullanılan alanı, önbellek isabeti oranını ve iş geçmişini incelemek için **Runner'lar → Birimler** bölümünü açın. Xcode, modül ve Gradle önbellekleri de burada görünür.

Hesap yöneticileri, bir birimi ve kaydedilen içeriğini kaldırmak için **Birimi sil** seçeneğini belirleyebilir. Çalışan işler özel kopyalarını korur ancak bunları geri kaydedemez ve aynı anahtarı kullanan sonraki iş boş bir birimle başlar. Silinen birimler artık listede görünmez.

Bir birimi terminalden veya bir iş akışından silmek için kimliğini bulun ve `tuist runner volume delete` komutuna iletin:

```bash
tuist runner volume list --account my-org --name gradle-build-cache --json
tuist runner volume delete <volume-id> --account my-org --yes
```

Aynı işlem [API](https://tuist.dev/api/docs#tag/runners) üzerinden `DELETE /api/accounts/{account_handle}/runners/volumes/{volume_id}` olarak ve [MCP sunucusu](/guides/features/agentic-coding/mcp) üzerinden `delete_runner_volume` olarak kullanılabilir. Tümü hesap yöneticiliği veya `account:runners:write` kapsamına sahip bir belirteç gerektirir.
