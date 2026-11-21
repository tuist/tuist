---
{
  "title": "Modül önbelleği",
  "titleTemplate": ":title · Önbellek · Özellikler · Kılavuzlar · Tuist",
  "description": "Derlenmiş ikili dosyaları önbelleğe alın ve Tuist Modül Önbelleği ile ekibiniz arasında paylaşın."
}
---

# Modül önbelleği {#module-cache}

> [!IMPORTANT]
> **Gereksinimler**
>
> - Bir <.localized_link href="/guides/features/projects">oluşturulmuş proje</.localized_link>. Modül önbelleği, hedefleri hashlemek ve ikili dosyalarıyla değiştirmek için Tuist’in `Project.swift` arkasında tuttuğu proje grafiğini okur.

Tuist Modül Önbelleği, modüllerinizi ikili dosyalar (`.xcframework`) olarak önbelleğe alıp farklı ortamlarda paylaşarak derleme sürelerini optimize etmenin güçlü bir yolunu sunar. Bu yetenek, daha önce oluşturulmuş ikili dosyalardan yararlanmanızı sağlayarak tekrarlanan derleme ihtiyacını azaltır ve geliştirme sürecini hızlandırır. Önbelleğin yavaş bir derlemenin hangi bölümünü ortadan kaldırdığını öğrenmek için bkz. [Yavaş derlemeler](https://tuist.dev/solutions/slow-builds).

> [!TIP]
> **Xcode önbelleği ile birleştirin**
>
> Modül önbelleği ve <.localized_link href="/guides/features/cache/xcode-cache">Xcode önbelleği</.localized_link>, farklı granülerite seviyelerinde çalıştıkları için birbirini tamamlar. Modül önbelleği, derleme çalışmadan önce tüm modülleri önceden oluşturulmuş `.xcframework` dosyalarıyla değiştirirken, Xcode önbelleği derleme sırasında derleme çıktılarını yeniden kullanır.
>
> Derleme önbelleği ayarları modül önbelleği hashlerinin bir parçası değildir, bu nedenle Xcode önbelleğini açıp kapatmak zaten ısıttığınız ikili dosyaları korur. Xcode 27 ve sonrasında, bununla birlikte gelen ön ek eşleme ayarları hashlenir. Bkz. <.localized_link href="/guides/features/cache/xcode-cache#module-cache-hashes">modül önbelleği hashleri</.localized_link>.

## Isıtma {#warming}

Tuist, bağımlılık grafiğindeki her hedef için değişiklikleri algılamak amacıyla <.localized_link href="/guides/features/projects/hashing">hashleri verimli şekilde kullanır</.localized_link>. Bu verileri kullanarak, bu hedeflerden türetilen ikili dosyaları oluşturur ve benzersiz tanımlayıcılar atar. Grafik oluşturma sırasında Tuist, orijinal hedefleri karşılık gelen ikili sürümleriyle sorunsuz bir şekilde değiştirir.

*"Isıtma"* olarak bilinen bu işlem, yerel kullanım veya Tuist aracılığıyla ekip arkadaşlarınız ve CI ortamlarıyla paylaşım için ikili dosyalar üretir. Önbelleği ısıtma süreci basittir ve tek bir komutla başlatılabilir:

```bash
tuist cache
```

Komut, süreci hızlandırmak için ikili dosyaları yeniden kullanır.

Bir ikili dosyanın yüklenmesi başarısız olursa, komut geri kalanlarını yine de yükler, ardından sıfır dışı bir durum koduyla çıkar ve yüklenmemiş hedefleri listeler. Bir makinenin yerel önbelleğindeki ikili dosyalar önbelleğe alınmış sayılır, bu nedenle bunları aynı makineden tekrar yüklemek için ısıtmadan önce `tuist clean binaries` komutunu çalıştırın. İkili dosyaları yalnızca yerel önbellekte depolamak için `--no-upload` seçeneğini kullanın.

### Hedef seçimi {#destination-selection}

Tek bir hedef için önbelleğe almak, oluşturmak ve test etmek üzere `--destination simulator` veya `--destination device` kullanın:

```bash
tuist cache --destination simulator
tuist generate --destination simulator
tuist test --destination simulator

tuist cache --destination device
tuist generate --destination device
tuist test --destination device -- -destination 'platform=iOS,id=DEVICE_IDENTIFIER'
```

Varsayılan değer `all` olup, Mac Catalyst dahil olmak üzere hedeflerinizin desteklediği tüm hedefleri korur. Daha sonra çalıştırılan bir `tuist cache`, önbelleğe alınmış dilimleri yeniden kullanır ve yalnızca eksik SDK’ları derler. Normal oluşturma, gerekli herhangi bir dilim eksikse modülün kaynaklarını korur.

Kısıtlı oluşturma, kaynak hedefleri seçilen hedefle sınırlar ve makrolar dahil olmak üzere yerel macOS hedeflerini korur. Kısıtlı modların hiçbiri Mac Catalyst’i içermez. Tüm hedefleri geri yüklemek için `--destination all` ile yeniden oluşturun.

`tuist test --destination`, yalnızca seçilen hedefin dilimlerini kullanır ve indirir; bu nedenle simülatör test çalıştırması, yalnızca simülatöre yönelik veya tam bir ısıtmadan gelen ikili dosyaları kullanabilir. `--` sonrasında `xcodebuild` öğesine geçirilen hedef eşleşmediğinde başarısız olur ve `--destination device` bir cihaz `-destination` gerektirir. Seçici test hashleri hedefe bağlı değildir, bu nedenle farklı `--destination` değerlerine sahip çalıştırmalar test sonuçlarını paylaşır.

Dilim bazlı önbellekleme, standart mimarilere sahip iOS ve macOS’u destekler. Diğer platformlar, özel mimariler ve desteklenmeyen ürünler tam artefact önbelleklemeyi korur. Eski modül önbellekleme her zaman tam artefact’leri indirir ve ısıtma sırasında `--destination all` gerektirir.

### Uzak yükleme kabulü {#remote-upload-admission}

Modern modül önbellekleme REAPI kullanır. Yoğun bir önbellek, bir yüklemeyi `RESOURCE_EXHAUSTED` ile geçici olarak reddettiğinde Tuist, jitter ile geri çekilir, standart `google.rpc.RetryInfo` minimum gecikmelerine uyar ve sınırlı bir bekleme bütçesi içinde yeniden dener. Yükleme kabulü, çağrı başına en fazla altı yeniden denemeye izin verir. Her blob yükleme işlemi, varlık kontrolleri, toplu yüklemeler ve akış yazmaları arasında tek bir 60 saniyelik kümülatif geri çekilme bütçesini paylaşır; eşzamanlı beklemeler bütçeyi tüketir, bu nedenle tekrarlanan reddetmeler kuyruktaki her bloğa başka bir dakika yeniden deneme hakkı vermez. Başarılı aktarımlar bu bütçeyi tüketmez ve bütçe tükendiğinde iptal edilmez. Eylem sonucu yayınlamanın kendi sınırlı bütçesi vardır. Üstel gecikme bir saniyede başlar ve orantılı jitter’dan önce 30 saniyeye doğru artar. Bir sunucunun gereken gecikmesi kalan bütçeyi aşarsa, Tuist talimat verilenden daha erken yeniden denemek yerine başarısız olur. İptal etme işlemi geri çekilmeyi keser ve önbellek okumaları kısa yeniden denemeleri korur, böylece aşırı yüklenme oluşturmaya engel olmaz.

Bu varsayılanlar, yeniden deneme ipuçları olmayan eski Kura sürümlerine de yardımcı olur. Daha uzun yeniden denemeler geçici çekişmeyi emer, sürekli aşırı yüklenmeyi değil: reddetmeler devam ederse ısıtma işlerinde [önbellek eşzamanlılık sınırını](#cache-concurrency-limit) düşürün veya sunucu kapasitesini artırın. Pod belleği tahminleri ve kabul metrikleri için bkz. [Kura yükleme boyutlandırma](https://github.com/tuist/tuist/blob/main/kura/README.md#upload-admission-and-sizing).

### Yapılandırma seçimi {#configuration-selection}

Önbelleği ısıtırken `--configuration` parametresini geçmeden, Tuist kullanılacak derleme yapılandırmasını aşağıdaki sırayla seçer:

1. Manifest dosyanızdaki `Project.Options.generationOptions` içinde ayarlanmış [`defaultConfiguration`](https://projectdescription.tuist.dev/documentation/projectdescription/tuist/generationoptions/defaultconfiguration) (varsa).
2. Aksi takdirde, adı alfabetik olarak sıralanan `debug` varyantının ilk derleme yapılandırması.

Belirli bir yapılandırma için önbelleği ısıtmak amacıyla bunu açıkça belirtin:

```bash
tuist cache --configuration Release
```

## Kullanım {#usage}

Varsayılan olarak, Tuist komutları proje oluşturmayı gerektirdiğinde, bağımlılıkları varsa önbellekten alınan ikili eşdeğerleriyle otomatik olarak değiştirir. Ayrıca, odaklanılacak hedeflerin bir listesini belirtirseniz, Tuist bağımlı hedefleri de varsa önbelleğe alınmış ikili dosyalarıyla değiştirir. Farklı bir yaklaşımı tercih edenler için, belirli bir bayrak kullanarak bu davranışı tamamen devre dışı bırakma seçeneği vardır:

::: code-group
```bash [Project generation]
tuist generate # Only dependencies
tuist generate Search # Dependencies + Search dependencies
tuist generate Search Settings # Dependencies, and Search and Settings dependencies
tuist generate --cache-profile none # No cache at all
```

```bash [Testing]
tuist test
```
<!-- -->
:::

> [!WARNING]
> İkili önbellekleme, uygulamayı simülatörde veya cihazda çalıştırmak ya da testleri yürütmek gibi geliştirme iş akışları için tasarlanmış bir özelliktir. Sürüm derlemeleri için intended değildir. Uygulamayı arşivlerken, `--cache-profile none` kullanarak kaynaklarla birlikte bir proje oluşturun.

## Önbellek profilleri {#cache-profiles}

Tuist, projeler oluşturulurken hedeflerin önbelleğe alınmış ikili dosyalarla ne kadar agresif bir şekilde değiştirileceğini kontrol etmek için önbellek profillerini destekler.

- Yerleşikler:
  - `only-external`: yalnızca harici bağımlılıkları değiştir (sistem varsayılanı)
  - `all-possible`: mümkün olduğunca çok hedefi değiştir (dahili hedefler dahil)
  - `none`: önbelleğe alınmış ikili dosyalarla asla değiştirme

`tuist generate` üzerinde `--cache-profile` ile bir profil seçin:

```bash
# Built-in profiles
tuist generate --cache-profile all-possible

# Custom profiles (defined in Tuist Config)
tuist generate --cache-profile development

# Use config default (no flag)
tuist generate

# Focus on specific targets (implies all-possible)
tuist generate MyModule AnotherTarget

# Disable binary replacement entirely
tuist generate --cache-profile none
```

> [!NOTE]
> **Kullanımdan kaldırılmış bayrak**
>
> `--no-binary-cache` bayrağı kullanımdan kaldırıldı. Bunun yerine `--cache-profile none` kullanın. Kullanımdan kaldırılmış bayrak, geriye dönük uyumluluk için hala çalışır.

Etkili davranış çözümlenirken öncelik (yüksekten düşüğe):

1. `--cache-profile none`
2. Hedef odağı (`generate` komutuna hedefleri geçirme) → `all-possible` profili
3. `--cache-profile <value>`
4. Yapılandırma varsayılanı (ayarlanmışsa)
5. Sistem varsayılanı (`only-external`)

## Desteklenen ürünler {#supported-products}

Yalnızca aşağıdaki hedef ürünler Tuist tarafından önbelleklenebilir:

- Çatılar (statik ve dinamik), [XCTest](https://developer.apple.com/documentation/xctest) veya Swift Testing'e bağımlı test destek çatıları dahil
- Kütüphaneler (statik ve dinamik), XCTest veya Swift Testing'e bağımlı test destek kütüphaneleri dahil
- Paketler
- Swift Makroları

Test paketleri modül önbelleğinin dışında tutulur. Bu, `unitTests` ve `uiTests` hedeflerinin ikili dosya olarak önbelleğe alınmadığı anlamına gelir; ancak testlerin bağımlı olduğu normal çatı ve kütüphane hedefleri, XCTest veya Swift Testing ile bağlantı kurduklarında bile önbelleğe alınabilir.

Önbelleğe alınmış kütüphane `.xcframework` dosyaları, oluşturulan projelerin bunları içe aktarmak için ihtiyaç duyduğu meta verileri korur; kaynak hedef genel başlıklar tanımladığında Swift modülleri ve genel C/Objective-C başlıkları da buna dahildir.

> [!NOTE]
> **Yukarı akış bağımlılıkları**
>
> Bir hedef önbellenemez olduğunda, yukarı akış hedefleri de önbellenemez hale gelir. Örneğin, A'nın B'ye bağımlı olduğu `A > B` bağımlılık grafiğiniz varsa ve B önbellenemezse, A da önbellenemez olacaktır.

## Analitik {#analytics}

Sık önbellek isabetsizliği yaşayan modülleri bulmak için projenizin kontrol panelinde **Modül Önbelleği → Modüller** bölümünü açın. İyileştirmek istediğiniz ortamı (örneğin **CI**) ve bir tarih aralığını seçin. Genel bakış, önbellek isabetlerini, isabetsizlikleri ve isabetsizliği olan modülleri gösterir; bir modülü açtığınızda geçmişini ve her gözleme atanan nedeni görürsünüz.

**Isabetsizlikler** açılır menüsü, tek bir neden için bir sayı ve açıklama seçer. Grafik, dört nedenin dağılımını gösterir. Bir modülün sayfasında, tekil olayları incelemek için geçmişteki **Neden** filtresini kullanın. Tanımını görmek için bir neden etiketinin üzerine gelin veya klavyeyle odaklanın.

### Isabetsizlik nedenleri {#miss-reasons}

| Neden | Anlamı |
| --- | --- |
| **Değişti** | Modülün kendi karşılaştırılan girdileri değişti. Bunlar dosya karma değerlerini, derleme ayarlarını, çözümlenen yapılandırmayı ve derleyici tanımlayıcısını içerir. Kaynak düzenlemesi yalnızca olası nedenlerden biridir. |
| **Yukarı akış** | Modülün kendi karşılaştırılan girdileri aynı kaldı, ancak bağımlılığının veya harici paketinin karma değeri değişti. Modülün kaynak dosyaları dokunulmamış olabilir. |
| **Soğuk** | Karşılaştırılacak önceki bir modül gözlemi yok veya bildirilen girdiler isabetsizliği açıklamıyor ve önceki uzaktan erişilebilirliğe dair yeterli kanıt bulunmuyor. Soğuk olması, modülün hiç önbelleğe alınmadığını kanıtlamaz. |
| **Tahliye edildi** | Tam önbellek anahtarı daha önce aynı projede, aynı kaydedilmiş önbellek uç noktasında uzaktan bir isabet almıştı, ancak şimdi isabetsizlik yaşıyor. |

**Tahliye edildi** olarak etiketlenen isabetsizliklerde, yapıt daha önce uzak önbellekten indirilmişti ancak bu sefer yeniden kullanılamadı. Muhtemel neden tahliyedir, ancak erişim veya indirme hataları da isabetsizliği açıklayabilir. Tuist bu etiketi yalnızca önceki bir uzak isabet bulduğunda atar; önceki isabetsizlikler ve yerel isabetler yeterli değildir.

Örneğin:

| Senaryo | Sınıflandırma |
| --- | --- |
| Bir modül, önceki gözlem veya nitelikli uzak isabet olmaksızın isabetsizlik yaşıyor | Soğuk |
| A değişiyor; B, A'ya bağımlı ve C, B'ye bağımlı; üç anahtar da değişiyor | A Değişti; B ve C Yukarı akış |
| Derleyici sürümü, kaynaklar ve ayarlar değişmeden ısınma sonrası değişir | Etkilenen isabetsizlikler, her iki gözlem de derleyici girdilerini bildirdiğinde Değişti olarak sınıflandırılır |
| Tam bir anahtar uzaktan indirildi, ardından yapıtı tahliye edildikten sonra isabetsizlik yaşandı | Önceki isabet kanıt olarak nitelendiğinde Tahliye edildi |
| Bir anahtar tekrar tekrar isabetsizlik yaşıyor ve hiçbir zaman başarıyla ısıtılmadı | Soğuk kalabilir |

Nedenler gözlemleri tanımlar; bunlar bir anahtara bağlı kalıcı etiketler değildir. Örneğin, bir derleyici yükseltmesinden sonraki ilk isabetsizlik Değişti olabilir, ancak bu yeni anahtar için sonraki bir isabetsizlik, uzaktan erişilebilir olarak hiç gözlemlenmediyse Soğuk olabilir.

### Önbellek isabet oranını iyileştirme {#improving-cache-hit-rate}

1. **Tutarlı bir temel seçin.** CI ve temsilci bir tarih aralığı ile başlayın. Modülleri isabetsizliklere göre sıralayın, ardından isabet oranlarını, bağımlıları ve derleme maliyetlerini değerlendirin. Sıkça isabetsizlik yaşayan, maliyetli bir bağımlılığı düzeltmek, küçük bir modülün isabet oranını iyileştirmekten daha fazla zaman kazandırabilir. Bir değişiklik yaptıktan sonra aynı ortamı ve benzer iş yüklerini karşılaştırın.
2. **Değişti isabetsizliklerini inceleyin.** İlgili çalıştırmaları açın ve tam anahtarlarını ile bildirilen girdilerini karşılaştırın. Isıtma ve tüketen işleri hedeflenen Xcode/derleyici sürümü, yapılandırma ve hedef destinasyonları üzerinde hizalayın. Kasıtlı değişikliklerden sonra yeniden ısıtın. Kararsız oluşturulan dosyalar veya ortama bağımlı ayarlar aksi takdirde kararlı olan modülleri geçersiz kılıyorsa, bu girdileri inceleyin. İkili uyumluluğu etkileyen girdileri karma değerinde tutun.
3. **Yukarı akış isabetsizliklerini değişen bağımlılığa kadar takip edin.** Doğrudan değişikliği bulmak için geçmişini inceleyin. Ortaya çıkan anahtarları ısıtmak yeniden kullanımı restore edebilir. Sık sık değişen bir uygulama birçok maliyetli bağımlıyı geçersiz kılıyorsa, [Verimlilik](#efficiency) bölümünde açıklandığı gibi daha küçük modüller veya kararlı arayüzler düşünün.
4. **Soğuk isabetsizlikler için ısıtma kapsamını kontrol edin.** Isıtmanın gerekli modülleri seçtiğini, tüketen işin yapılandırmasını ve ortamını kullandığını ve yapıtları başarıyla yüklediğini doğrulayın. Gerçek CI işleri tarafından kullanılan tam anahtarları kontrol edin. Isıtma ve tüketim farklı anahtarlar istiyorsa, önbelleğin tahliye edildiğini varsaymadan önce karma girdilerini inceleyin. Modülün kaynakları değişmemiş olsa bile, önceki başarılı bir yükleme olmadan tekrarlanan isabetsizlikler mümkündür.
5. **Tahliye edildi isabetsizlikleri için kanıtları kullanın.** Tüketen çalıştırmanın anahtarını ve uç noktasını onaylayın, ardından tüketen çalıştırmanın önbellek uyarılarını ve ısıtma işinin yükleme sonucunu inceleyin. Uygun olduğunda saklama veya tahliyeyi kontrol edin. Gerekli yapıtları yeniden ısıtın ve sonraki bir isabeti doğrulayın. Hala isabetsizlik yaşıyorlarsa, ilgili çalıştırma bağlantılarını ve günlükleri destek ekibiyle paylaşın.

Karma karşılaştırması için, ısıtmak ve tüketmek niyetinde olduğunuz yapılandırmayı kullanarak bunu her ilgili ortamda çalıştırın:

```bash
tuist hash cache --configuration Debug --verbose
```

Modülün tam karma değerini ve bileşen bloğunu karşılaştırın. Komutu aynı değişmemiş makinede tekrarlamak normalde aynı sonucu vermelidir; bir uyumsuzluğu araştırmak için gerçek ısıtma ve tüketme ortamlarını karşılaştırın. Her iki komutun da önbelleğe isabet etmesi gerekmez. Daha fazla kontrol için <.localized_link href="/guides/features/projects/hashing#debugging">karma teşhislerine</.localized_link> bakın.

## Verimlilik {#efficiency}

İkili önbellekleme ile elde edilebilecek verimlilik düzeyi büyük ölçüde graf yapısına bağlıdır. En iyi sonuçları elde etmek için şunları öneririz:

1. Çok iç içe geçmiş bağımlılık grafiklerinden kaçının. Graf ne kadar sığ olursa, o kadar iyidir.
2. Bağımlılıkları uygulama hedefleri yerine protokol/arayüz hedefleriyle tanımlayın ve uygulamaları en üst düzey hedeflerden bağımlılık enjeksiyonu ile sağlayın.
3. Sık değiştirilen hedefleri, değişme olasılığı daha düşük olan daha küçük hedeflere bölün.

Yukarıdaki öneriler, projelerinizi yalnızca ikili önbelleklemeden değil, aynı zamanda Xcode'un yeteneklerinden de maksimum fayda sağlayacak şekilde yapılandırmanın bir yolu olarak önerdiğimiz <.localized_link href="/guides/features/projects/tma-architecture">Modüler Mimari</.localized_link>'nin bir parçasıdır.

## Önerilen kurulum {#recommended-setup}

Önbelleği ısıtmak için **ana dalda her commit'te çalışan** bir CI işine sahip olmanızı öneririz. Bu, önbelleğin her zaman `main` içindeki değişiklikler için ikilileri içerdiğini garanti eder, böylece yerel ve CI dalları bunlar üzerine artımlı olarak inşa edilir.

> [!TIP]
> **Önbellek ısıtmayı izole tutun**
>
> `tuist cache` komutunu, oluşturulan çalışma alanına bağımlı sonraki adımlar olmadan ayrı bir CI adımında çalıştırın. `tuist cache` önbellek oluşturma amacıyla çalışma alanını değiştirdiğinden, çalışma alanına ihtiyaç duyan herhangi bir CI adımı önce taze, kullanılabilir bir çalışma alanı almak için `tuist generate` çalıştırmalıdır.

> [!TIP]
> **Önbellek ısıtma ikilileri kullanır**
>
> `tuist cache` komutu ayrıca ısıtmayı hızlandırmak için ikili önbelleği kullanır.

Aşağıda yaygın iş akışlarına bazı örnekler verilmiştir:

### Bir geliştirici yeni bir özellik üzerinde çalışmaya başlar {#a-developer-starts-to-work-on-a-new-feature}

1. `main` üzerinden yeni bir dal oluştururlar.
2. `tuist generate` çalıştırırlar.
3. Tuist, `main` üzerindeki en son ikilileri çeker ve projeyi bunlarla oluşturur.

### Bir geliştirici değişiklikleri yukarı akışa iter {#a-developer-pushes-changes-upstream}

1. CI hattı projeyi derlemek veya test etmek için `xcodebuild build` veya `tuist test` çalıştıracaktır.
2. İş akışı, `main` üzerindeki en son ikilileri çeker ve projeyi bunlarla oluşturur.
3. Ardından projeyi artımlı olarak derler veya test eder.

## Yapılandırma {#configuration}

### Önbellek eşzamanlılık limiti {#cache-concurrency-limit}

Hem indirmeleri hem de yüklemeleri sınırlamak için `TUIST_CACHE_CONCURRENCY_LIMIT` değerini pozitif bir tamsayıya ayarlayın. Örneğin, ısıtma işlerinde küçük, kendi barındırılan bir önbellekteki yükü azaltın:

```bash
TUIST_CACHE_CONCURRENCY_LIMIT=2 tuist cache
```

Ayarlanmadığında, REAPI yüklemeleri sekiz aktarım görevi kullanır. İndirmeler, herhangi bir blob ByteStream gerektirdiğinde sekiz ve yalnızca toplu planlar için 32 kullanır. Eski HTTP önbellek yolu varsayılan olarak 100'dür; bu varsayılan REAPI için geçerli değildir. Geçersiz değerler, daha önce belgelenen `none` dahil, limitleri kaldırmak yerine varsayılanları korur. Varsayılanları geri yüklemek için `unset TUIST_CACHE_CONCURRENCY_LIMIT` kullanın.

Limitler her aktarım işlemi için geçerlidir, işlemler veya CI işleri genelinde değil. Limiti iki olan üç eşzamanlı ısıtma işlemi, aynı önbelleğe karşı altı aktif yüklemeye sahip olabilir. Tüketici işleri, varsayılan indirme paralelliğini korumak için değişkeni ayarlanmamış bırakabilir.

### Önbellek ısıtma geçici dizini {#cache-warm-scratch-directory}

Varsayılan olarak, `tuist cache` derleme ara dosyaları ve birleştirilmiş önbellek yapıtları için geçici bir geçici dizin oluşturur ve önbellek ısıtma tamamlandığında bunu kaldırır. Bu dosyaları yönettiğiniz bir dizin altında tutmak için `TUIST_CACHE_WARM_SCRATCH_DIRECTORY` değerini ayarlayın.

Yol mutlak veya geçerli çalışma dizinine göre göreceli olabilir. Tuist, dizin mevcut olmadığında onu oluşturur. Zaten mevcutsa, boş bir dizin olmalıdır.

Bu ortam değişkeni ayarlandığında, Tuist komut tamamlandıktan sonra dizini ve içeriğini yerinde bırakır. Arayan, sonraki önbellek ısıtmadan önce temizlemekle sorumludur. Değişken ayarlanmadığında, Tuist geçici bir dizin kullanmaya ve kaldırmaya devam eder.

Tuist, yabancı bir derleme hedefinin ısıtılması gerektiğinde arayan tarafından sahip olunan geçici dizini reddeder. Yabancı derleme betikleri kendi çıktı konumlarını kontrol eder, bu nedenle Tuist bu çıktıların geçici dizin içinde kalacağını garanti edemez.

### Kod kapsamı {#code-coverage}

Modül önbelleğinden gelen bir hedef önceden derlenmiş bir ikilidir ve bir test çalıştırması kodunu yalnızca o ikili kapsam sayaçlarıyla derlendiğinde ölçer. Bu bölüm önbelleğin kapsamı nasıl ele aldığını açıklar; ucuca kapsam kurulumu için bkz. <.localized_link href="/guides/features/test-code-coverage/generated-xcode-project">Kod Kapsamı</.localized_link>. Projeniz için kapsamı `Tuist.swift` içinde açın:

```swift
import ProjectDescription

let tuist = Tuist(
    project: .tuist(
        generationOptions: .options(
            coverage: .coverage(enabled: true)
        )
    )
)
```

`enabled` ile, her komut ve her ortam projenizin kendi hedefleri için önbelleğin enstrümanlı bir varyantını okur, böylece CI'daki tek bir ısıtma hem CI hem de yerel makineler için hizmet verir:

| Komut | Projenizin hedefleri | Harici paketler |
| --- | --- | --- |
| `tuist cache` (Debug yapılandırması) | Enstrümanlı ikilileri ısıtır | Düz ikilileri ısıtır |
| `tuist cache` (Release yapılandırması) | Düz ikilileri ısıtır | Düz ikilileri ısıtır |
| `tuist hash cache` | Enstrümanlı anahtarları yazdırır | Düz anahtarları yazdırır |
| `tuist generate` | Enstrümanlı ikilileri okur | Düz ikilileri okur |
| `tuist test` | Enstrümanlı ikilileri okur | Düz ikilileri okur |

Seçenek, Xcode'un Debug olarak kabul ettiği her yapılandırma için geçerlidir. Release derlemeleri asla enstrümanlanmaz. Tuist ayrıca bu yapılandırmalarda profil çalışma zamanını bağlar (`CLANG_COVERAGE_MAPPING_LINKER_ARGS`), böylece kapsam toplanmayan derlemeler yine de enstrümanlı ikilileri bağlar ve otomatik olarak oluşturduğu şemaların test eyleminde ve `coverage` ayarlanmamış bıraktığınız tanımladığınız şemaların test eyleminde kapsamı açar.

Tanımladığınız bir şema, kapsamı kendisi ayarlamadığı sürece seçeneği izler: `.options(coverage: false)` onu kapalı tutar ve `.options(coverage: true)` seçeneğin ne dediğine bakmaksızın açık tutar. Test planları kapsamı kendileri belirler ve `-enableCodeCoverage` Xcode'da olduğu gibi bir çalıştırmayı yine de geçersiz kılar. Enstrümanlı ikilileri okuyan ancak kapsam toplamayan bir çalıştırma normal şekilde derler ve test eder. Bir çalıştırma kapsam topladığında ancak projenizin hedefleri önbellekten düz ikililer olarak geldiğinde, Tuist kapsamlarının ölçülmediğine dair uyarı verir.

`TUIST_COVERAGE_ENABLED` ortam değişkeni (`1` veya `0`), `coverage: .coverage(enabled:)` üzerinde önceliklidir. Bunu tek bir komut için değil, tüm bir ortam için (örneğin bir CI iş akışı için) ayarlayın, böylece önbelleği ısıtan komutlar ile onu okuyan komutlar uyumlu olsun.

`prefixMapping` (bkz. <.localized_link href="/guides/features/cache/xcode-cache#coverage-with-prefix-mapping">Xcode önbelleği</.localized_link>) kendi geçersiz kılmasına sahiptir: `TUIST_COVERAGE_PREFIX_MAPPING` ortam değişkeni (`1` veya `0`), `coverage: .coverage(prefixMapping:)` üzerinde önceliklidir.

Kapalıya geçersiz kılmak düz varyantı okur; kapsam açıkken ısıtılan bir önbellek bunu doldurmaz, bu nedenle bu hedefler kaynaktan derlenir. Bir Release ısıtma her zaman düz ikilileri ısıtır.

> [!IMPORTANT] KEEP THE VALUES THE SAME EVERYWHERE
> `enabled` ve `prefixMapping`, projenizin hedeflerinin derleme ayarlarını ve önbellek anahtarlarını ve test hedeflerinin seçici test hash'lerini değiştirir. Önbelleği paylaşan her makinede bunları aynı değere ayarlayın ve ortamdan türetmeyin (örneğin `Environment.isCI` üzerinden): CI ve yerel makineler arasında farklılık gösteren bir değer onlara farklı anahtarlar verir. Aynı durum ortam değişkenleri için de geçerlidir: `TUIST_COVERAGE_ENABLED=0` ile yapılan bir çalıştırma, kapsamı açık olan çalıştırmaların ikililerini veya seçici test sonuçlarını yeniden kullanmaz.

Şunları göz önünde bulundurun:

- Enstrümanlı ikililer daha büyüktür: statik arşivler ve dinamik kütüphaneler için yaklaşık %20–30. Debug derlemeleri aynı hızda çalışır.
- Xcode'un kapsam raporu, bu seçenek açık veya kapalı olsun, önbellekten gelen kodu asla göstermez. Tuist'in kapsam yüklemesi bunu ölçer. Xcode'da bir hedefin kapsamını görmek için, kaynaktan derlenmesi amacıyla `tuist generate <target>` ile ona odaklanın.

## Sorun giderme {#troubleshooting}

### Hedeflerim için ikilileri kullanmıyor {#it-doesnt-use-binaries-for-my-targets}

Ortamlar ve çalıştırmalar arasında <.localized_link href="/guides/features/projects/hashing#debugging">hash'lerin deterministik</.localized_link> olduğundan emin olun. Bu, projenin ortama referansları varsa, örneğin mutlak yollar aracılığıyla, gerçekleşebilir. İki ardışık `tuist generate` çağrısı tarafından veya ortamlar ya da çalıştırmalar arasında oluşturulan projeleri karşılaştırmak için `diff` komutunu kullanabilirsiniz.

Ayrıca hedefin doğrudan veya dolaylı olarak bir <.localized_link href="/guides/features/cache/module-cache#supported-products">önbelleklenemez hedefe</.localized_link> bağımlı olmadığından emin olun.

### Eksik semboller {#missing-symbols}

Kaynaklar kullanılırken, Xcode'un derleme sistemi Derived Data aracılığıyla açıkça bildirilmeyen bağımlılıkları çözebilir. Ancak, ikili önbelleğe güvendiğinizde bağımlılıkların açıkça bildirilmesi gerekir; aksi takdirde semboller bulunamadığında derleme hataları görmeniz muhtemeldir. Bunu hata ayıklamak için, <.localized_link href="/guides/features/projects/inspect/implicit-dependencies">`tuist inspect dependencies --only implicit`</.localized_link> komutunu kullanmanızı ve örtük bağlantıda gerilemeleri önlemek için bunu CI'da kurmanızı öneririz.
