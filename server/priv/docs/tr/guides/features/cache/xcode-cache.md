---
{
  "title": "Xcode önbelleği",
  "titleTemplate": ":title · Önbellek · Özellikler · Kılavuzlar · Tuist",
  "description": "Tuist'in Xcode önbelleği entegrasyonu ile yerel ortamda ve CI üzerinde Xcode derlemelerini hızlandırın."
}
---
# Xcode önbelleği {#xcode-cache}

Tuist, derleme sisteminin önbellekleme yeteneklerinden yararlanarak ekiplerin derleme yapıtlarını paylaşmasına olanak tanıyan Xcode derleme önbelleği desteği sağlar.

Xcode önbelleği Xcode 26'da tanıtıldı. Buna Xcode derleme önbelleği de denir; girdilerine göre anahtarlanmış derleme yapıtlarını yeniden kullanır ve Tuist'in uzak önbelleği bu yapıtların makineler arasında paylaşılabilir olmasını sağlar.

> [!TIP]
> **Modül önbelleği ile birleştirin**
>
> Xcode önbelleği ve <.localized_link href="/guides/features/cache/module-cache">modül önbelleği</.localized_link> farklı granülerite düzeylerinde çalışır ve birbirini tamamlar. Modül önbelleği, derleme başlamadan önce tüm modülleri önceden oluşturulmuş `.xcframework` dosyalarıyla değiştirirken, Xcode önbelleği derleme sırasında derleme çıktılarını yeniden kullanır.

> [!TIP]
> **Geliştirici makinelerinde temizleme yaparken `CompilationCache.noindex` öğesini koruyun**
>
> Varsayılan olarak, derleme önbellek deposu `DerivedData` içinde bulunur, bu nedenle `DerivedData` silindiğinde derleme ürünleriyle birlikte önbellek de atılır. Bir geliştirici makinesinde yalnızca derleme ürünlerini silmeyi tercih edin: yeniden derleme daha sonra diskteki depodan yeniden oynatılır ve hiçbir şey getirilmez.

## Kurulum {#setup}

Henüz bir Tuist hesabınız ve projeniz yoksa, aşağıdaki komutu çalıştırarak oluşturabilirsiniz:

```bash
tuist init
```

`Tuist.swift` dosyanızda `fullHandle` referansınız olduğunda, projeniz için önbellekleme kurulumunu aşağıdaki komutu çalıştırarak yapabilirsiniz:

```bash
tuist setup cache
```

