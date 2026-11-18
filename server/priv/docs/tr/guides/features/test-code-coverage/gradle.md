---
{
  "title": "Gradle Kod Kapsamı",
  "titleTemplate": ":title · Kod Kapsamı · Özellikler · Kılavuzlar · Tuist",
  "description": "JaCoCo ile ölçülen Gradle projenizin testlerinin kod kapsamını yükleyin ve dosya, proje ve commit bazında takip edin."
}
---
# Gradle kod kapsamı {#gradle-code-coverage}

Kod kapsamı, testlerinizin kodunuzun hangi satırlarını çalıştırdığını gösterir. Tuist Gradle eklentisi, test görevlerinizin kapsamını JaCoCo ile ölçer ve her test çalıştırmasında yükler; Tuist ise bir commit'in çalıştırmalarını proje, her Gradle projesi ve her dosya için tek bir rakamda birleştirir. Kontrol panelinin **Kod Kapsamı** sayfası bunu commit başına ve her dal için bir eğilim olarak gösterir.

> [!IMPORTANT]
> **Gereksinimler**
>
> - `dev.tuist` Gradle eklentisinin uygulanmış olması, <.localized_link href="/guides/get-started/gradle-project">Gradle projesiyle başlayın</.localized_link> bölümünde açıklandığı gibi
> - Projenizin bir Git deposunda bulunması: Bunun dışındaki bir çalıştırma test sonuçlarını yükler ancak kapsam verisi yüklemez

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

Veya tek bir çağrı için, örneğin bir CI işi için, ayarlardan bağımsız olarak öncelikli olan bir ortam değişkeniyle açın:

```sh
TUIST_TEST_COVERAGE=1 ./gradlew test
```

