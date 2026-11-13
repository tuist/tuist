---
{
  "title": "Oluşturulan Xcode projesi",
  "titleTemplate": ":title · Seçici test · Özellikler · Kılavuzlar · Tuist",
  "description": "Tuist Seçici Test ile yalnızca en son değişikliklerinizden etkilenen Xcode ve oluşturulan proje testlerini çalıştırın, böylece sürekli entegrasyon geri bildirimi saniyeler içinde alın."
}
---
# Oluşturulan Xcode projesi {#generated-xcode-project}

Bir proje büyüdükçe, her push işleminde tüm testleri çalıştırmak ölçeklenebilirliğini yitirir. Tuist'in seçici testi, Tuist'in <.localized_link href="/guides/features/projects/hashing">karma algoritmasına</.localized_link> dayanarak yalnızca son başarılı test çalıştırmasından bu yana hedefleri değişen testleri çalıştırır.

<.localized_link href="/guides/features/projects">Oluşturulan projenizle</.localized_link> testleri seçici olarak çalıştırmak için `tuist test` komutunu kullanın. Komut, projenizi <.localized_link href="/guides/features/cache/module-cache">modül önbelleği</.localized_link> için yaptığı gibi <.localized_link href="/guides/features/projects/hashing">karmalar</.localized_link> ve başarılı olduğunda, gelecekteki çalıştırmalarda nelerin değiştiğini belirlemek için karmaları kalıcı hale getirir. Gelecekteki çalıştırmalarda `tuist test`, testleri daraltmak ve yalnızca son başarılı test çalıştırmasından bu yana değişenleri çalıştırmak için karmaları şeffaf bir şekilde kullanır.

`tuist test`, test paketinizi çalıştırırken derleme süresini iyileştirmek amacıyla yerel veya uzak depolamanızdaki ikili dosyaları mümkün olduğunca kullanmak üzere <.localized_link href="/guides/features/cache/module-cache">modül önbelleği</.localized_link> ile doğrudan entegre olur. Seçici testin modül önbellekleme ile birleşimi, CI ortamınızda testleri çalıştırma süresini önemli ölçüde azaltabilir.

Testleriniz yalnızca simülatör hedeflerini çalıştırıyorsa, `tuist test` öğesinin önbelleğe alınmış ikili dosyaların yalnızca simülatör dilimlerini kullanması ve indirmesi için `--destination simulator` parametresini iletin. Bkz. <.localized_link href="/guides/features/cache/module-cache#destination-selection">hedef seçimi</.localized_link>. Seçici test karmaları her `--destination` değeri için aynıdır.

## Derleme ve test işlerini ayırma {#separate-build-and-test-jobs}

Seçici test, ayrı derleme ve test işlerini destekler. Derleme işinde `tuist test --build-only` komutunu çalıştırın; böylece Tuist, derlemenin ürettiği ürünlerin yanında bir `selective-testing-graph.json` dosyasını kalıcı hale getirebilir. Bu grafik, seçici testin ihtiyaç duyduğu karmaları taşır; bu sayede test işi, hangi hedeflerin çalıştırılacağını belirlemek için projeyi yeniden oluşturmak veya Swift Package bağımlılıklarını çözümlemek zorunda kalmaz.

Tuist, `--build-only` sırasında grafiği iki yere yazar:

- `-testProductsPath` parametresini ilettiğinizde `.xctestproducts` paketi içinde.
- Türetilmiş verilerin `Build/Products/` dizini altındaki her bir `.xctestrun` dosyasının yanında.

Her iki çıktıdan birini derlenen ürünlerin yanında önbelleğe alın ve test işinde `--without-building` parametresine aynı yolu iletin. Her iki form da çalışır:

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

Tuist bu grafiği girdinin yanında bulamadığında (örneğin, derleme işi `tuist test --build-only` yerine düz `xcodebuild build-for-testing` kullandığında), etkilenen hedefleri yine de hesaplayabilmek için projeyi yeniden oluşturmaya geri döner. Bu geri dönüş mekanizması, test işinde Swift Package bağımlılıklarının çözülmüş olmasını gerektirir; bu nedenle önce `tuist install` komutunu çalıştırın veya işler arasında `Tuist/.build` öğesini önbelleğe alın.

