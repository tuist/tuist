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
> - <.localized_link href="/guides/features/test-insights/gradle">Gradle test içgörülerinin</.localized_link> yapılandırılmış olması.

<!-- @snippet: ./_intro -->

![Kararsız Testler sayfası](/images/guides/features/test-insights/flaky-tests-page.png)

## Kararsızlık algılama nasıl çalışır {#how-it-works}

Tuist, kararsız testleri iki şekilde algılar:

### Test yeniden denemeleri {#test-retries}

Yeniden deneme işleviyle testleri çalıştırdığınızda Tuist, her denemenin sonuçlarını analiz eder. Bir test bazı denemelerde başarısız olurken diğerlerinde başarılı oluyorsa kararsız olarak işaretlenir.

Başarısız testleri yeniden çalıştırmak için [Test Retry eklentisini](https://github.com/gradle/test-retry-gradle-plugin) veya benzer bir mekanizmayı kullanabilirsiniz. Tuist, bazı denemelerde başarılı olan ancak diğerlerinde başarısız olan testleri algılar.

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

### Çalışmalar arası algılama {#cross-run-detection}

Test yeniden denemeleri olmadan bile Tuist, aynı commit ve aynı Gradle projesindeki farklı CI çalıştırmalarındaki sonuçları karşılaştırarak kararsız testleri algılayabilir. Bir test aynı commit ve proje için bir CI çalıştırmasında başarılı olurken başka bir çalıştırmada başarısız olursa başarısız yürütme kararsız olarak işaretlenir.

Aynı test projeler arasında deterministik olarak farklı davranabileceği için Gradle projesi karşılaştırma anahtarının bir parçasıdır; örneğin farklı bağımlılıklarla derlenen paylaşılan bir test sınıfı veya farklı bir modül sabitinde çalışan bir test. Aynı commit’in farklı Gradle projelerindeki iki çalıştırması ayrı yürütme varyantları olarak ele alınır ve birbirini kararsız olarak işaretlemeyeceklerdir.

Bu, yeniden denemelerle yakalanacak kadar tutarlı başarısız olmayan ancak yine de aralıklı CI hatalarına neden olan kararsız testleri yakalamak için özellikle faydalıdır.

<!-- @snippet: ./_managing -->

## Kararsız testleri karantinaya alma {#quarantining}

<!-- @snippet: ./_quarantine-intro -->

Karantinaya alınmış bir test iki moddan birindedir:

- **Susturulmuş**: test yine de çalışır, ancak eklenti `ignoreFailures = true` ayarlar ve yalnızca karantina dışı hatalarda derlemeyi tekrar başarısız kılar. Hatalar hâlâ kararsız-test algılayıcısına beslenir, böylece derlemeyi bozmadan testi izlemeye devam edebilirsiniz. Aktif olarak incelediğiniz bir test için bunu seçin.
- **Atlanan**: eklenti testi Gradle’ın `excludeTestsMatching` yoluyla filtreler, bu nedenle test hiç başlamaz. Yeni sonuç üretmez ve siz yeniden etkinleştirene kadar kararsız-testler panosundan çıkar. Test bozuk, yavaş veya o kadar sürekli kararsızsa ki çalıştırmak sadece CI dakikalarını boşa harcıyorsa bunu seçin.

<!-- @snippet: ./_quarantined-passing -->

### Karantinayı etkinleştirme {#enabling-quarantine}

Karantina **CI’da otomatik olarak etkindir** (`CI` ortam değişkeni ayarlandığında) ve yerel derlemeler için devre dışı bırakılır. Eklenti, her test görevinden önce karantinaya alınmış testlerin listesini Tuist sunucusundan alır; susturulmuş testler normal şekilde çalışır ve hataları maskelenir, atlanan testler filtrelenir.

Bunu `settings.gradle.kts` içinde açıkça kontrol edebilirsiniz:

```kotlin
tuist {
    testQuarantine {
        enabled = true  // or false to disable
    }
}
```

`enabled` ayarlanmadığında varsayılan olarak otomatik algılama kullanılır: CI’da etkin, yerelde devre dışı.

## Yeni testleri stres testiyle değerlendirme {#stress-testing-new-tests}

<!-- @snippet: ./_stress-intro -->

Bir test senaryosu, projenin varsayılan dalında son 90 gün içinde CI’da çalışmamışsa veya o dala daha sonra entegre edilmiş bir commit üzerinde çalışmamışsa yeni olarak sayılır. Bir birleştirme kuyruğu varsa kuyruğun çalıştırdığı bir test senaryosu, kuyruğun commit’i dala entegre edildiğinde bilinir hale gelir ve kuyruk onu düşürürse yeni olarak kalır. Commit eşleştirmeleri, Tuist’in CI’da topladığı <.localized_link href="/guides/features/test-insights/gradle#git-history">Git geçmişi</.localized_link> üzerinden yapılır.

<!-- @snippet: ./_stress-modes -->

Bunu `settings.gradle.kts` içinde bildirin veya CI hattına göre modu değiştirmek için `TUIST_TEST_STRESS_NEW_TESTS` ayarlayın:

```kotlin
tuist {
    stressNewTests {
        mode = "report" // or "enforce"
    }
}
```

Karantinadan farklı olarak, bu geçidin CI farkındalığına sahip bir varsayılanı yoktur. `mode` ayarlanmadığında hiçbir yerde çalışmaz.

<!-- @snippet: ./_stress-reruns -->

Her yeniden deneme, yalnızca o test senaryosuna filtrelenmiş iç içe geçmiş bir Gradle derlemesidir; bu nedenle her yeniden deneme temiz bir test JVM’si alır.

<!-- @snippet: ./_stress-skipped -->

<!-- @snippet: ./_slack -->

<!-- @snippet: ./_querying -->