Kapsamı açık ve kapalı olan test görevleri ayrı derleme önbelleği girdilerine sahiptir (bkz. [Performans etkisi](#performance-impact)), bu nedenle CI ve yerel derlemeleriniz aynı derleme önbelleğini paylaşıyorsa ayarı tercih edin: Kapsamı yalnızca CI'da açmak, birbirlerinin test sonuçlarını yeniden kullanmalarını engeller.

Kapsam açıkken, eklenti Gradle'ın `jacoco` eklentisini her JVM projesine uygular. JaCoCo aracısı, eklentiyi kendiniz uyguladığınızda olduğu gibi projenizin depolarından gelir. JaCoCo'yu zaten yapılandıran bir proje ayarlarını korur ve kendi raporları çalışmaya devam eder.

### Android projeleri {#android-projects}

Eklenti, `testDebugUnitTest` gibi Android projelerinin yerel birim testlerini ölçer. Cihaz veya emülatör üzerinde çalışan enstrümante testler ölçülmez.

Birim testleriniz Robolectric kullanıyorsa, JaCoCo'ya Robolectric'in yüklediği sınıfları dahil etmesini söyleyin. Robolectric, uygulamanızın sınıflarını kendi sınıf yükleyicisinde tanımlar ve JaCoCo varsayılan olarak bu tür sınıfları atlar, bu nedenle bu testlerin çalıştırdığı kod kapsanmamış olarak görünür. Android projesinin `build.gradle.kts` dosyasında:

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

Android birim testleri varsayılan olarak JUnit 4 üzerinde çalışır; bu kapsamı kaydeder ancak [her testin hangi kodu çalıştırdığını](#per-test-evidence) kaydetmez. Bunu kaydetmek için JUnit Vintage aracılığıyla JUnit Platform üzerinde çalıştırın.

### Parçalı çalıştırmalar {#sharded-runs}

Testlerinizi <.localized_link href="/guides/features/test-sharding/gradle">parçalara böldüğünüzde</.localized_link>, kapsamı açık çalışan her parça, çalıştırdığı testlerin kapsamını bildirir ve Tuist bir çalıştırmanın parçalarını tek bir rakamda birleştirir. Bir parça, test paketinin bir kısmını kasıtlı olarak çalıştırdığından commit'in kapsamını eksik hale getirmez.

### CI'da her commiti tamamlayın {#complete-each-commit}

Bir commit'in kapsamı genellikle, parça başına bir tane gibi birkaç işten gelir. Tuist, bunlardan sonuncusunun ne zaman bildirim yaptığını bilemez, bu yüzden siz belirtin. Bir commit için tüm test işleri bittiğinde, hepsine bağımlı olan bir işte şunu çalıştırın:

```sh
./gradlew tuistCoverageComplete
```

Tek bir iş bir commit'in tüm testlerini çalıştırdığında, görevi testlerden sonra bir adım olarak çalıştırın; testler başarısız olsa bile: Başarısız testleri olan bir çalıştırma yine de kapsamını bildirmiştir.

Görev, commiti `GIT_COMMIT` veya checkout'un `HEAD` değerinden okur; başka birini belirtmek için `-Ptuist.coverage.commit=<sha>` parametresini geçin. Bir commit tamamlanana kadar, kapsamı **Devam ediyor** olarak gösterilir ve dalının eğilimine dahil edilmez.

## Nasıl çalışır {#how-it-works}

### Tuist neyi ölçer {#what-tuist-measures}

- **Projeler.** Her Gradle projesi, kontrol panelinde kendi kapsamına sahip bir modüldür.
- **Yalnızca ürün kodu.** Test kaynak kümelerinden derlenen sınıflar test kodudur. Tuist bunları saklar ancak her rakamın dışında bırakır.
- **Deponuzun dosyaları.** Bir sınıf, derlendiği kaynak dosya için, deponuzdaki yolu altında sayılır. Oluşturulan kaynaklar ve Git'in yoksaydığı dosyalar raporlanmaz.
- **Her satırın çalışıp çalışmadığı.** JaCoCo, kodun kaç kez çalıştığını değil, çalışıp çalışmadığını kaydeder, bu nedenle kontrol panelindeki yürütme sayıları 0 veya 1'dir.

### Her testin hangi kodu çalıştırdığı {#per-test-evidence}

JUnit Platform üzerinde çalışan testler için (JUnit 5 veya JUnit Vintage aracılığıyla JUnit 4), eklenti ayrıca her testin hangi kodu çalıştırdığını ve her test sınıfının testleri dışında, örneğin `@BeforeAll` içinde ne çalıştırdığını da kaydeder. Bu, Tuist'in bir çalıştırmanın dışladığı testlerin kapsamını ileri taşımasını sağlar (bkz. [Atlanan testler](#skipped-tests)). Testlerinize hiçbir şey eklenmesine gerek yoktur.

Bu, her test JVM'si aynı anda bir test çalıştırdığında işe yarar; JUnit'ün paralel yürütmesini açmadığınız sürece Gradle testleri bu şekilde çalıştırır. `maxParallelForks` ile test sınıflarını birkaç JVM'de çalıştırmak sorun değildir. Aynı JVM'de aynı anda çalışan testler yine de kapsama sayılır, ancak tek tek sayılmaz.

### Derleme önbelleği {#build-cache}

Gradle'ın derleme önbelleğinden geri yüklediği veya güncel olan bir test görevi hiçbir testi çalıştırmaz. Kapsamı yine de yüklenir: JaCoCo verisi, görevin çıktılarından biridir ve testlerini aynı girdilerle yürüten çalıştırma tarafından kaydedilir.

### Atlanan testler {#skipped-tests}

Bir çalıştırma testleri dışladığında, Tuist çalıştırdıkları kod değişmediği sürece daha önceki bir çalıştırmadan neleri kapsadıklarını doldurur. Yapamadığında, commit'in kapsamı **Eksik** olur. Bir çalıştırmanın dışladıkları:

- **Bir projenin test görevinin hariç tutulması** (`-x :app:test` ile). Testleri, kodu değişmemiş olan son çalıştırmalarından ileri taşınır.
- **Bazı projelerin testleri** (`./gradlew :core:test` ile) veya **bazı testler** (`--tests` ile). Çalıştırma yalnızca istediğiniz kısmı kapsar, bu nedenle commit'in başka bir çalıştırması her şeyi çalıştırmadıkça eksik kalır.
- **İlk hatasında duran bir test görevi** (`failFast`).

Bazı testler kasıtlı olarak dışlanır ve bir commiti eksik hale getirmez:

- **Derleme betiğinizdeki filtreler**, örneğin `filter { excludeTestsMatching(...) }`, test paketinizin neyi çalıştıracağını tanımlar.
- **Derleme betiğinizin kapattığı test görevleri**, `enabled = false` veya bunları atlayan bir `onlyIf` ile.
- **<.localized_link href="/guides/features/test-insights/flaky-tests/gradle">Karantina</.localized_link> tarafından atlanan testler.** Bunlar, kaldırılmış gibi dışlanır, bu nedenle yalnızca bunların kapsadığı satırlar kapsanmamış sayılır.
- **Diğer parçaların testleri**, [testlerinizi parçalara böldüğünüzde](#sharded-runs).

### Tam ve eksik commit'ler {#commit-status}

| Durum | Anlamı |
| --- | --- |
| Devam ediyor | Çalıştırmalar kapsam bildirdi, ancak `tuistCoverageComplete` henüz bu commit için çalıştırılmadı. |
| Tam | Commit'in çalıştırmalarına ait her test ya çalıştırıldı, ya ileri taşındı ya da kasıtlı olarak dışlandı. |
| Eksik | Bazı kapsamlar belirlenemedi, bu nedenle gösterilen değer alt sınırdır. |
| Ölçülmedi | Hiçbir çalıştırma bu commit için kapsam bildirmedi. |

Bir dalın eğilimi yalnızca tam commit'leri içerir.

## Performans etkisi {#performance-impact}

JaCoCo, test JVM'si sınıfları yüklerken onları enstrümante eder; bu nedenle derlenmiş sınıflarınız ve derleme görevlerinin önbellek girdileri kapsam açık veya kapalıyken aynı kalır. SBOM oluşturucular gibi her bağımlılık yapılandırmasını okuyan görevler de JaCoCo aracısını görür, bu nedenle kapsamı açtığınızda çıktıları değişir. Testler biraz daha yavaş çalışır ve eklenti, test görevleri tamamlandığında JaCoCo verilerini okur. Kapsamı açık ve kapalı olan test görevlerinin ayrı önbellek girdileri vardır, bu nedenle kapsam açıkken yapılan ilk çalıştırma, kapsam olmadan elde edilen sonuçlar önbellekte olsa bile testleri yürütür.

## Sınırlamalar {#limitations}

- **Yalıtılmış Projeler ve isteğe bağlı yapılandırma.** Bu derlemeler her projeyi yapılandırmaz, bu nedenle eklenti bir çalıştırmanın hangi projelerin testlerini dışladığını bilemez ve bazı projelerin testlerinin çalıştırılması tam olarak kabul edilir.
- **Fork'lardan gelen çekme isteklerinden kapsam yok.** Kapsam yalnızca Tuist ile kimlik doğrulaması yapan çalıştırmalar tarafından yüklenir ve CI genellikle fork'lardan açılan çekme isteklerinden gizli anahtarları ve kimlik belirteçlerini esirger.

## Kapsam sorgulama {#querying}

Panonun **Kod Kapsamı** sayfası, her commit'in değerini, modüllerini ve dosyalarını, her çalıştırmanın kapsadığı satırlarla birlikte gösterir. Aynı verilere ajanlar <.localized_link href="/guides/features/agentic-coding/mcp">Model Context Protocol sunucusu</.localized_link> üzerinden erişebilir.
