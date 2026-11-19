---
{
  "title": "Rust Kararsız Testler",
  "titleTemplate": ":title · Kararsız Testler · Test İçgörüler · Özellikler · Kılavuzlar · Tuist",
  "description": "CI geçmişini kullanarak kararsız Cargo testlerini tespit edin ve inceleyin."
}
---
# Rust kararsız testleri {#rust-flaky-tests}

Tuist, tutarsız Cargo test sonuçlarını tespit edebilir ve bunları **Testler → Kararsız Testler** bölümünde incelemenize yardımcı olabilir.

> [!IMPORTANT]
> **Gereksinimler**
>
> - <.localized_link href="/guides/features/test-insights/rust">Rust Test İçgörülerini</.localized_link> yapılandırın.

## Kararsızlık algılamanın çalışma şekli {#how-it-works}

Tuist, aynı commit üzerindeki CI çalıştırmalarını karşılaştırır. Bir çalıştırmada geçen, diğerinde başarısız olan bir test kararsız olarak işaretlenebilir.

Her çalıştırmayı olağan komutla bildirin:

```sh
tuist cargo test --workspace
```

Cargo, başarısız testleri otomatik olarak yeniden denemez. Aynı commit üzerinde bir CI işini yeniden çalıştırmak, çapraz-çalıştırma algılaması için başka bir sonuç sağlar.

<!-- @snippet: ./_managing -->

## Kararsız testlerin karantinaya alınması {#quarantining}

Bir testi ayrıntı sayfasından susturun veya atlayın ya da karantinayı **Ayarlar → Otomasyonlar** bölümünde yapılandırın. Sonraki `tuist cargo test`, projenin mevcut karantina durumunu getirir:

- **Susturulan** testler yine de çalışır ve gerçek sonuçlarını bildirir, ancak bunların başarısızlıkları komutu başarısız kılmaz. Diğer test başarısızlıkları, derleme hataları, çökmeler ve eksik sonuçlar normal şekilde başarısız olmaya devam eder.
- **Atlanan** testler yürütmeden hariç tutulur ve karantinaya alınmış atlamalar olarak raporlanır. Eşleştirme paket, hedef, Rust modül yolu ve test adını içerir; bu nedenle benzer ada sahip testler bağımsız kalır.

Susturma, seçilen workspace paketlerini ve özelliklerini korur ve susturulan bir hedef başarısız olsa bile tüm seçili hedefleri çalıştırır. Atlama karantinası tek bir seçili paket gerektirir: çoklu paketli workspace komutu yerine `tuist cargo test -p store` kullanın. Tuist, komutu daraltmanın Cargo'nun birleştirilmiş bağımlılık özelliklerini değiştirebileceği gerekçesiyle çoklu paket atlamayı reddeder.

Karantina ayrıca <.localized_link href="/guides/features/test-sharding/rust">parçalı Cargo çalıştırmalarına</.localized_link> da uygulanır. Tuist durumu getiremezse uyarı verir ve karantina olmadan çalıştırır; başarısızlıklar bastırılmaz. Bilerek karantina olmadan çalıştırmak için:

```sh
TUIST_TEST_SKIP_QUARANTINE=1 tuist cargo test --workspace
```

### Sınırlamalar {#limitations}

- Uygulama, standart libtest harness'lerini ve yakalanan varsayılan çıktıyı gerektirir. Sessiz, ayrıntılı, alternatif biçimli veya yakalanmamış çıktı içeren komutlar, karantina uygulanması gerektiğinde başarısız olur.
- Hedef ataması belirsizse tam bir workspace paketini `-p <package>` ile seçin. Özel harness'ler, paket/hedef adı glob desenleri ve çözümlenmemiş paket seçimleri desteklenmez.
- Doctest'ler de susturulabilir veya atlanabilir, ancak Rustdoc'un test filtrelemesi her olası örnek adı çiftini ayırt edemez. Bir örneği atlamak etkin bir örneği de atlayacaksa veya kısmi doctest dışlaması `--exact` kullanıyorsa, Tuist atlanan örneği yürütmek veya etkin testleri sessizce atlamak yerine bir tanılama ile başarısız olur. İnceleme sırasında yukarıdaki geçersiz kılmayı kullanın.

## Yeni testlerin stres testi {#stress-testing-new-tests}

Tuist, yeni Cargo testlerine stres testi uygulamaz. Başarısız olan bir testi incelerken tekrarlamak için bir Cargo test filtresi kullanın:

```sh
tuist cargo test -p store rejects_invalid_token
```

<!-- @snippet: ./_slack -->

<!-- @snippet: ./_querying -->
