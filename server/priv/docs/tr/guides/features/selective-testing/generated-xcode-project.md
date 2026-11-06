---
{
  "title": "Oluşturulan Xcode projesi",
  "titleTemplate": ":title · Seçici test · Özellikler · Kılavuzlar · Tuist",
  "description": "Tuist Seçici Test ile yalnızca en son değişikliklerinizden etkilenen Xcode ve oluşturulmuş proje testlerini çalıştırın, böylece sürekli entegrasyon geri bildirimi saniyeler içinde sunar."
}
---
# Oluşturulan Xcode projesi {#generated-xcode-project}

Proje büyüdükçe, her push işleminden sonra tüm testleri çalıştırmak ölçeklenemez hale gelir. Tuist'in seçici testi, Tuist'in <.localized_link href="/guides/features/projects/hashing">karma algoritmasına</.localized_link> dayanarak yalnızca son başarılı test çalıştırmasından bu yana hedefleri değişen testleri çalıştırır.

<.localized_link href="/guides/features/projects">Oluşturulan projenizle</.localized_link> testleri seçici olarak çalıştırmak için `tuist test` komutunu kullanın. Komut, projenizi <.localized_link href="/guides/features/cache/module-cache">modül önbelleği</.localized_link> için yaptığı gibi <.localized_link href="/guides/features/projects/hashing">karmalar</.localized_link> ve başarı durumunda gelecekteki çalıştırmalarda neyin değiştiğini belirlemek için karmaları kalıcı hale getirir. Gelecekteki çalıştırmalarda `tuist test`, testleri daraltmak ve yalnızca son başarılı test çalıştırmasından bu yana değişenleri çalıştırmak için karmaları şeffaf bir şekilde kullanır.

`tuist test`, test paketinizi çalıştırırken derleme süresini iyileştirmek amacıyla yerel veya uzak depolamanızdaki ikili dosyaları mümkün olduğunca kullanmak üzere <.localized_link href="/guides/features/cache/module-cache">modül önbelleği</.localized_link> ile doğrudan entegre olur. Seçici testin modül önbellekleme ile birleşimi, CI ortamınızda testlerin çalışma süresini önemli ölçüde azaltabilir.

Testleriniz yalnızca simülatör hedeflerini içeriyorsa, `tuist test` öğesinin önbelleğe alınmış ikili dosyaların yalnızca simülatör dilimlerini kullanmasını ve indirmesini sağlamak için `--destination simulator` parametresini iletin. Bkz. <.localized_link href="/guides/features/cache/module-cache#destination-selection">hedef seçimi</.localized_link>. Seçici test karmaları her `--destination` değeri için aynıdır.

## Derleme ve test işlerini ayırma {#separate-build-and-test-jobs}

Seçici test, ayrı derleme ve test işlerini destekler. Derleme işinde `tuist test --build-only` komutunu çalıştırın; böylece Tuist, derlemenin ürettiği ürünlerin yanında bir `selective-testing-graph.json` dosyasını kalıcı hale getirebilir. Bu graf, seçici testin ihtiyaç duyduğu karmaları taşır; bu sayede test işi, hangi hedeflerin çalıştırılacağını belirlemek için projeyi yeniden oluşturmak veya Swift Package bağımlılıklarını çözümlemek zorunda kalmaz.

Tuist, `--build-only` sırasında grafiği iki yere yazar:

- `-testProductsPath` parametresini ilettiğinizde `.xctestproducts` paketi içinde.
- Türetilmiş verilerin `Build/Products/` dizini altındaki her bir `.xctestrun` dosyasının yanında.

Her iki çıktıdan birini derlenen ürünlerin yanında önbelleğe alın ve test işinde aynı yolu `--without-building` parametresine iletin. Her iki yöntem de çalışır:

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

Tuist bu grafiği girdinin yanında bulamazsa (örneğin, derleme işi `tuist test --build-only` yerine düz `xcodebuild build-for-testing` kullandıysa), etkilenen hedefleri yine hesaplayabilmek için projeyi yeniden oluşturmaya geri döner. Bu geri dönüş mekanizması, test işinde Swift Package bağımlılıklarının çözülmüş olmasını gerektirir; bu nedenle önce `tuist install` komutunu çalıştırın veya işler arasında `Tuist/.build` önbelleğe alın.

