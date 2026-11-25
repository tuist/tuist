---
{
  "title": "Gradle Kod Kapsamı",
  "titleTemplate": ":title · Kod Kapsamı · Özellikler · Kılavuzlar · Tuist",
  "description": "Gradle projenizin JaCoCo ile ölçülen testlerinin kod kapsamını yükleyin ve dosya, proje ve commit bazında takip edin."
}
---
# Gradle kod kapsamı {#gradle-code-coverage}

Kod kapsamı, testlerinizin kodunuzun hangi satırlarını çalıştırdığını gösterir. Tuist Gradle eklentisi, test görevlerinizin kapsamını JaCoCo ile ölçer ve her test çalıştırmasında yükler; Tuist ise bir commit’in çalıştırmalarını proje, her Gradle projesi ve her dosya bazında tek bir değerde birleştirir. Kontrol panelinin **Kod Kapsamı** sayfası bunu commit başına ve her dal için trend olarak gösterir.

> [!IMPORTANT]
> **Gereksinimler**
>
> - `dev.tuist` Gradle eklentisinin uygulanmış olması; ayrıntılar için bkz. <.localized_link href="/guides/get-started/gradle-project">Gradle projesiyle başlayın</.localized_link>
> - Projenizin bir Git deposunda bulunması: Git dışındaki bir çalıştırma test sonuçlarını yükler ancak kapsam verisi yüklemez

## Kurulum {#setup}

### Kapsamı açın {#turn-coverage-on}

`settings.gradle.kts` dosyanızdaki `tuist` bloğunda kapsamı açın:

```kotlin
tuist {
    coverage {
        enabled = true
    }
}
```

Veya tek bir çağrı için (örneğin bir CI işi için) ortam değişkeniyle açın; bu ayar her durumda yapılandırmadan önce gelir:

```sh
TUIST_TEST_COVERAGE=1 ./gradlew test
```

