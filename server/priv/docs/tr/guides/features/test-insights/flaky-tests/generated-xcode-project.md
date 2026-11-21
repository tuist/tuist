---
{
  "title": "Oluşturulan Xcode projesi",
  "titleTemplate": ":title · Kararsız Testler · Test İçgörüler · Özellikler · Kılavuzlar · Tuist",
  "description": "Tuist ile oluşturulan bir Xcode projesinde kararsız testleri tespit edin, yönetin ve karantinaya alın."
}
---
# Oluşturulan Xcode projesi {#generated-xcode-project-flaky-tests}

> [!IMPORTANT]
> **Gereksinimler**
>
> - <.localized_link href="/guides/features/test-insights/xcode">Xcode test içgörüsü</.localized_link> yapılandırılmış (otomatik oluşturulan şemalar `tuist inspect test` son eylemini içerir; özel şemalara bu eylemin eklenmesi gerekir).

<!-- @snippet: ./_intro -->

![Kararsız Testler sayfası](/images/guides/features/test-insights/flaky-tests-page.png)

## Kararsızlık algılamanın çalışma biçimi {#how-it-works}

Tuist, kararsız testleri iki şekilde algılar:

### Test yeniden denemeleri {#test-retries}

Yeniden deneme özelliğiyle test çalıştırdığınızda Tuist her girişimin sonuçlarını analiz eder. Bir test bazı girişimlerde başarısız olurken diğerlerinde başarılı olursa kararsız olarak işaretlenir.

`-retry-tests-on-failure` veya `-test-iterations` parametrelerini `tuist test` aracılığıyla iletin:

```sh
tuist test MyScheme -- -retry-tests-on-failure -test-iterations 3
```

![Kararsız test senaryosu detayı](/images/guides/features/test-insights/flaky-test-case-detail.png)

<!-- @snippet: ./_xcode-cross-run -->

<!-- @snippet: ./_managing -->

## Kararsız testleri karantinaya alma {#quarantining}

<!-- @snippet: ./_quarantine-intro -->

Karantinaya alınmış bir test iki moddan birinde olabilir:

- **Susturulmuş**: test hâlâ çalışır ancak `tuist test` hatayı maskeler. Hatalar yine de kararsız-test algılayıcısına beslenir, böylece derlemeyi bozmadan testi izlemeye devam edebilirsiniz. Aktif olarak incelediğiniz bir test için bunu seçin.
- **Atlanmış**: xcodebuild `-skip-testing <identifier>` alır, bu nedenle test hiç başlamaz. Yeni sonuç üretmez ve siz yeniden etkinleştirene kadar kararsız-testler panosundan kaybolur. Test bozuk, yavaş veya o kadar sürekli kararsız ki çalıştırmak yalnızca CI dakikalarını boşa harcamak anlamına geliyorsa bunu seçin.

<!-- @snippet: ./_quarantined-passing -->

### Testleri çalıştırma {#running-tests}

`tuist test` her iki moda da otomatik olarak uyar:

```sh
tuist test
```

Atlanan testler xcodebuild’e `-skip-testing` olarak iletilir ve hiç başlamaz. Susturulmuş testler normal şekilde çalışır; başarısız olurlarsa hata, ortaya çıkan derleme durumunda maskelenir.

Karantinayı tamamen atlamak ve susturulmuş ile atlanmış testler dahil her şeyi çalıştırmak için:

```sh
tuist test --skip-quarantine
```

## Yeni testlere stres testi uygulama {#stress-testing-new-tests}

<!-- @snippet: ./_stress-intro -->

Bir test senaryosu, projenin varsayılan dalında son 90 gün içinde CI’da çalışmamışsa veya o dala daha sonra entegre edilmiş bir commit üzerinde çalışmamışsa yeni olarak sayılır. Bir birleştirme kuyruğu kullanıldığında, kuyruğun çalıştırdığı bir test senaryosu kuyruğun commit’i dala entegre edildiğinde bilinir hale gelir ve kuyruk onu bırakırsa yeni olarak kalır. Commit’ler, Tuist’in CI’da topladığı <.localized_link href="/guides/features/test-insights/xcode#git-history">Git geçmişi</.localized_link> üzerinden eşleştirilir.

<!-- @snippet: ./_stress-modes -->

Her iki modda da <.localized_link href="/guides/features/selective-testing/generated-xcode-project">seçici test</.localized_link>, sonraki çalıştırmada kararsız yeni bir test senaryosu içeren bir test hedefini atlamaz. Hedef tekrar çalışır ve kapı, test senaryosu tüm yeniden denemelerini geçene kadar onu tekrar stres testine tabi tutar.

Bunu passthrough argümanlarının önünde iletin veya CI hattı başına modu değiştirmek için `TUIST_TEST_STRESS_NEW_TESTS` ortam değişkenini ayarlayın:

```sh
tuist test --stress-new-tests report
```

<!-- @snippet: ./_stress-reruns -->

Yeniden denemeler, ilk geçişte üretilen çıktıyı yeniden kullanır.

<!-- @snippet: ./_stress-skipped -->

<!-- @snippet: ./_slack -->

<!-- @snippet: ./_querying -->
