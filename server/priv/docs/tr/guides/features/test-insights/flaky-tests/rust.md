---
{
  "title": "Rust Kararsız Testler",
  "titleTemplate": ":title · Kararsız Testler · Test İçgörüleri · Özellikler · Kılavuzlar · Tuist",
  "description": "CI geçmişini kullanarak kararsız Cargo testlerini tespit edin ve inceleyin."
}
---
# Rust kararsız testleri {#rust-flaky-tests}

Tuist, tutarsız Cargo test sonuçlarını tespit edebilir ve bunları **Tests → Flaky Tests** altında incelemenize yardımcı olabilir.

> [!IMPORTANT]
> **Gereksinimler**
>
> - <.localized_link href="/guides/features/test-insights/rust">Rust Test Insights</.localized_link> özelliğini yapılandırın.

## Kararsızlık algılama nasıl çalışır {#how-it-works}

Tuist, aynı commit üzerindeki CI çalıştırmalarını karşılaştırır. Bir çalıştırmada geçen, diğerinde başarısız olan bir test kararsız olarak işaretlenebilir.

Her çalıştırmayı alışılmış komutla bildirin:

```sh
tuist cargo test --workspace
```

Cargo, başarısız testleri otomatik olarak yeniden denemez. Aynı commit üzerinde bir CI işini yeniden çalıştırmak, çapraz çalıştırma algılaması için başka bir sonuç sağlar.

<!-- @snippet: ./_managing -->

## Kararsız testleri karantinaya alma {#quarantining}

Bir testi ayrıntı sayfasından sessize alabilir veya atlayabilir ya da karantinayı **Settings → Automations** içinde yapılandırabilirsiniz. Sonraki `tuist cargo test` projenin mevcut karantina durumunu getirir:

- **Sessize alınan** testler yine de çalışır ve gerçek sonuçlarını bildirir, ancak bunların başarısızlıkları komutu başarısız kılmaz. Diğer test başarısızlıkları, derleme hataları, çökmeler ve eksik sonuçlar normal şekilde başarısız olmaya devam eder.
- **Atlanan** testler yürütmeden hariç tutulur ve karantinaya alınmış atlama olarak raporlanır. Eşleştirme paket, hedef, Rust modül yolu ve test adını içerir; bu nedenle benzer ada sahip testler bağımsız kalır.

Sessize alma, seçilen çalışma alanı paketlerini ve özelliklerini korur ve sessize alınmış bir hedef başarısız olsa bile tüm seçili hedefleri çalıştırır. Atlama karantinası tek bir seçili paket gerektirir: çok paketli bir çalışma alanı komutu yerine `tuist cargo test -p store` kullanın. Tuist, komutu daraltmanın Cargo'nun birleştirilmiş bağımlılık özelliklerini değiştirebileceği gerekçesiyle çok paketli atlamayı reddeder.

Karantina ayrıca <.localized_link href="/guides/features/test-sharding/rust">parçalı Cargo çalıştırmalarına</.localized_link> da uygulanır. Tuist durumu getiremezse uyarı verir ve karantina olmadan çalıştırır; başarısızlıklar bastırılmaz. Karantina olmadan bilinçli olarak çalıştırmak için:

```sh
TUIST_TEST_SKIP_QUARANTINE=1 tuist cargo test --workspace
```

### Sınırlamalar {#limitations}

- Uygulama, standart libtest harness'lerini ve yakalanan varsayılan çıktıyı gerektirir. Sessiz, ayrıntılı, alternatif biçimli veya yakalanmamış çıktılı komutlar, karantina uygulanması gerektiğinde başarısız olur.
- Hedef ataması belirsizse tam bir çalışma alanı paketini `-p <package>` ile seçin. Özel harness'ler, paket/hedef adı glob desenleri ve çözümlenmemiş paket seçimleri desteklenmez.
- Doctest'ler de sessize alınabilir veya atlanabilir, ancak Rustdoc'un test filtrelemesi her olası örnek adı çiftini ayırt edemez. Bir örneği atlamak etkin bir örneği de atlayacaksa veya kısmi doctest dışlaması `--exact` kullanıyorsa, Tuist atlanan örneği yürütmek veya etkin testleri sessizce atlamak yerine bir tanılama ile başarısız olur. İnceleme sırasında yukarıdaki geçersiz kılmayı kullanın.

## Yeni testleri stres testi yapma {#stress-testing-new-tests}

Tuist yeni Cargo testlerini stres testi yapmaz. Başarısız olan bir testi incelerken tekrarlamak için bir Cargo test filtresi kullanın:

```sh
tuist cargo test -p store rejects_invalid_token
```

<!-- @snippet: ./_slack -->

<!-- @snippet: ./_querying -->
