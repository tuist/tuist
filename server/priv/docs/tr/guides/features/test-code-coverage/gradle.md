---
{
  "title": "Gradle Kod Kapsamı",
  "titleTemplate": ":title · Kod Kapsamı · Özellikler · Kılavuzlar · Tuist",
  "description": "JaCoCo ile ölçülen Gradle projenizin testlerinin kod kapsamını yükleyin ve dosya, proje ve commit bazında takip edin."
}
---
# Gradle kod kapsamı {#gradle-code-coverage}

Kod kapsamı, testlerinizin kodunuzun hangi satırlarını çalıştırdığını gösterir. Tuist Gradle eklentisi, JaCoCo ile test görevlerinizin kapsamını ölçer ve her test çalıştırmasında yükler; Tuist, bir commit’in çalıştırmalarını proje, her Gradle projesi ve her dosya bazında tek bir değerde birleştirir. Kontrol panelinin **Kod Kapsamı** sayfası bunu commit başına ve her dal için bir eğilim olarak gösterir.

> [!IMPORTANT]
> **Gereksinimler**
>
> - `dev.tuist` Gradle eklentisinin uygulanmış olması; bkz. <.localized_link href="/guides/get-started/gradle-project">Gradle projesiyle başlayın</.localized_link>
> - Projenizin bir Git deposunda bulunması: Git dışındaki bir çalıştırma test sonuçlarını yükler ancak kapsam yüklemez

## Kurulum {#setup}

### Kapsamı açma {#turn-coverage-on}

`settings.gradle.kts` dosyanızdaki `tuist` bloğunda kapsamı açın:

```kotlin
tuist {
    coverage {
        enabled = true
    }
}
```

Veya bir ortam değişkeniyle, örneğin bir CI işi gibi tek bir çağrı için açın; bu ayar her durumda önceliklidir:

```sh
TUIST_TEST_COVERAGE=1 ./gradlew test
```

Kapsam açıkken, eklenti Gradle’ın `jacoco` eklentisini her JVM projesine uygular. JaCoCo aracısı, projenizin depolarından gelir; tıpkı eklentiyi kendiniz uyguladığınızda olduğu gibi. JaCoCo’yu zaten yapılandıran bir proje ayarlarını korur ve kendi raporları çalışmaya devam eder.

### Parçalı çalıştırmalar {#sharded-runs}

<.localized_link href="/guides/features/test-sharding/gradle">Testlerinizi parçalara böldüğünüzde</.localized_link>, kapsam açıkken çalışan her parça, çalıştırdığı testlerin kapsamını bildirir ve Tuist bir çalıştırmanın parçalarını tek bir değerde birleştirir. Bir parça, test paketinin bir bölümünü bilinçli olarak çalıştırır; bu nedenle commit’in kapsamını eksik bırakmaz.

### CI’da her commiti tamamlayın {#complete-each-commit}

Bir commit’in kapsamı genellikle birkaç işten gelir; örneğin parça başına bir iş. Tuist, bunların sonuncusunun ne zaman bildirim yaptığını bilemez, bu yüzden siz belirtin. Bir commit için tüm test işleri tamamlandığında, hepsine bağımlı olan bir işte şunu çalıştırın:

```sh
./gradlew tuistCoverageComplete
```

Görev, commiti `GIT_COMMIT` veya checkout’un `HEAD` değerinden okur; farklı birini belirtmek için `-Ptuist.coverage.commit=<sha>` parametresini geçin. Bir commit tamamlanana kadar kapsamı **Devam ediyor** olarak görünür ve dalının eğilimine dahil edilmez.

## Nasıl çalışır {#how-it-works}

### Tuist’in ölçtüğü şeyler {#what-tuist-measures}

- **Projeler.** Her Gradle projesi kontrol panelinde kendi kapsamıyla birlikte bir modül olarak yer alır.
- **Yalnızca ürün kodu.** Test kaynak kümelerinden derlenen sınıflar test kodudur. Tuist bunları saklar ancak hiçbir değere dahil etmez.
- **Deponuzdaki dosyalar.** Bir sınıf, derlendiği kaynak dosya adına, deponuzdaki yoluna göre sayılır. Oluşturulan kaynaklar ve Git’in yoksaydığı dosyalar raporlanmaz.
- **Her satırın çalışıp çalışmadığı.** JaCoCo, kodun kaç kez değil, yalnızca çalışıp çalışmadığını kaydeder; bu nedenle kontrol panelindeki yürütme sayıları 0 veya 1’dir.

### Her testin hangi kodu çalıştırdığı {#per-test-evidence}