Graf, derleme zamanındaki kaynak ağacını yansıtır. Test işini, derleme işiyle aynı commit üzerinde çalıştırın — eğer ikisi arasında kaynak farklılaşırsa, karmalar artık kaynakla eşleşmez ve seçici test, yeni kaynağa karşı aslında başarısız olacak testleri atlayabilir.

### Hangi bayrağı kullanmalıyım? {#which-flag-should-i-use}

`.xctestrun` ve `.xctestproducts`, iki farklı Xcode çıktı formatıdır ve taşınabilirlik ile pipeline kolaylığı arasında bir denge sunar:

- **`-testProductsPath` (`.xctestproducts`) — yeni pipeline'lar için önerilir.** Kendi kendine yeten bir dizindir: derlenen `.xctest` ikili dosyaları ve bunların `.xctestrun` dosyaları, yolları paket köküne göreli hale getirilmiş şekilde içinde bulunur; bu sayede nereye giderse geçersizliğini korumaz.
- **`-xctestrun` (ham `.xctestrun`) — türetilmiş veri etrafında zaten bir pipeline kurduysanız bunu kullanın.** `xcodebuild build-for-testing`, varsayılan olarak `<derivedData>/Build/Products/` üst kısmına bir `.xctestrun` yazar ve onu o ağaçtaki başka yerlerde bulunan test paketlerine işaret eder. Başka bir işte yeniden kullanmak, `Build/Products/` içindeki yolların bozulmadan kalmasını gerektirir.

Yeni başlıyorsanız `-testProductsPath` tercih edin. Türetilmiş veriyi zaten önbelleğe alan mevcut bir pipeline'a Tuist'i entegre ediyorsanız, derleme işi `tuist test --build-only` üzerinden çalıştığı sürece `-xctestrun` aynı hızlı yolu izler.

Her iki giriş modu da `-workspace`/`-project`/`-scheme` ile karşılıklı olarak dışlayıcıdır; bu nedenle passthrough argümanları `-xctestrun` veya `-testProductsPath` içerdiğinde Tuist bu bayrakları atlar ve seçilen hedefleri `-only-testing` aracılığıyla iletir.