Grafik, derleme zamanındaki kaynak ağacını yansıtır. Test işini, derleme işiyle aynı commit üzerinde çalıştırın — eğer ikisi arasında kaynak farklılaşırsa, karmalar artık kaynakla eşleşmez ve seçici test, daha yeni kaynağa karşı aslında başarısız olacak testleri atlayabilir.

### Hangi bayrağı kullanmalıyım? {#which-flag-should-i-use}

`.xctestrun` ve `.xctestproducts`, iki farklı Xcode çıktı formatıdır ve taşınabilirlik ile işlem hattı kolaylığı arasında bir denge kurarlar:

- **`-testProductsPath` (`.xctestproducts`) — yeni işlem hatları için önerilir.** Kendi içinde bütünlüklü bir dizindir: derlenen `.xctest` ikili dosyaları ve bunların `.xctestrun` dosyaları, yolları paket köküne göre göreceli olacak şekilde içinde barındırılır; böylece nereye giderse gitsin geçerliliğini korur.
- **`-xctestrun` (ham `.xctestrun`) — zaten türetilmiş veri etrafında kurgulanmış bir işlem hattınız varsa bunu kullanın.** `xcodebuild build-for-testing`, varsayılan olarak `<derivedData>/Build/Products/` konumunun en üstüne bir `.xctestrun` yazar ve onu o ağaçtaki başka yerlerde bulunan test paketlerine yönlendirir. Başka bir işte yeniden kullanmak, `Build/Products/` içindeki yolların bozulmadan kalmasını gerektirir.

Sıfırdan başlıyorsanız `-testProductsPath` tercih edin. Tuist'i, türetilmiş veriyi zaten önbelleğe alan mevcut bir işlem hattına entegre ediyorsanız, derleme işi `tuist test --build-only` üzerinden çalıştığı sürece `-xctestrun` aynı hızlı yolu sağlar.

Her iki giriş modu da `-workspace`/`-project`/`-scheme` ile karşılıklı olarak özel olduğundan, Tuist passthrough argümanları `-xctestrun` veya `-testProductsPath` içerdiğinde bu bayrakları atlar ve seçilen hedefleri `-only-testing` aracılığıyla iletir.

