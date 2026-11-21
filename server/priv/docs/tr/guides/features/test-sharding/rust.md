---
{
  "title": "Rust Test Parçalama",
  "titleTemplate": ":title · Test Parçalama · Özellikler · Kılavuzlar · Tuist",
  "description": "Geçmiş test sürelerini kullanarak Cargo test hedeflerini CI işçileri arasında dağıtın."
}
---
# Rust testlerini parçalara ayırma {#rust-test-sharding}

Tuist, geçmiş hedef sürelerini kullanarak Cargo test hedeflerini CI çalışanlarına dağıtır. Birim test hedefleri, entegrasyon test hedefleri ve her kütüphanenin doctest'leri ayrı modüllerdir. Tek bir hedef içindeki testler birlikte kalır.

> [!IMPORTANT]
> **Gereksinimler**
>
> - <.localized_link href="/guides/features/test-insights/rust">Rust Test Insights</.localized_link> özelliğini yapılandırın ve planlama işinde ile çalışanlarda CLI kimlik doğrulamasını yapın.
> - Bir çalışma alanında `-p <package>` kullanarak tek bir paket seçin. Çoklu paket parçalama desteklenmez.
> - Her işte aynı revizyonu, Rust araç zincirini, paket seçimini, özellikleri ve test filtrelerini kullanın.

## Plan oluşturma {#create-a-plan}

Testleri çalıştırmadan hedefleri derlemek ve listelemek için `--no-run` komutuna bir parça sayısı ekleyin:

```sh
TUIST_SHARD_REFERENCE=my-ci-run tuist cargo test -p store --no-run --shard-max 4
```

Komut, `shard_plan_id` içeren ve sıfır tabanlı bir `shards` dizisi içeren JSON çıktısı verir. GitHub Actions'da ayrıca `shard-plan-id` ve `shards` değerlerini `GITHUB_OUTPUT` değişkenine yazar. Açık bir referans belirtilmediğinde Tuist, desteklenen CI ortamından bir referans türetir.

| Seçenek | Açıklama |
| --- | --- |
| `--shard-max N` | Maksimum parça sayısı |
| `--shard-min N` | Minimum parça sayısı |
| `--shard-total N` | Mevcut hedeflere kadar tam sayı |
| `--shard-max-duration N` | Hedeflenen maksimum parça süresi (milisaniye) |

`--shard-total` seçeneğini tek başına kullanın veya `--shard-min` ile `--shard-max` seçeneklerini birleştirin. Geçmiş süre verisi olmadığında planlayıcı varsayılan hedef tahminlerini kullanır. Parçalama seçenekleri olmadan normal `--no-run` komutu yalnızca derleme işlemi gerçekleştirir.

## Her parçayı yürütme {#execute-each-shard}

Her çalışanda plan kimliğini ve parça indeksini ayarlayın, ardından aynı Cargo test argümanlarını kullanın:

```sh
TUIST_SHARD_PLAN_ID=<plan-id> TUIST_SHARD_INDEX=0 tuist cargo test -p store
```

Alternatif olarak, plan kimliğini geçmek yerine `TUIST_SHARD_REFERENCE` değerini planlama işinin referansına ayarlayın. Tuist atamayı alır ve Cargo'dan yalnızca bu hedefleri yürütmesini ister. Geçersiz veya uyumsuz atamalar tüm testleri çalıştırmak yerine komutu başarısız kılar. Boş atamalar hiçbir testi çalıştırmaz. Çalışanlardan gelen sonuçlar Test Insights'ta planla ilişkilendirilir ve her parça içinde <.localized_link href="/guides/features/test-insights/flaky-tests/rust#quarantining">karantina</.localized_link> uygulanır.

## Sınırlamalar {#limits}

Bu, hedef düzeyinde parçalama olup tek seferlik derleme dağıtımı değildir. Her çalışanın kaynak kodunu çekmesi ve kendi hedeflerini derlemesi gerekir; <.localized_link href="/guides/features/cache/rust">Cargo derleme önbelleği</.localized_link> uygun derleme çıktılarını yeniden kullanabilir. Tuist test çalıştırılabilir dosyalarını yüklemez veya başka bir Rust test çalıştırıcısı gerektirmez.

Parçalama için tek bir seçili paket gerekir. Çoklu paketli bir komutu daraltmak Cargo'nun birleşik bağımlılık özelliklerini değiştirebilir, bu nedenle Tuist farklı bir özellik grafiğiyle testleri çalıştırmak yerine bunu reddeder. Çoklu paket parçalama desteklenene kadar her paketi ayrı ayrı planlayın.

Parçalama standart libtest harness'lerini ve yakalanan varsayılan çıktıyı gerektirir. Sessiz, ayrıntılı, alternatif formatlı, yakalanmamış çıktılı ve özel harness komutları reddedilir. Cargo bir hedefi benzersiz şekilde tanımlayamazsa, `-p <package>` ile kesin bir çalışma alanı paketi seçin. Bağımlılık paketleri, sürüm nitelikli seçiciler, paket/hedef adı glob desenleri ve Cargo'nun nightly `-C` seçeneği parçalama için desteklenmez. Planlama ve yürütme arasında test seçimini aynı tutun.
