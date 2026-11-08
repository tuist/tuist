---
{
  "title": "Oluşturulan Xcode projesi",
  "titleTemplate": ":title · Seçici test · Özellikler · Kılavuzlar · Tuist",
  "description": "Tuist Seçici Test ile en son değişikliklerinizden etkilenen yalnızca Xcode ve oluşturulan proje testlerini çalıştırın, böylece sürekli entegrasyon geri bildirimi saniyeler içinde sağlar."
}
---
# Oluşturulan Xcode projesi {#generated-xcode-project}

Bir proje büyüdükçe, her push işlemi için tüm testleri çalıştırmak ölçeklenebilirliğini yitirir. Tuist'in seçici testi, Tuist'in <.localized_link href="/guides/features/projects/hashing">hashing algoritmasına</.localized_link> dayanarak yalnızca son başarılı test çalıştırmasından bu yana hedefleri değişen testleri çalıştırır.

<.localized_link href="/guides/features/projects">Oluşturulan projenizle</.localized_link> testleri seçici olarak çalıştırmak için `tuist test` komutunu kullanın. Komut, projenizi <.localized_link href="/guides/features/cache/module-cache">modül önbelleği</.localized_link> için yaptığı gibi <.localized_link href="/guides/features/projects/hashing">hash'ler</.localized_link> ve başarı durumunda, gelecekteki çalıştırmalarda nelerin değiştiğini belirlemek için hash değerlerini kalıcı hale getirir. Gelecekteki çalıştırmalarda, `tuist test` testleri daraltmak ve yalnızca son başarılı test çalıştırmasından bu yana değişenleri çalıştırmak için hash değerlerini şeffaf bir şekilde kullanır.

`tuist test`, test paketinizi çalıştırırken derleme süresini iyileştirmek amacıyla yerel veya uzak depolamanızdaki ikili dosyaları mümkün olduğunca kullanmak üzere <.localized_link href="/guides/features/cache/module-cache">modül önbelleği</.localized_link> ile doğrudan entegre olur. Seçici testin modül önbellekleme ile birleşimi, CI ortamınızda testlerin çalıştırılma süresini önemli ölçüde azaltabilir.

Testleriniz yalnızca simülatör hedeflerini çalıştırıyorsa, `tuist test` tarafından önbelleğe alınmış ikili dosyaların yalnızca simülatör dilimlerini kullanması ve indirmesi için `--destination simulator` parametresini geçirin. Bkz. <.localized_link href="/guides/features/cache/module-cache#destination-selection">hedef seçimi</.localized_link>. Seçici test hash değerleri her `--destination` değeri için aynıdır.

## Derleme ve test işlerini ayırma {#separate-build-and-test-jobs}

Seçici test, ayrı derleme ve test işlerini destekler. Derleme işinde `tuist test --build-only` komutunu çalıştırın; böylece Tuist, derlemenin ürettiği ürünlerin yanında bir `selective-testing-graph.json` dosyasını kalıcı hale getirebilir. Bu grafik, seçici testin ihtiyaç duyduğu hash değerlerini taşır; bu sayede test işi, hangi hedeflerin çalıştırılacağını belirlemek için projeyi yeniden oluşturmak veya Swift Package bağımlılıklarını çözmek zorunda kalmaz.

Tuist, `--build-only` sırasında grafiği iki yere yazar:

- `-testProductsPath` parametresini geçtiğinizde `.xctestproducts` paketi içinde.
- Türetilmiş verilerin `Build/Products/` dizini altındaki her bir `.xctestrun` dosyasının yanında.

Her iki çıktıdan birini derlenen ürünlerin yanında önbelleğe alın ve test işinde aynı yolu `--without-building` parametresine iletin. Her iki form da çalışır:

```sh
# Build job — writes an .xctestproducts bundle with the graph inside it.
tuist test MyScheme \
  --build-only \
  -- \
  -testProductsPath artifacts/MyScheme.xctestproducts \
  -destination 'platform=iOS Simulator,id=SIMULATOR_IDENTIFIER'

# Test job — restores the same bundle.
tuist test MyScheme \
  --without-building \
  -- \
  -testProductsPath artifacts/MyScheme.xctestproducts \
  -destination 'platform=iOS Simulator,id=SIMULATOR_IDENTIFIER'
```

```sh
# Build job — writes the graph as a sibling of each xctestrun in derived data.
tuist test MyScheme \
  --build-only \
  -- \
  -derivedDataPath artifacts/derived-data

# Test job — points --without-building at any of those xctestrun files.
tuist test MyScheme \
  --without-building \
  -- \
  -derivedDataPath artifacts/derived-data \
  -destination 'platform=iOS Simulator,id=SIMULATOR_IDENTIFIER' \
  -xctestrun artifacts/derived-data/Build/Products/MyScheme_iphonesimulator.xctestrun
```

