---
{
  "title": "Xcode önbelleği",
  "titleTemplate": ":title · Önbellek · Özellikler · Kılavuzlar · Tuist",
  "description": "Tuist'in Xcode önbelleği entegrasyonu ile yerel ve CI ortamındaki Xcode derlemelerini hızlandırın."
}
---
# Xcode önbelleği {#xcode-cache}

Tuist, Xcode derleme önbelleği için destek sağlar; bu sayede ekipler, derleme sisteminin önbellekleme yeteneklerinden yararlanarak derleme yapıtlarını paylaşabilir.

Xcode önbelleği Xcode 26 ile tanıtıldı. Buna Xcode derleme önbelleği de denebilir; girdilerine göre anahtarlanan derleme yapıtlarını yeniden kullanır ve Tuist’in uzak önbelleği bu yapıtların makineler arasında paylaşılmasını mümkün kılar.

> [!TIP]
> **Modül önbelleği ile birleştirin**
>
> Xcode önbelleği ve <.localized_link href="/guides/features/cache/module-cache">modül önbelleği</.localized_link> farklı granülerite düzeylerinde çalışır ve birbirini tamamlar. Modül önbelleği, derleme başlamadan önce tüm modülleri önceden oluşturulmuş `.xcframework` dosyalarıyla değiştirirken, Xcode önbelleği derleme sırasında derleme çıktılarını yeniden kullanır.

> [!TIP]
> **Geliştirici makinelerinde temizleme yaparken `CompilationCache.noindex` öğesini koruyun**
>
> Varsayılan olarak derleme önbellek deposu `DerivedData` içinde bulunur, bu nedenle `DerivedData` silindiğinde derleme ürünleriyle birlikte önbellek de atılır. Geliştirici makinesinde yalnızca derleme ürünlerini silmeyi tercih edin: yeniden derleme ardından diskteki depodan oynatma yapar ve hiçbir şeyi çekmez.

## Kurulum {#setup}

Henüz bir Tuist hesabınız ve projeniz yoksa, aşağıdaki komutu çalıştırarak oluşturabilirsiniz:

```bash
tuist init
```

`Tuist.swift` dosyanızda `fullHandle` referansınız olduğunda, projeniz için önbellekleme kurulumunu aşağıdaki komutu çalıştırarak yapabilirsiniz:

```bash
tuist setup cache
```