Bu komut, Swift [derleme sistemi](https://github.com/swiftlang/swift-build)nin derleme yapıtlarını paylaşmak için kullandığı yerel bir önbellek hizmetini başlangıçta çalıştırmak üzere bir [LaunchAgent](https://developer.apple.com/library/archive/documentation/MacOSX/Conceptual/BPSystemStartup/Chapters/CreatingLaunchdJobs.html) oluşturur. İlk olarak geliştirici makinenizde ve her CI işinin kurulumunun bir parçası olarak çalıştırın.

CI üzerinde önbelleği kurmak için <.localized_link href="/guides/server/authentication#continuous-integration">kimlik doğrulaması</.localized_link> yaptığınızdan emin olun.

### Önbellek bileşenlerini güncelleme {#updating-the-cache-components}

Önbellek proxy'si, kurulumu en son çalıştıran Tuist kurulumuna sabitlenmiş bir yol yerine kararlı bir başlatıcı kullanır. Kurulduktan sonra, `tuist setup cache` ve önbellek etkinleştirilmiş `tuist generate`, kullanılabilir bir hedefi daha yeni Tuist sürümlerine ilerletir. Daha eski bir Tuist'e sabitlenmiş projeler bu nedenle paylaşılan proxy'yi düşürmez. Oluşturma yalnızca mevcut bir başlatıcı hedefini günceller: bir hizmet kurmaz, kimlik doğrulaması yapmaz, eklentiyi değiştirmez veya proxy'yi yeniden başlatmaz. Özel eklenti, proxy, soket veya kayıt defteri geçersiz kılmaları otomatik ilerlemeyi atlar.

Çalışan proxy, yeni hedefi yalnızca en az 30 saniye boyunca önbellek isteği olmadan, havada herhangi bir istek veya arka plan işi kalmadığında ve yayın kuyrukları boşaltıldığında benimser. Ardından çıkar ve launchd seçilen CLI'yı başlatarak hizmetin argümanlarını ve kimlik bilgisi ortamını korur. Hedefi gerçekten benimseyen proxy yalnızca disk üzerindeki eklentiyi paketinden atomik olarak yeniler; kurulum, eski proxy hala boşaltılırken daha yeni bir eklenti kurmaz. Kurulu eklenti eksikse, açıkça yapılan boşta kurulum seçilen proxy'yi yenilemeyi yeniden denemek için yeniden başlatır. Kayıt defterine ve kuyruklara sahip hâlâ yalnızca bir proxy vardır. Kullanılamayan bir hedef veya boşaltılmamış yüklemeler, aktif istekleri kesintiye uğratmak yerine geçişi erteler. Kimlik bilgisi yenileme, geçişten önce bile seçilen CLI'yı takip eder, bu nedenle daha eski bir CLI kurulumunu kaldırmak boşaltılmayı bekleyen yüklemeleri mahsur bırakmaz.

Kararlı başlatıcıdan önce oluşturulan mevcut bir kurulum tek bir açık migrasyon gerektirir. Hiçbir derleme çalışmıyorken aşağıdakini çalıştırın:

```bash
tuist setup cache
```

Bu migrasyondan sonra, Tuist'i güncellemek ve olağan `tuist generate` komutunu çalıştırmak proxy'yi ve kurulu eklentiyi ilerletmek için yeterlidir; her CLI sürümü için kurulumu yeniden çalıştırmanız gerekmez. Farklı bir Xcode seçmek için, aynı yolda güncellenen bir Xcode dahil olmak üzere, açık kurulum hâlâ gereklidir. Yapılandırması değiştiğinde kurulum paylaşılan hizmeti değiştirebilir, bu nedenle önce makinedeki tüm derlemelerin bitmesini bekleyin. Proxy, önceki eklenti protokolünü ve mevcut olanı destekler, bu nedenle Xcode'da zaten yüklü uyumlu bir eklenti proxy yükseltmesi sırasında çalışmaya devam eder. En yeni eklentiyi yüklemek için Xcode'u tamamen kapatıp yeniden açın, ancak uyumlu yüklü bir eklenti acil bir yeniden başlatma gerektirmez. Bir sürüm oluşturulan derleme ayarlarını değiştirdiğinde projeleri yeniden oluşturun.

Seçilen Tuist kurulumunu kullanılabilir tutun: başlatıcı bunu başlangıç, yapılandırma ve kimlik bilgisi yenileme için kullanır. Başlatıcı ilerledikten sonra daha eski kurulumlar kaldırılabilir. Seçilen çalıştırılabilir dosya silinmişse veya artık çalıştırılabilir değilse, `tuist setup cache` önbelleği önce kaldırmadan kullanılabilir bir kurulumu, hatta daha eski bir sürümü kullanarak hedefi onarabilir. Kararlı çalıştırılabilir dosya takma adları paket yöneticisi yükseltmeleri boyunca korunur; sembolik bağlantılar yalnızca kurulum kimliği karşılaştırılırken çözülür. Başlangıçta proxy, yerinde güncellemeler veya kasıtlı geri almalar dahil olmak üzere gerçekten başlatılan sürümü kaydeder ve alakasız eski checkout'ların kullanılabilir bir kurulumu değiştirmesini önlemek için kullanılan en yüksek sürümü saklar.

Sürüm numarası olmayan kaynak tabanlı CLİ'ler ve açık `TUIST_CAS_PLUGIN_PATH` veya `TUIST_CAS_PROXY_PATH` kurulumları, otomatik sürüm seçimi yerine açık bir başlatma yapılandırması kullanır. Bu bileşenleri yeniden oluşturduktan sonra kurulumu yeniden çalıştırın. Kurulum, tazeliklerini kontrol eder ve yedeği hazır olduktan sonra yönetilen hedef ilerlemesini devre dışı bırakır.

`tuist teardown cache`, başlatıcı hedefini kaldırmadan önce hizmeti durdurur ve mevcut projeler için kararlı eklentiyi korur. Hizmeti durdurma başarısız olursa, başlatıcısı yeniden başlatma ve başka bir sökme denemesi için kullanılabilir kalır. Başarılı sökmeden sonra oluşturma hizmeti yeniden oluşturamaz.

### Xcode Derleme Ayarlarını Yapılandırma {#configure-xcode-build-settings}

Mevcut bir Xcode projesi için, `tuist setup cache` tarafından yazdırılan derleme ayarlarını projenizin Derleme Ayarlarına veya mevcut bir `.xcconfig` dosyasına kopyalayın. Komut, hesabınız için yapılandırmayı yazdırır; bir yapılandırma dosyası oluşturmaz veya Xcode projenizi düzenlemez. Diğer derleyici seçeneklerinin korunması için `OTHER_SWIFT_FLAGS` genişletilirken `$(inherited)` ifadesini koruyun.

Ayarlar şunları içerir:

```
COMPILATION_CACHE_ENABLE_CACHING = YES
COMPILATION_CACHE_ENABLE_PLUGIN = YES
COMPILATION_CACHE_PLUGIN_PATH = $HOME/.local/state/tuist/libtuist_cas_plugin.dylib
COMPILATION_CACHE_REMOTE_SERVICE_PATH = $HOME/.local/state/tuist/cas-proxy.sock
COMPILATION_CACHE_ENABLE_DETACHED_KEY_QUERIES = YES
COMPILATION_CACHE_ENABLE_DIAGNOSTIC_REMARKS = YES
OTHER_SWIFT_FLAGS = $(inherited) -cas-plugin-option tuist-instance=your-org/your-project
```

`COMPILATION_CACHE_ENABLE_PLUGIN`, `COMPILATION_CACHE_PLUGIN_PATH`, `COMPILATION_CACHE_REMOTE_SERVICE_PATH` ve `COMPILATION_CACHE_ENABLE_DETACHED_KEY_QUERIES` değerlerinin Xcode'un derleme ayarları arayüzünde doğrudan gösterilmediği için **kullanıcı tanımlı derleme ayarları** olarak eklenmesi gerektiğini unutmayın.

> [!NOTE]
> **Eklenti yolu**
>
> `libtuist_cas_plugin.dylib`, Tuist ile birlikte gelen ve `tuist` çalıştırılabilir dosyasının yanında yer alan derleme önbelleği eklentisidir. `tuist setup cache` onu `$HOME/.local/state/tuist/libtuist_cas_plugin.dylib` konumuna kopyalar ve `COMPILATION_CACHE_PLUGIN_PATH` bu kopyayı işaret eder. Yol her makinede aynıdır ve Tuist'i güncellediğinizde değişmez, bu nedenle ayarı projenizle birlikte sürüm kontrolüne ekleyebilirsiniz. Kurulum ve yeni başlatılan proxy, seçilen Tuist paketinden kopyayı yeniler; daha eski bir checkout'tan kurulum çalıştırmak daha yeni bir eklentiyi düşürmez.

> [!NOTE]
> **Her proje için tek bir soket**
>
> `tuist setup cache`, makine başına tek bir önbellek proxy'si yükler, bu nedenle her proje aynı `COMPILATION_CACHE_REMOTE_SERVICE_PATH` değerini kullanır. Projeyi tanımlayan şey `tuist-instance` eklenti seçeneğidir.

> [!IMPORTANT]
> **`COMPILATION_CACHE_REMOTE_SERVICE_PATH`, C ve Objective-C kodlarını paylaşan bileşendir**
>
> Bu ayarı "önbellek hizmetinin bulunduğu yer" olarak okuyup isteğe bağlı olarak değerlendirmek kolaydır. Ancak aynı zamanda C, Objective-C, önceden derlenmiş modüller ve önceden derlenmiş üstbilgilerin paylaşılıp paylaşılmayacağına karar veren anahtardır: Derleme sistemi, yalnızca bir uzak önbellek hizmeti yapılandırıldığında bunlar için önbellekleme yapar. Bu ayarı bırakırsanız Swift derlemeleri yine de paylaşılır, ancak projeyi daha önce derlememiş herhangi bir makinede her C/Objective-C dosyası ve her modül yeniden derlenir.

> [!NOTE]
> **Eşzamanlı önbellek aramaları**
>
> `COMPILATION_CACHE_ENABLE_DETACHED_KEY_QUERIES`, derleme sisteminin her derleme için yaptığı uzak önbellek aramalarını, derlemenin yürütme kanallarında birkaçını birden yapmak yerine, derlemenin geri kalanıyla paralel olarak çalıştırır. Uzak bir önbellekten birçok derlemeyi kaçıran veya geri yükleyen derlemeler daha hızlı tamamlanır.

Aşağıdaki bayrakları ekleyerek `xcodebuild` çalıştırırken bu ayarları da belirtebilirsiniz, örneğin:

```
xcodebuild build -project YourProject.xcodeproj -scheme YourScheme \
    COMPILATION_CACHE_ENABLE_CACHING=YES \
    COMPILATION_CACHE_ENABLE_PLUGIN=YES \
    COMPILATION_CACHE_PLUGIN_PATH=$HOME/.local/state/tuist/libtuist_cas_plugin.dylib \
    COMPILATION_CACHE_REMOTE_SERVICE_PATH=$HOME/.local/state/tuist/cas-proxy.sock \
    COMPILATION_CACHE_ENABLE_DETACHED_KEY_QUERIES=YES \
    COMPILATION_CACHE_ENABLE_DIAGNOSTIC_REMARKS=YES \
    'OTHER_SWIFT_FLAGS=$(inherited) -cas-plugin-option tuist-instance=your-org/your-project'
```

> [!NOTE]
> **Xcode 27 ve sonraki sürümlerde ön ek eşlemesi**
>
> Xcode 27 ve sonraki sürümlerde `tuist setup cache`, ayrıca `SWIFT_ENABLE_PREFIX_MAPPING`, `SWIFT_ENABLE_PROJECT_PREFIX_MAPPING`, `CLANG_ENABLE_PREFIX_MAPPING` ve `CLANG_ENABLE_PROJECT_PREFIX_MAPPING` değerlerini yazdırır. Bunlar, derleme önbelleği anahtarlarını projenin ve `DerivedData` konumundan bağımsız hale getirir. Bunları kullanıcı tanımlı derleme ayarları olarak ekleyin. Etkinleştirmek her önbellek anahtarını değiştirir, bu nedenle sonraki derleme önbelleği tekrar doldurur. `enableCaching` açıkken `tuist generate` bunları sizin için ayarlar.
>
> Derleyici ayrıca eşlenen yolları kod kapsamı verilerine yazar ve Xcode bunları çözümleyemez, bu nedenle bir kapsam raporu ön ek eşlemesiyle derlenen her kaynağı dışarıda bırakır. Yazdırılan ayarlar, `TUIST_PREFIX_MAPPING_FOR_COVERAGE_*` ayarlarıyla birlikte, kod kapsamı toplayan derlemelerde ön ek eşlemesini kapatır. `tuist generate` de aynısını yapar. Bu derlemeler hâlâ derleme önbelleğini kullanır, ancak önbellek anahtarları proje ve `DerivedData` yollarına bağlıdır.
>
> Bu ayarları komut satırında `xcodebuild` öğesine aktardığınızda, yukarıdaki `OTHER_SWIFT_FLAGS` örneğinde olduğu gibi `$(...)` içeren değerleri tek tırnak içine alın. Aksi takdirde kabuk bunları boş dizelere genişletir ve ön ek eşlemesi kapatılır:
>
> ```
> xcodebuild build -project YourProject.xcodeproj -scheme YourScheme \
>     'SWIFT_ENABLE_PREFIX_MAPPING=$(TUIST_PREFIX_MAPPING_FOR_COVERAGE_$(CLANG_COVERAGE_MAPPING))' \
>     SWIFT_ENABLE_PROJECT_PREFIX_MAPPING=YES \
>     'CLANG_ENABLE_PREFIX_MAPPING=$(TUIST_PREFIX_MAPPING_FOR_COVERAGE_$(CLANG_COVERAGE_MAPPING))' \
>     CLANG_ENABLE_PROJECT_PREFIX_MAPPING=YES \
>     TUIST_PREFIX_MAPPING_FOR_COVERAGE_=YES \
>     TUIST_PREFIX_MAPPING_FOR_COVERAGE_NO=YES \
>     TUIST_PREFIX_MAPPING_FOR_COVERAGE_YES=NO
> ```

> [!NOTE]
> **Oluşturulan projeler**
>
> Projeniz Tuist tarafından oluşturuluyorsa ayarları manuel olarak belirlemeniz gerekmez.
>
> Bu durumda, tek yapmanız gereken `Tuist.swift` dosyanıza `enableCaching: true` eklemektir:
> ```swift
> import ProjectDescription
>
> let tuist = Tuist(
>     fullHandle: "your-org/your-project",
>     project: .tuist(
>         generationOptions: .options(
>             enableCaching: true
>         )
>     )
> )
> ```

### Ön ek eşlemeli kapsam {#coverage-with-prefix-mapping}

Varsayılan olarak, oluşturulan projeler Xcode'un kapsam raporlarının ve `xccov` işlevinin çalışmasını sağlamak için kapsam derlemelerinde ön ek eşlemesini devre dışı bırakır. Kapsam derlemelerini checkout'lar arasında paylaşılabilir tutmak için bunu etkinleştirebilirsiniz:

```swift
let tuist = Tuist(
    project: .tuist(
        generationOptions: .options(
            enableCaching: true,
            coverage: .coverage(prefixMapping: true)
        )
    )
)
```

`TUIST_COVERAGE_PREFIX_MAPPING` ortam değişkeni (`1` veya `0`), `prefixMapping` üzerinde önceliklidir. Bu seçenek Xcode 27 ve sonraki sürümlerde geçerlidir ve `enableCaching` gerektirir. Kapsam `tuist test` yüklemeleri bunu destekler: Tuist, eşlenen yollarla kaynakları okuyan ve bunları deposundaki dosyalara bağlayan `llvm-cov` ile çalışmayı ölçer. Xcode'un kendi kapsam raporu ve `xccov` yine de bu kaynakları dışarıda bırakabilir; ayrıca `llvm-cov` dışa aktarımı başarısız olduğu için sonuç paketinin `xccov` raporuna geri dönen bir yükleme de aynı durumu gösterebilir. Eşlenen `#filePath` değerleri, sabitleri kaynak dosyalara göre konumlandıran testleri de etkileyebilir; bunun yerine sabitleri açık çalışma zamanı checkout yolları üzerinden çözümleyin. Kapsamı kendiniz işliyorsanız, her enstrüman edilmiş ikili dosyayı sanal ön ekleri yerel dizinlere eşleyen hedefin `$(TARGET_TEMP_DIR)/compilation-prefix-map.json` değeriyle eşleştirin. Proje başına eşleme etkinleştirildiğinde bir hedefin haritasını her ikili dosya için yeniden kullanmayın.

Kapsam-ön ek ayarları, kapsam yapıtlarına yazılan yolları kontrol ettikleri için ikili önbellek ve seçici test karma değerlerine katılır. Bu seçeneği değiştirmek veya `TUIST_COVERAGE_PREFIX_MAPPING` değerini farklı ayarlamak, olağan derlemeler için bile bu karma değerleri geçersiz kılar. Geliştiriciler ve CI işleri arasında ikili önbellekleri ve seçici test sonuçlarını paylaşmaları gerekiyorsa değeri tutarlı tutun.

### Oluşturulan projelerde hata ayıklama {#debugging-generated-projects}

Geri yüklenen yerel modüller, bağlantılı hata ayıklama bilgilerinin yanı sıra derleme önbelleğine erişim de gerektirir. Tuist, Debug ve Release modüllerini dSYM'ler ve dilim başına kaynak kimliği meta verileriyle ısıtır, ardından bir hedefi değiştirmeden önce meta verileri tüketicinin bildirilen kaynaklarına karşı doğrular. Eksik veya uyumsuz meta veriler, o hedefin kaynaklarını korur. Betikle oluşturulan `.generated(...)` kaynakları, doğrulanabilir içerik sağlama toplamları yerine bildirim parmak izlerine sahiptir, bu nedenle bu hedefler kaynak tabanlı kalır ve yerel modül önbelleğine yayınlanmaz. Gerçek içerik sağlama toplamlarına sahip oluşturulmuş kaynak erişimcileri uygun olmaya devam eder. Desteklenmeyen hata ayıklama bilgileri, ilgili olmayan ürünleri engellemeden etkilenen hedefin yayınlanmasını atlar; kaynak mutasyonu ve iptal etme yine de ısıtma işlemini başarısız kılar. Önbellek formatı değiştiği için daha eski sürümler tarafından ısıtılan yapıtların yeniden ısıtılması gerekir.

Doğrulanmış değiştirmeler için Tuist, tüketiciye ait dSYM UUID plist'lerinde kaynak yeniden konumlandırmaları hazırlar ve statik önbelleğe alınmış kod için hata ayıklamaya özel eşlikçileri bağlar. Önbelleğe alınmış ikili dosyaları yeniden yazmaz veya LLDB'nin kalıcı global kaynak haritasına üretici kaynak yollarını yüklemez. Açık hata ayıklayıcı başlatıcıları ve modül yükleyici ayarları yetkili olmaya devam eder. Hata ayıklama sembolleri ve kaynak yeniden konumlandırma, kaynak bağımlı çalışma zamanı dosya erişimini veya yerel Xcode kapsam raporlarını onarmaz; kapsam varyantı seçimi ve LLVM dışa aktarma ayrı özellikler olarak kalır.

`enableCaching: true` ile Tuist, Run ve Test eylemleri için LLDB kaynak haritalarını yapılandırır. Bir eylem özel bir LLDB başlatıcısına sahip olduğunda, Tuist önce çözümlenmiş kaynak haritasını yazar, ardından haritayı genişletmesi veya üzerine yazması için özel başlatıcıyı kaynaklar. Aksi takdirde, kaynak haritasını değiştirmeden önce dosya varsa `~/.lldbinit-Xcode` yükler, yoksa `~/.lldbinit` kullanır. Yalnızca bir ev dizini dosyası yükleyerek, çift kaynaklama olmadan kullanıcı başına hata ayıklayıcı kurulumunu geri yükler. Değiştirme, önceki çalıştırmalardaki eski eşlemeleri kaldırır ve ev dizini dosyası kaynak haritalarına göre önceliklidir; kalması gereken kaynak haritası girdilerini eylemin özel başlatıcısına ekleyin. Diğer ev dizini ayarları korunur. Tuist'in önbelleğe özel modül arama yolları, yükleyici ayarları ve Clang bayrakları sonrasında uygulanır ve bu ayarlar için kullanıcı değerlerine göre önceliklidir. Ev dizini dosyası hataları, sonraki komutların yüklenmesini engellemeden görünür kalır ve komutlar yankılanmaz. Bu başlatıcı koruma, Tuist modül önbelleğinden geri yüklenen ikili dosyalar için hata ayıklamayı yapılandırdığında da geçerlidir; hatta `enableCaching` olmadan ve daha eski Xcode sürümlerinde bile.

Xcode 27 ve sonraki sürümlerde, oluşturulan projeler bir proje bunları ayarlamadıkça Xcode'un proje başına ön ek eşlemelerini (`SWIFT_ENABLE_PROJECT_PREFIX_MAPPING` ve `CLANG_ENABLE_PROJECT_PREFIX_MAPPING`) kapalı bırakır. `/^src` gibi ön ekleri, her projede farklı bir dizini adlandırır ve LLDB bunları yalnızca hata ayıklanan hedefin projesine göre çözer. Kaynaklar bunun yerine çalışma alanı genelindeki ön ekler altında kaydedilir: Tuist kök dizini için `/^root`, Swift paketi geçici dizini için `/^spm` ve derleme çıktıları için `/^intermediates` ile `/^products`. Her biri her projede aynı dizini adlandırdığından, kesme noktaları çalışma alanındaki herhangi bir projedeki kaynaklarda çözülür.

Tuist kökü dışındaki yollar eşlenmez. Kök dışındaki bir projenin önbellek anahtarları, projenin nereye çekildiğine bağlıdır, bu nedenle diğer çekimler ve makineler onun için önbelleği ıskalar. Anahtarlarının çekim konumundan bağımsız kalmasını sağlamak için, o projenin manifestosunda proje başına eşlemeleri açın:

```swift
let checkoutIndependentSettings = Settings.settings(base: [
    "SWIFT_ENABLE_PROJECT_PREFIX_MAPPING": "YES",
    "CLANG_ENABLE_PROJECT_PREFIX_MAPPING": "YES",
])
```

Bu ayarları ilgili `Project` öğesine iletin. Başka bir projeden bir hedefte hata ayıkladığınızda, LLDB o projenin kaynaklarını bulamaz. Manifesto proje tabanlı ayarları, proje düzeyindeki xcconfig değerlerine göre önceliklidir, bu nedenle bunları manifesto içinde ayarlayın.

Bu ayarları değiştirmek, derleme önbelleği anahtarlarını, ikili önbellek karmalarını ve seçici test karmalarını değiştirir, bu nedenle bu önbelleklerin yeniden ısıtılması gerekir. Seçiminizi ekibiniz genelinde tutarlı tutun.

### Önbellek yükleme politikası {#cache-upload-policy}

Varsayılan olarak, önbellek hizmeti hem uzak önbelleğe yapıtları indirir hem de yükler. Bunu, yapıtların indirildiği ancak asla yüklenmediği salt okunur modu etkinleştirmek için `Tuist.swift` dosyanızdaki `xcodeCache` seçeneğiyle kontrol edebilirsiniz:

```swift
import ProjectDescription

let tuist = Tuist(
    fullHandle: "your-org/your-project",
    xcodeCache: .xcodeCache(
        upload: false
    ),
    project: .tuist(
        generationOptions: .options(
            enableCaching: true
        )
    )
)
```

Yaygın bir model, yerel ortamları salt okunur tutarken, derlemelerin tekrarlanabilir olduğu CI'dan yalnızca yapıtları göndermektir. Bunu, çoğu CI sağlayıcısı tarafından ayarlanan `CI` ortam değişkenini kontrol eden `Environment.isCI` kullanarak başarabilirsiniz:

```swift
import ProjectDescription

let tuist = Tuist(
    fullHandle: "your-org/your-project",
    xcodeCache: .xcodeCache(
        upload: Environment.isCI
    ),
    project: .tuist(
        generationOptions: .options(
            enableCaching: true
        )
    )
)
```

Bu kurulumla, yerel derlemeler yükleme yapmadan önbelleğe alınmış yapıtlardan yararlanır, CI derlemeleri ise ekibin geri kalanı için önbelleği doldurur.

Yükleme politikası, `tuist setup cache` çalıştıran makinede proje başına kaydedilir. Değiştirmek için `upload` güncelleyin ve `tuist setup cache` komutunu tekrar çalıştırın; Tuist projenizi oluşturuyorsa `tuist generate` komutunu da çalıştırın. Bundan sonraki yüklemeler, o makinedeki önbelleği yeniden başlatmadan yeni politikayı izler. Aynı makinede aynı anda çalışan aynı proje için işler politikasını paylaşır, bu nedenle en son `tuist setup cache` hepsi için bunu belirler.

### Depolama boyutu sınırı {#store-size-limit}

Derleme önbelleği deposu her derleme ile büyür. Projenin depolarını sınırlamak için `Tuist.swift` dosyanızda `storeSizeLimit` ayarlayın:

```swift
import ProjectDescription

let tuist = Tuist(
    fullHandle: "your-org/your-project",
    xcodeCache: .xcodeCache(
        storeSizeLimit: .gigabytes(20)
    ),
    project: .tuist(
        generationOptions: .options(
            enableCaching: true
        )
    )
)
```

Hiçbir derleme çalışmıyorken, Tuist projenin her deposunu 10 dakikada bir kontrol eder. Daha yeni derlemeler sınırın yaklaşık yarısını yazdığında, deponun en eski önbelleğe alınmış çıktılarını siler, böylece depo yaklaşık sınıra yerleşir. Derlemeler çalışırken bir depo sınırdan büyük olabilir ve sınırı ayarladığınızda zaten daha büyük olan bir depo, yeni derlemeler bu kadar yazdıktan sonra küçülür. Varsayılan konumunda olduğu gibi birkaç proje aynı depoyu kullandığında, en küçük limit uygulanır. Sınır, `tuist setup cache` çalıştırdığınız her makinede geçerlidir, bu nedenle sınırı değiştirdikten sonra tekrar çalıştırın.

### Modül önbelleği karmaları {#module-cache-hashes}

Derleme önbelleği ayarları <.localized_link href="/guides/features/projects/hashing">modül önbelleği karmalarının</.localized_link> parçası değildir. Tuist, her `COMPILATION_CACHE_*` derleme ayarını ve değeriyle birlikte her `-cas-plugin-option` bayrağını karma dışında bırakır. `enableCaching` özelliğini açıp kapatmak veya yükleme politikasını değiştirmek, hedeflerinizin karmalarını korur, bu nedenle zaten ısıttığınız <.localized_link href="/guides/features/cache/module-cache">modül önbelleği</.localized_link> ikili dosyaları geçerli kalır. Xcode önbelleği olan ve olmayan derlemeleri aynı modül önbelleğine karşı karşılaştırabilirsiniz.

> [!NOTE]
> **Ön ek eşleme ayarları karmalanır**
>
> Xcode 27 ve sonraki sürümlerde, `enableCaching: true` ayrıca `SWIFT_ENABLE_PREFIX_MAPPING`, `SWIFT_ENABLE_PROJECT_PREFIX_MAPPING`, `CLANG_ENABLE_PREFIX_MAPPING`, `CLANG_ENABLE_PROJECT_PREFIX_MAPPING` ve `TUIST_PREFIX_MAPPING_FOR_COVERAGE_*` ayarlarını da ayarlar. Bu ayarlar modül önbelleği karmalarının parçasıdır, bu nedenle Xcode 27 ve sonraki sürümlerde `enableCaching` özelliğini açıp kapatmak hedeflerinizin karmalarını değiştirir.

### Büyük çıktıların parçalarının yeniden kullanılması {#reusing-parts-of-large-outputs}

Sunucu desteklediğinde, Xcode önbelleği büyük çıktıları parçalar halinde aktarır ve yalnızca önceki bir sürümden bu yana değişen parçaları gönderir veya getirir. Parçalar, `DerivedData` öğesinden ayrı küçük bir yerel önbellekte tutulur, böylece derleme önbelleğini temizlerken korunurlar. Küçük çıktılar, daha eski sunucular ve daha eski istemciler normal tüm çıktı aktarımlarını kullanır.

Bu, ne kadar yeniden derlendiğini değil, ne kadar indirilip yüklendiğini azaltır. Eşleşen parçaları olmayan soğuk bir makine yine de tüm çıktıyı indirir.

### Sürekli entegrasyon {#continuous-integration}

CI ortamınızda önbelleğe almayı etkinleştirmek için, yerel ortamlardakiyle aynı komutu çalıştırmanız gerekir: `tuist setup cache`.

Kimlik doğrulama için, desteklenen CI sağlayıcıları için önerilen <.localized_link href="/guides/server/authentication#oidc-tokens">OIDC kimlik doğrulamasını</.localized_link> veya `TUIST_TOKEN` ortam değişkeni aracılığıyla bir <.localized_link href="/guides/server/authentication#account-tokens">hesap jetonunu</.localized_link> kullanabilirsiniz.

OIDC kimlik doğrulaması kullanan GitHub Actions için örnek bir iş akışı:
```yaml
name: Build

permissions:
  id-token: write
  contents: read

jobs:
  build:
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v4
      - uses: jdx/mise-action@v2
      - run: tuist auth login
      - run: tuist setup cache
      - # Your build steps
```

Jeton tabanlı kimlik doğrulama ve Xcode Cloud, CircleCI, Bitrise ve Codemagic gibi diğer CI platformları dahil olmak üzere daha fazla örnek için <.localized_link href="/guides/integrations/continuous-integration">Sürekli Entegrasyon kılavuzuna</.localized_link> bakın.

### CI'da derleme önbelleği deposu {#compilation-cache-store-on-ci}

Derleme önbelleği deposu, Xcode'un derleme çıktılarını sakladığı yerel dizindir. Konumunu `COMPILATION_CACHE_CAS_PATH` derleme ayarı belirler; varsayılan olarak `DerivedData` içindeki `CompilationCache.noindex` konumundadır.

#### Durumlu depo {#stateful-store}

Depoları derlemeler arasında korumak için `COMPILATION_CACHE_CAS_PATH` (ve `tuist cache` için `TUIST_COMPILATION_CACHE_CAS_PATH`) ayarını kalıcı bir yola yönlendirin ve boyutunu bir [depo boyutu sınırı](#store-size-limit) ile sınırlayın.

## Sorun giderme {#troubleshooting}

### Derlemeler, Xcode önbellek proxy'sinin başarısız olduğunu bildirir {#cas-proxy-failed}

Bir derleme aşağıdaki gibi bir uyarı gösteriyorsa, Xcode bu uyarının başına hangi derlemenin ilk hatayla karşılaştığına bağlı olarak `CAS error:` veya `CAS operation failed:` ekler:

```
warning: CAS error: The Tuist Xcode cache proxy at /Users/you/.local/state/tuist/cas-proxy.sock failed (proxy connect: No such file or directory (os error 2)). Compilations that needed it used the local cache only, without remote cache hits. Their uploads are kept on disk and sent once the proxy is reachable again. Run `tuist setup cache` if the proxy is not running.
```

bu durumda derleme önbelleği, `tuist setup cache` tarafından kurulan yerel önbellek proxy'sine ulaşamamış demektir. Derleme yine de başarılı olur, ancak etkilenen derlemeler uzak önbellek isabeti alamaz, bu nedenle boş bir önbellekle çalışan bir derleme gibi çalışır. Yüklemeleri diskte tutulur ve proxy tekrar istekleri işlemeye başladığında gönderilir: aynı derleme içinde zamanında geri gelirse daha sonra, aksi takdirde aynı makinedeki sonraki derleme sırasında. İşten sonra atılan bir CI makinesi bunları kaybeder. Uyarı, her derlemede bir kez, Xcode'un Sorun gezgininde ve `xcodebuild` çıktısında görünür.

Proxy'nin çalışıp çalışmadığını kontrol etmek için, uyarıda adı geçen sokette dinleyen bir süreç olup olmadığına bakın:

```bash
lsof ~/.local/state/tuist/cas-proxy.sock
```

Komut hiçbir şey yazdırmazsa, proxy'yi yeniden başlatmak için `tuist setup cache` komutunu çalıştırın. CI'da, her işteki herhangi bir `xcodebuild` çağrısından önce `tuist setup cache` komutunu çalıştırın.

### Derlemeler son derece yavaş çalışır ve `CAS error: deadlineExceeded` uyarıları verir {#cas-deadline-exceeded}

Derlemeleriniz beklenenden çok daha uzun sürüyorsa ve Xcode derleme günlüğü şu şekilde uyarılarla doluyorsa:

```
Warning: CAS error: deadlineExceeded(connectionError: Optional(connect(descriptor:addr:size:): No such file or directory (errno: 2)))
note: cache key query failed
```

veya:

```
Warning: CAS error: deadlineExceeded(connectionError: Optional(connect(descriptor:addr:size:): Connection refused (errno: 61)))
```

bu durumda `COMPILATION_CACHE_REMOTE_SERVICE_PATH`, genellikle Tuist'in önceki sürümlerinin yapılandırdığı proje başına soket (`~/.local/state/tuist/<org>_<project>.sock`) olan, hiçbir şeyin dinlemediği bir soketi işaret eder. Tuist artık bu sokete hizmet vermez. Xcode, hızlı hata vermek yerine her derleme önbelleği isteğinde bağlantıyı yeniden dener; bu durum bir derlemenin bir saat veya daha fazla sürmesine neden olabilir ve Tuist bu davranışı değiştiremez.

Düzeltmek için:

- **Oluşturulan projeler**: `tuist generate` komutunu tekrar çalıştırın.
- **Diğer projeler**: `COMPILATION_CACHE_*` derleme ayarlarını, [Xcode Derleme Ayarlarını Yapılandırma](#configure-xcode-build-settings) bölümünde açıklandığı gibi `tuist setup cache` tarafından yazdırılanlarla değiştirin.

Xcode önbelleğini kullanmıyorsanız, bunun yerine `COMPILATION_CACHE_*` derleme ayarlarını kaldırın ve `tuist teardown cache` komutunu çalıştırın.

### Yüklemeler devre dışı olsa bile `uploaded CAS output` yerel olarak görünür {#uploaded-cas-output-with-upload-disabled}

`xcodeCache: .xcodeCache(upload: false)` (veya CI olmayan bir makinede `upload: Environment.isCI`) ayarlandığında, derleme günlüğünde yine de `note: uploaded CAS output ...` görebilirsiniz. `xcodebuild` bu çağrıları atlamanın bir yoluna sahip değildir, bu nedenle Tuist bunları alır ancak Tuist sunucusuna hiçbir şey yayınlamaz. Gösterge paneli metrikleri bunu hesaba katar, bu nedenle sahte yükleme trafiği raporlanmaz.