Tuist bu grafiği girdinin yanında bulamadığında (örneğin, derleme işi `tuist test --build-only` yerine düz `xcodebuild build-for-testing` kullandığında), etkilenen hedefleri yine de hesaplayabilmek için projeyi yeniden oluşturmaya geri döner. Bu geri dönüş mekanizması, test işinde Swift Package bağımlılıklarının çözülmesini gerektirir; bu nedenle önce `tuist install` komutunu çalıştırın veya işler arasında `Tuist/.build` dizinini önbelleğe alın.

Grafik, derleme zamanındaki kaynak ağacını yansıtır. Test işini, derleme işiyle aynı commit üzerinde çalıştırın — eğer ikisi arasında kaynak farklılaşırsa, hash değerleri artık kaynakla eşleşmez ve seçici test, yeni kaynağa karşı aslında başarısız olacak testleri atlayabilir.

### Hangi bayrağı kullanmalıyım? {#which-flag-should-i-use}

`.xctestrun` ve `.xctestproducts`, iki farklı Xcode çıktı formatıdır ve taşınabilirlik ile pipeline kolaylığı arasında bir denge kurarlar:

- **`-testProductsPath` (`.xctestproducts`) — yeni pipeline'lar için önerilir.** Kendi kendine yeten bir dizindir: derlenen `.xctest` ikili dosyaları ve bunların `.xctestrun` dosyaları, yolları paket köküne göreli hale getirilmiş olarak içinde bulunur; bu sayede nereye giderse geçerliliğini korur.
- **`-xctestrun` (ham `.xctestrun`) — türetilmiş veri etrafında zaten kurulmuş bir pipeline'ınız varsa bunu kullanın.** `xcodebuild build-for-testing`, varsayılan olarak `<derivedData>/Build/Products/` konumunun en üstüne bir `.xctestrun` yazar ve onu o ağaçtaki başka yerlerde bulunan test paketlerine işaret eder. Başka bir işte yeniden kullanmak, `Build/Products/` içindeki yolların bozulmadan kalmasını gerektirir.

Yeni başlıyorsanız, `-testProductsPath` tercih edin. Tuist'i, türetilmiş verileri zaten önbelleğe alan mevcut bir pipeline'a entegre ediyorsanız, derleme işi `tuist test --build-only` üzerinden çalıştığı sürece `-xctestrun` aynı hızlı yolu izler.

Her iki giriş modu da `-workspace`/`-project`/`-scheme` ile karşılıklı olarak dışlayıcıdır; bu nedenle passthrough argümanları `-xctestrun` veya `-testProductsPath` içerdiğinde Tuist bu bayrakları atlar ve seçilen hedefleri `-only-testing` aracılığıyla iletir.

