---
{
  "title": "Oluşturulan Xcode projesi",
  "titleTemplate": ":title · Kararsız Testler · Test Analizleri · Özellikler · Kılavuzlar · Tuist",
  "description": "Tuist ile oluşturulmuş bir Xcode projesinde kararsız testleri tespit edin, yönetin ve karantinaya alın."
}
---
# Oluşturulan Xcode projesi {#generated-xcode-project-flaky-tests}

> [!IMPORTANT]
> **Gereksinimler**
>
> - <.localized_link href="/guides/features/test-insights/xcode">Xcode test içgörülerini</.localized_link> yapılandırın (otomatik oluşturulan şemalar `tuist inspect test` post-action'ını içerir; özel şemalara bunu eklemeniz gerekir).

<!-- @snippet: ./_intro -->

![Kararsız Testler sayfası](/images/guides/features/test-insights/flaky-tests-page.png)

## Kararsızlık algılama nasıl çalışır {#how-it-works}

Tuist, kararsız testleri iki şekilde algılar:

### Test yeniden denemeleri {#test-retries}

Yeniden deneme işleviyle testleri çalıştırdığınızda, Tuist her denemenin sonuçlarını analiz eder. Bir test bazı denemelerde başarısız olurken diğerlerinde başarılı oluyorsa, kararsız olarak işaretlenir.

`-retry-tests-on-failure` veya `-test-iterations` parametrelerini `tuist test` aracılığıyla iletin:

```sh
tuist test MyScheme -- -retry-tests-on-failure -test-iterations 3
```

![Kararsız test senaryosu detayı](/images/guides/features/test-insights/flaky-test-case-detail.png)

<!-- @snippet: ./_xcode-cross-run -->

<!-- @snippet: ./_managing -->

## Kararsız testlerin karantinaya alınması {#quarantining}

<!-- @snippet: ./_quarantine-intro -->

Karantinaya alınan bir test iki moddan birinde olabilir:

- **Susturulmuş**: test yine çalışır ancak `tuist test` hatayı maskeler. Hatalar kararsız test algılayıcısına beslenmeye devam eder, böylece derlemeyi bozmadan testi izlemeye devam edebilirsiniz. Aktif olarak incelediğiniz bir test için bunu seçin.
- **Atlanan**: xcodebuild `-skip-testing <identifier>` alır, bu nedenle test asla başlamaz. Yeni sonuç üretmez ve siz yeniden etkinleştirene kadar kararsız testler panosundan düşer. Test bozuk, yavaş veya o kadar sürekli kararsızsa ki çalıştırmak sadece CI dakikalarını boşa harcamak anlamına geliyorsa bunu seçin.

<!-- @snippet: ./_quarantined-passing -->

### Testleri çalıştırma {#running-tests}

`tuist test` her iki moda da otomatik olarak uyar:

```sh
tuist test
```

Atlanan testler xcodebuild'a `-skip-testing` olarak iletilir ve asla başlamaz. Susturulmuş testler normal şekilde çalışır; başarısız olurlarsa, hata ortaya çıkan derleme durumunda maskelenir.

Karantinayı tamamen atlamak ve susturulmuş ile atlanmış testler dahil her şeyi çalıştırmak için:

```sh
tuist test --skip-quarantine
```

## Yeni testleri stres testine tabi tutma {#stress-testing-new-tests}

<!-- @snippet: ./_stress-intro -->

Bir test senaryosu, projenin varsayılan dalında son 90 gün içinde CI'da çalışmadığında veya o dala daha sonra entegre edilen bir commit üzerinde çalışmadığında yeni olarak sayılır. Bir birleştirme kuyruğu varsa, kuyruğun çalıştırdığı bir test senaryosu, kuyruğun commit'i entegre edildiğinde bilinir hale gelir ve kuyruk onu bırakırsa yeni olarak kalır. Commit'ler, Tuist'in CI'da topladığı <.localized_link href="/guides/features/test-insights/xcode#git-history">Git geçmişi</.localized_link> üzerinden eşleştirilir.

<!-- @snippet: ./_stress-modes -->

Her iki modda da, <.localized_link href="/guides/features/selective-testing/generated-xcode-project">seçici test</.localized_link> bir sonraki çalıştırmada kararsız yeni bir test senaryosu içeren bir test hedefini atlamaz. Hedef tekrar çalışır ve kapı, test senaryosu tüm yeniden denemelerini geçene kadar onu tekrar stres testine tabi tutar.

Bunu passthrough argümanlarından önce iletin veya CI hattı başına modu değiştirmek için `TUIST_TEST_STRESS_NEW_TESTS` ayarlayın:

```sh
tuist test --stress-new-tests report
```

<!-- @snippet: ./_stress-reruns -->

Yeniden denemeler, ilk geçişte derlenenleri yeniden kullanır.

<!-- @snippet: ./_stress-skipped -->

<!-- @snippet: ./_slack -->

<!-- @snippet: ./_querying -->