JUnit Platform üzerinde çalışan testler için (JUnit 5 veya JUnit Vintage aracılığıyla JUnit 4), eklenti ayrıca her testin hangi kodu çalıştırdığını ve her test sınıfının testleri dışında, örneğin `@BeforeAll` içinde çalıştırdıklarını da kaydeder. Bu, Tuist’in bir çalıştırmanın dışarıda bıraktığı testlerin kapsamını ileri taşımasını sağlar (bkz. [Atlanan testler](#skipped-tests)). Testlerinize ek bir şey yapmanız gerekmez.

Bu, her test JVM’si aynı anda yalnızca bir test çalıştırdığında işe yarar; JUnit’ün paralel yürütmeyi açmadığınız sürece Gradle testleri bu şekilde çalıştırır. `maxParallelForks` ile birden fazla JVM’de test sınıflarını çalıştırmak sorun değildir. Aynı JVM içinde aynı anda çalışan testler yine kapsama dahil edilir, ancak tek tek izlenmezler.

### Derleme önbelleği {#build-cache}

Gradle’ın derleme önbelleğinden geri yüklediği veya güncel olan bir test görevi hiçbir testi çalıştırmaz. Kapsamı yine de yüklenir: JaCoCo verisi, görevin çıktılarından biridir ve aynı girdilerle testlerini yürüten çalıştırma tarafından kaydedilir.

### Atlanan testler {#skipped-tests}

Bir çalıştırma testleri dışarıda bıraktığında, Tuist çalıştırdıkları kod değişmediği sürece önceki bir çalıştırmadan kapsamlarını doldurur. Yapamadığında, commit’in kapsamı **Eksik** olur. Bir çalıştırmanın dışarıda bıraktıkları:

- **Bir projenin test görevinin hariç tutulması** (`-x :app:test` ile). Testleri, kodu değişmeyen en son çalıştırmadan ileri taşınır.
- **Bazı projelerin testleri** (`./gradlew :core:test` ile) veya **bazı testler** (`--tests` ile). Çalıştırma yalnızca istediğiniz kısmı kapsar; bu nedenle, o commit’in başka bir çalıştırması her şeyi çalıştırmadıkça commit eksik kalır.
- **İlk hatasında duran bir test görevi** (`failFast`).

Bazı testler bilinçli olarak dışarıda bırakılır ve commit’i eksik hale getirmez:

- **Derleme betiğinizdeki filtreler**; örneğin `filter { excludeTestsMatching(...) }`, test paketinizin neleri çalıştıracağını tanımlar.
- **Derleme betiğinizin kapattığı test görevleri**; `enabled = false` veya bunları atlayan bir `onlyIf` ile.
- **<.localized_link href="/guides/features/test-insights/flaky-tests/gradle">Karantina</.localized_link> tarafından atlanan testler.** Silinmiş gibi dışarıda bırakılırlar, bu nedenle yalnızca onların kapsadığı satırlar kapsanmamış sayılır.
- **Diğer parçaların testleri**; [testlerinizi parçalara böldüğünüzde](#sharded-runs).

### Tamamlanan ve eksik commit’ler {#commit-status}

| Durum | Anlamı |
| --- | --- |
| Devam ediyor | Çalıştırmalar kapsamı bildirdi, ancak `tuistCoverageComplete` henüz commit için çalıştırılmadı. |
| Tamamlandı | Commit’in çalıştırmalarındaki her test ya çalıştırıldı, ya ileri taşındı ya da bilinçli olarak dışarıda bırakıldı. |
| Eksik | Bazı kapsamlar belirlenemedi, bu nedenle gösterilen değer alt sınırdır. |
| Ölçülmedi | Commit için kapsam bildiren hiçbir çalıştırma yok. |

Bir dalın eğilimi yalnızca tamamlanan commit’leri içerir.

## Performans etkisi {#performance-impact}

JaCoCo, test JVM’si sınıfları yüklerken onları enstrüman eder; bu nedenle derlenmiş sınıflarınız ve derleme görevlerinin derleme önbelleği girdileri, kapsam açık veya kapalıyken aynı kalır. SBOM oluşturucular gibi her bağımlılık yapılandırmasını okuyan görevler de JaCoCo aracısını görür, bu yüzden kapsamı açtığınızda çıktıları değişir. Testler biraz daha yavaş çalışır ve eklenti, test görevleri tamamlandığında JaCoCo verisini okur. Kapsamı açık ve kapalı olan test görevlerinin ayrı derleme önbelleği girdileri vardır; bu nedenle, kapsam olmadan sonuçları önbelleğe alınmış olsa bile, kapsam açıkken yapılan ilk çalıştırma testleri yürütür.

## Sınırlamalar {#limitations}

- **Yalıtılmış Projeler ve isteğe bağlı yapılandırma.** Bu derlemeler her projeyi yapılandırmaz, bu nedenle eklenti bir çalıştırmanın hangi projelerin testlerini dışarıda bıraktığını belirleyemez ve bazı projelerin testlerinin çalıştırılması tamamlanmış sayılır.
- **Fork’lardan gelen pull request’lerden kapsam yok.** Kapsam yalnızca Tuist ile kimlik doğrulaması yapan çalıştırmalar tarafından yüklenir ve CI genellikle fork’lardan açılan pull request’lerde gizli anahtarları ve kimlik jetonlarını tutar.

## Kapsam sorgulama {#querying}

Dashboard’un **Kod Kapsamı** sayfası, her commit’in değerini, modüllerini ve dosyalarını, her çalıştırmanın kapsadığı satırlarla birlikte gösterir. Aynı verilere ajanlar <.localized_link href="/guides/features/agentic-coding/mcp">Model Context Protocol sunucusu</.localized_link> üzerinden erişebilir.
