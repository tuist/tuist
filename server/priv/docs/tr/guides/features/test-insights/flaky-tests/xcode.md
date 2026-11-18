---
{
  "title": "Xcode Kararsız Testleri",
  "titleTemplate": ":title · Kararsız Testler · Test İçgörüleri · Özellikler · Kılavuzlar · Tuist",
  "description": "Tuist ile Xcode projelerindeki kararsız testleri tespit edin, yönetin ve karantinaya alın."
}
---
# Xcode kararsız testleri {#xcode-flaky-tests}

> [!IMPORTANT]
> **Gereksinimler**
>
> - <.localized_link href="/guides/features/test-insights/xcode">Xcode test içgörülerinin</.localized_link> yapılandırılmış olması gerekir. Tuist, her test çalıştırması tarafından yüklenen test-içgörü olaylarından kararsız testleri algılar.

<!-- @snippet: ./_intro -->

![Kararsız Testler sayfası](/images/guides/features/test-insights/flaky-tests-page.png)

## Kararsızlık algılama nasıl çalışır? {#how-it-works}

Tuist kararsız testleri iki şekilde algılar:

### Test yeniden denemeleri {#test-retries}

Yeniden deneme işleviyle testleri çalıştırdığınızda, Tuist her denemenin sonuçlarını analiz eder. Bir test bazı denemelerde başarısız olurken diğerlerinde başarılı oluyorsa, kararsız olarak işaretlenir.

`-retry-tests-on-failure` veya `-test-iterations` parametrelerini `tuist xcodebuild test` üzerinden iletin:

```sh
tuist xcodebuild test \
  -scheme MyScheme \
  -retry-tests-on-failure \
  -test-iterations 3
```

![Kararsız test senaryosu detayı](/images/guides/features/test-insights/flaky-test-case-detail.png)

<!-- @snippet: ./_xcode-cross-run -->

<!-- @snippet: ./_managing -->

## Kararsız testlerin karantinaya alınması {#quarantining}

<!-- @snippet: ./_quarantine-intro -->

Karantinaya alınan bir test iki moddan birinde olabilir:

- **Susturulmuş**: test yine de çalışır ancak `tuist xcodebuild test` hatayı maskeler. Hatalar yine de kararsız-test dedektörüne beslenir, böylece derlemeyi bozmadan testi izlemeye devam edebilirsiniz. Aktif olarak incelediğiniz bir test için bunu seçin.
- **Atlanmış**: xcodebuild `-skip-testing <identifier>` alır, bu nedenle test hiç başlamaz. Yeni sonuç üretmez ve siz yeniden etkinleştirene kadar kararsız-testler panosundan düşer. Test bozuk, yavaş veya o kadar sürekli kararsızsa ki çalıştırmak sadece CI dakikalarını boşa harcamak anlamına geliyorsa bunu seçin.

<!-- @snippet: ./_quarantined-passing -->

### Testleri çalıştırma {#running-tests}

`tuist xcodebuild test`, her iki modu da otomatik olarak dikkate alan bir passthrough sarmalayıcıdır. Onu xcodebuild'ı çağırdığınız gibi kullanın:

```sh
tuist xcodebuild test -scheme MyScheme
```

Atlanan testler, xcodebuild çağrınıza `-skip-testing <identifier>` olarak eklenir ve asla başlamaz. Susturulan testler normal şekilde çalışır; başarısız olurlarsa, hata oluşan derleme durumunda maskelenir.

#### Karantinayı atlama {#bypassing-quarantine}

`tuist xcodebuild test`, susturulan ve atlanan testler dahil her şeyi çalıştırmak için `--skip-quarantine` kabul eder:

```sh
tuist xcodebuild test --skip-quarantine -scheme MyScheme
```

#### xcodebuild'ı doğrudan çağırma {#calling-xcodebuild-directly}

`tuist xcodebuild test` üzerinden gidemiyorsanız, karantinaya alınmış testleri `-skip-testing` bağımsız değişkenlerine kendiniz `tuist test case list` ile genişletin:

```sh
xcodebuild test \
  -scheme MyScheme \
  $(tuist test case list --quarantined --skip-testing)
```

Bu, `tuist xcodebuild test` dışındaki güvenli varsayılan davranıştır: susturulan testler için hata maskeleme yalnızca o komut üzerinden gittiğinizde gerçekleşir, bu nedenle her iki modu da atlamak sahte CI hatalarını önler. Daha ince kontrol gerekiyorsa bunun yerine `tuist xcodebuild test` üzerinden gidin.

## Yeni testleri stres testiyle değerlendirme {#stress-testing-new-tests}

<!-- @snippet: ./_stress-intro -->

Bir test senaryosu, projenin varsayılan dalında son 90 gün içinde CI'da çalışmadığında veya o tarihten beri üzerine merge edilmiş bir commit'te çalışmadığında yeni olarak sayılır. Bir merge kuyruğuyla, kuyruğun çalıştırdığı bir test senaryosu, kuyruğun commit'i merge edildiğinde bilinir hale gelir ve kuyruk onu bırakırsa yeni olarak kalır. Commit'ler, Tuist'in CI'da topladığı <.localized_link href="/guides/features/test-insights/xcode#git-history">Git geçmişi</.localized_link> üzerinden eşleştirilir.

<!-- @snippet: ./_stress-modes -->

Bunu passthrough bağımsız değişkenlerinden önce iletin veya CI hattı başına modu değiştirmek için `TUIST_TEST_STRESS_NEW_TESTS` ayarlayın:

```sh
tuist xcodebuild test --stress-new-tests report -scheme MyScheme
```

<!-- @snippet: ./_stress-reruns -->

Yeniden çalıştırmalar, ilk geçişte oluşturulanları yeniden kullanır.

<!-- @snippet: ./_stress-skipped -->

<!-- @snippet: ./_slack -->

<!-- @snippet: ./_querying -->
