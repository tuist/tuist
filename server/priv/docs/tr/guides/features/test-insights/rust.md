---
{
  "title": "Rust Test İçgörüler",
  "titleTemplate": ":title · Test İçgörüler · Özellikler · Kılavuzlar · Tuist",
  "description": "Cargo test sonuçlarını, Rust doctestleri dahil olmak üzere, Tuist kontrol panelinde takip edin."
}
---
# Rust test içgörüleri {#rust-test-insights}

Tuist, `cargo test` komutundan gelen birim testleri, entegrasyon testleri ve dokümantasyon testleri dahil olmak üzere bireysel test sonuçlarını raporlar. Ek bir Rust bağımlılığı veya test çalıştırıcısı gerekmez.

> [!IMPORTANT]
> **Gereksinimler**
>
> - <.localized_link href="/guides/get-started/rust-project">Rust proje kurulumu</.localized_link> adımlarını izleyin.

## Test çalışmalarınızı raporlayın {#report-your-test-runs}

```sh
tuist cargo test --workspace
```

mise Cargo sarmalayıcısı yapılandırıldığında, `cargo test` yazmaya devam edebilirsiniz. Cargo, testlerinizi her zamanki argümanları, çıktıyı ve çıkış koduyla derlemeye ve çalıştırmaya devam eder. Raporlama hataları testlerinizin sonucunu değiştirmez.

Her zamanki gibi bir paket seçebilir veya testleri filtreleyebilirsiniz:

```sh
tuist cargo test -p store
tuist cargo test authentication
```

## Tuist’in izlediği veriler {#what-is-tracked}

- Tamamlanan test kümelerinden geçen, başarısız olan ve yoksayılan testler.
- Birim testleri, entegrasyon testleri ve dokümantasyon testleri.
- Tüm test kümesi süreleri.
- Mevcut dal, commit, CI ve çalıştırıcı meta verileri.

Filtrelenmiş testler ve bir başarısızlıktan sonra çalıştırılmayan testler asla geçen olarak raporlanmaz. Sonuçlar panoda **Testler** altında görünür.

## Sürekli entegrasyon {#continuous-integration}

Tuist; GitHub Actions, GitLab CI, Bitrise, CircleCI, Buildkite ve Codemagic’i tanır ve her çalıştırmayı ilgili CI işine bağlar. Diğer herhangi bir CI sisteminde, `CI` ortam değişkeni ayarlandığında bir çalıştırma CI çalıştırması olarak sayılır. Çoğu CI sistemi bunu otomatik ayarlar; Fly.io Machines gibi ayarlamayan ortamlarda kendiniz ayarlayın. Kararsız test algılama yalnızca CI çalıştırmalarını karşılaştırır.

Bir dal yerine bir commit’i checkout eden bir iş, Git’e adlandırılacak bir dal bırakmadığından bu tür çalıştırmaların dal bilgisi olmaz. Tuist’in tanıdığı CI sistemlerinde dal bilgisi sağlayıcıdan gelir. Diğer durumlarda, dala `TUIST_GIT_BRANCH` ile ad verin:

```sh
CI=true TUIST_GIT_BRANCH=main tuist cargo test --workspace
```

## Paketler, modüller ve test senaryoları {#test-hierarchy}

Tuist sonuçları Cargo paketine ve hedefine göre gruplar. Rust modül yolları, bir hedef içindeki bireysel testleri gruplar:

| Panel etiketi | Rust anlamı | Örnek |
| --- | --- | --- |
| Modüller | Cargo paketi ve hedefi | `store::api` |
| Test Kümeleri | Rust modül yolları | `api::authentication` |
| Test Senaryoları | Bireysel testler | `rejects_invalid_token` |

Dokümantasyon testleri, `store::doctest/store` gibi ayrı bir modül kullanır. Adları kaynak konumunu içerdiğinden, bir örneğin yerini değiştirmek kimliğini değiştirebilir.

## Dokümantasyon testleri ve süreler {#cargo-test}

Dokümantasyon testleri, `compile_fail`, `should_panic` ve `no_run` örnekleri dahil olmak üzere alışılmış test komutunuzla çalışır. Yalnızca dokümantasyon testlerini çalıştırmak için:

```sh
tuist cargo test --doc
```

Kararlı libtest, tüm test kümesi süresini bildirir ancak bireysel test sürelerini bildirmez. Kullanılamayan zamanlamalar, senaryo bazlı süre geçmişlerinden ve süre analizlerinden hariç tutulur; test sonuçları ise güvenilirlik ve çalıştırma sayılarına katkıda bulunmaya devam eder.

## Raporlama sınırları {#reporting-limits}

Bireysel sonuçlar, Cargo/libtest’in varsayılan çıktısından toplanır. `--no-run`, `--list`, sessiz veya ayrıntılı Cargo çıktısı, alternatif formatlar veya yakalanmamış test çıktısı kullanan komutlar, bireysel test raporu olmadan normal şekilde çalışır. Özel test koşumları, eksik özetler, belirsiz hedef atamaları ve aşırı büyük raporlar yüklenmez.

Çalışma alanı paketlerinde aynı ada sahip entegrasyon hedefleri varsa, `-p <package>` ile birini seçin. Raporlama, tam çalışma alanı paket adlarını destekler; bağımlılık paketleri, sürüm nitelikli seçiciler ve glob desenleri normal şekilde çalıştırılır ancak raporlanmaz. Mutlak dokümantasyon testi yolları, checkout yollarının test kimliklerine karışmasını önlemek için atlanır.

Tuist, sonuçları toplarken çıktıyı akış olarak iletir. Bu durum, otomatik renk algılamasını etkileyebilir. Cargo’dan çıktıktan sonra çıktı borularını açık tutan arka plan işlemleri, raporun atlanmasına neden olabilir ancak Cargo’nun çıkış durumunu değiştirmez.

## Güvenilirlik ve seçim {#reliability-and-selection}

Kararsız testleri incelemek ve bunları susturmak veya atlamak için <.localized_link href="/guides/features/test-insights/flaky-tests/rust">kararsız test algılama ve karantinaya alma</.localized_link> özelliğini kullanın. <.localized_link href="/guides/features/test-sharding/rust">Test parçalama</.localized_link>, tüm Cargo hedeflerini CI çalışanları arasında dağıtır. Test çalıştırmalarınızın satır kapsama oranını takip etmek için <.localized_link href="/guides/features/test-code-coverage/rust">kod kapsamı</.localized_link>nı açın. Kapsama tabanlı test seçimi ve tek seferlik derleme dağıtımı, düz Cargo test çalıştırmaları için kullanılamaz.

## Sorun giderme {#troubleshooting}

Bir test çalıştırması panoda görünmüyorsa, raporunun neden gönderilmediğini görmek için hata ayıklama çıktısını etkinleştirin:

```sh
TUIST_DEBUG=1 tuist cargo test --workspace
```