> [!WARNING]
> **Modül ve dosya düzeyinde granülerlik**
>
> Testler ve kaynaklar arasındaki kod içi bağımlılıkların tespit edilmesinin imkansızlığı nedeniyle, varsayılan seçici testin maksimum granülerliği hedef düzeyindedir. [Kapsam stratejisi](#coverage-based-test-selection) bunu tekil XCTest testlerine indirger. Bu nedenle, seçici testin faydalarını en üst düzeye çıkarmak için hedeflerinizi küçük ve odaklı tutmanızı öneririz.


## Kapsama dayalı test seçimi {#coverage-based-test-selection}

> [!NOTE]
> **Erken erişim**
>
> Kapsama dayalı test seçimi erken erişim aşamasındadır. Hesabınızda etkinleştirmek için bizimle iletişime geçin. Etkinleştirilene kadar strateji, varsayılan seçici test gibi davranır.

Varsayılan olarak, seçici test karması daha önce geçen tüm test hedeflerini atlar. `.coverage()` stratejisi daha ileri gider: kalan test hedeflerinde, önceki bir çalıştırmadaki kod kapsamı değişikliğinizin dokunduğu dosyalardan hiçbirini içermeyen XCTest ve XCUITest testlerini de atlar. Bunu `Tuist.swift` içinde etkinleştirin:

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

- **Kapsam yüklemeleri.** Tuist, testleri önceki çalıştırmaların yüklediği kapsama göre seçer; bu nedenle `tuist test`, `.coverage()` ayarını `upload: false` ile yapan bir manifesti yükleyemez.
- Test hedefleriniz tarafından bağlanan **[TestCoverageAttribution](https://github.com/tuist/TestCoverageAttribution) 0.3.0 veya üzeri**. Her testin hangi dosyaları yürüttüğünü kaydeder ve Tuist'in seçmediği testleri atlar. Bu olmadan bir hedef, varsayılandaki gibi yalnızca tamamıyla atlanır.
- **Seçim olmadan varsayılan dalınızda test çalıştırmaları.** Orada ve testlerin atlanmaması gereken diğer dallarda `tuist test --no-selective-testing` komutunu çalıştırın. Bu çalıştırmalar her testi yürütür ve sonraki çalıştırmaların karşılaştıracağı temel referanslar haline gelir.

Strateji açıkken, `tuist test` karması daha önce geçen hedefleri atlar ve ardından Tuist'e, değişikliğinizin kalan hedeflerden hangilerini etkileyebileceğini sorar. Etkilenen testi olmayan hedefler derlenmez. Yeni testler, en son başarısız olan testler, değiştirilmiş bir test dosyasındaki testler ve kaydedilmiş kapsamı olmayan testler her zaman çalışır. Swift Testing testleri, hedefleri çalıştığında yürütülür.

Bazen kapsam uygulanmaz ve çıktı nedenini belirtir: Karması geçmeyen hedeflerin her testi, varsayılan seçici testteki gibi çalışır. Bu durum, aynı platformda yakın tarihli bir temel referans olmadığında, değişikliğin 5.000'den fazla dosyaya dokunduğunda veya herhangi bir testi etkileyebilecek bir dosyanın (`Package.resolved`, `Project.swift` veya bir `.xcconfig` gibi) değiştiğinde gerçekleşir. Her testi çalıştırmak için `--no-selective-testing` parametresini iletin.

> [!NOTE]
> **Test kapsamı**
>
> Tek bir çalıştırmanın raporunu okuyan kapsam araçları (Xcode dahil) tüm test paketinin çalıştığını varsayar; bu nedenle seçici bir çalıştırmanın raporu atladığı testleri dışarıda bırakır. Tuist'in <.localized_link href="/guides/features/test-code-coverage/generated-xcode-project">kod kapsamı</.localized_link> bunun yerine, her çalıştırmada kaydettiği <.localized_link href="/guides/features/test-code-coverage/generated-xcode-project#target-level-coverage">hedef düzeyi kapsamı</.localized_link> kullanarak atlanan test hedeflerinin kapsamını önceki bir çalıştırmadan taşır.


## Çekme/birleştirme isteği yorumları {#pullmerge-request-comments}

> [!WARNING]
> **Git forge entegrasyonu gerekli**
>
> Otomatik çekme/birleştirme isteği yorumları almak için <.localized_link href="/guides/server/accounts-and-projects">Tuist projenizi</.localized_link> bir Git forge ile entegre edin: <.localized_link href="/guides/integrations/gitforge/github">GitHub</.localized_link>, <.localized_link href="/guides/integrations/gitforge/origin">Cursor Origin</.localized_link> veya <.localized_link href="/guides/integrations/gitforge/entire">Entire</.localized_link>.


Tuist projeniz [GitHub](https://github.com) gibi Git platformunuzla bağlantılı hale geldiğinde ve `tuist test` komutunu CI iş akışınızın bir parçası olarak kullanmaya başladığınızda, Tuist doğrudan çekme/birleştirme isteklerinize hangi testlerin çalıştırıldığını ve hangilerinin atlandığını içeren bir yorum ekler: ![Tuist Önizleme bağlantısı içeren GitHub uygulaması yorumu](/images/guides/features/selective-testing/github-app-comment.png)


## Panoda kayıpları inceleme {#investigating-misses-on-the-dashboard}

Daha önce önbelleğe alınmış bir test hedefi kayıp olarak göründüğünde, bir test çalıştırması sayfasındaki **Seçici Test** sekmesi karmayı üreten girdileri derinlemesine incelemenizi sağlar. Bir satırı genişletmek kaynaklar, bağımlılıklar, ortam değişkenleri, proje ve hedef ayarları, Info.plist, yetkiler, başlık dosyaları vb. gibi bileşen başına alt karmaları ortaya çıkarır; böylece çalıştırmalar arasında sapma gösteren girdiyi tam olarak belirleyebilirsiniz.

Seçici Test kartının üst kısmındaki **JSON olarak Kopyala** düğmesini kullanarak her seçici test hedefini karması ve alt karmalarıyla birlikte dışa aktarın. İki çalıştırma arasındaki JSON'u karşılaştırmak, test hedefinin karması saptığında hangi girdinin değiştiğini doğrulamanın en hızlı yoludur.
