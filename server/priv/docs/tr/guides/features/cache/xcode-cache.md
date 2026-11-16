---
{
  "title": "Xcode önbelleği",
  "titleTemplate": ":title · Önbellek · Özellikler · Kılavuzlar · Tuist",
  "description": "Tuist'in Xcode önbellek entegrasyonu ile yerel ve CI ortamında Xcode derlemelerini hızlandırın."
}
---
# Xcode önbelleği {#xcode-cache}

Tuist, Xcode derleme önbelleği desteği sunar; bu sayede ekipler, derleme sisteminin önbellekleme yeteneklerinden yararlanarak derleme yapıtlarını paylaşabilir.

Xcode önbelleği Xcode 26 ile tanıtıldı. Buna Xcode derleme önbelleği de denir; girdilerine göre anahtarlanan derleme yapıtlarını yeniden kullanır ve Tuist’in uzak önbelleği bu yapıtların makineler arasında paylaşılmasını sağlar. DerivedData ve Clang modül önbelleği ile ilişkisi için bkz. <.localized_link href="/references/concepts/build-cache#xcode">Xcode önbellekleri nelerdir?</.localized_link>. Yavaş bir derlemede önbelleğin hangi kısmı ortadan kaldırdığını ve projede öncelikle neyin düzeltilmesi gerektiğini öğrenmek için bkz. [Yavaş derlemeler](https://tuist.dev/solutions/slow-builds).

> [!TIP]
> **Modül önbelleği ile birlikte kullanın**
>
> Xcode önbelleği ve <.localized_link href="/guides/features/cache/module-cache">modül önbelleği</.localized_link> farklı granülerite düzeylerinde çalışır ve birbirini tamamlar. Modül önbelleği, derleme başlamadan önce tüm modülleri önceden oluşturulmuş `.xcframework` dosyalarıyla değiştirirken, Xcode önbelleği derleme sırasında derleme çıktılarını yeniden kullanır.

> [!TIP]
> **Geliştirici makinelerinde temizleme yaparken `CompilationCache.noindex` dosyasını saklayın**
>
> Varsayılan olarak, derleme önbelleği deposu `DerivedData` içinde bulunur; bu nedenle `DerivedData` silindiğinde derleme ürünleriyle birlikte önbellek de atılır. Geliştirici makinesinde yalnızca derleme ürünlerini silmeyi tercih edin: böylece yeniden derleme diskteki depodan oynatılır ve hiçbir şey indirilmez.

## Kurulum {#setup}

Henüz bir Tuist hesabınız ve projeniz yoksa, aşağıdaki komutu çalıştırarak oluşturabilirsiniz:

```bash
tuist init
```

`Tuist.swift` dosyanızda `fullHandle` referansı bulunduğunda, projeniz için önbelleklemeyi şu komutu çalıştırarak kurabilirsiniz:

```bash
tuist setup cache
```

Bu komut, Swift [derleme sisteminin](https://github.com/swiftlang/swift-build) derleme yapıtlarını paylaşmak için kullandığı yerel bir önbellek hizmetini başlangıçta çalıştırmak üzere bir [LaunchAgent](https://developer.apple.com/library/archive/documentation/MacOSX/Conceptual/BPSystemStartup/Chapters/CreatingLaunchdJobs.html) oluşturur. İlk olarak geliştirici makinenizde ve her CI işinin kurulumunun bir parçası olarak çalıştırın.

CI üzerinde önbelleği kurmak için <.localized_link href="/guides/server/authentication#continuous-integration">kimlik doğrulaması</.localized_link> yaptığınızdan emin olun.

### Önbellek bileşenlerini güncelleme {#updating-the-cache-components}

Önbellek vekil sunucusu, en son kurulumu çalıştıran Tuist kurulumuna sabitlenmiş bir yol yerine kararlı bir başlatıcı kullanır. Kurulduktan sonra, `tuist setup cache` ve önbellek etkinleştirilmiş `tuist generate` kullanılabilir bir hedefi daha yeni Tuist sürümlerine ilerletir. Daha eski bir Tuist’e sabitlenmiş projeler bu nedenle paylaşılan vekil sunucuyu düşürmez. Oluşturma yalnızca mevcut bir başlatıcı hedefini günceller: bir hizmet kurmaz, kimlik doğrulaması yapmaz, eklentiyi değiştirmez veya vekil sunucuyu yeniden başlatmaz. Özel eklenti, vekil sunucu, soket veya kayıt defteri geçersiz kılmaları otomatik ilerlemeyi atlar.

Çalışan vekil sunucu, en az 30 saniye boyunca önbellek isteği olmadığında, havada kalan istek veya arka plan işi kalmadığında ve yayın kuyrukları boşaltıldığında yeni hedefi benimser. Ardından çıkar ve launchd seçilen CLI’yı başlatarak hizmetin bağımsız değişkenlerini ve kimlik bilgisi ortamını korur. Hedefi gerçekten benimseyen vekil sunucu yalnızca disk üzerindeki eklentiyi paketinden atomik olarak yeniler; eski vekil sunucu hâlâ boşaltma yaparken kurulum daha yeni bir eklenti yüklemez. Kurulu eklenti eksikse, açıkça belirtilen boşta kurulum seçilen vekil sunucuyu yeniden başlatarak yenilemeyi tekrar dener. Kayıt defterine ve kuyruklara sahip hâlâ tek bir vekil sunucu vardır. Kullanılamayan bir hedef veya boşaltılmamış yüklemeler, aktif istekleri kesintiye uğratmak yerine geçişi erteler. Kimlik bilgisi yenileme, geçişten önce bile seçilen CLI’yı takip eder; bu nedenle daha eski bir CLI kurulumunu kaldırmak, boşaltmayı bekleyen yüklemeleri yarı yolda bırakmaz.

Kararlı başlatıcıdan önce oluşturulmuş mevcut bir kurulum tek bir açık migrasyon gerektirir. Hiçbir derleme çalışmıyorken aşağıdakini çalıştırın:

```bash
tuist setup cache
```

Bu migrasyondan sonra, Tuist’i güncellemek ve alıştığınız `tuist generate` komutunu çalıştırmak vekil sunucuyu ve kurulu eklentiyi ilerletmek için yeterlidir; her CLI sürümü için kurulumu yeniden çalıştırmanız gerekmez. Farklı bir Xcode seçmek için, aynı yolda güncellenen bir Xcode dahil, açık kurulum hâlâ gereklidir. Yapılandırması değiştiğinde kurulum paylaşılan hizmeti değiştirebilir; bu nedenle önce makinedeki tüm derlemelerin bitmesini bekleyin. Vekil sunucu önceki eklenti protokolünü ve mevcut olanı destekler; bu nedenle Xcode’da zaten yüklü uyumlu bir eklenti, vekil sunucu yükseltmesi sırasında çalışmaya devam eder. En yeni eklentiyi yüklemek için Xcode’u tamamen kapatıp yeniden açın, ancak uyumlu yüklü bir eklenti acil yeniden başlatma gerektirmez. Bir sürüm oluşturulan derleme ayarlarını değiştirdiğinde projeleri yeniden oluşturun.

Seçilen Tuist kurulumunu kullanılabilir durumda tutun: başlatıcı bunu başlangıç, yapılandırma ve kimlik bilgisi yenileme için kullanır. Başlatıcı ilerledikten sonra daha eski kurulumlar kaldırılabilir. Seçilen yürütülebilir dosya silindiyse veya artık yürütülebilir değilse, `tuist setup cache` önbelleği önce kaldırmadan, mevcut bir kurulumu (hatta daha eski bir sürümü) kullanarak hedefi onarabilir. Kararlı yürütülebilir takma adları paket yöneticisi yükseltmeleri boyunca korunur; sembolik bağlantılar yalnızca kurulum kimliği karşılaştırılırken çözülür. Başlangıçta vekil sunucu, yerinde güncellemeler veya kasıtlı geri almalar dahil olmak üzere gerçekten başlatılan sürümü kaydeder ve alakasız eski checkout’ların kullanılabilir bir kurulumu değiştirmesini önlemek için kullanılan en yüksek sürümü saklar.

Sürüm numarası olmayan kaynak tabanlı CLI’lar ve açık `TUIST_CAS_PLUGIN_PATH` veya `TUIST_CAS_PROXY_PATH` kurulumları, otomatik sürüm seçimi yerine açık bir başlatma yapılandırması kullanır. Bu bileşenleri yeniden derledikten sonra kurulumu yeniden çalıştırın. Kurulum, bunların güncelliğini kontrol eder ve yedek hazır olduktan sonra yönetilen hedef ilerlemesini devre dışı bırakır.

`tuist teardown cache` başlatıcı hedefini kaldırmadan önce hizmeti durdurur ve mevcut projeler için kararlı eklentiyi saklar. Hizmeti durdurma başarısız olursa, başlatıcısı yeniden başlatma ve başka bir sökme denemesi için kullanılabilir kalır. Başarılı sökmeden sonra oluşturma hizmeti yeniden oluşturamaz.

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
> `libtuist_cas_plugin.dylib`, Tuist ile birlikte gelen ve `tuist` yürütülebilir dosyasının yanında yer alan derleme önbelleği eklentisidir. `tuist setup cache` bunu `$HOME/.local/state/tuist/libtuist_cas_plugin.dylib` konumuna kopyalar ve `COMPILATION_CACHE_PLUGIN_PATH` bu kopyayı işaret eder. Yol her makinede aynıdır ve Tuist'i güncellediğinizde değişmez, bu nedenle ayarı projenizle birlikte commit edebilirsiniz. Kurulum ve yeni başlatılan proxy, seçilen Tuist paketinden kopyayı yeniler; daha eski bir checkout'tan kurulum çalıştırmak daha yeni bir eklentiyi düşürmez.

> [!NOTE]
> **Her proje için tek bir soket**
>
> `tuist setup cache` makine başına tek bir önbellek proxy'si kurar, bu nedenle her proje aynı `COMPILATION_CACHE_REMOTE_SERVICE_PATH` değerini kullanır. Projeyi tanımlayan şey `tuist-instance` eklenti seçeneğidir.

> [!IMPORTANT]
> **`COMPILATION_CACHE_REMOTE_SERVICE_PATH` C ve Objective-C kodunu paylaşan öğedir**
>
> Bu ayarı "önbellek hizmetinin bulunduğu yer" olarak okuyup isteğe bağlı olarak değerlendirmek kolaydır. Aynı zamanda C, Objective-C, önceden derlenmiş modüller ve önceden derlenmiş başlık dosyalarının paylaşılıp paylaşılmayacağını belirleyen anahtardır: derleme sistemi yalnızca bir uzak önbellek hizmeti yapılandırıldığında bunlar için önbellekleme çalıştırır. Bunu dışarıda bırakırsanız Swift derlemeleri yine de paylaşılır, ancak projeyi daha önce derlememiş olan herhangi bir makinede her C/Objective-C dosyası ve her modül yeniden derlenir.

> [!NOTE]
> **Eşzamanlı önbellek aramaları**
>
> `COMPILATION_CACHE_ENABLE_DETACHED_KEY_QUERIES`, derleme sisteminin her derleme için yaptığı uzak önbellek aramalarını, derlemenin yürütme kanallarında birkaçずつ yapmak yerine, derlemenin geri kalanıyla birlikte çalıştırır. Uzak bir önbellekten birçok derlemeyi kaçıran veya geri yükleyen derlemeler daha hızlı tamamlanır.

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
> Xcode 27 ve sonraki sürümlerde `tuist setup cache` ayrıca `SWIFT_ENABLE_PREFIX_MAPPING`, `SWIFT_ENABLE_PROJECT_PREFIX_MAPPING`, `CLANG_ENABLE_PREFIX_MAPPING` ve `CLANG_ENABLE_PROJECT_PREFIX_MAPPING` değerlerini yazdırır. Bunlar, derleme önbelleği anahtarlarını projenin ve `DerivedData` konumundan bağımsız hale getirir. Bunları kullanıcı tanımlı derleme ayarları olarak ekleyin. Bunları etkinleştirmek her önbellek anahtarını değiştirir, bu nedenle sonraki derleme önbelleği tekrar doldurur. `enableCaching` açıkken `tuist generate` bunları sizin için ayarlar.
>
> Derleyici ayrıca eşlenen yolları kod kapsamı verilerine yazar ve Xcode bunları çözemez, bu nedenle bir kapsam raporu ön ek eşleme ile derlenen her kaynağı dışarıda bırakır. Yazdırılan ayarlar, `TUIST_PREFIX_MAPPING_FOR_COVERAGE_*` ayarlarıyla birlikte, kod kapsamı toplayan derlemelerde ön ek eşlemeyi kapatır. `tuist generate` de aynısını yapar. Bu derlemeler hâlâ derleme önbelleğini kullanır, ancak önbellek anahtarları proje ve `DerivedData` yollarına bağlıdır.
>
> Bu ayarları komut satırında `xcodebuild` öğesine aktardığınızda, yukarıdaki `OTHER_SWIFT_FLAGS` örneğinde olduğu gibi `$(...)` içeren değerleri tek tırnak içine alın. Aksi takdirde kabuk bunları boş dizelere genişletir ve ön ek eşleme kapatılır:
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

Varsayılan olarak, oluşturulan projeler Xcode'un kapsam raporlarının ve `xccov` işlevinin çalışmasını sağlamak için kapsam derlemelerinde ön ek eşlemeyi devre dışı bırakır. Kapsam derlemelerini checkout'lar arasında paylaşılabilir tutmak için bunu açabilirsiniz:

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

`TUIST_COVERAGE_PREFIX_MAPPING` ortam değişkeni (`1` veya `0`), `prefixMapping` üzerinde önceliklidir. Bu seçenek Xcode 27 ve sonraki sürümlerde geçerlidir ve `enableCaching` gerektirir. Kapsam `tuist test` yüklemeleri bunu destekler: Tuist, çalışmayı eşlenen yollarla kaynakları okuyan `llvm-cov` ile ölçer ve bunları deponuzdaki dosyalara bağlar. Xcode'un kendi kapsam raporu ve `xccov` bu kaynakları yine de dışarıda bırakabilir; ayrıca `llvm-cov` dışa aktarma başarısız olduğunda sonuç paketinin `xccov` raporuna geri dönen bir yükleme de aynı şekilde davranabilir. Eşlenen `#filePath` değerleri, sabitleri kaynak dosyalara göre konumlandıran testleri de etkileyebilir; bunun yerine sabitleri açık çalışma zamanı checkout yolları üzerinden çözün. Kapsamı kendiniz işliyorsanız, her enstrümante edilmiş ikili dosyayı sanal ön ekleri yerel dizinlere eşleyen hedefin `$(TARGET_TEMP_DIR)/compilation-prefix-map.json` değeriyle eşleştirin. Proje başına eşleme etkinleştirildiğinde bir hedefin haritasını her ikili dosya için yeniden kullanmayın.

Kapsam-ön ek ayarları, kapsam yapıtlarına yazılan yolları kontrol ettikleri için ikili önbellek ve seçici test karma değerlerine katılır. Bu seçeneği değiştirmek veya `TUIST_COVERAGE_PREFIX_MAPPING` değerini farklı ayarlamak, normal derlemeler için bile bu karma değerleri geçersiz kılar. Geliştiriciler ve CI işleri arasında ikili önbellekleri ve seçici test sonuçlarını paylaşmaları gerekiyorsa değeri tutarlı tutun.

### Oluşturulan projelerde hata ayıklama {#debugging-generated-projects}

Geri yüklenen yerel modüller, bağlantılı hata ayıklama bilgilerinin yanı sıra derleme önbelleğine erişim gerektirir. Tuist, Debug ve Release modüllerini dSYM'ler ve dilim başına kaynak kimliği meta verileriyle ısıtır, ardından bir hedefi değiştirmeden önce meta verileri tüketicinin bildirilen kaynaklarına karşı doğrular. Eksik veya uyumsuz meta veriler, o hedefin kaynaklarını korur. Betik tarafından oluşturulan `.generated(...)` kaynakları, doğrulanabilir içerik sağlama toplamları yerine bildirim parmak izlerine sahiptir, bu nedenle bu hedefler kaynak tabanlı kalır ve yerel modül önbelleğine yayınlanmaz. Gerçek içerik sağlama toplamlarına sahip oluşturulmuş kaynak erişimcileri uygun olmaya devam eder. Desteklenmeyen hata ayıklama bilgileri, ilişkisi olmayan ürünleri engellemeden etkilenen hedefin yayınlanmasını atlar; kaynak mutasyonu ve iptal işlemi yine de ısıtmayı başarısız kılar. Önbellek formatı değişir, bu nedenle daha eski sürümler tarafından ısıtılan yapıtların yeniden ısıtılması gerekir.

Doğrulanmış değiştirmeler için Tuist, tüketiciye ait dSYM UUID plist'lerinde kaynak yeniden konumlandırmaları hazırlar ve statik önbelleğe alınmış kod için yalnızca hata ayıklamaya yönelik eşlikçileri bağlar. Önbelleğe alınmış ikili dosyaları yeniden yazmaz veya LLDB'nin kalıcı genel kaynak haritasına üretici kaynak yollarını yüklemez. Açık hata ayıklayıcı başlatıcıları ve modül yükleyici ayarları yetkili olmaya devam eder. CI'da (`CI` veya `JENKINS_URL` ayarlandığında), bunu yapan şema ön eylemi değişiklik yapmadan çıkar, çünkü orada testlere hiçbir hata ayıklayıcı bağlanmaz. Hata ayıklama sembolleri ve kaynak yeniden konumlandırma, kaynak bağımlı çalışma zamanı dosya erişimini veya yerel Xcode kapsam raporlarını onarmaz; kapsam varyantı seçimi ve LLVM dışa aktarma ayrı özellikler olarak kalır.

`enableCaching: true` ile Tuist, Çalıştır ve Test eylemleri için LLDB kaynak haritalarını yapılandırır. Bir eylem özel bir LLDB başlatıcısına sahip olduğunda, Tuist önce çözümlenmiş kaynak haritasını yazar, ardından haritayı genişletebilmesi veya üzerine yazabilmesi için özel başlatıcıyı yükler. Aksi takdirde, kaynak haritasını değiştirmeden önce dosya varsa `~/.lldbinit-Xcode` dosyasını yükler, yoksa `~/.lldbinit` dosyasına geri döner. Yalnızca bir ana dizin dosyası yükleyerek, çift yükleme yapmadan kullanıcı başına hata ayıklayıcı kurulumunu geri yükler. Değiştirme işlemi önceki çalıştırmalardan kalan eski eşlemeleri kaldırır ve ana dizin dosyası kaynak haritalarına göre önceliklidir; kalması gereken kaynak haritası girişlerini eylemin özel başlatıcısına ekleyin. Diğer ana dizin ayarları korunur. Tuist'in önbelleğe özgü modül arama yolları, yükleyici ayarları ve Clang bayrakları sonrasında uygulanır ve bu ayarlar için kullanıcı değerlerine göre önceliklidir. Ana dizin dosyası hataları, sonraki komutların yüklenmesini engellemeden görünür kalır ve komutlar yansıtılmaz. Bu başlatıcı koruma, Tuist modül önbelleğinden geri yüklenen ikili dosyalar için hata ayıklamayı yapılandırdığında da geçerlidir; hatta `enableCaching` olmadan ve daha eski Xcode sürümlerinde bile.

Xcode 27 ve sonraki sürümlerde, oluşturulan projeler bir proje bunları ayarlamadığı sürece Xcode'un proje başına ön ek eşlemelerini (`SWIFT_ENABLE_PROJECT_PREFIX_MAPPING` ve `CLANG_ENABLE_PROJECT_PREFIX_MAPPING`) kapalı tutar. `/^src` gibi ön ekleri, her projede farklı bir dizini adlandırır ve LLDB bunları yalnızca hata ayıklanan hedefin projesine göre çözümler. Kaynaklar bunun yerine çalışma alanı genelindeki ön ekler altında kaydedilir: Tuist kök dizini için `/^root`, Swift paket geçici dizini için `/^spm` ve derleme çıktıları için `/^intermediates` ve `/^products`. Her biri her projede aynı dizini adlandırdığından, kesme noktaları çalışma alanındaki herhangi bir projedeki kaynaklarda çözümlenir.

Tuist kökü dışındaki yollar eşlenmez. Kök dışındaki bir projenin önbellek anahtarları, projenin nereye çekildiğine bağlıdır, bu nedenle diğer çekimler ve makineler onun önbelleğini ıskalar. Anahtarlarını çekim konumundan bağımsız hale getirmek için, o projenin manifestosunda proje başına eşlemeleri açın:

```swift
let checkoutIndependentSettings = Settings.settings(base: [
    "SWIFT_ENABLE_PROJECT_PREFIX_MAPPING": "YES",
    "CLANG_ENABLE_PROJECT_PREFIX_MAPPING": "YES",
])
```

Bu ayarları ilgili `Project` öğesine iletin. Başka bir projeden bir hedefte hata ayıkladığınızda, LLDB o projenin kaynaklarını bulamaz. Manifesto proje tabanlı ayarları, proje düzeyindeki xcconfig değerlerine göre önceliklidir, bu nedenle bunları manifesto içinde ayarlayın.

Bu ayarları değiştirmek derleme önbelleği anahtarlarını, ikili önbellek karmalarını ve seçici test karmalarını değiştirir, bu nedenle bu önbelleklerin yeniden ısıtılması gerekir. Seçiminizi ekibiniz arasında tutarlı tutun.

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

Yaygın bir desen, yerel ortamları salt okunur tutarken, yapıların tekrarlanabilir olduğu CI'dan yalnızca yapıtları itmekdir. Bunu, çoğu CI sağlayıcısı tarafından ayarlanan `CI` ortam değişkenini kontrol eden `Environment.isCI` kullanarak başarabilirsiniz:

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

Bu kurulumla, yerel yapılar yükleme yapmadan önbelleğe alınmış yapıtlardan yararlanır, CI yapıları ise ekibin geri kalanı için önbelleği doldurur.

Yükleme politikası, `tuist setup cache` komutunu çalıştıran makinede proje başına kaydedilir. Değiştirmek için `upload` seçeneğini güncelleyin ve `tuist setup cache` komutunu tekrar çalıştırın; Tuist projenizi oluşturuyorsa `tuist generate` komutunu da çalıştırın. Bundan sonraki yüklemeler, o makinedeki önbelleği yeniden başlatmadan yeni politikayı izler. Aynı makinede aynı anda çalışan aynı proje için işler politikasını paylaşır, bu nedenle en son `tuist setup cache` hepsi için bunu belirler.

### Depolama boyutu limiti {#store-size-limit}

Bir derleme önbelleği deposu her derleme ile büyür. Projenin depolarını sınırlamak için `Tuist.swift` dosyanızda `storeSizeLimit` ayarını yapın:

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

Tuist, önbellek vekil sunucusu başladığında, herhangi bir derleme onları kullanmadan önce ve hiçbir derleme çalışmıyorken her 10 dakikada bir projenin her deposunu kontrol eder. `tuist setup cache`, vekil sunucu çalışmıyorken onu başlatır, bu nedenle derlemelerinden önce `tuist setup cache` ve sonrasında `tuist teardown cache` çalıştıran bir CI işi, uzun ömürlü bir çalıştırıcının depolarını her işin başında sınırlar. Daha yeni derlemeler limitin yaklaşık yarısını yazdığında, bir deponun en eski önbelleğe alınmış çıktılarını siler, böylece depo yaklaşık limite yerleşir. Derlemeler çalışırken bir depo limitten büyük olabilir ve limiti ayarladığınızda zaten daha büyük olan bir depo, yeni derlemeler bu kadar yazdıktan sonra küçülür. Varsayılan konumunda olduğu gibi birkaç proje aynı depoyu kullandığında, en küçük limit uygulanır. Limit, `tuist setup cache` çalıştırdığınız her makinede geçerlidir, bu nedenle limiti değiştirdikten sonra tekrar çalıştırın. Zaten çalışan bir önbellek vekil sunucusu çalışmaya devam eder ve yeni limiti sonraki kontrolünde uygular.

### Modül önbelleği karmaları {#module-cache-hashes}

Derleme önbelleği ayarları <.localized_link href="/guides/features/projects/hashing">modül önbelleği karmalarının</.localized_link> bir parçası değildir. Tuist, her `COMPILATION_CACHE_*` derleme ayarını ve değeriyle birlikte her `-cas-plugin-option` bayrağını karma dışında bırakır. `enableCaching` seçeneğini açıp kapatmak veya yükleme politikasını değiştirmek, hedeflerinizin karmalarını korur, bu nedenle zaten ısıttığınız <.localized_link href="/guides/features/cache/module-cache">modül önbelleği</.localized_link> ikili dosyaları geçerli kalır. Xcode önbelleği olan ve olmayan derlemeleri aynı modül önbelleğine karşı karşılaştırabilirsiniz.

> [!NOTE]
> **Ön ek eşleme ayarları karmalanır**
>
> Xcode 27 ve sonraki sürümlerde, `enableCaching: true` ayrıca `SWIFT_ENABLE_PREFIX_MAPPING`, `SWIFT_ENABLE_PROJECT_PREFIX_MAPPING`, `CLANG_ENABLE_PREFIX_MAPPING`, `CLANG_ENABLE_PROJECT_PREFIX_MAPPING` ve `TUIST_PREFIX_MAPPING_FOR_COVERAGE_*` ayarlarını da ayarlar. Bu ayarlar modül önbelleği karmalarının bir parçasıdır, bu nedenle Xcode 27 ve sonraki sürümlerde `enableCaching` seçeneğini açıp kapatmak hedeflerinizin karmalarını değiştirir.

### Büyük çıktıların parçalarını yeniden kullanma {#reusing-parts-of-large-outputs}

Sunucu desteklediğinde, Xcode önbelleği büyük çıktıları parçalar halinde aktarır ve yalnızca önceki bir sürümden bu yana değişen parçaları gönderir veya getirir. Parçalar, `DerivedData` ayrı küçük bir yerel önbellekte tutulur, bu nedenle derleme önbelleğini temizleseniz bile korunurlar. Küçük çıktılar, daha eski sunucular ve daha eski istemciler normal tüm çıktı aktarımlarını kullanır.

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

Jeton tabanlı kimlik doğrulama ve Xcode Cloud, CircleCI, Bitrise ve Codemagic gibi diğer CI platformlarını içeren daha fazla örnek için <.localized_link href="/guides/integrations/continuous-integration">Sürekli Entegrasyon kılavuzuna</.localized_link> bakın.

### CI üzerinde derleme önbelleği deposu {#compilation-cache-store-on-ci}

Derleme önbelleği deposu, Xcode'un derleme çıktılarını sakladığı yerel dizindir. `COMPILATION_CACHE_CAS_PATH` derleme ayarı konumunu belirler; varsayılan olarak `DerivedData` içindeki `CompilationCache.noindex` dizinidir.

#### Durum bilgisi içeren depo {#stateful-store}

Derlemeler arasında bir depoyu korumak için, `COMPILATION_CACHE_CAS_PATH` (ve `tuist cache` için `TUIST_COMPILATION_CACHE_CAS_PATH`) ayarını kalıcı bir yola yönlendirin ve boyutunu bir [depo boyutu sınırı](#store-size-limit) ile sınırlayın.

## Sorun giderme {#troubleshooting}

### Derlemeler, Xcode önbellek vekil sunucusunun başarısız olduğunu bildirir {#cas-proxy-failed}

Bir derleme, hangi derlemenin önce hatayla karşılaştığına bağlı olarak Xcode tarafından `CAS error:` veya `CAS operation failed:` ön ekiyle gösterilen aşağıdaki gibi bir uyarı gösteriyorsa:

```
warning: CAS error: The Tuist Xcode cache proxy at /Users/you/.local/state/tuist/cas-proxy.sock failed (proxy connect: No such file or directory (os error 2)). Compilations that needed it used the local cache only, without remote cache hits. Their uploads are kept on disk and sent once the proxy is reachable again. Run `tuist setup cache` if the proxy is not running.
```

derleme önbelleği, `tuist setup cache` tarafından kurulan yerel önbellek vekil sunucusuna ulaşamamış demektir. Derleme yine de başarılı olur, ancak etkilenen derlemeler uzak önbellek isabeti almaz, bu nedenle boş bir önbellekle çalışan bir derleme gibi çalışır. Yüklemeleri diskte tutulur ve vekil sunucu tekrar istekleri işlemeye başladığında gönderilir: zamanında geri gelirse aynı derleme sırasında, aksi takdirde aynı makinedeki sonraki derleme sırasında. İş sonrası atılan bir CI makinesi bunları kaybeder. Uyarı, her derlemede bir kez, Xcode'un Sorun gezgininde ve `xcodebuild` çıktısında görünür.

Vekil sunucunun çalışıp çalışmadığını kontrol etmek için, uyarıda adı geçen soketi dinleyen bir işlem olup olmadığına bakın:

```bash
lsof ~/.local/state/tuist/cas-proxy.sock
```

Komut hiçbir şey yazdırmazsa, vekil sunucuyu yeniden başlatmak için `tuist setup cache` komutunu çalıştırın. CI üzerinde, her işte herhangi bir `xcodebuild` çağrısından önce `tuist setup cache` komutunu çalıştırın.

### Derlemeler son derece yavaşlıyor ve `CAS error: deadlineExceeded` uyarıları veriyor {#cas-deadline-exceeded}

Derlemeleriniz beklenenden çok daha uzun sürüyorsa ve Xcode derleme günlüğü şu şekildeki uyarılarla doluyssa:

```
Warning: CAS error: deadlineExceeded(connectionError: Optional(connect(descriptor:addr:size:): No such file or directory (errno: 2)))
note: cache key query failed
```

veya:

```
Warning: CAS error: deadlineExceeded(connectionError: Optional(connect(descriptor:addr:size:): Connection refused (errno: 61)))
```

`COMPILATION_CACHE_REMOTE_SERVICE_PATH` ayarı, genellikle Tuist'in önceki sürümlerinin yapılandırdığı proje başına soket (`~/.local/state/tuist/<org>_<project>.sock`) olan, hiçbir şeyin dinlemediği bir soketi işaret ediyor demektir. Tuist artık bu sokete hizmet vermiyor. Xcode, hızlıca hata vermek yerine her derleme önbelleği isteğinde bağlantıyı yeniden dener; bu da bir derlemenin bir saat veya daha fazla sürmesine neden olabilir ve Tuist bu davranışı değiştiremez.

Düzeltmek için:

- **Oluşturulan projeler**: `tuist generate` komutunu tekrar çalıştırın.
- **Diğer projeler**: `COMPILATION_CACHE_*` derleme ayarlarını, [Xcode Derleme Ayarlarını Yapılandırma](#configure-xcode-build-settings) bölümünde açıklandığı gibi `tuist setup cache` tarafından yazdırılanlarla değiştirin.

Xcode önbelleğini kullanmıyorsanız, bunun yerine `COMPILATION_CACHE_*` derleme ayarlarını kaldırın ve `tuist teardown cache` komutunu çalıştırın.

### `uploaded CAS output`, yüklemeler devre dışı bırakılmış olsa bile yerel olarak görünür {#uploaded-cas-output-with-upload-disabled}

`xcodeCache: .xcodeCache(upload: false)` (veya CI olmayan bir makinede `upload: Environment.isCI`) ayarlandığında, derleme günlüğünde hala `note: uploaded CAS output ...` görebilirsiniz. `xcodebuild` bu çağrıları atlamanın bir yoluna sahip değildir, bu nedenle Tuist bunları yine de alır ancak Tuist sunucusuna hiçbir şey yayınlamaz. Kontrol paneli metrikleri bunu hesaba katar, bu nedenle sahte yükleme trafiği raporlanmaz.

## İlgili {#related}

Mühendislik ekiplerinin ve kodlama ajanlarının derleme yapıtlarını nasıl yeniden kullandığını görmek için [Tuist'in paylaşılan önbelleğini](https://tuist.dev/cache) keşfedin.
