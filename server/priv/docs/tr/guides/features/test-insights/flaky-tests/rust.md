---
{
  "title": "Rust Kararsız Testler",
  "titleTemplate": ":title · Kararsız Testler · Test İçgörüler · Özellikler · Kılavuzlar · Tuist",
  "description": "CI geçmişini kullanarak kararsız Cargo testlerini tespit edin ve inceleyin."
}
---
# Rust kararsız testleri {#rust-flaky-tests}

Tuist, tutarsız Cargo test sonuçlarını tespit edebilir ve bunları **Tests → Flaky Tests** bölümünde incelemenize yardımcı olabilir.

> [!IMPORTANT]
> **Gereksinimler**
>
> - <.localized_link href="/guides/features/test-insights/rust">Rust Test Insights</.localized_link> özelliğini yapılandırın.

## Kararsızlık tespiti nasıl çalışır {#how-it-works}

Tuist, aynı commit üzerindeki CI çalıştırmalarını karşılaştırır. Bir çalıştırmada geçen ancak diğerinde başarısız olan bir test kararsız olarak işaretlenebilir. Tuist’in tanımadığı bir CI sisteminde, çalıştırmaların CI çalıştırması olarak sayılması için `CI=true` ortam değişkenini ayarlayın: bkz. <.localized_link href="/guides/features/test-insights/rust#continuous-integration">sürekli entegrasyon</.localized_link>.

Her çalıştırmayı olağan komutla bildirin:

```sh
tuist cargo test --workspace
```

Cargo, başarısız testleri otomatik olarak yeniden denemez. Aynı commit üzerinde bir CI işini yeniden çalıştırmak, çapraz-çalıştırma tespiti için başka bir sonuç sağlar.

<!-- @snippet: ./_managing -->

## Kararsız testleri karantinaya alma {#quarantining}

Bir testi ayrıntı sayfasından sessize alın veya atlayın ya da karantinayı **Settings → Automations** içinde yapılandırın. Sonraki `tuist cargo test` komutu, projenin mevcut karantina durumunu getirir:

- **Sessize alınan** testler yine de çalışır ve gerçek sonuçlarını bildirir, ancak bunların başarısızlıkları komutun başarısız olmasına neden olmaz. Diğer test başarısızlıkları, derleme hataları, çökmeler ve eksik sonuçlar normal şekilde başarısız olmaya devam eder.
- **Atlanan** testler yürütmeden hariç tutulur ve karantinaya alınmış atlama olarak raporlanır. Eşleştirme; paket, hedef, Rust modül yolu ve test adını içerir, böylece benzer ada sahip testler bağımsız kalır.

Sessize alma, seçilen workspace paketlerini ve özelliklerini korur ve sessize alınan bir hedef başarısız olsa bile tüm seçili hedefleri çalıştırır. Atlama karantinası tek bir seçili paket gerektirir: çoklu paketli workspace komutu yerine `tuist cargo test -p store` kullanın. Tuist, çoklu paket atlamayı reddeder çünkü komutu daraltmak Cargo’nun birleştirilmiş bağımlılık özelliklerini değiştirebilir.

Karantina ayrıca <.localized_link href="/guides/features/test-sharding/rust">parçalı Cargo çalıştırmalarına</.localized_link> da uygulanır. Tuist durumu getiremezse uyarı verir ve karantina olmadan çalıştırır; başarısızlıklar bastırılmaz. Karantina olmadan bilinçli olarak çalıştırmak için:

```sh
TUIST_TEST_SKIP_QUARANTINE=1 tuist cargo test --workspace
```

### Sınırlamalar {#limitations}

- Uygulama, standart libtest harness’lerini ve yakalanan varsayılan çıktıyı gerektirir. Sessiz, ayrıntılı, alternatif biçimli veya yakalanmamış çıktı içeren komutlar, karantina uygulanması gerektiğinde başarısız olur.
- Hedef ataması belirsizse `-p <package>` ile tam bir workspace paketi seçin. Özel harness’ler, paket/hedef adı glob’ları ve çözümlenmemiş paket seçimleri desteklenmez.
- Doctest’ler de sessize alınabilir veya atlanabilir, ancak Rustdoc’un test filtrelemesi her olası örnek adı çiftini ayırt edemez. Bir örneği atlamak etkin bir örneği de atlayacaksa veya kısmi doctest dışlaması `--exact` kullanıyorsa, Tuist atlanan örneği yürütmek veya etkin testleri sessizce atlamak yerine bir tanılama ile başarısız olur. İnceleme sırasında yukarıdaki geçersiz kılmayı kullanın.

## Yeni testleri stres testine tabi tutma {#stress-testing-new-tests}

Tuist yeni Cargo testlerini stres testine tabi tutmaz. Başarısız olan bir testi incelerken tekrarlamak için bir Cargo test filtresi kullanın:

```sh
tuist cargo test -p store rejects_invalid_token
```

<!-- @snippet: ./_slack -->

<!-- @snippet: ./_querying -->
