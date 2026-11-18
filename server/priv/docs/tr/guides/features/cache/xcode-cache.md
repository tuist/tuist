---
{
  "title": "Xcode önbelleği",
  "titleTemplate": ":title · Önbellek · Özellikler · Kılavuzlar · Tuist",
  "description": "Tuist'in Xcode önbelleği entegrasyonu ile yerel ve CI ortamlarında Xcode derlemelerini hızlandırın."
}
---
# Xcode önbelleği {#xcode-cache}

Tuist, derleme sisteminin önbellekleme yeteneklerinden yararlanarak ekiplerin derleme yapıtlarını paylaşmasına olanak tanıyan Xcode derleme önbelleği için destek sağlar.

Xcode önbelleği Xcode 26 ile tanıtıldı. Buna Xcode derleme önbelleği de denir; girdilerine göre anahtarlanmış derleme yapıtlarını yeniden kullanır ve Tuist’in uzak önbelleği bu yapıtların makineler arasında paylaşılabilir olmasını sağlar. DerivedData ve Clang modül önbelleği ile ilişkisi için bkz. <.localized_link href="/references/concepts/build-cache#xcode">Xcode önbellekleri nelerdir?</.localized_link>. Yavaş bir derlemenin hangi bölümünün önbellek tarafından kaldırıldığını ve projede önce neyin düzeltilmesi gerektiğini öğrenmek için bkz. [Yavaş derlemeler](https://tuist.dev/solutions/slow-builds).

> [!TIP]
> **Modül önbelleği ile birleştirin**
>
> Xcode önbelleği ve <.localized_link href="/guides/features/cache/module-cache">modül önbelleği</.localized_link> farklı granülerlik düzeylerinde çalışır ve birbirini tamamlar. Modül önbelleği, derleme çalışmadan önce tüm modülleri önceden oluşturulmuş `.xcframework` dosyalarıyla değiştirirken, Xcode önbelleği derleme sırasında derleme çıktılarını yeniden kullanır.

> [!TIP]
> **Geliştirici makinelerinde temizlerken `CompilationCache.noindex` öğesini koruyun**
>
> Varsayılan olarak, derleme önbelleği deposu `DerivedData` içinde bulunur, bu nedenle `DerivedData` silindiğinde derleme ürünleriyle birlikte önbellek de atılır. Bir geliştirici makinesinde yalnızca derleme ürünlerini silmeyi tercih edin: yeniden derleme daha sonra diskteki depodan oynatılır ve hiçbir şey getirilmez.

## Kurulum {#setup}

Henüz bir Tuist hesabınız ve projeniz yoksa, aşağıdaki komutu çalıştırarak oluşturabilirsiniz:

```bash
tuist init
```

`Tuist.swift` dosyanızda `fullHandle` referansınız olduğunda, projeniz için önbelleklemeyi aşağıdaki komutu çalıştırarak ayarlayabilirsiniz:

```bash
tuist setup cache
```

Bu komut, Swift [derleme sistemi](https://github.com/swiftlang/swift-build)nin derleme yapıtlarını paylaşmak için kullandığı yerel bir önbellek hizmetini başlangıçta çalıştırmak üzere bir [LaunchAgent](https://developer.apple.com/library/archive/documentation/MacOSX/Conceptual/BPSystemStartup/Chapters/CreatingLaunchdJobs.html) oluşturur. İlk olarak geliştirici makinenizde ve her CI işinin kurulumunun bir parçası olarak çalıştırın.

CI üzerinde önbelleği ayarlamak için <.localized_link href="/guides/server/authentication#continuous-integration">kimlik doğrulaması</.localized_link> yaptığınızdan emin olun.

### Önbellek bileşenlerini güncelleme {#updating-the-cache-components}

Önbellek vekil sunucusu, kurulumu en son çalıştıran Tuist kurulumuna sabitlenmiş bir yol yerine kararlı bir başlatıcı kullanır. Kurulduktan sonra, `tuist setup cache` ve önbellek etkinleştirilmiş `tuist generate`, kullanılabilir bir hedefi daha yeni Tuist sürümlerine ilerletir. Daha eski bir Tuist’e sabitlenmiş projeler bu nedenle paylaşılan vekil sunucuyu düşürmez. Oluşturma yalnızca mevcut bir başlatıcı hedefini günceller: bir hizmet kurmaz, kimlik doğrulaması yapmaz, eklentiyi değiştirmez veya vekil sunucuyu yeniden başlatmaz. Özel eklenti, vekil sunucu, soket veya kayıt defteri geçersiz kılmaları otomatik ilerlemeyi atlar.

Çalışan vekil sunucu, en az 30 saniye boyunca önbellek isteği olmadan, uçuşta herhangi bir istek veya arka plan işi kalmadan ve yayın kuyrukları boşaltıldıktan sonra yeni hedefi benimser. Ardından çıkar ve launchd seçilen CLI’yı başlatarak hizmetin bağımsız değişkenlerini ve kimlik bilgisi ortamını korur. Hedefi gerçekten benimseyen tek vekil sunucu, disk üzerindeki eklentiyi paketinden atomik olarak yeniler; kurulum, eski vekil sunucu hâlâ boşaltma yaparken daha yeni bir eklenti kurmaz. Kurulu eklenti eksikse, açıkça yapılan boşta kurulum seçilen vekil sunucuyu yenilemeyi yeniden denemek için yeniden başlatır. Kayıt defterine ve kuyruklara sahip hâlâ yalnızca bir vekil sunucu vardır. Kullanılamayan bir hedef veya boşaltılmamış yüklemeler, aktif istekleri kesintiye uğratmak yerine geçişi erteler. Kimlik bilgisi yenileme, geçişten önce bile seçilen CLI’yı takip eder, bu nedenle daha eski bir CLI kurulumunu kaldırmak boşaltılmayı bekleyen yüklemeleri yolda bırakmaz.

Kararlı başlatıcıdan önce oluşturulan mevcut bir kurulum tek bir açık migrasyon gerektirir. Hiçbir derleme çalışmıyorken aşağıdakileri çalıştırın:

```bash
tuist setup cache
```

Bu migrasyondan sonra, Tuist’i güncellemek ve alıştığınız `tuist generate` komutunu çalıştırmak vekil sunucuyu ve kurulu eklentiyi ilerletmek için yeterlidir; her CLI sürümü için kurulumu yeniden çalıştırmanız gerekmez. Farklı bir Xcode seçmek için, aynı yolda güncellenen bir Xcode da dahil olmak üzere, açık kurulum hâlâ gereklidir. Yapılandırması değiştiğinde kurulum paylaşılan hizmeti değiştirebilir, bu nedenle önce makinedeki tüm derlemelerin bitmesini bekleyin. Vekil sunucu önceki eklenti protokolünü ve mevcut olanı destekler, bu nedenle Xcode’da zaten yüklenmiş uyumlu bir eklenti vekil sunucu yükseltmesi sırasında çalışmaya devam eder. En yeni eklentiyi yüklemek için Xcode’u tamamen kapatıp yeniden açın, ancak uyumlu yüklü bir eklenti acil bir yeniden başlatma gerektirmez. Bir sürüm oluşturulan derleme ayarlarını değiştirdiğinde projeleri yeniden oluşturun.

Seçilen Tuist kurulumunu kullanılabilir tutun: başlatıcı bunu başlangıç, yapılandırma ve kimlik bilgisi yenileme için kullanır. Başlatıcı ilerledikten sonra daha eski kurulumlar kaldırılabilir. Seçilen çalıştırılabilir dosya silinmişse veya artık çalıştırılabilir değilse, `tuist setup cache` önbelleği ilk önce sökmeden, mevcut bir kurulumu, hatta daha eski bir sürümü kullanarak hedefi onarabilir. Kararlı çalıştırılabilir takma adlar paket yöneticisi yükseltmeleri boyunca korunur; sembolik bağlantılar yalnızca kurulum kimliği karşılaştırılırken çözülür. Başlangıçta vekil sunucu, aslında başlatılan sürümü kaydeder; yerinde güncellemeler veya kasıtlı geri dönüşler dahil, kullanılabilir bir kurulumun ilgisiz eski checkout’lar tarafından değiştirilmesini önlemek için kullanılan en yüksek sürümü saklar.

Sürüm numarası olmayan kaynak tabanlı CLİ’ler ve açık `TUIST_CAS_PLUGIN_PATH` veya `TUIST_CAS_PROXY_PATH` kurulumları, otomatik sürüm seçimi yerine açık bir başlatma yapılandırması kullanır. Bu bileşenleri yeniden oluşturduktan sonra kurulumu yeniden çalıştırın. Kurulum tazeliklerini kontrol eder ve yönetilen hedef ilerlemesini yalnızca yedek hazır olduktan sonra devre dışı bırakır.

`tuist teardown cache`, launcher hedefini kaldırmadan önce hizmeti durdurur ve mevcut projeler için kararlı eklentiyi korur. Hizmeti durdurma başarısız olursa, launcher yeniden başlatma ve başka bir sökme denemesi için kullanılabilir kalır. Başarılı sökmeden sonra oluşturma hizmeti yeniden oluşturamaz.

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

`COMPILATION_CACHE_ENABLE_PLUGIN`, `COMPILATION_CACHE_PLUGIN_PATH`, `COMPILATION_CACHE_REMOTE_SERVICE_PATH` ve `COMPILATION_CACHE_ENABLE_DETACHED_KEY_QUERIES` öğelerinin Xcode’un derleme ayarları arayüzünde doğrudan gösterilmediğinden **kullanıcı tanımlı derleme ayarları** olarak eklenmesi gerektiğini unutmayın.

> [!NOTE]
> **Eklenti yolu**
>
> `libtuist_cas_plugin.dylib`, Tuist ile birlikte gelen ve `tuist` yürütülebilir dosyasının yanında yer alan derleme önbelleği eklentisidir. `tuist setup cache` bunu `$HOME/.local/state/tuist/libtuist_cas_plugin.dylib` konumuna kopyalar ve `COMPILATION_CACHE_PLUGIN_PATH` bu kopyayı işaret eder. Yol her makinede aynıdır ve Tuist’i güncellediğinizde değişmez, bu nedenle ayarı projenizle birlikte commit edebilirsiniz. Kurulum ve yeni başlatılan proxy, seçilen Tuist paketinden kopyayı yeniler; daha eski bir checkout’tan kurulum çalıştırmak daha yeni bir eklentiyi düşürmez.

> [!NOTE]
> **Her proje için tek bir soket**
>
> `tuist setup cache` makine başına tek bir önbellek proxy’si kurar, bu nedenle her proje aynı `COMPILATION_CACHE_REMOTE_SERVICE_PATH` değerini kullanır. Projeyi tanımlayan şey `tuist-instance` eklenti seçeneğidir.
>
> Xcode, `OTHER_SWIFT_FLAGS` ifadesini yalnızca Swift derleyicisine iletir; derleme sisteminin kendi yaptığı önbellek aramalarına iletmez. Bu aramalar, aynı derlemedeki Swift derleyicisi seçeneklerinden projeyi öğrenir. `tuist build`, `tuist test` ve `tuist xcodebuild` da projeyi doğrudan onlara iletir. Swift kodu içermeyen ve başka bir şekilde, örneğin düz `xcodebuild` veya Xcode uygulamasıyla derlenen bir proje, soket yolundan sonra projeyi ekleyebilir: `COMPILATION_CACHE_REMOTE_SERVICE_PATH = $HOME/.local/state/tuist/cas-proxy.sock?tuist-instance=your-org/your-project`. Aksi takdirde, önbellek proxy’sinin henüz görmediği bir makinedeki (örneğin işler arasında sıfırlanan bir CI makinesi) ilk derleme, zaten önbelleğe alınmış bazı dosyaları yeniden derleyebilir.

> [!IMPORTANT]
> **`COMPILATION_CACHE_REMOTE_SERVICE_PATH`, C ve Objective-C’yi paylaşan öğedir**
>
> Bu ayarı "önbellek hizmetinin bulunduğu yer" olarak okuyup isteğe bağlı olarak görmek kolaydır. Ayrıca C, Objective-C, önceden derlenmiş modüller ve önceden derlenmiş başlıkların paylaşılıp paylaşılmayacağına karar veren anahtardır: derleme sistemi, yalnızca bir uzak önbellek hizmeti yapılandırıldığında bunlar için önbellekleme çalıştırır. Bunu dışarıda bırakırsanız Swift derlemeleri yine de paylaşılır, ancak daha önce projeyi derlememiş herhangi bir makinede her C/Objective-C dosyası ve her modül yeniden derlenir.

> [!NOTE]
> **Eşzamanlı önbellek aramaları**
>
> `COMPILATION_CACHE_ENABLE_DETACHED_KEY_QUERIES`, derleme sisteminin her derleme için yaptığı uzak önbellek aramalarını, derlemenin yürütme şeritlerinde birkaçını birden yapmak yerine, derlemenin geri kalanıyla birlikte çalıştırır. Uzak bir önbellekten birçok derlemeyi kaçıran veya geri yükleyen derlemeler daha hızlı tamamlanır.

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
> Xcode 27 ve sonraki sürümlerde `tuist setup cache`, ayrıca `SWIFT_ENABLE_PREFIX_MAPPING`, `SWIFT_ENABLE_PROJECT_PREFIX_MAPPING`, `CLANG_ENABLE_PREFIX_MAPPING` ve `CLANG_ENABLE_PROJECT_PREFIX_MAPPING` değerlerini yazdırır. Bunlar, derleme önbelleği anahtarlarını projenin ve `DerivedData` konumundan bağımsız hale getirir. Bunları kullanıcı tanımlı derleme ayarları olarak ekleyin. Etkinleştirmek her önbellek anahtarını değiştirir, bu nedenle sonraki derleme önbelleği tekrar doldurur. `enableCaching` açıkken `tuist generate` bunları sizin için ayarlar.
>
> Derleyici ayrıca eşlenen yolları kod kapsamı verilerine yazar ve Xcode bunları çözümleyemez, bu nedenle bir kapsam raporu ön ek eşlemeyle derlenen tüm kaynakları dışarıda bırakır. Yazdırılan ayarlar, `TUIST_PREFIX_MAPPING_FOR_COVERAGE_*` ayarlarıyla birlikte, kod kapsamı toplayan derlemelerde ön ek eşlemeyi kapatır. `tuist generate` de aynısını yapar. Bu derlemeler hâlâ derleme önbelliğini kullanır, ancak önbellek anahtarları proje ve `DerivedData` yollarına bağlıdır.
>
> Bu ayarları komut satırında `xcodebuild` öğesine aktarırken, yukarıdaki `OTHER_SWIFT_FLAGS` örneğinde olduğu gibi `$(...)` içeren değerleri tek tırnak içine alın. Aksi takdirde kabuk bunları boş dizelere genişletir ve ön ek eşleme kapanır:
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

### Ön ek eşleme ile kapsam {#coverage-with-prefix-mapping}

Varsayılan olarak, oluşturulan projeler Xcode’un kapsam raporlarının ve `xccov` çalışmasını sağlamak için kapsam derlemelerinde ön ek eşlemeyi devre dışı bırakır. Kapsam derlemelerini checkout’lar arasında paylaşılabilir tutmak için bunu açabilirsiniz:

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

`TUIST_COVERAGE_PREFIX_MAPPING` ortam değişkeni (`1` veya `0`), `prefixMapping` üzerinde önceliklidir. Bu seçenek Xcode 27 ve sonraki sürümlerde geçerlidir ve `enableCaching` gerektirir. Kapsam `tuist test` yüklemeleri bunu destekler: Tuist, eşlenen yollarla kaynakları okuyan ve bunları deponuzun dosyalarına bağlayan `llvm-cov` ile çalışmayı ölçer. Xcode’un kendi kapsam raporu ve `xccov` hâlâ bu kaynakları dışarıda bırakabilir; ayrıca `llvm-cov` dışa aktarma başarısız olduğunda sonuç paketinin `xccov` raporuna geri dönen bir yükleme de aynı durumu gösterebilir. Eşlenen `#filePath` değerleri, sabitleri kaynak dosyalara göre konumlandıran testleri de etkileyebilir; bunun yerine sabitleri açık çalışma zamanı checkout yolları üzerinden çözümleyin. Kapsamı kendiniz işliyorsanız, her enstrümante edilmiş ikili dosyayı sanal ön ekleri yerel dizinlere eşleyen hedefin `$(TARGET_TEMP_DIR)/compilation-prefix-map.json` değeriyle eşleştirin. Proje başına eşleme etkinleştirildiğinde bir hedefin haritasını her ikili dosya için yeniden kullanmayın.

Kapsam-ön ek ayarları, kapsam yapıtlarına yazılan yolları kontrol ettikleri için ikili önbellek ve seçici test karma değerlerine katılır. Bu seçeneği değiştirmek veya `TUIST_COVERAGE_PREFIX_MAPPING` farklı ayarlamak, normal derlemeler için bile bu karma değerlerini geçersiz kılar. Geliştiriciler ve CI işleri arasında ikili önbellekleri ve seçici test sonuçlarını paylaşmaları gerekiyorsa değeri tutarlı tutun.

### Oluşturulan projelerde hata ayıklama {#debugging-generated-projects}

Geri yüklenen yerel modüller, bağlantılı hata ayıklama bilgilerinin yanı sıra derleme önbelleğine erişime de ihtiyaç duyar. Tuist, Debug ve Release modüllerini dSYM’ler ve dilim başına kaynak kimliği meta verileriyle ısıtır, ardından bir hedefi değiştirmeden önce meta verileri tüketicinin bildirilen kaynaklarına karşı doğrular. Eksik veya uyumsuz meta veriler, o hedefin kaynaklarını korur. Betikle oluşturulan `.generated(...)` kaynakları, doğrulanabilir içerik sağlama toplamları yerine bildirim parmak izlerine sahiptir, bu nedenle bu hedefler kaynak tabanlı kalır ve yerel modül önbelleğine yayımlanmaz. Gerçek içerik sağlama toplamlarına sahip oluşturulmuş kaynak erişimcileri uygun olmaya devam eder. Desteklenmeyen hata ayıklama bilgileri, ilgili olmayan ürünleri engellemeden etkilenen hedefin yayımlanmasını atlar; kaynak mutasyonu ve iptal hâlâ ısıtmayı başarısız kılar. Önbellek formatı değişir, bu nedenle daha eski sürümler tarafından ısıtılan yapıtların yeniden ısıtılması gerekir.

Doğrulanmış değiştirmeler için Tuist, tüketiciye ait dSYM UUID plist'lerinde kaynak yeniden konumlandırmaları hazırlar ve statik önbelleğe alınmış kodlar için yalnızca hata ayıklamaya yönelik eşlikçileri bağlar. Önbelleğe alınmış ikili dosyaları yeniden yazmaz veya LLDB'nin kalıcı genel kaynak haritasına üretici kaynak yollarını yüklemez. Açık hata ayıklayıcı başlatıcıları ve modül yükleyici ayarları belirleyici olmaya devam eder. CI ortamında (`CI` veya `JENKINS_URL` ayarlandığında), bunu yapan şema ön eylemi değişiklik yapmadan sonlanır çünkü orada testlere hiçbir hata ayıklayıcı bağlanmaz. Hata ayıklama sembolleri ve kaynak yeniden konumlandırma, kaynak bağımlı çalışma zamanı dosya erişimini veya yerel Xcode kapsam raporlarını onarmaz; kapsam varyantı seçimi ve LLVM dışa aktarma ayrı özellikler olarak kalır.

`enableCaching: true` ile Tuist, Çalıştırma ve Test eylemleri için LLDB kaynak haritalarını yapılandırır. Bir eylemin özel bir LLDB başlatıcısı varsa, Tuist önce çözümlenmiş kaynak haritasını yazar, ardından haritayı genişletmesi veya üzerine yazması için özel başlatıcıyı kaynak olarak yükler. Aksi takdirde, kaynak haritasını değiştirmeden önce dosya varsa `~/.lldbinit-Xcode` dosyasını yükler, yoksa `~/.lldbinit` dosyasına geri döner. Yalnızca bir ana dizin dosyası yükler, çift kaynak yükleme olmadan kullanıcı başına hata ayıklayıcı kurulumunu geri yükler. Değiştirme, önceki çalıştırmalardaki eski eşlemeleri kaldırır ve ana dizin dosyası kaynak haritalarına göre önceliklidir; hayatta kalması gereken kaynak haritası girdilerini eylemin özel başlatıcısına yerleştirin. Diğer ana dizin ayarları korunur. Tuist'in önbelleğe özgü modül arama yolları, yükleyici ayarları ve Clang bayrakları daha sonra uygulanır ve bu ayarlar için kullanıcı değerlerine göre öncelik kazanır. Ana dizin dosyası hataları, sonraki komutların yüklenmesini durdurmadan görünür kalır ve komutlar yankılanmaz. Bu başlatıcı koruma, Tuist modül önbelleğinden geri yüklenen ikili dosyalar için hata ayıklamayı yapılandırdığında, hatta `enableCaching` olmadan ve daha eski Xcode sürümlerinde bile geçerlidir.

Xcode 27 ve sonraki sürümlerde, oluşturulan projeler bir proje bunları ayarlamadıkça Xcode'un proje başına ön ek eşlemelerini (`SWIFT_ENABLE_PROJECT_PREFIX_MAPPING` ve `CLANG_ENABLE_PROJECT_PREFIX_MAPPING`) kapalı bırakır. `/^src` gibi ön ekleri, her projede farklı bir dizini adlandırır ve LLDB bunları yalnızca hata ayıklanan hedefin projesine göre çözümler. Kaynaklar bunun yerine çalışma alanı genelindeki ön ekler altında kaydedilir: Tuist kök dizini için `/^root`, Swift paketi geçici dizini için `/^spm` ve derleme çıktıları için `/^intermediates` ve `/^products`. Her biri her projede aynı dizini adlandırdığından, kesme noktaları çalışma alanındaki herhangi bir projedeki kaynaklarda çözümlenir.

Tuist kökü dışındaki yollar eşlenmez. Kök dışındaki bir projenin önbellek anahtarları, nereye çekildiğine bağlıdır, bu nedenle diğer çekimler ve makineler onun için önbelleği ıskalar. Anahtarlarının çekim konumundan bağımsız kalmasını sağlamak için, o projenin manifestosunda proje başına eşlemeleri açın:

```swift
let checkoutIndependentSettings = Settings.settings(base: [
    "SWIFT_ENABLE_PROJECT_PREFIX_MAPPING": "YES",
    "CLANG_ENABLE_PROJECT_PREFIX_MAPPING": "YES",
])
```

Bu ayarları o `Project` öğesine iletin. Başka bir projeden bir hedefi hata ayıkladığınızda, LLDB o projenin kaynaklarını bulamaz. Manifesto proje tabanı ayarları, proje düzeyindeki xcconfig değerlerine göre önceliklidir, bu nedenle bunları manifesto içinde ayarlayın.

Bu ayarları değiştirmek derleme önbelleği anahtarlarını, ikili önbellek karma değerlerini ve seçici test karma değerlerini değiştirir, bu nedenle bu önbelleklerin tekrar ısıtılması gerekir. Seçiminizi ekibiniz genelinde tutarlı tutun.

### Önbellek yükleme politikası {#cache-upload-policy}

Varsayılan olarak, önbellek hizmeti hem uzak önbelleğe yapıtları indirir hem de yükler. Bunu, yapıtların indirildiği ancak asla yüklenmediği salt okunur modu etkinleştirmek için `Tuist.swift` dosyanızdaki `xcodeCache` seçeneği ile kontrol edebilirsiniz:

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

Yaygın bir desen, yerel ortamları salt okunur tutarken, yapıtları yalnızca derlemelerin tekrarlanabilir olduğu CI ortamından itmektedir. Bunu, çoğu CI sağlayıcısı tarafından ayarlanan `CI` ortam değişkenini kontrol eden `Environment.isCI` kullanarak başarabilirsiniz:

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

Bu kurulumla, yerel derlemeler yükleme yapmadan önbelleğe alınmış yapıtlardan faydalanırken, CI derlemeleri ekibin geri kalanı için önbelleği doldurur.

Yükleme politikası, `tuist setup cache` çalıştıran makinede proje başına kaydedilir. Değiştirmek için `upload` güncelleyin ve `tuist setup cache` komutunu tekrar çalıştırın; Tuist projenizi oluşturuyorsa `tuist generate` komutunu da çalıştırın. Bundan sonraki yüklemeler, o makinedeki önbelleği yeniden başlatmadan yeni politikayı izler. Aynı makinede aynı anda çalışan aynı proje için işler politikayı paylaşır, bu nedenle en son `tuist setup cache` hepsi için kararı verir.

### Depo boyutu sınırı {#store-size-limit}

Derleme önbellek deposu her derleme ile büyür. Projenin depolarını sınırlamak için `Tuist.swift` dosyanızda `storeSizeLimit` ayarını yapın:

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

Tuist, önbellek vekil sunucusu başladığında, herhangi bir derleme bunları kullanmadan önce projenin her bir deposunu kontrol eder ve derleme çalışmadığı sürece her 10 dakikada bir kontrolü tekrarlar. `tuist setup cache`, vekil sunucu çalışmıyorsa onu başlatır; bu nedenle derlemelerinden önce `tuist setup cache` ve sonrasında `tuist teardown cache` çalıştıran bir CI işi, uzun ömürlü bir çalıştırıcının depolarını her işin başında sınırlar. Daha yeni derlemeler sınırın yaklaşık yarısı kadar veri yazdığında, deponun en eski önbelleğe alınmış çıktılarını siler, böylece depo yaklaşık sınırda dengelenir. Derlemeler çalışırken bir depo sınırdan daha büyük olabilir ve limiti ayarladığınızda zaten daha büyük olan bir depo, yeni derlemeler o kadar veri yazdığında küçülür. Varsayılan konumunda olduğu gibi birkaç proje aynı depoyu kullandığında, en küçük limit uygulanır. Limit, `tuist setup cache` çalıştırdığınız her makinede geçerlidir, bu nedenle limiti değiştirdikten sonra komutu tekrar çalıştırın. Zaten çalışan bir önbellek vekil sunucusu çalışmaya devam eder ve yeni limiti sonraki kontrolünde uygular.

### Modül önbelleği karma değerleri {#module-cache-hashes}

Derleme önbelleği ayarları <.localized_link href="/guides/features/projects/hashing">modül önbelleği karma değerlerinin</.localized_link> parçası değildir. Tuist, her `COMPILATION_CACHE_*` derleme ayarını ve değeriyle birlikte her `-cas-plugin-option` bayrağını karma değerinin dışında bırakır. `enableCaching` özelliğini açıp kapatmak veya yükleme politikasını değiştirmek hedeflerinizin karma değerlerini korur, bu nedenle zaten ısıttığınız <.localized_link href="/guides/features/cache/module-cache">modül önbelleği</.localized_link> ikili dosyaları geçerli kalır. Xcode önbelleği olan ve olmayan derlemeleri aynı modül önbelleğine karşı karşılaştırabilirsiniz.

> [!NOTE]
> **Ön ek eşleme ayarları karma değere dahildir**
>
> Xcode 27 ve sonraki sürümlerde, `enableCaching: true` ayrıca `SWIFT_ENABLE_PREFIX_MAPPING`, `SWIFT_ENABLE_PROJECT_PREFIX_MAPPING`, `CLANG_ENABLE_PREFIX_MAPPING`, `CLANG_ENABLE_PROJECT_PREFIX_MAPPING` ve `TUIST_PREFIX_MAPPING_FOR_COVERAGE_*` ayarlarını da ayarlar. Bu ayarlar modül önbelleği karma değerlerinin parçasıdır, bu nedenle Xcode 27 ve sonraki sürümlerde `enableCaching` özelliğini açıp kapatmak hedeflerinizin karma değerlerini değiştirir.

### Büyük çıktıların parçalarının yeniden kullanılması {#reusing-parts-of-large-outputs}

Sunucu desteklediğinde, Xcode önbelleği büyük çıktıları parçalar halinde aktarır ve yalnızca önceki bir sürümden bu yana değişen parçaları gönderir veya getirir. Parçalar, `DerivedData` öğesinden ayrı küçük bir yerel önbellekte tutulur, böylece derleme önbelleğini temizleseniz bile korunurlar. Küçük çıktılar, eski sunucular ve eski istemciler normal bütün çıktı transferlerini kullanır.

Bu, ne kadar yeniden derlendiğini değil, ne kadar indirilip yüklendiğini azaltır. Eşleşen parçası olmayan soğuk bir makine yine de tüm çıktıyı indirir.

### Sürekli entegrasyon {#continuous-integration}

CI ortamınızda önbelleğe almayı etkinleştirmek için yerel ortamlardakiyle aynı komutu çalıştırmanız gerekir: `tuist setup cache`.

Kimlik doğrulama için, desteklenen CI sağlayıcıları için önerilen <.localized_link href="/guides/server/authentication#oidc-tokens">OIDC kimlik doğrulamasını</.localized_link> veya `TUIST_TOKEN` ortam değişkeni aracılığıyla bir <.localized_link href="/guides/server/authentication#account-tokens">hesap token'ını</.localized_link> kullanabilirsiniz.

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

Token tabanlı kimlik doğrulama ve Xcode Cloud, CircleCI, Bitrise ve Codemagic gibi diğer CI platformlarını içeren daha fazla örnek için <.localized_link href="/guides/integrations/continuous-integration">Sürekli Entegrasyon kılavuzuna</.localized_link> bakın.

### CI üzerinde derleme önbelleği deposu {#compilation-cache-store-on-ci}

Derleme önbelleği deposu, Xcode'un derleme çıktılarını sakladığı yerel dizindir. `COMPILATION_CACHE_CAS_PATH` derleme ayarı konumunu belirler; varsayılan olarak `DerivedData` içindeki `CompilationCache.noindex` olur.

#### Durum bilgisi içeren depo {#stateful-store}

Derlemeler arasında bir depoyu korumak için `COMPILATION_CACHE_CAS_PATH` (ve `tuist cache` için `TUIST_COMPILATION_CACHE_CAS_PATH`) ayarını kalıcı bir yola yönlendirin ve boyutunu bir [depo boyutu limiti](#store-size-limit) ile sınırlayın.

## Sorun giderme {#troubleshooting}

### Derlemeler Xcode önbellek vekil sunucusunun başarısız olduğunu bildiriyor {#cas-proxy-failed}

Bir derleme, hangi derlemenin ilk olarak hatayla karşılaştığına bağlı olarak Xcode'un `CAS error:` veya `CAS operation failed:` ön ekiyle başlattığı aşağıdaki gibi bir uyarı gösteriyorsa:

```
warning: CAS error: The Tuist Xcode cache proxy at /Users/you/.local/state/tuist/cas-proxy.sock failed (proxy connect: No such file or directory (os error 2)). Compilations that needed it used the local cache only, without remote cache hits. Their uploads are kept on disk and sent once the proxy is reachable again. Run `tuist setup cache` if the proxy is not running.
```

derleme önbelleği, `tuist setup cache` tarafından kurulan yerel önbellek vekil sunucusuna ulaşamamış demektir. Derleme yine de başarılı olur ancak etkilenen derlemeler uzak önbellek isabeti alamaz, bu nedenle boş önbellekli bir derleme gibi çalışır. Yüklemeleri diskte tutulur ve vekil sunucu tekrar istekleri işlemeye başladığında gönderilir: zamanında geri gelirse aynı derleme içinde daha sonra, aksi takdirde aynı makinedeki sonraki derleme sırasında. İşten sonra atılan bir CI makinesi bunları kaybeder. Uyarı, her derleme için bir kez, Xcode'un Sorun gezgininde ve `xcodebuild` çıktısında görünür.

Vekil sunucunun çalışıp çalışmadığını kontrol etmek için uyarıda adı geçen soketi dinleyen bir süreç arayın:

```bash
lsof ~/.local/state/tuist/cas-proxy.sock
```

Komut hiçbir şey yazdırmazsa, vekil sunucuyu tekrar başlatmak için `tuist setup cache` çalıştırın. CI'da, her işte herhangi bir `xcodebuild` çağrısından önce `tuist setup cache` çalıştırın.

### Derlemeler son derece yavaş ve `CAS error: deadlineExceeded` uyarıları veriyor {#cas-deadline-exceeded}

Derlemeleriniz beklenenden çok daha uzun sürüyorsa ve Xcode derleme günlüğü şu şekilde uyarılarla doluyorsa:

```
Warning: CAS error: deadlineExceeded(connectionError: Optional(connect(descriptor:addr:size:): No such file or directory (errno: 2)))
note: cache key query failed
```

veya:

```
Warning: CAS error: deadlineExceeded(connectionError: Optional(connect(descriptor:addr:size:): Connection refused (errno: 61)))
```

`COMPILATION_CACHE_REMOTE_SERVICE_PATH`, genellikle Tuist'in önceki sürümlerinin yapılandırdığı proje başına sokete (`~/.local/state/tuist/<org>_<project>.sock`) işaret ediyor demektir. Tuist artık bu soketi sunmuyor. Xcode, hızlı hata vermek yerine her derleme önbelleği isteğinde bağlantıyı yeniden dener; bu da bir derlemenin bir saat veya daha fazla sürmesine neden olabilir ve Tuist bu davranışı değiştiremez.

Düzeltmek için:

- **Oluşturulan projeler**: `tuist generate` komutunu tekrar çalıştırın.
- **Diğer projeler**: [Xcode Derleme Ayarlarını Yapılandırma](#configure-xcode-build-settings) bölümünde açıklandığı gibi, `COMPILATION_CACHE_*` derleme ayarlarını `tuist setup cache` tarafından yazdırılanlarla değiştirin.

Xcode önbelleğini kullanmıyorsanız, bunun yerine `COMPILATION_CACHE_*` derleme ayarlarını kaldırın ve `tuist teardown cache` çalıştırın.

### `uploaded CAS output`, yüklemeler devre dışı olsa bile yerelde görünüyor {#uploaded-cas-output-with-upload-disabled}

`xcodeCache: .xcodeCache(upload: false)` (veya CI olmayan bir makinede `upload: Environment.isCI`) ayarlandığında, derleme günlüğünde hala `note: uploaded CAS output ...` görebilirsiniz. `xcodebuild` bu çağrıları atlamanın bir yoluna sahip değildir, bu nedenle Tuist bunları alır ancak Tuist sunucusunda hiçbir şey yayınlamaz. Kontrol paneli metrikleri bunu hesaba katar, bu nedenle sahte yükleme trafiği raporlanmaz.

## İlgili {#related}

Mühendislik ekiplerinin ve kodlama ajanlarının derleme yapıtlarını nasıl yeniden kullandığını görmek için [Tuist'in paylaşılan önbelleğini](https://tuist.dev/cache) keşfedin.