> [!WARNING]
> **Modül ve dosya düzeyinde granülerlik**
>
> Testler ve kaynaklar arasındaki kod içi bağımlılıkları tespit etmenin imkansızlığı nedeniyle, varsayılan seçici testin maksimum granülerliği hedef düzeyindedir. [Kapsama stratejisi](#coverage-based-test-selection) bunu tekil XCTest testlerine kadar daraltır. Bu nedenle, seçici testin faydalarını en üst düzeye çıkarmak için hedeflerinizi küçük ve odaklı tutmanızı öneririz.


## Kapsam tabanlı test seçimi {#coverage-based-test-selection}

> [!NOTE]
> **Erken erişim**
>
> Kapsam tabanlı test seçimi erken erişim aşamasındadır. Hesabınızda etkinleştirmek için bizimle iletişime geçin. Etkinleştirilene kadar strateji, varsayılan seçici test gibi davranır.

Varsayılan olarak seçici test, karması daha önce geçen tüm test hedeflerini atlar. `.coverage()` stratejisi daha ileri gider: kalan test hedeflerinde, daha önceki bir çalıştırmadaki kod kapsamının değişikliğinizin dokunduğu hiçbir dosyayı içermeyen XCTest ve XCUITest testlerini de atlar. Bunu `Tuist.swift` içinde etkinleştirin:

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

- **Kapsam yüklemeleri.** Tuist, testleri önceki çalıştırmaların yüklediği kapsama verilerine göre seçer; bu nedenle `tuist test`, `.coverage()` ayarını `upload: false` ile yapan bir manifesti yükleyemez.
- Test hedefleriniz tarafından bağlanan **[TestCoverageAttribution](https://github.com/tuist/TestCoverageAttribution) 0.3.0 veya sonrası**. Her testin hangi dosyaları yürüttüğünü kaydeder ve Tuist'in seçmediği testleri atlar. Bu olmadan bir hedef, varsayılandaki gibi yalnızca tamamıyla atlanır.
- **Seçim olmadan varsayılan dalınızda test çalıştırmaları.** Orada ve testlerin atlanmaması gereken diğer dallarda `tuist test --no-selective-testing` komutunu çalıştırın. Bu çalıştırmalar her testi yürütür ve sonraki çalıştırmaların karşılaştıracağı temel çizgiler haline gelir.

Strateji açıkken `tuist test`, karması daha önce geçen hedefleri atlar ve ardından Tuist'e, değişiklikinizin kalan hedeflerden hangilerini etkileyebileceğini sorar. Etkilenen testi olmayan hedefler derlenmez. Yeni testler, son seferde başarısız olan testler, değişen bir test dosyasındaki testler ve kaydedilmiş kapsamı olmayan testler her zaman çalışır. Swift Testing testleri, hedefleri çalıştığında yürütülür.

Kapsam karar veremediğinde, çıktı nedenini belirtir. Aynı platformda yakın tarihli bir temel çizgi yoksa veya değişiklik 5.000'den fazla dosyayı etkiliyorsa, commit'in temel çizgi olabilmesi için her test çalıştırılır. Herhangi bir testi etkileyebilecek bir dosya değiştiğinde, örneğin `Package.resolved`, `Project.swift` veya bir `.xcconfig`, çalıştırma varsayılan seçici testi kullanır. Her testi çalıştırmak için `--no-selective-testing` parametresini iletin.

> [!NOTE]
> **Test kapsamı**
>
> Tek bir çalıştırmanın raporunu okuyan kapsam araçları, Xcode da dahil olmak üzere, tüm test paketinin çalıştığını varsayar; bu nedenle seçici bir çalıştırmanın raporu atladığı testleri dışarıda bırakır. Tuist'in <.localized_link href="/guides/features/test-code-coverage/generated-xcode-project">kod kapsamı</.localized_link> ise her çalıştırmada kaydettiği <.localized_link href="/guides/features/test-code-coverage/generated-xcode-project#target-level-coverage">hedef düzeyi kapsamı</.localized_link> kullanarak, atlanan test hedeflerinin kapsam verilerini önceki bir çalıştırmadan taşır.


## Çekme/birleştirme isteği yorumları {#pullmerge-request-comments}

> [!WARNING]
> **Git platform entegrasyonu gerekli**
>
> Otomatik çekme/birleştirme isteği yorumları almak için <.localized_link href="/guides/server/accounts-and-projects">Tuist projenizi</.localized_link> bir <.localized_link href="/guides/server/authentication">Git platformuyla</.localized_link> entegre edin.


Tuist projeniz [GitHub](https://github.com) gibi Git platformunuzla bağlantılı hale geldiğinde ve CI iş akışınızın bir parçası olarak `tuist test` kullanmaya başladığınızda, Tuist doğrudan çekme/birleştirme isteklerinize hangi testlerin çalıştırıldığını ve hangilerinin atlandığını içeren bir yorum ekler: ![Bir Tuist Önizleme bağlantısı içeren GitHub uygulaması yorumu](/images/guides/features/selective-testing/github-app-comment.png)


## Panoda isabet dışı durumları inceleme {#investigating-misses-on-the-dashboard}

Daha önce önbelleğe alınmış bir test hedefi isabet dışı olarak göründüğünde, bir test çalıştırması sayfasındaki **Seçici Test** sekmesi, karmayı üreten girdileri detaylıca incelemenizi sağlar. Bir satırı genişlettiğinizde kaynaklar, bağımlılıklar, ortam değişkenleri, proje ve hedef ayarları, Info.plist, yetkiler, başlık dosyaları gibi bileşen bazlı alt karmalar ortaya çıkar; böylece çalıştırmalar arasında değişen girdiyi tam olarak tespit edebilirsiniz.

Seçici Test kartının üst kısmındaki **JSON olarak Kopyala** düğmesini kullanarak her seçici test hedefini karması ve alt karmalarıyla birlikte dışa aktarın. Test hedefinin karması değiştiğinde hangi girdinin değiştiğini doğrulamanın en hızlı yolu, iki çalıştırma arasındaki JSON'ı karşılaştırmaktır.