> [!WARNING]
> **Modül ve dosya düzeyinde granülerlik**
>
> Testler ve kaynaklar arasındaki kod içi bağımlılıkların tespit edilmesinin imkansızlığı nedeniyle, varsayılan seçici testin maksimum granülerliği hedef düzeyindedir. [Kapsam stratejisi](#coverage-based-test-selection) bunu tekil XCTest testlerine kadar daraltır. Bu nedenle, seçici testin faydalarını en üst düzeye çıkarmak için hedeflerinizi küçük ve odaklı tutmanızı öneririz.


## Kapsama dayalı test seçimi {#coverage-based-test-selection}

> [!NOTE]
> **Erken erişim**
>
> Kapsama dayalı test seçimi erken erişim aşamasındadır. Hesabınızda etkinleştirmek için bizimle iletişime geçin. Etkinleştirilene kadar strateji, varsayılan seçici test gibi davranır.

Varsayılan olarak, seçici test hash değeri daha önce geçen tüm test hedeflerini atlar. `.coverage()` stratejisi daha ileri gider: kalan test hedeflerinde, değişiklikinizin dokunduğu dosyalardan hiçbirini içermeyen XCTest ve XCUITest testlerini de atlar. Bunu `Tuist.swift` içinde etkinleştirin:

```swift
import ProjectDescription

let tuist = Tuist(
    fullHandle: "{account-handle}/{project-handle}",
    testInsights: .testInsights(
        coverage: .coverage(upload: true),
        selectiveTesting: .selectiveTesting(strategy: .coverage())
    ),
    project: .tuist()
)
```

Strateji şunları gerektirir:

- **Kapsam yüklemeleri.** Tuist, testleri önceki çalıştırmaların yüklediği kapsama verilerine göre seçer; bu nedenle `tuist test`, `upload: false` olarak ayarlanmış `.coverage()` içeren bir manifesti yükleyemez.
- Test hedefleriniz tarafından bağlantısı kurulmuş **[TestCoverageAttribution](https://github.com/tuist/TestCoverageAttribution) 0.3.0 veya sonrası**. Her testin hangi dosyaları yürüttüğünü kaydeder ve Tuist'in seçmediği testleri atlar. Bu olmadan bir hedef, varsayılan davranışta olduğu gibi yalnızca tamamıyla atlanır.
- **Varsayılan dalınızda seçim olmadan test çalıştırmaları.** Orada ve testlerin atlanmaması gereken diğer dallarda `tuist test --no-selective-testing` komutunu çalıştırın. Bu çalıştırmalar her testi yürütür ve sonraki çalıştırmaların karşılaştıracağı temel çizgiler haline gelir.

Strateji açıkken, `tuist test` hash değeri daha önce geçen hedefleri atlar, ardından Tuist'e değişiklikinizin kalan hedeflerin hangi testlerini etkileyebileceğini sorar. Etkilenen testi olmayan hedefler derlenmez. Yeni testler, son seferde başarısız olan testler, değiştirilmiş bir test dosyasındaki testler ve kaydedilmiş kapsamı olmayan testler her zaman çalışır. Swift Testing testleri, hedefleri çalıştığında yürütülür.

Bazen kapsam uygulanmaz ve çıktı nedenini belirtir: hash değeri geçmeyen hedeflerin her testi, varsayılan seçici testte olduğu gibi çalışır. Bu durum, aynı platformda yakın tarihli bir temel çizgi olmadığında, değişikliğin 5.000'den fazla dosyayı etkilediğinde veya `Package.resolved`, `Project.swift` ya da bir `.xcconfig` gibi herhangi bir testi etkileyebilecek bir dosya değiştiğinde gerçekleşir. Her testi çalıştırmak için `--no-selective-testing` parametresini geçirin.

> [!NOTE]
> **Test kapsamı**
>
> Tek bir çalıştırmanın raporunu okuyan kapsam araçları (Xcode dahil) tüm test paketinin çalıştığını varsayar; bu nedenle seçici bir çalıştırmanın raporu atlanan testleri dışarıda bırakır. Tuist'in <.localized_link href="/guides/features/test-code-coverage/generated-xcode-project">kod kapsamı</.localized_link> bunun yerine, her çalıştırmada kaydettiği <.localized_link href="/guides/features/test-code-coverage/generated-xcode-project#target-level-coverage">hedef düzeyi kapsam</.localized_link> verilerini kullanarak atlanan test hedeflerinin kapsamını önceki bir çalıştırmadan taşır.


## Çekme/birleştirme isteği yorumları {#pullmerge-request-comments}

> [!WARNING]
> **Git platform entegrasyonu gerekli**
>
> Otomatik çekme/birleştirme isteği yorumları almak için <.localized_link href="/guides/server/accounts-and-projects">Tuist projenizi</.localized_link> bir <.localized_link href="/guides/server/authentication">Git platformu</.localized_link> ile entegre edin.


Tuist projeniz [GitHub](https://github.com) gibi Git platformunuzla bağlantılı hale geldiğinde ve CI iş akışınızın bir parçası olarak `tuist test` kullanmaya başladığınızda, Tuist çekme/birleştirme isteklerinize doğrudan bir yorum ekler; hangi testlerin çalıştırıldığını ve hangilerinin atlandığını içerir: ![Tuist Önizleme bağlantısı içeren GitHub uygulaması yorumu](/images/guides/features/selective-testing/github-app-comment.png)


## Panoda isabet eksikliklerini inceleme {#investigating-misses-on-the-dashboard}

Daha önce önbelleğe alınmış bir test hedefi isabet eksikliği olarak göründüğünde, bir test çalıştırması sayfasındaki **Seçici Test** sekmesi hash değerini üreten girdileri detaylıca incelemenize olanak tanır. Bir satırı genişlettiğinizde kaynaklar, bağımlılıklar, ortam değişkenleri, proje ve hedef ayarları, Info.plist, yetkiler, başlık dosyaları gibi bileşen bazlı alt hash değerleri ortaya çıkar; böylece çalıştırmalar arasında sapma gösteren girdiyi tespit edebilirsiniz.

Her seçici test hedefini hash ve alt hash değerleriyle birlikte dışa aktarmak için Seçici Test kartının üst kısmındaki **JSON olarak kopyala** düğmesini kullanın. İki çalıştırma arasındaki JSON'u karşılaştırmak, test hedefinin hash değeri saptığında hangi girdinin değiştiğini doğrulamanın en hızlı yoludur.
