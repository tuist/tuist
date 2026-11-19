---
{
  "title": "Xcode Kararsız Testler",
  "titleTemplate": ":title · Kararsız Testler · Test İçgörüler · Özellikler · Kılavuzlar · Tuist",
  "description": "Tuist ile Xcode projelerindeki kararsız testleri tespit edin, yönetin ve izole edin."
}
---
# Xcode kararsız testleri {#xcode-flaky-tests}

> [!IMPORTANT]
> **Gereksinimler**
>
> - <.localized_link href="/guides/features/test-insights/xcode">Xcode test içgörüsü</.localized_link> yapılandırılmış. Tuist, her test çalıştırması tarafından yüklenen test-içgörüsü olaylarından kararsız testleri tespit eder.

<!-- @snippet: ./_intro -->

![Kararsız Testler sayfası](/images/guides/features/test-insights/flaky-tests-page.png)

## Kararsızlık algılamanın nasıl çalıştığı {#how-it-works}

Tuist kararsız testleri iki şekilde tespit eder:

### Test yeniden denemeleri {#test-retries}

Yeniden deneme işleviyle testleri çalıştırdığınızda, Tuist her girişimin sonuçlarını analiz eder. Bir test bazı girişimlerde başarısız olurken diğerlerinde başarılı oluyorsa kararsız olarak işaretlenir.

`-retry-tests-on-failure` veya `-test-iterations` parametrelerini `tuist xcodebuild test` aracılığıyla iletin:

```sh
tuist xcodebuild test \
  -scheme MyScheme \
  -retry-tests-on-failure \
  -test-iterations 3
```

![Kararsız test senaryosu ayrıntısı](/images/guides/features/test-insights/flaky-test-case-detail.png)

<!-- @snippet: ./_xcode-cross-run -->

<!-- @snippet: ./_managing -->

## Kararsız testleri karantinaya alma {#quarantining}

<!-- @snippet: ./_quarantine-intro -->

Karantinaya alınmış bir test iki moddan birinde olabilir:

- **Sessize alınmış**: test yine çalışır ancak `tuist xcodebuild test` hatayı maskeler. Hatalar yine de kararsız-test algılayıcısına beslenir; böylece derlemeyi bozmadan testi izlemeye devam edebilirsiniz. Aktif olarak incelediğiniz bir test için bunu seçin.
- **Atlanmış**: xcodebuild `-skip-testing <identifier>` alır, bu nedenle test hiç başlamaz. Yeni sonuç üretmez ve siz yeniden etkinleştirene kadar kararsız-testler panosundan düşer. Test bozuk, yavaş veya o kadar sürekli kararsızsa ki çalıştırmak yalnızca CI dakikalarını boşa harcıyorsa bunu seçin.

<!-- @snippet: ./_quarantined-passing -->

### Testleri çalıştırma {#running-tests}

`tuist xcodebuild test`, her iki modu da otomatik olarak dikkate alan bir passthrough sarmalayıcıdır. Onu xcodebuild’ı çağırırken kullandığınız gibi kullanın:

```sh
tuist xcodebuild test -scheme MyScheme
```

Atlanan testler, xcodebuild çağrınıza `-skip-testing <identifier>` olarak eklenir ve asla başlamaz. Sessize alınmış testler normal şekilde çalışır; başarısız olurlarsa hata, ortaya çıkan derleme durumunda maskelenir.

#### Karantinayı atlama {#bypassing-quarantine}

`tuist xcodebuild test`, sessize alınmış ve atlanmış testler dahil her şeyi çalıştırmak için `--skip-quarantine` kabul eder:

```sh
tuist xcodebuild test --skip-quarantine -scheme MyScheme
```

#### xcodebuild’ı doğrudan çağırma {#calling-xcodebuild-directly}

Eğer `tuist xcodebuild test` üzerinden gidemiyorsanız, karantinaya alınmış testleri `-skip-testing` bağımsız değişkenlerine kendiniz `tuist test case list` ile genişletin:

```sh
xcodebuild test \
  -scheme MyScheme \
  $(tuist test case list --quarantined --skip-testing)
```

Bu, `tuist xcodebuild test` dışındaki güvenli varsayılandır: sessize alınmış testler için hata maskesi yalnızca o komut üzerinden gittiğinizde gerçekleşir; bu nedenle her iki modu da atlamak sahte CI hatalarını önler. Daha ince kontrol gerekiyorsa bunun yerine `tuist xcodebuild test` üzerinden gidin.

## Yeni testleri stres testine tabi tutma {#stress-testing-new-tests}

<!-- @snippet: ./_stress-intro -->

Bir test senaryosu, projenin varsayılan dalında son 90 gün içinde CI’da çalışmadığında veya o zamandan beri üzerine merge edilmiş bir commit üzerinde çalışmadığında yeni olarak sayılır. Bir birleştirme kuyruğuyla, kuyruğun çalıştırdığı bir test senaryosu, kuyruğun commit’i merge edildiğinde bilinir hale gelir ve kuyruk onu bırakırsa yeni kalır. Commit’ler, Tuist’in CI’da topladığı <.localized_link href="/guides/features/test-insights/xcode#git-history">Git geçmişi</.localized_link> üzerinden eşleştirilir.

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
