---
{
  "title": "Rust Test İçgörüleri",
  "titleTemplate": ":title · Test İçgörüleri · Özellikler · Kılavuzlar · Tuist",
  "description": "Cargo test sonuçlarını, Rust doctest'leri dahil, Tuist panosunda takip edin."
}
---
# Rust test içgörüleri {#rust-test-insights}

Tuist, `cargo test` üzerinden gelen birim testleri, entegrasyon testleri ve doctestler dahil olmak üzere bireysel test sonuçlarını raporlar. Ek bir Rust bağımlılığına veya ek bir test çalıştırıcısına gerek yoktur.

> [!IMPORTANT]
> **Gereksinimler**
>
> - <.localized_link href="/guides/get-started/rust-project">Rust proje kurulumunu</.localized_link> takip edin.

## Test çalışmalarınızı raporlayın {#report-your-test-runs}

```sh
tuist cargo test --workspace
```

mise Cargo sarmalayıcısı yapılandırıldığında, `cargo test` yazmaya devam edebilirsiniz. Cargo, alışılmış argümanları, çıktıyı ve çıkış koduyla testlerinizi derlemeye ve çalıştırmaya devam eder. Raporlama hataları testlerinizin sonucunu değiştirmez.

Her zamanki gibi bir paket seçebilir veya testleri filtreleyebilirsiniz:

```sh
tuist cargo test -p store
tuist cargo test authentication
```

## Tuist’in izlediği veriler {#what-is-tracked}

- Tamamlanan test setlerinden geçen, başarısız olan ve yoksayılan testler.
- Birim testleri, entegrasyon testleri ve doctestler.
- Tüm test seti süreleri.
- Mevcut dal, commit, CI ve çalıştırıcı meta verileri.

Filtrelenmiş testler ve bir başarısızlıktan sonra çalıştırılmayan testler asla geçen olarak raporlanmaz. Sonuçlar, panoda **Testler** altında görünür.

## Paketler, modüller ve test senaryoları {#test-hierarchy}

Tuist sonuçları Cargo paketine ve hedefine göre gruplandırır. Rust modül yolları, bir hedef içindeki bireysel testleri gruplandırır:

| Pano etiketi | Rust anlamı | Örnek |
| --- | --- | --- |
| Modüller | Cargo paketi ve hedefi | `store::api` |
| Test Setleri | Rust modül yolları | `api::authentication` |
| Test Senaryoları | Bireysel testler | `rejects_invalid_token` |

Doctestler, `store::doctest/store` gibi ayrı bir modül kullanır. Adları kaynak konumunu içerir; bu nedenle bir örneğin taşınması kimliğini değiştirebilir.

## Doctestler ve süreler {#cargo-test}

Doctestler, `compile_fail`, `should_panic` ve `no_run` örnekleri dahil olmak üzere olağan test komutunuzla çalışır. Yalnızca doctestleri çalıştırmak için:

```sh
tuist cargo test --doc
```

Kararlı libtest, tüm test seti süresini bildirir ancak bireysel test sürelerini bildirmaz. Kullanılamayan zamanlamalar, senaryo bazlı süre geçmişlerinden ve süre analizlerinden hariç tutulurken test sonuçları güvenilirlik ve çalışma sayılarına katkıda bulunmaya devam eder.

## Raporlama sınırlamaları {#reporting-limits}

Bireysel sonuçlar, Cargo/libtest’in varsayılan çıktısından toplanır. `--no-run`, `--list`, sessiz veya Cargo-ayrıntılı çıktı, alternatif biçimler veya yakalanmamış test çıktısı kullanan komutlar, bireysel test raporu olmadan normal şekilde çalışır. Özel test koşumları, eksik özetler, belirsiz hedef ataması ve aşırı büyük raporlar yüklenmez.

Çalışma alanı paketlerinde aynı ada sahip entegrasyon hedefleri varsa, `-p <package>` ile birini seçin. Raporlama, tam çalışma alanı paket adlarını destekler; bağımlılık paketleri, sürüm nitelikli seçiciler ve glob desenleri normal şekilde yürütülür ancak raporlanmaz. Mutlak doctest yolları, kontrol yollarının test kimliklerine girmemesi için atlanır.

Tuist, sonuçları toplarken çıktıyı akış olarak iletir. Bu durum otomatik renk algılamasını etkileyebilir. Cargo’dan çıktıktan sonra çıktı borularını açık tutan arka plan işlemleri, raporun atlanmasına neden olabilir ancak Cargo’nun çıkış durumunu değiştirmez.

## Güvenilirlik ve seçim {#reliability-and-selection}

Kararsız testleri incelemek ve bunları sessize almak veya atlamak için <.localized_link href="/guides/features/test-insights/flaky-tests/rust">kararsız test algılama ve karantinaya alma</.localized_link> özelliğini kullanın. <.localized_link href="/guides/features/test-sharding/rust">Test parçalama</.localized_link>, tüm Cargo hedeflerini CI çalışanları arasında dağıtır. Test çalışmalarınızın satır kapsamını takip etmek için <.localized_link href="/guides/features/test-code-coverage/rust">kod kapsamı</.localized_link>nı açın. Kapsam tabanlı test seçimi ve tek seferde derleme dağıtımı, düz Cargo test çalıştırmaları için kullanılamaz.

## Sorun giderme {#troubleshooting}

Bir test çalıştırması panoda görünmüyorsa, raporunun neden gönderilmediğini görmek için hata ayıklama çıktısını etkinleştirin:

```sh
TUIST_DEBUG=1 tuist cargo test --workspace
```
