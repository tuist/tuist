---
{
  "title": "Gradle Kararsız Testler",
  "titleTemplate": ":title · Kararsız Testler · Test İçgörüleri · Özellikler · Kılavuzlar · Tuist",
  "description": "Tuist ile Gradle projelerindeki kararsız testleri tespit edin, yönetin ve karantinaya alın."
}
---
# Gradle kararsız testleri {#gradle-flaky-tests}

> [!IMPORTANT]
> **Gereksinimler**
>
> - <.localized_link href="/guides/features/test-insights/gradle">Gradle test içgörüsü</.localized_link> yapılandırıldı.

<!-- @snippet: ./_intro -->

![Kararsız Testler sayfası](/images/guides/features/test-insights/flaky-tests-page.png)

## Kararsızlık algılamanın çalışma biçimi {#how-it-works}

Tuist, kararsız testleri iki şekilde algılar:

### Test yeniden denemeleri {#test-retries}

Yeniden deneme işleviyle testleri çalıştırdığınızda Tuist her denemenin sonuçlarını analiz eder. Bir test bazı denemelerde başarısız olurken diğerlerinde başarılı oluyorsa kararsız olarak işaretlenir.

Başarısız olan testleri yeniden çalıştırmak için [Test Retry eklentisini](https://github.com/gradle/test-retry-gradle-plugin) veya benzer bir mekanizmayı kullanabilirsiniz. Tuist, bazı denemelerde başarılı olup diğerlerinde başarısız olan testleri algılar.

Eklentiyi `build.gradle.kts` dosyanıza ekleyin:

```kotlin
plugins {
    id("org.gradle.test-retry") version "1.6.2"
}

tasks.test {
    retry {
        maxRetries = 3
        maxFailures = 5
        failOnPassedAfterRetry = false
    }
}
```

![Kararsız test senaryosu ayrıntısı](/images/guides/features/test-insights/flaky-test-case-detail.png)

### Çapraz çalıştırma algılama {#cross-run-detection}

Test yeniden denemeleri olmadan bile Tuist, aynı commit ve aynı Gradle projesindeki farklı CI çalıştırmalarındaki sonuçları karşılaştırarak kararsız testleri algılayabilir. Bir test aynı commit ve proje için bir CI çalıştırmasında başarılı olurken başka bir çalıştırmada başarısız olursa başarısız yürütme kararsız olarak işaretlenir.

Gradle projesi karşılaştırma anahtarının bir parçasıdır çünkü aynı test projeler arasında deterministik olarak farklı davranabilir — örneğin farklı bağımlılıklarla derlenen paylaşılan bir test sınıfı veya farklı bir modül sabitinde çalışan bir test. Farklı Gradle projelerinde aynı committen yapılan iki çalıştırma ayrı yürütme varyantları olarak ele alınır ve birbirini kararsız olarak işaretlemeyecektir.

Bu, yeniden denemelerle yakalanacak kadar tutarlı başarısız olmayan ancak yine de aralıklı CI hatalarına neden olan kararsız testleri yakalamak için özellikle yararlıdır.

<!-- @snippet: ./_managing -->

## Kararsız testlerin karantinaya alınması {#quarantining}

<!-- @snippet: ./_quarantine-intro -->

Karantinaya alınmış bir test iki moddan birindedir:

- **Sessize alınmış**: test hâlâ çalışır ancak eklenti `ignoreFailures = true` ayarlar ve yalnızca karantinada olmayan hatalarda derlemeyi yeniden başarısız kılar. Hatalar kararsız-test algılayıcısına beslenmeye devam eder; böylece derlemeyi bozmadan testi izlemeye devam edebilirsiniz. Aktif olarak incelediğiniz bir test için bunu seçin.
- **Atlanmış**: eklenti testi Gradle’ın `excludeTestsMatching` yoluyla filtreler, bu nedenle test hiç başlamaz. Yeni sonuç üretmez ve siz yeniden etkinleştirene kadar kararsız-test panosundan düşer. Test bozuk, yavaş veya o kadar kalıcı kararsız ki çalıştırmak sadece CI dakikalarını boşa harcıyorsa bunu seçin.

<!-- @snippet: ./_quarantined-passing -->

### Karantinayı etkinleştirme {#enabling-quarantine}

Karantina **CI’da otomatik olarak etkindir** (`CI` ortam değişkeni ayarlandığında) ve yerel derlemeler için devre dışıdır. Eklenti, her test görevinden önce karantinaya alınmış testlerin listesini Tuist sunucusundan çeker; sessize alınmış testler normal şekilde çalışır ve hataları maskelenir, atlanmış testler filtrelenir.

Bunu `settings.gradle.kts` içinde açıkça kontrol edebilirsiniz:

```kotlin
tuist {
    testQuarantine {
        enabled = true  // or false to disable
    }
}
```

`enabled` ayarlanmadığında varsayılan olarak otomatik algılama kullanılır: CI’da etkin, yerelde devre dışı.

## Yeni testlere stres testi uygulama {#stress-testing-new-tests}

<!-- @snippet: ./_stress-intro -->

Bir test senaryosu, projenin varsayılan dalında son 90 gün içinde CI’da çalışmamışsa veya o dala daha sonra entegre edilmiş bir commit üzerinde çalışmamışsa yeni olarak sayılır. Bir birleştirme kuyruğu varsa kuyruğun çalıştırdığı bir test senaryosu, kuyruğun commiti dala indiğinde bilinir hale gelir ve kuyruk onu bırakırsa yeni olarak kalır. Commitler, Tuist’in CI’da topladığı <.localized_link href="/guides/features/test-insights/gradle#git-history">Git geçmişi</.localized_link> üzerinden eşleştirilir.

<!-- @snippet: ./_stress-modes -->

Bunu `settings.gradle.kts` içinde bildirin veya CI hattı başına modu değiştirmek için `TUIST_TEST_STRESS_NEW_TESTS` ayarlayın:

```kotlin
tuist {
    stressNewTests {
        mode = "report" // or "enforce"
    }
}
```

Karantinadan farklı olarak bu kapının CI farkında bir varsayılanı yoktur. `mode` ayarlanmadığında hiçbir yerde çalışmaz.

<!-- @snippet: ./_stress-reruns -->

Her yeniden çalıştırma, yalnızca o test senaryosuna filtrelenmiş iç içe geçmiş bir Gradle derlemesidir; bu nedenle her yeniden çalıştırmada taze bir test JVM’si elde edilir.

<!-- @snippet: ./_stress-skipped -->

<!-- @snippet: ./_slack -->

<!-- @snippet: ./_querying -->
