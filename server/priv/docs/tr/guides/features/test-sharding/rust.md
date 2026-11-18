---
{
  "title": "Rust Test Bölümleme",
  "titleTemplate": ":title · Test Bölümleme · Özellikler · Kılavuzlar · Tuist",
  "description": "Geçmiş test sürelerini kullanarak Cargo test hedeflerini CI işçileri arasında dağıtın."
}
---
# Rust test bölümlendirmesi {#rust-test-sharding}

Tuist, geçmiş hedef sürelerini kullanarak Cargo test hedeflerini CI çalışanları arasında dağıtır. Birim testi hedefleri, entegrasyon testi hedefleri ve her kütüphanenin doctest’leri ayrı modüllerdir. Tek bir hedef içindeki testler birlikte kalır.

> [!IMPORTANT]
> **Gereksinimler**
>
> - <.localized_link href="/guides/features/test-insights/rust">Rust Test Insights</.localized_link> özelliğini yapılandırın ve planlama işi ile çalışanlarda CLI kimlik doğrulamasını gerçekleştirin.
> - Bir çalışma alanında `-p <package>` kullanarak tek bir paket seçin. Çoklu paket bölümlendirmesi desteklenmez.
> - Her işte aynı revizyonu, Rust araç zincirini, paket seçimini, özellikleri ve test filtrelerini kullanın.

## Plan oluşturma {#create-a-plan}

Testleri çalıştırmadan hedefleri derlemek ve listelemek için `--no-run` komutuna bir bölüm sayısı ekleyin:

```sh
TUIST_SHARD_REFERENCE=my-ci-run tuist cargo test -p store --no-run --shard-max 4
```

Komut, `shard_plan_id` ve sıfır tabanlı bir `shards` dizisi içeren JSON çıktısı verir. GitHub Actions’ta ayrıca `shard-plan-id` ve `shards` değerlerini `GITHUB_OUTPUT` değişkenine yazar. Açık bir referans belirtilmediğinde Tuist, desteklenen CI ortamından bir referans türetir.

| Seçenek | Açıklama |
| --- | --- |
| `--shard-max N` | Maksimum bölüm sayısı |
| `--shard-min N` | Minimum bölüm sayısı |
| `--shard-total N` | Mevcut hedeflere kadar tam sayı |
| `--shard-max-duration N` | Hedeflenen maksimum bölüm süresi (milisaniye cinsinden) |

`--shard-total` tek başına kullanın veya `--shard-min` ile `--shard-max` seçeneklerini birleştirin. Geçmiş süre verileri olmadığında planlayıcı varsayılan hedef tahminlerini kullanır. Bölümleme seçenekleri olmadan kullanılan normal `--no-run` komutu yalnızca derleme işlemi yapar.

## Her bölümü yürütme {#execute-each-shard}

Her çalışanda plan kimliğini ve bölüm indeksini ayarlayın, ardından aynı Cargo test argümanlarını kullanın:

```sh
TUIST_SHARD_PLAN_ID=<plan-id> TUIST_SHARD_INDEX=0 tuist cargo test -p store
```

Alternatif olarak, plan kimliğini doğrudan vermek yerine `TUIST_SHARD_REFERENCE` değerini planlama işinin referansına ayarlayın. Tuist atamayı alır ve Cargo’dan yalnızca bu hedefleri yürütmesini ister. Geçersiz veya uyumsuz atamalar tüm testleri çalıştırmak yerine komutu başarısız kılar. Boş atamalar hiçbir testi çalıştırmaz. Çalışanlardan gelen sonuçlar Test Insights’ta planla ilişkilendirilir ve her bölüm içinde <.localized_link href="/guides/features/test-insights/flaky-tests/rust#quarantining">karantina</.localized_link> uygulanır.

## Sınırlamalar {#limits}

Bu, hedef düzeyinde bölümlendirmedir; tek seferlik derleme dağıtımı değildir. Her çalışanın kaynak kodunu alması ve kendi hedeflerini derlemesi gerekir; <.localized_link href="/guides/features/cache/rust">Cargo derleme önbelleği</.localized_link> uygun derleme çıktılarını yeniden kullanabilir. Tuist test çalıştırılabilir dosyalarını yüklemaz veya başka bir Rust test çalıştırıcısı gerektirmez.

Bölümlendirme için tek bir seçili paket gerekir. Çoklu paketli bir komutu daraltmak Cargo’nun birleştirilmiş bağımlılık özelliklerini değiştirebilir; bu nedenle Tuist, farklı bir özellik grafiğiyle test çalıştırmak yerine bunu reddeder. Çoklu paket bölümlendirmesi desteklenene kadar her paketi ayrı ayrı planlayın.

Bölümlendirme standart libtest koşum takımlarını ve yakalanan varsayılan çıktıyı gerektirir. Sessiz, ayrıntılı, alternatif biçim, yakalanmamış çıktı ve özel koşum takımı komutları reddedilir. Cargo bir hedefi benzersiz şekilde tanımlayamazsa, `-p <package>` ile tam bir çalışma alanı paketi seçin. Bağımlılık paketleri, sürüm nitelikli seçiciler, paket/hedef adı glob desenleri ve Cargo’nun nightly `-C` seçeneği bölümlendirme için desteklenmez. Planlama ve yürütme arasında test seçimini aynı tutun.