Kapsamı açık ve kapalı olan test görevleri ayrı derleme önbelleği girdilerine sahiptir (bkz. [Performans etkisi](#performance-impact)), bu nedenle CI ve yerel derlemeleriniz aynı derleme önbelleğini paylaşıyorsa ayarı tercih edin: kapsamı yalnızca CI’da açmak, birbirlerinin test sonuçlarını yeniden kullanmalarını engeller.

Kapsam açıkken, eklenti Gradle’ın `jacoco` eklentisini her JVM projesine uygular. JaCoCo aracısı, eklentiyi kendiniz uyguladığınızda olduğu gibi projenizin depolarından gelir. JaCoCo’yu zaten yapılandıran bir proje ayarlarını korur ve kendi raporları çalışmaya devam eder.

Eklenti yalnızca deponuzdaki kodun kapsamını raporlar, bu nedenle JaCoCo’yu bununla sınırlar: bir test görevi JaCoCo’nun `includes` değerini kendisi ayarlamadıkça, aracı yalnızca deponuzun derlediği sınıfların paketlerini enstrümanlar. Bağımlılıklar, Android çerçevesi ve test çerçeveleriniz enstrümansız çalışır; bu da JaCoCo verilerini ve test görevlerinin derleme önbelleği girdilerini küçük tutar.

### Android projeleri {#android-projects}

Eklenti, Android projelerinin yerel birim testlerini (örneğin `testDebugUnitTest`) ölçer. Cihazda veya emülatörde çalışan enstrümanlı testler ölçülmez.

Birim testleriniz Robolectric kullanıyorsa, JaCoCo’ya Robolectric’in yüklediği sınıfları dahil etmesini söyleyin. Robolectric uygulamanızın sınıflarını kendi sınıf yükleyicisinde tanımlar ve JaCoCo varsayılan olarak bu sınıfları atlar, dolayısıyla bu testlerin çalıştırdığı kod kapsanmamış olarak görünür. Android projesinin `build.gradle.kts` dosyasında:

```kotlin
pluginManager.withPlugin("jacoco") {
    tasks.withType<Test>().configureEach {
        extensions.configure<JacocoTaskExtension> {
            isIncludeNoLocationClasses = true
            excludes = listOf("jdk.internal.*")
        }
    }
}
```

Bu blok yalnızca kapsam açıkken geçerlidir, çünkü eklenti `jacoco` öğesini o zaman uygular.

Android birim testleri varsayılan olarak JUnit 4 üzerinde çalışır; bu kapsamı kaydeder ancak [her testin hangi kodu çalıştırdığını](#per-test-evidence) kaydetmez. Bunu kaydetmek için testleri JUnit Vintage aracılığıyla JUnit Platform üzerinde çalıştırın.

### Parçalı çalıştırmalar {#sharded-runs}

<.localized_link href="/guides/features/test-sharding/gradle">Testlerinizi parçalara böldüğünüzde</.localized_link>, kapsamı açık olarak çalışan her parça çalıştırdığı testlerin kapsamını bildirir ve Tuist bir çalıştırmanın parçalarını tek bir değerde birleştirir. Bir parça, test suite’inin bir bölümünü bilinçli olarak çalıştırır; bu nedenle commit’in kapsamını eksik hale getirmez.

### CI’da her commiti tamamlayın {#complete-each-commit}

Bir commit’in kapsamı genellikle birden fazla işten (örneğin parça başına bir iş) gelir. Tuist, bunlardan sonuncusunun ne zaman bildirim yaptığını bilemez, bu yüzden siz belirtin. Bir commit için tüm test işleri tamamlandığında, hepsine bağımlı olan bir işte şunu çalıştırın:

```sh
./gradlew tuistCoverageComplete
```

Tek bir iş bir commit’in tüm testlerini çalıştırıyorsa, testi başarısız olsa bile görevi testlerden sonra bir adım olarak çalıştırın: başarısız testlere sahip bir çalıştırma yine de kapsamını bildirir.

Görev, checkout’taki `HEAD` konumundan commiti okur; testlerinizin çalıştığı commit budur. Farklı bir commit belirtmek için `-Ptuist.coverage.commit=<sha>` parametresini geçirin. Bir commit tamamlanana kadar kapsamı **Devam ediyor** olarak görünür ve dalının trendine dahil edilmez.

## Nasıl çalışır {#how-it-works}

### Tuist’in ölçtüğü şeyler {#what-tuist-measures}

- **Projeler.** Her Gradle projesi kontrol panelinde kendi kapsamıyla birlikte bir modül olarak yer alır.
- **Yalnızca ürün kodu.** Test kaynak kümelerinden derlenen sınıflar test kodudur. Tuist bunları saklar ancak hiçbir değere dahil etmez.
- **Deponuzun dosyaları.** Bir sınıf, deponuzdaki yoluna göre derlendiği kaynak dosya için sayılır. Oluşturulan kaynaklar ve Git’in yoksaydığı dosyalar raporlanmaz.
- **Her satırın çalışıp çalışmadığı.** JaCoCo kodun çalışıp çalışmadığını kaydeder, kaç kez çalıştığını değil; bu nedenle kontrol panelindeki yürütme sayıları 0 veya 1’dir.

### Her testin hangi kodu çalıştırdığı {#per-test-evidence}

JUnit Platform üzerinde çalışan testler için (JUnit 5 veya JUnit Vintage üzerinden JUnit 4), eklenti ayrıca her testin hangi kodu çalıştırdığını ve her test sınıfının testleri dışında (örneğin `@BeforeAll` içinde) ne çalıştırdığını kaydeder. Bu, Tuist’in bir çalıştırmanın dışladığı testlerin kapsamını ileri taşımasını sağlar (bkz. [Atlanan testler](#skipped-tests)). Testlerinize hiçbir şey eklemeniz gerekmez.

Bu, her test JVM’si bir seferde bir test çalıştırdığında işe yarar; JUnit’un paralel yürütmesini açmadığınız sürece Gradle testleri bu şekilde çalıştırır. `maxParallelForks` ile test sınıflarını birkaç JVM’de çalıştırmak sorun değildir. Aynı JVM’de aynı anda çalışan testler yine de kapsama dahil edilir, ancak tek tek sayılmaz.

### Derleme önbelleği {#build-cache}

Gradle’ın derleme önbelleğinden geri yüklediği veya güncel olan bir test görevi hiçbir test çalıştırmaz. Kapsamı yine de yüklenir: JaCoCo verisi, görevin çıktılarından biridir ve aynı girdilerle testlerini yürüten çalıştırma tarafından kaydedilir.

### Atlanan testler {#skipped-tests}

Bir çalıştırma testleri dışladığında, Tuist çalıştırdıkları kod değişmediği sürece önceki bir çalıştırmadan kapsadıkları alanları doldurur. Yapamadığında, commit’in kapsamı **Eksik** olur. Bir çalıştırmanın dışladıkları:

- **Bir projenin test görevinin hariç tutulması** (`-x :app:test` ile). Bu testler, kodu değişmeyen son çalıştırmadan ileri taşınır.
- **Bazı projelerin testleri** (`./gradlew :core:test` ile) veya **bazı testler** (`--tests` ile). Çalıştırma yalnızca istediğiniz kısmı kapsar; bu nedenle commit’in başka bir çalıştırması her şeyi çalıştırmadıkça commit eksik kalır.
- **İlk hatasında duran bir test görevi** (`failFast`).

Bazı testler bilinçli olarak dışlanır ve bir commiti eksik hale getirmez:

- **Derleme betiğinizdeki filtreler**, örneğin `filter { excludeTestsMatching(...) }`, test paketinizin neleri çalıştıracağını tanımlar.
- **Derleme betiğinizin kapattığı test görevleri**; `enabled = false` veya bunları atlayan bir `onlyIf` ile.
- **<.localized_link href="/guides/features/test-insights/flaky-tests/gradle">Karantina</.localized_link> tarafından atlanan testler.** Silinmiş gibi dışlanırlar, bu nedenle yalnızca onların kapsadığı satırlar kapsam dışı sayılır.
- **Diğer parçaların testleri**, [testlerinizi parçalara böldüğünüzde](#sharded-runs).

### Eksik ve tamamlanmış commit’ler {#commit-status}

| Durum | Anlamı |
| --- | --- |
| Devam ediyor | Çalıştırmalar kapsam bildirdi, ancak `tuistCoverageComplete` henüz bu commit için çalıştırılmadı. |
| Tamamlandı | Commit’in çalıştırmalarındaki her test ya çalıştırıldı, ya ileri taşındı ya da bilinçli olarak dışlandı. |
| Eksik | Bazı kapsam verileri belirlenemedi, bu nedenle gösterilen değer alt sınırdır. |
| Ölçülmedi | Commit için kapsam bildiren hiçbir çalıştırma yok. |

Bir dalın eğilimi yalnızca tamamlanmış commit’leri içerir.

## Performans etkisi {#performance-impact}

JaCoCo, test JVM’si sınıfları yüklerken onları enstrümanlar; bu nedenle derlenmiş sınıflarınız ve derleme görevlerinin derleme önbelleği girdileri kapsam açık veya kapalıyken aynı kalır. SBOM oluşturucular gibi her bağımlılık yapılandırmasını okuyan görevler de JaCoCo aracısını görür, bu yüzden kapsamı açtığınızda çıktıları değişir. Testler biraz daha yavaş çalışır ve eklenti, test görevleri tamamlandığında JaCoCo verisini okur. Kapsamı açık ve kapalı olan test görevlerinin ayrı derleme önbelleği girdileri vardır; bu nedenle, kapsam olmadan sonuçları önbellekte olsa bile kapsam açıkken yapılan ilk çalıştırma testleri yürütür.

## Sınırlamalar {#limitations}

- **Yalıtılmış Projeler ve isteğe bağlı yapılandırma.** Bu derlemeler her projeyi yapılandırmaz, bu nedenle eklenti bir çalıştırmanın hangi projelerin testlerini dışladığını bilemez ve bazı projelerin testlerinin çalıştırılması tamamlanmış sayılır.
- **Fork’lardan gelen çekme isteklerinden kapsam yok.** Kapsam yalnızca Tuist ile kimlik doğrulaması yapan çalıştırmalar tarafından yüklenir ve CI genellikle fork’lardan açılan çekme isteklerinde gizli anahtarları ve kimlik belirteçlerini tutar.

## Kapsam sorgulama {#querying}

Kontrol panelinin **Kod Kapsamı** sayfası, her commit’in değerini, modüllerini ve dosyalarını, her çalıştırmanın kapsadığı satırlarla birlikte gösterir. Aynı verilere ajanlar <.localized_link href="/guides/features/agentic-coding/mcp">Model Context Protocol sunucusu</.localized_link> üzerinden erişebilir.