Bu komut, Swift [derleme sisteminin](https://github.com/swiftlang/swift-build) derleme yapıtlarını paylaşmak için kullandığı yerel bir önbellek hizmetini başlangıçta çalıştırmak üzere bir [LaunchAgent](https://developer.apple.com/library/archive/documentation/MacOSX/Conceptual/BPSystemStartup/Chapters/CreatingLaunchdJobs.html) oluşturur. İlk olarak geliştirici makinenizde ve her CI işinin kurulumunun bir parçası olarak çalıştırın.

CI üzerinde önbelleği kurmak için <.localized_link href="/guides/server/authentication#continuous-integration">kimlik doğrulaması yaptığınızdan</.localized_link> emin olun.

### Önbellek bileşenlerini güncelleme {#updating-the-cache-components}

Önbellek vekil sunucusu, en son kurulumu çalıştıran Tuist kurulumuna sabitlenmiş bir yol yerine kararlı bir başlatıcı kullanır. Kurulduktan sonra, `tuist setup cache` ve önbellek etkinleştirilmiş `tuist generate` kullanılabilir bir hedefi daha yeni Tuist sürümlerine ilerletir. Daha eski bir Tuist’e sabitlenmiş projeler bu nedenle paylaşılan vekil sunucuyu düşürmez. Oluşturma yalnızca mevcut bir başlatıcı hedefini günceller: bir hizmet kurmaz, kimlik doğrulaması yapmaz, eklentiyi değiştirmez veya vekil sunucuyu yeniden başlatmaz. Özel eklenti, vekil sunucu, soket veya kayıt defteri geçersiz kılmaları otomatik ilerlemeyi atlar.

Çalışan vekil sunucu, en az 30 saniye boyunca önbellek isteği olmadığında, havada kalan istek veya arka plan işi olmadan ve yayın kuyrukları boşaltıldığında yeni hedefi benimser. Ardından çıkar ve launchd seçilen CLI’yi başlatarak hizmetin bağımsız değişkenlerini ve kimlik bilgisi ortamını korur. Hedefi gerçekten benimseyen vekil sunucu yalnızca disk üzerindeki eklentiyi paketinden atomik olarak yeniler; kurulum, eski vekil sunucu hala boşaltma yaparken daha yeni bir eklenti kurmaz. Kurulu eklenti eksikse, açıkça yapılan boşta kurulum seçilen vekil sunucuyu yenilemeyi tekrar denemek için yeniden başlatır. Kayıt defterine ve kuyruklara sahip hâlâ yalnızca bir vekil sunucu vardır. Kullanılamayan bir hedef veya boşaltılmamış yüklemeler, aktif istekleri kesintiye uğratmak yerine geçişi erteler. Kimlik bilgisi yenileme, geçişten önce bile seçilen CLI’yi takip eder, bu nedenle daha eski bir CLI kurulumunu kaldırmak boşaltmayı bekleyen yüklemeleri askıda bırakmaz.

Kararlı başlatıcıdan önce oluşturulmuş mevcut bir kurulum tek bir açık migrasyon gerektirir. Hiçbir derleme çalışmıyorken aşağıdakini çalıştırın:

```bash
tuist setup cache
```

Bu migrasyondan sonra, Tuist’i güncellemek ve alıştığınız `tuist generate` komutunu çalıştırmak vekil sunucuyu ve kurulu eklentiyi ilerletmek için yeterlidir; her CLI sürümü için kurulumu yeniden çalıştırmanız gerekmez. Farklı bir Xcode seçmek için, aynı yolda güncellenen bir Xcode da dahil olmak üzere, açık kurulum hâlâ gereklidir. Yapılandırması değiştiğinde kurulum paylaşılan hizmeti değiştirebilir, bu nedenle önce makinedeki tüm derlemelerin bitmesini bekleyin. Vekil sunucu önceki eklenti protokolünü ve mevcut olanı destekler, bu nedenle Xcode’da zaten yüklü uyumlu bir eklenti vekil sunucu yükseltmesi sırasında çalışmaya devam eder. En yeni eklentiyi yüklemek için Xcode’u tamamen kapatıp yeniden açın, ancak uyumlu yüklü bir eklenti acil yeniden başlatma gerektirmez. Bir sürüm oluşturulan derleme ayarlarını değiştirdiğinde projeleri yeniden oluşturun.

Seçilen Tuist kurulumunu kullanılabilir tutun: başlatıcı bunu başlangıç, yapılandırma ve kimlik bilgisi yenileme için kullanır. Başlatıcı ilerledikten sonra daha eski kurulumlar kaldırılabilir. Seçilen çalıştırılabilir dosya silindiyse veya artık çalıştırılabilir değilse, `tuist setup cache` hedefi mevcut bir kurulumu, hatta daha eski bir sürümü kullanarak önbelleği önce sökmeden onarabilir. Kararlı çalıştırılabilir dosya takma adları paket yöneticisi yükseltmeleri boyunca korunur; sembolik bağlantılar yalnızca kurulum kimliği karşılaştırılırken çözülür. Başlangıçta vekil sunucu, aslında başlatılan sürümü, yerinde güncellemeler veya kasıtlı geri almalar dahil olmak üzere kaydeder ve ilgili olmayan eski checkout’ların kullanılabilir bir kurulumu değiştirmesini önlemek için kullanılan en yüksek sürümü saklar.

Sürüm numarası olmayan kaynak tabanlı CLI’lar ve açık `TUIST_CAS_PLUGIN_PATH` veya `TUIST_CAS_PROXY_PATH` kurulumları, otomatik sürüm seçimi yerine açık bir başlatma yapılandırması kullanır. Bu bileşenleri yeniden oluşturduktan sonra kurulumu yeniden çalıştırın. Kurulum tazeliklerini kontrol eder ve yönetilen hedef ilerlemesini yalnızca yedek hazır olduktan sonra devre dışı bırakır.

`tuist teardown cache` hizmetini durdurur ve ardından başlatıcı hedefini kaldırırken mevcut projeler için kararlı eklentiyi korur. Hizmeti durdurma başarısız olursa, başlatıcısı yeniden başlatma ve başka bir sökme denemesi için kullanılabilir kalır. Başarılı sökmeden sonra oluşturma hizmeti yeniden oluşturamaz.

### Xcode Derleme Ayarlarını Yapılandırma {#configure-xcode-build-settings}

Mevcut bir Xcode projesi için, `tuist setup cache` tarafından yazdırılan derleme ayarlarını projenizin Derleme Ayarlarına veya mevcut bir `.xcconfig` dosyasına kopyalayın. Komut hesabınız için yapılandırmayı yazdırır; bir yapılandırma dosyası oluşturmaz veya Xcode projenizi düzenlemez. Diğer derleyici seçeneklerinin korunması için `OTHER_SWIFT_FLAGS` genişletilirken `$(inherited)` ifadesini koruyun.

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

`COMPILATION_CACHE_ENABLE_PLUGIN`, `COMPILATION_CACHE_PLUGIN_PATH`, `COMPILATION_CACHE_REMOTE_SERVICE_PATH` ve `COMPILATION_CACHE_ENABLE_DETACHED_KEY_QUERIES` değerlerinin Xcode’un derleme ayarları arayüzünde doğrudan gösterilmediği için **kullanıcı tanımlı derleme ayarları** olarak eklenmesi gerektiğini unutmayın.

> [!NOTE]
> **Eklenti yolu**
>
> `libtuist_cas_plugin.dylib`, Tuist ile birlikte gelen ve `tuist` çalıştırılabilir dosyasının yanında yer alan derleme önbelleği eklentisidir. `tuist setup cache` onu `$HOME/.local/state/tuist/libtuist_cas_plugin.dylib` konumuna kopyalar ve `COMPILATION_CACHE_PLUGIN_PATH` bu kopyayı işaret eder. Yol her makinede aynıdır ve Tuist'i güncellediğinizde değişmez, bu nedenle ayarı projenizle birlikte commit edebilirsiniz. Kurulum ve yeni başlatılan proxy, seçilen Tuist paketinden kopyayı yeniler; daha eski bir checkout'tan kurulum çalıştırmak daha yeni bir eklentiyi düşürmez.

> [!NOTE]
> **Her proje için tek bir soket**
>
> `tuist setup cache` makine başına tek bir önbellek proxy’si kurar, bu nedenle her proje aynı `COMPILATION_CACHE_REMOTE_SERVICE_PATH` değerini kullanır. Projeyi tanımlayan şey `tuist-instance` eklenti seçeneğidir.

> [!IMPORTANT]
> **`COMPILATION_CACHE_REMOTE_SERVICE_PATH`, C ve Objective-C’yi paylaşan ayardır**
>
> Bu ayarı “önbellek hizmetinin bulunduğu yer” olarak okumak ve isteğe bağlı kabul etmek kolaydır. Aynı zamanda C, Objective-C, önceden derlenmiş modüller ve önceden derlenmiş üstbilgilerin paylaştırılıp paylaştırılmayacağını belirleyen anahtardır: Derleme sistemi, yalnızca uzak bir önbellek hizmeti yapılandırıldığında bunlar için önbellekleme çalıştırır. Bunu dışarıda bırakırsanız Swift derlemeleri yine de paylaşılır, ancak projeyi daha önce derlememiş olan herhangi bir makinede her C/Objective-C dosyası ve her modül yeniden derlenir.

> [!NOTE]
> **Eşzamanlı önbellek aramaları**
>
> `COMPILATION_CACHE_ENABLE_DETACHED_KEY_QUERIES`, derleme sisteminin her derleme için yaptığı uzak önbellek aramalarını, derlemenin yürütme kanallarında birkaç tanesini sırayla yapmak yerine, derlemenin geri kalanıyla eşzamanlı olarak çalıştırır. Uzak bir önbellekten birçok derlemeyi kaçıran veya geri yükleyen derlemeler daha hızlı tamamlanır.

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
> **Xcode 27 ve sonraki sürümlerde ön ek eşleme**
>
> Xcode 27 ve sonraki sürümlerde `tuist setup cache`, ayrıca `SWIFT_ENABLE_PREFIX_MAPPING`, `SWIFT_ENABLE_PROJECT_PREFIX_MAPPING`, `CLANG_ENABLE_PREFIX_MAPPING` ve `CLANG_ENABLE_PROJECT_PREFIX_MAPPING` değerlerini yazdırır. Bunlar, derleme önbelleği anahtarlarını projenin ve `DerivedData` konumundan bağımsız hale getirir. Bunları kullanıcı tanımlı derleme ayarları olarak ekleyin. Etkinleştirmek her önbellek anahtarını değiştirir, bu nedenle sonraki derleme önbelleği yeniden doldurur. `enableCaching` açıkken `tuist generate` bunları sizin için ayarlar.
>
> Derleyici ayrıca eşlenen yolları kod kapsamı verilerine yazar ve Xcode bunları çözümleyemez; bu nedenle bir kapsam raporu, ön ek eşleme ile derlenen tüm kaynakları dışarıda bırakır. Yazdırılan ayarlar, `TUIST_PREFIX_MAPPING_FOR_COVERAGE_*` ayarlarıyla birlikte, kod kapsamı toplayan derlemelerde ön ek eşlemeyi kapatır. `tuist generate` de aynısını yapar. Bu derlemeler hâlâ derleme önbelleğini kullanır, ancak önbellek anahtarları proje ve `DerivedData` yollarına bağlıdır.
>
> Bu ayarları komut satırında `xcodebuild` öğesine aktarırken, yukarıdaki `OTHER_SWIFT_FLAGS` örneğinde olduğu gibi `$(...)` içeren değerleri tek tırnak içine alın. Aksi takdirde kabuk bunları boş dizelere genişletir ve ön ek eşleme kapatılır:
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
> Projeniz Tuist tarafından oluşturuluyorsa ayarları manuel olarak belirlemenize gerek yoktur.
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

### Ön ek eşleme ile kapsam {#coverage-with-prefix-mapping}

Varsayılan olarak, oluşturulan projeler Xcode’un kapsam raporlarının ve `xccov` çalışmasını sağlamak için kapsam derlemelerinde ön ek eşlemeyi devre dışı bırakır. Kapsam derlemelerini farklı kopyalar arasında paylaşılabilir tutmak için bunu etkinleştirebilirsiniz:

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

`TUIST_COVERAGE_PREFIX_MAPPING` ortam değişkeni (`1` veya `0`), `prefixMapping` üzerinde önceliklidir. Bu seçenek Xcode 27 ve sonraki sürümlerde geçerlidir ve `enableCaching` gerektirir. Kapsam `tuist test` yüklemeleri bunu destekler: Tuist, çalışmayı eşlenen yollara sahip kaynakları okuyan `llvm-cov` ile ölçer ve bunları deposundaki dosyalara bağlar. Xcode’un kendi kapsam raporu ve `xccov` hâlâ bu kaynakları dışarıda bırakabilir; ayrıca `llvm-cov` dışa aktarma başarısız olduğunda sonuç paketinin `xccov` raporuna geri dönen bir yükleme de aynı şekilde davranabilir. Eşlenen `#filePath` değerleri, sabitleri kaynak dosyalara göre konumlandıran testleri de etkileyebilir; bunun yerine sabitleri açık çalışma zamanı kopyalama yolları üzerinden çözümleyin. Kapsamı kendiniz işliyorsanız, her enstrümante edilmiş ikiliyi sanal ön ekleri yerel dizinlere eşleyen hedefinin `$(TARGET_TEMP_DIR)/compilation-prefix-map.json` değeriyle eşleştirin. Proje başına eşleme etkinleştirildiğinde bir hedefin haritasını her ikili için yeniden kullanmayın.

Kapsam-ön ek ayarları, kapsam yapıtlarına yazılan yolları kontrol ettikleri için ikili önbellek ve seçici test karma değerlerine katılır. Bu seçeneği değiştirmek veya `TUIST_COVERAGE_PREFIX_MAPPING` değerini farklı ayarlamak, normal derlemeler için bile bu karmaları geçersiz kılar. Geliştiriciler ve CI işleri arasında ikili önbellekleri ve seçici test sonuçlarını paylaşmaları gerekiyorsa değeri tutarlı tutun.

### Oluşturulan projelerde hata ayıklama {#debugging-generated-projects}

Geri yüklenen yerel modüller, bağlantılı hata ayıklama bilgilerinin yanı sıra derleme önbelleğine erişim de gerektirir. Tuist, Debug ve Release modüllerini dSYM’ler ve dilim başına kaynak kimliği meta verileriyle ısıtır, ardından bir hedefi değiştirmeden önce meta verileri tüketicinin bildirilen kaynaklarına karşı doğrular. Eksik veya uyumsuz meta veriler, o hedefin kaynaklarını korur. Betikle oluşturulan `.generated(...)` kaynakları, doğrulanabilir içerik sağlama toplamları yerine bildirim parmak izlerine sahiptir; bu nedenle bu hedefler kaynak tabanlı kalır ve yerel modül önbelleğine yayımlanmaz. Gerçek içerik sağlama toplamlarına sahip oluşturulmuş kaynak erişimcileri uygun olmaya devam eder. Desteklenmeyen hata ayıklama bilgileri, etkilenen hedefin yayımlanmasını atlar ancak ilgisiz ürünleri engellemez; kaynak mutasyonu ve iptal yine de ısıtma işlemini başarısız kılar. Önbellek biçimi değiştiğinden, eski sürümler tarafından ısıtılan yapıtların yeniden ısıtılması gerekir.

Doğrulanmış değişiklikler için Tuist, tüketiciye ait dSYM UUID plistlerinde kaynak yeniden konumlandırmaları hazırlar ve statik önbelleğe alınmış kod için yalnızca hata ayıklamaya yönelik eşlikçileri bağlar. Önbelleğe alınmış ikilileri yeniden yazmaz veya LLDB’nin kalıcı genel kaynak haritasına üretici kaynak yollarını yüklemez. Açık hata ayıklayıcı başlatıcıları ve modül yükleyici ayarları yetkili olmaya devam eder. Hata ayıklama sembolleri ve kaynak yeniden konumlandırma, kaynağa göreli çalışma zamanı dosya erişimini veya yerel Xcode kapsam raporlarını onarmaz; kapsam varyantı seçimi ve LLVM dışa aktarma ayrı özellikler olarak kalır.

`enableCaching: true` ile Tuist, Çalıştır ve Test eylemleri için LLDB kaynak haritalarını yapılandırır. Bir eylem özel bir LLDB başlatıcısına sahipse, Tuist önce çözümlenmiş kaynak haritasını yazar, ardından haritayı genişletebilmesi veya geçersiz kılabilmesi için özel başlatıcıyı yükler. Aksi takdirde, kaynak haritasını değiştirmeden önce dosya varsa `~/.lldbinit-Xcode` dosyasını yükler, yoksa `~/.lldbinit` dosyasına geri döner. Yalnızca bir ana dizin dosyası yükleyerek, çift yükleme yapmadan kullanıcı başına hata ayıklayıcı kurulumunu geri yükler. Değişim, önceki çalıştırmalardan kalan eski eşlemeleri kaldırır ve ana dizin dosyası kaynak haritalarına göre önceliklidir; kalması gereken kaynak haritası girdilerini eylemin özel başlatıcısına yerleştirin. Diğer ana dizin ayarları korunur. Tuist’in önbelleğe özgü modül arama yolları, yükleyici ayarları ve Clang bayrakları daha sonra uygulanır ve bu ayarlar için kullanıcı değerlerine göre önceliklidir. Ana dizin dosyası hataları, sonraki komutların yüklenmesini engellemeden görünür kalır ve komutlar yansıtılmaz. Bu başlatıcı koruma, Tuist modül önbelleğinden geri yüklenen ikililer için hata ayıklamayı yapılandırdığında da geçerlidir; hatta `enableCaching` olmadan ve daha eski Xcode sürümlerinde bile.

Xcode 27 ve sonrasında, oluşturulan projeler bir proje bunları ayarlamadığı sürece Xcode’un proje başına ön ek eşlemelerini (`SWIFT_ENABLE_PROJECT_PREFIX_MAPPING` ve `CLANG_ENABLE_PROJECT_PREFIX_MAPPING`) kapalı bırakır. `/^src` gibi ön ekleri, her projede farklı bir dizini adlandırır ve LLDB bunları yalnızca hata ayıklanan hedefin projesine göre çözümler. Kaynaklar bunun yerine çalışma alanı genelindeki ön ekler altında kaydedilir: Tuist kök dizini için `/^root`, Swift paketi geçici dizini için `/^spm` ve derleme çıktıları için `/^intermediates` ile `/^products`. Her biri her projede aynı dizini adlandırdığından, kesme noktaları çalışma alanındaki herhangi bir projedeki kaynaklarda çözümlenir.

Tuist kökü dışındaki yollar eşlenmez. Kök dışındaki bir projenin önbellek anahtarları, projenin nereye çekildiğine bağlıdır; bu nedenle diğer çekimler ve makineler onun için önbelleği ıskalar. Anahtarlarının çekim konumundan bağımsız kalmasını sağlamak için, o projenin manifestosunda proje başına eşlemeleri açın:

```swift
let checkoutIndependentSettings = Settings.settings(base: [
    "SWIFT_ENABLE_PROJECT_PREFIX_MAPPING": "YES",
    "CLANG_ENABLE_PROJECT_PREFIX_MAPPING": "YES",
])
```

Bu ayarları ilgili `Project` öğesine iletin. Başka bir projeden bir hedefte hata ayıkladığınızda, LLDB o projenin kaynaklarını bulamaz. Manifesto proje tabanlı ayarları, proje düzeyindeki xcconfig değerlerine göre önceliklidir; bu nedenle bunları manifesto içinde ayarlayın.

Bu ayarları değiştirmek derleme önbelleği anahtarlarını, ikili önbellek karma değerlerini ve seçici test karma değerlerini değiştirir; bu nedenle bu önbelleklerin yeniden ısıtılması gerekir. Seçiminizi ekibiniz genelinde tutarlı tutun.

### Önbellek yükleme politikası {#cache-upload-policy}

Varsayılan olarak, önbellek hizmeti hem uzak önbelleğe yapıtları indirir hem de yükler. Bunu, `Tuist.swift` dosyanızdaki `xcodeCache` seçeneği ile kontrol ederek yalnızca okuma modunu etkinleştirebilirsiniz; bu modda yapıtlar indirilir ancak asla yüklenmez:

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

Yaygın bir model, yerel ortamları yalnızca okuma modunda tutarken, yapıtları yalnızca derlemelerin tekrarlanabilir olduğu CI ortamından itmektir. Bunu, çoğu CI sağlayıcısı tarafından ayarlanan `CI` ortam değişkenini kontrol eden `Environment.isCI` kullanarak gerçekleştirebilirsiniz:

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

Yükleme politikası, `tuist setup cache` komutunu çalıştıran makinede proje başına kaydedilir. Değiştirmek için `upload` değerini güncelleyin ve `tuist setup cache` komutunu tekrar çalıştırın; Tuist projenizi oluşturuyorsa `tuist generate` komutunu da çalıştırın. Bundan sonraki yüklemeler, o makinedeki önbelleği yeniden başlatmadan yeni politikayı izler. Aynı makinede aynı anda çalışan aynı proje için işler politikayı paylaşır; bu nedenle en son `tuist setup cache` tümü için kararı verir.

### Depolama boyutu sınırı {#store-size-limit}

Bir derleme önbelleği deposu her derleme ile büyür. Projenin depolarını sınırlamak için `Tuist.swift` dosyanızda `storeSizeLimit` değerini ayarlayın:

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

Tuist, önbellek vekil sunucusu başladığında, herhangi bir derleme onları kullanmadan önce ve derleme çalışmadığı sürece her 10 dakikada bir projenin her deposunu kontrol eder. `tuist setup cache`, vekil sunucu çalışmıyorsa onu başlatır; bu nedenle derlemelerinden önce `tuist setup cache` ve sonrasında `tuist teardown cache` çalıştıran bir CI işi, uzun ömürlü bir çalıştırıcının depolarını her işin başında sınırlar. Daha yeni derlemeler sınırın yaklaşık yarısını yazdığında, deponun en eski önbelleğe alınmış çıktılarını siler; böylece depo yaklaşık sınıra yerleşir. Derlemeler çalışırken bir depolama sınırı aşılabilir ve limiti ayarladığınızda zaten daha büyük olan bir depo, yeni derlemeler bu kadar veri yazdığında küçülür. Varsayılan konumunda olduğu gibi birkaç proje aynı depoyu kullandığında, en küçük limit uygulanır. Limit, `tuist setup cache` komutunu çalıştırdığınız her makinede geçerlidir; bu nedenle limiti değiştirdikten sonra komutu tekrar çalıştırın. Zaten çalışan bir önbellek vekil sunucusu çalışmaya devam eder ve yeni limiti sonraki kontrolünde uygular.

### Modül önbelleği karma değerleri {#module-cache-hashes}

Derleme önbelleği ayarları <.localized_link href="/guides/features/projects/hashing">modül önbelleği karma değerlerinin</.localized_link> parçası değildir. Tuist, her `COMPILATION_CACHE_*` derleme ayarını ve değeriyle birlikte her `-cas-plugin-option` bayrağını karma dışında bırakır. `enableCaching` özelliğini açıp kapatmak veya yükleme politikasını değiştirmek, hedeflerinizin karma değerlerini korur; bu nedenle zaten ısıttığınız <.localized_link href="/guides/features/cache/module-cache">modül önbelleği</.localized_link> ikilileri geçerli kalır. Xcode önbelleği olan ve olmayan derlemeleri aynı modül önbelleğine karşı karşılaştırabilirsiniz.

> [!NOTE]
> **Ön ek eşleme ayarları karma değerlerine dahildir**
>
> Xcode 27 ve sonrasında, `enableCaching: true` ayrıca `SWIFT_ENABLE_PREFIX_MAPPING`, `SWIFT_ENABLE_PROJECT_PREFIX_MAPPING`, `CLANG_ENABLE_PREFIX_MAPPING`, `CLANG_ENABLE_PROJECT_PREFIX_MAPPING` ve `TUIST_PREFIX_MAPPING_FOR_COVERAGE_*` ayarlarını da belirler. Bu ayarlar modül önbelleği karma değerlerinin parçası olduğundan, Xcode 27 ve sonrasında `enableCaching` özelliğini açıp kapatmak hedeflerinizin karma değerlerini değiştirir.

### Büyük çıktıların bölümlerinin yeniden kullanılması {#reusing-parts-of-large-outputs}

Sunucu desteklediğinde, Xcode önbelleği büyük çıktıları parçalar halinde aktarır ve yalnızca önceki bir sürümden bu yana değişen parçaları gönderir veya getirir. Parçalar, `DerivedData` öğesinden ayrı küçük bir yerel önbellekte tutulur; böylece derleme önbelleği temizlendiğinde korunurlar. Küçük çıktılar, eski sunucular ve eski istemciler normal bütün çıktı aktarımlarını kullanır.

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

### CI üzerinde derleme önbelleği deposu {#compilation-cache-store-on-ci}

Derleme önbelleği deposu, Xcode'un derleme çıktılarını sakladığı yerel dizindir. `COMPILATION_CACHE_CAS_PATH` derleme ayarı konumunu belirler; bu konum varsayılan olarak `DerivedData` içindeki `CompilationCache.noindex` değeridir.

#### Durum bilgisi içeren depo {#stateful-store}

Derlemeler arasında bir depoyu korumak için, `COMPILATION_CACHE_CAS_PATH` (ve `tuist cache` için `TUIST_COMPILATION_CACHE_CAS_PATH`) öğesini kalıcı bir yola yönlendirin ve boyutunu bir [depo boyutu sınırı](#store-size-limit) ile sınırlayın.

## Sorun giderme {#troubleshooting}

### Derlemeler, Xcode önbellek proxy'sinin başarısız olduğunu uyarır {#cas-proxy-failed}

Bir derleme, hangi derlemenin önce hatayla karşılaştığına bağlı olarak Xcode'un `CAS error:` veya `CAS operation failed:` ön ekiyle başlattığı aşağıdaki gibi bir uyarı gösteriyorsa:

```
warning: CAS error: The Tuist Xcode cache proxy at /Users/you/.local/state/tuist/cas-proxy.sock failed (proxy connect: No such file or directory (os error 2)). Compilations that needed it used the local cache only, without remote cache hits. Their uploads are kept on disk and sent once the proxy is reachable again. Run `tuist setup cache` if the proxy is not running.
```

derleme önbelleği, `tuist setup cache` tarafından kurulan yerel önbellek proxy'sine ulaşamamış demektir. Derleme yine de başarılı olur, ancak etkilenen derlemeler uzak önbellek isabeti almaz; bu nedenle boş bir önbellekle çalışan bir derleme gibi çalışır. Yüklemeleri diskte tutulur ve proxy tekrar istekleri işlemeye başladığında gönderilir: zamanında geri dönerse aynı derleme sırasında, aksi takdirde aynı makinedeki sonraki derleme sırasında. İşten sonra atılan bir CI makinesi bunları kaybeder. Uyarı, her derlemede bir kez, Xcode'un Sorun gezgininde ve `xcodebuild` çıktısında görünür.

Proxy'nin çalışıp çalışmadığını kontrol etmek için, uyarıda adı geçen soketi dinleyen bir işlem arayın:

```bash
lsof ~/.local/state/tuist/cas-proxy.sock
```

Komut hiçbir şey yazdırmazsa, proxy'yi yeniden başlatmak için `tuist setup cache` komutunu çalıştırın. CI'da, her işte herhangi bir `xcodebuild` çağrısından önce `tuist setup cache` komutunu çalıştırın.

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

`COMPILATION_CACHE_REMOTE_SERVICE_PATH`, genellikle Tuist'in önceki sürümlerinin yapılandırdığı proje başına soket (`~/.local/state/tuist/<org>_<project>.sock`) olan, hiçbir şeyin dinlemediği bir soketi işaret ediyor demektir. Tuist artık bu sokete hizmet vermemektedir. Xcode, hızlıca hata vermek yerine her derleme önbelleği isteğinde bağlantıyı yeniden dener; bu da bir derlemenin bir saat veya daha uzun sürmesine neden olabilir ve Tuist bu davranışı değiştiremez.

Bunu düzeltmek için:

- **Oluşturulan projeler**: `tuist generate` komutunu tekrar çalıştırın.
- **Diğer projeler**: `COMPILATION_CACHE_*` derleme ayarlarını, [Xcode Derleme Ayarlarını Yapılandırma](#configure-xcode-build-settings) bölümünde açıklandığı gibi `tuist setup cache` tarafından yazdırılanlarla değiştirin.

Xcode önbelleğini kullanmıyorsanız, bunun yerine `COMPILATION_CACHE_*` derleme ayarlarını kaldırın ve `tuist teardown cache` komutunu çalıştırın.

### `uploaded CAS output`, yüklemeler devre dışı bırakılmış olsa bile yerel olarak görünür {#uploaded-cas-output-with-upload-disabled}

`xcodeCache: .xcodeCache(upload: false)` (veya CI olmayan bir makinede `upload: Environment.isCI`) ayarlandığında, derleme günlüğünde hala `note: uploaded CAS output ...` görebilirsiniz. `xcodebuild` bu çağrıları atlamanın bir yoluna sahip olmadığından, Tuist bunları almaya devam eder ancak Tuist sunucusuna hiçbir şey yayınlamaz. Kontrol paneli metrikleri bunu hesaba katar, bu nedenle sahte yükleme trafiği raporlanmaz.

## İlgili {#related}

Mühendislik ekiplerinin ve kodlama ajanlarının derleme yapıtlarını nasıl yeniden kullandığını görmek için [Tuist'in paylaşılan önbelleğini](https://tuist.dev/cache) keşfedin.
