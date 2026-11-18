---
{
  "title": "Rust Test İçgörüler",
  "titleTemplate": ":title · Test İçgörüler · Özellikler · Kılavuzlar · Tuist",
  "description": "Cargo test sonuçlarını, Rust doctestleri dahil, Tuist kontrol panelinde takip edin."
}
---
# Rust test içgörüler {#rust-test-insights}

Tuist, birim testleri, entegrasyon testleri ve dokümantasyon testleri dahil olmak üzere `cargo test` tarafından üretilen tekil test sonuçlarını bildirir. Ek bir Rust bağımlılığı veya test çalıştırıcısı gerekmez.

> [!IMPORTANT]
> **Gereksinimler**
>
> - <.localized_link href="/guides/get-started/rust-project">Rust proje kurulumu</.localized_link> adımlarını izleyin.

## Test çalışmalarınızı bildirin {#report-your-test-runs}

```sh
tuist cargo test --workspace
```

Mise Cargo sarmalayıcısı yapılandırıldığında, `cargo test` yazmaya devam edebilirsiniz. Cargo, alışılmış argümanları, çıktıyı ve çıkış koduyla testlerinizi derlemeye ve çalıştırmaya devam eder. Bildirim hataları testlerinizin sonucunu değiştirmez.

Her zamanki gibi bir paket seçebilir veya testleri filtreleyebilirsiniz:

```sh
tuist cargo test -p store
tuist cargo test authentication
```

## Tuist’in izlediği veriler {#what-is-tracked}

- Tamamlanan test kümelerinden geçen, başarısız olan ve yoksayılan testler.
- Birim testleri, entegrasyon testleri ve dokümantasyon testleri.
- Tüm test kümesi süreleri.
- Kullanılabilir dal, commit, CI ve çalıştırıcı meta verileri.

Filtrelenmiş testler ve bir başarısızlıktan sonra çalıştırılmayan testler asla geçen olarak bildirilmez. Sonuçlar panoda **Testler** altında görünür.

## Paketler, modüller ve test senaryoları {#test-hierarchy}

Tuist sonuçları Cargo paketine ve hedefine göre gruplar. Rust modül yolları, bir hedef içindeki tekil testleri gruplar:

| Pano etiketi | Rust anlamı | Örnek |
| --- | --- | --- |
| Modüller | Cargo paketi ve hedefi | `store::api` |
| Test Kümeleri | Rust modül yolları | `api::authentication` |
| Test Senaryoları | Tekil testler | `rejects_invalid_token` |

Dokümantasyon testleri `store::doctest/store` gibi ayrı bir modül kullanır. Adları kaynak konumunu içerdiğinden, bir örneğin yerini değiştirmek kimliğini değiştirebilir.

## Dokümantasyon testleri ve süreler {#cargo-test}

Dokümantasyon testleri, `compile_fail`, `should_panic` ve `no_run` örnekleri dahil olmak üzere alışılmış test komutunuzla çalışır. Yalnızca dokümantasyon testlerini çalıştırmak için:

```sh
tuist cargo test --doc
```

Kararlı libtest, tüm test kümesi süresini bildirir ancak tekil test sürelerini bildirmez. Kullanılamayan zamanlamalar, senaryo başına süre geçmişlerinden ve süre analizlerinden hariç tutulur; test sonuçları güvenilirlik ve çalışma sayılarına katkıda bulunmaya devam eder.

## Bildirim sınırlamaları {#reporting-limits}

Tekil sonuçlar Cargo/libtest’in varsayılan çıktısından toplanır. `--no-run`, `--list`, sessiz veya Cargo-ayrıntılı çıktı, alternatif biçimler veya yakalanmamış test çıktısı kullanan komutlar, tekil test bildirimi olmadan normal şekilde çalışır. Özel test koşumları, eksik özetler, belirsiz hedef ataması ve aşırı büyük raporlar yüklenmez.

Çalışma alanı paketlerinde aynı ada sahip entegrasyon hedefleri varsa, `-p <package>` ile birini seçin. Bildirim, tam çalışma alanı paket adlarını destekler; bağımlılık paketleri, sürüm nitelikli seçiciler ve glob desenleri normal şekilde yürütülür ancak bildirilmez. Mutlak dokümantasyon testi yolları, checkout yollarının test kimliklerine karışmasını önlemek için atlanır.

Tuist, sonuçları toplarken çıktıyı akış olarak iletir. Bu durum otomatik renk algılamasını etkileyebilir. Cargo’dan çıktıktan sonra çıktı borularını açık tutan arka plan işlemleri raporun atlanmasına neden olabilir, ancak Cargo’nun çıkış durumunu değiştirmez.

## Güvenilirlik ve seçim {#reliability-and-selection}

Kararsız testleri incelemek ve bunları sessize almak veya atlamak için <.localized_link href="/guides/features/test-insights/flaky-tests/rust">kararsız test tespiti ve karantinaya alma</.localized_link> özelliğini kullanın. <.localized_link href="/guides/features/test-sharding/rust">Test parçalama</.localized_link>, tüm Cargo hedeflerini CI çalışanları arasında dağıtır. Kapsam alımı, kapsam tabanlı test seçimi ve tek seferde derleme dağıtımı düz Cargo test çalıştırmaları için kullanılamaz.

## Sorun giderme {#troubleshooting}

Bir test çalıştırması panoda görünmüyorsa, raporunun neden gönderilmediğini görmek için hata ayıklama çıktısını etkinleştirin:

```sh
TUIST_DEBUG=1 tuist cargo test --workspace
```
